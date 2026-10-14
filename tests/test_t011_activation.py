"""T011 tests: 2R partial-close activation state machine (pure; no order, no account, no persistence)."""
import math
import os
import random
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t011_activation_reference as a  # noqa: E402
import t011_activation_fixtures as fx  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def run_rows(mod):
    """Run the fixture rows against module `mod`; return the list of mismatching rows."""
    bad = []
    st, cur = None, None
    for i, r in enumerate(fx.ROWS):
        if r['scn'] != cur:
            cur, st = r['scn'], mod.State()
        if r['kind'] == 'Q':
            res = mod.on_quote(st, r['pos'], r['d'], r['level'], r['bid'], r['ask'], r['vinit'], r['vcur'], r['vmin'], r['step'], r['vmax'])
        else:
            res = mod.on_report(st, r['rid'], r['rkind'], r['rvol'], r['step'])
        got = (res.event, st.status, res.action, res.request_id, res.request_steps, st.confirmations, st.duplicates_ignored)
        exp = (r['ev'], r['st'], r['act'], r['xrid'], r['rs'], r['conf'], r['dup'])
        if got != exp:
            bad.append((i, r['scn'], got, exp))
    return bad


class Scenarios(unittest.TestCase):
    def test_every_row(self):
        self.assertEqual(run_rows(a), [])

    def test_coverage(self):
        scns = {r['scn'] for r in fx.ROWS}
        for need in ('BUY_BEFORE_2R', 'BUY_AT_2R', 'BUY_BEYOND_2R', 'SELL_BEFORE_2R', 'SELL_AT_2R', 'SELL_BEYOND_2R',
                     'REPEATED_QUOTES_PENDING', 'FULL_CONFIRMATION_THEN_QUOTES', 'DUPLICATE_CONFIRMATION', 'REJECTED', 'TIMEOUT',
                     'PARTIAL_EXECUTION', 'WRONG_ID', 'FULL_WRONG_VOLUME_LOW', 'SPLIT_POLICY_UNSET_SEVEN_STEPS',
                     'VOLUME_MISMATCH_BEFORE_REQUEST', 'VOLUME_MISMATCH_AFTER_DONE', 'STABLE_ID_LARGE_POSITION'):
            self.assertIn(need, scns)
        events = {r['ev'] for r in fx.ROWS}
        self.assertEqual(events, {'OK', 'INVALID_INPUT', 'SPLIT_POLICY_UNSET', 'IGNORED', 'DUPLICATE_IGNORED', 'RECONCILE_REQUIRED', 'BLOCKED'})
        self.assertEqual({r['st'] for r in fx.ROWS}, {a.IDLE, a.REQUEST_PENDING, a.DONE, a.NEEDS_RECONCILIATION, a.BLOCKED})

    def test_at_most_one_request_per_scenario(self):
        per = {}
        st, cur = None, None
        for r in fx.ROWS:
            if r['scn'] != cur:
                cur, st = r['scn'], a.State()
            if r['kind'] == 'Q':
                res = a.on_quote(st, r['pos'], r['d'], r['level'], r['bid'], r['ask'], r['vinit'], r['vcur'], r['vmin'], r['step'], r['vmax'])
                if res.action == a.REQUEST_ACTION:
                    per[cur] = per.get(cur, 0) + 1
                    self.assertEqual(res.request_id, 'X2R80-%d' % r['pos'])
                    self.assertAlmostEqual(res.request_volume, res.request_steps * r['step'], places=12)
            else:
                a.on_report(st, r['rid'], r['rkind'], r['rvol'], r['step'])
        self.assertTrue(per and max(per.values()) == 1)

    def test_request_volume_is_80_percent_and_uses_the_split_module(self):
        st = a.State()
        res = a.on_quote(st, 7, a.BUY, 2000.0, 2000.0, 2000.3, 0.10, 0.10, 0.01, 0.01, 100.0)
        self.assertEqual((res.request_steps, st.initial_steps), (8, 10))
        self.assertEqual(res.request_steps * 5, st.initial_steps * 4)
        src = _read('tests', 't011_activation_reference.py')
        self.assertIn('es.split(', src)
        self.assertNotIn('// 5 * 4', src)
        self.assertNotIn('CLOSE_NUM', src)
        hdr = _read('src', 'include', 'ExitActivation.mqh')
        self.assertIn('ES_Split(', hdr)
        self.assertIn('PS_GridSteps(', hdr)
        self.assertNotIn('ES_CLOSE_NUM', hdr)
        self.assertNotIn('PS_GRID_ULPS', hdr)


class Properties(unittest.TestCase):
    def test_non_finite_inputs_change_nothing(self):
        nan, inf = float('nan'), float('inf')
        base = dict(position_id=7, direction=a.BUY, level_2r=2000.0, bid=2000.0, ask=2000.3, volume_initial=0.1, volume_current=0.1,
                    volume_min=0.01, volume_step=0.01, volume_max=100.0)
        for key in ('level_2r', 'bid', 'ask', 'volume_initial', 'volume_current'):
            for bad in (nan, inf, -inf, 0.0, -1.0, '1', None, True):
                st = a.State()
                kw = dict(base)
                kw[key] = bad
                res = a.on_quote(st, **kw)
                self.assertEqual(res.event, 'INVALID_INPUT', (key, bad))
                self.assertEqual((st.status, st.bound), (a.IDLE, False))
        for bad in (0, -1, 1.5, True, None, '7'):
            st = a.State()
            kw = dict(base)
            kw['position_id'] = bad
            self.assertEqual(a.on_quote(st, **kw).event, 'INVALID_INPUT')
        for bad in (nan, inf, -0.01, '0.08', None):
            st = a.State()
            a.on_quote(st, **base)
            self.assertEqual(a.on_report(st, 'X2R80-7', a.FULL, bad, 0.01).event, 'INVALID_INPUT')
            self.assertEqual(st.status, a.REQUEST_PENDING)

    def test_fuzz_invariants(self):
        rnd = random.Random(20261014)
        for run in range(400):
            st = a.State()
            actions = 0
            prev_conf = 0
            for _ in range(rnd.randint(2, 12)):
                before = st.status
                if rnd.random() < 0.65:
                    bid = rnd.choice([1999.0, 2000.0, 2001.0])
                    res = a.on_quote(st, 7, a.BUY, 2000.0, bid, bid + 0.3, 0.10, rnd.choice([0.10, 0.10, 0.02, 0.09]), 0.01, 0.01, 100.0)
                else:
                    res = a.on_report(st, rnd.choice(['X2R80-7', 'X2R80-7', 'X2R80-8']), rnd.choice(a.REPORT_KINDS),
                                      rnd.choice([0.0, 0.05, 0.08, 0.07, 0.075]), 0.01)
                if res.action == a.REQUEST_ACTION:
                    actions += 1
                    self.assertEqual(before, a.IDLE)
                if before in (a.NEEDS_RECONCILIATION, a.BLOCKED):
                    self.assertEqual(st.status, before)
                    self.assertEqual(res.action, a.NONE_ACTION)
                if before == a.REQUEST_PENDING:
                    self.assertNotEqual(res.action, a.REQUEST_ACTION)
                self.assertLessEqual(st.confirmations, 1)
                self.assertGreaterEqual(st.confirmations, prev_conf)
                prev_conf = st.confirmations
                if st.status == a.DONE:
                    self.assertEqual(st.confirmations, 1)
            self.assertLessEqual(actions, 1)

    def test_request_step_is_stored_and_used(self):
        for d, level, bid, ask in ((a.BUY, 2000.0, 2000.0, 2000.3), (a.SELL, 1990.0, 1989.0, 1989.4)):
            st = a.State()
            res = a.on_quote(st, 7, d, level, bid, ask, 0.5, 0.5, 0.01, 0.01, 100.0)
            self.assertEqual((res.request_steps, round(res.request_volume, 12), st.volume_step), (40, 0.4, 0.01))
            res = a.on_report(st, 'X2R80-7', a.FULL, 0.04, 0.001)         # the Codex defect: 0.04 lot on 0.001 is also 40 steps
            self.assertEqual((res.event, st.status, st.confirmations), ('BLOCKED', a.BLOCKED, 0))
            self.assertIn('STEP_CHANGED', res.reason)

    def test_invalid_first_quote_binds_nothing(self):
        base = dict(position_id=7, direction=a.BUY, level_2r=2000.0, bid=1999.0, ask=1999.3, volume_initial=0.1, volume_current=0.1,
                    volume_min=0.01, volume_step=0.01, volume_max=100.0)
        for key, bad in (('volume_step', 0.0), ('volume_step', float('nan')), ('volume_min', 0.0), ('volume_max', 0.0),
                         ('volume_max', float('inf')), ('volume_min', 0.015), ('volume_max', 5.005), ('volume_initial', 0.105)):
            for d, level in ((a.BUY, 2000.0), (a.SELL, 1990.0)):
                st = a.State()
                kw = dict(base, direction=d, level_2r=level, **{key: bad})
                if key == 'volume_initial':
                    kw['volume_current'] = bad
                res = a.on_quote(st, **kw)
                self.assertEqual(res.event, 'INVALID_INPUT', (key, bad))
                self.assertEqual((st.bound, st.status, st.position_id, st.volume_initial, st.volume_step), (False, a.IDLE, 0, 0.0, 0.0))
        st = a.State()
        a.on_quote(st, **dict(base, volume_max=float('nan')))
        self.assertFalse(st.bound)
        self.assertEqual(a.on_quote(st, **dict(base, position_id=8)).event, 'OK')
        self.assertEqual(st.position_id, 8)

    def test_unknown_report_kind_changes_nothing_in_every_state(self):
        import copy
        for sv in range(5):
            st = a.State()
            if sv >= 1:
                a.on_quote(st, 7, a.BUY, 2000.0, 2000.0, 2000.3, 0.1, 0.1, 0.01, 0.01, 100.0)
            if sv == 2:
                a.on_report(st, 'X2R80-7', a.FULL, 0.08, 0.01)
            if sv == 3:
                a.on_report(st, 'X2R80-7', a.TIMEOUT, 0.0, 0.01)
            if sv == 4:
                a.on_report(st, 'X2R80-8', a.FULL, 0.08, 0.01)
            self.assertEqual(st.status, (a.IDLE, a.REQUEST_PENDING, a.DONE, a.NEEDS_RECONCILIATION, a.BLOCKED)[sv])
            before = copy.deepcopy(st)
            for kind in (9, -1):
                res = a.on_report(st, 'X2R80-7', kind, 0.08, 0.01)
                self.assertEqual(res.event, 'INVALID_INPUT')
                self.assertEqual(st, before)

    def test_state_is_only_what_the_caller_passes(self):
        st1, st2 = a.State(), a.State()
        a.on_quote(st1, 7, a.BUY, 2000.0, 2000.0, 2000.3, 0.1, 0.1, 0.01, 0.01, 100.0)
        self.assertEqual((st2.status, st2.bound), (a.IDLE, False))
        src = _read('tests', 't011_activation_reference.py')
        for word in ('open(', 'import os', 'time.', 'datetime', 'random'):
            self.assertNotIn(word, src.split('"""', 2)[2])


class Mutants(unittest.TestCase):
    """Each mutant of the reference must be caught by the scenario table."""

    def _mutant(self, old, new, count=1):
        src = _read('tests', 't011_activation_reference.py')
        self.assertIn(old, src, 'mutation target absent (vacuous)')
        ns = {'__name__': 't011_mutant'}
        exec(compile(src.replace(old, new, count), 't011_mutant', 'exec'), ns)

        class M:
            pass
        m = M()
        for k, v in ns.items():
            setattr(m, k, v)
        return m

    def _mutant2(self, old, new, old2, new2):
        src = _read('tests', 't011_activation_reference.py')
        self.assertIn(old, src)
        self.assertIn(old2, src)
        ns = {'__name__': 't011_mutant2'}
        exec(compile(src.replace(old, new, 1).replace(old2, new2, 1), 't011_mutant2', 'exec'), ns)

        class M:
            pass
        m = M()
        for k, v in ns.items():
            setattr(m, k, v)
        return m

    def test_mutants_are_caught(self):
        cases = [
            ('BUY uses ask', "(bid >= level_2r) if direction == BUY else (ask <= level_2r)", "(ask >= level_2r) if direction == BUY else (ask <= level_2r)"),
            ('SELL uses bid', "else (ask <= level_2r)", "else (bid <= level_2r)"),
            ('strict comparison', "(bid >= level_2r)", "(bid > level_2r)"),
            ('pending quotes may request again', "    if state.status == REQUEST_PENDING:\n        return Result('IGNORED'", "    if False:\n        return Result('IGNORED'"),
            ('partial becomes DONE', "state.status = NEEDS_RECONCILIATION\n        state.executed_steps = steps", "state.status = DONE\n        state.executed_steps = steps"),
            ('rejected or timeout becomes DONE', "    state.status = NEEDS_RECONCILIATION\n    return _res('RECONCILE_REQUIRED', state, reason='%s: request", "    state.status = DONE\n    return _res('RECONCILE_REQUIRED', state, reason='%s: request"),
            ('duplicate counted twice', "state.duplicates_ignored += 1", "state.confirmations += 1"),
            ('wrong id accepted', "if request_id != state.request_id:", "if False:"),
            ('FULL with another volume accepted', "if steps != state.request_steps:", "if False:"),
            ('reconcile state is left by a quote', "    if state.status == NEEDS_RECONCILIATION:\n        return Result('RECONCILE_REQUIRED', reason='RECONCILE_REQUIRED: ' + state.reason)", "    if state.status == NEEDS_RECONCILIATION:\n        state.status = IDLE"),
            ('volume mismatch ignored before the request', "if cur != sp.initial_steps:", "if False:"),
            ('volume mismatch ignored after DONE', "if cur != expected:", "if False:"),
            ('identity not checked', "elif (state.position_id, state.direction, state.level, state.volume_initial) != (position_id, direction, level_2r, volume_initial):", "elif False:"),
            ('request id not stable', "return 'X2R80-%d' % position_id", "return 'X2R80-%d' % (position_id + len(str(position_id)))"),
            ('report step not compared with the request step', "    if volume_step != state.volume_step:\n        state.status = BLOCKED", "    if False:\n        state.status = BLOCKED"),
            ('the Codex defect: no step comparison and the volume converted on the reported step', "    if volume_step != state.volume_step:\n        state.status = BLOCKED\n        return _res('BLOCKED', state, reason='STEP_CHANGED: report step", "    if False:\n        state.status = BLOCKED\n        return _res('BLOCKED', state, reason='STEP_CHANGED: report step"),
            ('quote step change after DONE ignored', "    if volume_step != state.volume_step:\n        state.status = NEEDS_RECONCILIATION", "    if False:\n        state.status = NEEDS_RECONCILIATION"),
            ('invalid volume parameters bind the identity', "    sp = es.split(volume_initial, volume_min, volume_step, volume_max)\n    if sp.status == es.INVALID_INPUT:\n        return Result('INVALID_INPUT', reason='SPLIT_' + sp.reason)\n    # 2 stop states", "    sp = es.split(volume_initial, volume_min, volume_step, volume_max)\n    # 2 stop states"),
            ('unset split still requests', "    if sp.status == es.SPLIT_POLICY_UNSET:\n        return Result('SPLIT_POLICY_UNSET', reason=sp.reason)", "    if False:\n        pass"),
        ]
        for name, old, new in cases:
            with self.subTest(name):
                m = self._mutant(old, new)
                if name.startswith('the Codex defect'):
                    m = self._mutant2(old, new, 't006._grid_steps(executed_volume, state.volume_step) if executed_volume > 0 else 0',
                                      't006._grid_steps(executed_volume, volume_step) if executed_volume > 0 else 0')
                try:
                    bad = run_rows(m)
                except Exception:
                    bad = ['exception']
                self.assertTrue(bad, 'mutant not caught: ' + name)


class MqlBlock(unittest.TestCase):
    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T011_ActivationTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())


if __name__ == '__main__':
    unittest.main()
