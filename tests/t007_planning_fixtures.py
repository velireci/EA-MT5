"""Hand-computed T007 cases (shared by tests/test_t007_planning.py and src/tests/T007_PlanningTest.mq5).

Expected values were derived BY HAND (not by the code formula) with tick 0.01, digits 2 unless stated. The plan rows run the
REAL T005 and T006 references (and TradeGeometry.mqh / PositionSizing.mqh in MQL5). Numbers in the limits are ARBITRARY TEST
VALUES (positions 3, trades 5, cap 5000.0): they are NOT the client limits and decide nothing about 2-vs-3 trades.

PLAN rows
  BASIC BUY   E 1950.40 S 1944.15: |195040-194415| = 625 ticks, R_geom 6.25, level_2R = 1950.40 + 12.50 = 1962.90 = TP = partial.
              budget 1234.56, tick_value 1: loss/lot 625, raw 1.975296 -> 197 steps of .01 = 1.97 lots, risk 197*.01*625 = 1231.25.
  BASIC SELL  E 2310.20 S 2316.45 (mirror): R 6.25, level_2R = 2310.20 - 12.50 = 2297.70; volume 1.97, risk 1231.25.
  NORMALIZED  BUY E 1950.404 -> 195040.4 ticks -> 195040 -> 1950.40; S 1944.146 -> 194414.6 -> 194415 -> 1944.15 (same plan).
              SELL E 2310.196 -> 231019.6 -> 231020 -> 2310.20; S 2316.454 -> 231645.4 -> 231645 -> 2316.45.
  TARGET      BUY T 1970.00 is farther than 1962.90: TP 1970.00 (level_2R and partial stay 1962.90); BUY T 1955.00 is nearer: TP 1962.90.
              SELL T 2290.00 farther than 2297.70: TP 2290.00; SELL T 2305.00 nearer: TP 2297.70.
  TICK .05    BUY E 2500.05 S 2492.45: 152 ticks, R 7.60, 2R = 2500.05 + 15.20 = 2515.25; tick_value 5 -> loss/lot 760, budget 2000:
              2.6315 lots -> 263 steps = 2.63 lots, risk 263*.01*760 = 1998.8.  SELL E 2500.05 S 2507.65: 2R = 2484.85, same volume.
  STEP .1     BUY basic with step .1 / min .1: 19 steps = 1.9 lots, risk 19*.1*625 = 1187.5.
  QUOTE       BUY basic with ask 1951.00 bid 1950.90: gap (1951.00-1950.40)/.01 = 60 points > 0: plan unchanged.
  REFUSALS    SL on the wrong side, E == S, direction HOLD, tick .001 with digits 2, negative entry, target below a BUY entry,
              stops_level 700 > 625 points, ask 1950.40 == E (gap 0): each GEOMETRY_REFUSED with the T005 status.
              budget 50 with min .10 (8 steps < 10), budget 5 (0 steps), max 1.5 (197 > 150), cap 1.5 (197 > 150), step 0,
              min .015, budget 0, tick_value -1: SIZING_REFUSED with the T006 status. Empty/blank ids: INVALID_INPUT, stage INPUT,
              before any geometry.
PERMIT rows: BASIC plans have risk_model 1231.25. Limits positions 3 (allow <3), trades 5 (allow <5), cap 5000.0:
  3768.75 + 1231.25 = 5000.00 exactly at the cap (ALLOWED, proposal); 3768.76 + 1231.25 = 5000.01 (BLOCK).
  Binary noise: SELL_TICK005 plan risk is 1998.8 (stored as 1998.8000000000002); existing 0.01, cap 1998.81: decimal sum 1998.81 =
  cap (allowed; the binary sum is 1 ulp above the cap); existing 0.02 is a real excess (1 cent) and blocks.
PLAN VALIDATION rows (check_permit requires status OK + stage COMPLETE + non-blank ids + the 8 plan numbers finite and > 0):
  the plan is BUY_BASIC with one MODIFICATION (mod): ZERO_INPUT = the all-zero struct (status OK, stage INPUT, blank ids, zeros) ->
  PLAN_NOT_OK only; ZERO_COMPLETE = same with stage COMPLETE -> PLAN_INVALID_ID|PLAN_INVALID_VALUES; STAGE_* -> PLAN_NOT_OK;
  blank/empty signal or setup id -> PLAN_INVALID_ID; ('FIELD', name, kind) with kind NAN/INF/NEGINF/NEG(-1)/ZERO -> PLAN_INVALID_VALUES.
  Every permit row is also run through authorize on a second copy of the registry: ALLOW appends exactly the signal id, every
  refusal leaves ids and count identical (count override cnt: a registry count that does not match the ids, e.g. 3 with capacity 2).
OVERFLOW rows (real T005/T006 plans, E 2, SL 1, tick 1, digits 0, point 1, volume 1/1/1/1): R_geom 1, level_2R = 2 + 2 = 4 = TP,
  budget = tick_value = B -> loss/lot B, volume 1.0, risk_model B.
  B = 1e308, existing 1e308, cap DBL_MAX (1.7976931348623157e308): the true sum 2e308 > cap -> BLOCK (a naive float sum is inf and
  inf > inf is false). Mirror: existing 7e307 + 1e308 = 1.7e308 <= cap -> ALLOW; existing 8e307 + 1e308 = 1.8e308 > cap -> BLOCK.
  B = 4e307: existing 4e307, cap 8e307 -> exactly at the cap -> ALLOW; existing 4.1e307 -> 8.1e307 > 8e307 -> BLOCK; existing 5e307
  with cap 4e307 (already above the cap) -> BLOCK. existing DBL_MAX + plan 1e308 with cap DBL_MAX -> BLOCK (existing + 1231.25 would be absorbed by float resolution: tolerance there is 7e292).
CANCEL rows: events bitmask 1 DIRECTION_CHANGE, 2 OPPOSITE_SIGNAL, 4 SESSION_END, 8 NEWS_BLOCK, 16 DAILY_LIMIT; 12 = SESSION_END+NEWS_BLOCK;
  17 = DIRECTION_CHANGE+DAILY_LIMIT; 31 = all; 32 and above, negative: unknown.
"""

BUY, SELL, HOLD = 'BUY', 'SELL', 'HOLD'
SIGN = {BUY: 1, SELL: -1, HOLD: 0}
SYM = (0.01, 2, 0.01, 0)                    # tick_size, digits, point, stops_level
SYM05 = (0.05, 2, 0.01, 0)
OKS, INV, GREF, SREF = 'OK', 'INVALID_INPUT', 'GEOMETRY_REFUSED', 'SIZING_REFUSED'
S_INPUT, S_GEO, S_SIZ, S_DONE = 'INPUT', 'GEOMETRY', 'SIZING', 'COMPLETE'

PLAN_CASES = []


def VOL(vmin=0.01, step=0.01, vmax=100.0, cap=10.0):
    return (vmin, step, vmax, cap)


def plan(name, d, e, s, status, stage, exp=None, why='', under='', under_why='', t=None, budget=1234.56, tv=1.0,
         sym=SYM, quote=None, vol=None, sid='SIG-1', setup='SET-1'):
    """exp = (e_out, s_out, tp, level_2r, partial_price, r_geom, volume_out, risk_model) for an OK plan."""
    CASES_ARGS = (sid, setup, d, e, s, t, budget, tv, sym, quote, vol or VOL())
    PLAN_CASES.append(dict(name=name, args=CASES_ARGS, status=status, stage=stage, exp=exp, why=why, under=under,
                           under_why=under_why))


def ok(e_out, s_out, tp, lvl, rg, vol, risk):
    return (e_out, s_out, tp, lvl, lvl, rg, vol, risk)


# --- OK plans, BUY and mirrored SELL ---------------------------------------------------------------------------------
plan('BUY_BASIC', BUY, 1950.40, 1944.15, OKS, S_DONE, ok(1950.40, 1944.15, 1962.90, 1962.90, 6.25, 1.97, 1231.25))
plan('SELL_BASIC', SELL, 2310.20, 2316.45, OKS, S_DONE, ok(2310.20, 2316.45, 2297.70, 2297.70, 6.25, 1.97, 1231.25))
plan('BUY_NORMALIZED', BUY, 1950.404, 1944.146, OKS, S_DONE, ok(1950.40, 1944.15, 1962.90, 1962.90, 6.25, 1.97, 1231.25))
plan('SELL_NORMALIZED', SELL, 2310.196, 2316.454, OKS, S_DONE, ok(2310.20, 2316.45, 2297.70, 2297.70, 6.25, 1.97, 1231.25))
plan('BUY_TARGET_FARTHER', BUY, 1950.40, 1944.15, OKS, S_DONE, ok(1950.40, 1944.15, 1970.00, 1962.90, 6.25, 1.97, 1231.25), t=1970.00)
plan('SELL_TARGET_FARTHER', SELL, 2310.20, 2316.45, OKS, S_DONE, ok(2310.20, 2316.45, 2290.00, 2297.70, 6.25, 1.97, 1231.25), t=2290.00)
plan('BUY_TARGET_NEARER', BUY, 1950.40, 1944.15, OKS, S_DONE, ok(1950.40, 1944.15, 1962.90, 1962.90, 6.25, 1.97, 1231.25), t=1955.00)
plan('SELL_TARGET_NEARER', SELL, 2310.20, 2316.45, OKS, S_DONE, ok(2310.20, 2316.45, 2297.70, 2297.70, 6.25, 1.97, 1231.25), t=2305.00)
plan('BUY_TICK005', BUY, 2500.05, 2492.45, OKS, S_DONE, ok(2500.05, 2492.45, 2515.25, 2515.25, 7.60, 2.63, 1998.8),
     budget=2000.0, tv=5.0, sym=SYM05)
plan('SELL_TICK005', SELL, 2500.05, 2507.65, OKS, S_DONE, ok(2500.05, 2507.65, 2484.85, 2484.85, 7.60, 2.63, 1998.8),
     budget=2000.0, tv=5.0, sym=SYM05)
plan('BUY_STEP_01', BUY, 1950.40, 1944.15, OKS, S_DONE, ok(1950.40, 1944.15, 1962.90, 1962.90, 6.25, 1.9, 1187.5),
     vol=VOL(vmin=0.1, step=0.1))
plan('BUY_WITH_QUOTE', BUY, 1950.40, 1944.15, OKS, S_DONE, ok(1950.40, 1944.15, 1962.90, 1962.90, 6.25, 1.97, 1231.25),
     quote=(1950.90, 1951.00))
# --- geometry refused: the T005 status and reason are propagated, plan numbers are 0 --------------------------------------
plan('GEO_SL_WRONG_SIDE_BUY', BUY, 1950.40, 1955.00, GREF, S_GEO, under='SL_WRONG_SIDE', why='GEOMETRY_REFUSED: geometry SL_WRONG_SIDE')
plan('GEO_SL_WRONG_SIDE_SELL', SELL, 2310.20, 2300.00, GREF, S_GEO, under='SL_WRONG_SIDE', why='GEOMETRY_REFUSED: geometry SL_WRONG_SIDE')
plan('GEO_ZERO_RISK', BUY, 1950.40, 1950.40, GREF, S_GEO, under='ZERO_RISK', why='GEOMETRY_REFUSED: geometry ZERO_RISK')
plan('GEO_BAD_DIRECTION', HOLD, 1950.40, 1944.15, GREF, S_GEO, under='INVALID_DIRECTION', why='GEOMETRY_REFUSED: geometry INVALID_DIRECTION')
plan('GEO_INCOMPATIBLE_TICK', BUY, 1950.40, 1944.15, GREF, S_GEO, under='INVALID_INPUT', under_why='INCOMPATIBLE_TICK_DIGITS',
     why='GEOMETRY_REFUSED: geometry INVALID_INPUT', sym=(0.001, 2, 0.01, 0))
plan('GEO_NONPOSITIVE_PRICE', BUY, -5.0, 1944.15, GREF, S_GEO, under='INVALID_INPUT', under_why='prices must be > 0',
     why='GEOMETRY_REFUSED: geometry INVALID_INPUT')
plan('GEO_TARGET_WRONG_SIDE', BUY, 1950.40, 1944.15, GREF, S_GEO, under='TARGET_WRONG_SIDE', why='GEOMETRY_REFUSED: geometry TARGET_WRONG_SIDE', t=1949.00)
plan('GEO_BELOW_STOPS_LEVEL', BUY, 1950.40, 1944.15, GREF, S_GEO, under='BELOW_STOPS_LEVEL', why='GEOMETRY_REFUSED: geometry BELOW_STOPS_LEVEL',
     sym=(0.01, 2, 0.01, 700))
plan('GEO_PENDING_TOO_CLOSE', BUY, 1950.40, 1944.15, GREF, S_GEO, under='PENDING_TOO_CLOSE', why='GEOMETRY_REFUSED: geometry PENDING_TOO_CLOSE',
     quote=(1950.30, 1950.40))
plan('GEO_WINS_OVER_SIZING', BUY, 1950.40, 1955.00, GREF, S_GEO, under='SL_WRONG_SIDE', why='GEOMETRY_REFUSED', budget=0.0)
# --- sizing refused: the T006 status and reason are propagated ------------------------------------------------------------
plan('SIZ_BELOW_MIN', BUY, 1950.40, 1944.15, SREF, S_SIZ, under='SKIP_BELOW_MIN_VOLUME', why='SIZING_REFUSED: sizing SKIP_BELOW_MIN_VOLUME',
     budget=50.0, vol=VOL(vmin=0.10))
plan('SIZ_ROUNDS_TO_ZERO', SELL, 2310.20, 2316.45, SREF, S_SIZ, under='SKIP_BELOW_MIN_VOLUME', why='SIZING_REFUSED: sizing SKIP_BELOW_MIN_VOLUME',
     budget=5.0)
plan('SIZ_ABOVE_MAX', BUY, 1950.40, 1944.15, SREF, S_SIZ, under='SKIP_ABOVE_MAX_VOLUME', why='SIZING_REFUSED: sizing SKIP_ABOVE_MAX_VOLUME',
     vol=VOL(vmax=1.5))
plan('SIZ_ABOVE_CAP_BUY', BUY, 1950.40, 1944.15, SREF, S_SIZ, under='SKIP_ABOVE_CAP', why='SIZING_REFUSED: sizing SKIP_ABOVE_CAP',
     vol=VOL(cap=1.5))
plan('SIZ_ABOVE_CAP_SELL', SELL, 2310.20, 2316.45, SREF, S_SIZ, under='SKIP_ABOVE_CAP', why='SIZING_REFUSED: sizing SKIP_ABOVE_CAP',
     vol=VOL(cap=1.5))
plan('SIZ_BAD_STEP', BUY, 1950.40, 1944.15, SREF, S_SIZ, under='INVALID_INPUT', under_why='INVALID_VOLUME_STEP',
     why='SIZING_REFUSED: sizing INVALID_INPUT', vol=VOL(step=0.0))
plan('SIZ_OFF_GRID_MIN', BUY, 1950.40, 1944.15, SREF, S_SIZ, under='INVALID_INPUT', under_why='VOLUME_NOT_ON_GRID',
     why='SIZING_REFUSED: sizing INVALID_INPUT', vol=VOL(vmin=0.015))
plan('SIZ_BAD_BUDGET', BUY, 1950.40, 1944.15, SREF, S_SIZ, under='INVALID_INPUT', under_why='INVALID_RISK_BUDGET',
     why='SIZING_REFUSED: sizing INVALID_INPUT', budget=0.0)
plan('SIZ_BAD_TICK_VALUE', SELL, 2310.20, 2316.45, SREF, S_SIZ, under='INVALID_INPUT', under_why='INVALID_TICK_VALUE',
     why='SIZING_REFUSED: sizing INVALID_INPUT', tv=-1.0)
# --- ids ------------------------------------------------------------------------------------------------------------
plan('ID_EMPTY_SIGNAL', BUY, 1950.40, 1944.15, INV, S_INPUT, why='INVALID_SIGNAL_ID', sid='')
plan('ID_BLANK_SIGNAL', BUY, 1950.40, 1944.15, INV, S_INPUT, why='INVALID_SIGNAL_ID', sid='   ')
plan('ID_EMPTY_SETUP', BUY, 1950.40, 1944.15, INV, S_INPUT, why='INVALID_SETUP_ID', setup='')
plan('ID_BOTH_EMPTY_SIGNAL_FIRST', BUY, 1950.40, 1944.15, INV, S_INPUT, why='INVALID_SIGNAL_ID', sid='', setup='')
plan('ID_WINS_OVER_GEOMETRY', BUY, 1950.40, 1955.00, INV, S_INPUT, why='INVALID_SETUP_ID', setup='')

# --- overflow plans: real T005/T006 results with huge budgets -------------------------------------------------------------
SYM1 = (1.0, 0, 1.0, 0)
UNIT = VOL(vmin=1.0, step=1.0, vmax=1.0, cap=1.0)
plan('OVR_1E308', BUY, 2.0, 1.0, OKS, S_DONE, ok(2.0, 1.0, 4.0, 4.0, 1.0, 1.0, 1e308), budget=1e308, tv=1e308, sym=SYM1, vol=UNIT)
plan('HUGE_4E307', BUY, 2.0, 1.0, OKS, S_DONE, ok(2.0, 1.0, 4.0, 4.0, 1.0, 1.0, 4e307), budget=4e307, tv=4e307, sym=SYM1, vol=UNIT)

# --- permit rows -----------------------------------------------------------------------------------------------------
PERMIT_CASES = []
LIM = dict(pos=3, trd=5, cap=5000.0)


DBL_MAX = 1.7976931348623157e308
PLAN_FIELDS = ('e_out', 's_out', 'tp', 'level_2r', 'partial_price', 'r_geom', 'volume_out', 'risk_model')
MOD_KINDS = ('ZERO_INPUT', 'ZERO_COMPLETE', 'STAGE_INPUT', 'STAGE_GEOMETRY', 'STAGE_SIZING', 'SIGNAL_BLANK', 'SIGNAL_EMPTY',
             'SETUP_EMPTY', 'SETUP_BLANK')                  # MQL codes 1..9, FIELD = 10
VALUE_KINDS = ('NAN', 'INF', 'NEG', 'ZERO', 'NEGINF')       # MQL codes 0..4


def permit(name, plan_name, dec, reasons='', data='READY', rel=True, sess='OPEN', news='CLEAR', spr='CLEAR', pos=0, trd=0,
           risk=0.0, lim=None, reg=(), capacity=4, mod=None, cnt=None):
    L = dict(LIM)
    L.update(lim or {})
    PERMIT_CASES.append(dict(name=name, plan=plan_name, dec=dec, reasons=reasons, data=data, rel=rel, sess=sess, news=news,
                             spr=spr, pos=pos, trd=trd, risk=risk, lim=L, reg=tuple(reg), capacity=capacity, mod=mod, cnt=cnt))


permit('ALLOW_BUY', 'BUY_BASIC', 'ALLOW')
permit('ALLOW_SELL', 'SELL_BASIC', 'ALLOW')
permit('PLAN_GEOMETRY_REFUSED', 'GEO_SL_WRONG_SIDE_BUY', 'BLOCK', 'PLAN_NOT_OK')
permit('PLAN_SIZING_REFUSED', 'SIZ_ABOVE_CAP_BUY', 'BLOCK', 'PLAN_NOT_OK')
permit('PLAN_INVALID_ID', 'ID_EMPTY_SIGNAL', 'BLOCK', 'PLAN_NOT_OK')
permit('DATA_NOT_READY', 'BUY_BASIC', 'BLOCK', 'DATA_NOT_READY', data='NOT_READY')
permit('DATA_NOT_READY_AND_UNRELIABLE', 'BUY_BASIC', 'BLOCK', 'DATA_NOT_READY', data='NOT_READY', rel=False)
permit('DATA_UNKNOWN', 'BUY_BASIC', 'BLOCK', 'DATA_UNKNOWN', data='UNKNOWN')
permit('DATA_UNRELIABLE', 'BUY_BASIC', 'BLOCK', 'DATA_UNRELIABLE', rel=False)
permit('DATA_INVALID_STATE', 'BUY_BASIC', 'BLOCK', 'INVALID_SNAPSHOT:data_state', data='BOGUS')
permit('SESSION_CLOSED', 'BUY_BASIC', 'BLOCK', 'SESSION_CLOSED', sess='CLOSED')
permit('SESSION_UNKNOWN', 'BUY_BASIC', 'BLOCK', 'SESSION_UNKNOWN', sess='UNKNOWN')
permit('SESSION_INVALID_STATE', 'BUY_BASIC', 'BLOCK', 'INVALID_SNAPSHOT:session_state', sess='BOGUS')
permit('NEWS_BLOCK', 'BUY_BASIC', 'BLOCK', 'NEWS_BLOCK', news='BLOCKED')
permit('NEWS_UNKNOWN', 'BUY_BASIC', 'BLOCK', 'NEWS_UNKNOWN', news='UNKNOWN')
permit('NEWS_INVALID_STATE', 'BUY_BASIC', 'BLOCK', 'INVALID_SNAPSHOT:news_state', news='BOGUS')
permit('SPREAD_BLOCK', 'BUY_BASIC', 'BLOCK', 'SPREAD_BLOCK', spr='BLOCKED')
permit('SPREAD_UNKNOWN', 'BUY_BASIC', 'BLOCK', 'SPREAD_UNKNOWN', spr='UNKNOWN')
permit('SPREAD_INVALID_STATE', 'BUY_BASIC', 'BLOCK', 'INVALID_SNAPSHOT:spread_state', spr='BOGUS')
# boundaries: positions < max allows, == max blocks
permit('POSITIONS_BELOW_MAX', 'BUY_BASIC', 'ALLOW', pos=2)
permit('POSITIONS_AT_MAX', 'BUY_BASIC', 'BLOCK', 'MAX_POSITIONS_REACHED', pos=3)
permit('POSITIONS_ABOVE_MAX', 'BUY_BASIC', 'BLOCK', 'MAX_POSITIONS_REACHED', pos=4)
permit('POSITIONS_MAX_ZERO', 'BUY_BASIC', 'BLOCK', 'MAX_POSITIONS_REACHED', lim=dict(pos=0))
permit('TRADES_BELOW_MAX', 'BUY_BASIC', 'ALLOW', trd=4)
permit('TRADES_AT_MAX', 'BUY_BASIC', 'BLOCK', 'MAX_TRADES_REACHED', trd=5)
permit('TRADES_ABOVE_MAX', 'BUY_BASIC', 'BLOCK', 'MAX_TRADES_REACHED', trd=6)
# combined risk: existing + plan risk <= cap allows (exactly at the cap is allowed, proposal)
permit('RISK_EXACTLY_AT_CAP', 'BUY_BASIC', 'ALLOW', risk=3768.75)
permit('RISK_ONE_CENT_OVER_CAP', 'BUY_BASIC', 'BLOCK', 'COMBINED_RISK_EXCEEDED', risk=3768.76)
permit('RISK_FAR_OVER_CAP', 'BUY_BASIC', 'BLOCK', 'COMBINED_RISK_EXCEEDED', risk=4000.0)
permit('RISK_PLAN_ALONE_AT_CAP', 'BUY_BASIC', 'ALLOW', lim=dict(cap=1231.25))
permit('RISK_PLAN_ALONE_OVER_CAP', 'BUY_BASIC', 'BLOCK', 'COMBINED_RISK_EXCEEDED', lim=dict(cap=1231.24))
permit('RISK_BINARY_NOISE_AT_CAP', 'SELL_TICK005', 'ALLOW', risk=0.01, lim=dict(cap=1998.81))
permit('RISK_BINARY_NOISE_REAL_EXCESS', 'SELL_TICK005', 'BLOCK', 'COMBINED_RISK_EXCEEDED', risk=0.02, lim=dict(cap=1998.81))
permit('RISK_SELL_AT_CAP', 'SELL_TICK005', 'ALLOW', risk=3001.2)
permit('RISK_SELL_ONE_CENT_OVER', 'SELL_TICK005', 'BLOCK', 'COMBINED_RISK_EXCEEDED', risk=3001.21)
# policy UNSET never invents a limit
permit('POLICY_UNSET_POSITIONS', 'BUY_BASIC', 'BLOCK', 'POLICY_UNSET:max_positions', lim=dict(pos=None))
permit('POLICY_UNSET_TRADES', 'BUY_BASIC', 'BLOCK', 'POLICY_UNSET:max_trades_per_day', lim=dict(trd=None))
permit('POLICY_UNSET_RISK_CAP', 'BUY_BASIC', 'BLOCK', 'POLICY_UNSET:combined_risk_cap', lim=dict(cap=None))
permit('POLICY_UNSET_ALL', 'BUY_BASIC', 'BLOCK',
       'POLICY_UNSET:max_positions|POLICY_UNSET:max_trades_per_day|POLICY_UNSET:combined_risk_cap',
       lim=dict(pos=None, trd=None, cap=None))
permit('POLICY_UNSET_WINS_OVER_COUNT', 'BUY_BASIC', 'BLOCK', 'POLICY_UNSET:max_positions', lim=dict(pos=None), pos=-1)
permit('POLICY_UNSET_AND_DATA_UNKNOWN', 'BUY_BASIC', 'BLOCK', 'DATA_UNKNOWN|POLICY_UNSET:max_trades_per_day', data='UNKNOWN',
       lim=dict(trd=None))
# invalid numbers block
permit('INVALID_OPEN_POSITIONS', 'BUY_BASIC', 'BLOCK', 'INVALID_SNAPSHOT:open_positions', pos=-1)
permit('INVALID_TRADES_TODAY', 'BUY_BASIC', 'BLOCK', 'INVALID_SNAPSHOT:trades_today', trd=-1)
permit('INVALID_EXISTING_RISK', 'BUY_BASIC', 'BLOCK', 'INVALID_SNAPSHOT:existing_risk', risk=-1.0)
permit('INVALID_LIMIT_POSITIONS', 'BUY_BASIC', 'BLOCK', 'INVALID_SNAPSHOT:max_positions', lim=dict(pos=-1))
permit('INVALID_LIMIT_TRADES', 'BUY_BASIC', 'BLOCK', 'INVALID_SNAPSHOT:max_trades_per_day', lim=dict(trd=-2))
permit('INVALID_LIMIT_CAP', 'BUY_BASIC', 'BLOCK', 'INVALID_SNAPSHOT:combined_risk_cap', lim=dict(cap=-1.0))
# registry
permit('REGISTRY_OTHER_ID_ALLOWS', 'BUY_BASIC', 'ALLOW', reg=('SIG-0', 'SIG-9'))
permit('REGISTRY_DUPLICATE', 'BUY_BASIC', 'BLOCK', 'DUPLICATE_SIGNAL', reg=('SIG-0', 'SIG-1'))
permit('REGISTRY_FULL_NEW_ID', 'BUY_BASIC', 'BLOCK', 'REGISTRY_FULL', reg=('A', 'B'), capacity=2)
permit('REGISTRY_FULL_BUT_DUPLICATE', 'BUY_BASIC', 'BLOCK', 'DUPLICATE_SIGNAL', reg=('SIG-1', 'B'), capacity=2)
permit('REGISTRY_CAPACITY_ZERO', 'BUY_BASIC', 'BLOCK', 'REGISTRY_FULL', capacity=0)
permit('REGISTRY_LAST_SLOT_FREE', 'BUY_BASIC', 'ALLOW', reg=('A',), capacity=2)
permit('REGISTRY_COUNT_ABOVE_CAPACITY', 'BUY_BASIC', 'BLOCK', 'REGISTRY_INVALID', capacity=2, cnt=3)
permit('REGISTRY_COUNT_NEGATIVE', 'BUY_BASIC', 'BLOCK', 'REGISTRY_INVALID', capacity=2, cnt=-1)
permit('REGISTRY_CAPACITY_ZERO_COUNT_ONE', 'BUY_BASIC', 'BLOCK', 'REGISTRY_INVALID', capacity=0, cnt=1)
permit('REGISTRY_FULL_WITH_BLANK_ID', 'BUY_BASIC', 'BLOCK', 'PLAN_INVALID_ID|REGISTRY_FULL', capacity=0, mod='SIGNAL_BLANK')
# plan validation: an incomplete or malformed plan never gets ALLOW (and never reaches the registry)
permit('PLAN_ZERO_INPUT', 'BUY_BASIC', 'BLOCK', 'PLAN_NOT_OK', mod='ZERO_INPUT')
permit('PLAN_ZERO_COMPLETE', 'BUY_BASIC', 'BLOCK', 'PLAN_INVALID_ID|PLAN_INVALID_VALUES', mod='ZERO_COMPLETE')
permit('PLAN_ZERO_INPUT_REGISTRY_CAPACITY_ZERO', 'BUY_BASIC', 'BLOCK', 'PLAN_NOT_OK|REGISTRY_FULL', mod='ZERO_INPUT', capacity=0)
permit('PLAN_ZERO_COMPLETE_REGISTRY_CAPACITY_ZERO', 'BUY_BASIC', 'BLOCK', 'PLAN_INVALID_ID|PLAN_INVALID_VALUES|REGISTRY_FULL',
       mod='ZERO_COMPLETE', capacity=0)
permit('PLAN_STAGE_INPUT', 'BUY_BASIC', 'BLOCK', 'PLAN_NOT_OK', mod='STAGE_INPUT')
permit('PLAN_STAGE_GEOMETRY', 'BUY_BASIC', 'BLOCK', 'PLAN_NOT_OK', mod='STAGE_GEOMETRY')
permit('PLAN_STAGE_SIZING', 'BUY_BASIC', 'BLOCK', 'PLAN_NOT_OK', mod='STAGE_SIZING')
permit('PLAN_SIGNAL_BLANK', 'BUY_BASIC', 'BLOCK', 'PLAN_INVALID_ID', mod='SIGNAL_BLANK')
permit('PLAN_SIGNAL_EMPTY', 'BUY_BASIC', 'BLOCK', 'PLAN_INVALID_ID', mod='SIGNAL_EMPTY')
permit('PLAN_SETUP_EMPTY', 'BUY_BASIC', 'BLOCK', 'PLAN_INVALID_ID', mod='SETUP_EMPTY')
permit('PLAN_SETUP_BLANK', 'BUY_BASIC', 'BLOCK', 'PLAN_INVALID_ID', mod='SETUP_BLANK')
for _f in PLAN_FIELDS:
    for _k in VALUE_KINDS:
        permit('PLAN_FIELD_%s_%s' % (_f.upper(), _k), 'BUY_BASIC', 'BLOCK', 'PLAN_INVALID_VALUES', mod=('FIELD', _f, _k))
# combined risk at huge magnitudes: no overflow to infinity (real T005/T006 plans OVR_1E308 and HUGE_4E307)
permit('RISK_OVERFLOW_1E308', 'OVR_1E308', 'BLOCK', 'COMBINED_RISK_EXCEEDED', risk=1e308, lim=dict(cap=DBL_MAX))
permit('RISK_OVERFLOW_MIRROR_ALLOW', 'OVR_1E308', 'ALLOW', risk=7e307, lim=dict(cap=DBL_MAX))
permit('RISK_OVERFLOW_MIRROR_BLOCK', 'OVR_1E308', 'BLOCK', 'COMBINED_RISK_EXCEEDED', risk=8e307, lim=dict(cap=DBL_MAX))
permit('RISK_PLAN_ALONE_UNDER_DBL_MAX', 'OVR_1E308', 'ALLOW', lim=dict(cap=DBL_MAX))
permit('RISK_EXISTING_DBL_MAX_PLUS_BIG_PLAN', 'OVR_1E308', 'BLOCK', 'COMBINED_RISK_EXCEEDED', risk=DBL_MAX, lim=dict(cap=DBL_MAX))
permit('RISK_LARGE_EXACT_BOUNDARY', 'HUGE_4E307', 'ALLOW', risk=4e307, lim=dict(cap=8e307))
permit('RISK_LARGE_OVER', 'HUGE_4E307', 'BLOCK', 'COMBINED_RISK_EXCEEDED', risk=4.1e307, lim=dict(cap=8e307))
permit('RISK_LARGE_EXISTING_ABOVE_CAP', 'HUGE_4E307', 'BLOCK', 'COMBINED_RISK_EXCEEDED', risk=5e307, lim=dict(cap=4e307))
# several reasons together, fixed order
ALL_BAD = dict(data='NOT_READY', sess='CLOSED', news='BLOCKED', spr='BLOCKED', pos=3, trd=5, risk=4000.0, reg=('SIG-1',))
permit('ALL_REASONS_IN_FIXED_ORDER', 'BUY_BASIC', 'BLOCK',
       'DATA_NOT_READY|SESSION_CLOSED|NEWS_BLOCK|SPREAD_BLOCK|DUPLICATE_SIGNAL|MAX_POSITIONS_REACHED|MAX_TRADES_REACHED|COMBINED_RISK_EXCEEDED',
       **ALL_BAD)
permit('ALL_REASONS_WITH_BAD_PLAN', 'GEO_SL_WRONG_SIDE_BUY', 'BLOCK',
       'PLAN_NOT_OK|DATA_NOT_READY|SESSION_CLOSED|NEWS_BLOCK|SPREAD_BLOCK|DUPLICATE_SIGNAL|MAX_POSITIONS_REACHED|MAX_TRADES_REACHED',
       **ALL_BAD)
permit('UNKNOWNS_TOGETHER', 'BUY_BASIC', 'BLOCK', 'DATA_UNKNOWN|SESSION_UNKNOWN|NEWS_UNKNOWN|SPREAD_UNKNOWN',
       data='UNKNOWN', sess='UNKNOWN', news='UNKNOWN', spr='UNKNOWN')

# --- cancel rows -----------------------------------------------------------------------------------------------------
CANCEL_CASES = []


def cancel(name, pend, pid, pos, ev, status, reasons='', why=''):
    CANCEL_CASES.append(dict(name=name, pend=pend, pid=pid, pos=pos, ev=ev, status=status, reasons=reasons, why=why))


CR, NP, NE, CINV = 'CANCEL_REQUEST', 'NO_PENDING', 'NO_EVENT', 'INVALID_INPUT'
cancel('CAUSE_DIRECTION_CHANGE', True, 'SIG-1', False, 1, CR, 'DIRECTION_CHANGE')
cancel('CAUSE_OPPOSITE_SIGNAL', True, 'SIG-1', False, 2, CR, 'OPPOSITE_SIGNAL')
cancel('CAUSE_SESSION_END', True, 'SIG-1', False, 4, CR, 'SESSION_END')
cancel('CAUSE_NEWS_BLOCK', True, 'SIG-1', False, 8, CR, 'NEWS_BLOCK')
cancel('CAUSE_DAILY_LIMIT', True, 'SIG-1', False, 16, CR, 'DAILY_LIMIT')
cancel('COMBINED_SESSION_END_NEWS', True, 'SIG-1', False, 12, CR, 'SESSION_END|NEWS_BLOCK')
cancel('COMBINED_DIRECTION_DAILY', True, 'SIG-1', False, 17, CR, 'DIRECTION_CHANGE|DAILY_LIMIT')
cancel('COMBINED_ALL_FIVE', True, 'SIG-1', False, 31, CR, 'DIRECTION_CHANGE|OPPOSITE_SIGNAL|SESSION_END|NEWS_BLOCK|DAILY_LIMIT')
cancel('PENDING_AND_POSITION_ONLY_PENDING', True, 'SIG-1', True, 4, CR, 'SESSION_END')
cancel('PENDING_AND_POSITION_ALL_EVENTS', True, 'SIG-2', True, 31, CR, 'DIRECTION_CHANGE|OPPOSITE_SIGNAL|SESSION_END|NEWS_BLOCK|DAILY_LIMIT')
cancel('POSITION_ONLY_NO_REQUEST', False, '', True, 31, NP)
cancel('POSITION_ONLY_ONE_EVENT', False, '', True, 4, NP)
cancel('NOTHING_PENDING_NO_POSITION', False, '', False, 8, NP)
cancel('PENDING_ID_IGNORED_WHEN_NO_PENDING', False, 'SIG-1', False, 8, NP)
cancel('PENDING_WITHOUT_EVENT', True, 'SIG-1', False, 0, NE)
cancel('PENDING_AND_POSITION_WITHOUT_EVENT', True, 'SIG-1', True, 0, NE)
cancel('UNKNOWN_EVENT_32', True, 'SIG-1', False, 32, CINV, why='INVALID_EVENTS')
cancel('UNKNOWN_EVENT_BIT_WITH_KNOWN', True, 'SIG-1', False, 33, CINV, why='INVALID_EVENTS')
cancel('UNKNOWN_EVENT_NEGATIVE', True, 'SIG-1', False, -1, CINV, why='INVALID_EVENTS')
cancel('UNKNOWN_EVENT_WITHOUT_PENDING', False, '', True, 64, CINV, why='INVALID_EVENTS')
cancel('PENDING_EMPTY_ID', True, '', False, 4, CINV, why='INVALID_PENDING_SIGNAL_ID')
cancel('PENDING_BLANK_ID', True, '  ', True, 4, CINV, why='INVALID_PENDING_SIGNAL_ID')

# --- MQL5 data block -------------------------------------------------------------------------------------------------
DATA_INT = {'READY': 1, 'NOT_READY': 2, 'UNKNOWN': 3, 'BOGUS': 9}
SESS_INT = {'OPEN': 1, 'CLOSED': 2, 'UNKNOWN': 3, 'BOGUS': 9}
NEWS_INT = {'CLEAR': 1, 'BLOCKED': 2, 'UNKNOWN': 3, 'BOGUS': 9}
UNSET_INT = -1       # in the MQL5 table a limit is UNSET when its *_SET flag is 0


def _num(v):
    return repr(float(v))


def emit_mql():
    """Text of the MQL5 data block (kept in src/tests/T007_PlanningTest.mq5 between the markers)."""
    out = ['// BEGIN GENERATED FIXTURES (tests/t007_planning_fixtures.py emit_mql)']

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    def q(s):
        return '"%s"' % s

    P = PLAN_CASES
    out.append('#define NPLAN %d' % len(P))
    arr('string', 'P_NAME', [q(c['name']) for c in P])
    arr('string', 'P_SID', [q(c['args'][0]) for c in P])
    arr('string', 'P_SETUP', [q(c['args'][1]) for c in P])
    arr('int', 'P_DIR', [str(SIGN[c['args'][2]]) for c in P])
    arr('double', 'P_E', [_num(c['args'][3]) for c in P])
    arr('double', 'P_S', [_num(c['args'][4]) for c in P])
    arr('int', 'P_HAST', ['0' if c['args'][5] is None else '1' for c in P])
    arr('double', 'P_T', [_num(c['args'][5] or 0.0) for c in P])
    arr('double', 'P_BUDGET', [_num(c['args'][6]) for c in P])
    arr('double', 'P_TV', [_num(c['args'][7]) for c in P])
    arr('double', 'P_TICK', [_num(c['args'][8][0]) for c in P])
    arr('int', 'P_DIG', [str(c['args'][8][1]) for c in P])
    arr('double', 'P_POINT', [_num(c['args'][8][2]) for c in P])
    arr('int', 'P_STOPS', [str(c['args'][8][3]) for c in P])
    arr('int', 'P_HASQ', ['0' if c['args'][9] is None else '1' for c in P])
    arr('double', 'P_BID', [_num(c['args'][9][0] if c['args'][9] else 0.0) for c in P])
    arr('double', 'P_ASK', [_num(c['args'][9][1] if c['args'][9] else 0.0) for c in P])
    for i, nm in enumerate(('P_VMIN', 'P_STEP', 'P_VMAX', 'P_CAP')):
        arr('double', nm, [_num(c['args'][10][i]) for c in P])
    arr('string', 'PX_STATUS', [q(c['status']) for c in P])
    arr('string', 'PX_STAGE', [q(c['stage']) for c in P])
    arr('string', 'PX_UNDER', [q(c['under']) for c in P])
    arr('string', 'PX_UNDERWHY', [q(c['under_why']) for c in P])
    arr('string', 'PX_WHY', [q(c['why']) for c in P])
    arr('int', 'PX_HASNUM', ['0' if c['exp'] is None else '1' for c in P])
    ex = [c['exp'] if c['exp'] is not None else (0.0,) * 8 for c in P]
    for i, nm in enumerate(('PX_E', 'PX_S', 'PX_TP', 'PX_2R', 'PX_PARTIAL', 'PX_R', 'PX_VOL', 'PX_RISK')):
        arr('double', nm, [_num(x[i]) for x in ex])

    names = [c['name'] for c in P]
    M = PERMIT_CASES
    out.append('#define NPERMIT %d' % len(M))
    arr('string', 'M_NAME', [q(c['name']) for c in M])
    arr('int', 'M_PLAN', [str(names.index(c['plan'])) for c in M])
    arr('int', 'M_DATA', [str(DATA_INT[c['data']]) for c in M])
    arr('int', 'M_REL', ['1' if c['rel'] else '0' for c in M])
    arr('int', 'M_SESS', [str(SESS_INT[c['sess']]) for c in M])
    arr('int', 'M_NEWS', [str(NEWS_INT[c['news']]) for c in M])
    arr('int', 'M_SPR', [str(NEWS_INT[c['spr']]) for c in M])
    arr('long', 'M_POS', [str(c['pos']) for c in M])
    arr('long', 'M_TRD', [str(c['trd']) for c in M])
    arr('double', 'M_RISK', [_num(c['risk']) for c in M])
    arr('int', 'M_LPS', ['0' if c['lim']['pos'] is None else '1' for c in M])
    arr('long', 'M_LP', [str(c['lim']['pos'] or 0) for c in M])
    arr('int', 'M_LTS', ['0' if c['lim']['trd'] is None else '1' for c in M])
    arr('long', 'M_LT', [str(c['lim']['trd'] or 0) for c in M])
    arr('int', 'M_LCS', ['0' if c['lim']['cap'] is None else '1' for c in M])
    arr('double', 'M_LC', [_num(c['lim']['cap'] or 0.0) for c in M])
    arr('string', 'M_REG', [q('|'.join(c['reg'])) for c in M])
    arr('int', 'M_CNT', ['-1000' if c['cnt'] is None else str(c['cnt']) for c in M])   # -1000 = count is len(reg)

    def modk(m):
        if m is None:
            return 0
        return 10 if isinstance(m, tuple) else 1 + MOD_KINDS.index(m)
    arr('int', 'M_MODK', [str(modk(c['mod'])) for c in M])
    arr('int', 'M_MODF', [str(PLAN_FIELDS.index(c['mod'][1]) if isinstance(c['mod'], tuple) else 0) for c in M])
    arr('int', 'M_MODV', [str(VALUE_KINDS.index(c['mod'][2]) if isinstance(c['mod'], tuple) else 0) for c in M])
    arr('int', 'M_CAPREG', [str(c['capacity']) for c in M])
    arr('string', 'MX_DEC', [q(c['dec']) for c in M])
    arr('string', 'MX_REASONS', [q(c['reasons']) for c in M])

    K = CANCEL_CASES
    out.append('#define NCANCEL %d' % len(K))
    arr('string', 'K_NAME', [q(c['name']) for c in K])
    arr('int', 'K_PEND', ['1' if c['pend'] else '0' for c in K])
    arr('string', 'K_PID', [q(c['pid']) for c in K])
    arr('int', 'K_POS', ['1' if c['pos'] else '0' for c in K])
    arr('int', 'K_EV', [str(c['ev']) for c in K])
    arr('string', 'KX_STATUS', [q(c['status']) for c in K])
    arr('string', 'KX_WHY', [q(c['why']) for c in K])
    arr('string', 'KX_REASONS', [q(c['reasons']) for c in K])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
