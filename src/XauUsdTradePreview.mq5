// T008 manually supplied candidate + real broker parameters. NEVER sends orders.
// T010 adds opt-in automatic USD-high-news (MT5 calendar, read-only) and spread filters; results feed only the permit snapshot.
#property strict
#property version "1.03"
#include "include/SymbolSnapshot.mqh"
#include "include/BrokerLossCheck.mqh"
#include "include/SessionPolicy.mqh"
#include "include/NewsSpreadFilters.mqh"
enum PREVIEW_SIDE {PREVIEW_UNSET=0,PREVIEW_BUY=1,PREVIEW_SELL=-1};
enum PREVIEW_STATE {STATE_UNKNOWN=0,STATE_CLEAR=1,STATE_BLOCK=2};
enum PREVIEW_SESSION_SOURCE {SESSION_MANUAL=0,SESSION_TIRANE_CLOCK=1};
enum PREVIEW_NEWS_SOURCE {NEWS_SRC_MANUAL=0,NEWS_SRC_CALENDAR_AUTO=1};
enum PREVIEW_SPREAD_SOURCE {SPREAD_SRC_MANUAL=0,SPREAD_SRC_QUOTE_AUTO=1};
input PREVIEW_SIDE InpDirection=PREVIEW_UNSET;
input string InpSignalId="";
input string InpSetupId="";
input double InpEntry=0;
input double InpStopLoss=0;
input bool InpHasTarget=false;
input double InpTarget=0;
input double InpRiskBudget=0; // account currency, NOT percent; no automatic risk base
input double InpLotCap=10; // confirmed client cap; no clamping
input PREVIEW_STATE InpDataState=STATE_UNKNOWN;
input PREVIEW_STATE InpSessionState=STATE_UNKNOWN;
input PREVIEW_SESSION_SOURCE InpSessionSource=SESSION_MANUAL; // auto uses PC-derived UTC, unavailable in tester
input int InpSessionStartMinute=0;
input int InpSessionEndMinute=1230;
input int InpSessionWeekdayMask=62;
input bool InpFridayCloseEnabled=true;
input int InpFridayCloseMinute=1260;
input PREVIEW_NEWS_SOURCE InpNewsSource=NEWS_SRC_MANUAL; // auto: MT5 calendar, USD + HIGH, +-30 min, server time; unavailable in tester
input PREVIEW_STATE InpNewsState=STATE_UNKNOWN; // used only when InpNewsSource=NEWS_SRC_MANUAL
input PREVIEW_SPREAD_SOURCE InpSpreadSource=SPREAD_SRC_MANUAL; // auto: (Ask-Bid)/point of the quote this preview already reads
input double InpMaxSpreadPoints=-1; // auto spread only; -1 = policy UNSET (blocks); 0 = only zero spread; no default value is chosen
input PREVIEW_STATE InpSpreadState=STATE_UNKNOWN; // used only when InpSpreadSource=SPREAD_SRC_MANUAL
input PREVIEW_STATE InpSignalUnused=STATE_UNKNOWN; // CLEAR=externally confirmed unused; BLOCK=duplicate
input long InpOpenPositions=-1; // explicit external snapshot, NOT read from account
input long InpTradesToday=-1;
input double InpExistingRisk=-1;
input long InpMaxPositions=-1; // -1 = policy unset, no silent choice
input long InpMaxTrades=-1;
input double InpCombinedRiskCap=-1; // money in account currency, not percent
input double InpModelTolerance=.01; // diagnostic convention: relative model discrepancy
input int InpMaxQuoteAgeSeconds=30; // diagnostic freshness limit
string panel="PREVIEW ONLY / NO ORDERS\nInitialising";

void Paint()
  {
   Comment(panel);
   ChartRedraw();
  }
void StopPreview(const string reason)
  {
   panel="T008 PREVIEW ONLY / NO ORDERS\nBLOCK: "+reason;
   Print("T008 PREVIEW BLOCK: ",reason);Paint();
  }
// Thin READ-ONLY calendar reader (T010). The only place that touches the MT5 economic calendar. Converts calendar values into
// SNfEvent records for the pure NF_NewsEvaluate. Times are server time (calendar value time vs TimeTradeServer), no UTC/Tirane.
int ReadUsdCalendar(const datetime now,SNfEvent &events[],int &count)
  {
   ArrayResize(events,0);count=0;
   if(MQLInfoInteger(MQL_TESTER)) return(NF_Q_TESTER);
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return(NF_Q_NOT_READY);
   MqlCalendarValue values[];
   datetime query_from=0,query_to=0;
   if(!NF_QueryRange(now,query_from,query_to)) {Print("T010 CALENDAR query range invalid for server now ",(long)now);return(NF_Q_ERROR);}
   ResetLastError();
   // CalendarValueHistory returns int (the number of values): keep it as int and classify with the pure helper.
   int ret=CalendarValueHistory(values,query_from,query_to,NULL,"USD");
   int read_error=GetLastError();
   int total=ArraySize(values);
   int read_status=NF_ClassifyCalendarRead(ret,read_error,total);
   PrintFormat("T010 CALENDAR query ok=%d ret=%d error=%d values=%d range_server=%s..%s window +-%d s inside day-widened range",(int)(read_status==NF_Q_OK),ret,read_error,total,
               TimeToString(query_from,TIME_DATE|TIME_SECONDS),TimeToString(query_to,TIME_DATE|TIME_SECONDS),NF_WINDOW_SECONDS);
   if(read_status!=NF_Q_OK) return(NF_Q_ERROR);
   if(total<=0) return(NF_Q_OK);
   ArrayResize(events,total);
   for(int i=0;i<total;i++)
     {
      events[i].time=values[i].time;
      events[i].time_ok=false;events[i].currency="";events[i].importance=NF_IMP_NONE;events[i].fetch_ok=false;events[i].name="";
      MqlCalendarEvent cal_event;
      MqlCalendarCountry country;
      if(!CalendarEventById(values[i].event_id,cal_event)) continue;
      if(!CalendarCountryById(cal_event.country_id,country)) continue;
      events[i].fetch_ok=true;
      events[i].currency=country.currency;
      events[i].name=cal_event.name;
      events[i].importance=(cal_event.importance==CALENDAR_IMPORTANCE_HIGH ? NF_IMP_HIGH :
                            cal_event.importance==CALENDAR_IMPORTANCE_MODERATE ? NF_IMP_MODERATE :
                            cal_event.importance==CALENDAR_IMPORTANCE_LOW ? NF_IMP_LOW : NF_IMP_NONE);
      events[i].time_ok=(cal_event.time_mode==CALENDAR_TIMEMODE_DATETIME && values[i].time>0);
     }
   count=total;
   return(NF_Q_OK);
  }
void Evaluate()
  {
   SSymbolSnapshot symbol;
   if(!SymbolSnapshotLoad(_Symbol,symbol)) {StopPreview("SYMBOL: "+symbol.problem);return;}
   Print("T008 SYMBOL ",SymbolSnapshotReport(symbol));
   if(InpDirection==PREVIEW_UNSET || TP_IsBlank(InpSignalId) || TP_IsBlank(InpSetupId) ||
      InpEntry<=0 || InpStopLoss<=0 || InpRiskBudget<=0)
     {StopPreview("INPUT_UNSET: supply direction, IDs, entry, SL and monetary risk budget");return;}
   if(!TG_Finite(InpModelTolerance) || InpModelTolerance<0 || InpModelTolerance>1 || InpMaxQuoteAgeSeconds<1)
     {StopPreview("INVALID_INPUT: diagnostic tolerance or quote age");return;}
   if(symbol.stops_level<0 || symbol.stops_level>2147483647)
     {StopPreview("INVALID_SYMBOL_STOPS");return;}
   long mode=symbol.trade_mode;
   if(mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY ||
      (mode==SYMBOL_TRADE_MODE_LONGONLY && InpDirection==PREVIEW_SELL) ||
      (mode==SYMBOL_TRADE_MODE_SHORTONLY && InpDirection==PREVIEW_BUY) || mode<0 || mode>SYMBOL_TRADE_MODE_FULL)
     {StopPreview("SYMBOL_DIRECTION_NOT_ALLOWED");return;}
   MqlTick quote;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !SymbolInfoTick(_Symbol,quote) || quote.time<=0 ||
      !TG_Finite(quote.bid) || !TG_Finite(quote.ask) || quote.bid<=0 || quote.ask<quote.bid)
     {StopPreview("QUOTE_NOT_READY");return;}
   datetime now=TimeTradeServer();
   long age=(long)now-(long)quote.time;
   if(now<=0 || age<0 || age>InpMaxQuoteAgeSeconds) {StopPreview("QUOTE_STALE");return;}
   // Symbol tick values can be inconsistent with the broker's account-currency calculation.
   // Normalize through the existing geometry first, then calibrate this candidate with a
   // valid minimum-volume read-only profit estimate. No fallback to the reported property.
   STgResult geometry;
   TG_Compute((int)InpDirection,InpEntry,InpStopLoss,InpHasTarget,InpTarget,symbol.tick_size,symbol.digits,
              symbol.point,(int)symbol.stops_level,true,quote.bid,quote.ask,geometry);
   if(geometry.status!=TG_OK) {StopPreview("GEOMETRY: "+geometry.reason);return;}
   double property_tick=0;
   bool property_ok=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS,property_tick);
   double probe_profit=0;
   ResetLastError();
   bool probe_ok=OrderCalcProfit(InpDirection==PREVIEW_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                 _Symbol,symbol.volume_min,geometry.e_out,geometry.s_out,probe_profit);
   int probe_error=GetLastError();
   double tick_value=PB_ProbeTickValue(probe_ok,probe_profit,symbol.volume_min,geometry.r_ticks);
   PrintFormat("T008 BROKER PROBE calc=%d error=%d volume=%.8f profit=%.8f effective_tick=%.10f reported_tick=%.10f reported_ok=%d currency=%s",
               (int)probe_ok,probe_error,symbol.volume_min,probe_profit,tick_value,property_tick,(int)property_ok,symbol.account_currency);
   if(tick_value<=0) {StopPreview("BROKER_PROBE_FAILED: no reliable loss estimate; no property fallback");return;}
   STpPlan plan;
   TP_BuildPlan(InpSignalId,InpSetupId,(int)InpDirection,InpEntry,InpStopLoss,InpHasTarget,InpTarget,
                InpRiskBudget,tick_value,symbol.tick_size,symbol.digits,symbol.point,(int)symbol.stops_level,
                true,quote.bid,quote.ask,symbol.volume_min,symbol.volume_step,symbol.volume_max,InpLotCap,plan);
   if(plan.status!=TP_OK) {StopPreview("PLAN: "+plan.reason);return;}
   double profit=0;
   ResetLastError();
   bool calculated=OrderCalcProfit(InpDirection==PREVIEW_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                  _Symbol,plan.volume_out,plan.e_out,plan.s_out,profit);
   int calculation_error=GetLastError();
   string loss_check=PB_CheckLoss(calculated,profit,plan.risk_model,InpRiskBudget,InpModelTolerance);
   PrintFormat("T008 BROKER LOSS check=%s calc=%d error=%d model=%.8f broker=%.8f budget=%.8f currency=%s tolerance=%.6f",
               loss_check,(int)calculated,calculation_error,plan.risk_model,-profit,InpRiskBudget,symbol.account_currency,InpModelTolerance);
   STpSnapshot snap;
   snap.data_state=(InpDataState==STATE_CLEAR ? TP_DATA_READY : InpDataState==STATE_BLOCK ? TP_DATA_NOT_READY : TP_DATA_UNKNOWN);
   snap.data_reliable=(InpDataState==STATE_CLEAR);
   snap.session_state=(InpSessionState==STATE_CLEAR ? TP_SESSION_OPEN : InpSessionState==STATE_BLOCK ? TP_SESSION_CLOSED : TP_SESSION_UNKNOWN);
   if(InpSessionSource==SESSION_TIRANE_CLOCK)
     {
      if(MQLInfoInteger(MQL_TESTER)) {StopPreview("SESSION_UTC_UNAVAILABLE_IN_TESTER");return;}
      SSessionPolicy session;
      if(!SP_Evaluate(TimeGMT(),InpSessionStartMinute,InpSessionEndMinute,InpSessionWeekdayMask,
                      InpFridayCloseEnabled,InpFridayCloseMinute,session))
        {StopPreview("SESSION_CLOCK: "+session.status);return;}
      snap.session_state=(session.entry_open ? TP_SESSION_OPEN : TP_SESSION_CLOSED);
      PrintFormat("T009 SESSION UTC %s | Tirane %s | day %d | midnightUTC %s | open=%d cancel_pending_due=%d friday_close_due=%d | PC clock source, no actions",
                  TimeToString(session.utc,TIME_DATE|TIME_SECONDS),TimeToString(session.local_time,TIME_DATE|TIME_SECONDS),
                  session.day_key,TimeToString(session.midnight_utc,TIME_DATE|TIME_SECONDS),(int)session.entry_open,
                  (int)session.cancel_pending_due,(int)session.friday_close_due);
     }
   snap.news_state=(InpNewsState==STATE_CLEAR ? TP_NEWS_CLEAR : InpNewsState==STATE_BLOCK ? TP_NEWS_BLOCKED : TP_NEWS_UNKNOWN);
   snap.spread_state=(InpSpreadState==STATE_CLEAR ? TP_SPREAD_CLEAR : InpSpreadState==STATE_BLOCK ? TP_SPREAD_BLOCKED : TP_SPREAD_UNKNOWN);
   string news_text="MANUAL "+EnumToString(InpNewsState),spread_text="MANUAL "+EnumToString(InpSpreadState);
   if(InpNewsSource==NEWS_SRC_CALENDAR_AUTO)
     {
      SNfEvent news_events[];
      int news_count=0;
      int news_query=ReadUsdCalendar(now,news_events,news_count);
      SNfNews news;
      NF_NewsEvaluate(now,news_events,news_count,news_query,news);
      snap.news_state=NF_ToNewsState(news.state);
      PrintFormat("T010 NEWS source=CALENDAR_AUTO status=%s state=%s blocking=%d unknown=%d nearest=%s '%s' | server now %s | USD HIGH +-%d s inclusive | filter result feeds permit snapshot only, no actions",
                  news.status,NF_StateName(news.state),news.blocking,news.unknown,TimeToString(news.nearest_time,TIME_DATE|TIME_SECONDS),
                  news.nearest_name,TimeToString(now,TIME_DATE|TIME_SECONDS),NF_WINDOW_SECONDS);
      news_text="CALENDAR_AUTO "+news.status+(news.blocking>0 ? " ("+news.nearest_name+" "+TimeToString(news.nearest_time,TIME_DATE|TIME_SECONDS)+")" : "");
     }
   else PrintFormat("T010 NEWS source=MANUAL state=%s | filter result feeds permit snapshot only",EnumToString(InpNewsState));
   if(InpSpreadSource==SPREAD_SRC_QUOTE_AUTO)
     {
      SNfSpread spread;
      NF_SpreadEvaluate(quote.bid,quote.ask,symbol.point,InpMaxSpreadPoints,spread);
      snap.spread_state=NF_ToSpreadState(spread.state);
      PrintFormat("T010 SPREAD source=QUOTE_AUTO status=%s state=%s spread_points=%.6f max_points=%.6f tolerance=%.3e bid=%.8f ask=%.8f point=%.8f | same quote as the preview, feeds permit snapshot only, no actions",
                  spread.status,NF_StateName(spread.state),spread.spread_points,InpMaxSpreadPoints,spread.tolerance,quote.bid,quote.ask,symbol.point);
      spread_text="QUOTE_AUTO "+spread.status+" "+DoubleToString(spread.spread_points,4)+" pts (max "+DoubleToString(InpMaxSpreadPoints,4)+")";
     }
   snap.open_positions=InpOpenPositions;snap.trades_today=InpTradesToday;snap.existing_risk=InpExistingRisk;
   STpLimits limits;
   limits.max_positions_set=(InpMaxPositions>=0);limits.max_positions=InpMaxPositions;
   limits.max_trades_set=(InpMaxTrades>=0);limits.max_trades=InpMaxTrades;
   limits.risk_cap_set=(InpCombinedRiskCap>=0);limits.risk_cap=InpCombinedRiskCap;
   string ids[];ArrayResize(ids,1);ids[0]=(InpSignalUnused==STATE_BLOCK ? InpSignalId : "");
   STpPermit permit;
   STpPlan guarded=plan;
   // Keep original model for reporting; use the larger estimate for exposure checks.
   if(loss_check=="OK") guarded.risk_model=PB_PermitRisk(profit,plan.risk_model);
   TP_CheckPermit(guarded,snap,limits,ids,(InpSignalUnused==STATE_BLOCK ? 1 : 0),permit);
   // NEVER register or consume a preview signal. Unknown usage must still block.
   if(InpSignalUnused!=STATE_CLEAR && InpSignalUnused!=STATE_BLOCK)
     {
      TP_AddReason(permit,"SIGNAL_USAGE_UNKNOWN");
      permit.allow=false;
      if(permit.primary_reason=="") permit.primary_reason="SIGNAL_USAGE_UNKNOWN";
     }
   bool preview_ok=(loss_check=="OK" && permit.allow);
   string reasons=TP_ReasonsText(permit);
   panel="T008 PREVIEW ONLY / NO ORDERS\n"+_Symbol+" / "+symbol.account_currency+"\n"+
         "E "+DoubleToString(plan.e_out,symbol.digits)+" SL "+DoubleToString(plan.s_out,symbol.digits)+
         " TP "+DoubleToString(plan.tp,symbol.digits)+"\nLots "+DoubleToString(plan.volume_out,8)+
         " | model loss "+DoubleToString(plan.risk_model,4)+"\nBroker loss check: "+loss_check+
         "\n"+(preview_ok ? "PREVIEW CHECKS PASS" : "PREVIEW BLOCK")+"\n"+reasons+
         "\nPermit risk "+DoubleToString(guarded.risk_model,4)+
         "\nNEWS "+news_text+"\nSPREAD "+spread_text+"\nFilter results feed ONLY the permit snapshot; no order action."+
         "\nExternal policy snapshot; costs/actual fills NOT modelled.\nStatic snapshot: reattach or change inputs to refresh.";
   PrintFormat("T008 PREVIEW RESULT %s | E %.8f SL %.8f TP %.8f lots %.8f | loss_check %s | permit %s | reasons %s | NO ORDERS",
               preview_ok ? "CHECKS_PASS" : "BLOCK",plan.e_out,plan.s_out,plan.tp,plan.volume_out,loss_check,
               permit.allow ? "ALLOW_PREVIEW_ONLY" : "BLOCK",reasons);
   Paint();
  }
int OnInit() {Evaluate();return(INIT_SUCCEEDED);}
void OnDeinit(const int reason) {Comment("");Print("T008 preview stopped. No orders were sent, changed or closed.");}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {if(id==CHARTEVENT_CHART_CHANGE) Paint();}
