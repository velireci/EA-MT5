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

import t005_geometry_reference as tg
import t011_activation_reference as act
import t011_persist_reference as p
import t011_split_reference as es

AUTH_PHRASE = 'I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE'
FILL_UNSET, FILL_FOK, FILL_IOC, FILL_RETURN = 0, 1, 2, 3
POL_UNSET, POL_IGNORE, POL_NEEDS_CLEAR = 0, 1, 2
FS_UNKNOWN, FS_CLEAR, FS_BLOCKED = 0, 1, 2
SAVE_NONE, SAVE_BEFORE, SAVE_AFTER = 0, 1, 2
BLOCKED, RECOVERY_REQUIRED, NOT_IDLE, NO_REQUEST, SENT_MAPPED, REGISTERED = 'BLOCKED', 'RECOVERY_REQUIRED', 'NOT_IDLE', 'NO_REQUEST', 'SENT_MAPPED', 'REGISTERED'
ACCEPT_RETCODES = (10008, 10009, 10010)
RPOL_UNSET, RPOL_TYPED, RPOL_R_GEOM = 0, 1, 2     # UNSET blocks; TYPED = the diagnostic typed level of the demo harness; R_GEOM = R_GEOM from the stored E and the asserted initial SL (Part 14)


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
    r_policy: int = RPOL_UNSET
    sl_initial_set: bool = False     # R_GEOM: the initial stop ASSERTED by the owner (variant (a)); accepted at registration only while the live SL equals it
    sl_initial: float = 0.0


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
    digits: int = 2
    point: float = 0.01
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
    price_open: float = 0.0
    sl: float = 0.0


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


def _geometry(sym, direction, e_src, s_src, tp):
    """the ONLY place where the 2R level is derived: TG_Compute (here the T005 reference) over E and S; this module contains no 2R arithmetic. stops_level 0: the stops check judges an order, not a risk basis."""
    return tg.compute(tg.BUY if direction == 1 else tg.SELL, e_src, s_src, sym.tick_size, sym.digits, sym.point, 0, t_raw=tp)


def _plan_refusal(level, cfg, sym, direction, volume=None):
    """the grid / representation / TP-versus-2R checks of a plan whose level is already known; returns the reason or None (identical for the typed and the R_GEOM level)"""
    if not _on_grid(level, sym.tick_size):
        return 'PLAN_NOT_ON_SYMBOL_GRID: level_2R is refused, not rounded'
    if not _on_grid(cfg.tp_price, sym.tick_size):
        return 'PLAN_NOT_ON_SYMBOL_GRID: TP is refused, not rounded'
    if p.fnum(level) is None or p.fnum(cfg.tp_price) is None or (volume is not None and p.fnum(volume) is None):
        return 'PLAN_NOT_REPRESENTABLE_IN_RECORD: level_2R, TP or the initial volume does not round-trip through 12 decimals; nothing is rounded or persisted'
    if abs(cfg.tp_price - level) < sym.tick_size / 2:
        return 'TP_EQUALS_2R: the interaction is an open decision'
    if (direction == 1 and cfg.tp_price < level) or (direction == -1 and cfg.tp_price > level):
        return 'TP_BEFORE_2R: inconsistent with the minimum of 2R'
    return None


def _save(cfg, rt, store, name, rec):
    rt.save_calls += 1
    if cfg.test_save_fault != SAVE_NONE and cfg.test_fault_save_no == rt.save_calls:
        if cfg.test_save_fault == SAVE_AFTER:
            store.save(name, rec)
        return False, 'TEST_SAVE_FAULT'
    return store.save(name, rec)


def _rec(gen, identity, st, phase, o, complete=False, orders=()):
    """a record that carries the authorised plan unchanged from the loaded one"""
    return p.Record(gen, identity, st, phase, complete, list(orders), o.plan_set, o.plan_tp, o.plan_vol_min, o.plan_vol_step, o.plan_vol_max, o.plan_rpol, o.plan_e_src, o.plan_s_src,
                    o.plan_e_out, o.plan_s_out)


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
    if not _int(cfg.r_policy) or cfg.r_policy not in (RPOL_UNSET, RPOL_TYPED, RPOL_R_GEOM):
        return block('INVALID_INPUT: r_policy is not a known value')
    if cfg.ea_magic <= 0:
        return block('INPUT_UNSET: ea_magic')
    if cfg.r_policy == RPOL_UNSET:
        return block('INPUT_UNSET: r_policy')
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
    if cfg.r_policy != RPOL_R_GEOM:                    # typed diagnostic level: judged now; R_GEOM: judged after the level is derived from the stored basis
        why = _plan_refusal(q.level_2r, cfg, sym, q.direction)
        if why:
            return block(why)
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
    if not o.plan_set:
        return recovery('PLAN_MISSING: the IDLE record carries no authorised plan (an unregistered or old record); it is never filled in from the current inputs', latch=False)
    st = o.state
    if o.plan_rpol != cfg.r_policy:
        return block('PLAN_CHANGED: r_policy differs from the authorised plan (stored %r, now %r); nothing is persisted or sent' % (o.plan_rpol, cfg.r_policy))
    level = q.level_2r
    if cfg.r_policy == RPOL_R_GEOM:
        # the level is DERIVED from the STORED E and S (never from the live SL, never from the quote's level input) and must equal the stored level
        if not cfg.sl_initial_set:
            return block('INPUT_UNSET: initial_sl')
        if cfg.sl_initial != o.plan_s_src:
            return block('PLAN_CHANGED: initial_sl differs from the authorised plan (stored %r, now %r); nothing is persisted or sent' % (o.plan_s_src, cfg.sl_initial))
        geo = _geometry(sym, q.direction, o.plan_e_src, o.plan_s_src, cfg.tp_price)
        if geo.status != tg.OK:
            return block('GEOMETRY_REFUSED: %s: %s' % (geo.status, geo.reason))
        if geo.e_out != o.plan_e_out or geo.s_out != o.plan_s_out:
            return block('PLAN_CHANGED: normalized basis differs from the authorised plan; nothing is persisted or sent')
        level = geo.level_2r                         # compared with the stored level below, with the other plan fields
        why = _plan_refusal(level, cfg, sym, q.direction)
        if why:
            return block(why)
    for field_, stored, now in (('direction', st.direction, q.direction), ('level_2R', st.level, level), ('initial_volume', st.volume_initial, q.volume_initial),
                                ('tp', o.plan_tp, cfg.tp_price), ('volume_min', o.plan_vol_min, sym.vol_min), ('volume_step', o.plan_vol_step, sym.vol_step),
                                ('volume_max', o.plan_vol_max, sym.vol_max)):
        if stored != now:
            return block('PLAN_CHANGED: %s differs from the authorised plan (stored %r, now %r); nothing is persisted or sent' % (field_, stored, now))
    r = act.on_quote(st, identity.position_id, q.direction, level, q.bid, q.ask, q.volume_initial, pos.volume, sym.vol_min, sym.vol_step, sym.vol_max)
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
    ok, why = _save(cfg, rt, store, name, _rec(gen, identity, st, p.SEND_INTENT, o))
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
    ok, why = _save(cfg, rt, store, name, _rec(gen + 1, identity, st, p.SEND_MAPPED, o, True, [sr.order]))
    if not ok:
        return recovery('MAP_NOT_SAVED: %s; order ticket %d must be recorded by hand; the intent (or the map) is what the next load shows' % (why, sr.order))
    res.final, res.reason = SENT_MAPPED, 'sent once; order %d mapped; run the restart flow to reconcile (returned true is not a fill proof)' % sr.order
    return res


def register(cfg, tr, rt, store, name, identity, q):
    """REGISTRATION of the authorised plan (explicit; the executor never creates a file by itself): the bound IDLE record with direction, level 2R, initial volume (in the state) and
    TP, volume min / step / max (the plan block). Never adopts a manual or unproven position; never overwrites; the position's magic must equal the configured one (> 0)."""
    res = Result(BLOCKED)

    def block(reason):
        res.final, res.reason = BLOCKED, reason
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
    if not _int(cfg.r_policy) or cfg.r_policy not in (RPOL_UNSET, RPOL_TYPED, RPOL_R_GEOM):
        return block('INVALID_INPUT: r_policy is not a known value')
    if cfg.ea_magic <= 0:
        return block('INPUT_UNSET: ea_magic')
    if cfg.r_policy == RPOL_UNSET:
        return block('INPUT_UNSET: r_policy')
    if not cfg.tp_set:
        return block('TP_UNKNOWN')
    if rt.latched:
        return block('LATCHED: an earlier uncertainty on this executor; restart and recover first')
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
    if acct.margin_mode != 2:
        return block('UNSUPPORTED_ACCOUNT_MODE: only HEDGING')
    sym = tr.read_symbol(identity.symbol)
    if not sym.read_ok or sym.tick_size <= 0:
        return block('SYMBOL_UNREADABLE')
    if cfg.r_policy != RPOL_R_GEOM:
        why = _plan_refusal(q.level_2r, cfg, sym, q.direction, q.volume_initial)
        if why:
            return block(why)
    pos = tr.find_position(identity.position_id)
    if not pos.found or pos.ticket <= 0 or pos.identifier != identity.position_id:
        return block('POSITION_NOT_FOUND')
    if pos.symbol != identity.symbol or pos.magic != cfg.ea_magic or pos.type != (0 if q.direction == 1 else 1):
        return block('OWNERSHIP_NOT_PROVEN: a manual or foreign position is never adopted (symbol, magic or direction differ)')
    level, basis = q.level_2r, (0.0, 0.0, 0.0, 0.0)
    if cfg.r_policy == RPOL_R_GEOM:
        # E = the open price read ONCE now; S = the initial SL ASSERTED by the owner, accepted only while the live SL still equals it (variant (a)); nothing is read from history
        if not cfg.sl_initial_set:
            return block('INPUT_UNSET: initial_sl')
        if not (_finite(pos.price_open) and pos.price_open > 0):
            return block('ENTRY_UNAVAILABLE: the open price of the position is not readable')
        if not (pos.sl > 0 and abs(pos.sl - cfg.sl_initial) < sym.tick_size / 2):
            return block('INITIAL_SL_NOT_PROVEN: the live SL differs from the asserted initial SL (or is absent); it may have been moved, so the initial SL is unproven')
        if not (_on_grid(pos.price_open, sym.tick_size) and _on_grid(cfg.sl_initial, sym.tick_size)):
            return block('BASE_NOT_ON_SYMBOL_GRID: the open price or the asserted SL is refused, not rounded')
        geo = _geometry(sym, q.direction, pos.price_open, cfg.sl_initial, cfg.tp_price)
        if geo.status != tg.OK:
            return block('GEOMETRY_REFUSED: %s: %s' % (geo.status, geo.reason))
        if abs(geo.e_out - pos.price_open) > p.BASIS_TOL * max(1.0, pos.price_open) or abs(geo.s_out - cfg.sl_initial) > p.BASIS_TOL * max(1.0, cfg.sl_initial):
            return block('BASE_CHANGED_BY_NORMALIZATION: the normalized entry / stop differs from the declared one; nothing is rounded or persisted')
        level, basis = geo.level_2r, (pos.price_open, cfg.sl_initial, geo.e_out, geo.s_out)
        why = _plan_refusal(level, cfg, sym, q.direction, q.volume_initial)
        if why:
            return block(why)
    if pos.volume != q.volume_initial:
        return block('POSITION_VOLUME_DIFFERS_FROM_THE_PLAN: the initial volume must equal the volume of the position')
    sp = es.split(q.volume_initial, sym.vol_min, sym.vol_step, sym.vol_max)
    if sp.status != 'OK':
        return block('REGISTRATION_REFUSED: the 80/20 split is not realisable (%s): %s' % (sp.status, sp.reason))
    if store.exists(name) or store.exists(name + '.tmp'):
        return block('ALREADY_EXISTS: a state file exists; registration never overwrites')
    st = act.State()
    st.bound, st.position_id, st.direction, st.level, st.volume_initial = True, identity.position_id, q.direction, level, q.volume_initial
    rec = p.Record(1, identity, st, p.SEND_NONE, False, [], True, cfg.tp_price, sym.vol_min, sym.vol_step, sym.vol_max, cfg.r_policy, *basis)
    ok, why = _save(cfg, rt, store, name, rec)
    if not ok:
        rt.latched = True
        res.final, res.reason = RECOVERY_REQUIRED, 'REGISTRATION_SAVE_FAILED: %s; the file may or may not exist; nothing else is done' % why
        return res
    chk = store.load(name, identity)
    if not (chk.verdict == p.USABLE_IDLE and chk.generation == 1 and chk.plan_set and chk.plan_tp == cfg.tp_price and chk.state.direction == q.direction and chk.state.level == level
            and chk.plan_rpol == cfg.r_policy and (chk.plan_e_src, chk.plan_s_src, chk.plan_e_out, chk.plan_s_out) == basis
            and chk.state.volume_initial == q.volume_initial and (chk.plan_vol_min, chk.plan_vol_step, chk.plan_vol_max) == (sym.vol_min, sym.vol_step, sym.vol_max)):
        rt.latched = True
        res.final, res.reason = RECOVERY_REQUIRED, 'REGISTRATION_NOT_VERIFIED: the re-load does not show the registered plan'
        return res
    res.final, res.reason = REGISTERED, 'registered: the authorised plan is stored; a request may only be made against exactly this plan'
    return res
