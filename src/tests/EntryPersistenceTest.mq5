// T017: real sandbox file I/O, existing entry executor, FAKE transport only.
// Deletes only its exact VELO_T017_SELFTEST_ files. No order or position API.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/EntryExecutor.mqh"
#include "../include/EntryTransportFake.mqh"
#include "../include/EntryStateFile.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }

bool Clean(const string logical)
  {
   string name=EFS_Name(logical,false,true);
   if(StringFind(name,"VELO_T017_SELFTEST_")!=0) return(false);
   bool ok=true;
   if(FileIsExist(name)) ok=FileDelete(name);
   string tmp=name+ESF_TMP_SUFFIX;
   if(FileIsExist(tmp)) ok=FileDelete(tmp) && ok;
   return(ok);
  }

class CFixture
  {
public:
   CEnFakeTransport t;
   SEnConfig cfg;
   STpPlan plan;
   SEnPermit permit;
   SEnRuntime rt;
   SEnResult result;
   void Init(const int direction,const string signal)
     {
      EN_ConfigInit(cfg);
      cfg.enabled=true; cfg.ea_magic=777; cfg.symbol="XAUUSD";
      cfg.filling=EN_FILL_RETURN; cfg.expiry_mode=EN_EXP_GTC;
      cfg.permit_max_age=60; cfg.quote_max_age=30;
      EN_RuntimeInit(rt);
      t.quote.time=t.now;
      TP_PlanReset(plan,signal,"T017-SET",direction);
      plan.e_out=(direction==1 ? 1990.0 : 2010.0);
      plan.s_out=(direction==1 ? 1985.0 : 2015.0);
      plan.tp=2000.0; plan.volume_out=0.1;
      STpPermit p;
      p.allow=true; p.primary_reason=""; p.reason_count=0; p.registered=false;
      EN_PermitFrom(plan,p,t.now,permit);
     }
   string Name(void) {return(EN_FileName(t.account.login,plan.signal_id));}
   string Key(void) {return(EN_LockKey(t.account.login,plan.signal_id));}
   void Place(CEnStore *store) {EN_Place(cfg,GetPointer(t),store,rt,plan,permit,result);}
  };

void Restart(const int direction)
  {
   string signal="T017-RESTART-"+IntegerToString(direction);
   CFixture first;
   first.Init(direction,signal);
   Check(Clean(first.Name()),"restart: prepare own sandbox files");
   {
    CEnFakeFileStore store(true);
    first.Place(GetPointer(store));
    Check(first.result.outcome==EN_R_PLACED && first.t.sends==1,"first runtime places once with a persisted record");
   }
   CFixture fresh;
   fresh.Init(direction,signal);
   {
    CEnFakeFileStore recreated(true);
    fresh.Place(GetPointer(recreated));
    Check(fresh.result.outcome==EN_R_DUPLICATE && fresh.t.sends==0 && fresh.t.n_orders==0,"recreated store, transport and runtime: DUPLICATE, no virtual order reconstructed");
   }
   Check(Clean(first.Name()),"restart: remove only own sandbox files");
  }

void AllStates(void)
  {
   string states[]={EN_ST_INTENT,EN_ST_PRECHECK_REFUSED,EN_ST_REJECTED,EN_ST_PLACED,EN_ST_FILLED,
                    EN_ST_CANCEL_UNCERTAIN,EN_ST_CANCELLED,EN_ST_EXPIRED,EN_ST_RECOVERY,EN_ST_BLOCKED};
   for(int direction=-1;direction<=1;direction+=2)
      for(int i=0;i<ArraySize(states);i++)
        {
         string signal="T017-STATE-"+IntegerToString(direction)+"-"+IntegerToString(i);
         CFixture first;
         first.Init(direction,signal);
         if(!Clean(first.Name())) {Check(false,"cannot prepare state case"); continue;}
         CEnFakeFileStore store(true);
         first.Place(GetPointer(store));
         SEnRecord rec;
         string text,why;
         bool ok=store.Read(first.Name(),text) && EN_Decode(text,rec,why);
         if(!ok) {Check(false,"cannot read base state case"); Clean(first.Name()); continue;}
         rec.state=states[i];
         rec.position_id=(rec.state==EN_ST_FILLED ? 7 : 0);
         rec.cancel_attempts=(rec.state==EN_ST_CANCEL_UNCERTAIN ? 1 : 0);
         rec.attempts=(rec.state==EN_ST_INTENT || rec.state==EN_ST_PRECHECK_REFUSED ? 0 : 1);
         if(rec.state==EN_ST_INTENT || rec.state==EN_ST_PRECHECK_REFUSED || rec.state==EN_ST_REJECTED) {rec.order_ticket=0; rec.linked=0;}
         ok=EN_Encode(rec,text,why) && store.Write(first.Name(),text);
         Check(ok,"save valid consumed state "+rec.state);
         if(ok)
           {
            CFixture fresh;
            fresh.Init(direction,signal);
            CEnFakeFileStore reopened(true);
            fresh.Place(GetPointer(reopened));
            Check(fresh.result.outcome==EN_R_DUPLICATE && fresh.t.sends==0,"recreated store keeps signal consumed: "+rec.state);
           }
         Check(Clean(first.Name()),"state case: own sandbox files removed");
        }
  }

void NameBoundaries(void)
  {
   string logical="VELO_T013_ENTRY_1_ABCD1234.state";
   Check(EFS_Name(logical)=="VELO_T016_FAKE_VELO_T013_ENTRY_1_ABCD1234.state","fixed FAKE filename");
   Check(EFS_Name(logical,false,true)=="VELO_T017_SELFTEST_VELO_T013_ENTRY_1_ABCD1234.state","separate SELFTEST filename");
   string key="VELO_T013_LOCK_1_ABCD1234";
   Check(EFS_Name(key,true)!=key && EFS_Name(key,true)!=EFS_Name(key,true,true),"ordinary, FAKE and SELFTEST locks are distinct");
   string bad[]={"","../VELO_T013_ENTRY_1_A.state","C:/a.state","VELO_T011_A.state","VELO_T013_ENTRY_../x.state",
                 "VELO_T013_ENTRY_1_A.state.tmp","VELO_T013_ENTRY_.state","VELO_T013_ENTRY_1_A:stream.state"};
   CEnFakeFileStore store(true);
   for(int i=0;i<ArraySize(bad);i++)
     {
      string text="poison";
      Check(EFS_Name(bad[i],false,true)=="" && store.Exists(bad[i]) && !store.Read(bad[i],text) && text=="" && !store.Write(bad[i],"x") && !store.Lock(bad[i]),"invalid logical path fails closed: "+bad[i]);
     }
   string long_name="VELO_T013_ENTRY_";
   for(int i=0;i<250;i++) long_name+="A";
   Check(EFS_Name(long_name+".state")=="","oversize filename refused");
  }

void LockBoundaries(void)
  {
   CEnFakeFileStore a(true),b(true);
   string key="VELO_T013_LOCK_1_7A170001",other="VELO_T013_LOCK_1_7A170002";
   bool held=a.Lock(key);
   Check(held,"first instance holds self-test lock");
   if(!held) return;
   Check(!a.Lock(other) && !b.Lock(key),"nested acquire and competing instance refused");
   a.Unlock(other);
   Check(!b.Lock(key),"wrong-key unlock cannot release held lock");
   a.Unlock(key);
   bool acquired=b.Lock(key);
   Check(acquired,"second instance acquires after correct release");
   if(acquired) b.Unlock(key);
  }

// Test-only fault decorator: no production fault switches.
class CFaultStore : public CEnStore
  {
public:
   CEnFakeFileStore disk;
   int mode;
   CFaultStore(void):disk(true) {mode=0;}
   virtual bool Lock(const string key) {return(disk.Lock(key));}
   virtual void Unlock(const string key) {disk.Unlock(key);}
   virtual bool Exists(const string name) {return(disk.Exists(name));}
   virtual bool Read(const string name,string &text) {if(mode==2) {text=""; return(false);} return(disk.Read(name,text));}
   virtual bool Write(const string name,const string text)
     {
      if(mode==1) {disk.Write(name,"partial"); return(false);}
      return(disk.Write(name,text));
     }
  };

void Failures(void)
  {
   for(int k=0;k<5;k++)
     {
      string signal="T017-FAIL-"+IntegerToString(k);
      CFixture f;
      f.Init(1,signal);
      if(!Clean(f.Name())) {Check(false,"cannot prepare failure case"); continue;}
      CEnFakeFileStore s(true),held(true);
      CFaultStore faulty;
      CEnStore *port=GetPointer(s);
      string physical=EFS_Name(f.Name(),false,true);
      if(k==0) Check(s.Write(f.Name(),"corrupt"),"prepare corrupt self-test record");
      if(k==1) Check(ESF_WriteAll(physical+ESF_TMP_SUFFIX,"partial intent"),"prepare leftover self-test temp");
      bool locked=false;
      if(k==2) {locked=held.Lock(f.Key()); Check(locked,"prepare contended self-test lock");}
      if(k>=3) {faulty.mode=k-2; port=GetPointer(faulty);}
      f.Place(port);
      Check(f.t.sends==0 && (f.result.outcome==EN_R_BLOCKED || f.result.outcome==EN_R_LOCK_FAILED),StringFormat("failure %d: zero sends",k));
      if(locked) held.Unlock(f.Key());
      if(k>=3)
        {
         CFixture fresh;
         fresh.Init(1,signal);
         fresh.Place(GetPointer(s));
         Check(fresh.t.sends==0 && (fresh.result.outcome==EN_R_BLOCKED || fresh.result.outcome==EN_R_DUPLICATE),"failed write/readback never assumes rollback or resends");
        }
      Check(Clean(f.Name()),"failure case: own sandbox files removed");
     }
  }

void OnStart()
  {
   Print("T017 ENTRY PERSISTENCE TEST: FAKE transport, real sandbox file I/O; SELFTEST files only. No trading.");
   Restart(1); Restart(-1); AllStates(); NameBoundaries(); LockBoundaries(); Failures();
   PrintFormat("T017 ENTRY PERSISTENCE TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
