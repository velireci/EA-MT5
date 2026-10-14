// T007 test script: pure trade planning, permit checks and pending-cancel decision. Mirrors tests/test_t007_planning.py; the
// fixtures below are the hand-computed tables of tests/t007_planning_fixtures.py. NOT YET COMPILED OR RUN in MT5 (UNVERIFIED).
// Tests the pure helpers only: no order, no account or symbol read, no live price, no clock. Says nothing about entry quality.
// The limits in the tables (positions 3, trades 5, cap 5000.0) are ARBITRARY TEST VALUES, not client limits.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/TradePlanning.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
bool Near(const double a,const double b) {return(MathAbs(a-b)<1e-9*MathMax(1.0,MathAbs(b)));}
// BEGIN GENERATED FIXTURES (tests/t007_planning_fixtures.py emit_mql)
#define NPLAN 38
string P_NAME[]={"BUY_BASIC","SELL_BASIC","BUY_NORMALIZED","SELL_NORMALIZED","BUY_TARGET_FARTHER","SELL_TARGET_FARTHER","BUY_TARGET_NEARER","SELL_TARGET_NEARER","BUY_TICK005","SELL_TICK005","BUY_STEP_01","BUY_WITH_QUOTE","GEO_SL_WRONG_SIDE_BUY","GEO_SL_WRONG_SIDE_SELL","GEO_ZERO_RISK","GEO_BAD_DIRECTION","GEO_INCOMPATIBLE_TICK","GEO_NONPOSITIVE_PRICE","GEO_TARGET_WRONG_SIDE","GEO_BELOW_STOPS_LEVEL","GEO_PENDING_TOO_CLOSE","GEO_WINS_OVER_SIZING","SIZ_BELOW_MIN","SIZ_ROUNDS_TO_ZERO","SIZ_ABOVE_MAX","SIZ_ABOVE_CAP_BUY","SIZ_ABOVE_CAP_SELL","SIZ_BAD_STEP","SIZ_OFF_GRID_MIN","SIZ_BAD_BUDGET","SIZ_BAD_TICK_VALUE","ID_EMPTY_SIGNAL","ID_BLANK_SIGNAL","ID_EMPTY_SETUP","ID_BOTH_EMPTY_SIGNAL_FIRST","ID_WINS_OVER_GEOMETRY","OVR_1E308","HUGE_4E307"};
string P_SID[]={"SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","","   ","SIG-1","","SIG-1","SIG-1","SIG-1"};
string P_SETUP[]={"SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","SET-1","","","","SET-1","SET-1"};
int P_DIR[]={1,-1,1,-1,1,-1,1,-1,1,-1,1,1,1,-1,1,0,1,1,1,1,1,1,1,-1,1,1,-1,1,1,1,-1,1,1,1,1,1,1,1};
double P_E[]={1950.4,2310.2,1950.404,2310.196,1950.4,2310.2,1950.4,2310.2,2500.05,2500.05,1950.4,1950.4,1950.4,2310.2,1950.4,1950.4,1950.4,-5.0,1950.4,1950.4,1950.4,1950.4,1950.4,2310.2,1950.4,1950.4,2310.2,1950.4,1950.4,1950.4,2310.2,1950.4,1950.4,1950.4,1950.4,1950.4,2.0,2.0};
double P_S[]={1944.15,2316.45,1944.146,2316.454,1944.15,2316.45,1944.15,2316.45,2492.45,2507.65,1944.15,1944.15,1955.0,2300.0,1950.4,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1955.0,1944.15,2316.45,1944.15,1944.15,2316.45,1944.15,1944.15,1944.15,2316.45,1944.15,1944.15,1944.15,1944.15,1955.0,1.0,1.0};
int P_HAST[]={0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
double P_T[]={0.0,0.0,0.0,0.0,1970.0,2290.0,1955.0,2305.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1949.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0};
double P_BUDGET[]={1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,2000.0,2000.0,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,0.0,50.0,5.0,1234.56,1234.56,1234.56,1234.56,1234.56,0.0,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1e+308,4e+307};
double P_TV[]={1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,5.0,5.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,-1.0,1.0,1.0,1.0,1.0,1.0,1e+308,4e+307};
double P_TICK[]={0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.05,0.05,0.01,0.01,0.01,0.01,0.01,0.01,0.001,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,1.0,1.0};
int P_DIG[]={2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,0};
double P_POINT[]={0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,1.0,1.0};
int P_STOPS[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,700,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int P_HASQ[]={0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
double P_BID[]={0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1950.9,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1950.3,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0};
double P_ASK[]={0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1951.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1950.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0};
double P_VMIN[]={0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.1,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.1,0.01,0.01,0.01,0.01,0.01,0.015,0.01,0.01,0.01,0.01,0.01,0.01,0.01,1.0,1.0};
double P_STEP[]={0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.1,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.0,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,1.0,1.0};
double P_VMAX[]={100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,1.5,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,1.0,1.0};
double P_CAP[]={10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,1.5,1.5,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,1.0,1.0};
string PX_STATUS[]={"OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","GEOMETRY_REFUSED","GEOMETRY_REFUSED","GEOMETRY_REFUSED","GEOMETRY_REFUSED","GEOMETRY_REFUSED","GEOMETRY_REFUSED","GEOMETRY_REFUSED","GEOMETRY_REFUSED","GEOMETRY_REFUSED","GEOMETRY_REFUSED","SIZING_REFUSED","SIZING_REFUSED","SIZING_REFUSED","SIZING_REFUSED","SIZING_REFUSED","SIZING_REFUSED","SIZING_REFUSED","SIZING_REFUSED","SIZING_REFUSED","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","OK","OK"};
string PX_STAGE[]={"COMPLETE","COMPLETE","COMPLETE","COMPLETE","COMPLETE","COMPLETE","COMPLETE","COMPLETE","COMPLETE","COMPLETE","COMPLETE","COMPLETE","GEOMETRY","GEOMETRY","GEOMETRY","GEOMETRY","GEOMETRY","GEOMETRY","GEOMETRY","GEOMETRY","GEOMETRY","GEOMETRY","SIZING","SIZING","SIZING","SIZING","SIZING","SIZING","SIZING","SIZING","SIZING","INPUT","INPUT","INPUT","INPUT","INPUT","COMPLETE","COMPLETE"};
string PX_UNDER[]={"","","","","","","","","","","","","SL_WRONG_SIDE","SL_WRONG_SIDE","ZERO_RISK","INVALID_DIRECTION","INVALID_INPUT","INVALID_INPUT","TARGET_WRONG_SIDE","BELOW_STOPS_LEVEL","PENDING_TOO_CLOSE","SL_WRONG_SIDE","SKIP_BELOW_MIN_VOLUME","SKIP_BELOW_MIN_VOLUME","SKIP_ABOVE_MAX_VOLUME","SKIP_ABOVE_CAP","SKIP_ABOVE_CAP","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","","","","","","",""};
string PX_UNDERWHY[]={"","","","","","","","","","","","","","","","","INCOMPATIBLE_TICK_DIGITS","prices must be > 0","","","","","","","","","","INVALID_VOLUME_STEP","VOLUME_NOT_ON_GRID","INVALID_RISK_BUDGET","INVALID_TICK_VALUE","","","","","","",""};
string PX_WHY[]={"","","","","","","","","","","","","GEOMETRY_REFUSED: geometry SL_WRONG_SIDE","GEOMETRY_REFUSED: geometry SL_WRONG_SIDE","GEOMETRY_REFUSED: geometry ZERO_RISK","GEOMETRY_REFUSED: geometry INVALID_DIRECTION","GEOMETRY_REFUSED: geometry INVALID_INPUT","GEOMETRY_REFUSED: geometry INVALID_INPUT","GEOMETRY_REFUSED: geometry TARGET_WRONG_SIDE","GEOMETRY_REFUSED: geometry BELOW_STOPS_LEVEL","GEOMETRY_REFUSED: geometry PENDING_TOO_CLOSE","GEOMETRY_REFUSED","SIZING_REFUSED: sizing SKIP_BELOW_MIN_VOLUME","SIZING_REFUSED: sizing SKIP_BELOW_MIN_VOLUME","SIZING_REFUSED: sizing SKIP_ABOVE_MAX_VOLUME","SIZING_REFUSED: sizing SKIP_ABOVE_CAP","SIZING_REFUSED: sizing SKIP_ABOVE_CAP","SIZING_REFUSED: sizing INVALID_INPUT","SIZING_REFUSED: sizing INVALID_INPUT","SIZING_REFUSED: sizing INVALID_INPUT","SIZING_REFUSED: sizing INVALID_INPUT","INVALID_SIGNAL_ID","INVALID_SIGNAL_ID","INVALID_SETUP_ID","INVALID_SIGNAL_ID","INVALID_SETUP_ID","",""};
int PX_HASNUM[]={1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1};
double PX_E[]={1950.4,2310.2,1950.4,2310.2,1950.4,2310.2,1950.4,2310.2,2500.05,2500.05,1950.4,1950.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2.0,2.0};
double PX_S[]={1944.15,2316.45,1944.15,2316.45,1944.15,2316.45,1944.15,2316.45,2492.45,2507.65,1944.15,1944.15,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1.0,1.0};
double PX_TP[]={1962.9,2297.7,1962.9,2297.7,1970.0,2290.0,1962.9,2297.7,2515.25,2484.85,1962.9,1962.9,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,4.0,4.0};
double PX_2R[]={1962.9,2297.7,1962.9,2297.7,1962.9,2297.7,1962.9,2297.7,2515.25,2484.85,1962.9,1962.9,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,4.0,4.0};
double PX_PARTIAL[]={1962.9,2297.7,1962.9,2297.7,1962.9,2297.7,1962.9,2297.7,2515.25,2484.85,1962.9,1962.9,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,4.0,4.0};
double PX_R[]={6.25,6.25,6.25,6.25,6.25,6.25,6.25,6.25,7.6,7.6,6.25,6.25,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1.0,1.0};
double PX_VOL[]={1.97,1.97,1.97,1.97,1.97,1.97,1.97,1.97,2.63,2.63,1.9,1.97,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1.0,1.0};
double PX_RISK[]={1231.25,1231.25,1231.25,1231.25,1231.25,1231.25,1231.25,1231.25,1998.8,1998.8,1187.5,1231.25,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1e+308,4e+307};
#define NPERMIT 119
string M_NAME[]={"ALLOW_BUY","ALLOW_SELL","PLAN_GEOMETRY_REFUSED","PLAN_SIZING_REFUSED","PLAN_INVALID_ID","DATA_NOT_READY","DATA_NOT_READY_AND_UNRELIABLE","DATA_UNKNOWN","DATA_UNRELIABLE","DATA_INVALID_STATE","SESSION_CLOSED","SESSION_UNKNOWN","SESSION_INVALID_STATE","NEWS_BLOCK","NEWS_UNKNOWN","NEWS_INVALID_STATE","SPREAD_BLOCK","SPREAD_UNKNOWN","SPREAD_INVALID_STATE","POSITIONS_BELOW_MAX","POSITIONS_AT_MAX","POSITIONS_ABOVE_MAX","POSITIONS_MAX_ZERO","TRADES_BELOW_MAX","TRADES_AT_MAX","TRADES_ABOVE_MAX","RISK_EXACTLY_AT_CAP","RISK_ONE_CENT_OVER_CAP","RISK_FAR_OVER_CAP","RISK_PLAN_ALONE_AT_CAP","RISK_PLAN_ALONE_OVER_CAP","RISK_BINARY_NOISE_AT_CAP","RISK_BINARY_NOISE_REAL_EXCESS","RISK_SELL_AT_CAP","RISK_SELL_ONE_CENT_OVER","POLICY_UNSET_POSITIONS","POLICY_UNSET_TRADES","POLICY_UNSET_RISK_CAP","POLICY_UNSET_ALL","POLICY_UNSET_WINS_OVER_COUNT","POLICY_UNSET_AND_DATA_UNKNOWN","INVALID_OPEN_POSITIONS","INVALID_TRADES_TODAY","INVALID_EXISTING_RISK","INVALID_LIMIT_POSITIONS","INVALID_LIMIT_TRADES","INVALID_LIMIT_CAP","REGISTRY_OTHER_ID_ALLOWS","REGISTRY_DUPLICATE","REGISTRY_FULL_NEW_ID","REGISTRY_FULL_BUT_DUPLICATE","REGISTRY_CAPACITY_ZERO","REGISTRY_LAST_SLOT_FREE","REGISTRY_COUNT_ABOVE_CAPACITY","REGISTRY_COUNT_NEGATIVE","REGISTRY_CAPACITY_ZERO_COUNT_ONE","REGISTRY_FULL_WITH_BLANK_ID","PLAN_ZERO_INPUT","PLAN_ZERO_COMPLETE","PLAN_ZERO_INPUT_REGISTRY_CAPACITY_ZERO","PLAN_ZERO_COMPLETE_REGISTRY_CAPACITY_ZERO","PLAN_STAGE_INPUT","PLAN_STAGE_GEOMETRY","PLAN_STAGE_SIZING","PLAN_SIGNAL_BLANK","PLAN_SIGNAL_EMPTY","PLAN_SETUP_EMPTY","PLAN_SETUP_BLANK","PLAN_FIELD_E_OUT_NAN","PLAN_FIELD_E_OUT_INF","PLAN_FIELD_E_OUT_NEG","PLAN_FIELD_E_OUT_ZERO","PLAN_FIELD_E_OUT_NEGINF","PLAN_FIELD_S_OUT_NAN","PLAN_FIELD_S_OUT_INF","PLAN_FIELD_S_OUT_NEG","PLAN_FIELD_S_OUT_ZERO","PLAN_FIELD_S_OUT_NEGINF","PLAN_FIELD_TP_NAN","PLAN_FIELD_TP_INF","PLAN_FIELD_TP_NEG","PLAN_FIELD_TP_ZERO","PLAN_FIELD_TP_NEGINF","PLAN_FIELD_LEVEL_2R_NAN","PLAN_FIELD_LEVEL_2R_INF","PLAN_FIELD_LEVEL_2R_NEG","PLAN_FIELD_LEVEL_2R_ZERO","PLAN_FIELD_LEVEL_2R_NEGINF","PLAN_FIELD_PARTIAL_PRICE_NAN","PLAN_FIELD_PARTIAL_PRICE_INF","PLAN_FIELD_PARTIAL_PRICE_NEG","PLAN_FIELD_PARTIAL_PRICE_ZERO","PLAN_FIELD_PARTIAL_PRICE_NEGINF","PLAN_FIELD_R_GEOM_NAN","PLAN_FIELD_R_GEOM_INF","PLAN_FIELD_R_GEOM_NEG","PLAN_FIELD_R_GEOM_ZERO","PLAN_FIELD_R_GEOM_NEGINF","PLAN_FIELD_VOLUME_OUT_NAN","PLAN_FIELD_VOLUME_OUT_INF","PLAN_FIELD_VOLUME_OUT_NEG","PLAN_FIELD_VOLUME_OUT_ZERO","PLAN_FIELD_VOLUME_OUT_NEGINF","PLAN_FIELD_RISK_MODEL_NAN","PLAN_FIELD_RISK_MODEL_INF","PLAN_FIELD_RISK_MODEL_NEG","PLAN_FIELD_RISK_MODEL_ZERO","PLAN_FIELD_RISK_MODEL_NEGINF","RISK_OVERFLOW_1E308","RISK_OVERFLOW_MIRROR_ALLOW","RISK_OVERFLOW_MIRROR_BLOCK","RISK_PLAN_ALONE_UNDER_DBL_MAX","RISK_EXISTING_DBL_MAX_PLUS_BIG_PLAN","RISK_LARGE_EXACT_BOUNDARY","RISK_LARGE_OVER","RISK_LARGE_EXISTING_ABOVE_CAP","ALL_REASONS_IN_FIXED_ORDER","ALL_REASONS_WITH_BAD_PLAN","UNKNOWNS_TOGETHER"};
int M_PLAN[]={0,1,12,25,31,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9,9,9,9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,36,36,36,36,36,37,37,37,0,12,0};
int M_DATA[]={1,1,1,1,1,2,2,3,1,9,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,3,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,3};
int M_REL[]={1,1,1,1,1,1,0,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
int M_SESS[]={1,1,1,1,1,1,1,1,1,1,2,3,9,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,3};
int M_NEWS[]={1,1,1,1,1,1,1,1,1,1,1,1,1,2,3,9,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,3};
int M_SPR[]={1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,3,9,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,3};
long M_POS[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,-1,0,-1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,3,0};
long M_TRD[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,5,6,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,-1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,5,0};
double M_RISK[]={0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,3768.75,3768.76,4000.0,0.0,0.0,0.01,0.02,3001.2,3001.21,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,-1.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1e+308,7e+307,8e+307,0.0,1.7976931348623157e+308,4e+307,4.1e+307,5e+307,4000.0,4000.0,0.0};
int M_LPS[]={1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
long M_LP[]={3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,0,3,3,3,3,3,3,3,3,3,3,3,3,0,3,3,0,0,3,3,3,3,-1,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3};
int M_LTS[]={1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,0,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
long M_LT[]={5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,0,5,0,5,0,5,5,5,5,-2,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5};
int M_LCS[]={1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
double M_LC[]={5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,1231.25,1231.24,1998.81,1998.81,5000.0,5000.0,5000.0,5000.0,0.0,0.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,-1.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,5000.0,1.7976931348623157e+308,1.7976931348623157e+308,1.7976931348623157e+308,1.7976931348623157e+308,1.7976931348623157e+308,8e+307,8e+307,4e+307,5000.0,5000.0,5000.0};
string M_REG[]={"","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","SIG-0|SIG-9","SIG-0|SIG-1","A|B","SIG-1|B","","A","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","SIG-1","SIG-1",""};
int M_CNT[]={-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,3,-1,1,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000};
int M_MODK[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6,1,2,1,2,3,4,5,6,7,8,9,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,0,0,0,0,0,0,0,0,0,0,0};
int M_MODF[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,2,2,2,2,2,3,3,3,3,3,4,4,4,4,4,5,5,5,5,5,6,6,6,6,6,7,7,7,7,7,0,0,0,0,0,0,0,0,0,0,0};
int M_MODV[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,3,4,0,1,2,3,4,0,1,2,3,4,0,1,2,3,4,0,1,2,3,4,0,1,2,3,4,0,1,2,3,4,0,1,2,3,4,0,0,0,0,0,0,0,0,0,0,0};
int M_CAPREG[]={4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,2,2,0,2,2,2,0,0,4,4,0,0,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4};
string MX_DEC[]={"ALLOW","ALLOW","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","ALLOW","BLOCK","BLOCK","BLOCK","ALLOW","BLOCK","BLOCK","ALLOW","BLOCK","BLOCK","ALLOW","BLOCK","ALLOW","BLOCK","ALLOW","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","ALLOW","BLOCK","BLOCK","BLOCK","BLOCK","ALLOW","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","ALLOW","BLOCK","ALLOW","BLOCK","ALLOW","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK"};
string MX_REASONS[]={"","","PLAN_NOT_OK","PLAN_NOT_OK","PLAN_NOT_OK","DATA_NOT_READY","DATA_NOT_READY","DATA_UNKNOWN","DATA_UNRELIABLE","INVALID_SNAPSHOT:data_state","SESSION_CLOSED","SESSION_UNKNOWN","INVALID_SNAPSHOT:session_state","NEWS_BLOCK","NEWS_UNKNOWN","INVALID_SNAPSHOT:news_state","SPREAD_BLOCK","SPREAD_UNKNOWN","INVALID_SNAPSHOT:spread_state","","MAX_POSITIONS_REACHED","MAX_POSITIONS_REACHED","MAX_POSITIONS_REACHED","","MAX_TRADES_REACHED","MAX_TRADES_REACHED","","COMBINED_RISK_EXCEEDED","COMBINED_RISK_EXCEEDED","","COMBINED_RISK_EXCEEDED","","COMBINED_RISK_EXCEEDED","","COMBINED_RISK_EXCEEDED","POLICY_UNSET:max_positions","POLICY_UNSET:max_trades_per_day","POLICY_UNSET:combined_risk_cap","POLICY_UNSET:max_positions|POLICY_UNSET:max_trades_per_day|POLICY_UNSET:combined_risk_cap","POLICY_UNSET:max_positions","DATA_UNKNOWN|POLICY_UNSET:max_trades_per_day","INVALID_SNAPSHOT:open_positions","INVALID_SNAPSHOT:trades_today","INVALID_SNAPSHOT:existing_risk","INVALID_SNAPSHOT:max_positions","INVALID_SNAPSHOT:max_trades_per_day","INVALID_SNAPSHOT:combined_risk_cap","","DUPLICATE_SIGNAL","REGISTRY_FULL","DUPLICATE_SIGNAL","REGISTRY_FULL","","REGISTRY_INVALID","REGISTRY_INVALID","REGISTRY_INVALID","PLAN_INVALID_ID|REGISTRY_FULL","PLAN_NOT_OK","PLAN_INVALID_ID|PLAN_INVALID_VALUES","PLAN_NOT_OK|REGISTRY_FULL","PLAN_INVALID_ID|PLAN_INVALID_VALUES|REGISTRY_FULL","PLAN_NOT_OK","PLAN_NOT_OK","PLAN_NOT_OK","PLAN_INVALID_ID","PLAN_INVALID_ID","PLAN_INVALID_ID","PLAN_INVALID_ID","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","PLAN_INVALID_VALUES","COMBINED_RISK_EXCEEDED","","COMBINED_RISK_EXCEEDED","","COMBINED_RISK_EXCEEDED","","COMBINED_RISK_EXCEEDED","COMBINED_RISK_EXCEEDED","DATA_NOT_READY|SESSION_CLOSED|NEWS_BLOCK|SPREAD_BLOCK|DUPLICATE_SIGNAL|MAX_POSITIONS_REACHED|MAX_TRADES_REACHED|COMBINED_RISK_EXCEEDED","PLAN_NOT_OK|DATA_NOT_READY|SESSION_CLOSED|NEWS_BLOCK|SPREAD_BLOCK|DUPLICATE_SIGNAL|MAX_POSITIONS_REACHED|MAX_TRADES_REACHED","DATA_UNKNOWN|SESSION_UNKNOWN|NEWS_UNKNOWN|SPREAD_UNKNOWN"};
#define NCANCEL 22
string K_NAME[]={"CAUSE_DIRECTION_CHANGE","CAUSE_OPPOSITE_SIGNAL","CAUSE_SESSION_END","CAUSE_NEWS_BLOCK","CAUSE_DAILY_LIMIT","COMBINED_SESSION_END_NEWS","COMBINED_DIRECTION_DAILY","COMBINED_ALL_FIVE","PENDING_AND_POSITION_ONLY_PENDING","PENDING_AND_POSITION_ALL_EVENTS","POSITION_ONLY_NO_REQUEST","POSITION_ONLY_ONE_EVENT","NOTHING_PENDING_NO_POSITION","PENDING_ID_IGNORED_WHEN_NO_PENDING","PENDING_WITHOUT_EVENT","PENDING_AND_POSITION_WITHOUT_EVENT","UNKNOWN_EVENT_32","UNKNOWN_EVENT_BIT_WITH_KNOWN","UNKNOWN_EVENT_NEGATIVE","UNKNOWN_EVENT_WITHOUT_PENDING","PENDING_EMPTY_ID","PENDING_BLANK_ID"};
int K_PEND[]={1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1,0,1,1};
string K_PID[]={"SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-2","","","","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","SIG-1","","","  "};
int K_POS[]={0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,1,0,0,0,1,0,1};
int K_EV[]={1,2,4,8,16,12,17,31,4,31,31,4,8,8,0,0,32,33,-1,64,4,4};
string KX_STATUS[]={"CANCEL_REQUEST","CANCEL_REQUEST","CANCEL_REQUEST","CANCEL_REQUEST","CANCEL_REQUEST","CANCEL_REQUEST","CANCEL_REQUEST","CANCEL_REQUEST","CANCEL_REQUEST","CANCEL_REQUEST","NO_PENDING","NO_PENDING","NO_PENDING","NO_PENDING","NO_EVENT","NO_EVENT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT"};
string KX_WHY[]={"","","","","","","","","","","","","","","","","INVALID_EVENTS","INVALID_EVENTS","INVALID_EVENTS","INVALID_EVENTS","INVALID_PENDING_SIGNAL_ID","INVALID_PENDING_SIGNAL_ID"};
string KX_REASONS[]={"DIRECTION_CHANGE","OPPOSITE_SIGNAL","SESSION_END","NEWS_BLOCK","DAILY_LIMIT","SESSION_END|NEWS_BLOCK","DIRECTION_CHANGE|DAILY_LIMIT","DIRECTION_CHANGE|OPPOSITE_SIGNAL|SESSION_END|NEWS_BLOCK|DAILY_LIMIT","SESSION_END","DIRECTION_CHANGE|OPPOSITE_SIGNAL|SESSION_END|NEWS_BLOCK|DAILY_LIMIT","","","","","","","","","","","",""};
// END GENERATED FIXTURES
bool BuildCase(const int i,STpPlan &p)
  {
   return(TP_BuildPlan(P_SID[i],P_SETUP[i],P_DIR[i],P_E[i],P_S[i],P_HAST[i]==1,P_T[i],P_BUDGET[i],P_TV[i],P_TICK[i],P_DIG[i],
                       P_POINT[i],P_STOPS[i],P_HASQ[i]==1,P_BID[i],P_ASK[i],P_VMIN[i],P_STEP[i],P_VMAX[i],P_CAP[i],p));
  }
bool PlanIsZero(const STpPlan &p)
  {
   return(p.e_out==0.0 && p.s_out==0.0 && p.tp==0.0 && p.level_2r==0.0 && p.partial_price==0.0 && p.r_geom==0.0 &&
          p.volume_out==0.0 && p.risk_model==0.0 && !p.tp_equals_2r);
  }
void RunPlan(const int i)
  {
   STpPlan p;
   bool ok=BuildCase(i,p);
   string tag=P_NAME[i]+": ";
   Check(TP_StatusName(p.status)==PX_STATUS[i] && TP_StageName(p.stage)==PX_STAGE[i],tag+"status "+TP_StatusName(p.status)+" stage "+TP_StageName(p.stage)+" ("+p.reason+")");
   Check(ok==(PX_STATUS[i]=="OK"),tag+"return value matches status");
   Check(p.signal_id==P_SID[i] && p.setup_id==P_SETUP[i],tag+"ids echoed");
   if(PX_HASNUM[i]==0)
     {
      Check(p.reason!="" && StringFind(p.reason,PX_WHY[i])==0,tag+"reason names the stage: "+p.reason);
      Check(PlanIsZero(p),tag+"every plan number is 0 on refusal");
      if(PX_UNDER[i]!="") Check(p.under_status==PX_UNDER[i],tag+"underlying status "+p.under_status);
      if(PX_UNDERWHY[i]!="") Check(StringFind(p.under_reason,PX_UNDERWHY[i])==0,tag+"underlying reason "+p.under_reason);
     }
   else
     {
      Check(p.reason=="" && p.under_status=="" && p.under_reason=="",tag+"no refusal text on OK");
      Check(Near(p.e_out,PX_E[i]) && Near(p.s_out,PX_S[i]),tag+"E and SL");
      Check(Near(p.tp,PX_TP[i]) && Near(p.level_2r,PX_2R[i]) && Near(p.partial_price,PX_PARTIAL[i]),tag+"TP, 2R and partial price");
      Check(Near(p.r_geom,PX_R[i]) && Near(p.volume_out,PX_VOL[i]) && Near(p.risk_model,PX_RISK[i]),tag+"R, volume and risk_model");
     }
  }
void FillRegistry(const int i,string &ids[],int &count)
  {
   ArrayResize(ids,M_CAPREG[i]);
   for(int k=0;k<ArraySize(ids);k++) ids[k]="";
   string parts[];
   int n=0;
   if(M_REG[i]!="") n=StringSplit(M_REG[i],'|',parts);
   for(int k=0;k<n;k++) ids[k]=parts[k];
   count=(M_CNT[i]==-1000 ? n : M_CNT[i]);
  }
double BadValue(const int kind)
  {
   double zero=0.0;
   if(kind==0) return(MathSqrt(-1.0));
   if(kind==1) return(MathExp(1000.0));
   if(kind==2) return(-1.0);
   if(kind==3) return(zero);
   return(-MathExp(1000.0));
  }
// The fixture plan modification: a hand-built or damaged plan (see tests/t007_planning_fixtures.py).
void ApplyMod(const int i,STpPlan &p)
  {
   int k=M_MODK[i];
   if(k==0) return;
   if(k==1 || k==2)
     {
      TP_PlanReset(p,"","",0);
      if(k==1) p.stage=TP_STAGE_INPUT;
      return;
     }
   if(k==3) p.stage=TP_STAGE_INPUT;
   else if(k==4) p.stage=TP_STAGE_GEOMETRY;
   else if(k==5) p.stage=TP_STAGE_SIZING;
   else if(k==6) p.signal_id="   ";
   else if(k==7) p.signal_id="";
   else if(k==8) p.setup_id="";
   else if(k==9) p.setup_id="\t ";
   else if(k==10)
     {
      double v=BadValue(M_MODV[i]);
      switch(M_MODF[i])
        {
         case 0: p.e_out=v; break;
         case 1: p.s_out=v; break;
         case 2: p.tp=v; break;
         case 3: p.level_2r=v; break;
         case 4: p.partial_price=v; break;
         case 5: p.r_geom=v; break;
         case 6: p.volume_out=v; break;
         case 7: p.risk_model=v; break;
        }
     }
  }
void FillSnapshot(const int i,STpSnapshot &s)
  {
   s.data_state=M_DATA[i];
   s.data_reliable=(M_REL[i]==1);
   s.session_state=M_SESS[i];
   s.news_state=M_NEWS[i];
   s.spread_state=M_SPR[i];
   s.open_positions=M_POS[i];
   s.trades_today=M_TRD[i];
   s.existing_risk=M_RISK[i];
  }
void FillLimits(const int i,STpLimits &l)
  {
   l.max_positions_set=(M_LPS[i]==1);
   l.max_positions=M_LP[i];
   l.max_trades_set=(M_LTS[i]==1);
   l.max_trades=M_LT[i];
   l.risk_cap_set=(M_LCS[i]==1);
   l.risk_cap=M_LC[i];
  }
void RunPermit(const int i)
  {
   STpPlan p;
   BuildCase(M_PLAN[i],p);
   ApplyMod(i,p);
   STpSnapshot s;
   STpLimits l;
   FillSnapshot(i,s);
   FillLimits(i,l);
   string ids[];
   int count=0;
   FillRegistry(i,ids,count);
   int count_before=count;
   STpPermit r;
   bool allow=TP_CheckPermit(p,s,l,ids,count,r);
   string tag=M_NAME[i]+": ";
   string exp_primary=r.reason_count>0 ? r.reasons[0] : "";
   Check((allow ? "ALLOW" : "BLOCK")==MX_DEC[i],tag+"decision "+(allow ? "ALLOW" : "BLOCK")+" reasons "+TP_ReasonsText(r));
   Check(r.allow==allow && !r.registered,tag+"allow flag and not registered by the pure check");
   Check(TP_ReasonsText(r)==MX_REASONS[i],tag+"reasons "+TP_ReasonsText(r)+" expected "+MX_REASONS[i]);
   Check(r.primary_reason==exp_primary,tag+"primary reason is the first");
   Check(count==count_before,tag+"pure check leaves the registry count alone");
   // authorize on a fresh copy: ALLOW appends exactly the signal id; every refusal leaves ids and count unchanged
   string ref_ids[];
   int ref_count=0;
   FillRegistry(i,ref_ids,ref_count);
   string ids2[];
   int count2=0;
   FillRegistry(i,ids2,count2);
   STpPermit r2;
   bool allow2=TP_Authorize(p,s,l,ids2,count2,r2);
   bool same=(ArraySize(ids2)==ArraySize(ref_ids));
   int n=ArraySize(ref_ids);
   if(allow)
     {
      for(int k=0;same && k<n;k++)
         if(k==ref_count ? ids2[k]!=p.signal_id : ids2[k]!=ref_ids[k]) same=false;
      Check(allow2 && r2.registered && count2==ref_count+1 && same,tag+"authorize ALLOW appends exactly the signal id");
     }
   else
     {
      for(int k=0;same && k<n;k++)
         if(ids2[k]!=ref_ids[k]) same=false;
      Check(!allow2 && !r2.registered && count2==ref_count && same && TP_ReasonsText(r2)==MX_REASONS[i],tag+"authorize refusal leaves ids and count unchanged");
     }
  }
void RunCancel(const int i)
  {
   STpCancel c;
   bool req=TP_CancelDecision(K_PEND[i]==1,K_PID[i],K_POS[i]==1,K_EV[i],c);
   string tag=K_NAME[i]+": ";
   Check(TP_CancelStatusName(c.status)==KX_STATUS[i],tag+"status "+TP_CancelStatusName(c.status)+" ("+c.reason+")");
   Check(req==(KX_STATUS[i]=="CANCEL_REQUEST") && c.cancel_pending==req,tag+"cancel flag matches status");
   Check(TP_CancelReasonsText(c)==KX_REASONS[i],tag+"reasons "+TP_CancelReasonsText(c));
   Check(c.positions_untouched && c.position_present==(K_POS[i]==1),tag+"positions untouched");
   if(KX_WHY[i]!="") Check(StringFind(c.reason,KX_WHY[i])==0,tag+"reason tag "+KX_WHY[i]+" got: "+c.reason);
   if(req) Check(c.pending_signal_id==K_PID[i],tag+"request targets the pending signal id");
  }
int FindPlan(const string name)
  {
   for(int i=0;i<NPLAN;i++) if(P_NAME[i]==name) return(i);
   return(-1);
  }
void BasicPlan(const string name,const string sid,STpPlan &p)
  {
   int i=FindPlan(name);
   TP_BuildPlan(sid,P_SETUP[i],P_DIR[i],P_E[i],P_S[i],P_HAST[i]==1,P_T[i],P_BUDGET[i],P_TV[i],P_TICK[i],P_DIG[i],
                P_POINT[i],P_STOPS[i],P_HASQ[i]==1,P_BID[i],P_ASK[i],P_VMIN[i],P_STEP[i],P_VMAX[i],P_CAP[i],p);
  }
void DefaultSnapshot(STpSnapshot &s)
  {
   s.data_state=TP_DATA_READY; s.data_reliable=true; s.session_state=TP_SESSION_OPEN; s.news_state=TP_NEWS_CLEAR;
   s.spread_state=TP_SPREAD_CLEAR; s.open_positions=0; s.trades_today=0; s.existing_risk=0.0;
  }
void TestLimits(STpLimits &l)
  {
   l.max_positions_set=true; l.max_positions=3; l.max_trades_set=true; l.max_trades=5; l.risk_cap_set=true; l.risk_cap=5000.0;
  }
void Sequences()
  {
   STpPlan p1,p2;
   BasicPlan("BUY_BASIC","SIG-1",p1);
   BasicPlan("BUY_BASIC","SIG-2",p2);
   STpSnapshot s;
   DefaultSnapshot(s);
   STpLimits l;
   TestLimits(l);
   string reg[];
   ArrayResize(reg,4);
   for(int init=0;init<ArraySize(reg);init++) reg[init]="";
   int count=0;
   STpPermit r;
   bool a1=TP_Authorize(p1,s,l,reg,count,r);
   Check(a1 && r.allow && r.registered && count==1 && reg[0]=="SIG-1","first authorization ALLOW and registers the signal id");
   bool a2=TP_Authorize(p1,s,l,reg,count,r);
   Check(!a2 && !r.allow && r.primary_reason=="DUPLICATE_SIGNAL" && !r.registered && count==1,"same signal id twice: second is BLOCK DUPLICATE_SIGNAL, registry unchanged");
   bool a3=TP_Authorize(p2,s,l,reg,count,r);
   Check(a3 && count==2 && reg[1]=="SIG-2","a different signal id is allowed and registered");
   // a BLOCKed attempt does not consume the id
   string reg2[];
   ArrayResize(reg2,4);
   for(int init=0;init<ArraySize(reg2);init++) reg2[init]="";
   int c2=0;
   STpSnapshot bad=s;
   bad.data_state=TP_DATA_NOT_READY;
   string before2[];
   ArrayCopy(before2,reg2);
   bool b1=TP_Authorize(p1,bad,l,reg2,c2,r);
   bool same2=(ArraySize(before2)==ArraySize(reg2));
   for(int k=0;same2 && k<ArraySize(reg2);k++) if(reg2[k]!=before2[k]) same2=false;
   Check(!b1 && !r.allow && !r.registered && c2==0 && same2 && r.primary_reason=="DATA_NOT_READY","a blocked attempt does not register the id");
   bool b2=TP_Authorize(p1,s,l,reg2,c2,r);
   Check(b2 && c2==1,"the same id is allowed later because the blocked attempt did not consume it");
   // overflow blocks, never drops
   string reg3[];
   ArrayResize(reg3,1);
   for(int init=0;init<ArraySize(reg3);init++) reg3[init]="";
   int c3=0;
   TP_Authorize(p1,s,l,reg3,c3,r);
   bool o=TP_Authorize(p2,s,l,reg3,c3,r);
   Check(!o && r.primary_reason=="REGISTRY_FULL" && c3==1 && reg3[0]=="SIG-1","registry at capacity: BLOCK REGISTRY_FULL, nothing dropped or overwritten");
   string reg0[];
   ArrayResize(reg0,0);
   for(int init=0;init<ArraySize(reg0);init++) reg0[init]="";
   int c0=0;
   Check(!TP_Authorize(p1,s,l,reg0,c0,r) && r.primary_reason=="REGISTRY_FULL" && c0==0 && ArraySize(reg0)==0,"capacity 0: BLOCK REGISTRY_FULL, no write");
   STpPlan zero;
   TP_PlanReset(zero,"","",0);
   zero.stage=TP_STAGE_INPUT;
   c0=0;
   Check(!TP_Authorize(zero,s,l,reg0,c0,r) && !r.allow && c0==0 && ArraySize(reg0)==0,"zero plan with empty signal id and capacity 0: BLOCK, no write");
   string regz[];
   ArrayResize(regz,2);
   for(int init=0;init<ArraySize(regz);init++) regz[init]="";
   int cz=0;
   string beforez[];
   ArrayCopy(beforez,regz);
   bool az=TP_Authorize(zero,s,l,regz,cz,r);
   bool samez=(ArraySize(beforez)==ArraySize(regz));
   for(int k=0;samez && k<ArraySize(regz);k++) if(regz[k]!=beforez[k]) samez=false;
   Check(!az && !r.allow && !r.registered && r.primary_reason=="PLAN_NOT_OK" && cz==0 && samez,"zero plan: BLOCK, registry unchanged");
   int badcount=5;
   Check(!TP_CheckPermit(p1,s,l,reg3,badcount,r) && r.primary_reason=="REGISTRY_INVALID","count above capacity: REGISTRY_INVALID");
   badcount=-1;
   Check(!TP_CheckPermit(p1,s,l,reg3,badcount,r) && r.primary_reason=="REGISTRY_INVALID","negative count: REGISTRY_INVALID");
   // refused plans never register
   STpPlan rp;
   int gi=FindPlan("GEO_SL_WRONG_SIDE_BUY");
   TP_BuildPlan(P_SID[gi],P_SETUP[gi],P_DIR[gi],P_E[gi],P_S[gi],false,0.0,P_BUDGET[gi],P_TV[gi],P_TICK[gi],P_DIG[gi],P_POINT[gi],P_STOPS[gi],false,0.0,0.0,P_VMIN[gi],P_STEP[gi],P_VMAX[gi],P_CAP[gi],rp);
   string reg4[];
   ArrayResize(reg4,2);
   for(int init=0;init<ArraySize(reg4);init++) reg4[init]="";
   int c4=0;
   Check(!TP_Authorize(rp,s,l,reg4,c4,r) && r.primary_reason=="PLAN_NOT_OK" && c4==0,"a refused plan is PLAN_NOT_OK and never registers");
  }
void Numeric()
  {
   STpPlan p;
   BasicPlan("BUY_BASIC","SIG-1",p);
   STpSnapshot s;
   DefaultSnapshot(s);
   STpLimits l;
   TestLimits(l);
   string reg[];
   ArrayResize(reg,2);
   for(int init=0;init<ArraySize(reg);init++) reg[init]="";
   STpPermit r;
   double nan=MathSqrt(-1.0);
   double inf=MathExp(1000.0);
   s.existing_risk=nan;
   TP_CheckPermit(p,s,l,reg,0,r);
   Check(!r.allow && r.primary_reason=="INVALID_SNAPSHOT:existing_risk","NaN existing risk blocks");
   s.existing_risk=inf;
   TP_CheckPermit(p,s,l,reg,0,r);
   Check(!r.allow && r.primary_reason=="INVALID_SNAPSHOT:existing_risk","infinite existing risk blocks");
   DefaultSnapshot(s);
   l.risk_cap=nan;
   TP_CheckPermit(p,s,l,reg,0,r);
   Check(!r.allow && r.primary_reason=="INVALID_SNAPSHOT:combined_risk_cap","NaN cap blocks");
   l.risk_cap=inf;
   TP_CheckPermit(p,s,l,reg,0,r);
   Check(!r.allow && r.primary_reason=="INVALID_SNAPSHOT:combined_risk_cap","infinite cap blocks");
   TestLimits(l);
   // boundary with real noise: risk_model 1998.8000000000002 + 0.01 vs cap 1998.81
   STpPlan q;
   BasicPlan("SELL_TICK005","SIG-9",q);
   s.existing_risk=0.01;
   l.risk_cap=1998.81;
   TP_CheckPermit(q,s,l,reg,0,r);
   Check(r.allow,"sum 1 ulp above the cap in binary but equal in decimal is ALLOWED");
   s.existing_risk=0.02;
   TP_CheckPermit(q,s,l,reg,0,r);
   Check(!r.allow && r.primary_reason=="COMBINED_RISK_EXCEEDED","one cent over the cap blocks");
   // all labels and the plan-only constants
   Check(TP_PlanLabel()=="PLAN_ONLY / NOT_AN_ORDER" && TP_PermitLabel()=="PERMIT_ONLY / NOT_AN_ORDER" && TP_CancelLabel()=="CANCEL_REQUEST_ONLY / NOT_SENT","labels");
   Check(StringFind(TP_PartialLabel(),"PARTIAL_AT_2R")==0 && StringFind(TP_RiskLabel(),"COSTS_NOT_MODELLED")>0,"partial and risk labels");
   // plan inputs untouched by the permit and the cancel decision
   STpPlan before=p;
   STpPermit r2;
   TP_CheckPermit(p,s,l,reg,0,r2);
   Check(before.volume_out==p.volume_out && before.risk_model==p.risk_model && before.signal_id==p.signal_id && before.status==p.status,"plan unchanged by the permit check");
  }
void CancelExhaustive()
  {
   int bad=0;
   for(int pend=0;pend<2;pend++)
      for(int pos=0;pos<2;pos++)
         for(int ev=0;ev<32;ev++)
           {
            STpCancel c;
            bool req=TP_CancelDecision(pend==1,"SIG-1",pos==1,ev,c);
            if(!c.positions_untouched) bad++;
            if(req!=(pend==1 && ev!=0)) bad++;
            if(req && c.pending_signal_id!="SIG-1") bad++;
            int bits=0;
            for(int b=0;b<5;b++) if((ev & (1<<b))!=0) bits++;
            if(req && c.reason_count!=bits) bad++;
           }
   Check(bad==0,"every event mask and flag combination: positions untouched, request only with a pending and an event");
   STpCancel c;
   TP_CancelDecision(true,"SIG-1",false,31,c);
   Check(TP_CancelReasonsText(c)=="DIRECTION_CHANGE|OPPOSITE_SIGNAL|SESSION_END|NEWS_BLOCK|DAILY_LIMIT","fixed reason order");
  }
void Integration()
  {
   STpSnapshot s;
   DefaultSnapshot(s);
   s.open_positions=1; s.trades_today=2; s.existing_risk=2000.0;
   STpLimits l;
   TestLimits(l);
   string names[]={"BUY_BASIC","SELL_BASIC"};
   double tps[]={1962.90,2297.70};
   for(int k=0;k<2;k++)
     {
      STpPlan p;
      BasicPlan(names[k],"SIG-I"+IntegerToString(k),p);
      Check(p.status==TP_OK && Near(p.tp,tps[k]) && Near(p.volume_out,1.97) && Near(p.risk_model,1231.25),names[k]+": geometry -> sizing -> plan");
      string reg[];
      ArrayResize(reg,4);
      for(int init=0;init<ArraySize(reg);init++) reg[init]="";
      int count=0;
      STpPermit r;
      Check(TP_Authorize(p,s,l,reg,count,r) && r.registered && reg[0]==p.signal_id,names[k]+": permit ALLOW and registered");
      Check(!TP_Authorize(p,s,l,reg,count,r) && r.primary_reason=="DUPLICATE_SIGNAL",names[k]+": repeated signal blocked");
      STpCancel c;
      TP_CancelDecision(true,p.signal_id,true,TP_EV_SESSION_END|TP_EV_DAILY_LIMIT,c);
      Check(c.status==TP_CANCEL_REQUEST && TP_CancelReasonsText(c)=="SESSION_END|DAILY_LIMIT" && c.pending_signal_id==p.signal_id && c.positions_untouched,names[k]+": cancel request for the pending only");
     }
  }
void OnStart()
  {
   for(int i=0;i<NPLAN;i++) RunPlan(i);
   for(int i=0;i<NPERMIT;i++) RunPermit(i);
   for(int i=0;i<NCANCEL;i++) RunCancel(i);
   Sequences();
   Numeric();
   CancelExhaustive();
   Integration();
   PrintFormat("T007 PLANNING TEST finished: %d passed, %d failed",g_pass,g_fail);
  }

