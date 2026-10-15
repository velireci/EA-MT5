// T013 entry-executor test (FAKE transport and FAKE store only): validation -> intent -> one attempt -> link proof -> recovery / cancel, BUY_LIMIT and SELL_LIMIT, duplicates and failures.
// Mirrors tests/test_entry_executor.py (the scenario names are pinned equal by a Python test). NEVER includes the real transport; no terminal read, no file, no order, no trade.
// NOT YET COMPILED OR RUN (UNVERIFIED): Codex compiles it, the owner runs it in MT5.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/EntryExecutor.mqh"
#include "../include/EntryTransportFake.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
#define SIG "SIG-1"

class CWorld
  {
public:
   CEnFakeTransport t;
   CEnFakeStore s;
   SEnConfig cfg;
   STpPlan plan;
   SEnPermit pm;
   SEnRuntime rt;
   SEnResult r;
   void MakePlan(STpPlan &p,const int direction,const string signal)
     {
      TP_PlanReset(p,signal,"SET-1",direction);
      p.e_out=(direction==1 ? 1990.0 : 2010.0);
      p.s_out=(direction==1 ? 1985.0 : 2015.0);
      p.tp=2000.0;
      p.volume_out=0.1;
     }
   void MakePermit(const STpPlan &p,SEnPermit &out,const bool allow)
     {
      STpPermit tpm;
      tpm.allow=allow;
      tpm.primary_reason="";
      tpm.reason_count=0;
      tpm.registered=false;
      EN_PermitFrom(p,tpm,t.now,out);
     }
   CWorld(void)
     {
      Init(1);
     }
   void Init(const int direction)
     {
      EN_ConfigInit(cfg);
      cfg.enabled=true;
      cfg.ea_magic=777;
      cfg.symbol="XAUUSD";
      cfg.filling=EN_FILL_RETURN;
      cfg.expiry_mode=EN_EXP_GTC;
      cfg.permit_max_age=60;
      cfg.quote_max_age=30;
      EN_RuntimeInit(rt);
      t.quote.time=t.now;
      MakePlan(plan,direction,SIG);
      MakePermit(plan,pm,true);
     }
   void Place(void) {EN_Place(cfg,GetPointer(t),GetPointer(s),rt,plan,pm,r);}
   void PlaceWith(const STpPlan &p,const SEnPermit &permit,SEnRuntime &runtime) {EN_Place(cfg,GetPointer(t),GetPointer(s),runtime,p,permit,r);}
   void Reconcile(const string signal=SIG) {EN_Reconcile(cfg,GetPointer(t),GetPointer(s),signal,r);}
   string Name(const string signal=SIG) {return(EN_FileName(t.account.login,signal));}
   bool Has(const string signal=SIG) {return(s.Exists(Name(signal)));}
   bool Rec(SEnRecord &rec,const string signal=SIG)
     {
      string why;
      return(EN_Decode(s.Get(Name(signal)),rec,why));
     }
   string State(void)
     {
      SEnRecord rec;
      return(Rec(rec) ? rec.state : "NO_RECORD");
     }
   bool Clean(void) {return(s.n_held==0 && s.lock_calls==s.unlock_calls);}
   int IdxLast(void) {return(t.n_orders-1);}
  };

void Scenario_buy_limit_placed(void)
  {
   CWorld w;
   w.Place();
   SEnRecord rec;
   bool ok=w.Rec(rec);
   Check(w.r.outcome==EN_R_PLACED && w.r.sends==1 && w.t.sends==1 && w.r.state==EN_ST_PLACED,"BUY_LIMIT: placed, one send, state PLACED");
   Check(w.t.last_request.type==EN_TYPE_BUY_LIMIT && w.t.last_request.symbol=="XAUUSD" && w.t.last_request.volume==0.1 && w.t.last_request.price==1990.0 && w.t.last_request.sl==1985.0 &&
         w.t.last_request.tp==2000.0 && w.t.last_request.magic==777 && w.t.last_request.filling==EN_FILL_RETURN && w.t.last_request.expiry_mode==EN_EXP_GTC && w.t.last_request.expiration==0,
         "BUY_LIMIT: the request is exactly the plan");
   Check(w.t.last_request.comment==EN_ReqId(SIG),"BUY_LIMIT: the comment is the request id (never a proof)");
   Check(ok && rec.state==EN_ST_PLACED && rec.attempts==1 && rec.linked==1 && rec.order_ticket==w.r.order_ticket && rec.generation==2,"BUY_LIMIT: the record carries the attempt, the linked ticket and generation 2");
   Check(w.Clean(),"BUY_LIMIT: the lock is released");
   CWorld x;
   x.cfg.expiry_mode=EN_EXP_SECONDS;
   x.cfg.expiry_seconds=3600;
   x.Place();
   Check(x.r.outcome==EN_R_PLACED && x.t.last_request.expiry_mode==EN_EXP_SECONDS && x.t.last_request.expiration==x.t.now+3600,"expiry in seconds: the request carries now + seconds");
  }

void Scenario_sell_limit_placed(void)
  {
   CWorld w;
   w.Init(-1);
   w.Place();
   Check(w.r.outcome==EN_R_PLACED && w.t.sends==1 && w.t.last_request.type==EN_TYPE_SELL_LIMIT && w.t.last_request.price==2010.0 && w.t.last_request.sl==2015.0 && w.t.last_request.tp==2000.0,
         "SELL_LIMIT: placed, one send, exactly the plan");
   Check(w.State()==EN_ST_PLACED && w.Clean(),"SELL_LIMIT: record PLACED, lock released");
  }

void Scenario_unset_inputs_block(void)
  {
   for(int k=0;k<9;k++)
     {
      CWorld w;
      if(k==0) w.cfg.enabled=false;
      if(k==1) w.cfg.ea_magic=0;
      if(k==2) w.cfg.symbol="  ";
      if(k==3) w.cfg.filling=EN_FILL_UNSET;
      if(k==4) w.cfg.expiry_mode=EN_EXP_UNSET;
      if(k==5) {w.cfg.expiry_mode=EN_EXP_SECONDS; w.cfg.expiry_seconds=0;}
      if(k==6) w.cfg.permit_max_age=-1;
      if(k==7) w.cfg.quote_max_age=-1;
      if(k==8) w.cfg.filling=9;
      w.Place();
      Check(w.r.outcome==EN_R_REFUSED && w.r.sends==0 && w.t.sends==0 && !w.Has() && w.s.lock_calls==0,StringFormat("unset input %d: refused, zero sends, no file, no lock",k));
     }
  }

void Scenario_plan_refusals(void)
  {
   for(int k=0;k<7;k++)
     {
      CWorld w;
      STpPlan p=w.plan;
      if(k==0) p.status=TP_GEOMETRY_REFUSED;
      if(k==1) p.stage=TP_STAGE_SIZING;
      if(k==2) p.signal_id="";
      if(k==3) p.direction=0;
      if(k==4) p.s_out=1995.0;
      if(k==5) p.e_out=MathSqrt(-1.0);
      if(k==6) p.volume_out=0.0;
      w.PlaceWith(p,w.pm,w.rt);
      Check(w.r.outcome==EN_R_REFUSED && w.t.sends==0 && !w.Has() && w.s.lock_calls==0,StringFormat("plan refusal %d: zero sends, no file, no lock",k));
     }
   CWorld y;
   y.Init(-1);
   STpPlan q=y.plan;
   q.s_out=2005.0;
   y.PlaceWith(q,y.pm,y.rt);
   Check(y.r.outcome==EN_R_REFUSED && y.t.sends==0,"plan refusal: a SELL with SL below the entry");
  }

void Scenario_permit_binding(void)
  {
   for(int k=0;k<8;k++)
     {
      CWorld w;
      SEnPermit pm;
      EN_PermitInit(pm);
      STpPlan other=w.plan;
      if(k==0) EN_PermitInit(pm);
      if(k==1) w.MakePermit(w.plan,pm,false);
      if(k==2) {other.e_out=1991.0; w.MakePermit(other,pm,true);}
      if(k==3) {other.signal_id="SIG-2"; w.MakePermit(other,pm,true);}
      if(k==4) {pm.present=true; pm.allow=true; pm.digest=""; pm.issued=w.t.now;}
      if(k==5) {w.MakePermit(w.plan,pm,true); pm.issued=w.t.now-61;}
      if(k==6) {w.MakePermit(w.plan,pm,true); pm.issued=w.t.now+1;}
      if(k==7) {w.MakePermit(w.plan,pm,true); pm.issued=0;}
      w.PlaceWith(w.plan,pm,w.rt);
      Check(w.r.outcome==EN_R_REFUSED && w.t.sends==0 && !w.Has() && w.s.lock_calls==0 && StringFind(w.r.reason,"PERMIT")==0,StringFormat("permit case %d: refused before any I/O",k));
     }
   CWorld e;
   SEnPermit edge;
   e.MakePermit(e.plan,edge,true);
   edge.issued=e.t.now-60;
   e.PlaceWith(e.plan,edge,e.rt);
   Check(e.r.outcome==EN_R_PLACED,"a permit exactly at the maximum age is still fresh");
   CWorld c;
   STpPlan changed=c.plan;
   changed.volume_out=0.2;
   c.PlaceWith(changed,c.pm,c.rt);
   Check(c.r.outcome==EN_R_REFUSED && c.t.sends==0,"a permit issued for one plan never places a changed plan");
   CWorld g;
   g.t.real=true;
   g.Place();
   bool a=(g.r.outcome==EN_R_REFUSED && g.t.sends==0);
   g.cfg.real_authorised=true;
   g.cfg.authorisation="wrong";
   g.Place();
   bool b=(StringFind(g.r.reason,"REAL_NOT_AUTHORISED")>=0);
   g.cfg.authorisation=EN_AUTH_PHRASE;
   g.t.account.demo=false;
   g.Place();
   bool d=(StringFind(g.r.reason,"REAL_REQUIRES_DEMO_ACCOUNT")>=0);
   g.t.account.demo=true;
   g.Place();
   Check(a && b && d && g.r.outcome==EN_R_PLACED,"a real transport needs the phrase and a demo account");
  }

void Scenario_terminal_reads(void)
  {
   for(int k=0;k<15;k++)
     {
      CWorld w;
      if(k==0) w.t.account.read_ok=false;
      if(k==1) w.t.account.trade_allowed=false;
      if(k==2) w.t.account.margin_mode=0;
      if(k==3) w.t.symbol.read_ok=false;
      if(k==4) w.t.symbol.trade_ok=false;
      if(k==5) w.t.quote.read_ok=false;
      if(k==6) w.t.quote.time=w.t.now-31;
      if(k==7) w.t.quote.time=w.t.now+500;
      if(k==8) w.t.list_complete=false;
      if(k==9) w.t.now=0;
      if(k==10) w.t.quote.ask=1989.0;
      if(k==11) w.t.symbol.stops_level=2100;
      if(k==12) w.t.symbol.tick_size=0.03;
      if(k==13) w.t.symbol.vol_step=0.03;
      if(k==14) w.t.symbol.vol_max=0.05;
      w.Place();
      Check(w.r.outcome==EN_R_REFUSED && w.r.sends==0 && w.t.sends==0 && !w.Has() && w.Clean(),StringFormat("terminal read case %d: zero sends, no record, lock released",k));
     }
   CWorld s;
   s.Init(-1);
   s.t.quote.bid=2012.0;
   s.t.quote.ask=2012.3;
   s.Place();
   Check(s.r.outcome==EN_R_REFUSED && s.t.sends==0,"a SELL_LIMIT below the bid is refused");
  }

void Scenario_lock_failure(void)
  {
   CWorld w;
   w.s.deny_lock=true;
   w.Place();
   Check(w.r.outcome==EN_R_LOCK_FAILED && w.t.sends==0 && w.s.writes==0 && !w.Has(),"lock failure: zero sends, nothing written");
  }

void Scenario_intent_failures(void)
  {
   CWorld w;
   w.s.fail_write_at=1;
   w.Place();
   Check(w.r.outcome==EN_R_BLOCKED && w.r.sends==0 && w.t.sends==0 && !w.Has() && w.Clean(),"intent write failure: zero sends");
   CWorld x;
   x.s.readback_differs_at=1;
   x.Place();
   bool a=(x.r.outcome==EN_R_BLOCKED && x.r.sends==0 && x.t.sends==0);
   x.Reconcile();
   Check(a && x.r.outcome==EN_R_BLOCKED,"intent read-back difference: zero sends; the damaged file is never trusted");
   CWorld y;
   SEnOrder o;
   o.found=true;
   o.ticket=5;
   o.symbol="XAUUSD";
   o.type=EN_TYPE_BUY_LIMIT;
   o.state=EN_OS_ACTIVE;
   o.price=1990.0;
   o.sl=1985.0;
   o.tp=2000.0;
   o.volume=0.1;
   o.magic=777;
   o.comment="x";
   o.time_setup=y.t.now-5;
   o.expiration=0;
   o.position_id=0;
   y.t.AddOrder(o);
   y.Place();
   Check(y.r.outcome==EN_R_REFUSED && y.t.sends==0 && !y.Has(),"an identical pending order already in the terminal blocks the send");
   CWorld z;
   o.state=EN_OS_CANCELED;
   o.price=2100.0;
   for(int i=0;i<EN_MAX_SNAP+1;i++)
     {
      o.ticket=100+i;
      z.t.AddOrder(o);
     }
   z.Place();
   Check(z.r.outcome==EN_R_REFUSED && z.t.sends==0,"a snapshot that does not fit the record is refused");
  }

void Scenario_precheck_refusal(void)
  {
   CWorld w;
   w.t.precheck_ok=false;
   w.Place();
   Check(w.r.outcome==EN_R_PRECHECK_REFUSED && w.r.sends==0 && w.t.sends==0 && w.State()==EN_ST_PRECHECK_REFUSED,"pre-check refusal: zero sends, record PRECHECK_REFUSED");
   w.t.precheck_ok=true;
   SEnRuntime fresh;
   EN_RuntimeInit(fresh);
   w.PlaceWith(w.plan,w.pm,fresh);
   Check(w.r.outcome==EN_R_DUPLICATE && w.t.sends==0,"after a pre-check refusal the same signal is a duplicate");
  }

void Scenario_duplicates(void)
  {
   CWorld w;
   w.Place();
   SEnRuntime fresh;
   EN_RuntimeInit(fresh);
   w.PlaceWith(w.plan,w.pm,fresh);
   Check(w.r.outcome==EN_R_DUPLICATE && w.r.sends==0 && w.t.sends==1,"a restart (fresh runtime, same disk): DUPLICATE, no second send");
   w.Place();
   Check(w.r.outcome==EN_R_REFUSED && StringFind(w.r.reason,"DUPLICATE_CALL")>=0 && w.t.sends==1,"the same runtime cannot send twice");
   CWorld v;
   v.Place();
   STpPlan p2;
   v.MakePlan(p2,1,"SIG-2");
   p2.e_out=1980.0;
   p2.s_out=1975.0;
   p2.tp=1990.0;
   SEnPermit pm2;
   v.MakePermit(p2,pm2,true);
   SEnRuntime r2;
   EN_RuntimeInit(r2);
   v.PlaceWith(p2,pm2,r2);
   Check(v.r.outcome==EN_R_PLACED && v.t.sends==2 && EN_FileName(1,"SIG-1")!=EN_FileName(1,"SIG-2") && EN_LockKey(1,"SIG-1")!=EN_LockKey(1,"SIG-2"),"two signals: two records, two locks, two sends");
   CWorld d;
   d.s.Put(d.Name(),"garbage\n");
   d.Place();
   Check(d.r.outcome==EN_R_BLOCKED && d.t.sends==0 && d.s.Get(d.Name())=="garbage\n" && d.s.writes==0,"a damaged record blocks and is never overwritten");
   CWorld u;
   u.s.Put(u.Name(),"x\n");
   u.s.unreadable=u.Name();
   u.Place();
   Check(u.r.outcome==EN_R_BLOCKED && u.t.sends==0,"an unreadable record blocks");
  }

void Scenario_definite_reject(void)
  {
   CWorld w;
   w.t.send_mode=EN_SM_REJECTED;
   w.Place();
   SEnRecord rec;
   w.Rec(rec);
   Check(w.r.outcome==EN_R_REJECTED && w.r.sends==1 && w.t.sends==1 && rec.state==EN_ST_REJECTED && rec.attempts==1,"a definite reject is recorded as one attempt with no order");
   w.t.send_mode=EN_SM_PLACED;
   SEnRuntime fresh;
   EN_RuntimeInit(fresh);
   w.PlaceWith(w.plan,w.pm,fresh);
   Check(w.r.outcome==EN_R_DUPLICATE && w.t.sends==1,"no retry after a reject");
   w.Reconcile();
   Check(w.r.outcome==EN_R_NOCHANGE,"reconcile of a rejected record: terminal");
  }

void Scenario_uncertain_answer(void)
  {
   for(int m=0;m<4;m++)
     {
      CWorld w;
      w.t.send_mode=(m==0 ? EN_SM_UNCERTAIN_CREATED : (m==1 ? EN_SM_UNCERTAIN_NOT_CREATED : (m==2 ? EN_SM_PARTIAL_CODES : EN_SM_UNKNOWN_CODE_WITH_ORDER)));
      w.Place();
      SEnRecord rec;
      w.Rec(rec);
      Check(w.r.outcome==EN_R_RECOVERY && w.r.sends==1 && w.t.sends==1 && rec.state==EN_ST_RECOVERY && rec.attempts==1 && w.rt.latched,StringFormat("uncertain answer %d: one attempt recorded, RECOVERY_REQUIRED, latched (not zero sends)",m));
      w.Place();
      bool a=(w.r.outcome==EN_R_REFUSED);
      SEnRuntime fresh;
      EN_RuntimeInit(fresh);
      w.PlaceWith(w.plan,w.pm,fresh);
      Check(a && w.r.outcome==EN_R_DUPLICATE && w.t.sends==1,StringFormat("uncertain answer %d: no retry from this runtime or after a restart",m));
     }
  }

void Scenario_unproven_link(void)
  {
   for(int m=0;m<3;m++)
     {
      CWorld w;
      w.t.send_mode=(m==0 ? EN_SM_PLACED_UNREADABLE : (m==1 ? EN_SM_PLACED_MODIFIED : EN_SM_PLACED_OTHER_TICKET));
      w.Place();
      SEnRecord rec;
      w.Rec(rec);
      Check(w.r.outcome==EN_R_RECOVERY && rec.state==EN_ST_RECOVERY && rec.linked==0 && rec.attempts==1 && w.t.sends==1,StringFormat("unproven link %d: RECOVERY_REQUIRED, never PLACED",m));
     }
   CWorld o;
   SEnOrder old;
   old.found=true;
   old.ticket=5;
   old.symbol="XAUUSD";
   old.type=EN_TYPE_BUY_LIMIT;
   old.state=EN_OS_FILLED;
   old.price=1990.0;
   old.sl=1985.0;
   old.tp=2000.0;
   old.volume=0.1;
   old.magic=777;
   old.comment="";
   old.time_setup=o.t.now-9999;
   old.expiration=0;
   old.position_id=11;
   o.t.AddOrder(old);
   o.t.send_mode=EN_SM_RETURNS_OLD_TICKET;
   o.Place();
   SEnRecord ro;
   o.Rec(ro);
   Check(o.r.outcome==EN_R_RECOVERY && ro.state==EN_ST_RECOVERY && ro.linked==0 && o.t.sends==1,"a response ticket that was in the pre-send snapshot never links");
  }

void Scenario_recovery_by_tuple(void)
  {
   CWorld w;
   w.t.send_mode=EN_SM_UNCERTAIN_CREATED;
   w.Place();
   w.Reconcile();
   SEnRecord rec;
   w.Rec(rec);
   Check(w.r.outcome==EN_R_PLACED && w.r.sends==0 && rec.linked==1 && rec.state==EN_ST_PLACED && w.t.sends==1,"an uncertain answer is resolved by the unique tuple outside the snapshot, without a send");
   CWorld x;
   x.s.fail_write_at=2;
   x.Place();
   bool a=(x.r.outcome==EN_R_RECOVERY && x.r.sends==1 && x.State()==EN_ST_INTENT && x.rt.latched);
   x.Reconcile();
   Check(a && x.r.outcome==EN_R_PLACED && x.State()==EN_ST_PLACED && x.t.sends==1,"outcome not saved: INTENT stays on disk, latched, reconcile links the existing order");
   CWorld y;
   y.t.send_mode=EN_SM_UNCERTAIN_NOT_CREATED;
   y.Place();
   bool all=true;
   for(int i=0;i<3;i++)
     {
      y.Reconcile();
      all=all && (y.r.outcome==EN_R_RECOVERY && y.t.sends==1);
     }
   Check(all,"no candidate: RECOVERY_REQUIRED stays and nothing is resent");
   CWorld z;
   SEnOrder o;
   o.found=true;
   o.ticket=5;
   o.symbol="XAUUSD";
   o.type=EN_TYPE_BUY_LIMIT;
   o.state=EN_OS_CANCELED;
   o.price=1990.0;
   o.sl=1985.0;
   o.tp=2000.0;
   o.volume=0.1;
   o.magic=777;
   o.comment="";
   o.time_setup=z.t.now;
   o.expiration=0;
   o.position_id=0;
   z.t.AddOrder(o);
   z.t.send_mode=EN_SM_UNCERTAIN_NOT_CREATED;
   z.Place();
   z.Reconcile();
   SEnRecord rz;
   z.Rec(rz);
   Check(z.r.outcome==EN_R_RECOVERY && rz.linked==0,"an order that was in the pre-send snapshot is never a candidate");
  }

void Scenario_comment_magic_volume_not_proof(void)
  {
   CWorld w;
   w.t.send_mode=EN_SM_UNCERTAIN_NOT_CREATED;
   w.Place();
   SEnOrder b;
   b.found=true;
   b.symbol="XAUUSD";
   b.type=EN_TYPE_BUY_LIMIT;
   b.state=EN_OS_ACTIVE;
   b.magic=777;
   b.comment=EN_ReqId(SIG);
   b.volume=0.1;
   b.time_setup=w.t.now;
   b.expiration=0;
   b.position_id=0;
   for(int k=0;k<8;k++)
     {
      b.ticket=11+k;
      b.price=1990.0;
      b.sl=1985.0;
      b.tp=2000.0;
      b.magic=777;
      b.volume=0.1;
      b.type=EN_TYPE_BUY_LIMIT;
      b.symbol="XAUUSD";
      b.time_setup=w.t.now;
      if(k==0) b.price=1991.0;
      if(k==1) b.sl=1984.0;
      if(k==2) b.tp=2001.0;
      if(k==3) b.magic=1;
      if(k==4) b.volume=0.2;
      if(k==5) b.type=EN_TYPE_SELL_LIMIT;
      if(k==6) b.symbol="EURUSD";
      if(k==7) b.time_setup=w.t.now-5000;
      w.t.AddOrder(b);
     }
   w.Reconcile();
   SEnRecord rec;
   w.Rec(rec);
   Check(w.r.outcome==EN_R_RECOVERY && rec.linked==0 && w.t.sends==1,"orders sharing only the comment, the magic, the volume or most of the tuple are never linked");
  }

void Scenario_ambiguous_candidates(void)
  {
   CWorld w;
   w.t.send_mode=EN_SM_UNCERTAIN_CREATED;
   w.Place();
   SEnOrder dup=w.t.orders[w.IdxLast()];
   dup.ticket=dup.ticket+1;
   w.t.AddOrder(dup);
   w.Reconcile();
   SEnRecord rec;
   w.Rec(rec);
   Check(w.r.outcome==EN_R_BLOCKED && rec.state==EN_ST_BLOCKED && rec.linked==0 && w.t.sends==1,"two candidates: BLOCKED and none is chosen");
   CWorld x;
   x.t.send_mode=EN_SM_UNCERTAIN_CREATED;
   x.Place();
   x.t.list_complete=false;
   x.Reconcile();
   SEnRecord rx;
   x.Rec(rx);
   Check(x.r.outcome==EN_R_RECOVERY && rx.state==EN_ST_RECOVERY && rx.linked==0,"an incomplete list during recovery concludes nothing");
  }

void Scenario_reconcile_states(void)
  {
   CWorld a;
   a.Place();
   ulong tk=a.r.order_ticket;
   a.Reconcile();
   SEnRecord ra;
   a.Rec(ra);
   Check(a.r.outcome==EN_R_NOCHANGE && a.t.sends==1 && a.t.cancels==0 && ra.generation==2,"active: no change, no send, no cancel");
   int k=a.t.IndexOf(tk);
   a.t.orders[k].state=EN_OS_FILLED;
   a.t.orders[k].position_id=424242;
   a.Reconcile();
   a.Rec(ra);
   Check(a.r.outcome==EN_R_FILLED && a.r.position_id==424242 && ra.state==EN_ST_FILLED && ra.position_id==424242,"filled: the position id comes from the order");
   a.Reconcile();
   Check(a.r.outcome==EN_R_NOCHANGE,"filled is terminal for this module");
   CWorld b;
   b.Place();
   b.t.orders[b.t.IndexOf(b.r.order_ticket)].state=EN_OS_FILLED;
   b.Reconcile();
   Check(b.r.outcome==EN_R_RECOVERY && b.State()==EN_ST_RECOVERY,"filled without a position id is not trusted");
   CWorld c;
   c.Place();
   c.t.orders[c.t.IndexOf(c.r.order_ticket)].state=EN_OS_CANCELED;
   c.Reconcile();
   bool x1=(c.r.outcome==EN_R_CANCELLED && c.State()==EN_ST_CANCELLED);
   CWorld d;
   d.Place();
   d.t.orders[d.t.IndexOf(d.r.order_ticket)].state=EN_OS_EXPIRED;
   d.Reconcile();
   Check(x1 && d.r.outcome==EN_R_EXPIRED && d.State()==EN_ST_EXPIRED,"cancelled and expired orders end the record");
   CWorld e;
   e.Place();
   ulong te=e.r.order_ticket;
   e.t.Hide(te);
   e.Reconcile();
   bool y1=(e.r.outcome==EN_R_RECOVERY && e.State()==EN_ST_RECOVERY);
   e.t.Unhide();
   e.Reconcile();
   Check(y1 && e.r.outcome==EN_R_PLACED && e.State()==EN_ST_PLACED,"a missing order is RECOVERY_REQUIRED; it is accepted again when it reappears with the same tuple");
   CWorld f;
   f.Place();
   f.t.orders[f.t.IndexOf(f.r.order_ticket)].sl=1980.0;
   f.Reconcile();
   bool z1=(f.r.outcome==EN_R_BLOCKED && f.State()==EN_ST_BLOCKED && f.t.cancels==0 && f.t.sends==1);
   f.Reconcile();
   Check(z1 && f.r.outcome==EN_R_NOCHANGE,"a modified order is BLOCKED and not touched");
   CWorld g;
   g.Place();
   g.t.orders[g.t.IndexOf(g.r.order_ticket)].magic=5;
   g.Reconcile();
   Check(g.r.outcome==EN_R_BLOCKED && g.State()==EN_ST_BLOCKED,"a changed order identity is BLOCKED");
   CWorld h;
   h.Place();
   string good=h.s.Get(h.Name());
   string bad=good;
   StringReplace(bad,"LOGIN=5001234","LOGIN=5001235");
   h.s.Put(h.Name(),bad);
   h.Reconcile();
   bool u1=(h.r.outcome==EN_R_BLOCKED);
   h.s.Put(h.Name(),good);
   h.cfg.ea_magic=778;
   h.Reconcile();
   bool u2=(h.r.outcome==EN_R_BLOCKED);
   h.cfg.ea_magic=777;
   h.Reconcile("SIG-NONE");
   bool u3=(h.r.outcome==EN_R_NONE);
   h.t.account.read_ok=false;
   h.Reconcile();
   Check(u1 && u2 && u3 && h.r.outcome==EN_R_REFUSED,"damaged / other login / other magic / no record / unreadable account");
   bool never=true;
   for(int m=0;m<4;m++)
     {
      CWorld n;
      n.Place();
      int ix=n.t.IndexOf(n.r.order_ticket);
      if(m==1) n.t.orders[ix].state=EN_OS_CANCELED;
      if(m==2) n.t.Hide(n.r.order_ticket);
      if(m==3) n.t.orders[ix].sl=1.0;
      n.Reconcile();
      n.Reconcile();
      never=never && n.t.sends==1 && n.t.cancels==0;
     }
   Check(never,"reconcile never sends or cancels on any path");
   CWorld q;
   q.Place();
   CEnFakeStore s2;
   s2.Put(q.Name(),q.s.Get(q.Name()));
   EN_Reconcile(q.cfg,GetPointer(q.t),GetPointer(s2),SIG,q.r);
   Check(q.r.outcome==EN_R_NOCHANGE && q.t.sends==1,"a restart with a new store object finds the record");
  }

void Scenario_cancel_proven_only(void)
  {
   CWorld w;
   w.Place();
   STpCancel dec;
   TP_CancelDecision(true,SIG,false,TP_EV_SESSION_END,dec);
   SEnRuntime rt;
   EN_RuntimeInit(rt);
   EN_Cancel(w.cfg,GetPointer(w.t),GetPointer(w.s),rt,SIG,dec,w.r);
   Check(w.r.outcome==EN_R_CANCELLED && w.t.cancels==1 && w.State()==EN_ST_CANCELLED && w.t.sends==1 && w.Clean(),"a proven pending order is cancelled and confirmed");
   for(int k=0;k<4;k++)
     {
      CWorld d;
      d.Place();
      STpCancel bad;
      if(k==0) TP_CancelDecision(true,"OTHER",false,TP_EV_SESSION_END,bad);
      if(k==1) TP_CancelDecision(false,"",false,TP_EV_SESSION_END,bad);
      if(k==2) TP_CancelDecision(true,SIG,false,0,bad);
      if(k==3) TP_CancelDecision(true,SIG,false,999,bad);
      SEnRuntime r2;
      EN_RuntimeInit(r2);
      EN_Cancel(d.cfg,GetPointer(d.t),GetPointer(d.s),r2,SIG,bad,d.r);
      Check(d.r.outcome==EN_R_REFUSED && d.t.cancels==0,StringFormat("cancel decision case %d: refused",k));
     }
   for(int k=0;k<5;k++)
     {
      CWorld d;
      d.Place();
      int ix=d.t.IndexOf(d.r.order_ticket);
      if(k==0) d.t.orders[ix].sl=1980.0;
      if(k==1) d.t.orders[ix].magic=5;
      if(k==2) d.t.orders[ix].state=EN_OS_FILLED;
      if(k==3) d.t.orders[ix].symbol="EURUSD";
      if(k==4) d.t.Hide(d.r.order_ticket);
      SEnRuntime r2;
      EN_RuntimeInit(r2);
      EN_Cancel(d.cfg,GetPointer(d.t),GetPointer(d.s),r2,SIG,dec,d.r);
      Check(d.r.outcome==EN_R_REFUSED && d.t.cancels==0,StringFormat("unproven order %d: nothing is cancelled",k));
     }
   for(int k=0;k<4;k++)
     {
      CWorld d;
      if(k==0) {d.t.send_mode=EN_SM_REJECTED; d.Place();}
      if(k==1) {d.t.send_mode=EN_SM_UNCERTAIN_CREATED; d.Place();}
      if(k==2) {d.Place(); int ix=d.t.IndexOf(d.r.order_ticket); d.t.orders[ix].state=EN_OS_FILLED; d.t.orders[ix].position_id=9; d.Reconcile();}
      if(k==3) {d.Place(); d.t.orders[d.t.IndexOf(d.r.order_ticket)].state=EN_OS_CANCELED; d.Reconcile();}
      SEnRuntime r2;
      EN_RuntimeInit(r2);
      EN_Cancel(d.cfg,GetPointer(d.t),GetPointer(d.s),r2,SIG,dec,d.r);
      Check(d.r.outcome==EN_R_REFUSED && d.t.cancels==0,StringFormat("record state case %d: only a PLACED linked record can be cancelled",k));
     }
   CWorld f;
   f.Place();
   SEnOrder foreign=f.t.orders[0];
   foreign.ticket=77;
   foreign.magic=999;
   foreign.comment="manual";
   f.t.AddOrder(foreign);
   SEnRuntime r3;
   EN_RuntimeInit(r3);
   EN_Cancel(f.cfg,GetPointer(f.t),GetPointer(f.s),r3,SIG,dec,f.r);
   Check(f.r.outcome==EN_R_CANCELLED && f.t.orders[f.t.IndexOf(77)].state==EN_OS_ACTIVE,"a foreign pending order is never touched");
   CWorld g;
   g.Place();
   g.s.fail_write_at=g.s.writes+1;
   SEnRuntime r4;
   EN_RuntimeInit(r4);
   EN_Cancel(g.cfg,GetPointer(g.t),GetPointer(g.s),r4,SIG,dec,g.r);
   Check(g.r.outcome==EN_R_BLOCKED && g.t.cancels==0 && g.State()==EN_ST_PLACED,"the cancel intent is saved before the call; a failed save cancels nothing");
   CWorld h;
   h.Place();
   h.s.deny_lock=true;
   SEnRuntime r5;
   EN_RuntimeInit(r5);
   EN_Cancel(h.cfg,GetPointer(h.t),GetPointer(h.s),r5,SIG,dec,h.r);
   bool a=(h.r.outcome==EN_R_LOCK_FAILED && h.t.cancels==0);
   h.s.deny_lock=false;
   h.cfg.enabled=false;
   EN_Cancel(h.cfg,GetPointer(h.t),GetPointer(h.s),r5,SIG,dec,h.r);
   Check(a && h.r.outcome==EN_R_REFUSED && h.t.cancels==0,"cancel: lock failure and disabled executor do nothing");
  }

void Scenario_cancel_uncertain(void)
  {
   STpCancel dec;
   TP_CancelDecision(true,SIG,false,TP_EV_SESSION_END,dec);
   CWorld w;
   w.Place();
   w.t.cancel_mode=EN_CM_LOST;
   SEnRuntime rt;
   EN_RuntimeInit(rt);
   EN_Cancel(w.cfg,GetPointer(w.t),GetPointer(w.s),rt,SIG,dec,w.r);
   bool a=(w.r.outcome==EN_R_CANCEL_UNCERTAIN && w.t.cancels==1 && w.State()==EN_ST_CANCEL_UNCERTAIN);
   SEnRuntime r2;
   EN_RuntimeInit(r2);
   EN_Cancel(w.cfg,GetPointer(w.t),GetPointer(w.s),r2,SIG,dec,w.r);
   bool b=(w.r.outcome==EN_R_REFUSED);
   w.Reconcile();
   Check(a && b && w.r.outcome==EN_R_CANCELLED && w.State()==EN_ST_CANCELLED && w.t.cancels==1 && w.t.sends==1,"a lost answer: CANCEL_UNCERTAIN, no retry, reconcile confirms the cancellation");
   CWorld x;
   x.Place();
   x.t.cancel_mode=EN_CM_NOT_EFFECTIVE;
   SEnRuntime r3;
   EN_RuntimeInit(r3);
   EN_Cancel(x.cfg,GetPointer(x.t),GetPointer(x.s),r3,SIG,dec,x.r);
   bool c=(x.r.outcome==EN_R_CANCEL_UNCERTAIN && x.State()==EN_ST_CANCEL_UNCERTAIN);
   x.Reconcile();
   Check(c && x.r.outcome==EN_R_PLACED && x.State()==EN_ST_PLACED && x.t.cancels==1,"a cancel that did not take effect returns to PLACED through reconcile");
   CWorld x2;
   x2.Place();
   x2.t.cancel_mode=EN_CM_NOT_EFFECTIVE;
   SEnRuntime r6;
   EN_RuntimeInit(r6);
   EN_Cancel(x2.cfg,GetPointer(x2.t),GetPointer(x2.s),r6,SIG,dec,x2.r);
   SEnRuntime r7;
   EN_RuntimeInit(r7);
   EN_Cancel(x2.cfg,GetPointer(x2.t),GetPointer(x2.s),r7,SIG,dec,x2.r);
   Check(x2.State()==EN_ST_CANCEL_UNCERTAIN && x2.r.outcome==EN_R_REFUSED && x2.t.cancels==1,"a new runtime still cannot cancel a CANCEL_UNCERTAIN record: reconcile first");
   CWorld y;
   y.Place();
   y.t.cancel_mode=EN_CM_FAILS;
   SEnRuntime r4;
   EN_RuntimeInit(r4);
   EN_Cancel(y.cfg,GetPointer(y.t),GetPointer(y.s),r4,SIG,dec,y.r);
   bool d=(y.r.outcome==EN_R_CANCEL_UNCERTAIN && y.t.cancels==1);
   EN_Cancel(y.cfg,GetPointer(y.t),GetPointer(y.s),r4,SIG,dec,y.r);
   Check(d && y.r.outcome==EN_R_REFUSED && y.t.cancels==1,"a failed cancel is uncertain and one cancellation per runtime");
  }

void Scenario_codec(void)
  {
   CWorld w;
   w.Place();
   SEnRecord rec;
   w.Rec(rec);
   string text,why;
   bool ok=EN_Encode(rec,text,why);
   SEnRecord back;
   bool ok2=EN_Decode(text,back,why);
   string text2;
   EN_Encode(back,text2,why);
   Check(ok && ok2 && text==text2,"round trip");
   string d1=text;
   StringReplace(d1,"E=1990","E=1991");
   SEnRecord tmp;
   bool bad1=!EN_Decode(d1,tmp,why);
   bool bad2=!EN_Decode(StringSubstr(text,0,StringLen(text)-5),tmp,why);
   bool bad3=!EN_Decode("",tmp,why);
   string d4=text;
   StringReplace(d4,"VERSION=1","VERSION=2");
   bool bad4=!EN_Decode(d4,tmp,why);
   Check(bad1 && bad2 && bad3 && bad4,"damage, truncation, empty and version are refused");
   bool all=true;
   for(int k=0;k<20;k++)
     {
      SEnRecord r2=rec;
      if(k==0) r2.state="NOPE";
      if(k==1) r2.attempts=2;
      if(k==2) r2.linked=0;
      if(k==3) r2.order_ticket=0;
      if(k==4) r2.direction=0;
      if(k==5) r2.e=0.0;
      if(k==6) r2.s=1995.0;
      if(k==7) r2.req_id="x";
      if(k==8) r2.magic=0;
      if(k==9) r2.filling=0;
      if(k==10) r2.expiry_mode=0;
      if(k==11) r2.expiration=5;
      if(k==12) r2.position_id=3;
      if(k==13) {r2.n_snap=1; r2.snap[0]=r2.order_ticket;}
      if(k==14) {r2.n_snap=2; r2.snap[0]=1; r2.snap[1]=1;}
      if(k==15) r2.n_snap=EN_MAX_SNAP+1;
      if(k==16) r2.generation=0;
      if(k==17) r2.state=EN_ST_INTENT;
      if(k==18) r2.login=0;
      if(k==19) r2.t_intent=0;
      all=all && (EN_Validate(r2)!="");
     }
   Check(all,"validation rejects inconsistent records");
   Check(EN_FileName(1,"A")!=EN_FileName(2,"A") && EN_LockKey(1,"A")!=EN_LockKey(1,"B") && StringFind(EN_ReqId("A"),"VELO_EN_")==0 && StringLen(EN_ReqId("A"))<=31,"names and keys are per signal and account");
   STpPlan p1=w.plan;
   string base=EN_PlanDigest(p1);
   bool dg=true;
   for(int k=0;k<4;k++)
     {
      STpPlan p2=p1;
      if(k==0) p2.e_out=1991.0;
      if(k==1) p2.s_out=1984.0;
      if(k==2) p2.tp=2001.0;
      if(k==3) p2.volume_out=0.2;
      dg=dg && EN_PlanDigest(p2)!=base;
     }
   STpPlan p3=p1;
   p3.signal_id="X";
   STpPlan p4=p1;
   p4.signal_id="";
   Check(dg && EN_PlanDigest(p3)!=base && EN_PlanDigest(p4)=="","the digest binds every order field");
  }

void OnStart()
  {
   Print("T013 ENTRY EXECUTOR TEST: fake transport and fake store only; no file, no terminal read, no order, no trade.");
   Scenario_buy_limit_placed();
   Scenario_sell_limit_placed();
   Scenario_unset_inputs_block();
   Scenario_plan_refusals();
   Scenario_permit_binding();
   Scenario_terminal_reads();
   Scenario_lock_failure();
   Scenario_intent_failures();
   Scenario_precheck_refusal();
   Scenario_duplicates();
   Scenario_definite_reject();
   Scenario_uncertain_answer();
   Scenario_unproven_link();
   Scenario_recovery_by_tuple();
   Scenario_comment_magic_volume_not_proof();
   Scenario_ambiguous_candidates();
   Scenario_reconcile_states();
   Scenario_cancel_proven_only();
   Scenario_cancel_uncertain();
   Scenario_codec();
   PrintFormat("T013 ENTRY EXECUTOR TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
