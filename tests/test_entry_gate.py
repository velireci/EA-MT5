"""T015 entry-gate tests (FAKE transport and store only): plan (T014) + TP_CheckPermit data + broker loss check + T012 daily result -> one decision -> an executor permit for THAT plan, or no call to the
executor at all. BUY and SELL, every block separately, the T012 result not bypassed, permit for another / old plan, repetition without a second send."""
import copy
import os
import re
import sys
import unittest
from dataclasses import replace

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import entry_gate_reference as eg  # noqa: E402
import entry_reference as en  # noqa: E402
import spb_reference as sp  # noqa: E402
import t007_planning_reference as tp  # noqa: E402
import t008_broker_loss as bl  # noqa: E402
import t012_bridge_reference as br  # noqa: E402
import test_spb as ts  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


class World:
    def __init__(self, direction):
        self.dir = direction
        o, lvl = ts.observer(direction)
        self.spb = sp.build(ts.selection(), ts.market(direction), o, lvl, ts.asof_of(o))
        assert self.spb.plan_ready, self.spb.reason
        self.tr = en.FakeTransport()
        self.tr.quote = en.Quote(True, 108.0 if direction == 1 else 90.0, 108.3 if direction == 1 else 90.3, self.tr.now)
        self.store = en.FakeStore()
        self.rt = en.Runtime()
        self.gcfg = eg.GateConfig(max_age=60)
        self.cfg = en.Config(enabled=True, ea_magic=777, symbol='XAUUSD', filling=en.FILL_RETURN, expiry_mode=en.EXP_GTC, permit_max_age=60, quote_max_age=30)
        self.checks = self.fresh_checks()

    def digest(self, plan=None):
        return en.plan_digest(eg.entry_plan(plan or self.spb.plan))

    def fresh_checks(self):
        now, dg = self.tr.now, self.digest()
        risk = self.spb.plan.risk_model
        return eg.Checks(snapshot=tp.Snapshot(open_positions=0, trades_today=0, existing_risk=0.0), snapshot_time=now, snapshot_digest=dg,
                         limits=tp.Limits(max_positions=2, max_trades_per_day=3, combined_risk_cap=1000.0), registry=tp.Registry.new(8),
                         calc_ok=True, profit=-risk, tolerance=0.01, risk_budget=100.0, loss_time=now, loss_digest=dg,
                         daily_present=True, daily=br.Result(entry_allowed=True, primary='', dl_called=True), daily_time=now, daily_digest=dg)

    def submit(self, rt=None, pre_send=None):
        return eg.submit(self.gcfg, self.cfg, self.tr, self.store, rt or self.rt, self.spb, self.checks, pre_send)

    def rec(self):
        ok, text = self.store.read(en.file_name(self.tr.account.login, self.spb.plan.signal_id))
        ok, r = en.decode(text)
        assert ok, r
        return r

    def clean(self):
        return self.store.held == set() and self.store.lock_calls == self.store.unlock_calls

    def assert_nothing_happened(self, tc, res, reg0=0):
        tc.assertEqual(res.final, en.R_REFUSED)
        tc.assertTrue(res.reason.startswith('GATE_BLOCKED'), res.reason)
        tc.assertEqual((self.tr.sends, self.rt.send_calls, self.store.lock_calls, self.store.writes, len(self.store.files)), (0, 0, 0, 0, 0))
        tc.assertEqual(self.checks.registry.count, reg0)               # a block registers no signal use


def blocks(w):
    """(name, change, expected reason fragment) - every one changes ONE thing in an otherwise passing world"""
    plan = w.spb.plan
    snap = lambda **kw: (lambda c: setattr(c, 'snapshot', replace(c.snapshot, **kw)))
    return [
        ('plan not ready', lambda c: setattr(w.spb, 'plan_ready', False), 'PLAN_NOT_READY'),
        ('plan status not OK', lambda c: setattr(w.spb, 'plan', replace(plan, status=tp.GEOMETRY_REFUSED)), 'PERMIT:PLAN_NOT_OK'),
        ('data not ready', snap(data_state=tp.DATA_NOT_READY), 'PERMIT:DATA_NOT_READY'),
        ('data unknown', snap(data_state=tp.DATA_UNKNOWN), 'PERMIT:DATA_UNKNOWN'),
        ('data unreliable', snap(data_reliable=False), 'PERMIT:DATA_UNRELIABLE'),
        ('session closed', snap(session_state=tp.SESSION_CLOSED), 'PERMIT:SESSION_CLOSED'),
        ('session unknown', snap(session_state=tp.SESSION_UNKNOWN), 'PERMIT:SESSION_UNKNOWN'),
        ('news blocked', snap(news_state=tp.NEWS_BLOCKED), 'PERMIT:NEWS_BLOCK'),
        ('news unknown', snap(news_state=tp.NEWS_UNKNOWN), 'PERMIT:NEWS_UNKNOWN'),
        ('spread blocked', snap(spread_state=tp.SPREAD_BLOCKED), 'PERMIT:SPREAD_BLOCK'),
        ('spread unknown', snap(spread_state=tp.SPREAD_UNKNOWN), 'PERMIT:SPREAD_UNKNOWN'),
        ('positions reached', snap(open_positions=2), 'PERMIT:MAX_POSITIONS_REACHED'),
        ('trades reached', snap(trades_today=3), 'PERMIT:MAX_TRADES_REACHED'),
        ('combined risk exceeded', snap(existing_risk=999.0), 'PERMIT:COMBINED_RISK_EXCEEDED'),
        ('max positions unset', lambda c: setattr(c, 'limits', replace(c.limits, max_positions=None)), 'PERMIT:POLICY_UNSET:max_positions'),
        ('max trades unset', lambda c: setattr(c, 'limits', replace(c.limits, max_trades_per_day=None)), 'PERMIT:POLICY_UNSET:max_trades_per_day'),
        ('risk cap unset', lambda c: setattr(c, 'limits', replace(c.limits, combined_risk_cap=None)), 'PERMIT:POLICY_UNSET:combined_risk_cap'),
        ('duplicate signal', lambda c: (c.registry.ids.__setitem__(0, plan.signal_id), setattr(c.registry, 'count', 1)), 'PERMIT:DUPLICATE_SIGNAL'),
        ('permit inputs missing', lambda c: setattr(c, 'snapshot', None), 'PERMIT_INPUT_MISSING'),
        ('loss calc failed', lambda c: setattr(c, 'calc_ok', False), 'BROKER_LOSS_CHECK:CALC_FAILED'),
        ('loss not a loss', lambda c: setattr(c, 'profit', 5.0), 'BROKER_LOSS_CHECK:NOT_A_LOSS'),
        ('loss over budget', lambda c: setattr(c, 'profit', -150.0), 'BROKER_LOSS_CHECK:BUDGET_EXCEEDED'),
        ('loss model mismatch', lambda c: (setattr(c, 'profit', -plan.risk_model * 1.5), setattr(c, 'risk_budget', 10000.0)), 'BROKER_LOSS_CHECK:MODEL_MISMATCH'),
        ('loss invalid tolerance', lambda c: setattr(c, 'tolerance', 2.0), 'BROKER_LOSS_CHECK:INVALID_INPUT'),
        ('daily not evaluated', lambda c: setattr(c, 'daily_present', False), 'DAILY_NOT_EVALUATED'),
        ('daily result missing', lambda c: setattr(c, 'daily', None), 'DAILY_NOT_EVALUATED'),
        ('daily check not called', lambda c: setattr(c, 'daily', br.Result(entry_allowed=False, primary='BALANCE_START_UNSET', dl_called=False)), 'DAILY_NOT_CALLED'),
        ('daily blocks', lambda c: setattr(c, 'daily', br.Result(entry_allowed=False, primary='DAILY_LOSS_LIMIT', dl_called=True)), 'DAILY_BLOCK'),
        ('daily allowing without a call', lambda c: setattr(c, 'daily', br.Result(entry_allowed=True, primary='', dl_called=False)), 'DAILY_NOT_CALLED'),
        ('snapshot stale', lambda c: setattr(c, 'snapshot_time', w.tr.now - 61), 'SNAPSHOT_STALE'),
        ('snapshot future', lambda c: setattr(c, 'snapshot_time', w.tr.now + 1), 'SNAPSHOT_TIME_INVALID'),
        ('snapshot unset time', lambda c: setattr(c, 'snapshot_time', 0), 'SNAPSHOT_TIME_INVALID'),
        ('snapshot for another plan', lambda c: setattr(c, 'snapshot_digest', 'other'), 'SNAPSHOT_FOR_ANOTHER_PLAN'),
        ('loss check stale', lambda c: setattr(c, 'loss_time', w.tr.now - 61), 'LOSS_CHECK_STALE'),
        ('loss check future', lambda c: setattr(c, 'loss_time', w.tr.now + 1), 'LOSS_CHECK_TIME_INVALID'),
        ('loss check for another plan', lambda c: setattr(c, 'loss_digest', ''), 'LOSS_CHECK_FOR_ANOTHER_PLAN'),
        ('daily stale', lambda c: setattr(c, 'daily_time', w.tr.now - 61), 'DAILY_STALE'),
        ('daily future', lambda c: setattr(c, 'daily_time', w.tr.now + 1), 'DAILY_TIME_INVALID'),
        ('daily for another plan', lambda c: setattr(c, 'daily_digest', 'x'), 'DAILY_FOR_ANOTHER_PLAN'),
        ('gate max age unset', lambda c: setattr(w.gcfg, 'max_age', 0), 'INPUT_UNSET: gate_max_age'),
    ]


class Allow(unittest.TestCase):
    def test_all_checks_allowing_place_one_order_for_buy_and_sell(self):
        for d in (1, -1):
            w = World(d)
            res, dec = w.submit()
            self.assertTrue(dec.allow, dec.reasons)
            self.assertEqual((res.final, res.sends, w.tr.sends), (en.R_PLACED, 1, 1), res.reason)
            q = w.tr.requests[0]
            p = eg.entry_plan(w.spb.plan)
            self.assertEqual((q.type, q.price, q.sl, q.tp, q.volume), (en.TYPE_BUY_LIMIT if d == 1 else en.TYPE_SELL_LIMIT, p.e_out, p.s_out, p.tp, p.volume_out))
            self.assertEqual((dec.permit.present, dec.permit.allow, dec.permit.digest, dec.permit.issued), (True, True, w.digest(), w.tr.now))
            self.assertEqual(w.checks.registry.count, 0)                    # the gate registers nothing; the executor record is the durable guard
            self.assertEqual(dec.loss_check, 'OK')

    def test_the_permit_check_used_is_check_permit_and_the_final_decision_adds_the_others(self):
        w = World(1)
        plan = w.spb.plan
        guarded = replace(plan, risk_model=bl.permit_risk(w.checks.profit, plan.risk_model))
        self.assertEqual(tp.check_permit(guarded, w.checks.snapshot, w.checks.limits, w.checks.registry).decision, tp.ALLOW)
        self.assertTrue(eg.decide(w.gcfg, w.spb, w.checks, w.tr.now).allow)


class Blocks(unittest.TestCase):
    def test_every_block_alone_stops_before_the_executor_for_buy_and_sell(self):
        for d in (1, -1):
            names = [b[0] for b in blocks(World(d))]
            for name in names:
                with self.subTest('%s dir %d' % (name, d)):
                    w = World(d)
                    _, change, frag = [b for b in blocks(w) if b[0] == name][0]
                    change(w.checks)
                    reg0 = w.checks.registry.count
                    res, dec = w.submit()
                    self.assertFalse(dec.allow)
                    self.assertEqual((dec.permit.present, dec.permit.allow), (False, False))
                    self.assertTrue(any(frag in r for r in dec.reasons), dec.reasons)
                    w.assert_nothing_happened(self, res, reg0)

    def test_the_larger_broker_loss_feeds_the_exposure_check(self):
        for d in (1, -1):
            w = World(d)
            risk = w.spb.plan.risk_model
            w.checks.tolerance, w.checks.risk_budget = 0.05, 10000.0
            w.checks.profit = -risk * 1.04
            w.checks.snapshot = replace(w.checks.snapshot, existing_risk=100.0)
            w.checks.limits = replace(w.checks.limits, combined_risk_cap=100.0 + risk * 1.02)
            dec = eg.decide(w.gcfg, w.spb, w.checks, w.tr.now)
            self.assertEqual(dec.loss_check, 'OK')
            self.assertFalse(dec.allow)
            self.assertIn('PERMIT:COMBINED_RISK_EXCEEDED', dec.reasons)

    def test_a_plan_that_is_not_ready_never_reaches_check_permit(self):
        w = World(1)
        w.spb = sp.Result(False, 'SELECTION_UNSET: entry_edge')
        dec = eg.decide(w.gcfg, w.spb, w.checks, w.tr.now)
        self.assertEqual(dec.reasons, ['PLAN_NOT_READY: SELECTION_UNSET: entry_edge'])
        self.assertEqual(dec.loss_check, '')

    def test_the_default_gate_config_and_default_checks_block(self):
        w = World(1)
        self.assertFalse(eg.decide(eg.GateConfig(), w.spb, w.checks, w.tr.now).allow)
        res, dec = eg.submit(w.gcfg, w.cfg, w.tr, w.store, w.rt, w.spb, eg.Checks())
        self.assertFalse(dec.allow)
        self.assertEqual((res.final, w.tr.sends, w.store.lock_calls), (en.R_REFUSED, 0, 0))


class Daily(unittest.TestCase):
    def test_t012_is_never_bypassed_by_the_t007_allow(self):
        for d in (1, -1):
            w = World(d)
            plan = w.spb.plan
            self.assertEqual(tp.check_permit(plan, w.checks.snapshot, w.checks.limits, w.checks.registry).decision, tp.ALLOW)       # T007 alone would allow
            for daily in (br.Result(entry_allowed=False, primary='DAILY_LOSS_LIMIT', dl_called=True), br.Result(entry_allowed=True, dl_called=False), None):
                w.checks.daily = daily
                w.checks.daily_present = daily is not None
                res, dec = w.submit()
                self.assertFalse(dec.allow)
                self.assertEqual((res.final, w.tr.sends, w.store.writes), (en.R_REFUSED, 0, 0))

    def test_the_preview_manual_exception_is_not_used_on_the_execution_path(self):
        src = re.sub(r'#[^\n]*', '', _read('tests', 'entry_gate_reference.py'))
        for w in ('final_preview', 'FinalPreview', 'DG_', 'daily_evaluated or', 'not daily_evaluated'):
            self.assertNotIn(w, src)


class Binding(unittest.TestCase):
    def test_the_permit_is_for_this_plan_and_expires(self):
        for d in (1, -1):
            w = World(d)
            dec = eg.decide(w.gcfg, w.spb, w.checks, w.tr.now)
            other = replace(eg.entry_plan(w.spb.plan), volume_out=eg.entry_plan(w.spb.plan).volume_out + 0.01)
            r = en.place(w.cfg, w.tr, w.store, w.rt, other, dec.permit)
            self.assertEqual((r.final, w.tr.sends), (en.R_REFUSED, 0))
            self.assertIn('PERMIT_FOR_ANOTHER_PLAN', r.reason)
            w.tr.now += 100                                              # the decision is older than the permit age now
            w.tr.quote = en.Quote(True, w.tr.quote.bid, w.tr.quote.ask, w.tr.now)
            r2 = en.place(w.cfg, w.tr, w.store, w.rt, eg.entry_plan(w.spb.plan), dec.permit)
            self.assertEqual((r2.final, w.tr.sends), (en.R_REFUSED, 0))
            self.assertIn('PERMIT_STALE', r2.reason)

    def test_old_checks_block_the_decision_after_time_passes(self):
        w = World(-1)
        w.tr.now += 100
        w.tr.quote = en.Quote(True, 90.0, 90.3, w.tr.now)
        res, dec = w.submit()
        self.assertFalse(dec.allow)
        self.assertTrue(any('STALE' in r for r in dec.reasons), dec.reasons)
        self.assertEqual(w.tr.sends, 0)


class Repetition(unittest.TestCase):
    def test_a_second_submit_after_a_restart_never_sends_again(self):
        for d in (1, -1):
            w = World(d)
            first, _ = w.submit()
            self.assertEqual(first.final, en.R_PLACED)
            again, dec = w.submit(rt=en.Runtime())
            self.assertTrue(dec.allow)
            self.assertEqual((again.final, w.tr.sends), (en.R_DUPLICATE, 1))
            same, _ = w.submit()
            self.assertEqual((same.final, w.tr.sends), (en.R_REFUSED, 1))
            self.assertIn('DUPLICATE_CALL', same.reason)

    def test_a_block_leaves_no_trace_and_a_later_allowed_submit_still_places_once(self):
        w = World(1)
        w.checks.daily_present = False
        res, _ = w.submit()
        w.assert_nothing_happened(self, res)
        w.checks.daily_present = True
        res2, _ = w.submit()
        self.assertEqual((res2.final, w.tr.sends), (en.R_PLACED, 1))


class EvidenceExpiry(unittest.TestCase):
    """the Codex review of 9950ab7: the permit built by the gate must not outlive the OLDEST evidence it was built from (gate max_age), even when the executor permit age is longer"""

    def world(self, d, ages, advance=0, gate_age=5):
        w = World(d)
        w.gcfg.max_age = gate_age
        now = w.tr.now
        w.checks.snapshot_time, w.checks.loss_time, w.checks.daily_time = now - ages[0], now - ages[1], now - ages[2]
        w.tr.precheck_advance = advance
        self.assertEqual(w.cfg.permit_max_age, 60)
        return w

    def test_the_permit_carries_the_deadline_of_the_oldest_evidence(self):
        for d in (1, -1):
            for ages, oldest in (((4, 4, 4), 4), ((1, 4, 2), 4), ((0, 0, 3), 3), ((5, 1, 1), 5)):
                w = self.world(d, ages)
                dec = eg.decide(w.gcfg, w.spb, w.checks, w.tr.now)
                self.assertTrue(dec.allow, dec.reasons)
                self.assertEqual(dec.permit.issued, w.tr.now)
                self.assertEqual(dec.permit.valid_until, w.tr.now - oldest + 5)

    def test_evidence_that_expires_during_the_precheck_gives_zero_sends_after_the_intent(self):
        for d in (1, -1):
            for ages, advance in (((4, 4, 4), 10), ((1, 4, 2), 2), ((4, 4, 4), 2), ((5, 5, 5), 1)):
                with self.subTest('%d %s %d' % (d, ages, advance)):
                    w = self.world(d, ages, advance)
                    res, dec = w.submit()
                    self.assertTrue(dec.allow)                                           # the decision itself was legitimate
                    self.assertEqual((res.final, res.sends, w.tr.sends, w.rt.send_calls), (en.R_REFUSED, 0, 0, 0), res.reason)
                    self.assertIn('ABORTED_BEFORE_SEND', res.reason)                     # the intent was saved: this is NOT the initial block
                    self.assertIn('PERMIT_EVIDENCE_EXPIRED', res.reason)
                    self.assertEqual(w.rec().state, en.ST_PRECHECK_REFUSED)
                    self.assertEqual(w.store.writes, 2)                                  # intent + the refused state
                    self.assertTrue(w.clean())

    def test_evidence_that_is_still_valid_places_once(self):
        for d in (1, -1):
            for ages, advance in (((4, 4, 4), 1), ((1, 4, 2), 1), ((0, 0, 0), 5), ((2, 3, 1), 2)):
                with self.subTest('%d %s %d' % (d, ages, advance)):
                    w = self.world(d, ages, advance)
                    res, dec = w.submit()
                    self.assertEqual((res.final, res.sends, w.tr.sends), (en.R_PLACED, 1, 1), res.reason)

    def test_the_initial_block_has_no_intent_and_differs_from_the_refusal_after_the_precheck(self):
        for d in (1, -1):
            w = self.world(d, (6, 1, 1))                                                 # already older than the gate age: blocked by the gate, nothing written
            res, dec = w.submit()
            self.assertFalse(dec.allow)
            self.assertTrue(res.reason.startswith('GATE_BLOCKED'))
            self.assertEqual((w.tr.sends, w.store.lock_calls, w.store.writes, len(w.store.files)), (0, 0, 0, 0))
            w2 = self.world(d, (4, 4, 4))                                                # a permit whose deadline is already past when it reaches the executor: refused before any intent
            dec2 = eg.decide(w2.gcfg, w2.spb, w2.checks, w2.tr.now)
            late = replace(dec2.permit, valid_until=w2.tr.now - 1)
            r = en.place(w2.cfg, w2.tr, w2.store, w2.rt, eg.entry_plan(w2.spb.plan), late)
            self.assertEqual((r.final, w2.tr.sends, w2.store.lock_calls, w2.store.writes, len(w2.store.files)), (en.R_REFUSED, 0, 0, 0, 0))
            self.assertTrue(r.reason.startswith('PERMIT_EVIDENCE_EXPIRED'), r.reason)

    def test_a_permit_without_a_deadline_keeps_the_old_behaviour(self):
        w = World(1)
        pm = en.permit_from(eg.entry_plan(w.spb.plan), tp.Permit(tp.ALLOW, '', ()), w.tr.now)
        self.assertEqual(pm.valid_until, 0)
        self.assertEqual(en.place(w.cfg, w.tr, w.store, w.rt, eg.entry_plan(w.spb.plan), pm).final, en.R_PLACED)


class PreSendHook(unittest.TestCase):
    """T019 review: the caller's hook runs ONLY after the gate allowed and BEFORE the executor (before any lock, intent or send); a refusal places nothing and consumes nothing"""

    class Hook:
        def __init__(self, w, ok=True):
            self.w, self.ok, self.reserved, self.settled_with = w, ok, [], []

        def reserve(self, signal_id):
            self.reserved.append((signal_id, self.w.tr.sends, self.w.store.writes, self.w.store.lock_calls, len(self.w.store.files)))
            return (self.ok, '' if self.ok else 'INDEX_NOT_SAVED')

        def settled(self, signal_id, res):
            self.settled_with.append((signal_id, res.final))

    def test_the_hook_runs_after_the_gate_and_before_any_lock_intent_or_send(self):
        for d in (1, -1):
            w = World(d)
            h = self.Hook(w)
            res, dec = w.submit(pre_send=h)
            self.assertEqual(res.final, en.R_PLACED)
            self.assertEqual(h.reserved, [(w.spb.plan.signal_id, 0, 0, 0, 0)])
            self.assertEqual(h.settled_with, [(w.spb.plan.signal_id, en.R_PLACED)])
            self.assertEqual(w.tr.sends, 1)

    def test_a_refusal_places_nothing_and_consumes_nothing(self):
        for d in (1, -1):
            w = World(d)
            h = self.Hook(w, ok=False)
            res, dec = w.submit(pre_send=h)
            self.assertEqual(res.final, en.R_REFUSED)
            self.assertTrue(res.reason.startswith('PRE_SEND_RESERVATION_FAILED'), res.reason)
            self.assertEqual((w.tr.sends, w.rt.send_calls, w.store.lock_calls, w.store.writes, len(w.store.files)), (0, 0, 0, 0, 0))
            self.assertEqual(h.settled_with, [])
            h.ok = True
            res2, _ = w.submit(pre_send=h)
            self.assertEqual((res2.final, w.tr.sends), (en.R_PLACED, 1), 'the signal was not consumed by the refused reservation')

    def test_a_gate_block_never_calls_the_hook(self):
        for d in (1, -1):
            w = World(d)
            w.checks.daily_present = False
            h = self.Hook(w)
            res, dec = w.submit(pre_send=h)
            w.assert_nothing_happened(self, res)
            self.assertEqual((h.reserved, h.settled_with), ([], []))


SCENARIOS = ['allow_all', 'every_block', 'plan_not_ready', 'daily_not_bypassed', 'freshness_and_binding', 'permit_for_another_or_stale_plan', 'repeat_without_second_send', 'blocks_leave_no_trace', 'evidence_expiry_during_precheck', 'pre_send_hook']


class Sources(unittest.TestCase):
    def strip(self, t):
        return re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))

    def test_the_mql_test_names_the_same_scenarios_and_the_header_reuses_the_checks(self):
        hdr = self.strip(_read('src', 'include', 'EntryGate.mqh'))
        tst = _read('src', 'tests', 'EntryGateTest.mq5')
        names = re.findall(r'^void Scenario_(\w+)\(', tst, re.M)
        self.assertEqual(names, SCENARIOS)
        for n in SCENARIOS:
            self.assertEqual(len(re.findall(r'Scenario_%s\(\);' % n, tst)), 1, n)
        self.assertEqual(hdr.count('TP_CheckPermit('), 1)
        self.assertEqual(hdr.count('PB_CheckLoss('), 1)
        self.assertEqual(hdr.count('EN_Place('), 1)
        for w in ('TP_Authorize', 'DG_FinalPreview', 'DG_Evaluate', 'DB_Check(', 'DL_Check(', 'TG_Compute', 'PS_Compute', 'TP_BuildPlan', 'OrderSend', 'FileOpen', 'GlobalVariable',
                  'TimeCurrent', 'TimeGMT', 'store.Write', 'store.Lock', 'EN_Commit', 'M4Step('):
            self.assertNotIn(w, hdr, w)


class Mutants(unittest.TestCase):
    def _run(self, pairs):
        src = _read('tests', 'entry_gate_reference.py')
        for old, new in pairs:
            self.assertEqual(src.count(old), 1, 'not unique / vacuous: ' + old[:70])
            src = src.replace(old, new, 1)
        ns = {'__name__': 'gate_mutant'}
        exec(compile(src, 'gate_mutant', 'exec'), ns)
        saved = {k: eg.__dict__[k] for k in ('decide', 'submit', '_fresh')}
        for k in saved:
            eg.__dict__[k] = ns[k]
        try:
            suite = unittest.TestSuite()
            for cls in (Allow, Blocks, Daily, Binding, Repetition, EvidenceExpiry):
                suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(cls))
            r = unittest.TestResult()
            suite.run(r)
            return r.failures + r.errors
        finally:
            eg.__dict__.update(saved)

    def test_mutants_are_caught(self):
        cases = [
            ('the daily result is ignored', [("    if not checks.daily_present or checks.daily is None:\n        r.append('DAILY_NOT_EVALUATED')", "    if False:\n        r.append('DAILY_NOT_EVALUATED')")]),
            ('the MANUAL exception (not evaluated = no condition)', [("    if not checks.daily_present or checks.daily is None:\n        r.append('DAILY_NOT_EVALUATED')\n    elif not checks.daily.dl_called:", "    if not checks.daily_present or checks.daily is None:\n        pass\n    elif not checks.daily.dl_called:")]),
            ('a daily check that was not called is accepted', [("    elif not checks.daily.dl_called:\n        r.append('DAILY_NOT_CALLED: ' + checks.daily.primary)\n", "")]),
            ('a blocking daily result is accepted', [("    elif not checks.daily.entry_allowed:\n        r.append('DAILY_BLOCK: ' + checks.daily.primary)\n", "")]),
            ('the broker loss check is skipped', [("    if d.loss_check != 'OK':\n        r.append('BROKER_LOSS_CHECK:' + d.loss_check)", "    if False:\n        r.append('BROKER_LOSS_CHECK:' + d.loss_check)")]),
            ('the permit check is skipped', [("        if tpermit.decision != tp.ALLOW:\n            r.extend('PERMIT:' + x for x in tpermit.reasons)", "        if False:\n            r.extend('PERMIT:' + x for x in tpermit.reasons)")]),
            ('authorize registers the signal', [("tpermit = tp.check_permit(guarded, checks.snapshot, checks.limits, checks.registry)", "tpermit = tp.authorize(guarded, checks.snapshot, checks.limits, checks.registry)")]),
            ('the plan digest is not compared', [("    if digest != want:\n        reasons.append('%s_FOR_ANOTHER_PLAN' % name)", "    if False:\n        reasons.append('%s_FOR_ANOTHER_PLAN' % name)")]),
            ('stale checks are accepted', [("    elif now - t > max_age:\n        reasons.append('%s_STALE' % name)", "    elif False:\n        reasons.append('%s_STALE' % name)")]),
            ('future checks are accepted', [("    if not 0 < t <= now:", "    if not 0 < t:")]),
            ('an unset max age does not block', [("    if not gcfg.max_age > 0:", "    if False:")]),
            ('a plan that is not ready continues', [("    if not spb.plan_ready or spb.plan is None:", "    if spb.plan is None:")]),
            ('the executor is called after a block', [("    if not dec.allow:\n        return en.Result(en.R_REFUSED, 'GATE_BLOCKED: ' + ' | '.join(dec.reasons)), dec", "    if False:\n        return en.Result(en.R_REFUSED, 'GATE_BLOCKED: ' + ' | '.join(dec.reasons)), dec")]),
            ('the permit is stamped with another time', [("    d.permit = en.permit_from(plan, tpermit, now)", "    d.permit = en.permit_from(plan, tpermit, now - 1000)")]),
            ('the permit is built from another plan', [("    d.permit = en.permit_from(plan, tpermit, now)", "    d.permit = en.permit_from(replace(plan, volume_out=plan.volume_out + 0.01), tpermit, now)")]),
            ('the deadline is stamped from the decision time', [("min(checks.snapshot_time, checks.loss_time, checks.daily_time) + gcfg.max_age", "now + gcfg.max_age")]),
            ('the deadline follows the NEWEST evidence', [("min(checks.snapshot_time, checks.loss_time, checks.daily_time) + gcfg.max_age", "max(checks.snapshot_time, checks.loss_time, checks.daily_time) + gcfg.max_age")]),
            ('no deadline is stamped', [("    d.permit.valid_until = min(checks.snapshot_time, checks.loss_time, checks.daily_time) + gcfg.max_age        # never valid beyond the OLDEST evidence\n", "")]),
            ('the guarded risk model is not used', [("        guarded = replace(spb.plan, risk_model=bl.permit_risk(checks.profit, spb.plan.risk_model))", "        guarded = spb.plan")]),
        ]
        for name, pairs in cases:
            with self.subTest(name):
                try:
                    bad = self._run(pairs)
                except Exception:
                    bad = ['exception']
                self.assertTrue(bad, 'mutant not caught: ' + name)

    def test_an_executor_that_ignores_the_deadline_is_caught(self):
        src = _read('tests', 'entry_reference.py')
        old = "    if permit.valid_until > 0 and now > permit.valid_until:"
        self.assertEqual(src.count(old), 1)
        ns = {'__name__': 'entry_mutant'}
        exec(compile(src.replace(old, "    if False:", 1), 'entry_mutant', 'exec'), ns)
        saved = en.permit_refusal
        en.permit_refusal = ns['permit_refusal']
        try:
            suite = unittest.defaultTestLoader.loadTestsFromTestCase(EvidenceExpiry)
            r = unittest.TestResult()
            suite.run(r)
            self.assertTrue(r.failures + r.errors, 'mutant not caught')
        finally:
            en.permit_refusal = saved


if __name__ == '__main__':
    unittest.main()
