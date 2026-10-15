"""T014 SETUP -> PLAN bridge (Python mirror of src/include/SetupPlanBridge.mqh): turns ONE existing T004 candidate into a T007 plan request and calls the existing plan builder. PURE: no terminal read,
no clock (asof and live_after are arguments), no order, no permit, no execution record, no file. It does NOT detect H4 / M15 structure (the T004 observer state is the input), it does NOT copy the
geometry or sizing formulas (the plan comes from t007_planning_reference.build_plan) and it chooses NOTHING: every selection below is EXPLICIT and an unset one is a BLOCK with its name.

Output: a plan (plan_ready) or ONE concrete blocking reason. A plan is NOT a trade permission: the permit checks and the entry executor are separate steps.
WAIT_RETURN is the only phase that can yield a candidate for a PENDING order (the FVG exists and the price has not come back). RETURN_OBSERVED (a return already happened) never creates a delayed entry.
Identities are deterministic from the observer's own identities (never from a clock, a counter or the number of replays):
  setup_id  = 'S|' + context.source + '|' + context.setup + '|' + context.fvg + '|' + broken level id
  signal_id = setup_id + '|' + candidate id            (the candidate id already carries the time of its first candle and the direction)
A restart or a replay of the same bars therefore gives the SAME ids and the entry executor's one-record-per-signal rule keeps blocking."""
import math
from dataclasses import dataclass, field

import t004_reference as m4
import t007_planning_reference as tp
import t005_geometry_reference as tg

SWING_UNSET, SWING_LATEST_FRACTAL_PROPOSAL, SWING_SUPPLIED = 0, 1, 2
CAND_UNSET, CAND_EXPLICIT_ID, CAND_SOLE_ELIGIBLE = 0, 1, 2
EDGE_UNSET, EDGE_NEAR_SIDE, EDGE_FAR_SIDE = 0, 1, 2          # NEAR = the edge the price meets first on the return (BUY upper, SELL lower); FAR = the other edge
SL_UNSET, SL_BROKEN_LEVEL_PRICE, SL_SUPPLIED = 0, 1, 2
TGT_UNSET, TGT_NONE_2R_MINIMUM, TGT_SUPPLIED = 0, 1, 2

SWING_NAMES = {SWING_LATEST_FRACTAL_PROPOSAL: 'LATEST_FRACTAL_PROPOSAL', SWING_SUPPLIED: 'SUPPLIED'}
EDGE_NAMES = {EDGE_NEAR_SIDE: 'NEAR_SIDE', EDGE_FAR_SIDE: 'FAR_SIDE'}
SL_NAMES = {SL_BROKEN_LEVEL_PRICE: 'BROKEN_LEVEL_PRICE', SL_SUPPLIED: 'SUPPLIED'}
TGT_NAMES = {TGT_NONE_2R_MINIMUM: 'NONE_2R_MINIMUM', TGT_SUPPLIED: 'SUPPLIED'}


@dataclass
class Selection:
    context_source: str = ''
    swing_selector: int = SWING_UNSET
    timing_policy: int = m4.UNSET
    candidate_selector: int = CAND_UNSET
    candidate_id: str = ''
    entry_edge: int = EDGE_UNSET
    sl_rule: int = SL_UNSET
    sl_buffer_set: bool = False
    sl_buffer: float = 0.0
    sl_price: float = 0.0
    target_rule: int = TGT_UNSET
    target_price: float = 0.0
    target_source: str = ''
    live_after: int = 0


@dataclass
class Market:
    risk_budget: float = -1.0
    tick_value: float = -1.0
    tick_size: float = 0.0
    digits: int = -1
    point: float = 0.0
    stops_level: int = -1
    has_quote: bool = False
    bid: float = 0.0
    ask: float = 0.0
    vol_min: float = 0.0
    vol_step: float = 0.0
    vol_max: float = 0.0
    cap_lots: float = 0.0


@dataclass
class Result:
    plan_ready: bool = False
    reason: str = ''
    setup_id: str = ''
    signal_id: str = ''
    candidate_id: str = ''
    provenance: str = ''
    plan: object = None
    e_raw: float = 0.0
    s_raw: float = 0.0
    target_raw: object = None


def _fin(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)


def _blank(s):
    return not isinstance(s, str) or s.strip() == ''


def unset_fields(sel, asof):
    bad = []
    if _blank(sel.context_source):
        bad.append('context_source')
    if sel.swing_selector not in SWING_NAMES:
        bad.append('swing_selector')
    if sel.timing_policy != m4.A_AT_OR_AFTER_BREAK:
        bad.append('timing_policy')
    if sel.candidate_selector not in (CAND_EXPLICIT_ID, CAND_SOLE_ELIGIBLE):
        bad.append('candidate_selector')
    elif sel.candidate_selector == CAND_EXPLICIT_ID and _blank(sel.candidate_id):
        bad.append('candidate_id')
    if sel.entry_edge not in EDGE_NAMES:
        bad.append('entry_edge')
    if sel.sl_rule not in SL_NAMES:
        bad.append('sl_rule')
    elif sel.sl_rule == SL_BROKEN_LEVEL_PRICE and not (sel.sl_buffer_set and _fin(sel.sl_buffer) and sel.sl_buffer >= 0.0):
        bad.append('sl_buffer')
    elif sel.sl_rule == SL_SUPPLIED and not (_fin(sel.sl_price) and sel.sl_price > 0.0):
        bad.append('sl_price')
    if sel.target_rule not in TGT_NAMES:
        bad.append('target_rule')
    elif sel.target_rule == TGT_SUPPLIED and not (_fin(sel.target_price) and sel.target_price > 0.0 and not _blank(sel.target_source)):
        bad.append('target_price_and_source')
    if not sel.live_after > 0:
        bad.append('live_after')
    if not asof > 0:
        bad.append('asof')
    return bad


def ids(ob, broken, cand_id):
    setup = 'S|%s|%s|%s|%s' % (ob.context.source, ob.context.setup, ob.context.fvg, broken.id)
    return setup, setup + '|' + cand_id


def _block(reason, **kw):
    return Result(False, reason, **kw)


def prepare(sel, mkt, ob, broken, asof):
    """ob = the T004 observer state (phase, policy, context, candidates, bos_*), broken = the level the observer recorded; both are READ ONLY here"""
    bad = unset_fields(sel, asof)
    if bad:
        return _block('SELECTION_UNSET: ' + ', '.join(bad))
    c = ob.context
    if c is None or ob.phase == 'WAIT_CONTEXT' or not (c.ready and c.reliable and c.selected) or c.direction not in (1, -1):
        return _block('CONTEXT_LOST_OR_NOT_READY')
    if c.source != sel.context_source:
        return _block('CONTEXT_SOURCE_MISMATCH: the observer runs on %s, the selection names %s' % (c.source, sel.context_source))
    if ob.policy != sel.timing_policy:
        return _block('TIMING_MISMATCH: the observer policy differs from the selected timing')
    if ob.phase == 'REPLAY_REQUIRED':
        return _block('REPLAY_REQUIRED: a revised history never becomes a signal')
    if ob.phase == 'RETURN_OBSERVED':
        return _block('RETURN_ALREADY_OBSERVED: the price already came back; no delayed entry')
    if ob.phase != 'WAIT_RETURN':
        return _block('PHASE_NOT_WAIT_RETURN: ' + ob.phase)
    if ob.last_asof > asof or c.valid_from > asof or ob.bos_known > asof:
        return _block('FUTURE_DATA: the observer holds data newer than asof')
    if broken is None or _blank(broken.id) or broken.id != ob.bos_level or not (_fin(broken.price) and broken.price > 0.0) or not (0 < broken.known <= ob.bos_time):
        return _block('BROKEN_LEVEL_MISMATCH: the supplied level is not the one the observer recorded')
    if broken.known > asof:
        return _block('FUTURE_DATA: the broken level is newer than asof')
    seen = set()
    for k in ob.candidates:
        if _blank(k.id) or k.id in seen:
            return _block('CANDIDATE_IDS_NOT_UNIQUE')
        seen.add(k.id)
    if sel.candidate_selector == CAND_EXPLICIT_ID:
        found = [k for k in ob.candidates if k.id == sel.candidate_id]
        if not found:
            return _block('CANDIDATE_NOT_FOUND: ' + sel.candidate_id)
        cand = found[0]
        if cand.invalid:
            return _block('CANDIDATE_INVALIDATED: ' + cand.id)
        if cand.returned:
            return _block('CANDIDATE_RETURN_ALREADY_OBSERVED: ' + cand.id)
    else:
        eligible = [k for k in ob.candidates if not k.invalid and not k.returned]
        if not eligible:
            return _block('NO_ELIGIBLE_CANDIDATE')
        if len(eligible) > 1:
            return _block('AMBIGUOUS_CANDIDATES: ' + ','.join(k.id for k in eligible) + '; none is chosen')
        cand = eligible[0]
    if not (_fin(cand.lower) and _fin(cand.upper) and 0.0 < cand.lower < cand.upper):
        return _block('CANDIDATE_BOUNDS_INVALID: ' + cand.id)
    if not cand.id.endswith('U' if c.direction == 1 else 'D'):
        return _block('CANDIDATE_DIRECTION_INCONSISTENT: ' + cand.id)
    if cand.confirmed > asof:
        return _block('FUTURE_DATA: the candidate is newer than asof')
    if cand.confirmed <= sel.live_after:
        return _block('HISTORICAL_OR_REPLAYED_CANDIDATE: formed at or before the live baseline')
    d = c.direction
    if sel.entry_edge == EDGE_NEAR_SIDE:
        e = cand.upper if d == 1 else cand.lower
    else:
        e = cand.lower if d == 1 else cand.upper
    if sel.sl_rule == SL_BROKEN_LEVEL_PRICE:
        s = broken.price - sel.sl_buffer if d == 1 else broken.price + sel.sl_buffer
    else:
        s = sel.sl_price
    t = None if sel.target_rule == TGT_NONE_2R_MINIMUM else sel.target_price
    setup_id, signal_id = ids(ob, broken, cand.id)
    prov = 'source=%s swing=%s timing=A_AT_OR_AFTER_BREAK candidate=%s:%s edge=%s sl=%s target=%s' % (
        sel.context_source, SWING_NAMES[sel.swing_selector], 'EXPLICIT_ID' if sel.candidate_selector == CAND_EXPLICIT_ID else 'SOLE_ELIGIBLE', cand.id,
        EDGE_NAMES[sel.entry_edge], SL_NAMES[sel.sl_rule], TGT_NAMES[sel.target_rule] + ('' if t is None else ':' + sel.target_source))
    return Result(False, '', setup_id, signal_id, cand.id, prov, None, e, s, t)


def geometry(sel, mkt, ob, broken, asof):
    r = prepare(sel, mkt, ob, broken, asof)
    if r.reason:
        return r, None
    geo = tg.compute(tg.BUY if ob.context.direction == 1 else tg.SELL, r.e_raw, r.s_raw, mkt.tick_size, mkt.digits, mkt.point, mkt.stops_level,
                     r.target_raw, mkt.bid if mkt.has_quote else None, mkt.ask if mkt.has_quote else None)
    if geo.status != tg.OK:
        r.reason = 'GEOMETRY_REFUSED: ' + geo.reason
        return r, None
    return r, geo


def build(sel, mkt, ob, broken, asof):
    r = prepare(sel, mkt, ob, broken, asof)
    if r.reason:
        return r
    r.plan = tp.build_plan(r.signal_id, r.setup_id, 'BUY' if ob.context.direction == 1 else 'SELL', r.e_raw, r.s_raw, r.target_raw, mkt.risk_budget, mkt.tick_value,
                           mkt.tick_size, mkt.digits, mkt.point, mkt.stops_level, mkt.bid if mkt.has_quote else None, mkt.ask if mkt.has_quote else None,
                           mkt.vol_min, mkt.vol_step, mkt.vol_max, mkt.cap_lots)
    r.plan_ready = r.plan.status == tp.OK
    if not r.plan_ready:
        r.reason = 'PLAN_REFUSED: ' + r.plan.reason
    return r
