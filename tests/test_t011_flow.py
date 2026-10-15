"""T011 restart-flow tests: LOAD -> identity -> snapshot -> ER_Reconcile -> SAVE over the persistence file model, the adapter and the reconciliation references."""
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t011_activation_reference as act  # noqa: E402
import t011_flow_fixtures as fx  # noqa: E402
import t011_flow_reference as fl  # noqa: E402
import t011_persist_reference as p  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = 'VELO_T011_FLOW_TEST.state'


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def prepare(store, kind):
    if kind == fx.MISSING:
        return
    sk = fx.PEND_MAP if kind in (fx.OTHER_IDENT, fx.CORRUPT) else kind
    ok, text = p.encode(fx.start_record(sk))
    assert ok, text
    if kind == fx.CORRUPT:
        text = text.replace('LEVEL=2000', 'LEVEL=2001')
    with open(store.path(NAME), 'wb') as f:
        f.write(text.encode('latin-1'))


def disk_status(store):
    if not store.exists(NAME):
        return '', 0, 0
    ok, rec = p.decode(store.read(NAME))
    return (rec.state.status, rec.generation, rec.state.confirmations) if ok else ('CORRUPT', 0, 0)


def run_rows(mod, counters=None):
    bad = []
    for r in fx.ROWS:
        with tempfile.TemporaryDirectory() as d:
            store = p.FileStore(d)
            prepare(store, r['start'])
            ident = fx.IDENT if r['start'] != fx.OTHER_IDENT else p.Identity(fx.IDENT.server, fx.IDENT.login, fx.IDENT.symbol, 8)
            ra, rb = (fx.PROFILES[r['a']][1], fx.PROFILES[r['b']][1]) if r['a'] >= 0 else (None, None)
            res = mod.run(store, NAME, ident, ra, rb, bool(r['fail']))
            disk, gen, conf = disk_status(store)
            got = (res.final, int(res.snapshot_called), int(res.reconcile_called), int(res.saved), int(res.save_needed), res.generation if r['gen'] else 0,
                   disk if r['disk'] else '', res.state.confirmations if r['conf'] else 0, res.decision, res.adapter_verdict, res.request_produced)
            exp = (r['final'], r['snap'], r['recon'], r['saved'], r['save_needed'], r['gen'], r['disk'], r['conf'], r['decision'], r['adapter'], False)
            unsaved_ok = True
            if r['save_needed'] and not res.saved:
                unsaved_ok = res.state.status == disk           # a failed save exposes the state that IS on disk
            if got != exp or r['reason'] not in res.reason or store.exists(NAME + '.tmp') or not unsaved_ok:
                bad.append((r['name'], got, exp, res.reason))
    return bad


class Flow(unittest.TestCase):
    def test_every_row(self):
        self.assertEqual(run_rows(fl), [])

    def test_gates_never_read_the_snapshot_or_write_the_file(self):
        calls = {'build': 0, 'reconcile': 0}
        real_build, real_rec = fl.ad.build, fl.rec.reconcile
        fl.ad.build = lambda *a, **k: (calls.__setitem__('build', calls['build'] + 1), real_build(*a, **k))[1]
        fl.rec.reconcile = lambda *a, **k: (calls.__setitem__('reconcile', calls['reconcile'] + 1), real_rec(*a, **k))[1]
        try:
            for r in fx.ROWS:
                if r['snap'] == 0:
                    with tempfile.TemporaryDirectory() as d:
                        store = p.FileStore(d)
                        prepare(store, r['start'])
                        before = store.read(NAME) if store.exists(NAME) else None
                        ident = fx.IDENT if r['start'] != fx.OTHER_IDENT else p.Identity(fx.IDENT.server, fx.IDENT.login, fx.IDENT.symbol, 8)
                        fl.run(store, NAME, ident, fx.PROFILES[0][1], fx.PROFILES[0][1])
                        self.assertEqual(store.read(NAME) if store.exists(NAME) else None, before, r['name'])
            self.assertEqual(calls, {'build': 0, 'reconcile': 0})
            # a non-READY adapter verdict never reaches the reconciliation
            for prof in ('API_ERROR', 'EXIT_DEAL_OF_THE_SAME_SIDE'):
                with tempfile.TemporaryDirectory() as d:
                    store = p.FileStore(d)
                    prepare(store, fx.PEND_MAP)
                    fl.run(store, NAME, fx.IDENT, fx.PROFILES[fx.PI[prof]][1], fx.PROFILES[fx.PI[prof]][1])
            self.assertEqual(calls['reconcile'], 0)
        finally:
            fl.ad.build, fl.rec.reconcile = real_build, real_rec

    def test_late_fill_sequence(self):
        with tempfile.TemporaryDirectory() as d:
            store = p.FileStore(d)
            prepare(store, fx.PEND_MAP)
            not_yet, full = fx.PROFILES[fx.PI['NOT_YET_IN_HISTORY']][1], fx.PROFILES[fx.PI['FULL']][1]
            r1 = fl.run(store, NAME, fx.IDENT, not_yet)
            self.assertEqual((r1.final, r1.saved, r1.generation, r1.state.status), (fl.STILL_OPEN, False, 4, act.REQUEST_PENDING))
            r2 = fl.run(store, NAME, fx.IDENT, full)
            self.assertEqual((r2.final, r2.saved, r2.generation, r2.state.confirmations), (fl.DONE, True, 5, 1))
            r3 = fl.run(store, NAME, fx.IDENT, full)
            self.assertEqual((r3.final, r3.saved, r3.generation, r3.state.confirmations), (fl.DONE, False, 5, 1))
            q = act.on_quote(r3.state, 7, act.BUY, 2000.0, 2005.0, 2005.3, 0.5, 0.1, 0.01, 0.01, 100.0)
            self.assertEqual((q.event, q.action), ('IGNORED', act.NONE_ACTION))

    def test_save_failure_exposes_the_disk_state_and_a_rerun_is_idempotent(self):
        with tempfile.TemporaryDirectory() as d:
            store = p.FileStore(d)
            prepare(store, fx.PEND_MAP)
            full = fx.PROFILES[fx.PI['FULL']][1]
            r1 = fl.run(store, NAME, fx.IDENT, full, fail_save=True)
            self.assertEqual((r1.final, r1.saved, r1.state.status, r1.generation), (fl.RECOVERY_REQUIRED, False, act.REQUEST_PENDING, 4))
            self.assertEqual(disk_status(store)[:2], (act.REQUEST_PENDING, 4))
            r2 = fl.run(store, NAME, fx.IDENT, full)
            self.assertEqual((r2.final, r2.saved, r2.generation, r2.state.confirmations), (fl.DONE, True, 5, 1))

    def test_real_file_faults_during_the_save_are_recovery_not_saved(self):
        class Faulty(p.FileStore):
            fault = None

            def save(self, name, rec, fault=None):
                return super().save(name, rec, fault=self.fault)
        for fault in ('move_fails', 'target_differs'):
            with tempfile.TemporaryDirectory() as d:
                store = Faulty(d)
                store.fault = fault
                prepare(store, fx.PEND_MAP)
                res = fl.run(store, NAME, fx.IDENT, fx.PROFILES[0][1])
                self.assertEqual((res.final, res.saved), (fl.RECOVERY_REQUIRED, False), fault)
                self.assertIn('SAVE_FAILED', res.reason)
                self.assertEqual(res.state.status, act.REQUEST_PENDING)

    def test_no_row_and_no_path_produces_a_request(self):
        for r in fx.ROWS:
            with tempfile.TemporaryDirectory() as d:
                store = p.FileStore(d)
                prepare(store, r['start'])
                ra = fx.PROFILES[r['a']][1] if r['a'] >= 0 else None
                res = fl.run(store, NAME, fx.IDENT, ra)
                self.assertFalse(res.request_produced)
                self.assertNotEqual(res.state.status, act.IDLE) if r['start'] not in (fx.IDLE,) else None


class Mutants(unittest.TestCase):
    def test_mutants_are_caught(self):
        src = _read('tests', 't011_flow_reference.py')
        cases = [
            ('unusable load continues', "    if o.generation == 0:\n        out.reason", "    if False:\n        out.reason"),
            ('missing map gate removed', "    if not o.orders:\n        out.reason", "    if False:\n        out.reason"),
            ('adapter UNKNOWN bypassed', "    if res.verdict == ad.UNKNOWN:", "    if False:"),
            ('adapter BLOCK bypassed', "    if res.verdict == ad.BLOCK:", "    if False:"),
            ('save skipped', "    if out.save_needed:\n        if not after_ok:", "    if False:\n        if not after_ok:"),
            ('save failure ignored', "        if not ok:\n            out.state, out.reason = disk,", "        if False:\n            out.state, out.reason = disk,"),
            ('generation not incremented', "_rec(o, o.generation + 1, identity, st)", "_rec(o, o.generation, identity, st)"),
            ('unsaved state exposed after a failure', "            out.state, out.reason = disk, 'SAVE_FAILED: ' + why", "            out.state, out.reason = st, 'SAVE_FAILED: ' + why"),
            ('DONE trusted from the file', "    if not o.orders:\n        out.reason", "    if st.status == act.DONE:\n        out.final = DONE\n        return out\n    if not o.orders:\n        out.reason"),
            ('always save', "    out.save_needed = not (before_ok and after_ok and before_text == after_text)", "    out.save_needed = True"),
            ('blocked state read anyway', "    if o.verdict == p.USABLE_BLOCKED:", "    if False:"),
            ('idle state reconciled', "    if o.verdict == p.USABLE_IDLE:", "    if False:"),
            ('stored map replaced by an invented one', "    mp = ad.Map(st.request_id, st.position_id, identity.symbol, list(o.orders), bool(o.map_complete))",
             "    mp = ad.Map(st.request_id, st.position_id, identity.symbol, [501], True)"),
            ('save error not reported as recovery', "            out.state, out.reason = disk, 'SAVE_FAILED: ' + why + '; the reconciled state was NOT persisted'\n            return out\n        out.saved = True",
             "            out.state, out.reason = disk, 'SAVE_FAILED: ' + why + '; the reconciled state was NOT persisted'\n            out.final = STILL_OPEN\n            return out\n        out.saved = True"),
        ]
        for name, old, new in cases:
            with self.subTest(name):
                self.assertIn(old, src, 'vacuous mutant')
                ns = {'__name__': 'flow_mutant'}
                exec(compile(src.replace(old, new, 1), 'flow_mutant', 'exec'), ns)

                class M:
                    pass
                m = M()
                for k, v in ns.items():
                    setattr(m, k, v)
                try:
                    caught = bool(run_rows(m))
                except Exception:
                    caught = True
                self.assertTrue(caught, 'mutant not caught: ' + name)


class Sources(unittest.TestCase):
    def setUp(self):
        self.h = re.sub(r'//[^\n]*', '', _read('src', 'include', 'ExitRestartFlow.mqh'))

    def test_the_flow_composes_the_existing_pieces_in_order_and_produces_no_request(self):
        run = self.h[self.h.index('bool ERF_Run('):]
        order = ['ESF_Load(', 'XA_ReadAndBuild(', 'XA_Build(', 'ER_Reconcile(', 'ESF_Save(']
        pos = [run.index(s) for s in order]
        self.assertEqual(pos, sorted(pos))
        for s in order:
            self.assertEqual(self.h.count(s), 1, s)
        for word in ('EA_OnQuote', 'EA_ACT_REQUEST', 'EA_OnReport', 'EA_RequestId', 'OrderSend', 'CTrade', 'MqlTradeRequest', 'Sleep', 'TimeCurrent', 'TimeGMT', 'FileOpen', 'FileMove',
                     'PositionSelect', 'SymbolInfo', 'retry', 'Retry'):
            self.assertNotIn(word, self.h)
        self.assertIn('r.request_produced=false;', self.h)
        self.assertNotIn('request_produced=true', self.h)

    def test_er_reconcile_is_only_reachable_after_a_ready_verdict(self):
        run = self.h[self.h.index('bool ERF_Run('):]
        i = run.index('ER_Reconcile(')
        pre = run[:i]
        self.assertIn('if(xr.verdict==XA_UNKNOWN)', pre)
        self.assertIn('if(xr.verdict==XA_BLOCK)', pre)
        self.assertIn('if(o.generation==0)', pre)
        self.assertIn('if(o.n_orders==0)', pre)
        self.assertLess(pre.index('if(o.generation==0)'), pre.index('XA_MapInit('))
        self.assertLess(pre.index('if(o.n_orders==0)'), pre.index('XA_Build('))

    def test_the_map_comes_from_the_record_only(self):
        run = self.h[self.h.index('bool ERF_Run('):]
        self.assertIn('XA_MapAdd(mp,o.orders[i]);', run)
        self.assertEqual(run.count('XA_MapAdd('), 1)

    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T011_FlowTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())


if __name__ == '__main__':
    unittest.main()
