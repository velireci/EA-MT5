// T011 demo harness test (FAKE transport only): DM_Run over DemoHarness.mqh, ExitExecutor, the real ExitStateFile (sandbox file VELO_T011_DEMOTEST_A.state, deleted before and after)
// and the instance lock (terminal temporary global variable VELO_T011_LOCKTEST_A, removed at the end; it is the test's own variable). Mirrors tests/test_t011_demo.py.
// NEVER includes the real transport; no terminal read of positions, no order, no trade. NOT YET COMPILED OR RUN (UNVERIFIED): this run also verifies the lock semantics of the terminal.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/DemoHarness.mqh"
#include "../include/ExitTransportFake.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
#define FN "VELO_T011_DEMOTEST_A.state"
#define KEY "VELO_T011_LOCKTEST_A"
void Clean(void)
  {
   if(FileIsExist(FN)) FileDelete(FN);
   if(FileIsExist(FN+ESF_TMP_SUFFIX)) FileDelete(FN+ESF_TMP_SUFFIX);
  }
void Params(SDmParams &p,const ENUM_DM_STEP step)
  {
   DM_ParamsInit(p);
   p.step=step;
   p.magic=777;
   p.position_id=7;
   p.symbol="XAUUSD";
   p.direction=DM_DIR_BUY;
   p.level_2r=2000.0;
   p.tp_price=2010.0;
   p.volume_initial=0.5;
   p.filling=EX_FILL_IOC;
   p.deviation=20;
   p.filter_policy=EX_POL_IGNORE;
   p.filter_state=EX_FS_CLEAR;
   p.file_name=FN;
   p.lock_key=KEY;
  }
void BuildRaw(SXaRaw &r,const bool filled)
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
   r.deal[0].position_id=7;
   r.deal[0].entry=XA_ENTRY_IN;
   r.deal[0].type=XA_DEAL_BUY;
   r.deal[0].volume=0.5;
   r.n_deals=1;
   r.n_orders=1;
   r.ord[0].ticket=501;
   r.ord[0].position_id=7;
   if(filled)
     {
      r.pos_volume=0.1;
      r.deal[1].ticket=1001;
      r.deal[1].order=501;
      r.deal[1].position_id=7;
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
void Fill(CFakeTransport &t)
  {
   t.response.returned_true=true;
   t.response.have_result=true;
   t.response.retcode=10009;
   t.response.order=501;
   t.response.deal=1001;
   t.response.volume=0.4;
   t.response.price=2000.0;
  }
bool Step(const ENUM_DM_STEP step,CFakeTransport &t,const SDmQuote &quote,const SXaRaw &ra,const SXaRaw &rb,SDmResult &res,const bool confirm=false,const string auth="")
  {
   SDmParams p;
   Params(p,step);
   p.confirm_send_once=confirm;
   p.authorisation=auth;
   return(DM_Run(p,GetPointer(t),quote,ra,rb,res));
  }
bool LockFree(void)
  {
   bool held=false;
   string why;
   bool got=EL_Acquire(KEY,held,why);
   EL_Release(KEY,held);
   return(got);
  }
void TestLock(void)
  {
   bool h1=false,h2=false;
   string why;
   Check(EL_Acquire(KEY,h1,why) && h1,"the lock is acquired by the first caller");
   Check(!EL_Acquire(KEY,h2,why) && !h2 && StringFind(why,"INSTANCE_LOCK_HELD")>=0,"a second caller in the same terminal does not get it");
   EL_Release(KEY,h2);
   Check(!EL_Acquire(KEY,h2,why),"a caller that does not hold the lock cannot release it (still held)");
   EL_Release(KEY,h1);
   Check(EL_Acquire(KEY,h2,why) && h2,"after the release the lock can be acquired again");
   EL_Release(KEY,h2);
   Check(EL_Key(5001234,7)=="VELO_T011_LOCK_5001234_7","the lock key is per account and position");
  }
void TestPipeline(void)
  {
   Clean();
   CFakeTransport t;
   Fill(t);
   SDmQuote q;
   q.read_ok=true;
   q.bid=2000.0;
   q.ask=2000.3;
   SXaRaw nyet,full;
   BuildRaw(nyet,false);
   BuildRaw(full,true);
   SDmResult r;
   // disabled by default
   SDmParams d;
   DM_ParamsInit(d);
   Check(!DM_Run(d,GetPointer(t),q,full,full,r) && r.status=="DISABLED" && t.sends==0 && !FileIsExist(FN),"step NONE: disabled, nothing happens");
   // unset parameters block
   SDmParams u;
   Params(u,DM_STEP_REGISTER);
   u.magic=0;
   Check(!DM_Run(u,GetPointer(t),q,full,full,r) && !FileIsExist(FN) && t.sends==0,"REGISTER with an unset magic is refused");
   Params(u,DM_STEP_ACTIVATE);
   u.confirm_send_once=true;
   u.filling=EX_FILL_UNSET;
   Check(!DM_Run(u,GetPointer(t),q,full,full,r) && t.sends==0,"ACTIVATE with an unset filling is refused");
   // status is read-only
   Check(Step(DM_STEP_STATUS,t,q,full,full,r) && r.status=="STATUS" && !FileIsExist(FN) && StringFind(r.detail,"MISSING")>=0,"STATUS is read-only: no file appears, a missing file is reported");
   Check(!Step(DM_STEP_ACTIVATE,t,q,full,full,r,true) && r.status=="RECOVERY_REQUIRED" && t.sends==0,"without a registration the executor never starts from scratch");
   Check(Step(DM_STEP_REGISTER,t,q,full,full,r) && r.status=="REGISTERED" && FileIsExist(FN) && t.sends==0,"REGISTER stores the authorised plan, no send");
   Check(!Step(DM_STEP_ACTIVATE,t,q,full,full,r,false) && r.status=="BLOCKED" && t.sends==0,"ACTIVATE without confirm_send_once is refused");
   SDmQuote noq;
   noq.read_ok=false;
   noq.bid=0.0;
   noq.ask=0.0;
   Check(!Step(DM_STEP_ACTIVATE,t,noq,full,full,r,true) && r.status=="BLOCKED" && t.sends==0,"ACTIVATE without a quote is refused");
   SDmQuote below;
   below.read_ok=true;
   below.bid=1999.0;
   below.ask=1999.3;
   Step(DM_STEP_ACTIVATE,t,below,full,full,r,true);
   Check(r.status=="NO_REQUEST" && t.sends==0,"the level is not reached: no request");
   Check(Step(DM_STEP_ACTIVATE,t,q,full,full,r,true) && r.status=="SENT_MAPPED" && r.sends==1 && t.sends==1,"ACTIVATE at the level: INTENT, ONE send, map");
   for(int k=0;k<3;k++)
     {
      Step(DM_STEP_ACTIVATE,t,q,full,full,r,true);
      Check(r.status=="NOT_IDLE" && t.sends==1,"re-run "+IntegerToString(k+1)+": no second request");
     }
   Check(!Step(DM_STEP_RECONCILE,t,q,nyet,nyet,r) && r.status=="STILL_OPEN","RECONCILE without the fill in the history: STILL_OPEN");
   Check(Step(DM_STEP_RECONCILE,t,q,full,full,r) && r.status=="DONE","RECONCILE with complete evidence: DONE");
   Check(Step(DM_STEP_RECONCILE,t,q,full,full,r) && r.status=="DONE","RECONCILE again: DONE, unchanged");
   Step(DM_STEP_STATUS,t,q,full,full,r);
   Check(StringFind(r.detail,"state DONE")>=0 && StringFind(r.detail,"confirmations 1")>=0 && StringFind(r.detail,"plan_set 1")>=0 && t.sends==1,"STATUS after the whole sequence: DONE, one confirmation, plan stored, one send");
   Check(LockFree(),"every acting step released the lock");
   Clean();
  }
void TestRealGatesAndLock(void)
  {
   Clean();
   CFakeTransport t;
   Fill(t);
   SDmQuote q;
   q.read_ok=true;
   q.bid=2000.0;
   q.ask=2000.3;
   SXaRaw full;
   BuildRaw(full,true);
   SDmResult r;
   t.real=true;
   Check(!Step(DM_STEP_REGISTER,t,q,full,full,r) && StringFind(r.detail,"REAL_NOT_AUTHORISED")>=0 && !FileIsExist(FN),"a real transport without the phrase: refused");
   t.account.demo=false;
   Check(!Step(DM_STEP_REGISTER,t,q,full,full,r,false,EX_AUTH_PHRASE) && StringFind(r.detail,"REAL_REQUIRES_DEMO_ACCOUNT")>=0,"a real transport on a non-demo account: refused");
   t.account.demo=true;
   Check(Step(DM_STEP_REGISTER,t,q,full,full,r,false,EX_AUTH_PHRASE),"the phrase and a demo account: REGISTER passes");
   Check(!Step(DM_STEP_ACTIVATE,t,q,full,full,r,false,EX_AUTH_PHRASE) && t.sends==0,"the phrase without confirm_send_once: no send");
   Check(Step(DM_STEP_ACTIVATE,t,q,full,full,r,true,EX_AUTH_PHRASE) && t.sends==1,"phrase + demo + confirm_send_once: one send");
   Clean();
   // a manual position is never adopted
   CFakeTransport m;
   Fill(m);
   m.position.magic=0;
   Check(!Step(DM_STEP_REGISTER,m,q,full,full,r) && StringFind(r.detail,"OWNERSHIP_NOT_PROVEN")>=0 && !FileIsExist(FN),"a manual position (magic 0) is never adopted");
   // a second instance
   CFakeTransport t2;
   Fill(t2);
   bool held=false;
   string why;
   Check(EL_Acquire(KEY,held,why),"another instance takes the lock");
   Check(!Step(DM_STEP_REGISTER,t2,q,full,full,r) && StringFind(r.detail,"INSTANCE_LOCK_HELD")>=0 && !FileIsExist(FN) && t2.sends==0,"a second instance: REGISTER refused, nothing written");
   Check(!Step(DM_STEP_ACTIVATE,t2,q,full,full,r,true) && StringFind(r.detail,"INSTANCE_LOCK_HELD")>=0 && t2.sends==0,"a second instance: ACTIVATE refused, no send");
   Check(Step(DM_STEP_STATUS,t2,q,full,full,r),"STATUS is read-only and needs no lock");
   EL_Release(KEY,held);
   Check(Step(DM_STEP_REGISTER,t2,q,full,full,r),"after the other instance released the lock, REGISTER passes");
   Check(r.status=="REGISTERED" && FileIsExist(FN),"and registers");
   Clean();
  }
void OnStart()
  {
   Print("T011 DEMO HARNESS TEST: fake transport only; sandbox file VELO_T011_DEMOTEST_A.state; test lock variable VELO_T011_LOCKTEST_A; no order, no position read, no trade.");
   Clean();
   TestLock();
   TestPipeline();
   TestRealGatesAndLock();
   Clean();
   GlobalVariableDel(KEY);
   Check(!FileIsExist(FN) && !FileIsExist(FN+ESF_TMP_SUFFIX),"the test leaves no file behind");
   PrintFormat("T011 DEMO HARNESS TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
