"""T011 TICK DRIVER (Python mirror of src/include/ExitTickDriver.mqh): the thin wiring between a quote loop and the EXISTING executor. No state machine of its own, no trading call.
DISABLED by default. ONE lock (per terminal) wraps everything that reads or changes the record or could send (init / recovery, a tick that reaches the level, the reconcile timer, the explicit
registration); a lock failure means zero sends and no I/O. Init runs the RECOVERY (the restart flow) BEFORE any quote is allowed and arms the tick path only for an IDLE R_GEOM record.
The tick never calls the executor for a record that is not IDLE and does no I/O below the level. The timer only reconciles. OnInit never registers."""
from dataclasses import dataclass

import t011_executor_reference as ex
import t011_flow_reference as fl
import t011_persist_reference as p


@dataclass
class State:
    armed: bool = False
    direction: int = 0
    level: float = 0.0
    reconcile_due: bool = False
    reason: str = 'NOT_INITIALISED'
    process_calls: int = 0
    lock_failures: int = 0


def lock_key(identity):
    return 'VELO_T011_LOCK_%d_%d' % (identity.login, identity.position_id)


def register(cfg, tr, rt, store, name, identity, q, locks):
    key = lock_key(identity)
    if not locks.acquire(key):
        return ex.Result(ex.BLOCKED, 'INSTANCE_LOCK_HELD: zero sends')
    try:
        return ex.register(cfg, tr, rt, store, name, identity, q)
    finally:
        locks.release(key)


def init(cfg, tr, store, name, identity, raw_a, raw_b, s, locks):
    """returns (armed, flow result or None)"""
    s.__dict__.update(State().__dict__)
    if not cfg.enabled:
        s.reason = 'INIT_DISABLED: the driver is off by default; nothing is read, locked or armed'
        return False, None
    key = lock_key(identity)
    if not locks.acquire(key):
        s.lock_failures += 1
        s.reason = 'INIT_LOCK_FAILED: nothing is read, nothing can be sent'
        return False, None
    try:
        o = store.load(name, identity)
        if o.generation == 0:
            s.reason = 'INIT_LOAD_UNUSABLE: %s; the file is never created or changed here (registration is a separate action)' % o.reason
            return False, None
        if o.verdict != p.USABLE_IDLE:
            flow = fl.run(store, name, identity, raw_a, raw_b)       # RECOVERY BEFORE ACTIVATION; never arms the tick path
            s.reconcile_due = flow.final == fl.STILL_OPEN
            s.reason = 'INIT_RECOVERY: %s: %s' % (flow.final, flow.reason)
            return False, flow
        if not o.plan_set or o.plan_rpol != ex.RPOL_R_GEOM or cfg.r_policy != ex.RPOL_R_GEOM:
            s.reason = 'INIT_PLAN_NOT_R_GEOM: the record carries no R_GEOM plan or the configured policy differs; nothing is armed'
            return False, None
        s.armed, s.direction, s.level, s.reason = True, o.state.direction, o.state.level, 'ARMED'
        return True, None
    finally:
        locks.release(key)


def tick(cfg, tr, rt, store, name, identity, q, s, locks):
    """returns the executor Result (a driver-made one when the executor is not called)"""
    if not s.armed:
        return ex.Result(ex.BLOCKED, 'NOT_ARMED: ' + s.reason)
    if (not q.bid >= s.level) if s.direction == 1 else (not q.ask <= s.level):
        return ex.Result(ex.NO_REQUEST, 'the 2R level is not reached')
    key = lock_key(identity)
    if not locks.acquire(key):
        s.lock_failures += 1
        return ex.Result(ex.BLOCKED, 'TICK_LOCK_FAILED: zero sends')
    try:
        o = store.load(name, identity)
        if o.generation == 0 or o.verdict != p.USABLE_IDLE:
            s.armed = False
            s.reason = 'RECORD_NOT_IDLE: the record changed or needs reconciliation; EX_Process is not called'
            return ex.Result(ex.BLOCKED, s.reason)
        s.process_calls += 1
        res = ex.process(cfg, tr, rt, store, name, identity, q)
        if res.final == ex.SENT_MAPPED:
            s.armed, s.reconcile_due, s.reason = False, True, 'SENT: reconcile on the timer'
        elif res.final in (ex.RECOVERY_REQUIRED, ex.NOT_IDLE) or rt.latched:
            s.armed, s.reason = False, 'DISARMED: ' + res.reason
        return res
    finally:
        locks.release(key)


def timer(store, name, identity, raw_a, raw_b, s, locks):
    """returns the flow result or None when nothing was done"""
    if not s.reconcile_due:
        return None
    key = lock_key(identity)
    if not locks.acquire(key):
        s.lock_failures += 1
        s.reason = 'TIMER_LOCK_FAILED'
        return None
    try:
        flow = fl.run(store, name, identity, raw_a, raw_b)
        s.reconcile_due = flow.final == fl.STILL_OPEN
        s.reason = 'TIMER: %s: %s' % (flow.final, flow.reason)
        return flow
    finally:
        locks.release(key)
