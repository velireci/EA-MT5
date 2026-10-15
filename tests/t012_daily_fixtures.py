"""T012 hand-written scenarios. Base: 2026-07-15 09:00 UTC = 11:00 Tirane (offset +2h, DST), Tirane day 20260715, balance at the start of the day
10000.00, so the daily loss limit is 200.00. emit_mql() produces the flat data block of src/tests/T012_DailyLimitsTest.mq5 (equality is tested)."""
from datetime import datetime, timezone

ROWS = []


def U(y, mo, d, h=0, mi=0, s=0):
    return int(datetime(y, mo, d, h, mi, s, tzinfo=timezone.utc).timestamp())


BASE = dict(utc=U(2026, 7, 15, 9), snap=20260715, bal=10000.0, res=0.0, trades=0, wins=0, loss=0, mset=1, mtr=3)
UNSET = 'POLICY_UNSET:max_trades_per_day'


LIMITS = ('DAILY_WIN_STOP', 'CONSECUTIVE_LOSSES_STOP', 'DAILY_LOSS_LIMIT', 'MAX_TRADES_REACHED')
INVALIDS = ('INVALID', 'STALE', 'UNSUPPORTED', 'INCONSISTENT')


def row(name, allowed=0, reasons=(), cancel=None, day=20260715, **kw):
    """cancel (and daily_limit_reached) is expected True only when a limit reason is present and no validity reason is (written out, not computed
    from the module): pass cancel= to state it explicitly."""
    r = dict(BASE)
    r.update(kw)
    reasons = list(reasons)
    if cancel is None:
        cancel = any(x in LIMITS for x in reasons) and not any(x.startswith(INVALIDS) for x in reasons)
    r.update(name=name, allowed=int(allowed), reasons=reasons, primary=reasons[0] if reasons else '', cancel=int(bool(cancel)), day=day)
    ROWS.append(r)


# ---- clear and each stop
row('CLEAR_NOTHING_HAPPENED', allowed=1)
row('CLEAR_TWO_TRADES_NO_STOP', allowed=1, trades=2)
row('ONE_LOSS_IS_NOT_A_STREAK_STOP', allowed=1, trades=1, loss=1, res=-50.0)
row('POSITIVE_RESULT_WITHOUT_A_COUNTED_WIN_IS_NOT_JUDGED', allowed=1, trades=1, res=300.0)
row('ONE_WIN_STOPS_THE_DAY', reasons=['DAILY_WIN_STOP'], trades=1, wins=1, res=50.0)
row('TWO_WINS_STOP_THE_DAY', reasons=['DAILY_WIN_STOP'], trades=2, wins=2, res=90.0)
row('TWO_CONSECUTIVE_LOSSES_STOP', reasons=['CONSECUTIVE_LOSSES_STOP'], trades=2, loss=2, res=-100.0)
row('THREE_CONSECUTIVE_LOSSES_STOP', reasons=['CONSECUTIVE_LOSSES_STOP'], trades=3, loss=3, res=-100.0, mtr=5)
# ---- the 2% line: below, at, after
row('LOSS_BELOW_2_PERCENT', allowed=1, trades=1, loss=1, res=-199.99)
row('LOSS_AT_2_PERCENT_BLOCKS', reasons=['DAILY_LOSS_LIMIT'], trades=1, res=-200.0)
row('LOSS_AFTER_2_PERCENT_BLOCKS', reasons=['DAILY_LOSS_LIMIT'], trades=1, res=-200.01)
row('LOSS_FAR_BEYOND_2_PERCENT', reasons=['DAILY_LOSS_LIMIT'], trades=2, res=-900.0)
row('LOSS_LIMIT_USES_THE_START_OF_DAY_BALANCE', allowed=1, bal=20000.0, trades=1, res=-300.0)
row('LOSS_LIMIT_FRACTIONAL_BALANCE_BELOW', allowed=1, bal=12345.67, trades=1, res=-246.90)
row('LOSS_LIMIT_FRACTIONAL_BALANCE_AT', reasons=['DAILY_LOSS_LIMIT'], bal=12345.67, trades=1, res=-246.9134)
row('PROFIT_NEVER_BLOCKS_BY_LOSS_RULE', allowed=1, trades=1, res=5000.0)
# ---- the supplied trade limit (2 versus 3 is not decided here)
row('TRADES_BELOW_THE_SUPPLIED_LIMIT', allowed=1, trades=2, mtr=3)
row('TRADES_AT_THE_SUPPLIED_LIMIT', reasons=['MAX_TRADES_REACHED'], trades=3, mtr=3)
row('TRADES_ABOVE_THE_SUPPLIED_LIMIT', reasons=['MAX_TRADES_REACHED'], trades=4, mtr=3)
row('SUPPLIED_LIMIT_2_REACHED_AT_2', reasons=['MAX_TRADES_REACHED'], trades=2, mtr=2)
row('SUPPLIED_LIMIT_3_NOT_REACHED_AT_2', allowed=1, trades=2, mtr=3)
row('SUPPLIED_LIMIT_1_REACHED_AT_1', reasons=['MAX_TRADES_REACHED'], trades=1, mtr=1)
# ---- missing policy: blocked, but no daily limit is invented
row('POLICY_UNSET_BLOCKS_WITHOUT_A_DAILY_LIMIT', reasons=[UNSET], cancel=0, mset=0, mtr=0)
row('POLICY_UNSET_WITH_A_PROVEN_WIN_STOP', reasons=['DAILY_WIN_STOP', UNSET], cancel=1, mset=0, mtr=0, trades=1, wins=1)
row('POLICY_UNSET_WITH_A_PROVEN_LOSS_LIMIT', reasons=['DAILY_LOSS_LIMIT', UNSET], cancel=1, mset=0, mtr=0, trades=1, res=-250.0)
# ---- combined causes, stable order
row('WIN_AND_LOSS_LIMIT', reasons=['DAILY_WIN_STOP', 'DAILY_LOSS_LIMIT'], trades=2, wins=1, res=-300.0)
row('WIN_AND_TRADE_LIMIT', reasons=['DAILY_WIN_STOP', 'MAX_TRADES_REACHED'], trades=3, wins=1, res=100.0)
row('STREAK_LOSS_AND_TRADE_LIMIT', reasons=['CONSECUTIVE_LOSSES_STOP', 'DAILY_LOSS_LIMIT', 'MAX_TRADES_REACHED'], trades=3, loss=2, res=-210.0)
row('ALL_FOUR_LIMITS', reasons=['DAILY_WIN_STOP', 'CONSECUTIVE_LOSSES_STOP', 'DAILY_LOSS_LIMIT', 'MAX_TRADES_REACHED'], trades=3, wins=1, loss=2, res=-210.0)
row('ALL_FOUR_LIMITS_AND_NO_POLICY', reasons=['DAILY_WIN_STOP', 'CONSECUTIVE_LOSSES_STOP', 'DAILY_LOSS_LIMIT', UNSET], mset=0, mtr=0, trades=3, wins=1, loss=2, res=-210.0)
# ---- invalid / unknown / contradictory input: nothing is judged, no cancel flag
row('INVALID_BALANCE_ZERO', reasons=['INVALID_SNAPSHOT:balance_start'], bal=0.0, trades=1, wins=1)
row('INVALID_BALANCE_NEGATIVE', reasons=['INVALID_SNAPSHOT:balance_start'], bal=-10000.0)
row('INVALID_TRADES_NEGATIVE', reasons=['INVALID_SNAPSHOT:trades_today'], trades=-1)
row('INVALID_WINS_NEGATIVE', reasons=['INVALID_SNAPSHOT:wins_today'], wins=-1)
row('INVALID_LOSS_STREAK_NEGATIVE', reasons=['INVALID_SNAPSHOT:consecutive_losses'], loss=-1)
row('INVALID_LIMIT_ZERO', reasons=['INVALID_SNAPSHOT:max_trades_per_day'], mtr=0)
row('INVALID_LIMIT_NEGATIVE', reasons=['INVALID_SNAPSHOT:max_trades_per_day'], mtr=-3)
row('INVALID_COUNTER_ABSURD', reasons=['INVALID_SNAPSHOT:trades_today'], trades=1000000)
row('INVALID_UTC_ZERO', reasons=['INVALID_UTC'], utc=0, day=0)
row('INVALID_UTC_NEGATIVE', reasons=['INVALID_UTC'], utc=-5, day=0)
row('UNSUPPORTED_YEAR_2100', reasons=['UNSUPPORTED_YEAR'], utc=U(2100, 6, 1), day=0)
row('INVALID_SNAPSHOT_DAY_FORMAT', reasons=['INVALID_SNAPSHOT:snapshot_day'], snap=0)
row('INCONSISTENT_WINS_EXCEED_TRADES', reasons=['INCONSISTENT_COUNTERS:wins_exceed_trades'], trades=1, wins=2)
row('INCONSISTENT_STREAK_EXCEEDS_TRADES', reasons=['INCONSISTENT_COUNTERS:losses_exceed_trades'], trades=2, loss=3)
row('INCONSISTENT_WINS_PLUS_STREAK', reasons=['INCONSISTENT_COUNTERS:wins_plus_losses_exceed_trades'], trades=2, wins=1, loss=2)
row('INVALID_INPUT_HIDES_A_PROVEN_LIMIT', reasons=['INVALID_SNAPSHOT:balance_start'], bal=-1.0, trades=3, wins=1, loss=2, res=-9999.0)
row('SEVERAL_INVALID_REASONS_IN_A_STABLE_ORDER', reasons=['INVALID_SNAPSHOT:balance_start', 'INVALID_SNAPSHOT:trades_today', 'INVALID_SNAPSHOT:wins_today',
    'INVALID_SNAPSHOT:consecutive_losses', 'INVALID_SNAPSHOT:max_trades_per_day'], bal=0.0, trades=-1, wins=-1, loss=-1, mtr=0)
row('STALE_AND_INVALID_TOGETHER', reasons=['STALE_SNAPSHOT_DAY', 'INVALID_SNAPSHOT:balance_start'], snap=20260714, bal=0.0)
# ---- the Tirane day: snapshot of another day, midnight, DST (summer midnight = 22:00 UTC, winter = 23:00 UTC)
row('SNAPSHOT_OF_THE_NEXT_DAY', reasons=['STALE_SNAPSHOT_DAY'], snap=20260716)
row('SNAPSHOT_OF_THE_PREVIOUS_DAY', reasons=['STALE_SNAPSHOT_DAY'], snap=20260714)
row('SUMMER_LAST_SECOND_OF_THE_DAY', allowed=1, utc=U(2026, 7, 14, 21, 59, 59), snap=20260714, day=20260714)
row('SUMMER_LAST_SECOND_WITH_THE_NEXT_DAY_SNAPSHOT', reasons=['STALE_SNAPSHOT_DAY'], utc=U(2026, 7, 14, 21, 59, 59), snap=20260715, day=20260714)
row('SUMMER_MIDNIGHT_NEW_DAY', allowed=1, utc=U(2026, 7, 14, 22, 0, 0), snap=20260715, day=20260715)
row('SUMMER_MIDNIGHT_OLD_SNAPSHOT_IS_STALE', reasons=['STALE_SNAPSHOT_DAY'], utc=U(2026, 7, 14, 22, 0, 0), snap=20260714, day=20260715)
row('WINTER_LAST_SECOND_OF_THE_DAY', allowed=1, utc=U(2026, 12, 10, 22, 59, 59), snap=20261210, day=20261210)
row('WINTER_MIDNIGHT_NEW_DAY', allowed=1, utc=U(2026, 12, 10, 23, 0, 0), snap=20261211, day=20261211)
row('WINTER_MIDNIGHT_OLD_SNAPSHOT_IS_STALE', reasons=['STALE_SNAPSHOT_DAY'], utc=U(2026, 12, 10, 23, 0, 0), snap=20261210, day=20261211)
row('SPRING_FORWARD_DAY_START', allowed=1, utc=U(2026, 3, 28, 23, 0, 0), snap=20260329, day=20260329)
row('SPRING_FORWARD_BEFORE_THE_SWITCH', allowed=1, utc=U(2026, 3, 29, 0, 59, 59), snap=20260329, day=20260329)
row('SPRING_FORWARD_AFTER_THE_SWITCH', allowed=1, utc=U(2026, 3, 29, 1, 0, 0), snap=20260329, day=20260329)
row('SPRING_FORWARD_DAY_END', allowed=1, utc=U(2026, 3, 29, 21, 59, 59), snap=20260329, day=20260329)
row('SPRING_FORWARD_NEXT_DAY', allowed=1, utc=U(2026, 3, 29, 22, 0, 0), snap=20260330, day=20260330)
row('SPRING_FORWARD_NEXT_DAY_OLD_SNAPSHOT_IS_STALE', reasons=['STALE_SNAPSHOT_DAY'], utc=U(2026, 3, 29, 22, 0, 0), snap=20260329, day=20260330)
row('FALL_BACK_DAY_START', allowed=1, utc=U(2026, 10, 24, 22, 0, 0), snap=20261025, day=20261025)
row('FALL_BACK_BEFORE_THE_SWITCH', allowed=1, utc=U(2026, 10, 25, 0, 59, 59), snap=20261025, day=20261025)
row('FALL_BACK_REPEATED_HOUR', allowed=1, utc=U(2026, 10, 25, 1, 0, 0), snap=20261025, day=20261025)
row('FALL_BACK_DAY_END', allowed=1, utc=U(2026, 10, 25, 22, 59, 59), snap=20261025, day=20261025)
row('FALL_BACK_NEXT_DAY', allowed=1, utc=U(2026, 10, 25, 23, 0, 0), snap=20261026, day=20261026)
row('FALL_BACK_NEXT_DAY_OLD_SNAPSHOT_IS_STALE', reasons=['STALE_SNAPSHOT_DAY'], utc=U(2026, 10, 25, 23, 0, 0), snap=20261025, day=20261026)
row('LIMIT_REACHED_AT_THE_LAST_SECOND_OF_THE_DAY', reasons=['MAX_TRADES_REACHED'], utc=U(2026, 7, 14, 21, 59, 59), snap=20260714, day=20260714, trades=3)
row('NEW_DAY_NEW_SNAPSHOT_HAS_NO_YESTERDAYS_STOP', allowed=1, utc=U(2026, 7, 14, 22, 0, 0), snap=20260715, day=20260715, trades=0)


def _n(v):
    return repr(float(v))


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t012_daily_fixtures.py emit_mql)']
    out.append('#define NROWS %d' % len(ROWS))

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    q = lambda v: '"%s"' % v
    arr('string', 'R_NAME', [q(r['name']) for r in ROWS])
    arr('long', 'R_UTC', [str(r['utc']) for r in ROWS])
    arr('int', 'R_SNAP', [str(r['snap']) for r in ROWS])
    arr('double', 'R_BAL', [_n(r['bal']) for r in ROWS])
    arr('double', 'R_RES', [_n(r['res']) for r in ROWS])
    arr('int', 'R_TRADES', [str(r['trades']) for r in ROWS])
    arr('int', 'R_WINS', [str(r['wins']) for r in ROWS])
    arr('int', 'R_LOSS', [str(r['loss']) for r in ROWS])
    arr('int', 'R_MSET', [str(r['mset']) for r in ROWS])
    arr('int', 'R_MTR', [str(r['mtr']) for r in ROWS])
    arr('int', 'X_ALLOWED', [str(r['allowed']) for r in ROWS])
    arr('string', 'X_PRIMARY', [q(r['primary']) for r in ROWS])
    arr('string', 'X_REASONS', [q('|'.join(r['reasons'])) for r in ROWS])
    arr('int', 'X_CANCEL', [str(r['cancel']) for r in ROWS])
    arr('int', 'X_DAY', [str(r['day']) for r in ROWS])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
