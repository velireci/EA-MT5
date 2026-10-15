// T011 restart-flow test (fixtures + sandbox file): ERF_Run over the real ExitStateFile / ExitSnapshotAdapter (pure build over hand-written raw data) /
// ExitReconciliation. Mirrors tests/test_t011_flow.py; the fixtures below are the hand-written scenario table of tests/t011_flow_fixtures.py (equality is tested).
// Uses the file VELO_T011_FLOW_SELFTEST_A.state (+ ".tmp") that belongs ONLY to this test and is deleted before and after. No terminal read of positions, no order, no
// new trade, no clock. NOT YET COMPILED OR RUN in MT5 (UNVERIFIED).
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/ExitRestartFlow.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
// BEGIN GENERATED FIXTURES (tests/t011_flow_fixtures.py emit_mql)
#define NROWS 20
#define NPROF 8
#define MAXD 4
string P_NAME[]={"FULL","DUPLICATE_DEAL","NOT_YET_IN_HISTORY","INCOMPLETE_HISTORY","PARTIAL_FILL_CANCELED","API_ERROR","EXIT_DEAL_OF_THE_SAME_SIDE","NOTHING_EXECUTED_CANCELED"};
int P_API[]={1,1,1,1,1,0,1,1};
double P_POSVOL[]={0.1,0.1,0.5,0.1,0.4,0.1,0.1,0.5};
int P_ND[]={2,3,1,1,2,0,2,1};
int D_TICKET[]={100,1001,0,0,100,1001,1001,0,100,0,0,0,1001,0,0,0,100,1001,0,0,0,0,0,0,100,1001,0,0,100,0,0,0};
int D_ORDER[]={400,501,0,0,400,501,501,0,400,0,0,0,501,0,0,0,400,501,0,0,0,0,0,0,400,501,0,0,400,0,0,0};
int D_ENTRY[]={0,1,0,0,0,1,1,0,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,0};
int D_TYPE[]={0,1,0,0,0,1,1,0,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
double D_VOL[]={0.5,0.4,0.0,0.0,0.5,0.4,0.4,0.0,0.5,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.5,0.1,0.0,0.0,0.0,0.0,0.0,0.0,0.5,0.4,0.0,0.0,0.5,0.0,0.0,0.0};
int P_HASORD[]={1,1,1,1,1,0,1,1};
int O_WHERE[]={2,2,1,2,2,0,2,2};
int O_STATE[]={4,4,1,4,2,0,4,2};
double O_VI[]={0.4,0.4,0.4,0.4,0.4,0.0,0.4,0.4};
double O_VC[]={0.0,0.0,0.4,0.0,0.3,0.0,0.0,0.4};
string R_NAME[]={"PENDING_WITH_MAP_FULL_EVIDENCE_IS_DONE_AND_SAVED","NEEDS_RECONCILIATION_WITH_MAP_FULL_EVIDENCE_IS_DONE","DUPLICATE_DEAL_COUNTS_ONCE","DONE_STORED_AND_CONFIRMED_AGAIN_ADDS_NOTHING","DONE_STORED_BUT_NO_EVIDENCE_IS_NOT_KEPT_AS_PROOF","LATE_FILL_NOT_YET_IN_HISTORY_STAYS_OPEN","INCOMPLETE_HISTORY_STAYS_OPEN","PARTIAL_FILL_GOES_TO_RECONCILIATION_AND_IS_SAVED","NOTHING_EXECUTED_NEVER_BECOMES_A_NEW_REQUEST","THE_STORED_ORDER_MAP_IS_USED_NOT_A_GUESS","API_ERROR_SNAPSHOT_UNKNOWN_SKIPS_THE_RECONCILIATION","UNSTABLE_READ_SNAPSHOT_UNKNOWN","ADAPTER_BLOCK_SKIPS_THE_RECONCILIATION_AND_THE_SAVE","SAVE_FAILURE_IS_RECOVERY_REQUIRED_AND_NOT_EXPOSED_AS_SAVED","MISSING_FILE_BLOCKS_BEFORE_ANY_READ","DAMAGED_FILE_BLOCKS_BEFORE_ANY_READ","OTHER_IDENTITY_BLOCKS_BEFORE_ANY_READ","MISSING_ORDER_MAP_AFTER_AN_UNCERTAIN_SEND_BLOCKS_BEFORE_THE_SNAPSHOT","STORED_BLOCKED_IS_NOT_READ_OR_WRITTEN","STORED_IDLE_IS_NOTHING_TO_RECONCILE_AND_NEVER_A_REQUEST"};
int R_START[]={1,3,1,4,4,1,1,1,3,9,1,1,1,1,6,7,8,2,5,0};
int R_A[]={0,0,1,0,2,2,3,4,7,0,5,0,6,0,0,0,0,0,0,0};
int R_B[]={0,0,1,0,2,2,3,4,7,0,5,2,6,0,0,0,0,0,0,0};
int R_FAIL[]={0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0};
int X_SNAP[]={1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0};
int X_RECON[]={1,1,1,1,1,1,1,1,1,1,0,0,0,1,0,0,0,0,0,0};
int X_SAVENEED[]={1,1,1,0,1,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0};
int X_SAVED[]={1,1,1,0,1,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0};
int X_GEN[]={5,5,5,4,5,4,4,5,4,4,4,4,4,4,0,0,0,4,4,1};
int X_CONF[]={1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
string X_FINAL[]={"DONE","DONE","DONE","DONE","STILL_OPEN","STILL_OPEN","STILL_OPEN","STILL_OPEN","STILL_OPEN","STILL_OPEN","STILL_OPEN","STILL_OPEN","BLOCKED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","BLOCKED","NOTHING_TO_RECONCILE"};
string X_DISK[]={"DONE","DONE","DONE","DONE","NEEDS_RECONCILIATION","REQUEST_PENDING","REQUEST_PENDING","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","","","REQUEST_PENDING","REQUEST_PENDING","BLOCKED","IDLE"};
string X_DECISION[]={"CONFIRMED","CONFIRMED","CONFIRMED","CONFIRMED","UNKNOWN","UNKNOWN","UNKNOWN","PARTIAL","NOT_EXECUTED","UNKNOWN","","","","CONFIRMED","","","","","",""};
string X_ADAPTER[]={"READY","READY","READY","READY","READY","READY","READY","READY","READY","READY","UNKNOWN","UNKNOWN","BLOCK","READY","","","","","",""};
string X_REASON[]={"","","","","","","","","","","SNAPSHOT_UNKNOWN","SNAPSHOT_UNKNOWN: READ_UNSTABLE","SNAPSHOT_BLOCK","SAVE_FAILED","LOAD_UNUSABLE: MISSING","LOAD_UNUSABLE: CRC_MISMATCH","LOAD_UNUSABLE: IDENTITY_MISMATCH","NO_MAP","",""};
// END GENERATED FIXTURES
#define FN "VELO_T011_FLOW_SELFTEST_A.state"
#define POS 7
#define K_IDLE 0
#define K_PEND_MAP 1
#define K_PEND_INTENT 2
#define K_NR_MAP 3
#define K_DONE_MAP 4
#define K_BLOCKED_MAP 5
#define K_MISSING 6
#define K_CORRUPT 7
#define K_OTHER_IDENT 8
#define K_PEND_MAP_777 9
SEsIdentity Ident(const ulong position)
  {
   SEsIdentity i;
   i.server="MetaQuotes-Demo";
   i.login=5001234;
   i.symbol="XAUUSD";
   i.position_id=position;
   return(i);
  }
void Clean(void)
  {
   if(FileIsExist(FN)) FileDelete(FN);
   if(FileIsExist(FN+ESF_TMP_SUFFIX)) FileDelete(FN+ESF_TMP_SUFFIX);
  }
// an empty expectation means "no condition on the text"
bool ReasonOk(const string expected,const string reason)
  {
   if(expected=="") return(true);
   return(StringFind(reason,expected)>=0);
  }
bool Quote(SEaState &s,SEaResult &r,const double bid)
  {
   return(EA_OnQuote(s,POS,1,2000.0,bid,bid+0.3,0.5,0.5,0.01,0.01,100.0,r));
  }
void StateBelow(SEaState &s)
  {
   EA_StateInit(s);
   SEaResult r;
   Quote(s,r,1999.0);
  }
void StatePending(SEaState &s)
  {
   EA_StateInit(s);
   SEaResult r;
   Quote(s,r,2000.0);
  }
void StateOfKind(SEaState &s,const int kind)
  {
   SEaResult r;
   if(kind==K_IDLE) {StateBelow(s); return;}
   StatePending(s);
   if(kind==K_NR_MAP) EA_OnReport(s,"X2R80-7",EA_REP_TIMEOUT,0.0,0.01,r);
   if(kind==K_DONE_MAP) EA_OnReport(s,"X2R80-7",EA_REP_FULL,0.4,0.01,r);
   if(kind==K_BLOCKED_MAP) EA_OnReport(s,"X2R80-8",EA_REP_FULL,0.4,0.01,r);
  }
// writes the stored record of `kind` with ESF_WriteAll (arbitrary generation allowed); K_MISSING writes nothing
void Prepare(const int kind)
  {
   Clean();
   if(kind==K_MISSING) return;
   SEsRecord rec;
   ESC_RecordInit(rec);
   rec.id=Ident(POS);
   int sk=(kind==K_OTHER_IDENT || kind==K_CORRUPT || kind==K_PEND_MAP_777 ? K_PEND_MAP : kind);
   StateOfKind(rec.state,sk);
   rec.generation=(sk==K_IDLE ? 1 : 4);
   if(sk==K_PEND_INTENT)
      rec.send_phase=ESC_SEND_INTENT;
   else
      if(sk!=K_IDLE)
        {
         rec.send_phase=ESC_SEND_MAPPED;
         rec.map_complete=true;
         rec.n_orders=1;
         rec.orders[0]=(kind==K_PEND_MAP_777 ? 777 : 501);
        }
   string text,why;
   if(!ESC_Encode(rec,text,why)) {Print("FAIL fixture record not encodable: ",why); g_fail++; return;}
   if(kind==K_CORRUPT) StringReplace(text,"LEVEL=2000","LEVEL=2001");
   ESF_WriteAll(FN,text);
  }
void BuildRaw(SXaRaw &r,const int p)
  {
   XA_RawInit(r);
   r.api_ok=(P_API[p]==1);
   r.api_error="terminal error";
   r.symbol_ok=true;
   r.vol_step=0.01;
   r.vol_min=0.01;
   r.vol_max=100.0;
   r.margin_ok=true;
   r.margin_mode=XA_MARGIN_HEDGING;
   r.n_pos=1;
   r.pos_ticket=9;
   r.pos_type=XA_POS_BUY;
   r.pos_volume=P_POSVOL[p];
   r.pos_symbol="XAUUSD";
   r.hist_ok=true;
   r.deals_truncated=false;
   r.n_deals=P_ND[p];
   for(int k=0;k<P_ND[p];k++)
     {
      r.deal[k].ticket=(ulong)D_TICKET[p*MAXD+k];
      r.deal[k].order=(ulong)D_ORDER[p*MAXD+k];
      r.deal[k].position_id=POS;
      r.deal[k].entry=D_ENTRY[p*MAXD+k];
      r.deal[k].type=D_TYPE[p*MAXD+k];
      r.deal[k].volume=D_VOL[p*MAXD+k];
     }
   r.n_orders=P_HASORD[p];
   for(int k=0;k<P_HASORD[p];k++)
     {
      r.ord[k].ticket=501;
      r.ord[k].where=O_WHERE[p+k];
      r.ord[k].state=O_STATE[p+k];
      r.ord[k].vol_initial=O_VI[p+k];
      r.ord[k].vol_current=O_VC[p+k];
      r.ord[k].position_id=POS;
     }
  }
void Input(SErfInput &in,const int a,const int b,const bool fail)
  {
   ERF_InputInit(in);
   BuildRaw(in.raw_a,a);
   BuildRaw(in.raw_b,b);
   in.test_fail_save=fail;
  }
string DiskStatus(int &generation,int &confirmations)
  {
   generation=0;
   confirmations=0;
   string text,why;
   SEsRecord rec;
   if(!FileIsExist(FN) || !ESF_ReadAll(FN,text)) return("");
   if(!ESC_Decode(text,rec,why)) return("CORRUPT");
   generation=rec.generation;
   confirmations=rec.state.confirmations;
   return(EA_StateName(rec.state.status));
  }
void RunRows(void)
  {
   for(int i=0;i<NROWS;i++)
     {
      string tag=R_NAME[i]+": ";
      Prepare(R_START[i]);
      SErfInput in;
      if(R_A[i]>=0) Input(in,R_A[i],R_B[i],R_FAIL[i]==1);
      else ERF_InputInit(in);
      SEsIdentity id=Ident(R_START[i]==K_OTHER_IDENT ? POS+1 : POS);
      SErfResult res;
      ERF_Run(FN,id,in,res);
      Print(tag,ERF_Text(res));
      Check(ERF_FinalName(res.final_state)==X_FINAL[i],tag+"final "+ERF_FinalName(res.final_state));
      Check((int)res.snapshot_called==X_SNAP[i],tag+"snapshot_called "+(string)res.snapshot_called);
      Check((int)res.reconcile_called==X_RECON[i],tag+"reconcile_called "+(string)res.reconcile_called);
      Check((int)res.save_needed==X_SAVENEED[i],tag+"save_needed "+(string)res.save_needed);
      Check((int)res.saved==X_SAVED[i],tag+"saved "+(string)res.saved);
      Check(res.decision==X_DECISION[i],tag+"decision '"+res.decision+"'");
      Check(res.adapter_verdict==X_ADAPTER[i],tag+"adapter verdict '"+res.adapter_verdict+"'");
      Check(ReasonOk(X_REASON[i],res.reason),tag+"reason contains '"+X_REASON[i]+"' got '"+res.reason+"'");
      if(X_GEN[i]>0) Check(res.generation==X_GEN[i],tag+"generation on disk "+IntegerToString(res.generation));
      if(X_CONF[i]>0) Check(res.state.confirmations==X_CONF[i],tag+"confirmations "+IntegerToString(res.state.confirmations));
      int g,c;
      string disk=DiskStatus(g,c);
      if(X_DISK[i]!="") Check(disk==X_DISK[i],tag+"status on disk '"+disk+"'");
      if(X_SAVENEED[i]==1 && X_SAVED[i]==0) Check(EA_StateName(res.state.status)==disk,tag+"a failed save exposes the state that IS on disk, not the unsaved one");
      Check(!res.request_produced,tag+"no request is produced");
      Check(!FileIsExist(FN+ESF_TMP_SUFFIX),tag+"no temporary file is left");
      if(res.final_state==ERF_RECOVERY_REQUIRED || res.final_state==ERF_STILL_OPEN)
        {
         SEaResult q;
         Check(!Quote(res.state,q,2005.0),tag+"a quote after the flow produces no request ("+EA_EventName(q.event)+")");
        }
     }
  }
void TestLateFillSequence(void)
  {
   Prepare(K_PEND_MAP);
   SEsIdentity id=Ident(POS);
   SErfInput in;
   SErfResult res;
   Input(in,2,2,false);                     // NOT_YET_IN_HISTORY
   ERF_Run(FN,id,in,res);
   Check(res.final_state==ERF_STILL_OPEN && !res.saved && res.generation==4 && res.state.status==EA_ST_REQUEST_PENDING,"late fill, run 1: still open, nothing saved");
   Input(in,0,0,false);                     // FULL appears in the history
   ERF_Run(FN,id,in,res);
   Check(res.final_state==ERF_DONE && res.saved && res.generation==5 && res.state.confirmations==1,"late fill, run 2: DONE, saved with generation 5, one confirmation");
   ERF_Run(FN,id,in,res);
   Check(res.final_state==ERF_DONE && !res.saved && res.generation==5 && res.state.confirmations==1,"late fill, run 3: DONE again, nothing saved, confirmations still 1");
   SEaResult q;
   Check(!EA_OnQuote(res.state,POS,1,2000.0,2005.0,2005.3,0.5,0.1,0.01,0.01,100.0,q) && q.event==EA_EV_IGNORED,"DONE: a later quote produces no request");
   Clean();
  }
void TestSaveFailureThenRetryOfTheFlow(void)
  {
   Prepare(K_PEND_MAP);
   SEsIdentity id=Ident(POS);
   SErfInput in;
   SErfResult res;
   Input(in,0,0,true);
   ERF_Run(FN,id,in,res);
   int g,c;
   string disk=DiskStatus(g,c);
   Check(res.final_state==ERF_RECOVERY_REQUIRED && !res.saved && res.state.status==EA_ST_REQUEST_PENDING && res.generation==4 && disk=="REQUEST_PENDING" && g==4,"save failure: RECOVERY_REQUIRED, the returned state is the one on disk, nothing exposed as saved");
   Input(in,0,0,false);
   ERF_Run(FN,id,in,res);
   Check(res.final_state==ERF_DONE && res.saved && res.generation==5 && res.state.confirmations==1,"the same flow run again (no retry inside the flow) reaches DONE once, confirmations 1");
   Clean();
  }
void OnStart()
  {
   Print("T011 FLOW TEST: sandbox file VELO_T011_FLOW_SELFTEST_A.state only; fixtures for the terminal data; no order, no new trade.");
   RunRows();
   TestLateFillSequence();
   TestSaveFailureThenRetryOfTheFlow();
   Clean();
   Check(!FileIsExist(FN) && !FileIsExist(FN+ESF_TMP_SUFFIX),"the test leaves no file behind");
   PrintFormat("T011 FLOW TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
