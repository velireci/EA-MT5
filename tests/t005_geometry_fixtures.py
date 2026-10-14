"""Hand-computed T005 geometry cases (shared by the Python tests and src/tests/T005_GeometryTest.mq5).

Every expected value below was derived BY HAND from the contract in tests/t005_geometry_reference.py (ticks as
integers first, then R, 2R and TP from the normalized prices); BUY and SELL were computed separately, not by one
formula. Notation: x/t means price divided by tick size. Expected tuple (exp) =
(E_out, S_out, R_geom, level_2R, TP, target_case, tp_equals_2R). Symbol tuples: (tick, digits, point, stops_level).

  BUY_*  E 1950.40 S 1944.15 (tick .01): R = 6.25, 2R level = 1950.40 + 12.50 = 1962.90.
  SELL_* E 2310.20 S 2316.45 (tick .01): R = 6.25, 2R level = 2310.20 - 12.50 = 2297.70.
  BUY_ROUND_FAR (tick .05): E 2000.02 -> 40000.4 -> 40000 = 2000.00; S 1994.93 -> 39898.6 -> 39899 = 1994.95;
      R ticks 101 = 5.05; 2R ticks 40000 + 202 = 40202 = 2010.10 (raw S would give 2*5.07 -> 2010.14); T 2012.33
      -> 40246.6 -> up 40247 = 2012.35 (> 2R: kept).
  BUY_ROUND_EQ: T 2010.07 -> 40201.4 -> up 40202 = 2R: EQUAL, TP 2010.10.
  SELL_ROUND_FAR (tick .05): E 2500.07 -> 50001.4 -> 50001 = 2500.05; S 2507.64 -> 50152.8 -> 50153 = 2507.65;
      R ticks 152 = 7.60; 2R ticks 50001 - 304 = 49697 = 2484.85; T 2480.03 -> 49600.6 -> down 49600 = 2480.00.
  SELL_ROUND_NEAR: T 2490.02 -> 49800.4 -> down 49800 = 2490.00, nearer than 2484.85 -> TP 2484.85.
  HALF: tick .05: BUY E 2000.025 -> 40000.5 -> tie up 40001 = 2000.05; S 1999.975 -> 39999.5 -> tie up 40000 = 2000.00.
        SELL E 2000.075 -> 40001.5 -> 40002 = 2000.10; S 2000.275 -> 40005.5 -> 40006 = 2000.30.
  COARSE: tick .5: BUY E 1000.3 -> 2000.6 -> 2001 = 1000.5; S 995.2 -> 1990.4 -> 1990 = 995.0; R 11 ticks = 5.5;
        2R ticks 2001 + 22 = 2023 = 1011.5; T 1011.1 -> 2022.2 -> up 2023 = 1011.5 (EQUAL).
        tick 1.0: SELL E 1500.4 -> 1500; S 1507.5 -> tie up 1508; R = 8; 2R = 1500 - 16 = 1484; T 1480.6 -> down 1480.
"""

BUY, SELL, HOLD = 'BUY', 'SELL', 'HOLD'
S01 = (0.01, 2, 0.01, 0)
S05 = (0.05, 2, 0.01, 0)
S_STOPS30 = (0.01, 2, 0.01, 30)
S_COARSE5 = (0.5, 1, 0.1, 0)
S_COARSE1 = (1.0, 0, 1.0, 0)
N, NEAR, EQ, FAR = 'NONE', 'NEARER_THAN_2R', 'EQUAL_TO_2R', 'FARTHER_THAN_2R'

CASES = []


def case(name, d, e, s, t, sym, status, exp=None, quote=None, pend='NOT_CHECKED', why=''):
    CASES.append(dict(name=name, d=d, e=e, s=s, t=t, sym=sym, quote=quote, status=status, exp=exp, pend=pend, why=why))


# --- BUY and SELL, tick .01, target farther / nearer / equal / none -------------------------------------
case('BUY_FAR', BUY, 1950.40, 1944.15, 1970.00, S01, 'OK', (1950.40, 1944.15, 6.25, 1962.90, 1970.00, FAR, False))
case('BUY_NEAR', BUY, 1950.40, 1944.15, 1960.00, S01, 'OK', (1950.40, 1944.15, 6.25, 1962.90, 1962.90, NEAR, True))
case('BUY_EQ', BUY, 1950.40, 1944.15, 1962.90, S01, 'OK', (1950.40, 1944.15, 6.25, 1962.90, 1962.90, EQ, True))
case('BUY_NONE', BUY, 1950.40, 1944.15, None, S01, 'OK', (1950.40, 1944.15, 6.25, 1962.90, 1962.90, N, True))
case('SELL_FAR', SELL, 2310.20, 2316.45, 2290.10, S01, 'OK', (2310.20, 2316.45, 6.25, 2297.70, 2290.10, FAR, False))
case('SELL_NEAR', SELL, 2310.20, 2316.45, 2300.00, S01, 'OK', (2310.20, 2316.45, 6.25, 2297.70, 2297.70, NEAR, True))
case('SELL_EQ', SELL, 2310.20, 2316.45, 2297.70, S01, 'OK', (2310.20, 2316.45, 6.25, 2297.70, 2297.70, EQ, True))
case('SELL_NONE', SELL, 2310.20, 2316.45, None, S01, 'OK', (2310.20, 2316.45, 6.25, 2297.70, 2297.70, N, True))
# --- normalization changes E and S: R, 2R follow the reported prices -------------------------------------
case('BUY_ROUND_FAR', BUY, 2000.02, 1994.93, 2012.33, S05, 'OK', (2000.00, 1994.95, 5.05, 2010.10, 2012.35, FAR, False))
case('BUY_ROUND_EQ', BUY, 2000.02, 1994.93, 2010.07, S05, 'OK', (2000.00, 1994.95, 5.05, 2010.10, 2010.10, EQ, True))
case('SELL_ROUND_FAR', SELL, 2500.07, 2507.64, 2480.03, S05, 'OK', (2500.05, 2507.65, 7.60, 2484.85, 2480.00, FAR, False))
case('SELL_ROUND_NEAR', SELL, 2500.07, 2507.64, 2490.02, S05, 'OK', (2500.05, 2507.65, 7.60, 2484.85, 2484.85, NEAR, True))
# --- exact half ticks: both E and S go UP (proposal) -----------------------------------------------------
case('BUY_HALF', BUY, 2000.025, 1999.975, None, S05, 'OK', (2000.05, 2000.00, 0.05, 2000.15, 2000.15, N, True))
case('SELL_HALF', SELL, 2000.075, 2000.275, None, S05, 'OK', (2000.10, 2000.30, 0.20, 1999.70, 1999.70, N, True))
# --- coarse ticks, on-grid inputs that are inexact in binary floating point -----------------------------
case('BUY_COARSE_HALF', BUY, 1000.3, 995.2, 1011.1, S_COARSE5, 'OK', (1000.5, 995.0, 5.5, 1011.5, 1011.5, EQ, True))
case('SELL_COARSE_ONE', SELL, 1500.4, 1507.5, 1480.6, S_COARSE1, 'OK', (1500.0, 1508.0, 8.0, 1484.0, 1480.0, FAR, False))
case('SELL_ON_GRID_05', SELL, 2310.15, 2316.40, None, S05, 'OK', (2310.15, 2316.40, 6.25, 2297.65, 2297.65, N, True))
# --- zero risk and wrong side ----------------------------------------------------------------------------
case('BUY_ZERO', BUY, 2000.00, 2000.00, None, S01, 'ZERO_RISK')
case('BUY_ZERO_AFTER_NORM', BUY, 2000.02, 2000.01, None, S05, 'ZERO_RISK')
case('SELL_ZERO_AFTER_NORM', SELL, 2000.01, 2000.02, None, S05, 'ZERO_RISK')
case('BUY_SL_WRONG', BUY, 2000.00, 2001.00, None, S01, 'SL_WRONG_SIDE')
case('SELL_SL_WRONG', SELL, 2000.00, 1999.00, None, S01, 'SL_WRONG_SIDE')
# --- target on the wrong side (normalized target must be strictly beyond E_out) ---------------------------
case('BUY_T_BELOW', BUY, 2000.00, 1995.00, 1999.00, S01, 'TARGET_WRONG_SIDE')
case('BUY_T_EQ_E', BUY, 2000.00, 1995.00, 2000.00, S01, 'TARGET_WRONG_SIDE')
case('BUY_T_SAME_TICK_BELOW', BUY, 2000.00, 1995.00, 1999.99, S05, 'TARGET_WRONG_SIDE')
case('SELL_T_ABOVE', SELL, 2000.00, 2005.00, 2001.00, S01, 'TARGET_WRONG_SIDE')
case('SELL_T_EQ_E', SELL, 2000.00, 2005.00, 2000.00, S01, 'TARGET_WRONG_SIDE')
case('BUY_T_SUBTICK_BEYOND', BUY, 2000.00, 1995.00, 2000.01, S05, 'OK', (2000.00, 1995.00, 5.00, 2010.00, 2010.00, NEAR, True))
# --- stops level 30 points (min distance 0.30) ------------------------------------------------------------
case('BUY_SL_BELOW_STOPS', BUY, 2000.00, 1999.71, None, S_STOPS30, 'BELOW_STOPS_LEVEL')
case('BUY_SL_AT_STOPS', BUY, 2000.00, 1999.70, None, S_STOPS30, 'OK', (2000.00, 1999.70, 0.30, 2000.60, 2000.60, N, True))
case('SELL_SL_BELOW_STOPS', SELL, 2000.00, 2000.29, None, S_STOPS30, 'BELOW_STOPS_LEVEL')
case('SELL_SL_AT_STOPS', SELL, 2000.00, 2000.30, None, S_STOPS30, 'OK', (2000.00, 2000.30, 0.30, 1999.40, 1999.40, N, True))
# --- pending-order distance (E 2000.00, S 1995.00 / 2005.00, stops 30) -------------------------------------
case('BUY_ASK_AT_STOPS', BUY, 2000.00, 1995.00, None, S_STOPS30, 'OK', (2000.00, 1995.00, 5.00, 2010.00, 2010.00, N, True), (1999.90, 2000.30), 'PASSED')
case('BUY_ASK_TOO_CLOSE', BUY, 2000.00, 1995.00, None, S_STOPS30, 'PENDING_TOO_CLOSE', None, (1999.90, 2000.29), 'TOO_CLOSE')
case('BUY_ASK_BELOW_LIMIT', BUY, 2000.00, 1995.00, None, S_STOPS30, 'PENDING_TOO_CLOSE', None, (1998.90, 1999.00), 'TOO_CLOSE')
case('SELL_BID_AT_STOPS', SELL, 2000.00, 2005.00, None, S_STOPS30, 'OK', (2000.00, 2005.00, 5.00, 1990.00, 1990.00, N, True), (1999.70, 2000.10), 'PASSED')
case('SELL_BID_TOO_CLOSE', SELL, 2000.00, 2005.00, None, S_STOPS30, 'PENDING_TOO_CLOSE', None, (1999.71, 2000.10), 'TOO_CLOSE')
case('SELL_BID_ABOVE_LIMIT', SELL, 2000.00, 2005.00, None, S_STOPS30, 'PENDING_TOO_CLOSE', None, (2001.00, 2001.10), 'TOO_CLOSE')
case('BUY_ASK_EQ_LIMIT_STOPS0', BUY, 2000.00, 1995.00, None, S01, 'PENDING_TOO_CLOSE', None, (1999.90, 2000.00), 'TOO_CLOSE')
case('BUY_ASK_ONE_POINT_STOPS0', BUY, 2000.00, 1995.00, None, S01, 'OK', (2000.00, 1995.00, 5.00, 2010.00, 2010.00, N, True), (1999.90, 2000.01), 'PASSED')
case('BUY_NO_QUOTE_STOPS30', BUY, 2000.00, 1995.00, None, S_STOPS30, 'OK', (2000.00, 1995.00, 5.00, 2010.00, 2010.00, N, True), None, 'NOT_CHECKED')
# --- invalid inputs ---------------------------------------------------------------------------------------
case('DIRECTION_INVALID', HOLD, 2000.00, 1995.00, None, S01, 'INVALID_DIRECTION')
case('QUOTE_CROSSED', BUY, 2000.00, 1995.00, None, S01, 'INVALID_INPUT', None, (2001.00, 2000.00))
case('TICK_ZERO', BUY, 2000.00, 1995.00, None, (0.0, 2, 0.01, 0), 'INVALID_INPUT')
case('TICK_NEGATIVE', SELL, 2000.00, 2005.00, None, (-0.01, 2, 0.01, 0), 'INVALID_INPUT')
case('POINT_ZERO', BUY, 2000.00, 1995.00, None, (0.01, 2, 0.0, 0), 'INVALID_INPUT')
case('STOPS_NEGATIVE', BUY, 2000.00, 1995.00, None, (0.01, 2, 0.01, -1), 'INVALID_INPUT')
case('ENTRY_ZERO', BUY, 0.0, -5.0, None, S01, 'INVALID_INPUT')
case('TARGET_NEGATIVE', BUY, 2000.00, 1995.00, -1.0, S01, 'INVALID_INPUT')
# --- validation of tick/digits compatibility, non-positive and overflowing results (INVALID_INPUT + tag) --
TD, NP, OV = 'INCOMPATIBLE_TICK_DIGITS', 'NONPOSITIVE_PRICE', 'NUMERIC_OVERFLOW'
I = 'INVALID_INPUT'
case('BUY_TICK_DIGITS_MISMATCH', BUY, 1.004, 1.003, None, (0.001, 2, 0.01, 0), I, why=TD)       # was OK with R=0
case('SELL_TICK_DIGITS_MISMATCH', SELL, 1.003, 1.004, None, (0.001, 2, 0.01, 0), I, why=TD)
case('TICK_015_DIGITS_2', BUY, 2000.00, 1995.00, None, (0.015, 2, 0.01, 0), I, why=TD)         # not a multiple of 0.01
case('TICK_FINER_THAN_DIGITS_0', BUY, 2000.0, 1995.0, None, (0.5, 0, 1.0, 0), I, why=TD)
case('TICK_025_DIGITS_2_OK', BUY, 2000.00, 1995.00, None, (0.25, 2, 0.01, 0), 'OK', (2000.00, 1995.00, 5.00, 2010.00, 2010.00, N, True))
case('SELL_2R_NEGATIVE', SELL, 100.00, 160.00, None, S01, I, why=NP)                           # 2R level -20
case('BUY_SL_ROUNDS_TO_ZERO', BUY, 0.6, 0.4, None, S_COARSE1, I, why=NP)                       # S_out = 0
case('SELL_ENTRY_ROUNDS_TO_ZERO', SELL, 0.4, 0.2, None, S_COARSE1, I, why=NP)                  # E_out = 0
case('SELL_TARGET_ROUNDS_TO_ZERO', SELL, 5.0, 7.0, 0.4, S_COARSE1, I, why=NP)                  # T_out = 0, 2R = 3 > 0
case('SELL_2R_EXACTLY_ZERO', SELL, 100.00, 150.00, None, S01, I, why=NP)                       # 2R level = 0
case('SELL_2R_JUST_POSITIVE', SELL, 100.00, 149.99, None, S01, 'OK', (100.00, 149.99, 49.99, 0.02, 0.02, N, True))
case('BUY_HUGE_TINY_TICK', BUY, 1e300, 1e299, None, S01, I, why=OV)
case('BUY_RANGE_AT_LIMIT_PLUS', BUY, 1.0e10 + 1.0, 1.0e10, None, S01, I, why=OV)               # 1e12 + 100 ticks
case('BUY_2R_OVERFLOW_TO_INF', BUY, 1.5e308, 1.0e308, None, (1e308, 0, 1.0, 0), I, why=OV)     # E_out = 2e308 = inf

SIGN = {BUY: 1, SELL: -1, HOLD: 0}


def _num(v):
    return repr(float(v))


def emit_mql():
    """Text of the MQL5 data block (kept in src/tests/T005_GeometryTest.mq5 between the markers)."""
    out = ['// BEGIN GENERATED FIXTURES (tests/t005_geometry_fixtures.py emit_mql)']
    out.append('#define NCASES %d' % len(CASES))

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    arr('string', 'C_NAME', ['"%s"' % c['name'] for c in CASES])
    arr('int', 'C_DIR', [str(SIGN[c['d']]) for c in CASES])
    arr('double', 'C_E', [_num(c['e']) for c in CASES])
    arr('double', 'C_S', [_num(c['s']) for c in CASES])
    arr('int', 'C_HAST', ['0' if c['t'] is None else '1' for c in CASES])
    arr('double', 'C_T', [_num(0.0 if c['t'] is None else c['t']) for c in CASES])
    arr('double', 'C_TICK', [_num(c['sym'][0]) for c in CASES])
    arr('int', 'C_DIG', [str(c['sym'][1]) for c in CASES])
    arr('double', 'C_POINT', [_num(c['sym'][2]) for c in CASES])
    arr('int', 'C_STOPS', [str(c['sym'][3]) for c in CASES])
    arr('int', 'C_HASQ', ['0' if c['quote'] is None else '1' for c in CASES])
    arr('double', 'C_BID', [_num(0.0 if c['quote'] is None else c['quote'][0]) for c in CASES])
    arr('double', 'C_ASK', [_num(0.0 if c['quote'] is None else c['quote'][1]) for c in CASES])
    arr('string', 'X_STATUS', ['"%s"' % c['status'] for c in CASES])
    arr('string', 'X_WHY', ['"%s"' % c['why'] for c in CASES])
    arr('string', 'X_PEND', ['"%s"' % c['pend'] for c in CASES])
    arr('int', 'X_HASNUM', ['0' if c['exp'] is None else '1' for c in CASES])
    ex = [c['exp'] if c['exp'] is not None else (0.0, 0.0, 0.0, 0.0, 0.0, 'NONE', False) for c in CASES]
    arr('double', 'X_E', [_num(x[0]) for x in ex])
    arr('double', 'X_S', [_num(x[1]) for x in ex])
    arr('double', 'X_R', [_num(x[2]) for x in ex])
    arr('double', 'X_2R', [_num(x[3]) for x in ex])
    arr('double', 'X_TP', [_num(x[4]) for x in ex])
    arr('string', 'X_CASE', ['"%s"' % x[5] for x in ex])
    arr('int', 'X_COINC', ['1' if x[6] else '0' for x in ex])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
