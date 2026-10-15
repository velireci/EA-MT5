"""T013 entry-executor tests (FAKE transport and FAKE store only): validation -> intent -> one attempt -> link proof -> recovery / cancel. No real order, no terminal."""
import copy
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import entry_reference as en  # noqa: E402
import t007_planning_reference as tp  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIGNAL = 'SIG-1'


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def plan(direction=1, signal=SIGNAL, **kw):
    if direction == 1:
        v = dict(e_out=1990.0, s_out=1985.0, tp=2000.0)
    else:
        v = dict(e_out=2010.0, s_out=2015.0, tp=2000.0)
    v.update(kw)
    return tp.Plan(status=tp.OK, stage=tp.STAGE_COMPLETE, reason='', signal_id=signal, setup_id='SET-1', direction=direction, volume_out=kw.get('volume_out', 0.1),
                   **{k: val for k, val in v.items() if k in ('e_out', 's_out', 'tp')})


def cfg(**kw):
    c = en.Config(enabled=True, ea_magic=777, symbol='XAUUSD', filling=en.FILL_RETURN, expiry_mode=en.EXP_GTC, permit_max_age=60, quote_max_age=30)
    for k, v in kw.items():
        setattr(c, k, v)
    return c


def permit_for(pl, tr, allow=True):
    return en.permit_from(pl, tp.Permit(tp.ALLOW if allow else tp.BLOCK, '', ()), tr.now)


class World:
    def __init__(self, direction=1, **ckw):
        self.tr = en.FakeTransport()
        self.tr.quote = en.Quote(True, 2000.0, 2000.3, self.tr.now)
        self.store = en.FakeStore()
        self.rt = en.Runtime()
        self.cfg = cfg(**ckw)
        self.plan = plan(direction)
        self.permit = permit_for(self.plan, self.tr)

    def place(self, pl=None, permit=None, rt=None):
        return en.place(self.cfg, self.tr, self.store, rt or self.rt, pl or self.plan, permit or self.permit)

    def rec(self, signal=SIGNAL):
        ok, text = self.store.read(en.file_name(self.tr.account.login, signal))
        ok, r = en.decode(text)
        assert ok, r
        return r

    def has_file(self, signal=SIGNAL):
        return self.store.exists(en.file_name(self.tr.account.login, signal))

    def reconcile(self, signal=SIGNAL):
        return en.reconcile(self.cfg, self.tr, self.store, signal)

    def clean(self):
        return self.store.held == set() and self.store.lock_calls == self.store.unlock_calls


def cancel_decision(signal=SIGNAL):
    return tp.cancel_decision(True, signal, False, tp.EV_SESSION_END)


class Placement(unittest.TestCase):
    def test_buy_limit_is_placed_linked_and_the_request_is_exactly_the_plan(self):
        w = World(1)
        r = w.place()
        self.assertEqual((r.final, r.sends, r.state, w.tr.sends), (en.R_PLACED, 1, en.ST_PLACED, 1))
        q = w.tr.requests[0]
        self.assertEqual((q.type, q.symbol, q.volume, q.price, q.sl, q.tp, q.magic, q.filling, q.expiry_mode, q.expiration), (en.TYPE_BUY_LIMIT, 'XAUUSD', 0.1, 1990.0, 1985.0, 2000.0, 777, en.FILL_RETURN, en.EXP_GTC, 0))
        self.assertEqual(q.comment, en.req_id(SIGNAL))
        rec = w.rec()
        self.assertEqual((rec.state, rec.attempts, rec.linked, rec.order_ticket, rec.generation), (en.ST_PLACED, 1, 1, r.order_ticket, 2))
        self.assertTrue(w.clean())

    def test_sell_limit_is_placed_linked_and_the_request_is_exactly_the_plan(self):
        w = World(-1)
        r = w.place()
        self.assertEqual((r.final, w.tr.sends), (en.R_PLACED, 1))
        q = w.tr.requests[0]
        self.assertEqual((q.type, q.price, q.sl, q.tp), (en.TYPE_SELL_LIMIT, 2010.0, 2015.0, 2000.0))
        self.assertTrue(w.clean())

    def test_expiry_modes(self):
        w = World(1, expiry_mode=en.EXP_SECONDS, expiry_seconds=3600)
        self.assertEqual(w.place().final, en.R_PLACED)
        self.assertEqual((w.tr.requests[0].expiry_mode, w.tr.requests[0].expiration), (en.EXP_SECONDS, w.tr.now + 3600))
        self.assertEqual(w.rec().expiration, w.tr.now + 3600)

    def test_every_unset_mandatory_input_blocks_with_zero_sends_and_no_file(self):
        for name, kw in (('disabled', dict(enabled=False)), ('magic', dict(ea_magic=0)), ('symbol', dict(symbol='  ')), ('filling', dict(filling=en.FILL_UNSET)),
                         ('expiry_mode', dict(expiry_mode=en.EXP_UNSET)), ('expiry_seconds', dict(expiry_mode=en.EXP_SECONDS, expiry_seconds=0)),
                         ('permit_age', dict(permit_max_age=-1)), ('quote_age', dict(quote_max_age=-1)), ('filling_range', dict(filling=9))):
            with self.subTest(name):
                w = World(1, **kw)
                r = w.place()
                self.assertEqual((r.final, r.sends, w.tr.sends, w.has_file(), w.store.lock_calls), (en.R_REFUSED, 0, 0, False, 0), r.reason)
                self.assertTrue(r.reason.startswith(('DISABLED', 'INPUT_UNSET')), r.reason)

    def test_plan_refusals(self):
        for name, pl in (('status', tp.Plan(status=tp.GEOMETRY_REFUSED, stage=tp.STAGE_GEOMETRY, reason='x')), ('stage', copy.replace(plan(), stage=tp.STAGE_SIZING) if hasattr(copy, 'replace') else None),
                         ('blank signal', plan(signal='')), ('direction', plan(direction=0)), ('buy geometry', plan(1, s_out=1995.0)), ('sell geometry', plan(-1, s_out=2005.0)),
                         ('nan', plan(1, e_out=float('nan'))), ('zero volume', plan(1, volume_out=0.0))):
            if pl is None:
                continue
            with self.subTest(name):
                w = World(1)
                r = en.place(w.cfg, w.tr, w.store, w.rt, pl, w.permit)
                self.assertEqual((r.final, w.tr.sends, w.has_file(SIGNAL), w.store.lock_calls), (en.R_REFUSED, 0, False, 0), r.reason)

    def test_permit_must_be_present_allowing_bound_to_this_plan_and_fresh(self):
        w = World(1)
        other = plan(1, e_out=1991.0)
        cases = (('missing', en.Permit()), ('not allowed', permit_for(w.plan, w.tr, allow=False)), ('another plan', permit_for(other, w.tr)),
                 ('another signal', permit_for(plan(1, signal='SIG-2'), w.tr)), ('empty digest', en.Permit(True, True, '', w.tr.now)),
                 ('stale', en.Permit(True, True, en.plan_digest(w.plan), w.tr.now - 61)), ('future', en.Permit(True, True, en.plan_digest(w.plan), w.tr.now + 1)),
                 ('unset time', en.Permit(True, True, en.plan_digest(w.plan), 0)))
        for name, pm in cases:
            with self.subTest(name):
                w2 = World(1)
                r = w2.place(permit=pm)
                self.assertEqual((r.final, w2.tr.sends, w2.has_file(), w2.store.lock_calls), (en.R_REFUSED, 0, False, 0), r.reason)
                self.assertTrue(r.reason.startswith('PERMIT'), r.reason)
        edge = en.Permit(True, True, en.plan_digest(w.plan), w.tr.now - 60)
        self.assertEqual(World(1).place(permit=edge).final, en.R_PLACED)         # exactly the maximum age is still fresh

    def test_a_permit_issued_for_one_plan_never_places_a_changed_plan(self):
        w = World(1)
        changed = plan(1, volume_out=0.2)
        self.assertEqual(en.place(w.cfg, w.tr, w.store, w.rt, changed, w.permit).final, en.R_REFUSED)
        self.assertEqual(w.tr.sends, 0)

    def test_real_transport_needs_authorisation_and_a_demo_account(self):
        w = World(1)
        w.tr.real = True
        self.assertEqual((w.place().final, w.tr.sends), (en.R_REFUSED, 0))
        w.cfg.real_authorised, w.cfg.authorisation = True, 'wrong'
        self.assertIn('REAL_NOT_AUTHORISED', w.place().reason)
        w.cfg.authorisation = en.AUTH_PHRASE
        w.tr.account.demo = False
        self.assertIn('REAL_REQUIRES_DEMO_ACCOUNT', w.place().reason)
        w.tr.account.demo = True
        self.assertEqual(w.place().final, en.R_PLACED)

    def test_terminal_read_failures_are_zero_sends_and_no_record(self):
        changes = (('account', lambda tr: setattr(tr.account, 'read_ok', False)), ('trade not allowed', lambda tr: setattr(tr.account, 'trade_allowed', False)),
                   ('netting', lambda tr: setattr(tr.account, 'margin_mode', 0)), ('symbol', lambda tr: setattr(tr.symbol, 'read_ok', False)),
                   ('symbol closed', lambda tr: setattr(tr.symbol, 'trade_ok', False)), ('quote', lambda tr: setattr(tr.quote, 'read_ok', False)),
                   ('stale quote', lambda tr: setattr(tr.quote, 'time', tr.now - 31)), ('future quote', lambda tr: setattr(tr.quote, 'time', tr.now + 500)),
                   ('list incomplete', lambda tr: setattr(tr, 'list_complete', False)), ('server time', lambda tr: setattr(tr, 'now', 0)),
                   ('buy above ask', lambda tr: setattr(tr.quote, 'ask', 1989.0)), ('stops level', lambda tr: setattr(tr.symbol, 'stops_level', 2100)),
                   ('off grid', lambda tr: setattr(tr.symbol, 'tick_size', 0.03)), ('volume step', lambda tr: setattr(tr.symbol, 'vol_step', 0.03)),
                   ('volume max', lambda tr: setattr(tr.symbol, 'vol_max', 0.05)))
        for name, ch in changes:
            with self.subTest(name):
                w = World(1)
                ch(w.tr)
                if name == 'server time':
                    w.permit = en.Permit(True, True, en.plan_digest(w.plan), 1)
                r = w.place()
                self.assertEqual((r.final, r.sends, w.tr.sends, w.has_file()), (en.R_REFUSED, 0, 0, False), r.reason)
                self.assertTrue(w.clean(), name)

    def test_sell_limit_below_the_bid_is_refused(self):
        w = World(-1)
        w.tr.quote.bid = 2012.0
        w.tr.quote.ask = 2012.3
        r = w.place()
        self.assertEqual((r.final, w.tr.sends), (en.R_REFUSED, 0))

    def test_lock_failure_is_zero_sends_and_nothing_is_written(self):
        w = World(1)
        w.store.deny_lock = True
        r = w.place()
        self.assertEqual((r.final, w.tr.sends, w.store.writes, w.has_file()), (en.R_LOCK_FAILED, 0, 0, False))

    def test_an_identical_pending_order_already_in_the_terminal_blocks_the_send(self):
        w = World(1)
        w.tr.orders.append(en.Order(True, 5, 'XAUUSD', en.TYPE_BUY_LIMIT, en.OS_ACTIVE, 1990.0, 1985.0, 2000.0, 0.1, 777, 'x', w.tr.now - 5))
        r = w.place()
        self.assertEqual((r.final, w.tr.sends, w.has_file()), (en.R_REFUSED, 0, False))

    def test_snapshot_too_large_is_zero_sends(self):
        w = World(1)
        for i in range(en.MAX_SNAP + 1):
            w.tr.orders.append(en.Order(True, 100 + i, 'XAUUSD', en.TYPE_SELL_LIMIT, en.OS_CANCELED, 2100.0, 2105.0, 2090.0, 0.5, 5, '', 1))
        self.assertEqual((w.place().final, w.tr.sends), (en.R_REFUSED, 0))


class IntentAndDuplicates(unittest.TestCase):
    def test_intent_write_failure_is_zero_sends(self):
        w = World(1)
        w.store.fail_write = {1}
        r = w.place()
        self.assertEqual((r.final, r.sends, w.tr.sends, w.has_file()), (en.R_BLOCKED, 0, 0, False))
        self.assertTrue(w.clean())

    def test_intent_readback_difference_is_zero_sends(self):
        w = World(1)
        w.store.readback_differs = {1}
        r = w.place()
        self.assertEqual((r.final, r.sends, w.tr.sends), (en.R_BLOCKED, 0, 0))
        self.assertEqual(w.reconcile().final, en.R_BLOCKED)          # the damaged file is never trusted or overwritten

    def test_precheck_refusal_is_zero_sends_and_terminal_for_the_signal(self):
        w = World(1)
        w.tr.precheck_ok = False
        r = w.place()
        self.assertEqual((r.final, r.sends, w.tr.sends, w.rec().state), (en.R_PRECHECK_REFUSED, 0, 0, en.ST_PRECHECK_REFUSED))
        w.tr.precheck_ok = True
        self.assertEqual((w.place(rt=en.Runtime()).final, w.tr.sends), (en.R_DUPLICATE, 0))

    def test_second_call_for_the_same_signal_never_sends_again(self):
        w = World(1)
        self.assertEqual(w.place().final, en.R_PLACED)
        again = w.place(rt=en.Runtime())                         # a restart: new runtime, same disk
        self.assertEqual((again.final, again.sends, w.tr.sends), (en.R_DUPLICATE, 0, 1))
        again2 = w.place()                                       # same runtime
        self.assertEqual((again2.final, w.tr.sends), (en.R_REFUSED, 1))
        self.assertIn('DUPLICATE_CALL', again2.reason)

    def test_two_signals_use_two_records_and_two_locks(self):
        w = World(1)
        self.assertEqual(w.place().final, en.R_PLACED)
        pl2 = plan(1, signal='SIG-2', e_out=1980.0, s_out=1975.0, tp=1990.0)
        r2 = en.place(w.cfg, w.tr, w.store, en.Runtime(), pl2, permit_for(pl2, w.tr))
        self.assertEqual((r2.final, w.tr.sends), (en.R_PLACED, 2))
        self.assertNotEqual(en.file_name(1, 'SIG-1'), en.file_name(1, 'SIG-2'))
        self.assertNotEqual(en.lock_key(1, 'SIG-1'), en.lock_key(1, 'SIG-2'))

    def test_a_damaged_or_foreign_record_blocks_and_is_never_overwritten(self):
        for text in ('garbage\n', ''):
            w = World(1)
            name = en.file_name(w.tr.account.login, SIGNAL)
            w.store.files[name] = text
            before = w.store.files[name]
            r = w.place()
            self.assertEqual((r.final, w.tr.sends, w.store.files[name], w.store.writes), (en.R_BLOCKED, 0, before, 0), r.reason)
        w = World(1)
        w.store.files[en.file_name(w.tr.account.login, SIGNAL)] = 'x\n'
        w.store.unreadable.add(en.file_name(w.tr.account.login, SIGNAL))
        self.assertEqual((w.place().final, w.tr.sends), (en.R_BLOCKED, 0))


class Outcomes(unittest.TestCase):
    def test_definite_reject_is_recorded_and_not_retried(self):
        w = World(1)
        w.tr.send_mode = 'rejected'
        r = w.place()
        self.assertEqual((r.final, r.sends, w.tr.sends, w.rec().state, w.rec().attempts), (en.R_REJECTED, 1, 1, en.ST_REJECTED, 1))
        w.tr.send_mode = 'placed'
        self.assertEqual((w.place(rt=en.Runtime()).final, w.tr.sends), (en.R_DUPLICATE, 1))
        self.assertEqual(w.reconcile().final, en.R_NOCHANGE)

    def test_uncertain_answer_records_one_attempt_and_recovery_without_claiming_zero_sends(self):
        for mode in ('uncertain_created', 'uncertain_not_created', 'partial_codes', 'unknown_code_with_order'):
            with self.subTest(mode):
                w = World(1)
                w.tr.send_mode = mode
                r = w.place()
                self.assertEqual((r.final, r.sends, w.tr.sends, w.rec().state, w.rec().attempts, w.rt.latched), (en.R_RECOVERY, 1, 1, en.ST_RECOVERY, 1, True))
                self.assertEqual(w.place().final, en.R_REFUSED)               # latched runtime
                self.assertEqual(w.place(rt=en.Runtime()).final, en.R_DUPLICATE)
                self.assertEqual(w.tr.sends, 1)

    def test_unproven_link_is_recovery_never_a_placed_state(self):
        for mode in ('placed_unreadable', 'placed_modified', 'placed_other_ticket'):
            with self.subTest(mode):
                w = World(1)
                w.tr.send_mode = mode
                r = w.place()
                self.assertEqual((r.final, w.rec().state, w.rec().linked, w.rec().attempts, w.tr.sends), (en.R_RECOVERY, en.ST_RECOVERY, 0, 1, 1))

    def test_a_response_ticket_that_was_in_the_pre_send_snapshot_never_links(self):
        w = World(1)
        w.tr.orders.append(en.Order(True, 5, 'XAUUSD', en.TYPE_BUY_LIMIT, en.OS_FILLED, 1990.0, 1985.0, 2000.0, 0.1, 777, '', w.tr.now - 9999, 0, 11))   # an old filled order with the same tuple
        w.tr.send_mode = 'placed_returns_old_ticket'
        r = w.place()
        self.assertEqual((r.final, w.rec().state, w.rec().linked, w.tr.sends), (en.R_RECOVERY, en.ST_RECOVERY, 0, 1))

    def test_outcome_save_failure_leaves_intent_and_latches(self):
        w = World(1)
        w.store.fail_write = {2}
        r = w.place()
        self.assertEqual((r.final, r.sends, w.rec().state, w.rt.latched), (en.R_RECOVERY, 1, en.ST_INTENT, True))
        rr = w.reconcile()                                          # the restart finds the intent and the order that exists
        self.assertEqual((rr.final, rr.sends, w.rec().state, w.tr.sends), (en.R_PLACED, 0, en.ST_PLACED, 1))

    def test_uncertain_answer_is_resolved_by_the_tuple_outside_the_snapshot(self):
        w = World(1)
        w.tr.send_mode = 'uncertain_created'
        w.place()
        r = w.reconcile()
        self.assertEqual((r.final, r.sends, w.rec().linked, w.rec().state, w.tr.sends), (en.R_PLACED, 0, 1, en.ST_PLACED, 1))

    def test_no_candidate_stays_recovery_and_never_resends(self):
        w = World(1)
        w.tr.send_mode = 'uncertain_not_created'
        w.place()
        for _ in range(3):
            r = w.reconcile()
            self.assertEqual((r.final, w.tr.sends), (en.R_RECOVERY, 1))

    def test_comment_magic_or_volume_alone_never_link_an_order(self):
        w = World(1)
        w.tr.send_mode = 'uncertain_not_created'
        w.place()
        base = dict(found=True, symbol='XAUUSD', type=en.TYPE_BUY_LIMIT, state=en.OS_ACTIVE, magic=777, comment=en.req_id(SIGNAL), volume=0.1, time_setup=w.tr.now)
        for ticket, over in ((11, dict(price=1991.0, sl=1985.0, tp=2000.0)), (12, dict(price=1990.0, sl=1984.0, tp=2000.0)), (13, dict(price=1990.0, sl=1985.0, tp=2001.0)),
                             (14, dict(price=1990.0, sl=1985.0, tp=2000.0, magic=1)), (15, dict(price=1990.0, sl=1985.0, tp=2000.0, volume=0.2)),
                             (16, dict(price=1990.0, sl=1985.0, tp=2000.0, type=en.TYPE_SELL_LIMIT)), (17, dict(price=1990.0, sl=1985.0, tp=2000.0, symbol='EURUSD')),
                             (18, dict(price=1990.0, sl=1985.0, tp=2000.0, time_setup=w.tr.now - 5000))):
            o = en.Order(ticket=ticket, **{**base, **over})
            w.tr.orders.append(o)
        r = w.reconcile()
        self.assertEqual((r.final, w.rec().linked, w.tr.sends), (en.R_RECOVERY, 0, 1), r.reason)

    def test_an_order_that_was_in_the_pre_send_snapshot_is_never_a_candidate(self):
        w = World(1)
        w.tr.orders.append(en.Order(True, 5, 'XAUUSD', en.TYPE_BUY_LIMIT, en.OS_CANCELED, 1990.0, 1985.0, 2000.0, 0.1, 777, '', w.tr.now))   # old history order with the same tuple
        w.tr.send_mode = 'uncertain_not_created'
        w.place()
        r = w.reconcile()
        self.assertEqual((r.final, w.rec().linked), (en.R_RECOVERY, 0))
        self.assertIn('NO_CANDIDATE', r.reason)                      # not even tried: the snapshot excludes it before any save is attempted

    def test_two_candidates_are_blocked_and_none_is_chosen(self):
        w = World(1)
        w.tr.send_mode = 'uncertain_created'
        w.place()
        dup = copy.deepcopy(w.tr.orders[-1])
        dup.ticket += 1
        w.tr.orders.append(dup)
        r = w.reconcile()
        self.assertEqual((r.final, w.rec().state, w.rec().linked, w.tr.sends), (en.R_BLOCKED, en.ST_BLOCKED, 0, 1))

    def test_incomplete_list_during_recovery_concludes_nothing(self):
        w = World(1)
        w.tr.send_mode = 'uncertain_created'
        w.place()
        w.tr.list_complete = False
        r = w.reconcile()
        self.assertEqual((r.final, w.rec().state, w.rec().linked), (en.R_RECOVERY, en.ST_RECOVERY, 0))


class Reconcile(unittest.TestCase):
    def placed(self):
        w = World(1)
        r = w.place()
        self.assertEqual(r.final, en.R_PLACED)
        return w, r.order_ticket

    def order(self, w, ticket):
        return next(o for o in w.tr.orders if o.ticket == ticket)

    def test_active_stays_and_nothing_is_sent_or_cancelled(self):
        w, t = self.placed()
        r = w.reconcile()
        self.assertEqual((r.final, w.tr.sends, w.tr.cancels, w.rec().generation), (en.R_NOCHANGE, 1, 0, 2))

    def test_filled_gets_the_position_id_from_the_order(self):
        w, t = self.placed()
        o = self.order(w, t)
        o.state, o.position_id = en.OS_FILLED, 424242
        r = w.reconcile()
        self.assertEqual((r.final, r.position_id, w.rec().state, w.rec().position_id), (en.R_FILLED, 424242, en.ST_FILLED, 424242))
        self.assertEqual(w.reconcile().final, en.R_NOCHANGE)

    def test_filled_without_a_position_id_is_not_trusted(self):
        w, t = self.placed()
        self.order(w, t).state = en.OS_FILLED
        self.assertEqual((w.reconcile().final, w.rec().state), (en.R_RECOVERY, en.ST_RECOVERY))

    def test_cancelled_expired_and_missing_orders(self):
        w, t = self.placed()
        self.order(w, t).state = en.OS_CANCELED
        self.assertEqual((w.reconcile().final, w.rec().state), (en.R_CANCELLED, en.ST_CANCELLED))
        w, t = self.placed()
        self.order(w, t).state = en.OS_EXPIRED
        self.assertEqual((w.reconcile().final, w.rec().state), (en.R_EXPIRED, en.ST_EXPIRED))
        w, t = self.placed()
        w.tr.hide.add(t)
        self.assertEqual((w.reconcile().final, w.rec().state), (en.R_RECOVERY, en.ST_RECOVERY))
        w.tr.hide.clear()
        self.assertEqual((w.reconcile().final, w.rec().state), (en.R_PLACED, en.ST_PLACED))      # an order that reappears with the same tuple is accepted again

    def test_a_modified_order_is_blocked_and_not_touched(self):
        w, t = self.placed()
        self.order(w, t).sl = 1980.0
        r = w.reconcile()
        self.assertEqual((r.final, w.rec().state, w.tr.cancels, w.tr.sends), (en.R_BLOCKED, en.ST_BLOCKED, 0, 1))
        self.assertEqual(w.reconcile().final, en.R_NOCHANGE)

    def test_a_changed_order_identity_is_blocked(self):
        w, t = self.placed()
        self.order(w, t).magic = 5
        self.assertEqual((w.reconcile().final, w.rec().state), (en.R_BLOCKED, en.ST_BLOCKED))

    def test_damaged_missing_other_account_and_other_magic(self):
        w, t = self.placed()
        name = en.file_name(w.tr.account.login, SIGNAL)
        good = w.store.files[name]
        w.store.files[name] = good.replace('LOGIN=5001234', 'LOGIN=5001235')
        self.assertEqual(w.reconcile().final, en.R_BLOCKED)
        w.store.files[name] = good
        w.cfg.ea_magic = 778
        self.assertEqual(w.reconcile().final, en.R_BLOCKED)
        w.cfg.ea_magic = 777
        self.assertEqual(w.reconcile(signal='SIG-NONE').final, en.R_NONE)
        w.tr.account.read_ok = False
        self.assertEqual(w.reconcile().final, en.R_REFUSED)

    def test_reconcile_never_sends_or_cancels_on_any_path(self):
        for mutate in (lambda w, t: None, lambda w, t: setattr(self.order(w, t), 'state', en.OS_CANCELED), lambda w, t: w.tr.hide.add(t),
                       lambda w, t: setattr(self.order(w, t), 'sl', 1.0), lambda w, t: setattr(w.tr, 'list_complete', False)):
            w, t = self.placed()
            mutate(w, t)
            for _ in range(2):
                w.reconcile()
            self.assertEqual((w.tr.sends, w.tr.cancels), (1, 0))

    def test_restart_with_a_fresh_runtime_and_store_object_finds_the_record(self):
        w, t = self.placed()
        store2 = en.FakeStore()
        store2.files = dict(w.store.files)
        r = en.reconcile(w.cfg, w.tr, store2, SIGNAL)
        self.assertEqual((r.final, w.tr.sends), (en.R_NOCHANGE, 1))


class Cancel(unittest.TestCase):
    def placed(self):
        w = World(1)
        r = w.place()
        return w, r.order_ticket

    def cancel(self, w, signal=SIGNAL, decision=None, rt=None):
        return en.cancel(w.cfg, w.tr, w.store, rt or en.Runtime(), signal, decision or cancel_decision(signal))

    def test_a_proven_pending_order_is_cancelled_and_confirmed(self):
        w, t = self.placed()
        r = self.cancel(w)
        self.assertEqual((r.final, w.tr.cancels, w.rec().state, w.tr.sends), (en.R_CANCELLED, 1, en.ST_CANCELLED, 1))
        self.assertTrue(w.clean())

    def test_the_decision_must_be_a_cancel_request_for_this_signal(self):
        w, t = self.placed()
        for dec in (tp.cancel_decision(True, 'OTHER', False, tp.EV_SESSION_END), tp.cancel_decision(False, '', False, tp.EV_SESSION_END), tp.cancel_decision(True, SIGNAL, False, 0),
                    tp.cancel_decision(True, SIGNAL, False, 999)):
            r = self.cancel(w, decision=dec)
            self.assertEqual((r.final, w.tr.cancels), (en.R_REFUSED, 0))

    def test_only_a_placed_linked_record_can_be_cancelled(self):
        for setup in ('rejected', 'recovery', 'none', 'filled', 'cancelled'):
            w = World(1)
            if setup == 'rejected':
                w.tr.send_mode = 'rejected'
                w.place()
            elif setup == 'recovery':
                w.tr.send_mode = 'uncertain_created'
                w.place()
            elif setup in ('filled', 'cancelled'):
                r = w.place()
                o = w.tr.orders[-1]
                if setup == 'filled':
                    o.state, o.position_id = en.OS_FILLED, 9
                else:
                    o.state = en.OS_CANCELED
                w.reconcile()
            r = self.cancel(w)
            self.assertEqual((r.final, w.tr.cancels), (en.R_REFUSED, 0), setup)

    def test_an_order_not_proven_as_the_eas_active_pending_is_never_cancelled(self):
        for name, ch in (('modified', lambda o, w: setattr(o, 'sl', 1980.0)), ('other magic', lambda o, w: setattr(o, 'magic', 5)), ('filled', lambda o, w: setattr(o, 'state', en.OS_FILLED)),
                         ('other symbol', lambda o, w: setattr(o, 'symbol', 'EURUSD')), ('hidden', lambda o, w: w.tr.hide.add(o.ticket))):
            with self.subTest(name):
                w, t = self.placed()
                ch(w.tr.orders[-1], w)
                r = self.cancel(w)
                self.assertEqual((r.final, w.tr.cancels), (en.R_REFUSED, 0), r.reason)

    def test_a_recovery_record_with_a_linked_ticket_is_not_cancelled_even_when_the_order_is_active_again(self):
        w, t = self.placed()
        w.tr.hide.add(t)
        self.assertEqual(w.reconcile().final, en.R_RECOVERY)
        w.tr.hide.clear()
        self.assertEqual((w.rec().state, w.rec().linked), (en.ST_RECOVERY, 1))
        r = self.cancel(w)
        self.assertEqual((r.final, w.tr.cancels), (en.R_REFUSED, 0))

    def test_a_foreign_pending_order_of_another_ea_is_never_touched(self):
        w, t = self.placed()
        w.tr.orders.append(en.Order(True, 77, 'XAUUSD', en.TYPE_BUY_LIMIT, en.OS_ACTIVE, 1990.0, 1985.0, 2000.0, 0.1, 999, 'manual', w.tr.now))
        self.assertEqual(self.cancel(w).final, en.R_CANCELLED)
        self.assertEqual([o.state for o in w.tr.orders if o.ticket == 77], [en.OS_ACTIVE])

    def test_intent_is_saved_before_the_call_and_a_failed_save_cancels_nothing(self):
        w, t = self.placed()
        w.store.fail_write = {w.store.writes + 1}
        r = self.cancel(w)
        self.assertEqual((r.final, w.tr.cancels, w.rec().state), (en.R_BLOCKED, 0, en.ST_PLACED))

    def test_lost_answer_is_cancel_uncertain_then_reconcile_confirms_without_a_retry(self):
        w, t = self.placed()
        w.tr.cancel_mode = 'lost'
        r = self.cancel(w)
        self.assertEqual((r.final, w.tr.cancels, w.rec().state), (en.R_CANCEL_UNCERTAIN, 1, en.ST_CANCEL_UNCERTAIN))
        self.assertEqual(self.cancel(w).final, en.R_REFUSED)
        rr = w.reconcile()
        self.assertEqual((rr.final, w.rec().state, w.tr.cancels, w.tr.sends), (en.R_CANCELLED, en.ST_CANCELLED, 1, 1))

    def test_a_cancel_that_did_not_take_effect_returns_to_placed_through_reconcile(self):
        w, t = self.placed()
        w.tr.cancel_mode = 'not_effective'
        r = self.cancel(w)
        self.assertEqual((r.final, w.rec().state), (en.R_CANCEL_UNCERTAIN, en.ST_CANCEL_UNCERTAIN))
        rr = w.reconcile()
        self.assertEqual((rr.final, w.rec().state, w.tr.cancels), (en.R_PLACED, en.ST_PLACED, 1))
        w2, t2 = self.placed()
        w2.tr.cancel_mode = 'not_effective'
        self.cancel(w2)
        self.assertEqual(w2.rec().state, en.ST_CANCEL_UNCERTAIN)
        again = self.cancel(w2)                                        # a NEW runtime, but the record still says CANCEL_UNCERTAIN: reconcile first
        self.assertEqual((again.final, w2.tr.cancels), (en.R_REFUSED, 1))

    def test_failed_cancel_and_one_cancel_per_runtime(self):
        w, t = self.placed()
        w.tr.cancel_mode = 'fails'
        rt = en.Runtime()
        r = self.cancel(w, rt=rt)
        self.assertEqual((r.final, w.tr.cancels), (en.R_CANCEL_UNCERTAIN, 1))
        self.assertEqual((self.cancel(w, rt=rt).final, w.tr.cancels), (en.R_REFUSED, 1))

    def test_cancel_lock_failure_and_disabled(self):
        w, t = self.placed()
        w.store.deny_lock = True
        self.assertEqual((self.cancel(w).final, w.tr.cancels), (en.R_LOCK_FAILED, 0))
        w.store.deny_lock = False
        w.cfg.enabled = False
        self.assertEqual((self.cancel(w).final, w.tr.cancels), (en.R_REFUSED, 0))


class Review4de81f5(unittest.TestCase):
    """regressions reproduced by the Codex review of 4de81f5: stored cancel attempts, every state save checked in recovery, time / permit / quote re-checked right before Send, PENDING needs RETURN filling"""

    def placed(self, direction):
        w = World(direction)
        r = w.place()
        self.assertEqual(r.final, en.R_PLACED)
        return w, r.order_ticket

    def order(self, w, ticket):
        return next(o for o in w.tr.orders if o.ticket == ticket)

    def test_a_stored_cancel_attempt_blocks_a_second_cancel_after_a_restart(self):
        for direction in (1, -1):
            with self.subTest(direction):
                w, t = self.placed(direction)
                w.tr.cancel_mode = 'not_effective'
                dec = cancel_decision()
                first = en.cancel(w.cfg, w.tr, w.store, en.Runtime(), SIGNAL, dec)
                self.assertEqual((first.final, w.rec().cancel_attempts), (en.R_CANCEL_UNCERTAIN, 1))
                self.assertEqual((w.reconcile().final, w.rec().state, w.rec().cancel_attempts), (en.R_PLACED, en.ST_PLACED, 1))
                again = en.cancel(w.cfg, w.tr, w.store, en.Runtime(), SIGNAL, dec)         # a NEW runtime: only the stored attempt can stop it
                self.assertEqual((again.final, w.tr.cancels), (en.R_REFUSED, 1), again.reason)
                self.assertIn('CANCEL_ALREADY_ATTEMPTED', again.reason)

    def test_every_state_save_in_recovery_is_checked_and_a_failed_save_never_claims_the_new_state(self):
        def to_filled(w, t): (lambda o: (setattr(o, 'state', en.OS_FILLED), setattr(o, 'position_id', 7)))(self.order(w, t))
        def to_canceled(w, t): self.order(w, t).state = en.OS_CANCELED
        def to_expired(w, t): self.order(w, t).state = en.OS_EXPIRED
        def to_hidden(w, t): w.tr.hide.add(t)
        def to_modified(w, t): self.order(w, t).sl = 1.0
        def to_identity(w, t): self.order(w, t).magic = 5
        for direction in (1, -1):
            for name, mutate in (('filled', to_filled), ('canceled', to_canceled), ('expired', to_expired), ('missing', to_hidden), ('modified', to_modified), ('identity', to_identity)):
                for fault in ('fail', 'differs'):
                    with self.subTest('%s %s dir %d' % (name, fault, direction)):
                        w, t = self.placed(direction)
                        mutate(w, t)
                        n = w.store.writes + 1
                        if fault == 'fail':
                            w.store.fail_write = {n}
                        else:
                            w.store.readback_differs = {n}
                        r = w.reconcile()
                        self.assertEqual(r.final, en.R_RECOVERY, r.reason)
                        self.assertIn('STATE_NOT_SAVED', r.reason)
                        self.assertEqual(r.state, en.ST_PLACED if fault == 'fail' else 'UNUSABLE')
                        self.assertEqual((w.tr.sends, w.tr.cancels), (1, 0))
                        if fault == 'fail':
                            self.assertEqual((w.rec().state, w.rec().generation), (en.ST_PLACED, 2))

    def test_the_recovery_scan_and_the_cancel_confirmation_also_check_their_saves(self):
        for direction in (1, -1):
            for mode in ('uncertain_created',):
                w = World(direction)
                w.tr.send_mode = mode
                w.place()
                w.store.fail_write = {w.store.writes + 1}
                r = w.reconcile()
                self.assertEqual((r.final, w.rec().state), (en.R_RECOVERY, en.ST_RECOVERY), r.reason)
                self.assertIn('STATE_NOT_SAVED', r.reason)
            w, t = self.placed(direction)
            w.store.fail_write = {w.store.writes + 2}                    # the cancel intent is saved, the CANCELLED state is not
            r = en.cancel(w.cfg, w.tr, w.store, en.Runtime(), SIGNAL, cancel_decision())
            self.assertEqual((r.final, w.tr.cancels), (en.R_CANCEL_UNCERTAIN, 1))
            self.assertEqual(w.rec().state, en.ST_CANCEL_UNCERTAIN)

    def test_time_permit_and_quote_are_rechecked_right_before_the_send(self):
        for direction in (1, -1):
            for name, setup in (('permit expires', lambda w: setattr(w.tr, 'precheck_advance', 1000)),
                                ('permit alone expires', lambda w: (setattr(w.cfg, 'quote_max_age', 5000), setattr(w.tr, 'precheck_advance', 100))),
                                ('quote goes stale', lambda w: (setattr(w.cfg, 'permit_max_age', 5000), setattr(w.tr, 'precheck_advance', 100))),
                                ('market moves to the wrong side', lambda w: setattr(w.tr, 'precheck_quote', (1989.0, 1989.3) if direction == 1 else (2012.0, 2012.3))),
                                ('expiration already passed', lambda w: (setattr(w.cfg, 'expiry_mode', en.EXP_SECONDS), setattr(w.cfg, 'expiry_seconds', 50), setattr(w.cfg, 'permit_max_age', 5000),
                                                                       setattr(w.cfg, 'quote_max_age', 5000), setattr(w.tr, 'precheck_advance', 100)))):
                with self.subTest('%s dir %d' % (name, direction)):
                    w = World(direction)
                    setup(w)
                    r = w.place()
                    self.assertEqual((r.final, r.sends, w.tr.sends, w.rt.send_calls), (en.R_REFUSED, 0, 0, 0), r.reason)
                    self.assertIn('ABORTED_BEFORE_SEND', r.reason)
                    self.assertEqual(w.rec().state, en.ST_PRECHECK_REFUSED)
                    self.assertTrue(w.clean())
                    w.permit = permit_for(w.plan, w.tr)                      # a fresh permit and quote: the record, not the clock, now blocks the signal
                    w.tr.quote = en.Quote(True, 2000.0, 2000.3, w.tr.now)
                    w.tr.precheck_advance, w.tr.precheck_quote = 0, None
                    self.assertEqual(w.place(rt=en.Runtime()).final, en.R_DUPLICATE)

    def test_a_pending_limit_needs_return_filling(self):
        for direction in (1, -1):
            for filling in (en.FILL_IOC, en.FILL_FOK):
                w = World(direction, filling=filling)
                r = w.place()
                self.assertEqual((r.final, r.sends, w.tr.sends, w.has_file(), w.store.lock_calls), (en.R_REFUSED, 0, 0, False, 0), r.reason)
                self.assertIn('FILLING_NOT_ALLOWED_FOR_PENDING', r.reason)
            self.assertEqual(World(direction, filling=en.FILL_RETURN).place().final, en.R_PLACED)
        w = World(1)
        w.place()
        rec = w.rec()
        rec.filling = en.FILL_IOC
        self.assertNotEqual(en.validate(rec), '')


class Codec(unittest.TestCase):
    def sample(self):
        w = World(1)
        w.place()
        return w.rec(), w

    def test_round_trip_and_damage(self):
        rec, w = self.sample()
        ok, text = en.encode(rec)
        self.assertTrue(ok)
        self.assertEqual(en.decode(text), (True, rec))
        self.assertFalse(en.decode(text.replace('E=1990', 'E=1991'))[0])
        self.assertFalse(en.decode(text[:-5])[0])
        self.assertFalse(en.decode('')[0])
        self.assertFalse(en.decode(text.replace('VERSION=1', 'VERSION=2'))[0])

    def test_validation_rejects_inconsistent_records(self):
        rec, w = self.sample()
        bad = (dict(state='NOPE'), dict(attempts=2), dict(linked=0), dict(order_ticket=0), dict(direction=0), dict(e=0.0), dict(s=1995.0), dict(req_id='x'), dict(magic=0), dict(filling=0),
               dict(expiry_mode=0), dict(expiration=5), dict(position_id=3), dict(snap=[rec.order_ticket]), dict(snap=[1, 1]), dict(snap=list(range(1, 40))), dict(generation=0),
               dict(state=en.ST_INTENT), dict(state=en.ST_REJECTED), dict(state=en.ST_FILLED), dict(login=0), dict(signal_id=' '), dict(t_intent=0))
        for ch in bad:
            r2 = copy.deepcopy(rec)
            for k, v in ch.items():
                setattr(r2, k, v)
            self.assertNotEqual(en.validate(r2), '', ch)

    def test_names_and_keys_are_per_signal_and_account(self):
        self.assertNotEqual(en.file_name(1, 'A'), en.file_name(2, 'A'))
        self.assertNotEqual(en.lock_key(1, 'A'), en.lock_key(1, 'B'))
        self.assertTrue(en.req_id('A').startswith('VELO_EN_') and len(en.req_id('A')) <= 31)

    def test_digest_binds_every_order_field(self):
        base = en.plan_digest(plan(1))
        for kw in (dict(e_out=1991.0), dict(s_out=1984.0), dict(tp=2001.0), dict(volume_out=0.2)):
            self.assertNotEqual(en.plan_digest(plan(1, **kw)), base)
        self.assertNotEqual(en.plan_digest(plan(1, signal='X')), base)
        self.assertNotEqual(en.plan_digest(plan(-1)), base)
        self.assertEqual(en.plan_digest(plan(1, signal='')), '')


class Mutants(unittest.TestCase):
    """each mutant changes ONE rule of the reference; the behaviour battery above must notice"""

    def _build(self, pairs):
        src = _read('tests', 'entry_reference.py')
        for old, new in pairs:
            self.assertEqual(src.count(old), 1, 'not unique / vacuous: ' + old[:60])
            src = src.replace(old, new, 1)
        ns = {'__name__': 'entry_mutant'}
        exec(compile(src, 'entry_mutant', 'exec'), ns)
        return ns

    def _run(self, ns):
        import types
        saved = {}
        for k, v in ns.items():
            if isinstance(v, types.FunctionType) and k in en.__dict__ and isinstance(en.__dict__[k], types.FunctionType):
                saved[k] = en.__dict__[k]
                en.__dict__[k] = v
        try:
            suite = unittest.TestSuite()
            for cls in (Placement, IntentAndDuplicates, Outcomes, Reconcile, Cancel, Review4de81f5):
                suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(cls))
            r = unittest.TestResult()
            suite.run(r)
            return r.failures + r.errors
        finally:
            en.__dict__.update(saved)

    def test_mutants_are_caught(self):
        cases = [
            ('permit digest not compared', [("permit.digest == '' or permit.digest != plan_digest(plan)", "permit.digest == ''")]),
            ('stale permit accepted', [("if now - permit.issued > cfg.permit_max_age:", "if False:")]),
            ('future permit accepted', [("permit.issued <= 0 or permit.issued > now", "permit.issued <= 0")]),
            ('not-allowed permit accepted', [("    if not permit.allow:\n        return 'PERMIT_NOT_ALLOWED'", "    if False:\n        return 'PERMIT_NOT_ALLOWED'")]),
            ('existing record does not block', [("        if kind != 'NONE':\n            if kind == 'BAD':", "        if False:\n            if kind == 'BAD':")]),
            ('intent read-back not checked', [("        if not ok or back != text:\n            return _res(R_BLOCKED, 'INTENT_READBACK_DIFFERS", "        if False:\n            return _res(R_BLOCKED, 'INTENT_READBACK_DIFFERS")]),
            ('pre-check ignored', [("        if not tr.pre_check(req):", "        if False:")]),
            ('lock not released by place', [("    finally:\n        store.unlock(key)\n\n\n# ------------------------------------------------------------------------------------------------ RECONCILE", "    finally:\n        pass\n\n\n# ------------------------------------------------------------------------------------------------ RECONCILE")]),
            ('uncertain answer treated as a reject', [("if sr.have_result and sr.retcode in RC_DEFINITE_REJECT and sr.order == 0:", "if True:")]),
            ('an unknown retcode counts as placed', [("sr.retcode in (RC_PLACED, RC_DONE) and sr.order > 0", "sr.retcode in (RC_PLACED, RC_DONE, 10031) and sr.order > 0")]),
            ('uncertain answer does not latch', [("        if not (sr.have_result and sr.retcode in (RC_PLACED, RC_DONE) and sr.order > 0):\n            rt.latched = True", "        if not (sr.have_result and sr.retcode in (RC_PLACED, RC_DONE) and sr.order > 0):\n            pass")]),
            ('link without the read-back of the order', [("o.found and o.ticket == sr.order and sr.order not in new.snap and tuple_matches(o, new)", "True")]),
            ('link ignores the snapshot', [("o.found and o.ticket == sr.order and sr.order not in new.snap and", "o.found and o.ticket == sr.order and")]),
            ('link by comment, magic and volume only', [("return (o.found and o.symbol == rec.symbol and o.type == _otype(rec.direction) and _close(o.price, rec.e) and _close(o.sl, rec.s) and _close(o.tp, rec.tp)\n            and _close(o.volume, rec.volume) and o.magic == rec.magic and (rec.expiry_mode == EXP_GTC or o.expiration == rec.expiration))",
                                                        "return o.found and o.comment == rec.req_id and o.magic == rec.magic and _close(o.volume, rec.volume)")]),
            ('recovery scan ignores the snapshot', [("cands = [o for o in lst.orders if o.ticket not in rec.snap and ", "cands = [o for o in lst.orders if ")]),
            ('recovery scan ignores the time', [("and o.time_setup >= rec.t_intent - TIME_TOL and tuple_matches(o, rec)]", "and tuple_matches(o, rec)]")]),
            ('ambiguous candidates are chosen', [("    if len(cands) > 1:\n        return _transition(store, rec, R_BLOCKED, 'AMBIGUOUS_CANDIDATES", "    if False:\n        return _transition(store, rec, R_BLOCKED, 'AMBIGUOUS_CANDIDATES")]),
            ('reconcile resends', [("    lst = tr.list_orders(rec.symbol, rec.t_intent - TIME_TOL)\n    if not lst.complete:", "    tr.send(None)\n    lst = tr.list_orders(rec.symbol, rec.t_intent - TIME_TOL)\n    if not lst.complete:")]),
            ('a modified order is accepted in reconcile', [("            if not tuple_matches(o, rec):\n                return _transition(store, rec, R_BLOCKED, 'ORDER_MODIFIED", "            if False:\n                return _transition(store, rec, R_BLOCKED, 'ORDER_MODIFIED")]),
            ('filled without a position id is trusted', [("if o.position_id <= 0 or not tuple_matches(o, rec):", "if False:")]),
            ('cancel without the tuple proof', [("o.state == OS_ACTIVE and tuple_matches(o, rec) and o.magic == cfg.ea_magic):", "o.state == OS_ACTIVE and o.magic == cfg.ea_magic):")]),
            ('cancel of a non placed record', [("        if rec.state != ST_PLACED or rec.linked != 1:\n            return _res(R_REFUSED, 'NOT_A_PROVEN_PENDING_ORDER", "        if False:\n            return _res(R_REFUSED, 'NOT_A_PROVEN_PENDING_ORDER")]),
            ('cancel decision not checked', [("    if decision.status != tp.CANCEL_REQUEST or not decision.cancel_pending or decision.pending_signal_id != signal_id:", "    if False:")]),
            ('cancel intent not saved first', [("        ok, r2 = _save(store, rec, state=ST_CANCEL_UNCERTAIN, cancel_attempts=1, reason='CANCEL_INTENT')\n        if not ok:", "        ok, r2 = True, rec\n        if not ok:")]),
            ('cancel confirmed without the read-back', [("            if o2.found and o2.ticket == rec.order_ticket and o2.state == OS_CANCELED:", "            if True:")]),
            ('stored cancel attempt ignored', [("        if rec.cancel_attempts >= 1:\n            return _res(R_REFUSED, 'CANCEL_ALREADY_ATTEMPTED", "        if False:\n            return _res(R_REFUSED, 'CANCEL_ALREADY_ATTEMPTED")]),
            ('a failed state save is reported as success', [("    ok, r2 = _save(store, rec, **chg)\n    if ok:\n        return _res(final, msg, 0, r2.state, ticket, pos)", "    ok, r2 = _save(store, rec, **chg)\n    if True:\n        return _res(final, msg, 0, chg.get('state', ''), ticket, pos)")]),
            ('no permit re-check before the send', [("        if not bad:\n            bad = permit_refusal(cfg, plan, permit, now2)\n", "")]),
            ('no quote re-check before the send', [("            bad = market_refusal(cfg, plan, sym, tr.read_quote(cfg.symbol), now2)", "            bad = ''")]),
            ('no expiration re-check before the send', [("if not bad and cfg.expiry_mode == EXP_SECONDS and exp <= now2:", "if False:")]),
            ('IOC accepted for a pending order', [("    if cfg.filling != FILL_RETURN:\n        return 'FILLING_NOT_ALLOWED_FOR_PENDING", "    if False:\n        return 'FILLING_NOT_ALLOWED_FOR_PENDING")]),
            ('unset permit age does not block', [("    if cfg.permit_max_age <= 0:\n        return 'INPUT_UNSET: permit_max_age'", "    if False:\n        return 'INPUT_UNSET: permit_max_age'")]),
            ('unset expiry does not block', [("    if cfg.expiry_mode not in (EXP_GTC, EXP_SECONDS):\n        return 'INPUT_UNSET: expiry_mode'", "    if False:\n        return 'INPUT_UNSET: expiry_mode'")]),
            ('stale quote accepted', [("or now - quote.time > cfg.quote_max_age:", "or False:")]),
            ('wrong side of the market accepted', [("    if plan.direction == 1 and not plan.e_out <= quote.ask - gap:", "    if False:")]),
            ('real transport without authorisation', [("        if not (cfg.real_authorised and cfg.authorisation == AUTH_PHRASE):", "        if False:")]),
            ('incomplete order list accepted', [("        if not lst.complete:\n            return _res(R_REFUSED, 'ORDER_LIST_INCOMPLETE: the existing orders cannot be proven')", "        if False:\n            return _res(R_REFUSED, 'ORDER_LIST_INCOMPLETE: the existing orders cannot be proven')")]),
        ]
        for name, pairs in cases:
            with self.subTest(name):
                ns = self._build(pairs)
                try:
                    bad = self._run(ns)
                except Exception:
                    bad = ['exception']
                self.assertTrue(bad, 'mutant not caught: ' + name)


SCENARIOS = [
    'buy_limit_placed', 'sell_limit_placed', 'unset_inputs_block', 'plan_refusals', 'permit_binding', 'terminal_reads', 'lock_failure', 'intent_failures', 'precheck_refusal',
    'duplicates', 'definite_reject', 'uncertain_answer', 'unproven_link', 'recovery_by_tuple', 'comment_magic_volume_not_proof', 'ambiguous_candidates', 'reconcile_states',
    'cancel_proven_only', 'cancel_uncertain', 'codec',
    'review_cancel_attempt_survives_restart', 'review_state_saves_checked', 'review_recheck_before_send', 'review_pending_needs_return_filling',
]


class Sources(unittest.TestCase):
    def strip(self, t):
        return re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))

    def test_the_mql_test_names_the_same_scenarios(self):
        src = _read('src', 'tests', 'EntryExecutorTest.mq5')
        names = re.findall(r'^void Scenario_(\w+)\(', src, re.M)
        self.assertEqual(names, SCENARIOS)
        for n in SCENARIOS:
            self.assertEqual(len(re.findall(r'Scenario_%s\(\);' % n, src)), 1, n)

    def test_the_python_reference_orders_the_steps(self):
        src = self.strip(_read('tests', 'entry_reference.py'))
        place = src[src.index('def place('):src.index('# ----', src.index('def place('))]
        order = ['config_unset(cfg)', 'plan_refusal(plan)', 'permit_refusal(', 'store.lock(key)', "_load(store, name)", 'market_refusal(', 'list_orders(', 'store.write(name, text)', 'store.read(name)',
                 'tr.pre_check(req)', 'rt.send_calls += 1', 'tr.send(req)', 'tr.read_order(sr.order)']
        pos = [place.index(o) for o in order]
        self.assertEqual(pos, sorted(pos))
        self.assertEqual(place.count('tr.send('), 1)
        self.assertGreater(place.rindex('permit_refusal('), place.index('tr.pre_check(req)'))
        self.assertLess(place.rindex('permit_refusal('), place.index('tr.send(req)'))
        self.assertGreater(place.rindex('market_refusal('), place.index('tr.pre_check(req)'))
        self.assertLess(place.rindex('market_refusal('), place.index('tr.send(req)'))
        rec = src[src.index('def reconcile('):src.index('# ----', src.index('def reconcile('))]
        self.assertNotIn('tr.send(', rec)
        self.assertNotIn('tr.cancel(', rec)
        self.assertEqual(src.count('tr.cancel('), 1)


if __name__ == '__main__':
    unittest.main()
