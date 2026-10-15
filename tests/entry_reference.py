"""T013 ENTRY EXECUTOR (Python mirror of src/include/EntryExecutor.mqh): places AT MOST ONE pending LIMIT order per signal from an EXPLICIT plan and an EXPLICIT permit, links the result to
the order it created, reconciles WITHOUT ever sending again, and cancels only an order proven to be the EA's. FAKE transport / FAKE store only in the tests; the real transport is never executed.

It chooses NO signal, direction, FVG, entry, stop, target or policy: the plan is the T007 plan (TP_BuildPlan) and the permit the T007 permit (TP_CheckPermit / TP_Authorize); this module only checks that
the permit belongs to THIS plan (canonical digest), that it is present, allowing and fresh, and then places the order. Every mandatory unresolved input is UNSET = BLOCK.

ORDER OF A PLACEMENT: static validation (no I/O) -> lock -> record check (an existing record of ANY state for the signal blocks) -> terminal reads (a failure = zero sends) -> INTENT saved and read
back -> read-only pre-check -> the ONE send -> classify (PLACED / definite reject / uncertain) -> save the outcome -> link proof (ticket from the response + the whole attribute tuple + the ticket was not
in the pre-send snapshot). An uncertain answer records the attempt and RECOVERY_REQUIRED; nothing is resent. A comment, magic or volume alone never links an order.
RECONCILE never calls Send or Cancel. CANCEL needs the T007 cancel decision for this signal, the stored linked ticket and the order read back as an ACTIVE pending of the EA with the stored attributes; the
intent is saved before the call; an uncertain answer is CANCEL_UNCERTAIN and is resolved by RECONCILE, not by a retry."""
from dataclasses import dataclass, field

import t007_planning_reference as tp
import t011_persist_reference as p

HEADER, VERSION = 'VELO_T013_ENTRY_ORDER', 1
MAX_TEXT, MAX_SNAP = 4096, 32
TIME_TOL = 120                    # seconds: technical tolerance between the intent time and the server time of an order (not a strategy value)
AUTH_PHRASE = 'I_AUTHORISE_REAL_ENTRY_ORDERS_ON_THIS_DEMO_ACCOUNT'

# states stored in the record
ST_INTENT, ST_PRECHECK_REFUSED, ST_REJECTED, ST_PLACED, ST_FILLED = 'INTENT', 'PRECHECK_REFUSED', 'REJECTED', 'PLACED', 'FILLED'
ST_CANCEL_UNCERTAIN, ST_CANCELLED, ST_EXPIRED, ST_RECOVERY, ST_BLOCKED = 'CANCEL_UNCERTAIN', 'CANCELLED', 'EXPIRED', 'RECOVERY_REQUIRED', 'BLOCKED'
STATES = (ST_INTENT, ST_PRECHECK_REFUSED, ST_REJECTED, ST_PLACED, ST_FILLED, ST_CANCEL_UNCERTAIN, ST_CANCELLED, ST_EXPIRED, ST_RECOVERY, ST_BLOCKED)

# results
R_NONE, R_REFUSED, R_LOCK_FAILED, R_DUPLICATE, R_PRECHECK_REFUSED, R_REJECTED = 'NONE', 'REFUSED', 'LOCK_FAILED', 'DUPLICATE', 'PRECHECK_REFUSED', 'REJECTED'
R_PLACED, R_FILLED, R_RECOVERY, R_BLOCKED, R_CANCELLED, R_CANCEL_UNCERTAIN, R_NOCHANGE, R_EXPIRED = 'PLACED', 'FILLED', 'RECOVERY_REQUIRED', 'BLOCKED', 'CANCELLED', 'CANCEL_UNCERTAIN', 'NO_CHANGE', 'EXPIRED'

RC_PLACED, RC_DONE = 10008, 10009
RC_DEFINITE_REJECT = (10006, 10013, 10014, 10015, 10016, 10017, 10018, 10019, 10022, 10026, 10027, 10030)   # the server answered and did not create an order

FILL_UNSET, FILL_RETURN, FILL_IOC, FILL_FOK = 0, 1, 2, 3
EXP_UNSET, EXP_GTC, EXP_SECONDS = 0, 1, 2
OS_ACTIVE, OS_FILLED, OS_CANCELED, OS_EXPIRED, OS_REJECTED, OS_OTHER = 'ACTIVE', 'FILLED', 'CANCELED', 'EXPIRED', 'REJECTED', 'OTHER'
TYPE_BUY_LIMIT, TYPE_SELL_LIMIT, TYPE_OTHER = 0, 1, 2


@dataclass
class Config:
    enabled: bool = False
    ea_magic: int = 0
    symbol: str = ''                    # blank = UNSET = BLOCK
    filling: int = FILL_UNSET
    expiry_mode: int = EXP_UNSET
    expiry_seconds: int = 0
    permit_max_age: int = -1            # seconds; -1 = UNSET = BLOCK
    quote_max_age: int = -1
    real_authorised: bool = False
    authorisation: str = ''


@dataclass
class Permit:
    present: bool = False
    allow: bool = False
    digest: str = ''
    issued: int = 0


@dataclass
class Account:
    read_ok: bool = True
    login: int = 5001234
    server: str = 'MetaQuotes-Demo'
    demo: bool = True
    trade_allowed: bool = True
    margin_mode: int = 2


@dataclass
class Symbol:
    read_ok: bool = True
    vol_min: float = 0.01
    vol_step: float = 0.01
    vol_max: float = 100.0
    tick_size: float = 0.01
    digits: int = 2
    point: float = 0.01
    stops_level: int = 0
    trade_ok: bool = True


@dataclass
class Quote:
    read_ok: bool = True
    bid: float = 2000.0
    ask: float = 2000.3
    time: int = 0


@dataclass
class Order:
    found: bool = True
    ticket: int = 0
    symbol: str = 'XAUUSD'
    type: int = TYPE_BUY_LIMIT
    state: str = OS_ACTIVE
    price: float = 0.0
    sl: float = 0.0
    tp: float = 0.0
    volume: float = 0.0
    magic: int = 0
    comment: str = ''
    time_setup: int = 0
    expiration: int = 0
    position_id: int = 0


@dataclass
class OrderList:
    complete: bool = True
    orders: list = field(default_factory=list)


@dataclass
class Request:
    type: int
    symbol: str
    volume: float
    price: float
    sl: float
    tp: float
    expiry_mode: int
    expiration: int
    filling: int
    magic: int
    comment: str


@dataclass
class SendResult:
    returned_true: bool = False
    have_result: bool = False
    retcode: int = 0
    order: int = 0


@dataclass
class CancelResult:
    returned_true: bool = False
    have_result: bool = False
    retcode: int = 0


@dataclass
class Runtime:
    send_calls: int = 0
    cancel_calls: int = 0
    latched: bool = False


@dataclass
class Result:
    final: str = R_NONE
    reason: str = ''
    sends: int = 0
    state: str = ''
    order_ticket: int = 0
    position_id: int = 0


@dataclass
class Record:
    login: int = 0
    server: str = ''
    symbol: str = ''
    signal_id: str = ''
    setup_id: str = ''
    direction: int = 0
    e: float = 0.0
    s: float = 0.0
    tp: float = 0.0
    volume: float = 0.0
    magic: int = 0
    filling: int = 0
    expiry_mode: int = 0
    expiration: int = 0
    t_intent: int = 0
    req_id: str = ''
    generation: int = 1
    state: str = ST_INTENT
    attempts: int = 0
    cancel_attempts: int = 0
    order_ticket: int = 0
    linked: int = 0
    position_id: int = 0
    snap: list = field(default_factory=list)
    reason: str = ''


# ------------------------------------------------------------------------------------------------ names, digest
def file_name(login, signal_id):
    return 'VELO_T013_ENTRY_%d_%08X.state' % (login, p.crc32(signal_id))


def lock_key(login, signal_id):
    return 'VELO_T013_LOCK_%d_%08X' % (login, p.crc32(signal_id))


def req_id(signal_id):
    return 'VELO_EN_%08X' % p.crc32(signal_id)


def _blank(s):
    return not isinstance(s, str) or s.strip() == ''


def _fin(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and x == x and abs(x) != float('inf')


def plan_digest(plan):
    """canonical text of exactly the fields the order is built from; the permit must carry the digest of the SAME plan"""
    f = [p.fnum(plan.e_out), p.fnum(plan.s_out), p.fnum(plan.tp), p.fnum(plan.volume_out)]
    if any(x is None for x in f) or _blank(plan.signal_id) or _blank(plan.setup_id) or plan.direction not in (1, -1) or isinstance(plan.direction, bool):
        return ''
    return '%s|%s|%d|%s|%s|%s|%s' % (p.esc(plan.signal_id), p.esc(plan.setup_id), plan.direction, f[0], f[1], f[2], f[3])


def permit_from(plan, tpermit, issued):
    """binds a T007 permit to the plan it was issued for; call it right after TP_CheckPermit / TP_Authorize"""
    return Permit(True, tpermit.decision == tp.ALLOW, plan_digest(plan), issued)


def _close(a, b):
    return abs(a - b) <= 1e-9 * max(1.0, abs(a), abs(b))


def _on_grid(x, tick):
    return abs(x - round(x / tick) * tick) <= 1e-9 * max(1.0, abs(x))


# ------------------------------------------------------------------------------------------------ record codec
KEYS = ['VERSION', 'LOGIN', 'SERVER', 'SYMBOL', 'SIGNAL_ID', 'SETUP_ID', 'DIRECTION', 'E', 'S', 'TP', 'VOLUME', 'MAGIC', 'FILLING', 'EXPIRY_MODE', 'EXPIRATION', 'T_INTENT',
        'REQ_ID', 'GENERATION', 'STATE', 'ATTEMPTS', 'CANCEL_ATTEMPTS', 'ORDER_TICKET', 'LINKED', 'POSITION_ID', 'N_SNAP', 'SNAP', 'REASON']


def validate(r):
    if r.login <= 0 or _blank(r.server) or _blank(r.symbol):
        return 'INVALID_IDENTITY'
    if _blank(r.signal_id) or _blank(r.setup_id) or r.direction not in (1, -1):
        return 'INVALID_SIGNAL'
    for x in (r.e, r.s, r.tp, r.volume):
        if p.fnum(x) is None or not x > 0.0:
            return 'INVALID_PRICE_OR_VOLUME'
    if r.direction == 1 and not (r.s < r.e < r.tp):
        return 'INVALID_GEOMETRY'
    if r.direction == -1 and not (r.tp < r.e < r.s):
        return 'INVALID_GEOMETRY'
    if r.magic <= 0 or r.filling != FILL_RETURN or r.expiry_mode not in (EXP_GTC, EXP_SECONDS):
        return 'INVALID_CONFIG'
    if (r.expiry_mode == EXP_GTC and r.expiration != 0) or (r.expiry_mode == EXP_SECONDS and r.expiration <= r.t_intent):
        return 'INVALID_EXPIRATION'
    if r.t_intent <= 0 or r.req_id != req_id(r.signal_id):
        return 'INVALID_INTENT'
    if r.generation < 1 or r.state not in STATES or r.attempts not in (0, 1) or r.cancel_attempts not in (0, 1):
        return 'INVALID_STATE'
    if r.order_ticket < 0 or r.position_id < 0 or r.linked not in (0, 1) or (r.linked == 1 and r.order_ticket == 0) or (r.position_id > 0 and r.state != ST_FILLED):
        return 'INVALID_LINK'
    if r.state == ST_INTENT and (r.attempts != 0 or r.order_ticket != 0 or r.linked):
        return 'INVALID_INTENT_STATE'
    if r.state in (ST_PLACED, ST_CANCEL_UNCERTAIN, ST_FILLED) and (r.attempts != 1 or r.linked != 1):
        return 'INVALID_PLACED_STATE'
    if r.state == ST_FILLED and r.position_id <= 0:
        return 'INVALID_FILLED_STATE'
    if r.state == ST_REJECTED and (r.attempts != 1 or r.order_ticket != 0 or r.linked):
        return 'INVALID_REJECTED_STATE'
    if r.state == ST_PRECHECK_REFUSED and (r.attempts != 0 or r.order_ticket != 0):
        return 'INVALID_PRECHECK_STATE'
    if len(r.snap) > MAX_SNAP or any(not isinstance(t, int) or isinstance(t, bool) or t <= 0 for t in r.snap) or len(set(r.snap)) != len(r.snap):
        return 'INVALID_SNAPSHOT'
    if r.order_ticket in r.snap and r.order_ticket != 0:
        return 'INVALID_SNAPSHOT_TICKET'
    return ''


def encode(r):
    bad = validate(r)
    if bad:
        return False, bad
    lines = [HEADER, 'VERSION=%d' % VERSION, 'LOGIN=%d' % r.login, 'SERVER=' + p.esc(r.server), 'SYMBOL=' + p.esc(r.symbol), 'SIGNAL_ID=' + p.esc(r.signal_id),
             'SETUP_ID=' + p.esc(r.setup_id), 'DIRECTION=%d' % r.direction, 'E=' + p.fnum(r.e), 'S=' + p.fnum(r.s), 'TP=' + p.fnum(r.tp), 'VOLUME=' + p.fnum(r.volume),
             'MAGIC=%d' % r.magic, 'FILLING=%d' % r.filling, 'EXPIRY_MODE=%d' % r.expiry_mode, 'EXPIRATION=%d' % r.expiration, 'T_INTENT=%d' % r.t_intent, 'REQ_ID=' + r.req_id,
             'GENERATION=%d' % r.generation, 'STATE=' + r.state, 'ATTEMPTS=%d' % r.attempts, 'CANCEL_ATTEMPTS=%d' % r.cancel_attempts, 'ORDER_TICKET=%d' % r.order_ticket,
             'LINKED=%d' % r.linked, 'POSITION_ID=%d' % r.position_id, 'N_SNAP=%d' % len(r.snap), 'SNAP=' + ','.join(str(t) for t in r.snap), 'REASON=' + p.esc(r.reason[:120]), 'END']
    body = '\n'.join(lines) + '\n'
    text = body + 'CRC=%08X\n' % p.crc32(body)
    return (True, text) if len(text) <= MAX_TEXT else (False, 'TOO_LARGE')


def decode(text):
    import re
    if not isinstance(text, str) or text == '':
        return False, 'EMPTY'
    if len(text) > MAX_TEXT:
        return False, 'TOO_LARGE'
    if not text.endswith('\n'):
        return False, 'TRUNCATED: no final newline'
    if text.count('CRC=') != 1:
        return False, 'TRUNCATED: no single END / CRC trailer'
    k = text.rfind('END\nCRC=')
    if k < 0:
        return False, 'TRUNCATED: no trailer'
    body, trailer = text[:k + 4], text[k + 4:]
    if not re.fullmatch(r'CRC=[0-9A-F]{8}\n', trailer):
        return False, 'BAD_TRAILER'
    if int(trailer[4:12], 16) != p.crc32(body):
        return False, 'CRC_MISMATCH: the record is damaged (the CRC does not protect against a deliberate edit)'
    lines = body.split('\n')[:-1]
    if not lines or lines[0] != HEADER:
        return False, 'BAD_HEADER'
    if len(lines) != 1 + len(KEYS) + 1 or lines[-1] != 'END':
        return False, 'BAD_LENGTH'
    v = {}
    for i, key in enumerate(KEYS):
        line = lines[1 + i]
        if not line.startswith(key + '='):
            return False, 'BAD_FIELD_ORDER: expected ' + key
        v[key] = line[len(key) + 1:]
    if p._geti(v['VERSION']) != VERSION:
        return False, 'UNSUPPORTED_VERSION: %s' % v['VERSION'][:20]
    ints = {k2: p._geti(v[k2]) for k2 in ('LOGIN', 'DIRECTION', 'MAGIC', 'FILLING', 'EXPIRY_MODE', 'EXPIRATION', 'T_INTENT', 'GENERATION', 'ATTEMPTS', 'CANCEL_ATTEMPTS',
                                          'ORDER_TICKET', 'LINKED', 'POSITION_ID', 'N_SNAP')}
    dbl = {k2: p._getd(v[k2]) for k2 in ('E', 'S', 'TP', 'VOLUME')}
    strs = {k2: p.unesc(v[k2]) for k2 in ('SERVER', 'SYMBOL', 'SIGNAL_ID', 'SETUP_ID', 'REASON')}
    if any(x is None for x in ints.values()) or any(x is None for x in dbl.values()) or any(x is None for x in strs.values()):
        return False, 'BAD_NUMBER_OR_STRING'
    if v['STATE'] not in STATES:
        return False, 'BAD_ENUM: STATE'
    snap = []
    if v['SNAP'] != '':
        for t in v['SNAP'].split(','):
            x = p._geti(t)
            if x is None:
                return False, 'BAD_NUMBER_OR_STRING: SNAP'
            snap.append(x)
    if ints['N_SNAP'] != len(snap):
        return False, 'BAD_SNAPSHOT_COUNT'
    rec = Record(ints['LOGIN'], strs['SERVER'], strs['SYMBOL'], strs['SIGNAL_ID'], strs['SETUP_ID'], ints['DIRECTION'], dbl['E'], dbl['S'], dbl['TP'], dbl['VOLUME'], ints['MAGIC'],
                 ints['FILLING'], ints['EXPIRY_MODE'], ints['EXPIRATION'], ints['T_INTENT'], v['REQ_ID'], ints['GENERATION'], v['STATE'], ints['ATTEMPTS'], ints['CANCEL_ATTEMPTS'],
                 ints['ORDER_TICKET'], ints['LINKED'], ints['POSITION_ID'], snap, strs['REASON'])
    bad = validate(rec)
    return (False, bad) if bad else (True, rec)


# ------------------------------------------------------------------------------------------------ helpers
def _otype(direction):
    return TYPE_BUY_LIMIT if direction == 1 else TYPE_SELL_LIMIT


def tuple_matches(o, rec):
    """the whole attribute tuple of the order the record describes (never the comment, magic or volume alone)"""
    return (o.found and o.symbol == rec.symbol and o.type == _otype(rec.direction) and _close(o.price, rec.e) and _close(o.sl, rec.s) and _close(o.tp, rec.tp)
            and _close(o.volume, rec.volume) and o.magic == rec.magic and (rec.expiry_mode == EXP_GTC or o.expiration == rec.expiration))


def _res(final, reason, sends=0, state='', ticket=0, pos=0):
    return Result(final, reason, sends, state, ticket, pos)


def core_unset(cfg):
    """enabled + the identity inputs every action needs (place, reconcile, cancel)"""
    if not cfg.enabled:
        return 'DISABLED: the entry executor is off by default'
    if cfg.ea_magic <= 0:
        return 'INPUT_UNSET: ea_magic'
    if _blank(cfg.symbol):
        return 'INPUT_UNSET: symbol'
    return ''


def config_unset(cfg):
    """the first mandatory input that is still UNSET, or ''"""
    bad = core_unset(cfg)
    if bad:
        return bad
    if cfg.filling not in (FILL_RETURN, FILL_IOC, FILL_FOK):
        return 'INPUT_UNSET: filling'
    if cfg.filling != FILL_RETURN:
        return 'FILLING_NOT_ALLOWED_FOR_PENDING: the documented rule for pending orders is ORDER_FILLING_RETURN'
    if cfg.expiry_mode not in (EXP_GTC, EXP_SECONDS):
        return 'INPUT_UNSET: expiry_mode'
    if cfg.expiry_mode == EXP_SECONDS and not 0 < cfg.expiry_seconds <= 31536000:
        return 'INPUT_UNSET: expiry_seconds'
    if cfg.permit_max_age <= 0:
        return 'INPUT_UNSET: permit_max_age'
    if cfg.quote_max_age <= 0:
        return 'INPUT_UNSET: quote_max_age'
    return ''


def plan_refusal(plan):
    if plan.status != tp.OK or plan.stage != tp.STAGE_COMPLETE:
        return 'PLAN_NOT_OK: only a COMPLETE OK plan can be placed'
    if plan_digest(plan) == '':
        return 'PLAN_INVALID: ids, direction or numbers are not usable'
    for x in (plan.e_out, plan.s_out, plan.tp, plan.volume_out):
        if not x > 0.0:
            return 'PLAN_INVALID: a price or the volume is not positive'
    if plan.direction == 1 and not (plan.s_out < plan.e_out < plan.tp):
        return 'PLAN_INVALID: BUY needs SL < entry < TP'
    if plan.direction == -1 and not (plan.tp < plan.e_out < plan.s_out):
        return 'PLAN_INVALID: SELL needs TP < entry < SL'
    return ''


def permit_refusal(cfg, plan, permit, now):
    if not permit.present:
        return 'PERMIT_MISSING'
    if not permit.allow:
        return 'PERMIT_NOT_ALLOWED'
    if permit.digest == '' or permit.digest != plan_digest(plan):
        return 'PERMIT_FOR_ANOTHER_PLAN: the permit digest differs from this plan'
    if permit.issued <= 0 or permit.issued > now:
        return 'PERMIT_TIME_INVALID: issued in the future or unset'
    if now - permit.issued > cfg.permit_max_age:
        return 'PERMIT_STALE: older than the configured maximum age'
    return ''


def market_refusal(cfg, plan, sym, quote, now):
    if not sym.read_ok or sym.tick_size <= 0 or sym.vol_step <= 0 or sym.point <= 0 or not sym.trade_ok:
        return 'SYMBOL_UNREADABLE_OR_NOT_TRADABLE'
    if not quote.read_ok or not (quote.bid > 0 and quote.ask >= quote.bid) or quote.time <= 0 or quote.time > now + TIME_TOL or now - quote.time > cfg.quote_max_age:
        return 'QUOTE_UNUSABLE_OR_STALE'
    for x in (plan.e_out, plan.s_out, plan.tp):
        if not _on_grid(x, sym.tick_size):
            return 'PRICE_NOT_ON_TICK_GRID: refused, never rounded'
    steps = plan.volume_out / sym.vol_step
    if not (sym.vol_min <= plan.volume_out <= sym.vol_max) or abs(steps - round(steps)) > 1e-6:
        return 'VOLUME_OUTSIDE_SYMBOL_RULES: refused, never adjusted'
    gap = sym.stops_level * sym.point
    if plan.direction == 1 and not plan.e_out <= quote.ask - gap:
        return 'LIMIT_ON_THE_WRONG_SIDE: a BUY_LIMIT must lie below the ask by at least the stops level'
    if plan.direction == -1 and not plan.e_out >= quote.bid + gap:
        return 'LIMIT_ON_THE_WRONG_SIDE: a SELL_LIMIT must lie above the bid by at least the stops level'
    return ''


def _identity_ok(rec, acct, cfg, signal_id):
    return rec.login == acct.login and rec.server == acct.server and rec.signal_id == signal_id and rec.magic == cfg.ea_magic


def _save(store, rec, **chg):
    new = Record(**{**rec.__dict__, **chg})
    new.snap = list(rec.snap)
    new.generation = rec.generation + 1
    ok, text = encode(new)
    if not ok:
        return False, rec
    if not store.write(file_name(rec.login, rec.signal_id), text):
        return False, rec
    ok2, back = store.read(file_name(rec.login, rec.signal_id))
    if not ok2 or back != text:
        return False, rec
    return True, new


def _load(store, name):
    """-> ('NONE'|'OK'|'BAD', Record|reason)"""
    if not store.exists(name):
        return 'NONE', None
    ok, text = store.read(name)
    if not ok:
        return 'BAD', 'FILE_UNREADABLE'
    ok, rec = decode(text)
    return ('OK', rec) if ok else ('BAD', rec)


def _real_gate(cfg, tr, acct):
    if tr.is_real():
        if not (cfg.real_authorised and cfg.authorisation == AUTH_PHRASE):
            return 'REAL_NOT_AUTHORISED'
        if not acct.read_ok or not acct.demo:
            return 'REAL_REQUIRES_DEMO_ACCOUNT'
    return ''


# ------------------------------------------------------------------------------------------------ PLACE
def place(cfg, tr, store, rt, plan, permit):
    bad = config_unset(cfg)
    if bad:
        return _res(R_REFUSED, bad)
    if rt.latched:
        return _res(R_REFUSED, 'LATCHED: an earlier uncertainty on this executor; restart and reconcile first')
    if rt.send_calls >= 1:
        return _res(R_REFUSED, 'DUPLICATE_CALL: a send was already made by this executor instance')
    bad = plan_refusal(plan)
    if bad:
        return _res(R_REFUSED, bad)
    now = tr.server_time()
    if not now > 0:
        return _res(R_REFUSED, 'SERVER_TIME_UNREADABLE')
    bad = permit_refusal(cfg, plan, permit, now)
    if bad:
        return _res(R_REFUSED, bad)
    acct = tr.read_account()
    bad = _real_gate(cfg, tr, acct)
    if bad:
        return _res(R_REFUSED, bad)
    if not acct.read_ok or acct.login <= 0 or _blank(acct.server):
        return _res(R_REFUSED, 'ACCOUNT_UNREADABLE')
    if not acct.trade_allowed:
        return _res(R_REFUSED, 'TRADING_NOT_ALLOWED')
    if acct.margin_mode != 2:
        return _res(R_REFUSED, 'UNSUPPORTED_ACCOUNT_MODE: only HEDGING')
    name, key = file_name(acct.login, plan.signal_id), lock_key(acct.login, plan.signal_id)
    if not store.lock(key):
        return _res(R_LOCK_FAILED, 'INSTANCE_LOCK_HELD_OR_UNAVAILABLE: zero sends')
    try:
        kind, rec = _load(store, name)
        if kind != 'NONE':
            if kind == 'BAD':
                return _res(R_BLOCKED, 'EXISTING_RECORD_UNUSABLE: ' + rec)
            return _res(R_DUPLICATE, 'RECORD_EXISTS: state %s; one order per signal, nothing is sent' % rec.state, 0, rec.state, rec.order_ticket, rec.position_id)
        sym = tr.read_symbol(cfg.symbol)
        quote = tr.read_quote(cfg.symbol)
        bad = market_refusal(cfg, plan, sym, quote, now)
        if bad:
            return _res(R_REFUSED, bad)
        lst = tr.list_orders(cfg.symbol, now - 86400)
        if not lst.complete:
            return _res(R_REFUSED, 'ORDER_LIST_INCOMPLETE: the existing orders cannot be proven')
        if len(lst.orders) > MAX_SNAP:
            return _res(R_REFUSED, 'SNAPSHOT_TOO_LARGE')
        exp = 0 if cfg.expiry_mode == EXP_GTC else now + cfg.expiry_seconds
        new = Record(acct.login, acct.server, cfg.symbol, plan.signal_id, plan.setup_id, plan.direction, plan.e_out, plan.s_out, plan.tp, plan.volume_out, cfg.ea_magic,
                     cfg.filling, cfg.expiry_mode, exp, now, req_id(plan.signal_id), 1, ST_INTENT, 0, 0, 0, 0, 0, [o.ticket for o in lst.orders], '')
        for o in lst.orders:
            if o.state == OS_ACTIVE and tuple_matches(o, new):
                return _res(R_REFUSED, 'IDENTICAL_ORDER_ALREADY_PENDING: refused, nothing is sent')
        ok, text = encode(new)
        if not ok:
            return _res(R_REFUSED, 'INTENT_NOT_ENCODABLE: ' + text)
        if not store.write(name, text):
            return _res(R_BLOCKED, 'INTENT_NOT_SAVED: zero sends')
        ok, back = store.read(name)
        if not ok or back != text:
            return _res(R_BLOCKED, 'INTENT_READBACK_DIFFERS: zero sends', 0, ST_INTENT)
        req = Request(_otype(plan.direction), new.symbol, new.volume, new.e, new.s, new.tp, cfg.expiry_mode, exp, cfg.filling, cfg.ea_magic, new.req_id)
        if not tr.pre_check(req):
            ok, rec2 = _save(store, new, state=ST_PRECHECK_REFUSED, reason='PRECHECK_REFUSED')
            return _res(R_PRECHECK_REFUSED, 'PRECHECK_REFUSED: zero sends' + ('' if ok else '; the state could not be saved (record stays INTENT)'), 0, rec2.state)
        now2 = tr.server_time()                              # time passed during the pre-check: permit, expiry and quote are judged AGAIN right before the send
        bad = '' if now2 > 0 else 'SERVER_TIME_UNREADABLE'
        if not bad:
            bad = permit_refusal(cfg, plan, permit, now2)
        if not bad and cfg.expiry_mode == EXP_SECONDS and exp <= now2:
            bad = 'EXPIRATION_ALREADY_PASSED'
        if not bad:
            bad = market_refusal(cfg, plan, sym, tr.read_quote(cfg.symbol), now2)
        if bad:
            ok, rec2 = _save(store, new, state=ST_PRECHECK_REFUSED, reason='ABORTED_BEFORE_SEND')
            return _res(R_REFUSED, 'ABORTED_BEFORE_SEND: ' + bad + '; zero sends' + ('' if ok else '; the state could not be saved (record stays INTENT)'), 0, rec2.state)
        rt.send_calls += 1
        sr = tr.send(req)
        if sr.have_result and sr.retcode in RC_DEFINITE_REJECT and sr.order == 0:
            ok, rec2 = _save(store, new, state=ST_REJECTED, attempts=1, reason='REJECTED retcode %d' % sr.retcode)
            if not ok:
                rt.latched = True
                return _res(R_RECOVERY, 'REJECTED_NOT_SAVED: the attempt is on disk as INTENT; reconcile', 1, ST_INTENT)
            return _res(R_REJECTED, 'REJECTED: retcode %d, no order was created' % sr.retcode, 1, ST_REJECTED)
        if not (sr.have_result and sr.retcode in (RC_PLACED, RC_DONE) and sr.order > 0):
            rt.latched = True
            ok, rec2 = _save(store, new, state=ST_RECOVERY, attempts=1, reason='UNCERTAIN_ANSWER retcode %d' % sr.retcode)
            return _res(R_RECOVERY, 'UNCERTAIN_ANSWER: one attempt recorded, nothing is resent' + ('' if ok else '; not saved (record stays INTENT)'), 1, rec2.state)
        o = tr.read_order(sr.order)
        if o.found and o.ticket == sr.order and sr.order not in new.snap and tuple_matches(o, new) and o.state in (OS_ACTIVE, OS_FILLED) and (o.state == OS_ACTIVE or o.position_id > 0):
            st, pos = (ST_PLACED, 0) if o.state == OS_ACTIVE else (ST_FILLED, o.position_id)
            ok, rec2 = _save(store, new, state=st, attempts=1, order_ticket=sr.order, linked=1, position_id=pos)
            if not ok:
                rt.latched = True
                return _res(R_RECOVERY, 'OUTCOME_NOT_SAVED: the attempt is on disk as INTENT; reconcile', 1, ST_INTENT, sr.order)
            return _res(R_PLACED if st == ST_PLACED else R_FILLED, 'LINKED: ticket from the response + the whole attribute tuple + not in the pre-send snapshot', 1, st, sr.order, pos)
        rt.latched = True
        ok, rec2 = _save(store, new, state=ST_RECOVERY, attempts=1, order_ticket=0, linked=0, reason='LINK_UNPROVEN ticket %d' % sr.order)
        return _res(R_RECOVERY, 'LINK_UNPROVEN: the order of the response is not proven to be this one; nothing is resent' + ('' if ok else '; not saved'), 1, rec2.state, sr.order)
    finally:
        store.unlock(key)


# ------------------------------------------------------------------------------------------------ RECONCILE (never sends, never cancels)
def _disk_state(store, rec):
    """what the disk really holds now (a false write does not prove the old record is still there)"""
    kind, r = _load(store, file_name(rec.login, rec.signal_id))
    return r.state if kind == 'OK' else ('NONE' if kind == 'NONE' else 'UNUSABLE')


def _transition(store, rec, final, msg, ticket=0, pos=0, **chg):
    """saves the new state; the result claims it only when the save was verified, otherwise RECOVERY_REQUIRED with the state the disk really holds"""
    ok, r2 = _save(store, rec, **chg)
    if ok:
        return _res(final, msg, 0, r2.state, ticket, pos)
    disk = _disk_state(store, rec)
    return _res(R_RECOVERY, 'STATE_NOT_SAVED: %s (%s); the disk holds %s; nothing is resent' % (chg.get('state', ''), msg, disk), 0, disk, ticket)


def reconcile(cfg, tr, store, signal_id):
    bad = core_unset(cfg)
    if bad:
        return _res(R_REFUSED, bad)
    acct = tr.read_account()
    if not acct.read_ok or acct.login <= 0 or _blank(acct.server):
        return _res(R_REFUSED, 'ACCOUNT_UNREADABLE')
    if _blank(signal_id):
        return _res(R_REFUSED, 'SIGNAL_ID_EMPTY')
    name, key = file_name(acct.login, signal_id), lock_key(acct.login, signal_id)
    if not store.lock(key):
        return _res(R_LOCK_FAILED, 'INSTANCE_LOCK_HELD_OR_UNAVAILABLE')
    try:
        kind, rec = _load(store, name)
        if kind == 'NONE':
            return _res(R_NONE, 'NO_RECORD')
        if kind == 'BAD':
            return _res(R_BLOCKED, 'RECORD_UNUSABLE: ' + rec)
        if not _identity_ok(rec, acct, cfg, signal_id):
            return _res(R_BLOCKED, 'IDENTITY_MISMATCH: the record belongs to another account, signal or magic')
        if rec.state in (ST_PRECHECK_REFUSED, ST_REJECTED, ST_CANCELLED, ST_EXPIRED, ST_BLOCKED, ST_FILLED):
            return _res(R_NOCHANGE, 'TERMINAL_STATE %s' % rec.state, 0, rec.state, rec.order_ticket, rec.position_id)
        if rec.state in (ST_INTENT, ST_RECOVERY) and rec.linked == 0:
            return _scan_for_order(cfg, tr, store, rec)
        # PLACED / CANCEL_UNCERTAIN / RECOVERY with a linked ticket
        o = tr.read_order(rec.order_ticket)
        tk = rec.order_ticket
        if not o.found:
            if rec.state == ST_RECOVERY:
                return _res(R_RECOVERY, 'ORDER_NOT_FOUND: cannot prove what happened to the order', 0, rec.state, tk)
            return _transition(store, rec, R_RECOVERY, 'ORDER_NOT_FOUND: cannot prove what happened to the order', tk, state=ST_RECOVERY, reason='ORDER_NOT_FOUND')
        if o.ticket != rec.order_ticket or not (o.symbol == rec.symbol and o.type == _otype(rec.direction) and o.magic == rec.magic):
            return _transition(store, rec, R_BLOCKED, 'ORDER_IDENTITY_CHANGED', tk, state=ST_BLOCKED, reason='ORDER_IDENTITY_CHANGED')
        if o.state == OS_ACTIVE:
            if not tuple_matches(o, rec):
                return _transition(store, rec, R_BLOCKED, 'ORDER_MODIFIED: the pending order no longer matches the plan; it is not touched', tk, state=ST_BLOCKED, reason='ORDER_MODIFIED')
            if rec.state == ST_CANCEL_UNCERTAIN:
                return _transition(store, rec, R_PLACED, 'STILL_ACTIVE: the cancellation did not take effect', tk, state=ST_PLACED, reason='CANCEL_NOT_EFFECTIVE')
            if rec.state == ST_RECOVERY:
                return _transition(store, rec, R_PLACED, 'RECOVERED_ACTIVE', tk, state=ST_PLACED, reason='RECOVERED_ACTIVE')
            return _res(R_NOCHANGE, 'ACTIVE', 0, rec.state, tk)
        if o.state == OS_FILLED:
            if o.position_id <= 0 or not tuple_matches(o, rec):
                return _transition(store, rec, R_RECOVERY, 'FILLED_WITHOUT_PROOF', tk, state=ST_RECOVERY, reason='FILLED_WITHOUT_PROOF')
            return _transition(store, rec, R_FILLED, 'FILLED: position id from the order history', tk, o.position_id, state=ST_FILLED, position_id=o.position_id, reason='FILLED')
        if o.state in (OS_CANCELED, OS_REJECTED):
            return _transition(store, rec, R_CANCELLED, 'ORDER_' + o.state, tk, state=ST_CANCELLED, reason='ORDER_' + o.state)
        if o.state == OS_EXPIRED:
            return _transition(store, rec, R_EXPIRED, 'ORDER_EXPIRED', tk, state=ST_EXPIRED, reason='ORDER_EXPIRED')
        return _transition(store, rec, R_RECOVERY, 'ORDER_STATE_UNKNOWN', tk, state=ST_RECOVERY, reason='ORDER_STATE_UNKNOWN')
    finally:
        store.unlock(key)


def _scan_for_order(cfg, tr, store, rec):
    """INTENT / RECOVERY without a proven ticket: the attempt may or may not have created an order. NEVER resends. Exactly one order with the whole tuple that was not in the pre-send snapshot and is
    not older than the intent is linked; none keeps RECOVERY_REQUIRED; more than one is BLOCKED (ambiguous)."""
    lst = tr.list_orders(rec.symbol, rec.t_intent - TIME_TOL)
    if not lst.complete:
        return _res(R_RECOVERY, 'ORDER_LIST_INCOMPLETE: nothing can be concluded', 0, rec.state)
    cands = [o for o in lst.orders if o.ticket not in rec.snap and o.time_setup >= rec.t_intent - TIME_TOL and tuple_matches(o, rec)]
    if len(cands) > 1:
        return _transition(store, rec, R_BLOCKED, 'AMBIGUOUS_CANDIDATES: more than one order fits; none is chosen', 0, state=ST_BLOCKED, reason='AMBIGUOUS_CANDIDATES %d' % len(cands))
    if not cands:
        if rec.state == ST_INTENT:
            return _transition(store, rec, R_RECOVERY, 'INTENT_WITHOUT_PROOF: the send may or may not have happened; nothing is resent', 0, state=ST_RECOVERY, attempts=1, reason='INTENT_WITHOUT_ORDER')
        return _res(R_RECOVERY, 'NO_CANDIDATE: nothing is resent', 0, rec.state)
    o = cands[0]
    if o.state == OS_ACTIVE:
        return _transition(store, rec, R_PLACED, 'LINKED_BY_RECOVERY: unique tuple match outside the snapshot', o.ticket, state=ST_PLACED, attempts=1, order_ticket=o.ticket, linked=1, reason='LINKED_BY_RECOVERY')
    if o.state == OS_FILLED and o.position_id > 0:
        return _transition(store, rec, R_FILLED, 'LINKED_BY_RECOVERY_FILLED', o.ticket, o.position_id, state=ST_FILLED, attempts=1, order_ticket=o.ticket, linked=1, position_id=o.position_id,
                           reason='LINKED_BY_RECOVERY_FILLED')
    if o.state in (OS_CANCELED, OS_REJECTED):
        return _transition(store, rec, R_CANCELLED, 'LINKED_BY_RECOVERY_ENDED', o.ticket, state=ST_CANCELLED, attempts=1, order_ticket=o.ticket, linked=1, reason='LINKED_BY_RECOVERY_ENDED')
    if o.state == OS_EXPIRED:
        return _transition(store, rec, R_EXPIRED, 'LINKED_BY_RECOVERY_EXPIRED', o.ticket, state=ST_EXPIRED, attempts=1, order_ticket=o.ticket, linked=1, reason='LINKED_BY_RECOVERY_EXPIRED')
    return _res(R_RECOVERY, 'CANDIDATE_STATE_UNUSABLE', 0, rec.state)


# ------------------------------------------------------------------------------------------------ CANCEL
def cancel(cfg, tr, store, rt, signal_id, decision):
    bad = core_unset(cfg)
    if bad:
        return _res(R_REFUSED, bad)
    if rt.cancel_calls >= 1:
        return _res(R_REFUSED, 'DUPLICATE_CALL: a cancellation was already made by this executor instance')
    if _blank(signal_id):
        return _res(R_REFUSED, 'SIGNAL_ID_EMPTY')
    if decision.status != tp.CANCEL_REQUEST or not decision.cancel_pending or decision.pending_signal_id != signal_id:
        return _res(R_REFUSED, 'CANCEL_DECISION_NOT_FOR_THIS_SIGNAL')
    acct = tr.read_account()
    bad = _real_gate(cfg, tr, acct)
    if bad:
        return _res(R_REFUSED, bad)
    if not acct.read_ok or acct.login <= 0 or _blank(acct.server):
        return _res(R_REFUSED, 'ACCOUNT_UNREADABLE')
    name, key = file_name(acct.login, signal_id), lock_key(acct.login, signal_id)
    if not store.lock(key):
        return _res(R_LOCK_FAILED, 'INSTANCE_LOCK_HELD_OR_UNAVAILABLE: zero cancellations')
    try:
        kind, rec = _load(store, name)
        if kind == 'NONE':
            return _res(R_REFUSED, 'NO_RECORD: there is no order of this EA for the signal')
        if kind == 'BAD':
            return _res(R_BLOCKED, 'RECORD_UNUSABLE: ' + rec)
        if not _identity_ok(rec, acct, cfg, signal_id):
            return _res(R_BLOCKED, 'IDENTITY_MISMATCH')
        if rec.state != ST_PLACED or rec.linked != 1:
            return _res(R_REFUSED, 'NOT_A_PROVEN_PENDING_ORDER: state %s; reconcile first' % rec.state, 0, rec.state, rec.order_ticket)
        if rec.cancel_attempts >= 1:
            return _res(R_REFUSED, 'CANCEL_ALREADY_ATTEMPTED: the record stores one cancellation; there is no automatic second one', 0, rec.state, rec.order_ticket)
        o = tr.read_order(rec.order_ticket)
        if not (o.found and o.ticket == rec.order_ticket and o.state == OS_ACTIVE and tuple_matches(o, rec) and o.magic == cfg.ea_magic):
            return _res(R_REFUSED, 'ORDER_NOT_PROVEN_AS_THE_EAS_ACTIVE_PENDING: nothing is cancelled', 0, rec.state, rec.order_ticket)
        ok, r2 = _save(store, rec, state=ST_CANCEL_UNCERTAIN, cancel_attempts=1, reason='CANCEL_INTENT')
        if not ok:
            return _res(R_BLOCKED, 'CANCEL_INTENT_NOT_SAVED: nothing is cancelled', 0, rec.state, rec.order_ticket)
        rt.cancel_calls += 1
        cr = tr.cancel(rec.order_ticket)
        if cr.have_result and cr.retcode == RC_DONE:
            o2 = tr.read_order(rec.order_ticket)
            if o2.found and o2.ticket == rec.order_ticket and o2.state == OS_CANCELED:
                ok, r3 = _save(store, r2, state=ST_CANCELLED, reason='CANCELLED_BY_EA')
                if not ok:
                    return _res(R_CANCEL_UNCERTAIN, 'CANCELLED_NOT_SAVED: reconcile', 0, ST_CANCEL_UNCERTAIN, rec.order_ticket)
                return _res(R_CANCELLED, 'CANCELLED: confirmed by the order read back', 0, r3.state, rec.order_ticket)
        return _res(R_CANCEL_UNCERTAIN, 'CANCEL_UNCERTAIN: no retry; reconcile reads the order', 0, ST_CANCEL_UNCERTAIN, rec.order_ticket)
    finally:
        store.unlock(key)


# ------------------------------------------------------------------------------------------------ FAKES (tests only)
class FakeStore:
    def __init__(self):
        self.files = {}
        self.held = set()
        self.lock_calls = 0
        self.unlock_calls = 0
        self.writes = 0
        self.fail_write = set()          # 1-based indexes of write calls that fail
        self.readback_differs = set()    # 1-based indexes of write calls whose read-back differs
        self.deny_lock = False
        self.unreadable = set()

    def lock(self, key):
        self.lock_calls += 1
        if self.deny_lock or key in self.held:
            return False
        self.held.add(key)
        return True

    def unlock(self, key):
        self.unlock_calls += 1
        self.held.discard(key)

    def exists(self, name):
        return name in self.files

    def read(self, name):
        if name in self.unreadable:
            return False, ''
        return True, self.files[name]

    def write(self, name, text):
        self.writes += 1
        if self.writes in self.fail_write:
            return False
        self.files[name] = text + ('X' if self.writes in self.readback_differs else '')
        return True


class FakeTransport:
    def __init__(self):
        self.real = False
        self.now = 1_000_000
        self.symbol_name = 'XAUUSD'
        self.account = Account()
        self.symbol = Symbol()
        self.quote = Quote(time=self.now)
        self.orders = []
        self.list_complete = True
        self.precheck_ok = True
        self.send_mode = 'placed'        # placed | rejected | uncertain_created | uncertain_not_created | placed_unreadable | placed_modified | placed_other_ticket | partial_codes
        self.cancel_mode = 'ok'          # ok | lost | fails | not_effective
        self.sends = 0
        self.cancels = 0
        self.requests = []
        self.next_ticket = 9000
        self.hide = set()
        self.reads = 0
        self.precheck_advance = 0        # seconds the fake clock moves during the pre-check (time passes between the checks and the send)
        self.precheck_quote = None       # (bid, ask) the quote becomes during the pre-check

    def is_real(self):
        return self.real

    def server_time(self):
        return self.now

    def read_account(self):
        return self.account

    def read_symbol(self, name):
        return self.symbol

    def read_quote(self, name):
        return self.quote

    def list_orders(self, name, since):
        return OrderList(self.list_complete, [o for o in self.orders if o.symbol == name and o.ticket not in self.hide])

    def read_order(self, ticket):
        self.reads += 1
        for o in self.orders:
            if o.ticket == ticket and ticket not in self.hide:
                return o
        return Order(found=False, ticket=ticket)

    def pre_check(self, req):
        self.now += self.precheck_advance
        if self.precheck_quote is not None:
            self.quote = Quote(True, self.precheck_quote[0], self.precheck_quote[1], self.now)
        return self.precheck_ok

    def send(self, req):
        self.sends += 1
        self.requests.append(req)
        m = self.send_mode
        if m == 'rejected':
            return SendResult(True, True, 10013, 0)
        if m == 'uncertain_not_created':
            return SendResult(False, False, 0, 0)
        if m == 'partial_codes':
            return SendResult(True, True, 10031, 0)
        if m == 'placed_returns_old_ticket':
            return SendResult(True, True, RC_PLACED, self.orders[0].ticket)
        self.next_ticket += 1
        o = Order(True, self.next_ticket, req.symbol, req.type, OS_ACTIVE, req.price, req.sl, req.tp, req.volume, req.magic, req.comment, self.now, req.expiration, 0)
        if m == 'placed_modified':
            o.sl = req.sl + 1.0
        self.orders.append(o)
        if m == 'uncertain_created':
            return SendResult(False, False, 0, 0)
        if m == 'placed_unreadable':
            self.hide.add(o.ticket)
        if m == 'placed_other_ticket':
            return SendResult(True, True, RC_PLACED, o.ticket + 500)
        if m == 'unknown_code_with_order':
            return SendResult(True, True, 10031, o.ticket)
        return SendResult(True, True, RC_PLACED, o.ticket)

    def cancel(self, ticket):
        self.cancels += 1
        m = self.cancel_mode
        for o in self.orders:
            if o.ticket == ticket and o.state == OS_ACTIVE:
                if m in ('ok', 'lost'):
                    o.state = OS_CANCELED
                if m == 'ok':
                    return CancelResult(True, True, RC_DONE)
                if m == 'lost':
                    return CancelResult(False, False, 0)
                if m == 'not_effective':
                    return CancelResult(True, True, RC_DONE)
        return CancelResult(True, True, 10013)
