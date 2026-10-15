// T019 ENTRY LIFECYCLE (mirror of tests/lifecycle_reference.py; read its header for the contract): what happens to a pending order after the placement - a persistent INDEX of the signals that need attention + a
// persistent HALT flag (one CRC-protected file through the entry store), STARTUP reconcile (the existing EN_Reconcile, never a send), TICK (reconcile; a fill is FILLED_UNMANAGED because the T011 registration is
// not connected; due cancel events cancel an open pending order only when the owner enabled that event: the existing TP_CancelDecision + EN_Cancel with a fresh runtime per cancel; an unconfirmed cancel halts).
// No order function here; FAKE tickets are never mapped to broker facts (after a restart under the FAKE transport the book is empty, so a placed record cannot be proven and halts).
#ifndef VELO_ENTRY_LIFECYCLE_MQH
#define VELO_ENTRY_LIFECYCLE_MQH

#include "EntryExecutor.mqh"

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
  };

void LC_StateInit(SLcState &s,const long login)
  {
   s.login=login;
   s.halted="";
   s.n=0;
   for(int i=0;i<LC_MAX;i++) s.ids[i]="";
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

bool LC_Persist(CEnStore *store,SLcState &s,string &notes)
  {
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

// called after the executor reached the intent for a signal: the id must be indexed or the layer halts
bool LC_Register(CEnStore *store,SLcState &s,const string id,string &notes)
  {
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
      else
        {
         LC_Remove(s,i);
         if(v==LC_V_FILLED) LC_Note(notes,"FILLED_UNMANAGED "+id+": no T011 registration is connected");
        }
     }
  }

// returns false when the account is unreadable (s.halted is set); a damaged state file is never overwritten
bool LC_Startup(const SEnConfig &cfg,CEnTransport *tr,CEnStore *store,const bool acknowledge,SLcState &s,string &notes)
  {
   notes="";
   SEnAccount acct;
   tr.ReadAccount(acct);
   if(!acct.read_ok || acct.login<=0) {LC_StateInit(s,0); s.halted="ACCOUNT_UNREADABLE"; LC_Note(notes,"ACCOUNT_UNREADABLE"); return(false);}
   int kind=LC_Load(store,acct.login,s);
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
#endif
