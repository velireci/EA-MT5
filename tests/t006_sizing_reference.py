"""T006 pure position-sizing reference (Python mirror of src/include/PositionSizing.mqh).

NOT a trading rule. No order, no trading API, no broker/account/symbol read, no clock, no live price. Every number is
an ARGUMENT supplied by the caller. NOT wired to an EA.

WHAT IS SUPPLIED BY THE CALLER (this module chooses none of it):
  geo          the result of the T005 TradeGeometry (Result here, STgResult in MQL5). Only status, computed,
               e_ticks and s_ticks are read. No price is normalized or validated again: the stop distance in ticks is
               stop_ticks = |e_ticks - s_ticks| of the already verified geometry.
  risk_budget  monetary risk in ACCOUNT currency. The module does NOT choose the base of the 1% (balance, equity,
               ...) and does NOT apply the 1% anywhere (open item).
  tick_value   value of ONE tick for ONE LOT in ACCOUNT currency, exactly as the caller passes it (for example the
               broker's SYMBOL_TRADE_TICK_VALUE when that is already in account currency). No currency conversion here.
  volume_min, volume_step, volume_max   broker volume parameters in lots. volume_step = 0.01 is NEVER assumed.
  cap_lots     per-trade cap in lots, an INPUT (the client number 10 is passed by the caller; no default is hidden here).

LINEAR MODEL (this is a model with the supplied parameters, NOT a guarantee of the broker's real loss):
  loss_per_lot_at_SL = stop_ticks * tick_value
  volume_raw         = risk_budget / loss_per_lot_at_SL
  Costs (spread, commission, slippage), contract changes and profit-currency conversion are outside the model:
  COSTS_NOT_MODELLED. The realized risk reported below is a model figure, not a promise.

ROUNDING (the only adjustment this module ever makes): the volume is rounded DOWN to a whole number of volume steps n.
  risk_per_step = volume_step * loss_per_lot_at_SL            (computed once, double precision)
  n             = floor(risk_budget / risk_per_step + EPS_STEPS)      EPS_STEPS = 1e-6 step: float noise on an exact fit
  while n > 0 and n * risk_per_step > risk_budget: n -= 1             the SAME expression as the reported risk
  volume_out    = n * volume_step ; risk_realized = n * risk_per_step
  So risk_realized <= risk_budget ALWAYS holds for the double expression, in both languages. In exact real arithmetic
  of the (binary inexact) inputs it can exceed the budget by float rounding only (relative ~1e-15, below any money
  granularity). A fit that is exact in decimal but lands 1 ulp above the budget in binary loses ONE step (conservative,
  never rounded up). The integer steps_rounded is authoritative; volume_out = n * step may carry binary noise
  (3 * 0.1 = 0.30000000000000004), so the caller normalizes to the volume digits at the order stage (not here).
  The volume is NEVER raised to volume_min and NEVER reduced/clamped to volume_max or cap_lots. There is no
  reduced_to_limit field: a limit conflict is always a SKIP status and then volume_out = 0.

LIMITS (integer steps, evaluated AFTER the rounding, first conflict wins):
  n < min_steps   -> SKIP_BELOW_MIN_VOLUME (includes n = 0, i.e. rounds to zero)
  n > max_steps   -> SKIP_ABOVE_MAX_VOLUME (broker maximum, checked BEFORE the cap)
  n > cap_steps   -> SKIP_ABOVE_CAP        (cap_steps = floor(cap_lots / volume_step + EPS_STEPS); the cap need NOT be on
                                            the step grid: it is only a comparison bound, never used as a volume)
  max and cap are NOT merged into one smaller limit: the broker maximum is reported first when both are exceeded.
  A cap below volume_min is valid input: every sizing is then a SKIP (below min or above cap).

STATUSES, first failure wins, in this order (fixed reason tags; INVALID_INPUT reasons start with the tag):
  1 GEOMETRY_NOT_OK    geo.status != OK or not geo.computed (nothing is recomputed)
  2 INVALID_INPUT      INVALID_STOP_TICKS    e_ticks/s_ticks not integers, |tick| > MAX_STOP_TICKS (1e13), or |e-s| == 0
                       INVALID_RISK_BUDGET   non-finite or <= 0
                       INVALID_TICK_VALUE    non-finite or <= 0
                       INVALID_VOLUME_MIN    non-finite or <= 0
                       INVALID_VOLUME_STEP   non-finite or <= 0
                       INVALID_VOLUME_MAX    non-finite or <= 0
                       INVALID_CAP           non-finite or <= 0
                       VOLUME_MAX_BELOW_MIN  volume_max < volume_min (equal is allowed)
                       STEP_RANGE            volume_max/step or cap_lots/step non-finite or > MAX_STEPS (1e9)
                       VOLUME_NOT_ON_GRID    volume_min or volume_max is not an integer >= 1 multiple of the step
                                             (|x - round(x)| <= EPS_STEPS in steps, x = value/step; min checked first)
                       NUMERIC_OVERFLOW      loss_per_lot, risk_per_step or volume_raw not finite or <= 0, or
                                             risk_budget/risk_per_step > MAX_RAW_STEPS (1e15)
  3 SKIP_BELOW_MIN_VOLUME -> SKIP_ABOVE_MAX_VOLUME -> SKIP_ABOVE_CAP
  4 OK
Nothing is coerced: an input that is not on the grid is rejected, never rounded.
OUTPUT ON FAILURE: GEOMETRY_NOT_OK and INVALID_INPUT report no number at all (computed False, every numeric field 0).
A SKIP status keeps the DIAGNOSTIC fields (computed True, stop_ticks, loss_per_lot, risk_per_step, volume_raw,
steps_rounded, min/max/cap steps) so the skip can be explained, but volume_out, risk_realized and the rounding fields are
0. Act only on volume_out / risk_realized of a status OK result.
NOT handled here (open): the base of the 1%, costs, combined 2% risk and pending reservation, the 2-position and
2-vs-3-trades limits, the 80/20 partial volume rounding, the 50 stop-distance limit, order placement, EA wiring.
"""
import math
from dataclasses import dataclass

import t005_geometry_reference as g005

OK = 'OK'
INVALID_INPUT = 'INVALID_INPUT'
GEOMETRY_NOT_OK = 'GEOMETRY_NOT_OK'
SKIP_BELOW_MIN_VOLUME = 'SKIP_BELOW_MIN_VOLUME'
SKIP_ABOVE_MAX_VOLUME = 'SKIP_ABOVE_MAX_VOLUME'
SKIP_ABOVE_CAP = 'SKIP_ABOVE_CAP'

EPS_STEPS = 1e-6          # tolerance, in volume steps, for "on the grid" and float noise on an exact fit
MAX_STEPS = 1e9           # volume_max/step and cap/step bound (double spacing there is 1.2e-7 < EPS_STEPS)
MAX_RAW_STEPS = 1e15      # risk_budget/risk_per_step bound; far below 2^53, so the integer n is exact
MAX_STOP_TICKS = 1e13     # bound for the geometry tick counts (T005 itself stays below 3e12)

COSTS_LABEL = 'COSTS_NOT_MODELLED'
MODEL_LABEL = 'LINEAR_MODEL (loss per lot at SL = stop ticks * tick value; not the broker real loss)'
NO_REDUCTION_LABEL = 'NO_REDUCTION_TO_LIMIT (a limit conflict is a SKIP; volume is never raised to min or clamped to max/cap)'


@dataclass(frozen=True)
class Sizing:
    status: str
    reason: str
    computed: bool = False
    stop_ticks: int = 0
    loss_per_lot: float = 0.0
    risk_per_step: float = 0.0
    volume_raw: float = 0.0
    steps_rounded: int = 0
    min_steps: int = 0
    max_steps: int = 0
    cap_steps: int = 0
    volume_out: float = 0.0
    risk_realized: float = 0.0
    step_rounded: bool = False
    volume_rounding_loss: float = 0.0
    risk_unused: float = 0.0
    costs_label: str = COSTS_LABEL
    model_label: str = MODEL_LABEL


def _num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)


def _g(x):
    return '%.10g' % x if _num(x) else repr(x)


def _fail(status, reason, **kw):
    return Sizing(status=status, reason=reason, **kw)


def _grid_steps(value, step):
    """Integer number of steps when value is a >= 1 multiple of step within EPS_STEPS, else -1."""
    x = value / step
    k = math.floor(x + 0.5)
    if k < 1 or abs(x - k) > EPS_STEPS:
        return -1
    return int(k)


def size(geo, risk_budget, tick_value, volume_min, volume_step, volume_max, cap_lots):
    # 1 geometry: taken as given, never recomputed
    if getattr(geo, 'status', None) != g005.OK or getattr(geo, 'computed', False) is not True:
        return _fail(GEOMETRY_NOT_OK, 'GEOMETRY_NOT_OK: geometry status %s computed %s' %
                     (getattr(geo, 'status', None), getattr(geo, 'computed', None)))
    # 2 validation, fixed order, before any computation
    e_t, s_t = getattr(geo, 'e_ticks', None), getattr(geo, 's_ticks', None)
    if (isinstance(e_t, bool) or isinstance(s_t, bool) or not isinstance(e_t, int) or not isinstance(s_t, int) or
            abs(e_t) > MAX_STOP_TICKS or abs(s_t) > MAX_STOP_TICKS):
        return _fail(INVALID_INPUT, 'INVALID_STOP_TICKS: geometry ticks are not integers within +/-1e13')
    stop_ticks = abs(e_t - s_t)
    if stop_ticks <= 0:
        return _fail(INVALID_INPUT, 'INVALID_STOP_TICKS: stop distance is %d ticks, must be > 0' % stop_ticks)
    for tag, v in (('INVALID_RISK_BUDGET', risk_budget), ('INVALID_TICK_VALUE', tick_value),
                   ('INVALID_VOLUME_MIN', volume_min), ('INVALID_VOLUME_STEP', volume_step),
                   ('INVALID_VOLUME_MAX', volume_max), ('INVALID_CAP', cap_lots)):
        if not _num(v) or v <= 0:
            return _fail(INVALID_INPUT, '%s: %s must be finite and > 0' % (tag, _g(v)))
    if volume_max < volume_min:
        return _fail(INVALID_INPUT, 'VOLUME_MAX_BELOW_MIN: volume_max %.10g < volume_min %.10g' % (volume_max, volume_min))
    max_x = volume_max / volume_step
    cap_x = cap_lots / volume_step
    if not (math.isfinite(max_x) and math.isfinite(cap_x)) or max_x > MAX_STEPS or cap_x > MAX_STEPS:
        return _fail(INVALID_INPUT, 'STEP_RANGE: volume_max/volume_step or cap_lots/volume_step is not finite or > 1e9 steps')
    min_steps = _grid_steps(volume_min, volume_step)
    if min_steps < 0:
        return _fail(INVALID_INPUT, 'VOLUME_NOT_ON_GRID: volume_min %.10g is not a multiple of step %.10g' %
                     (volume_min, volume_step))
    max_steps = _grid_steps(volume_max, volume_step)
    if max_steps < 0:
        return _fail(INVALID_INPUT, 'VOLUME_NOT_ON_GRID: volume_max %.10g is not a multiple of step %.10g' %
                     (volume_max, volume_step))
    cap_steps = int(math.floor(cap_x + EPS_STEPS))

    # linear model
    loss_per_lot = float(stop_ticks) * tick_value
    risk_per_step = volume_step * loss_per_lot
    if not (math.isfinite(loss_per_lot) and loss_per_lot > 0 and math.isfinite(risk_per_step) and risk_per_step > 0):
        return _fail(INVALID_INPUT, 'NUMERIC_OVERFLOW: loss per lot or risk per step is not finite and > 0')
    volume_raw = risk_budget / loss_per_lot
    raw_steps = risk_budget / risk_per_step
    if not (math.isfinite(volume_raw) and math.isfinite(raw_steps)) or raw_steps > MAX_RAW_STEPS:
        return _fail(INVALID_INPUT, 'NUMERIC_OVERFLOW: raw volume is not finite or > 1e15 steps')

    # ROUND DOWN (the only adjustment)
    n = int(math.floor(raw_steps + EPS_STEPS))
    while n > 0 and n * risk_per_step > risk_budget:
        n -= 1

    diag = dict(computed=True, stop_ticks=stop_ticks, loss_per_lot=loss_per_lot, risk_per_step=risk_per_step,
                volume_raw=volume_raw, steps_rounded=n, min_steps=min_steps, max_steps=max_steps, cap_steps=cap_steps)
    # LIMITS: a conflict is a skip, never a reduction
    if n < min_steps:
        return _fail(SKIP_BELOW_MIN_VOLUME, 'SKIP_BELOW_MIN_VOLUME: %d steps rounded down from raw volume %.10g, minimum is %d steps' %
                     (n, volume_raw, min_steps), **diag)
    if n > max_steps:
        return _fail(SKIP_ABOVE_MAX_VOLUME, 'SKIP_ABOVE_MAX_VOLUME: %d steps rounded down from raw volume %.10g, broker maximum is %d steps' %
                     (n, volume_raw, max_steps), **diag)
    if n > cap_steps:
        return _fail(SKIP_ABOVE_CAP, 'SKIP_ABOVE_CAP: %d steps rounded down from raw volume %.10g, cap is %d steps' %
                     (n, volume_raw, cap_steps), **diag)
    volume_out = n * volume_step
    risk_realized = n * risk_per_step
    rounded = abs(raw_steps - n) > EPS_STEPS
    return Sizing(status=OK, reason='', step_rounded=rounded,
                  volume_rounding_loss=(max(0.0, volume_raw - volume_out) if rounded else 0.0),
                  volume_out=volume_out, risk_realized=risk_realized, risk_unused=max(0.0, risk_budget - risk_realized),
                  **diag)
