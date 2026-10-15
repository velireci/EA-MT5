// T016 ENTRY ORCHESTRATOR EA: H4/M15 observer flow (T004) -> SetupPlanBridge (T014) -> EntryGate (T015) -> EntryExecutor (T013) -> fill -> T011 registration -> T011 management (the existing driver).
//   DEFAULT = FAKE ENTRY EXECUTION: a virtual request is logged and counted in memory; nothing is sent to the terminal; the management transport is READ-ONLY (every closing request is refused).
//   The real transports are compiled in but are SELECTED only by explicit inputs: InpEntryTransport = BROKER_DEMO (pending orders; phrase EN_AUTH_PHRASE, registration on, magic, filling RETURN) and
//   InpManagementTransport = BROKER_DEMO (closing requests at 2R; phrase EX_AUTH_PHRASE + InpManagementConfirmAutoSend). Both executors additionally refuse a non-demo account. The build does NOT enable real sending.
//   Provenance: a FAKE entry transport's fills are SYNTHETIC and are never matched to a real position; only the real entry transport declares BROKER.
//   Market/account reads: closed bars, symbol / quote properties, OrderCalcProfit, calendar, deal history and T012 balance LOAD only.
//   Every source / selection / policy input is UNSET by default and UNSET blocks. Exposure: EXPLICIT inputs by default (-1 = unknown) or the opt-in READ-ONLY account reader (T018). Chart symbol only (incl. XAUUSD.fx).
//   FAKE entry records and the T019 lifecycle index / halt flag persist in VELO_T016_FAKE_ files (real records: VELO_T013_ENTRY_ files). The baseline is REBUILT at every start (a restart never revives a signal).
//   A filled order is registered with the existing T011 executor and then managed by the T011 driver inside this EA (OnTick = the 2R level, OnTimer = reconcile only) only when InpManagementRegistration is true;
//   the registered fill stays in the lifecycle index until the T011 record is DONE or the position is proven closed (that index is the restart memory). Not proof of broker execution. UNVERIFIED: not compiled or run.
#property strict
#property version "1.08"
#include "include/EntryOrchestratorFeed.mqh"
#include "include/EntryTransportFake.mqh"
#include "include/ExposureReaderReal.mqh"
#include "include/EntryStateFile.mqh"
#include "include/EntryLifecycle.mqh"
#include "include/EntryManagementHandoff.mqh"
#include "include/EntryTransportReal.mqh"   // compiled in, but selected ONLY by InpEntryTransport = BROKER_DEMO with the explicit phrase (default FAKE)
#include "include/ExitTransportReal.mqh"    // compiled in, but selected ONLY by InpManagementTransport = BROKER_DEMO with the explicit phrase and confirmation (default READ_ONLY)

enum ENUM_EO_SOURCE {EOI_SRC_UNSELECTED=0,EOI_SRC_T003_RECONF_PROPOSAL=1,EOI_SRC_T002_TOUCH_AFTER_LOSS_PROPOSAL=2,EOI_SRC_T002_TOUCH_FIRST_ONLY_PROPOSAL=3};
enum ENUM_EO_SWING {EOI_SWING_UNSELECTED=0,EOI_SWING_LATEST_FRACTAL_PROPOSAL=1};
enum ENUM_EO_TIMING {EOI_TIMING_UNSELECTED=0,EOI_A_AT_OR_AFTER_BREAK_PROPOSAL=1};
enum ENUM_EO_CANDIDATE {EOI_CAND_UNSELECTED=0,EOI_CAND_SOLE_ELIGIBLE=2};
enum ENUM_EO_EDGE {EOI_EDGE_UNSELECTED=0,EOI_EDGE_NEAR_SIDE=1,EOI_EDGE_FAR_SIDE=2};
enum ENUM_EO_SL {EOI_SL_UNSELECTED=0,EOI_SL_BROKEN_LEVEL_PRICE_PLUS_BUFFER=1};
enum ENUM_EO_TARGET {EOI_TGT_UNSELECTED=0,EOI_TGT_NONE_2R_MINIMUM=1};
enum ENUM_EO_EXPOSURE {EOI_EXPOSURE_EXPLICIT=0,EOI_EXPOSURE_ACCOUNT_READ=1};
enum ENUM_EO_PENDING {EOI_PENDING_UNSET=0,EOI_PENDING_COUNT_AS_POSITIONS=1,EOI_PENDING_IGNORE=2};
enum ENUM_EO_PENDING_RISK {EOI_PENDRISK_UNSET=0,EOI_PENDRISK_INCLUDE=1,EOI_PENDRISK_EXCLUDE=2};
enum ENUM_EO_FILLING {EOI_FILL_UNSET=0,EOI_FILL_RETURN=1};
enum ENUM_EO_EXPIRY {EOI_EXP_UNSET=0,EOI_EXP_GTC=1,EOI_EXP_SECONDS=2};
enum ENUM_EO_MGMT_RPOL {EOI_MGMT_RPOL_UNSET=0,EOI_MGMT_RPOL_R_GEOM=1};
enum ENUM_EO_RISK_SOURCE {EOI_RISK_AMOUNT=0,EOI_RISK_DEMO_1PCT_CURRENT_BALANCE=1};
enum ENUM_EO_ENTRY_TRANSPORT {EOI_ETR_FAKE=0,EOI_ETR_BROKER_DEMO=1};
enum ENUM_EO_MGMT_TRANSPORT {EOI_MTR_READ_ONLY=0,EOI_MTR_BROKER_DEMO=1};

input ENUM_EO_SOURCE InpContextSource=EOI_SRC_UNSELECTED;
input ENUM_EO_SWING InpM15Level=EOI_SWING_UNSELECTED;
input ENUM_EO_TIMING InpFvgTiming=EOI_TIMING_UNSELECTED;
input ENUM_EO_CANDIDATE InpCandidate=EOI_CAND_UNSELECTED;
input ENUM_EO_EDGE InpEntryEdge=EOI_EDGE_UNSELECTED;
input ENUM_EO_SL InpSlRule=EOI_SL_UNSELECTED;
input double InpSlBuffer=-1;                 // price units; -1 = UNSET (blocks); 0 is a deliberate "no buffer"
input ENUM_EO_TARGET InpTargetRule=EOI_TGT_UNSELECTED;
input double InpRiskBudget=-1;               // account currency, NOT percent; -1 = UNSET
input ENUM_EO_RISK_SOURCE InpRiskSource=EOI_RISK_AMOUNT; // AMOUNT = InpRiskBudget above (default). DEMO_1PCT_CURRENT_BALANCE = DEMO-ONLY policy: 1% of the CURRENT ACCOUNT_BALANCE read at every step (InpRiskBudget is then ignored, there is NO fallback: an unreadable / invalid / stale / non-demo balance blocks). Not a client confirmation for live (D2)
input double InpLotCap=-1;                   // -1 = UNSET
input double InpModelTolerance=-1;           // 0..1; -1 = UNSET
input long InpMaxQuoteAgeSeconds=-1;         // -1 = UNSET
input long InpGateMaxAgeSeconds=-1;          // age of the gate evidence; -1 = UNSET
input long InpPermitMaxAgeSeconds=-1;        // executor permit age; -1 = UNSET
input ENUM_EO_EXPOSURE InpExposureSource=EOI_EXPOSURE_EXPLICIT; // ACCOUNT_READ = READ-ONLY: open positions (+ pending per policy) and the loss-at-SL risk of THIS EA magic on a HEDGING account; the two explicit exposure inputs below are then IGNORED (no fallback)
input ENUM_EO_PENDING InpPendingPolicy=EOI_PENDING_UNSET; // ACCOUNT_READ only: whether an owned pending order RESERVES a position (owner policy; UNSET blocks)
input ENUM_EO_PENDING_RISK InpPendingRiskPolicy=EOI_PENDRISK_UNSET; // ACCOUNT_READ only: whether the RISK of an owned pending order is part of the existing risk (a separate owner policy; UNSET = risk unknown while such an order exists)
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
input bool InpCancelOnSessionEnd=false;       // lifecycle: cancel an open (proven) pending order when the session filter reports CLOSED. false = never (owner decision)
input bool InpCancelOnNewsBlock=false;        // lifecycle: ... when the news filter reports BLOCKED
input bool InpCancelOnDailyLimit=false;       // lifecycle: ... when the T012 daily result says cancel_pending_due
input bool InpAcknowledgeLifecycleHalt=false; // owner acknowledgement at the START: clears a persisted lifecycle halt and drops its unresolved ids (their records stay, the signals stay consumed). Never automatic
input bool InpManagementRegistration=false;   // true = register a FILLED entry with the T011 executor automatically (the existing ETD_Register: ownership, initial SL, plan, never overwritten); false = report only
input string InpManagementAuthorisation="";   // the T011 standing authorisation phrase (EX_AUTH_PHRASE); required when registration is on; the account must be a demo account (T011 gate)
input ENUM_EO_MGMT_RPOL InpManagementRPolicy=EOI_MGMT_RPOL_UNSET; // required R_GEOM when registration is on; UNSET blocks
input ENUM_EO_ENTRY_TRANSPORT InpEntryTransport=EOI_ETR_FAKE; // FAKE = in-memory virtual requests (default). BROKER_DEMO = REAL pending orders on a DEMO account: needs the phrase below, registration + management on, magic > 0 and filling RETURN. Real sending is NOT enabled by the build; it is the owner's explicit decision
input string InpEntryAuthorisation="";         // EN_AUTH_PHRASE (I_AUTHORISE_REAL_ENTRY_ORDERS_ON_THIS_DEMO_ACCOUNT); required for BROKER_DEMO; the executor also refuses a non-demo account
input ENUM_EO_MGMT_TRANSPORT InpManagementTransport=EOI_MTR_READ_ONLY; // READ_ONLY = reads the terminal, every closing request is refused (default). BROKER_DEMO = REAL partial-close requests at 2R on a DEMO account
input bool InpManagementConfirmAutoSend=false; // must be true for BROKER_DEMO management: the EA may send a closing request on its own at the 2R level
input ENUM_EX_FILLING InpMgmtFilling=EX_FILL_UNSET;            // filling of the closing request; UNSET blocks (required when registration is on)
input long InpMgmtDeviation=-1;                // deviation of the closing request in points; -1 blocks (required when registration is on)
input ENUM_EX_FILTER_POLICY InpMgmtFilterPolicy=EX_POL_UNSET;  // behaviour of the closing request towards spread / news / session filters; UNSET blocks (required when registration is on)
input ENUM_EX_FILTER_STATE InpMgmtFilterState=EX_FS_UNKNOWN;   // state of those filters supplied by the owner (used only with NEEDS_CLEAR)
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
// DEMO risk policy: the CURRENT balance of a DEMO account, read now (the feed header stays untouched); anything else is "unreadable" and the core blocks, with no fallback
class CEoDemoMarket : public CEoRealMarket
  {
public:
   virtual void Balance(SEoBalance &b)
     {
      ResetLastError();
      b.amount=AccountInfoDouble(ACCOUNT_BALANCE);
      b.demo=(AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO);
      b.time=(long)TimeTradeServer();
      b.read_ok=(GetLastError()==0 && TerminalInfoInteger(TERMINAL_CONNECTED)!=0 && AccountInfoInteger(ACCOUNT_LOGIN)>0 && MathIsValidNumber(b.amount));
     }
  };

CEoDemoMarket g_market;
CEoTerminalFake g_tr;
CEnFakeFileStore g_store;
CEnRealStore g_rstore;             // real entry records (BROKER_DEMO only)
CEnRealStore g_rlockstore;
CEnRealTransport g_etr;            // real entry transport (BROKER_DEMO only)
CRealTransport g_mreal;            // real closing transport (BROKER_DEMO management only)
CEnTransport *g_trp=NULL;          // the entry transport in use: g_tr (FAKE) unless BROKER_DEMO was selected explicitly
CEnStore *g_storep=NULL;
CEnStore *g_lockp=NULL;
bool g_real_entry=false;
CMhManager g_mgr;                  // T011 management inside the orchestrator (the existing driver)
bool g_mgr_on=false;
COrchestrator g_orch;
SEoConfig g_cfg;
CMhReadTransport g_xtr;               // READ-ONLY exit transport of the registrar (IsReal() = true keeps the T011 authorisation / demo gates; Send does nothing)
CMhRegistrar g_registrar;
CLcFillSink *g_sink=NULL;          // NULL = registration off (report only)
CLcGuard g_guard;                  // the gate's pre-send hook + the lifecycle state (g_guard.st)
CEnFakeFileStore g_lockstore;      // dedicated store for the index lock: the file store above holds ONE lock at a time (the executor's per-signal lock)
ulong g_lc_filters_ms=0;
string g_last="";

void Status(const string text)
  {
   if(text==g_last) return;
   g_last=text;
   Print("T016 ",text);
   Comment(g_real_entry ? "T016 ENTRY ORCHESTRATOR - REAL DEMO ORDERS ENABLED BY THE OWNER\n" : "T016 ENTRY ORCHESTRATOR - FAKE EXECUTION ONLY, nothing is sent to the terminal\n",text);
  }

bool Configure(void)
  {
   g_sink=NULL;
   g_mgr_on=false;
   g_real_entry=false;
   g_trp=GetPointer(g_tr);
   g_storep=GetPointer(g_store);
   g_lockp=GetPointer(g_lockstore);
   if((int)InpRiskSource!=(int)EOI_RISK_AMOUNT && (int)InpRiskSource!=(int)EOI_RISK_DEMO_1PCT_CURRENT_BALANCE) return(false);
   if((int)InpEntryTransport!=(int)EOI_ETR_FAKE && (int)InpEntryTransport!=(int)EOI_ETR_BROKER_DEMO) return(false);
   if((int)InpManagementTransport!=(int)EOI_MTR_READ_ONLY && (int)InpManagementTransport!=(int)EOI_MTR_BROKER_DEMO) return(false);
   if(InpEntryTransport==EOI_ETR_BROKER_DEMO)
     {
      // REAL pending orders (demo account only: the executor refuses anything else): every guard is explicit and UNSET blocks. The build does not enable sending; the owner does, by these inputs.
      if(InpEntryAuthorisation!=EN_AUTH_PHRASE || !InpManagementRegistration || InpEaMagic<=0 || InpFilling!=EOI_FILL_RETURN) return(false);
      g_real_entry=true;
      g_trp=GetPointer(g_etr);
      g_storep=GetPointer(g_rstore);
      g_lockp=GetPointer(g_rlockstore);
     }
   if(InpManagementTransport==EOI_MTR_BROKER_DEMO && (!InpManagementConfirmAutoSend || !InpManagementRegistration)) return(false);
   if(InpManagementRegistration)
     {
      // registration (and the management that follows it) on: every input it needs is explicit, UNSET blocks, nothing is guessed
      if(InpManagementAuthorisation!=EX_AUTH_PHRASE || InpManagementRPolicy!=EOI_MGMT_RPOL_R_GEOM || InpEaMagic<=0) return(false);
      if(InpMgmtFilling==EX_FILL_UNSET || (int)InpMgmtFilling<(int)EX_FILL_FOK || (int)InpMgmtFilling>(int)EX_FILL_RETURN || InpMgmtDeviation<0) return(false);
      if(InpMgmtFilterPolicy==EX_POL_UNSET || (int)InpMgmtFilterPolicy<(int)EX_POL_IGNORE || (int)InpMgmtFilterPolicy>(int)EX_POL_NEEDS_CLEAR) return(false);
      if((int)InpMgmtFilterState<(int)EX_FS_UNKNOWN || (int)InpMgmtFilterState>(int)EX_FS_BLOCKED) return(false);
      g_registrar.entry_store=g_storep;
      g_registrar.exit_tr=GetPointer(g_xtr);
      g_registrar.magic=InpEaMagic;
      g_registrar.phrase=InpManagementAuthorisation;
      g_registrar.rpol=EX_RPOL_R_GEOM;
      g_registrar.provenance=(g_real_entry ? MH_PROV_BROKER : MH_PROV_SYNTHETIC);   // a FAKE entry transport's fills are never matched to real positions; only the real entry transport declares BROKER
      g_registrar.selftest=false;
      if(InpManagementTransport==EOI_MTR_BROKER_DEMO) g_mgr.tr=GetPointer(g_mreal);
      else g_mgr.tr=GetPointer(g_xtr);
      g_mgr.magic=InpEaMagic;
      g_mgr.phrase=InpManagementAuthorisation;
      g_mgr.filling=(int)InpMgmtFilling;
      g_mgr.deviation=InpMgmtDeviation;
      g_mgr.filter_policy=(int)InpMgmtFilterPolicy;
      g_mgr.filter_state=(int)InpMgmtFilterState;
      g_registrar.manager=GetPointer(g_mgr);
      g_mgr_on=true;
      g_sink=GetPointer(g_registrar);
     }
   // an unknown enum value (a preset or a hand-typed number) is refused here; it must never fall through to the manual exposure inputs
   if((int)InpExposureSource!=(int)EOI_EXPOSURE_EXPLICIT && (int)InpExposureSource!=(int)EOI_EXPOSURE_ACCOUNT_READ) return(false);
   if((int)InpPendingPolicy<(int)EOI_PENDING_UNSET || (int)InpPendingPolicy>(int)EOI_PENDING_IGNORE) return(false);
   if((int)InpPendingRiskPolicy<(int)EOI_PENDRISK_UNSET || (int)InpPendingRiskPolicy>(int)EOI_PENDRISK_EXCLUDE) return(false);
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
   g_cfg.risk_source=(int)InpRiskSource;
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
   g_cfg.exec.enabled=true;                       // enables the executor; the transport is FAKE unless BROKER_DEMO was selected with the phrase
   g_cfg.exec.real_authorised=g_real_entry;
   g_cfg.exec.authorisation=(g_real_entry ? InpEntryAuthorisation : "");
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

int EnabledCancelEvents(void)
  {
   return((InpCancelOnSessionEnd ? TP_EV_SESSION_END : 0)|(InpCancelOnNewsBlock ? TP_EV_NEWS_BLOCK : 0)|(InpCancelOnDailyLimit ? TP_EV_DAILY_LIMIT : 0));
  }

// the two layers share ONE halt: whichever halts first stops new entries; the lifecycle halt is persisted
void SyncHalts(void)
  {
   string notes="";
   // only a halt caused by an executor outcome is persisted (a full handled list, for instance, is cured by the restart itself)
   if(g_guard.st.login>0 && StringFind(g_orch.halted,"HALTED after")==0 && g_guard.st.halted=="") LC_Halt(g_storep,g_guard.st,g_orch.halted,notes);
   if(g_guard.st.halted!="" && g_orch.halted=="") g_orch.halted="LIFECYCLE: "+g_guard.st.halted;
   if(notes!="") Print("T019 ",notes);
  }

// every timer tick: reconcile the indexed signals; cancel an open pending order only for an event that is due AND enabled by the owner (the filters are read at most every 10 s, only when an event is enabled and a signal is open)
void Lifecycle()
  {
   if(g_guard.st.login<=0) return;
   int enabled=EnabledCancelEvents();
   int due=0;
   if(enabled!=0 && g_guard.st.n>0 && (g_lc_filters_ms==0 || GetTickCount64()-g_lc_filters_ms>=10000))
     {
      g_lc_filters_ms=GetTickCount64();
      int session=TP_SESSION_UNKNOWN,news=TP_NEWS_UNKNOWN,spread=TP_SPREAD_UNKNOWN;
      g_market.Filters(session,news,spread);
      STpPlan none;
      TP_PlanReset(none,"-","-",1);
      SDbResult daily;
      bool present=g_market.Daily(none,daily);
      due=LC_DueEvents(session,news,present,(present && daily.cancel_pending_due));
     }
   string notes="";
   if(g_mgr_on) g_mgr.OnTimer();                       // reconcile only (the driver's timer): a DONE slot is released by the sweep below
   LC_Tick(g_cfg.exec,g_trp,g_storep,g_guard.st,due,enabled,notes,g_sink);
   if(notes!="") Print("T019 LIFECYCLE | ",notes);
   SyncHalts();
  }

void Poll()
  {
   Lifecycle();
   bool feed_ok=false;
   if(!g_feed.Poll(feed_ok)) return;                // nothing new on the closed bars
   if(InpExposureSource==EOI_EXPOSURE_ACCOUNT_READ)
     {
      SExpResult ex;
      CExRealPort port;
      EX_Compute(InpEaMagic,_Symbol,(int)InpPendingPolicy,(int)InpPendingRiskPolicy,GetPointer(port),ex);      // 1 = COUNT / INCLUDE, 2 = IGNORE / EXCLUDE, 0 = UNSET
      g_cfg.open_positions=EX_GatePositions(ex);
      g_cfg.existing_risk=EX_GateRisk(ex);
      PrintFormat("T018 EXPOSURE source=ACCOUNT_READ (read-only) ok=%d reason=%s owned+reserved=%I64d pending=%I64d foreign_positions=%I64d foreign_pending=%I64d risk_known=%d risk=%.2f %s",
                  (int)ex.ok,ex.reason,ex.open_positions,ex.pending,ex.foreign_positions,ex.foreign_pending,(int)ex.risk_known,ex.existing_risk,ex.risk_reason);
     }
   SEoOutcome out;
   g_orch.Step(g_cfg,GetPointer(g_market),feed_ok,g_feed.st,g_feed.f,g_feed.broken,g_feed.cut,g_trp,g_storep,out,GetPointer(g_guard));      // the guard indexes the signal BEFORE the executor can send
   if(g_guard.notes!="") {Print("T019 ",g_guard.notes); g_guard.notes="";}
   SyncHalts();
   string text=out.status+" | "+out.reason+" | cut "+TimeToString(g_feed.cut,TIME_DATE|TIME_MINUTES)+" | baseline "+TimeToString((datetime)g_orch.baseline,TIME_DATE|TIME_MINUTES)+
               (g_real_entry ? " | REAL DEMO" : " | virtual requests "+IntegerToString(g_tr.sends))+" | lifecycle open "+IntegerToString(g_guard.st.n)+(g_guard.st.halted!="" ? " HALTED" : "");
   if(out.request) text+=" | "+out.label+" | "+out.spb.signal_id;
   Status(text);
  }

int OnInit()
  {
   if(MQLInfoInteger(MQL_TESTER)) {Print("T016 REFUSED: the Strategy Tester is not a supported environment (terminal reads)."); return(INIT_FAILED);}
   if(!Configure()) {Print("T016 INIT FAILED: invalid or UNSET source / feed inputs (see docs/T016-entry-orchestrator.md)."); return(INIT_PARAMETERS_INCORRECT);}
   if(g_real_entry) Print("T016 REAL DEMO ORDER MODE selected explicitly by the owner (phrase given). Symbol ",_Symbol,". Management transport: ",(InpManagementTransport==EOI_MTR_BROKER_DEMO ? "REAL closing requests" : "read-only (closing requests refused)"));
   else Print("T016 FAKE ENTRY EXECUTION: virtual requests only; the real entry transport is not selected. Symbol ",_Symbol,". Management transport: ",(InpManagementTransport==EOI_MTR_BROKER_DEMO ? "REAL closing requests" : "read-only (closing requests refused)"));
   string startup_notes="";
   g_guard.Bind(g_storep);
   // exclusive ownership of the index comes FIRST (the existing lock mechanism); an instance that does not get it neither reads nor writes the index and never sends or cancels (the layer stays halted)
   if(!LC_Startup(g_cfg.exec,g_trp,g_storep,g_lockp,InpAcknowledgeLifecycleHalt,g_guard.st,startup_notes,g_sink))
      Print("T019 LIFECYCLE startup: the account is not readable; the layer stays halted.");
   if(startup_notes!="") Print("T019 LIFECYCLE startup | ",startup_notes);
   if(g_guard.st.halted!="") g_orch.halted="LIFECYCLE: "+g_guard.st.halted;
   if(!EventSetTimer(InpPollSeconds))
     {
      LC_Release(g_lockp,g_guard.st);              // a failed start releases what this instance owns, and nothing else
      return(INIT_FAILED);
     }
   Poll();
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason)
  {
   EventKillTimer();
   LC_Release(g_lockp,g_guard.st);                  // only the owner releases, and only its own key
   Comment("");
   if(g_real_entry) PrintFormat("T016 stopped (reason %d).",reason);
   else PrintFormat("T016 stopped (reason %d). %d virtual request(s), nothing was sent to the terminal by the entry layer.",reason,g_tr.sends);
  }
void OnTimer() {Poll();}
// the quote loop of the T011 management: below the level no I/O (the driver's pre-filter); at the level the existing executor is the only request source
void OnTick()
  {
   if(!g_mgr_on || g_mgr.n==0) return;
   MqlTick t;
   if(!SymbolInfoTick(_Symbol,t) || !(t.bid>0.0) || !(t.ask>0.0)) return;
   int sent=g_mgr.OnQuote(t.bid,t.ask);
   if(sent>0) PrintFormat("T011 MANAGEMENT: %d closing request(s) sent at the 2R level; the timer reconciles them",sent);
  }
