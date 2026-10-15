// T012 DAY-BALANCE STORE: keeps the ACCOUNT_BALANCE at the START of the Tirane day. Mirrors tests/t012_balance_reference.py (its header documents the rules in full).
// Reuses, without copying: the Tirane day window (T009 through DH_DayWindow), the history facts (DH_Build: deals_in_window counts EVERY deal of the account in the day window, any magic,
// any type, after de-duplication), SDbBalance (the form in which the balance reaches DB_Check) and ONLY these primitives of the T011 codec / file layer: ESC_Crc32, ESC_Escape,
// ESC_Unescape, ESC_Fnum, ESC_ParseInt, ESC_ParseDouble, ESC_Lines, ESC_Field, ESF_ReadAll, ESF_WriteAll, ESF_Exists, plus the generic instance lock EL_Acquire / EL_Release.
// No T011 module is changed, no T011 record function is used and no T011 file is read or written.
// DBS_Load is READ-ONLY (no lock, no write, never creates a file). DBS_Capture is an EXPLICIT action: a lock per terminal for (login, day); the existence check and the write are inside it;
// an existing file of any kind (valid, partial, damaged, of another account) is NEVER overwritten; the record is written once, read back and validated; every failure is UNKNOWN or BLOCK.
// WINDOW_EMPTY is a CONDITIONAL proof: READY + complete history facts (the OWNER asserted completeness and gave the server offset; both are stored), no deal of any kind in [midnight, now],
// two equal ACCOUNT_BALANCE reads around a history read that covers the instant, the Tirane day unchanged during the acquisition. OWNER_ASSERTED is a separate explicit source and is never
// promoted. Nothing is reconstructed by subtracting profits. Base = ACCOUNT_BALANCE only. The CRC detects accidental damage, NOT a deliberate edit.
// No order, no cancellation, no result formula / classification / 2-3 limit, no EA integration. UNVERIFIED: not compiled or run by the author.
#ifndef VELO_DAILY_BALANCE_STORE_MQH
#define VELO_DAILY_BALANCE_STORE_MQH

#include "DailyBridge.mqh"
#include "ExitStateFile.mqh"
#include "ExitInstanceLock.mqh"

#define DBS_VERSION 1
#define DBS_HEADER "VELO_T012_DAY_BALANCE"
#define DBS_MAX_SPAN 120              // seconds between the first and the last instant of one acquisition (a technical limit, not a policy)
#define DBS_OFFSET_UNSET 2147483647
#define DBS_MAX_TEXT 2048
#define DBS_ACTIONS 3                 // the actions of the script: 0 LOAD, 1 CAPTURE_WINDOW_EMPTY, 2 CAPTURE_OWNER_ASSERTED; anything else is refused
#define DBS_SRC_NONE ""
#define DBS_SRC_WE "WINDOW_EMPTY"
#define DBS_SRC_OA "OWNER_ASSERTED"

enum ENUM_DBS_STATUS
  {
   DBS_USABLE=0,
   DBS_NONE,
   DBS_UNKNOWN,
   DBS_BLOCK
  };

struct SDbsAccount
  {
   bool read_ok;
   long login;
   string server;
   string currency;
  };

struct SDbsHist
  {
   ENUM_DH_VERDICT verdict;
   bool complete;
   int day_key;
   long window_start;
   long window_end;
   int deals_in_window;
  };

struct SDbsAsserts
  {
   bool complete;
   int offset;
  };

struct SDbsRecord
  {
   long login;
   string server;
   string currency;
   int day;
   double amount;
   string source;
   int complete_asserted;
   int offset;
   long t_first;
   long t_last;
  };

struct SDbsResult
  {
   ENUM_DBS_STATUS status;
   string reason;
   SDbBalance balance;
   string source;
   bool written;
   bool existed;
  };

class CDbsPort
  {
public:
   virtual void ReadAccount(SDbsAccount &a)=0;
   virtual bool ReadBalance(double &amount)=0;
   virtual long NowUtc(void)=0;
   virtual void ReadHistory(const long utc,SDbsHist &h)=0;
   virtual bool Lock(const string key)=0;
   virtual void Unlock(const string key)=0;
   virtual bool Exists(const string name)=0;
   virtual bool ReadFile(const string name,string &text)=0;
   virtual bool WriteFile(const string name,const string text)=0;
  };

bool DBS_ActionKnown(const int action) {return(action>=0 && action<DBS_ACTIONS);}

string DBS_StatusName(const ENUM_DBS_STATUS s)
  {
   switch(s)
     {
      case DBS_USABLE: return("USABLE");
      case DBS_NONE: return("NONE");
      case DBS_UNKNOWN: return("UNKNOWN");
      case DBS_BLOCK: return("BLOCK");
     }
   return("?");
  }

void DBS_ResultInit(SDbsResult &r,const ENUM_DBS_STATUS status,const string reason)
  {
   r.status=status;
   r.reason=reason;
   r.balance.known=false;
   r.balance.day=0;
   r.balance.amount=0.0;
   r.source=DBS_SRC_NONE;
   r.written=false;
   r.existed=false;
  }

string DBS_FileName(const long login,const int day) {return("VELO_T012_BALANCE_"+IntegerToString(login)+"_"+IntegerToString(day)+".txt");}
string DBS_LockKey(const long login,const int day) {return("VELO_T012_LOCK_BAL_"+IntegerToString(login)+"_"+IntegerToString(day));}

// "" when the record is internally consistent (independent of the account / day it is later checked against)
string DBS_Validate(const SDbsRecord &r)
  {
   string t;
   if(r.login<=0) return("INVALID_LOGIN");
   if(r.server=="" || r.currency=="") return("INVALID_IDENTITY");
   if(r.day<20000101 || r.day>29991231) return("INVALID_DAY");
   if(!ESC_Fnum(r.amount,t) || !(r.amount>0.0)) return("INVALID_AMOUNT: must be finite, > 0 and exact with 12 decimals");
   if(r.source!=DBS_SRC_WE && r.source!=DBS_SRC_OA) return("INVALID_SOURCE");
   if((r.complete_asserted!=0 && r.complete_asserted!=1) || r.t_first<=0 || r.t_last<r.t_first) return("INVALID_ASSERTIONS_OR_TIMES");
   if(r.source==DBS_SRC_WE)
     {
      if(r.complete_asserted!=1 || r.offset%900!=0 || r.offset>50400 || r.offset<-50400 || r.t_last-r.t_first>DBS_MAX_SPAN)
         return("INVALID_WINDOW_EMPTY_EVIDENCE: needs the complete assertion, a valid server offset and a short acquisition");
     }
   else
      if(r.complete_asserted!=0 || r.offset!=0 || r.t_last!=r.t_first) return("INVALID_OWNER_ASSERTED_FIELDS");
   long ts[2];
   ts[0]=r.t_first;
   ts[1]=r.t_last;
   for(int i=0;i<2;i++)
     {
      int day=0;
      long start=0,end=0;
      if(!DH_DayWindow((datetime)ts[i],day,start,end) || day!=r.day) return("INVALID_INSTANT: the instant of the record is not inside its Tirane day");
     }
   return("");
  }

bool DBS_Encode(const SDbsRecord &r,string &text,string &reason)
  {
   text="";
   reason=DBS_Validate(r);
   if(reason!="") return(false);
   string amount;
   ESC_Fnum(r.amount,amount);
   string b=DBS_HEADER+"\nVERSION="+IntegerToString(DBS_VERSION)+"\nLOGIN="+IntegerToString(r.login)+"\nSERVER="+ESC_Escape(r.server)+"\nCURRENCY="+ESC_Escape(r.currency)+
            "\nDAY="+IntegerToString(r.day)+"\nAMOUNT="+amount+"\nSOURCE="+r.source+"\nHISTORY_COMPLETE_ASSERTED="+IntegerToString(r.complete_asserted)+
            "\nSERVER_OFFSET_SECONDS="+IntegerToString(r.offset)+"\nT_FIRST_UTC="+IntegerToString(r.t_first)+"\nT_LAST_UTC="+IntegerToString(r.t_last)+"\nEND\n";
   text=b+"CRC="+StringFormat("%08X",ESC_Crc32(b))+"\n";
   if(StringLen(text)>DBS_MAX_TEXT)
     {
      text="";
      reason="TOO_LARGE";
      return(false);
     }
   return(true);
  }

bool DBS_Decode(const string text,SDbsRecord &rec,string &reason)
  {
   reason="";
   rec.login=0;
   rec.server="";
   rec.currency="";
   rec.day=0;
   rec.amount=0.0;
   rec.source="";
   rec.complete_asserted=0;
   rec.offset=0;
   rec.t_first=0;
   rec.t_last=0;
   if(text=="") {reason="EMPTY"; return(false);}
   if(StringLen(text)>DBS_MAX_TEXT) {reason="TOO_LARGE"; return(false);}
   if(StringGetCharacter(text,StringLen(text)-1)!='\n') {reason="TRUNCATED: no final newline"; return(false);}
   int c1=StringFind(text,"CRC=");
   if(c1<0 || StringFind(text,"CRC=",c1+1)>=0) {reason="TRUNCATED: no single END / CRC trailer"; return(false);}
   int k=StringFind(text,"END\nCRC=");
   if(k<0) {reason="TRUNCATED: no trailer"; return(false);}
   string body=StringSubstr(text,0,k+4);
   string trailer=StringSubstr(text,k+4);
   string want="CRC="+StringFormat("%08X",ESC_Crc32(body))+"\n";
   if(trailer!=want)
     {
      reason=(StringLen(trailer)==13 && StringSubstr(trailer,0,4)=="CRC=" ? "CRC_MISMATCH: the record is damaged (the CRC does not protect against a deliberate edit)" : "BAD_TRAILER");
      return(false);
     }
   string lines[];
   if(ESC_Lines(body,lines)<0 || ArraySize(lines)<1 || lines[0]!=DBS_HEADER) {reason="BAD_HEADER"; return(false);}
   string keys[]={"VERSION","LOGIN","SERVER","CURRENCY","DAY","AMOUNT","SOURCE","HISTORY_COMPLETE_ASSERTED","SERVER_OFFSET_SECONDS","T_FIRST_UTC","T_LAST_UTC"};
   int nk=ArraySize(keys);
   if(ArraySize(lines)!=1+nk+1 || lines[ArraySize(lines)-1]!="END") {reason="BAD_LENGTH"; return(false);}
   string v[11];
   for(int i=0;i<nk;i++)
      if(!ESC_Field(lines,1+i,keys[i],v[i])) {reason="BAD_FIELD_ORDER: expected "+keys[i]; return(false);}
   long ver=0,login=0,day=0,comp=0,off=0,tf=0,tl=0;
   double amount=0.0;
   if(!ESC_ParseInt(v[0],ver) || ver!=DBS_VERSION) {reason="UNSUPPORTED_VERSION: "+StringSubstr(v[0],0,20); return(false);}
   string server,currency;
   if(!ESC_ParseInt(v[1],login) || !ESC_ParseInt(v[4],day) || !ESC_ParseInt(v[7],comp) || !ESC_ParseInt(v[8],off) || !ESC_ParseInt(v[9],tf) || !ESC_ParseInt(v[10],tl) ||
      !ESC_ParseDouble(v[5],amount) || !ESC_Unescape(v[2],server) || !ESC_Unescape(v[3],currency)) {reason="BAD_NUMBER_OR_STRING"; return(false);}
   if(v[6]!=DBS_SRC_WE && v[6]!=DBS_SRC_OA) {reason="BAD_ENUM: SOURCE"; return(false);}
   if(comp!=0 && comp!=1) {reason="BAD_NUMBER_OR_STRING: HISTORY_COMPLETE_ASSERTED must be exactly 0 or 1 (checked before any narrowing)"; return(false);}
   if(day<0 || day>2147483647 || off<-2147483647 || off>2147483647) {reason="BAD_NUMBER_OR_STRING"; return(false);}
   rec.login=login;
   rec.server=server;
   rec.currency=currency;
   rec.day=(int)day;
   rec.amount=amount;
   rec.source=v[6];
   rec.complete_asserted=(int)comp;
   rec.offset=(int)off;
   rec.t_first=tf;
   rec.t_last=tl;
   reason=DBS_Validate(rec);
   return(reason=="");
  }

string DBS_CheckAgainst(const SDbsRecord &r,const SDbsAccount &a,const int day)
  {
   if(r.login!=a.login || r.server!=a.server || r.currency!=a.currency)
      return("WRONG_ACCOUNT: the record belongs to another login / server / currency");
   if(r.day!=day) return("WRONG_DAY_IN_RECORD: the file name and the record disagree about the Tirane day");
   return("");
  }

void DBS_FromFile(CDbsPort &port,const SDbsAccount &a,const int day,SDbsResult &res)
  {
   string text;
   if(!port.ReadFile(DBS_FileName(a.login,day),text)) {DBS_ResultInit(res,DBS_BLOCK,"FILE_UNREADABLE: the file exists and could not be read"); return;}
   SDbsRecord rec;
   string why;
   if(!DBS_Decode(text,rec,why)) {DBS_ResultInit(res,DBS_BLOCK,"DAMAGED: "+why); return;}
   why=DBS_CheckAgainst(rec,a,day);
   if(why!="") {DBS_ResultInit(res,DBS_BLOCK,why); return;}
   DBS_ResultInit(res,DBS_USABLE,"");
   res.balance.known=true;
   res.balance.day=day;
   res.balance.amount=rec.amount;
   res.source=rec.source;
   res.existed=true;
  }

// identity + instant + Tirane day; false (res filled) when the account is not fully known or the instant is outside the T009 rules
bool DBS_Identity(CDbsPort &port,SDbsAccount &a,long &t,int &day,SDbsResult &res)
  {
   port.ReadAccount(a);
   if(!a.read_ok || a.login<=0 || a.server=="" || a.currency=="")
     {
      DBS_ResultInit(res,DBS_UNKNOWN,"ACCOUNT_UNREADABLE: login, server and currency must all be known");
      return(false);
     }
   t=port.NowUtc();
   long start=0,end=0;
   if(!DH_DayWindow((datetime)t,day,start,end))
     {
      DBS_ResultInit(res,DBS_UNKNOWN,"DAY_UNSUPPORTED: the instant is outside the T009 rules");
      return(false);
     }
   return(true);
  }

// READ-ONLY: never creates, writes or locks anything. NONE = no file for this account and Tirane day (nothing is invented).
void DBS_Load(CDbsPort &port,SDbsResult &res)
  {
   SDbsAccount a;
   long t=0;
   int day=0;
   if(!DBS_Identity(port,a,t,day,res)) return;
   if(!port.Exists(DBS_FileName(a.login,day)))
     {
      DBS_ResultInit(res,DBS_NONE,"NO_RECORD: no file for this account and Tirane day; the balance at the start of the day is unknown");
      return;
     }
   DBS_FromFile(port,a,day,res);
  }

// EXPLICIT action: src DBS_SRC_WE (needs the owner's complete + offset assertions) or DBS_SRC_OA (needs an amount and the day it is for).
void DBS_Capture(CDbsPort &port,const string src,const SDbsAsserts &asserts,const double owner_amount,const int owner_day,SDbsResult &res)
  {
   DBS_ResultInit(res,DBS_UNKNOWN,"");
   string tmp;
   if(src!=DBS_SRC_WE && src!=DBS_SRC_OA) {res.reason="SOURCE_NOT_SELECTED"; return;}
   if(src==DBS_SRC_WE)
     {
      if(!asserts.complete) {res.reason="HISTORY_COMPLETE_NOT_ASSERTED: WINDOW_EMPTY is a conditional proof over a history the owner declares complete"; return;}
      if(asserts.offset==DBS_OFFSET_UNSET) {res.reason="OFFSET_NOT_ASSERTED: the server offset must be given"; return;}
      if(asserts.offset%900!=0 || asserts.offset>50400 || asserts.offset<-50400) {res.reason="OFFSET_INVALID"; return;}
     }
   else
      if(!ESC_Fnum(owner_amount,tmp) || !(owner_amount>0.0) || owner_day<=0) {res.reason="OWNER_AMOUNT_INVALID: a finite exact amount > 0 and the day it is for are required"; return;}
   SDbsAccount a;
   long t_a=0;
   int day=0;
   if(!DBS_Identity(port,a,t_a,day,res)) return;
   if(src==DBS_SRC_OA && owner_day!=day) {DBS_ResultInit(res,DBS_UNKNOWN,"OWNER_DAY_MISMATCH: the asserted day is not the current Tirane day"); return;}
   string key=DBS_LockKey(a.login,day);
   if(!port.Lock(key)) {DBS_ResultInit(res,DBS_UNKNOWN,"LOCK_FAILED: another capture holds this account / day in this terminal; nothing is read or written"); return;}
   string name=DBS_FileName(a.login,day);
   if(port.Exists(name))                                  // INSIDE the lock; never overwritten, whatever it holds
     {
      DBS_FromFile(port,a,day,res);
      if(res.status==DBS_USABLE) res.reason="ALREADY_CAPTURED: the stored record is returned unchanged";
      port.Unlock(key);
      return;
     }
   SDbsRecord rec;
   rec.login=a.login;
   rec.server=a.server;
   rec.currency=a.currency;
   rec.day=day;
   if(src==DBS_SRC_WE)
     {
      double b1=0.0,b2=0.0;
      if(!port.ReadBalance(b1) || !MathIsValidNumber(b1) || !(b1>0.0)) {DBS_ResultInit(res,DBS_UNKNOWN,"BALANCE_UNREADABLE"); port.Unlock(key); return;}
      SDbsHist h;
      port.ReadHistory(t_a,h);
      if(h.verdict!=DH_READY) {DBS_ResultInit(res,DBS_UNKNOWN,"HISTORY_NOT_READY:"+(h.verdict==DH_UNKNOWN ? "UNKNOWN" : (h.verdict==DH_BLOCK ? "BLOCK" : "?"))); port.Unlock(key); return;}
      if(!h.complete) {DBS_ResultInit(res,DBS_UNKNOWN,"HISTORY_NOT_COMPLETE"); port.Unlock(key); return;}
      if(!port.ReadBalance(b2) || !MathIsValidNumber(b2) || !(b2>0.0)) {DBS_ResultInit(res,DBS_UNKNOWN,"BALANCE_UNREADABLE"); port.Unlock(key); return;}
      if(b2!=b1) {DBS_ResultInit(res,DBS_UNKNOWN,"BALANCE_CHANGED_DURING_ACQUISITION"); port.Unlock(key); return;}
      long t_b=port.NowUtc();
      if(t_b<t_a) {DBS_ResultInit(res,DBS_UNKNOWN,"CLOCK_WENT_BACKWARDS"); port.Unlock(key); return;}
      if(t_b-t_a>DBS_MAX_SPAN) {DBS_ResultInit(res,DBS_UNKNOWN,"ACQUISITION_TOO_SLOW"); port.Unlock(key); return;}
      int day_b=0;
      long sb=0,eb=0;
      if(!DH_DayWindow((datetime)t_b,day_b,sb,eb) || day_b!=day) {DBS_ResultInit(res,DBS_UNKNOWN,"DAY_CHANGED_DURING_ACQUISITION"); port.Unlock(key); return;}
      if(h.day_key!=day) {DBS_ResultInit(res,DBS_UNKNOWN,"HISTORY_DAY_DIFFERS"); port.Unlock(key); return;}
      if(!(h.window_start<=t_a && t_b<h.window_end)) {DBS_ResultInit(res,DBS_UNKNOWN,"HISTORY_DOES_NOT_COVER_THE_INSTANT"); port.Unlock(key); return;}
      if(h.deals_in_window!=0)
        {
         DBS_ResultInit(res,DBS_UNKNOWN,StringFormat("MID_DAY_NOT_PROVEN: %d deal(s) of the account already exist in the day window; the balance read now is not the start-of-day balance",h.deals_in_window));
         port.Unlock(key);
         return;
        }
      rec.amount=b1;
      rec.source=DBS_SRC_WE;
      rec.complete_asserted=1;
      rec.offset=asserts.offset;
      rec.t_first=t_a;
      rec.t_last=t_b;
     }
   else
     {
      rec.amount=owner_amount;
      rec.source=DBS_SRC_OA;
      rec.complete_asserted=0;
      rec.offset=0;
      rec.t_first=t_a;
      rec.t_last=t_a;
     }
   string text,why;
   if(!DBS_Encode(rec,text,why)) {DBS_ResultInit(res,DBS_UNKNOWN,"RECORD_REFUSED: "+why); port.Unlock(key); return;}
   if(!port.WriteFile(name,text))
     {
      DBS_ResultInit(res,DBS_UNKNOWN,"WRITE_FAILED: a partial file may exist and then blocks later captures until the owner removes it; the amount is not usable");
      port.Unlock(key);
      return;
     }
   string back;
   if(!port.ReadFile(name,back) || back!=text)
     {
      DBS_ResultInit(res,DBS_UNKNOWN,"READBACK_FAILED: the stored text differs from the written one; the amount is not usable");
      port.Unlock(key);
      return;
     }
   SDbsRecord rec2;
   if(!DBS_Decode(back,rec2,why) || DBS_CheckAgainst(rec2,a,day)!="")
     {
      DBS_ResultInit(res,DBS_UNKNOWN,"READBACK_INVALID: the stored record does not validate; the amount is not usable");
      port.Unlock(key);
      return;
     }
   DBS_ResultInit(res,DBS_USABLE,"");
   res.balance.known=true;
   res.balance.day=day;
   res.balance.amount=rec2.amount;
   res.source=rec2.source;
   res.written=true;
   port.Unlock(key);
  }

// ======================= THE ONLY TERMINAL ACCESS (UNVERIFIED against a live terminal): reads and the file layer; no order, no deletion =======================
class CDbsRealPort : public CDbsPort
  {
   long              m_magic;                 // only to satisfy DH_Build (a config must name a magic); the emptiness check covers every magic
   int               m_offset;
   bool              m_complete;
   string            m_symbol;
   bool              m_held;
public:
   CDbsRealPort(const long magic,const int offset,const bool complete,const string symbol) {m_magic=magic; m_offset=offset; m_complete=complete; m_symbol=symbol; m_held=false;}
   virtual void ReadAccount(SDbsAccount &a)
     {
      ResetLastError();
      a.login=AccountInfoInteger(ACCOUNT_LOGIN);
      a.server=AccountInfoString(ACCOUNT_SERVER);
      a.currency=AccountInfoString(ACCOUNT_CURRENCY);
      a.read_ok=(GetLastError()==0 && a.login>0 && a.server!="" && a.currency!="");
     }
   virtual bool ReadBalance(double &amount)
     {
      ResetLastError();
      amount=AccountInfoDouble(ACCOUNT_BALANCE);
      return(GetLastError()==0);
     }
   virtual long NowUtc(void) {return((long)TimeGMT());}
   virtual void ReadHistory(const long utc,SDbsHist &h)
     {
      SDhCfg c;
      c.ea_magic=m_magic;
      c.utc_in_day=(datetime)utc;
      c.server_offset_seconds=m_offset;
      c.history_complete_asserted=m_complete;
      SDhFacts f;
      SDhRaw raw;
      string reason;
      h.verdict=DH_ReadAndBuild(m_symbol,c,f,reason,raw);
      h.complete=(h.verdict==DH_READY && f.complete);
      h.day_key=(h.verdict==DH_READY ? f.day_key : 0);
      h.window_start=(h.verdict==DH_READY ? f.window_start : 0);
      h.window_end=(h.verdict==DH_READY ? f.window_end : 0);
      h.deals_in_window=(h.verdict==DH_READY ? f.deals_in_window : -1);
     }
   virtual bool Lock(const string key)
     {
      string why;
      return(EL_Acquire(key,m_held,why));
     }
   virtual void Unlock(const string key) {EL_Release(key,m_held);}
   virtual bool Exists(const string name) {return(ESF_Exists(name));}
   virtual bool ReadFile(const string name,string &text) {return(ESF_ReadAll(name,text));}
   virtual bool WriteFile(const string name,const string text) {return(ESF_WriteAll(name,text));}
  };
#endif
