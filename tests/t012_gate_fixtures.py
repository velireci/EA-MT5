"""T012 integration scenarios for the preview gate: inputs as the PREVIEW supplies them (sentinels -1 / false = unknown) -> daily evaluation
-> final decision together with a loss check and a T007 permit. Hand-written expectations. Base: 2026-07-15 09:00 UTC (Tirane day 20260715)."""
from datetime import datetime, timezone

ROWS = []


def U(y, mo, d, h=0, mi=0, s=0):
    return int(datetime(y, mo, d, h, mi, s, tzinfo=timezone.utc).timestamp())


BASE = dict(src=1, utc=U(2026, 7, 15, 9), day=20260715, bal=10000.0, known=1, res=0.0, trades=0, wins=0, losses=0, maxt=3, loss_ok=1, permit=1)


def row(name, evaluated, allowed, reasons, final, cancel=0, **kw):
    r = dict(BASE)
    r.update(kw)
    r.update(name=name, evaluated=int(evaluated), allowed=int(allowed), reasons='|'.join(reasons), final=int(final), cancel=int(cancel))
    ROWS.append(r)


# ---- MANUAL: nothing evaluated, behaviour as before for every combination of the existing checks
row('MANUAL_BOTH_OK_STAYS_OK', 0, 1, [], 1, src=0)
row('MANUAL_PERMIT_BLOCK_STAYS_BLOCK', 0, 1, [], 0, src=0, permit=0)
row('MANUAL_LOSS_CHECK_FAIL_STAYS_BLOCK', 0, 1, [], 0, src=0, loss_ok=0)
row('MANUAL_IGNORES_A_LIMIT_BREACHING_FIGURE', 0, 1, [], 1, src=0, wins=3, trades=5, res=-900.0)
row('MANUAL_IGNORES_GARBAGE_FIGURES', 0, 1, [], 1, src=0, bal=-1.0, trades=-1, wins=-1, losses=-1, known=0, day=0, maxt=-1)
# ---- DAILY_SNAPSHOT clear: the final result stays the existing one
row('SNAPSHOT_CLEAR_BOTH_OK', 1, 1, [], 1)
row('SNAPSHOT_CLEAR_PERMIT_BLOCK_STILL_BLOCKS', 1, 1, [], 0, permit=0)
row('SNAPSHOT_CLEAR_LOSS_CHECK_FAIL_STILL_BLOCKS', 1, 1, [], 0, loss_ok=0)
# ---- a daily BLOCK must reach the final result even when everything else is OK
row('DAILY_WIN_STOP_BLOCKS_THE_FINAL_RESULT', 1, 0, ['DAILY_WIN_STOP'], 0, cancel=1, trades=1, wins=1, res=50.0)
row('DAILY_STREAK_BLOCKS_THE_FINAL_RESULT', 1, 0, ['CONSECUTIVE_LOSSES_STOP'], 0, cancel=1, trades=2, losses=2, res=-100.0)
row('DAILY_LOSS_BLOCKS_THE_FINAL_RESULT', 1, 0, ['DAILY_LOSS_LIMIT'], 0, cancel=1, trades=1, res=-250.0)
row('DAILY_LOSS_AT_THE_LINE_BLOCKS', 1, 0, ['DAILY_LOSS_LIMIT'], 0, cancel=1, trades=1, res=-200.0)
row('DAILY_LOSS_JUST_BELOW_THE_LINE_DOES_NOT_BLOCK', 1, 1, [], 1, trades=1, res=-199.99)
row('DAILY_TRADE_LIMIT_BLOCKS_THE_FINAL_RESULT', 1, 0, ['MAX_TRADES_REACHED'], 0, cancel=1, trades=3, maxt=3)
row('DAILY_COMBINED_BLOCKS_THE_FINAL_RESULT', 1, 0, ['DAILY_WIN_STOP', 'DAILY_LOSS_LIMIT'], 0, cancel=1, trades=2, wins=1, res=-300.0)
# ---- the 2 vs 3 limit stays an unset input by default
row('DEFAULT_TRADE_LIMIT_UNSET_BLOCKS_WITHOUT_A_DAILY_LIMIT', 1, 0, ['POLICY_UNSET:max_trades_per_day'], 0, cancel=0, maxt=-1)
row('UNSET_LIMIT_WITH_A_PROVEN_WIN_STOP', 1, 0, ['DAILY_WIN_STOP', 'POLICY_UNSET:max_trades_per_day'], 0, cancel=1, maxt=-1, trades=1, wins=1)
# ---- the defaults of the preview inputs (everything unknown) block and invent no limit
row('ALL_PREVIEW_DEFAULTS_BLOCK', 1, 0, ['INVALID_SNAPSHOT:snapshot_day', 'INVALID_SNAPSHOT:balance_start', 'INVALID_SNAPSHOT:closed_result',
    'INVALID_SNAPSHOT:trades_today', 'INVALID_SNAPSHOT:wins_today', 'INVALID_SNAPSHOT:consecutive_losses'], 0, day=0, bal=-1.0, known=0, trades=-1, wins=-1, losses=-1, maxt=-1)
row('UNKNOWN_RESULT_IS_INVALID_NOT_ZERO', 1, 0, ['INVALID_SNAPSHOT:closed_result'], 0, known=0, res=0.0)
row('UNKNOWN_BALANCE_IS_INVALID', 1, 0, ['INVALID_SNAPSHOT:balance_start'], 0, bal=-1.0)
row('UNKNOWN_TRADES_IS_INVALID', 1, 0, ['INVALID_SNAPSHOT:trades_today'], 0, trades=-1)
row('UNKNOWN_WINS_IS_INVALID', 1, 0, ['INVALID_SNAPSHOT:wins_today'], 0, wins=-1)
row('UNKNOWN_LOSS_STREAK_IS_INVALID', 1, 0, ['INVALID_SNAPSHOT:consecutive_losses'], 0, losses=-1)
row('LIMIT_ZERO_IS_INVALID_NOT_UNSET', 1, 0, ['INVALID_SNAPSHOT:max_trades_per_day'], 0, maxt=0)
row('ABSURD_COUNTER_IS_INVALID', 1, 0, ['INVALID_SNAPSHOT:trades_today'], 0, trades=2000000)
row('ABSURD_LIMIT_IS_INVALID', 1, 0, ['INVALID_SNAPSHOT:max_trades_per_day'], 0, maxt=2000000)
row('INVALID_FIGURES_HIDE_A_PROVEN_LIMIT', 1, 0, ['INVALID_SNAPSHOT:balance_start', 'INCONSISTENT_COUNTERS:wins_plus_losses_exceed_trades'], 0, bal=-1.0, wins=2, trades=3, losses=2, res=-9999.0)
# ---- the day: stale snapshot / next day / midnight
row('STALE_SNAPSHOT_BLOCKS', 1, 0, ['STALE_SNAPSHOT_DAY'], 0, day=20260714)
row('NEXT_DAY_SNAPSHOT_BLOCKS', 1, 0, ['STALE_SNAPSHOT_DAY'], 0, day=20260716)
row('MIDNIGHT_NEW_DAY_FRESH_SNAPSHOT_CLEAR', 1, 1, [], 1, utc=U(2026, 7, 14, 22, 0, 0), day=20260715)
row('MIDNIGHT_OLD_DAY_SNAPSHOT_STALE', 1, 0, ['STALE_SNAPSHOT_DAY'], 0, utc=U(2026, 7, 14, 22, 0, 0), day=20260714)
row('INVALID_UTC_BLOCKS_AND_INVENTS_NO_LIMIT', 1, 0, ['INVALID_UTC'], 0, utc=0, wins=1, trades=1)
# ---- counters contradictory
row('CONTRADICTORY_COUNTERS_BLOCK', 1, 0, ['INCONSISTENT_COUNTERS:wins_exceed_trades'], 0, trades=1, wins=2)
row('CLEAR_SNAPSHOT_AND_NO_REASON_TEXT', 1, 1, [], 1, trades=2)


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t012_gate_fixtures.py emit_mql)']
    out.append('#define NROWS %d' % len(ROWS))

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    q = lambda v: '"%s"' % v
    arr('string', 'R_NAME', [q(r['name']) for r in ROWS])
    arr('int', 'R_SRC', [str(r['src']) for r in ROWS])
    arr('long', 'R_UTC', [str(r['utc']) for r in ROWS])
    arr('int', 'R_DAY', [str(r['day']) for r in ROWS])
    arr('double', 'R_BAL', [repr(float(r['bal'])) for r in ROWS])
    arr('int', 'R_KNOWN', [str(r['known']) for r in ROWS])
    arr('double', 'R_RES', [repr(float(r['res'])) for r in ROWS])
    arr('long', 'R_TRADES', [str(r['trades']) for r in ROWS])
    arr('long', 'R_WINS', [str(r['wins']) for r in ROWS])
    arr('long', 'R_LOSSES', [str(r['losses']) for r in ROWS])
    arr('long', 'R_MAXT', [str(r['maxt']) for r in ROWS])
    arr('int', 'R_LOSSOK', [str(r['loss_ok']) for r in ROWS])
    arr('int', 'R_PERMIT', [str(r['permit']) for r in ROWS])
    arr('int', 'X_EVAL', [str(r['evaluated']) for r in ROWS])
    arr('int', 'X_ALLOWED', [str(r['allowed']) for r in ROWS])
    arr('string', 'X_REASONS', [q(r['reasons']) for r in ROWS])
    arr('int', 'X_FINAL', [str(r['final']) for r in ROWS])
    arr('int', 'X_CANCEL', [str(r['cancel']) for r in ROWS])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
