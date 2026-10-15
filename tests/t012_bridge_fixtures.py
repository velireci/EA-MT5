"""T012 bridge scenarios: history FACTS + explicit balance / policies / classified counts -> DL_Check. Hand-written expectations.
Base: 2026-07-15 09:00 UTC (Tirane day 20260715), balance 10000 (2% = 200), 1 robot position, READY + complete, all policies defined, limit 3.
Verdict codes: 0 READY, 1 UNKNOWN, 2 BLOCK, 7 not a verdict."""
from datetime import datetime, timezone

ROWS = []
VERDICT = {0: 'READY', 1: 'UNKNOWN', 2: 'BLOCK', 7: '?'}


def U(y, mo, d, h=0, mi=0, s=0):
    return int(datetime(y, mo, d, h, mi, s, tzinfo=timezone.utc).timestamp())


BASE = dict(verdict=0, fday=20260715, complete=1, npos=1, deals=3, cp=-50.0, cpcs=-60.0, cpcsf=-65.0, nanp=0, utc=U(2026, 7, 15, 9),
            bknown=1, bday=20260715, bamt=10000.0, formula='PROFIT', classif='CALLER_CLASSIFIED', trades=1, wins=0, losses=0, maxset=1, maxt=3)


def row(name, allowed, reasons, called, closed=None, cancel=0, **kw):
    r = dict(BASE)
    r.update(kw)
    r.update(name=name, allowed=int(allowed), reasons='|'.join(reasons), called=int(called), closed=(0.0 if closed is None else closed), cancel=int(cancel))
    ROWS.append(r)


# ---- everything defined: DL_Check decides and the result is propagated
row('CLEAR_DAY_PROFIT_FORMULA', 1, [], 1, closed=-50.0)
row('CLEAR_DAY_NO_TRADES_NO_POSITIONS', 1, [], 1, closed=0.0, npos=0, trades=0, cp=0.0, cpcs=0.0, cpcsf=0.0)
row('FORMULA_PROFIT_DOES_NOT_REACH_THE_LINE', 1, [], 1, closed=-150.0, cp=-150.0, cpcs=-199.0, cpcsf=-205.0)
row('FORMULA_PCS_JUST_ABOVE_THE_LINE', 1, [], 1, closed=-199.0, cp=-150.0, cpcs=-199.0, cpcsf=-205.0, formula='PROFIT_COMMISSION_SWAP')
row('FORMULA_PCSF_REACHES_THE_LINE', 0, ['DAILY_LOSS_LIMIT'], 1, closed=-205.0, cancel=1, cp=-150.0, cpcs=-199.0, cpcsf=-205.0, formula='PROFIT_COMMISSION_SWAP_FEE')
row('FORMULA_PROFIT_REACHES_THE_LINE', 0, ['DAILY_LOSS_LIMIT'], 1, closed=-250.0, cancel=1, cp=-250.0, cpcs=-120.0, cpcsf=-110.0)
row('WIN_STOP_PROPAGATED', 0, ['DAILY_WIN_STOP'], 1, closed=40.0, cancel=1, cp=40.0, wins=1)
row('CONSECUTIVE_LOSSES_PROPAGATED', 0, ['CONSECUTIVE_LOSSES_STOP'], 1, closed=-100.0, cancel=1, cp=-100.0, trades=2, losses=2)
row('TRADE_LIMIT_PROPAGATED', 0, ['MAX_TRADES_REACHED'], 1, closed=-50.0, cancel=1, trades=3)
row('TRADE_LIMIT_TWO_IS_AN_INPUT', 0, ['MAX_TRADES_REACHED'], 1, closed=-50.0, cancel=1, trades=2, maxt=2)
row('TRADE_LIMIT_UNSET_BLOCKS_WITHOUT_A_LIMIT', 0, ['POLICY_UNSET:max_trades_per_day'], 1, closed=-50.0, maxset=0, maxt=0)
row('TRADE_LIMIT_UNSET_WITH_A_PROVEN_WIN_STOP', 0, ['DAILY_WIN_STOP', 'POLICY_UNSET:max_trades_per_day'], 1, closed=40.0, cancel=1, cp=40.0, wins=1, maxset=0, maxt=0)
row('COMBINED_LIMITS_PROPAGATED', 0, ['DAILY_WIN_STOP', 'DAILY_LOSS_LIMIT'], 1, closed=-300.0, cancel=1, cp=-300.0, trades=2, wins=1)
row('DEALS_ARE_NOT_TRADES', 1, [], 1, closed=-50.0, deals=7, trades=1, maxt=2)
row('MANY_POSITIONS_DO_NOT_SET_THE_TRADE_COUNT', 1, [], 1, closed=-50.0, npos=5, trades=1, maxt=2)
# ---- the day
row('FACTS_OF_ANOTHER_DAY_ARE_STALE', 0, ['STALE_SNAPSHOT_DAY'], 1, closed=-50.0, fday=20260714, bday=20260714)
row('FACTS_OF_THE_NEXT_DAY_ARE_STALE', 0, ['STALE_SNAPSHOT_DAY'], 1, closed=-50.0, fday=20260716, bday=20260716)
row('MIDNIGHT_FACTS_OF_THE_NEW_DAY_ARE_FRESH', 1, [], 1, closed=-50.0, utc=U(2026, 7, 14, 22), fday=20260715, bday=20260715)
row('MIDNIGHT_FACTS_OF_THE_OLD_DAY_ARE_STALE', 0, ['STALE_SNAPSHOT_DAY'], 1, closed=-50.0, utc=U(2026, 7, 14, 22), fday=20260714, bday=20260714)
row('INVALID_UTC_IS_REPORTED_BY_THE_DAILY_CHECK', 0, ['INVALID_UTC'], 1, closed=-50.0, utc=0)
row('BALANCE_OF_ANOTHER_DAY_BLOCKS', 0, ['BALANCE_DAY_MISMATCH'], 0, bday=20260714)
row('BALANCE_DAY_ZERO_BLOCKS', 0, ['BALANCE_DAY_MISMATCH'], 0, bday=0)
row('BALANCE_AND_FACTS_BOTH_STALE_REACH_THE_DAILY_CHECK', 0, ['STALE_SNAPSHOT_DAY'], 1, closed=-50.0, fday=20260714, bday=20260714)
# ---- individual gaps: nothing is invented, no limit is proven from missing data
row('HISTORY_UNKNOWN_BLOCKS', 0, ['HISTORY_NOT_READY:UNKNOWN'], 0, verdict=1)
row('HISTORY_BLOCK_BLOCKS', 0, ['HISTORY_NOT_READY:BLOCK'], 0, verdict=2)
row('HISTORY_INVALID_VERDICT_BLOCKS', 0, ['HISTORY_NOT_READY:?'], 0, verdict=7)
row('HISTORY_INCOMPLETE_BLOCKS', 0, ['HISTORY_INCOMPLETE'], 0, complete=0)
row('BALANCE_START_UNSET_BLOCKS', 0, ['BALANCE_START_UNSET'], 0, bknown=0)
row('BALANCE_START_UNSET_IGNORES_AMOUNT_AND_DAY', 0, ['BALANCE_START_UNSET'], 0, bknown=0, bamt=10000.0, bday=20260715)
row('FORMULA_UNSET_BLOCKS', 0, ['POLICY_UNSET:result_formula'], 0, formula='UNSET')
row('FORMULA_UNSUPPORTED_BLOCKS', 0, ['POLICY_UNSUPPORTED:result_formula'], 0, formula='NET_PROFIT')
row('FORMULA_NAME_IS_CASE_SENSITIVE', 0, ['POLICY_UNSUPPORTED:result_formula'], 0, formula='profit')
row('FORMULA_EMPTY_IS_UNSUPPORTED', 0, ['POLICY_UNSUPPORTED:result_formula'], 0, formula='')
row('CLASSIFICATION_UNSET_BLOCKS', 0, ['POLICY_UNSET:trade_classification'], 0, classif='UNSET')
row('CLASSIFICATION_UNSUPPORTED_BLOCKS', 0, ['POLICY_UNSUPPORTED:trade_classification'], 0, classif='DEALS_AS_TRADES')
row('CLASSIFICATION_EMPTY_IS_UNSUPPORTED', 0, ['POLICY_UNSUPPORTED:trade_classification'], 0, classif='')
row('TRADES_WITHOUT_ANY_ROBOT_POSITION_CONTRADICT_THE_FACTS', 0, ['CLASSIFICATION_CONTRADICTS_FACTS:trades_without_positions'], 0, npos=0, trades=1)
row('ZERO_TRADES_WITHOUT_POSITIONS_IS_FINE', 1, [], 1, closed=-50.0, npos=0, trades=0)
# ---- combined gaps (all listed, fixed order, daily check not called)
row('UNKNOWN_AND_NO_BALANCE', 0, ['HISTORY_NOT_READY:UNKNOWN', 'BALANCE_START_UNSET'], 0, verdict=1, bknown=0)
row('INCOMPLETE_AND_BALANCE_OF_ANOTHER_DAY', 0, ['HISTORY_INCOMPLETE', 'BALANCE_DAY_MISMATCH'], 0, complete=0, bday=20260714)
row('UNKNOWN_HIDES_THE_FACTS_DEPENDENT_CHECKS', 0, ['HISTORY_NOT_READY:UNKNOWN'], 0, verdict=1, bday=20260714, npos=0, trades=3)
row('ALL_POLICIES_UNSET_ON_A_READY_COMPLETE_HISTORY', 0, ['BALANCE_START_UNSET', 'POLICY_UNSET:result_formula', 'POLICY_UNSET:trade_classification'], 0,
    bknown=0, formula='UNSET', classif='UNSET')
row('EVERYTHING_MISSING', 0, ['HISTORY_NOT_READY:BLOCK', 'BALANCE_START_UNSET', 'POLICY_UNSET:result_formula', 'POLICY_UNSET:trade_classification'], 0,
    verdict=2, bknown=0, formula='UNSET', classif='UNSET', complete=0)
row('INCOMPLETE_AND_BOTH_POLICIES_UNSUPPORTED', 0, ['HISTORY_INCOMPLETE', 'POLICY_UNSUPPORTED:result_formula', 'POLICY_UNSUPPORTED:trade_classification'], 0,
    complete=0, formula='X', classif='Y')
row('MISSING_DATA_DO_NOT_PROVE_A_LIMIT', 0, ['POLICY_UNSET:result_formula'], 0, formula='UNSET', wins=1, trades=1, cp=-9999.0, losses=2)
row('INCOMPLETE_HISTORY_WITH_A_LOSS_BEYOND_THE_LINE_PROVES_NOTHING', 0, ['HISTORY_INCOMPLETE'], 0, complete=0, cp=-9999.0)
# ---- figures the daily check validates (nothing turned into zero)
row('UNKNOWN_COUNTS_ARE_NOT_ZERO', 0, ['INVALID_SNAPSHOT:trades_today', 'INVALID_SNAPSHOT:wins_today', 'INVALID_SNAPSHOT:consecutive_losses'], 1, closed=-50.0,
    trades=-1, wins=-1, losses=-1)
row('UNKNOWN_WINS_ONLY', 0, ['INVALID_SNAPSHOT:wins_today'], 1, closed=-50.0, wins=-1)
row('INVALID_BALANCE_AMOUNT_IS_NOT_A_BALANCE', 0, ['INVALID_SNAPSHOT:balance_start'], 1, closed=-50.0, bamt=-1.0)
row('ZERO_BALANCE_AMOUNT_IS_NOT_A_BALANCE', 0, ['INVALID_SNAPSHOT:balance_start'], 1, closed=-50.0, bamt=0.0)
row('NAN_RESULT_OF_THE_CHOSEN_FORMULA_IS_INVALID', 0, ['INVALID_SNAPSHOT:closed_result'], 1, closed=0.0, nanp=1)
row('NAN_IN_AN_UNCHOSEN_CANDIDATE_IS_IRRELEVANT', 1, [], 1, closed=-60.0, nanp=1, formula='PROFIT_COMMISSION_SWAP')
row('CONTRADICTORY_COUNTERS_BLOCK', 0, ['INCONSISTENT_COUNTERS:wins_exceed_trades'], 1, closed=-50.0, trades=1, wins=2)
row('INVALID_FIGURES_HIDE_A_PROVEN_LIMIT', 0, ['INVALID_SNAPSHOT:balance_start'], 1, closed=-9999.0, cp=-9999.0, bamt=-1.0)


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t012_bridge_fixtures.py emit_mql)']
    out.append('#define NROWS %d' % len(ROWS))

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    q = lambda v: '"%s"' % v
    arr('string', 'R_NAME', [q(r['name']) for r in ROWS])
    for key, nm in (('verdict', 'R_VERDICT'), ('fday', 'R_FDAY'), ('complete', 'R_COMPLETE'), ('npos', 'R_NPOS'), ('deals', 'R_DEALS'), ('nanp', 'R_NANP'),
                    ('bknown', 'R_BKNOWN'), ('bday', 'R_BDAY'), ('trades', 'R_TRADES'), ('wins', 'R_WINS'), ('losses', 'R_LOSSES'), ('maxset', 'R_MAXSET'),
                    ('maxt', 'R_MAXT')):
        arr('int', nm, [str(r[key]) for r in ROWS])
    arr('long', 'R_UTC', [str(r['utc']) for r in ROWS])
    for key, nm in (('cp', 'R_CP'), ('cpcs', 'R_CPCS'), ('cpcsf', 'R_CPCSF'), ('bamt', 'R_BAMT'), ('closed', 'X_CLOSED')):
        arr('double', nm, [repr(float(r[key])) for r in ROWS])
    arr('string', 'R_FORMULA', [q(r['formula']) for r in ROWS])
    arr('string', 'R_CLASSIF', [q(r['classif']) for r in ROWS])
    arr('int', 'X_ALLOWED', [str(r['allowed']) for r in ROWS])
    arr('string', 'X_REASONS', [q(r['reasons']) for r in ROWS])
    arr('int', 'X_CALLED', [str(r['called']) for r in ROWS])
    arr('int', 'X_CANCEL', [str(r['cancel']) for r in ROWS])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)
