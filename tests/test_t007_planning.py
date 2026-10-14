"""Unit tests for the T007 pure trade-planning reference. Run: python3 -m unittest test_t007_planning (from tests/).
Expected values come from tests/t007_planning_fixtures.py (hand-computed, not by the code formula). These tests prove the
CONTRACT of side-effect-free plan / permit / cancel-request helpers only; they say nothing about entry quality, the real
broker, the base of the 1%, the client limits or any executed order. The geometry and sizing inside the plan come from the
REAL T005 and T006 references."""
import dataclasses
import math
import os
import re
import sys
import types
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t005_geometry_reference as g5  # noqa: E402
import t006_sizing_reference as p6  # noqa: E402
import t007_planning_reference as ref  # noqa: E402
from t007_planning_fixtures import (CANCEL_CASES, PERMIT_CASES, PLAN_CASES, emit_mql)  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAN, INF = float('nan'), float('inf')
PLAN_BY_NAME = {c['name']: c for c in PLAN_CASES}
NUMERIC = ('e_out', 's_out', 'tp', 'level_2r', 'partial_price', 'r_geom', 'volume_out', 'risk_model')


def same(a, b):
    return abs(a - b) <= 1e-9 * max(1.0, abs(b))


def call_plan(m, c, **over):
    sid, setup, d, e, s, t, budget, tv, sym, quote, vol = c['args']
    a = dict(sid=sid, setup=setup, d=d, e=e, s=s, t=t, budget=budget, tv=tv, sym=sym, quote=quote, vol=vol)
    a.update(over)
    bid, ask = a['quote'] if a['quote'] else (None, None)
    return m.build_plan(a['sid'], a['setup'], a['d'], a['e'], a['s'], a['t'], a['budget'], a['tv'],
                        a['sym'][0], a['sym'][1], a['sym'][2], a['sym'][3], bid, ask, *a['vol'])


def snap_of(m, c):
    return m.Snapshot(data_state=c['data'], data_reliable=c['rel'], session_state=c['sess'], news_state=c['news'],
                      spread_state=c['spr'], open_positions=c['pos'], trades_today=c['trd'], existing_risk=c['risk'])


def limits_of(m, c):
    return m.Limits(max_positions=c['lim']['pos'], max_trades_per_day=c['lim']['trd'], combined_risk_cap=c['lim']['cap'])


def registry_of(m, c):
    r = m.Registry.new(c['capacity'])
    for i, rid in enumerate(c['reg']):
        r.ids[i] = rid
    r.count = len(c['reg'])
    return r


def good_plan(m, sid='SIG-1'):
    return call_plan(m, PLAN_BY_NAME['BUY_BASIC'], sid=sid)


def default_snap(m, **kw):
    return m.Snapshot(**kw)


FULL_LIMITS = dict(max_positions=3, max_trades_per_day=5, combined_risk_cap=5000.0)


def behaviour_failures(m):
    """Names of the hand-computed rows and sequences that module/namespace `m` gets wrong (empty list = all correct)."""
    bad = []
    for c in PLAN_CASES:
        try:
            p = call_plan(m, c)
            ok = p.status == c['status'] and p.stage == c['stage']
            if c['why']:
                ok = ok and p.reason.startswith(c['why'])
            if c['under']:
                ok = ok and p.under_status == c['under']
            if c['under_why']:
                ok = ok and p.under_reason.startswith(c['under_why'])
            if c['exp'] is not None:
                ok = ok and all(same(getattr(p, f), v) for f, v in zip(NUMERIC, c['exp']))
            else:
                ok = ok and all(getattr(p, f) == 0 for f in NUMERIC)
            if not ok:
                bad.append(c['name'])
        except Exception:
            bad.append(c['name'])
    for c in PERMIT_CASES:
        try:
            p = call_plan(m, PLAN_BY_NAME[c['plan']])
            r = m.check_permit(p, snap_of(m, c), limits_of(m, c), registry_of(m, c))
            exp = tuple(x for x in c['reasons'].split('|') if x)
            ok = (r.decision == c['dec'] and r.reasons == exp and r.primary_reason == (exp[0] if exp else ''))
            if not ok:
                bad.append(c['name'])
        except Exception:
            bad.append(c['name'])
    for c in CANCEL_CASES:
        try:
            r = m.cancel_decision(c['pend'], c['pid'], c['pos'], c['ev'])
            exp = tuple(x for x in c['reasons'].split('|') if x)
            ok = (r.status == c['status'] and r.reasons == exp and r.cancel_pending == (c['status'] == 'CANCEL_REQUEST') and
                  r.positions_untouched is True and r.position_present == c['pos'])
            if c['why']:
                ok = ok and r.reason.startswith(c['why'])
            if c['status'] == 'CANCEL_REQUEST':
                ok = ok and r.pending_signal_id == c['pid']
            if not ok:
                bad.append(c['name'])
        except Exception:
            bad.append(c['name'])
    bad += sequence_failures(m)
    return bad


def sequence_failures(m):
    bad = []
    lim = m.Limits(**FULL_LIMITS)
    snap = m.Snapshot()
    try:
        reg = m.Registry.new(4)
        a1 = m.authorize(good_plan(m), snap, lim, reg)
        a2 = m.authorize(good_plan(m), snap, lim, reg)
        if not (a1.decision == 'ALLOW' and a1.registered and reg.count == 1 and reg.ids[0] == 'SIG-1'):
            bad.append('SEQ_FIRST_AUTHORIZATION_REGISTERS')
        if not (a2.decision == 'BLOCK' and a2.primary_reason == 'DUPLICATE_SIGNAL' and not a2.registered and reg.count == 1):
            bad.append('SEQ_SAME_SIGNAL_TWICE_BLOCKS')
        a3 = m.authorize(good_plan(m, 'SIG-2'), snap, lim, reg)
        if not (a3.decision == 'ALLOW' and reg.count == 2 and reg.ids[:2] == ['SIG-1', 'SIG-2']):
            bad.append('SEQ_DIFFERENT_SIGNAL_ALLOWED')
    except Exception:
        bad.append('SEQ_DUPLICATE_PROTECTION_RAISED')
    try:
        reg = m.Registry.new(4)
        b = m.authorize(good_plan(m), m.Snapshot(data_state='NOT_READY'), lim, reg)
        count_after_block = reg.count
        again = m.authorize(good_plan(m), snap, lim, reg)
        if not (b.decision == 'BLOCK' and count_after_block == 0 and again.decision == 'ALLOW' and reg.count == 1):
            bad.append('SEQ_BLOCKED_ATTEMPT_DOES_NOT_CONSUME_ID')
    except Exception:
        bad.append('SEQ_BLOCKED_ATTEMPT_RAISED')
    try:
        reg = m.Registry.new(1)
        m.authorize(good_plan(m), snap, lim, reg)
        full = m.authorize(good_plan(m, 'SIG-2'), snap, lim, reg)
        if not (full.decision == 'BLOCK' and full.primary_reason == 'REGISTRY_FULL' and reg.count == 1 and reg.ids == ['SIG-1']):
            bad.append('SEQ_REGISTRY_OVERFLOW_BLOCKS_NOT_DROPS')
    except Exception:
        bad.append('SEQ_REGISTRY_OVERFLOW_RAISED')
    try:
        reg = m.Registry.new(4)
        before = (list(reg.ids), reg.count)
        m.check_permit(good_plan(m), snap, lim, reg)
        if (list(reg.ids), reg.count) != before:
            bad.append('SEQ_CHECK_PERMIT_IS_PURE')
    except Exception:
        bad.append('SEQ_CHECK_PERMIT_RAISED')
    return bad


class TableTests(unittest.TestCase):
    def test_every_hand_computed_plan_permit_cancel_and_sequence(self):
        self.assertEqual(behaviour_failures(ref), [])

    def test_plan_rows_one_by_one(self):
        for c in PLAN_CASES:
            with self.subTest(c['name']):
                p = call_plan(ref, c)
                self.assertEqual((p.status, p.stage), (c['status'], c['stage']), p.reason)
                self.assertEqual(p.plan_label, 'PLAN_ONLY / NOT_AN_ORDER')
                if c['exp'] is None:
                    self.assertTrue(p.reason)
                    self.assertTrue(p.reason.startswith(c['why']), p.reason)
                    for f in NUMERIC:
                        self.assertEqual(getattr(p, f), 0, f)
                    self.assertFalse(p.tp_equals_2r)
                    if c['under']:
                        self.assertEqual(p.under_status, c['under'])
                        self.assertTrue(p.under_reason.startswith(c['under_why']), p.under_reason)
                else:
                    self.assertEqual(p.reason, '')
                    for f, v in zip(NUMERIC, c['exp']):
                        self.assertTrue(same(getattr(p, f), v), '%s %r != %r' % (f, getattr(p, f), v))
                    self.assertEqual((p.under_status, p.under_reason), ('', ''))
                self.assertEqual(p.signal_id, c['args'][0])
                self.assertEqual(p.setup_id, c['args'][1])


class PlanTests(unittest.TestCase):
    def test_plan_calls_the_real_modules_and_passes_the_geometry_result_to_sizing(self):
        c = PLAN_BY_NAME['BUY_TARGET_FARTHER']
        with mock.patch.object(g5, 'compute', wraps=g5.compute) as gc, mock.patch.object(p6, 'size', wraps=p6.size) as sz:
            p = call_plan(ref, c)
        self.assertEqual(gc.call_count, 1)
        self.assertEqual(sz.call_count, 1)
        geo = g5.compute('BUY', 1950.40, 1944.15, 0.01, 2, 0.01, 0, 1970.00, None, None)
        self.assertEqual(sz.call_args[0][0], geo)
        siz = p6.size(geo, 1234.56, 1.0, 0.01, 0.01, 100.0, 10.0)
        self.assertEqual((p.e_out, p.s_out, p.tp, p.level_2r, p.partial_price, p.r_geom), (geo.e_out, geo.s_out, geo.tp, geo.level_2r, geo.partial_price, geo.r_geom))
        self.assertEqual((p.volume_out, p.risk_model), (siz.volume_out, siz.risk_realized))

    def test_sizing_is_not_called_after_a_geometry_refusal_and_ids_come_first(self):
        with mock.patch.object(p6, 'size', wraps=p6.size) as sz:
            call_plan(ref, PLAN_BY_NAME['GEO_SL_WRONG_SIDE_BUY'])
        self.assertEqual(sz.call_count, 0)
        with mock.patch.object(g5, 'compute', wraps=g5.compute) as gc:
            call_plan(ref, PLAN_BY_NAME['ID_EMPTY_SIGNAL'])
        self.assertEqual(gc.call_count, 0)

    def test_every_geometry_status_is_propagated_with_its_reason(self):
        for name in ('GEO_SL_WRONG_SIDE_BUY', 'GEO_ZERO_RISK', 'GEO_BAD_DIRECTION', 'GEO_INCOMPATIBLE_TICK', 'GEO_NONPOSITIVE_PRICE',
                     'GEO_TARGET_WRONG_SIDE', 'GEO_BELOW_STOPS_LEVEL', 'GEO_PENDING_TOO_CLOSE'):
            c = PLAN_BY_NAME[name]
            sid, setup, d, e, s, t, budget, tv, sym, quote, vol = c['args']
            geo = g5.compute(d, e, s, sym[0], sym[1], sym[2], sym[3], t, *(quote or (None, None)))
            p = call_plan(ref, c)
            self.assertEqual((p.under_status, p.under_reason), (geo.status, geo.reason), name)
            self.assertIn(geo.reason, p.reason)
            self.assertEqual(p.stage, 'GEOMETRY')

    def test_every_sizing_status_is_propagated_with_its_reason(self):
        for name in ('SIZ_BELOW_MIN', 'SIZ_ROUNDS_TO_ZERO', 'SIZ_ABOVE_MAX', 'SIZ_ABOVE_CAP_BUY', 'SIZ_ABOVE_CAP_SELL', 'SIZ_BAD_STEP',
                     'SIZ_OFF_GRID_MIN', 'SIZ_BAD_BUDGET', 'SIZ_BAD_TICK_VALUE'):
            c = PLAN_BY_NAME[name]
            sid, setup, d, e, s, t, budget, tv, sym, quote, vol = c['args']
            geo = g5.compute(d, e, s, sym[0], sym[1], sym[2], sym[3], t, *(quote or (None, None)))
            siz = p6.size(geo, budget, tv, *vol)
            p = call_plan(ref, c)
            self.assertEqual((p.under_status, p.under_reason), (siz.status, siz.reason), name)
            self.assertEqual(p.stage, 'SIZING')

    def test_buy_and_mirrored_sell_give_the_same_distances_volume_and_risk(self):
        for a, b in (('BUY_BASIC', 'SELL_BASIC'), ('BUY_TICK005', 'SELL_TICK005'), ('BUY_NORMALIZED', 'SELL_NORMALIZED')):
            pa, pb = call_plan(ref, PLAN_BY_NAME[a]), call_plan(ref, PLAN_BY_NAME[b])
            self.assertEqual((pa.r_geom, pa.volume_out, pa.risk_model), (pb.r_geom, pb.volume_out, pb.risk_model))
            self.assertEqual(round(pa.level_2r - pa.e_out, 2), round(pb.e_out - pb.level_2r, 2))

    def test_partial_point_is_the_2r_level_and_has_no_volume_split(self):
        p = call_plan(ref, PLAN_BY_NAME['BUY_TARGET_FARTHER'])
        self.assertEqual(p.partial_price, p.level_2r)
        self.assertNotEqual(p.partial_price, p.tp)
        self.assertIn('PARTIAL_AT_2R', p.partial_label)
        self.assertIn('80%', p.partial_label)
        self.assertEqual(p.risk_label, 'LINEAR_MODEL, COSTS_NOT_MODELLED')
        fields = {f.name for f in dataclasses.fields(ref.Plan)}
        self.assertFalse({n for n in fields if re.search(r'partial_vol|volume_80|volume_20|remainder|ticket|order|magic', n)})

    def test_invalid_ids_are_input_errors_with_a_tag_and_zero_numbers(self):
        for bad in ('', ' ', '\t', None, 5, b'x'):
            p = call_plan(ref, PLAN_BY_NAME['BUY_BASIC'], sid=bad)
            self.assertEqual((p.status, p.stage), ('INVALID_INPUT', 'INPUT'))
            self.assertTrue(p.reason.startswith('INVALID_SIGNAL_ID'))
            p = call_plan(ref, PLAN_BY_NAME['BUY_BASIC'], setup=bad)
            self.assertEqual((p.status, p.stage), ('INVALID_INPUT', 'INPUT'))
            self.assertTrue(p.reason.startswith('INVALID_SETUP_ID'))
            self.assertTrue(all(getattr(p, f) == 0 for f in NUMERIC))

    def test_non_finite_numbers_are_refused_not_planned(self):
        base = PLAN_BY_NAME['BUY_BASIC']
        for over in (dict(e=NAN), dict(s=INF), dict(t=NAN), dict(budget=NAN), dict(budget=INF), dict(tv=NAN), dict(tv=INF)):
            p = call_plan(ref, base, **over)
            self.assertNotEqual(p.status, 'OK', over)
            self.assertTrue(all(getattr(p, f) == 0 for f in NUMERIC))

    def test_plan_is_immutable_and_inputs_are_not_changed(self):
        c = PLAN_BY_NAME['BUY_WITH_QUOTE']
        args_before = repr(c['args'])
        p1, p2 = call_plan(ref, c), call_plan(ref, c)
        self.assertEqual(p1, p2)
        self.assertEqual(repr(c['args']), args_before)
        with self.assertRaises(dataclasses.FrozenInstanceError):
            p1.volume_out = 5.0


class PermitTests(unittest.TestCase):
    def test_permit_rows_one_by_one(self):
        for c in PERMIT_CASES:
            with self.subTest(c['name']):
                p = call_plan(ref, PLAN_BY_NAME[c['plan']])
                r = ref.check_permit(p, snap_of(ref, c), limits_of(ref, c), registry_of(ref, c))
                exp = tuple(x for x in c['reasons'].split('|') if x)
                self.assertEqual(r.decision, c['dec'])
                self.assertEqual(r.reasons, exp)
                self.assertEqual(r.primary_reason, exp[0] if exp else '')
                self.assertEqual(r.label, 'PERMIT_ONLY / NOT_AN_ORDER')
                self.assertFalse(r.registered)

    def test_reason_order_is_fixed_and_documented(self):
        order = ['PLAN_NOT_OK', 'DATA_NOT_READY', 'SESSION_CLOSED', 'NEWS_BLOCK', 'SPREAD_BLOCK', 'DUPLICATE_SIGNAL',
                 'MAX_POSITIONS_REACHED', 'MAX_TRADES_REACHED', 'COMBINED_RISK_EXCEEDED']
        doc = ref.__doc__
        pos = [doc.index(t) for t in order]
        self.assertEqual(pos, sorted(pos))
        r = ref.check_permit(None, ref.Snapshot(data_state='NOT_READY', session_state='CLOSED', news_state='BLOCKED', spread_state='BLOCKED',
                                                open_positions=3, trades_today=5, existing_risk=9999.0),
                             ref.Limits(3, 5, 5000.0), ref.Registry.new(2))
        self.assertEqual(r.reasons, ('PLAN_NOT_OK', 'DATA_NOT_READY', 'SESSION_CLOSED', 'NEWS_BLOCK', 'SPREAD_BLOCK',
                                     'MAX_POSITIONS_REACHED', 'MAX_TRADES_REACHED'))

    def test_a_plan_that_is_not_an_ok_plan_object_blocks(self):
        for junk in (None, 5, 'OK', object(), types.SimpleNamespace(status='OK_LOOKING')):
            r = ref.check_permit(junk, ref.Snapshot(), ref.Limits(3, 5, 5000.0), ref.Registry.new(2))
            self.assertEqual(r.decision, 'BLOCK')
            self.assertEqual(r.primary_reason, 'PLAN_NOT_OK')

    def test_defaults_alone_never_allow_because_limits_are_unset(self):
        r = ref.check_permit(good_plan(ref), ref.Snapshot(), ref.Limits(), ref.Registry.new(2))
        self.assertEqual(r.decision, 'BLOCK')
        self.assertEqual(r.reasons, ('POLICY_UNSET:max_positions', 'POLICY_UNSET:max_trades_per_day', 'POLICY_UNSET:combined_risk_cap'))

    def test_each_unset_limit_blocks_with_its_own_tag_even_when_everything_else_is_fine(self):
        for field, tag in (('max_positions', 'max_positions'), ('max_trades_per_day', 'max_trades_per_day'),
                           ('combined_risk_cap', 'combined_risk_cap')):
            kw = dict(FULL_LIMITS)
            kw[field] = None
            r = ref.check_permit(good_plan(ref), ref.Snapshot(), ref.Limits(**kw), ref.Registry.new(2))
            self.assertEqual(r.reasons, ('POLICY_UNSET:' + tag,))

    def test_invalid_numbers_and_types_block_fail_closed(self):
        plan = good_plan(ref)
        lim = ref.Limits(**FULL_LIMITS)
        for bad in (-1, 1.5, NAN, INF, None, True, '1'):
            r = ref.check_permit(plan, ref.Snapshot(open_positions=bad), lim, ref.Registry.new(2))
            self.assertEqual(r.reasons, ('INVALID_SNAPSHOT:open_positions',), bad)
            r = ref.check_permit(plan, ref.Snapshot(trades_today=bad), lim, ref.Registry.new(2))
            self.assertEqual(r.reasons, ('INVALID_SNAPSHOT:trades_today',), bad)
        for bad in (-1.0, NAN, INF, None, True, '1'):
            r = ref.check_permit(plan, ref.Snapshot(existing_risk=bad), lim, ref.Registry.new(2))
            self.assertEqual(r.reasons, ('INVALID_SNAPSHOT:existing_risk',), bad)
        for bad in (-1.0, NAN, INF, True, '1'):
            r = ref.check_permit(plan, ref.Snapshot(), ref.Limits(3, 5, bad), ref.Registry.new(2))
            self.assertEqual(r.reasons, ('INVALID_SNAPSHOT:combined_risk_cap',), bad)
        for bad in (-1, 1.5, True, '3'):
            r = ref.check_permit(plan, ref.Snapshot(), ref.Limits(bad, 5, 5000.0), ref.Registry.new(2))
            self.assertEqual(r.reasons, ('INVALID_SNAPSHOT:max_positions',), bad)
            r = ref.check_permit(plan, ref.Snapshot(), ref.Limits(3, bad, 5000.0), ref.Registry.new(2))
            self.assertEqual(r.reasons, ('INVALID_SNAPSHOT:max_trades_per_day',), bad)
        r = ref.check_permit(plan, ref.Snapshot(data_reliable=None), lim, ref.Registry.new(2))
        self.assertEqual(r.reasons, ('DATA_UNRELIABLE',))

    def test_risk_boundary_is_inclusive_with_only_binary_noise_tolerance(self):
        plan = good_plan(ref)
        self.assertEqual(plan.risk_model, 1231.25)
        for cap in (1231.25, 1.0e4, 123456.78):
            lim = ref.Limits(3, 5, cap)
            at = cap - plan.risk_model
            self.assertEqual(ref.check_permit(plan, ref.Snapshot(existing_risk=at), lim, ref.Registry.new(2)).decision, 'ALLOW', cap)
            self.assertEqual(ref.check_permit(plan, ref.Snapshot(existing_risk=at + 1e-6), lim, ref.Registry.new(2)).decision, 'BLOCK', cap)
            self.assertEqual(ref.check_permit(plan, ref.Snapshot(existing_risk=at + 0.01), lim, ref.Registry.new(2)).decision, 'BLOCK', cap)

    def test_registry_invalid_count_and_capacity(self):
        plan = good_plan(ref)
        lim = ref.Limits(**FULL_LIMITS)
        for count in (-1, 3, 1.5, None):
            reg = ref.Registry(ids=['', ''], count=count)
            r = ref.check_permit(plan, ref.Snapshot(), lim, reg)
            self.assertEqual(r.reasons, ('REGISTRY_INVALID',), count)
        reg = ref.Registry(ids=[], count=0)
        self.assertEqual(ref.authorize(plan, ref.Snapshot(), lim, reg).reasons, ('REGISTRY_FULL',))
        self.assertEqual((reg.ids, reg.count), ([], 0))

    def test_registry_is_only_changed_by_an_allow_and_only_by_the_signal_id(self):
        plan = good_plan(ref)
        lim = ref.Limits(**FULL_LIMITS)
        snap = ref.Snapshot()
        reg = ref.Registry.new(3)
        reg.ids[0], reg.count = 'OLD', 1
        before = (list(reg.ids), reg.count, repr(snap), repr(lim), repr(plan))
        r = ref.authorize(plan, snap, lim, reg)
        self.assertEqual((r.decision, r.registered), ('ALLOW', True))
        self.assertEqual((reg.ids, reg.count), (['OLD', 'SIG-1', ''], 2))
        self.assertEqual((repr(snap), repr(lim), repr(plan)), before[2:])
        blocked = ref.authorize(plan, ref.Snapshot(session_state='CLOSED'), lim, reg)
        self.assertEqual((blocked.decision, blocked.registered), ('BLOCK', False))
        self.assertEqual((reg.ids, reg.count), (['OLD', 'SIG-1', ''], 2))

    def test_an_allow_is_a_permit_not_an_order(self):
        r = ref.authorize(good_plan(ref), ref.Snapshot(), ref.Limits(**FULL_LIMITS), ref.Registry.new(2))
        self.assertEqual(r.decision, 'ALLOW')
        self.assertIn('NOT_AN_ORDER', r.label)
        self.assertFalse({f.name for f in dataclasses.fields(ref.Permit)} & {'ticket', 'order', 'volume', 'price'})


class CancelTests(unittest.TestCase):
    def test_cancel_rows_one_by_one(self):
        for c in CANCEL_CASES:
            with self.subTest(c['name']):
                r = ref.cancel_decision(c['pend'], c['pid'], c['pos'], c['ev'])
                self.assertEqual(r.status, c['status'], r.reason)
                self.assertEqual(r.reasons, tuple(x for x in c['reasons'].split('|') if x))
                self.assertTrue(r.positions_untouched)
                self.assertEqual(r.position_present, c['pos'])
                self.assertEqual(r.label, 'CANCEL_REQUEST_ONLY / NOT_SENT')

    def test_positions_are_untouched_for_every_event_mask_and_flag_combination(self):
        for pend in (False, True):
            for pos in (False, True):
                for ev in range(0, 32):
                    r = ref.cancel_decision(pend, 'SIG-1', pos, ev)
                    self.assertTrue(r.positions_untouched)
                    self.assertEqual(r.cancel_pending, pend and ev != 0)
                    self.assertEqual(r.status == 'CANCEL_REQUEST', pend and ev != 0)
                    if r.status == 'CANCEL_REQUEST':
                        self.assertEqual(r.pending_signal_id, 'SIG-1')
                        self.assertEqual(len(r.reasons), bin(ev).count('1'))
        self.assertFalse({f.name for f in dataclasses.fields(ref.CancelDecision)} &
                         {'close_positions', 'cancel_positions', 'close_position', 'ticket'})

    def test_reasons_follow_the_fixed_order(self):
        r = ref.cancel_decision(True, 'SIG-1', False, 31)
        self.assertEqual(r.reasons, ('DIRECTION_CHANGE', 'OPPOSITE_SIGNAL', 'SESSION_END', 'NEWS_BLOCK', 'DAILY_LIMIT'))

    def test_unknown_events_and_types_are_invalid_input(self):
        for ev in (32, 33, 63, 64, 1 << 20, -1, 1.0, None, True, '4'):
            r = ref.cancel_decision(True, 'SIG-1', True, ev)
            self.assertEqual(r.status, 'INVALID_INPUT', ev)
            self.assertFalse(r.cancel_pending)
            self.assertTrue(r.reason.startswith('INVALID_EVENTS'))
            self.assertTrue(r.positions_untouched)

    def test_no_time_expiry_cooldown_or_reentry_exists(self):
        names = {f.name for f in dataclasses.fields(ref.CancelDecision)}
        self.assertFalse({n for n in names if re.search(r'expir|cooldown|reentry|re_entry|candle|bars|seconds', n)})
        self.assertEqual(set(ref.EVENT_ORDER[i][1] for i in range(5)),
                         {'DIRECTION_CHANGE', 'OPPOSITE_SIGNAL', 'SESSION_END', 'NEWS_BLOCK', 'DAILY_LIMIT'})


class IntegrationTests(unittest.TestCase):
    def test_geometry_sizing_plan_permit_cancel_chain_buy_and_sell(self):
        lim = ref.Limits(**FULL_LIMITS)
        for name, sid, e_out, tp, vol in (('BUY_BASIC', 'SIG-B', 1950.40, 1962.90, 1.97), ('SELL_BASIC', 'SIG-S', 2310.20, 2297.70, 1.97)):
            plan = call_plan(ref, PLAN_BY_NAME[name], sid=sid)
            self.assertEqual((plan.status, plan.e_out, plan.tp, plan.volume_out, plan.risk_model), ('OK', e_out, tp, vol, 1231.25))
            reg = ref.Registry.new(4)
            permit = ref.authorize(plan, ref.Snapshot(open_positions=1, trades_today=2, existing_risk=2000.0), lim, reg)
            self.assertEqual((permit.decision, permit.registered, reg.ids[0]), ('ALLOW', True, sid))
            again = ref.authorize(plan, ref.Snapshot(), lim, reg)
            self.assertEqual((again.decision, again.primary_reason), ('BLOCK', 'DUPLICATE_SIGNAL'))
            cancel = ref.cancel_decision(True, plan.signal_id, True, ref.EV_SESSION_END | ref.EV_DAILY_LIMIT)
            self.assertEqual((cancel.status, cancel.reasons, cancel.pending_signal_id, cancel.positions_untouched),
                             ('CANCEL_REQUEST', ('SESSION_END', 'DAILY_LIMIT'), sid, True))

    def test_a_refused_plan_never_reaches_a_permit_and_never_registers(self):
        reg = ref.Registry.new(2)
        for name in ('GEO_SL_WRONG_SIDE_BUY', 'SIZ_ABOVE_CAP_SELL', 'ID_EMPTY_SIGNAL'):
            r = ref.authorize(call_plan(ref, PLAN_BY_NAME[name]), ref.Snapshot(), ref.Limits(**FULL_LIMITS), reg)
            self.assertEqual((r.decision, r.primary_reason, r.registered), ('BLOCK', 'PLAN_NOT_OK', False))
        self.assertEqual((reg.ids, reg.count), (['', ''], 0))


def load_mutant(old, new, count=1):
    with open(os.path.join(ROOT, 'tests', 't007_planning_reference.py'), encoding='ascii') as fh:
        src = fh.read()
    assert src.count(old) == count, (old, src.count(old))
    ns = {'__name__': 't007_mutant'}
    exec(compile(src.replace(old, new), 't007_mutant', 'exec'), ns)
    return types.SimpleNamespace(**ns)


POS_UNSET = "    if limits.max_positions is None:\n        reasons.append('POLICY_UNSET:max_positions')\n"
TRD_UNSET = "    if limits.max_trades_per_day is None:\n        reasons.append('POLICY_UNSET:max_trades_per_day')\n"
CAP_UNSET = "    if cap is None:\n        reasons.append('POLICY_UNSET:combined_risk_cap')\n"
REGISTER = "    if permit.decision != ALLOW:\n        return permit\n"
MUTANTS = {
    'POLICY_UNSET positions ignored (unset = unlimited)': (POS_UNSET, "    if limits.max_positions is None:\n        pass\n", 'POLICY_UNSET_POSITIONS'),
    'POLICY_UNSET trades ignored (unset = unlimited)': (TRD_UNSET, "    if limits.max_trades_per_day is None:\n        pass\n", 'POLICY_UNSET_TRADES'),
    'POLICY_UNSET cap ignored (unset = unlimited)': (CAP_UNSET, "    if cap is None:\n        pass\n", 'POLICY_UNSET_RISK_CAP'),
    'registering also on BLOCK': (REGISTER, "    if False:\n        return permit\n", 'SEQ_BLOCKED_ATTEMPT_DOES_NOT_CONSUME_ID'),
    'never registering': ("    registry.ids[registry.count] = plan.signal_id\n    registry.count += 1\n", "", 'SEQ_FIRST_AUTHORIZATION_REGISTERS'),
    'allow at max positions': ("snap.open_positions >= limits.max_positions", "snap.open_positions > limits.max_positions", 'POSITIONS_AT_MAX'),
    'allow at max trades': ("snap.trades_today >= limits.max_trades_per_day", "snap.trades_today > limits.max_trades_per_day", 'TRADES_AT_MAX'),
    'block exactly at the risk cap': ("> cap + RISK_ULPS * DBL_EPSILON * max(1.0, cap)", ">= cap", 'RISK_EXACTLY_AT_CAP'),
    'no binary noise tolerance': ("> cap + RISK_ULPS * DBL_EPSILON * max(1.0, cap)", "> cap", 'RISK_BINARY_NOISE_AT_CAP'),
    'tolerance too wide (swallows a real excess)': ("RISK_ULPS * DBL_EPSILON * max(1.0, cap)", "0.1", 'RISK_BINARY_NOISE_REAL_EXCESS'),
    'plan status ignored': ("plan_ok = getattr(plan, 'status', None) == OK", "plan_ok = True", 'PLAN_GEOMETRY_REFUSED'),
    'unreliable data allowed': ("        if snap.data_reliable is not True:\n            reasons.append('DATA_UNRELIABLE')\n",
                                "        pass\n", 'DATA_UNRELIABLE'),
    'unknown news allowed': ("    elif snap.news_state == NEWS_UNKNOWN:\n        reasons.append('NEWS_UNKNOWN')\n",
                             "    elif snap.news_state == NEWS_UNKNOWN:\n        pass\n", 'NEWS_UNKNOWN'),
    'duplicate not detected': ("if sid in registry.ids[:registry.count]:", "if False:", 'REGISTRY_DUPLICATE'),
    'registry overflow ignored': ("        elif registry.count >= capacity:\n            reasons.append('REGISTRY_FULL')\n",
                                  "        elif False:\n            pass\n", 'REGISTRY_FULL_NEW_ID'),
    'position alone gives a cancel request': ("    if not pending_exists:\n        return CancelDecision(status=NO_PENDING",
                                              "    if not (pending_exists or pos):\n        return CancelDecision(status=NO_PENDING", 'POSITION_ONLY_NO_REQUEST'),
    'positions_untouched can be False': ("positions_untouched: bool = True ", "positions_untouched: bool = False ", 'CAUSE_SESSION_END'),
    'unknown event bit accepted': (" or (events & ~EV_ALL) != 0", "", 'UNKNOWN_EVENT_32'),
    'events validated after pending check': ("    if isinstance(events, bool) or not isinstance(events, int) or events < 0 or (events & ~EV_ALL) != 0:",
                                              "    if False:", 'UNKNOWN_EVENT_WITHOUT_PENDING'),
    'tp taken from level_2r': ("tp=geo.tp,", "tp=geo.level_2r,", 'BUY_TARGET_FARTHER'),
    'risk_model is the budget': ("risk_model=siz.risk_realized", "risk_model=risk_budget", 'BUY_BASIC'),
    'sizing refusal ignored': ("    if siz.status != p6.OK:\n", "    if False:\n", 'SIZ_ABOVE_CAP_BUY'),
    'geometry refusal ignored': ("    if geo.status != g5.OK:\n", "    if False:\n", 'GEO_SL_WRONG_SIDE_BUY'),
    'ids not validated': ("    if _blank(signal_id):\n", "    if False:\n", 'ID_EMPTY_SIGNAL'),
}


class MutationTests(unittest.TestCase):
    def test_the_unmutated_reference_has_no_failures(self):
        self.assertEqual(behaviour_failures(ref), [])

    def test_each_defective_copy_is_caught_by_the_named_row_or_sequence(self):
        for name, (old, new, expect) in MUTANTS.items():
            with self.subTest(name):
                bad = behaviour_failures(load_mutant(old, new))
                self.assertIn(expect, bad, '%s was not caught by %s (failures: %s)' % (name, expect, bad))


class SyncAndScopeTests(unittest.TestCase):
    def test_mql_fixture_block_equals_generated_text(self):
        with open(os.path.join(ROOT, 'src', 'tests', 'T007_PlanningTest.mq5'), encoding='ascii') as fh:
            text = fh.read()
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', text, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), emit_mql())

    def test_reference_has_no_trading_clock_random_or_file_use(self):
        with open(os.path.join(ROOT, 'tests', 't007_planning_reference.py'), encoding='ascii') as fh:
            src = fh.read()
        code = re.sub(r'(?s)""".*?"""|#[^\n]*', '', src)
        for word in ('time', 'datetime', 'random', 'os', 'sys', 'json', 'pickle', 'sqlite3', 'socket'):
            self.assertIsNone(re.search(r'^\s*(import|from)\s+%s\b' % word, code, re.M), word)
        for word in ('open(', 'OrderSend', 'print('):
            self.assertNotIn(word, code)

    def test_every_fixture_name_is_unique_and_permit_plans_exist(self):
        for rows in (PLAN_CASES, PERMIT_CASES, CANCEL_CASES):
            names = [c['name'] for c in rows]
            self.assertEqual(len(names), len(set(names)))
        for c in PERMIT_CASES:
            self.assertIn(c['plan'], PLAN_BY_NAME)

    def test_the_documented_boundary_proposals_are_stated_in_the_header(self):
        doc = ref.__doc__
        for text in ('open_positions < max_positions allows, == blocks', 'trades_today < max_trades_per_day allows, == blocks',
                     'exactly at the cap is ALLOWED', 'NOT atomic, NOT persistent', 'never consumes', 'REGISTRY_FULL',
                     'positions_untouched is ALWAYS True', 'PLAN_ONLY / NOT_AN_ORDER', 'NOT decided here'):
            self.assertIn(text, doc)
        self.assertTrue(math.isfinite(ref.RISK_ULPS))


if __name__ == '__main__':
    unittest.main()
