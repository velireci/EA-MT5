// T019 ENTRY LIFECYCLE (mirror of tests/lifecycle_reference.py; read its header for the contract): what happens to a pending order after the placement - a persistent INDEX of the signals that need attention + a
// persistent HALT flag (one CRC-protected file through the entry store), STARTUP reconcile (the existing EN_Reconcile, never a send), TICK (reconcile; a fill is FILLED_UNMANAGED because the T011 registration is
// not connected; due cancel events cancel an open pending order only when the owner enabled that event: the existing TP_CancelDecision + EN_Cancel with a fresh runtime per cancel; an unconfirmed cancel halts).
// No order function here; FAKE tickets are never mapped to broker facts (after a restart under the FAKE transport the book is empty, so a placed record cannot be proven and halts).
#ifndef VELO_ENTRY_LIFECYCLE_MQH
#define VELO_ENTRY_LIFECYCLE_MQH

#include "EntryGate.mqh"

#define LC_MAX 32
#define LC_HEADER "VELO_EO_LIFECYCLE"
#define LC_NONE 0
#define LC_OK 1
#define LC_DAMAGED 2
#define LC_V_OPEN 0
#define LC_V_CLOSED 1
#define LC_V_FILLED 2
#define LC_V_HALT 3

struct SLcState
  {
   long login;
   string halted;
   string ids[LC_MAX];
   int n;
   string noted[LC_MAX];        // fills already reported in THIS process (not persisted): a fill is forgotten only on the tick after its report
   int n_noted;
   bool lock_owned;             // exclusive ownership of the index (the existing store lock); every index access needs it
   string lock_key;
  };

void LC_StateInit(SLcState &s,const long login)
  {
   s.login=login;
   s.halted="";
   s.n=0;
   s.lock_owned=false;
   s.lock_key="";
   s.n_noted=0;
   for(int i=0;i<LC_MAX;i++) {s.ids[i]=""; s.noted[i]="";}
  }

string LC_LockKey(const long login) {return("VELO_T013_LOCK_INDEX_"+IntegerToString(login));}

bool LC_Acquire(CEnStore *lockstore,const long login,SLcState &s)
  {
   string key=LC_LockKey(login);
   if(!lockstore.Lock(key)) return(false);
   s.lock_owned=true;
   s.lock_key=key;
   return(true);
  }

// only the owner releases, and only its own key; a refused instance, a forged key or a second release do nothing
void LC_Release(CEnStore *lockstore,SLcState &s)
  {
   if(s.lock_owned && s.lock_key!="")
     {
      lockstore.Unlock(s.lock_key);
      s.lock_owned=false;
     }
  }

bool LC_Owned(SLcState &s)
  {
   if(!s.lock_owned)
     {
      if(s.halted=="") s.halted="LIFECYCLE_LOCK_NOT_OWNED";
      return(false);
     }
   return(true);
  }

string LC_FileName(const long login) {return("VELO_T013_ENTRY_INDEX_"+IntegerToString(login)+".state");}

string LC_Clean(string s)
  {
   StringReplace(s,"\n"," ");
   StringReplace(s,"\r"," ");
   return(s);
  }

void LC_Note(string &notes,const string text) {notes+=(notes=="" ? "" : " | ")+text;}

string LC_Encode(const SLcState &s)
  {
   string body=LC_HEADER+"\n1\nlogin="+IntegerToString(s.login)+"\nhalt="+LC_Clean(s.halted)+"\nn="+IntegerToString(s.n)+"\n";
   for(int i=0;i<s.n;i++) body+=s.ids[i]+"\n";
   return(body+"CRC="+StringFormat("%08X",ESC_Crc32(body))+"\n");
  }

// reason is filled when false
bool LC_Decode(const string text,const long login,SLcState &s,string &reason)
  {
   LC_StateInit(s,login);
   int k=-1;
   for(int p=StringLen(text)-4;p>=0;p--)
      if(StringSubstr(text,p,4)=="CRC=") {k=p; break;}
   int len=StringLen(text);
   if(k<0 || len<1 || StringGetCharacter(text,len-1)!='\n') {reason="NO_CRC"; return(false);}
   string body=StringSubstr(text,0,k);
   string crc=StringSubstr(text,k+4,len-k-5);
   if(crc!=StringFormat("%08X",ESC_Crc32(body))) {reason="CRC_MISMATCH"; return(false);}
   string lines[];
   int nl=StringSplit(body,'\n',lines)-1;                 // the text after the last newline is empty
   if(nl<5 || lines[0]!=LC_HEADER || lines[1]!="1") {reason="BAD_HEADER"; return(false);}
   if(lines[2]!="login="+IntegerToString(login)) {reason="LOGIN_MISMATCH"; return(false);}
   if(StringFind(lines[3],"halt=")!=0 || StringFind(lines[4],"n=")!=0) {reason="BAD_FIELDS"; return(false);}
   string ns=StringSubstr(lines[4],2);
   long n=StringToInteger(ns);
   if(ns!=IntegerToString(n) || n!=nl-5 || n<0 || n>LC_MAX) {reason="BAD_COUNT"; return(false);}
   for(int i=0;i<n;i++)
     {
      string id=lines[5+i];
      StringTrimLeft(id);
      StringTrimRight(id);
      if(id=="") {reason="BAD_COUNT"; return(false);}
      s.ids[i]=lines[5+i];
     }
   s.n=(int)n;
   s.halted=StringSubstr(lines[3],5);
   return(true);
  }

int LC_Load(CEnStore *store,const long login,SLcState &s)
  {
   LC_StateInit(s,login);
   string name=LC_FileName(login);
   if(!store.Exists(name)) return(LC_NONE);
   string text;
   if(!store.Read(name,text)) {s.halted="LIFECYCLE_STATE_UNREADABLE"; return(LC_DAMAGED);}
   string why;
   SLcState t;
   if(!LC_Decode(text,login,t,why)) {s.halted="LIFECYCLE_STATE_DAMAGED: "+why; return(LC_DAMAGED);}
   s=t;
   return(LC_OK);
  }

bool LC_Save(CEnStore *store,const SLcState &s)
  {
   string text=LC_Encode(s);
   string name=LC_FileName(s.login);
   if(!store.Write(name,text)) return(false);
   string back;
   return(store.Read(name,back) && back==text);
  }

// the EXISTING index is validated (readable, CRC, login) before every update and every lifecycle action; no file = the initial creation is allowed. No repair, retry, deletion or migration.
bool LC_DiskCheck(CEnStore *store,const SLcState &s,string &why)
  {
   why="";
   string name=LC_FileName(s.login);
   if(!store.Exists(name)) return(true);
   string text;
   if(!store.Read(name,text)) {why="LIFECYCLE_STATE_UNREADABLE"; return(false);}
   SLcState t;
   string r;
   if(!LC_Decode(text,s.login,t,r)) {why="LIFECYCLE_STATE_DAMAGED: "+r; return(false);}
   return(true);
  }

bool LC_Persist(CEnStore *store,SLcState &s,string &notes)
  {
   if(!LC_Owned(s)) return(false);
   string why;
   if(!LC_DiskCheck(store,s,why))
     {
      if(s.halted=="") s.halted=why;
      LC_Note(notes,why);
      return(false);
     }
   if(LC_Save(store,s)) return(true);
   if(s.halted=="") s.halted="LIFECYCLE_STATE_NOT_SAVED";
   LC_Note(notes,"LIFECYCLE_STATE_NOT_SAVED");
   return(false);
  }

int LC_IndexOf(const SLcState &s,const string id)
  {
   for(int i=0;i<s.n;i++)
      if(s.ids[i]==id) return(i);
   return(-1);
  }

void LC_Remove(SLcState &s,const int i)
  {
   for(int k=i;k<s.n-1;k++) s.ids[k]=s.ids[k+1];
   s.n--;
   s.ids[s.n]="";
  }

// the id must be indexed (saved and read back) BEFORE the executor can send; any failure halts
bool LC_Register(CEnStore *store,SLcState &s,const string id,string &notes)
  {
   if(!LC_Owned(s)) return(false);
   string t=id;
   StringTrimLeft(t);
   StringTrimRight(t);
   if(t=="" || StringFind(id,"\n")>=0 || StringFind(id,"\r")>=0) {if(s.halted=="") s.halted="LIFECYCLE_BAD_SIGNAL_ID"; return(false);}
   if(LC_IndexOf(s,id)<0)
     {
      if(s.n>=LC_MAX) {if(s.halted=="") s.halted="LIFECYCLE_INDEX_FULL"; return(false);}
      s.ids[s.n]=id;
      s.n++;
     }
   return(LC_Persist(store,s,notes));
  }

void LC_Halt(CEnStore *store,SLcState &s,const string reason,string &notes)
  {
   if(s.halted=="") s.halted=LC_Clean(reason);
   LC_Persist(store,s,notes);
  }

int LC_Verdict(const SEnResult &r)
  {
   ENUM_EN_RESULT f=r.outcome;
   if(f==EN_R_NOCHANGE)
     {
      if(r.reason=="ACTIVE") return(LC_V_OPEN);
      if(r.state==EN_ST_FILLED) return(LC_V_FILLED);
      if(r.state==EN_ST_PRECHECK_REFUSED || r.state==EN_ST_REJECTED || r.state==EN_ST_CANCELLED || r.state==EN_ST_EXPIRED) return(LC_V_CLOSED);
      return(LC_V_HALT);
     }
   if(f==EN_R_PLACED) return(LC_V_OPEN);
   if(f==EN_R_FILLED) return(LC_V_FILLED);
   if(f==EN_R_CANCELLED || f==EN_R_EXPIRED) return(LC_V_CLOSED);
   return(LC_V_HALT);
  }

int LC_NotedIndex(const SLcState &s,const string id)
  {
   for(int i=0;i<s.n_noted;i++)
      if(s.noted[i]==id) return(i);
   return(-1);
  }

void LC_NotedRemove(SLcState &s,const int i)
  {
   for(int k=i;k<s.n_noted-1;k++) s.noted[k]=s.noted[k+1];
   s.n_noted--;
   s.noted[s.n_noted]="";
  }

// The fill is NOT registered with T011 (the registration stays the explicit, owner-asserted script): this is the exact input set of that script, read from the executor record, with every reason
// T011 would refuse it. It writes nothing and calls nothing of T011.
string LC_Proposal(CEnTransport *tr,CEnStore *store,const long login,const string id)
  {
   SEnRecord rec;
   string why;
   if(EN_Load(store,EN_FileName(login,id),rec,why)!=1) return("T011_REGISTRATION: NOT_REGISTRABLE (the executor record is unreadable)");
   SEnSymbol sym;
   tr.ReadSymbol(rec.symbol,sym);
   string reasons="";
   if(rec.state!=EN_ST_FILLED || rec.linked!=1 || rec.position_id==0) reasons+="FILL_NOT_PROVEN";
   bool buy=(rec.direction==1);
   STgResult geo;
   TG_Compute(buy ? TG_BUY : TG_SELL,rec.e,rec.s,false,0.0,sym.tick_size,sym.digits,sym.point,sym.stops_level,false,0.0,0.0,geo);
   if(geo.status!=TG_OK) reasons+=(reasons=="" ? "" : "; ")+"GEOMETRY_REFUSED: "+TG_StatusName(geo.status);
   else if(MathAbs(rec.tp-geo.level_2r)<sym.tick_size/2.0) reasons+=(reasons=="" ? "" : "; ")+"TP_EQUALS_2R: T011 refuses a TP that is not strictly beyond the 2R level (the remainder behaviour is an open decision)";
   else if((buy && rec.tp<geo.level_2r) || (!buy && rec.tp>geo.level_2r)) reasons+=(reasons=="" ? "" : "; ")+"TP_BEFORE_2R: inconsistent with the minimum of 2R";
   string out="T011_REGISTRATION_INPUTS (the explicit script; the owner asserts the initial SL): InpEnabled=true InpRPolicy=R_GEOM InpEaMagic="+IntegerToString(rec.magic)+" InpPositionId="+IntegerToString((long)rec.position_id)+
              " InpSymbol="+rec.symbol+" InpDirection="+(buy ? "BUY" : "SELL")+" InpInitialSl="+DoubleToString(rec.s,8)+" InpTpPrice="+DoubleToString(rec.tp,8)+" InpVolumeInitial="+DoubleToString(rec.volume,8)+
              " (planned entry "+DoubleToString(rec.e,8)+"; R_GEOM is derived from the real open price)";
   return(out+(reasons!="" ? " | NOT_REGISTRABLE: "+reasons : ""));
  }

// reconcile every indexed id (never a send); the open pending orders are returned
void LC_Sweep(const SEnConfig &cfg,CEnTransport *tr,CEnStore *store,SLcState &s,string &open_ids[],int &n_open,string &notes)
  {
   n_open=0;
   ArrayResize(open_ids,LC_MAX);
   for(int i=s.n-1;i>=0;i--)
     {
      string id=s.ids[i];
      SEnResult r;
      EN_Reconcile(cfg,tr,store,id,r);
      int v=LC_Verdict(r);
      if(v==LC_V_OPEN) {open_ids[n_open]=id; n_open++;}
      else if(v==LC_V_HALT)
        {
         LC_Note(notes,"UNRESOLVED "+id+": "+EN_ResultName(r.outcome)+" "+r.reason);
         if(s.halted=="") s.halted="UNRESOLVED_ENTRY_RECORD: "+LC_Clean(r.reason);
        }
      else if(v==LC_V_FILLED && LC_NotedIndex(s,id)<0)
        {
         LC_Note(notes,"FILLED_UNMANAGED "+id+": no T011 registration is connected | "+LC_Proposal(tr,store,s.login,id));
         s.noted[s.n_noted]=id;                           // reported first; forgotten on the next sweep, so a restart in between reports it again
         s.n_noted++;
        }
      else
        {
         LC_Remove(s,i);
         int nk=LC_NotedIndex(s,id);
         if(nk>=0) LC_NotedRemove(s,nk);
        }
     }
  }

// The instance lock comes first: without it the index is neither read nor written and nothing is sent or cancelled. Returns false when the account is unreadable (nothing acquired).
// A damaged state file is never overwritten. The lock is kept for every run that continues (halted or not) and released by LC_Release.
bool LC_Startup(const SEnConfig &cfg,CEnTransport *tr,CEnStore *store,CEnStore *lockstore,const bool acknowledge,SLcState &s,string &notes)
  {
   notes="";
   SEnAccount acct;
   tr.ReadAccount(acct);
   if(!acct.read_ok || acct.login<=0) {LC_StateInit(s,0); s.halted="ACCOUNT_UNREADABLE"; LC_Note(notes,"ACCOUNT_UNREADABLE"); return(false);}
   LC_StateInit(s,acct.login);
   if(!LC_Acquire(lockstore,acct.login,s))
     {
      s.halted="LIFECYCLE_INSTANCE_LOCK_NOT_ACQUIRED";
      LC_Note(notes,s.halted);
      return(true);
     }
   string key=s.lock_key;
   SLcState loaded;
   int kind=LC_Load(store,acct.login,loaded);
   loaded.lock_owned=true;
   loaded.lock_key=key;
   s=loaded;
   if(kind==LC_DAMAGED) {LC_Note(notes,s.halted); return(true);}
   string was=s.halted;
   string open_ids[];
   int n_open=0;
   LC_Sweep(cfg,tr,store,s,open_ids,n_open,notes);
   if(acknowledge && s.halted!="")
     {
      LC_Note(notes,"HALT_ACKNOWLEDGED by the owner: "+(was!="" ? was : s.halted));
      for(int i=s.n-1;i>=0;i--)
        {
         SEnResult r;
         EN_Reconcile(cfg,tr,store,s.ids[i],r);
         if(LC_Verdict(r)==LC_V_HALT) LC_Remove(s,i);         // the record stays on disk: the signal stays consumed
        }
      s.halted="";
     }
   if(kind==LC_OK || s.n>0 || s.halted!="") LC_Persist(store,s,notes);
   return(true);
  }

int LC_DueEvents(const int session,const int news,const bool daily_present,const bool daily_cancel_due)
  {
   int ev=0;
   if(session==TP_SESSION_CLOSED) ev|=TP_EV_SESSION_END;
   if(news==TP_NEWS_BLOCKED) ev|=TP_EV_NEWS_BLOCK;
   if(daily_present && daily_cancel_due) ev|=TP_EV_DAILY_LIMIT;
   return(ev);
  }

void LC_Tick(const SEnConfig &cfg,CEnTransport *tr,CEnStore *store,SLcState &s,const int due,const int enabled,string &notes)
  {
   notes="";
   if(s.login<=0) return;
   if(!s.lock_owned) return;                                // without the instance lock: no index access, no reconcile, no cancel
   string disk_why;
   if(!LC_DiskCheck(store,s,disk_why))                      // a damaged / unreadable index stops every action of the layer and is never written over
     {
      if(s.halted=="") s.halted=disk_why;
      LC_Note(notes,disk_why);
      return;
     }
   string before_halt=s.halted;
   int before_n=s.n;
   string open_ids[];
   int n_open=0;
   LC_Sweep(cfg,tr,store,s,open_ids,n_open,notes);
   int events=(due & enabled);
   bool changed=(s.n!=before_n || s.halted!=before_halt);
   if(due!=0 && events==0) LC_Note(notes,"CANCEL_DUE_NOT_ENABLED events="+IntegerToString(due));
   if(events!=0)
     {
      for(int i=0;i<n_open;i++)
        {
         STpCancel dec;
         TP_CancelDecision(true,open_ids[i],false,events,dec);
         if(dec.status!=TP_CANCEL_REQUEST) continue;
         SEnRuntime rt;
         EN_RuntimeInit(rt);
         SEnResult r;
         EN_Cancel(cfg,tr,store,rt,open_ids[i],dec,r);
         if(r.outcome==EN_R_CANCELLED)
           {
            int k=LC_IndexOf(s,open_ids[i]);
            if(k>=0) LC_Remove(s,k);
            LC_Note(notes,"CANCELLED "+open_ids[i]+": "+dec.reason);
            changed=true;
           }
         else
           {
            LC_Note(notes,"CANCEL_NOT_CONFIRMED "+open_ids[i]+": "+EN_ResultName(r.outcome)+" "+r.reason);
            if(s.halted=="") s.halted="CANCEL_NOT_CONFIRMED: "+LC_Clean(r.reason);
            changed=true;
           }
        }
     }
   if(changed) LC_Persist(store,s,notes);
  }

// the gate's pre-send hook: the index entry is saved and read back BEFORE the executor can create an intent or send
class CLcGuard : public CEgPreSend
  {
public:
   SLcState st;
   CEnStore *store;
   bool is_new;
   int calls;
   string notes;
   CLcGuard(void) {store=NULL; is_new=false; calls=0; notes=""; LC_StateInit(st,0);}
   void Bind(CEnStore *s) {store=s;}
   virtual bool Reserve(const string signal_id,string &reason)
     {
      calls++;
      if(store==NULL) {reason="LIFECYCLE_NOT_BOUND"; return(false);}
      if(!st.lock_owned)
        {
         if(st.halted=="") st.halted="LIFECYCLE_LOCK_NOT_OWNED";
         reason="LIFECYCLE_LOCK_NOT_OWNED";
         return(false);
        }
      if(st.halted!="") {reason="LIFECYCLE_HALTED: "+st.halted; return(false);}
      bool had=(LC_IndexOf(st,signal_id)>=0);
      if(!LC_Register(store,st,signal_id,notes)) {reason="INDEX_NOT_SAVED: "+(st.halted!="" ? st.halted : "unknown"); return(false);}
      is_new=!had;
      return(true);
     }
   // a reservation the executor did not turn into a record (refused before the intent) is released again; a signal with a record stays indexed
   virtual void Settled(const string signal_id,const SEnResult &res)
     {
      if(store==NULL) return;
      bool record=store.Exists(EN_FileName(st.login,signal_id));
      int k=LC_IndexOf(st,signal_id);
      if(!record && is_new && k>=0)
        {
         LC_Remove(st,k);
         LC_Persist(store,st,notes);
        }
      is_new=false;
     }
  };
#endif
