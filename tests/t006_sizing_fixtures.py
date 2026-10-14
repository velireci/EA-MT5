"""Hand-computed T006 sizing cases (shared by the Python tests and src/tests/T006_SizingTest.mq5).

Every expected number was derived BY HAND (not by the code formula) from the linear model of
tests/t006_sizing_reference.py: loss_per_lot = stop_ticks * tick_value; raw volume = budget / loss_per_lot; round DOWN to
whole steps. The geometry is NOT in the table as a result: each row lists the T005 inputs (direction, E, S, tick, digits)
and the test runs the real T005 module first (Python reference / TradeGeometry.mqh) and passes its result to the sizer.
Expected tuple exp = (stop_ticks, loss_per_lot, steps, volume_out, risk_realized); for SKIP rows steps is the rounded
candidate and volume_out/risk are 0; invalid and geometry rows have exp None (nothing reported).

  GA_BUY  BUY  E 1950.40 S 1944.15, tick .01: |195040-194415| = 625 ticks.  GA_SELL SELL 2310.20 / 2316.45: 625 ticks.
  GB_BUY  BUY  E 2500.05 S 2492.45, tick .05: 7.60/.05 = 152 ticks.         GB_SELL SELL 2500.05 / 2507.65: 152 ticks.
  G10     BUY  1950.10 / 1950.00 tick .01: 10 ticks.
  tick_value 1.0 unless stated. Budget 1234.56 on 625 ticks: raw 1234.56/625 = 1.975296 lots.
    step .01  -> 197 steps = 1.97, risk 197*.01*625 = 1231.25      step .1 -> 19 = 1.9, risk 19*.1*625 = 1187.5
    step .05  -> 39 = 1.95, risk 39*.05*625 = 1218.75              step 1  -> 1, risk 625
    step .001 -> 1975 = 1.975, risk 1975*.001*625 = 1234.375       step .5 -> 3 = 1.5, risk 3*.5*625 = 937.5
  On the step grid: 187.5/625 = .3 lots step .1 -> 3; 43.75/625 = .07 step .01 -> 7; 181.25/625 = .29 -> 29;
    1000/625 = 1.6 -> 160.  Budget 187.49996875 = 2.9999995 steps of .1 (5e-7 below 3): 2 steps = .2 lots, risk 2*.1*625 = 125
    (the 1e-6 step tolerance proposes 3, the never-exceed guard removes it: 3 steps would cost 187.5).  tick_value .8: loss 500; 1000/500 = 2.0 -> 200 steps; 1234.56/500 = 2.46912 -> 246, risk 1230.
    tick_value 2: loss 1250; 1234.56/1250 = .987648 -> 98, risk 1225.   GB, tick_value 5: loss 760; 2000/760 = 2.6315 -> 263
    steps = 2.63 lots, risk 263*.01*760 = 1998.8.   G10 budget .29: loss 10; .29/10 = .029 lots step .001 -> 29 (float
    noise: .29/.01 style division gives 28.999999999999996 steps; the 1e-6 step tolerance restores 29).
  Limits (budget 1234.56, step .01, 197 candidate steps): min .10 with budget 50 -> .08 lots = 8 steps below min; budget 5 ->
    .008 lots = 0 steps (rounds to zero); budget 62.5 -> .10 lots exactly the minimum; max 1.5 -> 150 < 197 skip; max 1.97 ok;
    cap 1.5 skip; cap 1.97 ok; cap 1.975 (off grid) floors to 197 steps: ok; cap 1.969 floors to 196: skip; both exceeded:
    the broker maximum is reported first; cap .05 below min .10: 197 > 5 steps: skip above cap. Float-sensitive cap 0.3 with step .1 (0.3/0.1 = 2.9999999999999996)
    still allows 3 steps.  Cap rule: cap_steps = floor(x + 4*DBL_EPSILON*max(1, x)), x = cap/step; cap .29999995 (x = 2.9999995)
    is 2 steps and the 3-step candidate is SKIP_ABOVE_CAP; cap .3 and .30000005 allow 3 (see the cap-rule block below).
"""

BUY, SELL, HOLD = 'BUY', 'SELL', 'HOLD'
S01 = (0.01, 2)
S05 = (0.05, 2)

GA_BUY = (BUY, 1950.40, 1944.15, S01)
GA_SELL = (SELL, 2310.20, 2316.45, S01)
GB_BUY = (BUY, 2500.05, 2492.45, S05)
GB_SELL = (SELL, 2500.05, 2507.65, S05)
G10 = (BUY, 1950.10, 1950.00, S01)

CASES = []


def case(name, geo, p, status, exp=None, why=''):
    """p = (risk_budget, tick_value, volume_min, volume_step, volume_max, cap_lots)."""
    CASES.append(dict(name=name, geo=geo, p=p, status=status, exp=exp, why=why))


def P(budget=1234.56, tv=1.0, vmin=0.01, step=0.01, vmax=100.0, cap=10.0):
    return (budget, tv, vmin, step, vmax, cap)


OKS, BMIN, AMAX, ACAP, INV, GNO = ('OK', 'SKIP_BELOW_MIN_VOLUME', 'SKIP_ABOVE_MAX_VOLUME', 'SKIP_ABOVE_CAP',
                                   'INVALID_INPUT', 'GEOMETRY_NOT_OK')

# --- BUY and SELL, five different steps ---------------------------------------------------------------------
case('BUY_STEP_001', GA_BUY, P(), OKS, (625, 625.0, 197, 1.97, 1231.25))
case('SELL_STEP_001', GA_SELL, P(), OKS, (625, 625.0, 197, 1.97, 1231.25))
case('BUY_STEP_01', GA_BUY, P(vmin=0.1, step=0.1), OKS, (625, 625.0, 19, 1.9, 1187.5))
case('SELL_STEP_01', GA_SELL, P(vmin=0.1, step=0.1), OKS, (625, 625.0, 19, 1.9, 1187.5))
case('BUY_STEP_005', GA_BUY, P(vmin=0.05, step=0.05), OKS, (625, 625.0, 39, 1.95, 1218.75))
case('BUY_STEP_1', GA_BUY, P(vmin=1.0, step=1.0), OKS, (625, 625.0, 1, 1.0, 625.0))
case('BUY_STEP_0001', GA_BUY, P(vmin=0.001, step=0.001), OKS, (625, 625.0, 1975, 1.975, 1234.375))
case('SELL_STEP_0001', GA_SELL, P(vmin=0.001, step=0.001), OKS, (625, 625.0, 1975, 1.975, 1234.375))
case('BUY_STEP_05', GA_BUY, P(vmin=0.5, step=0.5, vmax=50.0), OKS, (625, 625.0, 3, 1.5, 937.5))
# --- raw volume exactly on the step grid, float-sensitive -----------------------------------------------------
case('BUY_EXACT_03_STEP_01', GA_BUY, P(budget=187.5, vmin=0.1, step=0.1), OKS, (625, 625.0, 3, 0.3, 187.5))
case('BUY_EXACT_007', GA_BUY, P(budget=43.75), OKS, (625, 625.0, 7, 0.07, 43.75))
case('BUY_EXACT_029', GA_BUY, P(budget=181.25), OKS, (625, 625.0, 29, 0.29, 181.25))
case('SELL_EXACT_16', GA_SELL, P(budget=1000.0), OKS, (625, 625.0, 160, 1.6, 1000.0))
case('BUY_TOLERANCE_OVERSHOOT', GA_BUY, P(budget=187.49996875, vmin=0.1, step=0.1), OKS, (625, 625.0, 2, 0.2, 125.0))
case('BUY_EPS_BUMP_NEEDED', G10, P(budget=0.29, vmin=0.001, step=0.001), OKS, (10, 10.0, 29, 0.029, 0.29))
# --- tick_value is in the result ---------------------------------------------------------------------------
case('BUY_TICKVALUE_08_EXACT', GA_BUY, P(budget=1000.0, tv=0.8), OKS, (625, 500.0, 200, 2.0, 1000.0))
case('BUY_TICKVALUE_08', GA_BUY, P(tv=0.8), OKS, (625, 500.0, 246, 2.46, 1230.0))
case('SELL_TICKVALUE_2', GA_SELL, P(tv=2.0), OKS, (625, 1250.0, 98, 0.98, 1225.0))
case('BUY_TICK005_TV5', GB_BUY, P(budget=2000.0, tv=5.0), OKS, (152, 760.0, 263, 2.63, 1998.8))
case('SELL_TICK005_TV5', GB_SELL, P(budget=2000.0, tv=5.0), OKS, (152, 760.0, 263, 2.63, 1998.8))
# --- limits: below min, exactly min, above max, exactly max, above cap, exactly cap ---------------------------
case('BUY_BELOW_MIN', GA_BUY, P(budget=50.0, vmin=0.10), BMIN, (625, 625.0, 8, 0.0, 0.0))
case('SELL_BELOW_MIN', GA_SELL, P(budget=50.0, vmin=0.10), BMIN, (625, 625.0, 8, 0.0, 0.0))
case('BUY_ROUNDS_TO_ZERO', GA_BUY, P(budget=5.0), BMIN, (625, 625.0, 0, 0.0, 0.0))
case('BUY_EXACTLY_MIN', GA_BUY, P(budget=62.5, vmin=0.10), OKS, (625, 625.0, 10, 0.1, 62.5))
case('BUY_ABOVE_MAX', GA_BUY, P(vmax=1.5), AMAX, (625, 625.0, 197, 0.0, 0.0))
case('SELL_ABOVE_MAX', GA_SELL, P(vmax=1.5), AMAX, (625, 625.0, 197, 0.0, 0.0))
case('BUY_EXACTLY_MAX', GA_BUY, P(vmax=1.97), OKS, (625, 625.0, 197, 1.97, 1231.25))
case('BUY_ABOVE_CAP', GA_BUY, P(cap=1.5), ACAP, (625, 625.0, 197, 0.0, 0.0))
case('SELL_ABOVE_CAP', GA_SELL, P(cap=1.5), ACAP, (625, 625.0, 197, 0.0, 0.0))
case('BUY_EXACTLY_CAP', GA_BUY, P(cap=1.97), OKS, (625, 625.0, 197, 1.97, 1231.25))
case('BUY_CAP_OFF_GRID_ABOVE', GA_BUY, P(cap=1.975), OKS, (625, 625.0, 197, 1.97, 1231.25))
case('BUY_CAP_OFF_GRID_BELOW', GA_BUY, P(cap=1.969), ACAP, (625, 625.0, 197, 0.0, 0.0))
case('BUY_CAP_FLOAT_03', GA_BUY, P(budget=187.5, vmin=0.1, step=0.1, cap=0.3), OKS, (625, 625.0, 3, 0.3, 187.5))
# --- cap rule: floor(x + 4 ulp * max(1, x)), x = cap/step; a real shortfall (5e-7 step) is NOT absorbed ------
# step .1, budget 187.5 on 625 ticks = raw .3 lots = 3 steps (risk 3*.1*625 = 187.5): cap .29999995 = 2.9999995 steps -> 2.
case('BUY_CAP_JUST_BELOW_STEP01', GA_BUY, P(budget=187.5, vmin=0.1, step=0.1, cap=0.29999995), ACAP, (625, 625.0, 3, 0.0, 0.0))
case('BUY_CAP_ON_GRID_STEP01', GA_BUY, P(budget=187.5, vmin=0.1, step=0.1, cap=0.3), OKS, (625, 625.0, 3, 0.3, 187.5))
case('BUY_CAP_JUST_ABOVE_STEP01', GA_BUY, P(budget=187.5, vmin=0.1, step=0.1, cap=0.30000005), OKS, (625, 625.0, 3, 0.3, 187.5))
case('SELL_CAP_JUST_BELOW_STEP01', GA_SELL, P(budget=187.5, vmin=0.1, step=0.1, cap=0.29999995), ACAP, (625, 625.0, 3, 0.0, 0.0))
case('SELL_CAP_ON_GRID_STEP01', GA_SELL, P(budget=187.5, vmin=0.1, step=0.1, cap=0.3), OKS, (625, 625.0, 3, 0.3, 187.5))
case('SELL_CAP_JUST_ABOVE_STEP01', GA_SELL, P(budget=187.5, vmin=0.1, step=0.1, cap=0.30000005), OKS, (625, 625.0, 3, 0.3, 187.5))
# step .01, budget 18.75 = raw .03 lots = 3 steps (risk 3*.01*625 = 18.75): cap .0299999 = 2.99999 steps -> 2.
case('BUY_CAP_JUST_BELOW_STEP001', GA_BUY, P(budget=18.75, step=0.01, cap=0.0299999), ACAP, (625, 625.0, 3, 0.0, 0.0))
case('BUY_CAP_ON_GRID_STEP001', GA_BUY, P(budget=18.75, step=0.01, cap=0.03), OKS, (625, 625.0, 3, 0.03, 18.75))
case('BUY_CAP_JUST_ABOVE_STEP001', GA_BUY, P(budget=18.75, step=0.01, cap=0.0300001), OKS, (625, 625.0, 3, 0.03, 18.75))
case('SELL_CAP_JUST_BELOW_STEP001', GA_SELL, P(budget=18.75, step=0.01, cap=0.0299999), ACAP, (625, 625.0, 3, 0.0, 0.0))
case('SELL_CAP_ON_GRID_STEP001', GA_SELL, P(budget=18.75, step=0.01, cap=0.03), OKS, (625, 625.0, 3, 0.03, 18.75))
# step .05, budget 93.75 = raw .15 lots = 3 steps (risk 3*.05*625 = 93.75): cap .1499999 = 2.999998 steps -> 2;
# 0.15/0.05 = 2.9999999999999996 is binary noise and stays 3.
case('BUY_CAP_JUST_BELOW_STEP005', GA_BUY, P(budget=93.75, vmin=0.05, step=0.05, cap=0.1499999), ACAP, (625, 625.0, 3, 0.0, 0.0))
case('BUY_CAP_ON_GRID_STEP005', GA_BUY, P(budget=93.75, vmin=0.05, step=0.05, cap=0.15), OKS, (625, 625.0, 3, 0.15, 93.75))
case('BUY_CAP_JUST_ABOVE_STEP005', GA_BUY, P(budget=93.75, vmin=0.05, step=0.05, cap=0.1500001), OKS, (625, 625.0, 3, 0.15, 93.75))
# large x: step .001, budget 3125000 = raw 5000 lots = 5000000 steps (risk 5000000*.001*625 = 3125000). The cap 4999.999999999
# is 1e-6 step below the 5000000 boundary: floor(x + 1e-6) would call it 5000000 (above the cap); 4 ulp of 5e6 is 4.4e-9.
case('BUY_CAP_LARGE_ON_GRID', GA_BUY, P(budget=3125000.0, vmin=0.001, step=0.001, vmax=10000.0, cap=5000.0), OKS, (625, 625.0, 5000000, 5000.0, 3125000.0))
case('BUY_CAP_LARGE_JUST_BELOW', GA_BUY, P(budget=3125000.0, vmin=0.001, step=0.001, vmax=10000.0, cap=4999.999999999), ACAP, (625, 625.0, 5000000, 0.0, 0.0))
# binary noise on the boundary is NOT misclassified as below: 0.7/0.1 = 6.999999999999999 (7 steps, budget 437.5),
# cap 0.1+0.2 = 0.30000000000000004 and 3*0.1 style sums.
case('BUY_CAP_NOISE_07', GA_BUY, P(budget=437.5, vmin=0.1, step=0.1, cap=0.7), OKS, (625, 625.0, 7, 0.7, 437.5))
case('BUY_CAP_NOISE_SUM_03', GA_BUY, P(budget=187.5, vmin=0.1, step=0.1, cap=0.1 + 0.2), OKS, (625, 625.0, 3, 0.3, 187.5))
case('BUY_CAP_GREATER_THAN_MAX', GA_BUY, P(vmax=1.5, cap=10.0), AMAX, (625, 625.0, 197, 0.0, 0.0))
case('BUY_CAP_SMALLER_THAN_MAX', GA_BUY, P(vmax=100.0, cap=1.5), ACAP, (625, 625.0, 197, 0.0, 0.0))
case('BUY_BOTH_EXCEEDED', GA_BUY, P(vmax=1.5, cap=1.0), AMAX, (625, 625.0, 197, 0.0, 0.0))
case('BUY_CAP_BELOW_MIN', GA_BUY, P(vmin=0.10, cap=0.05), ACAP, (625, 625.0, 197, 0.0, 0.0))
case('BUY_MIN_EQUALS_MAX', GA_BUY, P(vmin=1.97, vmax=1.97), OKS, (625, 625.0, 197, 1.97, 1231.25))
# --- geometry not OK: nothing is recomputed ------------------------------------------------------------------
case('GEOMETRY_ZERO_RISK', (BUY, 1950.40, 1950.40, S01), P(), GNO, why='GEOMETRY_NOT_OK')
case('GEOMETRY_SL_WRONG_SIDE', (BUY, 1950.40, 1955.00, S01), P(), GNO, why='GEOMETRY_NOT_OK')
case('GEOMETRY_BAD_DIRECTION', (HOLD, 1950.40, 1944.15, S01), P(), GNO, why='GEOMETRY_NOT_OK')
case('GEOMETRY_WINS_OVER_BAD_RISK', (BUY, 1950.40, 1950.40, S01), P(budget=-1.0), GNO, why='GEOMETRY_NOT_OK')
# --- invalid inputs and incompatible volume parameters (tag first, nothing reported) ---------------------------
case('RISK_ZERO', GA_BUY, P(budget=0.0), INV, why='INVALID_RISK_BUDGET')
case('RISK_NEGATIVE', GA_BUY, P(budget=-5.0), INV, why='INVALID_RISK_BUDGET')
case('TICKVALUE_ZERO', GA_BUY, P(tv=0.0), INV, why='INVALID_TICK_VALUE')
case('TICKVALUE_NEGATIVE', GA_BUY, P(tv=-1.0), INV, why='INVALID_TICK_VALUE')
case('VMIN_ZERO', GA_BUY, P(vmin=0.0), INV, why='INVALID_VOLUME_MIN')
case('STEP_ZERO', GA_BUY, P(step=0.0), INV, why='INVALID_VOLUME_STEP')
case('STEP_NEGATIVE', GA_BUY, P(step=-0.01), INV, why='INVALID_VOLUME_STEP')
case('VMAX_ZERO', GA_BUY, P(vmax=0.0), INV, why='INVALID_VOLUME_MAX')
case('CAP_ZERO', GA_BUY, P(cap=0.0), INV, why='INVALID_CAP')
case('CAP_NEGATIVE', GA_BUY, P(cap=-10.0), INV, why='INVALID_CAP')
case('FIRST_FAILURE_RISK_BEFORE_TICKVALUE', GA_BUY, P(budget=0.0, tv=0.0), INV, why='INVALID_RISK_BUDGET')
case('MAX_BELOW_MIN', GA_BUY, P(vmin=1.0, vmax=0.5), INV, why='VOLUME_MAX_BELOW_MIN')
case('MIN_OFF_GRID', GA_BUY, P(vmin=0.015), INV, why='VOLUME_NOT_ON_GRID')
case('MIN_BELOW_ONE_STEP', GA_BUY, P(vmin=0.004), INV, why='VOLUME_NOT_ON_GRID')
case('MAX_OFF_GRID', GA_BUY, P(vmax=5.005), INV, why='VOLUME_NOT_ON_GRID')
case('MIN_OFF_GRID_STEP_01', GA_BUY, P(vmin=0.15, step=0.1), INV, why='VOLUME_NOT_ON_GRID')
case('STEP_TINY', GA_BUY, P(vmin=1e-12, step=1e-12), INV, why='STEP_RANGE')
case('CAP_TOO_MANY_STEPS', GA_BUY, P(cap=1e8), INV, why='STEP_RANGE')
case('RAW_OVERFLOW', GA_BUY, P(budget=1e300), INV, why='NUMERIC_OVERFLOW')
case('RAW_NOT_FINITE', GA_BUY, P(budget=1e100, tv=1e-300), INV, why='NUMERIC_OVERFLOW')

SIGN = {BUY: 1, SELL: -1, HOLD: 0}


def _num(v):
    return repr(float(v))


def emit_mql():
    """Text of the MQL5 data block (kept in src/tests/T006_SizingTest.mq5 between the markers)."""
    out = ['// BEGIN GENERATED FIXTURES (tests/t006_sizing_fixtures.py emit_mql)']
    out.append('#define NCASES %d' % len(CASES))

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    arr('string', 'C_NAME', ['"%s"' % c['name'] for c in CASES])
    arr('int', 'C_DIR', [str(SIGN[c['geo'][0]]) for c in CASES])
    arr('double', 'C_E', [_num(c['geo'][1]) for c in CASES])
    arr('double', 'C_S', [_num(c['geo'][2]) for c in CASES])
    arr('double', 'C_TICK', [_num(c['geo'][3][0]) for c in CASES])
    arr('int', 'C_DIG', [str(c['geo'][3][1]) for c in CASES])
    for i, nm in enumerate(('C_BUDGET', 'C_TV', 'C_VMIN', 'C_STEP', 'C_VMAX', 'C_CAP')):
        arr('double', nm, [_num(c['p'][i]) for c in CASES])
    arr('string', 'X_STATUS', ['"%s"' % c['status'] for c in CASES])
    arr('string', 'X_WHY', ['"%s"' % c['why'] for c in CASES])
    arr('int', 'X_HASNUM', ['0' if c['exp'] is None else '1' for c in CASES])
    ex = [c['exp'] if c['exp'] is not None else (0, 0.0, 0, 0.0, 0.0) for c in CASES]
    arr('long', 'X_STOP', [str(x[0]) for x in ex])
    arr('double', 'X_LOSS', [_num(x[1]) for x in ex])
    arr('long', 'X_STEPS', [str(x[2]) for x in ex])
    arr('double', 'X_VOL', [_num(x[3]) for x in ex])
    arr('double', 'X_RISK', [_num(x[4]) for x in ex])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
