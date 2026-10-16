// T016 FEED + REAL READ-ONLY MARKET for the entry-orchestrator EA. COMPILE-ONLY (it reads the terminal, so no unit test can run it; the decision core in EntryOrchestrator.mqh is the tested part).
//  CEoFeed        : the existing T004 replay glue (a COPY of Build / CopyClosed / Snapshot of XauUsdM15Observer.mq5, which cannot be included: it is an EA) -> SM4State / SM4Candidate / the broken level.
//  CEoRealMarket  : CEoMarket over READ-ONLY terminal reads (SymbolInfo*, SymbolInfoTick, OrderCalcProfit, calendar, history, the T012 day-balance store via DBS_Load ONLY).
// No OrderSend, no CAPTURE, no file write, no drawing. A value that cannot be read is UNKNOWN / not ready, never zero and never CLEAR.
#ifndef VELO_ENTRY_ORCHESTRATOR_FEED_MQH
#define VELO_ENTRY_ORCHESTRATOR_FEED_MQH

#include "TimeframeWatcher.mqh"
#include "H4M15Bridge.mqh"
#include "H4TouchContext.mqh"
#include "M15Timeline.mqh"
#include "SymbolSnapshot.mqh"
#include "SessionPolicy.mqh"
#include "NewsSpreadFilters.mqh"
#include "DailyPreviewGate.mqh"
#include "DailyBridge.mqh"
#include "DailyBalanceStore.mqh"
#include "EntryOrchestrator.mqh"

#define EO_SRC_UNSELECTED 0
#define EO_SRC_T003 1
#define EO_SRC_T002_AFTER_LOSS 2
#define EO_SRC_T002_FIRST_ONLY 3

struct SEoFeedCfg
  {
   int source;                  // EO_SRC_*; UNSELECTED blocks
   bool level_proposal;         // M15 level = latest fractal PROPOSAL; false blocks
   bool timing_after_bos;       // FVG timing = A_AT_OR_AFTER_BREAK PROPOSAL; false blocks
   int h4_rebuild;
   int h4_lookback;
   int h4_left;
   int h4_right;
   int warm;
   int m15_replay;
   int m15_lookback;
   int m15_left;
   int m15_right;
  };

bool EO_FeedCfgValid(const SEoFeedCfg &c)
  {
   return(c.source>=EO_SRC_T003 && c.source<=EO_SRC_T002_FIRST_ONLY && c.level_proposal && c.timing_after_bos &&
          c.h4_lookback>=50 && c.h4_lookback<=1000 && c.h4_rebuild>=3*c.h4_lookback && c.h4_rebuild<=5000 && c.h4_left>=1 && c.h4_left<=10 && c.h4_right>=1 && c.h4_right<=10 &&
          c.m15_left>=1 && c.m15_left<=10 && c.m15_right>=1 && c.m15_right<=10 && c.m15_lookback>=c.m15_left+c.m15_right+1 && c.m15_lookback<=1000 &&
          c.warm>=10 && c.warm<=1000 && c.m15_replay>=16 && c.m15_replay<=5000);
  }

string EO_SourceId(const int source)
  {
   if(source==EO_SRC_T002_AFTER_LOSS || source==EO_SRC_T002_FIRST_ONLY) return(M4_SRC_T002_TOUCH);
   return(source==EO_SRC_T003 ? M4_SRC_T003 : "");
  }

class CEoFeed
  {
public:
   CTimeframeWatcher h4,m15;
   SEoFeedCfg cfg;
   SH3Params params;
   SM4State st;
   SM4Candidate f[];
   SM4Event ev[];
   SM4TimelineInfo info;
   SM4OrdInfo ord;
   string notes[];
   SM4ContextUpdate updates[];
   MqlRates mbars[],hbars[];
   SM4Level broken;
   datetime cut;
   datetime replay_start;
   bool built;
   string problem;
   // chart view only (InpChartView): the arrays and the evaluation of the LAST snapshot, copied from what the build already computed; nothing here is read by a decision
   bool keep_view;
   bool dv_have;
   int dv_n;                    // closed H4 bars of that snapshot (hbars[0..dv_n-1])
   SH3Eval dv_ev;
   SH3Track dv_tracks[];
   SH3Event dv_events[];
   // diagnostics only: the result of the T003 evaluation that the existing build already computed for the LAST snapshot (no second evaluation, nothing here is read by a decision)
   bool dg_have;
   bool dg_ctx_ok;              // what M4ContextFromH3 returned for that snapshot
   bool dg_state;
   bool dg_reliable;
   int dg_flag;
   string dg_reason;
   bool dg_valid;
   bool dg_ready;
   string dg_phase;
   string dg_direction;
   datetime dg_known;
   void Init(const SEoFeedCfg &c)
     {
      cfg=c;
      keep_view=false;                         // the EA switches it on AFTER Init when the chart view is requested
      dv_n=0;
      H3ParamsDefault(params);
      params.rebuild=c.h4_rebuild;
      params.lookback=c.h4_lookback;
      params.left=c.h4_left;
      params.right=c.h4_right;
      h4.Configure(_Symbol,PERIOD_H4,3);
      m15.Configure(_Symbol,PERIOD_M15,3);
      Reset("initialising");
     }
   void Reset(const string reason)
     {
      M4ResetReplay(st,f,ev,info,built,cut);
      M4NoLevel(broken);
      problem=reason;
      replay_start=0;
      dg_have=false;
      dv_have=false;
     }
   bool Ordinary(void) {return(cfg.source==EO_SRC_T002_AFTER_LOSS || cfg.source==EO_SRC_T002_FIRST_ONLY);}
   int CopyClosed(const ENUM_TIMEFRAMES tf,const datetime at,const int want,MqlRates &out[])
     {
      MqlRates raw[];
      ArraySetAsSeries(raw,false);
      int n=CopyRates(_Symbol,tf,at,want+2,raw);
      ArrayResize(out,0);
      if(n<=0) {ResetLastError(); return(-1);}
      int period=PeriodSeconds(tf);
      int closed=H4ClosedCountAsOf(raw,n,at,period);
      int start=(closed>want ? closed-want : 0);
      for(int i=0;i<n;i++)
         if(i>0 && raw[i].time<=raw[i-1].time) return(-1);
      ArrayResize(out,closed-start);
      for(int i=start;i<closed;i++)
        {
         if(!MathIsValidNumber(raw[i].high) || !MathIsValidNumber(raw[i].low) || !MathIsValidNumber(raw[i].close) || raw[i].low<=0 || raw[i].high<raw[i].low ||
            raw[i].close<raw[i].low || raw[i].close>raw[i].high) return(-1);
         out[i-start]=raw[i];
        }
      return(ArraySize(out));
     }
   // copy for the chart view; field by field (the structs hold strings); the evaluation is NOT repeated
   void KeepView(const int n,const SH3Eval &e,const SH3Track &tracks[],const SH3Event &events[])
     {
      dv_have=true;
      dv_n=n;
      dv_ev.has_state=e.has_state; dv_ev.reliable=e.reliable; dv_ev.flag=e.flag; dv_ev.reason=e.reason; dv_ev.note=e.note;
      dv_ev.r_request=e.r_request; dv_ev.r_req=e.r_req; dv_ev.r_eff=e.r_eff; dv_ev.b_depth=e.b_depth; dv_ev.warm=e.warm; dv_ev.chk=e.chk; dv_ev.n_avail=e.n_avail;
      dv_ev.key=e.key; dv_ev.key_prev=e.key_prev; dv_ev.last_time=e.last_time; dv_ev.trusted_from=e.trusted_from; dv_ev.anchor=e.anchor; dv_ev.anchor_missing=e.anchor_missing;
      dv_ev.prev_ok=e.prev_ok; dv_ev.cause=e.cause; dv_ev.nt=e.nt; dv_ev.ne=e.ne;
      H3StateCopy(e.st,dv_ev.st);
      int nt=(e.nt>0 ? MathMin(e.nt,ArraySize(tracks)) : 0);
      int ne=(e.ne>0 ? MathMin(e.ne,ArraySize(events)) : 0);
      ArrayResize(dv_tracks,nt);
      for(int i=0;i<nt;i++) H3TrackCopy(tracks[i],dv_tracks[i]);
      ArrayResize(dv_events,ne);
      for(int j=0;j<ne;j++)
        {
         dv_events[j].type=events[j].type; dv_events[j].bar_time=events[j].bar_time; dv_events[j].ref=events[j].ref;
         dv_events[j].detail=events[j].detail; dv_events[j].market=events[j].market; dv_events[j].sig=events[j].sig;
        }
     }
   void T003View(const int n,SH3Eval &e,SH3SetupCtx &c)
     {
      SH3Track tracks[];
      SH3Event events[];
      H3Evaluate(hbars,n,params,e,tracks,events);
      H3SetupContext(e.st,tracks,e.nt,c);
      if(keep_view) KeepView(n,e,tracks,events);
     }
   void Snapshot(const int n,const datetime known)
     {
      SH3Eval e;
      SH3SetupCtx c;
      T003View(n,e,c);
      int k=ArraySize(updates);
      ArrayResize(updates,k+1,64);
      updates[k].known=known;
      dg_ctx_ok=M4ContextFromH3(c,e.reliable,updates[k].context,cfg.source==EO_SRC_T003);
      dg_have=true; dg_state=e.has_state; dg_reliable=e.reliable; dg_flag=e.flag; dg_reason=e.reason;
      dg_valid=c.valid; dg_ready=c.ready; dg_phase=c.phase; dg_direction=c.direction; dg_known=known;
     }
   // the broken level of the current BOS: the level the SAME M15 selection offered to the bar that broke it (no new level rule; SetupPlanBridge verifies id / price / time)
   void BrokenLevel(const int nm)
     {
      M4NoLevel(broken);
      if(!st.has_context || st.bos_time==0) return;
      for(int i=0;i<nm;i++)
         if(mbars[i].time==st.bos_time)
           {
            SM4Selection s;
            M4SelectSwingProposal(mbars,i,st.context.direction,s,true,cfg.m15_left,cfg.m15_right,cfg.m15_lookback);
            if(s.level.valid && s.level.id==st.bos_level) broken=s.level;
            return;
           }
     }
   bool Build(const datetime at)
     {
      int want=cfg.m15_replay+cfg.m15_lookback;
      int nm=CopyClosed(PERIOD_M15,at,want,mbars);
      if(nm<want) {Reset("M15 history loading"); return(false);}
      if(mbars[nm-1].time!=m15.ClosedOpenTime()) {Reset("M15 boundary changed during copy"); return(false);}
      int first=nm-cfg.m15_replay;
      replay_start=mbars[first].time;
      int extra=(int)((at-replay_start+14399)/14400)+2;
      bool ordinary=Ordinary();
      int need=(int)MathMax(params.rebuild,3*params.lookback);
      if(ordinary) need=(int)MathMax(need,cfg.h4_lookback+cfg.warm);
      int depth=(int)MathMin(10000,need+extra);
      int nh=CopyClosed(PERIOD_H4,at,depth,hbars);
      if(nh<=0) {Reset("H4 copy not ready"); return(false);}
      if(hbars[nh-1].time!=h4.ClosedOpenTime()) {Reset("H4 boundary changed during copy"); return(false);}
      int initial=H4ClosedCountAsOf(hbars,nh,replay_start,14400);
      int h4_need=(ordinary ? cfg.h4_lookback+cfg.warm : params.rebuild);
      if(initial<h4_need) {Reset("H4 replay history loading"); return(false);}
      ArrayResize(updates,0);
      ArrayResize(notes,0);
      ZeroMemory(ord);
      ord.status="-";
      if(!ordinary)
        {
         Snapshot(initial,replay_start);
         for(int i=initial;i<nh;i++)
           {
            datetime known=hbars[i].time+14400;
            if(known>at) break;
            Snapshot(i+1,known);                     // prefix only, never the final H4 state for an earlier M15 bar
           }
        }
      else
        {
         int retouch=(cfg.source==EO_SRC_T002_FIRST_ONLY ? M4_RETOUCH_FIRST_ONLY : M4_RETOUCH_AFTER_LOSS);
         M4OrdinaryScan(hbars,nh,initial-cfg.warm,params.left,params.right,cfg.h4_lookback,retouch,updates,notes,ord);
         if(ord.status!="OK") {Reset("ordinary scan "+ord.status); return(false);}
        }
      M4ReplayTimeline(mbars,nm,updates,ArraySize(updates),replay_start,at,cfg.level_proposal,M4_A_AT_OR_AFTER_BREAK,cfg.m15_left,cfg.m15_right,cfg.m15_lookback,st,f,ev,info);
      if(info.status!="OK") {Reset("timeline "+info.status); return(false);}
      BrokenLevel(nm);
      cut=at;
      built=true;
      problem="";
      return(true);
     }
   // one line for the status: the T003 result kept from the build, then the M15 observer state. The M15 context flags are cleared by the observer when has_context=0, so they never explain an H4 refusal.
   string Diag(void)
     {
      string h=(dg_have ? StringFormat("h3[phase=%s valid=%d ready=%d dir=%s eval_state=%d eval_reliable=%d flag=%d reason='%s' ctx_ok=%d known=%s]",dg_phase,(int)dg_valid,(int)dg_ready,dg_direction,(int)dg_state,(int)dg_reliable,dg_flag,dg_reason,(int)dg_ctx_ok,TimeToString(dg_known,TIME_DATE|TIME_MINUTES))
                                : (Ordinary() && built ? "h3[not used: ordinary T002 scan]" : "h3[no evaluation in the current build]"));
      return(StringFormat("feed[problem='%s' timeline=%s] %s m15[phase=%s has_context=%d ready=%d reliable=%d selected=%d]",problem,info.status,h,st.phase,(int)st.has_context,(int)st.context.ready,(int)st.context.reliable,(int)st.context.selected));
     }
   // true = a (re)build ran this call; feed_ok = the confirmed data is usable (false = a defect: the caller restarts the baseline)
   bool Poll(bool &feed_ok)
     {
      bool hc=false,mc=false;
      bool hr=h4.Refresh(hc),mr=m15.Refresh(mc);
      if(!hr || !mr)
        {
         Reset("series not ready: H4 "+h4.StateName()+" M15 "+m15.StateName());
         feed_ok=false;
         return(true);
        }
      datetime at=m15.FormingOpenTime();
      if(!M4TimelineNeedsBuild(false,built,at,cut,hc,mc)) {feed_ok=built; return(false);}
      feed_ok=Build(at);
      return(true);
     }
  };

struct SEoMarketCfg
  {
   bool session_on;             // PC-derived UTC window (SessionPolicy); false = session UNKNOWN (blocks)
   int session_start_minute;
   int session_end_minute;
   int session_weekday_mask;
   bool friday_close_enabled;
   int friday_close_minute;
   bool news_on;                // MT5 calendar (USD, HIGH); false = news UNKNOWN (blocks)
   double max_spread_points;    // -1 = UNSET = spread UNKNOWN (blocks)
   bool daily_on;               // T012 history bridge + day-balance store (LOAD only); false = no daily result (blocks)
   long daily_magic;
   long daily_offset_seconds;   // 99999 = UNSET
   bool daily_history_complete;
   string daily_formula;
   string daily_classification;
   long trades_today;           // the explicit counter inputs of the daily check (-1 = unknown)
   long wins;
   long consecutive_losses;
   long max_trades;
  };

int EO_ReadUsdCalendar(const datetime now,SNfEvent &events[],int &count)
  {
   ArrayResize(events,0);
   count=0;
   if(MQLInfoInteger(MQL_TESTER)) return(NF_Q_TESTER);
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return(NF_Q_NOT_READY);
   MqlCalendarValue values[];
   datetime query_from=0,query_to=0;
   if(!NF_QueryRange(now,query_from,query_to)) return(NF_Q_ERROR);
   ResetLastError();
   int ret=CalendarValueHistory(values,query_from,query_to,NULL,"USD");
   int read_error=GetLastError();
   int total=ArraySize(values);
   if(NF_ClassifyCalendarRead(ret,read_error,total)!=NF_Q_OK) return(NF_Q_ERROR);
   if(total<=0) return(NF_Q_OK);
   ArrayResize(events,total);
   for(int i=0;i<total;i++)
     {
      events[i].time=values[i].time;
      events[i].time_ok=false;
      events[i].currency="";
      events[i].importance=NF_IMP_NONE;
      events[i].fetch_ok=false;
      events[i].name="";
      MqlCalendarEvent cal_event;
      MqlCalendarCountry country;
      if(!CalendarEventById(values[i].event_id,cal_event)) continue;
      if(!CalendarCountryById(cal_event.country_id,country)) continue;
      events[i].fetch_ok=true;
      events[i].currency=country.currency;
      events[i].name=cal_event.name;
      events[i].importance=(cal_event.importance==CALENDAR_IMPORTANCE_HIGH ? NF_IMP_HIGH : cal_event.importance==CALENDAR_IMPORTANCE_MODERATE ? NF_IMP_MODERATE :
                            cal_event.importance==CALENDAR_IMPORTANCE_LOW ? NF_IMP_LOW : NF_IMP_NONE);
      events[i].time_ok=(cal_event.time_mode==CALENDAR_TIMEMODE_DATETIME && values[i].time>0);
     }
   count=total;
   return(NF_Q_OK);
  }

class CEoRealMarket : public CEoMarket
  {
public:
   SEoMarketCfg mc;
   virtual long Now(void) {return((long)TimeTradeServer());}
   virtual void Symbol(SEoSymbol &s)
     {
      SSymbolSnapshot snap;
      s.read_ok=SymbolSnapshotLoad(_Symbol,snap);
      s.tick_size=snap.tick_size;
      s.digits=snap.digits;
      s.point=snap.point;
      s.stops_level=snap.stops_level;
      s.vol_min=snap.volume_min;
      s.vol_step=snap.volume_step;
      s.vol_max=snap.volume_max;
      s.trade_ok=(snap.trade_mode==SYMBOL_TRADE_MODE_FULL);
      double loss_tick=0.0;
      s.reported_tick_value=(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS,loss_tick) ? loss_tick : 0.0);
      if(!s.read_ok) s.reported_tick_value=0.0;
     }
   virtual void Quote(SEoQuote &q)
     {
      MqlTick t;
      q.read_ok=(TerminalInfoInteger(TERMINAL_CONNECTED)!=0 && SymbolInfoTick(_Symbol,t) && t.time>0 && MathIsValidNumber(t.bid) && MathIsValidNumber(t.ask));
      q.bid=(q.read_ok ? t.bid : 0.0);
      q.ask=(q.read_ok ? t.ask : 0.0);
      q.time=(q.read_ok ? (long)t.time : 0);
     }
   virtual bool CalcProfit(const bool buy,const double volume,const double e,const double s,double &profit)
     {
      profit=0.0;
      ResetLastError();
      return(OrderCalcProfit(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,volume,e,s,profit));
     }
   virtual void Filters(int &session,int &news,int &spread)
     {
      session=TP_SESSION_UNKNOWN;
      news=TP_NEWS_UNKNOWN;
      spread=TP_SPREAD_UNKNOWN;
      if(MQLInfoInteger(MQL_TESTER)) return;
      if(mc.session_on)
        {
         SSessionPolicy sp;
         if(SP_Evaluate(TimeGMT(),mc.session_start_minute,mc.session_end_minute,mc.session_weekday_mask,mc.friday_close_enabled,mc.friday_close_minute,sp))
            session=(sp.entry_open ? TP_SESSION_OPEN : TP_SESSION_CLOSED);
        }
      if(mc.news_on)
        {
         SNfEvent events[];
         int count=0;
         int query=EO_ReadUsdCalendar(TimeTradeServer(),events,count);
         SNfNews n;
         NF_NewsEvaluate(TimeTradeServer(),events,count,query,n);
         news=NF_ToNewsState(n.state);
        }
      MqlTick t;
      double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      if(SymbolInfoTick(_Symbol,t) && point>0.0)
        {
         SNfSpread sp2;
         NF_SpreadEvaluate(t.bid,t.ask,point,mc.max_spread_points,sp2);
         spread=NF_ToSpreadState(sp2.state);
        }
     }
   // T012 daily result: READ-ONLY history facts -> DB_Check; the day balance comes from the store with DBS_Load ONLY (no CAPTURE). Anything not obtained -> false (the gate blocks).
   virtual bool Daily(const STpPlan &plan,SDbResult &r)
     {
      if(!mc.daily_on || MQLInfoInteger(MQL_TESTER)) return(false);
      int daily_offset=0;
      if(!EO_OffsetSeconds(mc.daily_offset_seconds,daily_offset)) return(false);
      SDhCfg hcfg;
      hcfg.ea_magic=mc.daily_magic;
      hcfg.utc_in_day=TimeGMT();
      hcfg.server_offset_seconds=daily_offset;
      hcfg.history_complete_asserted=mc.daily_history_complete;
      SDhFacts facts;
      SDhRaw raw;
      string reason="";
      ENUM_DH_VERDICT verdict=DH_ReadAndBuild(_Symbol,hcfg,facts,reason,raw);
      SDbBalance balance;
      CDbsRealPort port(mc.daily_magic,daily_offset,mc.daily_history_complete,_Symbol);
      SDbsResult stored;
      DBS_Load(port,stored);
      DBS_ForBridge(stored,balance);
      SDbPolicy policy;
      policy.result_formula=mc.daily_formula;
      policy.classification=mc.daily_classification;
      SDbClassified cl;
      cl.trades=DG_Counter(mc.trades_today);
      cl.wins=DG_Counter(mc.wins);
      cl.consecutive_losses=DG_Counter(mc.consecutive_losses);
      DB_Check(verdict,facts,hcfg.utc_in_day,balance,policy,cl,mc.max_trades>=0,(mc.max_trades>DL_MAX_COUNT ? DL_MAX_COUNT+1 : (int)(mc.max_trades<0 ? 0 : mc.max_trades)),r);
      return(true);
     }
  };
#endif
