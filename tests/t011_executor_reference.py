"""T011 partial-close EXECUTOR (Python mirror of src/include/ExitExecutor.mqh): DETACHED and DISABLED by default, no signal, no trading-EA hook.

PROTOCOL (existing modules only): request from ExitActivation (EA_OnQuote, the ONLY producer) -> INTENT persisted AND verified -> at most ONE send call -> order-ticket map persisted
-> ExitRestartFlow (ERF_Run) reconciles; DONE comes only from the reconciliation. The transport is an abstract seam: tests use the FAKE transport only; the REAL transport lives in
its own header, is never included by a test and is never executed here.

EVERY UNCERTAINTY IS RECOVERY_REQUIRED, NEVER A SEND OR A RESEND. In particular a SAVE that returns false does NOT prove the old file is still on disk (the move may have happened and
the read-back may have failed): after any save failure the executor returns RECOVERY_REQUIRED, sends nothing (or nothing more) and latches the position in memory until restart;
what is on disk is whatever the next ESF_Load says. A restart after INTENT is a record that is not IDLE -> no send (NOT_IDLE) and the flow reports the uncertain send.

GATES (zero sends when any fails, in this order): enabled (default False); mandatory inputs (ea_magic > 0, filling, deviation, exit-filter policy: UNSET blocks); exit-filter policy NEEDS_CLEAR with a
state that is not CLEAR; TP known and strictly beyond the 2R level (TP == 2R or before it blocks); in-memory latch; real transport only with an explicit authorisation phrase AND a DEMO account;
account readable, same login/server as the record, trading allowed, HEDGING; symbol readable and tradable (full or close-only); level and TP exactly on the tick grid (a value off the grid is REFUSED,
never rounded - the plan is never changed to fit); the position found by IDENTIFIER with its current TICKET, the same symbol, magic == ea_magic (> 0) and the same direction; the record loads and is IDLE
(unusable -> RECOVERY_REQUIRED, other states -> NOT_IDLE, use the flow); EA_OnQuote (SPLIT_POLICY_UNSET, a changed volume, ... block; below the level -> NO_REQUEST); a read-only pre-check of the
request (OrderCheck in the real transport); the INTENT save + an independent re-load that must show exactly generation + 1 with PENDING + INTENT and no map.
SEND: one call (the runtime counter refuses a second call for the same request). ACCEPTED = the call returned true AND a result exists AND retcode in {PLACED 10008, DONE 10009, DONE_PARTIAL 10010}
AND an order ticket > 0 (returned true alone is NOT a fill proof; a fill is proven only by the reconciliation). Anything else = uncertain: INTENT stays on disk, RECOVERY_REQUIRED, latch.
No rejection class exists until the return-code table is verified from the official documentation (it could not be opened here).
MAP: PENDING + MAPPED with the single order ticket (orders_complete true: one request, one call), generation + 1; a failed map save is RECOVERY_REQUIRED (the ticket is in the message).
NOT PROTECTED: parallel writers (two terminals / two instances on the same folder): there is no lock; nothing here proves otherwise.
"""
import math
import sys
from dataclasses import dataclass, field

import t011_activation_reference as act
import t011_persist_reference as p

AUTH_PHRASE = 'I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE'
FILL_UNSET, FILL_FOK, FILL_IOC, FILL_RETURN = 0, 1, 2, 3
POL_UNSET, POL_IGNORE, POL_NEEDS_CLEAR = 0, 1, 2
FS_UNKNOWN, FS_CLEAR, FS_BLOCKED = 0, 1, 2
SAVE_NONE, SAVE_BEFORE, SAVE_AFTER = 0, 1, 2
BLOCKED, RECOVERY_REQUIRED, NOT_IDLE, NO_REQUEST, SENT_MAPPED = 'BLOCKED', 'RECOVERY_REQUIRED', 'NOT_IDLE', 'NO_REQUEST', 'SENT_MAPPED'
ACCEPT_RETCODES = (10008, 10009, 10010)


@dataclass
class Config:
    enabled: bool = False
    real_authorised: bool = False
    authorisation: str = ''
    ea_magic: int = 0
    filling: int = FILL_UNSET
    deviation: int = -1
    filter_policy: int = POL_UNSET
    filter_state: int = FS_UNKNOWN
    tp_set: bool = False
    tp_price: float = 0.0
    test_save_fault: int = SAVE_NONE
    test_fault_save_no: int = 0


@dataclass
class Quote:
    direction: int
    level_2r: float
    bid: float
    ask: float
    volume_initial: float


@dataclass
class Runtime:
    latched: bool = False
    send_calls: int = 0
    save_calls: int = 0


@dataclass
class Account:
    read_ok: bool = True
    login: int = 5001234
    server: str = 'MetaQuotes-Demo'
    demo: bool = True
    trade_allowed: bool = True
    margin_mode: int = 2


@dataclass
class SymbolW:
    read_ok: bool = True
    vol_min: float = 0.01
    vol_step: float = 0.01
    vol_max: float = 100.0
    tick_size: float = 0.01
    close_allowed: bool = True


@dataclass
class PositionW:
    found: bool = True
    ticket: int = 9
    identifier: int = 7
    symbol: str = 'XAUUSD'
    magic: int = 777
    type: int = 0
    volume: float = 0.5


@dataclass
class SendRequest:
    action: str
    symbol: str
    volume: float
    type: int
    position: int
    magic: int
    deviation: int
    filling: int
    price: float
    comment: str


@dataclass
class SendResult:
    returned_true: bool = False
    have_result: bool = False
    retcode: int = 0
    order: int = 0
    deal: int = 0
    volume: float = 0.0
    price: float = 0.0


class FakeTransport:
    """Test double. Counts every send; never touches a terminal."""

    def __init__(self):
        self.real = False
        self.account = Account()
        self.symbol = SymbolW()
        self.position = PositionW()
        self.precheck_ok = True
        self.response = SendResult()
        self.sends = []

    def is_real(self):
        return self.real

    def read_account(self):
        return self.account

    def read_symbol(self, name):
        return self.symbol

    def find_position(self, identifier):
        return self.position

    def precheck(self, req):
        return self.precheck_ok

    def send(self, req):
        self.sends.append(req)
        return self.response


@dataclass
class Result:
    final: str
    reason: str = ''
    sends: int = 0
    order_ticket: int = 0
    request: object = None


def _int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def _finite(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)


def _on_grid(x, tick):
    """Exactly on the tick grid up to FLOATING-POINT NOISE only: eight units of the machine epsilon relative to the number of ticks. A real difference (0.004 with a tick of 0.01) is refused.
    Non-finite or non-positive inputs are never on the grid."""
    if not _finite(x) or not _finite(tick) or x <= 0 or tick <= 0:
        return False
    r = x / tick
    if not math.isfinite(r) or abs(r) > 1e12:
        return False
    return abs(r - round(r)) <= 8 * sys.float_info.epsilon * max(1.0, abs(r))


def _save(cfg, rt, store, name, rec):
    rt.save_calls += 1
    if cfg.test_save_fault != SAVE_NONE and cfg.test_fault_save_no == rt.save_calls:
        if cfg.test_save_fault == SAVE_AFTER:
            store.save(name, rec)
        return False, 'TEST_SAVE_FAULT'
    return store.save(name, rec)


def process(cfg, tr, rt, store, name, identity, q):
    res = Result(BLOCKED)

    def block(reason):
        res.final, res.reason = BLOCKED, reason
        return res

    def recovery(reason, latch=True):
        res.final, res.reason = RECOVERY_REQUIRED, reason
        if latch:
            rt.latched = True
        res.sends = rt.send_calls
        return res

    if not cfg.enabled:
        return block('DISABLED: the executor is off by default')
    if not _int(cfg.filling) or cfg.filling not in (FILL_UNSET, FILL_FOK, FILL_IOC, FILL_RETURN):
        return block('INVALID_INPUT: filling is not a known value')
    if not _int(cfg.filter_policy) or cfg.filter_policy not in (POL_UNSET, POL_IGNORE, POL_NEEDS_CLEAR):
        return block('INVALID_INPUT: exit_filter_policy is not a known value')
    if not _int(cfg.filter_state) or cfg.filter_state not in (FS_UNKNOWN, FS_CLEAR, FS_BLOCKED):
        return block('INVALID_INPUT: exit_filter_state is not a known value')
    if not _int(cfg.test_save_fault) or cfg.test_save_fault not in (SAVE_NONE, SAVE_BEFORE, SAVE_AFTER):
        return block('INVALID_INPUT: test_save_fault is not a known value')
    if not _int(q.direction) or q.direction not in (1, -1):
        return block('INVALID_INPUT: direction must be 1 (BUY) or -1 (SELL)')
    if cfg.ea_magic <= 0:
        return block('INPUT_UNSET: ea_magic')
    if cfg.filling == FILL_UNSET:
        return block('INPUT_UNSET: filling')
    if cfg.deviation < 0:
        return block('INPUT_UNSET: deviation')
    if cfg.filter_policy == POL_UNSET:
        return block('INPUT_UNSET: exit_filter_policy')
    if cfg.filter_policy == POL_NEEDS_CLEAR and cfg.filter_state != FS_CLEAR:
        return block('EXIT_FILTERS_NOT_CLEAR')
    if not cfg.tp_set:
        return block('TP_UNKNOWN')
    if rt.latched:
        return block('LATCHED: an earlier uncertainty on this executor; restart and recover first')
    if rt.send_calls >= 1:
        return block('DUPLICATE_CALL: a send was already made by this executor instance')
    acct = tr.read_account()
    if tr.is_real():
        if not (cfg.real_authorised and cfg.authorisation == AUTH_PHRASE):
            return block('REAL_NOT_AUTHORISED')
        if not acct.read_ok or not acct.demo:
            return block('REAL_REQUIRES_DEMO_ACCOUNT')
    if not acct.read_ok:
        return block('ACCOUNT_UNREADABLE')
    if acct.login != identity.login or acct.server != identity.server:
        return block('ACCOUNT_IDENTITY_MISMATCH')
    if not acct.trade_allowed:
        return block('TRADING_NOT_ALLOWED')
    if acct.margin_mode != 2:
        return block('UNSUPPORTED_ACCOUNT_MODE: only HEDGING')
    sym = tr.read_symbol(identity.symbol)
    if not sym.read_ok or not sym.close_allowed or sym.tick_size <= 0:
        return block('SYMBOL_UNREADABLE_OR_NOT_TRADABLE')
    if not _on_grid(q.level_2r, sym.tick_size):
        return block('PLAN_NOT_ON_SYMBOL_GRID: level_2R is refused, not rounded')
    if not _on_grid(cfg.tp_price, sym.tick_size):
        return block('PLAN_NOT_ON_SYMBOL_GRID: TP is refused, not rounded')
    if p.fnum(q.level_2r) is None or p.fnum(cfg.tp_price) is None:
        return block('PLAN_NOT_REPRESENTABLE_IN_RECORD: level_2R or TP does not round-trip through 12 decimals; the plan is not rounded and nothing is persisted')
    if abs(cfg.tp_price - q.level_2r) < sym.tick_size / 2:
        return block('TP_EQUALS_2R: the interaction is an open decision')
    if (q.direction == 1 and cfg.tp_price < q.level_2r) or (q.direction == -1 and cfg.tp_price > q.level_2r):
        return block('TP_BEFORE_2R: inconsistent with the minimum of 2R')
    pos = tr.find_position(identity.position_id)
    if not pos.found or pos.ticket <= 0 or pos.identifier != identity.position_id:
        return block('POSITION_NOT_FOUND')
    if pos.symbol != identity.symbol or pos.magic != cfg.ea_magic or pos.type != (0 if q.direction == 1 else 1):
        return block('OWNERSHIP_NOT_PROVEN: symbol, magic or direction differ from the record / configuration')
    o = store.load(name, identity)
    if o.generation == 0:
        return recovery('LOAD_UNUSABLE: ' + o.reason, latch=False)
    if o.verdict != p.USABLE_IDLE:
        res.final, res.reason = NOT_IDLE, 'The record is not IDLE (%s): no send; use the restart flow' % o.verdict
        return res
    st = o.state
    r = act.on_quote(st, identity.position_id, q.direction, q.level_2r, q.bid, q.ask, q.volume_initial, pos.volume, sym.vol_min, sym.vol_step, sym.vol_max)
    if r.action != act.REQUEST_ACTION:
        if r.event == 'OK':
            res.final, res.reason = NO_REQUEST, 'the 2R level is not reached'
            return res
        return block('%s: %s' % (r.event, r.reason))
    req = SendRequest('DEAL', identity.symbol, r.request_volume, 1 if q.direction == 1 else 0, pos.ticket, cfg.ea_magic, cfg.deviation, cfg.filling,
                      q.bid if q.direction == 1 else q.ask, r.request_id)
    if not tr.precheck(req):
        return block('PRECHECK_FAILED: nothing persisted, nothing sent')
    gen = o.generation + 1
    ok, why = _save(cfg, rt, store, name, p.Record(gen, identity, st, p.SEND_INTENT))
    if not ok:
        return recovery('INTENT_SAVE_FAILED: %s; the file may or may not hold the new record; nothing is sent' % why)
    chk = store.load(name, identity)
    if not (chk.verdict == p.RECOVERY_REQUIRED and chk.generation == gen and not chk.orders and chk.state.request_id == st.request_id and 'SEND_UNCERTAIN' in chk.reason):
        return recovery('INTENT_NOT_VERIFIED: the re-load does not show the saved intent; nothing is sent')
    if rt.send_calls >= 1:
        return recovery('DUPLICATE_CALL_GUARD: unreachable unless the gates above were bypassed; nothing more is sent')
    rt.send_calls += 1
    sr = tr.send(req)
    res.sends = rt.send_calls
    res.request = req
    accepted = sr.returned_true and sr.have_result and sr.retcode in ACCEPT_RETCODES and sr.order > 0
    if not accepted:
        return recovery('SEND_UNCERTAIN: returned_true=%s result=%s retcode=%d order=%d; no retry, no resend, the intent stays on disk' %
                        (sr.returned_true, sr.have_result, sr.retcode, sr.order))
    res.order_ticket = sr.order
    ok, why = _save(cfg, rt, store, name, p.Record(gen + 1, identity, st, p.SEND_MAPPED, True, [sr.order]))
    if not ok:
        return recovery('MAP_NOT_SAVED: %s; order ticket %d must be recorded by hand; the intent (or the map) is what the next load shows' % (why, sr.order))
    res.final, res.reason = SENT_MAPPED, 'sent once; order %d mapped; run the restart flow to reconcile (returned true is not a fill proof)' % sr.order
    return res
