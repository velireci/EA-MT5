"""T011 pure 80/20 exit-volume split reference (Python mirror of src/include/ExitSplit.mqh).

NOT a trading rule engine. No order, no trading API, no account/symbol read, no clock, no price. Every number is an
ARGUMENT supplied by the caller. NOT wired to an EA. No BE, costs, trailing or 2R detection here.

CLIENT STATEMENT (STRATEGY_SPEC section 8): at 2R close 80% of the INITIAL volume; the remaining 20% runs to TP or SL.
This module only answers: can the initial volume be split EXACTLY 80/20 on the volume grid with both parts allowed?

INPUTS: volume_initial, volume_min, volume_step, volume_max (lots, all from the caller; step 0.01 is never assumed).

GRID: the volume grid validation is the T006 one and is REUSED, not copied: PS_GridSteps (t006_sizing_reference._grid_steps)
turns volume_min, volume_max and volume_initial into integer step counts or rejects them (VOLUME_NOT_ON_GRID).
The split is then pure integer arithmetic:  N = initial steps;  exact 80/20 needs N % 5 == 0;
close_steps = 4*N/5;  remaining_steps = N/5;  close_steps + remaining_steps == N by construction.

EXACT OR NOTHING: if N % 5 != 0, or the remainder is below volume_min, the status is SPLIT_POLICY_UNSET. This module invents
NO rounding, NO full close, NO skipping of the partial exit. (close_steps >= remaining_steps >= min_steps and
close_steps < N <= max_steps, so the close part is always inside [min, max] once the remainder is.) The decision of what to
do in that case is an open client/owner question, not made here.

STATUSES, first failure wins, fixed reason tags (INVALID_INPUT reasons start with the tag):
  INVALID_INPUT       INVALID_VOLUME_MIN | INVALID_VOLUME_STEP | INVALID_VOLUME_MAX | INVALID_INITIAL (non-finite or <= 0, in
                      this order), VOLUME_MAX_BELOW_MIN, STEP_RANGE (max/step or initial/step non-finite or > 1e9),
                      VOLUME_NOT_ON_GRID (min, then max, then initial), INITIAL_BELOW_MIN, INITIAL_ABOVE_MAX
  SPLIT_POLICY_UNSET  NOT_EXACT_80_20 (N % 5 != 0) | REMAINDER_BELOW_MIN (N/5 < min_steps)
  OK                  plan returned
OUTPUT: status, reason, initial/min/max steps (diagnostic, kept on SPLIT_POLICY_UNSET), close_steps, remaining_steps,
close_volume = close_steps*step, remaining_volume = remaining_steps*step (binary noise possible, e.g. 3*0.1; the integer
steps are authoritative), close_percent = close_steps/N (exactly the double nearest 0.8 when OK).
On INVALID_INPUT nothing is reported; on SPLIT_POLICY_UNSET only the step diagnostics; volumes are 0 unless status OK.
"""
import math
from dataclasses import dataclass

import t006_sizing_reference as t006

OK = 'OK'
INVALID_INPUT = 'INVALID_INPUT'
SPLIT_POLICY_UNSET = 'SPLIT_POLICY_UNSET'
MAX_STEPS = t006.MAX_STEPS
CLOSE_NUM, CLOSE_DEN = 4, 5


@dataclass
class Split:
    status: str
    reason: str = ''
    initial_steps: int = 0
    min_steps: int = 0
    max_steps: int = 0
    close_steps: int = 0
    remaining_steps: int = 0
    close_volume: float = 0.0
    remaining_volume: float = 0.0
    close_percent: float = 0.0


def _fail(status, reason, **kw):
    return Split(status=status, reason=reason, **kw)


def split(volume_initial, volume_min, volume_step, volume_max):
    for tag, v in (('INVALID_VOLUME_MIN', volume_min), ('INVALID_VOLUME_STEP', volume_step),
                   ('INVALID_VOLUME_MAX', volume_max), ('INVALID_INITIAL', volume_initial)):
        if not t006._num(v) or v <= 0:
            return _fail(INVALID_INPUT, '%s: %s must be finite and > 0' % (tag, t006._g(v)))
    if volume_max < volume_min:
        return _fail(INVALID_INPUT, 'VOLUME_MAX_BELOW_MIN: volume_max %.10g < volume_min %.10g' % (volume_max, volume_min))
    max_x = volume_max / volume_step
    init_x = volume_initial / volume_step
    if not (math.isfinite(max_x) and math.isfinite(init_x)) or max_x > MAX_STEPS or init_x > MAX_STEPS:
        return _fail(INVALID_INPUT, 'STEP_RANGE: volume_max/volume_step or volume_initial/volume_step is not finite or > 1e9 steps')
    min_steps = t006._grid_steps(volume_min, volume_step)
    max_steps = t006._grid_steps(volume_max, volume_step)
    n = t006._grid_steps(volume_initial, volume_step)
    if min_steps < 0:
        return _fail(INVALID_INPUT, 'VOLUME_NOT_ON_GRID: volume_min %.10g is not a multiple of step %.10g' % (volume_min, volume_step))
    if max_steps < 0:
        return _fail(INVALID_INPUT, 'VOLUME_NOT_ON_GRID: volume_max %.10g is not a multiple of step %.10g' % (volume_max, volume_step))
    if n < 0:
        return _fail(INVALID_INPUT, 'VOLUME_NOT_ON_GRID: volume_initial %.10g is not a multiple of step %.10g' % (volume_initial, volume_step))
    if n < min_steps:
        return _fail(INVALID_INPUT, 'INITIAL_BELOW_MIN: %d steps < minimum %d steps' % (n, min_steps))
    if n > max_steps:
        return _fail(INVALID_INPUT, 'INITIAL_ABOVE_MAX: %d steps > maximum %d steps' % (n, max_steps))
    diag = dict(initial_steps=n, min_steps=min_steps, max_steps=max_steps)
    if n % CLOSE_DEN != 0:
        return _fail(SPLIT_POLICY_UNSET, 'NOT_EXACT_80_20: %d steps cannot be split exactly 80/20; no rounding policy is defined' % n, **diag)
    close_steps = n // CLOSE_DEN * CLOSE_NUM
    rem_steps = n // CLOSE_DEN
    if rem_steps < min_steps:
        return _fail(SPLIT_POLICY_UNSET, 'REMAINDER_BELOW_MIN: remainder %d steps < minimum %d steps; no full-close or skip policy is defined' %
                     (rem_steps, min_steps), **diag)
    return Split(status=OK, close_steps=close_steps, remaining_steps=rem_steps,
                 close_volume=close_steps * volume_step, remaining_volume=rem_steps * volume_step,
                 close_percent=close_steps / n, **diag)
