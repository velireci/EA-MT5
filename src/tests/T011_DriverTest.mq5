// T011 tick-driver test (FAKE transport only; Part 14): ETD_Init / ETD_Tick / ETD_Timer / ETD_Register over ExitTickDriver.mqh with CFakeTransport, the real ExitStateFile (sandbox file
// VELO_T011_DRIVERTEST_A.state, deleted before and after) and the REAL instance lock (the driver's own key VELO_T011_LOCK_5001234_7, removed at the end by this test). Mirrors
// tests/test_t011_driver.py. NEVER includes the real transport; no terminal read of positions, no order, no trade. NOT YET COMPILED OR RUN (UNVERIFIED): this run also verifies
// the lock semantics of the terminal for init / tick / timer / registration.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/ExitTickDriver.mqh"
#include "../include/ExitTransportFake.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
#define FN "VELO_T011_DRIVERTEST_A.state"
#define KEY "VELO_T011_LOCK_5001234_7"
#define S_MISSING 0
#define S_GEOM 1
#define S_TYPED 2
#define S_PEND_MAP 3
#define S_INTENT 4
SEsIdentity Ident()
  {
   SEsIdentity i;
   i.server="MetaQuotes-Demo";
   i.login=5001234;
   i.symbol="XAUUSD";
   i.position_id=7;
   return(i);
  }
void Clean(void)
  {
   if(FileIsExist(FN)) FileDelete(FN);
   if(FileIsExist(FN+ESF_TMP_SUFFIX)) FileDelete(FN+ESF_TMP_SUFFIX);
  }
bool LockFree(void)
  {
   bool held=false;
   string why;
   bool got=EL_Acquire(KEY,held,why);
   EL_Release(KEY,held);
   return(got);
  }
// raw terminal data (as in the adapter fixtures): 0 = the exit is not in the history yet, 1 = filled and the position open with 0.1, 2 = filled and the remainder closed by hand
void BuildRaw(SXaRaw &r,const int kind)
  {
   XA_RawInit(r);
   r.api_ok=true;
   r.symbol_ok=true;
   r.vol_step=0.01;
   r.vol_min=0.01;
   r.vol_max=100.0;
   r.margin_ok=true;
   r.margin_mode=XA_MARGIN_HEDGING;
   r.n_pos=(kind==2 ? 0 : 1);
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
   if(kind==0)
     {
      r.pos_volume=0.5;
      r.ord[0].where=XA_WHERE_ACTIVE;
      r.ord[0].state=XA_ORD_PLACED;
      r.ord[0].vol_initial=0.4;
      r.ord[0].vol_current=0.4;
      return;
     }
   r.pos_volume=(kind==2 ? 0.0 : 0.1);
   r.deal[1].ticket=1001;
   r.deal[1].order=501;
   r.deal[1].position_id=7;
   r.deal[1].entry=XA_ENTRY_OUT;
   r.deal[1].type=XA_DEAL_SELL;
   r.deal[1].volume=0.4;
   r.n_deals=2;
   if(kind==2)
     {
      r.deal[2].ticket=1005;
      r.deal[2].order=900;
      r.deal[2].position_id=7;
      r.deal[2].entry=XA_ENTRY_OUT;
      r.deal[2].type=XA_DEAL_SELL;
      r.deal[2].volume=0.1;
      r.n_deals=3;
     }
   r.ord[0].where=XA_WHERE_HISTORY;
   r.ord[0].state=XA_ORD_FILLED;
   r.ord[0].vol_initial=0.4;
   r.ord[0].vol_current=0.0;
  }
// the stored record: BUY, E 2000.0, S 1995.0, level 2010.0, TP 2015.0 (R_GEOM) / typed / pending with a map / intent without a map
void Prepare(const int start)
  {
   Clean();
   if(start==S_MISSING) return;
   SEsRecord rec;
   ESC_RecordInit(rec);
   rec.id=Ident();
   rec.generation=1;
   EA_StateInit(rec.state);
   rec.state.bound=true;
   rec.state.position_id=7;
   rec.state.direction=1;
   rec.state.level=2010.0;
   rec.state.volume_initial=0.5;
   rec.plan_set=true;
   rec.plan_tp=2015.0;
   rec.plan_vol_min=0.01;
   rec.plan_vol_step=0.01;
   rec.plan_vol_max=100.0;
   rec.plan_rpol=(start==S_TYPED ? ESC_RPOL_TYPED : ESC_RPOL_R_GEOM);
   if(start!=S_TYPED)
     {
      rec.plan_e_src=2000.0;
      rec.plan_s_src=1995.0;
      rec.plan_e_out=2000.0;
      rec.plan_s_out=1995.0;
     }
   if(start==S_PEND_MAP || start==S_INTENT)
     {
      SEaResult r;
      EA_OnQuote(rec.state,7,1,2010.0,2010.0,2010.3,0.5,0.5,0.01,0.01,100.0,r);
      rec.generation=(start==S_INTENT ? 2 : 3);
      rec.send_phase=(start==S_INTENT ? ESC_SEND_INTENT : ESC_SEND_MAPPED);
      if(start==S_PEND_MAP)
        {
         rec.map_complete=true;
         rec.n_orders=1;
         rec.orders[0]=501;
        }
     }
   string text,why;
   if(!ESC_Encode(rec,text,why)) {Print("FAIL fixture record not encodable: ",why); g_fail++; return;}
   ESF_WriteAll(FN,text);
  }
string DiskStatus(int &generation)
  {
   generation=0;
   string text,why;
   SEsRecord rec;
   if(!FileIsExist(FN) || !ESF_ReadAll(FN,text)) return("MISSING");
   if(!ESC_Decode(text,rec,why)) return("CORRUPT");
   generation=rec.generation;
   return(EA_StateName(rec.state.status));
  }
void World(SExConfig &cfg,CFakeTransport &t,SExQuote &q)
  {
   EX_ConfigInit(cfg);
   cfg.enabled=true;
   cfg.r_policy=EX_RPOL_R_GEOM;
   cfg.sl_initial_set=true;
   cfg.sl_initial=1995.0;
   cfg.ea_magic=777;
   cfg.filling=EX_FILL_IOC;
   cfg.deviation=20;
   cfg.filter_policy=EX_POL_IGNORE;
   cfg.filter_state=EX_FS_CLEAR;
   cfg.tp_set=true;
   cfg.tp_price=2015.0;
   t.response.returned_true=true;
   t.response.have_result=true;
   t.response.retcode=10009;
   t.response.order=501;
   t.response.deal=1001;
   t.response.volume=0.4;
   t.response.price=2000.0;
   t.position.type=0;
   t.position.price_open=2000.0;
   t.position.sl=1995.0;
   t.position.volume=0.5;
   q.direction=1;
   q.level_2r=0.0;
   q.bid=2010.0;
   q.ask=2010.3;
   q.volume_initial=0.5;
  }
bool Has(const string text,const string part) {return(StringFind(text,part)>=0);}

void TestInit(void)
  {
   SExConfig cfg;
   CFakeTransport t;
   SExQuote q;
   SEtdState s;
   SErfResult flow;
   SXaRaw nyet;
   BuildRaw(nyet,0);
   World(cfg,t,q);
   Prepare(S_GEOM);
   int g;
   bool armed=ETD_Init(cfg,GetPointer(t),FN,Ident(),nyet,nyet,s,flow);
   Check(armed && s.armed && s.level==2010.0 && s.direction==1 && t.sends==0 && DiskStatus(g)=="IDLE" && g==1 && LockFree(),"init arms an IDLE R_GEOM record, reads nothing else and releases the lock");
   Prepare(S_MISSING);
   armed=ETD_Init(cfg,GetPointer(t),FN,Ident(),nyet,nyet,s,flow);
   SExRuntime rt;
   EX_RuntimeInit(rt);
   SExResult res;
   ETD_Tick(cfg,GetPointer(t),rt,FN,Ident(),q,s,res);
   Check(!armed && Has(s.reason,"INIT_LOAD_UNUSABLE") && !FileIsExist(FN) && t.sends==0 && res.final_state==EX_BLOCKED && s.process_calls==0,"init with a missing file arms nothing, creates nothing, a tick is blocked");
   Prepare(S_TYPED);
   armed=ETD_Init(cfg,GetPointer(t),FN,Ident(),nyet,nyet,s,flow);
   Check(!armed && Has(s.reason,"INIT_PLAN_NOT_R_GEOM"),"a typed diagnostic record never arms the tick path");
   Prepare(S_GEOM);
   cfg.enabled=false;
   armed=ETD_Init(cfg,GetPointer(t),FN,Ident(),nyet,nyet,s,flow);
   Check(!armed && Has(s.reason,"INIT_DISABLED") && LockFree(),"disabled by default: nothing is armed");
   cfg.enabled=true;
   bool h=false;
   string why;
   EL_Acquire(KEY,h,why);
   armed=ETD_Init(cfg,GetPointer(t),FN,Ident(),nyet,nyet,s,flow);
   EL_Release(KEY,h);
   Check(!armed && s.lock_failures==1 && Has(s.reason,"INIT_LOCK_FAILED") && LockFree(),"a lock failure at init arms nothing");
  }
void TestRecovery(void)
  {
   SExConfig cfg;
   CFakeTransport t;
   SExQuote q;
   SEtdState s;
   SErfResult flow;
   SXaRaw nyet,full,closed;
   BuildRaw(nyet,0);
   BuildRaw(full,1);
   BuildRaw(closed,2);
   World(cfg,t,q);
   Prepare(S_PEND_MAP);
   bool armed=ETD_Init(cfg,GetPointer(t),FN,Ident(),full,full,s,flow);
   int g;
   Check(!armed && flow.final_state==ERF_DONE && DiskStatus(g)=="DONE" && !s.reconcile_due,"recovery BEFORE activation: a pending record with a full fill is reconciled to DONE and never arms");
   SExRuntime rt;
   EX_RuntimeInit(rt);
   SExResult res;
   ETD_Tick(cfg,GetPointer(t),rt,FN,Ident(),q,s,res);
   Check(t.sends==0 && s.process_calls==0,"after that recovery a tick at the level sends nothing and never reaches the executor");
   armed=ETD_Init(cfg,GetPointer(t),FN,Ident(),closed,closed,s,flow);
   Check(!armed && flow.final_state==ERF_DONE && StringFind(flow.decision,"CONFIRMED")>=0 && !flow.save_needed,"a finished position after DONE: ALREADY_DONE, nothing saved");
   Prepare(S_PEND_MAP);
   armed=ETD_Init(cfg,GetPointer(t),FN,Ident(),nyet,nyet,s,flow);
   Check(!armed && flow.final_state==ERF_STILL_OPEN && s.reconcile_due,"a pending record without history evidence stays open and is left to the timer");
   Prepare(S_INTENT);
   armed=ETD_Init(cfg,GetPointer(t),FN,Ident(),full,full,s,flow);
   Check(!armed && flow.final_state==ERF_RECOVERY_REQUIRED && !s.reconcile_due && t.sends==0,"an uncertain-send record (intent without a map) is reported, never armed, nothing is sent");
   Check(LockFree(),"recovery paths release the lock");
  }
void TestTick(void)
  {
   SExConfig cfg;
   CFakeTransport t;
   SExQuote q;
   SEtdState s;
   SErfResult flow;
   SXaRaw nyet;
   BuildRaw(nyet,0);
   World(cfg,t,q);
   Prepare(S_GEOM);
   ETD_Init(cfg,GetPointer(t),FN,Ident(),nyet,nyet,s,flow);
   SExRuntime rt;
   EX_RuntimeInit(rt);
   SExResult res;
   bool h=false;
   string why;
   EL_Acquire(KEY,h,why);                              // held "elsewhere": a tick BELOW the level must not even try the lock
   q.bid=2009.99;
   bool sent=ETD_Tick(cfg,GetPointer(t),rt,FN,Ident(),q,s,res);
   Check(!sent && res.final_state==EX_NO_REQUEST && s.process_calls==0 && s.lock_failures==0,"below the level: no lock, no file, no executor call");
   q.bid=2009.9;
   q.ask=2010.1;
   sent=ETD_Tick(cfg,GetPointer(t),rt,FN,Ident(),q,s,res);
   Check(!sent && res.final_state==EX_NO_REQUEST && s.process_calls==0,"a BUY needs the BID at the level; the ask alone is not enough");
   q.bid=2010.0;
   q.ask=2010.3;
   sent=ETD_Tick(cfg,GetPointer(t),rt,FN,Ident(),q,s,res);
   Check(!sent && s.lock_failures==1 && t.sends==0 && s.armed && Has(res.reason,"TICK_LOCK_FAILED"),"at the level with the lock held elsewhere: zero sends, still armed");
   EL_Release(KEY,h);
   sent=ETD_Tick(cfg,GetPointer(t),rt,FN,Ident(),q,s,res);
   int g;
   Check(sent && t.sends==1 && s.armed==false && s.reconcile_due && DiskStatus(g)=="REQUEST_PENDING" && g==3 && LockFree(),"at the level: exactly one send, mapped, disarmed, reconcile due, lock released");
   for(int i=0;i<3;i++)
      ETD_Tick(cfg,GetPointer(t),rt,FN,Ident(),q,s,res);
   Check(t.sends==1 && s.process_calls==1,"more ticks above the level send nothing and do not reach the executor");
  }
void TestBreakEvenAndChangedRecord(void)
  {
   SExConfig cfg;
   CFakeTransport t;
   SExQuote q;
   SEtdState s;
   SErfResult flow;
   SXaRaw nyet;
   BuildRaw(nyet,0);
   // BUY with the live SL moved to break-even after arming: the level and the request price do not change
   World(cfg,t,q);
   Prepare(S_GEOM);
   ETD_Init(cfg,GetPointer(t),FN,Ident(),nyet,nyet,s,flow);
   t.position.sl=2000.0;
   SExRuntime rt;
   EX_RuntimeInit(rt);
   SExResult res;
   q.bid=2009.0;
   q.ask=2009.3;
   bool a=ETD_Tick(cfg,GetPointer(t),rt,FN,Ident(),q,s,res);
   q.bid=2010.0;
   q.ask=2010.3;
   bool b=ETD_Tick(cfg,GetPointer(t),rt,FN,Ident(),q,s,res);
   Check(!a && b && t.sends==1 && t.last_request.price==2010.0,"a live SL moved to break-even does not change the level");
   // a record that changed under the driver is not given to the executor
   World(cfg,t,q);
   Prepare(S_GEOM);
   ETD_Init(cfg,GetPointer(t),FN,Ident(),nyet,nyet,s,flow);
   Prepare(S_PEND_MAP);
   EX_RuntimeInit(rt);
   CFakeTransport t2;
   World(cfg,t2,q);
   bool c=ETD_Tick(cfg,GetPointer(t2),rt,FN,Ident(),q,s,res);
   Check(!c && !s.armed && s.process_calls==0 && t2.sends==0,"a record that needs reconciliation is not given to EX_Process");
  }
void TestRestartAndTimer(void)
  {
   SExConfig cfg;
   CFakeTransport t;
   SExQuote q;
   SEtdState s;
   SErfResult flow;
   SXaRaw nyet,full;
   BuildRaw(nyet,0);
   BuildRaw(full,1);
   World(cfg,t,q);
   Prepare(S_GEOM);
   ETD_Init(cfg,GetPointer(t),FN,Ident(),nyet,nyet,s,flow);
   SExRuntime rt;
   EX_RuntimeInit(rt);
   SExResult res;
   ETD_Tick(cfg,GetPointer(t),rt,FN,Ident(),q,s,res);
   // timer: not found yet -> still open and still due; lock held elsewhere -> nothing; full evidence -> DONE
   bool ran=ETD_Timer(GetPointer(t),FN,Ident(),nyet,nyet,s,flow);
   Check(ran && flow.final_state==ERF_STILL_OPEN && s.reconcile_due,"timer: without history evidence the record stays open and due");
   bool h=false;
   string why;
   EL_Acquire(KEY,h,why);
   ran=ETD_Timer(GetPointer(t),FN,Ident(),full,full,s,flow);
   EL_Release(KEY,h);
   Check(!ran && s.reconcile_due && s.lock_failures==1,"timer: a lock failure does nothing");
   ran=ETD_Timer(GetPointer(t),FN,Ident(),full,full,s,flow);
   int g;
   Check(ran && flow.final_state==ERF_DONE && !s.reconcile_due && DiskStatus(g)=="DONE" && t.sends==1 && !flow.request_produced && LockFree(),"timer: full evidence reconciles to DONE under the lock; no request");
   ran=ETD_Timer(GetPointer(t),FN,Ident(),full,full,s,flow);
   Check(!ran,"timer: nothing due, nothing done");
   // restart: a new driver state over the same disk
   SEtdState s2;
   SExRuntime rt2;
   EX_RuntimeInit(rt2);
   bool armed=ETD_Init(cfg,GetPointer(t),FN,Ident(),full,full,s2,flow);
   ETD_Tick(cfg,GetPointer(t),rt2,FN,Ident(),q,s2,res);
   Check(!armed && flow.final_state==ERF_DONE && t.sends==1,"restart after the send: reconciled first, no second request");
  }
void TestRegister(void)
  {
   SExConfig cfg;
   CFakeTransport t;
   SExQuote q;
   World(cfg,t,q);
   Prepare(S_MISSING);
   SExRuntime rt;
   EX_RuntimeInit(rt);
   SExResult res;
   bool h=false;
   string why;
   EL_Acquire(KEY,h,why);
   bool ok=ETD_Register(cfg,GetPointer(t),rt,FN,Ident(),q,res);
   EL_Release(KEY,h);
   Check(!ok && res.final_state==EX_BLOCKED && !FileIsExist(FN),"registration with the lock held elsewhere: blocked, no file");
   ok=ETD_Register(cfg,GetPointer(t),rt,FN,Ident(),q,res);
   int g;
   Check(ok && res.final_state==EX_REGISTERED && DiskStatus(g)=="IDLE" && g==1 && LockFree(),"explicit registration under the lock; the lock is released");
  }
void OnStart()
  {
   Print("T011 DRIVER TEST: fake transport only; sandbox file VELO_T011_DRIVERTEST_A.state; the driver's real lock variable ",KEY," is removed at the end; no order, no position read, no trade.");
   Clean();
   TestInit();
   TestRecovery();
   TestTick();
   TestBreakEvenAndChangedRecord();
   TestRestartAndTimer();
   TestRegister();
   Clean();
   GlobalVariableDel(KEY);
   Check(!FileIsExist(FN) && !FileIsExist(FN+ESF_TMP_SUFFIX),"the test leaves no file behind");
   PrintFormat("T011 DRIVER TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
