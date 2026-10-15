"""T019 lifecycle tests (FAKE transport and FAKE store only): persistent index + halt, startup reconcile, tick (fill / gated cancel), events from facts. Never a send."""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import entry_reference as en  # noqa: E402
import lifecycle_reference as lc  # noqa: E402
import t007_planning_reference as tp  # noqa: E402
import test_entry_executor as te  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIG = te.SIGNAL
SCENARIOS = ['index_codec_and_damage', 'register_and_save_failure', 'startup_clean', 'startup_halts_on_unprovable', 'startup_keeps_open_pending', 'tick_fill_unmanaged',
             'cancel_gated_by_enabled_events', 'cancel_uncertain_halts', 'due_events_from_facts', 'damaged_state_never_overwritten']
EV_ALL_ENABLED = tp.EV_SESSION_END | tp.EV_NEWS_BLOCK | tp.EV_DAILY_LIMIT


def placed(direction=1):
    w = te.World(direction)
    assert w.place().final == en.R_PLACED
    st = lc.State(w.tr.account.login)
    notes = []
    assert lc.register(w.store, st, SIG, notes)
    return w, st


def restart(w):
    """a new process with the same disk: the FAKE transport has an EMPTY book (nothing is mapped to a broker fact)"""
    tr = en.FakeTransport()
    tr.quote = en.Quote(True, 2000.0, 2000.3, tr.now)
    return tr


class Index(unittest.TestCase):
    def test_index_codec_and_damage(self):
        st = lc.State(5001234, 'HALT: reason\nwith newline', ['S|a|b|c|L1|M15F1U', 'SIG-2'])
        ok, back = lc.decode(lc.encode(st), 5001234)
        self.assertTrue(ok)
        self.assertEqual((back.ids, back.halted), (st.ids, 'HALT: reason with newline'))
        text = lc.encode(st)
        for bad in (text.replace('SIG-2', 'SIG-3'), text[:-10], text.replace('login=5001234', 'login=5001235')):
            ok, r = lc.decode(bad, 5001234)
            self.assertFalse(ok)
        ok, r = lc.decode(lc.encode(lc.State(77, '', ['A'])), 5001234)
        self.assertEqual((ok, r), (False, 'LOGIN_MISMATCH'))
        body = '%s\n1\nlogin=5\nhalt=\nn=2\nA\n' % lc.HEADER
        ok, r = lc.decode(body + 'CRC=%08X\n' % lc.p.crc32(body), 5)
        self.assertEqual((ok, r), (False, 'BAD_COUNT'))
        self.assertEqual(lc.file_name(5001234), 'VELO_T013_ENTRY_INDEX_5001234.state')

    def test_register_and_save_failure(self):
        w = te.World()
        st = lc.State(w.tr.account.login)
        notes = []
        w.store.fail_write = {1}
        self.assertFalse(lc.register(w.store, st, SIG, notes))
        self.assertIn('LIFECYCLE_STATE_NOT_SAVED', st.halted)
        w2 = te.World()
        st2 = lc.State(w2.tr.account.login)
        w2.store.readback_differs = {1}
        self.assertFalse(lc.register(w2.store, st2, SIG, []))
        self.assertTrue(st2.halted)
        st3 = lc.State(1)
        self.assertFalse(lc.register(te.World().store, st3, 'bad\nid', []))
        self.assertEqual(st3.halted, 'LIFECYCLE_BAD_SIGNAL_ID')
        st4 = lc.State(1)
        store = te.World().store
        for i in range(lc.LC_MAX):
            self.assertTrue(lc.register(store, st4, 'ID%d' % i, []))
        self.assertFalse(lc.register(store, st4, 'ONE-TOO-MANY', []))
        self.assertEqual(st4.halted, 'LIFECYCLE_INDEX_FULL')

    def test_damaged_state_never_overwritten(self):
        w, st = placed()
        name = lc.file_name(w.tr.account.login)
        w.store.files[name] = w.store.files[name].replace(SIG, 'SIG-X')
        damaged = w.store.files[name]
        tr = restart(w)
        st2, notes = lc.startup(w.cfg, tr, w.store, acknowledge=True)
        self.assertIn('LIFECYCLE_STATE_DAMAGED', st2.halted)
        self.assertEqual(w.store.files[name], damaged, 'a damaged file is never repaired or overwritten, an acknowledgement does not change that')
        self.assertEqual((tr.sends, tr.cancels), (0, 0))
        w.store.unreadable = {name}
        st3, _ = lc.startup(w.cfg, tr, w.store)
        self.assertIn('LIFECYCLE_STATE_UNREADABLE', st3.halted)


class Startup(unittest.TestCase):
    def test_startup_clean(self):
        w = te.World()
        st, notes = lc.startup(w.cfg, w.tr, w.store)
        self.assertEqual((st.halted, st.ids, w.store.writes), ('', [], 0), 'nothing indexed: nothing is written')
        for direction in (1, -1):
            w, st = placed(direction)
            w.tr.orders[0].state = en.OS_CANCELED       # the order ended while the EA was away
            st2, notes = lc.startup(w.cfg, w.tr, w.store)
            self.assertEqual((st2.halted, st2.ids), ('', []))
            ok, back = lc.decode(w.store.files[lc.file_name(w.tr.account.login)], w.tr.account.login)
            self.assertEqual(back.ids, [])
            self.assertEqual(w.tr.sends, 1)

    def test_startup_halts_on_unprovable(self):
        for direction in (1, -1):
            w, st = placed(direction)
            tr = restart(w)
            st2, notes = lc.startup(w.cfg, tr, w.store)
            self.assertIn('UNRESOLVED_ENTRY_RECORD', st2.halted)
            self.assertEqual((tr.sends, tr.cancels), (0, 0), 'reconcile never sends or cancels')
            self.assertEqual(w.rec().state, en.ST_RECOVERY, 'the record says it cannot prove the order; it is not turned into a fact')
            st3, _ = lc.startup(w.cfg, restart(w), w.store)                      # the halt survives another restart
            self.assertIn('UNRESOLVED_ENTRY_RECORD', st3.halted)
            self.assertEqual(st3.ids, [SIG])
            # an explicit acknowledgement clears the halt and drops the unresolved id; the record stays, so the signal stays consumed
            st4, notes4 = lc.startup(w.cfg, restart(w), w.store, acknowledge=True)
            self.assertEqual((st4.halted, st4.ids), ('', []))
            self.assertTrue(w.has_file())
            tr5 = restart(w)
            again = en.place(w.cfg, tr5, w.store, en.Runtime(), w.plan, te.permit_for(w.plan, tr5))
            self.assertEqual((again.final, tr5.sends), (en.R_DUPLICATE, 0), 'the signal is still consumed')

    def test_startup_keeps_open_pending(self):
        w, st = placed()
        st2, notes = lc.startup(w.cfg, w.tr, w.store)             # same book: the order is provably still active
        self.assertEqual((st2.halted, st2.ids), ('', [SIG]))
        self.assertEqual((w.tr.sends, w.tr.cancels), (1, 0))


class Tick(unittest.TestCase):
    def test_tick_fill_unmanaged(self):
        for direction in (1, -1):
            w, st = placed(direction)
            w.tr.orders[0].state = en.OS_FILLED
            w.tr.orders[0].position_id = 4242
            notes = lc.tick(w.cfg, w.tr, w.store, st, 0, 0)
            self.assertEqual(st.ids, [])
            self.assertTrue(any(n.startswith('FILLED_UNMANAGED') for n in notes))
            self.assertEqual(st.halted, '')
            self.assertEqual((w.tr.sends, w.tr.cancels), (1, 0), 'no registration, no cancel, no second send')
            self.assertEqual(w.rec().state, en.ST_FILLED)

    def test_cancel_gated_by_enabled_events(self):
        for direction in (1, -1):
            w, st = placed(direction)
            notes = lc.tick(w.cfg, w.tr, w.store, st, tp.EV_SESSION_END, 0)
            self.assertEqual((w.tr.cancels, st.ids), (0, [SIG]))
            self.assertTrue(any(n.startswith('CANCEL_DUE_NOT_ENABLED') for n in notes))
            notes = lc.tick(w.cfg, w.tr, w.store, st, tp.EV_SESSION_END, tp.EV_NEWS_BLOCK)
            self.assertEqual(w.tr.cancels, 0, 'another event enabled does not enable this one')
            notes = lc.tick(w.cfg, w.tr, w.store, st, tp.EV_SESSION_END | tp.EV_NEWS_BLOCK, tp.EV_NEWS_BLOCK)
            self.assertEqual((w.tr.cancels, st.ids, st.halted), (1, [], ''))
            self.assertEqual(w.rec().state, en.ST_CANCELLED)
            self.assertTrue(any(n.startswith('CANCELLED') for n in notes))
            lc.tick(w.cfg, w.tr, w.store, st, EV_ALL_ENABLED, EV_ALL_ENABLED)
            self.assertEqual(w.tr.cancels, 1, 'a cancelled order is not cancelled twice')
            self.assertEqual(w.tr.sends, 1)

    def test_cancel_uncertain_halts(self):
        for mode in ('lost', 'not_effective', 'fails'):
            w, st = placed()
            w.tr.cancel_mode = mode
            lc.tick(w.cfg, w.tr, w.store, st, tp.EV_DAILY_LIMIT, tp.EV_DAILY_LIMIT)
            self.assertIn('CANCEL_NOT_CONFIRMED', st.halted, mode)
            self.assertEqual(w.tr.cancels, 1, mode)
            lc.tick(w.cfg, w.tr, w.store, st, tp.EV_DAILY_LIMIT, tp.EV_DAILY_LIMIT)
            self.assertLessEqual(w.tr.cancels, 1, mode + ': no automatic second cancellation')
            self.assertEqual(w.tr.sends, 1)
            ok, back = lc.decode(w.store.files[lc.file_name(w.tr.account.login)], w.tr.account.login)
            self.assertIn('CANCEL_NOT_CONFIRMED', back.halted, 'the halt is persisted')

    def test_due_events_from_facts(self):
        d = lc.due_events
        self.assertEqual(d(tp.SESSION_OPEN, tp.NEWS_CLEAR, True, False), 0)
        self.assertEqual(d(tp.SESSION_CLOSED, tp.NEWS_CLEAR, False, False), tp.EV_SESSION_END)
        self.assertEqual(d(tp.SESSION_OPEN, tp.NEWS_BLOCKED, False, False), tp.EV_NEWS_BLOCK)
        self.assertEqual(d(tp.SESSION_OPEN, tp.NEWS_CLEAR, True, True), tp.EV_DAILY_LIMIT)
        self.assertEqual(d(tp.SESSION_UNKNOWN, tp.NEWS_UNKNOWN, False, True), 0, 'unknown never asserts an event; an absent daily result does not either')
        self.assertEqual(d(tp.SESSION_CLOSED, tp.NEWS_BLOCKED, True, True), EV_ALL_ENABLED)


class Sources(unittest.TestCase):
    def test_mql_scenarios_pinned(self):
        with open(os.path.join(ROOT, 'src', 'tests', 'EntryLifecycleTest.mq5'), encoding='ascii') as f:
            t = f.read()
        self.assertEqual(re.findall(r'^\s+Scenario_(\w+)\(\);', t, re.M), SCENARIOS)
        for n in SCENARIOS:
            self.assertEqual(len(re.findall(r'void Scenario_%s\(void\)' % n, t)), 1, n)


class Mutants(unittest.TestCase):
    SRC = os.path.join(ROOT, 'tests', 'lifecycle_reference.py')
    NAMES = ('test_index_codec_and_damage', 'test_register_and_save_failure', 'test_damaged_state_never_overwritten')

    def _count_failures(self, old, new):
        with open(self.SRC, encoding='utf-8') as f:
            text = f.read()
        self.assertEqual(text.count(old), 1, old)
        mod = type(sys)('lifecycle_mutant')
        exec(compile(text.replace(old, new), 'mutant', 'exec'), mod.__dict__)
        global lc
        saved = lc
        lc = mod
        try:
            suite = unittest.TestSuite()
            for cls in (Index, Startup, Tick):
                for n in unittest.TestLoader().getTestCaseNames(cls):
                    suite.addTest(cls(n))
            res = unittest.TestResult()
            suite.run(res)
            return len(res.failures) + len(res.errors)
        finally:
            lc = saved

    def test_each_mutant_is_caught(self):
        muts = [("    events = due & enabled\n", "    events = due\n"),
                ("        if res.reason == 'ACTIVE':\n            return OPEN", "        if res.reason == 'ACTIVE':\n            return CLOSED"),
                ("        st.halted = ''\n    if kind == 'OK'", "        pass\n    if kind == 'OK'"),
                ("    if kind == 'DAMAGED':\n        notes.append(st.halted)\n        return st, notes", "    if kind == 'DAMAGED':\n        st = State(acct.login)"),
                ("                if not st.halted:\n                    st.halted = 'CANCEL_NOT_CONFIRMED: %s' % _clean(res.reason)", "                pass"),
                ("            if not st.halted:\n                st.halted = 'UNRESOLVED_ENTRY_RECORD: %s' % _clean(res.reason)", "            pass"),
                ("    if n != len(ids) or n < 0 or n > LC_MAX or any(not i.strip() for i in ids):", "    if False:"),
                ("    if crc != '%08X' % p.crc32(body):\n        return False, 'CRC_MISMATCH'", "    if False:\n        return False, 'CRC_MISMATCH'"),
                ("        if len(st.ids) >= LC_MAX:", "        if False:"),
                ("    return ok and back == text", "    return ok"),
                ("    if session == tp.SESSION_CLOSED:", "    if session != tp.SESSION_OPEN:"),
                ("            res = en.cancel(cfg, tr, store, en.Runtime(), sid, dec)", "            res = en.cancel(cfg, tr, store, en.Runtime(), sid, dec)\n            res = en.cancel(cfg, tr, store, en.Runtime(), sid, dec)")]
        for old, new in muts:
            self.assertGreater(self._count_failures(old, new), 0, 'not caught: ' + old)


if __name__ == '__main__':
    unittest.main()
