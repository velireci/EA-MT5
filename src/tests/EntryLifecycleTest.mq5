// T019 entry-lifecycle test (FAKE transport and FAKE store only): persistent index + halt, index saved BEFORE every send, exclusive ownership of the index (the existing lock), startup reconcile,
// tick (fill / gated cancel), events from facts. Never a send of its own. Mirrors tests/test_lifecycle.py (the scenario names are pinned equal by a Python test); the gate / orchestrator wiring of the
// pre-send hook is tested in EntryGateTest and EntryOrchestratorTest. NEVER includes the real transport; no order, no trade. The five auto_registration_* scenarios use the T011 state-file code, so they write ONLY terminal files named VELO_T019_SELFTEST_VELO_T011_EXIT_* (deleted at the start and the end) and one temporary lock variable VELO_T011_LOCK_*; everything else is fake.
// NOT YET COMPILED OR RUN (UNVERIFIED): Codex compiles it, the owner runs it in MT5.
#property strict
#property script_show_inputs
#property version "1.06"
#include "../include/EntryLifecycle.mqh"
#include "../include/EntryTransportFake.mqh"
#include "../include/ExitTransportFake.mqh"
#include "../include/EntryManagementHandoff.mqh"
#include "../include/EntryNotify.mqh"
#include "../include/ExitSnapshotAdapter.mqh"
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

// ---- automatic fill -> T011 registration (CMhRegistrar through the existing ETD_Register); the exit transport is the FAKE one with real=true (the gates of a real transport stay in force)
#define REG_POS 7
void RegClean(const long login)
  {
   string n="VELO_T019_SELFTEST_"+ESF_FileName(login,REG_POS);
   FileDelete(n);
   FileDelete(n+ESF_TMP_SUFFIX);
   GlobalVariableDel(EL_Key(login,REG_POS));
  }

class CTestRegistrar : public CMhRegistrar
  {
public:
   bool closed;                                   // scripted: the position list is readable, stable and holds no such position
   CTestRegistrar(void) {closed=false;}
   virtual bool Absent(const ulong position_id) {return(closed);}
  };

void BuildRawFacts(SXaRaw &r,const int dir,const bool filled)
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
   r.pos_type=(dir==1 ? XA_POS_BUY : XA_POS_SELL);
   r.pos_symbol="XAUUSD";
   r.hist_ok=true;
   r.deals_truncated=false;
   r.deal[0].ticket=100;
   r.deal[0].order=400;
   r.deal[0].position_id=7;
   r.deal[0].entry=XA_ENTRY_IN;
   r.deal[0].type=(dir==1 ? XA_DEAL_BUY : XA_DEAL_SELL);
   r.deal[0].volume=0.1;
   r.n_deals=1;
   r.n_orders=1;
   r.ord[0].ticket=501;
   r.ord[0].position_id=7;
   if(!filled)
     {
      r.pos_volume=0.1;
      r.ord[0].where=XA_WHERE_NONE;
      r.ord[0].state=0;
      r.ord[0].vol_initial=0.0;
      r.ord[0].vol_current=0.0;
      return;
     }
   r.pos_volume=0.02;
   r.deal[1].ticket=1001;
   r.deal[1].order=501;
   r.deal[1].position_id=7;
   r.deal[1].entry=XA_ENTRY_OUT;
   r.deal[1].type=(dir==1 ? XA_DEAL_SELL : XA_DEAL_BUY);
   r.deal[1].volume=0.08;
   r.n_deals=2;
   r.ord[0].where=XA_WHERE_HISTORY;
   r.ord[0].state=XA_ORD_FILLED;
   r.ord[0].vol_initial=0.08;
   r.ord[0].vol_current=0.0;
  }

class CRegWorld
  {
public:
   CWorld w;
   CFakeTransport x;                              // the registrar's READ transport (IsReal = true keeps the authorisation and demo gates)
   CFakeTransport m;                              // the MANAGEMENT transport (fixtures for the reconcile, scripted sends)
   CTestRegistrar reg;
   CMhManager mgr;
   CLcObserver *obs;
   int dir;
   double tp;
   long login;
   bool ok;
   int calls;
   void Build(const int direction,const double tp_beyond,const string phrase)
     {
      obs=NULL;
      dir=direction;
      tp=tp_beyond;
      w.InitTp(direction,tp_beyond);
      w.Own();
      login=w.t.account.login;
      RegClean(login);
      ok=(w.Seq() && w.r.outcome==EN_R_PLACED);
      w.t.orders[0].state=EN_OS_FILLED;
      w.t.orders[0].position_id=REG_POS;
      x.real=true;
      x.position.found=true;
      x.position.ticket=9;
      x.position.identifier=REG_POS;
      x.position.symbol="XAUUSD";
      x.position.magic=777;
      x.position.type=(direction==1 ? 0 : 1);
      x.position.volume=0.1;
      x.position.price_open=w.plan.e_out;
      x.position.sl=w.plan.s_out;
      m.real=false;
      m.account=x.account;
      m.symbol=x.symbol;
      m.position=x.position;
      m.response.returned_true=true;
      m.response.have_result=true;
      m.response.retcode=10009;
      m.response.order=501;
      m.response.deal=1001;
      m.response.volume=0.08;
      m.response.price=w.plan.e_out;
      BindMgr(mgr,phrase);
      Bind(phrase);
     }
   void BindMgr(CMhManager &g,const string phrase)
     {
      g.tr=GetPointer(m);
      g.magic=777;
      g.phrase=phrase;
      g.filling=EX_FILL_IOC;
      g.deviation=20;
      g.filter_policy=EX_POL_IGNORE;
      g.filter_state=EX_FS_CLEAR;
     }
   void Bind(const string phrase)
     {
      reg.entry_store=GetPointer(w.s);
      reg.exit_tr=GetPointer(x);
      reg.magic=777;
      reg.phrase=phrase;
      reg.rpol=EX_RPOL_R_GEOM;
      reg.provenance=MH_PROV_BROKER;
      reg.selftest=true;
     }
   string Tick(void)
     {
      string notes;
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,0,0,notes,GetPointer(reg),obs);
      return(notes);
     }
   string File(void)
     {
      string text;
      return(ESF_ReadAll(reg.Name(login,REG_POS),text) ? text : "");
     }
   bool Locked(void) {return(GlobalVariableCheck(EL_Key(login,REG_POS)) && GlobalVariableGet(EL_Key(login,REG_POS))!=0.0);}
  };

void Scenario_auto_registration_confirms_once(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CRegWorld r;
      r.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      string text=r.Tick();
      Check(r.ok && Has(text,"REGISTERED_WITH_T011") && Has(text,"InpRPolicy=R_GEOM") && Has(text,"InpEaMagic=777") && Has(text,"InpPositionId=7") && Has(text,"InpInitialSl="+DoubleToString(r.w.plan.s_out,8)) &&
            Has(text,"InpTpPrice="+DoubleToString(r.tp,8)) && Has(text,"InpDirection="+(d==0 ? "BUY" : "SELL")) && r.w.g.st.n==0 && r.w.g.st.halted=="",StringFormat("dir %d: a filled entry is registered with T011 and forgotten",dir));
      string saved=r.File();
      Check(saved!="" && r.x.sends==0 && !r.Locked(),StringFormat("dir %d: the T011 record exists, nothing was sent, the T011 lock is released",dir));
      string again=r.Tick();
      Check(again=="" && r.File()==saved && r.w.t.sends==1,StringFormat("dir %d: a registered fill is not registered again; the entry transport sent only the one order",dir));
      RegClean(r.login);
     }
  }

void Scenario_auto_registration_idempotent_after_crash(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CRegWorld r;
      r.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      string detail;
      string n0;
      LC_Tick(r.w.cfg,GetPointer(r.w.t),GetPointer(r.w.s),r.w.g.st,0,0,n0,NULL);           // the sweep moves the record to FILLED before the sink is asked (no sink: reported only)
      int first=r.reg.OnFilled(r.login,SIG,detail);
      string saved=r.File();
      LC_Release(GetPointer(r.w.s),r.w.g.st);
      CEnFakeStore s2;
      CloneDisk(r.w.s,s2);
      CMhRegistrar reg2;
      reg2.entry_store=GetPointer(s2);
      reg2.exit_tr=GetPointer(r.x);
      reg2.magic=777;
      reg2.phrase=EX_AUTH_PHRASE;
      reg2.rpol=EX_RPOL_R_GEOM;
      reg2.provenance=MH_PROV_BROKER;
      reg2.selftest=true;
      SLcState st2;
      string notes;
      LC_Startup(r.w.cfg,GetPointer(r.w.t),GetPointer(s2),GetPointer(s2),false,st2,notes,GetPointer(reg2));
      Check(first==LC_SINK_CONFIRMED && saved!="" && Has(notes,"ALREADY_REGISTERED") && st2.n==0 && st2.halted=="" && r.File()==saved && r.x.sends==0,
            StringFormat("dir %d: T011 saved, the process died before the index update: confirmed by comparison after the restart, nothing rewritten",dir));
      // a different existing record is a conflict and is never overwritten
      CMhRegistrar reg3;
      reg3.entry_store=GetPointer(s2);
      reg3.exit_tr=GetPointer(r.x);
      reg3.magic=777;
      reg3.phrase=EX_AUTH_PHRASE;
      reg3.rpol=EX_RPOL_R_GEOM;
      reg3.provenance=MH_PROV_BROKER;
      reg3.selftest=true;
      string tampered=saved+"x";                                          // any edit breaks the record check: unusable
      ESF_WriteAll(reg3.Name(r.login,REG_POS),tampered);
      string d3;
      int res3=reg3.OnFilled(r.login,SIG,d3);
      Check(res3==LC_SINK_REFUSED && Has(d3,"T011_RECORD_CONFLICT"),StringFormat("dir %d: a record that differs or is damaged is a conflict, never overwritten",dir));
      RegClean(r.login);
     }
  }

void Scenario_auto_registration_refusals_keep_the_t011_contracts(void)
  {
   string label[9]={"live SL moved","TP equals 2R","TP before 2R","foreign magic","other direction","netting account","not a demo account","no authorisation phrase","volume differs"};
   string frag[9]={"INITIAL_SL_NOT_PROVEN","TP_EQUALS_2R","TP_BEFORE_2R","OWNERSHIP_NOT_PROVEN","OWNERSHIP_NOT_PROVEN","UNSUPPORTED_ACCOUNT_MODE","REAL_REQUIRES_DEMO_ACCOUNT","REAL_NOT_AUTHORISED","POSITION_VOLUME_DIFFERS"};
   for(int k=0;k<9;k++)
      for(int d=0;d<2;d++)
        {
         int dir=(d==0 ? 1 : -1);
         double beyond=(d==0 ? 2005.0 : 1995.0);
         double eq=(d==0 ? 2000.0 : 2000.0);
         double before=(d==0 ? 1999.0 : 2001.0);
         CRegWorld r;
         r.Build(dir,(k==1 ? eq : (k==2 ? before : beyond)),(k==7 ? "" : EX_AUTH_PHRASE));
         if(k==0) r.x.position.sl=r.w.plan.s_out-dir*5.0;
         if(k==3) r.x.position.magic=0;
         if(k==4) r.x.position.type=1-r.x.position.type;
         if(k==5) r.x.account.margin_mode=0;
         if(k==6) r.x.account.demo=false;
         if(k==8) r.x.position.volume=0.04;
         string text=r.Tick();
         Check(r.ok && Has(text,frag[k]) && r.File()=="" && r.x.sends==0 && Has(r.w.g.st.halted,"MANAGEMENT_REGISTRATION_REFUSED") && r.w.g.st.n==1 && !r.Locked(),
               StringFormat("%s dir %d: refused (%s), nothing registered, the fill stays indexed (unmanaged), the lock is released",label[k],dir,frag[k]));
         RegClean(r.login);
        }
   for(int d=0;d<2;d++)
     {
      CRegWorld r;
      r.Build((d==0 ? 1 : -1),(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      string detail;
      int res=r.reg.OnFilled(r.login,SIG,detail);
      Check(res==LC_SINK_REFUSED && detail=="FILL_NOT_PROVEN" && r.File()=="" && r.x.sends==0,"the sink alone never trusts a record that is not a proven fill");
      RegClean(r.login);
     }
  }

void Scenario_auto_registration_transient_and_locks(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      double beyond=(d==0 ? 2005.0 : 1995.0);
      CRegWorld r;
      r.Build(dir,beyond,EX_AUTH_PHRASE);
      r.x.position.found=false;
      bool pending=true;
      for(int i=0;i<MH_MAX_TRIES-1;i++)
        {
         string n=r.Tick();
         if(!Has(n,"FILL_REGISTRATION_PENDING") || r.w.g.st.halted!="" || r.w.g.st.n!=1 || r.File()!="") pending=false;
        }
      r.x.position.found=true;
      Check(pending && Has(r.Tick(),"REGISTERED_WITH_T011"),StringFormat("dir %d: a transient refusal is retried and registers once the position is visible",dir));
      RegClean(r.login);
      CRegWorld e;
      e.Build(dir,beyond,EX_AUTH_PHRASE);
      e.x.position.found=false;
      string last="";
      for(int i=0;i<MH_MAX_TRIES;i++) last=e.Tick();
      Check(Has(last,"RETRIES_EXHAUSTED") && Has(e.w.g.st.halted,"MANAGEMENT_REGISTRATION_REFUSED"),StringFormat("dir %d: retries are bounded; exhaustion halts",dir));
      RegClean(e.login);
      CRegWorld l;
      l.Build(dir,beyond,EX_AUTH_PHRASE);
      string key=EL_Key(l.login,REG_POS);
      GlobalVariableTemp(key);
      GlobalVariableSet(key,1.0);
      string held=l.Tick();
      bool pend=(Has(held,"FILL_REGISTRATION_PENDING") && l.File()=="" && l.w.g.st.halted=="");
      GlobalVariableSet(key,0.0);
      Check(pend && Has(l.Tick(),"REGISTERED_WITH_T011") && !l.Locked(),StringFormat("dir %d: a held T011 per-position lock is a retry, and the registrar releases its own lock",dir));
      RegClean(l.login);
     }
  }

void Scenario_auto_registration_acknowledge_and_instances(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CRegWorld r;
      r.Build(dir,2000.0,EX_AUTH_PHRASE);                                  // TP == 2R: T011 refuses
      r.Tick();
      bool halted=Has(r.w.g.st.halted,"MANAGEMENT_REGISTRATION_REFUSED");
      r.Tick();
      Check(halted && r.w.g.st.n_unmanaged==1,StringFormat("dir %d: a refused fill halts and is not offered to the sink again in this process",dir));
      LC_Release(GetPointer(r.w.s),r.w.g.st);
      CEnFakeStore s2;
      CloneDisk(r.w.s,s2);
      SLcState st2;
      string n2;
      LC_Startup(r.w.cfg,GetPointer(r.w.t),GetPointer(s2),GetPointer(s2),false,st2,n2,GetPointer(r.reg));
      bool survives=Has(st2.halted,"MANAGEMENT_REGISTRATION_REFUSED");
      LC_Release(GetPointer(s2),st2);
      SLcState st3;
      string n3;
      LC_Startup(r.w.cfg,GetPointer(r.w.t),GetPointer(s2),GetPointer(s2),true,st3,n3,GetPointer(r.reg));
      Check(survives && st3.halted=="" && st3.n==0 && r.File()=="" && s2.Exists(EN_FileName(r.login,SIG)),StringFormat("dir %d: the halt survives a restart; the acknowledgement accepts the unmanaged position, registers nothing, keeps the entry record",dir));
      LC_Release(GetPointer(s2),st3);
      // an instance without the index lock never reaches the registrar
      CRegWorld f;
      f.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      SLcState forged;
      LC_StateInit(forged,f.login);
      forged.ids[0]=SIG;
      forged.n=1;
      string nf;
      LC_Tick(f.w.cfg,GetPointer(f.w.t),GetPointer(f.w.s),forged,0,0,nf,GetPointer(f.reg));
      Check(nf=="" && f.File()=="" && f.x.sends==0,StringFormat("dir %d: without the index lock the registrar is never reached",dir));
      RegClean(f.login);
      RegClean(r.login);
     }
  }

// a fresh registrar over the SAME T011 files, asked directly about the already registered fill
int RegAgain(CRegWorld &r,const long magic,const string phrase,string &detail)
  {
   CTestRegistrar g;
   g.closed=false; // unreadable fixture is not proof of closure; never scan real positions here
   g.entry_store=GetPointer(r.w.s);
   g.exit_tr=GetPointer(r.x);
   g.magic=magic;
   g.phrase=phrase;
   g.rpol=EX_RPOL_R_GEOM;
   g.provenance=MH_PROV_BROKER;
   g.selftest=true;
   return(g.OnFilled(r.login,SIG,detail));
  }

void Scenario_auto_registration_existing_record_needs_the_full_base(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CRegWorld r;
      r.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      bool reg=Has(r.Tick(),"REGISTERED_WITH_T011");
      string saved=r.File();
      string detail;
      Check(reg && RegAgain(r,777,EX_AUTH_PHRASE,detail)==LC_SINK_CONFIRMED,StringFormat("dir %d: the unchanged world is confirmed by comparison",dir));
      string label[8]={"stored E differs from the live open price","magic of the configuration differs","configuration and live position of a magic that is not the entry record magic","live position of another magic",
                       "live position of another direction","wrong authorisation phrase","not a demo account","netting account"};
      string frag[8]={"T011_RECORD_CONFLICT","OWNERSHIP_NOT_PROVEN","OWNERSHIP_NOT_PROVEN","OWNERSHIP_NOT_PROVEN","OWNERSHIP_NOT_PROVEN","REAL_NOT_AUTHORISED","REAL_REQUIRES_DEMO_ACCOUNT","UNSUPPORTED_ACCOUNT_MODE"};
      for(int k=0;k<9;k++)
        {
         double open0=r.x.position.price_open;
         long magic0=r.x.position.magic;
         int type0=r.x.position.type;
         bool demo0=r.x.account.demo;
         int mode0=r.x.account.margin_mode;
         double step0=r.x.symbol.vol_step;
         long cfg_magic=777;
         string phrase=EX_AUTH_PHRASE;
         string lab="symbol volume step differs from the stored plan";
         string fr="T011_RECORD_CONFLICT";
         if(k<8) {lab=label[k]; fr=frag[k];}
         if(k==0) r.x.position.price_open=(d==0 ? 2001.0 : 1999.0);
         if(k==1) cfg_magic=999;
         if(k==2) {cfg_magic=999; r.x.position.magic=999;}
         if(k==3) r.x.position.magic=0;
         if(k==4) r.x.position.type=1-r.x.position.type;
         if(k==5) phrase="NOPE";
         if(k==6) r.x.account.demo=false;
         if(k==7) r.x.account.margin_mode=0;
         if(k==8) r.x.symbol.vol_step=0.1;
         string dt;
         int res=RegAgain(r,cfg_magic,phrase,dt);
         r.x.position.price_open=open0;
         r.x.position.magic=magic0;
         r.x.position.type=type0;
         r.x.account.demo=demo0;
         r.x.account.margin_mode=mode0;
         r.x.symbol.vol_step=step0;
         Check(res==LC_SINK_REFUSED && Has(dt,fr) && r.File()==saved,StringFormat("dir %d: %s: refused (%s), the record is never rewritten",dir,lab,fr));
        }
      Check(r.x.sends==0,StringFormat("dir %d: nothing was sent",dir));
      RegClean(r.login);
     }
  }

void Scenario_auto_registration_idempotent_after_management_started(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CRegWorld r;
      r.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      bool reg=Has(r.Tick(),"REGISTERED_WITH_T011");
      string saved=r.File();
      r.x.position.sl=r.w.plan.e_out;                              // management moved the stop to the entry
      r.x.position.volume=0.02;                                    // and closed the 80% part
      string detail;
      int res=RegAgain(r,777,EX_AUTH_PHRASE,detail);
      Check(reg && res==LC_SINK_CONFIRMED && Has(detail,"ALREADY_REGISTERED") && r.File()==saved,StringFormat("dir %d: a moved SL and a reduced volume do not break the idempotent confirmation; nothing is rewritten",dir));
      r.x.position.found=false;
      res=RegAgain(r,777,EX_AUTH_PHRASE,detail);
      Check(res==LC_SINK_PENDING && Has(detail,"POSITION_NOT_FOUND") && r.File()==saved,StringFormat("dir %d: an unreadable position cannot prove the stored base: pending, not confirmed",dir));
      RegClean(r.login);
     }
  }

void Scenario_auto_registration_synthetic_fill_is_rejected(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      for(int k=0;k<2;k++)
        {
         CRegWorld r;                                                // a REAL position with the same identifier, magic, symbol, direction, volume and SL exists
         r.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
         r.reg.provenance=(k==0 ? MH_PROV_SYNTHETIC : MH_PROV_UNSET);
         string text=r.Tick();
         Check(r.ok && Has(text,"PROVENANCE_NOT_BROKER") && r.File()=="" && r.x.sends==0 && Has(r.w.g.st.halted,"MANAGEMENT_REGISTRATION_REFUSED") && r.w.g.st.n==1 && !r.Locked(),
               StringFormat("dir %d %s: the identifier collision registers nothing (no T011 file, no send, halted, the fill stays indexed)",dir,(k==0 ? "synthetic" : "unset")));
         RegClean(r.login);
        }
      CRegWorld b;
      b.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      Check(Has(b.Tick(),"REGISTERED_WITH_T011"),StringFormat("dir %d: the same world with BROKER provenance registers",dir));
      RegClean(b.login);
     }
  }

// ---- management inside the orchestrator (the registrar hands a confirmed registration to CMhManager = the EXISTING T011 driver under the per-position lock)
class CProc
  {
public:
   CEnFakeStore s;                // this process's view of the entry disk
   CTestRegistrar reg;
   CMhManager mgr;
   SLcState st;
   string notes;
   // a (re)start: the same disks (entry store clone, T011 files, broker facts), no lock held, a new registrar and manager
   void Boot(CRegWorld &r,CEnFakeStore &disk,const SXaRaw &raw)
     {
      CloneDisk(disk,s);
      reg.entry_store=GetPointer(s);
      reg.exit_tr=GetPointer(r.x);
      reg.magic=777;
      reg.phrase=EX_AUTH_PHRASE;
      reg.rpol=EX_RPOL_R_GEOM;
      reg.provenance=MH_PROV_BROKER;
      reg.selftest=true;
      reg.manager=GetPointer(mgr);
      r.BindMgr(mgr,EX_AUTH_PHRASE);
      mgr.raw_a=raw;
      mgr.raw_b=raw;
      LC_Startup(r.w.cfg,GetPointer(r.w.t),GetPointer(s),GetPointer(s),false,st,notes,GetPointer(reg));
     }
   string Tick(CRegWorld &r)
     {
      string n;
      LC_Tick(r.w.cfg,GetPointer(r.w.t),GetPointer(s),st,0,0,n,GetPointer(reg));
      return(n);
     }
   void Stop(void) {LC_Release(GetPointer(s),st);}
  };

void LevelQuote(const int dir,double &bid,double &ask)
  {
   bid=(dir==1 ? 2000.0 : 1999.7);
   ask=(dir==1 ? 2000.3 : 2000.0);
  }

void Scenario_managed_fill_registration_management_to_done(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      string tag=StringFormat("dir %d",dir);
      CRegWorld r;
      r.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      r.reg.manager=GetPointer(r.mgr);
      SXaRaw full,nyet;
      BuildRawFacts(full,dir,true);
      BuildRawFacts(nyet,dir,false);
      r.mgr.raw_a=nyet;
      r.mgr.raw_b=nyet;
      string text=r.Tick();
      Check(r.ok && Has(text,"REGISTERED_WITH_T011") && r.mgr.n==1 && r.mgr.slots[0].st.armed && r.w.g.st.n==1 && r.w.g.st.halted=="",tag+": registered, armed, still indexed (the restart memory)");
      Check(r.Tick()=="",tag+": an unchanged active fill is not reported again");
      double bid,ask;
      LevelQuote(dir,bid,ask);
      int below=r.mgr.OnQuote(bid-(dir==1 ? 5.0 : -5.0),ask-(dir==1 ? 5.0 : -5.0));
      Check(below==0 && r.m.sends==0,tag+": below the level nothing is sent");
      int sent=r.mgr.OnQuote(bid,ask);
      int more=r.mgr.OnQuote(bid,ask)+r.mgr.OnQuote(bid,ask)+r.mgr.OnQuote(bid,ask);
      Check(sent==1 && more==0 && r.m.sends==1,tag+": exactly one closing request, the slot is disarmed after the send");
      r.Tick();
      Check(r.w.g.st.n==1,tag+": still managed while the request is reconciled");
      r.mgr.raw_a=full;
      r.mgr.raw_b=full;
      r.m.position.volume=0.02;
      int runs=r.mgr.OnTimer();
      string done=r.Tick();
      Check(runs==1 && r.mgr.slots[0].done && Has(done,"MANAGEMENT_DONE") && r.w.g.st.n==0 && r.w.g.st.halted=="" && r.m.sends==1 && !r.Locked(),tag+": released only after DONE; exactly one send; the lock is released");
      RegClean(r.login);
     }
  }

void Scenario_managed_restart_in_every_critical_window(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      string tag=StringFormat("dir %d",dir);
      CRegWorld r;
      r.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      SXaRaw full,nyet;
      BuildRawFacts(full,dir,true);
      BuildRawFacts(nyet,dir,false);
      LC_Release(GetPointer(r.w.s),r.w.g.st);
      // (a) after the fill, before any registration
      CProc a;
      a.Boot(r,r.w.s,nyet);
      Check(Has(a.notes,"REGISTERED_WITH_T011") && a.st.n==1 && a.mgr.n==1 && a.mgr.slots[0].st.armed && r.m.sends==0,tag+" (a): registered and armed by the startup sweep, zero sends");
      a.Stop();
      // (b) after the registration: the record exists, the index entry is still there
      CProc b;
      b.Boot(r,a.s,nyet);
      Check(b.st.n==1 && b.mgr.slots[0].st.armed && r.m.sends==0 && b.st.halted=="",tag+" (b): confirmed by comparison, armed again, nothing rewritten");
      string saved=r.File();
      // (c) after the closing request was sent, before the reconcile
      double bid,ask;
      LevelQuote(dir,bid,ask);
      int sent=b.mgr.OnQuote(bid,ask);
      r.m.position.volume=0.02;
      b.Stop();
      CProc c;
      c.Boot(r,b.s,nyet);
      Check(sent==1 && c.st.n==1 && !c.mgr.slots[0].st.armed && c.mgr.slots[0].st.reconcile_due && r.m.sends==1 && c.st.halted=="",tag+" (c): recovery first, not armed, no new send");
      Check(c.mgr.OnQuote(bid,ask)==0 && r.m.sends==1,tag+" (c): no second send after the restart");
      // (d) DONE on the broker, the index entry still exists
      c.mgr.raw_a=full;
      c.mgr.raw_b=full;
      Check(c.mgr.OnTimer()==1 && c.mgr.slots[0].done,tag+" (d): the timer reconciles to DONE");
      c.Stop();
      CProc e;
      e.Boot(r,c.s,full);
      Check(e.st.n==0 && r.m.sends==1 && e.st.halted=="" && r.File()!=saved,tag+" (d): released from the persisted DONE after the restart, no new send");
      e.Stop();
      RegClean(r.login);
     }
  }

void Scenario_managed_closed_position_released_without_management(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      string tag=StringFormat("dir %d",dir);
      CRegWorld r;
      r.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      r.reg.manager=GetPointer(r.mgr);
      r.Tick();
      r.x.position.found=false;
      r.reg.closed=false;
      bool pending=Has(r.Tick(),"FILL_REGISTRATION_PENDING");
      r.reg.closed=true;                                       // readable and stable list, no such position: it was closed (SL, TP or by hand)
      string text=r.Tick();
      Check(pending && Has(text,"POSITION_CLOSED") && r.w.g.st.n==0 && r.w.g.st.halted=="" && r.m.sends==0 && r.mgr.n==0,tag+": unreadable is not closed; a proven-closed position is released without management");
      RegClean(r.login);
     }
  }

void Scenario_managed_manual_foreign_and_synthetic_untouched(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      string tag=StringFormat("dir %d",dir);
      CRegWorld r;
      r.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      r.reg.manager=GetPointer(r.mgr);
      r.x.position.identifier=99;                              // a manual position: another identifier, no magic
      r.x.position.ticket=99;
      r.x.position.magic=0;
      double bid,ask;
      LevelQuote(dir,bid,ask);
      bool quiet=(r.mgr.OnQuote(bid,ask)==0 && r.m.sends==0 && r.mgr.n==0);
      string t1=r.Tick();
      Check(quiet && Has(t1,"POSITION_NOT_FOUND") && r.mgr.n==0 && r.File()=="" && r.m.sends==0,tag+": a manual position gets no slot, no T011 file, no request");
      r.x.position.identifier=7;                               // the same identifier but not the robot's magic
      string t2=r.Tick();
      Check(Has(t2,"OWNERSHIP_NOT_PROVEN") && r.mgr.n==0 && r.File()=="" && r.m.sends==0,tag+": the same identifier with a foreign magic is refused");
      RegClean(r.login);
      CRegWorld s;                                             // the FAKE entry transport: a REAL position with the same identifier / magic / symbol / direction / volume / SL exists
      s.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      s.reg.manager=GetPointer(s.mgr);
      s.reg.provenance=MH_PROV_SYNTHETIC;
      string t3=s.Tick();
      Check(Has(t3,"PROVENANCE_NOT_BROKER") && s.mgr.n==0 && s.File()=="" && s.mgr.OnQuote(bid,ask)==0 && s.m.sends==0 && s.x.sends==0,tag+": a synthetic fill is not managed and touches no real position");
      RegClean(s.login);
     }
  }

void Scenario_managed_failures_block_and_lock_at_the_level(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      string tag=StringFormat("dir %d",dir);
      double beyond=(d==0 ? 2005.0 : 1995.0);
      double bid,ask;
      LevelQuote(dir,bid,ask);
      CRegWorld r;                                             // registered, then the position volume is changed by hand before the management is armed again (restart)
      r.Build(dir,beyond,EX_AUTH_PHRASE);
      r.reg.manager=GetPointer(r.mgr);
      SXaRaw nyet;
      BuildRawFacts(nyet,dir,false);
      r.Tick();
      r.x.position.volume=0.03;
      r.m.position.volume=0.03;
      LC_Release(GetPointer(r.w.s),r.w.g.st);
      CProc p;
      p.Boot(r,r.w.s,nyet);
      Check(Has(p.st.halted,"MANAGEMENT_REGISTRATION_REFUSED") && Has(p.st.halted+p.notes,"VOLUME_MISMATCH") && !p.mgr.slots[0].st.armed && r.m.sends==0,tag+": a volume the robot did not set blocks the management");
      p.Stop();
      RegClean(r.login);
      CRegWorld l;                                             // a T011 per-position lock that never becomes available
      l.Build(dir,beyond,EX_AUTH_PHRASE);
      l.reg.manager=GetPointer(l.mgr);
      string key=EL_Key(l.login,REG_POS);
      GlobalVariableTemp(key);
      GlobalVariableSet(key,1.0);
      string last="";
      for(int i=0;i<MH_MAX_TRIES;i++) last=l.Tick();
      GlobalVariableSet(key,0.0);
      Check(Has(last,"RETRIES_EXHAUSTED") && Has(l.w.g.st.halted,"MANAGEMENT_REGISTRATION_REFUSED") && l.m.sends==0,tag+": a lock that never frees halts after the bounded retries");
      RegClean(l.login);
      CRegWorld q;                                             // a lock held elsewhere at the level: zero sends, the slot stays armed
      q.Build(dir,beyond,EX_AUTH_PHRASE);
      q.reg.manager=GetPointer(q.mgr);
      q.Tick();
      GlobalVariableSet(key,1.0);
      int blocked=q.mgr.OnQuote(bid,ask);
      bool armed=q.mgr.slots[0].st.armed;
      GlobalVariableSet(key,0.0);
      int sent=q.mgr.OnQuote(bid,ask);
      Check(blocked==0 && armed && sent==1 && q.m.sends==1,tag+": a lock held elsewhere at the level sends nothing; the request goes out once it is free");
      RegClean(q.login);
     }
  }

void Scenario_managed_slots_released_and_capacity(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      double beyond=(d==0 ? 2005.0 : 1995.0);
      SXaRaw full,nyet;
      BuildRawFacts(full,dir,true);
      BuildRawFacts(nyet,dir,false);
      CMhManager shared;                                       // one process, one manager, more cycles than slots
      bool all_ok=true;
      for(int cycle=0;cycle<MH_MAX_SLOTS+3;cycle++)
        {
         CRegWorld r;
         r.Build(dir,beyond,EX_AUTH_PHRASE);
         r.BindMgr(shared,EX_AUTH_PHRASE);
         r.reg.manager=GetPointer(shared);
         shared.raw_a=nyet;
         shared.raw_b=nyet;
         bool reg=Has(r.Tick(),"REGISTERED_WITH_T011") && shared.n==1;
         double bid,ask;
         LevelQuote(dir,bid,ask);
         bool sent=(shared.OnQuote(bid,ask)==1);
         shared.raw_a=full;
         shared.raw_b=full;
         r.m.position.volume=0.02;
         bool timer=(shared.OnTimer()==1);
         bool done=Has(r.Tick(),"MANAGEMENT_DONE");
         if(!(r.ok && reg && sent && timer && done && shared.n==0 && r.w.g.st.n==0 && r.w.g.st.halted=="" && r.m.sends==1))
           {
            all_ok=false;
            PrintFormat("dir %d cycle %d: reg %d sent %d timer %d done %d slots %d ids %d halted [%s] sends %d",dir,cycle,(int)reg,(int)sent,(int)timer,(int)done,shared.n,r.w.g.st.n,r.w.g.st.halted,r.m.sends);
           }
         RegClean(r.login);
         if(!all_ok) break;
        }
      Check(all_ok,StringFormat("dir %d: %d consecutive cycles in one process; every slot is released with its index entry",dir,MH_MAX_SLOTS+3));
      // the capacity itself: MH_MAX_SLOTS slots in use refuse the next position, one less accepts it
      CRegWorld f;
      f.Build(dir,beyond,EX_AUTH_PHRASE);
      f.reg.manager=GetPointer(f.mgr);
      for(int i=0;i<MH_MAX_SLOTS;i++) f.mgr.slots[i].pid=1000+i;
      f.mgr.n=MH_MAX_SLOTS;
      string tf=f.Tick();
      Check(Has(tf,"MANAGEMENT_SLOTS_FULL") && Has(f.w.g.st.halted,"MANAGEMENT_REGISTRATION_REFUSED") && f.m.sends==0,StringFormat("dir %d: a full manager refuses the next position and halts",dir));
      RegClean(f.login);
      CRegWorld g;
      g.Build(dir,beyond,EX_AUTH_PHRASE);
      g.reg.manager=GetPointer(g.mgr);
      for(int i=0;i<MH_MAX_SLOTS-1;i++) g.mgr.slots[i].pid=1000+i;
      g.mgr.n=MH_MAX_SLOTS-1;
      Check(Has(g.Tick(),"REGISTERED_WITH_T011"),StringFormat("dir %d: one free slot accepts it",dir));
      RegClean(g.login);
      // a restart between DONE and the saved index: the DONE is recovered from the T011 record, no new send
      CRegWorld r2;
      r2.Build(dir,beyond,EX_AUTH_PHRASE);
      LC_Release(GetPointer(r2.w.s),r2.w.g.st);
      CProc p1;
      p1.Boot(r2,r2.w.s,nyet);
      double bid2,ask2;
      LevelQuote(dir,bid2,ask2);
      bool sent2=(p1.mgr.OnQuote(bid2,ask2)==1);
      p1.mgr.raw_a=full;
      p1.mgr.raw_b=full;
      r2.m.position.volume=0.02;
      bool timer2=(p1.mgr.OnTimer()==1);
      string detail;
      int conf=p1.reg.OnFilled(r2.login,SIG,detail);
      bool released=(p1.mgr.n==0 && p1.st.n==1);                // the process dies here: the index was not saved
      p1.Stop();
      CProc p2;
      p2.Boot(r2,p1.s,full);
      Check(sent2 && timer2 && conf==LC_SINK_CONFIRMED && released && p2.st.n==0 && p2.st.halted=="" && p2.mgr.n==0 && r2.m.sends==1,StringFormat("dir %d: restart between DONE and the saved index recovers the DONE without a send",dir));
      p2.Stop();
      RegClean(r2.login);
     }
  }

// ---- per-record direction events (S:29-30): several pending orders of different directions in one store
class CMulti
  {
public:
   CWorld w;
   int k;
   CMulti(void) {k=0;}
   bool Add(const string sid,const int dir)
     {
      w.Init(dir);
      TP_PlanReset(w.plan,sid,"SET-1",dir);
      double shift=-0.5*k*dir;                                  // distinct prices: the executor refuses an identical pending order
      w.plan.e_out=(dir==1 ? 1990.0 : 2010.0)+shift;
      w.plan.s_out=(dir==1 ? 1985.0 : 2015.0)+shift;
      w.plan.tp=2000.0;
      w.plan.volume_out=0.1;
      STpPermit tpm;
      tpm.allow=true;
      tpm.primary_reason="";
      tpm.reason_count=0;
      tpm.registered=false;
      EN_PermitFrom(w.plan,tpm,w.t.now,w.pm);
      if(k==0) w.Own();
      k++;
      string why;
      if(!w.g.Reserve(sid,why)) return(false);
      EN_RuntimeInit(w.rt);
      EN_Place(w.cfg,GetPointer(w.t),GetPointer(w.s),w.rt,w.plan,w.pm,w.r);
      w.g.Settled(sid,w.r);
      return(w.r.outcome==EN_R_PLACED);
     }
   bool Three(void) {return(Add("SIG-A",1) && Add("SIG-B",-1) && Add("SIG-C",1));}
   void Facts(SLcFacts &f,const int ctx,const int sig,const string sid,const bool valid=true,const long age=0)
     {
      LC_FactsInit(f);
      f.valid=valid;
      f.ctx_direction=ctx;
      f.signal_direction=sig;
      f.signal_id=sid;
      f.time=w.t.now-age;
     }
   string Tick(const SLcFacts &f,const int dir_enabled)
     {
      string n;
      LC_TickEx(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,0,0,f,dir_enabled,n);
      return(n);
     }
   bool Open(const string sid) {return(LC_IndexOf(w.g.st,sid)>=0);}
   string StateOf(const string sid)
     {
      SEnRecord rec;
      string why;
      return(EN_Load(GetPointer(w.s),EN_FileName(w.t.account.login,sid),rec,why)==1 ? rec.state : "NO_RECORD");
     }
  };

void Scenario_direction_cancel_only_opposite_records(void)
  {
   for(int c=0;c<2;c++)
     {
      int ctx=(c==0 ? -1 : 1);
      CMulti m;
      bool ok=m.Three();
      SLcFacts f;
      m.Facts(f,ctx,0,"");
      string n=m.Tick(f,TP_EV_DIRECTION_CHANGE);
      bool a=(ctx==-1 ? !m.Open("SIG-A") && !m.Open("SIG-C") && m.Open("SIG-B") : m.Open("SIG-A") && m.Open("SIG-C") && !m.Open("SIG-B"));
      bool st=(ctx==-1 ? m.StateOf("SIG-A")==EN_ST_CANCELLED && m.StateOf("SIG-C")==EN_ST_CANCELLED && m.StateOf("SIG-B")==EN_ST_PLACED : m.StateOf("SIG-B")==EN_ST_CANCELLED && m.StateOf("SIG-A")==EN_ST_PLACED);
      Check(ok && a && st && m.w.t.cancels==(ctx==-1 ? 2 : 1) && m.w.g.st.halted=="" && Has(n,"CANCEL_REQUEST: DIRECTION_CHANGE"),StringFormat("context %d: only the records of the opposite direction are cancelled, the others stay pending",ctx));
     }
  }

void Scenario_opposite_signal_cancel_per_record(void)
  {
   for(int c=0;c<2;c++)
     {
      int sd=(c==0 ? -1 : 1);
      CMulti m;
      bool ok=m.Three();
      SLcFacts f;
      m.Facts(f,0,sd,"SIG-NEW");
      m.Tick(f,TP_EV_OPPOSITE_SIGNAL);
      bool a=(sd==-1 ? !m.Open("SIG-A") && !m.Open("SIG-C") && m.Open("SIG-B") : !m.Open("SIG-B") && m.Open("SIG-A") && m.Open("SIG-C"));
      CMulti x;                                                  // inconsistent data: the signal id of the record itself with the other direction proves nothing
      bool ok2=x.Add("SIG-A",1);
      SLcFacts g;
      x.Facts(g,0,-1,"SIG-A");
      x.Tick(g,TP_EV_OPPOSITE_SIGNAL);
      Check(ok && a && ok2 && x.w.t.cancels==0 && x.Open("SIG-A"),StringFormat("signal %d: only the opposite records are cancelled; inconsistent data cancels nothing",sd));
     }
  }

void Scenario_direction_unknown_data_proves_nothing(void)
  {
   for(int k=0;k<7;k++)
     {
      CMulti m;
      bool ok=m.Three();
      SLcFacts f;
      int dir_enabled=TP_EV_DIRECTION_CHANGE|TP_EV_OPPOSITE_SIGNAL;
      if(k==0) m.Facts(f,0,0,"");                                           // unknown context
      if(k==1) m.Facts(f,-1,0,"",false);                                    // invalid facts
      if(k==2) m.Facts(f,-1,0,"",true,m.w.cfg.quote_max_age+1);             // stale
      if(k==3) m.Facts(f,-1,0,"",true,-5);                                  // from the future
      if(k==4) {m.Facts(f,-1,0,""); dir_enabled=0;}                         // not enabled by the owner
      if(k==5) {m.Facts(f,-1,0,""); dir_enabled=TP_EV_OPPOSITE_SIGNAL;}     // a context is not a signal
      if(k==6) {m.Facts(f,0,-1,"SIG-NEW"); dir_enabled=TP_EV_DIRECTION_CHANGE;}  // a signal is not a context change
      m.Tick(f,dir_enabled);
      Check(ok && m.w.t.cancels==0 && m.w.g.st.n==3 && m.w.g.st.halted=="",StringFormat("case %d: unknown, incomplete, stale or not enabled data cancels nothing",k));
     }
  }

void Scenario_direction_cancel_leaves_positions_and_foreign(void)
  {
   for(int c=0;c<2;c++)
     {
      int ctx=(c==0 ? -1 : 1);
      CMulti m;
      bool ok=m.Add("SIG-A",1) && m.Add("SIG-B",-1);
      m.w.t.orders[0].state=EN_OS_FILLED;                                  // SIG-A became a position
      m.w.t.orders[0].position_id=4242;
      SEnOrder manual,other;
      manual=m.w.t.orders[1];
      other=m.w.t.orders[1];
      manual.ticket=9001;
      manual.magic=0;
      manual.comment="manual";
      other.ticket=9002;
      other.magic=999;
      other.comment="other EA";
      m.w.t.orders[m.w.t.n_orders]=manual;
      m.w.t.n_orders++;
      m.w.t.orders[m.w.t.n_orders]=other;
      m.w.t.n_orders++;
      SLcFacts f;
      m.Facts(f,ctx,0,"");
      m.Tick(f,TP_EV_DIRECTION_CHANGE|TP_EV_OPPOSITE_SIGNAL);
      m.Tick(f,TP_EV_DIRECTION_CHANGE|TP_EV_OPPOSITE_SIGNAL);
      Check(ok && m.w.t.orders[2].state==EN_OS_ACTIVE && m.w.t.orders[3].state==EN_OS_ACTIVE && m.w.t.orders[0].state==EN_OS_FILLED && m.w.t.cancels==(ctx==1 ? 1 : 0),
            StringFormat("context %d: the open position, the manual order and the other magic are never touched; only the opposite pending of ours",ctx));
     }
  }

void Scenario_direction_cancel_uncertain_halts_no_retry(void)
  {
   int modes[3]={EN_CM_LOST,EN_CM_NOT_EFFECTIVE,EN_CM_FAILS};
   for(int k=0;k<3;k++)
     {
      CMulti m;
      bool ok=m.Three();
      m.w.t.cancel_mode=modes[k];
      SLcFacts f;
      m.Facts(f,-1,0,"");
      m.Tick(f,TP_EV_DIRECTION_CHANGE);
      bool halted=Has(m.w.g.st.halted,"CANCEL_NOT_CONFIRMED");
      int first=m.w.t.cancels;
      m.Tick(f,TP_EV_DIRECTION_CHANGE);
      LC_Release(GetPointer(m.w.s),m.w.g.st);
      CEnFakeStore s2;
      CloneDisk(m.w.s,s2);
      SLcState st2;
      string notes;
      LC_Startup(m.w.cfg,GetPointer(m.w.t),GetPointer(s2),GetPointer(s2),false,st2,notes);
      string n2;
      LC_TickEx(m.w.cfg,GetPointer(m.w.t),GetPointer(s2),st2,0,0,f,TP_EV_DIRECTION_CHANGE,n2);
      Check(ok && halted && first>=1 && m.w.t.cancels==first && st2.halted!="",StringFormat("cancel mode %d: an uncertain cancel halts; no second cancellation, not even after a restart",modes[k]));
     }
  }

// ---- push notifications for PROVEN facts of OWNED objects (FAKE sink only: nothing is ever pushed by a test)
class CNtFakeSink : public CNtSink
  {
public:
   string texts[64];
   int n;
   int calls;
   int mode;
   CNtFakeSink(void) {n=0; calls=0; mode=NT_SENT;}
   virtual int Send(const string text)
     {
      calls++;
      if(mode==NT_SENT && n<64) {texts[n]=text; n++;}
      return(mode);
     }
   int Count(const string frag)
     {
      int c=0;
      for(int i=0;i<n;i++)
         if(Has(texts[i],frag)) c++;
      return(c);
     }
  };

void NtBind(CNtNotifier &nf,CNtFakeSink &sink,CEnStore *store,const long magic,const bool baseline=false)
  {
   nf.sink=GetPointer(sink);
   nf.store=store;
   nf.magic=magic;
   nf.symbol="XAUUSD";
   nf.prefix="[FAKE] ";
   nf.baseline=baseline;
  }

void NtTick(CWorld &w,CLcObserver *o)
  {
   string n;
   LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,0,0,n,NULL,o);
  }

void Scenario_notify_pending_placed_then_filled_once(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CWorld w;
      bool placed=w.Placed(dir);
      CNtFakeSink sink;
      CNtNotifier nf;
      NtBind(nf,sink,GetPointer(w.s),777);
      for(int i=0;i<4;i++) NtTick(w,GetPointer(nf));
      bool first=(sink.Count("PENDING PLACED")==1 && sink.n==1 && Has(sink.texts[0],(dir==1 ? "BUY" : "SELL")) && StringFind(sink.texts[0],"[FAKE] ")==0);
      w.t.orders[0].state=EN_OS_FILLED;
      w.t.orders[0].position_id=4242;
      for(int i=0;i<4;i++) NtTick(w,GetPointer(nf));
      Check(placed && first && sink.Count("POSITION OPENED")==1 && sink.n==2 && w.t.sends==1,StringFormat("dir %d: placed and opened are announced once each; polls and reconciles repeat nothing",dir));
     }
  }

void Scenario_notify_unproven_order_send_is_silent(void)
  {
   int modes[3]={EN_SM_UNCERTAIN_NOT_CREATED,EN_SM_PLACED_UNREADABLE,EN_SM_REJECTED};
   for(int k=0;k<3;k++)
     {
      CWorld w;
      w.Init(1);
      w.Own();
      w.t.send_mode=modes[k];
      w.Seq();
      CNtFakeSink sink;
      CNtNotifier nf;
      NtBind(nf,sink,GetPointer(w.s),777);
      NtTick(w,GetPointer(nf));
      NtTick(w,GetPointer(nf));
      Check(sink.n==0,StringFormat("send mode %d: an order the broker facts do not show is never announced",modes[k]));
     }
  }

void Scenario_notify_removed_pending_once(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CWorld w;
      bool placed=w.Placed(dir);
      CNtFakeSink sink;
      CNtNotifier nf;
      NtBind(nf,sink,GetPointer(w.s),777);
      string n;
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,0,0,n,NULL,GetPointer(nf));
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,TP_EV_SESSION_END,TP_EV_SESSION_END,n,NULL,GetPointer(nf));
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(w.s),w.g.st,TP_EV_SESSION_END,TP_EV_SESSION_END,n,NULL,GetPointer(nf));
      Check(placed && sink.Count("PENDING PLACED")==1 && sink.Count("PENDING CANCELLED")==1,StringFormat("dir %d: a cancelled pending is announced once",dir));
     }
  }

void Scenario_notify_partial_modified_closed_are_distinct(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CRegWorld r;
      r.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      CNtFakeSink sink;
      CNtNotifier nf;
      NtBind(nf,sink,GetPointer(r.w.s),777);
      r.obs=GetPointer(nf);
      r.reg.obs=GetPointer(nf);
      r.reg.manager=GetPointer(r.mgr);
      r.Tick();
      bool opened=(sink.Count("POSITION OPENED")==1 && sink.n==1);
      for(int i=0;i<3;i++) r.Tick();
      bool quiet=(sink.n==1);
      r.x.position.sl=r.w.plan.e_out;                          // the stop moved to the entry
      for(int i=0;i<3;i++) r.Tick();
      bool mod=(sink.Count("POSITION MODIFIED")==1 && sink.Count("PARTIAL")==0);
      r.x.position.volume=0.02;                                // the 80% part closed
      for(int i=0;i<3;i++) r.Tick();
      bool part=(sink.Count("POSITION MODIFIED")==1 && sink.Count("PARTIAL")==1 && sink.Count("POSITION CLOSED")==0);
      r.x.position.found=false;
      r.reg.closed=true;                                       // readable, stable, no such position
      for(int i=0;i<3;i++) r.Tick();
      Check(r.ok && opened && quiet && mod && part && sink.Count("POSITION CLOSED")==1 && sink.n==4,StringFormat("dir %d: opening, modification, partial and final close are distinct and announced once",dir));
      RegClean(r.login);
      CRegWorld u;                                             // an unreadable position is not a close
      u.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      CNtFakeSink sink2;
      CNtNotifier nf2;
      NtBind(nf2,sink2,GetPointer(u.w.s),777);
      u.obs=GetPointer(nf2);
      u.reg.obs=GetPointer(nf2);
      u.reg.manager=GetPointer(u.mgr);
      u.Tick();
      u.x.position.found=false;
      u.Tick();
      Check(sink2.Count("POSITION CLOSED")==0,StringFormat("dir %d: an unreadable position is not announced as closed",dir));
      RegClean(u.login);
     }
  }

void Scenario_notify_failure_changes_no_decision(void)
  {
   int modes[2]={NT_FAILED,NT_RETRY_LATER};
   for(int k=0;k<2;k++)
      for(int d=0;d<2;d++)
        {
         int dir=(d==0 ? 1 : -1);
         CWorld w;
         bool placed=w.Placed(dir);
         CNtFakeSink sink;
         sink.mode=modes[k];
         CNtNotifier nf;
         NtBind(nf,sink,GetPointer(w.s),777);
         int sends=w.t.sends,cancels=w.t.cancels;
         for(int i=0;i<6;i++) NtTick(w,GetPointer(nf));
         bool same=(w.t.sends==sends && w.t.cancels==cancels && w.g.st.n==1 && w.g.st.halted=="");
         bool calls=(modes[k]==NT_FAILED ? sink.calls==NT_MAX_TRIES : sink.calls==6);
         bool later=true;
         if(modes[k]==NT_RETRY_LATER)
           {
            sink.mode=NT_SENT;
            NtTick(w,GetPointer(nf));
            later=(sink.Count("PENDING PLACED")==1);
           }
         Check(placed && same && calls && later,StringFormat("mode %d dir %d: a failing or throttled notification changes no decision and sends no order; retries are bounded",modes[k],dir));
        }
  }

void Scenario_notify_manual_foreign_unreadable_silent(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CRegWorld r;
      r.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      CNtFakeSink sink;
      CNtNotifier nf;
      NtBind(nf,sink,GetPointer(r.w.s),778);                   // another magic: the records of this robot are not owned by this notifier
      r.obs=GetPointer(nf);
      r.reg.obs=GetPointer(nf);
      r.Tick();
      bool foreign=(sink.n==0);
      RegClean(r.login);
      CRegWorld m;
      m.Build(dir,(d==0 ? 2005.0 : 1995.0),EX_AUTH_PHRASE);
      CNtFakeSink sink2;
      CNtNotifier nf2;
      NtBind(nf2,sink2,GetPointer(m.w.s),777);
      m.obs=GetPointer(nf2);
      m.reg.obs=GetPointer(nf2);
      m.x.position.identifier=99;                              // a manual position
      m.x.position.ticket=99;
      m.x.position.magic=0;
      SEnOrder manual=m.w.t.orders[0];                         // and a manual pending order
      manual.ticket=9001;
      manual.magic=0;
      manual.state=EN_OS_ACTIVE;
      m.w.t.orders[m.w.t.n_orders]=manual;
      m.w.t.n_orders++;
      m.Tick();
      bool manual_quiet=(sink2.Count("POSITION PARTIAL")+sink2.Count("POSITION MODIFIED")+sink2.Count("POSITION CLOSED")+sink2.Count("PENDING")==0);
      Check(foreign && manual_quiet,StringFormat("dir %d: a foreign magic, a manual position and a manual pending order never notify",dir));
      RegClean(m.login);
     }
  }

void Scenario_notify_restart_repeats_nothing(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CWorld w;
      bool placed=w.Placed(dir);
      CNtFakeSink sink;
      CNtNotifier nf;
      NtBind(nf,sink,GetPointer(w.s),777);
      NtTick(w,GetPointer(nf));
      bool one=(sink.n==1);
      LC_Release(GetPointer(w.s),w.g.st);
      CEnFakeStore s2;
      CloneDisk(w.s,s2);
      CNtNotifier n2;
      NtBind(n2,sink,GetPointer(s2),777,true);                 // the startup sweep only remembers
      SLcState st2;
      string notes;
      LC_Startup(w.cfg,GetPointer(w.t),GetPointer(s2),GetPointer(s2),false,st2,notes,NULL,GetPointer(n2));
      n2.baseline=false;
      string t;
      for(int i=0;i<3;i++) LC_Tick(w.cfg,GetPointer(w.t),GetPointer(s2),st2,0,0,t,NULL,GetPointer(n2));
      bool same=(sink.n==1);
      w.t.orders[0].state=EN_OS_FILLED;
      w.t.orders[0].position_id=4242;
      LC_Tick(w.cfg,GetPointer(w.t),GetPointer(s2),st2,0,0,t,NULL,GetPointer(n2));
      // an event during the downtime is not announced: a fill that already exists at the start is only remembered
      CWorld x;
      bool placed2=x.Placed(dir);
      x.t.orders[0].state=EN_OS_FILLED;
      x.t.orders[0].position_id=4242;
      LC_Release(GetPointer(x.s),x.g.st);
      CNtFakeSink sink3;
      CNtNotifier n3;
      NtBind(n3,sink3,GetPointer(x.s),777,true);
      SLcState st3;
      LC_Startup(x.cfg,GetPointer(x.t),GetPointer(x.s),GetPointer(x.s),false,st3,notes,NULL,GetPointer(n3));
      n3.baseline=false;
      LC_Tick(x.cfg,GetPointer(x.t),GetPointer(x.s),st3,0,0,t,NULL,GetPointer(n3));
      Check(placed && placed2 && one && same && sink.Count("POSITION OPENED")==1 && sink.n==2 && sink3.n==0 && Has(notes,"FILLED_UNMANAGED"),
            StringFormat("dir %d: a restart repeats nothing, a new fact is announced, a fact of the downtime is only logged",dir));
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
   Scenario_auto_registration_confirms_once();
   Scenario_auto_registration_idempotent_after_crash();
   Scenario_auto_registration_refusals_keep_the_t011_contracts();
   Scenario_auto_registration_transient_and_locks();
   Scenario_auto_registration_acknowledge_and_instances();
   Scenario_auto_registration_existing_record_needs_the_full_base();
   Scenario_auto_registration_idempotent_after_management_started();
   Scenario_auto_registration_synthetic_fill_is_rejected();
   Scenario_managed_fill_registration_management_to_done();
   Scenario_managed_restart_in_every_critical_window();
   Scenario_managed_closed_position_released_without_management();
   Scenario_managed_manual_foreign_and_synthetic_untouched();
   Scenario_managed_failures_block_and_lock_at_the_level();
   Scenario_managed_slots_released_and_capacity();
   Scenario_direction_cancel_only_opposite_records();
   Scenario_opposite_signal_cancel_per_record();
   Scenario_direction_unknown_data_proves_nothing();
   Scenario_direction_cancel_leaves_positions_and_foreign();
   Scenario_direction_cancel_uncertain_halts_no_retry();
   Scenario_notify_pending_placed_then_filled_once();
   Scenario_notify_unproven_order_send_is_silent();
   Scenario_notify_removed_pending_once();
   Scenario_notify_partial_modified_closed_are_distinct();
   Scenario_notify_failure_changes_no_decision();
   Scenario_notify_manual_foreign_unreadable_silent();
   Scenario_notify_restart_repeats_nothing();
   PrintFormat("T019 ENTRY LIFECYCLE TEST finished: %d passed, %d failed",g_pass,g_fail);
  }



