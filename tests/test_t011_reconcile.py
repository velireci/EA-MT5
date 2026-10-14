"""T011 tests: reconciliation of the partial-close request against a caller-supplied snapshot (pure; no broker, no order, no retry)."""
import copy
import os
import random
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t011_activation_reference as act  # noqa: E402
import t011_reconcile_reference as rec  # noqa: E402
import t011_reconcile_fixtures as fx  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def run_rows(mod_act, mod_rec, mods_eq=True):
    bad = []
    st, cur = None, None
    for i, row in enumerate(fx.ROWS):
        if row['scn'] != cur:
            cur, st = row['scn'], mod_act.State()
        if row['kind'] == 'Q':
            res = mod_act.on_quote(st, row['pos'], row['d'], row['level'], row['bid'], row['ask'], row['vinit'], row['vcur'], row['vmin'], row['step'], row['vmax'])
            if res.action != 'NONE' and row['st'] != act.REQUEST_PENDING:
                bad.append((i, cur, 'unexpected request', res.action))
            got, exp = (st.status,) + ((st.confirmations,) if row['conf'] >= 0 else ()), (row['st'],) + ((row['conf'],) if row['conf'] >= 0 else ())
        elif row['kind'] == 'R':
            mod_act.on_report(st, row['rid'], row['rkind'], row['rvol'], row['step'])
            got, exp = (st.status,) + ((st.confirmations,) if row['conf'] >= 0 else ()), (row['st'],) + ((row['conf'],) if row['conf'] >= 0 else ())
        else:
            snap = mod_rec.Snapshot(bool(row['found']), row['pos'], row['rid'], row['step'], row['vcur'],
                                    [mod_rec.Exec(*e) for e in row['ex']], bool(row['comp']))
            plan = (st.initial_steps, st.request_steps, st.request_id, st.volume_step)
            o = mod_rec.reconcile(st, snap)
            if (st.initial_steps, st.request_steps, st.request_id, st.volume_step) != plan:
                bad.append((i, cur, 'plan changed'))
            got = (o.decision, st.status, o.linked_steps, o.duplicates, o.unlinked, int(o.changed), st.confirmations)
            exp = (row['dec'], row['st'], row['lk'], row['dup'], row['unl'], row['chg'], row['conf'])
        if got != exp:
            bad.append((i, cur, got, exp))
    return bad


class Scenarios(unittest.TestCase):
    def test_every_row(self):
        self.assertEqual(run_rows(act, rec), [])

    def test_coverage(self):
        decisions = {r['dec'] for r in fx.ROWS if r['kind'] == 'S'}
        self.assertEqual(decisions, {'CONFIRMED', 'PARTIAL', 'NOT_EXECUTED', 'UNKNOWN', 'BLOCK', 'INVALID_INPUT'})
        scns = {r['scn'] for r in fx.ROWS}
        for need in ('BUY_FULL_FILL_ONE_EXECUTION', 'SELL_FULL_FILL_ONE_EXECUTION', 'BUY_PARTIAL_FILLS_THEN_FULL', 'BUY_DUPLICATE_EXECUTION_COUNTED_ONCE',
                     'BUY_TIMEOUT_THEN_LATE_FILL', 'SELL_TIMEOUT_THEN_LATE_FILL', 'BUY_VOLUME_DROP_ALONE_INCOMPLETE', 'BUY_MANUAL_EXTRA_CLOSE_AFTER_FULL_FILL',
                     'BUY_WRONG_POSITION', 'SELL_WRONG_REQUEST_ID', 'BUY_STEP_CHANGED', 'BUY_POSITION_MISSING', 'BUY_OVERFILL', 'BUY_NO_REQUEST_BEFORE_2R'):
            self.assertIn(need, scns)

    def test_late_fill_is_accepted_only_through_the_snapshot(self):
        st = act.State()
        act.on_quote(st, 7, act.BUY, 2000.0, 2000.0, 2000.3, 0.5, 0.5, 0.01, 0.01, 100.0)
        act.on_report(st, 'X2R80-7', act.TIMEOUT, 0.0, 0.01)
        self.assertEqual(st.status, act.NEEDS_RECONCILIATION)
        for bid in (2001.0, 2005.0, 1999.0):
            act.on_quote(st, 7, act.BUY, 2000.0, bid, bid + 0.3, 0.5, 0.1, 0.01, 0.01, 100.0)
            act.on_report(st, 'X2R80-7', act.FULL, 0.4, 0.01)
            self.assertEqual(st.status, act.NEEDS_RECONCILIATION)
        o = rec.reconcile(st, rec.Snapshot(True, 7, 'X2R80-7', 0.01, 0.1, [rec.Exec('e1', 'X2R80-7', 0.4)], False))
        self.assertEqual((o.decision, st.status, st.confirmations), (rec.UNKNOWN, act.NEEDS_RECONCILIATION, 0))        # a matching sum alone is not a complete list
        o = rec.reconcile(st, rec.Snapshot(True, 7, 'X2R80-7', 0.01, 0.1, [rec.Exec('e1', 'X2R80-7', 0.4)], True))
        self.assertEqual((o.decision, st.status, st.confirmations), (rec.CONFIRMED, act.DONE, 1))

    def test_reconcile_never_creates_a_request_or_changes_the_plan(self):
        src = _read('tests', 't011_reconcile_reference.py')
        body = src.split('"""', 2)[2]
        self.assertNotIn('REQUEST_ACTION', body)
        self.assertNotIn('on_quote', body)
        self.assertNotIn('es.split', body)
        hdr = _read('src', 'include', 'ExitReconciliation.mqh')
        self.assertNotIn('EA_OnQuote', hdr)
        self.assertNotIn('ES_Split', hdr)
        self.assertNotIn('EA_ACT_REQUEST_PARTIAL_CLOSE', hdr)
        self.assertIn('PS_GridSteps(', hdr)
        self.assertNotIn('PS_GRID_ULPS', hdr)

    def test_more_than_16_executions_is_invalid_and_16_is_accepted(self):
        st = act.State()
        act.on_quote(st, 7, act.BUY, 2000.0, 2000.0, 2000.3, 0.5, 0.5, 0.01, 0.01, 100.0)
        ex17 = [rec.Exec('e%d' % i, 'X2R80-7', 0.01) for i in range(17)]
        before = copy.deepcopy(st)
        self.assertEqual(rec.reconcile(st, rec.Snapshot(True, 7, 'X2R80-7', 0.01, 0.33, ex17, False)).decision, rec.INVALID_INPUT)
        self.assertEqual(st, before)
        ex16 = [rec.Exec('e%d' % i, 'X2R80-7', 0.02) for i in range(15)] + [rec.Exec('e15', 'X2R80-7', 0.1)]     # 0.3 + 0.1 = 0.4
        o = rec.reconcile(st, rec.Snapshot(True, 7, 'X2R80-7', 0.01, 0.1, ex16, True))
        self.assertEqual((o.decision, o.linked_steps, st.status), (rec.CONFIRMED, 40, act.DONE))


class Properties(unittest.TestCase):
    def test_non_finite_and_wrong_types_change_nothing(self):
        nan, inf = float('nan'), float('inf')
        good = dict(position_found=True, position_id=7, request_id='X2R80-7', volume_step=0.01, volume_current=0.1,
                    executions=[rec.Exec('e1', 'X2R80-7', 0.4)], executions_complete=False)
        mutations = [('position_id', 0), ('position_id', True), ('position_id', 7.0), ('request_id', ''), ('request_id', None),
                     ('volume_step', nan), ('volume_step', 0.0), ('volume_step', -0.01), ('volume_current', nan), ('volume_current', inf),
                     ('volume_current', 0.0), ('volume_current', -1.0), ('position_found', 1), ('executions_complete', 'yes'),
                     ('executions', [rec.Exec('e1', 'X2R80-7', nan)]), ('executions', [rec.Exec('e1', 'X2R80-7', inf)]),
                     ('executions', [rec.Exec('e1', 'X2R80-7', -0.4)]), ('executions', [rec.Exec('e1', '', 0.4)]), ('executions', ['e1'])]
        for key, bad in mutations:
            st = act.State()
            act.on_quote(st, 7, act.BUY, 2000.0, 2000.0, 2000.3, 0.5, 0.5, 0.01, 0.01, 100.0)
            before = copy.deepcopy(st)
            o = rec.reconcile(st, rec.Snapshot(**dict(good, **{key: bad})))
            self.assertEqual(o.decision, rec.INVALID_INPUT, (key, bad))
            self.assertEqual(st, before)
        st = act.State()
        self.assertEqual(rec.reconcile(st, None).decision, rec.INVALID_INPUT)

    def test_fuzz_invariants(self):
        rnd = random.Random(20261015)
        for run in range(600):
            st = act.State()
            act.on_quote(st, 7, act.BUY, 2000.0, 2000.0, 2000.3, 0.5, 0.5, 0.01, 0.01, 100.0)
            if rnd.random() < 0.5:
                act.on_report(st, 'X2R80-7', rnd.choice([act.TIMEOUT, act.REJECTED, act.PARTIAL]), 0.1, 0.01)
            plan = (st.initial_steps, st.request_steps, st.request_id, st.volume_step, st.position_id)
            confs = 0
            for _ in range(rnd.randint(1, 6)):
                before = st.status
                n = rnd.randint(0, 4)
                ex = [rec.Exec(rnd.choice(['e1', 'e2', 'e3', 'e1']), rnd.choice(['X2R80-7', 'X2R80-7', 'X2R80-8']), rnd.choice([0.1, 0.2, 0.3, 0.4, 0.05])) for _ in range(n)]
                snap = rec.Snapshot(rnd.random() > 0.1, rnd.choice([7, 7, 7, 8]), 'X2R80-7', rnd.choice([0.01, 0.01, 0.01, 0.001]),
                                    rnd.choice([0.5, 0.4, 0.3, 0.2, 0.1, 0.07]), ex, rnd.random() < 0.5)
                o = rec.reconcile(st, snap)
                self.assertEqual(plan, (st.initial_steps, st.request_steps, st.request_id, st.volume_step, st.position_id))
                self.assertLessEqual(st.confirmations, 1)
                self.assertGreaterEqual(st.confirmations, confs)
                confs = st.confirmations
                if before == act.BLOCKED:
                    self.assertEqual((st.status, o.decision), (act.BLOCKED, rec.BLOCK))
                if st.status == act.DONE:
                    self.assertEqual(o.decision, rec.CONFIRMED)
                if o.decision == rec.CONFIRMED:
                    self.assertEqual(o.linked_steps, st.request_steps)
                self.assertGreaterEqual(o.linked_steps, 0)

    def test_one_confirmation_per_request_over_many_cycles(self):
        for d, level, bid, ask in ((act.BUY, 2000.0, 2000.0, 2000.3), (act.SELL, 1990.0, 1989.0, 1989.4)):
            st = act.State()
            act.on_quote(st, 7, d, level, bid, ask, 0.5, 0.5, 0.01, 0.01, 100.0)
            full = rec.Snapshot(True, 7, 'X2R80-7', 0.01, 0.1, [rec.Exec('e1', 'X2R80-7', 0.4)], True)
            lost = rec.Snapshot(True, 7, 'X2R80-7', 0.01, 0.1, [], False)           # Codex repro: no executions, incomplete -> UNKNOWN
            for cycle in range(25):
                self.assertEqual(rec.reconcile(st, full).decision, rec.CONFIRMED)
                self.assertEqual((st.status, st.confirmations), (act.DONE, 1), cycle)
                self.assertEqual(rec.reconcile(st, full).decision, rec.CONFIRMED)    # same evidence again while DONE
                self.assertEqual((st.status, st.confirmations), (act.DONE, 1))
                o = rec.reconcile(st, lost)
                self.assertEqual((o.decision, st.status, st.confirmations), (rec.UNKNOWN, act.NEEDS_RECONCILIATION, 1), cycle)
                # the plain report path cannot regain DONE nor change the count
                act.on_report(st, 'X2R80-7', act.FULL, 0.4, 0.01)
                self.assertEqual((st.status, st.confirmations), (act.NEEDS_RECONCILIATION, 1))

    def test_report_path_keeps_one_confirmation_when_pending_again(self):
        # REQUEST_PENDING with an old confirmation is not reachable through the allowed transitions (a request starts at 0);
        # the guard is checked on a hand-built state anyway
        st = act.State()
        act.on_quote(st, 7, act.BUY, 2000.0, 2000.0, 2000.3, 0.5, 0.5, 0.01, 0.01, 100.0)
        st.confirmations = 1
        self.assertEqual(act.on_report(st, 'X2R80-7', act.FULL, 0.4, 0.01).event, 'OK')
        self.assertEqual((st.status, st.confirmations), (act.DONE, 1))

    def test_confirmed_needs_a_complete_list(self):
        for complete, dec in ((False, rec.UNKNOWN), (True, rec.CONFIRMED)):
            st = act.State()
            act.on_quote(st, 7, act.BUY, 2000.0, 2000.0, 2000.3, 0.5, 0.5, 0.01, 0.01, 100.0)
            o = rec.reconcile(st, rec.Snapshot(True, 7, 'X2R80-7', 0.01, 0.1, [rec.Exec('e1', 'X2R80-7', 0.4)], complete))
            self.assertEqual(o.decision, dec)
            self.assertEqual(st.status, act.DONE if complete else act.REQUEST_PENDING)

    def test_idempotent_snapshots(self):
        st = act.State()
        act.on_quote(st, 7, act.BUY, 2000.0, 2000.0, 2000.3, 0.5, 0.5, 0.01, 0.01, 100.0)
        snap = rec.Snapshot(True, 7, 'X2R80-7', 0.01, 0.4, [rec.Exec('e1', 'X2R80-7', 0.1)], False)
        o1 = rec.reconcile(st, snap)
        s1 = copy.deepcopy(st)
        o2 = rec.reconcile(st, snap)
        self.assertEqual((o1.decision, o2.decision, o2.changed), (rec.PARTIAL, rec.PARTIAL, False))
        self.assertEqual(st, s1)


class Mutants(unittest.TestCase):
    def _build(self, pairs):
        src = _read('tests', 't011_reconcile_reference.py')
        for old, new in pairs:
            self.assertIn(old, src, 'mutation target absent (vacuous): ' + old[:40])
            src = src.replace(old, new, 1)
        ns = {'__name__': 't011_rec_mutant'}
        exec(compile(src, 't011_rec_mutant', 'exec'), ns)

        class M:
            pass
        m = M()
        for k, v in ns.items():
            setattr(m, k, v)
        return m

    def test_mutants_are_caught(self):
        cases = [
            ('duplicates counted twice', [("            if seen[e.exec_id] == key:\n                dups += 1\n                continue", "            if seen[e.exec_id] == key:\n                dups += 1\n                linked += t006._grid_steps(e.volume, state.volume_step)\n                continue")]),
            ('volume drop alone confirms', [("    if linked == req:\n        if cur != expected:", "    if linked == req or (linked == 0 and cur == state.initial_steps - req):\n        if cur != expected:")]),
            ('overfill accepted', [("    if linked > req:", "    if False:")]),
            ('wrong position accepted', [("    if snap.position_id != state.position_id:", "    if False:")]),
            ('wrong request id accepted', [("    if snap.request_id != state.request_id:", "    if False:")]),
            ('step change accepted', [("    if snap.volume_step != state.volume_step:", "    if False:")]),
            ('missing position accepted', [("    if not snap.position_found:", "    if False:")]),
            ('volume mismatch after full fill accepted', [("        if cur != expected:\n            return _block(state, 'VOLUME_MISMATCH: position", "        if False:\n            return _block(state, 'VOLUME_MISMATCH: position")]),
            ('partial fill becomes DONE', [("    if linked > 0 and cur == expected:\n        out = _not_done", "    if linked > 0 and cur == expected:\n        state.status = act.DONE\n        out = _not_done")]),
            ('unlinked executions counted', [("        if e.request_id != state.request_id:\n            unlinked += 1\n            continue", "        if False:\n            continue")]),
            ('id conflict accepted', [("            return _block(state, 'EXEC_ID_CONFLICT", "            continue\n            return _block(state, 'EXEC_ID_CONFLICT")]),
            ('manual change during partial ignored when complete', [("    if complete:\n        return _block(state, what, **common)", "    if False:\n        return _block(state, what, **common)")]),
            ('incomplete evidence blocks instead of unknown', [("    if complete:\n        return _block(state, what, **common)", "    if True:\n        return _block(state, what, **common)")]),
            ('blocked state is left', [("    if state.status == act.BLOCKED:\n        return Outcome(BLOCK, 'ALREADY_BLOCKED", "    if False:\n        return Outcome(BLOCK, 'ALREADY_BLOCKED")]),
            ('DONE state kept on bad evidence', [("    if done_before:\n        state.status = act.NEEDS_RECONCILIATION", "    if False:\n        state.status = act.NEEDS_RECONCILIATION")]),
            ('confirmation counted every time DONE is regained', [("        if state.confirmations < 1:                  # ONE confirmation per request, also when DONE was lost and is regained\n            state.confirmations = 1", "        state.confirmations += 1")]),
            ('incomplete list confirms', [("        if not complete:\n            out = _not_done(state, done_before, linked, 'UNKNOWN: INCOMPLETE_EVIDENCE", "        if False:\n            out = _not_done(state, done_before, linked, 'UNKNOWN: INCOMPLETE_EVIDENCE")]),
            ('re-check of DONE confirmed again', [("        if done_before:\n            return Outcome(CONFIRMED, 'ALREADY_DONE', **common)", "        if False:\n            return Outcome(CONFIRMED, 'ALREADY_DONE', **common)")]),
            ('execution off the grid accepted', [("        if k < 0:", "        if False:")]),
        ]
        for name, pairs in cases:
            with self.subTest(name):
                m = self._build(pairs)
                try:
                    bad = run_rows(act, m)
                except Exception:
                    bad = ['exception']
                self.assertTrue(bad, 'mutant not caught: ' + name)


class MqlBlock(unittest.TestCase):
    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T011_ReconcileTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())


if __name__ == '__main__':
    unittest.main()
