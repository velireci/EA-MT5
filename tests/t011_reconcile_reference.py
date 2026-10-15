"""T011 pure reconciliation of the 2R partial-close request against a caller-supplied SNAPSHOT (Python mirror of
src/include/ExitReconciliation.mqh).

NOT a trading module. No broker read, no order, no retry, no clock, no persistence, no restart guarantee. The snapshot is built
by the caller from whatever it already knows; this module only judges it.

ONE SOURCE OF STATE (no second state machine): reconcile() is a CONTROLLED TRANSITION on the SAME State object that
t011_activation_reference owns. It returns a decision AND, only through this function, applies the permitted transition to that state:
  CONFIRMED  -> status DONE (from REQUEST_PENDING or NEEDS_RECONCILIATION); confirmations becomes 1 and STAYS 1 for the request even when DONE is
                lost (re-check) and regained; executed_steps set. Needs executions_complete == True.
                The ONLY way out of NEEDS_RECONCILIATION. A quote or a plain report can never do it (activation module unchanged).
  PARTIAL    -> status NEEDS_RECONCILIATION (a partial fill stays for reconciliation), executed_steps = the snapshot's linked steps.
  NOT_EXECUTED / UNKNOWN / INVALID_INPUT -> no change.
  BLOCK      -> status BLOCKED (absorbing, like the activation module).
It never produces a request and never changes the 80/20 plan (initial_steps, request_steps, request_id, volume_step stay).

SNAPSHOT (all supplied): position_found, position_id, request_id, volume_step, volume_current, executions[] of (exec_id, request_id,
volume), executions_complete (True only when the caller knows the list holds every execution of the position). At most 16 executions.
Executed steps are RECOMPUTED from each snapshot (not accumulated), so the same execution seen in two snapshots is never counted twice;
inside a snapshot an execution is identified by exec_id: the same id with the same request and volume is a DUPLICATE (counted once),
the same id with another request or volume is a conflict -> BLOCK. Only executions linked to the request id count; others are
reported as `unlinked` and ignored.

DECISION ORDER, first failure wins (reasons start with the tag):
  INVALID_INPUT   malformed snapshot (ids empty, non-finite or non-positive numbers, more than 16 executions): nothing changes.
  state gate      BLOCKED -> BLOCK (ALREADY_BLOCKED, no change); no request exists (IDLE, or a reconcile before the request) -> UNKNOWN NO_REQUEST.
  BLOCK           WRONG_POSITION, WRONG_REQUEST_ID, STEP_CHANGED (snapshot step != the step of the request), POSITION_MISSING (a missing
                  position cannot be matched, so DONE is never possible), EXEC_ID_CONFLICT, VOLUME_NOT_ON_GRID (an execution), OVERFILL
                  (linked steps > requested steps).
  then with linked = sum of the linked steps, expected = initial_steps - linked, cur = position steps (-1 off the grid):
    linked == requested:  cur != expected -> BLOCK (VOLUME_MISMATCH: the position differs from initial - requested);
                          list not declared complete -> UNKNOWN (INCOMPLETE_EVIDENCE: a matching sum is not proof of a complete list);
                          else CONFIRMED.
    0 < linked < requested: cur == expected -> PARTIAL;  else complete list -> BLOCK, incomplete -> UNKNOWN (an unseen fill may explain it).
    linked == 0:  cur == initial and complete -> NOT_EXECUTED;  cur == initial and incomplete -> UNKNOWN;
                  cur != initial: complete -> BLOCK (volume changed without a linked execution: manual change?), incomplete -> UNKNOWN.
                  A volume drop ALONE never proves that our request executed.
  A state DONE is re-checked the same way: CONFIRMED -> no change; BLOCK -> BLOCKED; anything else -> NEEDS_RECONCILIATION.
A late fill after a TIMEOUT is accepted only here: the snapshot must name the request id, show linked executions of exactly the requested
volume and a position that matches; an explicit REJECTED followed by such evidence is accepted the same way (the evidence is what counts).
"""
import math
from dataclasses import dataclass, field

import t006_sizing_reference as t006
import t011_activation_reference as act

MAX_EXEC = 16
CONFIRMED, PARTIAL, NOT_EXECUTED, UNKNOWN, BLOCK, INVALID_INPUT = 'CONFIRMED', 'PARTIAL', 'NOT_EXECUTED', 'UNKNOWN', 'BLOCK', 'INVALID_INPUT'


@dataclass
class Exec:
    exec_id: str
    request_id: str
    volume: float


@dataclass
class Snapshot:
    position_found: bool
    position_id: int
    request_id: str
    volume_step: float
    volume_current: float
    executions: list = field(default_factory=list)
    executions_complete: bool = False
    position_closed_proven: bool = False


@dataclass
class Outcome:
    decision: str
    reason: str = ''
    linked_steps: int = 0
    duplicates: int = 0
    unlinked: int = 0
    changed: bool = False


def _bad(reason):
    return Outcome(INVALID_INPUT, reason)


def _validate(snap):
    if not isinstance(snap, Snapshot):
        return _bad('INVALID_SNAPSHOT: not a snapshot')
    if not isinstance(snap.position_found, bool) or not isinstance(snap.executions_complete, bool) or not isinstance(snap.position_closed_proven, bool):
        return _bad('INVALID_SNAPSHOT: flags must be booleans')
    if snap.position_closed_proven and snap.position_found:
        return _bad('INVALID_SNAPSHOT: a position cannot be both found and proven closed')
    if isinstance(snap.position_id, bool) or not isinstance(snap.position_id, int) or snap.position_id <= 0:
        return _bad('INVALID_POSITION_ID: must be an integer > 0')
    if not isinstance(snap.request_id, str) or snap.request_id == '':
        return _bad('INVALID_REQUEST_ID: must be a non-empty string')
    if not t006._num(snap.volume_step) or snap.volume_step <= 0:
        return _bad('INVALID_VOLUME_STEP: %s must be finite and > 0' % t006._g(snap.volume_step))
    if not t006._num(snap.volume_current) or snap.volume_current < 0 or (snap.position_found and snap.volume_current <= 0):
        return _bad('INVALID_VOLUME_CURRENT: %s must be finite and > 0 for a found position' % t006._g(snap.volume_current))
    if not isinstance(snap.executions, (list, tuple)) or len(snap.executions) > MAX_EXEC:
        return _bad('INVALID_EXECUTIONS: at most %d executions' % MAX_EXEC)
    for e in snap.executions:
        if not isinstance(e, Exec) or not isinstance(e.exec_id, str) or e.exec_id == '' or not isinstance(e.request_id, str) or e.request_id == '':
            return _bad('INVALID_EXECUTION: ids must be non-empty strings')
        if not t006._num(e.volume) or e.volume <= 0:
            return _bad('INVALID_EXECUTION: volume %s must be finite and > 0' % t006._g(e.volume))
    return None


def _block(state, reason, **kw):
    state.status = act.BLOCKED
    state.reason = reason
    return Outcome(BLOCK, reason, changed=True, **kw)


def reconcile(state, snap):
    bad = _validate(snap)
    if bad:
        return bad
    if state.status == act.BLOCKED:
        return Outcome(BLOCK, 'ALREADY_BLOCKED: ' + state.reason)
    if not state.bound or state.request_id == '' or state.status == act.IDLE:
        return Outcome(UNKNOWN, 'NO_REQUEST: there is no request to reconcile')
    if snap.position_id != state.position_id:
        return _block(state, 'WRONG_POSITION: snapshot position %d is not %d' % (snap.position_id, state.position_id))
    if snap.request_id != state.request_id:
        return _block(state, 'WRONG_REQUEST_ID: snapshot request %s is not %s' % (snap.request_id, state.request_id))
    if snap.volume_step != state.volume_step:
        return _block(state, 'STEP_CHANGED: snapshot step %.10g is not the step %.10g of the request' % (snap.volume_step, state.volume_step))
    if not snap.position_found:
        fin = _finished_after_done(state, snap)
        if fin:
            return Outcome(CONFIRMED, 'ALREADY_DONE: POSITION_CLOSED_PROVEN_BY_HISTORY', linked_steps=fin[0], duplicates=fin[1], unlinked=fin[2])
        return _block(state, 'POSITION_MISSING: the position is not in the snapshot; DONE needs a matching position')
    seen = {}
    linked, dups, unlinked = 0, 0, 0
    for e in snap.executions:
        key = (e.request_id, e.volume)
        if e.exec_id in seen:
            if seen[e.exec_id] == key:
                dups += 1
                continue
            return _block(state, 'EXEC_ID_CONFLICT: execution %s appears with another request or volume' % e.exec_id, duplicates=dups, unlinked=unlinked)
        seen[e.exec_id] = key
        if e.request_id != state.request_id:
            unlinked += 1
            continue
        k = t006._grid_steps(e.volume, state.volume_step)
        if k < 0:
            return _block(state, 'VOLUME_NOT_ON_GRID: execution %s volume %.10g is not a multiple of step %.10g' % (e.exec_id, e.volume, state.volume_step),
                          duplicates=dups, unlinked=unlinked)
        linked += k
    req = state.request_steps
    if linked > req:
        return _block(state, 'OVERFILL: linked executions %d steps exceed the requested %d' % (linked, req), linked_steps=linked, duplicates=dups, unlinked=unlinked)
    cur = t006._grid_steps(snap.volume_current, state.volume_step)
    expected = state.initial_steps - linked
    complete = snap.executions_complete
    done_before = state.status == act.DONE
    common = dict(linked_steps=linked, duplicates=dups, unlinked=unlinked)
    if linked == req:
        if cur != expected:
            return _block(state, 'VOLUME_MISMATCH: position %.10g lot is not initial - requested (%d steps)' % (snap.volume_current, expected), **common)
        if not complete:
            out = _not_done(state, done_before, linked, 'UNKNOWN: INCOMPLETE_EVIDENCE: the linked executions equal the request and the position matches, but the list is not declared complete (a sum of volume does not make it complete)')
            out.decision, out.linked_steps, out.duplicates, out.unlinked = UNKNOWN, linked, dups, unlinked
            return out
        if done_before:
            return Outcome(CONFIRMED, 'ALREADY_DONE', **common)
        state.status = act.DONE
        state.executed_steps = linked
        if state.confirmations < 1:                  # ONE confirmation per request, also when DONE was lost and is regained
            state.confirmations = 1
        state.reason = ''
        return Outcome(CONFIRMED, '', changed=True, **common)
    if linked > 0 and cur == expected:
        out = _not_done(state, done_before, linked, 'PARTIAL_FILL: %d of %d steps executed; reconcile with the broker, no automatic retry' % (linked, req))
        out.decision, out.linked_steps, out.duplicates, out.unlinked = PARTIAL, linked, dups, unlinked
        return out
    if linked > 0:
        what = 'VOLUME_MISMATCH: position %.10g lot does not match %d linked steps' % (snap.volume_current, linked)
    elif cur == state.initial_steps:
        if complete:
            out = _not_done(state, done_before, 0, 'NOT_EXECUTED: complete evidence shows no linked execution and an unchanged position')
            out.decision, out.duplicates, out.unlinked = NOT_EXECUTED, dups, unlinked
            return out
        what = 'INCOMPLETE_EVIDENCE: no linked execution seen, the list is not complete'
    else:
        what = 'VOLUME_CHANGED_WITHOUT_LINKED_EXECUTION: position %.10g lot, no linked execution (a volume drop alone proves nothing)' % snap.volume_current
    if complete:
        return _block(state, what, **common)
    out = _not_done(state, done_before, linked, 'UNKNOWN: ' + what)
    out.decision, out.linked_steps, out.duplicates, out.unlinked = UNKNOWN, linked, dups, unlinked
    return out


def _finished_after_done(state, snap):
    """The ONLY answer for a position that is not open: an existing DONE (confirmations 1) whose linked executions still equal the request exactly, a complete
    list and a position the adapter PROVED closed from the history. Changes nothing. Returns (linked, duplicates, unlinked) or None; any doubt (conflict, off the
    grid, other volume) -> None -> POSITION_MISSING BLOCK."""
    if state.status != act.DONE or state.confirmations != 1 or not snap.position_closed_proven or not snap.executions_complete:
        return None
    seen, linked, dups, unlinked = {}, 0, 0, 0
    for e in snap.executions:
        key = (e.request_id, e.volume)
        if e.exec_id in seen:
            if seen[e.exec_id] != key:
                return None
            dups += 1
            continue
        seen[e.exec_id] = key
        if e.request_id != state.request_id:
            unlinked += 1
            continue
        k = t006._grid_steps(e.volume, state.volume_step)
        if k < 0:
            return None
        linked += k
    return (linked, dups, unlinked) if linked == state.request_steps else None


def _not_done(state, done_before, linked, reason):
    """No permission to confirm: a DONE state loses its DONE, a pending/reconciling state keeps its status (partial -> reconcile)."""
    before = (state.status, state.executed_steps)
    if done_before:
        state.status = act.NEEDS_RECONCILIATION
        state.reason = reason
    elif reason.startswith('PARTIAL_FILL'):
        state.status = act.NEEDS_RECONCILIATION
        state.executed_steps = linked
        state.reason = reason
    return Outcome(UNKNOWN, reason, changed=(before != (state.status, state.executed_steps)))
