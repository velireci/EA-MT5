// T019 FILL -> T011 AUTOMATIC REGISTRATION (mirror of Registrar in tests/lifecycle_reference.py; read its header for the contract). The orchestrator registers a FILLED entry with the existing T011 executor
// (ETD_Register -> EX_Register, under the T011 per-position lock) so that XauUsdT011ExitManager can arm from the stored IDLE record. NOTHING of the T011 contract changes: ownership (magic, symbol, direction,
// volume, hedging account), the initial SL (asserted from the executor record, accepted only while the LIVE SL equals it), the stored plan, a state file that is never overwritten, the authorisation phrase and
// the demo account (the read-only exit transport below reports IsReal() = true), the TP / 2R rule of T011 (TP_EQUALS_2R stays a refusal). Idempotent: an existing T011 record is accepted only when it matches
// the plan (nothing is rewritten); anything else is a conflict. Transient refusals are retried a bounded number of times. The ENTRY transport of the orchestrator stays FAKE; this header has no order call.
#ifndef VELO_ENTRY_MANAGEMENT_HANDOFF_MQH
#define VELO_ENTRY_MANAGEMENT_HANDOFF_MQH

#include "EntryLifecycle.mqh"
#include "ExitTickDriver.mqh"

#define MH_MAX_TRIES 5

// READ-ONLY exit transport over the terminal: account / symbol / position reads (flagged getters, a failed getter is "not found", never a default); PreCheck refuses, Send does nothing and is counted.
// IsReal() = true on purpose: it keeps the authorisation phrase and the demo-account gates of EX_Register in force.
class CMhReadTransport : public CExitTransport
  {
public:
   int send_attempts;
   CMhReadTransport(void) {send_attempts=0;}
   virtual bool IsReal(void) {return(true);}
   virtual void ReadAccount(SExAccount &a)
     {
      ResetLastError();
      a.login=AccountInfoInteger(ACCOUNT_LOGIN);
      a.server=AccountInfoString(ACCOUNT_SERVER);
      a.demo=(AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO);
      a.trade_allowed=(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)!=0 && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)!=0);
      a.margin_mode=(int)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      a.read_ok=(a.login>0 && a.server!="" && GetLastError()==0);
     }
   virtual void ReadSymbol(const string symbol,SExSymbol &s)
     {
      ResetLastError();
      long tm=0;
      bool got=(SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN,s.vol_min) && SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP,s.vol_step) && SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX,s.vol_max) &&
                SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE,s.tick_size) && SymbolInfoDouble(symbol,SYMBOL_POINT,s.point) && SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE,tm));
      long dg=-1;
      got=(got && SymbolInfoInteger(symbol,SYMBOL_DIGITS,dg));
      s.digits=(int)dg;
      s.close_allowed=(tm==SYMBOL_TRADE_MODE_FULL || tm==SYMBOL_TRADE_MODE_CLOSEONLY);
      s.read_ok=(got && s.vol_min>0.0 && s.vol_step>0.0 && s.vol_max>0.0 && s.tick_size>0.0 && s.digits>=0 && s.point>0.0);
     }
   virtual void FindPosition(const ulong identifier,SExPosition &p)
     {
      p.found=false;
      p.ticket=0;
      p.identifier=0;
      p.symbol="";
      p.magic=0;
      p.type=-1;
      p.volume=0.0;
      p.price_open=0.0;
      p.sl=0.0;
      int matches=0;
      bool readable=true;
      int total=PositionsTotal();
      for(int i=total-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(t==0) {readable=false; continue;}
         long idv=0;
         if(!PositionGetInteger(POSITION_IDENTIFIER,idv)) {readable=false; continue;}
         if((ulong)idv!=identifier) continue;
         matches++;
         long type=-1,magic=-1;
         string symbol="";
         double volume=0.0,price=0.0,sl=0.0;
         bool got=(PositionGetString(POSITION_SYMBOL,symbol) && symbol!="" && PositionGetInteger(POSITION_MAGIC,magic) && magic>=0 && PositionGetInteger(POSITION_TYPE,type) &&
                   PositionGetDouble(POSITION_VOLUME,volume) && PositionGetDouble(POSITION_PRICE_OPEN,price) && PositionGetDouble(POSITION_SL,sl));
         if(!got) {readable=false; continue;}
         p.ticket=t;
         p.identifier=identifier;
         p.symbol=symbol;
         p.magic=magic;
         p.type=(type==POSITION_TYPE_BUY ? 0 : 1);
         p.volume=volume;
         p.price_open=price;
         p.sl=sl;
        }
      p.found=(matches==1 && readable && PositionsTotal()==total);       // zero, ambiguous, unreadable or changed while read = not found
     }
   virtual bool PreCheck(const SExSendRequest &req) {return(false);}
   virtual void Send(const SExSendRequest &req,SExSendResult &res)
     {
      send_attempts++;
      res.returned_true=false;
      res.have_result=false;
      res.retcode=0;
      res.order=0;
      res.deal=0;
      res.volume=0.0;
      res.price=0.0;
     }
  };

class CMhRegistrar : public CLcFillSink
  {
public:
   CEnStore *entry_store;       // the executor's record store
   CExitTransport *exit_tr;
   long magic;
   string phrase;               // the standing authorisation phrase (EX_AUTH_PHRASE) given as an EA input
   int rpol;                    // EX_RPOL_R_GEOM
   bool selftest;               // test file names only (a prefix); the production name is ESF_FileName
   string tries_id[LC_MAX];
   int tries[LC_MAX];
   int n_tries;
   CMhRegistrar(void) {entry_store=NULL; exit_tr=NULL; magic=0; phrase=""; rpol=EX_RPOL_UNSET; selftest=false; n_tries=0;}
   string Name(const long login,const ulong position_id) {return((selftest ? "VELO_T019_SELFTEST_" : "")+ESF_FileName(login,position_id));}
   string Inputs(const SEnRecord &rec)
     {
      return("InpRPolicy=R_GEOM InpEaMagic="+IntegerToString(rec.magic)+" InpPositionId="+IntegerToString((long)rec.position_id)+" InpSymbol="+rec.symbol+" InpDirection="+(rec.direction==1 ? "BUY" : "SELL")+
             " InpInitialSl="+DoubleToString(rec.s,8)+" InpTpPrice="+DoubleToString(rec.tp,8)+" InpVolumeInitial="+DoubleToString(rec.volume,8)+
             " (start XauUsdT011ExitManager with these; its filling, deviation and filter policy stay the owner inputs)");
     }
   bool Transient(const string reason)
     {
      return(StringFind(reason,"ACCOUNT_UNREADABLE")==0 || StringFind(reason,"SYMBOL_UNREADABLE")==0 || StringFind(reason,"POSITION_NOT_FOUND")==0 || StringFind(reason,"INSTANCE_LOCK_HELD")==0 ||
             StringFind(reason,"ENTRY_UNAVAILABLE")==0);
     }
   int Compare(const string name,const SEsIdentity &idn,const SEnRecord &rec,string &detail)
     {
      if(ESF_Exists(name+ESF_TMP_SUFFIX)) {detail="T011_RECORD_CONFLICT: a leftover temporary file exists; recover by hand"; return(LC_SINK_REFUSED);}
      SEaState st;
      SEsRestore o;
      ESF_Load(name,idn,st,o);
      if((o.verdict==ESC_USABLE_IDLE || o.verdict==ESC_USABLE_REQUEST) && o.plan_set && st.direction==rec.direction && MathAbs(st.volume_initial-rec.volume)<1e-9 && MathAbs(o.plan_tp-rec.tp)<1e-9 &&
         MathAbs(o.plan_s_src-rec.s)<1e-9 && o.plan_rpol==rpol)
        {
         detail="ALREADY_REGISTERED (the T011 record matches the plan; nothing is rewritten) "+Inputs(rec);
         return(LC_SINK_CONFIRMED);
        }
      detail="T011_RECORD_CONFLICT: the existing T011 record is unusable or differs from the plan and is never overwritten ("+o.reason+")";
      return(LC_SINK_REFUSED);
     }
   int Attempt(const long login,const string signal_id,string &detail)
     {
      SEnRecord rec;
      string why;
      if(entry_store==NULL || exit_tr==NULL) {detail="REGISTRAR_NOT_BOUND"; return(LC_SINK_REFUSED);}
      if(EN_Load(entry_store,EN_FileName(login,signal_id),rec,why)!=1) {detail="ENTRY_RECORD_UNREADABLE"; return(LC_SINK_REFUSED);}
      if(rec.state!=EN_ST_FILLED || rec.linked!=1 || rec.position_id==0) {detail="FILL_NOT_PROVEN"; return(LC_SINK_REFUSED);}
      SExAccount acct;
      exit_tr.ReadAccount(acct);
      if(!acct.read_ok) {detail="ACCOUNT_UNREADABLE"; return(LC_SINK_PENDING);}
      if(acct.login!=rec.login || acct.server!=rec.server) {detail="ACCOUNT_IDENTITY_MISMATCH"; return(LC_SINK_REFUSED);}
      SEsIdentity idn;
      idn.server=acct.server;
      idn.login=acct.login;
      idn.symbol=rec.symbol;
      idn.position_id=rec.position_id;
      string name=Name(acct.login,rec.position_id);
      if(ESF_Exists(name) || ESF_Exists(name+ESF_TMP_SUFFIX)) return(Compare(name,idn,rec,detail));
      SExConfig cfg;
      EX_ConfigInit(cfg);
      cfg.enabled=true;
      cfg.r_policy=(ENUM_EX_R_POLICY)rpol;
      cfg.real_authorised=(phrase==EX_AUTH_PHRASE);
      cfg.authorisation=phrase;
      cfg.ea_magic=magic;
      cfg.sl_initial_set=true;
      cfg.sl_initial=rec.s;
      cfg.tp_set=true;
      cfg.tp_price=rec.tp;
      SExQuote q;
      q.direction=rec.direction;
      q.level_2r=0.0;
      q.bid=0.0;
      q.ask=0.0;
      q.volume_initial=rec.volume;
      SExRuntime rt;
      EX_RuntimeInit(rt);
      SExResult res;
      ETD_Register(cfg,exit_tr,rt,name,idn,q,res);
      if(res.final_state==EX_REGISTERED) {detail="REGISTERED_WITH_T011 "+Inputs(rec); return(LC_SINK_CONFIRMED);}
      if(res.final_state==EX_RECOVERY_REQUIRED) {detail="REGISTRATION_UNCERTAIN: "+res.reason; return(LC_SINK_PENDING);}
      detail=res.reason;
      return(Transient(res.reason) ? LC_SINK_PENDING : LC_SINK_REFUSED);
     }
   virtual int OnFilled(const long login,const string signal_id,string &detail)
     {
      int r=Attempt(login,signal_id,detail);
      if(r==LC_SINK_PENDING)
        {
         int k=-1;
         for(int i=0;i<n_tries;i++)
            if(tries_id[i]==signal_id) k=i;
         if(k<0 && n_tries<LC_MAX) {k=n_tries; tries_id[k]=signal_id; tries[k]=0; n_tries++;}
         if(k>=0)
           {
            tries[k]++;
            if(tries[k]>=MH_MAX_TRIES)
              {
               detail="RETRIES_EXHAUSTED after "+IntegerToString(tries[k])+" attempts: "+detail;
               return(LC_SINK_REFUSED);
              }
           }
        }
      return(r);
     }
  };
#endif
