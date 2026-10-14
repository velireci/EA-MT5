// T011 test script: pure 80/20 exit split. Mirrors tests/test_t011_split.py; the fixtures below are the hand-computed
// table of tests/t011_split_fixtures.py. NOT YET COMPILED OR RUN in MT5 (UNVERIFIED).
// Tests the split helper only: no order, no account or symbol read, no price.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/ExitSplit.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
// BEGIN GENERATED FIXTURES (tests/t011_split_fixtures.py emit_mql)
#define NCASES 36
string C_NAME[]={"EXACT_0_10","SMALLEST_EXACT_0_05","STEP_0_1","LARGE_10_LOTS","STEP_0_05","STEP_0_001","INITIAL_EQUALS_MAX","REMAINDER_EQUALS_MIN","NOISY_DIVISION_0_35","NOISY_DIVISION_0_15","NOISY_DIVISION_0_3_STEP_0_1","MIN_LOT_ONE_STEP_GRID_0_1","ONE_STEP","SEVEN_STEPS","ELEVEN_STEPS","NINETY_NINE_STEPS","EXACTNESS_BEFORE_MIN","REMAINDER_BELOW_MIN_1_OF_2","REMAINDER_BELOW_MIN_2_OF_3","INITIAL_EQUALS_MIN","MIN_LOT_ONLY_STEP_0_1","INITIAL_ZERO","INITIAL_NEGATIVE","VMIN_ZERO","STEP_ZERO","STEP_NEGATIVE","VMAX_ZERO","FIRST_FAILURE_STEP_BEFORE_INITIAL","MAX_BELOW_MIN","STEP_RANGE_MAX","MIN_OFF_GRID","MAX_OFF_GRID","INITIAL_OFF_GRID","INITIAL_BELOW_ONE_STEP","INITIAL_BELOW_MIN","INITIAL_ABOVE_MAX"};
double C_INIT[]={0.1,0.05,1.0,10.0,0.5,0.015,100.0,0.1,0.35,0.15,3.0,0.5,0.01,0.07,0.11,0.99,0.07,0.05,0.1,0.05,0.1,0.0,-0.1,0.1,0.1,0.1,0.1,0.0,0.1,0.1,0.1,0.1,0.105,0.004,0.05,200.0};
double C_VMIN[]={0.01,0.01,0.1,0.01,0.05,0.001,0.01,0.02,0.01,0.01,0.1,0.1,0.01,0.01,0.01,0.01,0.05,0.02,0.03,0.05,0.1,0.01,0.01,0.0,0.01,0.01,0.01,0.01,1.0,0.01,0.015,0.01,0.01,0.01,0.1,0.01};
double C_STEP[]={0.01,0.01,0.1,0.01,0.05,0.001,0.01,0.01,0.01,0.01,0.1,0.1,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.1,0.01,0.01,0.01,0.0,-0.01,0.01,0.0,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01};
double C_VMAX[]={100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0,0.0,100.0,0.5,100000000.0,100.0,5.005,100.0,100.0,100.0,100.0};
string X_STATUS[]={"OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","OK","SPLIT_POLICY_UNSET","SPLIT_POLICY_UNSET","SPLIT_POLICY_UNSET","SPLIT_POLICY_UNSET","SPLIT_POLICY_UNSET","SPLIT_POLICY_UNSET","SPLIT_POLICY_UNSET","SPLIT_POLICY_UNSET","SPLIT_POLICY_UNSET","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT"};
string X_WHY[]={"","","","","","","","","","","","","NOT_EXACT_80_20","NOT_EXACT_80_20","NOT_EXACT_80_20","NOT_EXACT_80_20","NOT_EXACT_80_20","REMAINDER_BELOW_MIN","REMAINDER_BELOW_MIN","REMAINDER_BELOW_MIN","NOT_EXACT_80_20","INVALID_INITIAL","INVALID_INITIAL","INVALID_VOLUME_MIN","INVALID_VOLUME_STEP","INVALID_VOLUME_STEP","INVALID_VOLUME_MAX","INVALID_VOLUME_STEP","VOLUME_MAX_BELOW_MIN","STEP_RANGE","VOLUME_NOT_ON_GRID","VOLUME_NOT_ON_GRID","VOLUME_NOT_ON_GRID","VOLUME_NOT_ON_GRID","INITIAL_BELOW_MIN","INITIAL_ABOVE_MAX"};
long X_N[]={10,5,10,1000,10,15,10000,10,35,15,30,5,1,7,11,99,7,5,10,5,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
long X_CLOSE[]={8,4,8,800,8,12,8000,8,28,12,24,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
long X_REM[]={2,1,2,200,2,3,2000,2,7,3,6,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
// END GENERATED FIXTURES
void RunCase(const int i)
  {
   SEsResult r;
   bool ok=ES_Split(C_INIT[i],C_VMIN[i],C_STEP[i],C_VMAX[i],r);
   string tag=C_NAME[i]+": ";
   Check(ES_StatusName(r.status)==X_STATUS[i],tag+"status "+ES_StatusName(r.status)+" expected "+X_STATUS[i]+" ("+r.reason+")");
   Check(ok==(X_STATUS[i]=="OK"),tag+"return value matches status");
   if(X_STATUS[i]!="OK") Check(r.reason!="",tag+"reason reported");
   if(X_WHY[i]!="") Check(StringFind(r.reason,X_WHY[i])==0,tag+"reason tag "+X_WHY[i]+" got: "+r.reason);
   if(X_STATUS[i]=="OK")
     {
      Check(r.initial_steps==X_N[i] && r.close_steps==X_CLOSE[i] && r.remaining_steps==X_REM[i],tag+"steps "+IntegerToString(r.close_steps)+"/"+IntegerToString(r.remaining_steps));
      Check(r.close_steps+r.remaining_steps==r.initial_steps,tag+"volume conserved in steps");
      Check(r.close_steps*ES_CLOSE_DEN==r.initial_steps*ES_CLOSE_NUM,tag+"exactly 80 percent in integers");
      Check(r.close_percent==0.8,tag+"real percent is 0.8");
      Check(r.close_volume==(double)r.close_steps*C_STEP[i] && r.remaining_volume==(double)r.remaining_steps*C_STEP[i],tag+"volumes are n*step expressions");
      Check(MathAbs(r.close_volume+r.remaining_volume-C_INIT[i])<=8.0*DBL_EPSILON*MathMax(1.0,C_INIT[i]),tag+"volume conserved within ulps");
      Check(r.remaining_steps>=r.min_steps && r.close_steps<=r.max_steps,tag+"both parts inside min and max");
     }
   else if(X_STATUS[i]=="SPLIT_POLICY_UNSET")
     {
      Check(r.initial_steps==X_N[i] && r.close_steps==0 && r.remaining_steps==0 && r.close_volume==0.0 && r.remaining_volume==0.0 && r.close_percent==0.0,
            tag+"no volume reported, only step diagnostics");
     }
   else
      Check(r.initial_steps==0 && r.min_steps==0 && r.max_steps==0 && r.close_steps==0 && r.remaining_steps==0 && r.close_volume==0.0 &&
            r.remaining_volume==0.0 && r.close_percent==0.0,tag+"nothing reported on invalid input");
  }
void OnStart()
  {
   for(int i=0;i<NCASES;i++) RunCase(i);
   double nan=MathSqrt(-1.0);
   double inf=MathExp(1000.0);
   SEsResult r;
   ES_Split(nan,0.01,0.01,100.0,r);
   Check(r.status==ES_INVALID_INPUT && StringFind(r.reason,"INVALID_INITIAL")==0,"NaN initial");
   ES_Split(0.1,nan,0.01,100.0,r);
   Check(r.status==ES_INVALID_INPUT && StringFind(r.reason,"INVALID_VOLUME_MIN")==0,"NaN volume_min");
   ES_Split(0.1,0.01,nan,100.0,r);
   Check(r.status==ES_INVALID_INPUT && StringFind(r.reason,"INVALID_VOLUME_STEP")==0,"NaN volume_step");
   ES_Split(0.1,0.01,0.01,inf,r);
   Check(r.status==ES_INVALID_INPUT && StringFind(r.reason,"INVALID_VOLUME_MAX")==0,"infinite volume_max");
   ES_Split(inf,0.01,0.01,100.0,r);
   Check(r.status==ES_INVALID_INPUT && StringFind(r.reason,"INVALID_INITIAL")==0,"infinite initial");
   // sweep: every OK split conserves volume exactly in steps and is exactly 80/20; all other multiples of 5 steps of a 0.01 grid are OK
   int bad=0,ok_count=0,unset=0;
   for(int n=1;n<=2000;n++)
     {
      SEsResult s;
      ES_Split((double)n*0.01,0.01,0.01,100.0,s);
      if(s.status==ES_OK)
        {
         ok_count++;
         if(n%5!=0 || s.close_steps+s.remaining_steps!=n || s.close_steps*5!=n*4 || s.initial_steps!=n) bad++;
        }
      else
        {
         unset++;
         if(s.status!=ES_SPLIT_POLICY_UNSET || n%5==0) bad++;
        }
     }
   Check(bad==0 && ok_count==400 && unset==1600,"sweep 1..2000 steps: OK exactly when divisible by 5 ("+IntegerToString(ok_count)+" OK, "+IntegerToString(unset)+" unset)");
   PrintFormat("T011 SPLIT TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
