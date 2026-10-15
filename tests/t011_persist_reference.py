"""T011 persistence of the 2R partial-close state: PURE codec + restore decision (Python mirror of src/include/ExitStateCodec.mqh) and a model of the
file protocol (mirror of src/include/ExitStateFile.mqh, tested here with real temporary files and injected faults).

WHAT IS STORED (one record per position, text, versioned, fully validated, checksummed):
  identity  : server name, account login, symbol, position identifier   (a record of another identity is never restored)
  state     : EVERY field of the T011 SEaState (status, bound, position, direction, level, initial volume, volume step, request id, request steps, close
              volume, initial steps, executed steps, CONFIRMATIONS, duplicates, reason)  -> a restore neither adds a confirmation nor forgets the request
  send      : send phase NONE | INTENT | MAPPED and the executor's order tickets (the request -> order map) with its completeness flag
  generation: positive counter, +1 per save
FORMAT: lines KEY=VALUE in a fixed order, header VELO_EXIT_STATE, VERSION=3, ..., END, then CRC=<8 hex> (CRC-32 of everything up to and including "END\\n")
and a final newline. Strings are escaped (only A-Z a-z 0-9 . _ - literal, everything else %XXXX of the UTF-16 code unit). Doubles are written with 12 decimals
and ONLY if that text parses back to the identical double (otherwise the encode is refused: the executor must pass price/volume values normalised to the symbol,
because the activation compares level / volume with ==). A truncated, edited, empty, oversized, unknown-version or out-of-order text is rejected.
RESTORE (never reads the broker, never trusts the file as proof of execution):
  USABLE_IDLE      valid IDLE record, same identity. new request allowed ONLY under the protocol "persist REQUEST_PENDING + INTENT and verify it BEFORE OrderSend"
                   (an IDLE file proves nothing about what was sent after it was written when that protocol was not followed).
  USABLE_REQUEST   PENDING / NEEDS_RECONCILIATION / DONE with the order map (or DONE): the state is restored AS STORED, a new request is NEVER allowed and
                   reconcile_required is True: the next action is reconciliation with the broker (the adapter + ER_Reconcile), not the file.
  USABLE_BLOCKED   BLOCKED stays BLOCKED (absorbing).
  RECOVERY_REQUIRED missing / corrupt / truncated / wrong version / wrong identity / leftover temporary file / invalid combination / an uncertain send (request
                   PENDING or NEEDS_RECONCILIATION with send phase INTENT = no order map): the returned state is BLOCKED (or NEEDS_RECONCILIATION for a valid record with an
                   uncertain send) so that EA_OnQuote cannot produce a request; no map is invented, no retry exists. A human / the owner must reconcile.
LIMITS (see tasks/T011-exit-persistence.md): the write is NOT atomic with the broker nor guaranteed atomic on the file system; a crash between "request sent"
and "map persisted" is detected only as an uncertain send; a file restored from a backup (older generation) cannot be detected as older; clock-free.
"""
import math
import os
import re
import zlib
from dataclasses import dataclass, field

import t011_activation_reference as act

VERSION = 3          # 3 adds the declared R basis (PLAN_RPOL, PLAN_E_SRC, PLAN_S_SRC, PLAN_E_OUT, PLAN_S_OUT); version 1 and 2 records are never migrated
RPOL_NONE, RPOL_TYPED, RPOL_R_GEOM = 0, 1, 2     # how the level was obtained: typed diagnostic level (no basis) or R_GEOM from the stored E and S
BASIS_TOL = 1e-9     # relative tolerance between the source price and its normalized value (floating-point noise only)
HEADER = 'VELO_EXIT_STATE'
STATUSES = [act.IDLE, act.REQUEST_PENDING, act.DONE, act.NEEDS_RECONCILIATION, act.BLOCKED]
SEND_NONE, SEND_INTENT, SEND_MAPPED = 0, 1, 2
MAX_ORDERS = 8
MAX_TEXT = 4096
MAX_STR = 1024
MAX_GEN = 2 ** 31 - 1
MAX_COUNT = 100000
MAX_ID = 10 ** 18 - 1
USABLE_IDLE, USABLE_REQUEST, USABLE_BLOCKED, RECOVERY_REQUIRED = 'USABLE_IDLE', 'USABLE_REQUEST', 'USABLE_BLOCKED', 'RECOVERY_REQUIRED'
LITERAL = re.compile(r'^[A-Za-z0-9._-]*$')


@dataclass(frozen=True)
class Identity:
    server: str
    login: int
    symbol: str
    position_id: int


@dataclass
class Record:
    generation: int
    identity: Identity
    state: act.State
    send_phase: int = SEND_NONE
    map_complete: bool = False
    orders: list = field(default_factory=list)
    plan_set: bool = False         # the AUTHORISED plan stored at registration: direction / level 2R / initial volume live in the bound state, TP and min / step / max here
    plan_tp: float = 0.0
    plan_vol_min: float = 0.0
    plan_vol_step: float = 0.0
    plan_vol_max: float = 0.0
    plan_rpol: int = 0
    plan_e_src: float = 0.0        # R_GEOM only: the declared entry / initial stop as read, and the values TG_Compute normalized them to (R itself is NOT stored)
    plan_s_src: float = 0.0
    plan_e_out: float = 0.0
    plan_s_out: float = 0.0


@dataclass
class Restore:
    verdict: str
    reason: str
    state: act.State
    new_request_allowed: bool = False
    reconcile_required: bool = False
    orders: list = field(default_factory=list)
    map_complete: bool = False
    generation: int = 0
    plan_set: bool = False
    plan_tp: float = 0.0
    plan_vol_min: float = 0.0
    plan_vol_step: float = 0.0
    plan_vol_max: float = 0.0
    plan_rpol: int = 0
    plan_e_src: float = 0.0
    plan_s_src: float = 0.0
    plan_e_out: float = 0.0
    plan_s_out: float = 0.0


def crc32(text):
    crc = 0xFFFFFFFF
    for ch in text:
        crc ^= ord(ch) & 0xFF
        for _ in range(8):
            crc = (crc >> 1) ^ 0xEDB88320 if crc & 1 else crc >> 1
    return crc ^ 0xFFFFFFFF


def esc(s):
    out = []
    for ch in s:
        if LITERAL.match(ch):
            out.append(ch)
        else:
            out.append('%%%04X' % ord(ch))
    return ''.join(out)


def unesc(s):
    out, i = [], 0
    while i < len(s):
        ch = s[i]
        if ch == '%':
            h = s[i + 1:i + 5]
            if len(h) != 4 or not re.fullmatch(r'[0-9A-F]{4}', h):
                return None
            out.append(chr(int(h, 16)))
            i += 5
        elif LITERAL.match(ch):
            out.append(ch)
            i += 1
        else:
            return None
    return ''.join(out)


def fnum(x):
    if not isinstance(x, (int, float)) or isinstance(x, bool) or not math.isfinite(x):
        return None
    t = '%.12f' % (x + 0.0)
    return t if float(t) == x else None


def _isint(x):
    return isinstance(x, int) and not isinstance(x, bool)


def _close(a, b):
    return abs(a - b) <= 1e-9 * max(1.0, abs(a), abs(b))


def validate(rec):
    """Returns '' or the first reason. Used by encode (never write an invalid record) and after decode."""
    idn, st = rec.identity, rec.state
    if not _isint(rec.generation) or not 1 <= rec.generation <= MAX_GEN:
        return 'INVALID_GENERATION'
    if not isinstance(idn.server, str) or not 1 <= len(idn.server) <= 128:
        return 'INVALID_IDENTITY: server'
    if not _isint(idn.login) or not 1 <= idn.login <= MAX_ID:
        return 'INVALID_IDENTITY: login'
    if not isinstance(idn.symbol, str) or not 1 <= len(idn.symbol) <= 32:
        return 'INVALID_IDENTITY: symbol'
    if not _isint(idn.position_id) or not 1 <= idn.position_id <= MAX_ID:
        return 'INVALID_IDENTITY: position'
    if st.status not in STATUSES:
        return 'INVALID_STATUS'
    if not isinstance(st.bound, bool) or st.direction not in (0, 1, -1):
        return 'INVALID_STATE: bound/direction'
    for name in ('level', 'volume_initial', 'volume_step', 'close_volume'):
        v = getattr(st, name)
        if fnum(v) is None or v < 0:
            return 'INVALID_STATE: ' + name
    for name in ('position_id', 'request_steps', 'initial_steps', 'executed_steps'):
        if not _isint(getattr(st, name)) or not 0 <= getattr(st, name) <= MAX_ID:
            return 'INVALID_STATE: ' + name
    for name in ('confirmations', 'duplicates_ignored'):
        if not _isint(getattr(st, name)) or not 0 <= getattr(st, name) <= MAX_COUNT:
            return 'INVALID_STATE: ' + name
    if not isinstance(st.request_id, str) or len(st.request_id) > 64 or not isinstance(st.reason, str) or len(st.reason) > MAX_STR:
        return 'INVALID_STATE: text'
    if rec.send_phase not in (SEND_NONE, SEND_INTENT, SEND_MAPPED):
        return 'INVALID_SEND_PHASE'
    if not isinstance(rec.map_complete, bool) or len(rec.orders) > MAX_ORDERS or len(set(rec.orders)) != len(rec.orders) \
            or any((not _isint(o)) or not 1 <= o <= MAX_ID for o in rec.orders):
        return 'INVALID_MAP: order tickets must be distinct positive integers, at most %d' % MAX_ORDERS
    if rec.send_phase == SEND_MAPPED and not rec.orders:
        return 'INVALID_MAP: send phase MAPPED without an order ticket'
    if rec.send_phase != SEND_MAPPED and (rec.orders or rec.map_complete):
        return 'INVALID_MAP: order tickets or completeness without send phase MAPPED'
    if st.bound and (st.position_id != idn.position_id or st.direction == 0 or st.level <= 0 or st.volume_initial <= 0):
        return 'INVALID_STATE: bound state does not match the identity or lacks direction/level/volume'
    if not st.bound and (st.position_id or st.direction or st.level or st.volume_initial):
        return 'INVALID_STATE: unbound state carries values'
    if not isinstance(rec.plan_set, bool):
        return 'INVALID_PLAN: plan_set'
    for name in ('plan_tp', 'plan_vol_min', 'plan_vol_step', 'plan_vol_max'):
        v = getattr(rec, name)
        if fnum(v) is None or v < 0:
            return 'INVALID_PLAN: ' + name
    if isinstance(rec.plan_rpol, bool) or not isinstance(rec.plan_rpol, int) or rec.plan_rpol not in (RPOL_NONE, RPOL_TYPED, RPOL_R_GEOM):
        return 'INVALID_PLAN: plan_rpol'
    basis = ('plan_e_src', 'plan_s_src', 'plan_e_out', 'plan_s_out')
    for name in basis:
        v = getattr(rec, name)
        if fnum(v) is None or v < 0:
            return 'INVALID_PLAN: ' + name
    if not rec.plan_set and (rec.plan_tp or rec.plan_vol_min or rec.plan_vol_step or rec.plan_vol_max or rec.plan_rpol or any(getattr(rec, n) for n in basis)):
        return 'INVALID_PLAN: values without plan_set'
    if rec.plan_set:
        if not st.bound:
            return 'INVALID_PLAN: a plan needs a bound state (direction, level, initial volume)'
        if rec.plan_tp <= 0 or rec.plan_vol_min <= 0 or rec.plan_vol_step <= 0 or rec.plan_vol_max < rec.plan_vol_min:
            return 'INVALID_PLAN: tp and the volume parameters must be positive and min <= max'
        if st.status not in (act.IDLE, act.BLOCKED) and st.volume_step != rec.plan_vol_step:
            return 'INVALID_PLAN: the request step differs from the authorised plan step'
        if rec.plan_rpol == RPOL_NONE:
            return 'INVALID_PLAN: the R policy of a plan must be set'
        if rec.plan_rpol == RPOL_TYPED and any(getattr(rec, n) for n in basis):
            return 'INVALID_PLAN: a typed diagnostic level carries no E / S basis'
        if rec.plan_rpol == RPOL_R_GEOM:
            if any(getattr(rec, n) <= 0 for n in basis):
                return 'INVALID_PLAN: the R_GEOM basis (E and S, source and normalized) must be positive'
            if abs(rec.plan_e_src - rec.plan_e_out) > BASIS_TOL * max(1.0, rec.plan_e_src) or abs(rec.plan_s_src - rec.plan_s_out) > BASIS_TOL * max(1.0, rec.plan_s_src):
                return 'INVALID_PLAN: the normalized basis differs from the declared source'
            if st.direction == 1 and not rec.plan_s_out < rec.plan_e_out < st.level:
                return 'INVALID_PLAN: BUY needs stop < entry < level 2R'
            if st.direction == -1 and not st.level < rec.plan_e_out < rec.plan_s_out:
                return 'INVALID_PLAN: SELL needs level 2R < entry < stop'
    if st.status == act.BLOCKED:
        return '' if st.reason else 'INVALID_STATE: BLOCKED without a reason'
    if st.status == act.IDLE:
        if rec.send_phase != SEND_NONE or st.request_id or st.request_steps or st.close_volume or st.initial_steps or st.executed_steps \
                or st.confirmations or st.duplicates_ignored or st.volume_step:
            return 'INVALID_STATE: IDLE with request data or a send phase'
        return ''
    # request-bearing states
    if not st.bound or st.volume_step <= 0 or st.initial_steps <= 0 or st.initial_steps % 5 != 0:
        return 'INVALID_STATE: request without a valid plan'
    if st.request_id != act.request_id_for(idn.position_id) or st.request_steps != 4 * st.initial_steps // 5:
        return 'INVALID_STATE: request id or 80% steps do not match the plan'
    if not _close(st.close_volume, st.request_steps * st.volume_step) or not _close(st.volume_initial, st.initial_steps * st.volume_step):
        return 'INVALID_STATE: volumes do not match the steps'
    if rec.send_phase == SEND_NONE:
        return 'INVALID_STATE: request without a persisted send intent'
    if st.executed_steps > st.request_steps or st.confirmations > 1:
        return 'INVALID_STATE: executed steps or confirmations'
    if st.status == act.REQUEST_PENDING and (st.executed_steps or st.confirmations):
        return 'INVALID_STATE: PENDING with executions or a confirmation'
    if st.status == act.DONE and (st.executed_steps != st.request_steps or st.confirmations != 1):
        return 'INVALID_STATE: DONE without exactly one confirmation of the requested steps'
    return ''


def encode(rec):
    """-> (True, text) or (False, reason)."""
    bad = validate(rec)
    if bad:
        return False, bad
    st, idn = rec.state, rec.identity
    lines = [HEADER, 'VERSION=%d' % VERSION, 'GEN=%d' % rec.generation, 'SERVER=' + esc(idn.server), 'LOGIN=%d' % idn.login, 'SYMBOL=' + esc(idn.symbol),
             'POSITION=%d' % idn.position_id, 'STATUS=%d' % STATUSES.index(st.status), 'BOUND=%d' % int(st.bound), 'STATE_POSITION=%d' % st.position_id,
             'DIRECTION=%d' % st.direction, 'LEVEL=' + fnum(st.level), 'VOLUME_INITIAL=' + fnum(st.volume_initial), 'VOLUME_STEP=' + fnum(st.volume_step),
             'REQUEST_ID=' + esc(st.request_id), 'REQUEST_STEPS=%d' % st.request_steps, 'CLOSE_VOLUME=' + fnum(st.close_volume), 'INITIAL_STEPS=%d' % st.initial_steps,
             'EXECUTED_STEPS=%d' % st.executed_steps, 'CONFIRMATIONS=%d' % st.confirmations, 'DUPLICATES=%d' % st.duplicates_ignored,
             'REASON=' + esc(st.reason), 'SEND_PHASE=%d' % rec.send_phase, 'MAP_COMPLETE=%d' % int(rec.map_complete),
             'PLAN_SET=%d' % int(rec.plan_set), 'PLAN_TP=' + fnum(rec.plan_tp), 'PLAN_VOL_MIN=' + fnum(rec.plan_vol_min), 'PLAN_VOL_STEP=' + fnum(rec.plan_vol_step),
             'PLAN_VOL_MAX=' + fnum(rec.plan_vol_max), 'PLAN_RPOL=%d' % rec.plan_rpol, 'PLAN_E_SRC=' + fnum(rec.plan_e_src), 'PLAN_S_SRC=' + fnum(rec.plan_s_src),
             'PLAN_E_OUT=' + fnum(rec.plan_e_out), 'PLAN_S_OUT=' + fnum(rec.plan_s_out), 'MAP_N=%d' % len(rec.orders)]
    lines += ['MAP_ORDER_%d=%d' % (k, o) for k, o in enumerate(rec.orders)]
    lines.append('END')
    body = '\n'.join(lines) + '\n'
    text = body + 'CRC=%08X\n' % crc32(body)
    if len(text) > MAX_TEXT:
        return False, 'TOO_LARGE'
    return True, text


_INT = re.compile(r"^-?(0|[1-9][0-9]{0,17})$")
_DBL = re.compile(r'^-?[0-9]{1,15}\.[0-9]{12}$')


def _geti(v):
    return int(v) if _INT.match(v) and str(int(v)) == v else None


def _getd(v):
    return float(v) if _DBL.match(v) and '%.12f' % float(v) == v else None


def decode(text):
    """-> (True, Record) or (False, reason)."""
    if not isinstance(text, str) or text == '':
        return False, 'EMPTY'
    if len(text) > MAX_TEXT:
        return False, 'TOO_LARGE'
    if not text.endswith('\n'):
        return False, 'TRUNCATED: no final newline'
    k = text.rfind('END\nCRC=')
    if k < 0 or text.count('CRC=') != 1:
        return False, 'TRUNCATED: no END / CRC trailer'
    body, trailer = text[:k + 4], text[k + 4:]
    if not re.fullmatch(r'CRC=[0-9A-F]{8}\n', trailer):
        return False, 'BAD_TRAILER'
    if int(trailer[4:12], 16) != crc32(body):
        return False, 'CRC_MISMATCH: the record is damaged or was edited'
    lines = body.split('\n')[:-1]
    if not lines or lines[0] != HEADER:
        return False, 'BAD_HEADER'
    keys = ['VERSION', 'GEN', 'SERVER', 'LOGIN', 'SYMBOL', 'POSITION', 'STATUS', 'BOUND', 'STATE_POSITION', 'DIRECTION', 'LEVEL', 'VOLUME_INITIAL', 'VOLUME_STEP',
            'REQUEST_ID', 'REQUEST_STEPS', 'CLOSE_VOLUME', 'INITIAL_STEPS', 'EXECUTED_STEPS', 'CONFIRMATIONS', 'DUPLICATES', 'REASON', 'SEND_PHASE', 'MAP_COMPLETE',
            'PLAN_SET', 'PLAN_TP', 'PLAN_VOL_MIN', 'PLAN_VOL_STEP', 'PLAN_VOL_MAX', 'PLAN_RPOL', 'PLAN_E_SRC', 'PLAN_S_SRC', 'PLAN_E_OUT', 'PLAN_S_OUT', 'MAP_N']
    if len(lines) < 2 or not lines[1].startswith('VERSION='):
        return False, 'BAD_FIELD_ORDER: expected VERSION'
    if _geti(lines[1][len('VERSION='):]) != VERSION:
        return False, 'UNSUPPORTED_VERSION: %s (a record without the authorised plan is never migrated)' % lines[1][len('VERSION='):][:20]
    if len(lines) < 1 + len(keys) + 1:
        return False, 'TRUNCATED: missing fields'
    vals = {}
    for i, key in enumerate(keys):
        line = lines[1 + i]
        if not line.startswith(key + '='):
            return False, 'BAD_FIELD_ORDER: expected ' + key
        vals[key] = line[len(key) + 1:]
    if _geti(vals['VERSION']) != VERSION:
        return False, 'UNSUPPORTED_VERSION: %s' % vals['VERSION'][:20]
    n = _geti(vals['MAP_N'])
    if n is None or not 0 <= n <= MAX_ORDERS:
        return False, 'BAD_MAP_COUNT'
    if len(lines) != 1 + len(keys) + n + 1 or lines[-1] != 'END':
        return False, 'BAD_LENGTH: the number of lines does not match'
    orders = []
    for k2 in range(n):
        line = lines[1 + len(keys) + k2]
        if not line.startswith('MAP_ORDER_%d=' % k2):
            return False, 'BAD_FIELD_ORDER: MAP_ORDER_%d' % k2
        o = _geti(line.split('=', 1)[1])
        if o is None:
            return False, 'BAD_NUMBER: MAP_ORDER_%d' % k2
        orders.append(o)
    ints = {k2: _geti(vals[k2]) for k2 in ('GEN', 'LOGIN', 'POSITION', 'STATUS', 'BOUND', 'STATE_POSITION', 'DIRECTION', 'REQUEST_STEPS', 'INITIAL_STEPS', 'EXECUTED_STEPS',
                                            'CONFIRMATIONS', 'DUPLICATES', 'SEND_PHASE', 'MAP_COMPLETE', 'PLAN_SET', 'PLAN_RPOL')}
    dbls = {k2: _getd(vals[k2]) for k2 in ('LEVEL', 'VOLUME_INITIAL', 'VOLUME_STEP', 'CLOSE_VOLUME', 'PLAN_TP', 'PLAN_VOL_MIN', 'PLAN_VOL_STEP', 'PLAN_VOL_MAX', 'PLAN_E_SRC', 'PLAN_S_SRC', 'PLAN_E_OUT', 'PLAN_S_OUT')}
    for k2, v in list(ints.items()) + list(dbls.items()):
        if v is None:
            return False, 'BAD_NUMBER: ' + k2
    strs = {k2: unesc(vals[k2]) for k2 in ('SERVER', 'SYMBOL', 'REQUEST_ID', 'REASON')}
    for k2, v in strs.items():
        if v is None:
            return False, 'BAD_STRING: ' + k2
    if not 0 <= ints['STATUS'] < len(STATUSES) or ints['BOUND'] not in (0, 1) or ints['MAP_COMPLETE'] not in (0, 1) or ints['PLAN_SET'] not in (0, 1) or ints['PLAN_RPOL'] not in (0, 1, 2):
        return False, 'BAD_ENUM'
    st = act.State(status=STATUSES[ints['STATUS']], bound=bool(ints['BOUND']), position_id=ints['STATE_POSITION'], direction=ints['DIRECTION'], level=dbls['LEVEL'],
                   volume_initial=dbls['VOLUME_INITIAL'], volume_step=dbls['VOLUME_STEP'], request_id=strs['REQUEST_ID'], request_steps=ints['REQUEST_STEPS'],
                   close_volume=dbls['CLOSE_VOLUME'], initial_steps=ints['INITIAL_STEPS'], executed_steps=ints['EXECUTED_STEPS'], confirmations=ints['CONFIRMATIONS'],
                   duplicates_ignored=ints['DUPLICATES'], reason=strs['REASON'])
    rec = Record(ints['GEN'], Identity(strs['SERVER'], ints['LOGIN'], strs['SYMBOL'], ints['POSITION']), st, ints['SEND_PHASE'], bool(ints['MAP_COMPLETE']), orders,
               bool(ints['PLAN_SET']), dbls['PLAN_TP'], dbls['PLAN_VOL_MIN'], dbls['PLAN_VOL_STEP'], dbls['PLAN_VOL_MAX'], ints['PLAN_RPOL'], dbls['PLAN_E_SRC'], dbls['PLAN_S_SRC'],
               dbls['PLAN_E_OUT'], dbls['PLAN_S_OUT'])
    bad = validate(rec)
    if bad:
        return False, bad
    return True, rec


def _blocked(reason, identity=None):
    st = act.State()
    st.status = act.BLOCKED
    st.reason = 'RECOVERY_REQUIRED: ' + reason
    return st


def restore(text, expected, tmp_present=False):
    """text: the content of the state file or None when it does not exist. expected: the Identity the executor is running for."""
    if tmp_present:
        return Restore(RECOVERY_REQUIRED, 'LEFTOVER_TMP: a temporary state file exists, the last save did not finish', _blocked('LEFTOVER_TMP'))
    if text is None:
        return Restore(RECOVERY_REQUIRED, 'MISSING: no state file; a missing file never allows a new request', _blocked('MISSING'))
    ok, rec = decode(text)
    if not ok:
        return Restore(RECOVERY_REQUIRED, rec, _blocked(rec))
    if rec.identity != expected:
        return Restore(RECOVERY_REQUIRED, 'IDENTITY_MISMATCH: the record belongs to another server / account / symbol / position', _blocked('IDENTITY_MISMATCH'))
    st = rec.state
    out = Restore(RECOVERY_REQUIRED, '', st, False, False, list(rec.orders), rec.map_complete, rec.generation, rec.plan_set, rec.plan_tp, rec.plan_vol_min, rec.plan_vol_step,
                  rec.plan_vol_max, rec.plan_rpol, rec.plan_e_src, rec.plan_s_src, rec.plan_e_out, rec.plan_s_out)
    if st.status == act.BLOCKED:
        out.verdict, out.reason = USABLE_BLOCKED, 'BLOCKED restored as stored'
        return out
    if st.status == act.IDLE:
        out.verdict, out.reason, out.new_request_allowed = USABLE_IDLE, 'IDLE restored; a new request is allowed only under the persist-before-send protocol', True
        return out
    out.new_request_allowed = False
    out.reconcile_required = True
    if rec.send_phase == SEND_INTENT and st.status in (act.REQUEST_PENDING, act.NEEDS_RECONCILIATION):
        st.status = act.NEEDS_RECONCILIATION
        st.reason = 'RECOVERY_REQUIRED: SEND_UNCERTAIN: the send intent was persisted but no order map; the request may or may not have reached the broker. No retry, no invented map'
        out.verdict, out.reason = RECOVERY_REQUIRED, st.reason
        return out
    out.verdict, out.reason = USABLE_REQUEST, 'request restored as stored; reconcile with the broker before any action (the file is not proof of execution)'
    return out


# ---------------------------------------------------------------- file protocol model (mirror of ExitStateFile.mqh)
class Crash(Exception):
    pass


class FileStore:
    """save(): temp file -> flush -> read back and compare -> move over the target -> read back and compare. load(): target + leftover temp detection.
    `fault` injects one failure: 'write_partial' (a truncated temp file, then Crash), 'crash_before_move', 'move_fails', 'crash_after_move', 'target_differs'."""

    def __init__(self, directory):
        self.dir = directory

    def path(self, name):
        return os.path.join(self.dir, name)

    def exists(self, name):
        return os.path.exists(self.path(name))

    def read(self, name):
        with open(self.path(name), 'rb') as f:
            return f.read().decode('latin-1')

    def _write(self, name, data):
        with open(self.path(name), 'wb') as f:
            f.write(data.encode('latin-1'))
            f.flush()
            os.fsync(f.fileno())

    def load(self, name, expected):
        tmp = name + '.tmp'
        text = self.read(name) if self.exists(name) else None
        return restore(text, expected, self.exists(tmp))

    def save(self, name, rec, fault=None):
        ok, text = encode(rec)
        if not ok:
            return False, 'ENCODE_REFUSED: ' + text
        tmp = name + '.tmp'
        if self.exists(name):
            cur = self.load_plain(name)
            if cur is None:
                return False, 'EXISTING_FILE_UNUSABLE: recover first'
            if cur.identity != rec.identity:
                return False, 'EXISTING_FILE_OTHER_IDENTITY'
            if rec.generation != cur.generation + 1:
                return False, 'GENERATION_NOT_NEXT: %d after %d' % (rec.generation, cur.generation)
        elif rec.generation != 1:
            return False, 'FIRST_GENERATION_MUST_BE_1'
        if self.exists(tmp):
            return False, 'LEFTOVER_TMP: recover first'
        if fault == 'write_partial':
            self._write(tmp, text[:len(text) // 2])
            raise Crash()
        self._write(tmp, text)
        if self.read(tmp) != text:
            os.remove(self.path(tmp))
            return False, 'TMP_READBACK_DIFFERS'
        if fault == 'crash_before_move':
            raise Crash()
        if fault == 'move_fails':
            os.remove(self.path(tmp))
            return False, 'MOVE_FAILED'
        os.replace(self.path(tmp), self.path(name))
        if fault == 'crash_after_move':
            raise Crash()
        if fault == 'target_differs':
            self._write(name, text[:-3] + 'XX\n')
        if self.read(name) != text:
            return False, 'TARGET_READBACK_DIFFERS'
        return True, ''

    def load_plain(self, name):
        ok, rec = decode(self.read(name))
        return rec if ok else None

    def init_fresh(self, name, identity):
        if self.exists(name) or self.exists(name + '.tmp'):
            return False, 'ALREADY_EXISTS: never overwrite'
        return self.save(name, Record(1, identity, act.State()))
