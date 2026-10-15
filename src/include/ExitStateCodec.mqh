// T011 persistence of the 2R partial-close state: PURE codec + restore decision. Mirrors tests/t011_persist_reference.py (its header documents the
// format, the restore verdicts and the limits in full). NOT a trading module and NOT a file module: no file, no terminal, no clock, no order, no retry.
// It turns the caller-owned SEaState (ExitActivation.mqh, not modified) plus identity / send phase / order map into a versioned, checksummed text and
// back, and decides what a restored text may do. A restored state is NEVER proof that a request was executed: reconciliation with the broker comes first.
// Unusable input (missing, damaged, truncated, other version, other identity, leftover temp file, invalid combination, uncertain send) returns a
// BLOCKED / NEEDS_RECONCILIATION state so that EA_OnQuote cannot produce a request. No map is invented, nothing is retried.
#ifndef VELO_EXIT_STATE_CODEC_MQH
#define VELO_EXIT_STATE_CODEC_MQH

#include "ExitActivation.mqh"

#define ESC_VERSION 3             // 3 adds the declared R basis (PLAN_RPOL, PLAN_E_SRC, PLAN_S_SRC, PLAN_E_OUT, PLAN_S_OUT); version 1 and 2 records are never migrated
#define ESC_RPOL_NONE 0
#define ESC_RPOL_TYPED 1          // a typed diagnostic level: no E / S basis
#define ESC_RPOL_R_GEOM 2         // the level was derived by TG_Compute from the stored E and S (R itself is NOT stored)
#define ESC_BASIS_TOL 1e-9        // relative: source price vs its normalized value (floating-point noise only)
#define ESC_HEADER "VELO_EXIT_STATE"
#define ESC_MAX_ORDERS 8          // equals XA_MAX_ORDERS of ExitSnapshotAdapter.mqh (checked statically; that header is not included here)
#define ESC_MAX_TEXT 4096
#define ESC_MAX_STR 1024
#define ESC_MAX_GEN 2147483647
#define ESC_MAX_COUNT 100000
#define ESC_MAX_ID 999999999999999999     // identifiers are written with at most 18 digits
#define ESC_SEND_NONE 0
#define ESC_SEND_INTENT 1
#define ESC_SEND_MAPPED 2

enum ENUM_ESC_VERDICT
  {
   ESC_USABLE_IDLE=0,
   ESC_USABLE_REQUEST,
   ESC_USABLE_BLOCKED,
   ESC_RECOVERY_REQUIRED
  };

struct SEsIdentity
  {
   string server;
   long login;
   string symbol;
   ulong position_id;
  };

struct SEsRecord
  {
   int generation;
   SEsIdentity id;
   SEaState state;
   int send_phase;
   bool map_complete;
   int n_orders;
   ulong orders[ESC_MAX_ORDERS];
   bool plan_set;             // the AUTHORISED plan stored at registration: direction / level 2R / initial volume live in the bound state, TP and min / step / max here
   double plan_tp;
   double plan_vol_min;
   double plan_vol_step;
   double plan_vol_max;
   int plan_rpol;
   double plan_e_src;         // R_GEOM: the declared entry / initial stop as read ...
   double plan_s_src;
   double plan_e_out;         // ... and the values TG_Compute normalized them to
   double plan_s_out;
  };

struct SEsRestore
  {
   ENUM_ESC_VERDICT verdict;
   string reason;
   bool new_request_allowed;
   bool reconcile_required;
   bool map_complete;
   int n_orders;
   ulong orders[ESC_MAX_ORDERS];
   int generation;
   bool plan_set;
   double plan_tp;
   double plan_vol_min;
   double plan_vol_step;
   double plan_vol_max;
   int plan_rpol;
   double plan_e_src;
   double plan_s_src;
   double plan_e_out;
   double plan_s_out;
  };

string ESC_VerdictName(const ENUM_ESC_VERDICT v)
  {
   switch(v)
     {
      case ESC_USABLE_IDLE: return("USABLE_IDLE");
      case ESC_USABLE_REQUEST: return("USABLE_REQUEST");
      case ESC_USABLE_BLOCKED: return("USABLE_BLOCKED");
      case ESC_RECOVERY_REQUIRED: return("RECOVERY_REQUIRED");
     }
   return("UNKNOWN");
  }

void ESC_RecordInit(SEsRecord &r)
  {
   r.generation=0;
   r.id.server="";
   r.id.login=0;
   r.id.symbol="";
   r.id.position_id=0;
   EA_StateInit(r.state);
   r.send_phase=ESC_SEND_NONE;
   r.map_complete=false;
   r.n_orders=0;
   for(int i=0;i<ESC_MAX_ORDERS;i++)
      r.orders[i]=0;
   r.plan_set=false;
   r.plan_tp=0.0;
   r.plan_vol_min=0.0;
   r.plan_vol_step=0.0;
   r.plan_vol_max=0.0;
   r.plan_rpol=ESC_RPOL_NONE;
   r.plan_e_src=0.0;
   r.plan_s_src=0.0;
   r.plan_e_out=0.0;
   r.plan_s_out=0.0;
  }

bool ESC_IdentityEqual(const SEsIdentity &a,const SEsIdentity &b)
  {
   return(a.server==b.server && a.login==b.login && a.symbol==b.symbol && a.position_id==b.position_id);
  }

// ---- CRC-32 (reflected, poly EDB88320), over the 8-bit value of each character (the text is ASCII by construction)
uint ESC_Crc32(const string text)
  {
   uint crc=0xFFFFFFFF;
   int n=StringLen(text);
   for(int i=0;i<n;i++)
     {
      crc^=(uint)(StringGetCharacter(text,i)&0xFF);
      for(int k=0;k<8;k++)
         crc=((crc&1)!=0 ? (crc>>1)^0xEDB88320 : (crc>>1));
     }
   return(crc^0xFFFFFFFF);
  }

bool ESC_IsLiteral(const ushort c)
  {
   return((c>='A' && c<='Z') || (c>='a' && c<='z') || (c>='0' && c<='9') || c=='.' || c=='_' || c=='-');
  }

string ESC_Escape(const string s)
  {
   string out="";
   int n=StringLen(s);
   for(int i=0;i<n;i++)
     {
      ushort c=StringGetCharacter(s,i);
      if(ESC_IsLiteral(c)) out+=ShortToString(c);
      else out+=StringFormat("%%%04X",(int)c);
     }
   return(out);
  }

int ESC_HexVal(const ushort c)
  {
   if(c>='0' && c<='9') return((int)c-'0');
   if(c>='A' && c<='F') return((int)c-'A'+10);
   return(-1);
  }

// false when the text is not a valid escaped string
bool ESC_Unescape(const string s,string &out)
  {
   out="";
   int n=StringLen(s);
   int i=0;
   while(i<n)
     {
      ushort c=StringGetCharacter(s,i);
      if(c=='%')
        {
         if(i+5>n) return(false);
         int v=0;
         for(int k=1;k<=4;k++)
           {
            int h=ESC_HexVal(StringGetCharacter(s,i+k));
            if(h<0) return(false);
            v=v*16+h;
           }
         out+=ShortToString((ushort)v);
         i+=5;
        }
      else
         if(ESC_IsLiteral(c))
           {
            out+=ShortToString(c);
            i++;
           }
         else
            return(false);
     }
   return(true);
  }

// canonical decimal text of a double with 12 decimals, only when it parses back to the identical double
bool ESC_Fnum(const double x,string &out)
  {
   out="";
   if(!(x==x && x-x==0.0)) return(false);
   string t=DoubleToString(x+0.0,12);
   if(StringToDouble(t)!=x) return(false);
   out=t;
   return(true);
  }

bool ESC_ParseInt(const string s,long &v)
  {
   v=0;
   if(s=="" || StringLen(s)>18) return(false);
   long x=StringToInteger(s);
   if(IntegerToString(x)!=s) return(false);       // canonical: no sign other than '-', no leading zeros, no "-0"
   v=x;
   return(true);
  }

bool ESC_ParseDouble(const string s,double &v)
  {
   v=0.0;
   if(s=="" || StringLen(s)>34) return(false);
   int dot=StringFind(s,".");
   if(dot<=0 || StringLen(s)-dot-1!=12) return(false);
   double x=StringToDouble(s);
   if(DoubleToString(x,12)!=s) return(false);
   v=x;
   return(true);
  }

bool ESC_FiniteNonNegative(const double x) {return(x==x && x-x==0.0 && x>=0.0);}

bool ESC_CloseTo(const double a,const double b)
  {
   double m=MathMax(1.0,MathMax(MathAbs(a),MathAbs(b)));
   return(MathAbs(a-b)<=1e-9*m);
  }

// "" when the record is valid, otherwise the first reason
string ESC_Validate(const SEsRecord &r)
  {
   if(r.generation<1) return("INVALID_GENERATION");           // int: the upper bound ESC_MAX_GEN is enforced at parse time, before the cast
   if(StringLen(r.id.server)<1 || StringLen(r.id.server)>128) return("INVALID_IDENTITY: server");
   if(r.id.login<1) return("INVALID_IDENTITY: login");
   if(StringLen(r.id.symbol)<1 || StringLen(r.id.symbol)>32) return("INVALID_IDENTITY: symbol");
   if(r.id.position_id<1 || r.id.position_id>ESC_MAX_ID) return("INVALID_IDENTITY: position");
   SEaState st;
   st=r.state;
   if((int)st.status<(int)EA_ST_IDLE || (int)st.status>(int)EA_ST_BLOCKED) return("INVALID_STATUS");
   if(st.direction!=0 && st.direction!=1 && st.direction!=-1) return("INVALID_STATE: bound/direction");
   if(!ESC_FiniteNonNegative(st.level)) return("INVALID_STATE: level");
   if(!ESC_FiniteNonNegative(st.volume_initial)) return("INVALID_STATE: volume_initial");
   if(!ESC_FiniteNonNegative(st.volume_step)) return("INVALID_STATE: volume_step");
   if(!ESC_FiniteNonNegative(st.close_volume)) return("INVALID_STATE: close_volume");
   string t;
   if(!ESC_Fnum(st.level,t) || !ESC_Fnum(st.volume_initial,t) || !ESC_Fnum(st.volume_step,t) || !ESC_Fnum(st.close_volume,t))
      return("INVALID_STATE: a value is not exactly representable with 12 decimals");
   if(st.position_id>ESC_MAX_ID) return("INVALID_STATE: position_id");
   if(st.request_steps<0 || st.initial_steps<0 || st.executed_steps<0) return("INVALID_STATE: steps");
   if(st.confirmations<0 || st.confirmations>ESC_MAX_COUNT || st.duplicates_ignored<0 || st.duplicates_ignored>ESC_MAX_COUNT) return("INVALID_STATE: counters");
   if(StringLen(st.request_id)>64 || StringLen(st.reason)>ESC_MAX_STR) return("INVALID_STATE: text");
   if(r.send_phase!=ESC_SEND_NONE && r.send_phase!=ESC_SEND_INTENT && r.send_phase!=ESC_SEND_MAPPED) return("INVALID_SEND_PHASE");
   if(r.n_orders<0 || r.n_orders>ESC_MAX_ORDERS) return("INVALID_MAP: at most 8 order tickets");
   for(int i=0;i<r.n_orders;i++)
     {
      if(r.orders[i]<1 || r.orders[i]>ESC_MAX_ID) return("INVALID_MAP: order tickets must be distinct positive integers, at most 8");
      for(int j=0;j<i;j++)
         if(r.orders[j]==r.orders[i]) return("INVALID_MAP: order tickets must be distinct positive integers, at most 8");
     }
   if(r.send_phase==ESC_SEND_MAPPED && r.n_orders==0) return("INVALID_MAP: send phase MAPPED without an order ticket");
   if(r.send_phase!=ESC_SEND_MAPPED && (r.n_orders>0 || r.map_complete)) return("INVALID_MAP: order tickets or completeness without send phase MAPPED");
   if(st.bound && (st.position_id!=r.id.position_id || st.direction==0 || st.level<=0.0 || st.volume_initial<=0.0))
      return("INVALID_STATE: bound state does not match the identity or lacks direction/level/volume");
   if(!st.bound && (st.position_id!=0 || st.direction!=0 || st.level!=0.0 || st.volume_initial!=0.0))
      return("INVALID_STATE: unbound state carries values");
   if(!ESC_FiniteNonNegative(r.plan_tp) || !ESC_FiniteNonNegative(r.plan_vol_min) || !ESC_FiniteNonNegative(r.plan_vol_step) || !ESC_FiniteNonNegative(r.plan_vol_max))
      return("INVALID_PLAN: a value is not finite and non-negative");
   if(!ESC_Fnum(r.plan_tp,t) || !ESC_Fnum(r.plan_vol_min,t) || !ESC_Fnum(r.plan_vol_step,t) || !ESC_Fnum(r.plan_vol_max,t))
      return("INVALID_PLAN: a value is not exactly representable with 12 decimals");
   if(r.plan_rpol!=ESC_RPOL_NONE && r.plan_rpol!=ESC_RPOL_TYPED && r.plan_rpol!=ESC_RPOL_R_GEOM) return("INVALID_PLAN: plan_rpol");
   if(!ESC_FiniteNonNegative(r.plan_e_src) || !ESC_FiniteNonNegative(r.plan_s_src) || !ESC_FiniteNonNegative(r.plan_e_out) || !ESC_FiniteNonNegative(r.plan_s_out))
      return("INVALID_PLAN: a basis value is not finite and non-negative");
   if(!ESC_Fnum(r.plan_e_src,t) || !ESC_Fnum(r.plan_s_src,t) || !ESC_Fnum(r.plan_e_out,t) || !ESC_Fnum(r.plan_s_out,t))
      return("INVALID_PLAN: a basis value is not exactly representable with 12 decimals");
   bool basis_any=(r.plan_e_src!=0.0 || r.plan_s_src!=0.0 || r.plan_e_out!=0.0 || r.plan_s_out!=0.0);
   if(!r.plan_set && (r.plan_tp!=0.0 || r.plan_vol_min!=0.0 || r.plan_vol_step!=0.0 || r.plan_vol_max!=0.0 || r.plan_rpol!=ESC_RPOL_NONE || basis_any)) return("INVALID_PLAN: values without plan_set");
   if(r.plan_set)
     {
      if(!st.bound) return("INVALID_PLAN: a plan needs a bound state (direction, level, initial volume)");
      if(r.plan_tp<=0.0 || r.plan_vol_min<=0.0 || r.plan_vol_step<=0.0 || r.plan_vol_max<r.plan_vol_min) return("INVALID_PLAN: tp and the volume parameters must be positive and min <= max");
      if(st.status!=EA_ST_IDLE && st.status!=EA_ST_BLOCKED && st.volume_step!=r.plan_vol_step) return("INVALID_PLAN: the request step differs from the authorised plan step");
      if(r.plan_rpol==ESC_RPOL_NONE) return("INVALID_PLAN: the R policy of a plan must be set");
      if(r.plan_rpol==ESC_RPOL_TYPED && basis_any) return("INVALID_PLAN: a typed diagnostic level carries no E / S basis");
      if(r.plan_rpol==ESC_RPOL_R_GEOM)
        {
         if(r.plan_e_src<=0.0 || r.plan_s_src<=0.0 || r.plan_e_out<=0.0 || r.plan_s_out<=0.0) return("INVALID_PLAN: the R_GEOM basis (E and S, source and normalized) must be positive");
         if(MathAbs(r.plan_e_src-r.plan_e_out)>ESC_BASIS_TOL*MathMax(1.0,r.plan_e_src) || MathAbs(r.plan_s_src-r.plan_s_out)>ESC_BASIS_TOL*MathMax(1.0,r.plan_s_src))
            return("INVALID_PLAN: the normalized basis differs from the declared source");
         if(st.direction==1 && !(r.plan_s_out<r.plan_e_out && r.plan_e_out<st.level)) return("INVALID_PLAN: BUY needs stop < entry < level 2R");
         if(st.direction==-1 && !(st.level<r.plan_e_out && r.plan_e_out<r.plan_s_out)) return("INVALID_PLAN: SELL needs level 2R < entry < stop");
        }
     }
   if(st.status==EA_ST_BLOCKED)
      return(st.reason!="" ? "" : "INVALID_STATE: BLOCKED without a reason");
   if(st.status==EA_ST_IDLE)
     {
      if(r.send_phase!=ESC_SEND_NONE || st.request_id!="" || st.request_steps!=0 || st.close_volume!=0.0 || st.initial_steps!=0 || st.executed_steps!=0 ||
         st.confirmations!=0 || st.duplicates_ignored!=0 || st.volume_step!=0.0)
         return("INVALID_STATE: IDLE with request data or a send phase");
      return("");
     }
   if(!st.bound || st.volume_step<=0.0 || st.initial_steps<=0 || st.initial_steps%5!=0)
      return("INVALID_STATE: request without a valid plan");
   if(st.request_id!=EA_RequestId(r.id.position_id) || st.request_steps!=4*st.initial_steps/5)
      return("INVALID_STATE: request id or 80% steps do not match the plan");
   if(!ESC_CloseTo(st.close_volume,(double)st.request_steps*st.volume_step) || !ESC_CloseTo(st.volume_initial,(double)st.initial_steps*st.volume_step))
      return("INVALID_STATE: volumes do not match the steps");
   if(r.send_phase==ESC_SEND_NONE) return("INVALID_STATE: request without a persisted send intent");
   if(st.executed_steps>st.request_steps || st.confirmations>1) return("INVALID_STATE: executed steps or confirmations");
   if(st.status==EA_ST_REQUEST_PENDING && (st.executed_steps!=0 || st.confirmations!=0)) return("INVALID_STATE: PENDING with executions or a confirmation");
   if(st.status==EA_ST_DONE && (st.executed_steps!=st.request_steps || st.confirmations!=1)) return("INVALID_STATE: DONE without exactly one confirmation of the requested steps");
   return("");
  }

// true and the text, or false and the reason; an invalid record is never written
bool ESC_Encode(const SEsRecord &r,string &text,string &reason)
  {
   text="";
   reason=ESC_Validate(r);
   if(reason!="") return(false);
   SEaState st;
   st=r.state;
   string lv,vi,vs,cv;
   ESC_Fnum(st.level,lv);
   ESC_Fnum(st.volume_initial,vi);
   ESC_Fnum(st.volume_step,vs);
   ESC_Fnum(st.close_volume,cv);
   string b=ESC_HEADER+"\n";
   b+="VERSION="+IntegerToString(ESC_VERSION)+"\n";
   b+="GEN="+IntegerToString(r.generation)+"\n";
   b+="SERVER="+ESC_Escape(r.id.server)+"\n";
   b+="LOGIN="+IntegerToString(r.id.login)+"\n";
   b+="SYMBOL="+ESC_Escape(r.id.symbol)+"\n";
   b+="POSITION="+IntegerToString((long)r.id.position_id)+"\n";
   b+="STATUS="+IntegerToString((int)st.status)+"\n";
   b+="BOUND="+IntegerToString(st.bound ? 1 : 0)+"\n";
   b+="STATE_POSITION="+IntegerToString((long)st.position_id)+"\n";
   b+="DIRECTION="+IntegerToString(st.direction)+"\n";
   b+="LEVEL="+lv+"\n";
   b+="VOLUME_INITIAL="+vi+"\n";
   b+="VOLUME_STEP="+vs+"\n";
   b+="REQUEST_ID="+ESC_Escape(st.request_id)+"\n";
   b+="REQUEST_STEPS="+IntegerToString(st.request_steps)+"\n";
   b+="CLOSE_VOLUME="+cv+"\n";
   b+="INITIAL_STEPS="+IntegerToString(st.initial_steps)+"\n";
   b+="EXECUTED_STEPS="+IntegerToString(st.executed_steps)+"\n";
   b+="CONFIRMATIONS="+IntegerToString(st.confirmations)+"\n";
   b+="DUPLICATES="+IntegerToString(st.duplicates_ignored)+"\n";
   b+="REASON="+ESC_Escape(st.reason)+"\n";
   b+="SEND_PHASE="+IntegerToString(r.send_phase)+"\n";
   b+="MAP_COMPLETE="+IntegerToString(r.map_complete ? 1 : 0)+"\n";
   string ptp,pmin,pstep,pmax;
   ESC_Fnum(r.plan_tp,ptp);
   ESC_Fnum(r.plan_vol_min,pmin);
   ESC_Fnum(r.plan_vol_step,pstep);
   ESC_Fnum(r.plan_vol_max,pmax);
   b+="PLAN_SET="+IntegerToString(r.plan_set ? 1 : 0)+"\n";
   b+="PLAN_TP="+ptp+"\n";
   b+="PLAN_VOL_MIN="+pmin+"\n";
   b+="PLAN_VOL_STEP="+pstep+"\n";
   b+="PLAN_VOL_MAX="+pmax+"\n";
   string pes,pss,peo,pso;
   ESC_Fnum(r.plan_e_src,pes);
   ESC_Fnum(r.plan_s_src,pss);
   ESC_Fnum(r.plan_e_out,peo);
   ESC_Fnum(r.plan_s_out,pso);
   b+="PLAN_RPOL="+IntegerToString(r.plan_rpol)+"\n";
   b+="PLAN_E_SRC="+pes+"\n";
   b+="PLAN_S_SRC="+pss+"\n";
   b+="PLAN_E_OUT="+peo+"\n";
   b+="PLAN_S_OUT="+pso+"\n";
   b+="MAP_N="+IntegerToString(r.n_orders)+"\n";
   for(int k=0;k<r.n_orders;k++)
      b+="MAP_ORDER_"+IntegerToString(k)+"="+IntegerToString((long)r.orders[k])+"\n";
   b+="END\n";
   text=b+"CRC="+StringFormat("%08X",ESC_Crc32(b))+"\n";
   if(StringLen(text)>ESC_MAX_TEXT)
     {
      text="";
      reason="TOO_LARGE";
      return(false);
     }
   return(true);
  }

// splits `s` at '\n' (every line is terminated); false when the text does not end with a newline
int ESC_Lines(const string s,string &lines[])
  {
   ArrayResize(lines,0);
   int n=StringLen(s);
   int start=0;
   for(int i=0;i<n;i++)
      if(StringGetCharacter(s,i)=='\n')
        {
         int m=ArraySize(lines);
         ArrayResize(lines,m+1);
         lines[m]=StringSubstr(s,start,i-start);
         start=i+1;
        }
   return(start==n ? ArraySize(lines) : -1);
  }

bool ESC_Field(const string &lines[],const int index,const string key,string &value)
  {
   value="";
   string prefix=key+"=";
   if(index>=ArraySize(lines) || StringSubstr(lines[index],0,StringLen(prefix))!=prefix) return(false);
   value=StringSubstr(lines[index],StringLen(prefix));
   return(true);
  }

bool ESC_Decode(const string text,SEsRecord &rec,string &reason)
  {
   ESC_RecordInit(rec);
   reason="";
   if(text=="") {reason="EMPTY"; return(false);}
   if(StringLen(text)>ESC_MAX_TEXT) {reason="TOO_LARGE"; return(false);}
   if(StringGetCharacter(text,StringLen(text)-1)!='\n') {reason="TRUNCATED: no final newline"; return(false);}
   int k=StringFind(text,"END\nCRC=");
   int last=-1;
   while(k>=0)
     {
      last=k;
      k=StringFind(text,"END\nCRC=",k+1);
     }
   k=last;
   if(k<0) {reason="TRUNCATED: no END / CRC trailer"; return(false);}
   int crc_first=StringFind(text,"CRC=");
   if(crc_first<0 || StringFind(text,"CRC=",crc_first+1)>=0) {reason="TRUNCATED: no END / CRC trailer"; return(false);}
   string body=StringSubstr(text,0,k+4);
   string trailer=StringSubstr(text,k+4);
   if(StringLen(trailer)!=13) {reason="BAD_TRAILER"; return(false);}
   uint want=0;
   for(int i=0;i<8;i++)
     {
      int h=ESC_HexVal(StringGetCharacter(trailer,4+i));
      if(h<0) {reason="BAD_TRAILER"; return(false);}
      want=want*16+(uint)h;
     }
   if(StringGetCharacter(trailer,12)!='\n') {reason="BAD_TRAILER"; return(false);}
   if(want!=ESC_Crc32(body)) {reason="CRC_MISMATCH: the record is damaged or was edited"; return(false);}
   string lines[];
   if(ESC_Lines(body,lines)<0) {reason="BAD_HEADER"; return(false);}
   if(ArraySize(lines)<1 || lines[0]!=ESC_HEADER) {reason="BAD_HEADER"; return(false);}
   string keys[]={"VERSION","GEN","SERVER","LOGIN","SYMBOL","POSITION","STATUS","BOUND","STATE_POSITION","DIRECTION","LEVEL","VOLUME_INITIAL","VOLUME_STEP",
                  "REQUEST_ID","REQUEST_STEPS","CLOSE_VOLUME","INITIAL_STEPS","EXECUTED_STEPS","CONFIRMATIONS","DUPLICATES","REASON","SEND_PHASE","MAP_COMPLETE","PLAN_SET","PLAN_TP","PLAN_VOL_MIN","PLAN_VOL_STEP","PLAN_VOL_MAX","PLAN_RPOL","PLAN_E_SRC","PLAN_S_SRC","PLAN_E_OUT","PLAN_S_OUT","MAP_N"};
   int nk=ArraySize(keys);
   string vtext;
   if(ArraySize(lines)<2 || !ESC_Field(lines,1,"VERSION",vtext)) {reason="BAD_FIELD_ORDER: expected VERSION"; return(false);}
   long vnum=0;
   if(!ESC_ParseInt(vtext,vnum) || vnum!=ESC_VERSION) {reason="UNSUPPORTED_VERSION: "+StringSubstr(vtext,0,20)+" (an older record without the declared R basis is never migrated)"; return(false);}
   if(ArraySize(lines)<1+nk+1) {reason="TRUNCATED: missing fields"; return(false);}
   string v[34];
   for(int i=0;i<nk;i++)
      if(!ESC_Field(lines,1+i,keys[i],v[i])) {reason="BAD_FIELD_ORDER: expected "+keys[i]; return(false);}
   long x=0;
   if(!ESC_ParseInt(v[0],x) || x!=ESC_VERSION) {reason="UNSUPPORTED_VERSION: "+StringSubstr(v[0],0,20); return(false);}
   long n=0;
   if(!ESC_ParseInt(v[33],n) || n<0 || n>ESC_MAX_ORDERS) {reason="BAD_MAP_COUNT"; return(false);}
   if(ArraySize(lines)!=1+nk+(int)n+1 || lines[ArraySize(lines)-1]!="END") {reason="BAD_LENGTH: the number of lines does not match"; return(false);}
   rec.n_orders=(int)n;
   for(int i=0;i<(int)n;i++)
     {
      string ov;
      if(!ESC_Field(lines,1+nk+i,"MAP_ORDER_"+IntegerToString(i),ov)) {reason="BAD_FIELD_ORDER: MAP_ORDER_"+IntegerToString(i); return(false);}
      long o=0;
      if(!ESC_ParseInt(ov,o)) {reason="BAD_NUMBER: MAP_ORDER_"+IntegerToString(i); return(false);}
      rec.orders[i]=(ulong)o;
     }
   long gen=0,login=0,pos=0,status=0,bound=0,spos=0,dir=0,rsteps=0,isteps=0,esteps=0,conf=0,dup=0,phase=0,mcomp=0;
   if(!ESC_ParseInt(v[1],gen)) {reason="BAD_NUMBER: GEN"; return(false);}
   if(!ESC_ParseInt(v[3],login)) {reason="BAD_NUMBER: LOGIN"; return(false);}
   if(!ESC_ParseInt(v[5],pos)) {reason="BAD_NUMBER: POSITION"; return(false);}
   if(!ESC_ParseInt(v[6],status)) {reason="BAD_NUMBER: STATUS"; return(false);}
   if(!ESC_ParseInt(v[7],bound)) {reason="BAD_NUMBER: BOUND"; return(false);}
   if(!ESC_ParseInt(v[8],spos)) {reason="BAD_NUMBER: STATE_POSITION"; return(false);}
   if(!ESC_ParseInt(v[9],dir)) {reason="BAD_NUMBER: DIRECTION"; return(false);}
   if(!ESC_ParseInt(v[14],rsteps)) {reason="BAD_NUMBER: REQUEST_STEPS"; return(false);}
   if(!ESC_ParseInt(v[16],isteps)) {reason="BAD_NUMBER: INITIAL_STEPS"; return(false);}
   if(!ESC_ParseInt(v[17],esteps)) {reason="BAD_NUMBER: EXECUTED_STEPS"; return(false);}
   if(!ESC_ParseInt(v[18],conf)) {reason="BAD_NUMBER: CONFIRMATIONS"; return(false);}
   if(!ESC_ParseInt(v[19],dup)) {reason="BAD_NUMBER: DUPLICATES"; return(false);}
   if(!ESC_ParseInt(v[21],phase)) {reason="BAD_NUMBER: SEND_PHASE"; return(false);}
   if(!ESC_ParseInt(v[22],mcomp)) {reason="BAD_NUMBER: MAP_COMPLETE"; return(false);}
   long pset=0;
   double ptp=0.0,pmin=0.0,pstep=0.0,pmax=0.0;
   if(!ESC_ParseInt(v[23],pset)) {reason="BAD_NUMBER: PLAN_SET"; return(false);}
   if(!ESC_ParseDouble(v[24],ptp)) {reason="BAD_NUMBER: PLAN_TP"; return(false);}
   if(!ESC_ParseDouble(v[25],pmin)) {reason="BAD_NUMBER: PLAN_VOL_MIN"; return(false);}
   if(!ESC_ParseDouble(v[26],pstep)) {reason="BAD_NUMBER: PLAN_VOL_STEP"; return(false);}
   if(!ESC_ParseDouble(v[27],pmax)) {reason="BAD_NUMBER: PLAN_VOL_MAX"; return(false);}
   long prpol=0;
   double pes=0.0,pss=0.0,peo=0.0,pso=0.0;
   if(!ESC_ParseInt(v[28],prpol)) {reason="BAD_NUMBER: PLAN_RPOL"; return(false);}
   if(!ESC_ParseDouble(v[29],pes)) {reason="BAD_NUMBER: PLAN_E_SRC"; return(false);}
   if(!ESC_ParseDouble(v[30],pss)) {reason="BAD_NUMBER: PLAN_S_SRC"; return(false);}
   if(!ESC_ParseDouble(v[31],peo)) {reason="BAD_NUMBER: PLAN_E_OUT"; return(false);}
   if(!ESC_ParseDouble(v[32],pso)) {reason="BAD_NUMBER: PLAN_S_OUT"; return(false);}
   double level=0.0,vinit=0.0,vstep=0.0,cvol=0.0;
   if(!ESC_ParseDouble(v[10],level)) {reason="BAD_NUMBER: LEVEL"; return(false);}
   if(!ESC_ParseDouble(v[11],vinit)) {reason="BAD_NUMBER: VOLUME_INITIAL"; return(false);}
   if(!ESC_ParseDouble(v[12],vstep)) {reason="BAD_NUMBER: VOLUME_STEP"; return(false);}
   if(!ESC_ParseDouble(v[15],cvol)) {reason="BAD_NUMBER: CLOSE_VOLUME"; return(false);}
   string server,symbol,request_id,why;
   if(!ESC_Unescape(v[2],server)) {reason="BAD_STRING: SERVER"; return(false);}
   if(!ESC_Unescape(v[4],symbol)) {reason="BAD_STRING: SYMBOL"; return(false);}
   if(!ESC_Unescape(v[13],request_id)) {reason="BAD_STRING: REQUEST_ID"; return(false);}
   if(!ESC_Unescape(v[20],why)) {reason="BAD_STRING: REASON"; return(false);}
   if(status<0 || status>(long)EA_ST_BLOCKED || (bound!=0 && bound!=1) || (mcomp!=0 && mcomp!=1) || (pset!=0 && pset!=1) || prpol<0 || prpol>2) {reason="BAD_ENUM"; return(false);}
   if(gen<1 || gen>ESC_MAX_GEN) {reason="INVALID_GENERATION"; return(false);}
   rec.generation=(int)gen;
   rec.id.server=server;
   rec.id.login=login;
   rec.id.symbol=symbol;
   rec.id.position_id=(ulong)pos;
   rec.state.status=(ENUM_EA_STATE)status;
   rec.state.bound=(bound==1);
   rec.state.position_id=(ulong)spos;
   rec.state.direction=(int)dir;
   rec.state.level=level;
   rec.state.volume_initial=vinit;
   rec.state.volume_step=vstep;
   rec.state.request_id=request_id;
   rec.state.request_steps=rsteps;
   rec.state.close_volume=cvol;
   rec.state.initial_steps=isteps;
   rec.state.executed_steps=esteps;
   rec.state.confirmations=(int)conf;
   rec.state.duplicates_ignored=(int)dup;
   rec.state.reason=why;
   rec.send_phase=(int)phase;
   rec.map_complete=(mcomp==1);
   rec.plan_set=(pset==1);
   rec.plan_tp=ptp;
   rec.plan_vol_min=pmin;
   rec.plan_vol_step=pstep;
   rec.plan_vol_max=pmax;
   rec.plan_rpol=(int)prpol;
   rec.plan_e_src=pes;
   rec.plan_s_src=pss;
   rec.plan_e_out=peo;
   rec.plan_s_out=pso;
   reason=ESC_Validate(rec);
   return(reason=="");
  }

void ESC_RestoreInit(SEsRestore &o)
  {
   o.verdict=ESC_RECOVERY_REQUIRED;
   o.reason="";
   o.new_request_allowed=false;
   o.reconcile_required=false;
   o.map_complete=false;
   o.n_orders=0;
   for(int i=0;i<ESC_MAX_ORDERS;i++)
      o.orders[i]=0;
   o.generation=0;
   o.plan_set=false;
   o.plan_tp=0.0;
   o.plan_vol_min=0.0;
   o.plan_vol_step=0.0;
   o.plan_vol_max=0.0;
   o.plan_rpol=ESC_RPOL_NONE;
   o.plan_e_src=0.0;
   o.plan_s_src=0.0;
   o.plan_e_out=0.0;
   o.plan_s_out=0.0;
  }

void ESC_Blocked(SEaState &st,SEsRestore &o,const string reason)
  {
   EA_StateInit(st);
   st.status=EA_ST_BLOCKED;
   st.reason="RECOVERY_REQUIRED: "+reason;
   o.verdict=ESC_RECOVERY_REQUIRED;
   o.reason=reason;
  }

// `have_text` false = the file does not exist. Never reads the broker; a restored request always needs reconciliation.
void ESC_Restore(const bool have_text,const string text,const SEsIdentity &expected,const bool tmp_present,SEaState &st,SEsRestore &o)
  {
   ESC_RestoreInit(o);
   if(tmp_present)
     {
      ESC_Blocked(st,o,"LEFTOVER_TMP: a temporary state file exists, the last save did not finish");
      return;
     }
   if(!have_text)
     {
      ESC_Blocked(st,o,"MISSING: no state file; a missing file never allows a new request");
      return;
     }
   SEsRecord rec;
   string why;
   if(!ESC_Decode(text,rec,why))
     {
      ESC_Blocked(st,o,why);
      return;
     }
   if(!ESC_IdentityEqual(rec.id,expected))
     {
      ESC_Blocked(st,o,"IDENTITY_MISMATCH: the record belongs to another server / account / symbol / position");
      return;
     }
   st=rec.state;
   o.map_complete=rec.map_complete;
   o.n_orders=rec.n_orders;
   for(int i=0;i<rec.n_orders;i++)
      o.orders[i]=rec.orders[i];
   o.generation=rec.generation;
   o.plan_set=rec.plan_set;
   o.plan_tp=rec.plan_tp;
   o.plan_vol_min=rec.plan_vol_min;
   o.plan_vol_step=rec.plan_vol_step;
   o.plan_vol_max=rec.plan_vol_max;
   o.plan_rpol=rec.plan_rpol;
   o.plan_e_src=rec.plan_e_src;
   o.plan_s_src=rec.plan_s_src;
   o.plan_e_out=rec.plan_e_out;
   o.plan_s_out=rec.plan_s_out;
   if(st.status==EA_ST_BLOCKED)
     {
      o.verdict=ESC_USABLE_BLOCKED;
      o.reason="BLOCKED restored as stored";
      return;
     }
   if(st.status==EA_ST_IDLE)
     {
      o.verdict=ESC_USABLE_IDLE;
      o.reason="IDLE restored; a new request is allowed only under the persist-before-send protocol";
      o.new_request_allowed=true;
      return;
     }
   o.reconcile_required=true;
   if(rec.send_phase==ESC_SEND_INTENT && (st.status==EA_ST_REQUEST_PENDING || st.status==EA_ST_NEEDS_RECONCILIATION))
     {
      st.status=EA_ST_NEEDS_RECONCILIATION;
      st.reason="RECOVERY_REQUIRED: SEND_UNCERTAIN: the send intent was persisted but no order map; the request may or may not have reached the broker. No retry, no invented map";
      o.verdict=ESC_RECOVERY_REQUIRED;
      o.reason=st.reason;
      return;
     }
   o.verdict=ESC_USABLE_REQUEST;
   o.reason="request restored as stored; reconcile with the broker before any action (the file is not proof of execution)";
  }
#endif
