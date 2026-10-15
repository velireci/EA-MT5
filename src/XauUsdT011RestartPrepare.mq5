//+------------------------------------------------------------------+
//| XauUsdT011RestartPrepare.mq5                                     |
//| T011 restart PROBE, step 1 of 3: PREPARE.                        |
//| Creates and saves a SYNTHETIC request REQUEST_PENDING + send     |
//| INTENT (no order map) for a DECLARED probe position, with the    |
//| real account/server identity, in VELO_T011_RESTART_PROBE.state.  |
//| Reads and changes no position or order, sends nothing, never     |
//| overwrites an existing file. Then: close and reopen MT5, run     |
//| XauUsdT011RestartRestore. UNVERIFIED until the owner runs it.    |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"
#property description "T011 restart probe PREPARE. Synthetic record only. No trading."
#include "include/T011RestartProbe.mqh"

void OnStart()
  {
   Print("T011 RESTART PREPARE: synthetic probe record only. No order, no position read or change, no existing file is overwritten.");
   SEsIdentity id;
   string why;
   if(!RP_Identity(id,why))
     {
      Print("T011 RESTART PREPARE: STOP ",why);
      return;
     }
   if(ESF_Exists(RP_FILE) || ESF_Exists(RP_FILE+ESF_TMP_SUFFIX))
     {
      Print("T011 RESTART PREPARE: STOP the probe file already exists (",RP_FILE,"). Nothing was changed. Run XauUsdT011RestartRestore, or its cleanup option, first.");
      return;
     }
   SEaState s;
   EA_StateInit(s);
   SEaResult r;
   bool request=RP_Quote(s,r,RP_BID);
   if(!request || r.action!=EA_ACT_REQUEST_PARTIAL_CLOSE || s.status!=EA_ST_REQUEST_PENDING || s.request_steps!=RP_EXPECT_REQUEST_STEPS ||
      s.initial_steps!=RP_EXPECT_INITIAL_STEPS)
     {
      Print("T011 RESTART PREPARE: STOP the synthetic plan did not produce the expected request: ",EA_EventName(r.event)," ",r.reason);
      return;
     }
   if(!ESF_InitFresh(RP_FILE,id,why))
     {
      Print("T011 RESTART PREPARE: STOP init failed: ",why);
      return;
     }
   SEsRecord rec;
   ESC_RecordInit(rec);
   rec.generation=RP_EXPECT_GENERATION;
   rec.id=id;
   rec.state=s;
   rec.send_phase=ESC_SEND_INTENT;          // persist-before-send: the intent is saved and verified; no order is sent and no order map exists
   if(!ESF_Save(RP_FILE,rec,why))
     {
      Print("T011 RESTART PREPARE: STOP the PENDING + INTENT record could not be saved: ",why,". The file may hold the IDLE record; clean it up with the RESTORE cleanup option.");
      return;
     }
   PrintFormat("T011 RESTART PREPARE: OK saved %s | account %I64d on '%s' | probe position %I64u symbol %s | request %s steps %I64d of %I64d, close volume %.2f, step %.2f | status %s | send INTENT, no order map | generation %d",
               RP_FILE,id.login,id.server,id.position_id,id.symbol,s.request_id,s.request_steps,s.initial_steps,s.close_volume,s.volume_step,EA_StateName(s.status),rec.generation);
   Print("T011 RESTART PREPARE: NEXT close MT5 completely, reopen it, then run XauUsdT011RestartRestore. This proves persistence across a TERMINAL restart only: no trading EA restart, no broker reconciliation.");
  }
