//+------------------------------------------------------------------+
//| XauUsdT011FlowDiag.mq5                                           |
//| T011 restart-flow DIAGNOSTIC (fixtures + sandbox file).          |
//| Narrates the whole flow LOAD -> identity -> snapshot ->          |
//| ER_Reconcile -> SAVE on a SYNTHETIC request (declared position 7,|
//| order 501) stored in VELO_T011_FLOW_DIAG.state with the real     |
//| account server/login. The terminal data are hand-written         |
//| fixtures: no position, order or deal is read, nothing is sent,   |
//| no new trade. All parameters are filled in; no input.            |
//| It deletes only its own file at the end. UNVERIFIED until run.   |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"
#property description "T011 restart flow diagnostic. Synthetic request + fixtures. No trading."
#include "include/ExitRestartFlow.mqh"

#define FD_FILE "VELO_T011_FLOW_DIAG.state"
#define FD_POSITION 7
#define FD_ORDER 501

void Raw(SXaRaw &r,const bool filled)
  {
   XA_RawInit(r);
   r.api_ok=true;
   r.symbol_ok=true;
   r.vol_step=0.01;
   r.vol_min=0.01;
   r.vol_max=100.0;
   r.margin_ok=true;
   r.margin_mode=XA_MARGIN_HEDGING;
   r.n_pos=1;
   r.pos_ticket=9;
   r.pos_type=XA_POS_BUY;
   r.pos_symbol="XAUUSD";
   r.hist_ok=true;
   r.deals_truncated=false;
   r.deal[0].ticket=100;
   r.deal[0].order=400;
   r.deal[0].position_id=FD_POSITION;
   r.deal[0].entry=XA_ENTRY_IN;
   r.deal[0].type=XA_DEAL_BUY;
   r.deal[0].volume=0.5;
   r.n_deals=1;
   r.n_orders=1;
   r.ord[0].ticket=FD_ORDER;
   r.ord[0].position_id=FD_POSITION;
   if(filled)
     {
      r.pos_volume=0.1;
      r.deal[1].ticket=1001;
      r.deal[1].order=FD_ORDER;
      r.deal[1].position_id=FD_POSITION;
      r.deal[1].entry=XA_ENTRY_OUT;
      r.deal[1].type=XA_DEAL_SELL;
      r.deal[1].volume=0.4;
      r.n_deals=2;
      r.ord[0].where=XA_WHERE_HISTORY;
      r.ord[0].state=XA_ORD_FILLED;
      r.ord[0].vol_initial=0.4;
      r.ord[0].vol_current=0.0;
     }
   else
     {
      r.pos_volume=0.5;
      r.ord[0].where=XA_WHERE_ACTIVE;
      r.ord[0].state=XA_ORD_PLACED;
      r.ord[0].vol_initial=0.4;
      r.ord[0].vol_current=0.4;
     }
  }

void Step(const string title,const SEsIdentity &id,const bool filled,const bool fail_save)
  {
   SErfInput in;
   ERF_InputInit(in);
   Raw(in.raw_a,filled);
   Raw(in.raw_b,filled);
   in.test_fail_save=fail_save;
   SErfResult res;
   ERF_Run(FD_FILE,id,in,res);
   Print("T011 FLOW DIAG [",title,"] ",ERF_Text(res));
  }

void OnStart()
  {
   Print("T011 FLOW DIAG: synthetic request on a DECLARED position (7, order 501) with fixture terminal data. No order, no position read, no new trade. Own file: ",FD_FILE);
   if(FileIsExist(FD_FILE) || FileIsExist(FD_FILE+ESF_TMP_SUFFIX))
     {
      Print("T011 FLOW DIAG: STOP the diagnostic file already exists; nothing was changed. Delete only ",FD_FILE," (and .tmp) from MQL5/Files and run again.");
      return;
     }
   SEsIdentity id;
   id.server=AccountInfoString(ACCOUNT_SERVER);
   id.login=AccountInfoInteger(ACCOUNT_LOGIN);
   id.symbol="XAUUSD";
   id.position_id=FD_POSITION;
   if(id.server=="" || id.login<=0)
     {
      Print("T011 FLOW DIAG: STOP the account identity could not be read");
      return;
     }
   PrintFormat("T011 FLOW DIAG: identity server '%s' login %I64d symbol %s position %I64u",id.server,id.login,id.symbol,id.position_id);
   // protocol of the unbuilt executor, on the synthetic request: init (IDLE) -> request + INTENT saved BEFORE any send -> order map saved after the (imaginary) acceptance
   string why;
   SEaState s;
   EA_StateInit(s);
   SEaResult r;
   EA_OnQuote(s,FD_POSITION,1,2000.0,2000.0,2000.3,0.5,0.5,0.01,0.01,100.0,r);
   if(r.action!=EA_ACT_REQUEST_PARTIAL_CLOSE || !ESF_InitFresh(FD_FILE,id,why))
     {
      Print("T011 FLOW DIAG: STOP setup failed: ",why," ",r.reason);
      return;
     }
   SEsRecord rec;
   ESC_RecordInit(rec);
   rec.id=id;
   rec.state=s;
   rec.generation=2;
   rec.send_phase=ESC_SEND_INTENT;
   bool ok=ESF_Save(FD_FILE,rec,why);
   Print("T011 FLOW DIAG: saved PENDING + INTENT (generation 2): ",ok," ",why);
   rec.generation=3;
   rec.send_phase=ESC_SEND_MAPPED;
   rec.map_complete=true;
   rec.n_orders=1;
   rec.orders[0]=FD_ORDER;
   ok=ok && ESF_Save(FD_FILE,rec,why);
   Print("T011 FLOW DIAG: saved PENDING + order map [501] (generation 3): ",ok," ",why);
   if(ok)
     {
      Step("1 fill not yet in the history: expect STILL_OPEN, nothing saved",id,false,false);
      Step("2 evidence complete but the save fails: expect RECOVERY_REQUIRED, state on disk unchanged",id,true,true);
      Step("3 evidence complete: expect DONE, saved as generation 4, confirmations 1",id,true,false);
      Step("4 the same again: expect DONE, nothing saved, confirmations still 1",id,true,false);
     }
   if(FileIsExist(FD_FILE)) FileDelete(FD_FILE);
   if(FileIsExist(FD_FILE+ESF_TMP_SUFFIX)) FileDelete(FD_FILE+ESF_TMP_SUFFIX);
   Print("T011 FLOW DIAG: own file removed. This is a FIXTURE run of the flow: it is not a trading-EA restart and not a reconciliation with the broker.");
  }
