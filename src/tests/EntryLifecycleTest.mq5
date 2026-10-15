// T019 entry-lifecycle test (FAKE transport and FAKE store only): persistent index + halt, startup reconcile, tick (fill / gated cancel), events from facts. Never a send.
// Mirrors tests/test_lifecycle.py (the scenario names are pinned equal by a Python test). NEVER includes the real transport; no terminal read, no file, no order, no trade.
// NOT YET COMPILED OR RUN (UNVERIFIED): Codex compiles it, the owner runs it in MT5.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/EntryLifecycle.mqh"
#include "../include/EntryTransportFake.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
#define SIG "SIG-1"
#define EV_ALL_ENABLED (TP_EV_SESSION_END|TP_EV_NEWS_BLOCK|TP_EV_DAILY_LIMIT)

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
   SLcState st;
   string notes;
   void MakePlan(STpPlan &p,const int direction)
     {
      TP_PlanReset(p,SIG,"SET-1",direction);
      p.e_out=(direction==1 ? 1990.0 : 2010.0);
      p.s_out=(direction==1 ? 1985.0 : 2015.0);
      p.tp=2000.0;
      p.volume_out=0.1;
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
      MakePlan(plan,direction);
      STpPermit tpm;
      tpm.allow=true;
      tpm.primary_reason="";
      tpm.reason_count=0;
      tpm.registered=false;
      EN_PermitFrom(plan,tpm,t.now,pm);
      LC_StateInit(st,t.account.login);
      notes="";
     }
   CWorld(void) {Init(1);}
   // placed AND indexed
   bool Placed(const int direction)
     {
      Init(direction);
      EN_Place(cfg,GetPointer(t),GetPointer(s),rt,plan,pm,r);
      return(r.outcome==EN_R_PLACED && LC_Register(GetPointer(s),st,SIG,notes));
     }
   string RecState(void)
     {
      SEnRecord rec;
      string why;
      return(EN_Decode(s.Get(EN_FileName(t.account.login,SIG)),rec,why) ? rec.state : "NO_RECORD");
     }
   bool Stored(SLcState &out)
     {
      string why;
      return(LC_Decode(s.Get(LC_FileName(t.account.login)),t.account.login,out,why));
     }
  };

bool Has(const string text,const string part) {return(StringFind(text,part)>=0);}
bool Starts(const string text,const string part) {return(StringFind(text,part)==0);}

void Scenario_index_codec_and_damage(void)
  {
   SLcState a;
   LC_StateInit(a,5001234);
   a.halted="HALT: reason\nwith newline";
   a.ids[0]="S|a|b|c|L1|M15F1U";
   a.ids[1]="SIG-2";
   a.n=2;
   SLcState b;
   string why;
   bool ok=LC_Decode(LC_Encode(a),5001234,b,why);
   Check(ok && b.n==2 && b.ids[0]==a.ids[0] && b.ids[1]=="SIG-2" && b.halted=="HALT: reason with newline","the index round-trips (ids with a separator, a newline in the reason is cleaned)");
   string text=LC_Encode(a);
   string t1=text;
   StringReplace(t1,"SIG-2","SIG-3");
   string t3=text;
   StringReplace(t3,"login=5001234","login=5001235");
   Check(!LC_Decode(t1,5001234,b,why) && why=="CRC_MISMATCH","an edited id is a CRC mismatch");
   Check(!LC_Decode(StringSubstr(text,0,StringLen(text)-10),5001234,b,why),"a truncated file is refused");
   Check(!LC_Decode(t3,5001234,b,why),"an edited login is refused");
   SLcState c;
   LC_StateInit(c,77);
   c.ids[0]="A";
   c.n=1;
   Check(!LC_Decode(LC_Encode(c),5001234,b,why) && why=="LOGIN_MISMATCH","another account's file is refused");
   string body=LC_HEADER+"\n1\nlogin=5\nhalt=\nn=2\nA\n";
   Check(!LC_Decode(body+"CRC="+StringFormat("%08X",ESC_Crc32(body))+"\n",5,b,why) && why=="BAD_COUNT","a count that does not match the ids is refused");
   Check(LC_FileName(5001234)=="VELO_T013_ENTRY_INDEX_5001234.state","the index file name");
  }

void Scenario_register_and_save_failure(void)
  {
   CWorld w;
   string notes="";
   w.s.fail_write_at=1;
   Check(!LC_Register(GetPointer(w.s),w.st,SIG,notes) && Has(w.st.halted,"LIFECYCLE_STATE_NOT_SAVED"),"a failed save halts");
   CWorld x;
   x.s.readback_differs_at=1;
   Check(!LC_Register(GetPointer(x.s),x.st,SIG,notes) && x.st.halted!="","a read-back that differs halts");
   CWorld y;
   Check(!LC_Register(GetPointer(y.s),y.st,"bad\nid",notes) && y.st.halted=="LIFECYCLE_BAD_SIGNAL_ID","a signal id with a newline halts");
   CWorld z;
   bool all=true;
   for(int i=0;i<LC_MAX;i++) all=all && LC_Register(GetPointer(z.s),z.st,"ID"+IntegerToString(i),notes);
   Check(all && !LC_Register(GetPointer(z.s),z.st,"ONE-TOO-MANY",notes) && z.st.halted=="LIFECYCLE_INDEX_FULL","a full index halts");
  }

void Scenario_startup_clean(void)
  {
   CWorld w;
   string notes;
   SLcState st;
   LC_Startup(w.cfg,GetPointer(w.t),GetPointer(w.s),false,st,notes);
   Check(st.halted=="" && st.n==0 && w.s.writes==0,"nothing indexed: nothing is written");
   for(int d=0;d<2;d++)
     {
      CWorld v;
      bool placed=v.Placed(d==0 ? 1 : -1);
      v.t.orders[0].state=EN_OS_CANCELED;              // the order ended while the EA was away
      SLcState s2;
      LC_Startup(v.cfg,GetPointer(v.t),GetPointer(v.s),false,s2,notes);
      SLcState stored;
      Check(placed && s2.halted=="" && s2.n==0 && v.Stored(stored) && stored.n==0 && v.t.sends==1,StringFormat("dir %d: an ended order closes its index entry, no halt, no send",d));
     }
  }

void Scenario_startup_halts_on_unprovable(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CWorld w;
      bool placed=w.Placed(dir);
      CEnFakeTransport fresh;                               // a restart: the FAKE book is empty, nothing is mapped to a broker fact
      fresh.quote.time=fresh.now;
      SLcState s2;
      string notes;
      LC_Startup(w.cfg,GetPointer(fresh),GetPointer(w.s),false,s2,notes);
      Check(placed && Has(s2.halted,"UNRESOLVED_ENTRY_RECORD") && fresh.sends==0 && fresh.cancels==0 && w.RecState()==EN_ST_RECOVERY,StringFormat("dir %d: an unprovable record halts, nothing is sent or cancelled",dir));
      CEnFakeTransport fresh2;
      fresh2.quote.time=fresh2.now;
      SLcState s3;
      LC_Startup(w.cfg,GetPointer(fresh2),GetPointer(w.s),false,s3,notes);
      Check(Has(s3.halted,"UNRESOLVED_ENTRY_RECORD") && s3.n==1,StringFormat("dir %d: the halt survives another restart",dir));
      CEnFakeTransport fresh3;
      fresh3.quote.time=fresh3.now;
      SLcState s4;
      LC_Startup(w.cfg,GetPointer(fresh3),GetPointer(w.s),true,s4,notes);
      Check(s4.halted=="" && s4.n==0 && s4.login>0 && s4.login==w.t.account.login && s4.n==0,StringFormat("dir %d: an explicit acknowledgement clears the halt and drops the unresolved id",dir));
      CEnFakeTransport fresh4;
      fresh4.quote.time=fresh4.now;
      SEnPermit pm2;
      STpPermit tpm;
      tpm.allow=true;
      tpm.primary_reason="";
      tpm.reason_count=0;
      tpm.registered=false;
      EN_PermitFrom(w.plan,tpm,fresh4.now,pm2);
      SEnRuntime rt2;
      EN_RuntimeInit(rt2);
      SEnResult again;
      EN_Place(w.cfg,GetPointer(fresh4),GetPointer(w.s),rt2,w.plan,pm2,again);
      Check(again.outcome==EN_R_DUPLICATE && fresh4.sends==0,StringFormat("dir %d: the signal stays consumed",dir));
     }
  }

void Scenario_startup_keeps_open_pending(void)
  {
   CWorld w;
   bool placed=w.Placed(1);
   SLcState s2;
   string notes;
   LC_Startup(w.cfg,GetPointer(w.t),GetPointer(w.s),false,s2,notes);
   Check(placed && s2.halted=="" && s2.n==1 && s2.ids[0]==SIG && w.t.sends==1 && w.t.cancels==0,"the same book: the order is provably still active, kept in the index");
  }

void Scenario_tick_fill_unmanaged(void)
  {
   for(int d=0;d<2;d++)
     {
      CWorld w;
      bool placed=w.Placed(d==0 ? 1 : -1);
      w.t.orders[0].state=EN_OS_FILLED;
      w.t.orders[0].position_id=4242;
      string notes;
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.st,0,0,notes);
      Check(placed && w.st.n==0 && Has(notes,"FILLED_UNMANAGED") && w.st.halted=="" && w.t.sends==1 && w.t.cancels==0 && w.RecState()==EN_ST_FILLED,
            StringFormat("dir %d: a fill is recorded and reported unmanaged; no registration, no cancel, no second send",d));
     }
  }

void Scenario_cancel_gated_by_enabled_events(void)
  {
   for(int d=0;d<2;d++)
     {
      CWorld w;
      bool placed=w.Placed(d==0 ? 1 : -1);
      string notes;
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.st,TP_EV_SESSION_END,0,notes);
      Check(placed && w.t.cancels==0 && w.st.n==1 && Has(notes,"CANCEL_DUE_NOT_ENABLED"),StringFormat("dir %d: a due event that the owner did not enable cancels nothing",d));
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.st,TP_EV_SESSION_END,TP_EV_NEWS_BLOCK,notes);
      Check(w.t.cancels==0,StringFormat("dir %d: another enabled event does not enable this one",d));
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.st,TP_EV_SESSION_END|TP_EV_NEWS_BLOCK,TP_EV_NEWS_BLOCK,notes);
      Check(w.t.cancels==1 && w.st.n==0 && w.st.halted=="" && w.RecState()==EN_ST_CANCELLED && Has(notes,"CANCELLED"),StringFormat("dir %d: an enabled due event cancels the proven pending order once",d));
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.st,EV_ALL_ENABLED,EV_ALL_ENABLED,notes);
      Check(w.t.cancels==1 && w.t.sends==1,StringFormat("dir %d: a cancelled order is not cancelled twice",d));
     }
  }

void Scenario_cancel_uncertain_halts(void)
  {
   int modes[3]={EN_CM_LOST,EN_CM_NOT_EFFECTIVE,EN_CM_FAILS};
   for(int k=0;k<3;k++)
     {
      CWorld w;
      bool placed=w.Placed(1);
      w.t.cancel_mode=modes[k];
      string notes;
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.st,TP_EV_DAILY_LIMIT,TP_EV_DAILY_LIMIT,notes);
      bool halted=Has(w.st.halted,"CANCEL_NOT_CONFIRMED");
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.st,TP_EV_DAILY_LIMIT,TP_EV_DAILY_LIMIT,notes);
      SLcState stored;
      Check(placed && halted && w.t.cancels<=1 && w.t.sends==1 && w.Stored(stored) && Has(stored.halted,"CANCEL_NOT_CONFIRMED"),
            StringFormat("cancel mode %d: not confirmed halts, persists, no automatic second cancellation",modes[k]));
     }
  }

void Scenario_due_events_from_facts(void)
  {
   Check(LC_DueEvents(TP_SESSION_OPEN,TP_NEWS_CLEAR,true,false)==0,"nothing due");
   Check(LC_DueEvents(TP_SESSION_CLOSED,TP_NEWS_CLEAR,false,false)==TP_EV_SESSION_END,"session closed");
   Check(LC_DueEvents(TP_SESSION_OPEN,TP_NEWS_BLOCKED,false,false)==TP_EV_NEWS_BLOCK,"news blocked");
   Check(LC_DueEvents(TP_SESSION_OPEN,TP_NEWS_CLEAR,true,true)==TP_EV_DAILY_LIMIT,"daily limit");
   Check(LC_DueEvents(TP_SESSION_UNKNOWN,TP_NEWS_UNKNOWN,false,true)==0,"unknown never asserts an event; an absent daily result does not either");
   Check(LC_DueEvents(TP_SESSION_CLOSED,TP_NEWS_BLOCKED,true,true)==EV_ALL_ENABLED,"all three");
  }

void Scenario_damaged_state_never_overwritten(void)
  {
   CWorld w;
   bool placed=w.Placed(1);
   string name=LC_FileName(w.t.account.login);
   string damaged=w.s.Get(name);
   StringReplace(damaged,SIG,"SIG-X");
   w.s.Put(name,damaged);
   CEnFakeTransport fresh;
   fresh.quote.time=fresh.now;
   SLcState s2;
   string notes;
   LC_Startup(w.cfg,GetPointer(fresh),GetPointer(w.s),true,s2,notes);
   Check(placed && Has(s2.halted,"LIFECYCLE_STATE_DAMAGED") && w.s.Get(name)==damaged && fresh.sends==0 && fresh.cancels==0,"a damaged file halts and is never repaired or overwritten, even with an acknowledgement");
   w.s.unreadable=name;
   SLcState s3;
   LC_Startup(w.cfg,GetPointer(fresh),GetPointer(w.s),false,s3,notes);
   Check(Has(s3.halted,"LIFECYCLE_STATE_UNREADABLE"),"an unreadable file halts");
  }

void OnStart()
  {
   Print("T019 ENTRY LIFECYCLE TEST: fake transport and fake store only; no terminal read, no order, no file.");
   Scenario_index_codec_and_damage();
   Scenario_register_and_save_failure();
   Scenario_startup_clean();
   Scenario_startup_halts_on_unprovable();
   Scenario_startup_keeps_open_pending();
   Scenario_tick_fill_unmanaged();
   Scenario_cancel_gated_by_enabled_events();
   Scenario_cancel_uncertain_halts();
   Scenario_due_events_from_facts();
   Scenario_damaged_state_never_overwritten();
   PrintFormat("T019 ENTRY LIFECYCLE TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
