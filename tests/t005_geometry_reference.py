"""T005 pure trade-geometry reference (Python mirror of src/include/TradeGeometry.mqh).

NOT a trading rule. Direction, entry E, stop S and optional target T are INPUTS supplied by the caller; this
module does not choose them, does not read T004 facts, has no volume/sizing, no order function and no clock.

CONTRACT (conventions marked PROPOSAL are for review and are not client answers):
  1. Validate inputs (see VALIDATION below). 2. Convert E and S to integer ticks with the PROPOSED rounding "nearest tick; an exact
  half tick goes UP (toward the larger price)" for BOTH E and S (so BUY and SELL are not mirror images at an
  exact half tick). 3. Everything else is computed from those integer ticks: R_geom = |E_out - S_out|,
  level_2R = E_out +/- 2*R_geom. The reported E_out and S_out are exactly the values used. 4. Target T is
  rounded AWAY from the entry (BUY up, SELL down; PROPOSAL, so rounding can never undercut the 2R minimum).
  5. TP = the farther of the normalized target and level_2R (client N6); a missing or nearer target gives
  level_2R, a farther target is kept. 6. partial_price = level_2R (client: 80% of INITIAL volume at 2R); no
  volume is computed. 7. Costs are NOT modelled; R_geom is NOT the client's final R definition (open C3/C4).
VALIDATION (all failures are INVALID_INPUT; the reason starts with a fixed tag; first failure wins, in this order):
  direction (INVALID_DIRECTION) -> finite/numeric, tick_size/point > 0, digits 0..8, stops_level >= 0 ->
  tick/digits compatibility [INCOMPATIBLE_TICK_DIGITS: q = tick_size * 10^digits must be finite, floor(q+0.5) >= 1
  and |q - floor(q+0.5)| <= 1e-6, i.e. tick_size is a >= 10^-digits integer multiple of 10^-digits; accepted:
  (0.01,2) (0.05,2) (0.25,2) (1,0) (0.5,1); rejected: (0.001,2) (0.015,2); `point` stays independent of digits] ->
  prices > 0, bid <= ask -> range [NUMERIC_OVERFLOW: max(E,S,T,bid,ask)/tick_size <= MAX_TICKS = 1e12, so every
  derived tick count (<= 3e12) stays far below 2^53 and integer tick arithmetic is exact] -> normalization ->
  E_out/S_out finite [NUMERIC_OVERFLOW] and > 0 [NONPOSITIVE_PRICE] -> ZERO_RISK -> SL_WRONG_SIDE -> level_2R/R_geom
  finite and level_2R > 0 -> target price finite and > 0 -> TARGET_WRONG_SIDE -> TP/partial finite and > 0 ->
  BELOW_STOPS_LEVEL (distances must be finite) -> PENDING_TOO_CLOSE (gap must be finite).
  On the new positivity/overflow failures NO geometry is reported: computed=False and every numeric/tick field is
  0 (only direction and the raw inputs are echoed). ZERO_RISK/SL_WRONG_SIDE keep E_out/S_out/E,S ticks (as before).
Not enforced: the '50 stop distance' limit (unit unconfirmed), freeze level, spread limit, volume rules.
"""
import math
from dataclasses import dataclass
from typing import Optional

BUY = 'BUY'
SELL = 'SELL'

EPS_TICKS = 1e-6      # tolerance, in ticks, for "exactly on the grid" and "exact half tick"
EPS_POINTS = 1e-6     # tolerance, in points, for distance comparisons
MAX_TICKS = 1e12      # same limit in TradeGeometry.mqh; far below 2^53 (9.007e15)

OK = 'OK'
INVALID_DIRECTION = 'INVALID_DIRECTION'
INVALID_INPUT = 'INVALID_INPUT'
SL_WRONG_SIDE = 'SL_WRONG_SIDE'
ZERO_RISK = 'ZERO_RISK'
TARGET_WRONG_SIDE = 'TARGET_WRONG_SIDE'
BELOW_STOPS_LEVEL = 'BELOW_STOPS_LEVEL'
PENDING_TOO_CLOSE = 'PENDING_TOO_CLOSE'

TARGET_NONE = 'NONE'
TARGET_NEARER = 'NEARER_THAN_2R'
TARGET_EQUAL = 'EQUAL_TO_2R'
TARGET_FARTHER = 'FARTHER_THAN_2R'

PENDING_NOT_CHECKED = 'NOT_CHECKED'
PENDING_PASSED = 'PASSED'
PENDING_TOO_CLOSE_STATE = 'TOO_CLOSE'

PARTIAL_LABEL = 'PARTIAL_AT_2R (client answer: 80% of initial volume)'
COSTS_LABEL = 'COSTS_NOT_MODELLED'
R_LABEL = 'R_GEOM (price distance of normalized E and S; not the client final R, open C3/C4)'
UNENFORCED = '50 stop-distance limit NOT enforced (unit unconfirmed); freeze level, spread and volume not handled'


@dataclass(frozen=True)
class Result:
    status: str
    reason: str
    direction: str
    e_raw: float
    s_raw: float
    t_raw: Optional[float]
    computed: bool            # True once E_out/S_out/R/level_2R are valid (even if a later check failed)
    e_ticks: int = 0
    s_ticks: int = 0
    t_ticks: int = 0
    e_out: float = 0.0
    s_out: float = 0.0
    r_ticks: int = 0
    r_geom: float = 0.0
    two_r_ticks: int = 0
    level_2r: float = 0.0
    tp_ticks: int = 0
    tp: float = 0.0
    target_case: str = TARGET_NONE
    tp_equals_2r: bool = False    # TP coincides with the 80% partial point; remainder behaviour unspecified
    partial_price: float = 0.0
    partial_label: str = PARTIAL_LABEL
    costs_label: str = COSTS_LABEL
    pending_check: str = PENDING_NOT_CHECKED
    min_distance: float = 0.0


def _finite(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)


def nearest_ticks(price, tick):
    """Nearest tick as an integer; an exact half tick goes up."""
    x = price / tick
    m = math.floor(x)
    f = x - m
    if abs(f - 0.5) <= EPS_TICKS:
        return int(m) + 1
    return int(m) if f < 0.5 else int(m) + 1


def away_ticks(price, tick, direction):
    """Tick rounded away from the entry: BUY up, SELL down; a value already on the grid stays."""
    x = price / tick
    r = math.floor(x + 0.5)
    if abs(x - r) <= EPS_TICKS:
        return int(r)
    return int(math.ceil(x)) if direction == BUY else int(math.floor(x))


def ticks_to_price(n, tick, digits):
    return round(n * tick, digits)


def _fail(status, reason, direction, e_raw, s_raw, t_raw, **kw):
    return Result(status=status, reason=reason, direction=direction, e_raw=e_raw, s_raw=s_raw, t_raw=t_raw,
                  computed=kw.pop('computed', False), **kw)


def compute(direction, e_raw, s_raw, tick_size, digits, point, stops_level, t_raw=None, bid=None, ask=None):
    if direction not in (BUY, SELL):
        return _fail(INVALID_DIRECTION, 'direction must be BUY or SELL', direction, e_raw, s_raw, t_raw)
    nums = [e_raw, s_raw, tick_size, point]
    if t_raw is not None:
        nums.append(t_raw)
    if (bid is None) != (ask is None):
        return _fail(INVALID_INPUT, 'bid and ask must be supplied together', direction, e_raw, s_raw, t_raw)
    if bid is not None:
        nums += [bid, ask]
    if not all(_finite(v) for v in nums):
        return _fail(INVALID_INPUT, 'non-finite or non-numeric price/parameter', direction, e_raw, s_raw, t_raw)
    if tick_size <= 0 or point <= 0:
        return _fail(INVALID_INPUT, 'tick_size and point must be > 0', direction, e_raw, s_raw, t_raw)
    if isinstance(digits, bool) or not isinstance(digits, int) or not 0 <= digits <= 8:
        return _fail(INVALID_INPUT, 'digits must be an integer 0..8', direction, e_raw, s_raw, t_raw)
    if isinstance(stops_level, bool) or not isinstance(stops_level, int) or stops_level < 0:
        return _fail(INVALID_INPUT, 'stops_level must be an integer >= 0', direction, e_raw, s_raw, t_raw)
    scale = 10.0 ** digits
    q = tick_size * scale
    qr = math.floor(q + 0.5) if math.isfinite(q) else 0.0
    if not math.isfinite(q) or qr < 1 or abs(q - qr) > EPS_TICKS:
        return _fail(INVALID_INPUT, 'INCOMPATIBLE_TICK_DIGITS: tick_size %.10g is not an integer multiple of 10^-%d' %
                     (tick_size, digits), direction, e_raw, s_raw, t_raw)
    if e_raw <= 0 or s_raw <= 0 or (t_raw is not None and t_raw <= 0) or (bid is not None and (bid <= 0 or ask <= 0)):
        return _fail(INVALID_INPUT, 'prices must be > 0', direction, e_raw, s_raw, t_raw)
    if bid is not None and bid > ask:
        return _fail(INVALID_INPUT, 'bid is above ask', direction, e_raw, s_raw, t_raw)
    if max(abs(e_raw), abs(s_raw), abs(t_raw or 0.0), abs(bid or 0.0), abs(ask or 0.0)) / tick_size > MAX_TICKS:
        return _fail(INVALID_INPUT, 'NUMERIC_OVERFLOW: price/tick_size is out of range (> 1e12 ticks)', direction,
                     e_raw, s_raw, t_raw)

    sign = 1 if direction == BUY else -1
    e_t = nearest_ticks(e_raw, tick_size)
    s_t = nearest_ticks(s_raw, tick_size)
    e_out = ticks_to_price(e_t, tick_size, digits)
    s_out = ticks_to_price(s_t, tick_size, digits)
    if not (math.isfinite(e_out) and math.isfinite(s_out)):
        return _fail(INVALID_INPUT, 'NUMERIC_OVERFLOW: normalized E or S is not finite', direction, e_raw, s_raw, t_raw)
    if e_out <= 0 or s_out <= 0:
        return _fail(INVALID_INPUT, 'NONPOSITIVE_PRICE: normalized E_out=%.10g or S_out=%.10g is not > 0' %
                     (e_out, s_out), direction, e_raw, s_raw, t_raw)
    common = dict(e_ticks=e_t, s_ticks=s_t, e_out=e_out, s_out=s_out)
    if e_t == s_t:
        return _fail(ZERO_RISK, 'E_out equals S_out after normalization', direction, e_raw, s_raw, t_raw, **common)
    if sign * (s_t - e_t) > 0:
        return _fail(SL_WRONG_SIDE, 'SL is on the wrong side of the entry after normalization', direction,
                     e_raw, s_raw, t_raw, **common)

    r_t = abs(e_t - s_t)
    two_r_t = e_t + sign * 2 * r_t
    r_geom = ticks_to_price(r_t, tick_size, digits)
    level_2r = ticks_to_price(two_r_t, tick_size, digits)
    if not (math.isfinite(r_geom) and math.isfinite(level_2r)):
        return _fail(INVALID_INPUT, 'NUMERIC_OVERFLOW: R_geom or level_2R is not finite', direction, e_raw, s_raw, t_raw)
    if level_2r <= 0:
        return _fail(INVALID_INPUT, 'NONPOSITIVE_PRICE: level_2R=%.10g is not > 0' % level_2r, direction,
                     e_raw, s_raw, t_raw)
    min_distance = stops_level * point
    base = dict(common, computed=True, r_ticks=r_t, r_geom=r_geom, two_r_ticks=two_r_t, level_2r=level_2r,
                partial_price=level_2r, min_distance=min_distance)

    tn = 0
    case = TARGET_NONE
    tp_t = two_r_t
    if t_raw is not None:
        tn = away_ticks(t_raw, tick_size, direction)
        t_price = ticks_to_price(tn, tick_size, digits)
        if not math.isfinite(t_price):
            return _fail(INVALID_INPUT, 'NUMERIC_OVERFLOW: normalized target is not finite', direction,
                         e_raw, s_raw, t_raw)
        if t_price <= 0:
            return _fail(INVALID_INPUT, 'NONPOSITIVE_PRICE: normalized target=%.10g is not > 0' % t_price,
                         direction, e_raw, s_raw, t_raw)
        if sign * (tn - e_t) <= 0:
            tp_price = ticks_to_price(two_r_t, tick_size, digits)
            return _fail(TARGET_WRONG_SIDE, 'target is not beyond the entry in the trade direction', direction,
                         e_raw, s_raw, t_raw, t_ticks=tn, tp_ticks=two_r_t, tp=tp_price,
                         tp_equals_2r=True, **base)
        if sign * (tn - two_r_t) > 0:
            case, tp_t = TARGET_FARTHER, tn
        elif tn == two_r_t:
            case = TARGET_EQUAL
        else:
            case = TARGET_NEARER
    tp = ticks_to_price(tp_t, tick_size, digits)
    if not math.isfinite(tp):
        return _fail(INVALID_INPUT, 'NUMERIC_OVERFLOW: TP is not finite', direction, e_raw, s_raw, t_raw)
    if tp <= 0 or level_2r <= 0:     # partial_price == level_2r
        return _fail(INVALID_INPUT, 'NONPOSITIVE_PRICE: TP=%.10g or partial_price is not > 0' % tp, direction,
                     e_raw, s_raw, t_raw)
    base.update(t_ticks=tn, tp_ticks=tp_t, tp=tp, target_case=case, tp_equals_2r=(tp_t == two_r_t))

    sl_points = r_t * tick_size / point
    tp_points = abs(tp_t - e_t) * tick_size / point
    if not (math.isfinite(sl_points) and math.isfinite(tp_points)):
        return _fail(INVALID_INPUT, 'NUMERIC_OVERFLOW: SL/TP distance in points is not finite', direction,
                     e_raw, s_raw, t_raw)
    if sl_points < stops_level - EPS_POINTS:
        return _fail(BELOW_STOPS_LEVEL, 'SL distance %.10g points < stops level %d' % (sl_points, stops_level),
                     direction, e_raw, s_raw, t_raw, **base)
    if tp_points < stops_level - EPS_POINTS:   # unreachable while SL passes (TP >= 2R >= R); kept as a guard
        return _fail(BELOW_STOPS_LEVEL, 'TP distance %.10g points < stops level %d' % (tp_points, stops_level),
                     direction, e_raw, s_raw, t_raw, **base)

    pending = PENDING_NOT_CHECKED
    if bid is not None:
        gap = ((ask - e_out) if direction == BUY else (e_out - bid)) / point
        if not math.isfinite(gap):
            return _fail(INVALID_INPUT, 'NUMERIC_OVERFLOW: pending gap in points is not finite', direction,
                         e_raw, s_raw, t_raw)
        if gap <= EPS_POINTS or gap < stops_level - EPS_POINTS:
            base['pending_check'] = PENDING_TOO_CLOSE_STATE
            return _fail(PENDING_TOO_CLOSE, 'limit %.10g points from the market side; needs > 0 and >= %d' %
                         (gap, stops_level), direction, e_raw, s_raw, t_raw, **base)
        pending = PENDING_PASSED
    base['pending_check'] = pending
    return Result(status=OK, reason='', direction=direction, e_raw=e_raw, s_raw=s_raw, t_raw=t_raw, **base)
