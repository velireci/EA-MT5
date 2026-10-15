//+------------------------------------------------------------------+
//| XauUsdT011RestartRestore.mq5                                     |
//| T011 restart PROBE, step 2 of 3: RESTORE (after closing and      |
//| reopening MT5). Reads VELO_T011_RESTART_PROBE.state with the     |
//| existing modules and checks: request id, plan, step,             |
//| confirmations, no invented order map, no second request on       |
//| repeated quotes, reconciliation required. It never writes the    |
//| record, never confirms an execution, sends nothing.              |
//| Cleanup (explicit, step 3): InpCleanupProbeFile deletes ONLY the |
//| probe's own file. UNVERIFIED until the owner runs it.            |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs
#property version "1.00"
#property description "T011 restart probe RESTORE. Read-only check of the synthetic record. No trading."
#include "include/T011RestartProbe.mqh"

input bool InpCleanupProbeFile=false; // true = ONLY delete the probe's own files (VELO_T011_RESTART_PROBE.state and .tmp), nothing else is run. Leave false for the probe (just press OK)

int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }

void OnStart()
  {
   if(InpCleanupProbeFile)
     {
      bool had=ESF_Exists(RP_FILE),had_tmp=ESF_Exists(RP_FILE+ESF_TMP_SUFFIX);
      if(had) FileDelete(RP_FILE);
      if(had_tmp) FileDelete(RP_FILE+ESF_TMP_SUFFIX);
      PrintFormat("T011 RESTART RESTORE: CLEANUP removed the probe's own files only (state %s, temporary %s). Nothing else was touched.",(had ? "deleted" : "absent"),(had_tmp ? "deleted" : "absent"));
      return;
     }
   Print("T011 RESTART RESTORE: read-only check of the synthetic probe record. No order, no position read, the record is not written, no execution is confirmed.");
   SEsIdentity id;
   string why;
   if(!RP_Identity(id,why))
     {
      Print("T011 RESTART RESTORE: STOP ",why);
      return;
     }
   SEaState st;
   SEsRestore o;
   ESF_Load(RP_FILE,id,st,o);
   PrintFormat("T011 RESTART RESTORE: verdict %s | status %s | generation %d | new_request_allowed %d | reconcile_required %d | order map entries %d | reason: %s",
               ESC_VerdictName(o.verdict),EA_StateName(st.status),o.generation,(int)o.new_request_allowed,(int)o.reconcile_required,o.n_orders,o.reason);
   if(o.generation==0)
     {
      Check(false,"the probe record could not be restored (see the reason above); run XauUsdT011RestartPrepare first, on the same account");
      PrintFormat("T011 RESTART RESTORE finished: %d passed, %d failed",g_pass,g_fail);
      return;
     }
   Check(o.generation==RP_EXPECT_GENERATION,"the saved generation survived the terminal restart: "+IntegerToString(o.generation));
   Check(st.request_id==EA_RequestId((ulong)RP_POSITION),"request_id preserved: "+st.request_id);
   Check(st.position_id==(ulong)RP_POSITION && st.direction==RP_DIRECTION && st.level==RP_LEVEL && st.volume_initial==RP_VOLUME_INITIAL,"identity of the plan preserved (position, direction, level, initial volume)");
   Check(st.initial_steps==RP_EXPECT_INITIAL_STEPS && st.request_steps==RP_EXPECT_REQUEST_STEPS && MathAbs(st.close_volume-RP_EXPECT_CLOSE_VOLUME)<1e-12,"plan preserved: 80% = 40 of 50 steps, close volume 0.40");
   Check(st.volume_step==RP_VOLUME_STEP,"volume step preserved: "+DoubleToString(st.volume_step,2));
   Check(st.confirmations==0 && st.executed_steps==0 && st.status!=EA_ST_DONE,"no confirmation or execution was added or invented");
   Check(o.n_orders==0 && !o.map_complete,"no order map was invented");
   Check(o.verdict==ESC_RECOVERY_REQUIRED && st.status==EA_ST_NEEDS_RECONCILIATION && o.reconcile_required && !o.new_request_allowed,"the uncertain send is RECOVERY_REQUIRED: reconciliation required, no new request allowed");
   int requests=0;
   for(int k=0;k<3;k++)
     {
      SEaResult r;
      if(RP_Quote(st,r,RP_BID+0.5*(k+1))) requests++;
      Check(r.event==EA_EV_RECONCILE_REQUIRED && r.action==EA_ACT_NONE,"repeated quote "+IntegerToString(k+1)+" at/above the level: "+EA_EventName(r.event)+", no action");
     }
   Check(requests==0,"the repeated quotes produced no second request");
   PrintFormat("T011 RESTART RESTORE finished: %d passed, %d failed",g_pass,g_fail);
   Print("T011 RESTART RESTORE: this proves persistence across a TERMINAL restart only. It is not the restart of a trading EA and not a reconciliation with the broker (no map, no snapshot). When done, run this script again with InpCleanupProbeFile=true.");
  }
