// T013 ENTRY EXECUTOR (mirror of tests/entry_reference.py; read its header for the full contract): places AT MOST ONE pending LIMIT order per signal from an EXPLICIT T007 plan and an EXPLICIT permit,
// links the result to the order it created, reconciles WITHOUT ever sending again, and cancels only an order proven to be the EA's. DISABLED by default. It chooses NO signal, direction, FVG, entry,
// stop, target or policy and copies no TradePlanning logic: the plan is STpPlan (TP_BuildPlan), the permit comes from TP_CheckPermit / TP_Authorize and is bound to the plan by a canonical digest, the
// cancellation request is the STpCancel of TP_CancelDecision. Every mandatory unresolved input is UNSET = BLOCK.
// ORDER OF A PLACEMENT: static validation (no I/O) -> lock -> record check (a record of ANY state for the signal blocks) -> terminal reads (a failure = ZERO sends) -> INTENT saved and read back ->
// read-only pre-check -> the ONE send -> classify (PLACED / definite reject / uncertain) -> save the outcome -> link proof (the ticket of the response + the whole attribute tuple + the ticket was not in the
// pre-send snapshot). An uncertain answer records ONE attempt and RECOVERY_REQUIRED and is never retried (the attempt is NOT zero sends). A comment, a magic or a volume alone never links an order.
// RECONCILE never calls Send or Cancel. CANCEL needs the cancel decision of this signal, the stored linked ticket and the order read back as an ACTIVE pending of the EA with the stored attributes; the
// intent is saved before the call; an uncertain answer is CANCEL_UNCERTAIN and is resolved by RECONCILE, not by a retry.
// LIMITS: terminal semantics (OrderSend / OrderCheck of pending orders, order history fields, retcodes) are UNVERIFIED until the owner runs the fake test in MT5 and, later, a demo test; the lock protects one
// terminal only; the CRC detects accidental damage, not a deliberate edit; a record is never deleted by this module.
#ifndef VELO_ENTRY_EXECUTOR_MQH
#define VELO_ENTRY_EXECUTOR_MQH

#include "EntryTransport.mqh"
#include "TradePlanning.mqh"
#include "ExitStateCodec.mqh"

#define EN_HEADER "VELO_T013_ENTRY_ORDER"
#define EN_VERSION 1
#define EN_MAX_TEXT 4096
#define EN_TIME_TOL 120
#define EN_AUTH_PHRASE "I_AUTHORISE_REAL_ENTRY_ORDERS_ON_THIS_DEMO_ACCOUNT"
#define EN_RC_PLACED 10008
#define EN_RC_DONE 10009

#define EN_ST_INTENT "INTENT"
#define EN_ST_PRECHECK_REFUSED "PRECHECK_REFUSED"
#define EN_ST_REJECTED "REJECTED"
#define EN_ST_PLACED "PLACED"
#define EN_ST_FILLED "FILLED"
#define EN_ST_CANCEL_UNCERTAIN "CANCEL_UNCERTAIN"
#define EN_ST_CANCELLED "CANCELLED"
#define EN_ST_EXPIRED "EXPIRED"
#define EN_ST_RECOVERY "RECOVERY_REQUIRED"
#define EN_ST_BLOCKED "BLOCKED"

enum ENUM_EN_RESULT
  {
   EN_R_NONE=0,
   EN_R_REFUSED,
   EN_R_LOCK_FAILED,
   EN_R_DUPLICATE,
   EN_R_PRECHECK_REFUSED,
   EN_R_REJECTED,
   EN_R_PLACED,
   EN_R_FILLED,
   EN_R_RECOVERY,
   EN_R_BLOCKED,
   EN_R_CANCELLED,
   EN_R_CANCEL_UNCERTAIN,
   EN_R_NOCHANGE,
   EN_R_EXPIRED
  };

string EN_ResultName(const ENUM_EN_RESULT r)
  {
   switch(r)
     {
      case EN_R_NONE: return("NONE");
      case EN_R_REFUSED: return("REFUSED");
      case EN_R_LOCK_FAILED: return("LOCK_FAILED");
      case EN_R_DUPLICATE: return("DUPLICATE");
      case EN_R_PRECHECK_REFUSED: return("PRECHECK_REFUSED");
      case EN_R_REJECTED: return("REJECTED");
      case EN_R_PLACED: return("PLACED");
      case EN_R_FILLED: return("FILLED");
      case EN_R_RECOVERY: return("RECOVERY_REQUIRED");
      case EN_R_BLOCKED: return("BLOCKED");
      case EN_R_CANCELLED: return("CANCELLED");
      case EN_R_CANCEL_UNCERTAIN: return("CANCEL_UNCERTAIN");
      case EN_R_NOCHANGE: return("NO_CHANGE");
      case EN_R_EXPIRED: return("EXPIRED");
     }
   return("?");
  }

struct SEnConfig
  {
   bool enabled;                 // false by default
   long ea_magic;                // > 0
   string symbol;                // blank = UNSET
   int filling;                  // EN_FILL_*; UNSET blocks
   int expiry_mode;              // EN_EXP_*; UNSET blocks
   long expiry_seconds;          // EN_EXP_SECONDS only
   long permit_max_age;          // seconds; <= 0 = UNSET = BLOCK
   long quote_max_age;           // seconds; <= 0 = UNSET = BLOCK
   bool real_authorised;
   string authorisation;
  };

void EN_ConfigInit(SEnConfig &c)
  {
   c.enabled=false;
   c.ea_magic=0;
   c.symbol="";
   c.filling=EN_FILL_UNSET;
   c.expiry_mode=EN_EXP_UNSET;
   c.expiry_seconds=0;
   c.permit_max_age=-1;
   c.quote_max_age=-1;
   c.real_authorised=false;
   c.authorisation="";
  }

struct SEnPermit
  {
   bool present;
   bool allow;
   string digest;
   long issued;
   long valid_until;             // 0 = no extra deadline; > 0 = the permit is void after this instant (the oldest evidence it was built from expires)
  };

void EN_PermitInit(SEnPermit &p)
  {
   p.present=false;
   p.allow=false;
   p.digest="";
   p.issued=0;
   p.valid_until=0;
  }

struct SEnRuntime
  {
   int send_calls;
   int cancel_calls;
   bool latched;
  };

void EN_RuntimeInit(SEnRuntime &r)
  {
   r.send_calls=0;
   r.cancel_calls=0;
   r.latched=false;
  }

struct SEnResult
  {
   ENUM_EN_RESULT outcome;
   string reason;
   int sends;
   string state;
   ulong order_ticket;
   ulong position_id;
  };

void EN_Res(SEnResult &r,const ENUM_EN_RESULT outcome,const string reason,const int sends=0,const string state="",const ulong ticket=0,const ulong pos=0)
  {
   r.outcome=outcome;
   r.reason=reason;
   r.sends=sends;
   r.state=state;
   r.order_ticket=ticket;
   r.position_id=pos;
  }

struct SEnRecord
  {
   long login;
   string server;
   string symbol;
   string signal_id;
   string setup_id;
   int direction;
   double e;
   double s;
   double tp;
   double volume;
   long magic;
   int filling;
   int expiry_mode;
   long expiration;
   long t_intent;
   string req_id;
   int generation;
   string state;
   int attempts;
   int cancel_attempts;
   ulong order_ticket;
   int linked;
   ulong position_id;
   int n_snap;
   ulong snap[EN_MAX_SNAP];
   string reason;
  };

void EN_RecordInit(SEnRecord &r)
  {
   r.login=0;
   r.server="";
   r.symbol="";
   r.signal_id="";
   r.setup_id="";
   r.direction=0;
   r.e=0.0;
   r.s=0.0;
   r.tp=0.0;
   r.volume=0.0;
   r.magic=0;
   r.filling=0;
   r.expiry_mode=0;
   r.expiration=0;
   r.t_intent=0;
   r.req_id="";
   r.generation=1;
   r.state=EN_ST_INTENT;
   r.attempts=0;
   r.cancel_attempts=0;
   r.order_ticket=0;
   r.linked=0;
   r.position_id=0;
   r.n_snap=0;
   r.reason="";
  }

// ------------------------------------------------------------------------------------------------ names, helpers
string EN_Hex(const string signal_id) {return(StringFormat("%08X",ESC_Crc32(signal_id)));}
string EN_FileName(const long login,const string signal_id) {return("VELO_T013_ENTRY_"+IntegerToString(login)+"_"+EN_Hex(signal_id)+".state");}
string EN_LockKey(const long login,const string signal_id) {return("VELO_T013_LOCK_"+IntegerToString(login)+"_"+EN_Hex(signal_id));}
string EN_ReqId(const string signal_id) {return("VELO_EN_"+EN_Hex(signal_id));}

bool EN_Blank(const string s)
  {
   string t=s;
   StringTrimLeft(t);
   StringTrimRight(t);
   return(t=="");
  }

bool EN_Fin(const double x) {return(x==x && x-x==0.0);}

bool EN_Close(const double a,const double b)
  {
   double m=MathMax(1.0,MathMax(MathAbs(a),MathAbs(b)));
   return(MathAbs(a-b)<=1e-9*m);
  }

bool EN_OnGrid(const double x,const double tick) {return(MathAbs(x-MathRound(x/tick)*tick)<=1e-9*MathMax(1.0,MathAbs(x)));}

int EN_OType(const int direction) {return(direction==1 ? EN_TYPE_BUY_LIMIT : EN_TYPE_SELL_LIMIT);}

// canonical text of exactly the fields the order is built from; the permit must carry the digest of the SAME plan
string EN_PlanDigest(const STpPlan &p)
  {
   string a,b,c,d;
   if(!ESC_Fnum(p.e_out,a) || !ESC_Fnum(p.s_out,b) || !ESC_Fnum(p.tp,c) || !ESC_Fnum(p.volume_out,d)) return("");
   if(EN_Blank(p.signal_id) || EN_Blank(p.setup_id) || (p.direction!=1 && p.direction!=-1)) return("");
   return(ESC_Escape(p.signal_id)+"|"+ESC_Escape(p.setup_id)+"|"+IntegerToString(p.direction)+"|"+a+"|"+b+"|"+c+"|"+d);
  }

// binds a permit of TP_CheckPermit / TP_Authorize to the plan it was issued for; call it right after the permit decision
void EN_PermitFrom(const STpPlan &plan,const STpPermit &tpermit,const long issued,SEnPermit &out)
  {
   out.present=true;
   out.allow=tpermit.allow;
   out.digest=EN_PlanDigest(plan);
   out.issued=issued;
   out.valid_until=0;
  }

// ------------------------------------------------------------------------------------------------ record codec
string EN_Validate(const SEnRecord &r)
  {
   string t;
   if(r.login<=0 || EN_Blank(r.server) || EN_Blank(r.symbol)) return("INVALID_IDENTITY");
   if(EN_Blank(r.signal_id) || EN_Blank(r.setup_id) || (r.direction!=1 && r.direction!=-1)) return("INVALID_SIGNAL");
   if(!ESC_Fnum(r.e,t) || !(r.e>0.0) || !ESC_Fnum(r.s,t) || !(r.s>0.0) || !ESC_Fnum(r.tp,t) || !(r.tp>0.0) || !ESC_Fnum(r.volume,t) || !(r.volume>0.0)) return("INVALID_PRICE_OR_VOLUME");
   if(r.direction==1 && !(r.s<r.e && r.e<r.tp)) return("INVALID_GEOMETRY");
   if(r.direction==-1 && !(r.tp<r.e && r.e<r.s)) return("INVALID_GEOMETRY");
   if(r.magic<=0 || r.filling!=EN_FILL_RETURN || (r.expiry_mode!=EN_EXP_GTC && r.expiry_mode!=EN_EXP_SECONDS)) return("INVALID_CONFIG");
   if((r.expiry_mode==EN_EXP_GTC && r.expiration!=0) || (r.expiry_mode==EN_EXP_SECONDS && r.expiration<=r.t_intent)) return("INVALID_EXPIRATION");
   if(r.t_intent<=0 || r.req_id!=EN_ReqId(r.signal_id)) return("INVALID_INTENT");
   bool known=(r.state==EN_ST_INTENT || r.state==EN_ST_PRECHECK_REFUSED || r.state==EN_ST_REJECTED || r.state==EN_ST_PLACED || r.state==EN_ST_FILLED || r.state==EN_ST_CANCEL_UNCERTAIN ||
               r.state==EN_ST_CANCELLED || r.state==EN_ST_EXPIRED || r.state==EN_ST_RECOVERY || r.state==EN_ST_BLOCKED);
   if(r.generation<1 || !known || (r.attempts!=0 && r.attempts!=1) || (r.cancel_attempts!=0 && r.cancel_attempts!=1)) return("INVALID_STATE");
   if(r.linked!=0 && r.linked!=1) return("INVALID_LINK");
   if(r.linked==1 && r.order_ticket==0) return("INVALID_LINK");
   if(r.position_id>0 && r.state!=EN_ST_FILLED) return("INVALID_LINK");
   if(r.state==EN_ST_INTENT && (r.attempts!=0 || r.order_ticket!=0 || r.linked!=0)) return("INVALID_INTENT_STATE");
   if((r.state==EN_ST_PLACED || r.state==EN_ST_CANCEL_UNCERTAIN || r.state==EN_ST_FILLED) && (r.attempts!=1 || r.linked!=1)) return("INVALID_PLACED_STATE");
   if(r.state==EN_ST_FILLED && r.position_id==0) return("INVALID_FILLED_STATE");
   if(r.state==EN_ST_REJECTED && (r.attempts!=1 || r.order_ticket!=0 || r.linked!=0)) return("INVALID_REJECTED_STATE");
   if(r.state==EN_ST_PRECHECK_REFUSED && (r.attempts!=0 || r.order_ticket!=0)) return("INVALID_PRECHECK_STATE");
   if(r.n_snap<0 || r.n_snap>EN_MAX_SNAP) return("INVALID_SNAPSHOT");
   for(int i=0;i<r.n_snap;i++)
     {
      if(r.snap[i]==0) return("INVALID_SNAPSHOT");
      for(int j=i+1;j<r.n_snap;j++)
         if(r.snap[j]==r.snap[i]) return("INVALID_SNAPSHOT");
      if(r.order_ticket!=0 && r.snap[i]==r.order_ticket) return("INVALID_SNAPSHOT_TICKET");
     }
   return("");
  }

bool EN_Encode(const SEnRecord &r,string &text,string &reason)
  {
   text="";
   reason=EN_Validate(r);
   if(reason!="") return(false);
   string e,s,tp,vol;
   ESC_Fnum(r.e,e);
   ESC_Fnum(r.s,s);
   ESC_Fnum(r.tp,tp);
   ESC_Fnum(r.volume,vol);
   string snap="";
   for(int i=0;i<r.n_snap;i++)
      snap+=(i>0 ? "," : "")+IntegerToString((long)r.snap[i]);
   string b=EN_HEADER+"\nVERSION="+IntegerToString(EN_VERSION)+"\nLOGIN="+IntegerToString(r.login)+"\nSERVER="+ESC_Escape(r.server)+"\nSYMBOL="+ESC_Escape(r.symbol)+
            "\nSIGNAL_ID="+ESC_Escape(r.signal_id)+"\nSETUP_ID="+ESC_Escape(r.setup_id)+"\nDIRECTION="+IntegerToString(r.direction)+"\nE="+e+"\nS="+s+"\nTP="+tp+"\nVOLUME="+vol+
            "\nMAGIC="+IntegerToString(r.magic)+"\nFILLING="+IntegerToString(r.filling)+"\nEXPIRY_MODE="+IntegerToString(r.expiry_mode)+"\nEXPIRATION="+IntegerToString(r.expiration)+
            "\nT_INTENT="+IntegerToString(r.t_intent)+"\nREQ_ID="+r.req_id+"\nGENERATION="+IntegerToString(r.generation)+"\nSTATE="+r.state+"\nATTEMPTS="+IntegerToString(r.attempts)+
            "\nCANCEL_ATTEMPTS="+IntegerToString(r.cancel_attempts)+"\nORDER_TICKET="+IntegerToString((long)r.order_ticket)+"\nLINKED="+IntegerToString(r.linked)+
            "\nPOSITION_ID="+IntegerToString((long)r.position_id)+"\nN_SNAP="+IntegerToString(r.n_snap)+"\nSNAP="+snap+"\nREASON="+ESC_Escape(StringSubstr(r.reason,0,120))+"\nEND\n";
   text=b+"CRC="+StringFormat("%08X",ESC_Crc32(b))+"\n";
   if(StringLen(text)>EN_MAX_TEXT)
     {
      text="";
      reason="TOO_LARGE";
      return(false);
     }
   return(true);
  }

bool EN_Decode(const string text,SEnRecord &rec,string &reason)
  {
   reason="";
   EN_RecordInit(rec);
   if(text=="") {reason="EMPTY"; return(false);}
   if(StringLen(text)>EN_MAX_TEXT) {reason="TOO_LARGE"; return(false);}
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
   if(ESC_Lines(body,lines)<0 || ArraySize(lines)<1 || lines[0]!=EN_HEADER) {reason="BAD_HEADER"; return(false);}
   string keys[]={"VERSION","LOGIN","SERVER","SYMBOL","SIGNAL_ID","SETUP_ID","DIRECTION","E","S","TP","VOLUME","MAGIC","FILLING","EXPIRY_MODE","EXPIRATION","T_INTENT","REQ_ID","GENERATION",
                  "STATE","ATTEMPTS","CANCEL_ATTEMPTS","ORDER_TICKET","LINKED","POSITION_ID","N_SNAP","SNAP","REASON"};
   int nk=ArraySize(keys);
   if(ArraySize(lines)!=1+nk+1 || lines[ArraySize(lines)-1]!="END") {reason="BAD_LENGTH"; return(false);}
   string v[27];
   for(int i=0;i<nk;i++)
      if(!ESC_Field(lines,1+i,keys[i],v[i])) {reason="BAD_FIELD_ORDER: expected "+keys[i]; return(false);}
   long ver=0,login=0,dir=0,magic=0,fill=0,expm=0,expv=0,tin=0,gen=0,att=0,catt=0,tick=0,lnk=0,pos=0,nsn=0;
   double e=0.0,s=0.0,tpv=0.0,vol=0.0;
   string server,symbol,sig,setup,why;
   if(!ESC_ParseInt(v[0],ver) || ver!=EN_VERSION) {reason="UNSUPPORTED_VERSION: "+StringSubstr(v[0],0,20); return(false);}
   if(!ESC_ParseInt(v[1],login) || !ESC_ParseInt(v[6],dir) || !ESC_ParseInt(v[11],magic) || !ESC_ParseInt(v[12],fill) || !ESC_ParseInt(v[13],expm) || !ESC_ParseInt(v[14],expv) ||
      !ESC_ParseInt(v[15],tin) || !ESC_ParseInt(v[17],gen) || !ESC_ParseInt(v[19],att) || !ESC_ParseInt(v[20],catt) || !ESC_ParseInt(v[21],tick) || !ESC_ParseInt(v[22],lnk) ||
      !ESC_ParseInt(v[23],pos) || !ESC_ParseInt(v[24],nsn) || !ESC_ParseDouble(v[7],e) || !ESC_ParseDouble(v[8],s) || !ESC_ParseDouble(v[9],tpv) || !ESC_ParseDouble(v[10],vol) ||
      !ESC_Unescape(v[2],server) || !ESC_Unescape(v[3],symbol) || !ESC_Unescape(v[4],sig) || !ESC_Unescape(v[5],setup) || !ESC_Unescape(v[26],why))
     {reason="BAD_NUMBER_OR_STRING"; return(false);}
   bool known=(v[18]==EN_ST_INTENT || v[18]==EN_ST_PRECHECK_REFUSED || v[18]==EN_ST_REJECTED || v[18]==EN_ST_PLACED || v[18]==EN_ST_FILLED || v[18]==EN_ST_CANCEL_UNCERTAIN ||
               v[18]==EN_ST_CANCELLED || v[18]==EN_ST_EXPIRED || v[18]==EN_ST_RECOVERY || v[18]==EN_ST_BLOCKED);
   if(!known) {reason="BAD_ENUM: STATE"; return(false);}
   // every narrowing is range-checked FIRST
   if(dir<-1 || dir>1 || fill<0 || fill>3 || expm<0 || expm>2 || gen<1 || gen>2147483647 || att<0 || att>1 || catt<0 || catt>1 || lnk<0 || lnk>1 || nsn<0 || nsn>EN_MAX_SNAP ||
      tick<0 || pos<0) {reason="BAD_NUMBER_OR_STRING: out of range"; return(false);}
   ulong snap[EN_MAX_SNAP];
   int ns=0;
   if(v[25]!="")
     {
      string parts[];
      int np=StringSplit(v[25],',',parts);
      if(np<0 || np>EN_MAX_SNAP) {reason="BAD_NUMBER_OR_STRING: SNAP"; return(false);}
      for(int i=0;i<np;i++)
        {
         long x=0;
         if(!ESC_ParseInt(parts[i],x) || x<=0) {reason="BAD_NUMBER_OR_STRING: SNAP"; return(false);}
         snap[ns]=(ulong)x;
         ns++;
        }
     }
   if(nsn!=ns) {reason="BAD_SNAPSHOT_COUNT"; return(false);}
   rec.login=login;
   rec.server=server;
   rec.symbol=symbol;
   rec.signal_id=sig;
   rec.setup_id=setup;
   rec.direction=(int)dir;
   rec.e=e;
   rec.s=s;
   rec.tp=tpv;
   rec.volume=vol;
   rec.magic=magic;
   rec.filling=(int)fill;
   rec.expiry_mode=(int)expm;
   rec.expiration=expv;
   rec.t_intent=tin;
   rec.req_id=v[16];
   rec.generation=(int)gen;
   rec.state=v[18];
   rec.attempts=(int)att;
   rec.cancel_attempts=(int)catt;
   rec.order_ticket=(ulong)tick;
   rec.linked=(int)lnk;
   rec.position_id=(ulong)pos;
   rec.n_snap=ns;
   for(int i=0;i<ns;i++) rec.snap[i]=snap[i];
   rec.reason=why;
   reason=EN_Validate(rec);
   return(reason=="");
  }

// ------------------------------------------------------------------------------------------------ checks (pure)
// the whole attribute tuple of the order the record describes (never the comment, the magic or the volume alone)
bool EN_TupleMatches(const SEnOrder &o,const SEnRecord &rec)
  {
   return(o.found && o.symbol==rec.symbol && o.type==EN_OType(rec.direction) && EN_Close(o.price,rec.e) && EN_Close(o.sl,rec.s) && EN_Close(o.tp,rec.tp) &&
          EN_Close(o.volume,rec.volume) && o.magic==rec.magic && (rec.expiry_mode==EN_EXP_GTC || o.expiration==rec.expiration));
  }

string EN_CoreUnset(const SEnConfig &c)
  {
   if(!c.enabled) return("DISABLED: the entry executor is off by default");
   if(c.ea_magic<=0) return("INPUT_UNSET: ea_magic");
   if(EN_Blank(c.symbol)) return("INPUT_UNSET: symbol");
   return("");
  }

string EN_ConfigUnset(const SEnConfig &c)
  {
   string bad=EN_CoreUnset(c);
   if(bad!="") return(bad);
   if(c.filling!=EN_FILL_RETURN && c.filling!=EN_FILL_IOC && c.filling!=EN_FILL_FOK) return("INPUT_UNSET: filling");
   if(c.filling!=EN_FILL_RETURN) return("FILLING_NOT_ALLOWED_FOR_PENDING: the documented rule for pending orders is ORDER_FILLING_RETURN");
   if(c.expiry_mode!=EN_EXP_GTC && c.expiry_mode!=EN_EXP_SECONDS) return("INPUT_UNSET: expiry_mode");
   if(c.expiry_mode==EN_EXP_SECONDS && !(c.expiry_seconds>0 && c.expiry_seconds<=31536000)) return("INPUT_UNSET: expiry_seconds");
   if(c.permit_max_age<=0) return("INPUT_UNSET: permit_max_age");
   if(c.quote_max_age<=0) return("INPUT_UNSET: quote_max_age");
   return("");
  }

string EN_PlanRefusal(const STpPlan &p)
  {
   if(p.status!=TP_OK || p.stage!=TP_STAGE_COMPLETE) return("PLAN_NOT_OK: only a COMPLETE OK plan can be placed");
   if(EN_PlanDigest(p)=="") return("PLAN_INVALID: ids, direction or numbers are not usable");
   if(!(p.e_out>0.0) || !(p.s_out>0.0) || !(p.tp>0.0) || !(p.volume_out>0.0)) return("PLAN_INVALID: a price or the volume is not positive");
   if(p.direction==1 && !(p.s_out<p.e_out && p.e_out<p.tp)) return("PLAN_INVALID: BUY needs SL < entry < TP");
   if(p.direction==-1 && !(p.tp<p.e_out && p.e_out<p.s_out)) return("PLAN_INVALID: SELL needs TP < entry < SL");
   return("");
  }

string EN_PermitRefusal(const SEnConfig &cfg,const STpPlan &plan,const SEnPermit &pm,const long now)
  {
   if(!pm.present) return("PERMIT_MISSING");
   if(!pm.allow) return("PERMIT_NOT_ALLOWED");
   if(pm.digest=="" || pm.digest!=EN_PlanDigest(plan)) return("PERMIT_FOR_ANOTHER_PLAN: the permit digest differs from this plan");
   if(pm.issued<=0 || pm.issued>now) return("PERMIT_TIME_INVALID: issued in the future or unset");
   if(now-pm.issued>cfg.permit_max_age) return("PERMIT_STALE: older than the configured maximum age");
   if(pm.valid_until>0 && now>pm.valid_until) return("PERMIT_EVIDENCE_EXPIRED: the evidence behind the permit is older than its validity allows");
   return("");
  }

string EN_MarketRefusal(const SEnConfig &cfg,const STpPlan &p,const SEnSymbol &sym,const SEnQuote &q,const long now)
  {
   if(!sym.read_ok || !(sym.tick_size>0.0) || !(sym.vol_step>0.0) || !(sym.point>0.0) || !sym.trade_ok) return("SYMBOL_UNREADABLE_OR_NOT_TRADABLE");
   if(!q.read_ok || !(q.bid>0.0) || !(q.ask>=q.bid) || q.time<=0 || q.time>now+EN_TIME_TOL || now-q.time>cfg.quote_max_age) return("QUOTE_UNUSABLE_OR_STALE");
   if(!EN_OnGrid(p.e_out,sym.tick_size) || !EN_OnGrid(p.s_out,sym.tick_size) || !EN_OnGrid(p.tp,sym.tick_size)) return("PRICE_NOT_ON_TICK_GRID: refused, never rounded");
   double steps=p.volume_out/sym.vol_step;
   if(!(p.volume_out>=sym.vol_min && p.volume_out<=sym.vol_max) || MathAbs(steps-MathRound(steps))>1e-6) return("VOLUME_OUTSIDE_SYMBOL_RULES: refused, never adjusted");
   double gap=(double)sym.stops_level*sym.point;
   if(p.direction==1 && !(p.e_out<=q.ask-gap)) return("LIMIT_ON_THE_WRONG_SIDE: a BUY_LIMIT must lie below the ask by at least the stops level");
   if(p.direction==-1 && !(p.e_out>=q.bid+gap)) return("LIMIT_ON_THE_WRONG_SIDE: a SELL_LIMIT must lie above the bid by at least the stops level");
   return("");
  }

string EN_RealGate(const SEnConfig &cfg,CEnTransport *tr,const SEnAccount &a)
  {
   if(tr.IsReal())
     {
      if(!(cfg.real_authorised && cfg.authorisation==EN_AUTH_PHRASE)) return("REAL_NOT_AUTHORISED");
      if(!a.read_ok || !a.demo) return("REAL_REQUIRES_DEMO_ACCOUNT");
     }
   return("");
  }

bool EN_IdentityOk(const SEnRecord &r,const SEnAccount &a,const SEnConfig &cfg,const string signal_id)
  {
   return(r.login==a.login && r.server==a.server && r.signal_id==signal_id && r.magic==cfg.ea_magic);
  }

// ------------------------------------------------------------------------------------------------ persistence helpers
// writes `next` as the successor of `cur`, reads it back; on success cur=next
bool EN_Commit(CEnStore *store,SEnRecord &cur,SEnRecord &next)
  {
   next.generation=cur.generation+1;
   string text,why;
   if(!EN_Encode(next,text,why)) return(false);
   string name=EN_FileName(cur.login,cur.signal_id);
   if(!store.Write(name,text)) return(false);
   string back;
   if(!store.Read(name,back) || back!=text) return(false);
   cur=next;
   return(true);
  }

// 0 = no file, 1 = record loaded, 2 = unusable (reason set)
int EN_Load(CEnStore *store,const string name,SEnRecord &rec,string &reason)
  {
   reason="";
   if(!store.Exists(name)) return(0);
   string text;
   if(!store.Read(name,text)) {reason="FILE_UNREADABLE"; return(2);}
   if(!EN_Decode(text,rec,reason)) return(2);
   return(1);
  }

// ------------------------------------------------------------------------------------------------ PLACE
void EN_PlaceLocked(const SEnConfig &cfg,CEnTransport *tr,CEnStore *store,SEnRuntime &rt,const STpPlan &plan,const SEnPermit &permit,const SEnAccount &acct,const long now,SEnResult &res)
  {
   string name=EN_FileName(acct.login,plan.signal_id);
   SEnRecord ex;
   string why;
   int kind=EN_Load(store,name,ex,why);
   if(kind==2) {EN_Res(res,EN_R_BLOCKED,"EXISTING_RECORD_UNUSABLE: "+why); return;}
   if(kind==1)
     {
      EN_Res(res,EN_R_DUPLICATE,"RECORD_EXISTS: state "+ex.state+"; one order per signal, nothing is sent",0,ex.state,ex.order_ticket,ex.position_id);
      return;
     }
   SEnSymbol sym;
   SEnQuote quote;
   tr.ReadSymbol(cfg.symbol,sym);
   tr.ReadQuote(cfg.symbol,quote);
   string bad=EN_MarketRefusal(cfg,plan,sym,quote,now);
   if(bad!="") {EN_Res(res,EN_R_REFUSED,bad); return;}
   SEnOrderList lst;
   tr.ListOrders(cfg.symbol,now-86400,lst);
   if(!lst.complete) {EN_Res(res,EN_R_REFUSED,"ORDER_LIST_INCOMPLETE: the existing orders cannot be proven"); return;}
   if(lst.n>EN_MAX_SNAP) {EN_Res(res,EN_R_REFUSED,"SNAPSHOT_TOO_LARGE"); return;}
   SEnRecord nw;
   EN_RecordInit(nw);
   long expiry=(cfg.expiry_mode==EN_EXP_GTC ? 0 : now+cfg.expiry_seconds);
   nw.login=acct.login;
   nw.server=acct.server;
   nw.symbol=cfg.symbol;
   nw.signal_id=plan.signal_id;
   nw.setup_id=plan.setup_id;
   nw.direction=plan.direction;
   nw.e=plan.e_out;
   nw.s=plan.s_out;
   nw.tp=plan.tp;
   nw.volume=plan.volume_out;
   nw.magic=cfg.ea_magic;
   nw.filling=cfg.filling;
   nw.expiry_mode=cfg.expiry_mode;
   nw.expiration=expiry;
   nw.t_intent=now;
   nw.req_id=EN_ReqId(plan.signal_id);
   nw.n_snap=lst.n;
   for(int i=0;i<lst.n;i++) nw.snap[i]=lst.o[i].ticket;
   for(int i=0;i<lst.n;i++)
      if(lst.o[i].state==EN_OS_ACTIVE && EN_TupleMatches(lst.o[i],nw)) {EN_Res(res,EN_R_REFUSED,"IDENTICAL_ORDER_ALREADY_PENDING: refused, nothing is sent"); return;}
   string text;
   if(!EN_Encode(nw,text,why)) {EN_Res(res,EN_R_REFUSED,"INTENT_NOT_ENCODABLE: "+why); return;}
   if(!store.Write(name,text)) {EN_Res(res,EN_R_BLOCKED,"INTENT_NOT_SAVED: zero sends"); return;}
   string back;
   if(!store.Read(name,back) || back!=text) {EN_Res(res,EN_R_BLOCKED,"INTENT_READBACK_DIFFERS: zero sends",0,EN_ST_INTENT); return;}
   SEnRequest req;
   req.type=EN_OType(plan.direction);
   req.symbol=nw.symbol;
   req.volume=nw.volume;
   req.price=nw.e;
   req.sl=nw.s;
   req.tp=nw.tp;
   req.expiry_mode=cfg.expiry_mode;
   req.expiration=expiry;
   req.filling=cfg.filling;
   req.magic=cfg.ea_magic;
   req.comment=nw.req_id;
   if(!tr.PreCheck(req))
     {
      SEnRecord nx=nw;
      nx.state=EN_ST_PRECHECK_REFUSED;
      nx.reason="PRECHECK_REFUSED";
      bool ok=EN_Commit(store,nw,nx);
      EN_Res(res,EN_R_PRECHECK_REFUSED,"PRECHECK_REFUSED: zero sends"+(ok ? "" : "; the state could not be saved (record stays INTENT)"),0,nw.state);
      return;
     }
   // time passed during the pre-check: permit, expiry and quote are judged AGAIN right before the send
   long now2=tr.ServerTime();
   bad=(now2>0 ? "" : "SERVER_TIME_UNREADABLE");
   if(bad=="") bad=EN_PermitRefusal(cfg,plan,permit,now2);
   if(bad=="" && cfg.expiry_mode==EN_EXP_SECONDS && expiry<=now2) bad="EXPIRATION_ALREADY_PASSED";
   if(bad=="")
     {
      SEnQuote quote2;
      tr.ReadQuote(cfg.symbol,quote2);
      bad=EN_MarketRefusal(cfg,plan,sym,quote2,now2);
     }
   if(bad!="")
     {
      SEnRecord nx=nw;
      nx.state=EN_ST_PRECHECK_REFUSED;
      nx.reason="ABORTED_BEFORE_SEND";
      bool ok=EN_Commit(store,nw,nx);
      EN_Res(res,EN_R_REFUSED,"ABORTED_BEFORE_SEND: "+bad+"; zero sends"+(ok ? "" : "; the state could not be saved (record stays INTENT)"),0,nw.state);
      return;
     }
   rt.send_calls++;
   SEnSendResult sr;
   tr.Send(req,sr);
   bool definite=false;
   int rcs[]={10006,10013,10014,10015,10016,10017,10018,10019,10022,10026,10027,10030};
   for(int i=0;i<ArraySize(rcs);i++)
      if(sr.retcode==rcs[i]) definite=true;
   if(sr.have_result && definite && sr.order==0)
     {
      SEnRecord nx=nw;
      nx.state=EN_ST_REJECTED;
      nx.attempts=1;
      nx.reason="REJECTED retcode "+IntegerToString(sr.retcode);
      if(!EN_Commit(store,nw,nx))
        {
         rt.latched=true;
         EN_Res(res,EN_R_RECOVERY,"REJECTED_NOT_SAVED: the attempt is on disk as INTENT; reconcile",1,EN_ST_INTENT);
         return;
        }
      EN_Res(res,EN_R_REJECTED,"REJECTED: retcode "+IntegerToString(sr.retcode)+", no order was created",1,EN_ST_REJECTED);
      return;
     }
   if(!(sr.have_result && (sr.retcode==EN_RC_PLACED || sr.retcode==EN_RC_DONE) && sr.order>0))
     {
      rt.latched=true;
      SEnRecord nx=nw;
      nx.state=EN_ST_RECOVERY;
      nx.attempts=1;
      nx.reason="UNCERTAIN_ANSWER retcode "+IntegerToString(sr.retcode);
      bool ok=EN_Commit(store,nw,nx);
      EN_Res(res,EN_R_RECOVERY,"UNCERTAIN_ANSWER: one attempt recorded, nothing is resent"+(ok ? "" : "; not saved (record stays INTENT)"),1,nw.state);
      return;
     }
   SEnOrder o;
   tr.ReadOrder(sr.order,o);
   bool in_snap=false;
   for(int i=0;i<nw.n_snap;i++)
      if(nw.snap[i]==sr.order) in_snap=true;
   if(o.found && o.ticket==sr.order && !in_snap && EN_TupleMatches(o,nw) && (o.state==EN_OS_ACTIVE || (o.state==EN_OS_FILLED && o.position_id>0)))
     {
      SEnRecord nx=nw;
      nx.attempts=1;
      nx.order_ticket=sr.order;
      nx.linked=1;
      if(o.state==EN_OS_ACTIVE) nx.state=EN_ST_PLACED;
      else
        {
         nx.state=EN_ST_FILLED;
         nx.position_id=o.position_id;
        }
      if(!EN_Commit(store,nw,nx))
        {
         rt.latched=true;
         EN_Res(res,EN_R_RECOVERY,"OUTCOME_NOT_SAVED: the attempt is on disk as INTENT; reconcile",1,EN_ST_INTENT,sr.order);
         return;
        }
      EN_Res(res,(nw.state==EN_ST_PLACED ? EN_R_PLACED : EN_R_FILLED),"LINKED: ticket from the response + the whole attribute tuple + not in the pre-send snapshot",1,nw.state,sr.order,nw.position_id);
      return;
     }
   rt.latched=true;
   SEnRecord nx=nw;
   nx.state=EN_ST_RECOVERY;
   nx.attempts=1;
   nx.reason="LINK_UNPROVEN ticket "+IntegerToString((long)sr.order);
   bool ok=EN_Commit(store,nw,nx);
   EN_Res(res,EN_R_RECOVERY,"LINK_UNPROVEN: the order of the response is not proven to be this one; nothing is resent"+(ok ? "" : "; not saved"),1,nw.state,sr.order);
  }

void EN_Place(const SEnConfig &cfg,CEnTransport *tr,CEnStore *store,SEnRuntime &rt,const STpPlan &plan,const SEnPermit &permit,SEnResult &res)
  {
   EN_Res(res,EN_R_NONE,"");
   string bad=EN_ConfigUnset(cfg);
   if(bad!="") {EN_Res(res,EN_R_REFUSED,bad); return;}
   if(rt.latched) {EN_Res(res,EN_R_REFUSED,"LATCHED: an earlier uncertainty on this executor; restart and reconcile first"); return;}
   if(rt.send_calls>=1) {EN_Res(res,EN_R_REFUSED,"DUPLICATE_CALL: a send was already made by this executor instance"); return;}
   bad=EN_PlanRefusal(plan);
   if(bad!="") {EN_Res(res,EN_R_REFUSED,bad); return;}
   long now=tr.ServerTime();
   if(!(now>0)) {EN_Res(res,EN_R_REFUSED,"SERVER_TIME_UNREADABLE"); return;}
   bad=EN_PermitRefusal(cfg,plan,permit,now);
   if(bad!="") {EN_Res(res,EN_R_REFUSED,bad); return;}
   SEnAccount acct;
   tr.ReadAccount(acct);
   bad=EN_RealGate(cfg,tr,acct);
   if(bad!="") {EN_Res(res,EN_R_REFUSED,bad); return;}
   if(!acct.read_ok || acct.login<=0 || EN_Blank(acct.server)) {EN_Res(res,EN_R_REFUSED,"ACCOUNT_UNREADABLE"); return;}
   if(!acct.trade_allowed) {EN_Res(res,EN_R_REFUSED,"TRADING_NOT_ALLOWED"); return;}
   if(acct.margin_mode!=2) {EN_Res(res,EN_R_REFUSED,"UNSUPPORTED_ACCOUNT_MODE: only HEDGING"); return;}
   string key=EN_LockKey(acct.login,plan.signal_id);
   if(!store.Lock(key)) {EN_Res(res,EN_R_LOCK_FAILED,"INSTANCE_LOCK_HELD_OR_UNAVAILABLE: zero sends"); return;}
   EN_PlaceLocked(cfg,tr,store,rt,plan,permit,acct,now,res);
   store.Unlock(key);
  }

// ------------------------------------------------------------------------------------------------ RECONCILE (never sends, never cancels)
// what the disk really holds now (a false write does not prove the old record is still there)
string EN_DiskState(CEnStore *store,const SEnRecord &rec)
  {
   SEnRecord tmp;
   string why;
   int kind=EN_Load(store,EN_FileName(rec.login,rec.signal_id),tmp,why);
   if(kind==1) return(tmp.state);
   return(kind==0 ? "NONE" : "UNUSABLE");
  }

// saves `nx` as the successor of `rec`; the result claims the new state ONLY when the save was verified, otherwise RECOVERY_REQUIRED with the state the disk really holds
void EN_Transition(CEnStore *store,SEnRecord &rec,SEnRecord &nx,const ENUM_EN_RESULT outcome,const string msg,const ulong ticket,const ulong pos,SEnResult &res)
  {
   string wanted=nx.state;
   if(EN_Commit(store,rec,nx)) {EN_Res(res,outcome,msg,0,rec.state,ticket,pos); return;}
   string disk=EN_DiskState(store,rec);
   EN_Res(res,EN_R_RECOVERY,"STATE_NOT_SAVED: "+wanted+" ("+msg+"); the disk holds "+disk+"; nothing is resent",0,disk,ticket,0);
  }

void EN_ScanForOrder(const SEnConfig &cfg,CEnTransport *tr,CEnStore *store,SEnRecord &rec,SEnResult &res)
  {
   SEnOrderList lst;
   tr.ListOrders(rec.symbol,rec.t_intent-EN_TIME_TOL,lst);
   if(!lst.complete) {EN_Res(res,EN_R_RECOVERY,"ORDER_LIST_INCOMPLETE: nothing can be concluded",0,rec.state); return;}
   int cand[EN_MAX_ORDERS];
   int nc=0;
   for(int i=0;i<lst.n;i++)
     {
      bool in_snap=false;
      for(int j=0;j<rec.n_snap;j++)
         if(rec.snap[j]==lst.o[i].ticket) in_snap=true;
      if(!in_snap && lst.o[i].time_setup>=rec.t_intent-EN_TIME_TOL && EN_TupleMatches(lst.o[i],rec))
        {
         cand[nc]=i;
         nc++;
        }
     }
   SEnRecord nx=rec;
   if(nc>1)
     {
      nx.state=EN_ST_BLOCKED;
      nx.reason="AMBIGUOUS_CANDIDATES "+IntegerToString(nc);
      EN_Transition(store,rec,nx,EN_R_BLOCKED,"AMBIGUOUS_CANDIDATES: more than one order fits; none is chosen",0,0,res);
      return;
     }
   if(nc==0)
     {
      if(rec.state==EN_ST_INTENT)
        {
         nx.state=EN_ST_RECOVERY;
         nx.attempts=1;
         nx.reason="INTENT_WITHOUT_ORDER";
         EN_Transition(store,rec,nx,EN_R_RECOVERY,"INTENT_WITHOUT_PROOF: the send may or may not have happened; nothing is resent",0,0,res);
         return;
        }
      EN_Res(res,EN_R_RECOVERY,"NO_CANDIDATE: nothing is resent",0,rec.state);
      return;
     }
   SEnOrder o=lst.o[cand[0]];
   nx.attempts=1;
   nx.order_ticket=o.ticket;
   nx.linked=1;
   if(o.state==EN_OS_ACTIVE)
     {
      nx.state=EN_ST_PLACED;
      nx.reason="LINKED_BY_RECOVERY";
      EN_Transition(store,rec,nx,EN_R_PLACED,"LINKED_BY_RECOVERY: unique tuple match outside the snapshot",o.ticket,0,res);
      return;
     }
   if(o.state==EN_OS_FILLED && o.position_id>0)
     {
      nx.state=EN_ST_FILLED;
      nx.position_id=o.position_id;
      nx.reason="LINKED_BY_RECOVERY_FILLED";
      EN_Transition(store,rec,nx,EN_R_FILLED,"LINKED_BY_RECOVERY_FILLED",o.ticket,o.position_id,res);
      return;
     }
   if(o.state==EN_OS_CANCELED || o.state==EN_OS_REJECTED)
     {
      nx.state=EN_ST_CANCELLED;
      nx.reason="LINKED_BY_RECOVERY_ENDED";
      EN_Transition(store,rec,nx,EN_R_CANCELLED,"LINKED_BY_RECOVERY_ENDED",o.ticket,0,res);
      return;
     }
   if(o.state==EN_OS_EXPIRED)
     {
      nx.state=EN_ST_EXPIRED;
      nx.reason="LINKED_BY_RECOVERY_EXPIRED";
      EN_Transition(store,rec,nx,EN_R_EXPIRED,"LINKED_BY_RECOVERY_EXPIRED",o.ticket,0,res);
      return;
     }
   EN_Res(res,EN_R_RECOVERY,"CANDIDATE_STATE_UNUSABLE",0,rec.state);
  }

void EN_ReconcileLocked(const SEnConfig &cfg,CEnTransport *tr,CEnStore *store,const SEnAccount &acct,const string signal_id,SEnResult &res)
  {
   SEnRecord rec;
   string why;
   int kind=EN_Load(store,EN_FileName(acct.login,signal_id),rec,why);
   if(kind==0) {EN_Res(res,EN_R_NONE,"NO_RECORD"); return;}
   if(kind==2) {EN_Res(res,EN_R_BLOCKED,"RECORD_UNUSABLE: "+why); return;}
   if(!EN_IdentityOk(rec,acct,cfg,signal_id)) {EN_Res(res,EN_R_BLOCKED,"IDENTITY_MISMATCH: the record belongs to another account, signal or magic"); return;}
   string st=rec.state;
   if(st==EN_ST_PRECHECK_REFUSED || st==EN_ST_REJECTED || st==EN_ST_CANCELLED || st==EN_ST_EXPIRED || st==EN_ST_BLOCKED || st==EN_ST_FILLED)
     {
      EN_Res(res,EN_R_NOCHANGE,"TERMINAL_STATE "+st,0,st,rec.order_ticket,rec.position_id);
      return;
     }
   if((st==EN_ST_INTENT || st==EN_ST_RECOVERY) && rec.linked==0)
     {
      EN_ScanForOrder(cfg,tr,store,rec,res);
      return;
     }
   SEnOrder o;
   tr.ReadOrder(rec.order_ticket,o);
   ulong tk=rec.order_ticket;
   SEnRecord nx=rec;
   if(!o.found)
     {
      if(st==EN_ST_RECOVERY) {EN_Res(res,EN_R_RECOVERY,"ORDER_NOT_FOUND: cannot prove what happened to the order",0,st,tk); return;}
      nx.state=EN_ST_RECOVERY;
      nx.reason="ORDER_NOT_FOUND";
      EN_Transition(store,rec,nx,EN_R_RECOVERY,"ORDER_NOT_FOUND: cannot prove what happened to the order",tk,0,res);
      return;
     }
   if(o.ticket!=rec.order_ticket || !(o.symbol==rec.symbol && o.type==EN_OType(rec.direction) && o.magic==rec.magic))
     {
      nx.state=EN_ST_BLOCKED;
      nx.reason="ORDER_IDENTITY_CHANGED";
      EN_Transition(store,rec,nx,EN_R_BLOCKED,"ORDER_IDENTITY_CHANGED",tk,0,res);
      return;
     }
   if(o.state==EN_OS_ACTIVE)
     {
      if(!EN_TupleMatches(o,rec))
        {
         nx.state=EN_ST_BLOCKED;
         nx.reason="ORDER_MODIFIED";
         EN_Transition(store,rec,nx,EN_R_BLOCKED,"ORDER_MODIFIED: the pending order no longer matches the plan; it is not touched",tk,0,res);
         return;
        }
      if(st==EN_ST_CANCEL_UNCERTAIN)
        {
         nx.state=EN_ST_PLACED;
         nx.reason="CANCEL_NOT_EFFECTIVE";
         EN_Transition(store,rec,nx,EN_R_PLACED,"STILL_ACTIVE: the cancellation did not take effect",tk,0,res);
         return;
        }
      if(st==EN_ST_RECOVERY)
        {
         nx.state=EN_ST_PLACED;
         nx.reason="RECOVERED_ACTIVE";
         EN_Transition(store,rec,nx,EN_R_PLACED,"RECOVERED_ACTIVE",tk,0,res);
         return;
        }
      EN_Res(res,EN_R_NOCHANGE,"ACTIVE",0,st,tk);
      return;
     }
   if(o.state==EN_OS_FILLED)
     {
      if(o.position_id==0 || !EN_TupleMatches(o,rec))
        {
         nx.state=EN_ST_RECOVERY;
         nx.reason="FILLED_WITHOUT_PROOF";
         EN_Transition(store,rec,nx,EN_R_RECOVERY,"FILLED_WITHOUT_PROOF",tk,0,res);
         return;
        }
      nx.state=EN_ST_FILLED;
      nx.position_id=o.position_id;
      nx.reason="FILLED";
      EN_Transition(store,rec,nx,EN_R_FILLED,"FILLED: position id from the order history",tk,o.position_id,res);
      return;
     }
   if(o.state==EN_OS_CANCELED || o.state==EN_OS_REJECTED)
     {
      nx.state=EN_ST_CANCELLED;
      nx.reason=(o.state==EN_OS_CANCELED ? "ORDER_CANCELED" : "ORDER_REJECTED");
      EN_Transition(store,rec,nx,EN_R_CANCELLED,nx.reason,tk,0,res);
      return;
     }
   if(o.state==EN_OS_EXPIRED)
     {
      nx.state=EN_ST_EXPIRED;
      nx.reason="ORDER_EXPIRED";
      EN_Transition(store,rec,nx,EN_R_EXPIRED,"ORDER_EXPIRED",tk,0,res);
      return;
     }
   nx.state=EN_ST_RECOVERY;
   nx.reason="ORDER_STATE_UNKNOWN";
   EN_Transition(store,rec,nx,EN_R_RECOVERY,"ORDER_STATE_UNKNOWN",tk,0,res);
  }

void EN_Reconcile(const SEnConfig &cfg,CEnTransport *tr,CEnStore *store,const string signal_id,SEnResult &res)
  {
   EN_Res(res,EN_R_NONE,"");
   string bad=EN_CoreUnset(cfg);
   if(bad!="") {EN_Res(res,EN_R_REFUSED,bad); return;}
   SEnAccount acct;
   tr.ReadAccount(acct);
   if(!acct.read_ok || acct.login<=0 || EN_Blank(acct.server)) {EN_Res(res,EN_R_REFUSED,"ACCOUNT_UNREADABLE"); return;}
   if(EN_Blank(signal_id)) {EN_Res(res,EN_R_REFUSED,"SIGNAL_ID_EMPTY"); return;}
   string key=EN_LockKey(acct.login,signal_id);
   if(!store.Lock(key)) {EN_Res(res,EN_R_LOCK_FAILED,"INSTANCE_LOCK_HELD_OR_UNAVAILABLE"); return;}
   EN_ReconcileLocked(cfg,tr,store,acct,signal_id,res);
   store.Unlock(key);
  }

// ------------------------------------------------------------------------------------------------ CANCEL
void EN_CancelLocked(const SEnConfig &cfg,CEnTransport *tr,CEnStore *store,SEnRuntime &rt,const SEnAccount &acct,const string signal_id,SEnResult &res)
  {
   SEnRecord rec;
   string why;
   int kind=EN_Load(store,EN_FileName(acct.login,signal_id),rec,why);
   if(kind==0) {EN_Res(res,EN_R_REFUSED,"NO_RECORD: there is no order of this EA for the signal"); return;}
   if(kind==2) {EN_Res(res,EN_R_BLOCKED,"RECORD_UNUSABLE: "+why); return;}
   if(!EN_IdentityOk(rec,acct,cfg,signal_id)) {EN_Res(res,EN_R_BLOCKED,"IDENTITY_MISMATCH"); return;}
   if(rec.state!=EN_ST_PLACED || rec.linked!=1) {EN_Res(res,EN_R_REFUSED,"NOT_A_PROVEN_PENDING_ORDER: state "+rec.state+"; reconcile first",0,rec.state,rec.order_ticket); return;}
   if(rec.cancel_attempts>=1) {EN_Res(res,EN_R_REFUSED,"CANCEL_ALREADY_ATTEMPTED: the record stores one cancellation; there is no automatic second one",0,rec.state,rec.order_ticket); return;}
   SEnOrder o;
   tr.ReadOrder(rec.order_ticket,o);
   if(!(o.found && o.ticket==rec.order_ticket && o.state==EN_OS_ACTIVE && EN_TupleMatches(o,rec) && o.magic==cfg.ea_magic))
     {
      EN_Res(res,EN_R_REFUSED,"ORDER_NOT_PROVEN_AS_THE_EAS_ACTIVE_PENDING: nothing is cancelled",0,rec.state,rec.order_ticket);
      return;
     }
   SEnRecord nx=rec;
   nx.state=EN_ST_CANCEL_UNCERTAIN;
   nx.cancel_attempts=1;
   nx.reason="CANCEL_INTENT";
   ulong ticket=rec.order_ticket;
   if(!EN_Commit(store,rec,nx)) {EN_Res(res,EN_R_BLOCKED,"CANCEL_INTENT_NOT_SAVED: nothing is cancelled",0,rec.state,ticket); return;}
   rt.cancel_calls++;
   SEnCancelResult cr;
   tr.Cancel(ticket,cr);
   if(cr.have_result && cr.retcode==EN_RC_DONE)
     {
      SEnOrder o2;
      tr.ReadOrder(ticket,o2);
      if(o2.found && o2.ticket==ticket && o2.state==EN_OS_CANCELED)
        {
         SEnRecord n3=rec;
         n3.state=EN_ST_CANCELLED;
         n3.reason="CANCELLED_BY_EA";
         if(!EN_Commit(store,rec,n3)) {EN_Res(res,EN_R_CANCEL_UNCERTAIN,"CANCELLED_NOT_SAVED: reconcile",0,EN_ST_CANCEL_UNCERTAIN,ticket); return;}
         EN_Res(res,EN_R_CANCELLED,"CANCELLED: confirmed by the order read back",0,rec.state,ticket);
         return;
        }
     }
   EN_Res(res,EN_R_CANCEL_UNCERTAIN,"CANCEL_UNCERTAIN: no retry; reconcile reads the order",0,EN_ST_CANCEL_UNCERTAIN,ticket);
  }

void EN_Cancel(const SEnConfig &cfg,CEnTransport *tr,CEnStore *store,SEnRuntime &rt,const string signal_id,const STpCancel &decision,SEnResult &res)
  {
   EN_Res(res,EN_R_NONE,"");
   string bad=EN_CoreUnset(cfg);
   if(bad!="") {EN_Res(res,EN_R_REFUSED,bad); return;}
   if(rt.cancel_calls>=1) {EN_Res(res,EN_R_REFUSED,"DUPLICATE_CALL: a cancellation was already made by this executor instance"); return;}
   if(EN_Blank(signal_id)) {EN_Res(res,EN_R_REFUSED,"SIGNAL_ID_EMPTY"); return;}
   if(decision.status!=TP_CANCEL_REQUEST || !decision.cancel_pending || decision.pending_signal_id!=signal_id) {EN_Res(res,EN_R_REFUSED,"CANCEL_DECISION_NOT_FOR_THIS_SIGNAL"); return;}
   SEnAccount acct;
   tr.ReadAccount(acct);
   bad=EN_RealGate(cfg,tr,acct);
   if(bad!="") {EN_Res(res,EN_R_REFUSED,bad); return;}
   if(!acct.read_ok || acct.login<=0 || EN_Blank(acct.server)) {EN_Res(res,EN_R_REFUSED,"ACCOUNT_UNREADABLE"); return;}
   string key=EN_LockKey(acct.login,signal_id);
   if(!store.Lock(key)) {EN_Res(res,EN_R_LOCK_FAILED,"INSTANCE_LOCK_HELD_OR_UNAVAILABLE: zero cancellations"); return;}
   EN_CancelLocked(cfg,tr,store,rt,acct,signal_id,res);
   store.Unlock(key);
  }
#endif
