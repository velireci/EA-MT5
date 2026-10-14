"""T007 pure trade-planning reference (Python mirror of src/include/TradePlanning.mqh).

NOT a trading rule, NOT an order. No order or trading API, no broker/account/symbol read, no clock, no live price, no file or
persistence. Every value is an ARGUMENT supplied by the caller. NOT wired to an EA. Three pure parts:

PART 1 TRADE PLAN  build_plan(...)
  The caller chooses signal_id, setup_id, direction, E_raw, S_raw, the optional T_raw, the risk budget (monetary; the base of
  the 1% is NOT chosen here), tick_value and the symbol/volume parameters. This part only CALLS the verified modules:
  t005_geometry_reference.compute (TG_Compute) and then t006_sizing_reference.size (PS_Compute) with the geometry result as
  the sizing input. It copies no formula and no normalization. It never selects an FVG, swing, target, the 1% base or the
  T002/T003 priority.
  Statuses (first failure wins): INVALID_INPUT (stage INPUT; tag INVALID_SIGNAL_ID, then INVALID_SETUP_ID; empty or blank id),
  GEOMETRY_REFUSED (stage GEOMETRY; under_status/under_reason = the T005 status and reason), SIZING_REFUSED (stage SIZING;
  under_status/under_reason = the T006 status and reason, including SKIP_*), OK (stage COMPLETE).
  OK plan: normalized e_out, s_out, tp, level_2r, partial_price (PARTIAL_AT_2R, client answer 80%, NO volume split),
  r_geom, volume_out, risk_model (= T006 risk_realized; LINEAR_MODEL, COSTS_NOT_MODELLED) and the constant label
  PLAN_ONLY / NOT_AN_ORDER. On ANY refusal every numeric plan field is 0 and reason names the stage.

PART 2 PERMIT CHECKS  check_permit(...) pure, authorize(...) = check_permit + registration
  Inputs: the plan (must be OK), a SNAPSHOT supplied by the caller (no clock, no feed inside), the LIMITS (each a value or
  UNSET = None) and a caller-owned in-memory REGISTRY of used signal_ids. Output: decision ALLOW/BLOCK, primary reason (the
  first one, '' on ALLOW) and the list of ALL blocking reasons in this FIXED order, one tag at most per group:
    1 PLAN_NOT_OK
    2 data:     DATA_NOT_READY | DATA_UNKNOWN | DATA_UNRELIABLE (state READY but the reliability flag is not True)
    3 session:  SESSION_CLOSED | SESSION_UNKNOWN
    4 news:     NEWS_BLOCK | NEWS_UNKNOWN
    5 spread:   SPREAD_BLOCK | SPREAD_UNKNOWN
    6 registry: DUPLICATE_SIGNAL | REGISTRY_FULL | REGISTRY_INVALID
    7 positions: POLICY_UNSET:max_positions | INVALID_SNAPSHOT:max_positions | INVALID_SNAPSHOT:open_positions | MAX_POSITIONS_REACHED
    8 trades:    POLICY_UNSET:max_trades_per_day | INVALID_SNAPSHOT:max_trades_per_day | INVALID_SNAPSHOT:trades_today | MAX_TRADES_REACHED
    9 risk:      POLICY_UNSET:combined_risk_cap | INVALID_SNAPSHOT:combined_risk_cap | INVALID_SNAPSHOT:existing_risk | COMBINED_RISK_EXCEEDED
  A state outside the documented values gives INVALID_SNAPSHOT:data_state / session_state / news_state / spread_state. Every
  uncertainty blocks (fail closed). A limit that is UNSET ALWAYS gives POLICY_UNSET:<name>: this module never invents the
  2-vs-3 trades, what counts as a win, the pending-order risk reservation or the manual-trade handling; those arrive only
  as supplied numbers/flags or UNSET.
  BOUNDARIES (PROPOSALS, for review, not client answers): open_positions < max_positions allows, == blocks;
  trades_today < max_trades_per_day allows, == blocks; existing_risk + plan.risk_model <= combined_risk_cap allows
  (exactly at the cap is ALLOWED: "maximum 2%"), tolerance only binary noise (RISK_ULPS = 4 ulps of max(1, cap)), so a
  sum a real cent above the cap blocks. The combined-risk comparison is skipped (not blocked a second time) when the plan
  is not OK: PLAN_NOT_OK already blocks and there is no plan risk. max_* limits are integers >= 0, the cap is finite >= 0;
  counts are integers >= 0 and existing_risk finite >= 0 (an unknown count is passed as an invalid value and blocks).
  ALLOW is a PERMIT RESULT ONLY, never an executed order.
  REGISTRY: a caller-owned list of ids (length = capacity) plus a count, in memory only. NOT atomic, NOT persistent, no
  broker recovery, no restart recovery. authorize() records the plan signal_id ONLY on ALLOW (a BLOCK never consumes the id).
  At capacity a new id is BLOCKED with REGISTRY_FULL, never dropped silently. A registry whose count is outside 0..capacity is
  REGISTRY_INVALID. A duplicate is checked before capacity.

PART 3 PENDING CANCEL DECISION  cancel_decision(...)
  Inputs: pending_exists, its signal_id, position_exists, and EXPLICIT external events as a bitmask: DIRECTION_CHANGE 1,
  OPPOSITE_SIGNAL 2, SESSION_END 4, NEWS_BLOCK 8, DAILY_LIMIT 16. Output: a cancel REQUEST object for the PENDING order only.
  Order of checks: unknown event bits or a non-integer/negative mask -> INVALID_INPUT (INVALID_EVENTS), even without a pending;
  no pending -> NO_PENDING (an open position alone never gives a cancel request); a pending with a blank id -> INVALID_INPUT
  (INVALID_PENDING_SIGNAL_ID); mask 0 -> NO_EVENT; else CANCEL_REQUEST with reasons in the fixed order DIRECTION_CHANGE,
  OPPOSITE_SIGNAL, SESSION_END, NEWS_BLOCK, DAILY_LIMIT (all lead to the same request, so the order has no semantic effect).
  positions_untouched is ALWAYS True: this decision never cancels or closes an open position. No expiry by time or candles,
  no cooldown, no re-entry, nothing is sent.

NOT decided here (open): the base of the 1%, costs, the combined 2% numbers, the 2-vs-3 trades, win/loss counting, pending
risk reservation, manual-trade ownership, session/news/spread sources and thresholds, time handling, order placement, 80/20
volume split, expiry, cooldown, re-entry, restart recovery, EA wiring.
"""
import math
from dataclasses import dataclass

import t005_geometry_reference as g5
import t006_sizing_reference as p6

OK = 'OK'
INVALID_INPUT = 'INVALID_INPUT'
GEOMETRY_REFUSED = 'GEOMETRY_REFUSED'
SIZING_REFUSED = 'SIZING_REFUSED'

STAGE_INPUT = 'INPUT'
STAGE_GEOMETRY = 'GEOMETRY'
STAGE_SIZING = 'SIZING'
STAGE_COMPLETE = 'COMPLETE'

PLAN_LABEL = 'PLAN_ONLY / NOT_AN_ORDER'
PERMIT_LABEL = 'PERMIT_ONLY / NOT_AN_ORDER'
CANCEL_LABEL = 'CANCEL_REQUEST_ONLY / NOT_SENT'
PARTIAL_LABEL = 'PARTIAL_AT_2R (client answer: 80% of initial volume; no volume split here)'
RISK_LABEL = 'LINEAR_MODEL, COSTS_NOT_MODELLED'

DATA_READY, DATA_NOT_READY, DATA_UNKNOWN = 'READY', 'NOT_READY', 'UNKNOWN'
SESSION_OPEN, SESSION_CLOSED, SESSION_UNKNOWN = 'OPEN', 'CLOSED', 'UNKNOWN'
NEWS_CLEAR, NEWS_BLOCKED, NEWS_UNKNOWN = 'CLEAR', 'BLOCKED', 'UNKNOWN'
SPREAD_CLEAR, SPREAD_BLOCKED, SPREAD_UNKNOWN = 'CLEAR', 'BLOCKED', 'UNKNOWN'

ALLOW = 'ALLOW'
BLOCK = 'BLOCK'
DBL_EPSILON = 2.220446049250313e-16
RISK_ULPS = 4.0           # binary-noise tolerance of the combined-risk comparison, in ulps of max(1, cap)
MAX_REASONS = 12

EV_DIRECTION_CHANGE = 1
EV_OPPOSITE_SIGNAL = 2
EV_SESSION_END = 4
EV_NEWS_BLOCK = 8
EV_DAILY_LIMIT = 16
EV_ALL = 31
EVENT_ORDER = ((EV_DIRECTION_CHANGE, 'DIRECTION_CHANGE'), (EV_OPPOSITE_SIGNAL, 'OPPOSITE_SIGNAL'),
               (EV_SESSION_END, 'SESSION_END'), (EV_NEWS_BLOCK, 'NEWS_BLOCK'), (EV_DAILY_LIMIT, 'DAILY_LIMIT'))

CANCEL_REQUEST = 'CANCEL_REQUEST'
NO_PENDING = 'NO_PENDING'
NO_EVENT = 'NO_EVENT'


# ----------------------------------------------------------------------------------------------- part 1: plan
@dataclass(frozen=True)
class Plan:
    status: str
    stage: str
    reason: str
    under_status: str = ''
    under_reason: str = ''
    signal_id: str = ''
    setup_id: str = ''
    direction: object = None
    e_out: float = 0.0
    s_out: float = 0.0
    tp: float = 0.0
    level_2r: float = 0.0
    partial_price: float = 0.0
    r_geom: float = 0.0
    volume_out: float = 0.0
    risk_model: float = 0.0
    tp_equals_2r: bool = False
    plan_label: str = PLAN_LABEL
    partial_label: str = PARTIAL_LABEL
    risk_label: str = RISK_LABEL


def _blank(s):
    return not isinstance(s, str) or s.strip() == ''


def _refuse(status, stage, reason, signal_id, setup_id, direction, under_status='', under_reason=''):
    return Plan(status=status, stage=stage, reason=reason, under_status=under_status, under_reason=under_reason,
                signal_id=signal_id, setup_id=setup_id, direction=direction)


def build_plan(signal_id, setup_id, direction, e_raw, s_raw, t_raw, risk_budget, tick_value,
               tick_size, digits, point, stops_level, bid, ask, volume_min, volume_step, volume_max, cap_lots):
    if _blank(signal_id):
        return _refuse(INVALID_INPUT, STAGE_INPUT, 'INVALID_SIGNAL_ID: signal_id must be a non-empty string',
                       signal_id, setup_id, direction)
    if _blank(setup_id):
        return _refuse(INVALID_INPUT, STAGE_INPUT, 'INVALID_SETUP_ID: setup_id must be a non-empty string',
                       signal_id, setup_id, direction)
    geo = g5.compute(direction, e_raw, s_raw, tick_size, digits, point, stops_level, t_raw, bid, ask)
    if geo.status != g5.OK:
        return _refuse(GEOMETRY_REFUSED, STAGE_GEOMETRY, 'GEOMETRY_REFUSED: geometry %s: %s' % (geo.status, geo.reason),
                       signal_id, setup_id, direction, geo.status, geo.reason)
    siz = p6.size(geo, risk_budget, tick_value, volume_min, volume_step, volume_max, cap_lots)
    if siz.status != p6.OK:
        return _refuse(SIZING_REFUSED, STAGE_SIZING, 'SIZING_REFUSED: sizing %s: %s' % (siz.status, siz.reason),
                       signal_id, setup_id, direction, siz.status, siz.reason)
    return Plan(status=OK, stage=STAGE_COMPLETE, reason='', signal_id=signal_id, setup_id=setup_id, direction=direction,
                e_out=geo.e_out, s_out=geo.s_out, tp=geo.tp, level_2r=geo.level_2r, partial_price=geo.partial_price,
                r_geom=geo.r_geom, volume_out=siz.volume_out, risk_model=siz.risk_realized,
                tp_equals_2r=geo.tp_equals_2r)


# --------------------------------------------------------------------------------------------- part 2: permit
@dataclass(frozen=True)
class Snapshot:
    data_state: str = DATA_READY
    data_reliable: bool = True
    session_state: str = SESSION_OPEN
    news_state: str = NEWS_CLEAR
    spread_state: str = SPREAD_CLEAR
    open_positions: int = 0
    trades_today: int = 0
    existing_risk: float = 0.0


@dataclass(frozen=True)
class Limits:
    max_positions: object = None        # None = UNSET
    max_trades_per_day: object = None
    combined_risk_cap: object = None


@dataclass
class Registry:
    ids: list
    count: int = 0

    @staticmethod
    def new(capacity):
        return Registry(ids=[''] * capacity, count=0)


@dataclass(frozen=True)
class Permit:
    decision: str
    primary_reason: str
    reasons: tuple
    registered: bool = False
    label: str = PERMIT_LABEL


def _count_ok(v):
    return isinstance(v, int) and not isinstance(v, bool) and v >= 0


def _money_ok(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and v >= 0


def check_permit(plan, snap, limits, registry):
    reasons = []
    plan_ok = getattr(plan, 'status', None) == OK
    if not plan_ok:
        reasons.append('PLAN_NOT_OK')
    # data
    if snap.data_state == DATA_READY:
        if snap.data_reliable is not True:
            reasons.append('DATA_UNRELIABLE')
    elif snap.data_state == DATA_NOT_READY:
        reasons.append('DATA_NOT_READY')
    elif snap.data_state == DATA_UNKNOWN:
        reasons.append('DATA_UNKNOWN')
    else:
        reasons.append('INVALID_SNAPSHOT:data_state')
    # session, news, spread
    if snap.session_state == SESSION_CLOSED:
        reasons.append('SESSION_CLOSED')
    elif snap.session_state == SESSION_UNKNOWN:
        reasons.append('SESSION_UNKNOWN')
    elif snap.session_state != SESSION_OPEN:
        reasons.append('INVALID_SNAPSHOT:session_state')
    if snap.news_state == NEWS_BLOCKED:
        reasons.append('NEWS_BLOCK')
    elif snap.news_state == NEWS_UNKNOWN:
        reasons.append('NEWS_UNKNOWN')
    elif snap.news_state != NEWS_CLEAR:
        reasons.append('INVALID_SNAPSHOT:news_state')
    if snap.spread_state == SPREAD_BLOCKED:
        reasons.append('SPREAD_BLOCK')
    elif snap.spread_state == SPREAD_UNKNOWN:
        reasons.append('SPREAD_UNKNOWN')
    elif snap.spread_state != SPREAD_CLEAR:
        reasons.append('INVALID_SNAPSHOT:spread_state')
    # registry
    capacity = len(registry.ids)
    sid = getattr(plan, 'signal_id', '')
    if not _count_ok(registry.count) or registry.count > capacity:
        reasons.append('REGISTRY_INVALID')
    elif not _blank(sid):
        if sid in registry.ids[:registry.count]:
            reasons.append('DUPLICATE_SIGNAL')
        elif registry.count >= capacity:
            reasons.append('REGISTRY_FULL')
    # positions
    if limits.max_positions is None:
        reasons.append('POLICY_UNSET:max_positions')
    elif not _count_ok(limits.max_positions):
        reasons.append('INVALID_SNAPSHOT:max_positions')
    elif not _count_ok(snap.open_positions):
        reasons.append('INVALID_SNAPSHOT:open_positions')
    elif snap.open_positions >= limits.max_positions:
        reasons.append('MAX_POSITIONS_REACHED')
    # trades
    if limits.max_trades_per_day is None:
        reasons.append('POLICY_UNSET:max_trades_per_day')
    elif not _count_ok(limits.max_trades_per_day):
        reasons.append('INVALID_SNAPSHOT:max_trades_per_day')
    elif not _count_ok(snap.trades_today):
        reasons.append('INVALID_SNAPSHOT:trades_today')
    elif snap.trades_today >= limits.max_trades_per_day:
        reasons.append('MAX_TRADES_REACHED')
    # combined risk
    cap = limits.combined_risk_cap
    if cap is None:
        reasons.append('POLICY_UNSET:combined_risk_cap')
    elif not _money_ok(cap):
        reasons.append('INVALID_SNAPSHOT:combined_risk_cap')
    elif not _money_ok(snap.existing_risk):
        reasons.append('INVALID_SNAPSHOT:existing_risk')
    elif plan_ok and snap.existing_risk + plan.risk_model > cap + RISK_ULPS * DBL_EPSILON * max(1.0, cap):
        reasons.append('COMBINED_RISK_EXCEEDED')
    if reasons:
        return Permit(decision=BLOCK, primary_reason=reasons[0], reasons=tuple(reasons))
    return Permit(decision=ALLOW, primary_reason='', reasons=())


def authorize(plan, snap, limits, registry):
    """check_permit, then records plan.signal_id in the caller-owned registry ONLY when the decision is ALLOW."""
    permit = check_permit(plan, snap, limits, registry)
    if permit.decision != ALLOW:
        return permit
    registry.ids[registry.count] = plan.signal_id
    registry.count += 1
    return Permit(decision=permit.decision, primary_reason='', reasons=(), registered=True)


# --------------------------------------------------------------------------------------------- part 3: cancel
@dataclass(frozen=True)
class CancelDecision:
    status: str
    reason: str
    reasons: tuple = ()
    cancel_pending: bool = False
    pending_signal_id: str = ''
    position_present: bool = False
    positions_untouched: bool = True      # ALWAYS True: an open position is never cancelled or closed by this decision
    label: str = CANCEL_LABEL


def cancel_decision(pending_exists, pending_signal_id, position_exists, events):
    pos = bool(position_exists)
    if isinstance(events, bool) or not isinstance(events, int) or events < 0 or (events & ~EV_ALL) != 0:
        return CancelDecision(status=INVALID_INPUT, reason='INVALID_EVENTS: %r is not a mask of the five known events' % (events,),
                              position_present=pos)
    if not pending_exists:
        return CancelDecision(status=NO_PENDING, reason='NO_PENDING: no pending order, nothing to cancel', position_present=pos)
    if _blank(pending_signal_id):
        return CancelDecision(status=INVALID_INPUT, reason='INVALID_PENDING_SIGNAL_ID: a pending order needs a non-empty signal_id',
                              position_present=pos)
    if events == 0:
        return CancelDecision(status=NO_EVENT, reason='NO_EVENT: no cancel event', pending_signal_id=pending_signal_id,
                              position_present=pos)
    why = tuple(name for bit, name in EVENT_ORDER if events & bit)
    return CancelDecision(status=CANCEL_REQUEST, reason='CANCEL_REQUEST: ' + ','.join(why), reasons=why,
                          cancel_pending=True, pending_signal_id=pending_signal_id, position_present=pos)
