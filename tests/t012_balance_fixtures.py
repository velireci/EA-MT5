"""T012 day-balance store scenarios (FAKE port only). A start file + a world tweaked by SET assignments + an operation (LOAD / CAPTURE WINDOW_EMPTY / CAPTURE OWNER_ASSERTED) -> hand-written
status, reason, source, amount, number of writes and balance reads, and the state of the file afterwards. The data is generic (field id + value) so that the MQL5 test applies the same
assignments; emit_mql() produces the flat data block of src/tests/T012_BalanceStoreTest.mq5 (equality is tested). Day D = 2026-10-15 (Tirane, UTC+2, 22:00 UTC the evening before)."""
import calendar
import datetime

import t011_persist_reference as p
import t012_balance_reference as b
import t012_history_reference as dh

REF = calendar.timegm(datetime.datetime(2026, 10, 15, 12, 0, 0).timetuple())
DAY, START, END = dh.day_window(REF)
OFF = 7200
ROWS = []
FIELDS = ['acct.ok', 'acct.login', 'acct.currency_empty', 'bal1.ok', 'bal1', 'bal2.ok', 'bal2', 'hist.verdict', 'hist.complete', 'hist.day_shift', 'hist.start_shift', 'hist.end_shift',
          'hist.deals', 't_a', 't_b', 'lock.free', 'write.mode', 'read.mode', 'asrt.complete', 'asrt.offset', 'own.amount', 'own.day_shift', 'clock.day_shift', 'file.unreadable']
FI = {n: i for i, n in enumerate(FIELDS)}
MAXSET = 6
LOAD, CAP_WE, CAP_OA = 0, 1, 2
(K_MISSING, K_VALID_WE, K_VALID_OA, K_CRC, K_TRUNC, K_EMPTY, K_BAD_VERSION, K_BAD_ENUM, K_AMOUNT_ZERO, K_OTHER_LOGIN, K_OTHER_SERVER, K_OTHER_CURRENCY, K_DAY_INSIDE_PREV,
 K_OUTSIDE_DAY, K_WE_NOT_COMPLETE) = range(15)


def base_account():
    return b.Account(True, 5001234, 'MetaQuotes-Demo', 'EUR')


def start_text(kind):
    """the file that exists before the operation (None = no file)"""
    if kind == K_MISSING:
        return None
    acct = base_account()
    we = b.Record(acct.login, acct.server, acct.currency, DAY, 999.0, b.SRC_WE, 1, OFF, START + 3600, START + 3602)
    oa = b.Record(acct.login, acct.server, acct.currency, DAY, 777.0, b.SRC_OA, 0, 0, START + 3600, START + 3600)
    if kind == K_VALID_WE:
        return b.encode(we)[1]
    if kind == K_VALID_OA:
        return b.encode(oa)[1]
    text = b.encode(we)[1]

    def reseal(old, new):
        body = text[:text.index('CRC=')]
        assert old in body, old
        body = body.replace(old, new, 1)
        return body + 'CRC=%08X\n' % p.crc32(body)
    if kind == K_CRC:
        return text.replace('AMOUNT=999.000000000000', 'AMOUNT=998.000000000000')
    if kind == K_TRUNC:
        return text[:len(text) // 2]
    if kind == K_EMPTY:
        return ''
    if kind == K_BAD_VERSION:
        return reseal('VERSION=1', 'VERSION=2')
    if kind == K_BAD_ENUM:
        return reseal('SOURCE=WINDOW_EMPTY', 'SOURCE=SOMETHING')
    if kind == K_AMOUNT_ZERO:
        return reseal('AMOUNT=999.000000000000', 'AMOUNT=0.000000000000')
    if kind == K_OTHER_LOGIN:
        return b.encode(b.Record(1, acct.server, acct.currency, DAY, 999.0, b.SRC_WE, 1, OFF, START + 3600, START + 3602))[1]
    if kind == K_OTHER_SERVER:
        return b.encode(b.Record(acct.login, 'Other-Server', acct.currency, DAY, 999.0, b.SRC_WE, 1, OFF, START + 3600, START + 3602))[1]
    if kind == K_OTHER_CURRENCY:
        return b.encode(b.Record(acct.login, acct.server, 'USD', DAY, 999.0, b.SRC_WE, 1, OFF, START + 3600, START + 3602))[1]
    if kind == K_DAY_INSIDE_PREV:
        return b.encode(b.Record(acct.login, acct.server, acct.currency, DAY - 1, 999.0, b.SRC_WE, 1, OFF, START - 7200, START - 7198))[1]
    if kind == K_OUTSIDE_DAY:
        return reseal('T_FIRST_UTC=%d\nT_LAST_UTC=%d' % (START + 3600, START + 3602), 'T_FIRST_UTC=%d\nT_LAST_UTC=%d' % (END + 10, END + 12))
    if kind == K_WE_NOT_COMPLETE:
        return reseal('HISTORY_COMPLETE_ASSERTED=1', 'HISTORY_COMPLETE_ASSERTED=0')
    raise KeyError(kind)


class FakePort:
    def __init__(self, start_kind, sets):
        self.s = {n: 0.0 for n in FIELDS}
        self.s.update({'acct.ok': 1, 'acct.login': 5001234, 'bal1.ok': 1, 'bal1': 1000.0, 'bal2.ok': 1, 'bal2': 1000.0, 'hist.complete': 1, 't_a': 5, 't_b': 7, 'lock.free': 1,
                       'asrt.complete': 0, 'asrt.offset': float(b.OFFSET_UNSET), 'own.amount': 0.0})
        self.s.update(sets)
        self.files = {}
        self.name = b.file_name(5001234, DAY)
        t = start_text(start_kind)
        if t is not None:
            self.files[self.name] = t
        self.start_text = t
        self.now_calls = 0
        self.bal_calls = 0
        self.writes = 0
        self.locks = 0
        self.locked_ok = 0
        self.unlocks = 0
        self.held = False
        self.after_write = False

    def read_account(self):
        s = self.s
        return b.Account(bool(s['acct.ok']), int(s['acct.login']), 'MetaQuotes-Demo', '' if s['acct.currency_empty'] else 'EUR')

    def now_utc(self):
        self.now_calls += 1
        shift = int(self.s['clock.day_shift']) * 86400
        off = self.s['t_a'] if self.now_calls == 1 else self.s['t_b']
        return START + int(off) + shift

    def read_balance(self):
        self.bal_calls += 1
        k = 'bal1' if self.bal_calls == 1 else 'bal2'
        return bool(self.s[k + '.ok']), self.s[k]

    def read_history(self, t):
        s = self.s
        return b.Hist(int(s['hist.verdict']) and (dh.UNKNOWN if int(s['hist.verdict']) == 1 else dh.BLOCK) or dh.READY, bool(s['hist.complete']), DAY + int(s['hist.day_shift']),
                      START + int(s['hist.start_shift']), END + int(s['hist.end_shift']), int(s['hist.deals']))

    def lock(self, key):
        self.locks += 1
        if not self.s['lock.free']:
            return False
        self.held = True
        self.locked_ok += 1
        return True

    def unlock(self, key):
        self.unlocks += 1
        self.held = False

    def exists(self, name):
        return name in self.files

    def read_file(self, name):
        if name not in self.files or self.s['file.unreadable']:
            return False, ''
        if self.after_write:
            if self.s['read.mode'] == 2:
                return False, ''
            if self.s['read.mode'] == 1:
                return True, self.files[name] + 'x'
        return True, self.files[name]

    def write_file(self, name, text):
        self.writes += 1
        self.after_write = True
        if self.s['write.mode'] == 1:
            self.files[name] = text[:len(text) // 2]
            return False
        if self.s['write.mode'] == 2:
            return False
        self.files[name] = text
        return True


def sets_of(d):
    assert len(d) <= MAXSET
    return dict(d)


def row(name, op, start=K_MISSING, sets=None, status='', reason='', source='', amount=0.0, writes=0, reads=0, disk=''):
    ROWS.append(dict(name=name, op=op, start=start, sets=sets_of(sets or {}), status=status, reason=reason, source=source, amount=amount, writes=writes, reads=reads, disk=disk))


U, N, K, X = b.USABLE, b.NONE, b.UNKNOWN, b.BLOCK
WE, OA = b.SRC_WE, b.SRC_OA
ASSERT_OK = {'asrt.complete': 1, 'asrt.offset': OFF}
# ---------------------------------------------------------------- LOAD: read-only
row('LOAD_MISSING_FILE_IS_NONE_AND_NOTHING_IS_CREATED', LOAD, K_MISSING, status=N, reason='NO_RECORD', disk='MISSING')
row('LOAD_VALID_WINDOW_EMPTY', LOAD, K_VALID_WE, status=U, source=WE, amount=999.0, disk='SAME')
row('LOAD_VALID_OWNER_ASSERTED_STAYS_DISTINCT', LOAD, K_VALID_OA, status=U, source=OA, amount=777.0, disk='SAME')
row('LOAD_RESTART_INSIDE_THE_DAY_KEEPS_THE_STORED_AMOUNT', LOAD, K_VALID_WE, {'bal1': 5000.0, 'bal2': 5000.0, 't_a': 40000}, status=U, source=WE, amount=999.0, disk='SAME')
row('LOAD_NEXT_DAY_DOES_NOT_CARRY_THE_OLD_BALANCE', LOAD, K_VALID_WE, {'clock.day_shift': 1}, status=N, reason='NO_RECORD', disk='SAME')
row('LOAD_RECORD_OF_ANOTHER_DAY_IN_TODAYS_FILE', LOAD, K_DAY_INSIDE_PREV, status=X, reason='WRONG_DAY_IN_RECORD', disk='SAME')
row('LOAD_DAMAGED_CRC', LOAD, K_CRC, status=X, reason='DAMAGED: CRC_MISMATCH', disk='SAME')
row('LOAD_TRUNCATED', LOAD, K_TRUNC, status=X, reason='DAMAGED', disk='SAME')
row('LOAD_EMPTY_FILE', LOAD, K_EMPTY, status=X, reason='DAMAGED: EMPTY', disk='SAME')
row('LOAD_OLD_VERSION', LOAD, K_BAD_VERSION, status=X, reason='UNSUPPORTED_VERSION', disk='SAME')
row('LOAD_UNKNOWN_SOURCE', LOAD, K_BAD_ENUM, status=X, reason='BAD_ENUM', disk='SAME')
row('LOAD_ZERO_AMOUNT', LOAD, K_AMOUNT_ZERO, status=X, reason='INVALID_AMOUNT', disk='SAME')
row('LOAD_INSTANT_OUTSIDE_THE_DAY', LOAD, K_OUTSIDE_DAY, status=X, reason='INVALID_INSTANT', disk='SAME')
row('LOAD_WINDOW_EMPTY_WITHOUT_THE_COMPLETE_ASSERTION', LOAD, K_WE_NOT_COMPLETE, status=X, reason='INVALID_WINDOW_EMPTY_EVIDENCE', disk='SAME')
row('LOAD_OTHER_LOGIN', LOAD, K_OTHER_LOGIN, status=X, reason='WRONG_ACCOUNT', disk='SAME')
row('LOAD_OTHER_SERVER', LOAD, K_OTHER_SERVER, status=X, reason='WRONG_ACCOUNT', disk='SAME')
row('LOAD_OTHER_CURRENCY', LOAD, K_OTHER_CURRENCY, status=X, reason='WRONG_ACCOUNT', disk='SAME')
row('LOAD_FILE_EXISTS_BUT_CANNOT_BE_READ', LOAD, K_VALID_WE, {'file.unreadable': 1}, status=X, reason='FILE_UNREADABLE', disk='SAME')
row('LOAD_ACCOUNT_UNREADABLE', LOAD, K_VALID_WE, {'acct.ok': 0}, status=K, reason='ACCOUNT_UNREADABLE', disk='SAME')
row('LOAD_CURRENCY_UNKNOWN', LOAD, K_VALID_WE, {'acct.currency_empty': 1}, status=K, reason='ACCOUNT_UNREADABLE', disk='SAME')
# ---------------------------------------------------------------- CAPTURE WINDOW_EMPTY
row('CAPTURE_WE_EMPTY_WINDOW_AT_00_00_05', CAP_WE, sets=ASSERT_OK, status=U, source=WE, amount=1000.0, writes=1, reads=2, disk='NEW')
row('CAPTURE_WE_EMPTY_WINDOW_AT_15_00', CAP_WE, sets=dict(ASSERT_OK, t_a=54000, t_b=54003), status=U, source=WE, amount=1000.0, writes=1, reads=2, disk='NEW')
row('CAPTURE_WE_ONE_DEAL_IN_THE_WINDOW_IS_MID_DAY', CAP_WE, sets=dict(ASSERT_OK, **{'hist.deals': 1}), status=K, reason='MID_DAY_NOT_PROVEN', reads=2, disk='MISSING')
row('CAPTURE_WE_ANY_DEAL_OF_ANY_MAGIC_OR_TYPE_COUNTS', CAP_WE, sets=dict(ASSERT_OK, **{'hist.deals': 7}), status=K, reason='MID_DAY_NOT_PROVEN', reads=2, disk='MISSING')
row('CAPTURE_WE_HISTORY_UNKNOWN', CAP_WE, sets=dict(ASSERT_OK, **{'hist.verdict': 1}), status=K, reason='HISTORY_NOT_READY', reads=1, disk='MISSING')
row('CAPTURE_WE_HISTORY_BLOCK', CAP_WE, sets=dict(ASSERT_OK, **{'hist.verdict': 2}), status=K, reason='HISTORY_NOT_READY', reads=1, disk='MISSING')
row('CAPTURE_WE_HISTORY_NOT_COMPLETE', CAP_WE, sets=dict(ASSERT_OK, **{'hist.complete': 0}), status=K, reason='HISTORY_NOT_COMPLETE', reads=1, disk='MISSING')
row('CAPTURE_WE_COMPLETE_NOT_ASSERTED_NOTHING_IS_READ', CAP_WE, sets={'asrt.offset': OFF}, status=K, reason='HISTORY_COMPLETE_NOT_ASSERTED', disk='MISSING')
row('CAPTURE_WE_OFFSET_NOT_ASSERTED', CAP_WE, sets={'asrt.complete': 1}, status=K, reason='OFFSET_NOT_ASSERTED', disk='MISSING')
row('CAPTURE_WE_OFFSET_INVALID', CAP_WE, sets={'asrt.complete': 1, 'asrt.offset': 7201}, status=K, reason='OFFSET_INVALID', disk='MISSING')
row('CAPTURE_WE_BALANCE_UNREADABLE', CAP_WE, sets=dict(ASSERT_OK, **{'bal1.ok': 0}), status=K, reason='BALANCE_UNREADABLE', reads=1, disk='MISSING')
row('CAPTURE_WE_BALANCE_ZERO', CAP_WE, sets=dict(ASSERT_OK, bal1=0.0, bal2=0.0), status=K, reason='BALANCE_UNREADABLE', reads=1, disk='MISSING')
row('CAPTURE_WE_BALANCE_NEGATIVE', CAP_WE, sets=dict(ASSERT_OK, bal1=-5.0, bal2=-5.0), status=K, reason='BALANCE_UNREADABLE', reads=1, disk='MISSING')
row('CAPTURE_WE_BALANCE_CHANGES_BETWEEN_THE_TWO_READS', CAP_WE, sets=dict(ASSERT_OK, bal2=1000.5), status=K, reason='BALANCE_CHANGED_DURING_ACQUISITION', reads=2, disk='MISSING')
row('CAPTURE_WE_SECOND_BALANCE_READ_FAILS', CAP_WE, sets=dict(ASSERT_OK, **{'bal2.ok': 0}), status=K, reason='BALANCE_UNREADABLE', reads=2, disk='MISSING')
row('CAPTURE_WE_MIDNIGHT_CROSSED_WITHIN_THE_SPAN', CAP_WE, sets=dict(ASSERT_OK, t_a=END - START - 2, t_b=END - START + 3), status=K, reason='DAY_CHANGED_DURING_ACQUISITION', reads=2, disk='MISSING')
row('CAPTURE_WE_ACQUISITION_TOO_SLOW', CAP_WE, sets=dict(ASSERT_OK, t_a=100, t_b=221), status=K, reason='ACQUISITION_TOO_SLOW', reads=2, disk='MISSING')
row('CAPTURE_WE_CLOCK_GOES_BACKWARDS', CAP_WE, sets=dict(ASSERT_OK, t_a=100, t_b=99), status=K, reason='CLOCK_WENT_BACKWARDS', reads=2, disk='MISSING')
row('CAPTURE_WE_HISTORY_OF_ANOTHER_DAY', CAP_WE, sets=dict(ASSERT_OK, **{'hist.day_shift': -1}), status=K, reason='HISTORY_DAY_DIFFERS', reads=2, disk='MISSING')
row('CAPTURE_WE_HISTORY_WINDOW_ENDS_BEFORE_THE_INSTANT', CAP_WE, sets=dict(ASSERT_OK, **{'hist.end_shift': -86395}), status=K, reason='HISTORY_DOES_NOT_COVER_THE_INSTANT', reads=2, disk='MISSING')
row('CAPTURE_WE_HISTORY_WINDOW_STARTS_AFTER_THE_INSTANT', CAP_WE, sets=dict(ASSERT_OK, **{'hist.start_shift': 100}), status=K, reason='HISTORY_DOES_NOT_COVER_THE_INSTANT', reads=2, disk='MISSING')
row('CAPTURE_WE_ACCOUNT_UNREADABLE', CAP_WE, sets=dict(ASSERT_OK, **{'acct.ok': 0}), status=K, reason='ACCOUNT_UNREADABLE', disk='MISSING')
row('CAPTURE_WE_LOCK_HELD_NOTHING_IS_READ_OR_WRITTEN', CAP_WE, sets=dict(ASSERT_OK, **{'lock.free': 0}), status=K, reason='LOCK_FAILED', disk='MISSING')
row('CAPTURE_WE_EXISTING_VALID_IS_RETURNED_NOT_OVERWRITTEN', CAP_WE, K_VALID_WE, sets=ASSERT_OK, status=U, reason='ALREADY_CAPTURED', source=WE, amount=999.0, disk='SAME')
row('CAPTURE_WE_EXISTING_OWNER_VALUE_IS_NEVER_REPLACED_BY_A_PROOF', CAP_WE, K_VALID_OA, sets=ASSERT_OK, status=U, reason='ALREADY_CAPTURED', source=OA, amount=777.0, disk='SAME')
row('CAPTURE_WE_EXISTING_DAMAGED_IS_NEVER_OVERWRITTEN', CAP_WE, K_CRC, sets=ASSERT_OK, status=X, reason='DAMAGED', disk='SAME')
row('CAPTURE_WE_EXISTING_TRUNCATED_IS_NEVER_OVERWRITTEN', CAP_WE, K_TRUNC, sets=ASSERT_OK, status=X, reason='DAMAGED', disk='SAME')
row('CAPTURE_WE_EXISTING_EMPTY_PARTIAL_IS_NEVER_OVERWRITTEN', CAP_WE, K_EMPTY, sets=ASSERT_OK, status=X, reason='DAMAGED', disk='SAME')
row('CAPTURE_WE_EXISTING_OF_ANOTHER_ACCOUNT_IS_NEVER_OVERWRITTEN', CAP_WE, K_OTHER_LOGIN, sets=ASSERT_OK, status=X, reason='WRONG_ACCOUNT', disk='SAME')
row('CAPTURE_WE_EXISTING_WITH_ANOTHER_CURRENCY', CAP_WE, K_OTHER_CURRENCY, sets=ASSERT_OK, status=X, reason='WRONG_ACCOUNT', disk='SAME')
row('CAPTURE_WE_EXISTING_UNREADABLE_IS_NEVER_OVERWRITTEN', CAP_WE, K_VALID_WE, sets=dict(ASSERT_OK, **{'file.unreadable': 1}), status=X, reason='FILE_UNREADABLE', disk='SAME')
row('CAPTURE_WE_WRITE_FAILS_WITH_A_PARTIAL_FILE', CAP_WE, sets=dict(ASSERT_OK, **{'write.mode': 1}), status=K, reason='WRITE_FAILED', writes=1, reads=2, disk='PARTIAL')
row('CAPTURE_WE_WRITE_FAILS_WITHOUT_A_FILE', CAP_WE, sets=dict(ASSERT_OK, **{'write.mode': 2}), status=K, reason='WRITE_FAILED', writes=1, reads=2, disk='MISSING')
row('CAPTURE_WE_READBACK_DIFFERS', CAP_WE, sets=dict(ASSERT_OK, **{'read.mode': 1}), status=K, reason='READBACK_FAILED', writes=1, reads=2, disk='NEW')
row('CAPTURE_WE_READBACK_UNREADABLE', CAP_WE, sets=dict(ASSERT_OK, **{'read.mode': 2}), status=K, reason='READBACK_FAILED', writes=1, reads=2, disk='NEW')
row('CAPTURE_WE_NEXT_DAY_STARTS_FROM_ZERO_AND_LEAVES_THE_OLD_FILE_ALONE', CAP_WE, K_VALID_WE, sets=dict(ASSERT_OK, **{'clock.day_shift': 1, 'hist.day_shift': 1, 'hist.start_shift': 86400, 'hist.end_shift': 86400}), status=U, source=WE,
    amount=1000.0, writes=1, reads=2, disk='NEWDAY')
# ---------------------------------------------------------------- CAPTURE OWNER_ASSERTED: an explicit, separate source
row('CAPTURE_OA_EXPLICIT_AMOUNT', CAP_OA, sets={'own.amount': 1234.5}, status=U, source=OA, amount=1234.5, writes=1, reads=0, disk='NEW')
row('CAPTURE_OA_DOES_NOT_NEED_AN_EMPTY_WINDOW_BUT_STAYS_DISTINCT', CAP_OA, sets={'own.amount': 1234.5, 'hist.deals': 9}, status=U, source=OA, amount=1234.5, writes=1, reads=0, disk='NEW')
row('CAPTURE_OA_AMOUNT_MISSING', CAP_OA, sets={'own.amount': 0.0}, status=K, reason='OWNER_AMOUNT_INVALID', disk='MISSING')
row('CAPTURE_OA_AMOUNT_NEGATIVE', CAP_OA, sets={'own.amount': -3.0}, status=K, reason='OWNER_AMOUNT_INVALID', disk='MISSING')
row('CAPTURE_OA_AMOUNT_NOT_EXACT', CAP_OA, sets={'own.amount': 1234.5678901234567}, status=K, reason='OWNER_AMOUNT_INVALID', disk='MISSING')
row('CAPTURE_OA_DAY_NOT_THE_CURRENT_ONE', CAP_OA, sets={'own.amount': 1234.5, 'own.day_shift': -1}, status=K, reason='OWNER_DAY_MISMATCH', disk='MISSING')
row('CAPTURE_OA_EXISTING_WINDOW_EMPTY_RECORD_IS_NOT_REPLACED', CAP_OA, K_VALID_WE, sets={'own.amount': 1234.5}, status=U, reason='ALREADY_CAPTURED', source=WE, amount=999.0, disk='SAME')
row('CAPTURE_OA_EXISTING_DAMAGED_IS_NOT_REPLACED', CAP_OA, K_CRC, sets={'own.amount': 1234.5}, status=X, reason='DAMAGED', disk='SAME')
row('CAPTURE_OA_LOCK_HELD', CAP_OA, sets={'own.amount': 1234.5, 'lock.free': 0}, status=K, reason='LOCK_FAILED', disk='MISSING')
row('CAPTURE_OA_WRITE_FAILS', CAP_OA, sets={'own.amount': 1234.5, 'write.mode': 2}, status=K, reason='WRITE_FAILED', writes=1, disk='MISSING')
row('CAPTURE_OA_READBACK_DIFFERS', CAP_OA, sets={'own.amount': 1234.5, 'read.mode': 1}, status=K, reason='READBACK_FAILED', writes=1, disk='NEW')


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t012_balance_fixtures.py emit_mql)']
    out.append('#define NROWS %d' % len(ROWS))
    out.append('#define MAXSET %d' % MAXSET)
    out.append('#define T_START %d' % START)
    out.append('#define T_END %d' % END)
    out.append('#define T_DAY %d' % DAY)
    q = lambda v: '"%s"' % v

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    num = lambda v: repr(float(v))
    arr('string', 'R_NAME', [q(r['name']) for r in ROWS])
    arr('int', 'R_OP', [str(r['op']) for r in ROWS])
    arr('int', 'R_START', [str(r['start']) for r in ROWS])
    arr('int', 'S_N', [str(len(r['sets'])) for r in ROWS])
    keys, vals = [], []
    for r in ROWS:
        items = list(r['sets'].items())
        for k in range(MAXSET):
            keys.append(str(FI[items[k][0]]) if k < len(items) else '-1')
            vals.append(num(items[k][1]) if k < len(items) else '0.0')
    arr('int', 'S_KEY', keys)
    arr('double', 'S_VAL', vals)
    arr('string', 'X_STATUS', [q(r['status']) for r in ROWS])
    arr('string', 'X_REASON', [q(r['reason']) for r in ROWS])
    arr('string', 'X_SOURCE', [q(r['source']) for r in ROWS])
    arr('double', 'X_AMOUNT', [num(r['amount']) for r in ROWS])
    arr('int', 'X_WRITES', [str(r['writes']) for r in ROWS])
    arr('int', 'X_READS', [str(r['reads']) for r in ROWS])
    arr('string', 'X_DISK', [q(r['disk']) for r in ROWS])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
