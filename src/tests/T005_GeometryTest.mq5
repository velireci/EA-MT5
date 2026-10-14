// T005 test script: pure trade geometry. Mirrors tests/test_t005_geometry.py; the fixtures below are the
// hand-computed table of tests/t005_geometry_fixtures.py. NOT YET COMPILED OR RUN in MT5 (UNVERIFIED).
// Tests the geometry helper only: no order, no volume, no live price. Says nothing about entry quality.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/TradeGeometry.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
bool Near(const double a,const double b) {return(MathAbs(a-b)<1e-9);}
// BEGIN GENERATED FIXTURES (tests/t005_geometry_fixtures.py emit_mql)
#define NCASES 63
string C_NAME[]={"BUY_FAR","BUY_NEAR","BUY_EQ","BUY_NONE","SELL_FAR","SELL_NEAR","SELL_EQ","SELL_NONE","BUY_ROUND_FAR","BUY_ROUND_EQ","SELL_ROUND_FAR","SELL_ROUND_NEAR","BUY_HALF","SELL_HALF","BUY_COARSE_HALF","SELL_COARSE_ONE","SELL_ON_GRID_05","BUY_ZERO","BUY_ZERO_AFTER_NORM","SELL_ZERO_AFTER_NORM","BUY_SL_WRONG","SELL_SL_WRONG","BUY_T_BELOW","BUY_T_EQ_E","BUY_T_SAME_TICK_BELOW","SELL_T_ABOVE","SELL_T_EQ_E","BUY_T_SUBTICK_BEYOND","BUY_SL_BELOW_STOPS","BUY_SL_AT_STOPS","SELL_SL_BELOW_STOPS","SELL_SL_AT_STOPS","BUY_ASK_AT_STOPS","BUY_ASK_TOO_CLOSE","BUY_ASK_BELOW_LIMIT","SELL_BID_AT_STOPS","SELL_BID_TOO_CLOSE","SELL_BID_ABOVE_LIMIT","BUY_ASK_EQ_LIMIT_STOPS0","BUY_ASK_ONE_POINT_STOPS0","BUY_NO_QUOTE_STOPS30","DIRECTION_INVALID","QUOTE_CROSSED","TICK_ZERO","TICK_NEGATIVE","POINT_ZERO","STOPS_NEGATIVE","ENTRY_ZERO","TARGET_NEGATIVE","BUY_TICK_DIGITS_MISMATCH","SELL_TICK_DIGITS_MISMATCH","TICK_015_DIGITS_2","TICK_FINER_THAN_DIGITS_0","TICK_025_DIGITS_2_OK","SELL_2R_NEGATIVE","BUY_SL_ROUNDS_TO_ZERO","SELL_ENTRY_ROUNDS_TO_ZERO","SELL_TARGET_ROUNDS_TO_ZERO","SELL_2R_EXACTLY_ZERO","SELL_2R_JUST_POSITIVE","BUY_HUGE_TINY_TICK","BUY_RANGE_AT_LIMIT_PLUS","BUY_2R_OVERFLOW_TO_INF"};
int C_DIR[]={1,1,1,1,-1,-1,-1,-1,1,1,-1,-1,1,-1,1,-1,-1,1,1,-1,1,-1,1,1,1,-1,-1,1,1,1,-1,-1,1,1,1,-1,-1,-1,1,1,1,0,1,1,-1,1,1,1,1,1,-1,1,1,1,-1,1,-1,-1,-1,-1,1,1,1};
double C_E[]={1950.4,1950.4,1950.4,1950.4,2310.2,2310.2,2310.2,2310.2,2000.02,2000.02,2500.07,2500.07,2000.025,2000.075,1000.3,1500.4,2310.15,2000.0,2000.02,2000.01,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,0.0,2000.0,1.004,1.003,2000.0,2000.0,2000.0,100.0,0.6,0.4,5.0,100.0,100.0,1e+300,10000000001.0,1.5e+308};
double C_S[]={1944.15,1944.15,1944.15,1944.15,2316.45,2316.45,2316.45,2316.45,1994.93,1994.93,2507.64,2507.64,1999.975,2000.275,995.2,1507.5,2316.4,2000.0,2000.01,2000.02,2001.0,1999.0,1995.0,1995.0,1995.0,2005.0,2005.0,1995.0,1999.71,1999.7,2000.29,2000.3,1995.0,1995.0,1995.0,2005.0,2005.0,2005.0,1995.0,1995.0,1995.0,1995.0,1995.0,1995.0,2005.0,1995.0,1995.0,-5.0,1995.0,1.003,1.004,1995.0,1995.0,1995.0,160.0,0.4,0.2,7.0,150.0,149.99,1e+299,10000000000.0,1e+308};
int C_HAST[]={1,1,1,0,1,1,1,0,1,1,1,1,0,0,1,1,0,0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0};
double C_T[]={1970.0,1960.0,1962.9,0.0,2290.1,2300.0,2297.7,0.0,2012.33,2010.07,2480.03,2490.02,0.0,0.0,1011.1,1480.6,0.0,0.0,0.0,0.0,0.0,0.0,1999.0,2000.0,1999.99,2001.0,2000.0,2000.01,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,-1.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0};
double C_TICK[]={0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.05,0.05,0.05,0.05,0.05,0.05,0.5,1.0,0.05,0.01,0.05,0.05,0.01,0.01,0.01,0.01,0.05,0.01,0.01,0.05,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.0,-0.01,0.01,0.01,0.01,0.01,0.001,0.001,0.015,0.5,0.25,0.01,1.0,1.0,1.0,0.01,0.01,0.01,0.01,1e+308};
int C_DIG[]={2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,2,2,0,0,0,2,2,2,2,0};
double C_POINT[]={0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.1,1.0,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.0,0.01,0.01,0.01,0.01,0.01,0.01,1.0,0.01,0.01,1.0,1.0,1.0,0.01,0.01,0.01,0.01,1.0};
int C_STOPS[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,30,30,30,30,30,30,30,30,30,30,0,0,30,0,0,0,0,0,-1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int C_HASQ[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
double C_BID[]={0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1999.9,1999.9,1998.9,1999.7,1999.71,2001.0,1999.9,1999.9,0.0,0.0,2001.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0};
double C_ASK[]={0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2000.3,2000.29,1999.0,2000.1,2000.1,2001.1,2000.0,2000.01,0.0,0.0,2000.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0};
string X_STATUS[]={"OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","ZERO_RISK","ZERO_RISK","ZERO_RISK","SL_WRONG_SIDE","SL_WRONG_SIDE","TARGET_WRONG_SIDE","TARGET_WRONG_SIDE","TARGET_WRONG_SIDE","TARGET_WRONG_SIDE","TARGET_WRONG_SIDE","OK","BELOW_STOPS_LEVEL","OK","BELOW_STOPS_LEVEL","OK","OK","PENDING_TOO_CLOSE","PENDING_TOO_CLOSE","OK","PENDING_TOO_CLOSE","PENDING_TOO_CLOSE","PENDING_TOO_CLOSE","OK","OK","INVALID_DIRECTION","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","OK","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","OK","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT"};
string X_WHY[]={"","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","INCOMPATIBLE_TICK_DIGITS","INCOMPATIBLE_TICK_DIGITS","INCOMPATIBLE_TICK_DIGITS","INCOMPATIBLE_TICK_DIGITS","","NONPOSITIVE_PRICE","NONPOSITIVE_PRICE","NONPOSITIVE_PRICE","NONPOSITIVE_PRICE","NONPOSITIVE_PRICE","","NUMERIC_OVERFLOW","NUMERIC_OVERFLOW","NUMERIC_OVERFLOW"};
string X_PEND[]={"NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","PASSED","TOO_CLOSE","TOO_CLOSE","PASSED","TOO_CLOSE","TOO_CLOSE","TOO_CLOSE","PASSED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED","NOT_CHECKED"};
int X_HASNUM[]={1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,1,0,0,1,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0};
double X_E[]={1950.4,1950.4,1950.4,1950.4,2310.2,2310.2,2310.2,2310.2,2000.0,2000.0,2500.05,2500.05,2000.05,2000.1,1000.5,1500.0,2310.15,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,2000.0,0.0,0.0,2000.0,0.0,0.0,0.0,2000.0,2000.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2000.0,0.0,0.0,0.0,0.0,0.0,100.0,0.0,0.0,0.0};
double X_S[]={1944.15,1944.15,1944.15,1944.15,2316.45,2316.45,2316.45,2316.45,1994.95,1994.95,2507.65,2507.65,2000.0,2000.3,995.0,1508.0,2316.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1995.0,0.0,1999.7,0.0,2000.3,1995.0,0.0,0.0,2005.0,0.0,0.0,0.0,1995.0,1995.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1995.0,0.0,0.0,0.0,0.0,0.0,149.99,0.0,0.0,0.0};
double X_R[]={6.25,6.25,6.25,6.25,6.25,6.25,6.25,6.25,5.05,5.05,7.6,7.6,0.05,0.2,5.5,8.0,6.25,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,5.0,0.0,0.3,0.0,0.3,5.0,0.0,0.0,5.0,0.0,0.0,0.0,5.0,5.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,5.0,0.0,0.0,0.0,0.0,0.0,49.99,0.0,0.0,0.0};
double X_2R[]={1962.9,1962.9,1962.9,1962.9,2297.7,2297.7,2297.7,2297.7,2010.1,2010.1,2484.85,2484.85,2000.15,1999.7,1011.5,1484.0,2297.65,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2010.0,0.0,2000.6,0.0,1999.4,2010.0,0.0,0.0,1990.0,0.0,0.0,0.0,2010.0,2010.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2010.0,0.0,0.0,0.0,0.0,0.0,0.02,0.0,0.0,0.0};
double X_TP[]={1970.0,1962.9,1962.9,1962.9,2290.1,2297.7,2297.7,2297.7,2012.35,2010.1,2480.0,2484.85,2000.15,1999.7,1011.5,1480.0,2297.65,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2010.0,0.0,2000.6,0.0,1999.4,2010.0,0.0,0.0,1990.0,0.0,0.0,0.0,2010.0,2010.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2010.0,0.0,0.0,0.0,0.0,0.0,0.02,0.0,0.0,0.0};
string X_CASE[]={"FARTHER_THAN_2R","NEARER_THAN_2R","EQUAL_TO_2R","NONE","FARTHER_THAN_2R","NEARER_THAN_2R","EQUAL_TO_2R","NONE","FARTHER_THAN_2R","EQUAL_TO_2R","FARTHER_THAN_2R","NEARER_THAN_2R","NONE","NONE","EQUAL_TO_2R","FARTHER_THAN_2R","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NEARER_THAN_2R","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE","NONE"};
int X_COINC[]={0,1,1,1,0,1,1,1,0,1,0,1,1,1,1,0,1,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,1,0,0,1,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0};
// END GENERATED FIXTURES
bool OnGrid(const double price,const double tick)
  {
   double x=price/tick;
   return(MathAbs(x-MathFloor(x+0.5))<1e-6);
  }
void RunCase(const int i)
  {
   STgResult r;
   bool ok=TG_Compute(C_DIR[i],C_E[i],C_S[i],C_HAST[i]==1,C_T[i],C_TICK[i],C_DIG[i],C_POINT[i],C_STOPS[i],
                      C_HASQ[i]==1,C_BID[i],C_ASK[i],r);
   string tag=C_NAME[i]+": ";
   Check(TG_StatusName(r.status)==X_STATUS[i],tag+"status "+TG_StatusName(r.status)+" expected "+X_STATUS[i]);
   Check(ok==(X_STATUS[i]=="OK"),tag+"return value matches status");
   Check(TG_PendingName(r.pending_check)==X_PEND[i],tag+"pending check "+TG_PendingName(r.pending_check));
   if(X_STATUS[i]!="OK") Check(r.reason!="",tag+"reason reported");
   if(X_WHY[i]!="") Check(StringFind(r.reason,X_WHY[i])==0,tag+"reason tag "+X_WHY[i]+" got: "+r.reason);
   if(X_WHY[i]!="") Check(!r.computed && r.e_out==0.0 && r.s_out==0.0 && r.r_geom==0.0 && r.level_2r==0.0 && r.tp==0.0 &&
                          r.partial_price==0.0 && r.e_ticks==0 && r.two_r_ticks==0 && r.tp_ticks==0,tag+"no geometry reported on failure");
   if(X_HASNUM[i]==1)
     {
      Check(Near(r.e_out,X_E[i]) && Near(r.s_out,X_S[i]),tag+"normalized E and S");
      Check(Near(r.r_geom,X_R[i]),tag+"R_geom");
      Check(Near(r.level_2r,X_2R[i]) && Near(r.partial_price,X_2R[i]),tag+"2R level and partial price");
      Check(Near(r.tp,X_TP[i]),tag+"TP");
      Check(TG_TargetCaseName(r.target_case)==X_CASE[i],tag+"target case "+TG_TargetCaseName(r.target_case));
      Check(r.tp_equals_2r==(X_COINC[i]==1),tag+"TP/partial coincidence flag");
      // invariants: computed from exactly the reported prices, all on the grid
      int sign=(C_DIR[i]==TG_BUY ? 1 : -1);
      Check(Near(MathAbs(r.e_out-r.s_out),r.r_geom),tag+"|E_out-S_out| equals R_geom");
      Check(Near(r.level_2r,r.e_out+sign*2.0*r.r_geom),tag+"level_2R equals E_out +/- 2*R_geom");
      Check(OnGrid(r.e_out,C_TICK[i]) && OnGrid(r.s_out,C_TICK[i]) && OnGrid(r.level_2r,C_TICK[i]) && OnGrid(r.tp,C_TICK[i]),
            tag+"E, S, 2R and TP are multiples of the tick");
     }
  }
void OnStart()
  {
   for(int i=0;i<NCASES;i++) RunCase(i);

   // determinism, no change to the caller's inputs (all by value / const), frozen labels
   STgResult a,b;
   double e=2500.07,s=2507.64,t=2480.03,bid=2499.0,ask=2500.2;
   TG_Compute(TG_SELL,e,s,true,t,0.05,2,0.01,30,true,bid,ask,a);
   TG_Compute(TG_SELL,e,s,true,t,0.05,2,0.01,30,true,bid,ask,b);
   Check(a.status==b.status && a.e_out==b.e_out && a.s_out==b.s_out && a.level_2r==b.level_2r && a.tp==b.tp &&
         a.reason==b.reason && a.pending_check==b.pending_check,"determinism: same inputs, same outputs");
   Check(e==2500.07 && s==2507.64 && t==2480.03 && bid==2499.0 && ask==2500.2,"inputs unchanged");
   Check(TG_PartialLabel()=="PARTIAL_AT_2R (client answer: 80% of initial volume)","partial label");
   Check(TG_CostsLabel()=="COSTS_NOT_MODELLED","costs label");
   Check(StringFind(TG_UnenforcedNote(),"50 stop-distance")>=0,"50 limit declared unenforced");

   // normalization contract: 2R must come from the REPORTED stop, never the raw one
   TG_Compute(TG_BUY,2000.02,1994.93,false,0.0,0.05,2,0.01,0,false,0.0,0.0,a);
   Check(a.status==TG_OK && Near(a.e_out,2000.00) && Near(a.s_out,1994.95) && Near(a.level_2r,2010.10),
         "2R follows the normalized stop (2010.10), not the raw one (2010.14)");
   Check(a.e_ticks==40000 && a.s_ticks==39899 && a.r_ticks==101 && a.two_r_ticks==40202,"integer ticks");

   // half-tick convention (proposal): up, for E and S
   Check(TG_NearestTicks(2000.025,0.05)==40001 && TG_NearestTicks(1999.975,0.05)==40000 && TG_NearestTicks(1507.5,1.0)==1508,
         "exact half tick goes up");
   Check(TG_AwayTicks(2012.33,0.05,TG_BUY)==40247 && TG_AwayTicks(2012.33,0.05,TG_SELL)==40246 &&
         TG_AwayTicks(2012.35,0.05,TG_BUY)==40247,"target rounds away from the entry");

   // non-finite and malformed input
   double nan=MathSqrt(-1.0);
   TG_Compute(TG_BUY,nan,1995.0,false,0.0,0.01,2,0.01,0,false,0.0,0.0,a);
   Check(a.status==TG_INVALID_INPUT,"NaN entry is INVALID_INPUT");
   TG_Compute(TG_BUY,2000.0,nan,false,0.0,0.01,2,0.01,0,false,0.0,0.0,a);
   Check(a.status==TG_INVALID_INPUT,"NaN stop is INVALID_INPUT");
   TG_Compute(TG_BUY,2000.0,1995.0,true,nan,0.01,2,0.01,0,false,0.0,0.0,a);
   Check(a.status==TG_INVALID_INPUT,"NaN target is INVALID_INPUT");
   TG_Compute(TG_BUY,2000.0,1995.0,false,0.0,nan,2,0.01,0,false,0.0,0.0,a);
   Check(a.status==TG_INVALID_INPUT,"NaN tick size is INVALID_INPUT");
   TG_Compute(TG_BUY,2000.0,1995.0,false,0.0,0.01,9,0.01,0,false,0.0,0.0,a);
   Check(a.status==TG_INVALID_INPUT,"digits above 8 is INVALID_INPUT");
   TG_Compute(TG_BUY,2000.0,1995.0,false,0.0,0.01,2,0.01,0,true,nan,2001.0,a);
   Check(a.status==TG_INVALID_INPUT,"NaN bid is INVALID_INPUT");
   TG_Compute(2,2000.0,1995.0,false,0.0,0.01,2,0.01,0,false,0.0,0.0,a);
   Check(a.status==TG_INVALID_DIRECTION,"direction 2 is INVALID_DIRECTION");
   TG_Compute(TG_BUY,2100.0,2000.0,false,0.0,0.01,2,0.01,0,false,0.0,0.0,a);
   Check(a.status==TG_OK,"a 100 USD stop is not rejected: the 50 limit is not enforced");

   // tick/digits compatibility and tolerance; non-finite / overflow inputs never wrap or report garbage
   TG_Compute(TG_BUY,2000.0,1995.0,false,0.0,0.05,2,0.01,0,false,0.0,0.0,a);
   Check(a.status==TG_OK,"tick 0.05 digits 2 accepted");
   TG_Compute(TG_BUY,2000.0,1995.0,false,0.0,0.015,2,0.01,0,false,0.0,0.0,a);
   Check(a.status==TG_INVALID_INPUT && StringFind(a.reason,"INCOMPATIBLE_TICK_DIGITS")==0,"tick 0.015 digits 2 rejected");
   double inf=MathExp(1000.0);
   TG_Compute(TG_BUY,inf,1995.0,false,0.0,0.01,2,0.01,0,false,0.0,0.0,a);
   Check(a.status==TG_INVALID_INPUT,"infinite entry is INVALID_INPUT");
   TG_Compute(TG_BUY,DBL_MAX,1995.0,false,0.0,0.01,2,0.01,0,false,0.0,0.0,a);
   Check(a.status==TG_INVALID_INPUT && StringFind(a.reason,"NUMERIC_OVERFLOW")==0,"DBL_MAX entry is NUMERIC_OVERFLOW");
   TG_Compute(TG_BUY,2000.0,1995.0,false,0.0,1e308,0,1.0,0,false,0.0,0.0,a);
   Check(a.status==TG_INVALID_INPUT,"tick 1e308 with prices far below one tick never yields garbage");
   // on-grid sweep: normalization never changes an on-grid price
   double tk[]={0.01,0.05,0.25,0.5,1.0};
   int dg[]={2,2,2,1,0};
   bool grid_ok=true;
   for(int k=0;k<5;k++)
      for(long n=1;n<=2000000 && grid_ok;n+=997)
        {
         double p=(double)n*tk[k];
         if(TG_NearestTicks(p,tk[k])!=n || TG_TicksToPrice(n,tk[k],dg[k])!=NormalizeDouble(p,dg[k]) ||
            MathAbs(TG_TicksToPrice(n,tk[k],dg[k])-p)>1e-6*tk[k]) grid_ok=false;
        }
   Check(grid_ok,"on-grid sweep: NormalizeDouble never changes an integer-tick price");

   PrintFormat("T005 GEOMETRY TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
