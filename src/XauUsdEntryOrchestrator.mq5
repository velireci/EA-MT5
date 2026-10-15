// T016 ENTRY ORCHESTRATOR EA: H4/M15 observer flow (T004) -> SetupPlanBridge (T014) -> EntryGate (T015) -> EntryExecutor (T013) with a FAKE transport FIXED IN THIS DELIVERY.
//   FAKE EXECUTION: a virtual request is logged and counted in memory; NOTHING is sent to the terminal. The real transport is NOT included in this file and is NOT selectable by any input.
//   Market/account reads: closed bars, symbol / quote properties, OrderCalcProfit, calendar, deal history and T012 balance LOAD only. Only isolated FAKE entry records are written.
//   Every source / selection / policy input is UNSET by default and UNSET blocks. Exposure: EXPLICIT inputs by default (-1 = unknown) or the opt-in READ-ONLY account reader (T018: this EA magic, hedging account, pending policy explicit); the trade counter stays an explicit input. Chart symbol only (incl. XAUUSD.fx).
//   FAKE entry records persist in VELO_T016_FAKE_ files. Baseline, halt and fake orders remain in memory; this is not complete orchestrator recovery or proof of broker execution.
#property strict
#property version "1.02"
#include "include/EntryOrchestratorFeed.mqh"
#include "include/EntryTransportFake.mqh"
#include "include/ExposureReaderReal.mqh"
#include "include/EntryStateFile.mqh"

enum ENUM_EO_SOURCE {EOI_SRC_UNSELECTED=0,EOI_SRC_T003_RECONF_PROPOSAL=1,EOI_SRC_T002_TOUCH_AFTER_LOSS_PROPOSAL=2,EOI_SRC_T002_TOUCH_FIRST_ONLY_PROPOSAL=3};
enum ENUM_EO_SWING {EOI_SWING_UNSELECTED=0,EOI_SWING_LATEST_FRACTAL_PROPOSAL=1};
enum ENUM_EO_TIMING {EOI_TIMING_UNSELECTED=0,EOI_A_AT_OR_AFTER_BREAK_PROPOSAL=1};
enum ENUM_EO_CANDIDATE {EOI_CAND_UNSELECTED=0,EOI_CAND_SOLE_ELIGIBLE=2};
enum ENUM_EO_EDGE {EOI_EDGE_UNSELECTED=0,EOI_EDGE_NEAR_SIDE=1,EOI_EDGE_FAR_SIDE=2};
enum ENUM_EO_SL {EOI_SL_UNSELECTED=0,EOI_SL_BROKEN_LEVEL_PRICE_PLUS_BUFFER=1};
enum ENUM_EO_TARGET {EOI_TGT_UNSELECTED=0,EOI_TGT_NONE_2R_MINIMUM=1};
enum ENUM_EO_EXPOSURE {EOI_EXPOSURE_EXPLICIT=0,EOI_EXPOSURE_ACCOUNT_READ=1};
enum ENUM_EO_PENDING {EOI_PENDING_UNSET=0,EOI_PENDING_COUNT_AS_POSITIONS=1,EOI_PENDING_IGNORE=2};
enum ENUM_EO_FILLING {EOI_FILL_UNSET=0,EOI_FILL_RETURN=1};
enum ENUM_EO_EXPIRY {EOI_EXP_UNSET=0,EOI_EXP_GTC=1,EOI_EXP_SECONDS=2};

input ENUM_EO_SOURCE InpContextSource=EOI_SRC_UNSELECTED;
input ENUM_EO_SWING InpM15Level=EOI_SWING_UNSELECTED;
input ENUM_EO_TIMING InpFvgTiming=EOI_TIMING_UNSELECTED;
input ENUM_EO_CANDIDATE InpCandidate=EOI_CAND_UNSELECTED;
input ENUM_EO_EDGE InpEntryEdge=EOI_EDGE_UNSELECTED;
input ENUM_EO_SL InpSlRule=EOI_SL_UNSELECTED;
input double InpSlBuffer=-1;                 // price units; -1 = UNSET (blocks); 0 is a deliberate "no buffer"
input ENUM_EO_TARGET InpTargetRule=EOI_TGT_UNSELECTED;
input double InpRiskBudget=-1;               // account currency, NOT percent; -1 = UNSET
input double InpLotCap=-1;                   // -1 = UNSET
input double InpModelTolerance=-1;           // 0..1; -1 = UNSET
input long InpMaxQuoteAgeSeconds=-1;         // -1 = UNSET
input long InpGateMaxAgeSeconds=-1;          // age of the gate evidence; -1 = UNSET
input long InpPermitMaxAgeSeconds=-1;        // executor permit age; -1 = UNSET
input ENUM_EO_EXPOSURE InpExposureSource=EOI_EXPOSURE_EXPLICIT; // ACCOUNT_READ = READ-ONLY: open positions (+ pending per policy) and the loss-at-SL risk of THIS EA magic on a HEDGING account; the two explicit exposure inputs below are then IGNORED (no fallback)
input ENUM_EO_PENDING InpPendingPolicy=EOI_PENDING_UNSET; // ACCOUNT_READ only: whether an owned pending order reserves a position (owner policy; UNSET blocks)
input long InpOpenPositions=-1;              // explicit external snapshot; -1 = unknown (blocks)
input long InpTradesToday=-1;                // also the trade counter of the daily check; -1 = unknown
input double InpExistingRisk=-1;             // -1 = unknown
input long InpMaxPositions=-1;               // -1 = UNSET
input long InpMaxTrades=-1;                  // -1 = UNSET
input double InpCombinedRiskCap=-1;          // -1 = UNSET
input bool InpSessionClock=false;            // true = PC-derived UTC window below; false = session UNKNOWN (blocks)
input int InpSessionStartMinute=0;
input int InpSessionEndMinute=1230;
input int InpSessionWeekdayMask=62;
input bool InpFridayCloseEnabled=true;
input int InpFridayCloseMinute=1260;
input bool InpNewsCalendar=false;            // true = MT5 calendar USD HIGH; false = news UNKNOWN (blocks)
input double InpMaxSpreadPoints=-1;          // -1 = UNSET (blocks)
input bool InpDailyHistoryBridge=false;      // true = T012 history bridge + day-balance store (LOAD only); false = no daily result (blocks)
input long InpDailyEaMagic=0;
input long InpDailyServerOffsetSeconds=99999; // 99999 = UNSET
input bool InpDailyHistoryComplete=false;
input string InpDailyResultFormula="";
input string InpDailyClassification="";
input long InpDailyWins=-1;
input long InpDailyConsecutiveLosses=-1;
input long InpEaMagic=0;                     // >0 required by the (fake) executor
input ENUM_EO_FILLING InpFilling=EOI_FILL_UNSET;
input ENUM_EO_EXPIRY InpExpiryMode=EOI_EXP_UNSET;
input long InpExpirySeconds=-1;
input int InpH4RebuildBars=2000;
input int InpH4LookbackBars=300;
input int InpH4LeftBars=2;
input int InpH4RightBars=2;
input int InpOrdinaryWarmBars=120;
input int InpM15ReplayBars=512;
input int InpM15LookbackBars=300;
input int InpM15LeftBars=2;
input int InpM15RightBars=2;
input int InpPollSeconds=2;

// FAKE transport: the execution side is the in-memory fake (every Send is a virtual request, logged with the label); the read side is READ-ONLY terminal state.
class CEoTerminalFake : public CEnFakeTransport
  {
public:
   virtual long ServerTime(void) {return((long)TimeTradeServer());}
   virtual void ReadAccount(SEnAccount &a)
     {
      ResetLastError();
      a.login=AccountInfoInteger(ACCOUNT_LOGIN);
      a.server=AccountInfoString(ACCOUNT_SERVER);
      a.demo=(AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO);
      a.trade_allowed=(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)!=0 && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)!=0);
      a.margin_mode=(int)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      a.read_ok=(a.login>0 && a.server!="" && GetLastError()==0);
     }
   virtual void ReadSymbol(const string name,SEnSymbol &s)
     {
      ResetLastError();
      s.vol_min=SymbolInfoDouble(name,SYMBOL_VOLUME_MIN);
      s.vol_step=SymbolInfoDouble(name,SYMBOL_VOLUME_STEP);
      s.vol_max=SymbolInfoDouble(name,SYMBOL_VOLUME_MAX);
      s.tick_size=SymbolInfoDouble(name,SYMBOL_TRADE_TICK_SIZE);
      s.digits=(int)SymbolInfoInteger(name,SYMBOL_DIGITS);
      s.point=SymbolInfoDouble(name,SYMBOL_POINT);
      s.stops_level=(int)SymbolInfoInteger(name,SYMBOL_TRADE_STOPS_LEVEL);
      s.trade_ok=(SymbolInfoInteger(name,SYMBOL_TRADE_MODE)==SYMBOL_TRADE_MODE_FULL);
      s.read_ok=(GetLastError()==0 && s.vol_min>0.0 && s.vol_step>0.0 && s.vol_max>0.0 && s.tick_size>0.0 && s.digits>=0 && s.point>0.0 && s.stops_level>=0);
     }
   virtual void ReadQuote(const string name,SEnQuote &q)
     {
      MqlTick t;
      ResetLastError();
      q.read_ok=SymbolInfoTick(name,t);
      q.bid=(q.read_ok ? t.bid : 0.0);
      q.ask=(q.read_ok ? t.ask : 0.0);
      q.time=(q.read_ok ? (long)t.time : 0);
     }
   virtual void Send(const SEnRequest &req,SEnSendResult &res)
     {
      PrintFormat("%s | type %d %s volume %.2f price %.*f sl %.*f tp %.*f magic %I64d",EO_FAKE_LABEL,req.type,req.symbol,req.volume,_Digits,req.price,_Digits,req.sl,_Digits,req.tp,req.magic);
      CEnFakeTransport::Send(req,res);
     }
  };

CEoFeed g_feed;
CEoRealMarket g_market;
CEoTerminalFake g_tr;
CEnFakeFileStore g_store;
COrchestrator g_orch;
SEoConfig g_cfg;
string g_last="";

void Status(const string text)
  {
   if(text==g_last) return;
   g_last=text;
   Print("T016 ",text);
   Comment("T016 ENTRY ORCHESTRATOR - FAKE EXECUTION ONLY, nothing is sent to the terminal\n",text);
  }

bool Configure(void)
  {
   SEoFeedCfg fc;
   fc.source=(int)InpContextSource;
   fc.level_proposal=(InpM15Level==EOI_SWING_LATEST_FRACTAL_PROPOSAL);
   fc.timing_after_bos=(InpFvgTiming==EOI_A_AT_OR_AFTER_BREAK_PROPOSAL);
   fc.h4_rebuild=InpH4RebuildBars;
   fc.h4_lookback=InpH4LookbackBars;
   fc.h4_left=InpH4LeftBars;
   fc.h4_right=InpH4RightBars;
   fc.warm=InpOrdinaryWarmBars;
   fc.m15_replay=InpM15ReplayBars;
   fc.m15_lookback=InpM15LookbackBars;
   fc.m15_left=InpM15LeftBars;
   fc.m15_right=InpM15RightBars;
   if(!EO_FeedCfgValid(fc)) return(false);
   g_feed.Init(fc);
   EO_ConfigInit(g_cfg);
   SPB_SelectionInit(g_cfg.sel);
   g_cfg.sel.context_source=EO_SourceId(fc.source);
   g_cfg.sel.swing_selector=(fc.level_proposal ? SPB_SWING_LATEST_FRACTAL_PROPOSAL : SPB_SWING_UNSET);
   g_cfg.sel.timing_policy=(fc.timing_after_bos ? M4_A_AT_OR_AFTER_BREAK : M4_POLICY_UNSET);
   g_cfg.sel.candidate_selector=(int)InpCandidate;
   g_cfg.sel.entry_edge=(int)InpEntryEdge;
   g_cfg.sel.sl_rule=(InpSlRule==EOI_SL_BROKEN_LEVEL_PRICE_PLUS_BUFFER ? SPB_SL_BROKEN_LEVEL_PRICE : SPB_SL_UNSET);
   g_cfg.sel.sl_buffer_set=(InpSlBuffer>=0.0);
   g_cfg.sel.sl_buffer=(InpSlBuffer>=0.0 ? InpSlBuffer : 0.0);
   g_cfg.sel.target_rule=(InpTargetRule==EOI_TGT_NONE_2R_MINIMUM ? SPB_TGT_NONE_2R_MINIMUM : SPB_TGT_UNSET);
   g_cfg.risk_budget=InpRiskBudget;
   g_cfg.lot_cap=InpLotCap;
   g_cfg.model_tolerance=InpModelTolerance;
   g_cfg.max_quote_age=InpMaxQuoteAgeSeconds;
   g_cfg.open_positions=InpOpenPositions;
   g_cfg.trades_today=InpTradesToday;
   g_cfg.existing_risk=InpExistingRisk;
   g_cfg.max_positions=InpMaxPositions;
   g_cfg.max_trades=InpMaxTrades;
   g_cfg.risk_cap=InpCombinedRiskCap;
   g_cfg.gate.max_age=InpGateMaxAgeSeconds;
   g_cfg.exec.enabled=true;                       // enables the FAKE executor only; the transport below is fake and fixed
   g_cfg.exec.ea_magic=InpEaMagic;
   g_cfg.exec.symbol=_Symbol;
   g_cfg.exec.filling=(InpFilling==EOI_FILL_RETURN ? EN_FILL_RETURN : EN_FILL_UNSET);
   g_cfg.exec.expiry_mode=(int)InpExpiryMode;
   g_cfg.exec.expiry_seconds=InpExpirySeconds;
   g_cfg.exec.permit_max_age=InpPermitMaxAgeSeconds;
   g_cfg.exec.quote_max_age=InpMaxQuoteAgeSeconds;
   g_market.mc.session_on=InpSessionClock;
   g_market.mc.session_start_minute=InpSessionStartMinute;
   g_market.mc.session_end_minute=InpSessionEndMinute;
   g_market.mc.session_weekday_mask=InpSessionWeekdayMask;
   g_market.mc.friday_close_enabled=InpFridayCloseEnabled;
   g_market.mc.friday_close_minute=InpFridayCloseMinute;
   g_market.mc.news_on=InpNewsCalendar;
   g_market.mc.max_spread_points=InpMaxSpreadPoints;
   g_market.mc.daily_on=InpDailyHistoryBridge;
   g_market.mc.daily_magic=InpDailyEaMagic;
   g_market.mc.daily_offset_seconds=InpDailyServerOffsetSeconds;
   g_market.mc.daily_history_complete=InpDailyHistoryComplete;
   g_market.mc.daily_formula=InpDailyResultFormula;
   g_market.mc.daily_classification=InpDailyClassification;
   g_market.mc.trades_today=InpTradesToday;
   g_market.mc.wins=InpDailyWins;
   g_market.mc.consecutive_losses=InpDailyConsecutiveLosses;
   g_market.mc.max_trades=InpMaxTrades;
   return(true);
  }

void Poll()
  {
   bool feed_ok=false;
   if(!g_feed.Poll(feed_ok)) return;                // nothing new on the closed bars
   if(InpExposureSource==EOI_EXPOSURE_ACCOUNT_READ)
     {
      SExResult ex;
      CExRealPort port;
      EX_Compute(InpEaMagic,_Symbol,(int)InpPendingPolicy,GetPointer(port),ex);      // InpPendingPolicy: 1 = EX_PEND_COUNT, 2 = EX_PEND_IGNORE, 0 = UNSET
      g_cfg.open_positions=EX_GatePositions(ex);
      g_cfg.existing_risk=EX_GateRisk(ex);
      PrintFormat("T018 EXPOSURE source=ACCOUNT_READ (read-only) ok=%d reason=%s owned+reserved=%I64d pending=%I64d foreign_positions=%I64d foreign_pending=%I64d risk_known=%d risk=%.2f %s",
                  (int)ex.ok,ex.reason,ex.open_positions,ex.pending,ex.foreign_positions,ex.foreign_pending,(int)ex.risk_known,ex.existing_risk,ex.risk_reason);
     }
   SEoOutcome out;
   g_orch.Step(g_cfg,GetPointer(g_market),feed_ok,g_feed.st,g_feed.f,g_feed.broken,g_feed.cut,GetPointer(g_tr),GetPointer(g_store),out);
   string text=out.status+" | "+out.reason+" | cut "+TimeToString(g_feed.cut,TIME_DATE|TIME_MINUTES)+" | baseline "+TimeToString((datetime)g_orch.baseline,TIME_DATE|TIME_MINUTES)+
               " | virtual requests "+IntegerToString(g_tr.sends);
   if(out.request) text+=" | "+out.label+" | "+out.spb.signal_id;
   Status(text);
  }

int OnInit()
  {
   if(MQLInfoInteger(MQL_TESTER)) {Print("T016 REFUSED: the Strategy Tester is not a supported environment (terminal reads)."); return(INIT_FAILED);}
   if(!Configure()) {Print("T016 INIT FAILED: invalid or UNSET source / feed inputs (see docs/T016-entry-orchestrator.md)."); return(INIT_PARAMETERS_INCORRECT);}
   Print("T016 FAKE EXECUTION ONLY: this EA has no order-sending call, the real transport is not included. Symbol ",_Symbol);
   if(!EventSetTimer(InpPollSeconds)) return(INIT_FAILED);
   Poll();
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
   PrintFormat("T016 stopped (reason %d). %d virtual request(s), nothing was sent to the terminal.",reason,g_tr.sends);
  }
void OnTimer() {Poll();}
