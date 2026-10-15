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

// where the filled order came from: UNSET blocks; SYNTHETIC = the FAKE entry transport (its position ids are not broker facts); BROKER = a real entry transport
#define MH_PROV_UNSET 0
#define MH_PROV_SYNTHETIC 1
#define MH_PROV_BROKER 2

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


// ---- T011 MANAGEMENT inside the orchestrator. No state machine of its own: every step is the EXISTING driver (ETD_Init = recovery first and the arming proof, ETD_Tick = the one request source at the
// 2R level, ETD_Timer = reconcile only) under the T011 per-position lock. The persistent memory of the managed set is the lifecycle INDEX: a registered fill stays indexed (LC_SINK_ACTIVE) until the
// T011 record is DONE or the position is proven closed, so after a restart the sweep hands every indexed fill back to Manage(), which runs the driver's recovery before anything can arm.
// A position that has no T011 record is never touched. Mirrors Manager in tests/lifecycle_reference.py.
#define MH_MAX_SLOTS 16

struct SMhSlot
  {
   ulong pid;
   string name;
   SEsIdentity id;
   SExConfig cfg;
   SEtdState st;
   SExRuntime rt;
   int direction;
   double volume;
   bool inited;
   bool done;
   string blocked;
  };

class CMhManager
  {
public:
   CExitTransport *tr;          // the MANAGEMENT transport: read-only (its Send is refused) by default; the real closing transport only by explicit EA inputs
   SXaRaw raw_a;                // fixtures for a non-live transport (tests); a live transport ignores them
   SXaRaw raw_b;
   long magic;
   string phrase;
   int filling;
   long deviation;
   int filter_policy;
   int filter_state;
   SMhSlot slots[MH_MAX_SLOTS];
   int n;
   CMhManager(void)
     {
      tr=NULL;
      magic=0;
      phrase="";
      filling=EX_FILL_UNSET;
      deviation=-1;
      filter_policy=EX_POL_UNSET;
      filter_state=EX_FS_UNKNOWN;
      n=0;
      XA_RawInit(raw_a);
      XA_RawInit(raw_b);
     }
   int Find(const ulong pid)
     {
      for(int i=0;i<n;i++)
         if(slots[i].pid==pid) return(i);
      return(-1);
     }
   void Forget(const ulong pid)
     {
      int k=Find(pid);
      if(k<0) return;
      for(int i=k;i<n-1;i++) slots[i]=slots[i+1];
      n--;
     }
   void MakeCfg(const SEnRecord &rec,SExConfig &c)
     {
      EX_ConfigInit(c);
      c.enabled=true;
      c.r_policy=EX_RPOL_R_GEOM;
      c.real_authorised=(phrase==EX_AUTH_PHRASE);
      c.authorisation=phrase;
      c.ea_magic=magic;
      c.filling=(ENUM_EX_FILLING)filling;
      c.deviation=deviation;
      c.filter_policy=(ENUM_EX_FILTER_POLICY)filter_policy;
      c.filter_state=(ENUM_EX_FILTER_STATE)filter_state;
      c.sl_initial_set=true;
      c.sl_initial=rec.s;
      c.tp_set=true;
      c.tp_price=rec.tp;
     }
   int Classify(const int k,const bool armed,const SErfResult &flow,const bool have_flow,string &detail)
     {
      if(slots[k].done) {detail="MANAGEMENT_DONE: the T011 record is DONE"; return(LC_SINK_CONFIRMED);}
      if(armed) {detail="ARMED"; return(LC_SINK_ACTIVE);}
      if(have_flow)
        {
         if(flow.final_state==ERF_DONE) {slots[k].done=true; detail="MANAGEMENT_DONE: recovered as DONE"; return(LC_SINK_CONFIRMED);}
         if(flow.final_state==ERF_STILL_OPEN) {detail="RECONCILING"; return(LC_SINK_ACTIVE);}
         slots[k].blocked="MANAGEMENT_BLOCKED: the T011 record is "+ERF_FinalName(flow.final_state)+" ("+flow.reason+")";
         detail=slots[k].blocked;
         return(LC_SINK_REFUSED);
        }
      string reason=slots[k].st.reason;
      if(StringFind(reason,"INIT_LOCK_FAILED")==0) {detail="MANAGEMENT_LOCK: "+reason; return(LC_SINK_PENDING);}
      if(StringFind(reason,"INIT_POSITION_NOT_PROVEN: POSITION_NOT_FOUND")==0) {detail="MANAGEMENT_POSITION_NOT_FOUND: "+reason; return(LC_SINK_PENDING);}
      slots[k].blocked="MANAGEMENT_NOT_ARMED: "+reason;
      detail=slots[k].blocked;
      return(LC_SINK_REFUSED);
     }
   int Manage(const SEnRecord &rec,const SEsIdentity &idn,const string name,string &detail)
     {
      if(tr==NULL) {detail="MANAGEMENT_NOT_BOUND"; return(LC_SINK_REFUSED);}
      int k=Find(rec.position_id);
      if(k<0)
        {
         if(n>=MH_MAX_SLOTS) {detail="MANAGEMENT_SLOTS_FULL"; return(LC_SINK_REFUSED);}
         k=n;
         n++;
         slots[k].pid=rec.position_id;
         slots[k].name=name;
         slots[k].id=idn;
         MakeCfg(rec,slots[k].cfg);
         ETD_StateInit(slots[k].st);
         EX_RuntimeInit(slots[k].rt);
         slots[k].direction=rec.direction;
         slots[k].volume=rec.volume;
         slots[k].inited=false;
         slots[k].done=false;
         slots[k].blocked="";
        }
      if(slots[k].blocked!="") {detail=slots[k].blocked; return(LC_SINK_REFUSED);}
      if(slots[k].done) {detail="MANAGEMENT_DONE: the T011 record is DONE"; return(LC_SINK_CONFIRMED);}
      if(slots[k].inited && (slots[k].st.armed || slots[k].st.reconcile_due)) {detail="ACTIVE"; return(LC_SINK_ACTIVE);}
      SErfResult flow;
      bool armed=ETD_Init(slots[k].cfg,tr,name,idn,raw_a,raw_b,slots[k].st,flow);      // not armed and nothing to reconcile (first sweep, a disarmed driver, a lock failure): the driver's init is the restart
      slots[k].inited=true;
      bool have_flow=(flow.snapshot_called || flow.reconcile_called || flow.final_state!=ERF_RECOVERY_REQUIRED || flow.reason!="");
      return(Classify(k,armed,flow,have_flow,detail));
     }
   // one quote for every armed slot; returns the number of closing requests SENT
   int OnQuote(const double bid,const double ask)
     {
      int sent=0;
      for(int i=0;i<n;i++)
        {
         if(!slots[i].st.armed) continue;
         SExQuote q;
         q.direction=slots[i].direction;
         q.level_2r=0.0;
         q.bid=bid;
         q.ask=ask;
         q.volume_initial=slots[i].volume;
         SExResult res;
         if(ETD_Tick(slots[i].cfg,tr,slots[i].rt,slots[i].name,slots[i].id,q,slots[i].st,res)) sent++;
        }
      return(sent);
     }
   // reconcile only; returns the number of timer runs
   int OnTimer(void)
     {
      int runs=0;
      for(int i=0;i<n;i++)
        {
         if(!slots[i].st.reconcile_due) continue;
         SErfResult flow;
         if(ETD_Timer(tr,slots[i].name,slots[i].id,raw_a,raw_b,slots[i].st,flow))
           {
            runs++;
            if(flow.final_state==ERF_DONE) slots[i].done=true;
            else
               if(flow.final_state!=ERF_STILL_OPEN)
                  slots[i].blocked="MANAGEMENT_BLOCKED: the T011 record is "+ERF_FinalName(flow.final_state)+" ("+flow.reason+")";
           }
        }
      return(runs);
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
   CLcObserver *obs;            // optional: PROVEN facts about the owned position (volume, SL, closed)
   CMhManager *manager;         // optional: after a confirmed registration the position is handed to the T011 driver (management inside the orchestrator)
   int provenance;              // MH_PROV_*; anything but BROKER refuses before any terminal read
   bool selftest;               // test file names only (a prefix); the production name is ESF_FileName
   string tries_id[LC_MAX];
   int tries[LC_MAX];
   int n_tries;
   CMhRegistrar(void) {entry_store=NULL; exit_tr=NULL; magic=0; phrase=""; rpol=EX_RPOL_UNSET; obs=NULL; manager=NULL; provenance=MH_PROV_UNSET; selftest=false; n_tries=0;}
   string Name(const long login,const ulong position_id) {return((selftest ? "VELO_T019_SELFTEST_" : "")+ESF_FileName(login,position_id));}
   // true only when the position list was readable, stable (two scans, the count unchanged) and holds no such position: the position is CLOSED, not merely unreadable. Tests override it.
   virtual bool Absent(const ulong position_id)
     {
      for(int pass=0;pass<2;pass++)
        {
         int total=PositionsTotal();
         for(int i=total-1;i>=0;i--)
           {
            ulong t=PositionGetTicket(i);
            if(t==0) return(false);
            long idv=0;
            if(!PositionGetInteger(POSITION_IDENTIFIER,idv)) return(false);
            if((ulong)idv==position_id) return(false);
           }
         if(PositionsTotal()!=total) return(false);
        }
      return(true);
     }
   // a confirmed registration is handed to the management (when wired): the id leaves the index only when the management is finished
   int Managed(const int status,const string detail_in,const SEnRecord &rec,const SEsIdentity &idn,const string name,string &detail)
     {
      detail=detail_in;
      if(status!=LC_SINK_CONFIRMED || manager==NULL) return(status);
      if(StringFind(detail_in,"POSITION_CLOSED")==0)
        {
         manager.Forget(rec.position_id);
         return(status);
        }
      string md;
      int ms=manager.Manage(rec,idn,name,md);
      if(ms==LC_SINK_CONFIRMED) manager.Forget(rec.position_id);     // finished: the slot is released (the T011 record stays; a restart before the index is saved recovers the DONE from it)
      if(ms==LC_SINK_CONFIRMED) detail=detail_in+" | "+md;
      else
         if(ms==LC_SINK_ACTIVE) detail=(md=="ACTIVE" ? md : detail_in+" | MANAGEMENT "+md);
         else detail=md;
      return(ms);
     }
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
   // an EXISTING T011 record is accepted only when the whole base of the plan matches what registration would store NOW and the registration gates still hold; nothing is written.
   // What management legitimately changes (live SL, live volume, request / order state) is not compared; what it cannot change (open price, initial SL, TP, direction, initial volume,
   // the symbol's volume rules, the derived 2R level) is.
   int Compare(const string name,const SEsIdentity &idn,const SEnRecord &rec,const SExAccount &acct,string &detail)
     {
      if(ESF_Exists(name+ESF_TMP_SUFFIX)) {detail="T011_RECORD_CONFLICT: a leftover temporary file exists; recover by hand"; return(LC_SINK_REFUSED);}
      if(phrase!=EX_AUTH_PHRASE) {detail="REAL_NOT_AUTHORISED"; return(LC_SINK_REFUSED);}
      if(!acct.demo) {detail="REAL_REQUIRES_DEMO_ACCOUNT"; return(LC_SINK_REFUSED);}
      if(acct.margin_mode!=2) {detail="UNSUPPORTED_ACCOUNT_MODE: only HEDGING"; return(LC_SINK_REFUSED);}
      if(!(magic>0 && rec.magic==magic)) {detail="OWNERSHIP_NOT_PROVEN: the magic of the configuration differs from the magic of the entry record"; return(LC_SINK_REFUSED);}
      SExSymbol sym;
      exit_tr.ReadSymbol(idn.symbol,sym);
      if(!sym.read_ok || sym.tick_size<=0.0) {detail="SYMBOL_UNREADABLE"; return(LC_SINK_PENDING);}
      SExPosition pos;
      exit_tr.FindPosition(idn.position_id,pos);
      if(!pos.found || pos.ticket==0 || pos.identifier!=idn.position_id)
        {
         if(Absent(idn.position_id))
           {
            if(obs!=NULL) obs.OnClosed(rec.login,rec.signal_id,idn.position_id);
            SEaState cst;
            SEsRestore co;
            ESF_Load(name,idn,cst,co);
            if((co.verdict==ESC_USABLE_IDLE || co.verdict==ESC_USABLE_REQUEST || co.verdict==ESC_USABLE_BLOCKED) && co.plan_set && (cst.status==EA_ST_IDLE || cst.status==EA_ST_DONE))
              {
               detail="POSITION_CLOSED: the position is proven absent (stable list); a record that is IDLE or DONE has nothing left to manage; the file is untouched";
               return(LC_SINK_CONFIRMED);
              }
           }
         detail="POSITION_NOT_FOUND: the open price of the position cannot be proven, so the stored base cannot be compared";
         return(LC_SINK_PENDING);
        }
      if(pos.symbol!=idn.symbol || pos.magic!=magic || pos.type!=(rec.direction==1 ? 0 : 1)) {detail="OWNERSHIP_NOT_PROVEN: symbol, magic or direction of the live position differ from the record / configuration"; return(LC_SINK_REFUSED);}
      if(obs!=NULL) obs.OnPosition(rec.login,rec.signal_id,idn.position_id,pos.volume,pos.sl);      // an OWNED position, read once, proven by identifier + magic + symbol + direction
      SEaState st;
      SEsRestore o;
      ESF_Load(name,idn,st,o);
      if(!((o.verdict==ESC_USABLE_IDLE || o.verdict==ESC_USABLE_REQUEST || o.verdict==ESC_USABLE_BLOCKED) && o.plan_set))
        {
         detail="T011_RECORD_CONFLICT: the existing T011 record is unusable and is never overwritten ("+o.reason+")";
         return(LC_SINK_REFUSED);
        }
      if(!(EX_Finite(pos.price_open) && pos.price_open>0.0 && EX_OnGrid(pos.price_open,sym.tick_size) && EX_OnGrid(rec.s,sym.tick_size)))
        {
         detail="T011_RECORD_CONFLICT: the live open price or the initial SL is not usable as a base";
         return(LC_SINK_REFUSED);
        }
      STgResult geo;
      EX_Geometry(sym,rec.direction,pos.price_open,rec.s,rec.tp,geo);
      if(geo.status!=TG_OK) {detail="T011_RECORD_CONFLICT: the base does not give a geometry ("+TG_StatusName(geo.status)+")"; return(LC_SINK_REFUSED);}
      bool same=(st.direction==rec.direction && st.volume_initial==rec.volume && o.plan_tp==rec.tp && o.plan_rpol==rpol && o.plan_e_src==pos.price_open && o.plan_s_src==rec.s &&
                 o.plan_e_out==geo.e_out && o.plan_s_out==geo.s_out && st.level==geo.level_2r && o.plan_vol_min==sym.vol_min && o.plan_vol_step==sym.vol_step && o.plan_vol_max==sym.vol_max);
      if(!same)
        {
         detail="T011_RECORD_CONFLICT: the existing T011 record differs from the plan (open price, initial SL, TP, direction, volume, 2R level or symbol volume rules) and is never overwritten";
         return(LC_SINK_REFUSED);
        }
      detail="ALREADY_REGISTERED (the whole base of the T011 record matches; nothing is rewritten) "+Inputs(rec);
      return(LC_SINK_CONFIRMED);
     }
   int Attempt(const long login,const string signal_id,string &detail)
     {
      SEnRecord rec;
      string why;
      if(provenance!=MH_PROV_BROKER)
        {
         detail="PROVENANCE_NOT_BROKER: the fill comes from a "+(provenance==MH_PROV_SYNTHETIC ? "synthetic (FAKE)" : "not declared")+" entry transport; its position id is not a broker fact and is never matched to a real position";
         return(LC_SINK_REFUSED);
        }
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
      if(ESF_Exists(name) || ESF_Exists(name+ESF_TMP_SUFFIX))
        {
         string cd;
         int cs=Compare(name,idn,rec,acct,cd);
         return(Managed(cs,cd,rec,idn,name,detail));
        }
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
      if(res.final_state==EX_REGISTERED) return(Managed(LC_SINK_CONFIRMED,"REGISTERED_WITH_T011 "+Inputs(rec),rec,idn,name,detail));
      if(res.final_state==EX_RECOVERY_REQUIRED) {detail="REGISTRATION_UNCERTAIN: "+res.reason; return(LC_SINK_PENDING);}
      detail=res.reason;
      return(Transient(res.reason) ? LC_SINK_PENDING : LC_SINK_REFUSED);
     }
   virtual int OnFilled(const long login,const string signal_id,string &detail)
     {
      int r=Attempt(login,signal_id,detail);
      if(r!=LC_SINK_PENDING)
        {
         for(int j=0;j<n_tries;j++)
            if(tries_id[j]==signal_id) tries[j]=0;
        }
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
