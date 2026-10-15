"""T012 daily-history FACTS scenarios (pure core). Hand-written. Base day: Tirane 2026-07-15 (UTC window 2026-07-14 22:00:00 .. 2026-07-15 22:00:00,
summer offset +2 h), server = UTC+3 (offset 10800), EA magic 777. Positions: 11 = robot (opening deal magic 777), 12 = manual (magic 0), 13 = another EA (555).
Expected values are written by hand per field; the flat canonical text below is produced from them. emit_mql() produces the flat data block of
src/tests/T012_HistoryTest.mq5 (equality is tested)."""
from datetime import datetime, timezone

ROWS = []
MAXD, MAXP = 12, 4
OFF = 10800
S0 = 1784066400            # 2026-07-14 22:00:00 UTC = Tirane midnight of 2026-07-15
E0 = 1784152800            # 2026-07-15 22:00:00 UTC = next Tirane midnight


def U(y, mo, d, h=0, mi=0, s=0):
    return int(datetime(y, mo, d, h, mi, s, tzinfo=timezone.utc).timestamp())


T = lambda h, m=0, s=0: U(2026, 7, 15, h, m, s)       # a UTC instant inside the base day
IN, OUT, INOUT, OUTBY, STATE = 0, 1, 2, 3, 4
BUY, SELL, BAL, CREDIT, CHARGE = 0, 1, 2, 3, 4


def D(ticket, pos, utc, entry, typ, magic, vol, profit=0.0, comm=0.0, swap=0.0, fee=0.0):
    return (ticket, pos, utc, entry, typ, magic, vol, profit, comm, swap, fee)


def P(pos, known=1, magic=777, open_total=0.5, closed_total=0.0, is_open=1):
    return (pos, known, magic, open_total, closed_total, is_open)


ZC = (0, 0.0, 0.0, 0.0, 0.0, 0.0)


def row(name, deals=(), positions=(), magic=777, utc=T(9), offset=OFF, asserted=0, stable=1, verdict='READY', why='', raw=None, **e):
    r = dict(name=name, deals=[(d[0], d[1], d[2] + offset if offset else d[2]) + d[3:] for d in deals], positions=list(positions), magic=magic, utc=utc,
             offset=offset, asserted=asserted, stable=int(stable), verdict=verdict, why=why)
    w = dict(api_ok=1, hist_ok=1, positions_ok=1, margin_ok=1, margin_mode=2, vol_step=0.01, deals_trunc=0, pos_trunc=0)
    w.update(raw or {})
    r['raw'] = w
    x = dict(day=20260715, start=S0, end=E0, dw=0, dup=0, out=0, other=0, exnot=0, nt=(0, 0.0, 0.0, 0.0, 0.0), IN=ZC, OUT=ZC, INOUT=ZC, OUT_BY=ZC, OTHER=ZC,
             pos=[], cand=(0.0, 0.0, 0.0), complete=int(asserted))
    x.update(e)
    r['exp'] = x
    ROWS.append(r)


def canon(x):
    f = lambda v: '%.6f' % (v + 0.0)
    cell = lambda c: '%d,%s' % (c[0], ','.join(f(v) for v in c[1:]))
    pos = ','.join('%d:%d:%d:%s:%s:%s:%s:%s:%s:%s' % (p[0], p[1], p[2], f(p[3]), f(p[4]), f(p[5]), f(p[6]), f(p[7]), f(p[8]), p[9]) for p in x['pos'])
    return ('day=%d;win=%d-%d;dw=%d;dup=%d;out=%d;other=%d;exnot=%d;nt=%d,%s;IN=%s;OUT=%s;INOUT=%s;OUT_BY=%s;OTHER=%s;pos=%s;cand=%s;formula=UNSET;bal=0;complete=%d' %
            (x['day'], x['start'], x['end'], x['dw'], x['dup'], x['out'], x['other'], x['exnot'], x['nt'][0], ','.join(f(v) for v in x['nt'][1:]), cell(x['IN']),
             cell(x['OUT']), cell(x['INOUT']), cell(x['OUT_BY']), cell(x['OTHER']), pos, ','.join(f(v) for v in x['cand']), x['complete']))


# ---- empty and simple days
row('EMPTY_DAY')
row('EMPTY_DAY_OWNER_ASSERTS_COMPLETE', asserted=1)
row('ONE_ROBOT_TRADE_OPENED_AND_CLOSED_TODAY',
    deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5), D(1002, 11, T(10), OUT, SELL, 777, 0.5, 12.5, -0.5, -0.25)],
    positions=[P(11, closed_total=0.5, is_open=0)],
    dw=2, IN=(1, 0.5, 0.0, -0.5, 0.0, 0.0), OUT=(1, 0.5, 12.5, -0.5, -0.25, 0.0),
    pos=[(11, 1, 1, 0.5, 0.5, 12.5, -1.0, -0.25, 0.0, 'CLOSED')], cand=(12.5, 11.25, 11.25))
row('ROBOT_POSITION_STILL_OPEN_NO_EXIT', deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5)], positions=[P(11)],
    dw=1, IN=(1, 0.5, 0.0, -0.5, 0.0, 0.0), pos=[(11, 1, 0, 0.5, 0.0, 0.0, -0.5, 0.0, 0.0, 'OPEN_NO_EXIT')], cand=(0.0, -0.5, -0.5))
row('PARTIAL_EXIT_80_PERCENT_POSITION_STILL_OPEN',
    deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5), D(1002, 11, T(10), OUT, SELL, 777, 0.4, 20.0, -0.25)],
    positions=[P(11, closed_total=0.4, is_open=1)],
    dw=2, IN=(1, 0.5, 0.0, -0.5, 0.0, 0.0), OUT=(1, 0.4, 20.0, -0.25, 0.0, 0.0),
    pos=[(11, 1, 1, 0.5, 0.4, 20.0, -0.75, 0.0, 0.0, 'OPEN_PARTIALLY_CLOSED')], cand=(20.0, 19.25, 19.25))
row('TWO_PARTIAL_EXITS_THEN_CLOSED_THREE_DEALS_ONE_POSITION',
    deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5), D(1002, 11, T(10), OUT, SELL, 777, 0.4, 20.0, -0.25), D(1003, 11, T(12), OUT, SELL, 777, 0.1, -2.5, -0.25, -0.5)],
    positions=[P(11, closed_total=0.5, is_open=0)],
    dw=3, IN=(1, 0.5, 0.0, -0.5, 0.0, 0.0), OUT=(2, 0.5, 17.5, -0.5, -0.5, 0.0),
    pos=[(11, 1, 2, 0.5, 0.5, 17.5, -1.0, -0.5, 0.0, 'CLOSED')], cand=(17.5, 16.0, 16.0))
row('OPENED_YESTERDAY_CLOSED_TODAY_ENTRY_COST_NOT_IN_THE_DAY', deals=[D(1002, 11, T(10), OUT, SELL, 777, 0.5, 7.5, -0.5)],
    positions=[P(11, closed_total=0.5, is_open=0)], dw=1, OUT=(1, 0.5, 7.5, -0.5, 0.0, 0.0), pos=[(11, 0, 1, 0.0, 0.5, 7.5, -0.5, 0.0, 0.0, 'CLOSED')], cand=(7.5, 7.0, 7.0))
row('OPENED_TODAY_STILL_OPEN_OVERNIGHT_SWAP_FIELD_SEPARATE', deals=[D(1001, 11, T(21), IN, BUY, 777, 0.5, 0.0, -0.5, 0.0, -0.25)], positions=[P(11)],
    dw=1, IN=(1, 0.5, 0.0, -0.5, 0.0, -0.25), pos=[(11, 1, 0, 0.5, 0.0, 0.0, -0.5, 0.0, -0.25, 'OPEN_NO_EXIT')], cand=(0.0, -0.5, -0.75))
# ---- ownership
row('MANUAL_TRADE_IS_NOT_COUNTED', deals=[D(2001, 12, T(9), IN, BUY, 0, 0.1, 0.0, -0.1), D(2002, 12, T(10), OUT, SELL, 0, 0.1, 99.0, -0.1)],
    positions=[P(12, magic=0, open_total=0.1, closed_total=0.1, is_open=0)], dw=2, other=2)
row('OTHER_EA_MAGIC_IS_NOT_COUNTED', deals=[D(3001, 13, T(9), IN, SELL, 555, 0.2, 0.0, -0.2)], positions=[P(13, magic=555, open_total=0.2)], dw=1, other=1)
row('ROBOT_AND_MANUAL_MIXED_ONLY_ROBOT_COUNTED',
    deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5), D(2001, 12, T(9, 5), IN, BUY, 0, 0.1, 0.0, -0.1), D(1002, 11, T(10), OUT, SELL, 777, 0.5, 5.0, -0.5)],
    positions=[P(11, closed_total=0.5, is_open=0), P(12, magic=0, open_total=0.1)], dw=3, other=1, IN=(1, 0.5, 0.0, -0.5, 0.0, 0.0), OUT=(1, 0.5, 5.0, -0.5, 0.0, 0.0),
    pos=[(11, 1, 1, 0.5, 0.5, 5.0, -1.0, 0.0, 0.0, 'CLOSED')], cand=(5.0, 4.0, 4.0))
row('MANUAL_CLOSE_OF_A_ROBOT_POSITION_IS_FLAGGED', deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5), D(1002, 11, T(10), OUT, SELL, 0, 0.5, -5.0, -0.5)],
    positions=[P(11, closed_total=0.5, is_open=0)], dw=2, exnot=1, IN=(1, 0.5, 0.0, -0.5, 0.0, 0.0), OUT=(1, 0.5, -5.0, -0.5, 0.0, 0.0),
    pos=[(11, 1, 1, 0.5, 0.5, -5.0, -1.0, 0.0, 0.0, 'CLOSED')], cand=(-5.0, -6.0, -6.0))
row('ZERO_MAGIC_CONFIG_IS_REFUSED', magic=0, verdict='UNKNOWN', why='INVALID_CONFIG')
row('NEGATIVE_MAGIC_CONFIG_IS_REFUSED', magic=-5, verdict='UNKNOWN', why='INVALID_CONFIG')
row('OPENING_DEAL_NOT_FOUND_OWNERSHIP_UNPROVABLE', deals=[D(1002, 11, T(10), OUT, SELL, 777, 0.5, 7.5)], positions=[P(11, known=0, magic=0, closed_total=0.5, is_open=0)],
    verdict='UNKNOWN', why='OWNERSHIP_UNPROVABLE')
row('TRADE_DEAL_OF_AN_UNDESCRIBED_POSITION', deals=[D(1002, 99, T(10), OUT, SELL, 777, 0.5, 7.5)], positions=[], verdict='UNKNOWN', why='OWNERSHIP_UNPROVABLE')
# ---- deduplication
row('DUPLICATE_DEAL_TICKET_COUNTED_ONCE', deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5), D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5)], positions=[P(11)],
    dw=1, dup=1, IN=(1, 0.5, 0.0, -0.5, 0.0, 0.0), pos=[(11, 1, 0, 0.5, 0.0, 0.0, -0.5, 0.0, 0.0, 'OPEN_NO_EXIT')], cand=(0.0, -0.5, -0.5))
row('THREE_COPIES_OF_AN_EXIT_DEAL', deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5)] + [D(1002, 11, T(10), OUT, SELL, 777, 0.5, 5.0, -0.5)] * 3,
    positions=[P(11, closed_total=0.5, is_open=0)], dw=2, dup=2, IN=(1, 0.5, 0.0, -0.5, 0.0, 0.0), OUT=(1, 0.5, 5.0, -0.5, 0.0, 0.0),
    pos=[(11, 1, 1, 0.5, 0.5, 5.0, -1.0, 0.0, 0.0, 'CLOSED')], cand=(5.0, 4.0, 4.0))
row('SAME_TICKET_DIFFERENT_CONTENT', deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5), D(1001, 11, T(9), IN, BUY, 777, 0.4, 0.0, -0.5)], positions=[P(11)],
    verdict='UNKNOWN', why='READ_INCONSISTENT')
# ---- non-trade deals (balance operations) stay apart
row('DEPOSIT_AND_WITHDRAWAL_STAY_APART', deals=[D(4001, 0, T(8), IN, BAL, 0, 0.0, 1000.0), D(4002, 0, T(11), IN, BAL, 0, 0.0, -200.0), D(4003, 0, T(12), IN, CHARGE, 0, 0.0, -1.5, 0.0, 0.0, -0.25)],
    dw=3, nt=(3, 798.5, 0.0, 0.0, -0.25))
row('DEPOSIT_DOES_NOT_ENTER_THE_ROBOT_SUMS', deals=[D(4001, 0, T(8), IN, BAL, 0, 0.0, 5000.0), D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5)], positions=[P(11)],
    dw=2, nt=(1, 5000.0, 0.0, 0.0, 0.0), IN=(1, 0.5, 0.0, -0.5, 0.0, 0.0), pos=[(11, 1, 0, 0.5, 0.0, 0.0, -0.5, 0.0, 0.0, 'OPEN_NO_EXIT')], cand=(0.0, -0.5, -0.5))
row('CREDIT_DEAL_IS_NOT_A_TRADE', deals=[D(4001, 0, T(8), IN, CREDIT, 0, 0.0, 300.0)], dw=1, nt=(1, 300.0, 0.0, 0.0, 0.0))
# ---- time window: boundaries, outside, DST days
row('FIRST_SECOND_OF_THE_DAY_IS_INSIDE_AND_THE_SECOND_BEFORE_IS_OUTSIDE',
    deals=[D(1001, 11, S0 - 1, IN, BUY, 777, 0.5, 0.0, -9.0), D(1002, 11, S0, IN, BUY, 777, 0.1, 0.0, -0.25)], positions=[P(11)],
    dw=1, out=1, IN=(1, 0.1, 0.0, -0.25, 0.0, 0.0), pos=[(11, 1, 0, 0.1, 0.0, 0.0, -0.25, 0.0, 0.0, 'OPEN_NO_EXIT')], cand=(0.0, -0.25, -0.25))
row('LAST_SECOND_OF_THE_DAY_IS_INSIDE_AND_THE_MIDNIGHT_IS_OUTSIDE',
    deals=[D(1001, 11, E0 - 1, IN, BUY, 777, 0.1, 0.0, -0.25), D(1002, 11, E0, IN, BUY, 777, 0.5, 0.0, -9.0)], positions=[P(11)],
    dw=1, out=1, IN=(1, 0.1, 0.0, -0.25, 0.0, 0.0), pos=[(11, 1, 0, 0.1, 0.0, 0.0, -0.25, 0.0, 0.0, 'OPEN_NO_EXIT')], cand=(0.0, -0.25, -0.25))
row('SERVER_OFFSET_ZERO_MEANS_SERVER_TIME_IS_UTC', offset=0, deals=[D(1001, 11, S0 - 1, IN, BUY, 777, 0.5, 0.0, -9.0), D(1002, 11, S0, IN, BUY, 777, 0.1, 0.0, -0.25)], positions=[P(11)],
    dw=1, out=1, IN=(1, 0.1, 0.0, -0.25, 0.0, 0.0), pos=[(11, 1, 0, 0.1, 0.0, 0.0, -0.25, 0.0, 0.0, 'OPEN_NO_EXIT')], cand=(0.0, -0.25, -0.25))
row('SERVER_OFFSET_NEGATIVE', offset=-18000, deals=[D(1001, 11, S0 - 1, IN, BUY, 777, 0.5, 0.0, -9.0), D(1002, 11, S0, IN, BUY, 777, 0.1, 0.0, -0.25)], positions=[P(11)],
    dw=1, out=1, IN=(1, 0.1, 0.0, -0.25, 0.0, 0.0), pos=[(11, 1, 0, 0.1, 0.0, 0.0, -0.25, 0.0, 0.0, 'OPEN_NO_EXIT')], cand=(0.0, -0.25, -0.25))
WIN_DEAL = lambda t: D(1001, 11, t, IN, BUY, 777, 0.1, 0.0, -0.25)
IN_ONE = dict(IN=(1, 0.1, 0.0, -0.25, 0.0, 0.0), pos=[(11, 1, 0, 0.1, 0.0, 0.0, -0.25, 0.0, 0.0, 'OPEN_NO_EXIT')], cand=(0.0, -0.25, -0.25))
row('FALL_BACK_DAY_IS_25_HOURS_A_DEAL_AT_22_30_UTC_IS_INSIDE', utc=U(2026, 10, 25, 12), positions=[P(11, open_total=0.1)], deals=[WIN_DEAL(U(2026, 10, 25, 22, 30))],
    day=20261025, start=U(2026, 10, 24, 22), end=U(2026, 10, 25, 23), dw=1, **IN_ONE)
row('FALL_BACK_DAY_FIRST_SECOND', utc=U(2026, 10, 25, 12), positions=[P(11, open_total=0.1)], deals=[WIN_DEAL(U(2026, 10, 24, 22, 0, 0))],
    day=20261025, start=U(2026, 10, 24, 22), end=U(2026, 10, 25, 23), dw=1, **IN_ONE)
row('FALL_BACK_DAY_AFTER_THE_END_IS_OUTSIDE', utc=U(2026, 10, 25, 12), positions=[P(11, open_total=0.1)], deals=[WIN_DEAL(U(2026, 10, 25, 23, 0, 0))],
    day=20261025, start=U(2026, 10, 24, 22), end=U(2026, 10, 25, 23), out=1)
row('SPRING_FORWARD_DAY_IS_23_HOURS_A_DEAL_AT_22_30_UTC_IS_OUTSIDE', utc=U(2026, 3, 29, 12), positions=[P(11, open_total=0.1)], deals=[WIN_DEAL(U(2026, 3, 29, 22, 30))],
    day=20260329, start=U(2026, 3, 28, 23), end=U(2026, 3, 29, 22), out=1)
row('SPRING_FORWARD_DAY_LAST_SECOND_INSIDE', utc=U(2026, 3, 29, 12), positions=[P(11, open_total=0.1)], deals=[WIN_DEAL(U(2026, 3, 29, 21, 59, 59))],
    day=20260329, start=U(2026, 3, 28, 23), end=U(2026, 3, 29, 22), dw=1, **IN_ONE)
row('WINTER_DAY', utc=U(2026, 12, 10, 12), positions=[P(11, open_total=0.1)], deals=[WIN_DEAL(U(2026, 12, 10, 22, 59, 59)), D(1002, 11, U(2026, 12, 10, 23, 0, 0), IN, BUY, 777, 0.5, 0.0, -9.0)],
    day=20261210, start=U(2026, 12, 9, 23), end=U(2026, 12, 10, 23), dw=1, out=1, **IN_ONE)
# ---- fields: commission, swap, fee, profit are kept separate; no result formula is selected
row('THE_FOUR_MONEY_FIELDS_STAY_SEPARATE_AND_NO_FORMULA_IS_SELECTED',
    deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5, 0.0, -0.25), D(1002, 11, T(10), OUT, SELL, 777, 0.5, 10.0, -0.5, -1.0, -0.25)], positions=[P(11, closed_total=0.5, is_open=0)],
    dw=2, IN=(1, 0.5, 0.0, -0.5, 0.0, -0.25), OUT=(1, 0.5, 10.0, -0.5, -1.0, -0.25), pos=[(11, 1, 1, 0.5, 0.5, 10.0, -1.0, -1.0, -0.5, 'CLOSED')],
    cand=(10.0, 8.0, 7.5))
row('INOUT_AND_OUT_BY_ARE_THEIR_OWN_CLASSES', deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5), D(1002, 11, T(10), OUTBY, SELL, 777, 0.25, 1.0, -0.25), D(1003, 11, T(11), INOUT, SELL, 777, 0.25, 2.0, -0.25), D(1004, 11, T(12), STATE, BUY, 777, 0.0, 0.5)],
    positions=[P(11, closed_total=0.5, is_open=0)], dw=4, IN=(1, 0.5, 0.0, -0.5, 0.0, 0.0), INOUT=(1, 0.25, 2.0, -0.25, 0.0, 0.0), OUT_BY=(1, 0.25, 1.0, -0.25, 0.0, 0.0), OTHER=(1, 0.0, 0.5, 0.0, 0.0, 0.0),
    exnot=0, pos=[(11, 1, 3, 0.5, 0.5, 3.5, -1.0, 0.0, 0.0, 'CLOSED')], cand=(3.5, 2.5, 2.5))
# ---- position volume consistency
row('CLOSED_POSITION_WITH_UNEXPLAINED_VOLUME_IS_UNKNOWN', deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5)], positions=[P(11, closed_total=0.3, is_open=0)], verdict='UNKNOWN', why='INCONSISTENT_POSITION_VOLUMES')
row('OPEN_POSITION_WHOSE_EXITS_COVER_THE_ENTRIES_IS_UNKNOWN', deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5)], positions=[P(11, closed_total=0.5, is_open=1)], verdict='UNKNOWN', why='INCONSISTENT_POSITION_VOLUMES')
row('POSITION_VOLUME_OFF_THE_STEP_GRID_IS_UNKNOWN', deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5)], positions=[P(11, open_total=0.505)], verdict='UNKNOWN', why='INCONSISTENT_POSITION_VOLUMES')
# ---- unreliable reads and unsupported modes
row('API_ERROR', raw=dict(api_ok=0), verdict='UNKNOWN', why='API_ERROR')
row('HISTORY_UNAVAILABLE', raw=dict(hist_ok=0), verdict='UNKNOWN', why='HISTORY_UNAVAILABLE')
row('POSITIONS_UNAVAILABLE', raw=dict(positions_ok=0), verdict='UNKNOWN', why='POSITIONS_UNAVAILABLE')
row('DEAL_LIST_TRUNCATED', raw=dict(deals_trunc=1), verdict='UNKNOWN', why='CAPACITY')
row('POSITION_LIST_TRUNCATED', raw=dict(pos_trunc=1), verdict='UNKNOWN', why='CAPACITY')
row('READ_CHANGED_BETWEEN_TWO_READS', stable=0, verdict='UNKNOWN', why='READ_UNSTABLE')
row('VOLUME_STEP_UNREADABLE', raw=dict(vol_step=0.0), verdict='UNKNOWN', why='SYMBOL_PARAMETERS_UNAVAILABLE')
row('ACCOUNT_MODE_UNREADABLE', raw=dict(margin_ok=0), verdict='UNKNOWN', why='ACCOUNT_MODE_UNAVAILABLE')
row('NETTING_BLOCKS', raw=dict(margin_mode=0), verdict='BLOCK', why='UNSUPPORTED_ACCOUNT_MODE')
row('EXCHANGE_BLOCKS', raw=dict(margin_mode=1), verdict='BLOCK', why='UNSUPPORTED_ACCOUNT_MODE')
row('UNKNOWN_ACCOUNT_MODE_BLOCKS', raw=dict(margin_mode=9), verdict='BLOCK', why='UNSUPPORTED_ACCOUNT_MODE')
row('SERVER_OFFSET_NOT_A_QUARTER_HOUR', offset=3601, verdict='UNKNOWN', why='INVALID_CONFIG')
row('SERVER_OFFSET_TOO_LARGE', offset=54000, verdict='UNKNOWN', why='INVALID_CONFIG')
row('UTC_IN_DAY_INVALID', utc=0, verdict='UNKNOWN', why='INVALID_CONFIG')
row('UTC_IN_DAY_UNSUPPORTED_YEAR', utc=U(2100, 6, 1), verdict='UNKNOWN', why='INVALID_CONFIG')
row('API_ERROR_WINS_OVER_A_FULL_ROBOT_DAY', deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5)], positions=[P(11)], raw=dict(api_ok=0), verdict='UNKNOWN', why='API_ERROR')
row('COMPLETE_ONLY_WHEN_THE_OWNER_ASSERTS_IT', deals=[D(1001, 11, T(9), IN, BUY, 777, 0.5, 0.0, -0.5)], positions=[P(11)], asserted=1,
    dw=1, IN=(1, 0.5, 0.0, -0.5, 0.0, 0.0), pos=[(11, 1, 0, 0.5, 0.0, 0.0, -0.5, 0.0, 0.0, 'OPEN_NO_EXIT')], cand=(0.0, -0.5, -0.5))


def _n(v):
    return repr(float(v))


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t012_history_fixtures.py emit_mql)']
    out.append('#define NROWS %d' % len(ROWS))
    out.append('#define FMAXD %d' % MAXD)
    out.append('#define FMAXP %d' % MAXP)

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    q = lambda v: '"%s"' % v
    arr('string', 'R_NAME', [q(r['name']) for r in ROWS])
    arr('long', 'C_MAGIC', [str(r['magic']) for r in ROWS])
    arr('long', 'C_UTC', [str(r['utc']) for r in ROWS])
    arr('int', 'C_OFFSET', [str(r['offset']) for r in ROWS])
    arr('int', 'C_ASSERTED', [str(r['asserted']) for r in ROWS])
    arr('int', 'R_STABLE', [str(r['stable']) for r in ROWS])
    for nm, k in (('W_APIOK', 'api_ok'), ('W_HISTOK', 'hist_ok'), ('W_POSOK', 'positions_ok'), ('W_MARGINOK', 'margin_ok'), ('W_MODE', 'margin_mode'),
                  ('W_DTRUNC', 'deals_trunc'), ('W_PTRUNC', 'pos_trunc')):
        arr('int', nm, [str(r['raw'][k]) for r in ROWS])
    arr('double', 'W_STEP', [_n(r['raw']['vol_step']) for r in ROWS])
    arr('int', 'D_N', [str(len(r['deals'])) for r in ROWS])
    pad = (0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0)
    flat = [(r['deals'][k] if k < len(r['deals']) else pad) for r in ROWS for k in range(MAXD)]
    arr('long', 'D_TICKET', [str(d[0]) for d in flat])
    arr('long', 'D_POS', [str(d[1]) for d in flat])
    arr('long', 'D_TIME', [str(d[2]) for d in flat])
    arr('int', 'D_ENTRY', [str(d[3]) for d in flat])
    arr('int', 'D_TYPE', [str(d[4]) for d in flat])
    arr('long', 'D_MAGIC', [str(d[5]) for d in flat])
    for i, nm in enumerate(('D_VOL', 'D_PROFIT', 'D_COMM', 'D_SWAP', 'D_FEE')):
        arr('double', nm, [_n(d[6 + i]) for d in flat])
    arr('int', 'P_N', [str(len(r['positions'])) for r in ROWS])
    padp = (0, 0, 0, 0.0, 0.0, 0)
    fp = [(r['positions'][k] if k < len(r['positions']) else padp) for r in ROWS for k in range(MAXP)]
    arr('long', 'P_ID', [str(p[0]) for p in fp])
    arr('int', 'P_KNOWN', [str(p[1]) for p in fp])
    arr('long', 'P_MAGIC', [str(p[2]) for p in fp])
    arr('double', 'P_OPENV', [_n(p[3]) for p in fp])
    arr('double', 'P_CLOSEDV', [_n(p[4]) for p in fp])
    arr('int', 'P_ISOPEN', [str(p[5]) for p in fp])
    arr('string', 'X_VERDICT', [q(r['verdict']) for r in ROWS])
    arr('string', 'X_WHY', [q(r['why']) for r in ROWS])
    arr('string', 'X_FACTS', [q(canon(r['exp']) if r['verdict'] == 'READY' else '') for r in ROWS])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
