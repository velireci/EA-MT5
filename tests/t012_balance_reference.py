"""T012 DAY-BALANCE STORE (Python mirror of src/include/DailyBalanceStore.mqh): keeps the ACCOUNT_BALANCE at the START of the Tirane day.
Reuses, without copying: the Tirane day window (T009 through t012_history_reference.day_window), the history facts (DH_Build: deals_in_window counts EVERY deal of the account in the day
window, any magic, any type, after de-duplication) and the text primitives of the T011 codec (CRC-32, escaping, exact numbers, strict parsing). The T011 modules and files are not touched.
LOAD is read-only and never creates a file. CAPTURE is an explicit action: it takes a lock per terminal for (login, day), checks the existence of the file INSIDE the lock, never overwrites any
existing file (valid, partial or damaged), writes ONE record, reads it back and validates it; every failure is UNKNOWN or BLOCK and the amount is then not usable.
WINDOW_EMPTY is a CONDITIONAL proof: the history facts are READY and `complete` (the OWNER asserted the history is complete and gave the server offset - both are stored in the record), the
window [midnight, now] holds no deal of any kind, two equal balance reads surround a history read that covers the instant, and the Tirane day does not change during the acquisition.
It is not a guarantee of the terminal. Nothing is reconstructed by subtracting profits. OWNER_ASSERTED is a separate explicit source and is never promoted to WINDOW_EMPTY.
The base is ACCOUNT_BALANCE only (the strategy's rule); equity and credit are not alternatives here. The CRC detects accidental damage, it is NOT protection against a deliberate edit.
No order, no cancellation, no policy (result formula, classification, 2/3), no EA integration."""
import math
from dataclasses import dataclass

import t011_persist_reference as p
import t012_history_reference as dh

HEADER, VERSION = 'VELO_T012_DAY_BALANCE', 1
SRC_WE, SRC_OA = 'WINDOW_EMPTY', 'OWNER_ASSERTED'
USABLE, NONE, UNKNOWN, BLOCK = 'USABLE', 'NONE', 'UNKNOWN', 'BLOCK'
MAX_SPAN = 120                 # seconds between the first and the last instant of one acquisition (a technical limit, not a policy)
OFFSET_UNSET = 2147483647
MAX_TEXT = 2048
KEYS = ['VERSION', 'LOGIN', 'SERVER', 'CURRENCY', 'DAY', 'AMOUNT', 'SOURCE', 'HISTORY_COMPLETE_ASSERTED', 'SERVER_OFFSET_SECONDS', 'T_FIRST_UTC', 'T_LAST_UTC']


@dataclass
class Record:
    login: int
    server: str
    currency: str
    day: int
    amount: float
    source: str
    complete_asserted: int
    offset: int
    t_first: int
    t_last: int


@dataclass
class Account:
    read_ok: bool = True
    login: int = 5001234
    server: str = 'MetaQuotes-Demo'
    currency: str = 'EUR'


@dataclass
class Hist:
    verdict: str = dh.READY
    complete: bool = True
    day_key: int = 0
    window_start: int = 0
    window_end: int = 0
    deals_in_window: int = 0


@dataclass
class Asserts:
    complete: bool = False
    offset: int = OFFSET_UNSET


@dataclass
class Result:
    status: str = UNKNOWN
    reason: str = ''
    known: bool = False
    day: int = 0
    amount: float = 0.0
    source: str = ''
    written: bool = False
    existed: bool = False


def file_name(login, day):
    return 'VELO_T012_BALANCE_%d_%d.txt' % (login, day)


def lock_key(login, day):
    return 'VELO_T012_LOCK_BAL_%d_%d' % (login, day)


def _isint(x):
    return isinstance(x, int) and not isinstance(x, bool)


def validate(r):
    """internal consistency of a record (independent of the account / day it is checked against)"""
    if not _isint(r.login) or r.login <= 0:
        return 'INVALID_LOGIN'
    if not isinstance(r.server, str) or r.server == '' or not isinstance(r.currency, str) or r.currency == '':
        return 'INVALID_IDENTITY'
    if not _isint(r.day) or not 20000101 <= r.day <= 29991231:
        return 'INVALID_DAY'
    if p.fnum(r.amount) is None or not r.amount > 0:
        return 'INVALID_AMOUNT: must be finite, > 0 and exact with 12 decimals'
    if r.source not in (SRC_WE, SRC_OA):
        return 'INVALID_SOURCE'
    if not _isint(r.offset) or r.complete_asserted not in (0, 1) or not _isint(r.t_first) or not _isint(r.t_last) or r.t_first <= 0 or r.t_last < r.t_first:
        return 'INVALID_ASSERTIONS_OR_TIMES'
    if r.source == SRC_WE:
        if r.complete_asserted != 1 or r.offset % 900 != 0 or abs(r.offset) > 50400 or r.t_last - r.t_first > MAX_SPAN:
            return 'INVALID_WINDOW_EMPTY_EVIDENCE: needs the complete assertion, a valid server offset and a short acquisition'
    elif r.complete_asserted != 0 or r.offset != 0 or r.t_last != r.t_first:
        return 'INVALID_OWNER_ASSERTED_FIELDS'
    for t in (r.t_first, r.t_last):
        w = dh.day_window(t)
        if w is None or w[0] != r.day:
            return 'INVALID_INSTANT: the instant of the record is not inside its Tirane day'
    return ''


def encode(r):
    bad = validate(r)
    if bad:
        return False, bad
    lines = [HEADER, 'VERSION=%d' % VERSION, 'LOGIN=%d' % r.login, 'SERVER=' + p.esc(r.server), 'CURRENCY=' + p.esc(r.currency), 'DAY=%d' % r.day, 'AMOUNT=' + p.fnum(r.amount),
             'SOURCE=' + r.source, 'HISTORY_COMPLETE_ASSERTED=%d' % r.complete_asserted, 'SERVER_OFFSET_SECONDS=%d' % r.offset, 'T_FIRST_UTC=%d' % r.t_first, 'T_LAST_UTC=%d' % r.t_last, 'END']
    body = '\n'.join(lines) + '\n'
    text = body + 'CRC=%08X\n' % p.crc32(body)
    return (True, text) if len(text) <= MAX_TEXT else (False, 'TOO_LARGE')


def decode(text):
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
    import re
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
    ver = p._geti(v['VERSION'])
    if ver != VERSION:
        return False, 'UNSUPPORTED_VERSION: %s' % v['VERSION'][:20]
    ints = {k2: p._geti(v[k2]) for k2 in ('LOGIN', 'DAY', 'HISTORY_COMPLETE_ASSERTED', 'SERVER_OFFSET_SECONDS', 'T_FIRST_UTC', 'T_LAST_UTC')}
    amount = p._getd(v['AMOUNT'])
    server, currency = p.unesc(v['SERVER']), p.unesc(v['CURRENCY'])
    if any(x is None for x in ints.values()) or amount is None or server is None or currency is None:
        return False, 'BAD_NUMBER_OR_STRING'
    if v['SOURCE'] not in (SRC_WE, SRC_OA):
        return False, 'BAD_ENUM: SOURCE'
    rec = Record(ints['LOGIN'], server, currency, ints['DAY'], amount, v['SOURCE'], ints['HISTORY_COMPLETE_ASSERTED'], ints['SERVER_OFFSET_SECONDS'], ints['T_FIRST_UTC'], ints['T_LAST_UTC'])
    bad = validate(rec)
    return (False, bad) if bad else (True, rec)


def _check_against(rec, acct, day):
    if (rec.login, rec.server, rec.currency) != (acct.login, acct.server, acct.currency):
        return 'WRONG_ACCOUNT: the record belongs to another login / server / currency'
    if rec.day != day:
        return 'WRONG_DAY_IN_RECORD: the file name and the record disagree about the Tirane day'
    return ''


def _from_file(port, acct, day):
    name = file_name(acct.login, day)
    ok, text = port.read_file(name)
    if not ok:
        return Result(BLOCK, 'FILE_UNREADABLE: the file exists and could not be read')
    ok, rec = decode(text)
    if not ok:
        return Result(BLOCK, 'DAMAGED: ' + rec)
    bad = _check_against(rec, acct, day)
    if bad:
        return Result(BLOCK, bad)
    return Result(USABLE, '', True, day, rec.amount, rec.source, False, True)


def _identity(port):
    acct = port.read_account()
    if not acct.read_ok or not _isint(acct.login) or acct.login <= 0 or acct.server == '' or acct.currency == '':
        return None, None, None, Result(UNKNOWN, 'ACCOUNT_UNREADABLE: login, server and currency must all be known')
    t = port.now_utc()
    w = dh.day_window(t)
    if w is None:
        return None, None, None, Result(UNKNOWN, 'DAY_UNSUPPORTED: the instant is outside the T009 rules')
    return acct, t, w, None


def load(port):
    """READ-ONLY: never creates, writes or locks anything. NONE = no file for this account and Tirane day (nothing is invented)."""
    acct, t, w, bad = _identity(port)
    if bad:
        return bad
    day = w[0]
    if not port.exists(file_name(acct.login, day)):
        return Result(NONE, 'NO_RECORD: no file for this account and Tirane day; the balance at the start of the day is unknown')
    return _from_file(port, acct, day)


def capture(port, src, asserts=None, owner_amount=0.0, owner_day=0):
    """EXPLICIT action. src WINDOW_EMPTY (needs the owner's complete + offset assertions) or OWNER_ASSERTED (needs an amount and the day it is for)."""
    asserts = asserts or Asserts()
    if src not in (SRC_WE, SRC_OA):
        return Result(UNKNOWN, 'SOURCE_NOT_SELECTED')
    if src == SRC_WE:
        if asserts.complete is not True:
            return Result(UNKNOWN, 'HISTORY_COMPLETE_NOT_ASSERTED: WINDOW_EMPTY is a conditional proof over a history the owner declares complete')
        if asserts.offset == OFFSET_UNSET:
            return Result(UNKNOWN, 'OFFSET_NOT_ASSERTED: the server offset must be given')
        if not _isint(asserts.offset) or asserts.offset % 900 != 0 or abs(asserts.offset) > 50400:
            return Result(UNKNOWN, 'OFFSET_INVALID')
    elif p.fnum(owner_amount) is None or not owner_amount > 0 or not _isint(owner_day) or owner_day <= 0:
        return Result(UNKNOWN, 'OWNER_AMOUNT_INVALID: a finite exact amount > 0 and the day it is for are required')
    acct, t_a, w, bad = _identity(port)
    if bad:
        return bad
    day = w[0]
    if src == SRC_OA and owner_day != day:
        return Result(UNKNOWN, 'OWNER_DAY_MISMATCH: the asserted day is not the current Tirane day')
    key = lock_key(acct.login, day)
    if not port.lock(key):
        return Result(UNKNOWN, 'LOCK_FAILED: another capture holds this account / day in this terminal; nothing is read or written')
    try:
        name = file_name(acct.login, day)
        if port.exists(name):                                          # INSIDE the lock; never overwritten, whatever it holds
            r = _from_file(port, acct, day)
            if r.status == USABLE:
                r.reason = 'ALREADY_CAPTURED: the stored record is returned unchanged'
            return r
        if src == SRC_WE:
            ok1, b1 = port.read_balance()
            if not ok1 or not math.isfinite(b1) or not b1 > 0:
                return Result(UNKNOWN, 'BALANCE_UNREADABLE')
            h = port.read_history(t_a)
            if h.verdict != dh.READY:
                return Result(UNKNOWN, 'HISTORY_NOT_READY:' + str(h.verdict))
            if not h.complete:
                return Result(UNKNOWN, 'HISTORY_NOT_COMPLETE')
            ok2, b2 = port.read_balance()
            if not ok2 or not math.isfinite(b2) or not b2 > 0:
                return Result(UNKNOWN, 'BALANCE_UNREADABLE')
            if b2 != b1:
                return Result(UNKNOWN, 'BALANCE_CHANGED_DURING_ACQUISITION')
            t_b = port.now_utc()
            if t_b < t_a:
                return Result(UNKNOWN, 'CLOCK_WENT_BACKWARDS')
            if t_b - t_a > MAX_SPAN:
                return Result(UNKNOWN, 'ACQUISITION_TOO_SLOW')
            wb = dh.day_window(t_b)
            if wb is None or wb[0] != day:
                return Result(UNKNOWN, 'DAY_CHANGED_DURING_ACQUISITION')
            if h.day_key != day:
                return Result(UNKNOWN, 'HISTORY_DAY_DIFFERS')
            if not (h.window_start <= t_a and t_b < h.window_end):
                return Result(UNKNOWN, 'HISTORY_DOES_NOT_COVER_THE_INSTANT')
            if h.deals_in_window != 0:
                return Result(UNKNOWN, 'MID_DAY_NOT_PROVEN: %d deal(s) of the account already exist in the day window; the balance read now is not the start-of-day balance' % h.deals_in_window)
            rec = Record(acct.login, acct.server, acct.currency, day, b1, SRC_WE, 1, asserts.offset, t_a, t_b)
        else:
            rec = Record(acct.login, acct.server, acct.currency, day, owner_amount, SRC_OA, 0, 0, t_a, t_a)
        ok, text = encode(rec)
        if not ok:
            return Result(UNKNOWN, 'RECORD_REFUSED: ' + text)
        if not port.write_file(name, text):
            return Result(UNKNOWN, 'WRITE_FAILED: a partial file may exist and then blocks later captures until the owner removes it; the amount is not usable')
        ok, back = port.read_file(name)
        if not ok or back != text:
            return Result(UNKNOWN, 'READBACK_FAILED: the stored text differs from the written one; the amount is not usable')
        ok, rec2 = decode(back)
        if not ok or _check_against(rec2, acct, day):
            return Result(UNKNOWN, 'READBACK_INVALID: the stored record does not validate; the amount is not usable')
        return Result(USABLE, '', True, day, rec2.amount, rec2.source, True, False)
    finally:
        port.unlock(key)
