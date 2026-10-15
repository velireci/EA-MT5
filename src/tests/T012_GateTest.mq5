// T012 integration test script: the preview's daily gate (DG_Evaluate / DG_FinalPreview over DailyLimits). Mirrors tests/test_t012_gate.py; the fixtures
// below are the hand-written scenario table of tests/t012_gate_fixtures.py. NOT YET COMPILED OR RUN in MT5 (UNVERIFIED).
// Pure: no order, no cancellation, no account or history read, no clock (the instant is a fixture), no persistence.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/DailyPreviewGate.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
// BEGIN GENERATED FIXTURES (tests/t012_gate_fixtures.py emit_mql)
#define NROWS 34
string R_NAME[]={"MANUAL_BOTH_OK_STAYS_OK","MANUAL_PERMIT_BLOCK_STAYS_BLOCK","MANUAL_LOSS_CHECK_FAIL_STAYS_BLOCK","MANUAL_IGNORES_A_LIMIT_BREACHING_FIGURE","MANUAL_IGNORES_GARBAGE_FIGURES","SNAPSHOT_CLEAR_BOTH_OK","SNAPSHOT_CLEAR_PERMIT_BLOCK_STILL_BLOCKS","SNAPSHOT_CLEAR_LOSS_CHECK_FAIL_STILL_BLOCKS","DAILY_WIN_STOP_BLOCKS_THE_FINAL_RESULT","DAILY_STREAK_BLOCKS_THE_FINAL_RESULT","DAILY_LOSS_BLOCKS_THE_FINAL_RESULT","DAILY_LOSS_AT_THE_LINE_BLOCKS","DAILY_LOSS_JUST_BELOW_THE_LINE_DOES_NOT_BLOCK","DAILY_TRADE_LIMIT_BLOCKS_THE_FINAL_RESULT","DAILY_COMBINED_BLOCKS_THE_FINAL_RESULT","DEFAULT_TRADE_LIMIT_UNSET_BLOCKS_WITHOUT_A_DAILY_LIMIT","UNSET_LIMIT_WITH_A_PROVEN_WIN_STOP","ALL_PREVIEW_DEFAULTS_BLOCK","UNKNOWN_RESULT_IS_INVALID_NOT_ZERO","UNKNOWN_BALANCE_IS_INVALID","UNKNOWN_TRADES_IS_INVALID","UNKNOWN_WINS_IS_INVALID","UNKNOWN_LOSS_STREAK_IS_INVALID","LIMIT_ZERO_IS_INVALID_NOT_UNSET","ABSURD_COUNTER_IS_INVALID","ABSURD_LIMIT_IS_INVALID","INVALID_FIGURES_HIDE_A_PROVEN_LIMIT","STALE_SNAPSHOT_BLOCKS","NEXT_DAY_SNAPSHOT_BLOCKS","MIDNIGHT_NEW_DAY_FRESH_SNAPSHOT_CLEAR","MIDNIGHT_OLD_DAY_SNAPSHOT_STALE","INVALID_UTC_BLOCKS_AND_INVENTS_NO_LIMIT","CONTRADICTORY_COUNTERS_BLOCK","CLEAR_SNAPSHOT_AND_NO_REASON_TEXT"};
int R_SRC[]={0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
long R_UTC[]={1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784106000,1784066400,1784066400,0,1784106000,1784106000};
int R_DAY[]={20260715,20260715,20260715,20260715,0,20260715,20260715,20260715,20260715,20260715,20260715,20260715,20260715,20260715,20260715,20260715,20260715,0,20260715,20260715,20260715,20260715,20260715,20260715,20260715,20260715,20260715,20260714,20260716,20260715,20260714,20260715,20260715,20260715};
double R_BAL[]={10000.0,10000.0,10000.0,10000.0,-1.0,10000.0,10000.0,10000.0,10000.0,10000.0,10000.0,10000.0,10000.0,10000.0,10000.0,10000.0,10000.0,-1.0,10000.0,-1.0,10000.0,10000.0,10000.0,10000.0,10000.0,10000.0,-1.0,10000.0,10000.0,10000.0,10000.0,10000.0,10000.0,10000.0};
int R_KNOWN[]={1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
double R_RES[]={0.0,0.0,0.0,-900.0,0.0,0.0,0.0,0.0,50.0,-100.0,-250.0,-200.0,-199.99,0.0,-300.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,-9999.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0};
long R_TRADES[]={0,0,0,5,-1,0,0,0,1,2,1,1,1,3,2,0,1,-1,0,0,-1,0,0,0,2000000,0,3,0,0,0,0,1,1,2};
long R_WINS[]={0,0,0,3,-1,0,0,0,1,0,0,0,0,0,1,0,1,-1,0,0,0,-1,0,0,0,0,2,0,0,0,0,1,2,0};
long R_LOSSES[]={0,0,0,0,-1,0,0,0,0,2,0,0,0,0,0,0,0,-1,0,0,0,0,-1,0,0,0,2,0,0,0,0,0,0,0};
long R_MAXT[]={3,3,3,3,-1,3,3,3,3,3,3,3,3,3,3,-1,-1,-1,3,3,3,3,3,0,3,2000000,3,3,3,3,3,3,3,3};
int R_LOSSOK[]={1,1,0,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
int R_PERMIT[]={1,0,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
int X_EVAL[]={0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
int X_ALLOWED[]={1,1,1,1,1,1,1,1,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,1};
string X_REASONS[]={"","","","","","","","","DAILY_WIN_STOP","CONSECUTIVE_LOSSES_STOP","DAILY_LOSS_LIMIT","DAILY_LOSS_LIMIT","","MAX_TRADES_REACHED","DAILY_WIN_STOP|DAILY_LOSS_LIMIT","POLICY_UNSET:max_trades_per_day","DAILY_WIN_STOP|POLICY_UNSET:max_trades_per_day","INVALID_SNAPSHOT:snapshot_day|INVALID_SNAPSHOT:balance_start|INVALID_SNAPSHOT:closed_result|INVALID_SNAPSHOT:trades_today|INVALID_SNAPSHOT:wins_today|INVALID_SNAPSHOT:consecutive_losses","INVALID_SNAPSHOT:closed_result","INVALID_SNAPSHOT:balance_start","INVALID_SNAPSHOT:trades_today","INVALID_SNAPSHOT:wins_today","INVALID_SNAPSHOT:consecutive_losses","INVALID_SNAPSHOT:max_trades_per_day","INVALID_SNAPSHOT:trades_today","INVALID_SNAPSHOT:max_trades_per_day","INVALID_SNAPSHOT:balance_start|INCONSISTENT_COUNTERS:wins_plus_losses_exceed_trades","STALE_SNAPSHOT_DAY","STALE_SNAPSHOT_DAY","","STALE_SNAPSHOT_DAY","INVALID_UTC","INCONSISTENT_COUNTERS:wins_exceed_trades",""};
int X_FINAL[]={1,0,0,1,1,1,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,1};
int X_CANCEL[]={0,0,0,0,0,0,0,0,1,1,1,1,0,1,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
// END GENERATED FIXTURES
void RunRows(void)
  {
   for(int i=0;i<NROWS;i++)
     {
      SDlResult d;
      bool ev=DG_Evaluate(R_SRC[i]==1,(datetime)R_UTC[i],R_DAY[i],R_BAL[i],R_KNOWN[i]==1,R_RES[i],R_TRADES[i],R_WINS[i],R_LOSSES[i],R_MAXT[i],d);
      string tag=R_NAME[i]+": ";
      bool allowed=(ev ? d.entry_allowed : true);
      string reasons=(ev ? DL_Joined(d) : "");
      bool cancel=(ev ? d.cancel_pending_due : false);
      bool final=DG_FinalPreview(R_LOSSOK[i]==1,R_PERMIT[i]==1,ev,d.entry_allowed);
      Check((int)ev==X_EVAL[i],tag+"evaluated "+(string)ev);
      Check((int)allowed==X_ALLOWED[i],tag+"daily allowed "+(string)allowed+" ("+reasons+")");
      Check(reasons==X_REASONS[i],tag+"daily reasons '"+reasons+"' expected '"+X_REASONS[i]+"'");
      Check((int)final==X_FINAL[i],tag+"final preview "+(string)final);
      Check((int)cancel==X_CANCEL[i] && (!ev || (int)d.daily_limit_reached==X_CANCEL[i]),tag+"cancel_pending_due (diagnostic) "+(string)cancel);
      if(ev && !d.entry_allowed)
         Check(!final,tag+"a daily BLOCK reaches the final result");
      if(!ev)
         Check(final==(R_LOSSOK[i]==1 && R_PERMIT[i]==1),tag+"MANUAL: the final result is the existing one");
     }
  }
void TestTruthTable(void)
  {
   int bad=0;
   for(int l=0;l<2;l++)
      for(int p=0;p<2;p++)
         for(int e=0;e<2;e++)
            for(int a=0;a<2;a++)
              {
               bool f=DG_FinalPreview(l==1,p==1,e==1,a==1);
               bool want=(l==1 && p==1 && (e==0 || a==1));
               if(f!=want) bad++;
               if(e==1 && a==0 && f) bad++;                       // a daily BLOCK never allows
               if(e==0 && f!=(l==1 && p==1)) bad++;               // MANUAL changes nothing
              }
   Check(bad==0,"truth table: the final result is existing checks AND (not evaluated OR daily allowed)");
  }
void TestCounter(void)
  {
   Check(DG_Counter(0)==0 && DG_Counter(5)==5 && DG_Counter(-1)==-1 && DG_Counter(DL_MAX_COUNT)==DL_MAX_COUNT && DG_Counter(DL_MAX_COUNT+1)==-1,"counters: 0..100000 pass, anything else is invalid (-1)");
  }
void OnStart()
  {
   RunRows();
   TestTruthTable();
   TestCounter();
   PrintFormat("T012 GATE TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
