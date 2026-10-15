// T019 entry-lifecycle test (FAKE transport and FAKE store only): persistent index + halt, index saved BEFORE every send, exclusive ownership of the index (the existing lock), startup reconcile,
// tick (fill / gated cancel), events from facts. Never a send of its own. Mirrors tests/test_lifecycle.py (the scenario names are pinned equal by a Python test); the gate / orchestrator wiring of the
// pre-send hook is tested in EntryGateTest and EntryOrchestratorTest. NEVER includes the real transport; no terminal read, no file, no order, no trade.
// NOT YET COMPILED OR RUN (UNVERIFIED): Codex compiles it, the owner runs it in MT5.
#property strict
#property script_show_inputs
#property version "1.01"
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

bool Has(const string text,const string part) {return(StringFind(text,part)>=0);}
bool Starts(const string text,const string part) {return(StringFind(text,part)==0);}

// counts the accesses to the lifecycle index file
class CCountingStore : public CEnFakeStore
  {
public:
   int index_reads;
   int index_writes;
   CCountingStore(void) {index_reads=0; index_writes=0;}
   virtual bool Read(const string name,string &text)
     {
      if(StringFind(name,"VELO_T013_ENTRY_INDEX_")==0) index_reads++;
      return(CEnFakeStore::Read(name,text));
     }
   virtual bool Write(const string name,const string text)
     {
      if(StringFind(name,"VELO_T013_ENTRY_INDEX_")==0) index_writes++;
      return(CEnFakeStore::Write(name,text));
     }
  };

// records what the disk holds at the moment of every send
class CSpyTransport : public CEnFakeTransport
  {
public:
   CEnFakeStore *store;
   int sends_seen;
   bool index_had_id;
   bool intent_existed;
   CSpyTransport(void) {store=NULL; sends_seen=0; index_had_id=false; intent_existed=false;}
   virtual void Send(const SEnRequest &req,SEnSendResult &res)
     {
      if(store!=NULL)
        {
         index_had_id=Has(store.Get(LC_FileName(account.login)),SIG);
         intent_existed=store.Exists(EN_FileName(account.login,SIG));
        }
      sends_seen++;
      CEnFakeTransport::Send(req,res);
     }
  };

// a restart: the same disk, no lock held
void CloneDisk(CEnFakeStore &from,CEnFakeStore &to)
  {
   to.n_files=from.n_files;
   for(int i=0;i<from.n_files;i++)
     {
      to.names[i]=from.names[i];
      to.texts[i]=from.texts[i];
     }
  }

class CWorld
  {
public:
   CSpyTransport t;
   CEnFakeStore s;
   SEnConfig cfg;
   STpPlan plan;
   SEnPermit pm;
   SEnRuntime rt;
   SEnResult r;
   CLcGuard g;
   double tp_val;
   void MakePlan(STpPlan &p,const int direction)
     {
      TP_PlanReset(p,SIG,"SET-1",direction);
      p.e_out=(direction==1 ? 1990.0 : 2010.0);
      p.s_out=(direction==1 ? 1985.0 : 2015.0);
      p.tp=tp_val;
      p.volume_out=0.1;
     }
   void InitTp(const int direction,const double tp)
     {
      tp_val=tp;
      Init(direction);
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
      t.store=GetPointer(s);
      MakePlan(plan,direction);
      STpPermit tpm;
      tpm.allow=true;
      tpm.primary_reason="";
      tpm.reason_count=0;
      tpm.registered=false;
      EN_PermitFrom(plan,tpm,t.now,pm);
     }
   void Own(void)
     {
      LC_StateInit(g.st,t.account.login);
      LC_Acquire(GetPointer(s),t.account.login,g.st);
      g.Bind(GetPointer(s));
     }
   CWorld(void) {tp_val=2000.0; Init(1);}
   // the sequence the gate defines: Reserve (index saved + read back) -> executor -> Settled; false = the reservation failed and nothing was placed
   bool Seq(void)
     {
      string why;
      if(!g.Reserve(SIG,why)) return(false);
      EN_Place(cfg,GetPointer(t),GetPointer(s),rt,plan,pm,r);
      g.Settled(SIG,r);
      return(true);
     }
   bool Placed(const int direction)
     {
      Init(direction);
      Own();
      return(Seq() && r.outcome==EN_R_PLACED);
     }
   bool HasRecord(void) {return(s.Exists(EN_FileName(t.account.login,SIG)));}
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
   Check(LC_FileName(5001234)=="VELO_T013_ENTRY_INDEX_5001234.state" && LC_LockKey(5001234)=="VELO_T013_LOCK_INDEX_5001234","the index file name and the lock key");
  }

void Scenario_register_and_save_failure(void)
  {
   CWorld w;
   string notes="";
   w.Own();
   w.s.fail_write_at=1;
   Check(!LC_Register(GetPointer(w.s),w.g.st,SIG,notes) && Has(w.g.st.halted,"LIFECYCLE_STATE_NOT_SAVED"),"a failed save halts");
   CWorld x;
   x.Own();
   x.s.readback_differs_at=1;
   Check(!LC_Register(GetPointer(x.s),x.g.st,SIG,notes) && x.g.st.halted!="","a read-back that differs halts");
   CWorld y;
   y.Own();
   Check(!LC_Register(GetPointer(y.s),y.g.st,"bad\nid",notes) && y.g.st.halted=="LIFECYCLE_BAD_SIGNAL_ID","a signal id with a newline halts");
   CWorld z;
   z.Own();
   bool all=true;
   for(int i=0;i<LC_MAX;i++) all=all && LC_Register(GetPointer(z.s),z.g.st,"ID"+IntegerToString(i),notes);
   Check(all && !LC_Register(GetPointer(z.s),z.g.st,"ONE-TOO-MANY",notes) && z.g.st.halted=="LIFECYCLE_INDEX_FULL","a full index halts");
   CWorld u;
   LC_StateInit(u.g.st,u.t.account.login);
   Check(!LC_Register(GetPointer(u.s),u.g.st,SIG,notes) && u.s.writes==0,"without the lock nothing is written");
  }

void Scenario_startup_clean(void)
  {
   CWorld w;
   string notes;
   SLcState st;
   LC_Startup(w.cfg,GetPointer(w.t),GetPointer(w.s),GetPointer(w.s),false,st,notes);
   Check(st.halted=="" && st.n==0 && w.s.writes==0 && st.lock_owned,"nothing indexed: nothing is written, the lock is owned");
   for(int d=0;d<2;d++)
     {
      CWorld v;
      bool placed=v.Placed(d==0 ? 1 : -1);
      v.t.orders[0].state=EN_OS_CANCELED;              // the order ended while the EA was away
      CEnFakeStore s2;
      CloneDisk(v.s,s2);
      SLcState s3;
      LC_Startup(v.cfg,GetPointer(v.t),GetPointer(s2),GetPointer(s2),false,s3,notes);
      string why;
      SLcState stored;
      bool ok=LC_Decode(s2.Get(LC_FileName(v.t.account.login)),v.t.account.login,stored,why);
      Check(placed && s3.halted=="" && s3.n==0 && ok && stored.n==0 && v.t.sends==1,StringFormat("dir %d: an ended order closes its index entry, no halt, no send",d));
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
      CEnFakeStore s2;
      CloneDisk(w.s,s2);
      SLcState st2;
      string notes;
      LC_Startup(w.cfg,GetPointer(fresh),GetPointer(s2),GetPointer(s2),false,st2,notes);
      Check(placed && Has(st2.halted,"UNRESOLVED_ENTRY_RECORD") && fresh.sends==0 && fresh.cancels==0,StringFormat("dir %d: an unprovable record halts, nothing is sent or cancelled",dir));
      CEnFakeTransport fresh2;
      fresh2.quote.time=fresh2.now;
      CEnFakeStore s3;
      CloneDisk(s2,s3);
      SLcState st3;
      LC_Startup(w.cfg,GetPointer(fresh2),GetPointer(s3),GetPointer(s3),false,st3,notes);
      Check(Has(st3.halted,"UNRESOLVED_ENTRY_RECORD") && st3.n==1,StringFormat("dir %d: the halt survives another restart",dir));
      CEnFakeTransport fresh3;
      fresh3.quote.time=fresh3.now;
      CEnFakeStore s4;
      CloneDisk(s3,s4);
      SLcState st4;
      LC_Startup(w.cfg,GetPointer(fresh3),GetPointer(s4),GetPointer(s4),true,st4,notes);
      Check(st4.halted=="" && st4.n==0 && st4.login==w.t.account.login,StringFormat("dir %d: an explicit acknowledgement clears the halt and drops the unresolved id",dir));
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
      EN_Place(w.cfg,GetPointer(fresh4),GetPointer(s4),rt2,w.plan,pm2,again);
      Check(again.outcome==EN_R_DUPLICATE && fresh4.sends==0,StringFormat("dir %d: the signal stays consumed",dir));
     }
  }

void Scenario_startup_keeps_open_pending(void)
  {
   CWorld w;
   bool placed=w.Placed(1);
   CEnFakeStore s2;
   CloneDisk(w.s,s2);
   SLcState st2;
   string notes;
   LC_Startup(w.cfg,GetPointer(w.t),GetPointer(s2),GetPointer(s2),false,st2,notes);
   Check(placed && st2.halted=="" && st2.n==1 && st2.ids[0]==SIG && w.t.sends==1 && w.t.cancels==0,"the same book: the order is provably still active, kept in the index");
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
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,0,0,notes);
      bool reported=(w.g.st.n==1 && Has(notes,"FILLED_UNMANAGED"));
      string notes2;
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,0,0,notes2);
      SLcState stored;
      Check(placed && reported && notes2=="" && w.g.st.n==0 && w.Stored(stored) && stored.n==0 && w.g.st.halted=="" && w.t.sends==1 && w.t.cancels==0 && w.RecState()==EN_ST_FILLED,
            StringFormat("dir %d: a fill is reported first and forgotten on the next tick; no registration, no cancel, no second send",d));
     }
  }

void Scenario_cancel_gated_by_enabled_events(void)
  {
   for(int d=0;d<2;d++)
     {
      CWorld w;
      bool placed=w.Placed(d==0 ? 1 : -1);
      string notes;
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,TP_EV_SESSION_END,0,notes);
      Check(placed && w.t.cancels==0 && w.g.st.n==1 && Has(notes,"CANCEL_DUE_NOT_ENABLED"),StringFormat("dir %d: a due event that the owner did not enable cancels nothing",d));
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,TP_EV_SESSION_END,TP_EV_NEWS_BLOCK,notes);
      Check(w.t.cancels==0,StringFormat("dir %d: another enabled event does not enable this one",d));
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,TP_EV_SESSION_END|TP_EV_NEWS_BLOCK,TP_EV_NEWS_BLOCK,notes);
      Check(w.t.cancels==1 && w.g.st.n==0 && w.g.st.halted=="" && w.RecState()==EN_ST_CANCELLED && Has(notes,"CANCELLED"),StringFormat("dir %d: an enabled due event cancels the proven pending order once",d));
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,EV_ALL_ENABLED,EV_ALL_ENABLED,notes);
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
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,TP_EV_DAILY_LIMIT,TP_EV_DAILY_LIMIT,notes);
      bool halted=Has(w.g.st.halted,"CANCEL_NOT_CONFIRMED");
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,TP_EV_DAILY_LIMIT,TP_EV_DAILY_LIMIT,notes);
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
   CEnFakeStore s2;
   CloneDisk(w.s,s2);
   s2.Put(name,damaged);
   CEnFakeTransport fresh;
   fresh.quote.time=fresh.now;
   SLcState st2;
   string notes;
   LC_Startup(w.cfg,GetPointer(fresh),GetPointer(s2),GetPointer(s2),true,st2,notes);
   Check(placed && Has(st2.halted,"LIFECYCLE_STATE_DAMAGED") && s2.Get(name)==damaged && fresh.sends==0 && fresh.cancels==0,"a damaged file halts and is never repaired or overwritten, even with an acknowledgement");
   CEnFakeStore s3;
   CloneDisk(s2,s3);
   s3.unreadable=name;
   SLcState st3;
   LC_Startup(w.cfg,GetPointer(fresh),GetPointer(s3),GetPointer(s3),false,st3,notes);
   Check(Has(st3.halted,"LIFECYCLE_STATE_UNREADABLE"),"an unreadable file halts");
  }

// ----------------------------------------------------------------------------------------------------- review findings: index before send, exclusive ownership

void Scenario_index_saved_before_send(void)
  {
   for(int d=0;d<2;d++)
     {
      CWorld w;
      w.Init(d==0 ? 1 : -1);
      w.Own();
      bool ok=w.Seq();
      SLcState stored;
      Check(ok && w.r.outcome==EN_R_PLACED && w.t.sends_seen==1 && w.t.index_had_id && w.t.intent_existed && w.Stored(stored) && stored.n==1 && stored.ids[0]==SIG && w.g.st.halted=="",
            StringFormat("dir %d: at the send the index holds the signal (saved, read back) and the intent exists",d));
     }
   CWorld r;
   r.Init(1);
   r.Own();
   r.t.quote.time=r.t.now-1000;                              // the executor's own market check refuses: no intent
   bool ok=r.Seq();
   SLcState stored;
   Check(ok && r.r.outcome==EN_R_REFUSED && r.t.sends==0 && !r.HasRecord() && r.Stored(stored) && stored.n==0 && r.g.st.halted=="","a refusal before the intent releases the reservation: no record, empty index, no halt");
  }

void Scenario_no_send_when_index_unusable(void)
  {
   for(int d=0;d<2;d++)
     {
      for(int k=0;k<5;k++)
        {
         CWorld w;
         w.Init(d==0 ? 1 : -1);
         w.Own();
         string notes;
         if(k==0) w.s.fail_write_at=1;
         if(k==1) w.s.readback_differs_at=1;
         if(k==2)
           {
            for(int i=0;i<LC_MAX;i++) LC_Register(GetPointer(w.s),w.g.st,"OTHER-"+IntegerToString(i),notes);
            w.s.writes=0;
           }
         if(k==3) w.g.st.halted="LIFECYCLE_STATE_DAMAGED: CRC_MISMATCH";
         if(k==4) w.g.st.lock_owned=false;
         int locks0=w.s.lock_calls;
         bool ok=w.Seq();
         Check(!ok && w.t.sends==0 && !w.HasRecord() && w.s.lock_calls==locks0,StringFormat("dir %d case %d: reservation fails, zero sends, no intent, no per-signal lock",d,k));
        }
     }
  }

void Scenario_crash_windows_restart_halts(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      // (a) the index is saved, the process dies before the intent
      CWorld a;
      a.Init(dir);
      a.Own();
      string why;
      bool reserved=a.g.Reserve(SIG,why);
      CEnFakeTransport tr;
      tr.quote.time=tr.now;
      CEnFakeStore s1;
      CloneDisk(a.s,s1);
      SLcState st1;
      string notes;
      LC_Startup(a.cfg,GetPointer(tr),GetPointer(s1),GetPointer(s1),false,st1,notes);
      Check(reserved && Has(st1.halted,"UNRESOLVED_ENTRY_RECORD") && tr.sends==0 && tr.cancels==0 && st1.n==1,StringFormat("dir %d (a): a reserved signal without a record halts the restart",dir));
      // (b) the intent is saved, the pre-check refuses and its state cannot be saved: the record stays INTENT, zero sends
      CWorld b;
      b.Init(dir);
      b.Own();
      b.t.precheck_ok=false;
      b.s.fail_write_at=3;                                  // 1 = index, 2 = intent, 3 = the state after the refusal
      bool seq=b.Seq();
      CEnFakeTransport tr2;
      tr2.quote.time=tr2.now;
      CEnFakeStore s2;
      CloneDisk(b.s,s2);
      SLcState st2;
      LC_Startup(b.cfg,GetPointer(tr2),GetPointer(s2),GetPointer(s2),false,st2,notes);
      Check(seq && b.t.sends==0 && b.RecState()==EN_ST_INTENT && Has(st2.halted,"UNRESOLVED_ENTRY_RECORD") && tr2.sends==0 && st2.n==1,StringFormat("dir %d (b): intent on disk, no send: the restart halts",dir));
      // (c) the send happened, the outcome could not be saved
      CWorld c;
      c.Init(dir);
      c.Own();
      c.s.fail_write_at=3;
      bool seq3=c.Seq();
      SLcState stored;
      bool indexed=c.Stored(stored) && stored.n==1 && stored.ids[0]==SIG;
      CEnFakeTransport tr3;
      tr3.quote.time=tr3.now;
      CEnFakeStore s3;
      CloneDisk(c.s,s3);
      SLcState st3;
      LC_Startup(c.cfg,GetPointer(tr3),GetPointer(s3),GetPointer(s3),false,st3,notes);
      Check(seq3 && c.t.sends==1 && indexed && Has(st3.halted,"UNRESOLVED_ENTRY_RECORD") && tr3.sends==0 && tr3.cancels==0,StringFormat("dir %d (c): sent, index saved before, empty book: the restart halts without a send",dir));
      CEnFakeStore s4;
      CloneDisk(c.s,s4);
      SLcState st4;
      LC_Startup(c.cfg,GetPointer(c.t),GetPointer(s4),GetPointer(s4),false,st4,notes);
      Check(c.t.sends==1 && st4.n==1,StringFormat("dir %d (c): the book still holds the order: the existing recovery links it, a restart never sends",dir));
     }
  }

void Scenario_two_instances_no_lost_update(void)
  {
   CWorld w;
   w.Init(1);
   CCountingStore store;
   long login=w.t.account.login;
   SLcState a;
   LC_StateInit(a,login);
   bool got=LC_Acquire(GetPointer(store),login,a);
   CLcGuard ga;
   ga.Bind(GetPointer(store));
   ga.st=a;
   string why;
   bool ra=ga.Reserve("SIG-A",why);
   int reads=store.index_reads,writes=store.index_writes,files=store.n_files;
   string snapshot=store.Get(LC_FileName(login));
   CEnFakeTransport trb;
   SLcState b;
   string notes;
   LC_Startup(w.cfg,GetPointer(trb),GetPointer(store),GetPointer(store),false,b,notes);
   Check(got && ra && b.halted=="LIFECYCLE_INSTANCE_LOCK_NOT_ACQUIRED" && !b.lock_owned,"the second instance does not get the lock");
   CLcGuard gb;
   gb.Bind(GetPointer(store));
   gb.st=b;
   bool rb=gb.Reserve("SIG-B",why);
   bool regb=LC_Register(GetPointer(store),b,"SIG-B",notes);
   string tick_notes;
   LC_Tick(w.cfg,GetPointer(trb),GetPointer(store),b,EV_ALL_ENABLED,EV_ALL_ENABLED,tick_notes);
   LC_Halt(GetPointer(store),b,"x",notes);
   Check(!rb && !regb && trb.sends==0 && trb.cancels==0 && store.index_reads==reads && store.index_writes==writes && store.n_files==files && store.Get(LC_FileName(login))==snapshot,
         "the refused instance neither reads nor writes the index, sends nothing, cancels nothing");
   bool a2=LC_Register(GetPointer(store),ga.st,"SIG-A2",notes);
   SLcState stored;
   string d1;
   LC_Decode(store.Get(LC_FileName(login)),login,stored,d1);
   Check(a2 && stored.n==2 && stored.ids[0]=="SIG-A" && stored.ids[1]=="SIG-A2","the owner keeps working and its update is on disk");
   LC_Release(GetPointer(store),ga.st);
   CEnFakeTransport trc;
   SLcState c;
   LC_Startup(w.cfg,GetPointer(trc),GetPointer(store),GetPointer(store),false,c,notes);
   bool regc=LC_Register(GetPointer(store),c,"SIG-C",notes);
   SLcState fin;
   LC_Decode(store.Get(LC_FileName(login)),login,fin,d1);
   Check(c.lock_owned && regc && fin.n>=3 && LC_IndexOf(fin,"SIG-A")>=0 && LC_IndexOf(fin,"SIG-A2")>=0 && LC_IndexOf(fin,"SIG-C")>=0,"after the release the next instance loads both ids and adds its own: no update is lost");
  }

void Scenario_refused_instance_and_wrong_release(void)
  {
   CWorld w;
   w.Init(1);
   CEnFakeStore store;
   long login=w.t.account.login;
   SLcState a;
   LC_StateInit(a,login);
   bool got=LC_Acquire(GetPointer(store),login,a);
   string key=LC_LockKey(login);
   SLcState b;
   LC_StateInit(b,login);
   bool refused=!LC_Acquire(GetPointer(store),login,b);
   int unlocks=store.unlock_calls;
   LC_Release(GetPointer(store),b);
   LC_Release(GetPointer(store),b);
   SLcState forged;
   LC_StateInit(forged,login);
   forged.lock_key=key;                                     // a key without ownership
   LC_Release(GetPointer(store),forged);
   Check(got && refused && !b.lock_owned && store.unlock_calls==unlocks && store.n_held==1 && store.held[0]==key,"a refused instance and a forged key release nothing: the owner's lock is untouched");
   string notes;
   Check(LC_Register(GetPointer(store),a,SIG,notes),"the owner still works");
   LC_Release(GetPointer(store),a);
   Check(store.unlock_calls==unlocks+1 && store.n_held==0 && !a.lock_owned,"the owner releases once");
   LC_Release(GetPointer(store),a);
   Check(store.unlock_calls==unlocks+1,"a second release by the same owner is a no-op");
   Check(!LC_Register(GetPointer(store),a,"AFTER-RELEASE",notes),"no index access after the release");
   Check(LC_Acquire(GetPointer(store),login,b),"after the owner released, another instance can take the lock");
  }

void Scenario_release_only_by_owner_on_failure_paths(void)
  {
   CWorld w0;
   bool placed=w0.Placed(1);
   long login=w0.t.account.login;
   string name=LC_FileName(login);
   string damaged=w0.s.Get(name);
   StringReplace(damaged,SIG,"SIG-X");
   CEnFakeStore s1;
   CloneDisk(w0.s,s1);
   s1.Put(name,damaged);
   CEnFakeTransport tr;
   tr.quote.time=tr.now;
   SLcState st;
   string notes;
   LC_Startup(w0.cfg,GetPointer(tr),GetPointer(s1),GetPointer(s1),false,st,notes);
   Check(placed && Has(st.halted,"LIFECYCLE_STATE_DAMAGED") && st.lock_owned && s1.n_held==1 && s1.held[0]==LC_LockKey(login),"a damaged index: the instance keeps running halted and still owns the lock");
   LC_Release(GetPointer(s1),st);
   Check(s1.n_held==0 && !st.lock_owned,"the owner releases it itself");
   CWorld w2;
   w2.t.account.read_ok=false;
   SLcState st2;
   LC_Startup(w2.cfg,GetPointer(w2.t),GetPointer(w2.s),GetPointer(w2.s),false,st2,notes);
   Check(st2.halted=="ACCOUNT_UNREADABLE" && !st2.lock_owned && w2.s.lock_calls==0 && w2.s.unlock_calls==0,"an unreadable account: nothing acquired, nothing released");
   CWorld w3;
   w3.Init(1);
   w3.Own();
   w3.s.fail_write_at=1;
   string why;
   bool res=w3.g.Reserve(SIG,why);
   Check(!res && w3.g.st.lock_owned && w3.s.n_held==1 && w3.s.unlock_calls==0,"a failed reservation keeps the ownership: the owner releases, not the failure path");
   CWorld w4;
   w4.Init(1);
   SLcState other;
   LC_StateInit(other,w4.t.account.login);
   LC_Acquire(GetPointer(w4.s),w4.t.account.login,other);
   SLcState st4;
   LC_Startup(w4.cfg,GetPointer(w4.t),GetPointer(w4.s),GetPointer(w4.s),false,st4,notes);
   Check(!st4.lock_owned && w4.s.unlock_calls==0 && w4.s.n_held==1,"a refused start releases nothing of the other instance");
  }

// Codex finding on 10a2ee1: a VALID index at the start, damaged AFTER it. The existing index is validated before every update and every lifecycle action; nothing writes over the evidence.
void CorruptIndex(CWorld &w,const int how,string &original)
  {
   string name=LC_FileName(w.t.account.login);
   if(how==0)
     {
      string text=w.s.Get(name);
      StringReplace(text,"halt=\n","halt=X\n");
      w.s.Put(name,text);
     }
   else w.s.unreadable=name;
   original=w.s.Get(name);
  }

void Scenario_damage_during_run_never_overwritten(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      for(int how=0;how<2;how++)
        {
         // an entry attempt after the damage: HALT, zero sends, no new intent, original bytes untouched, the lock stays owned
         CWorld w;
         w.Init(dir);
         SLcState seed;
         LC_StateInit(seed,w.t.account.login);
         bool seeded=LC_Save(GetPointer(w.s),seed);
         string notes;
         LC_Startup(w.cfg,GetPointer(w.t),GetPointer(w.s),GetPointer(w.s),false,w.g.st,notes);
         w.g.Bind(GetPointer(w.s));
         bool owned=w.g.st.lock_owned && w.g.st.halted=="";
         string original;
         CorruptIndex(w,how,original);
         int writes=w.s.writes;
         bool seq=w.Seq();
         string name=LC_FileName(w.t.account.login);
         Check(seeded && owned && !seq && w.t.sends==0 && !w.HasRecord() && w.s.Get(name)==original && w.s.writes==writes && Has(w.g.st.halted,"LIFECYCLE_STATE_") &&
               w.g.st.lock_owned && w.s.n_held==1 && w.s.unlock_calls==0,StringFormat("dir %d how %d: an entry attempt after the damage halts, zero sends, no intent, bytes untouched, lock kept",dir,how));
         // Halt / Persist / Settled never repair it
         string n2;
         LC_Halt(GetPointer(w.s),w.g.st,"x",n2);
         bool reg=LC_Register(GetPointer(w.s),w.g.st,"NEW-1",n2);
         w.g.is_new=true;
         w.g.st.ids[w.g.st.n]="NEW-2";
         w.g.st.n++;
         SEnResult none;
         EN_Res(none,EN_R_NONE,"");
         w.g.Settled("NEW-2",none);
         string n3;
         LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,0,0,n3);
         Check(!reg && w.s.Get(name)==original && w.s.writes==writes && w.g.st.lock_owned && w.s.unlock_calls==0,StringFormat("dir %d how %d: Halt, Persist and Settled never repair an unusable index",dir,how));
         LC_Release(GetPointer(w.s),w.g.st);
         Check(w.s.n_held==0 && !w.g.st.lock_owned,StringFormat("dir %d how %d: the normal release still works",dir,how));
         // a tick with every cancel enabled cancels nothing and reconciles nothing
         CWorld v;
         bool placed=v.Placed(dir);
         string original2;
         CorruptIndex(v,how,original2);
         int writes2=v.s.writes;
         string n4;
         LC_Tick(v.cfg,GetPointer(v.t),GetPointer(v.s),v.g.st,EV_ALL_ENABLED,EV_ALL_ENABLED,n4);
         Check(placed && v.t.cancels==0 && v.t.sends==1 && v.s.Get(name)==original2 && v.s.writes==writes2 && Has(v.g.st.halted,"LIFECYCLE_STATE_") && v.RecState()==EN_ST_PLACED && v.g.st.lock_owned,
               StringFormat("dir %d how %d: a tick with cancel enabled and a damaged index cancels nothing and writes nothing",dir,how));
        }
      // a valid index and the initial creation work as before
      CWorld u;
      u.Init(dir);
      u.Own();
      string n5;
      bool a=LC_Register(GetPointer(u.s),u.g.st,"ID-1",n5);
      bool b=LC_Register(GetPointer(u.s),u.g.st,"ID-2",n5);
      SLcState stored;
      Check(a && b && u.Stored(stored) && stored.n==2,StringFormat("dir %d: the initial creation and the update of a valid index work",dir));
     }
  }

void Scenario_fill_report_and_registration_inputs(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      string side=(d==0 ? "BUY" : "SELL");
      double beyond=(d==0 ? 2005.0 : 1995.0);
      CWorld w;
      w.InitTp(dir,beyond);
      w.Own();
      bool placed=(w.Seq() && w.r.outcome==EN_R_PLACED);
      w.t.orders[0].state=EN_OS_FILLED;
      w.t.orders[0].position_id=4242;
      int files=w.s.n_files;
      string notes;
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,0,0,notes);
      Check(placed && Has(notes,"FILLED_UNMANAGED "+SIG) && Has(notes,"InpEnabled=true") && Has(notes,"InpRPolicy=R_GEOM") && Has(notes,"InpEaMagic=777") && Has(notes,"InpPositionId=4242") &&
            Has(notes,"InpSymbol=XAUUSD") && Has(notes,"InpDirection="+side) && Has(notes,"InpInitialSl="+DoubleToString(w.plan.s_out,8)) && Has(notes,"InpTpPrice="+DoubleToString(beyond,8)) &&
            Has(notes,"InpVolumeInitial="+DoubleToString(0.1,8)) && !Has(notes,"NOT_REGISTRABLE") && w.s.n_files==files && w.t.sends==1 && w.t.cancels==0,
            StringFormat("dir %d: the report carries the exact inputs of the explicit registration script; it writes nothing and registers nothing",dir));
      // at-least-once across a restart between the report and the next tick
      LC_Release(GetPointer(w.s),w.g.st);
      CEnFakeStore s2;
      CloneDisk(w.s,s2);
      SLcState st2;
      string notes2;
      LC_Startup(w.cfg,GetPointer(w.t),GetPointer(s2),GetPointer(s2),false,st2,notes2);
      bool again=(Has(notes2,"FILLED_UNMANAGED") && st2.n==1);
      string notes3;
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(s2),st2,0,0,notes3);
      Check(again && st2.n==0,StringFormat("dir %d: reported again after the restart, forgotten on the next tick",dir));
      // planned geometry cannot prove refusal: an improved fill changes actual 2R
      CWorld e;
      e.InitTp(dir,2000.0);
      e.Own();
      bool placed2=(e.Seq() && e.r.outcome==EN_R_PLACED);
      e.t.orders[0].state=EN_OS_FILLED;
      e.t.orders[0].position_id=4242;
      string n4;
      LC_Tick(e.cfg,GetPointer(e.t),GetPointer(e.s),e.g.st,0,0,n4);
      Check(placed2 && !Has(n4,"NOT_REGISTRABLE") && Has(n4,"LIVE_CHECK_REQUIRED") && Has(n4,"PLANNED_GEOMETRY") && Has(n4,"TP_EQUALS_2R"),StringFormat("dir %d: planned TP == 2R requires live verification, never a definitive refusal",dir));
      double actual_entry=(d==0 ? 1989.0 : 2011.0);
      STgResult actual_geo;
      TG_Compute(d==0 ? TG_BUY : TG_SELL,actual_entry,e.plan.s_out,false,0.0,0.01,2,0.01,0,false,0.0,0.0,actual_geo);
      Check(actual_geo.status==TG_OK && dir*(2000.0-actual_geo.level_2r)>0.0,StringFormat("dir %d: improved fill puts TP beyond actual 2R despite equality in the plan",dir));
      CWorld b;
      b.InitTp(dir,(d==0 ? 1999.0 : 2001.0));
      b.Own();
      bool placed3=(b.Seq() && b.r.outcome==EN_R_PLACED);
      b.t.orders[0].state=EN_OS_FILLED;
      b.t.orders[0].position_id=4242;
      string n5;
      LC_Tick(b.cfg,GetPointer(b.t),GetPointer(b.s),b.g.st,0,0,n5);
      Check(placed3 && Has(n5,"LIVE_CHECK_REQUIRED") && !Has(n5,"NOT_REGISTRABLE") && Has(n5,"TP_BEFORE_2R"),StringFormat("dir %d: a TP before planned 2R is a planned diagnostic only",dir));
      // a record of another magic is blocked by the executor's own identity proof and never reported for registration
      CWorld m;
      m.InitTp(dir,beyond);
      m.Own();
      bool placed4=(m.Seq() && m.r.outcome==EN_R_PLACED);
      m.t.orders[0].state=EN_OS_FILLED;
      m.t.orders[0].position_id=4242;
      m.cfg.ea_magic=778;
      string n6;
      LC_Tick(m.cfg,GetPointer(m.t),GetPointer(m.s),m.g.st,0,0,n6);
      Check(placed4 && Has(n6,"IDENTITY_MISMATCH") && !Has(n6,"T011_REGISTRATION_INPUTS") && Has(m.g.st.halted,"UNRESOLVED_ENTRY_RECORD"),StringFormat("dir %d: another magic is never reported for registration",dir));
     }
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
   Scenario_index_saved_before_send();
   Scenario_no_send_when_index_unusable();
   Scenario_crash_windows_restart_halts();
   Scenario_two_instances_no_lost_update();
   Scenario_refused_instance_and_wrong_release();
   Scenario_release_only_by_owner_on_failure_paths();
   Scenario_damage_during_run_never_overwritten();
   Scenario_fill_report_and_registration_inputs();
   PrintFormat("T019 ENTRY LIFECYCLE TEST finished: %d passed, %d failed",g_pass,g_fail);
  }

