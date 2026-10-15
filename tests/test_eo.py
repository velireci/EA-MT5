"""T016 orchestrator-core tests (FAKE transport and store only): the T004 observer state -> SetupPlanBridge -> EntryGate -> EntryExecutor chain, BUY and SELL up to a FAKE request; blocks without a request;
baseline: replay, restart, data defect and context change never create a signal; real data only (missing = block); the effective tick value comes from the broker probe; an uncertain outcome halts."""
import copy
import os
import re
import sys
import unittest
from dataclasses import replace

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import entry_gate_reference as eg  # noqa: E402
import entry_reference as en  # noqa: E402
import eo_reference as eo  # noqa: E402
import spb_reference as sp  # noqa: E402
import t004_reference as m4  # noqa: E402
import t007_planning_reference as tp  # noqa: E402
import t012_bridge_reference as br  # noqa: E402
import test_spb as ts  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
START = ts.START


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def observer_n(direction, nbars, ctx_changes=None):
    """the real T004 reference observer fed with the first nbars closed bars of the standard setup"""
    o = m4.Observer(m4.A_AT_OR_AFTER_BREAK)
    o.set_context(ts.context(direction, **(ctx_changes or {})), START)
    if direction == -1:
        rows, lvl = ((101, 95, 96), (96, 89, 90), (93, 87, 88)), m4.Level('L-SELL', 98.0, START)
    else:
        rows, lvl = ((100, 94, 99), (104, 98, 103), (108, 102, 107)), m4.Level('L-BUY', 98.0, START)
    for i, (h, lo, c) in enumerate(rows[:nbars]):
        b = ts.bar(i, h, lo, c)
        o.step(b, b.time + 900, lvl if i == 0 else None)
    return o, lvl


class FakeMarket:
    def __init__(self, tr, direction):
        self.tr = tr
        self.dir = direction
        self.sym = eo.Sym(True, 0.01, 2, 0.01, 0, 0.01, 0.01, 100.0, 2.0, True)         # the REPORTED tick value (2.0) differs from the broker's effective one (1.0)
        self.eff_tick = 1.0
        self.q = eo.Quote(True, 108.0 if direction == 1 else 90.0, 108.3 if direction == 1 else 90.3, tr.now)
        self.calls = 0
        self.fail_call = 0
        self.session, self.news, self.spread = tp.SESSION_OPEN, tp.NEWS_CLEAR, tp.SPREAD_CLEAR
        self.daily_result = (True, br.Result(entry_allowed=True, primary='', dl_called=True))
        self.bal = eo.Balance(True, 10000.0, tr.now, True)           # the CURRENT balance of a DEMO account
        self.balance_calls = 0

    def balance(self):
        self.balance_calls += 1
        return self.bal

    def now(self):
        return self.tr.now

    def symbol(self):
        return self.sym

    def quote(self):
        return self.q

    def calc_profit(self, buy, volume, e, s):
        self.calls += 1
        if self.fail_call and self.calls == self.fail_call:
            return False, 0.0
        return True, -volume * round(abs(e - s) / self.sym.tick_size) * self.eff_tick

    def filters(self):
        return self.session, self.news, self.spread

    def daily(self, r):
        return self.daily_result


class World:
    def __init__(self, direction):
        self.dir = direction
        self.tr = en.FakeTransport()
        self.tr.quote = en.Quote(True, 108.0 if direction == 1 else 90.0, 108.3 if direction == 1 else 90.3, self.tr.now)
        self.store = en.FakeStore()
        self.mk = FakeMarket(self.tr, direction)
        self.o = eo.Orchestrator()
        self.cfg = eo.Config(sel=ts.selection(), risk_budget=100.0, lot_cap=10.0, model_tolerance=0.01, max_quote_age=30, open_positions=0, trades_today=0, existing_risk=0.0,
                             max_positions=2, max_trades=3, risk_cap=1000.0, gate=eg.GateConfig(max_age=60),
                             exec=en.Config(enabled=True, ea_magic=777, symbol='XAUUSD', filling=en.FILL_RETURN, expiry_mode=en.EXP_GTC, permit_max_age=60, quote_max_age=30))

    def step(self, ob, lvl, feed_ok=True, orch=None, pre_send=None):
        return (orch or self.o).step(self.cfg, self.mk, feed_ok, ob, lvl, ob.last_asof if ob is not None else 0, self.tr, self.store, pre_send)

    def untouched(self, tc):
        tc.assertEqual((self.tr.sends, self.store.lock_calls, self.store.writes, len(self.store.files)), (0, 0, 0, 0))

    def live_candidate(self, tc):
        """early build (baseline), then the build in which the FVG candidate is confirmed: the first real signal"""
        o1, l1 = observer_n(self.dir, 2)
        self.step(o1, l1)                                                      # the baseline is set by whatever the first build gives
        o2, l2 = observer_n(self.dir, 3)
        return o2, l2, self.step(o2, l2)


class TimerMarketRetry(unittest.TestCase):
    def test_cached_feed_quote_recovery_keeps_history_blocked(self):
        for d in (1, -1):
            w = World(d)
            before, level = observer_n(d, 2)
            w.step(before, level)
            after, level = observer_n(d, 3)
            w.mk.q = replace(w.mk.q, time=w.tr.now - 31)
            self.assertEqual(w.step(after, level).status, 'MARKET_NOT_READY')
            w.mk.q = replace(w.mk.q, time=w.tr.now)
            recovered = w.step(after, level)
            self.assertEqual(recovered.status, 'NO_PLAN')
            self.assertTrue(recovered.reason.startswith('HISTORICAL'), recovered.reason)
            self.assertEqual(w.o.baseline, after.last_asof)
            w.untouched(self)

    def test_cached_feed_gate_recheck_sends_once_and_not_on_feed_failure(self):
        for d in (1, -1):
            w = World(d)
            before, level = observer_n(d, 2)
            w.step(before, level)
            after, level = observer_n(d, 3)
            w.mk.spread = tp.SPREAD_BLOCKED
            self.assertEqual(w.step(after, level).status, 'GATE_BLOCKED')
            self.assertEqual(w.tr.sends, 0)
            w.mk.spread = tp.SPREAD_CLEAR
            self.assertTrue(w.step(after, level).request)
            for _ in range(3):
                self.assertEqual(w.step(after, level).status, 'ALREADY_HANDLED')
            self.assertEqual(w.tr.sends, 1)
            self.assertEqual(w.step(after, level, feed_ok=False).status, 'FEED_NOT_OK')
            self.assertEqual(w.tr.sends, 1)

class Chain(unittest.TestCase):
    def test_buy_and_sell_reach_one_fake_request_equal_to_the_plan(self):
        for d in (1, -1):
            w = World(d)
            ob, lvl, out = w.live_candidate(self)
            self.assertEqual((out.status, out.request, out.result.final), ('EXECUTOR', True, en.R_PLACED), out.reason)
            self.assertEqual(w.o.baseline, observer_n(d, 2)[0].last_asof)
            self.assertEqual(out.label, eo.FAKE_LABEL)
            q = w.tr.requests[0]
            p = eg.entry_plan(out.spb.plan)
            self.assertEqual((w.tr.sends, q.type, q.price, q.sl, q.tp, q.volume), (1, en.TYPE_BUY_LIMIT if d == 1 else en.TYPE_SELL_LIMIT, p.e_out, p.s_out, p.tp, p.volume_out))
            self.assertEqual(out.decision.permit.digest, en.plan_digest(p))
            self.assertEqual(w.o.signals, 1)
            self.assertEqual(w.o.baseline, ts.asof_of(observer_n(d, 2)[0]) - 900)

    def test_the_probe_tick_value_not_the_reported_one_sizes_the_plan(self):
        for d in (1, -1):
            w = World(d)
            ob, lvl, out = w.live_candidate(self)
            pl = out.spb.plan
            ticks = round(pl.r_geom / 0.01)
            direct = tp.build_plan(out.spb.signal_id, out.spb.setup_id, pl.direction, pl.e_out, pl.s_out, None, 100.0, 1.0, 0.01, 2, 0.01, 0,
                                   w.mk.q.bid, w.mk.q.ask, 0.01, 0.01, 100.0, 10.0)
            self.assertEqual(pl, direct)                                       # sized with the effective tick value 1.0
            reported = tp.build_plan(out.spb.signal_id, out.spb.setup_id, pl.direction, pl.e_out, pl.s_out, None, 100.0, 2.0, 0.01, 2, 0.01, 0,
                                     w.mk.q.bid, w.mk.q.ask, 0.01, 0.01, 100.0, 10.0)
            self.assertNotEqual(pl.volume_out, reported.volume_out)
            self.assertEqual(w.mk.calls, 2)                                    # the probe and the loss estimate
            self.assertGreater(ticks, 0)

    def test_a_probe_that_fails_blocks_without_a_property_fallback(self):
        for d in (1, -1):
            w = World(d)
            w.mk.fail_call = 1
            ob, lvl, out = w.live_candidate(self)
            self.assertEqual((out.status, out.request), ('PROBE_FAILED', False))
            w.untouched(self)


class Baseline(unittest.TestCase):
    def test_the_replay_at_start_is_never_a_signal(self):
        for d in (1, -1):
            w = World(d)
            ob, lvl = observer_n(d, 3)                                          # the candidate already exists when the EA starts
            out = w.step(ob, lvl)
            self.assertEqual(out.status, 'NO_PLAN')
            self.assertTrue(out.reason.startswith('HISTORICAL_OR_REPLAYED_CANDIDATE'), out.reason)
            w.untouched(self)
            self.assertEqual(w.o.baseline, ob.last_asof)

    def test_a_restart_never_sends_the_same_signal_again(self):
        for d in (1, -1):
            w = World(d)
            ob, lvl, out = w.live_candidate(self)
            self.assertTrue(out.request)
            again = w.step(ob, lvl)                                              # the same build repeated
            self.assertEqual((again.status, w.tr.sends), ('ALREADY_HANDLED', 1))
            fresh = eo.Orchestrator()                                            # a restart: new baseline, same durable store
            r = w.step(ob, lvl, orch=fresh)
            self.assertEqual((r.status, w.tr.sends), ('NO_PLAN', 1))
            self.assertTrue(r.reason.startswith('HISTORICAL'))
            forced = eo.Orchestrator()                                           # even a layer that lost its baseline cannot send twice: the executor record blocks
            forced.baseline, forced.rebase = 1, False
            forced.key = copy.deepcopy(ob.context)
            r2 = w.step(ob, lvl, orch=forced)
            self.assertEqual((r2.result.final, w.tr.sends), (en.R_DUPLICATE, 1))

    def test_a_data_defect_does_not_revive_a_candidate_formed_during_the_outage(self):
        for d in (1, -1):
            w = World(d)
            o1, l1 = observer_n(d, 2)
            w.step(o1, l1)
            lost = w.step(None, None, feed_ok=False)
            self.assertEqual(lost.status, 'FEED_NOT_OK')
            o2, l2 = observer_n(d, 3)                                           # the candidate was confirmed while the data was missing
            out = w.step(o2, l2)
            self.assertEqual(out.status, 'NO_PLAN')
            self.assertTrue(out.reason.startswith('HISTORICAL'), out.reason)
            w.untouched(self)

    def test_losing_or_changing_the_context_restarts_the_baseline(self):
        for d in (1, -1):
            w = World(d)
            o1, l1 = observer_n(d, 2)
            w.step(o1, l1)
            o2, l2 = observer_n(d, 3, ctx_changes=dict(setup='H4SET2'))          # another setup: its candidate is not a live signal of the old baseline
            out = w.step(o2, l2)
            self.assertEqual(out.status, 'NO_PLAN')
            self.assertTrue(out.reason.startswith('HISTORICAL'), out.reason)
            w.untouched(self)
            o3, l3 = observer_n(d, 3)
            o3.set_context(ts.context(d, ready=False), o3.last_asof + 900)       # the context is lost
            self.assertEqual(w.step(o3, l3).status, 'NO_PLAN')
            self.assertTrue(w.o.rebase is False and w.o.key == '')
            o4, l4 = observer_n(d, 3)
            self.assertTrue(w.step(o4, l4).reason.startswith('HISTORICAL'))
            w.untouched(self)

    def test_the_baseline_never_moves_backwards(self):
        w = World(1)
        o1, l1 = observer_n(1, 3)
        w.step(o1, l1)
        high = w.o.baseline
        w.o.defect()
        o0, l0 = observer_n(1, 2)
        w.step(o0, l0)
        self.assertEqual(w.o.baseline, high)


class Blocks(unittest.TestCase):
    def test_every_unset_input_blocks_without_a_request(self):
        for d in (1, -1):
            for name, kw, frag in (('risk', dict(risk_budget=-1.0), 'risk_budget'), ('lot cap', dict(lot_cap=0.0), 'lot_cap'), ('tolerance', dict(model_tolerance=-1.0), 'model_tolerance'),
                                   ('quote age', dict(max_quote_age=0), 'max_quote_age')):
                with self.subTest('%s %d' % (name, d)):
                    w = World(d)
                    w.cfg = replace(w.cfg, **kw)
                    ob, lvl, out = w.live_candidate(self)
                    self.assertEqual(out.status, 'CONFIG_UNSET')
                    self.assertIn(frag, out.reason)
                    w.untouched(self)
            w = World(d)
            w.cfg = replace(w.cfg, sel=sp.Selection())                          # the default T014 selection is all UNSET
            ob, lvl, out = w.live_candidate(self)
            self.assertEqual(out.status, 'NO_PLAN')
            self.assertTrue(out.reason.startswith('SELECTION_UNSET'))
            w.untouched(self)

    def test_missing_market_data_is_never_zero_or_clear(self):
        changes = (('symbol unreadable', lambda m: setattr(m.sym, 'read_ok', False), 'MARKET_NOT_READY'),
                   ('symbol not tradable', lambda m: setattr(m.sym, 'trade_ok', False), 'MARKET_NOT_READY'),
                   ('quote missing', lambda m: setattr(m.q, 'read_ok', False), 'MARKET_NOT_READY'),
                   ('quote stale', lambda m: setattr(m.q, 'time', m.tr.now - 31), 'MARKET_NOT_READY'),
                   ('quote in the future', lambda m: setattr(m.q, 'time', m.tr.now + 5), 'MARKET_NOT_READY'),
                   ('loss estimate fails', lambda m: setattr(m, 'fail_call', 2), 'GATE_BLOCKED'),
                   ('session unknown', lambda m: setattr(m, 'session', tp.SESSION_UNKNOWN), 'GATE_BLOCKED'),
                   ('news unknown', lambda m: setattr(m, 'news', tp.NEWS_UNKNOWN), 'GATE_BLOCKED'),
                   ('spread unknown', lambda m: setattr(m, 'spread', tp.SPREAD_UNKNOWN), 'GATE_BLOCKED'),
                   ('daily not evaluated', lambda m: setattr(m, 'daily_result', (False, None)), 'GATE_BLOCKED'),
                   ('daily blocks', lambda m: setattr(m, 'daily_result', (True, br.Result(entry_allowed=False, primary='DAILY_LOSS_LIMIT', dl_called=True))), 'GATE_BLOCKED'))
        for d in (1, -1):
            for name, change, status in changes:
                with self.subTest('%s %d' % (name, d)):
                    w = World(d)
                    change(w.mk)
                    ob, lvl, out = w.live_candidate(self)
                    self.assertEqual((out.status, out.request), (status, False), out.reason)
                    w.untouched(self)

    def test_exposure_counters_and_limits_that_nothing_proves_stay_unknown_and_block(self):
        for d in (1, -1):
            for name, kw, frag in (('positions unknown', dict(open_positions=-1), 'INVALID_SNAPSHOT:open_positions'), ('trades unknown', dict(trades_today=-1), 'INVALID_SNAPSHOT:trades_today'),
                                   ('risk unknown', dict(existing_risk=-1.0), 'INVALID_SNAPSHOT:existing_risk'), ('max positions unset', dict(max_positions=-1), 'POLICY_UNSET:max_positions'),
                                   ('max trades unset', dict(max_trades=-1), 'POLICY_UNSET:max_trades_per_day'), ('risk cap unset', dict(risk_cap=-1.0), 'POLICY_UNSET:combined_risk_cap'),
                                   ('positions at the limit', dict(open_positions=2), 'MAX_POSITIONS_REACHED')):
                with self.subTest('%s %d' % (name, d)):
                    w = World(d)
                    w.cfg = replace(w.cfg, **kw)
                    ob, lvl, out = w.live_candidate(self)
                    self.assertEqual((out.status, out.request), ('GATE_BLOCKED', False))
                    self.assertIn(frag, ' | '.join(out.decision.reasons))
                    w.untouched(self)

    def test_a_blocked_attempt_is_retried_at_the_next_build_and_places_once(self):
        w = World(-1)
        w.mk.session = tp.SESSION_CLOSED
        o1, l1 = observer_n(-1, 2)
        w.step(o1, l1)
        o2, l2 = observer_n(-1, 3)
        self.assertEqual(w.step(o2, l2).status, 'GATE_BLOCKED')
        w.untouched(self)
        w.mk.session = tp.SESSION_OPEN
        out = w.step(o2, l2)
        self.assertTrue(out.request)
        self.assertEqual(w.tr.sends, 1)

    def test_an_uncertain_outcome_halts_the_layer_until_restart(self):
        for d in (1, -1):
            w = World(d)
            w.tr.send_mode = 'uncertain_not_created'
            ob, lvl, out = w.live_candidate(self)
            self.assertEqual((out.result.final, out.request, w.tr.sends), (en.R_RECOVERY, False, 1))
            self.assertTrue(w.o.halted)
            nxt = w.step(ob, lvl)
            self.assertEqual((nxt.status, w.tr.sends), ('HALTED', 1))


class RiskFromBalance(unittest.TestCase):
    """DEMO policy (owner agreement 2026-10-15, D2 stays a client question before live): risk budget = 1% of the CURRENT account balance, read at every step. A failed / invalid / stale /
    non-demo read blocks with no fallback. The budget that sizes the plan is the budget the loss check uses (one value, one instant). The daily-limit base is not touched here."""

    def world(self, d, balance=10000.0, **cfg):
        w = World(d)
        w.cfg.risk_source = eo.RISK_SOURCE_DEMO_BALANCE_PCT
        w.cfg.risk_budget = -1.0                              # the explicit amount is NOT the fallback
        w.mk.bal = eo.Balance(True, balance, w.tr.now, True)
        for k, v in cfg.items():
            setattr(w.cfg, k, v)
        return w

    def test_one_percent_of_the_current_balance_sizes_the_plan_and_the_loss_check(self):
        for d in (1, -1):
            w = self.world(d, 10000.0)
            ob, lvl, out = w.live_candidate(self)
            self.assertEqual((out.status, out.request, out.risk_budget, out.risk_base), ('EXECUTOR', True, 100.0, 10000.0), out.reason)
            ref = World(d)                                                      # the same world with the explicit amount 100 gives the identical plan
            ob2, lvl2, ref_out = ref.live_candidate(self)
            self.assertEqual(out.spb.plan, ref_out.spb.plan)
            half = self.world(d, 5000.0)                                         # the balance follows the account: half the balance, half the budget
            ob3, lvl3, out3 = half.live_candidate(self)
            self.assertEqual((out3.request, out3.risk_budget), (True, 50.0), out3.reason)
            self.assertLessEqual(out3.spb.plan.risk_model, 50.0)
            self.assertLess(out3.spb.plan.volume_out, out.spb.plan.volume_out)
            self.assertEqual(out.decision.permit.digest, en.plan_digest(eg.entry_plan(out.spb.plan)))

    def test_the_balance_is_read_at_every_step_and_not_cached(self):
        w = self.world(1, 10000.0)
        o1, l1 = observer_n(1, 2)
        w.step(o1, l1)
        w.step(o1, l1)
        self.assertEqual(w.mk.balance_calls, 2)

    def test_an_unreadable_invalid_stale_or_non_demo_base_blocks_with_no_fallback(self):
        bad = [('unreadable', eo.Balance(False, 10000.0, 0, True)), ('zero', eo.Balance(True, 0.0, 0, True)), ('negative', eo.Balance(True, -5.0, 0, True)),
               ('nan', eo.Balance(True, float('nan'), 0, True)), ('inf', eo.Balance(True, float('inf'), 0, True)), ('not demo', eo.Balance(True, 10000.0, 0, False)),
               ('stale', eo.Balance(True, 10000.0, -1000, True))]
        for d in (1, -1):
            for label, b in bad:
                w = self.world(d)
                w.cfg.risk_budget = 100.0                                         # an explicit amount exists: it must NOT be used as a fallback
                w.mk.bal = eo.Balance(b.read_ok, b.amount, w.tr.now + (b.time if label == 'stale' else 0), b.demo)
                ob, lvl, out = w.live_candidate(self)
                self.assertEqual((out.status, out.request), ('RISK_BASE_NOT_READY', False), '%s dir %d: %s' % (label, d, out.reason))
                w.untouched(self)

    def test_an_unknown_source_value_is_unset(self):
        for d in (1, -1):
            w = self.world(d)
            w.cfg.risk_source = 7
            ob, lvl, out = w.live_candidate(self)
            self.assertEqual(out.status, 'CONFIG_UNSET')
            self.assertIn('risk_source', out.reason)
            w.untouched(self)

    def test_the_explicit_amount_source_ignores_the_balance(self):
        for d in (1, -1):
            w = World(d)
            w.mk.bal = eo.Balance(False, 0.0, 0, False)
            ob, lvl, out = w.live_candidate(self)
            self.assertEqual((out.status, out.request, w.mk.balance_calls), ('EXECUTOR', True, 0))

    def test_a_balance_outage_does_not_revive_a_signal_formed_during_it(self):
        for d in (1, -1):
            w = self.world(d)
            o1, l1 = observer_n(d, 2)
            w.step(o1, l1)
            w.mk.bal = eo.Balance(False, 0.0, 0, True)
            o2, l2 = observer_n(d, 3)
            self.assertEqual(w.step(o2, l2).status, 'RISK_BASE_NOT_READY')
            w.mk.bal = eo.Balance(True, 10000.0, w.tr.now, True)
            out = w.step(o2, l2)
            self.assertEqual(out.status, 'NO_PLAN')
            self.assertTrue(out.reason.startswith('HISTORICAL'), out.reason)
            w.untouched(self)


SCENARIOS = ['buy_to_fake_request', 'sell_to_fake_request', 'replay_baseline_no_signal', 'restart_no_double', 'defect_rebases', 'context_change_rebases', 'unset_inputs_block',
             'market_missing_blocks', 'gate_blocks_no_request', 'probe_uses_effective_tick', 'halt_after_uncertainty',
             'market_recovery_rebases', 'context_fields_rebase', 'probe_independent_of_property', 'reservation_before_every_send', 'risk_budget_from_current_balance', 'risk_base_failure_blocks', 'cached_feed_market_recheck']


class Reservation(unittest.TestCase):
    """T019 review: the pre-send hook of the gate is wired through the orchestrator; a refusal places nothing and the signal is retried at the next build"""

    class Hook:
        def __init__(self, w, ok=True):
            self.w, self.ok, self.calls, self.at, self.settled_n = w, ok, 0, None, 0

        def reserve(self, signal_id):
            self.calls += 1
            self.at = (self.w.tr.sends, self.w.store.writes, self.w.store.lock_calls, len(self.w.store.files))
            return self.ok, '' if self.ok else 'INDEX_NOT_SAVED'

        def settled(self, signal_id, res):
            self.settled_n += 1

    def test_a_refused_reservation_places_nothing_and_the_signal_is_retried(self):
        for d in (1, -1):
            w = World(d)
            h = self.Hook(w, ok=False)
            o1, l1 = observer_n(d, 2)
            w.step(o1, l1, pre_send=h)
            o2, l2 = observer_n(d, 3)
            out = w.step(o2, l2, pre_send=h)
            self.assertEqual((out.status, out.request, h.calls, h.at), ('RESERVATION_FAILED', False, 1, (0, 0, 0, 0)))
            w.untouched(self)
            self.assertNotIn(out.spb.signal_id, w.o.handled)
            h.ok = True
            out2 = w.step(o2, l2, pre_send=h)
            self.assertEqual((out2.request, w.tr.sends, h.settled_n), (True, 1, 1))

    def test_a_gate_block_never_reaches_the_hook(self):
        for d in (1, -1):
            w = World(d)
            w.mk.session = tp.SESSION_CLOSED
            h = self.Hook(w)
            o1, l1 = observer_n(d, 2)
            w.step(o1, l1, pre_send=h)
            o2, l2 = observer_n(d, 3)
            out = w.step(o2, l2, pre_send=h)
            self.assertEqual((out.status, h.calls, h.settled_n), ('GATE_BLOCKED', 0, 0))
            w.untouched(self)


class ReviewRegressions(unittest.TestCase):
    def test_market_data_recovery_does_not_revive_the_candidate(self):
        for d in (1, -1):
            for kind in ('symbol', 'quote'):
                with self.subTest(direction=d, kind=kind):
                    w = World(d)
                    ob, lvl = observer_n(d, 2)
                    w.step(ob, lvl)
                    ob, lvl = observer_n(d, 3)
                    source = w.mk.sym if kind == 'symbol' else w.mk.q
                    source.read_ok = False
                    self.assertFalse(w.step(ob, lvl).request)
                    source.read_ok = True
                    recovered = w.step(ob, lvl)
                    self.assertFalse(recovered.request)
                    self.assertEqual(w.tr.sends, 0)
                    self.assertEqual(w.o.baseline, ob.last_asof)

    def test_changed_context_fields_rebase_even_when_ids_are_unchanged(self):
        for d in (1, -1):
            for change in ({'lower': 81}, {'upper': 119}, {'confirmed': START-1}, {'confirmed': START-1, 'valid_from': START-1}):
                with self.subTest(direction=d, change=change):
                    w = World(d)
                    ob, lvl = observer_n(d, 2)
                    w.step(ob, lvl)
                    ob, lvl = observer_n(d, 3, change)
                    result = w.step(ob, lvl)
                    self.assertFalse(result.request)
                    self.assertEqual(w.tr.sends, 0)
                    self.assertEqual(w.o.baseline, ob.last_asof)

    def test_broker_probe_precedes_sizing_with_an_unreliable_property(self):
        for d in (1, -1):
            for reported in (0.0, 0.000001, 1e9):
                with self.subTest(direction=d, reported=reported):
                    w = World(d)
                    w.mk.sym.reported_tick_value = reported
                    ob, lvl = observer_n(d, 2)
                    w.step(ob, lvl)
                    ob, lvl = observer_n(d, 3)
                    result = w.step(ob, lvl)
                    self.assertTrue(result.request, result.reason)
                    self.assertEqual(w.mk.calls, 2)
                    self.assertEqual(result.spb.plan.volume_out, 0.22 if d == 1 else 0.18)


class Sources(unittest.TestCase):
    def test_ea_timer_rechecks_market_even_without_a_feed_rebuild(self):
        ea = self.strip(_read('src', 'XauUsdEntryOrchestrator.mq5'))
        poll = ea[ea.index('void Poll()'):ea.index('int OnInit()')]
        before_step = poll[:poll.index('g_orch.Step(')]
        self.assertIn('g_feed.Poll(feed_ok);', before_step)
        self.assertNotIn('return;', before_step)
        self.assertEqual(poll.count('g_feed.Poll('), 1)
        self.assertEqual(poll.count('g_orch.Step('), 1)
        feed = self.strip(_read('src', 'include', 'EntryOrchestratorFeed.mqh'))
        self.assertIn('if(!M4TimelineNeedsBuild(false,built,at,cut,hc,mc)) {feed_ok=built; return(false);}', feed)

    def strip(self, t):
        return re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))

    def test_the_mql_test_names_the_same_scenarios(self):
        tst = _read('src', 'tests', 'EntryOrchestratorTest.mq5')
        names = re.findall(r'^void Scenario_(\w+)\(', tst, re.M)
        self.assertEqual(names, SCENARIOS)
        for n in SCENARIOS:
            self.assertEqual(len(re.findall(r'Scenario_%s\(\);' % n, tst)), 1, n)

    def test_the_python_core_calls_the_existing_modules_and_copies_none_of_their_rules(self):
        src = self.strip(_read('tests', 'eo_reference.py'))
        for call in ('sp.build(', 'bl.probe_tick_value(', 'eg.submit(', 'en.plan_digest('):
            self.assertIn(call, src)
        for w in ('tp.check_permit', 'tp.authorize', 'build_plan', 'g5.compute', 'p6.size', 'en.place(', 'DG_FinalPreview'):
            self.assertNotIn(w, src, w)


class Mutants(unittest.TestCase):
    def _run(self, pairs):
        src = _read('tests', 'eo_reference.py')
        for old, new in pairs:
            self.assertEqual(src.count(old), 1, 'not unique / vacuous: ' + old[:70])
            src = src.replace(old, new, 1)
        ns = {'__name__': 'eo_mutant'}
        exec(compile(src, 'eo_mutant', 'exec'), ns)
        saved = eo.Orchestrator
        eo.Orchestrator = ns['Orchestrator']
        try:
            suite = unittest.TestSuite()
            for cls in (Chain, Baseline, Blocks, ReviewRegressions, RiskFromBalance):
                suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(cls))
            r = unittest.TestResult()
            suite.run(r)
            return r.failures + r.errors
        finally:
            eo.Orchestrator = saved

    def test_mutants_are_caught(self):
        cases = [
            ('no baseline: live_after stays 0 for the first build', [("        if self.rebase or self.baseline == 0:\n            self.baseline = max(self.baseline, cut)\n            self.rebase = False", "        if self.rebase or self.baseline == 0:\n            self.baseline = 1\n            self.rebase = False")]),
            ('a defect does not restart the baseline', [("        if not feed_ok or ob is None:\n            self.defect()\n", "        if not feed_ok or ob is None:\n")]),
            ('a changed context does not restart the baseline', [("        if key == '' or key != self.key:", "        if key == '':")]),
            ('the baseline moves backwards', [("            self.baseline = max(self.baseline, cut)", "            self.baseline = cut")]),
            ('the balance is not demo-checked', [("b.read_ok and b.demo and _finite", "b.read_ok and _finite")]),
            ('a stale balance is accepted', [(" and 0 <= now - b.time <= cfg.max_quote_age):\n                self.defect()\n                return Outcome('RISK_BASE_NOT_READY', 'BALANCE", "):\n                self.defect()\n                return Outcome('RISK_BASE_NOT_READY', 'BALANCE")]),
            ('a failed balance falls back to the explicit amount', [("                return Outcome('RISK_BASE_NOT_READY', 'BALANCE_UNREADABLE_INVALID_STALE_OR_NOT_DEMO: the demo risk policy (1% of the current balance) has no usable base; no fallback')", "                budget, b = cfg.risk_budget, mk.balance()")]),
            ('the loss check uses the explicit amount', [("risk_budget=budget, loss_time=now", "risk_budget=cfg.risk_budget, loss_time=now")]),
            ('the policy is not one percent', [("RISK_PCT_DEMO = 1.0", "RISK_PCT_DEMO = 2.0")]),
            ('the reported tick value is used', [("replace(mkt, tick_value=tick)", "replace(mkt, tick_value=sym.reported_tick_value)")]),
            ('a probe failure falls back to the property', [("        if not tick > 0:\n            self.defect()\n            return Outcome('PROBE_FAILED'", "        if False:\n            self.defect()\n            return Outcome('PROBE_FAILED'")]),
            ('context bounds and times are ignored', [("return '' if c is None else copy.deepcopy(c)", "return '' if c is None else (c.source, c.setup, c.fvg)")]),
            ('symbol recovery does not rebase', [("            self.defect()\n            return Outcome('MARKET_NOT_READY', 'SYMBOL_UNREADABLE_OR_NOT_TRADABLE')", "            return Outcome('MARKET_NOT_READY', 'SYMBOL_UNREADABLE_OR_NOT_TRADABLE')")]),
            ('quote recovery does not rebase', [("            self.defect()\n            return Outcome('MARKET_NOT_READY', 'QUOTE_NOT_READY_OR_STALE')", "            return Outcome('MARKET_NOT_READY', 'QUOTE_NOT_READY_OR_STALE')")]),
            ('a stale quote is accepted', [("0 <= now - q.time <= cfg.max_quote_age", "True")]),
            ('unset config is ignored', [("        if bad:\n            return Outcome('CONFIG_UNSET'", "        if False:\n            return Outcome('CONFIG_UNSET'")]),
            ('handled signals are not remembered', [("        if res.final in HANDLED_FINALS:\n            self.handled.append(r2.signal_id)", "        if False:\n            self.handled.append(r2.signal_id)")]),
            ('an uncertain outcome does not halt', [("        if res.final in HALT_FINALS:", "        if False:")]),
            ('the executor runtime is shared', [("en.Runtime()", "self.rt")]),
            ('the daily result is replaced by an allowing one', [("        present, daily = mk.daily(r2)", "        present, daily = True, br.Result(entry_allowed=True, primary='', dl_called=True)")]),
            ('filters default to CLEAR', [("        session, news, spread = mk.filters()", "        session, news, spread = tp.SESSION_OPEN, tp.NEWS_CLEAR, tp.SPREAD_CLEAR")]),
            ('exposure defaults to zero', [("open_positions=cfg.open_positions, trades_today=cfg.trades_today, existing_risk=cfg.existing_risk", "open_positions=max(cfg.open_positions, 0), trades_today=max(cfg.trades_today, 0), existing_risk=max(cfg.existing_risk, 0.0)")]),
            ('the pass-1 plan goes to the gate', [("res, dec = eg.submit(cfg.gate, cfg.exec, tr, store, en.Runtime(), r2, checks)", "res, dec = eg.submit(cfg.gate, cfg.exec, tr, store, en.Runtime(), r1, checks)")]),
        ]
        for name, pairs in cases:
            with self.subTest(name):
                try:
                    bad = self._run(pairs)
                except Exception:
                    bad = ['exception']
                self.assertTrue(bad, 'mutant not caught: ' + name)


if __name__ == '__main__':
    unittest.main()

