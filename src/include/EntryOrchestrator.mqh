// T016 ENTRY ORCHESTRATOR core (mirror of tests/eo_reference.py; read its header for the full contract): the decision layer of the EA that links the EXISTING flow
//   H4/M15 observer state (T004: SM4State / SM4Candidate / SM4Level) -> SetupPlanBridge (T014) -> EntryGate (T015) -> EntryExecutor (T013)
// with a FAKE transport fixed by the caller. It re-implements no H4 / M15 algorithm, no geometry or sizing formula, no filter and no limit: every step is a call into the existing module.
// What this layer adds: the BASELINE (the first successful build after the start, after ANY data defect, after the context was lost or CHANGED; a candidate confirmed at or before the baseline is
// historical / replayed and is never a signal), geometry without sizing followed by the broker probe for the EFFECTIVE tick value; the final plan is the one the gate
// sees), real data only (a missing value is never zero or CLEAR), explicit exposure / limit inputs (unknown by default, nothing is accounted here), one shared instant and the plan digest for the checks of
// one decision, a fresh executor runtime per signal, and a HALT after an uncertain outcome. No terminal call here: the market port and the transport are supplied.
#ifndef VELO_ENTRY_ORCHESTRATOR_MQH
#define VELO_ENTRY_ORCHESTRATOR_MQH

#include "EntryGate.mqh"

#define EO_FAKE_LABEL "FAKE EXECUTION: a virtual request, nothing is sent to the terminal"
#define EO_MAX_HANDLED 64

bool EO_OffsetSeconds(const long value,int &offset)
  {
   if(value<-50400 || value>50400 || value%900!=0) return(false);
   offset=(int)value;
   return(true);
  }

struct SEoSymbol
  {
   bool read_ok;
   double tick_size;
   int digits;
   double point;
   long stops_level;
   double vol_min;
   double vol_step;
   double vol_max;
   double reported_tick_value;
   bool trade_ok;
  };

struct SEoQuote
  {
   bool read_ok;
   double bid;
   double ask;
   long time;
  };

// everything the core needs from the terminal; the EA implements it with READ-ONLY reads, the test with scripted values
class CEoMarket
  {
public:
   virtual long Now(void)=0;
   virtual void Symbol(SEoSymbol &s)=0;
   virtual void Quote(SEoQuote &q)=0;
   virtual bool CalcProfit(const bool buy,const double volume,const double e,const double s,double &profit)=0;     // OrderCalcProfit; false = not obtained
   virtual void Filters(int &session,int &news,int &spread)=0;                                                    // TP_SESSION_* / TP_NEWS_* / TP_SPREAD_*; UNKNOWN when a filter is not configured or not readable
   virtual bool Daily(const STpPlan &plan,SDbResult &r)=0;                                                       // false = the T012 daily result was not evaluated
  };

struct SEoConfig
  {
   SSpbSelection sel;           // live_after is set by the core
   double risk_budget;
   double lot_cap;
   double model_tolerance;
   long max_quote_age;
   long open_positions;         // exposure and counters: explicit inputs, -1 = unknown (no accounting is invented)
   long trades_today;
   double existing_risk;
   long max_positions;          // limits: -1 = UNSET
   long max_trades;
   double risk_cap;
   SEgConfig gate;
   SEnConfig exec;
  };

void EO_ConfigInit(SEoConfig &c)
  {
   SPB_SelectionInit(c.sel);
   c.risk_budget=-1.0;
   c.lot_cap=-1.0;
   c.model_tolerance=-1.0;
   c.max_quote_age=-1;
   c.open_positions=-1;
   c.trades_today=-1;
   c.existing_risk=-1.0;
   c.max_positions=-1;
   c.max_trades=-1;
   c.risk_cap=-1.0;
   EG_ConfigInit(c.gate);
   EN_ConfigInit(c.exec);
  }

struct SEoOutcome
  {
   string status;               // FEED_NOT_OK, HALTED, CONFIG_UNSET, MARKET_NOT_READY, NO_PLAN, ALREADY_HANDLED, PROBE_FAILED, GATE_BLOCKED, EXECUTOR
   string reason;
   bool request;                // a virtual (fake) request was accepted by the fake transport
   SEnResult res;
   SEgDecision dec;
   SSpbResult spb;
   string label;
  };

void EO_OutcomeInit(SEoOutcome &o)
  {
   o.status="";
   o.reason="";
   o.request=false;
   EN_Res(o.res,EN_R_NONE,"");
   EG_DecisionInit(o.dec);
   SPB_ResultInit(o.spb);
   o.label="";
  }

void EO_Set(SEoOutcome &o,const string status,const string reason)
  {
   o.status=status;
   o.reason=reason;
  }

string EO_UnsetConfig(const SEoConfig &c)
  {
   string bad="";
   if(!(c.risk_budget>0.0)) bad+=(bad=="" ? "" : ", ")+"risk_budget";
   if(!(c.lot_cap>0.0)) bad+=(bad=="" ? "" : ", ")+"lot_cap";
   if(!(c.model_tolerance>=0.0 && c.model_tolerance<=1.0)) bad+=(bad=="" ? "" : ", ")+"model_tolerance";
   if(!(c.max_quote_age>0)) bad+=(bad=="" ? "" : ", ")+"max_quote_age";
   return(bad);
  }

class COrchestrator
  {
public:
   long baseline;
   bool rebase;
   string key;
   bool have_key;
   SM4Context previous_context;
   string handled[EO_MAX_HANDLED];
   int n_handled;
   string halted;
   int signals;
   COrchestrator(void)
     {
      baseline=0;
      rebase=true;
      key="";
      have_key=false;
      M4ContextInit(previous_context);
      n_handled=0;
      halted="";
      signals=0;
     }
   // a data defect or a recovery: the next successful build starts a new baseline (an old signal is never revived)
   void Defect(void) {rebase=true;}
   bool Handled(const string id)
     {
      for(int i=0;i<n_handled;i++)
         if(handled[i]==id) return(true);
      return(false);
     }
   void Remember(const string id)
     {
      if(n_handled<EO_MAX_HANDLED) {handled[n_handled]=id; n_handled++;}
      else halted="HANDLED_LIST_FULL: restart";
     }
   void Step(const SEoConfig &c,CEoMarket *mk,const bool feed_ok,const SM4State &st,const SM4Candidate &f[],const SM4Level &broken,const datetime cut,CEnTransport *tr,CEnStore *store,SEoOutcome &out,CEgPreSend *pre_send=NULL)
     {
      EO_OutcomeInit(out);
      if(!feed_ok)
        {
         Defect();
         EO_Set(out,"FEED_NOT_OK","no confirmed data; the baseline restarts with the next successful build");
         return;
        }
      string k=(st.has_context ? st.context.source+"|"+st.context.setup+"|"+st.context.fvg : "");
      if(k=="" || !have_key || !M4ContextEqual(st.context,previous_context)) rebase=true;
      key=k;
      have_key=true;
      previous_context=st.context;
      if(rebase || baseline==0)
        {
         baseline=MathMax(baseline,(long)cut);
         rebase=false;
        }
      if(halted!="") {EO_Set(out,"HALTED",halted); return;}
      string bad=EO_UnsetConfig(c);
      if(bad!="") {EO_Set(out,"CONFIG_UNSET","INPUT_UNSET: "+bad); return;}
      SEoSymbol sym;
      mk.Symbol(sym);
      if(!(sym.read_ok && sym.trade_ok && sym.tick_size>0.0 && sym.vol_min>0.0 && sym.vol_step>0.0))
        {Defect(); EO_Set(out,"MARKET_NOT_READY","SYMBOL_UNREADABLE_OR_NOT_TRADABLE"); return;}
      SEoQuote q;
      mk.Quote(q);
      long now=mk.Now();
      if(!(q.read_ok && q.bid>0.0 && q.ask>=q.bid && q.time>0 && now>0 && now-q.time>=0 && now-q.time<=c.max_quote_age))
        {Defect(); EO_Set(out,"MARKET_NOT_READY","QUOTE_NOT_READY_OR_STALE"); return;}
      SSpbSelection sel=c.sel;
      sel.live_after=baseline;
      SSpbMarket m;
      SPB_MarketInit(m);
      m.risk_budget=c.risk_budget;
      m.tick_value=sym.reported_tick_value;
      m.tick_size=sym.tick_size;
      m.digits=sym.digits;
      m.point=sym.point;
      m.stops_level=(int)sym.stops_level;
      m.has_quote=true;
      m.bid=q.bid;
      m.ask=q.ask;
      m.vol_min=sym.vol_min;
      m.vol_step=sym.vol_step;
      m.vol_max=sym.vol_max;
      m.cap_lots=c.lot_cap;
      SSpbResult r1;
      STgResult geo;
      bool geometry_ok=SPB_Geometry(sel,m,st,f,broken,cut,r1,geo);
      out.spb=r1;
      if(!geometry_ok) {EO_Set(out,"NO_PLAN",r1.reason); return;}
      if(Handled(r1.signal_id)) {EO_Set(out,"ALREADY_HANDLED",r1.signal_id); return;}
      bool buy=(st.context.direction==1);
      long stop_ticks=(long)MathRound(geo.r_geom/sym.tick_size);
      double profit=0.0;
      bool ok=mk.CalcProfit(buy,sym.vol_min,geo.e_out,geo.s_out,profit);
      double tick=PB_ProbeTickValue(ok,profit,sym.vol_min,stop_ticks);
      if(!(tick>0.0)) {Defect(); EO_Set(out,"PROBE_FAILED","BROKER_PROBE_FAILED: no reliable loss estimate; no property fallback"); return;}
      m.tick_value=tick;
      SSpbResult r2;
      SPB_Build(sel,m,st,f,broken,cut,r2);                    // pass 2: the plan the gate sees
      out.spb=r2;
      if(!r2.plan_ready) {EO_Set(out,"NO_PLAN",r2.reason); return;}
      profit=0.0;
      ok=mk.CalcProfit(buy,r2.plan.volume_out,r2.plan.e_out,r2.plan.s_out,profit);
      if(!ok || !TG_Finite(profit)) Defect();
      int session=TP_SESSION_UNKNOWN,news=TP_NEWS_UNKNOWN,spread=TP_SPREAD_UNKNOWN;
      mk.Filters(session,news,spread);
      string digest=EN_PlanDigest(r2.plan);
      SEgChecks chk;
      chk.permit_inputs=true;
      chk.snap.data_state=(st.context.ready && st.context.reliable && st.context.selected ? TP_DATA_READY : TP_DATA_NOT_READY);
      chk.snap.data_reliable=st.context.reliable;
      chk.snap.session_state=session;
      chk.snap.news_state=news;
      chk.snap.spread_state=spread;
      chk.snap.open_positions=c.open_positions;
      chk.snap.trades_today=c.trades_today;
      chk.snap.existing_risk=c.existing_risk;
      chk.snap_time=now;
      chk.snap_digest=digest;
      chk.lim.max_positions_set=(c.max_positions>=0);
      chk.lim.max_positions=c.max_positions;
      chk.lim.max_trades_set=(c.max_trades>=0);
      chk.lim.max_trades=c.max_trades;
      chk.lim.risk_cap_set=(c.risk_cap>=0.0);
      chk.lim.risk_cap=c.risk_cap;
      chk.calc_ok=ok;
      chk.profit=profit;
      chk.tolerance=c.model_tolerance;
      chk.risk_budget=c.risk_budget;
      chk.loss_time=now;
      chk.loss_digest=digest;
      SDbResult daily;
      daily.entry_allowed=false;
      daily.primary="";
      daily.n_reasons=0;
      daily.dl_called=false;
      daily.closed_result=0.0;
      daily.cancel_pending_due=false;
      daily.daily_limit_reached=false;
      daily.day_key=0;
      chk.daily_present=mk.Daily(r2.plan,daily);
      chk.daily=daily;
      chk.daily_time=now;
      chk.daily_digest=digest;
      string reg[];
      ArrayResize(reg,n_handled+1);
      for(int i=0;i<n_handled;i++) reg[i]=handled[i];
      reg[n_handled]="";
      SEnRuntime rt;
      EN_RuntimeInit(rt);
      EG_Submit(c.gate,c.exec,tr,store,rt,r2,chk,reg,n_handled,out.res,out.dec,pre_send);
      out.status="EXECUTOR";
      out.reason=out.res.reason;
      if(!out.dec.allow) {out.status="GATE_BLOCKED"; return;}
      if(StringFind(out.res.reason,"PRE_SEND_RESERVATION_FAILED")==0) {out.status="RESERVATION_FAILED"; return;}      // nothing was placed and the signal is NOT consumed
      if(out.res.outcome==EN_R_PLACED || out.res.outcome==EN_R_FILLED)
        {
         out.request=true;
         out.label=EO_FAKE_LABEL;
         signals++;
        }
      ENUM_EN_RESULT fr=out.res.outcome;
      if(fr==EN_R_PLACED || fr==EN_R_FILLED || fr==EN_R_DUPLICATE || fr==EN_R_REJECTED || fr==EN_R_RECOVERY || fr==EN_R_BLOCKED || fr==EN_R_PRECHECK_REFUSED || fr==EN_R_CANCELLED ||
         fr==EN_R_EXPIRED || fr==EN_R_NOCHANGE) Remember(r2.signal_id);
      if(fr==EN_R_RECOVERY || fr==EN_R_BLOCKED || fr==EN_R_CANCEL_UNCERTAIN) halted="HALTED after "+EN_ResultName(fr)+": restart and reconcile first";
     }
  };
#endif
