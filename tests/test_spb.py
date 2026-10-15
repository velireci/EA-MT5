"""T014 setup -> plan bridge tests: one existing T004 candidate -> TradePlanning plan, or one concrete blocking reason. BUY and SELL, every selection UNSET, several candidates, invalidation, a return that already happened,
future / historical data, identity stability across restarts and replays. No permit, no order, no execution record."""
import copy
import os
import re
import sys
import unittest
from dataclasses import replace

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import entry_reference as en  # noqa: E402
import spb_reference as sp  # noqa: E402
import t004_reference as m4  # noqa: E402
import t007_planning_reference as tp  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
START = 14400


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def context(direction, **changes):
    return replace(m4.Context('H4SET1', direction, 'T003_PROTOTYPE', 'H4F1', 80, 120, START, START, True, True, True), **changes)


def bar(i, high, low, close):
    return m4.Bar(START + i * 900, high, low, close)


def observer(direction, policy=m4.A_AT_OR_AFTER_BREAK, ctx_changes=None):
    """the real T004 reference observer driven by closed M15 bars: BOS on bar 0, FVG candidate confirmed at bar 2 (SELL: [93,95], BUY: [100,102]); phase WAIT_RETURN"""
    o = m4.Observer(policy)
    o.set_context(context(direction, **(ctx_changes or {})), START)
    if direction == -1:
        rows = ((101, 95, 96), (96, 89, 90), (93, 87, 88))
        lvl = m4.Level('L-SELL', 98.0, START)
    else:
        rows = ((100, 94, 99), (104, 98, 103), (108, 102, 107))
        lvl = m4.Level('L-BUY', 98.0, START)
    for i, (h, lo, c) in enumerate(rows):
        b = bar(i, h, lo, c)
        o.step(b, b.time + 900, lvl if i == 0 else None)
    return o, lvl


def selection(**kw):
    s = sp.Selection(context_source='T003_PROTOTYPE', swing_selector=sp.SWING_LATEST_FRACTAL_PROPOSAL, timing_policy=m4.A_AT_OR_AFTER_BREAK, candidate_selector=sp.CAND_SOLE_ELIGIBLE,
                     entry_edge=sp.EDGE_NEAR_SIDE, sl_rule=sp.SL_BROKEN_LEVEL_PRICE, sl_buffer_set=True, sl_buffer=0.5, target_rule=sp.TGT_NONE_2R_MINIMUM, live_after=START)
    for k, v in kw.items():
        setattr(s, k, v)
    return s


def market(direction, **kw):
    m = sp.Market(risk_budget=100.0, tick_value=1.0, tick_size=0.01, digits=2, point=0.01, stops_level=0, has_quote=True,
                  bid=90.0 if direction == -1 else 108.0, ask=90.3 if direction == -1 else 108.3, vol_min=0.01, vol_step=0.01, vol_max=100.0, cap_lots=10.0)
    for k, v in kw.items():
        setattr(m, k, v)
    return m


def asof_of(o):
    return o.last_asof + 900


class Plans(unittest.TestCase):
    def test_sell_candidate_becomes_the_plan_of_the_existing_builder(self):
        o, lvl = observer(-1)
        self.assertEqual(o.phase, 'WAIT_RETURN')
        r = sp.build(selection(), market(-1), o, lvl, asof_of(o))
        self.assertTrue(r.plan_ready, r.reason)
        pl = r.plan
        self.assertEqual((pl.status, pl.direction, pl.e_out, pl.s_out), (tp.OK, 'SELL', 93.0, 98.5))
        self.assertEqual(pl, tp.build_plan(r.signal_id, r.setup_id, 'SELL', 93.0, 98.5, None, 100.0, 1.0, 0.01, 2, 0.01, 0, 90.0, 90.3, 0.01, 0.01, 100.0, 10.0))   # the same call, nothing re-computed
        self.assertEqual(r.candidate_id, 'M15F14400D')
        self.assertTrue(pl.tp < pl.e_out < pl.s_out and pl.volume_out > 0)

    def test_buy_candidate_becomes_the_plan_of_the_existing_builder(self):
        o, lvl = observer(1)
        self.assertEqual(o.phase, 'WAIT_RETURN')
        r = sp.build(selection(), market(1), o, lvl, asof_of(o))
        self.assertTrue(r.plan_ready, r.reason)
        pl = r.plan
        self.assertEqual((pl.status, pl.direction, pl.e_out, pl.s_out), (tp.OK, 'BUY', 102.0, 97.5))
        self.assertEqual(r.candidate_id, 'M15F14400U')
        self.assertTrue(pl.s_out < pl.e_out < pl.tp and pl.volume_out > 0)

    def test_the_explicit_rules_change_exactly_what_they_name(self):
        for d in (1, -1):
            o, lvl = observer(d)
            base = sp.build(selection(), market(d), o, lvl, asof_of(o))
            far = sp.build(selection(entry_edge=sp.EDGE_FAR_SIDE), market(d), o, lvl, asof_of(o))
            self.assertEqual(far.plan.e_out, 100.0 if d == 1 else 95.0)
            self.assertNotEqual(far.plan.e_out, base.plan.e_out)
            sup = sp.build(selection(sl_rule=sp.SL_SUPPLIED, sl_price=96.0 if d == 1 else 99.0), market(d), o, lvl, asof_of(o))
            self.assertEqual(sup.plan.s_out, 96.0 if d == 1 else 99.0)
            buf = sp.build(selection(sl_buffer=0.0), market(d), o, lvl, asof_of(o))
            self.assertEqual(buf.plan.s_out, 98.0)
            tgt = sp.build(selection(target_rule=sp.TGT_SUPPLIED, target_price=130.0 if d == 1 else 60.0, target_source='client example E1'), market(d), o, lvl, asof_of(o))
            self.assertTrue(tgt.plan_ready, tgt.reason)
            self.assertEqual(tgt.plan.tp, 130.0 if d == 1 else 60.0)
            self.assertIn('client example E1', tgt.provenance)

    def test_a_plan_the_builder_refuses_is_a_block_with_its_reason_and_no_plan_ready(self):
        o, lvl = observer(-1)
        r = sp.build(selection(), market(-1, risk_budget=0.0), o, lvl, asof_of(o))
        self.assertFalse(r.plan_ready)
        self.assertTrue(r.reason.startswith('PLAN_REFUSED: '), r.reason)
        r = sp.build(selection(), market(-1, tick_size=0.0), o, lvl, asof_of(o))
        self.assertFalse(r.plan_ready)


class Unset(unittest.TestCase):
    FIELDS = (('context_source', dict(context_source='')), ('swing_selector', dict(swing_selector=sp.SWING_UNSET)), ('timing_policy', dict(timing_policy=m4.UNSET)),
              ('candidate_selector', dict(candidate_selector=sp.CAND_UNSET)), ('candidate_id', dict(candidate_selector=sp.CAND_EXPLICIT_ID, candidate_id='')),
              ('entry_edge', dict(entry_edge=sp.EDGE_UNSET)), ('sl_rule', dict(sl_rule=sp.SL_UNSET)), ('sl_buffer', dict(sl_buffer_set=False)), ('sl_buffer', dict(sl_buffer=-0.1)),
              ('sl_buffer', dict(sl_buffer=float('nan'))), ('sl_price', dict(sl_rule=sp.SL_SUPPLIED, sl_price=0.0)), ('target_rule', dict(target_rule=sp.TGT_UNSET)),
              ('target_price_and_source', dict(target_rule=sp.TGT_SUPPLIED, target_price=120.0, target_source='')), ('target_price_and_source', dict(target_rule=sp.TGT_SUPPLIED, target_price=0.0, target_source='x')),
              ('live_after', dict(live_after=0)), ('swing_selector', dict(swing_selector=99)), ('entry_edge', dict(entry_edge=7)))

    def test_every_unset_or_unknown_selection_blocks_with_its_name_and_never_picks_a_default(self):
        for d in (1, -1):
            o, lvl = observer(d)
            for name, kw in self.FIELDS:
                with self.subTest('%s %d %s' % (name, d, kw)):
                    r = sp.build(selection(**kw), market(d), o, lvl, asof_of(o))
                    self.assertFalse(r.plan_ready)
                    self.assertTrue(r.reason.startswith('SELECTION_UNSET'), r.reason)
                    self.assertIn(name, r.reason)
                    self.assertEqual((r.setup_id, r.signal_id, r.plan), ('', '', None))

    def test_the_default_selection_is_all_unset(self):
        o, lvl = observer(1)
        r = sp.build(sp.Selection(), market(1), o, lvl, asof_of(o))
        self.assertFalse(r.plan_ready)
        for name in ('context_source', 'swing_selector', 'timing_policy', 'candidate_selector', 'entry_edge', 'sl_rule', 'target_rule', 'live_after'):
            self.assertIn(name, r.reason)

    def test_asof_unset_blocks(self):
        o, lvl = observer(1)
        self.assertIn('asof', sp.build(selection(), market(1), o, lvl, 0).reason)


class CandidatesAndPhases(unittest.TestCase):
    def two(self, d):
        o, lvl = observer(d)
        first = o.candidates[0]
        second = m4.Candidate(first.id[:-1].replace('14400', '15300') + first.id[-1], first.lower + (10 if d == 1 else -10) - 0.0, first.upper + (10 if d == 1 else -10), first.confirmed + 900)
        o.candidates.append(second)
        return o, lvl, first, second

    def test_several_eligible_candidates_block_the_sole_selector_and_the_first_is_never_taken(self):
        for d in (1, -1):
            o, lvl, first, second = self.two(d)
            r = sp.build(selection(), market(d), o, lvl, asof_of(o) + 2000)
            self.assertFalse(r.plan_ready)
            self.assertTrue(r.reason.startswith('AMBIGUOUS_CANDIDATES'), r.reason)
            self.assertIn(first.id, r.reason)
            self.assertIn(second.id, r.reason)

    def test_an_explicit_candidate_id_picks_exactly_that_candidate(self):
        for d in (1, -1):
            o, lvl, first, second = self.two(d)
            a = sp.build(selection(candidate_selector=sp.CAND_EXPLICIT_ID, candidate_id=second.id), market(d, bid=200.0 if d == 1 else 50.0, ask=200.3 if d == 1 else 50.3), o, lvl, asof_of(o) + 2000)
            self.assertTrue(a.plan_ready, a.reason)
            self.assertEqual(a.candidate_id, second.id)
            b = sp.build(selection(candidate_selector=sp.CAND_EXPLICIT_ID, candidate_id='NOPE'), market(d), o, lvl, asof_of(o) + 2000)
            self.assertTrue(b.reason.startswith('CANDIDATE_NOT_FOUND'))

    def test_invalidated_candidates_are_never_candidates(self):
        for d in (1, -1):
            o, lvl, first, second = self.two(d)
            first.invalid = True
            self.assertTrue(sp.build(selection(candidate_selector=sp.CAND_EXPLICIT_ID, candidate_id=first.id), market(d), o, lvl, asof_of(o) + 2000).reason.startswith('CANDIDATE_INVALIDATED'))
            sole = sp.build(selection(), market(d, bid=200.0 if d == 1 else 50.0, ask=200.3 if d == 1 else 50.3), o, lvl, asof_of(o) + 2000)
            self.assertTrue(sole.plan_ready and sole.candidate_id == second.id, sole.reason)      # the invalidated one is not counted: only one eligible remains
            second.invalid = True
            self.assertEqual(sp.build(selection(), market(d), o, lvl, asof_of(o) + 2000).reason, 'NO_ELIGIBLE_CANDIDATE')

    def test_a_returned_candidate_is_not_counted_by_the_sole_selector(self):
        for d in (1, -1):
            o, lvl = observer(d)
            o.candidates.append(m4.Candidate('M15F15300' + ('U' if d == 1 else 'D'), o.candidates[0].lower, o.candidates[0].upper, o.candidates[0].confirmed + 900, returned=True))
            r = sp.build(selection(), market(d), o, lvl, asof_of(o) + 2000)
            self.assertTrue(r.plan_ready and r.candidate_id == 'M15F14400' + ('U' if d == 1 else 'D'), r.reason)

    def test_a_real_invalidating_bar_removes_the_candidate_and_the_phase(self):
        o, lvl = observer(-1)
        b = bar(3, 97, 90, 96)                                           # closes above the FVG: invalidated
        o.step(b, b.time + 900, None)
        self.assertTrue(o.candidates[0].invalid)
        r = sp.build(selection(), market(-1), o, lvl, asof_of(o))
        self.assertFalse(r.plan_ready)
        self.assertTrue(r.reason.startswith('PHASE_NOT_WAIT_RETURN'), r.reason)

    def test_a_return_that_already_happened_is_never_a_delayed_entry(self):
        for d in (1, -1):
            o, lvl = observer(d)
            b = bar(3, 96 if d == -1 else 110, 90 if d == -1 else 101, 94 if d == -1 else 105)          # touches the FVG
            o.step(b, b.time + 900, None)
            self.assertEqual(o.phase, 'RETURN_OBSERVED')
            for kw in (dict(), dict(candidate_selector=sp.CAND_EXPLICIT_ID, candidate_id=o.candidates[0].id)):
                r = sp.build(selection(**kw), market(d), o, lvl, asof_of(o))
                self.assertFalse(r.plan_ready)
                self.assertTrue(r.reason.startswith('RETURN_ALREADY_OBSERVED'), r.reason)
        o, lvl = observer(-1)                                          # returned flag on the candidate while the phase still says WAIT_RETURN (defensive)
        o.candidates.append(m4.Candidate('M15F99999D', 93.0, 95.0, 20000, returned=True))
        r = sp.build(selection(candidate_selector=sp.CAND_EXPLICIT_ID, candidate_id='M15F99999D'), market(-1), o, lvl, asof_of(o) + 5000)
        self.assertTrue(r.reason.startswith('CANDIDATE_RETURN_ALREADY_OBSERVED'))

    def test_lost_or_unselected_context_blocks(self):
        for d in (1, -1):
            o, lvl = observer(d)
            o.set_context(context(d, ready=False), asof_of(o) + 900)
            self.assertEqual(sp.build(selection(), market(d), o, lvl, asof_of(o)).reason, 'CONTEXT_LOST_OR_NOT_READY')
            o2, lvl2 = observer(d, ctx_changes=dict(selected=False))
            self.assertEqual(sp.build(selection(), market(d), o2, lvl2, asof_of(o2)).reason, 'CONTEXT_LOST_OR_NOT_READY')

    def test_source_timing_and_replay_state_must_match_the_selection(self):
        o, lvl = observer(-1)
        self.assertTrue(sp.build(selection(context_source='T002_H4_TOUCH_PROPOSAL'), market(-1), o, lvl, asof_of(o)).reason.startswith('CONTEXT_SOURCE_MISMATCH'))
        o2, lvl2 = observer(-1, policy=m4.UNSET)
        self.assertTrue(sp.build(selection(), market(-1), o2, lvl2, asof_of(o2)).reason.startswith('TIMING_MISMATCH'))
        o.step(bar(0, 101, 95, 96), asof_of(o), None)                  # a revised bar: the observer demands a replay
        self.assertEqual(o.phase, 'REPLAY_REQUIRED')
        self.assertTrue(sp.build(selection(), market(-1), o, lvl, asof_of(o)).reason.startswith('REPLAY_REQUIRED'))

    def test_the_broken_level_must_be_the_one_the_observer_recorded(self):
        o, lvl = observer(-1)
        for bad in (m4.Level('OTHER', 98.0, START), m4.Level('L-SELL', 0.0, START), m4.Level('L-SELL', 98.0, 0), m4.Level('L-SELL', 98.0, o.bos_time + 900), None):
            self.assertTrue(sp.build(selection(), market(-1), o, bad, asof_of(o)).reason.startswith('BROKEN_LEVEL_MISMATCH'))

    def test_future_data_and_historical_candidates_are_not_signals(self):
        for d in (1, -1):
            o, lvl = observer(d)
            cand = o.candidates[0]
            self.assertTrue(sp.build(selection(), market(d), o, lvl, o.last_asof - 1).reason.startswith('FUTURE_DATA'))         # the observer is ahead of asof
            o.last_asof = cand.confirmed - 1
            r = sp.build(selection(), market(d), o, lvl, cand.confirmed - 1)
            self.assertTrue(r.reason.startswith('FUTURE_DATA'), r.reason)
            o, lvl = observer(d)
            cand = o.candidates[0]
            self.assertTrue(sp.build(selection(live_after=cand.confirmed), market(d), o, lvl, asof_of(o)).reason.startswith('HISTORICAL_OR_REPLAYED_CANDIDATE'))
            self.assertTrue(sp.build(selection(live_after=cand.confirmed + 1), market(d), o, lvl, asof_of(o)).reason.startswith('HISTORICAL_OR_REPLAYED_CANDIDATE'))
            self.assertTrue(sp.build(selection(live_after=cand.confirmed - 1), market(d), o, lvl, asof_of(o)).plan_ready)

    def test_future_data_in_the_observer_alone_blocks(self):
        for d in (1, -1):
            o, lvl = observer(d)
            asof = asof_of(o)
            o.last_asof = asof + 5
            self.assertTrue(sp.build(selection(), market(d), o, lvl, asof).reason.startswith('FUTURE_DATA'))
            o, lvl = observer(d)
            o.bos_known = asof + 5
            self.assertTrue(sp.build(selection(), market(d), o, lvl, asof).reason.startswith('FUTURE_DATA'))

    def test_the_direction_of_the_candidate_must_agree_with_the_context(self):
        o, lvl = observer(-1)
        o.candidates[0].id = 'M15F14400U'
        self.assertTrue(sp.build(selection(), market(-1), o, lvl, asof_of(o)).reason.startswith('CANDIDATE_DIRECTION_INCONSISTENT'))

    def test_duplicate_or_blank_candidate_ids_block(self):
        o, lvl = observer(-1)
        o.candidates.append(copy.deepcopy(o.candidates[0]))
        self.assertTrue(sp.build(selection(), market(-1), o, lvl, asof_of(o)).reason.startswith('CANDIDATE_IDS_NOT_UNIQUE'))

    def test_the_bridge_never_changes_the_observer(self):
        for d in (1, -1):
            o, lvl = observer(d)
            before = copy.deepcopy(o.__dict__)
            sp.build(selection(), market(d), o, lvl, asof_of(o))
            sp.build(selection(candidate_selector=sp.CAND_UNSET), market(d), o, lvl, asof_of(o))
            self.assertEqual(o.__dict__, before)


class Identities(unittest.TestCase):
    def test_the_same_setup_gives_the_same_ids_after_a_restart_a_replay_or_other_inputs(self):
        for d in (1, -1):
            o1, l1 = observer(d)
            o2, l2 = observer(d)                                         # a restart: a fresh observer replays the same closed bars
            a = sp.build(selection(), market(d), o1, l1, asof_of(o1))
            b = sp.build(selection(), market(d), o2, l2, asof_of(o2) + 12345)                     # another asof
            c = sp.build(selection(candidate_selector=sp.CAND_EXPLICIT_ID, candidate_id=o1.candidates[0].id, entry_edge=sp.EDGE_FAR_SIDE, sl_buffer=1.0),
                         market(d, risk_budget=50.0), o2, l2, asof_of(o2))                         # other selector, edge, buffer, risk budget
            o3, l3 = observer(d)
            quiet = bar(3, 92, 90, 91) if d == -1 else bar(3, 108, 104, 106)          # a later bar that does not touch the FVG: the observer is further along, the setup is the same
            o3.step(quiet, quiet.time + 900, None)
            self.assertEqual(o3.phase, 'WAIT_RETURN')
            e3 = sp.build(selection(), market(d), o3, l3, asof_of(o3))
            self.assertTrue(e3.plan_ready, e3.reason)
            self.assertEqual((a.setup_id, a.signal_id), (e3.setup_id, e3.signal_id))
            self.assertTrue(a.plan_ready and b.plan_ready and c.plan_ready, (a.reason, b.reason, c.reason))
            self.assertEqual((a.setup_id, a.signal_id), (b.setup_id, b.signal_id))
            self.assertEqual((a.setup_id, a.signal_id), (c.setup_id, c.signal_id))
            self.assertTrue(a.signal_id.startswith(a.setup_id + '|M15F'))

    def test_other_setups_or_candidates_give_other_ids(self):
        o, lvl = observer(-1)
        base = sp.build(selection(), market(-1), o, lvl, asof_of(o))
        o2, lvl2 = observer(-1, ctx_changes=dict(setup='H4SET2'))
        other_setup = sp.build(selection(), market(-1), o2, lvl2, asof_of(o2))
        o3, lvl3 = observer(-1, ctx_changes=dict(fvg='H4F2'))
        other_fvg = sp.build(selection(), market(-1), o3, lvl3, asof_of(o3))
        self.assertEqual(len({base.setup_id, other_setup.setup_id, other_fvg.setup_id}), 3)
        o.candidates.append(m4.Candidate('M15F15300D', 93.0, 95.0, o.candidates[0].confirmed + 900))
        second = sp.build(selection(candidate_selector=sp.CAND_EXPLICIT_ID, candidate_id='M15F15300D'), market(-1), o, lvl, asof_of(o) + 2000)
        self.assertEqual(second.setup_id, base.setup_id)
        self.assertNotEqual(second.signal_id, base.signal_id)

    def test_no_clock_counter_or_random_value_enters_an_id(self):
        src = re.sub(r'#[^\n]*', '', _read('tests', 'spb_reference.py'))
        i = src.index('def ids(')
        body = src[i:src.index('def _block(')]
        for w in ('time', 'random', 'uuid', 'count', 'asof', 'live_after'):
            self.assertNotIn(w, body)

    def test_a_restart_cannot_bypass_the_one_signal_one_order_rule_of_the_entry_executor(self):
        o, lvl = observer(-1)
        r1 = sp.build(selection(), market(-1), o, lvl, asof_of(o))
        tr, store, rt = en.FakeTransport(), en.FakeStore(), en.Runtime()
        tr.quote = en.Quote(True, 90.0, 90.3, tr.now)
        cfg = en.Config(enabled=True, ea_magic=777, symbol='XAUUSD', filling=en.FILL_RETURN, expiry_mode=en.EXP_GTC, permit_max_age=60, quote_max_age=30)
        plan1 = replace(r1.plan, direction=-1)                           # the executor reference takes the signed direction of the MQL plan
        permit = en.permit_from(plan1, tp.Permit(tp.ALLOW, '', ()), tr.now)
        first = en.place(cfg, tr, store, rt, plan1, permit)
        self.assertEqual((first.final, tr.sends), (en.R_PLACED, 1))
        o2, lvl2 = observer(-1)                                           # restart / replay: a NEW observer, a NEW build
        r2 = sp.build(selection(), market(-1), o2, lvl2, asof_of(o2))
        self.assertEqual(r2.signal_id, r1.signal_id)
        plan2 = replace(r2.plan, direction=-1)
        again = en.place(cfg, tr, store, en.Runtime(), plan2, en.permit_from(plan2, tp.Permit(tp.ALLOW, '', ()), tr.now))
        self.assertEqual((again.final, tr.sends), (en.R_DUPLICATE, 1))


class Sources(unittest.TestCase):
    def strip(self, t):
        return re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))

    def test_the_mql_header_and_test_mirror_the_reference(self):
        hdr = self.strip(_read('src', 'include', 'SetupPlanBridge.mqh'))
        tst = _read('src', 'tests', 'SetupPlanBridgeTest.mq5')
        names = re.findall(r'^void Scenario_(\w+)\(', tst, re.M)
        self.assertEqual(names, SCENARIOS)
        for n in SCENARIOS:
            self.assertEqual(len(re.findall(r'Scenario_%s\(\);' % n, tst)), 1, n)
        self.assertEqual(hdr.count('TP_BuildPlan('), 1)
        for w in ('TG_Compute', 'PS_Compute', 'TP_CheckPermit', 'TP_Authorize', 'TP_CancelDecision', 'OrderSend', 'FileOpen', 'GlobalVariable', 'TimeCurrent', 'TimeGMT', 'M4Step(', 'M4SetContext(', 'M4Init('):
            self.assertNotIn(w, hdr, w)
        self.assertIsNone(re.search(r'\b(EN|EX|ETD|ER|XA)_', hdr))
        self.assertNotIn('#include "Entry', hdr)
        self.assertNotIn('#include "Exit', hdr)


SCENARIOS = ['sell_plan', 'buy_plan', 'explicit_rules', 'unset_selections', 'several_candidates', 'invalidation', 'return_already_observed', 'context_and_phase', 'future_and_historical',
             'identity_stability', 'plan_refused', 'observer_untouched']


class Mutants(unittest.TestCase):
    def _run(self, pairs):
        src = _read('tests', 'spb_reference.py')
        for old, new in pairs:
            self.assertEqual(src.count(old), 1, 'not unique / vacuous: ' + old[:60])
            src = src.replace(old, new, 1)
        ns = {'__name__': 'spb_mutant'}
        exec(compile(src, 'spb_mutant', 'exec'), ns)
        saved = {k: sp.__dict__[k] for k in ('build', 'ids', 'unset_fields')}
        for k in saved:
            sp.__dict__[k] = ns[k]
        try:
            suite = unittest.TestSuite()
            for cls in (Plans, Unset, CandidatesAndPhases, Identities):
                suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(cls))
            r = unittest.TestResult()
            suite.run(r)
            return r.failures + r.errors
        finally:
            sp.__dict__.update(saved)

    def test_mutants_are_caught(self):
        cases = [
            ('ambiguity takes the first candidate', [("        if len(eligible) > 1:\n            return _block('AMBIGUOUS_CANDIDATES", "        if False:\n            return _block('AMBIGUOUS_CANDIDATES")]),
            ('a returned phase still builds', [("    if ob.phase == 'RETURN_ALREADY_OBSERVED_X':", "")] if False else [("    if ob.phase == 'RETURN_OBSERVED':\n        return _block('RETURN_ALREADY_OBSERVED", "    if False:\n        return _block('RETURN_ALREADY_OBSERVED")]),
            ('invalid candidates are eligible', [("eligible = [k for k in ob.candidates if not k.invalid and not k.returned]", "eligible = [k for k in ob.candidates if not k.returned]")]),
            ('returned candidates are eligible', [("eligible = [k for k in ob.candidates if not k.invalid and not k.returned]", "eligible = [k for k in ob.candidates if not k.invalid]")]),
            ('historical candidates are signals', [("    if cand.confirmed <= sel.live_after:", "    if False:")]),
            ('future candidates are signals', [("    if cand.confirmed > asof:", "    if False:")]),
            ('future observer data accepted', [("    if ob.last_asof > asof or c.valid_from > asof or ob.bos_known > asof:", "    if False:")]),
            ('source not compared', [("    if c.source != sel.context_source:", "    if False:")]),
            ('timing not compared', [("    if ob.policy != sel.timing_policy:", "    if False:")]),
            ('replay required accepted', [("    if ob.phase == 'REPLAY_REQUIRED':", "    if False:")]),
            ('broken level not checked', [("    if broken is None or _blank(broken.id) or broken.id != ob.bos_level or", "    if broken is None or ")]),
            ('near side swapped', [("e = cand.upper if d == 1 else cand.lower\n    else:", "e = cand.lower if d == 1 else cand.upper\n    else:")]),
            ('buffer applied inward', [("s = broken.price - sel.sl_buffer if d == 1 else broken.price + sel.sl_buffer", "s = broken.price + sel.sl_buffer if d == 1 else broken.price - sel.sl_buffer")]),
            ('a default buffer is invented', [("not (sel.sl_buffer_set and _fin(sel.sl_buffer) and sel.sl_buffer >= 0.0)", "not (_fin(sel.sl_buffer) and sel.sl_buffer >= 0.0)")]),
            ('a clock enters the id', [("    return setup, setup + '|' + cand_id", "    return setup, setup + '|' + cand_id + '|' + str(ob.last_asof)")]),
            ('direction not checked', [("    if not cand.id.endswith('U' if c.direction == 1 else 'D'):", "    if False:")]),
            ('unique ids not checked', [("        if _blank(k.id) or k.id in seen:", "        if _blank(k.id):")]),
            ('unset target accepted', [("    if sel.target_rule not in TGT_NAMES:\n        bad.append('target_rule')", "    if False:\n        bad.append('target_rule')")]),
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
