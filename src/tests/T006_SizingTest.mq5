// T006 test script: pure position sizing. Mirrors tests/test_t006_sizing.py; the fixtures below are the
// hand-computed table of tests/t006_sizing_fixtures.py. NOT YET COMPILED OR RUN in MT5 (UNVERIFIED).
// Tests the sizing helper only: no order, no account or symbol read, no live price. Says nothing about entry quality.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/PositionSizing.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
bool Near(const double a,const double b) {return(MathAbs(a-b)<1e-9*MathMax(1.0,MathAbs(b)));}
// BEGIN GENERATED FIXTURES (tests/t006_sizing_fixtures.py emit_mql)
#define NCASES 80
string C_NAME[]={"BUY_STEP_001","SELL_STEP_001","BUY_STEP_01","SELL_STEP_01","BUY_STEP_005","BUY_STEP_1","BUY_STEP_0001","SELL_STEP_0001","BUY_STEP_05","BUY_EXACT_03_STEP_01","BUY_EXACT_007","BUY_EXACT_029","SELL_EXACT_16","BUY_TOLERANCE_OVERSHOOT","BUY_EPS_BUMP_NEEDED","BUY_TICKVALUE_08_EXACT","BUY_TICKVALUE_08","SELL_TICKVALUE_2","BUY_TICK005_TV5","SELL_TICK005_TV5","BUY_BELOW_MIN","SELL_BELOW_MIN","BUY_ROUNDS_TO_ZERO","BUY_EXACTLY_MIN","BUY_ABOVE_MAX","SELL_ABOVE_MAX","BUY_EXACTLY_MAX","BUY_ABOVE_CAP","SELL_ABOVE_CAP","BUY_EXACTLY_CAP","BUY_CAP_OFF_GRID_ABOVE","BUY_CAP_OFF_GRID_BELOW","BUY_CAP_FLOAT_03","BUY_CAP_JUST_BELOW_STEP01","BUY_CAP_ON_GRID_STEP01","BUY_CAP_JUST_ABOVE_STEP01","SELL_CAP_JUST_BELOW_STEP01","SELL_CAP_ON_GRID_STEP01","SELL_CAP_JUST_ABOVE_STEP01","BUY_CAP_JUST_BELOW_STEP001","BUY_CAP_ON_GRID_STEP001","BUY_CAP_JUST_ABOVE_STEP001","SELL_CAP_JUST_BELOW_STEP001","SELL_CAP_ON_GRID_STEP001","BUY_CAP_JUST_BELOW_STEP005","BUY_CAP_ON_GRID_STEP005","BUY_CAP_JUST_ABOVE_STEP005","BUY_CAP_LARGE_ON_GRID","BUY_CAP_LARGE_JUST_BELOW","BUY_CAP_NOISE_07","BUY_CAP_NOISE_SUM_03","BUY_CAP_GREATER_THAN_MAX","BUY_CAP_SMALLER_THAN_MAX","BUY_BOTH_EXCEEDED","BUY_CAP_BELOW_MIN","BUY_MIN_EQUALS_MAX","GEOMETRY_ZERO_RISK","GEOMETRY_SL_WRONG_SIDE","GEOMETRY_BAD_DIRECTION","GEOMETRY_WINS_OVER_BAD_RISK","RISK_ZERO","RISK_NEGATIVE","TICKVALUE_ZERO","TICKVALUE_NEGATIVE","VMIN_ZERO","STEP_ZERO","STEP_NEGATIVE","VMAX_ZERO","CAP_ZERO","CAP_NEGATIVE","FIRST_FAILURE_RISK_BEFORE_TICKVALUE","MAX_BELOW_MIN","MIN_OFF_GRID","MIN_BELOW_ONE_STEP","MAX_OFF_GRID","MIN_OFF_GRID_STEP_01","STEP_TINY","CAP_TOO_MANY_STEPS","RAW_OVERFLOW","RAW_NOT_FINITE"};
int C_DIR[]={1,-1,1,-1,1,1,1,-1,1,1,1,1,-1,1,1,1,1,-1,1,-1,1,-1,1,1,1,-1,1,1,-1,1,1,1,1,1,1,1,-1,-1,-1,1,1,1,-1,-1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
double C_E[]={1950.4,2310.2,1950.4,2310.2,1950.4,1950.4,1950.4,2310.2,1950.4,1950.4,1950.4,1950.4,2310.2,1950.4,1950.1,1950.4,1950.4,2310.2,2500.05,2500.05,1950.4,2310.2,1950.4,1950.4,1950.4,2310.2,1950.4,1950.4,2310.2,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,2310.2,2310.2,2310.2,1950.4,1950.4,1950.4,2310.2,2310.2,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4,1950.4};
double C_S[]={1944.15,2316.45,1944.15,2316.45,1944.15,1944.15,1944.15,2316.45,1944.15,1944.15,1944.15,1944.15,2316.45,1944.15,1950.0,1944.15,1944.15,2316.45,2492.45,2507.65,1944.15,2316.45,1944.15,1944.15,1944.15,2316.45,1944.15,1944.15,2316.45,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,2316.45,2316.45,2316.45,1944.15,1944.15,1944.15,2316.45,2316.45,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1950.4,1955.0,1944.15,1950.4,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15,1944.15};
double C_TICK[]={0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.05,0.05,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01};
int C_DIG[]={2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2};
double C_BUDGET[]={1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,187.5,43.75,181.25,1000.0,187.49996875,0.29,1000.0,1234.56,1234.56,2000.0,2000.0,50.0,50.0,5.0,62.5,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,187.5,187.5,187.5,187.5,187.5,187.5,187.5,18.75,18.75,18.75,18.75,18.75,93.75,93.75,93.75,3125000.0,3125000.0,437.5,187.5,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,-1.0,0.0,-5.0,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,0.0,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1234.56,1e+300,1e+100};
double C_TV[]={1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0.8,0.8,2.0,5.0,5.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0.0,-1.0,1.0,1.0,1.0,1.0,1.0,1.0,0.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1e-300};
double C_VMIN[]={0.01,0.01,0.1,0.1,0.05,1.0,0.001,0.001,0.5,0.1,0.01,0.01,0.01,0.1,0.001,0.01,0.01,0.01,0.01,0.01,0.1,0.1,0.01,0.1,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.01,0.01,0.01,0.01,0.01,0.05,0.05,0.05,0.001,0.001,0.1,0.1,0.01,0.01,0.01,0.1,1.97,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.0,0.01,0.01,0.01,0.01,0.01,0.01,1.0,0.015,0.004,0.01,0.15,1e-12,0.01,0.01,0.01};
double C_STEP[]={0.01,0.01,0.1,0.1,0.05,1.0,0.001,0.001,0.5,0.1,0.01,0.01,0.01,0.1,0.001,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.01,0.01,0.01,0.01,0.01,0.05,0.05,0.05,0.001,0.001,0.1,0.1,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.0,-0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.1,1e-12,0.01,0.01,0.01};
double C_VMAX[]={100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,50.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,1.5,1.5,1.97,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,10000.0,10000.0,100.0,100.0,1.5,100.0,1.5,100.0,1.97,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,0.0,100.0,100.0,100.0,0.5,100.0,100.0,5.005,100.0,100.0,100.0,100.0,100.0};
double C_CAP[]={10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,1.5,1.5,1.97,1.975,1.969,0.3,0.29999995,0.3,0.30000005,0.29999995,0.3,0.30000005,0.0299999,0.03,0.0300001,0.0299999,0.03,0.1499999,0.15,0.1500001,5000.0,4999.999999999,0.7,0.30000000000000004,10.0,1.5,1.0,0.05,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,0.0,-10.0,10.0,10.0,10.0,10.0,10.0,10.0,10.0,100000000.0,10.0,10.0};
string X_STATUS[]={"OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","SKIP_BELOW_MIN_VOLUME","SKIP_BELOW_MIN_VOLUME","SKIP_BELOW_MIN_VOLUME","OK","SKIP_ABOVE_MAX_VOLUME","SKIP_ABOVE_MAX_VOLUME","OK","SKIP_ABOVE_CAP","SKIP_ABOVE_CAP","OK","OK","SKIP_ABOVE_CAP","OK","SKIP_ABOVE_CAP","OK","OK","SKIP_ABOVE_CAP","OK","OK","SKIP_ABOVE_CAP","OK","OK","SKIP_ABOVE_CAP","OK","SKIP_ABOVE_CAP","OK","OK","OK","SKIP_ABOVE_CAP","OK","OK","SKIP_ABOVE_MAX_VOLUME","SKIP_ABOVE_CAP","SKIP_ABOVE_MAX_VOLUME","SKIP_ABOVE_CAP","OK","GEOMETRY_NOT_OK","GEOMETRY_NOT_OK","GEOMETRY_NOT_OK","GEOMETRY_NOT_OK","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT"};
string X_WHY[]={"","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","GEOMETRY_NOT_OK","GEOMETRY_NOT_OK","GEOMETRY_NOT_OK","GEOMETRY_NOT_OK","INVALID_RISK_BUDGET","INVALID_RISK_BUDGET","INVALID_TICK_VALUE","INVALID_TICK_VALUE","INVALID_VOLUME_MIN","INVALID_VOLUME_STEP","INVALID_VOLUME_STEP","INVALID_VOLUME_MAX","INVALID_CAP","INVALID_CAP","INVALID_RISK_BUDGET","VOLUME_MAX_BELOW_MIN","VOLUME_NOT_ON_GRID","VOLUME_NOT_ON_GRID","VOLUME_NOT_ON_GRID","VOLUME_NOT_ON_GRID","STEP_RANGE","STEP_RANGE","NUMERIC_OVERFLOW","NUMERIC_OVERFLOW"};
int X_HASNUM[]={1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
long X_STOP[]={625,625,625,625,625,625,625,625,625,625,625,625,625,625,10,625,625,625,152,152,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,625,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
double X_LOSS[]={625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,10.0,500.0,500.0,1250.0,760.0,760.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,625.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0};
long X_STEPS[]={197,197,19,19,39,1,1975,1975,3,3,7,29,160,2,29,200,246,98,263,263,8,8,0,10,197,197,197,197,197,197,197,197,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,5000000,5000000,7,3,197,197,197,197,197,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
double X_VOL[]={1.97,1.97,1.9,1.9,1.95,1.0,1.975,1.975,1.5,0.3,0.07,0.29,1.6,0.2,0.029,2.0,2.46,0.98,2.63,2.63,0.0,0.0,0.0,0.1,0.0,0.0,1.97,0.0,0.0,1.97,1.97,0.0,0.3,0.0,0.3,0.3,0.0,0.3,0.3,0.0,0.03,0.03,0.0,0.03,0.0,0.15,0.15,5000.0,0.0,0.7,0.3,0.0,0.0,0.0,0.0,1.97,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0};
double X_RISK[]={1231.25,1231.25,1187.5,1187.5,1218.75,625.0,1234.375,1234.375,937.5,187.5,43.75,181.25,1000.0,125.0,0.29,1000.0,1230.0,1225.0,1998.8,1998.8,0.0,0.0,0.0,62.5,0.0,0.0,1231.25,0.0,0.0,1231.25,1231.25,0.0,187.5,0.0,187.5,187.5,0.0,187.5,187.5,0.0,18.75,18.75,0.0,18.75,0.0,93.75,93.75,3125000.0,0.0,437.5,187.5,0.0,0.0,0.0,0.0,1231.25,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0};
// END GENERATED FIXTURES
bool OnGridStep(const double value,const double step)
  {
   double x=value/step;
   return(MathAbs(x-MathFloor(x+0.5))<=PS_EPS_STEPS);
  }
void RunCase(const int i)
  {
   STgResult g;
   TG_Compute(C_DIR[i],C_E[i],C_S[i],false,0.0,C_TICK[i],C_DIG[i],0.01,0,false,0.0,0.0,g);
   SPsResult r;
   bool ok=PS_Compute(g,C_BUDGET[i],C_TV[i],C_VMIN[i],C_STEP[i],C_VMAX[i],C_CAP[i],r);
   string tag=C_NAME[i]+": ";
   Check(PS_StatusName(r.status)==X_STATUS[i],tag+"status "+PS_StatusName(r.status)+" expected "+X_STATUS[i]+" ("+r.reason+")");
   Check(ok==(X_STATUS[i]=="OK"),tag+"return value matches status");
   if(X_STATUS[i]!="OK") Check(r.reason!="",tag+"reason reported");
   if(X_WHY[i]!="") Check(StringFind(r.reason,X_WHY[i])==0,tag+"reason tag "+X_WHY[i]+" got: "+r.reason);
   if(X_HASNUM[i]==0)
     {
      Check(!r.computed && r.stop_ticks==0 && r.loss_per_lot==0.0 && r.risk_per_step==0.0 && r.volume_raw==0.0 && r.steps_rounded==0 &&
            r.min_steps==0 && r.max_steps==0 && r.cap_steps==0 && r.volume_out==0.0 && r.risk_realized==0.0 && !r.step_rounded &&
            r.volume_rounding_loss==0.0 && r.risk_unused==0.0,tag+"nothing reported on failure");
     }
   else
     {
      Check(r.computed && r.stop_ticks==X_STOP[i],tag+"stop ticks");
      Check(Near(r.loss_per_lot,X_LOSS[i]),tag+"loss per lot");
      Check(r.steps_rounded==X_STEPS[i],tag+"steps "+IntegerToString(r.steps_rounded)+" expected "+IntegerToString(X_STEPS[i]));
      Check(Near(r.volume_out,X_VOL[i]) && Near(r.risk_realized,X_RISK[i]),tag+"volume and realized risk");
      if(X_STATUS[i]!="OK")
         Check(r.volume_out==0.0 && r.risk_realized==0.0 && !r.step_rounded && r.volume_rounding_loss==0.0 && r.risk_unused==0.0,tag+"skip: no volume to act on");
      else
        {
         Check(r.risk_realized<=C_BUDGET[i],tag+"realized risk does not exceed the budget");
         Check(r.risk_realized==(double)r.steps_rounded*r.risk_per_step && r.volume_out==(double)r.steps_rounded*C_STEP[i],tag+"reported values are exactly n*step expressions");
         Check(r.volume_out>=C_VMIN[i]-1e-9 && r.volume_out<=C_VMAX[i]+1e-9 && r.steps_rounded<=r.cap_steps,tag+"volume inside min, max and cap");
        }
     }
  }
// deterministic LCG sweep: the realized risk never exceeds the budget and the result is maximal (one more step would exceed it)
ulong g_seed=88172645463325252;
double NextU()
  {
   g_seed=g_seed*6364136223846793005+1442695040888963407;
   return((double)((g_seed>>11)&0x1FFFFFFFFFFFFF)/9007199254740992.0);
  }
void Sweep()
  {
   double steps[]={0.01,0.1,0.05,1.0,0.001,0.5};
   int bad_risk=0,bad_max=0,ok_count=0,skip_count=0;
   for(int k=0;k<5000;k++)
     {
      STgResult g;
      g.status=TG_OK;
      g.computed=true;
      g.e_ticks=100000+(long)(NextU()*50000.0);
      g.s_ticks=g.e_ticks-1-(long)(NextU()*3000.0);
      double step=steps[(int)(NextU()*6.0)%6];
      double tv=0.05+NextU()*10.0;
      double budget=0.01+NextU()*20000.0;
      SPsResult r;
      PS_Compute(g,budget,tv,step,step,1000.0,1000.0,r);
      if(r.status==PS_OK)
        {
         ok_count++;
         if(r.risk_realized>budget) bad_risk++;
         if(((double)r.steps_rounded+1.0)*r.risk_per_step<=budget) bad_max++;
        }
      else skip_count++;
     }
   Check(bad_risk==0,"sweep: realized risk never exceeds the budget ("+IntegerToString(ok_count)+" OK, "+IntegerToString(skip_count)+" skip)");
   Check(bad_max==0,"sweep: one more step would always exceed the budget (maximal round down)");
   Check(ok_count>1000,"sweep: enough OK cases");
  }
void OnStart()
  {
   for(int i=0;i<NCASES;i++) RunCase(i);

   // geometry result with the real T005 numbers: BUY and SELL with the same stop ticks give the same volume
   STgResult gb,gs;
   TG_Compute(TG_BUY,1950.40,1944.15,false,0.0,0.01,2,0.01,0,false,0.0,0.0,gb);
   TG_Compute(TG_SELL,2310.20,2316.45,false,0.0,0.01,2,0.01,0,false,0.0,0.0,gs);
   SPsResult a,b;
   PS_Compute(gb,1234.56,1.0,0.01,0.01,100.0,10.0,a);
   PS_Compute(gs,1234.56,1.0,0.01,0.01,100.0,10.0,b);
   Check(a.status==PS_OK && b.status==PS_OK && a.steps_rounded==b.steps_rounded && a.volume_out==b.volume_out && a.risk_realized==b.risk_realized,
         "BUY and SELL with equal stop ticks give identical volume and risk");

   // determinism; inputs untouched (all by value or const)
   double budget=1234.56,tv=0.8,vmin=0.01,step=0.01,vmax=100.0,cap=10.0;
   PS_Compute(gb,budget,tv,vmin,step,vmax,cap,a);
   PS_Compute(gb,budget,tv,vmin,step,vmax,cap,b);
   Check(a.status==b.status && a.steps_rounded==b.steps_rounded && a.volume_out==b.volume_out && a.risk_realized==b.risk_realized && a.reason==b.reason,"determinism");
   Check(budget==1234.56 && tv==0.8 && vmin==0.01 && step==0.01 && vmax==100.0 && cap==10.0 && gb.e_ticks==195040 && gb.s_ticks==194415 && gb.status==TG_OK,"inputs unchanged");

   // geometry given as a struct: an OK status with equal ticks, or not computed, is rejected without recomputation
   STgResult h;
   TG_Reset(h,TG_BUY,0.0,0.0,false,0.0);
   h.status=TG_OK; h.computed=true; h.e_ticks=195040; h.s_ticks=195040;
   PS_Compute(h,100.0,1.0,0.01,0.01,100.0,10.0,a);
   Check(a.status==PS_INVALID_INPUT && StringFind(a.reason,"INVALID_STOP_TICKS")==0,"zero stop ticks is INVALID_INPUT");
   h.e_ticks=195040; h.s_ticks=194415; h.computed=false;
   PS_Compute(h,100.0,1.0,0.01,0.01,100.0,10.0,a);
   Check(a.status==PS_GEOMETRY_NOT_OK,"geometry not computed is GEOMETRY_NOT_OK");
   h.computed=true; h.status=TG_ZERO_RISK;
   PS_Compute(h,100.0,1.0,0.01,0.01,100.0,10.0,a);
   Check(a.status==PS_GEOMETRY_NOT_OK && a.volume_out==0.0 && !a.computed,"geometry status ZERO_RISK is GEOMETRY_NOT_OK, nothing reported");
   h.status=TG_OK; h.s_ticks=195040-20000000000000;
   PS_Compute(h,100.0,1.0,0.01,0.01,100.0,10.0,a);
   Check(a.status==PS_INVALID_INPUT && StringFind(a.reason,"INVALID_STOP_TICKS")==0,"tick count beyond 1e13 is INVALID_INPUT");

   // non-finite input
   double nan=MathSqrt(-1.0);
   double inf=MathExp(1000.0);
   PS_Compute(gb,nan,1.0,0.01,0.01,100.0,10.0,a);
   Check(a.status==PS_INVALID_INPUT && StringFind(a.reason,"INVALID_RISK_BUDGET")==0,"NaN budget");
   PS_Compute(gb,1000.0,inf,0.01,0.01,100.0,10.0,a);
   Check(a.status==PS_INVALID_INPUT && StringFind(a.reason,"INVALID_TICK_VALUE")==0,"infinite tick value");
   PS_Compute(gb,1000.0,1.0,nan,0.01,100.0,10.0,a);
   Check(a.status==PS_INVALID_INPUT && StringFind(a.reason,"INVALID_VOLUME_MIN")==0,"NaN volume_min");
   PS_Compute(gb,1000.0,1.0,0.01,nan,100.0,10.0,a);
   Check(a.status==PS_INVALID_INPUT && StringFind(a.reason,"INVALID_VOLUME_STEP")==0,"NaN volume_step");
   PS_Compute(gb,1000.0,1.0,0.01,0.01,inf,10.0,a);
   Check(a.status==PS_INVALID_INPUT && StringFind(a.reason,"INVALID_VOLUME_MAX")==0,"infinite volume_max");
   PS_Compute(gb,1000.0,1.0,0.01,0.01,100.0,nan,a);
   Check(a.status==PS_INVALID_INPUT && StringFind(a.reason,"INVALID_CAP")==0,"NaN cap");

   // step is not assumed to be 0.01, and the documented conservative tie (decimal fit lost by one ulp)
   TG_Compute(TG_BUY,1950.47,1950.00,false,0.0,0.01,2,0.01,0,false,0.0,0.0,h);
   PS_Compute(h,249.1,1.0,0.1,0.1,100.0,10.0,a);
   Check(a.status==PS_OK && a.steps_rounded==52 && a.risk_realized<=249.1,"ULP tie: 47 ticks, step 0.1, budget 249.1 gives 52 steps (53 is exact in decimal), never 54");
   Check(PS_CostsLabel()=="COSTS_NOT_MODELLED","costs label");
   Check(StringFind(PS_ModelLabel(),"LINEAR_MODEL")==0,"linear model label");
   Check(StringFind(PS_NoReductionLabel(),"NO_REDUCTION_TO_LIMIT")==0,"no reduction label");

   Sweep();
   PrintFormat("T006 SIZING TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
