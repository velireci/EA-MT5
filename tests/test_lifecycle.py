"""T019 lifecycle tests (FAKE transport and FAKE store only): persistent index + halt, startup reconcile, tick (fill / gated cancel), events from facts. Never a send."""
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import entry_reference as en  # noqa: E402
import t011_driver_reference as dr  # noqa: E402
import t011_executor_reference as ex  # noqa: E402
import t011_persist_reference as t11  # noqa: E402
import lifecycle_reference as lc  # noqa: E402
import t007_planning_reference as tp  # noqa: E402
import test_entry_executor as te  # noqa: E402
import test_eo as teo  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIG = te.SIGNAL
SCENARIOS = ['index_codec_and_damage', 'register_and_save_failure', 'startup_clean', 'startup_halts_on_unprovable', 'startup_keeps_open_pending', 'tick_fill_unmanaged',
             'cancel_gated_by_enabled_events', 'cancel_uncertain_halts', 'due_events_from_facts', 'damaged_state_never_overwritten',
             'index_saved_before_send', 'no_send_when_index_unusable', 'crash_windows_restart_halts', 'two_instances_no_lost_update', 'refused_instance_and_wrong_release',
             'release_only_by_owner_on_failure_paths', 'damage_during_run_never_overwritten', 'fill_report_and_registration_inputs',
             'auto_registration_confirms_once', 'auto_registration_idempotent_after_crash', 'auto_registration_refusals_keep_the_t011_contracts', 'auto_registration_transient_and_locks',
             'auto_registration_acknowledge_and_instances', 'auto_registration_existing_record_needs_the_full_base', 'auto_registration_idempotent_after_management_started',
        'auto_registration_synthetic_fill_is_rejected', 'managed_fill_registration_management_to_done', 'managed_restart_in_every_critical_window',
        'managed_closed_position_released_without_management', 'managed_manual_foreign_and_synthetic_untouched', 'managed_failures_block_and_lock_at_the_level', 'managed_slots_released_and_capacity',
             'direction_cancel_only_opposite_records', 'opposite_signal_cancel_per_record', 'direction_unknown_data_proves_nothing', 'direction_cancel_leaves_positions_and_foreign',
             'direction_cancel_uncertain_halts_no_retry', 'notify_pending_placed_then_filled_once', 'notify_unproven_order_send_is_silent', 'notify_removed_pending_once',
             'notify_partial_modified_closed_are_distinct', 'notify_failure_changes_no_decision', 'notify_manual_foreign_unreadable_silent', 'notify_restart_repeats_nothing',
             'notify_terminal_event_survives_object_removal', 'notify_remainder_close_after_done_observed', 'notify_sixteen_plus_positions_one_process']
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
            self.assertEqual(st.ids, [SIG], 'reported first, forgotten only on the next tick')
            self.assertTrue(any(n.startswith('FILLED_UNMANAGED') for n in notes))
            self.assertEqual(lc.tick(w.cfg, w.tr, w.store, st, 0, 0), [])
            self.assertEqual(st.ids, [])
            self.assertEqual(index_ids(w.store, w.tr.account.login), [])
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


class FillHandoff(unittest.TestCase):
    """fill -> T011 management, WITHOUT any change of the T011 contracts: the fill is reported with the exact inputs of the EXPLICIT registration script (the owner still asserts the initial SL);
    the report is at-least-once (the index entry is forgotten only on the tick after the report, so a restart in between reports it again)"""

    def filled(self, direction, tp=None, magic=None):
        w = te.World(direction)
        if tp is not None:
            w.plan = te.plan(direction, tp=tp)
            w.permit = te.permit_for(w.plan, w.tr)
        st = owner(w.store, w.tr.account.login)
        res, guard, why = guarded_place(w, st)
        self.assertEqual(res.final, en.R_PLACED, why)
        w.tr.orders[0].state = en.OS_FILLED
        w.tr.orders[0].position_id = 4242
        if magic is not None:
            w.cfg.ea_magic = magic
        return w, st

    def test_the_report_carries_the_exact_registration_inputs(self):
        for direction, side, tp in ((1, 'BUY', 2005.0), (-1, 'SELL', 1995.0)):
            w, st = self.filled(direction, tp=tp)
            rec_before = dict(w.store.files)
            notes = lc.tick(w.cfg, w.tr, w.store, st, 0, 0)
            text = ' '.join(notes)
            rec = w.rec()
            for frag in ('FILLED_UNMANAGED ' + SIG, 'InpEnabled=true', 'InpRPolicy=R_GEOM', 'InpEaMagic=777', 'InpPositionId=4242', 'InpSymbol=XAUUSD', 'InpDirection=' + side,
                         'InpInitialSl=%.8f' % rec.s, 'InpTpPrice=%.8f' % tp, 'InpVolumeInitial=%.8f' % rec.volume):
                self.assertIn(frag, text, side)
            self.assertNotIn('NOT_REGISTRABLE', text, side)
            self.assertEqual(set(w.store.files) - set(rec_before), set(), 'the report writes nothing of T011 and creates no file')
            self.assertEqual((w.tr.sends, w.tr.cancels), (1, 0))

    def test_planned_geometry_requires_live_registration_check(self):
        for direction in (1, -1):
            w, st = self.filled(direction)                  # the default plan: TP == the 2R level (what the 2R-minimum target rule produces)
            text = ' '.join(lc.tick(w.cfg, w.tr, w.store, st, 0, 0))
            self.assertNotIn('NOT_REGISTRABLE', text)
            self.assertIn('LIVE_CHECK_REQUIRED', text)
            self.assertIn('PLANNED_GEOMETRY', text)
            actual_entry = 1989.0 if direction == 1 else 2011.0
            actual_level = actual_entry + direction * 2 * abs(actual_entry - w.rec().s)
            self.assertGreater(direction * (w.rec().tp - actual_level), 0, 'improved fill makes TP beyond actual 2R')
            self.assertIn('TP_EQUALS_2R', text)
            w3, st3 = self.filled(direction, tp=1999.0 if direction == 1 else 2001.0)
            self.assertIn('TP_BEFORE_2R', ' '.join(lc.tick(w3.cfg, w3.tr, w3.store, st3, 0, 0)))

    def test_a_record_of_another_magic_is_never_reported_for_registration(self):
        w, st = self.filled(1, tp=2005.0)
        w.cfg.ea_magic = 778                                 # the record was written with 777: the executor's own identity proof blocks it first
        text = ' '.join(lc.tick(w.cfg, w.tr, w.store, st, 0, 0))
        self.assertIn('IDENTITY_MISMATCH', text)
        self.assertNotIn('T011_REGISTRATION_INPUTS', text)
        self.assertIn('UNRESOLVED_ENTRY_RECORD', st.halted)

    def test_the_report_is_at_least_once_across_a_restart(self):
        for direction in (1, -1):
            w, st = self.filled(direction, tp=2005.0 if direction == 1 else 1995.0)
            self.assertTrue(any(n.startswith('FILLED_UNMANAGED') for n in lc.tick(w.cfg, w.tr, w.store, st, 0, 0)))
            lc.release(w.store, st)                           # the process dies after the report, before the next tick
            tr, store = new_process(w, keep_book=True)
            st2, notes = start(w.cfg, tr, store)
            self.assertTrue(any(n.startswith('FILLED_UNMANAGED') for n in notes), 'reported again after the restart')
            self.assertEqual(st2.ids, [SIG])
            lc.tick(w.cfg, tr, store, st2, 0, 0)
            self.assertEqual(st2.ids, [])
            self.assertEqual(index_ids(store, w.tr.account.login), [])


class Locks:
    def __init__(self):
        self.held = set()

    def acquire(self, k):
        if k in self.held:
            return False
        self.held.add(k)
        return True

    def release(self, k):
        self.held.discard(k)


EXIT_IDENT = t11.Identity('MetaQuotes-Demo', 5001234, 'XAUUSD', 7)


class CountingRegistrar:
    """wraps the CURRENT lc.Registrar (so the mutants of the registrar take effect) and counts the calls"""

    def __init__(self, *a, **k):
        k.setdefault('provenance', lc.PROV_BROKER)
        self.inner = lc.Registrar(*a, **k)
        self.calls = 0

    def on_filled(self, login, sid):
        self.calls += 1
        return self.inner.on_filled(login, sid)


class RegWorld:
    """an entry that is FILLED (position id 7) + the T011 world of the same position; the registrar is the lifecycle's fill sink"""

    def __init__(self, tc, direction, tp=None, phrase=ex.AUTH_PHRASE, pos_changes=None, pos=7):
        self.dirn = direction
        e, sl, tp0 = (2000.0, 1995.0, 2015.0) if direction == 1 else (2000.0, 2005.0, 1985.0)
        self.sl, self.tp = sl, (tp if tp is not None else tp0)
        self.w = te.World(direction)
        self.w.plan = te.plan(direction, e_out=e, s_out=sl, tp=self.tp, volume_out=0.5)
        self.w.permit = te.permit_for(self.w.plan, self.w.tr)
        self.w.tr.quote = en.Quote(True, 2003.0 if direction == 1 else 1997.0, 2003.3 if direction == 1 else 1997.3, self.w.tr.now)
        self.login = self.w.tr.account.login
        self.st = owner(self.w.store, self.login)
        res, guard, why = guarded_place(self.w, self.st)
        assert res.final == en.R_PLACED, (res, why)
        self.w.tr.orders[0].state = en.OS_FILLED
        self.pos = pos
        self.w.tr.orders[0].position_id = pos
        self.dir = tempfile.TemporaryDirectory()
        tc.addCleanup(self.dir.cleanup)
        self.xstore = t11.FileStore(self.dir.name)
        self.xtr = ex.FakeTransport()
        self.xtr.real = True                      # the registration transport reports IsReal() = true, so the authorisation phrase and the demo-account gates stay in force
        self.xtr.position = ex.PositionW(found=True, ticket=9, identifier=pos, symbol='XAUUSD', magic=777, type=0 if direction == 1 else 1, volume=0.5, price_open=2000.0, sl=sl)
        for k, v in (pos_changes or {}).items():
            setattr(self.xtr.position, k, v)
        self.locks = Locks()
        self.phrase = phrase
        self.reg = self.make_registrar()
        self.name = lc.exit_file_name(self.login, pos)

    def make_registrar(self, **kw):
        return CountingRegistrar(self.w.store, self.xtr, self.xstore, self.locks, magic=777, phrase=self.phrase, rpol=ex.RPOL_R_GEOM, **kw)

    def tick(self, st=None, reg=None):
        return lc.tick(self.w.cfg, self.w.tr, self.w.store, st or self.st, 0, 0, sink=reg or self.reg, obs=getattr(self, 'obs', None))

    def stored(self):
        return self.xstore.load(self.name, EXIT_IDENT)

    def t11_files(self):
        return sorted(os.listdir(self.dir.name))


class AutoRegistration(unittest.TestCase):
    """fill -> T011 registration by the orchestrator (the existing ex.register through the T011 driver's lock): ownership, the initial SL (accepted only while the live SL equals it), the stored plan,
    persistence (never overwritten) and idempotency are exactly those of the explicit script; the entry transport stays FAKE; the T011 TP / 2R, break-even and cost rules are NOT changed"""

    def test_auto_registration_confirms_once(self):
        for d in (1, -1):
            rw = RegWorld(self, d)
            text = ' '.join(rw.tick())
            self.assertIn('REGISTERED_WITH_T011', text)
            for frag in ('InpRPolicy=R_GEOM', 'InpEaMagic=777', 'InpPositionId=7', 'InpSymbol=XAUUSD', 'InpDirection=' + ('BUY' if d == 1 else 'SELL'), 'InpInitialSl=%.8f' % rw.sl,
                         'InpTpPrice=%.8f' % rw.tp, 'InpVolumeInitial=%.8f' % 0.5):
                self.assertIn(frag, text)
            self.assertEqual((rw.st.ids, rw.st.halted, index_ids(rw.w.store, rw.login)), ([], '', []))
            o = rw.stored()
            self.assertEqual((o.verdict, o.state.direction, o.state.level, o.plan_s_src, o.plan_tp, o.state.volume_initial, o.plan_rpol),
                             (t11.USABLE_IDLE, d, 2010.0 if d == 1 else 1990.0, rw.sl, rw.tp, 0.5, ex.RPOL_R_GEOM))
            self.assertEqual((rw.xtr.sends, rw.locks.held, rw.reg.calls), ([], set(), 1))
            before = rw.xstore.read(rw.name)
            self.assertEqual(rw.tick(), [])
            self.assertEqual((rw.xstore.read(rw.name), rw.reg.calls), (before, 1), 'a registered fill is not registered again')
            self.assertEqual(rw.w.tr.sends, 1, 'the entry transport sent exactly the one order')

    def test_auto_registration_idempotent_after_crash(self):
        for d in (1, -1):
            rw = RegWorld(self, d)
            rw.w.reconcile()                                       # the sweep moves the entry record to FILLED before the sink is asked
            self.assertEqual(rw.reg.on_filled(rw.login, SIG)[0], lc.SINK_CONFIRMED)         # T011 saved; the process dies before the index is updated
            saved = rw.xstore.read(rw.name)
            self.assertEqual(index_ids(rw.w.store, rw.login), [SIG])
            tr, store = new_process(rw.w, keep_book=True)
            reg2 = CountingRegistrar(store, rw.xtr, rw.xstore, Locks(), magic=777, phrase=rw.phrase, rpol=ex.RPOL_R_GEOM)
            st2, notes = lc.startup(rw.w.cfg, tr, store, store, False, sink=reg2)
            self.assertIn('ALREADY_REGISTERED', ' '.join(notes))
            self.assertEqual((st2.ids, st2.halted, rw.xstore.read(rw.name), reg2.calls), ([], '', saved, 1), 'confirmed by comparison, nothing rewritten')
            self.assertEqual(rw.xtr.sends, [])

    def test_a_conflicting_t11_record_is_never_overwritten(self):
        for d in (1, -1):
            rw = RegWorld(self, d)
            other = rw.sl - 1.0 if d == 1 else rw.sl + 1.0
            rw.xtr.position.sl = other
            cfg = ex.Config(enabled=True, r_policy=ex.RPOL_R_GEOM, sl_initial_set=True, sl_initial=other, ea_magic=777, tp_set=True, tp_price=rw.tp, real_authorised=True, authorisation=ex.AUTH_PHRASE)
            q = ex.Quote(d, 0.0, 0.0, 0.0, 0.5)
            self.assertEqual(ex.register(cfg, rw.xtr, ex.Runtime(), rw.xstore, rw.name, EXIT_IDENT, q).final, ex.REGISTERED)
            rw.xtr.position.sl = rw.sl
            before = rw.xstore.read(rw.name)
            text = ' '.join(rw.tick())
            self.assertIn('T011_RECORD_CONFLICT', text)
            self.assertEqual(rw.xstore.read(rw.name), before, 'a different record is never replaced')
            self.assertIn('MANAGEMENT_REGISTRATION_REFUSED', rw.st.halted)
            self.assertEqual(rw.st.ids, [SIG])

    def test_auto_registration_refusals_keep_the_t011_contracts(self):
        def run(label, frag, **kw):
            for d in (1, -1):
                tp = kw.get('tp')
                tp = ({'eq': 2010.0 if d == 1 else 1990.0, 'before': 2005.0 if d == 1 else 1995.0}[tp] if tp else None)
                rw = RegWorld(self, d, tp=tp, phrase=kw.get('phrase', ex.AUTH_PHRASE), pos_changes=kw.get('pos'))
                if 'acct' in kw:
                    for k, v in kw['acct'].items():
                        setattr(rw.xtr.account, k, v)
                if 'flip' in kw:
                    rw.xtr.position.type = 1 - rw.xtr.position.type
                text = ' '.join(rw.tick())
                tag = '%s dir %d' % (label, d)
                self.assertIn(frag, text, tag)
                self.assertEqual(rw.t11_files(), [], tag + ': nothing is registered')
                self.assertEqual(rw.xtr.sends, [], tag)
                self.assertIn('MANAGEMENT_REGISTRATION_REFUSED', rw.st.halted, tag)
                self.assertEqual(rw.st.ids, [SIG], tag + ': the fill stays indexed (unmanaged) until the owner acknowledges')
                self.assertEqual(rw.locks.held, set(), tag)
        run('live SL moved', 'INITIAL_SL_NOT_PROVEN', pos={'sl': 1990.0})
        run('TP equals 2R', 'TP_EQUALS_2R', tp='eq')
        run('TP before 2R', 'TP_BEFORE_2R', tp='before')
        run('foreign magic', 'OWNERSHIP_NOT_PROVEN', pos={'magic': 0})
        run('other direction', 'OWNERSHIP_NOT_PROVEN', flip=True)
        run('netting account', 'UNSUPPORTED_ACCOUNT_MODE', acct={'margin_mode': 0})
        run('not a demo account', 'REAL_REQUIRES_DEMO_ACCOUNT', acct={'demo': False})
        run('no authorisation phrase', 'REAL_NOT_AUTHORISED', phrase='')
        run('volume differs', 'POSITION_VOLUME_DIFFERS', pos={'volume': 0.4})
        for d in (1, -1):                                       # the sink alone never trusts a record that is not a proven fill
            rw = RegWorld(self, d)
            self.assertEqual(rw.reg.on_filled(rw.login, SIG), (lc.SINK_REFUSED, 'FILL_NOT_PROVEN'))
            self.assertEqual((rw.t11_files(), rw.xtr.sends), ([], []))

    def test_auto_registration_transient_and_locks(self):
        for d in (1, -1):
            rw = RegWorld(self, d, pos_changes={'found': False})
            for i in range(lc.Registrar.MAX_TRIES - 1):
                notes = rw.tick()
                self.assertTrue(any('FILL_REGISTRATION_PENDING' in n for n in notes), notes)
                self.assertEqual((rw.st.halted, rw.st.ids, rw.t11_files()), ('', [SIG], []))
            rw.xtr.position.found = True                                       # the position becomes visible before the retries are exhausted
            self.assertIn('REGISTERED_WITH_T011', ' '.join(rw.tick()))
            rw2 = RegWorld(self, d, pos_changes={'found': False})
            texts = [' '.join(rw2.tick()) for _ in range(lc.Registrar.MAX_TRIES)]
            self.assertIn('RETRIES_EXHAUSTED', texts[-1])
            self.assertIn('MANAGEMENT_REGISTRATION_REFUSED', rw2.st.halted)
            rw3 = RegWorld(self, d)
            rw3.locks.held.add(dr.lock_key(EXIT_IDENT))                         # the T011 per-position lock is held by someone else
            self.assertTrue(any('FILL_REGISTRATION_PENDING' in n for n in rw3.tick()))
            self.assertEqual((rw3.t11_files(), rw3.st.halted), ([], ''))
            rw3.locks.held.discard(dr.lock_key(EXIT_IDENT))
            self.assertIn('REGISTERED_WITH_T011', ' '.join(rw3.tick()))
            self.assertEqual(rw3.locks.held, set(), 'the T011 lock is released by the registrar')

    def test_auto_registration_acknowledge_and_instances(self):
        for d in (1, -1):
            rw = RegWorld(self, d, tp=2010.0 if d == 1 else 1990.0)                   # TP == 2R: T011 refuses
            rw.tick()
            self.assertIn('MANAGEMENT_REGISTRATION_REFUSED', rw.st.halted)
            rw.tick()
            self.assertEqual(rw.reg.calls, 1, 'a refused fill is not offered to the sink again in the same process')
            lc.release(rw.w.store, rw.st)
            tr, store = new_process(rw.w, keep_book=True)
            reg2 = CountingRegistrar(store, rw.xtr, rw.xstore, Locks(), magic=777, phrase=rw.phrase, rpol=ex.RPOL_R_GEOM)
            st2, notes = lc.startup(rw.w.cfg, tr, store, store, False, sink=reg2)
            self.assertIn('MANAGEMENT_REGISTRATION_REFUSED', st2.halted, 'the halt survives the restart')
            lc.release(store, st2)
            reg3 = CountingRegistrar(store, rw.xtr, rw.xstore, Locks(), magic=777, phrase=rw.phrase, rpol=ex.RPOL_R_GEOM)
            st3, notes3 = lc.startup(rw.w.cfg, tr, store, store, True, sink=reg3)
            self.assertEqual((st3.halted, st3.ids, rw.t11_files()), ('', [], []), 'the owner accepted the unmanaged position; the signal stays consumed, nothing was registered')
            self.assertTrue(rw.w.has_file())
            # an instance without the index lock never reaches the registrar
            rw2 = RegWorld(self, d)
            forged = lc.State(rw2.login, '', [SIG])
            self.assertEqual(rw2.tick(forged), [])
            self.assertEqual((rw2.reg.calls, rw2.t11_files()), (0, []))

    def _again(self, rw, **kw):
        """a fresh registrar over the SAME T011 store, asked directly about the already registered fill"""
        base = dict(magic=777, phrase=ex.AUTH_PHRASE, rpol=ex.RPOL_R_GEOM, provenance=lc.PROV_BROKER)
        base.update(kw)
        return lc.Registrar(rw.w.store, rw.xtr, rw.xstore, Locks(), **base).on_filled(rw.login, SIG)

    def test_auto_registration_existing_record_needs_the_full_base(self):
        for d in (1, -1):
            rw = RegWorld(self, d)
            self.assertIn('REGISTERED_WITH_T011', ' '.join(rw.tick()))
            saved = rw.xstore.read(rw.name)
            self.assertEqual(self._again(rw)[0], lc.SINK_CONFIRMED, 'the unchanged world is confirmed by comparison')

            def refused(label, frag, change, **kw):
                tr = rw.xtr
                backup = (tr.position.price_open, tr.position.magic, tr.position.type, tr.account.demo, tr.account.margin_mode, tr.symbol.vol_step)
                change(tr)
                status, detail = self._again(rw, **kw)
                (tr.position.price_open, tr.position.magic, tr.position.type, tr.account.demo, tr.account.margin_mode, tr.symbol.vol_step) = backup
                tag = '%s dir %d' % (label, d)
                self.assertEqual(status, lc.SINK_REFUSED, tag + ': ' + detail)
                self.assertIn(frag, detail, tag)
                self.assertEqual(rw.xstore.read(rw.name), saved, tag + ': the record is never rewritten')
            refused('stored E differs from the live open price', 'T011_RECORD_CONFLICT', lambda t: setattr(t.position, 'price_open', 2001.0 if d == 1 else 1999.0))
            refused('magic of the configuration differs', 'OWNERSHIP_NOT_PROVEN', lambda t: None, magic=999)
            refused('configuration and live position of a magic that is not the entry record magic', 'OWNERSHIP_NOT_PROVEN', lambda t: setattr(t.position, 'magic', 999), magic=999)
            refused('live position of another magic', 'OWNERSHIP_NOT_PROVEN', lambda t: setattr(t.position, 'magic', 0))
            refused('live position of another direction', 'OWNERSHIP_NOT_PROVEN', lambda t: setattr(t.position, 'type', 1 - t.position.type))
            refused('wrong authorisation phrase', 'REAL_NOT_AUTHORISED', lambda t: None, phrase='NOPE')
            refused('not a demo account', 'REAL_REQUIRES_DEMO_ACCOUNT', lambda t: setattr(t.account, 'demo', False))
            refused('netting account', 'UNSUPPORTED_ACCOUNT_MODE', lambda t: setattr(t.account, 'margin_mode', 0))
            refused('symbol volume step differs from the stored plan', 'T011_RECORD_CONFLICT', lambda t: setattr(t.symbol, 'vol_step', 0.1))
            self.assertEqual(rw.xtr.sends, [])

    def test_auto_registration_idempotent_after_management_started(self):
        for d in (1, -1):
            rw = RegWorld(self, d)
            self.assertIn('REGISTERED_WITH_T011', ' '.join(rw.tick()))
            saved = rw.xstore.read(rw.name)
            rw.xtr.position.sl = 2000.0                                   # management moved the stop to the entry
            rw.xtr.position.volume = 0.1                                  # and closed the 80% part
            status, detail = self._again(rw)
            self.assertEqual(status, lc.SINK_CONFIRMED, detail)
            self.assertIn('ALREADY_REGISTERED', detail)
            self.assertEqual(rw.xstore.read(rw.name), saved)
            rw.xtr.position.found = False                                 # the position is not readable: the open price cannot be proven
            status, detail = self._again(rw)
            self.assertEqual(status, lc.SINK_PENDING, detail)
            self.assertIn('POSITION_NOT_FOUND', detail)

    def test_auto_registration_synthetic_fill_is_rejected(self):
        for d in (1, -1):
            for prov, label in ((lc.PROV_SYNTHETIC, 'synthetic'), (lc.PROV_UNSET, 'unset')):
                rw = RegWorld(self, d)                                  # a REAL position with the same identifier, magic, symbol, direction, volume and SL exists
                reads = []
                orig = rw.xtr.find_position
                rw.xtr.find_position = lambda i, orig=orig: (reads.append(i), orig(i))[1]
                reg = CountingRegistrar(rw.w.store, rw.xtr, rw.xstore, rw.locks, magic=777, phrase=rw.phrase, rpol=ex.RPOL_R_GEOM, provenance=prov)
                text = ' '.join(rw.tick(reg=reg))
                tag = '%s dir %d' % (label, d)
                self.assertIn('PROVENANCE_NOT_BROKER', text, tag)
                self.assertEqual((rw.t11_files(), rw.xtr.sends, reads), ([], [], []), tag + ': no file, no send, the real position is not even read')
                self.assertIn('MANAGEMENT_REGISTRATION_REFUSED', rw.st.halted, tag)
                self.assertEqual(rw.st.ids, [SIG], tag)
            rw = RegWorld(self, d)
            self.assertIn('REGISTERED_WITH_T011', ' '.join(rw.tick()), 'the same world with BROKER provenance registers')


import t011_adapter_reference as ad  # noqa: E402
import t011_flow_reference as fl  # noqa: E402


def raw_full(direction):
    """the broker facts after the 80% closing order 501 (0.4 of 0.5) was filled: 0.1 remains"""
    din, dout = (ad.DEAL_BUY, ad.DEAL_SELL) if direction == 1 else (ad.DEAL_SELL, ad.DEAL_BUY)
    filled = ad.RawOrder(501, ad.WHERE_HISTORY, ad.ORD_FILLED, 0.4, 0.0, 7)
    return ad.Raw(deals=[ad.RawDeal(100, 400, 7, ad.ENTRY_IN, din, 0.5), ad.RawDeal(1001, 501, 7, ad.ENTRY_OUT, dout, 0.4)], orders=[filled], pos_volume=0.1, pos_type=ad.POS_BUY if direction == 1 else ad.POS_SELL)


def raw_not_yet(direction):
    din = ad.DEAL_BUY if direction == 1 else ad.DEAL_SELL
    return ad.Raw(deals=[ad.RawDeal(100, 400, 7, ad.ENTRY_IN, din, 0.5)], orders=[ad.RawOrder(501, ad.WHERE_NONE, 0, 0.0, 0.0, 0)], pos_volume=0.5, pos_type=ad.POS_BUY if direction == 1 else ad.POS_SELL)


class MgmtWorld(RegWorld):
    """RegWorld + the management inside the orchestrator: the registrar hands a confirmed registration to the Manager (the T011 driver under the per-position lock)"""

    def __init__(self, tc, direction, **kw):
        super().__init__(tc, direction, **kw)
        self.xtr.response = ex.SendResult(True, True, 10009, 501, 1001, 0.4, 2000.0)
        self.raw_now = raw_not_yet(direction)
        self.closed = False
        self.attach()

    def cfg_for(self, rec):
        return ex.Config(enabled=True, real_authorised=True, authorisation=ex.AUTH_PHRASE, ea_magic=777, filling=ex.FILL_IOC, deviation=20, filter_policy=ex.POL_IGNORE, filter_state=ex.FS_CLEAR,
                         tp_set=True, tp_price=rec.tp, r_policy=ex.RPOL_R_GEOM, sl_initial_set=True, sl_initial=rec.s)

    def attach(self):
        self.mgr = lc.Manager(self.xtr, self.xstore, self.locks, self.cfg_for, raw=lambda: (self.raw_now, self.raw_now))
        self.reg.inner.manager = self.mgr
        self.reg.inner.absent = lambda pid: self.closed

    def restart(self):
        """a new process: the same disks (entry store, T011 files, broker), a new lifecycle state, a new registrar and manager, no lock held"""
        lc.release(self.w.store, self.st)
        self.w.tr, store = new_process(self.w, keep_book=True)
        self.w.store = store
        self.locks = Locks()
        self.reg = self.make_registrar()
        self.attach()
        self.st, self.notes = lc.startup(self.w.cfg, self.w.tr, store, store, False, sink=self.reg)
        return self.notes

    def level_quote(self):
        return (2010.0, 2010.3) if self.dirn == 1 else (1989.7, 1990.0)


class ManagedFlow(unittest.TestCase):
    """fill -> registration -> management, all in the orchestrator, on the EXISTING T011 driver; the entry transport stays FAKE and no real position is touched without BROKER provenance"""

    def test_fill_registration_management_to_done(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            text = ' '.join(rw.tick())
            tag = 'dir %d' % d
            self.assertIn('REGISTERED_WITH_T011', text, tag)
            self.assertEqual((rw.st.ids, rw.st.halted, rw.mgr.slots[7].st.armed), ([SIG], '', True), tag + ': registered, armed, still indexed (the restart memory)')
            self.assertEqual(rw.tick(), [], tag + ': an unchanged active fill is not reported again')
            bid, ask = rw.level_quote()
            self.assertEqual([r.final for _, r in rw.mgr.on_quote(bid - 5.0 if d == 1 else bid, ask if d == 1 else ask + 5.0)], [ex.NO_REQUEST], tag + ': below the level nothing is sent')
            self.assertEqual(rw.xtr.sends, [], tag)
            res = rw.mgr.on_quote(bid, ask)
            self.assertEqual([r.final for _, r in res], [ex.SENT_MAPPED], tag)
            self.assertEqual(len(rw.xtr.sends), 1, tag)
            for _ in range(3):
                self.assertEqual(rw.mgr.on_quote(bid, ask), [], tag + ': the slot is disarmed after the send')
            self.assertEqual(len(rw.xtr.sends), 1, tag + ': no duplicate closing request')
            rw.tick()
            self.assertEqual(rw.st.ids, [SIG], tag + ': still managed while the request is reconciled')
            rw.raw_now = raw_full(d)
            rw.xtr.position.volume = 0.1
            flows = rw.mgr.on_timer()
            self.assertEqual([f.final for _, f in flows], [fl.DONE], tag)
            self.assertTrue(any('MANAGEMENT_DONE' in n for n in rw.tick()), tag)
            self.assertEqual((rw.st.ids, rw.st.halted, len(rw.xtr.sends), rw.locks.held), ([], '', 1, set()), tag + ': released only after DONE; exactly one send')
            self.assertEqual(index_ids(rw.w.store, rw.login), [], tag)

    def test_restart_in_every_critical_window(self):
        for d in (1, -1):
            tag = 'dir %d' % d
            # (a) after the fill, before any registration
            rw = MgmtWorld(self, d)
            notes = rw.restart()
            self.assertTrue(any('REGISTERED_WITH_T011' in n for n in notes), tag + ' (a)')
            self.assertEqual((rw.st.ids, rw.mgr.slots[7].st.armed, rw.xtr.sends), ([SIG], True, []), tag + ' (a): registered and armed by the startup sweep, zero sends')
            # (b) after the registration, before anything else: the record exists, the index entry is still there
            notes = rw.restart()
            self.assertEqual((rw.st.ids, rw.mgr.slots[7].st.armed, rw.xtr.sends, rw.st.halted), ([SIG], True, [], ''), tag + ' (b): confirmed by comparison, armed again, nothing rewritten')
            saved = rw.xstore.read(rw.name)
            # (c) after the closing request was sent, before the reconcile
            bid, ask = rw.level_quote()
            self.assertEqual([r.final for _, r in rw.mgr.on_quote(bid, ask)], [ex.SENT_MAPPED], tag)
            rw.xtr.position.volume = 0.1
            rw.restart()
            self.assertEqual((rw.st.ids, rw.mgr.slots[7].st.armed, rw.mgr.slots[7].st.reconcile_due, len(rw.xtr.sends), rw.st.halted), ([SIG], False, True, 1, ''), tag + ' (c): recovery first, not armed')
            self.assertEqual(rw.mgr.on_quote(bid, ask), [], tag + ' (c): no second send after the restart')
            self.assertEqual(len(rw.xtr.sends), 1)
            # (d) the request is DONE on the broker, the index entry still exists
            rw.raw_now = raw_full(d)
            self.assertEqual([f.final for _, f in rw.mgr.on_timer()], [fl.DONE], tag)
            rw.restart()                                          # the process dies after DONE, before the index entry was released
            self.assertEqual((rw.st.ids, len(rw.xtr.sends), rw.st.halted), ([], 1, ''), tag + ' (d): released from the persisted DONE, no new send')
            self.assertNotEqual(rw.xstore.read(rw.name), saved)

    def test_slots_are_released_after_done_and_the_capacity_is_enforced(self):
        for d in (1, -1):
            shared = None
            for cycle in range(lc.Manager.MAX_SLOTS + 3):                 # more cycles than slots, one process, one manager
                rw = MgmtWorld(self, d)
                if shared is None:
                    shared = rw.mgr
                shared.tr, shared.store, shared.locks, shared.cfg_for, shared.raw = rw.xtr, rw.xstore, rw.locks, rw.cfg_for, rw.mgr.raw
                rw.mgr = shared
                rw.reg.inner.manager = shared
                tag = 'dir %d cycle %d' % (d, cycle)
                self.assertIn('REGISTERED_WITH_T011', ' '.join(rw.tick()), tag)
                self.assertEqual(len(shared.slots), 1, tag)
                self.assertEqual([r.final for _, r in shared.on_quote(*rw.level_quote())], [ex.SENT_MAPPED], tag + ': a stale slot of an earlier cycle must not swallow the request')
                rw.raw_now = raw_full(d)
                rw.xtr.position.volume = 0.1
                shared.raw = lambda rw=rw: (rw.raw_now, rw.raw_now)
                self.assertEqual([f.final for _, f in shared.on_timer()], [fl.DONE], tag)
                self.assertTrue(any('MANAGEMENT_DONE' in n for n in rw.tick()), tag)
                self.assertEqual((rw.st.ids, rw.st.halted, shared.slots, len(rw.xtr.sends)), ([], '', {}, 1), tag + ': the slot is released with the index entry')
            # the capacity itself: 16 slots in use refuse the next position, 15 accept it
            rw = MgmtWorld(self, d)
            for i in range(lc.Manager.MAX_SLOTS):
                rw.mgr.slots[1000 + i] = lc.Slot(None, '', None)
            text = ' '.join(rw.tick())
            self.assertIn('MANAGEMENT_SLOTS_FULL', text)
            self.assertIn('MANAGEMENT_REGISTRATION_REFUSED', rw.st.halted)
            self.assertEqual(rw.xtr.sends, [])
            rw2 = MgmtWorld(self, d)
            for i in range(lc.Manager.MAX_SLOTS - 1):
                rw2.mgr.slots[1000 + i] = lc.Slot(None, '', None)
            self.assertIn('REGISTERED_WITH_T011', ' '.join(rw2.tick()))

    def test_restart_between_done_and_the_saved_index_recovers_without_a_send(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            rw.tick()
            self.assertEqual([r.final for _, r in rw.mgr.on_quote(*rw.level_quote())], [ex.SENT_MAPPED])
            rw.raw_now = raw_full(d)
            rw.xtr.position.volume = 0.1
            self.assertEqual([f.final for _, f in rw.mgr.on_timer()], [fl.DONE])
            self.assertEqual(rw.reg.on_filled(rw.login, SIG)[0], lc.SINK_CONFIRMED)      # DONE is confirmed and the slot released ...
            self.assertEqual(rw.mgr.slots, {})
            self.assertEqual(rw.st.ids, [SIG], 'the process dies here: the index was not saved')
            rw.restart()                                                                   # ... the restart finds the id, the T011 record says DONE
            self.assertEqual((rw.st.ids, rw.st.halted, len(rw.xtr.sends), rw.mgr.slots), ([], '', 1, {}))
            self.assertEqual(index_ids(rw.w.store, rw.login), [])

    def test_a_closed_position_before_the_level_is_released_without_management(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            rw.tick()
            rw.xtr.position.found = False
            rw.closed = False
            self.assertTrue(any('FILL_REGISTRATION_PENDING' in n for n in rw.tick()), 'unreadable is not closed')
            rw.closed = True                                      # the list is readable and stable and holds no such position: it was closed (SL, TP or by hand)
            rw.st.ids = [SIG]
            self.assertTrue(any('POSITION_CLOSED' in n for n in rw.tick()))
            self.assertEqual((rw.st.ids, rw.st.halted, rw.xtr.sends), ([], '', []))

    def test_manual_and_foreign_positions_are_never_managed(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            rw.xtr.position = ex.PositionW(found=True, ticket=99, identifier=99, symbol='XAUUSD', magic=0, type=0 if d == 1 else 1, volume=0.5, price_open=2000.0, sl=rw.sl)   # a manual position
            self.assertEqual(rw.mgr.on_quote(*rw.level_quote()), [])
            self.assertEqual((rw.mgr.slots, rw.xtr.sends, rw.t11_files()), ({}, [], []), 'no T011 record, no slot, nothing is sent')
            text = ' '.join(rw.tick())
            self.assertIn('POSITION_NOT_FOUND', text)
            self.assertEqual((rw.mgr.slots, rw.xtr.sends, rw.t11_files()), ({}, [], []))
            rw.xtr.position = ex.PositionW(found=True, ticket=9, identifier=7, symbol='XAUUSD', magic=0, type=0 if d == 1 else 1, volume=0.5, price_open=2000.0, sl=rw.sl)   # the same id but not the robot's
            self.assertIn('OWNERSHIP_NOT_PROVEN', ' '.join(rw.tick()))
            self.assertEqual((rw.mgr.slots, rw.xtr.sends, rw.t11_files()), ({}, [], []))

    def test_a_synthetic_fill_is_not_managed_and_touches_no_real_position(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            reads = []
            orig = rw.xtr.find_position
            rw.xtr.find_position = lambda i, orig=orig: (reads.append(i), orig(i))[1]
            reg = CountingRegistrar(rw.w.store, rw.xtr, rw.xstore, rw.locks, magic=777, phrase=rw.phrase, rpol=ex.RPOL_R_GEOM, provenance=lc.PROV_SYNTHETIC)
            reg.inner.manager = rw.mgr
            self.assertIn('PROVENANCE_NOT_BROKER', ' '.join(rw.tick(reg=reg)))
            self.assertEqual((reads, rw.mgr.slots, rw.xtr.sends, rw.t11_files()), ([], {}, [], []))
            self.assertEqual(rw.mgr.on_quote(*rw.level_quote()), [])
            self.assertEqual(rw.xtr.sends, [])

    def test_failures_block_instead_of_continuing(self):
        for d in (1, -1):
            tag = 'dir %d' % d
            rw = MgmtWorld(self, d)                                # registered, then the position volume is changed by hand before the management is armed again (restart)
            rw.tick()
            rw.xtr.position.volume = 0.3
            rw.restart()
            self.assertIn('VOLUME_MISMATCH', rw.st.halted + ' ' + ' '.join(rw.notes), tag)
            self.assertIn('MANAGEMENT_REGISTRATION_REFUSED', rw.st.halted, tag)
            self.assertEqual((rw.mgr.slots[7].st.armed, rw.xtr.sends), (False, []), tag)
            rw2 = MgmtWorld(self, d)                               # a lock that never becomes available
            rw2.locks.held.add(dr.lock_key(EXIT_IDENT))
            texts = [' '.join(rw2.tick()) for _ in range(lc.Registrar.MAX_TRIES)]
            self.assertIn('RETRIES_EXHAUSTED', texts[-1], tag)
            self.assertIn('MANAGEMENT_REGISTRATION_REFUSED', rw2.st.halted, tag)
            self.assertEqual(rw2.xtr.sends, [], tag)
            rw3 = MgmtWorld(self, d)                               # a request whose reconcile is blocked halts the layer
            rw3.tick()
            rw3.mgr.on_quote(*rw3.level_quote())
            rw3.raw_now = ad.Raw(deals=[], orders=[], pos_volume=0.5, n_pos=1, pos_type=ad.POS_BUY if d == 1 else ad.POS_SELL)
            for _ in range(2):
                rw3.mgr.on_timer()
            blocked = rw3.mgr.slots[7].blocked or rw3.mgr.slots[7].st.reconcile_due
            self.assertTrue(blocked, tag)
            self.assertEqual(len(rw3.xtr.sends), 1, tag)

    def test_a_lock_held_elsewhere_at_the_level_sends_nothing_and_keeps_the_slot_armed(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            rw.tick()
            rw.locks.held.add(dr.lock_key(EXIT_IDENT))
            self.assertEqual([r.final for _, r in rw.mgr.on_quote(*rw.level_quote())], [ex.BLOCKED])
            self.assertEqual((rw.xtr.sends, rw.mgr.slots[7].st.armed), ([], True))
            rw.locks.held.discard(dr.lock_key(EXIT_IDENT))
            self.assertEqual([r.final for _, r in rw.mgr.on_quote(*rw.level_quote())], [ex.SENT_MAPPED])
            self.assertEqual(len(rw.xtr.sends), 1)


def multi(specs):
    """several PENDING orders of one robot in one store: specs = [(signal_id, direction), ...]; returns (world, state)"""
    w = te.World(1)
    st = owner(w.store, w.tr.account.login)
    guard = lc.Guard(w.store, st)
    for k, (sid, d) in enumerate(specs):
        ok, why = guard.reserve(sid)
        assert ok, why
        base = te.plan(d, signal=sid)
        shift = -0.5 * k * d                                          # distinct prices: the executor refuses an identical pending order
        pl = te.plan(d, signal=sid, e_out=base.e_out + shift, s_out=base.s_out + shift)
        res = w.place(pl=pl, permit=te.permit_for(pl, w.tr), rt=en.Runtime())
        assert res.final == en.R_PLACED, res
        guard.settled(sid, res)
    return w, st


def facts_for(w, ctx=0, sig=0, sid='', valid=True, age=0):
    return lc.Facts(valid, ctx, sig, sid, w.tr.now - age)


def state_of(w, sid):
    ok, rec = en.decode(w.store.read(en.file_name(w.tr.account.login, sid))[1])
    return rec.state


DIR_BOTH = tp.EV_DIRECTION_CHANGE | tp.EV_OPPOSITE_SIGNAL


class DirectionCancel(unittest.TestCase):
    """client S:29-30: a pending order is cancelled when the direction changes or an opposite signal appears. The event is judged PER RECORD against ITS direction (never one global flag), through the
    existing TP_CancelDecision + EN_Cancel; unknown or incomplete data proves nothing; positions, manual orders and other magics are never touched; an uncertain cancel halts and is never retried."""

    SPECS = [('SIG-A', 1), ('SIG-B', -1), ('SIG-C', 1)]

    def test_a_direction_change_cancels_only_the_records_of_the_other_direction(self):
        for ctx in (-1, 1):
            w, st = multi(self.SPECS)
            notes = lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, ctx=ctx), dir_enabled=tp.EV_DIRECTION_CHANGE)
            opposite = [sid for sid, d in self.SPECS if d == -ctx]
            kept = [sid for sid, d in self.SPECS if d == ctx]
            self.assertEqual((w.tr.cancels, sorted(st.ids), st.halted), (len(opposite), sorted(kept), ''), 'ctx %d' % ctx)
            for sid in opposite:
                self.assertEqual(state_of(w, sid), en.ST_CANCELLED)
                self.assertTrue(any(n.startswith('CANCELLED %s: CANCEL_REQUEST: DIRECTION_CHANGE' % sid) for n in notes), notes)
            for sid in kept:
                self.assertEqual(state_of(w, sid), en.ST_PLACED)
            self.assertEqual(w.tr.sends, 3)

    def test_an_opposite_signal_cancels_only_the_other_direction_and_never_the_signal_itself(self):
        for sd in (-1, 1):
            w, st = multi(self.SPECS)
            lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, sig=sd, sid='SIG-NEW'), dir_enabled=tp.EV_OPPOSITE_SIGNAL)
            expected = sorted(sid for sid, d in self.SPECS if d == sd)
            self.assertEqual(sorted(st.ids), expected, 'signal %d' % sd)
            w2, st2 = multi(self.SPECS)                                    # the signal of an existing record is that record, not a reason to cancel it
            lc.tick(w2.cfg, w2.tr, w2.store, st2, 0, 0, facts=facts_for(w2, sig=-1, sid='SIG-B'), dir_enabled=tp.EV_OPPOSITE_SIGNAL)
            self.assertEqual(sorted(st2.ids), ['SIG-B'], 'SIG-B is its own signal; the BUY records are opposite to it')
            w3, st3 = multi([('SIG-A', 1)])                                   # inconsistent data (the signal id of the record with the other direction) proves nothing
            lc.tick(w3.cfg, w3.tr, w3.store, st3, 0, 0, facts=facts_for(w3, sig=-1, sid='SIG-A'), dir_enabled=tp.EV_OPPOSITE_SIGNAL)
            self.assertEqual((w3.tr.cancels, st3.ids), (0, ['SIG-A']))

    def test_unknown_or_incomplete_data_proves_no_change(self):
        cases = [('no facts', None), ('invalid', facts_for(None or te.World(1), valid=False, ctx=-1)), ('unknown context', None), ('stale', 'stale'), ('future', 'future')]
        for label, f in cases:
            w, st = multi(self.SPECS)
            if label == 'no facts' or label == 'unknown context':
                f = None if label == 'no facts' else facts_for(w, ctx=0, sig=0)
            elif label == 'invalid':
                f = facts_for(w, ctx=-1, valid=False)
            elif label == 'stale':
                f = facts_for(w, ctx=-1, age=w.cfg.quote_max_age + 1)
            elif label == 'future':
                f = facts_for(w, ctx=-1, age=-5)
            lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=f, dir_enabled=DIR_BOTH)
            self.assertEqual((w.tr.cancels, sorted(st.ids)), (0, ['SIG-A', 'SIG-B', 'SIG-C']), label)
        w, st = multi(self.SPECS)
        lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, ctx=-1), dir_enabled=0)
        self.assertEqual(w.tr.cancels, 0, 'the direction events are enabled by the owner; off = never')
        w, st = multi(self.SPECS)
        lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, ctx=-1), dir_enabled=tp.EV_OPPOSITE_SIGNAL)
        self.assertEqual(w.tr.cancels, 0, 'a context fact is not an opposite SIGNAL')
        w, st = multi(self.SPECS)
        lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, sig=-1, sid='SIG-NEW'), dir_enabled=tp.EV_DIRECTION_CHANGE)
        self.assertEqual(w.tr.cancels, 0, 'a signal fact is not a context change')

    def test_an_unreadable_record_or_another_magic_is_not_judged(self):
        w, st = multi(self.SPECS)
        w.cfg.ea_magic = 778                                              # the records were written with 777
        lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, ctx=-1), dir_enabled=DIR_BOTH)
        self.assertEqual(w.tr.cancels, 0)
        w, st = multi(self.SPECS)
        name = en.file_name(w.tr.account.login, 'SIG-A')
        w.store.files[name] = 'garbage'
        lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, ctx=-1), dir_enabled=DIR_BOTH)
        self.assertEqual((w.tr.cancels, sorted(st.ids)), (1, ['SIG-A', 'SIG-B']), 'only the readable BUY record SIG-C is judged and cancelled; the unreadable SIG-A is left alone')
        self.assertIn('UNRESOLVED', ' '.join(lc.tick(w.cfg, w.tr, w.store, st, 0, 0)), 'the unreadable record halts through the sweep, it is not cancelled')

    def test_open_positions_manual_orders_and_other_magics_are_never_touched(self):
        for ctx in (-1, 1):
            w, st = multi([('SIG-A', 1), ('SIG-B', -1)])
            filled = [o for o in w.tr.orders if o.ticket][0]
            w.tr.orders[0].state = en.OS_FILLED                              # SIG-A became a position
            w.tr.orders[0].position_id = 4242
            manual = en.Order(found=True, ticket=9001, symbol='XAUUSD', type=en.TYPE_SELL_LIMIT, state=en.OS_ACTIVE, price=2100.0, sl=2105.0, tp=2090.0, volume=0.1, magic=0, comment='manual')
            other = en.Order(found=True, ticket=9002, symbol='XAUUSD', type=en.TYPE_BUY_LIMIT, state=en.OS_ACTIVE, price=1900.0, sl=1895.0, tp=1910.0, volume=0.1, magic=999, comment='other EA')
            w.tr.orders += [manual, other]
            lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, ctx=ctx), dir_enabled=DIR_BOTH)
            lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, ctx=ctx), dir_enabled=DIR_BOTH)
            self.assertEqual((manual.state, other.state), (en.OS_ACTIVE, en.OS_ACTIVE), 'ctx %d' % ctx)
            self.assertNotIn(9001, [c for c in getattr(w.tr, 'cancelled_tickets', [])])
            self.assertEqual(w.tr.orders[0].state, en.OS_FILLED, 'the open position is not touched')
            self.assertEqual(w.tr.cancels, 1 if ctx == 1 else 0, 'only the pending of the opposite direction (SELL when the context turned BUY); a filled BUY is a position')

    def test_an_uncertain_cancel_halts_and_is_never_retried_even_after_a_restart(self):
        for mode in ('lost', 'not_effective', 'fails'):
            w, st = multi(self.SPECS)
            w.tr.cancel_mode = mode
            lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, ctx=-1), dir_enabled=tp.EV_DIRECTION_CHANGE)
            self.assertIn('CANCEL_NOT_CONFIRMED', st.halted, mode)
            first = w.tr.cancels
            self.assertGreaterEqual(first, 1, mode)
            lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, ctx=-1), dir_enabled=tp.EV_DIRECTION_CHANGE)
            self.assertEqual(w.tr.cancels, first, mode + ': no automatic second cancellation')
            lc.release(w.store, st)
            tr2, store2 = new_process(w, keep_book=True)                     # a restart: the halt is persisted, the stored intent blocks a second cancel
            st2, notes = lc.startup(w.cfg, tr2, store2, store2)
            lc.tick(w.cfg, tr2, store2, st2, 0, 0, facts=facts_for(w, ctx=-1), dir_enabled=tp.EV_DIRECTION_CHANGE)
            self.assertEqual(w.tr.cancels, first, mode + ': still no second cancellation after the restart')
            self.assertTrue(st2.halted, mode)

    def test_a_cancelled_record_is_not_cancelled_twice_and_a_restart_does_not_revive_it(self):
        w, st = multi(self.SPECS)
        lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, ctx=-1), dir_enabled=DIR_BOTH)
        n = w.tr.cancels
        lc.tick(w.cfg, w.tr, w.store, st, 0, 0, facts=facts_for(w, ctx=-1), dir_enabled=DIR_BOTH)
        self.assertEqual(w.tr.cancels, n)
        lc.release(w.store, st)
        tr2, store2 = new_process(w, keep_book=True)
        st2, notes = lc.startup(w.cfg, tr2, store2, store2)
        self.assertEqual(sorted(st2.ids), ['SIG-B'])
        lc.tick(w.cfg, tr2, store2, st2, 0, 0, facts=facts_for(w, ctx=-1), dir_enabled=DIR_BOTH)
        self.assertEqual((w.tr.cancels, sorted(st2.ids)), (n, ['SIG-B']))

    def test_global_events_and_direction_events_combine_per_record(self):
        w, st = multi(self.SPECS)
        lc.tick(w.cfg, w.tr, w.store, st, tp.EV_SESSION_END, tp.EV_SESSION_END, facts=facts_for(w, ctx=-1), dir_enabled=tp.EV_DIRECTION_CHANGE)
        self.assertEqual((w.tr.cancels, st.ids), (3, []), 'session end cancels every pending; the direction event adds its reason for the opposite ones')


class OrchestratorFacts(unittest.TestCase):
    def test_the_orchestrator_exposes_the_direction_it_knows_and_nothing_else(self):
        for d in (1, -1):
            w = teo.World(d)
            o1, l1 = teo.observer_n(d, 2)
            w.step(o1, l1)
            self.assertEqual((w.o.facts.valid, w.o.facts.ctx_direction, w.o.facts.signal_direction), (True, d, 0), 'a known context, no signal yet')
            o2, l2 = teo.observer_n(d, 3)
            w.step(o2, l2)
            self.assertEqual((w.o.facts.valid, w.o.facts.ctx_direction, w.o.facts.signal_direction), (True, d, d))
            self.assertTrue(w.o.facts.signal_id)
            w.step(None, None, feed_ok=False)
            self.assertEqual((w.o.facts.valid, w.o.facts.ctx_direction, w.o.facts.signal_direction), (False, 0, 0), 'no confirmed data proves nothing')
            o3, l3 = teo.observer_n(d, 3)
            o3.set_context(teo.ts.context(d, ready=False), o3.last_asof + 900)
            w.step(o3, l3)
            self.assertEqual((w.o.facts.valid, w.o.facts.ctx_direction), (False, 0), 'a lost context proves nothing')



class FakeSink:
    """the FAKE push receiver: records the texts; a mode scripts the answer (no real notification is ever sent)"""

    def __init__(self):
        self.texts, self.calls, self.mode = [], 0, lc.NT_SENT

    def send(self, text):
        self.calls += 1
        if self.mode == lc.NT_SENT:
            self.texts.append(text)
        return self.mode

    def has(self, frag):
        return [t for t in self.texts if frag in t]


class Notifications(unittest.TestCase):
    """push notifications for PROVEN facts of OWNED objects: placed pending (broker facts, never OrderSend=true), filled position, partial close vs final close, modification; once each; a failed
    notification changes nothing (no decision, no order); a manual trade never notifies; a restart repeats nothing"""

    def notifier(self, w, sink=None, magic=777, baseline=False):
        n = lc.Notifier(sink or FakeSink(), w.store, magic, 'XAUUSD', prefix='[FAKE] ')
        n.baseline = baseline
        return n

    def test_a_pending_is_announced_when_the_broker_facts_show_it_and_a_fill_when_it_is_a_position(self):
        for d in (1, -1):
            w, st = placed(d)
            sink = FakeSink()
            n = self.notifier(w, sink)
            for _ in range(4):                                                    # polls and reconciles repeat the same fact
                lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)
            self.assertEqual(len(sink.has('PENDING PLACED')), 1, 'dir %d' % d)
            self.assertIn('BUY' if d == 1 else 'SELL', sink.texts[0])
            self.assertTrue(sink.texts[0].startswith('[FAKE] '), 'the FAKE provenance is in the text')
            w.tr.orders[0].state = en.OS_FILLED
            w.tr.orders[0].position_id = 4242
            for _ in range(4):
                lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)
            self.assertEqual((len(sink.has('POSITION OPENED')), len(sink.texts), w.tr.sends), (1, 2, 1))

    def test_an_order_send_that_returned_true_but_is_not_proven_is_not_announced(self):
        for mode in ('uncertain_not_created', 'placed_unreadable', 'rejected'):
            w = te.World(1)
            w.tr.send_mode = mode
            st = owner(w.store, w.tr.account.login)
            guard = lc.Guard(w.store, st)
            ok, why = guard.reserve(SIG)
            res = w.place()
            guard.settled(SIG, res)
            sink = FakeSink()
            n = self.notifier(w, sink)
            lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)
            lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)
            self.assertEqual(sink.texts, [], mode)

    def test_a_removed_pending_is_announced_once(self):
        for d in (1, -1):
            w, st = placed(d)
            sink = FakeSink()
            n = self.notifier(w, sink)
            lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)
            lc.tick(w.cfg, w.tr, w.store, st, tp.EV_SESSION_END, tp.EV_SESSION_END, obs=n)
            lc.tick(w.cfg, w.tr, w.store, st, tp.EV_SESSION_END, tp.EV_SESSION_END, obs=n)
            self.assertEqual((len(sink.has('PENDING PLACED')), len(sink.has('PENDING CANCELLED'))), (1, 1), 'dir %d' % d)

    def test_partial_close_modification_and_final_close_are_distinct_and_announced_once(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            sink = FakeSink()
            rw.obs = n = self.notifier(rw.w, sink)
            rw.reg.inner.obs = n
            rw.tick()
            self.assertEqual(len(sink.has('POSITION OPENED')), 1, 'dir %d' % d)
            self.assertEqual(len(sink.texts), 1, 'the first observation of the position is the opening, not a modification')
            for _ in range(3):
                rw.tick()
            self.assertEqual(len(sink.texts), 1, 'unchanged facts are not repeated by the polls')
            rw.xtr.position.sl = 2000.0                                           # the stop moved to the entry
            for _ in range(3):
                rw.tick()
            self.assertEqual((len(sink.has('POSITION MODIFIED')), len(sink.has('PARTIAL'))), (1, 0), 'dir %d: an SL change is a modification, not a partial close' % d)
            rw.xtr.position.volume = 0.1                                          # the 80% part was closed
            for _ in range(3):
                rw.tick()
            self.assertEqual((len(sink.has('POSITION MODIFIED')), len(sink.has('PARTIAL')), len(sink.has('POSITION CLOSED'))), (1, 1, 0), 'a partial close is not a final close')
            rw.xtr.position.volume = 0.3                                          # a volume that INCREASES is not a partial close
            rw.tick()
            self.assertEqual(len(sink.has('PARTIAL')), 1)
            rw.xtr.position.found = False
            rw.closed = True                                                      # the list is readable and stable and holds no such position
            for _ in range(3):
                rw.tick()
            self.assertEqual((len(sink.has('POSITION CLOSED')), len(sink.texts)), (1, 4), 'dir %d' % d)

    def test_an_unreadable_position_is_not_a_close(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            sink = FakeSink()
            rw.obs = n = self.notifier(rw.w, sink)
            rw.reg.inner.obs = n
            rw.tick()
            rw.xtr.position.found = False                                         # unreadable, not proven absent
            rw.tick()
            self.assertEqual(sink.has('POSITION CLOSED'), [])

    def test_a_failing_notification_changes_no_decision_and_sends_no_order(self):
        for mode in (lc.NT_FAILED, lc.NT_RETRY_LATER):
            for d in (1, -1):
                w, st = placed(d)
                sink = FakeSink()
                sink.mode = mode
                n = self.notifier(w, sink)
                before = (w.tr.sends, w.tr.cancels)
                for _ in range(6):
                    lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)
                self.assertEqual(((w.tr.sends, w.tr.cancels), st.ids, st.halted), (before, [SIG], ''), 'the trading state is unchanged')
                if mode == lc.NT_FAILED:
                    self.assertEqual(sink.calls, lc.Notifier.MAX_TRIES, 'bounded retries, then the event is dropped')
                else:
                    self.assertEqual(sink.calls, 6, 'a throttled sink is asked again at every observation and does not consume attempts')
                    sink.mode = lc.NT_SENT
                    lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)
                    self.assertEqual(len(sink.has('PENDING PLACED')), 1)

    def test_a_throttled_position_event_is_delivered_by_a_later_observation(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            sink = FakeSink()
            rw.obs = n = self.notifier(rw.w, sink)
            rw.reg.inner.obs = n
            rw.tick()
            rw.tick()
            sink.mode = lc.NT_RETRY_LATER
            rw.xtr.position.volume = 0.1
            rw.xtr.position.sl = 2000.0
            for _ in range(3):
                rw.tick()
            self.assertTrue(all('POSITION OPENED' in t for t in sink.texts), 'nothing but the opening was delivered while the sink was throttled')
            sink.mode = lc.NT_SENT
            rw.tick()
            rw.tick()
            self.assertEqual((len(sink.has('PARTIAL')), len(sink.has('POSITION MODIFIED'))), (1, 1), 'delivered once after the throttle')

    def test_a_throttled_or_failed_terminal_event_survives_the_removal_of_its_object(self):
        """the confirmed cancel removes the pending from the index: the waiting notification must still be delivered by a later tick (a restart is the documented limit: nothing waits across it)"""
        for d in (1, -1):
            for mode in (lc.NT_RETRY_LATER, lc.NT_FAILED):
                w, st = placed(d)
                sink = FakeSink()
                n = self.notifier(w, sink)
                lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)
                self.assertEqual(len(sink.has('PENDING PLACED')), 1)
                sink.mode = mode
                before = (w.tr.sends, w.tr.cancels)
                lc.tick(w.cfg, w.tr, w.store, st, tp.EV_SESSION_END, tp.EV_SESSION_END, obs=n)       # the cancel is confirmed, the object leaves the index
                self.assertEqual((st.ids, w.tr.cancels), ([], before[1] + 1))
                for _ in range(2):
                    lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)                                   # nothing left to observe, the receiver still refuses
                self.assertEqual(sink.has('PENDING CANCELLED'), [])
                if mode == lc.NT_RETRY_LATER:
                    sink.mode = lc.NT_SENT
                    lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)
                    lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)
                    self.assertEqual(len(sink.has('PENDING CANCELLED')), 1, 'delivered once, later, after the throttle')
                else:
                    self.assertEqual(sink.calls, 1 + lc.Notifier.MAX_TRIES, 'failures consume the existing attempts, then the event is dropped')
                    sink.mode = lc.NT_SENT
                    lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)
                    self.assertEqual(sink.has('PENDING CANCELLED'), [], 'a dropped event is not resurrected')
                self.assertEqual(w.tr.sends, 1, 'the notification never touches the trading')

    def test_the_final_close_of_the_remainder_is_announced_after_partial_and_done(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            sink = FakeSink()
            rw.obs = n = self.notifier(rw.w, sink)
            rw.reg.inner.obs = n
            manages = []
            orig = rw.mgr.manage
            rw.mgr.manage = lambda rec, ident, name, orig=orig: (manages.append(1), orig(rec, ident, name))[1]
            rw.tick()
            rw.tick()
            bid, ask = rw.level_quote()
            self.assertEqual([r.final for _, r in rw.mgr.on_quote(bid, ask)], [ex.SENT_MAPPED])
            rw.xtr.position.volume = 0.1
            rw.raw_now = raw_full(d)
            self.assertEqual([f.final for _, f in rw.mgr.on_timer()], [fl.DONE])
            notes = ' '.join(rw.tick())
            self.assertIn('MANAGEMENT_DONE', notes)
            self.assertEqual((rw.st.ids, rw.mgr.slots), ([SIG], {}), 'dir %d: the finished slot is released, the id stays only to observe' % d)
            count = len(manages)
            for _ in range(4):
                rw.tick()
            self.assertEqual((len(manages), len(rw.xtr.sends), rw.mgr.slots), (count, 1, {}), 'the finished management is not re-armed, no slot is held')
            self.assertEqual((len(sink.has('PARTIAL')), len(sink.has('POSITION CLOSED'))), (1, 0))
            rw.xtr.position.found = False
            rw.closed = True
            for _ in range(3):
                rw.tick()
            self.assertEqual((len(sink.has('POSITION CLOSED')), rw.st.ids, rw.st.halted, n.last), (1, [], '', {}), 'dir %d: the final close is announced once and the index is empty' % d)

    def test_the_observation_after_done_survives_a_restart_without_rearming(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            sink = FakeSink()
            rw.obs = n = self.notifier(rw.w, sink)
            rw.reg.inner.obs = n
            rw.tick()
            rw.tick()
            bid, ask = rw.level_quote()
            rw.mgr.on_quote(bid, ask)
            rw.xtr.position.volume = 0.1
            rw.raw_now = raw_full(d)
            rw.mgr.on_timer()
            rw.tick()
            self.assertEqual(rw.st.ids, [SIG])
            sends = len(rw.xtr.sends)
            lc.release(rw.w.store, rw.st)
            rw.w.tr, store = new_process(rw.w, keep_book=True)
            rw.w.store = store
            rw.locks = Locks()
            rw.reg = rw.make_registrar()
            rw.attach()
            n2 = lc.Notifier(sink, store, 777, 'XAUUSD', prefix='[FAKE] ')
            n2.baseline = True
            rw.obs = n2
            rw.reg.inner.obs = n2
            rw.st, notes = lc.startup(rw.w.cfg, rw.w.tr, store, store, False, sink=rw.reg, obs=n2)
            n2.baseline = False
            self.assertEqual((rw.st.ids, rw.mgr.slots, len(rw.xtr.sends)), ([SIG], {}, sends), 'recovered as DONE: observed, no slot, no re-arming, no send')
            rw.xtr.position.found = False
            rw.closed = True
            rw.tick()
            rw.tick()
            self.assertEqual((len(sink.has('POSITION CLOSED')), rw.st.ids, len(rw.xtr.sends)), (1, [], sends))

    def test_without_an_observer_the_index_is_released_at_done_as_before(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            rw.tick()
            bid, ask = rw.level_quote()
            rw.mgr.on_quote(bid, ask)
            rw.xtr.position.volume = 0.1
            rw.raw_now = raw_full(d)
            rw.mgr.on_timer()
            rw.tick()
            self.assertEqual((rw.st.ids, rw.mgr.slots), ([], {}))

    def test_more_than_sixteen_different_positions_pass_through_one_notifier_in_one_process(self):
        sink = FakeSink()
        n = None
        for d in (1, -1):
            for i in range(lc.Notifier.MAX_TRACKED + 4):
                rw = MgmtWorld(self, d, pos=(100 if d == 1 else 200) + i)
                if n is None:
                    n = self.notifier(rw.w, sink)
                n.store = rw.w.store
                rw.obs = n
                rw.reg.inner.obs = n
                before = len(sink.texts)
                rw.tick()
                rw.tick()
                rw.xtr.position.volume = 0.1
                rw.tick()
                rw.xtr.position.found = False
                rw.closed = True
                rw.tick()
                rw.tick()
                got = sink.texts[before:]
                self.assertEqual(len(got), 3, 'cycle %d: %s' % (i, got))
                self.assertTrue('POSITION OPENED' in got[0] and 'PARTIAL CLOSE' in got[1] and 'POSITION CLOSED' in got[2], got)
                self.assertEqual((len(got), n.last, rw.st.ids), (3, {}, []), 'dir %d position %d: every event announced, the tracking entry released at the close, the index empty' % (d, i))
        self.assertEqual(len(sink.has('POSITION CLOSED')), 2 * (lc.Notifier.MAX_TRACKED + 4))

    def test_a_new_position_is_never_ignored_when_the_tracking_is_full(self):
        sink = FakeSink()
        rw = MgmtWorld(self, 1)
        n = self.notifier(rw.w, sink)
        for pid in range(1, lc.Notifier.MAX_TRACKED + 6):
            n.on_position(rw.login, SIG, pid, 0.5, 1995.0)
        self.assertEqual((len(n.last), lc.Notifier.MAX_TRACKED + 5 in n.last, 1 in n.last), (lc.Notifier.MAX_TRACKED, True, False), 'the oldest falls out, the newest is followed')


    def test_manual_trades_and_foreign_records_never_notify(self):
        for d in (1, -1):
            rw = MgmtWorld(self, d)
            sink = FakeSink()
            rw.obs = n = self.notifier(rw.w, sink, magic=778)                      # another magic: the records of this robot are not owned by this notifier
            rw.reg.inner.obs = n
            rw.tick()
            self.assertEqual(sink.texts, [])
            rw2 = MgmtWorld(self, d)
            sink2 = FakeSink()
            rw2.obs = n2 = self.notifier(rw2.w, sink2)
            rw2.reg.inner.obs = n2
            rw2.xtr.position = ex.PositionW(found=True, ticket=99, identifier=99, symbol='XAUUSD', magic=0, type=0 if d == 1 else 1, volume=0.5, price_open=2000.0, sl=rw2.sl)     # a manual position
            rw2.w.tr.orders.append(en.Order(found=True, ticket=9001, symbol='XAUUSD', type=en.TYPE_SELL_LIMIT, state=en.OS_ACTIVE, price=2100.0, sl=2105.0, tp=2090.0, volume=0.1, magic=0, comment='manual'))
            rw2.tick()
            self.assertEqual(sink2.has('POSITION PARTIAL') + sink2.has('POSITION MODIFIED') + sink2.has('POSITION CLOSED') + sink2.has('PENDING'), [], 'the manual pending and the manual position are not announced')

    def test_a_restart_repeats_nothing_and_new_events_are_announced(self):
        for d in (1, -1):
            w, st = placed(d)
            sink = FakeSink()
            n = self.notifier(w, sink)
            lc.tick(w.cfg, w.tr, w.store, st, 0, 0, obs=n)
            self.assertEqual(len(sink.texts), 1)
            lc.release(w.store, st)
            tr2, store2 = new_process(w, keep_book=True)
            n2 = lc.Notifier(sink, store2, 777, 'XAUUSD', prefix='[FAKE] ')
            n2.baseline = True                                                       # the startup sweep only remembers
            st2, notes = lc.startup(w.cfg, tr2, store2, store2, obs=n2)
            n2.baseline = False
            for _ in range(3):
                lc.tick(w.cfg, tr2, store2, st2, 0, 0, obs=n2)
            self.assertEqual(len(sink.texts), 1, 'dir %d: the restart does not repeat the placement' % d)
            tr2.orders[0].state = en.OS_FILLED
            tr2.orders[0].position_id = 4242
            lc.tick(w.cfg, tr2, store2, st2, 0, 0, obs=n2)
            self.assertEqual((len(sink.has('POSITION OPENED')), len(sink.texts)), (1, 2), 'a new fact after the restart is announced')

    def test_an_event_during_the_downtime_is_not_announced_after_the_restart(self):
        w, st = placed(1)
        w.tr.orders[0].state = en.OS_FILLED                                            # filled while the robot was down
        w.tr.orders[0].position_id = 4242
        lc.release(w.store, st)
        sink = FakeSink()
        n = lc.Notifier(sink, w.store, 777, 'XAUUSD')
        n.baseline = True
        st2, notes = lc.startup(w.cfg, w.tr, w.store, w.store, obs=n)
        n.baseline = False
        lc.tick(w.cfg, w.tr, w.store, st2, 0, 0, obs=n)
        self.assertEqual(sink.texts, [])
        self.assertTrue(any('FILLED_UNMANAGED' in x for x in notes), 'the fill is still reported in the log')


class Sources(unittest.TestCase):
    def test_mql_notification_recorder_holds_the_full_multi_position_scenario(self):
        path = os.path.join(ROOT, 'src', 'tests', 'EntryLifecycleTest.mq5')
        with open(path, encoding='ascii') as f:
            text = f.read()
        sink = text[text.index('class CNtFakeSink'):text.index('void NtBind(')]
        capacity = int(re.search(r'string texts\[(\d+)\]', sink).group(1))
        needed = 2 * (lc.Notifier.MAX_TRACKED + 4) * 3
        self.assertGreaterEqual(capacity, needed, '40 positions need 120 recorded messages, not a 64-message recorder')
        self.assertIn('if(n>=ArraySize(texts)) return(NT_FAILED);', sink)

    def test_regagain_uses_scripted_absence_instead_of_live_positions(self):
        with open(os.path.join(ROOT, 'src', 'tests', 'EntryLifecycleTest.mq5'), encoding='ascii') as f:
            text = f.read()
        helper = text[text.index('int RegAgain('):text.index('void Scenario_auto_registration_existing_record_needs_the_full_base')]
        self.assertIn('CTestRegistrar g;', helper)
        self.assertIn('g.closed=false;', helper)
        self.assertNotIn('CMhRegistrar g;', helper)

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
        for cls in (Index, Startup, Tick, IndexBeforeSend, Crash, Instances, DamageDuringRun, FillHandoff, AutoRegistration, ManagedFlow, DirectionCancel, Notifications):
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
                # automatic registration
                ("        if self.exit_store.exists(name) or self.exit_store.exists(name + '.tmp'):\n            status, detail = self._compare(name, ident, rec, acct)", "        if False:\n            status, detail = self._compare(name, ident, rec, acct)"),
                ("o.plan_e_src == pos.price_open\n                and o.plan_s_src == rec.s and o.plan_e_out == geo.e_out and o.plan_s_out == geo.s_out and o.state.level == geo.level_2r", "o.plan_s_src == rec.s and o.plan_s_out == geo.s_out"),
                ("        if not (self.phrase == ex.AUTH_PHRASE):\n            return SINK_REFUSED, 'REAL_NOT_AUTHORISED'", "        if False:\n            return SINK_REFUSED, 'REAL_NOT_AUTHORISED'"),
                ("        if not acct.demo:\n            return SINK_REFUSED, 'REAL_REQUIRES_DEMO_ACCOUNT'", "        if False:\n            return SINK_REFUSED, 'REAL_REQUIRES_DEMO_ACCOUNT'"),
                ("        if not (self.magic > 0 and rec.magic == self.magic):", "        if False:"),
                ("        if pos.symbol != ident.symbol or pos.magic != self.magic or pos.type != (0 if rec.direction == 1 else 1):\n            return SINK_REFUSED, 'OWNERSHIP_NOT_PROVEN: symbol, magic or direction of the live", "        if False:\n            return SINK_REFUSED, 'OWNERSHIP_NOT_PROVEN: symbol, magic or direction of the live"),
                                ("        if self.provenance != PROV_BROKER:", "        if False:"),
                ("and o.plan_vol_min == sym.vol_min and o.plan_vol_step == sym.vol_step and o.plan_vol_max == sym.vol_max)", ")"),
                ("        return (SINK_PENDING if res.reason.startswith(self.TRANSIENT) else SINK_REFUSED), res.reason", "        return SINK_CONFIRMED, res.reason"),
                ("            self.tries[sid] = n\n            if n >= self.MAX_TRIES:", "            self.tries[sid] = n\n            if False:"),
                ("            if sid in st.unmanaged:\n                continue", "            if False:\n                continue"),
                ("            if sid in st.unmanaged or verdict(en.reconcile(cfg, tr, store, sid)) == HALT:", "            if verdict(en.reconcile(cfg, tr, store, sid)) == HALT:"),
                ("        if rec.state != en.ST_FILLED or rec.linked != 1 or rec.position_id <= 0:\n            return SINK_REFUSED, 'FILL_NOT_PROVEN'", "        if False:\n            return SINK_REFUSED, 'FILL_NOT_PROVEN'"),
                # per-record direction events
                ("facts.ctx_direction in (1, -1) and facts.ctx_direction == -rec.direction", "facts.ctx_direction == -rec.direction or True"),
                ("facts.ctx_direction in (1, -1) and facts.ctx_direction == -rec.direction", "facts.ctx_direction != rec.direction"),
                ("facts.signal_direction in (1, -1) and facts.signal_direction == -rec.direction and facts.signal_id != sid", "facts.signal_direction in (1, -1) and facts.signal_direction == -rec.direction"),
                ("    if age < 0 or age > cfg.quote_max_age:\n        return 0\n", ""),
                ("    if not dir_enabled or facts is None or not facts.valid:\n        return 0\n", "    if not dir_enabled or facts is None:\n        return 0\n"),
                # push notifications
                ("        if key in self.done or any(k == key for k, _ in self.outbox):\n            return\n", ""),
                ("        if self.baseline:\n            self.done.add(key)\n            return\n", ""),
                ("        if not ok or rec.magic != self.magic or rec.symbol != self.symbol:\n            return None", "        if not ok:\n            return None"),
                ("                if n >= self.MAX_TRIES:\n                    self.done.add(key)\n                else:\n                    keep.append((key, text))", "                if False:\n                    self.done.add(key)\n                else:\n                    keep.append((key, text))"),
                ("            elif status == NT_RETRY_LATER:\n                keep.append((key, text))\n                blocked = True", "            elif False:\n                keep.append((key, text))\n                blocked = True"),
                ("        if volume < prev[0] - 1e-9:", "        if volume != prev[0]:"),
                ("        self.last.pop(position_id, None)                      # the position is gone: its tracking entry is released", "        pass"),
                ("            if len(self.last) >= self.MAX_TRACKED:\n                self.last.pop(next(iter(self.last)))                # evict the oldest: a new position is never ignored\n", "            if len(self.last) >= self.MAX_TRACKED:\n                return\n"),
                ("    if obs is not None:\n        obs.on_tick()                                         # waiting notifications are delivered at the end of EVERY tick, also when the layer is halted or the object is gone\n", ""),
                ("        if pid in self.observing:\n            return SINK_ACTIVE, 'ACTIVE'                      # observe-only: no slot, no driver, no re-arming\n", ""),
                ("            if self.obs is not None:\n                self.observing.add(pid)\n                return SINK_ACTIVE,", "            if False:\n                return SINK_ACTIVE,"),
                # management inside the orchestrator
                ("            self.manager.forget(pid)       # finished: the slot is released (the T011 record stays; a restart before the index is saved recovers the DONE from it)\n", ""),
                ("            if len(self.slots) >= self.MAX_SLOTS:\n                return SINK_REFUSED, 'MANAGEMENT_SLOTS_FULL'\n", ""),
                ("            if flow.final == fl.DONE:\n                slot.done = True\n                return SINK_CONFIRMED, 'MANAGEMENT_DONE: recovered as DONE'", "            if False:\n                return SINK_CONFIRMED, 'MANAGEMENT_DONE: recovered as DONE'"),
                ("        if status != SINK_CONFIRMED or self.manager is None:\n            return status, detail\n", "        if self.manager is None:\n            return status, detail\n"),
                ("            if self.absent(ident.position_id):", "            if True:"),
                ("        if detail.startswith('POSITION_CLOSED'):\n            self.manager.forget(pid)\n            self.observing.discard(pid)\n            return status, detail\n", ""),
                ("            elif status == SINK_ACTIVE:\n                if detail != 'ACTIVE':", "            elif False:\n                if detail != 'ACTIVE':"),
                # fill -> T011: reported first, forgotten on the next tick; the report states why T011 would refuse
                ("        elif v == FILLED and sid not in st.noted:", "        elif False:"),
                ("    elif abs(rec.tp - geo.level_2r) < sym.tick_size / 2.0:", "    elif False:"),
                ("    elif (buy and rec.tp < geo.level_2r) or (not buy and rec.tp > geo.level_2r):", "    elif False:"),
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



