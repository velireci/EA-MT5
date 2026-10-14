"""T011 pure 2R partial-close activation state machine (Python mirror of src/include/ExitActivation.mqh).

NOT a trading module. No order, no trading API, no account/symbol read, no clock, no persistence. Every number is an
ARGUMENT supplied by the caller; the state is an in-memory object OWNED BY THE CALLER (no guarantee after a restart,
not atomic, not shared). It only DECIDES whether a request to close 80% of the initial volume should be produced and tracks
the caller-supplied execution reports. No BE, costs, trailing, retry, price normalization or order sending.

CLIENT STATEMENT (STRATEGY_SPEC section 8): at 2R close 80% of the INITIAL volume; the remaining 20% runs to TP or SL.
TECHNICAL CONVENTION (for review, not a client rule): 2R is reached when BUY: Bid >= level_2R; SELL: Ask <= level_2R.
level_2R is supplied by the caller from the T005 TradeGeometry (partial_price); nothing is recomputed here.
The 80/20 split is ExitSplit (T011 first part, which reuses the T006 grid): REUSED via t011_split_reference.split.

STATES (state.status): IDLE -> REQUEST_PENDING -> DONE, plus the two stop states NEEDS_RECONCILIATION and BLOCKED.
  IDLE                 no request. Quote before 2R: nothing. Quote at/after 2R with an exact split and the actual volume equal
                       to the initial volume: ONE request, id "X2R80-<position_id>" (stable), state REQUEST_PENDING.
                       Split not realizable -> event SPLIT_POLICY_UNSET, no request, state stays IDLE (re-evaluated, never
                       rounded). Actual volume != initial volume at 2R -> NEEDS_RECONCILIATION (no request, plan not changed).
                       A report in IDLE has no request to match -> BLOCKED.
  REQUEST_PENDING      quotes are IGNORED (no new request, volume not checked: the fill may be ahead of its confirmation).
                       Report with the request id:
                         FULL      executed volume == request volume (in volume steps)  -> DONE, confirmations = 1
                         REJECTED / TIMEOUT        -> NEEDS_RECONCILIATION (no retry)
                         PARTIAL   0 < executed < request volume (steps)  -> NEEDS_RECONCILIATION, executed steps kept
                       Wrong id, FULL with a different volume, PARTIAL outside (0, request), a volume not on the grid
                       -> BLOCKED.
  DONE                 quotes IGNORED, except: the actual volume must equal initial - closed (steps); otherwise
                       NEEDS_RECONCILIATION. The SAME confirmation again (same id, FULL, same volume) -> DUPLICATE_IGNORED,
                       confirmations stays 1. Any other report -> BLOCKED.
  NEEDS_RECONCILIATION the caller must reconcile with the broker. Every later quote or report changes nothing and returns
                       RECONCILE_REQUIRED. NO automatic retry, no automatic transition out (a late fill after a timeout is
                       NOT accepted here).
  BLOCKED              inconsistent input (identity, level, wrong id/volume). Every later quote or report changes nothing and
                       returns BLOCKED.
VOLUME STEP: the step of the request is stored in the state. A report (also a duplicate) with another step is BLOCKED
(STEP_CHANGED); a quote in DONE with another step is NEEDS_RECONCILIATION. The executed volume is converted to steps with the stored
step only, so 0.04 lot on a 0.001 grid can never confirm 0.4 lot (40 steps) on a 0.01 grid.
VALIDATION: the volume parameters are validated (ExitSplit) on EVERY quote before anything is bound; invalid input binds nothing.
IDENTITY: the first valid quote binds position_id, direction, level_2R and volume_initial; a later quote with another value is
BLOCKED (IDENTITY_CHANGED). Invalid input (non-finite, <= 0, ask < bid, direction not BUY/SELL, id <= 0, empty request id)
returns INVALID_INPUT and changes nothing.
EVENT STATUS: OK, INVALID_INPUT, SPLIT_POLICY_UNSET, IGNORED, DUPLICATE_IGNORED, RECONCILE_REQUIRED, BLOCKED.
ACTION: NONE or REQUEST_PARTIAL_CLOSE (only the quote that creates the request). The request carries id and volume; the caller
sends it elsewhere (not in this module).
"""
import math
from dataclasses import dataclass

import t006_sizing_reference as t006
import t011_split_reference as es

IDLE, REQUEST_PENDING, DONE, NEEDS_RECONCILIATION, BLOCKED = 'IDLE', 'REQUEST_PENDING', 'DONE', 'NEEDS_RECONCILIATION', 'BLOCKED'
BUY, SELL = 1, -1
FULL, PARTIAL, REJECTED, TIMEOUT = 0, 1, 2, 3
REPORT_KINDS = (FULL, PARTIAL, REJECTED, TIMEOUT)
NONE_ACTION, REQUEST_ACTION = 'NONE', 'REQUEST_PARTIAL_CLOSE'


@dataclass
class State:
    status: str = IDLE
    bound: bool = False
    position_id: int = 0
    direction: int = 0
    level: float = 0.0
    volume_initial: float = 0.0
    volume_step: float = 0.0       # the grid of the request: reports, duplicates and the remainder check use THIS step
    request_id: str = ''
    request_steps: int = 0
    close_volume: float = 0.0
    initial_steps: int = 0
    executed_steps: int = 0
    confirmations: int = 0
    duplicates_ignored: int = 0
    reason: str = ''


@dataclass
class Result:
    event: str
    action: str = NONE_ACTION
    reason: str = ''
    request_id: str = ''
    request_volume: float = 0.0
    request_steps: int = 0


def request_id_for(position_id):
    return 'X2R80-%d' % position_id


def _num(x):
    return t006._num(x)


def _res(event, state=None, action=NONE_ACTION, reason=''):
    if state is not None and reason:
        state.reason = reason
    return Result(event=event, action=action, reason=reason)


def on_quote(state, position_id, direction, level_2r, bid, ask, volume_initial, volume_current,
             volume_min, volume_step, volume_max):
    # 1 input validation: nothing changes
    if isinstance(position_id, bool) or not isinstance(position_id, int) or position_id <= 0:
        return Result('INVALID_INPUT', reason='INVALID_POSITION_ID: must be an integer > 0')
    if isinstance(direction, bool) or direction not in (BUY, SELL):
        return Result('INVALID_INPUT', reason='INVALID_DIRECTION: must be BUY (1) or SELL (-1)')
    for tag, v in (('INVALID_LEVEL', level_2r), ('INVALID_BID', bid), ('INVALID_ASK', ask)):
        if not _num(v) or v <= 0:
            return Result('INVALID_INPUT', reason='%s: %s must be finite and > 0' % (tag, t006._g(v)))
    if ask < bid:
        return Result('INVALID_INPUT', reason='INVALID_QUOTE: ask %.10g < bid %.10g' % (ask, bid))
    for tag, v in (('INVALID_VOLUME_INITIAL', volume_initial), ('INVALID_VOLUME_CURRENT', volume_current)):
        if not _num(v) or v <= 0:
            return Result('INVALID_INPUT', reason='%s: %s must be finite and > 0' % (tag, t006._g(v)))
    # 1b the volume parameters are validated on EVERY quote (ExitSplit), BEFORE anything is bound or changed
    sp = es.split(volume_initial, volume_min, volume_step, volume_max)
    if sp.status == es.INVALID_INPUT:
        return Result('INVALID_INPUT', reason='SPLIT_' + sp.reason)
    # 2 stop states change nothing
    if state.status == NEEDS_RECONCILIATION:
        return Result('RECONCILE_REQUIRED', reason='RECONCILE_REQUIRED: ' + state.reason)
    if state.status == BLOCKED:
        return Result('BLOCKED', reason='BLOCKED: ' + state.reason)
    # 3 identity
    if not state.bound:
        state.bound = True
        state.position_id, state.direction, state.level, state.volume_initial = position_id, direction, level_2r, volume_initial
        state.request_id = ''
    elif (state.position_id, state.direction, state.level, state.volume_initial) != (position_id, direction, level_2r, volume_initial):
        state.status = BLOCKED
        return _res('BLOCKED', state, reason='IDENTITY_CHANGED: position, direction, level_2R or initial volume differs from the bound values')
    # 4 pending: ignored
    if state.status == REQUEST_PENDING:
        return Result('IGNORED', reason='IGNORED: request %s is pending' % state.request_id)
    reached = (bid >= level_2r) if direction == BUY else (ask <= level_2r)
    if state.status == DONE:
        return _done_quote(state, volume_current, volume_step)
    # 5 IDLE
    if not reached:
        return Result('OK', reason='')
    if sp.status == es.SPLIT_POLICY_UNSET:
        return Result('SPLIT_POLICY_UNSET', reason=sp.reason)
    cur = t006._grid_steps(volume_current, volume_step)
    if cur != sp.initial_steps:
        state.status = NEEDS_RECONCILIATION
        return _res('RECONCILE_REQUIRED', state, reason='VOLUME_MISMATCH_BEFORE_REQUEST: actual volume %.10g is not the initial volume %.10g (%d steps); the plan is not changed' %
                    (volume_current, volume_initial, sp.initial_steps))
    state.status = REQUEST_PENDING
    state.request_id = request_id_for(position_id)
    state.request_steps = sp.close_steps
    state.initial_steps = sp.initial_steps
    state.close_volume = sp.close_volume
    state.volume_step = volume_step
    state.reason = ''
    return Result('OK', REQUEST_ACTION, '', state.request_id, sp.close_volume, sp.close_steps)


def _done_quote(state, volume_current, volume_step):
    if volume_step != state.volume_step:
        state.status = NEEDS_RECONCILIATION
        return _res('RECONCILE_REQUIRED', state, reason='STEP_CHANGED: volume step %.10g is not the step %.10g of the request; reconcile with the broker' %
                    (volume_step, state.volume_step))
    cur = t006._grid_steps(volume_current, volume_step)
    expected = state.initial_steps - state.request_steps
    if cur != expected:
        state.status = NEEDS_RECONCILIATION
        return _res('RECONCILE_REQUIRED', state, reason='VOLUME_MISMATCH_AFTER_DONE: actual volume %.10g is not the expected remainder (%d steps)' %
                    (volume_current, expected))
    return Result('IGNORED', reason='IGNORED: partial close is DONE')


def on_report(state, request_id, kind, executed_volume, volume_step):
    if not isinstance(request_id, str) or request_id == '':
        return Result('INVALID_INPUT', reason='INVALID_REQUEST_ID: must be a non-empty string')
    if isinstance(kind, bool) or kind not in REPORT_KINDS:
        return Result('INVALID_INPUT', reason='INVALID_REPORT_KIND')
    if not _num(executed_volume) or executed_volume < 0:
        return Result('INVALID_INPUT', reason='INVALID_EXECUTED_VOLUME: %s must be finite and >= 0' % t006._g(executed_volume))
    if not _num(volume_step) or volume_step <= 0:
        return Result('INVALID_INPUT', reason='INVALID_VOLUME_STEP: %s must be finite and > 0' % t006._g(volume_step))
    if state.status == NEEDS_RECONCILIATION:
        return Result('RECONCILE_REQUIRED', reason='RECONCILE_REQUIRED: ' + state.reason)
    if state.status == BLOCKED:
        return Result('BLOCKED', reason='BLOCKED: ' + state.reason)
    if state.status == IDLE:
        state.status = BLOCKED
        return _res('BLOCKED', state, reason='REPORT_WITHOUT_REQUEST: no request exists for %s' % request_id)
    if request_id != state.request_id:
        state.status = BLOCKED
        return _res('BLOCKED', state, reason='WRONG_REQUEST_ID: %s is not %s' % (request_id, state.request_id))
    if volume_step != state.volume_step:
        state.status = BLOCKED
        return _res('BLOCKED', state, reason='STEP_CHANGED: report step %.10g is not the step %.10g of the request; the volume is not compared on another grid' %
                    (volume_step, state.volume_step))
    steps = t006._grid_steps(executed_volume, state.volume_step) if executed_volume > 0 else 0
    if steps < 0:
        state.status = BLOCKED
        return _res('BLOCKED', state, reason='VOLUME_NOT_ON_GRID: executed volume %.10g is not a multiple of step %.10g' % (executed_volume, volume_step))
    if state.status == DONE:
        if kind == FULL and steps == state.request_steps:
            state.duplicates_ignored += 1
            return Result('DUPLICATE_IGNORED', reason='DUPLICATE_IGNORED: confirmation already counted')
        state.status = BLOCKED
        return _res('BLOCKED', state, reason='CONFLICTING_REPORT_AFTER_DONE')
    # REQUEST_PENDING
    if kind == FULL:
        if steps != state.request_steps:
            state.status = BLOCKED
            return _res('BLOCKED', state, reason='VOLUME_MISMATCH: FULL confirmation of %d steps, requested %d' % (steps, state.request_steps))
        state.status = DONE
        state.executed_steps = steps
        state.confirmations += 1
        state.reason = ''
        return Result('OK')
    if kind == PARTIAL:
        if not (0 < steps < state.request_steps):
            state.status = BLOCKED
            return _res('BLOCKED', state, reason='VOLUME_MISMATCH: PARTIAL execution of %d steps is outside (0, %d)' % (steps, state.request_steps))
        state.status = NEEDS_RECONCILIATION
        state.executed_steps = steps
        return _res('RECONCILE_REQUIRED', state, reason='PARTIAL_EXECUTION: %d of %d steps executed; reconcile with the broker, no automatic retry' %
                    (steps, state.request_steps))
    state.status = NEEDS_RECONCILIATION
    return _res('RECONCILE_REQUIRED', state, reason='%s: request %s not confirmed; reconcile with the broker, no automatic retry' %
                ('REJECTED' if kind == REJECTED else 'TIMEOUT', state.request_id))
