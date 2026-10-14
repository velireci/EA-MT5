// T008 manually supplied candidate + real broker parameters. NEVER sends orders.
#property strict
#property version "1.00"
#include "include/SymbolSnapshot.mqh"
#include "include/BrokerLossCheck.mqh"
enum PREVIEW_SIDE {PREVIEW_UNSET=0,PREVIEW_BUY=1,PREVIEW_SELL=-1};
enum PREVIEW_STATE {STATE_UNKNOWN=0,STATE_CLEAR=1,STATE_BLOCK=2};
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
input PREVIEW_STATE InpNewsState=STATE_UNKNOWN;
input PREVIEW_STATE InpSpreadState=STATE_UNKNOWN;
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
   double tick_value=0;
   if(!SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS,tick_value) || !TG_Finite(tick_value) || tick_value<=0)
     {StopPreview("LOSS_TICK_VALUE_UNAVAILABLE");return;}
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
   snap.news_state=(InpNewsState==STATE_CLEAR ? TP_NEWS_CLEAR : InpNewsState==STATE_BLOCK ? TP_NEWS_BLOCKED : TP_NEWS_UNKNOWN);
   snap.spread_state=(InpSpreadState==STATE_CLEAR ? TP_SPREAD_CLEAR : InpSpreadState==STATE_BLOCK ? TP_SPREAD_BLOCKED : TP_SPREAD_UNKNOWN);
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
