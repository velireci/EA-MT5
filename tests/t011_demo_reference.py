"""T011 demo harness (Python mirror of src/include/DemoHarness.mqh): the existing modules wired for ONE controlled demo test, behind explicit gates. FAKE transport only here.
Steps: NONE (default, disabled) / STATUS (read-only) / REGISTER / ACTIVATE / RECONCILE. The acting steps hold an instance lock (per terminal; NOT protection between terminals).
ACTIVATE is the only step that can send, and it needs confirm_send_once as well as every gate of the executor (authorisation phrase and a DEMO account for a real transport,
registered plan, IDLE record, owned position, mandatory parameters). Nothing here deletes or cleans a record."""
from dataclasses import dataclass

import t011_executor_reference as ex
import t011_flow_reference as fl
import t011_persist_reference as p

NONE, STATUS, REGISTER, ACTIVATE, RECONCILE = 'NONE', 'STATUS', 'REGISTER', 'ACTIVATE', 'RECONCILE'


@dataclass
class Params:
    step: str = NONE
    authorisation: str = ''
    confirm_send_once: bool = False
    magic: int = 0
    position_id: int = 0
    symbol: str = ''
    direction: int = 0
    level_2r: float = -1.0
    tp_price: float = -1.0
    volume_initial: float = 0.0
    filling: int = ex.FILL_UNSET
    deviation: int = -1
    filter_policy: int = ex.POL_UNSET
    filter_state: int = ex.FS_UNKNOWN
    use_lock: bool = True
    file_name: str = ''
    lock_key: str = ''


@dataclass
class Quote:
    read_ok: bool = False
    bid: float = 0.0
    ask: float = 0.0


@dataclass
class Result:
    status: str = 'DISABLED'
    detail: str = 'step NONE: the harness is off by default'
    sends: int = 0
    file: str = ''


class Locks:
    """a stand-in for the terminal's temporary global variables (one terminal)"""

    def __init__(self):
        self.held = set()

    def acquire(self, key):
        if not key or key in self.held:
            return False
        self.held.add(key)
        return True

    def release(self, key):
        self.held.discard(key)


def demo_file(login, position_id):
    return 'VELO_T011_DEMO_%d_%d.state' % (login, position_id)


def lock_key(login, position_id):
    return 'VELO_T011_LOCK_%d_%d' % (login, position_id)


def run(prm, tr, quote, raw_a, raw_b, store, locks):
    res = Result()
    if prm.step == NONE:
        return False, res
    if prm.position_id <= 0 or prm.symbol == '':
        res.status, res.detail = 'BLOCKED', 'INPUT_UNSET: position_id or symbol'
        return False, res
    acct = tr.read_account()
    if not acct.read_ok:
        res.status, res.detail = 'BLOCKED', 'ACCOUNT_UNREADABLE'
        return False, res
    ident = p.Identity(acct.server, acct.login, prm.symbol, prm.position_id)
    name = prm.file_name or demo_file(acct.login, prm.position_id)
    res.file = name
    if prm.step == STATUS:
        o = store.load(name, ident)
        res.status = 'STATUS'
        res.detail = 'verdict %s state %s generation %d plan_set %d orders %d confirmations %d new_request_allowed %d reconcile_required %d %s' % (
            o.verdict, o.state.status, o.generation, int(o.plan_set), len(o.orders), o.state.confirmations, int(o.new_request_allowed), int(o.reconcile_required), o.reason)
        return True, res
    cfg = ex.Config(enabled=True, r_policy=ex.RPOL_TYPED, real_authorised=(prm.authorisation == ex.AUTH_PHRASE), authorisation=prm.authorisation, ea_magic=prm.magic, filling=prm.filling,
                    deviation=prm.deviation, filter_policy=prm.filter_policy, filter_state=prm.filter_state, tp_set=prm.tp_price > 0, tp_price=prm.tp_price)
    q = ex.Quote(prm.direction, prm.level_2r, quote.bid, quote.ask, prm.volume_initial)
    key = prm.lock_key or lock_key(acct.login, prm.position_id)
    held = False
    if prm.use_lock:
        if not locks.acquire(key):
            res.status, res.detail = 'BLOCKED', 'INSTANCE_LOCK_HELD: another instance holds %s in this terminal' % key
            return False, res
        held = True
    ok = False
    rt = ex.Runtime()
    try:
        if prm.step == REGISTER:
            xr = ex.register(cfg, tr, rt, store, name, ident, q)
            res.status, res.detail, ok = xr.final, xr.reason, xr.final == ex.REGISTERED
        elif prm.step == ACTIVATE:
            if not prm.confirm_send_once:
                res.status, res.detail = 'BLOCKED', 'ACTIVATE needs confirm_send_once = true'
            elif not quote.read_ok or not quote.bid > 0 or not quote.ask > 0:
                res.status, res.detail = 'BLOCKED', 'QUOTE_UNAVAILABLE'
            else:
                xr = ex.process(cfg, tr, rt, store, name, ident, q)
                res.status, res.detail, res.sends, ok = xr.final, xr.reason, xr.sends, xr.final == ex.SENT_MAPPED
        elif prm.step == RECONCILE:
            fr = fl.run(store, name, ident, raw_a, raw_b)
            res.status, res.detail, ok = fr.final, fr.reason, fr.final == fl.DONE
    finally:
        if held:
            locks.release(key)
    return ok, res
