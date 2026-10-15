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
import test_eo as teo  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIG = te.SIGNAL
SCENARIOS = ['index_codec_and_damage', 'register_and_save_failure', 'startup_clean', 'startup_halts_on_unprovable', 'startup_keeps_open_pending', 'tick_fill_unmanaged',
             'cancel_gated_by_enabled_events', 'cancel_uncertain_halts', 'due_events_from_facts', 'damaged_state_never_overwritten',
             'index_saved_before_send', 'no_send_when_index_unusable', 'crash_windows_restart_halts', 'two_instances_no_lost_update', 'refused_instance_and_wrong_release',
             'release_only_by_owner_on_failure_paths', 'damage_during_run_never_overwritten']
EV_ALL_ENABLED = tp.EV_SESSION_END | tp.EV_NEWS_BLOCK | tp.EV_DAILY_LIMIT


def owner(store, login):
    st = lc.State(login)
    assert lc.acquire(store, login, st)
    return st


def guarded_place(w, st, guard=None):
    """the sequence the gate defines: reserve (index saved + read back) -> executor -> settled"""
    guard = guard or lc.Guard(w.store, st)
    ok, why = guard.reserve(SIG)
    if not ok:
        return None, guard, why
    res = w.place()
    guard.settled(SIG, res)
    return res, guard, ''


def placed(direction=1):
    w = te.World(direction)
    st = owner(w.store, w.tr.account.login)
    res, guard, why = guarded_place(w, st)
    assert res.final == en.R_PLACED, why
    return w, st


def new_process(w, keep_book=False):
    """a restart: the same disk, no lock held; the FAKE book is EMPTY (nothing is mapped to a broker fact) unless the caller keeps it"""
    store = en.FakeStore()
    store.files = w.store.files
    if keep_book:
        return w.tr, store
    tr = en.FakeTransport()
    tr.quote = en.Quote(True, 2000.0, 2000.3, tr.now)
    return tr, store


def start(cfg, tr, store, ack=False):
    return lc.startup(cfg, tr, store, store, ack)


class CountingStore(en.FakeStore):
    """counts the accesses to the lifecycle index file"""
    def __init__(self):
        super().__init__()
        self.index_reads = 0
        self.index_writes = 0

    def read(self, name):
        if name.startswith('VELO_T013_ENTRY_INDEX_'):
            self.index_reads += 1
        return super().read(name)

    def write(self, name, text):
        if name.startswith('VELO_T013_ENTRY_INDEX_'):
            self.index_writes += 1
        return super().write(name, text)


def live(dirn, guard=None, w=None):
    """early build (baseline), then the build in which the FVG candidate is confirmed: the first real signal, through the orchestrator and the gate"""
    w = w or teo.World(dirn)
    o1, l1 = teo.observer_n(dirn, 2)
    w.step(o1, l1, pre_send=guard)
    o2, l2 = teo.observer_n(dirn, 3)
    return w, w.step(o2, l2, pre_send=guard)


def index_ids(store, login):
    ok, text = store.read(lc.file_name(login))
    ok, st = lc.decode(text, login)
    return st.ids if ok else None


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
        self.assertEqual(lc.lock_key(5001234), 'VELO_T013_LOCK_INDEX_5001234')

    def test_register_and_save_failure(self):
        w = te.World()
        st = owner(w.store, w.tr.account.login)
        w.store.fail_write = {1}
        self.assertFalse(lc.register(w.store, st, SIG, []))
        self.assertIn('LIFECYCLE_STATE_NOT_SAVED', st.halted)
        w2 = te.World()
        st2 = owner(w2.store, w2.tr.account.login)
        w2.store.readback_differs = {1}
        self.assertFalse(lc.register(w2.store, st2, SIG, []))
        self.assertTrue(st2.halted)
        st3 = owner(te.World().store, 1)
        self.assertFalse(lc.register(te.World().store, st3, 'bad\nid', []))
        self.assertEqual(st3.halted, 'LIFECYCLE_BAD_SIGNAL_ID')
        store = te.World().store
        st4 = owner(store, 1)
        for i in range(lc.LC_MAX):
            self.assertTrue(lc.register(store, st4, 'ID%d' % i, []))
        self.assertFalse(lc.register(store, st4, 'ONE-TOO-MANY', []))
        self.assertEqual(st4.halted, 'LIFECYCLE_INDEX_FULL')

    def test_damaged_state_never_overwritten(self):
        w, st = placed()
        name = lc.file_name(w.tr.account.login)
        w.store.files[name] = w.store.files[name].replace(SIG, 'SIG-X')
        damaged = w.store.files[name]
        tr, store = new_process(w)
        st2, notes = start(w.cfg, tr, store, ack=True)
        self.assertIn('LIFECYCLE_STATE_DAMAGED', st2.halted)
        self.assertEqual(store.files[name], damaged, 'a damaged file is never repaired or overwritten, an acknowledgement does not change that')
        self.assertEqual((tr.sends, tr.cancels), (0, 0))
        tr2, store2 = new_process(w)
        store2.unreadable = {name}
        st3, _ = start(w.cfg, tr2, store2)
        self.assertIn('LIFECYCLE_STATE_UNREADABLE', st3.halted)


class Startup(unittest.TestCase):
    def test_startup_clean(self):
        w = te.World()
        st, notes = start(w.cfg, w.tr, w.store)
        self.assertEqual((st.halted, st.ids, w.store.writes), ('', [], 0), 'nothing indexed: nothing is written')
        self.assertTrue(st.lock_owned)
        for direction in (1, -1):
            w, st = placed(direction)
            w.tr.orders[0].state = en.OS_CANCELED       # the order ended while the EA was away
            tr, store = new_process(w, keep_book=True)
            st2, notes = start(w.cfg, tr, store)
            self.assertEqual((st2.halted, st2.ids), ('', []))
            ok, back = lc.decode(store.files[lc.file_name(w.tr.account.login)], w.tr.account.login)
            self.assertEqual(back.ids, [])
            self.assertEqual(w.tr.sends, 1)

    def test_startup_halts_on_unprovable(self):
        for direction in (1, -1):
            w, st = placed(direction)
            tr, store = new_process(w)
            st2, notes = start(w.cfg, tr, store)
            self.assertIn('UNRESOLVED_ENTRY_RECORD', st2.halted)
            self.assertEqual((tr.sends, tr.cancels), (0, 0), 'reconcile never sends or cancels')
            self.assertEqual(w.rec().state, en.ST_RECOVERY, 'the record says it cannot prove the order; it is not turned into a fact')
            tr3, store3 = new_process(w)
            st3, _ = start(w.cfg, tr3, store3)                                   # the halt survives another restart
            self.assertIn('UNRESOLVED_ENTRY_RECORD', st3.halted)
            self.assertEqual(st3.ids, [SIG])
            # an explicit acknowledgement clears the halt and drops the unresolved id; the record stays, so the signal stays consumed
            tr4, store4 = new_process(w)
            st4, notes4 = start(w.cfg, tr4, store4, ack=True)
            self.assertEqual((st4.halted, st4.ids), ('', []))
            self.assertTrue(w.has_file())
            tr5 = en.FakeTransport()
            tr5.quote = en.Quote(True, 2000.0, 2000.3, tr5.now)
            again = en.place(w.cfg, tr5, store4, en.Runtime(), w.plan, te.permit_for(w.plan, tr5))
            self.assertEqual((again.final, tr5.sends), (en.R_DUPLICATE, 0), 'the signal is still consumed')

    def test_startup_keeps_open_pending(self):
        w, st = placed()
        tr, store = new_process(w, keep_book=True)       # the same book: the order is provably still active
        st2, notes = start(w.cfg, tr, store)
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


class IndexBeforeSend(unittest.TestCase):
    """review finding 1: the index (saved + read back) exists BEFORE every send, through the real orchestrator and gate"""

    def test_index_saved_before_send(self):
        for dirn in (1, -1):
            w = teo.World(dirn)
            login = w.tr.account.login
            st = owner(w.store, login)
            guard = lc.Guard(w.store, st)
            seen = []
            real_send = w.tr.send

            def spy(req):
                ids = index_ids(w.store, login)
                seen.append((ids is not None and len(ids) == 1, any(n.startswith('VELO_T013_ENTRY_%d_' % login) for n in w.store.files)))
                return real_send(req)
            w.tr.send = spy
            w, out = live(dirn, guard, w)
            self.assertTrue(out.request)
            self.assertEqual(seen, [(True, True)], 'at the send: the index holds the signal and the intent exists')
            self.assertEqual(index_ids(w.store, login), [out.spb.signal_id])
            self.assertEqual((w.tr.sends, st.halted), (1, ''))

    def test_gate_block_never_reserves_and_keeps_the_signal(self):
        for dirn in (1, -1):
            w = teo.World(dirn)
            st = owner(w.store, w.tr.account.login)
            guard = lc.Guard(w.store, st)
            w.mk.session = tp.SESSION_CLOSED
            w, out = live(dirn, guard, w)
            self.assertEqual(out.status, 'GATE_BLOCKED')
            self.assertEqual((w.tr.sends, w.store.writes, [n for n in w.store.files]), (0, 0, []), 'no index write, no intent, no send')
            self.assertEqual(guard.calls, 0)
            w.mk.session = tp.SESSION_OPEN
            o2, l2 = teo.observer_n(dirn, 3)
            out2 = w.step(o2, l2, pre_send=guard)
            self.assertTrue(out2.request, 'the blocked attempt did not consume the signal')
            self.assertEqual((w.tr.sends, guard.calls), (1, 1))

    def test_no_send_when_the_index_is_unusable(self):
        def full(w, st):
            for i in range(lc.LC_MAX):
                self.assertTrue(lc.register(w.store, st, 'OTHER-%d' % i, []))
            w.store.writes = 0

        cases = {'save fails': (lambda w, st: setattr(w.store, 'fail_write', {1}), 'PRE_SEND_RESERVATION_FAILED: INDEX_NOT_SAVED'),
                 'read-back differs': (lambda w, st: setattr(w.store, 'readback_differs', {1}), 'PRE_SEND_RESERVATION_FAILED: INDEX_NOT_SAVED'),
                 'index full': (full, 'PRE_SEND_RESERVATION_FAILED: INDEX_NOT_SAVED: LIFECYCLE_INDEX_FULL'),
                 'damaged at startup': (lambda w, st: setattr(st, 'halted', 'LIFECYCLE_STATE_DAMAGED: CRC_MISMATCH'), 'PRE_SEND_RESERVATION_FAILED: LIFECYCLE_HALTED'),
                 'lock not owned': (lambda w, st: setattr(st, 'lock_owned', False), 'PRE_SEND_RESERVATION_FAILED: LIFECYCLE_LOCK_NOT_OWNED')}
        for dirn in (1, -1):
            for label, (setup, reason) in cases.items():
                w = teo.World(dirn)
                st = owner(w.store, w.tr.account.login)
                guard = lc.Guard(w.store, st)
                setup(w, st)
                w, out = live(dirn, guard, w)
                tag = '%s dir %d' % (label, dirn)
                self.assertEqual(out.status, 'RESERVATION_FAILED', tag)
                self.assertTrue(out.reason.startswith(reason), tag + ': ' + out.reason)
                if label == 'lock not owned':
                    self.assertEqual(out.reason, reason, tag)
                self.assertEqual(w.tr.sends, 0, tag)
                self.assertFalse(any(n.startswith('VELO_T013_ENTRY_%d_' % w.tr.account.login) for n in w.store.files), tag + ': no intent')
                self.assertFalse(out.request, tag)
                self.assertNotIn(out.spb.signal_id, w.o.handled, tag + ': the signal is not consumed')

    def test_a_refusal_before_the_intent_releases_the_reservation(self):
        for dirn in (1, -1):
            w = teo.World(dirn)
            login = w.tr.account.login
            st = owner(w.store, login)
            guard = lc.Guard(w.store, st)
            w.tr.quote = en.Quote(True, w.tr.quote.bid, w.tr.quote.ask, w.tr.now - 1000)      # the executor's own market check refuses: no intent
            w, out = live(dirn, guard, w)
            self.assertEqual(out.result.final, en.R_REFUSED)
            self.assertEqual((w.tr.sends, st.halted), (0, ''))
            self.assertFalse(any(n.startswith('VELO_T013_ENTRY_%d_' % login) for n in w.store.files), 'no intent')
            self.assertEqual(index_ids(w.store, login), [], 'a reservation that never became a record is released, so a restart does not halt on it')
            self.assertNotIn(out.spb.signal_id, w.o.handled)

    def test_gate_hook_is_called_only_after_the_gate_allowed_and_before_the_executor(self):
        for dirn in (1, -1):
            w = teo.World(dirn)
            order = []

            class Hook:
                calls = 0

                def reserve(self, signal_id):
                    order.append(('reserve', w.tr.sends, w.store.writes, w.store.lock_calls))
                    return True, ''

                def settled(self, signal_id, res):
                    order.append(('settled', res.final))
            hook = Hook()
            w, out = live(dirn, hook, w)
            self.assertEqual(order[0], ('reserve', 0, 0, 0), 'before any write, lock or send')
            self.assertEqual(order[1], ('settled', en.R_PLACED))
            self.assertEqual(len(order), 2)


class Boom(Exception):
    """a simulated process death"""


class CrashAfterReserve(lc.Guard):
    def reserve(self, signal_id):
        ok, why = super().reserve(signal_id)
        raise Boom()


class Crash(unittest.TestCase):
    """a restart finds every reserved signal and halts when the proof is missing; a restart never sends"""

    def test_crash_windows_restart_halts(self):
        for dirn in (1, -1):
            # (a) the index is saved, the process dies before the intent
            w = teo.World(dirn)
            login = w.tr.account.login
            st = owner(w.store, login)
            with self.assertRaises(Boom):
                live(dirn, CrashAfterReserve(w.store, st), w)
            ids = index_ids(w.store, login)
            self.assertEqual(len(ids), 1)
            self.assertFalse(any(n.startswith('VELO_T013_ENTRY_%d_' % login) for n in w.store.files))
            tr, store = new_process(w)
            st2, notes = start(w.cfg.exec, tr, store)
            self.assertIn('UNRESOLVED_ENTRY_RECORD', st2.halted, 'a reserved signal without a record is not provably harmless: the layer halts')
            self.assertEqual((tr.sends, tr.cancels), (0, 0))
            self.assertEqual(st2.ids, ids)
            # (b) the intent is saved, the pre-check refuses and its state cannot be saved: the record stays INTENT, zero sends
            w = teo.World(dirn)
            st = owner(w.store, w.tr.account.login)
            guard = lc.Guard(w.store, st)
            w.tr.precheck_ok = False
            w.store.fail_write = {3}                 # 1 = index, 2 = intent, 3 = the state after the refusal
            w, out = live(dirn, guard, w)
            self.assertEqual(w.tr.sends, 0)
            sig = out.spb.signal_id
            self.assertEqual(en.decode(w.store.files[en.file_name(w.tr.account.login, sig)])[1].state, en.ST_INTENT)
            tr, store = new_process(w)
            st2, notes = start(w.cfg.exec, tr, store)
            self.assertIn('UNRESOLVED_ENTRY_RECORD', st2.halted)
            self.assertEqual((tr.sends, tr.cancels), (0, 0))
            self.assertEqual(st2.ids, [sig])
            # (c) the send happened, the outcome could not be saved: INTENT on disk
            w = teo.World(dirn)
            st = owner(w.store, w.tr.account.login)
            guard = lc.Guard(w.store, st)
            w.store.fail_write = {3}                 # 1 = index, 2 = intent, 3 = the outcome after the send
            w, out = live(dirn, guard, w)
            self.assertEqual(w.tr.sends, 1)
            sig = out.spb.signal_id
            self.assertEqual(index_ids(w.store, w.tr.account.login), [sig], 'the index was saved before the send')
            tr, store = new_process(w)               # empty FAKE book: no proof
            st2, notes = start(w.cfg.exec, tr, store)
            self.assertIn('UNRESOLVED_ENTRY_RECORD', st2.halted)
            self.assertEqual((tr.sends, tr.cancels), (0, 0))
            tr, store = new_process(w, keep_book=True)       # the book still holds the order: the existing recovery links it by the unique tuple
            st3, notes = start(w.cfg.exec, tr, store)
            self.assertEqual(w.tr.sends, 1, 'a restart never sends')
            self.assertIn(sig, st3.ids)


class Instances(unittest.TestCase):
    """review finding 2: exclusive ownership of the index through the existing lock mechanism"""

    def test_two_instances_no_lost_update(self):
        w = te.World()
        store = CountingStore()
        login = w.tr.account.login
        a = owner(store, login)
        ga = lc.Guard(store, a)
        self.assertTrue(ga.reserve('SIG-A')[0])
        after_a = (dict(store.files), store.index_reads, store.index_writes)
        tr_b = en.FakeTransport()
        b, notes = lc.startup(w.cfg, tr_b, store, store, False)
        self.assertEqual(b.halted, 'LIFECYCLE_INSTANCE_LOCK_NOT_ACQUIRED')
        self.assertFalse(b.lock_owned)
        self.assertEqual((dict(store.files), store.index_reads, store.index_writes), after_a, 'the refused instance neither reads nor writes the index')
        gb = lc.Guard(store, b)
        self.assertFalse(gb.reserve('SIG-B')[0])
        self.assertFalse(lc.register(store, b, 'SIG-B', []))
        self.assertEqual(lc.tick(w.cfg, tr_b, store, b, EV_ALL_ENABLED, EV_ALL_ENABLED), [])
        lc.halt(store, b, 'x', [])
        self.assertEqual((tr_b.sends, tr_b.cancels, dict(store.files)), (0, 0, after_a[0]))
        self.assertEqual((store.index_reads, store.index_writes), after_a[1:])
        # A keeps working and its update is not lost
        self.assertTrue(lc.register(store, a, 'SIG-A2', []))
        self.assertEqual(index_ids(store, login), ['SIG-A', 'SIG-A2'])
        lc.release(store, a)
        c, _ = lc.startup(w.cfg, en.FakeTransport(), store, store, False)
        self.assertTrue(c.lock_owned)
        self.assertEqual(c.ids, ['SIG-A', 'SIG-A2'] if not c.halted else c.ids)
        self.assertTrue(lc.register(store, c, 'SIG-C', []))
        self.assertEqual(index_ids(store, login), ['SIG-A', 'SIG-A2', 'SIG-C'], 'no update of the other instance is lost')

    def test_an_instance_without_the_lock_neither_reconciles_nor_cancels(self):
        w, st = placed()
        forged = lc.State(w.tr.account.login, '', [SIG])             # knows the id, does not own the index
        writes = w.store.writes
        self.assertEqual(lc.tick(w.cfg, w.tr, w.store, forged, EV_ALL_ENABLED, EV_ALL_ENABLED), [])
        self.assertEqual((w.tr.cancels, w.tr.sends, w.store.writes, w.rec().state), (0, 1, writes, en.ST_PLACED))

    def test_refused_instance_and_wrong_release_keep_the_lock(self):
        w = te.World()
        store = en.FakeStore()
        login = w.tr.account.login
        a = owner(store, login)
        key = lc.lock_key(login)
        self.assertEqual(store.held, {key})
        b = lc.State(login)
        self.assertFalse(lc.acquire(store, login, b))
        self.assertFalse(b.lock_owned)
        unlocks = store.unlock_calls
        lc.release(store, b)                                      # a refused instance releases nothing
        lc.release(store, b)
        forged = lc.State(login)
        forged.lock_key = key                                     # a key without ownership
        lc.release(store, forged)
        self.assertEqual((store.held, store.unlock_calls), ({key}, unlocks), "the owner's lock is untouched")
        self.assertTrue(lc.register(store, a, SIG, []), 'the owner still works')
        lc.release(store, a)
        self.assertEqual((store.held, store.unlock_calls), (set(), unlocks + 1))
        lc.release(store, a)                                      # a second release by the same owner is a no-op
        self.assertEqual(store.unlock_calls, unlocks + 1)
        self.assertFalse(a.lock_owned)
        self.assertFalse(lc.register(store, a, 'AFTER-RELEASE', []), 'no index access after the release')
        self.assertTrue(lc.acquire(store, login, b), 'after the owner released, another instance can take it')

    def test_release_only_by_owner_on_failure_paths(self):
        w = te.World()
        login = w.tr.account.login
        # a damaged index: the instance still owns the lock (it keeps running halted) and releases it itself
        w0, st0 = placed()
        name = lc.file_name(login)
        w0.store.files[name] = w0.store.files[name].replace(SIG, 'SIG-X')
        tr, store = new_process(w0)
        st, _ = start(w0.cfg, tr, store)
        self.assertIn('LIFECYCLE_STATE_DAMAGED', st.halted)
        self.assertTrue(st.lock_owned)
        self.assertEqual(store.held, {lc.lock_key(login)})
        lc.release(store, st)
        self.assertEqual(store.held, set())
        # an unreadable account: nothing was acquired, nothing is released
        w2 = te.World()
        w2.tr.account.read_ok = False
        st2, _ = start(w2.cfg, w2.tr, w2.store)
        self.assertEqual((st2.halted, st2.lock_owned, w2.store.lock_calls, w2.store.unlock_calls), ('ACCOUNT_UNREADABLE', False, 0, 0))
        # a reservation that fails keeps the ownership (it is the owner's to release, not the failure path's)
        w3 = te.World()
        st3 = owner(w3.store, login)
        w3.store.fail_write = {1}
        self.assertFalse(lc.Guard(w3.store, st3).reserve(SIG)[0])
        self.assertTrue(st3.lock_owned)
        self.assertEqual(w3.store.held, {lc.lock_key(login)})
        self.assertEqual(w3.store.unlock_calls, 0)
        # a refused start releases nothing of the other instance
        w4 = te.World()
        store4 = w4.store
        owner(store4, login)
        st4, _ = lc.startup(w4.cfg, en.FakeTransport(), store4, store4, False)
        self.assertEqual((st4.lock_owned, store4.unlock_calls, store4.held), (False, 0, {lc.lock_key(login)}))


class DamageDuringRun(unittest.TestCase):
    """Codex finding on 10a2ee1: a valid index at the start, damaged AFTER it: Reserve -> register -> save used to overwrite the proof with a fresh CRC and allow a send.
    The existing index is validated before every update and before every lifecycle action; damage or an unreadable file halts without writing over it."""

    def corrupt(self, w, how):
        name = lc.file_name(w.tr.account.login)
        if how == 'bytes':
            w.store.files[name] = w.store.files[name].replace('halt=\n', 'halt=X\n')
        else:
            w.store.unreadable = {name}
        return name, w.store.files[name]

    def started(self, dirn):
        """a VALID existing index (no ids) and the lock owned after the start"""
        w = teo.World(dirn)
        login = w.tr.account.login
        self.assertTrue(lc.save(w.store, lc.State(login)))
        st, notes = start(w.cfg.exec, w.tr, w.store)
        self.assertTrue(st.lock_owned)
        self.assertEqual((st.halted, st.ids), ('', []))
        return w, st

    def test_entry_attempt_after_damage_halts_without_a_send_or_a_write(self):
        for dirn in (1, -1):
            for how in ('bytes', 'unreadable'):
                w, st = self.started(dirn)
                name, original = self.corrupt(w, how)
                writes = w.store.writes
                guard = lc.Guard(w.store, st)
                w, out = live(dirn, guard, w)
                tag = '%s dir %d' % (how, dirn)
                self.assertEqual(out.status, 'RESERVATION_FAILED', tag)
                self.assertEqual(w.tr.sends, 0, tag)
                self.assertFalse(any(n.startswith('VELO_T013_ENTRY_%d_' % w.tr.account.login) for n in w.store.files), tag + ': no new intent')
                self.assertEqual((w.store.files[name], w.store.writes), (original, writes), tag + ': the original bytes are untouched, nothing was written')
                self.assertIn('LIFECYCLE_STATE_', st.halted, tag)
                self.assertTrue(st.lock_owned and w.store.held == {lc.lock_key(w.tr.account.login)} and w.store.unlock_calls == 0, tag + ': the failure does not release the lock')
                self.assertNotIn(out.spb.signal_id, w.o.handled, tag)

    def test_a_tick_with_cancel_enabled_and_a_damaged_index_cancels_nothing(self):
        for dirn in (1, -1):
            for how in ('bytes', 'unreadable'):
                w, st = placed(dirn)
                name, original = self.corrupt(w, how)
                writes, unlocks = w.store.writes, w.store.unlock_calls
                notes = lc.tick(w.cfg, w.tr, w.store, st, EV_ALL_ENABLED, EV_ALL_ENABLED)
                tag = '%s dir %d' % (how, dirn)
                self.assertEqual((w.tr.cancels, w.tr.sends), (0, 1), tag)
                self.assertEqual((w.store.files[name], w.store.writes), (original, writes), tag)
                self.assertIn('LIFECYCLE_STATE_', st.halted, tag)
                self.assertEqual(w.rec().state, en.ST_PLACED, tag + ': no reconcile either')
                self.assertTrue(st.lock_owned and w.store.unlock_calls == unlocks and w.store.held == {lc.lock_key(w.tr.account.login)}, tag)

    def test_halt_persist_and_settled_never_repair_an_unusable_index(self):
        for dirn in (1, -1):
            for how in ('bytes', 'unreadable'):
                w, st = self.started(dirn)
                name, original = self.corrupt(w, how)
                writes = w.store.writes
                guard = lc.Guard(w.store, st)
                notes = []
                lc.halt(w.store, st, 'x', notes)
                self.assertFalse(lc.register(w.store, st, 'NEW-1', notes))
                guard.new = True
                st.ids.append('NEW-2')
                guard.settled('NEW-2', None)                  # no record: the release path tries to persist
                lc.tick(w.cfg.exec, w.tr, w.store, st, 0, 0)
                tag = '%s dir %d' % (how, dirn)
                self.assertEqual((w.store.files[name], w.store.writes), (original, writes), tag + ': nothing writes over the evidence')
                self.assertTrue(st.lock_owned and w.store.unlock_calls == 0, tag)
        lc.release(w.store, st)                                # the normal release still works
        self.assertEqual((w.store.held, st.lock_owned), (set(), False))

    def test_a_valid_index_and_the_initial_creation_work_as_before(self):
        for dirn in (1, -1):
            w = teo.World(dirn)
            login = w.tr.account.login
            st = owner(w.store, login)                         # no file yet: the first save creates it
            self.assertTrue(lc.register(w.store, st, 'ID-1', []))
            self.assertTrue(lc.register(w.store, st, 'ID-2', []))      # a valid existing file is updated
            self.assertEqual(index_ids(w.store, login), ['ID-1', 'ID-2'])
            w3 = teo.World(dirn)
            st3 = owner(w3.store, w3.tr.account.login)
            w3, out = live(dirn, lc.Guard(w3.store, st3), w3)
            self.assertTrue(out.request)
            self.assertEqual(index_ids(w3.store, w3.tr.account.login), [out.spb.signal_id])


class Sources(unittest.TestCase):
    def test_mql_scenarios_pinned(self):
        with open(os.path.join(ROOT, 'src', 'tests', 'EntryLifecycleTest.mq5'), encoding='ascii') as f:
            t = f.read()
        self.assertEqual(re.findall(r'^\s+Scenario_(\w+)\(\);', t, re.M), SCENARIOS)
        for n in SCENARIOS:
            self.assertEqual(len(re.findall(r'void Scenario_%s\(void\)' % n, t)), 1, n)


class Mutants(unittest.TestCase):
    SRC = os.path.join(ROOT, 'tests', 'lifecycle_reference.py')
    GATE = os.path.join(ROOT, 'tests', 'entry_gate_reference.py')

    def _suite_failures(self):
        suite = unittest.TestSuite()
        for cls in (Index, Startup, Tick, IndexBeforeSend, Crash, Instances, DamageDuringRun):
            for n in unittest.TestLoader().getTestCaseNames(cls):
                suite.addTest(cls(n))
        res = unittest.TestResult()
        suite.run(res)
        return len(res.failures) + len(res.errors)

    def _count_failures(self, old, new, path=None):
        path = path or self.SRC
        with open(path, encoding='utf-8') as f:
            text = f.read()
        self.assertEqual(text.count(old), 1, old)
        gate = (path == self.GATE)
        mod = type(sys)('entry_gate_mutant' if gate else 'lifecycle_mutant')
        exec(compile(text.replace(old, new), 'mutant', 'exec'), mod.__dict__)
        g = globals()
        if gate:
            saved = teo.eo.eg
            teo.eo.eg = mod
        else:
            saved = g['lc']
            g['lc'] = mod
        try:
            return self._suite_failures()
        finally:
            if gate:
                teo.eo.eg = saved
            else:
                g['lc'] = saved

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
                ("            res = en.cancel(cfg, tr, store, en.Runtime(), sid, dec)", "            res = en.cancel(cfg, tr, store, en.Runtime(), sid, dec)\n            res = en.cancel(cfg, tr, store, en.Runtime(), sid, dec)"),
                # review findings: the reservation and the lock
                ("        if not st.lock_owned:\n            st.halted = st.halted or 'LIFECYCLE_LOCK_NOT_OWNED'\n            return False, 'LIFECYCLE_LOCK_NOT_OWNED'", "        if False:\n            return False, 'LIFECYCLE_LOCK_NOT_OWNED'"),
                ("        if st.halted:\n            return False, 'LIFECYCLE_HALTED: ' + st.halted", "        if False:\n            return False, 'LIFECYCLE_HALTED: ' + st.halted"),
                ("        if not record and self.new and signal_id in st.ids:", "        if False:"),
                ("    if not st.lock_owned:\n        return notes", "    if False:\n        return notes"),
                ("    if st.lock_owned and st.lock_key:\n        lockstore.unlock(st.lock_key)", "    if st.lock_key:\n        lockstore.unlock(st.lock_key)"),
                ("    if not lockstore.lock(key):", "    if False:"),
                ("    if not st.lock_owned:\n        st.halted = st.halted or 'LIFECYCLE_LOCK_NOT_OWNED'\n        return False", "    if False:\n        return False"),
                # Codex finding on 10a2ee1: the existing index is validated before every update and every lifecycle action
                ("    ok, why = disk_check(store, st)\n    if not ok:\n        st.halted = st.halted or why\n        notes.append(why)\n        return False\n    if not save(store, st):", "    if not save(store, st):"),
                ("    ok, why = disk_check(store, st)\n    if not ok:\n        st.halted = st.halted or why\n        notes.append(why)\n        return notes\n", "    pass\n"),
                ("    acct = tr.read_account()\n    if not acct.read_ok or acct.login <= 0:\n        return State(0, 'ACCOUNT_UNREADABLE'), ['ACCOUNT_UNREADABLE']\n    st = State(acct.login)\n    if not acquire(lockstore, acct.login, st):",
                 "    acct = tr.read_account()\n    if not acct.read_ok or acct.login <= 0:\n        return State(0, 'ACCOUNT_UNREADABLE'), ['ACCOUNT_UNREADABLE']\n    st = State(acct.login)\n    if False:")]
        for old, new in muts:
            self.assertGreater(self._count_failures(old, new), 0, 'not caught: ' + old)
        gate_muts = [("    ok, why = pre_send.reserve(spb.plan.signal_id)\n        if not ok:", "    ok, why = True, ''\n        if not ok:"),
                     ("    if pre_send is not None:\n        pre_send.settled(spb.plan.signal_id, res)\n", "    pass\n")]
        for old, new in gate_muts:
            self.assertGreater(self._count_failures(old, new, self.GATE), 0, 'not caught (gate): ' + old)


if __name__ == '__main__':
    unittest.main()
