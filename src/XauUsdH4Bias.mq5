//+------------------------------------------------------------------+
//|                                              XauUsdH4Bias.mq5    |
//|                                                                  |
//|  Submission XAU-20261006-E27N93 - task T003 (H4 bias, VISUAL).   |
//|                                                                  |
//|  VISUAL VALIDATION of the T003 bias logic (H4Bias.mqh, revision |
//|  10 PROTOTYPE) against the client's examples. Draws, from CLOSED |
//|  H4 bars of the chart symbol, with STRUCTURE and SETUP kept      |
//|  apart:                                                          |
//|   1 T002 BASELINE (lookback N = InpLookbackBars, the T002 EA's   |
//|     window: the last N closed bars, 2/2 swings) HH+HL / LH+LL (or|
//|     MIXED / UNKNOWN); the direction of the whole replay window is|
//|     named 'replay-window structure' and is a different thing;    |
//|     the two source highs and lows are drawn with InpShowDetails; |
//|   2 the T003 prototype bias, the CURRENT protecting level (solid)|
//|     and the swings it was selected from;                         |
//|   3 MODEL DISAGREEMENT when the T002 BASELINE is BULLISH and T003|
//|     BEAR, or the baseline BEARISH and T003 BULL (MIXED / UNKNOWN |
//|     never count), since-when and for how many closed bars;       |
//|   4 the SETUP: setup_id, phase ACTIVE / HOLD / SWEEP_WAIT /      |
//|     RECONFIRMED with its reason, the SNAPSHOT level (dashed,     |
//|     reference only), the wick / sweep record, the eligible new   |
//|     FVGs, the reconfirmation FVG and the ready flag;             |
//|   5 HISTORICAL LIQUIDITY (PROPOSAL, not ERL / target / protecting|
//|     level): confirmed 2/2 swings no later wick has exceeded,     |
//|     dotted, limited by InpLiqMax, switchable;                    |
//|   6 the A/B reliability flag CONVERGED / SEEDED / LIMITED_BY_    |
//|     HISTORY with its reasons and the depths.                     |
//|                                                                  |
//|  EVERY RULE IS A PROPOSAL (tasks/T003-h4-bias-change.md): a      |
//|  developer proposal awaiting the client's visual validation, not |
//|  a client answer and not a trading rule. The T003 bias is never  |
//|  presented as the client's confirmed direction. The panel says so.|
//|                                                                  |
//|  LIVE (InpAsOfTime = 0): the logic is replayed when an H4 bar    |
//|  CLOSES (the forming bar is never read). At start or restart the |
//|  events already in the history are NOT reported as new (baseline |
//|  cursor, H3BaselineCursor / H3ConsumeNew); they are drawn as     |
//|  history. Events after the baseline are drawn and logged as NEW. |
//|                                                                  |
//|  HISTORICAL (InpAsOfTime > 0): AsOfTime is BROKER/SERVER time as |
//|  shown by MT5, NOT UTC and NOT TradingView chart time (they can  |
//|  differ; never assume equal). Only H4 bars CLOSED by then are    |
//|  used, no live price is read, the picture is static.             |
//|                                                                  |
//|  PANEL: COMPACT by default (mode/date, T003 bias, T002 baseline, |
//|  current level + snapshot, phase / READY, the FVG, reliability). |
//|  InpShowDetails = true adds the long view. The panel is wrapped  |
//|  to the chart size and the lowest priority lines are dropped when|
//|  the chart is too small (the font is not shrunk); it is laid out |
//|  again on CHARTEVENT_CHART_CHANGE. Everything is in the Experts. |
//|  Chart labels are short, the full text is the object tooltip.    |
//|                                                                  |
//|  DIAGNOSTICS (InpDiagnostics, default on): when the evaluation is |
//|  LIMITED_BY_HISTORY the Experts log (and the panel) say WHY: the |
//|  first differing field and event between replays A and B, origin,|
//|  level, anchors, window starts, warm-up ends, level undefined.   |
//|  CANDLE EXPORT (InpExportCandles, default OFF): writes the closed |
//|  bars used by the evaluation to MQL5/Files/velo_t003_diag_*.csv  |
//|  (closed bars only; no trading API) so a real case can be        |
//|  replayed offline with tests/t003_replay_csv.py. The file name    |
//|  follows the last bar; the file is OVERWRITTEN whenever the set   |
//|  changes (key: symbol, as-of, last and first bar time, bar count  |
//|  and a content hash), also when history is added with the same   |
//|  last candle.                                                    |
//|                                                                  |
//|  Does NOT: send, modify or close orders; use M5/M15; draw the    |
//|  intrabar overlay (P12) or the target (P13); compute entries,    |
//|  stop loss, take profit or lot size. The two entry-block flags   |
//|  are only displayed; nothing acts on them.                       |
//|                                                                  |
//|  INSTALL (Expert Advisor, NOT a script): copy the whole          |
//|  repository src/ folder to                                       |
//|    <terminal data folder>/MQL5/Experts/velo_src/                 |
//|  so that MQL5/Experts/velo_src/XauUsdH4Bias.mq5 sits next to     |
//|  MQL5/Experts/velo_src/include/. Compile in MetaEditor, attach   |
//|  to an XAUUSD H4 chart. See docs/T003-visual-ea.md.              |
//|                                                                  |
//|  Verification status: NOT COMPILED here (no MetaEditor) and NOT  |
//|  observed on a chart. Static checks only                         |
//|  (tools/t003-visual-static-checks.sh).                           |
//+------------------------------------------------------------------+
#property copyright   "velireci"
#property version     "1.13"
#property description "T003 H4 bias (visual validation): proposed rules - client validation pending."
#property description "Contains no order functions and no trading logic."

#include "include/SymbolSnapshot.mqh"
#include "include/TimeframeWatcher.mqh"
#include "include/H4Structure.mqh"
#include "include/H4Bias.mqh"
#include "include/H4BiasLayers.mqh"
#include "include/H4BiasDrawer.mqh"

enum ENUM_T3_PANEL_CORNER
  {
   T3_PANEL_TOP_LEFT     = 0,  // Top left
   T3_PANEL_TOP_RIGHT    = 1,  // Top right
   T3_PANEL_BOTTOM_LEFT  = 2,  // Bottom left
   T3_PANEL_BOTTOM_RIGHT = 3   // Bottom right
  };

input group "Proposed H4 bias model (client validation pending)"
input int              InpLeftBars      = 2;                   // Swing: closed bars on the left (1..10)
input int              InpRightBars     = 2;                   // Swing: closed bars on the right (1..10)
input int              InpLookbackBars  = 300;                 // L: warm-up and A/B check depth, closed H4 bars (clamped 50..1000)
input int              InpRebuildBars   = 1000;                // R: closed H4 bars replayed (raised to 3*L, capped at 5000)

input group "Diagnostics (why LIMITED_BY_HISTORY)"
input bool             InpDiagnostics   = true;                // Log (Experts) and show (panel) the A/B diagnostics when the evaluation is LIMITED_BY_HISTORY
input bool             InpExportCandles = false;               // Write the closed-bar set of the evaluation to MQL5/Files/velo_t003_diag_<symbol>_<last bar>.csv (closed bars only)

input group "Historical liquidity layer (PROPOSAL - not ERL / target / protecting level)"
input bool             InpShowLiquidity = true;                // Draw the historical liquidity layer: confirmed 2/2 swings that no later wick has exceeded (dotted). A proposal; never used by the bias
input int              InpLiqMax        = 6;                   // Most levels drawn, the NEAREST to the last closed bar's close first (0..50)

input group "Historical review (0 = live mode)"
input datetime         InpAsOfTime      = 0;                   // AsOfTime: BROKER/SERVER time as shown by MT5 - NOT UTC, NOT TradingView chart time (they can differ; never assume equal). 0 = live mode

input group "Display"
input bool             InpShowPanel     = true;                // Draw the status panel
input ENUM_T3_PANEL_CORNER InpPanelCorner = T3_PANEL_TOP_LEFT; // Panel corner
input bool             InpShowDetails   = false;               // Panel: also show the long DETAILS view (sources, ids, setup facts, events, liquidity). Default false = compact view; the details are always in the Experts log
input int              InpPanelFontSize = 9;                   // Panel font size (7..24); never shrunk to fit: lines that do not fit are dropped, lowest priority first
input color            InpPanelBgColor  = C'16,20,28';         // Panel background colour
input int              InpLabelFontSize = 8;                   // Chart label font size (6..20)
input int              InpMaxEvents     = 8;                   // Most recent events drawn on the chart (0..200)
input int              InpMaxFvgs       = 6;                   // Most recent eligible FVGs drawn (0..50)
input bool             InpShowNonMarket = false;               // Also draw CONTINUATION / INTERNAL_BREAK / NONE_WICK / CONFLICT events
input bool             InpShowInvalidFvgs = false;             // Also draw INVALID eligible FVGs (dimmed)
input color            InpColorBear     = clrTomato;           // Bearish bias colour
input color            InpColorBull     = clrDodgerBlue;       // Bullish bias colour
input color            InpColorLevel    = clrOrange;           // Level pivots colour
input int              InpPollSeconds   = 1;                   // Timer poll interval in seconds

#define H4_MIN_READY_BARS 60
#define NEW_IDS_MAX       200
#define CHANGES_MAX       4

string            g_symbol = "";
SSymbolSnapshot   g_snapshot;
CTimeframeWatcher g_h4;
CH3Panel          g_panel;
CH3BiasDrawer     g_drawer;

SH3Params         g_params;
int               g_left     = 2;
int               g_right    = 2;
int               g_depth    = 1000;      // closed bars copied = min(max(R, 3L), hard cap)

MqlRates          g_bars[];
int               g_n        = 0;
SH3Eval           g_ev;
SH3Track          g_tracks[];
SH3Event          g_events[];
SH3View           g_view;
bool              g_timer_active = false;
bool              g_dirty        = false;

//--- live consumer: cursor = open time of the last bar already consumed (0 = no baseline yet)
datetime          g_cursor   = 0;
string            g_new_ids[];
int               g_n_new    = 0;
SH3LSince         g_since;                          // values labelled 'since baseline' (NEW events, observed changes); zeroed on clear/recovery
string            g_cons_text = "";
int               g_cons_status = H3_C_BASELINE;   // consumer status of the last evaluation (TrackChanges input)

//--- diagnostics and candle export
SH3Diag           g_diag;
string            g_diag_lines[];
int               g_ndiag      = 0;
string            g_diag_key   = "";
string            g_export_key = "";
string            g_export_text = "";

//--- changes observed while running (live only), and the previous reliable snapshot
bool              g_prev_valid = false;
string            g_prev_bias  = "";
string            g_prev_t2    = "";
string            g_prev_phase = "";
string            g_changes[];
int               g_nchanges   = 0;
string            g_prev_setup = "";
string            g_last_flag_text = "";
int               g_tc_mode    = H3_TC_BASELINE;   // decision of the last TrackChanges (live); BASELINE in historical mode
string            g_dis_key    = "";               // MODEL DISAGREEMENT state last logged (once per change)

//--- historical review mode
bool              g_hist     = false;
datetime          g_asof     = 0;
datetime          g_asof_eff = 0;
int               g_set_closed = 0;

//--- lifecycle (history state, stall counter, cadence): H4LifeDecide / H4LifeOnCopy in H4Structure.mqh
SH4Life           g_life;
string            g_clear_reason = "";

void Poll(void);
bool RebuildBias(void);
bool HistoryProbe(void);
void ClearBiasState(const string reason);
void ApplyLifeOut(const SH4LifeOut &o);
int  CopyClosedSet(MqlRates &out[], datetime &oldest, bool &newest_ok);
void EvaluateAndDraw(const string was_cleared);
void ConsumeEvents(void);
void TrackChanges(void);
void LogDisagreement(void);
void LogDetails(void);
void RunDiagnostics(void);
void ExportCandles(void);
void LogEvaluation(void);
void PushChange(const string text);
void RenderPanel(void);

//+------------------------------------------------------------------+
void ResetEval(void)
  {
   H3StateInit(g_ev.st);
   g_ev.has_state = false;
   g_ev.reliable  = false;
   g_ev.flag      = H3_FLAG_LIMITED;
   g_ev.reason    = "";
   g_ev.note      = "";
   g_ev.nt        = 0;
   g_ev.ne        = 0;
   g_ev.last_time = 0;
   ArrayResize(g_tracks, 0);
   ArrayResize(g_events, 0);
   H3DiagInit(g_diag);
   ArrayResize(g_diag_lines, 0);
   g_ndiag = 0;
  }

int OnInit(void)
  {
   H4LifeInit(g_life);
   g_timer_active = false;
   g_dirty = false;
   g_n = 0;
   g_cursor = 0;
   g_n_new = 0;
   H3LSinceInit(g_since);
   g_cons_text = "";
   g_cons_status = H3_C_BASELINE;
   g_diag_key = "";
   g_export_key = "";
   g_export_text = "";
   g_prev_valid = false;
   g_nchanges = 0;
   g_prev_setup = "";
   g_tc_mode = H3_TC_BASELINE;
   g_dis_key = "";
   g_last_flag_text = "";
   g_clear_reason = "";
   g_set_closed = 0;
   g_asof_eff = 0;
   ResetEval();
   H3VViewInit(g_view);
   ArrayResize(g_new_ids, 0);
   ArrayResize(g_changes, 0);

   if(InpAsOfTime < 0)
     {
      Print("T003 INIT FAILED: AsOfTime must be 0 (live) or a positive broker/server time.");
      return(INIT_FAILED);
     }
   g_asof = InpAsOfTime;
   g_hist = (g_asof > 0);

   g_symbol = _Symbol;
   if(!SymbolSnapshotLoad(g_symbol, g_snapshot))
     {
      PrintFormat("T003 INIT FAILED: symbol '%s' unusable - %s", g_symbol, g_snapshot.problem);
      return(INIT_FAILED);
     }
   if(InpPollSeconds < 1)
     {
      Print("T003 INIT FAILED: poll interval must be at least 1 second.");
      return(INIT_FAILED);
     }

   H3ParamsDefault(g_params);
   g_params.left     = MathMax(1, MathMin(10, InpLeftBars));
   g_params.right    = MathMax(1, MathMin(10, InpRightBars));
   g_params.lookback = MathMax(50, MathMin(1000, InpLookbackBars));
   g_params.rebuild  = MathMax(1, InpRebuildBars);
   g_params.period   = PeriodSeconds(PERIOD_H4);
   g_left  = g_params.left;
   g_right = g_params.right;
   int r_req = MathMax(g_params.rebuild, 3 * g_params.lookback);
   g_depth = MathMin(r_req, g_params.hard_cap);
   if(g_left != InpLeftBars || g_right != InpRightBars || g_params.lookback != InpLookbackBars)
      PrintFormat("NOTICE: inputs clamped to LeftBars=%d RightBars=%d LookbackBars=%d", g_left, g_right, g_params.lookback);
   if(g_depth != InpRebuildBars)
      PrintFormat("NOTICE: rebuild depth R=%d requested, %d closed bars are copied (R is at least 3*L and at most %d)",
                  InpRebuildBars, g_depth, g_params.hard_cap);

   PrintFormat("T003 historical liquidity layer (PROPOSAL, not ERL / target / protecting level; read-only, never used by the bias): %s, at most %d level(s), nearest to the last close first",
               (InpShowLiquidity ? "ON" : "off"), MathMax(0, MathMin(50, InpLiqMax)));
   PrintFormat("T003 diagnostics: log/panel %s | candle export %s (closed bars only; file in MQL5\\Files of the terminal data folder)",
               (InpDiagnostics ? "ON" : "off"), (InpExportCandles ? "ON" : "off"));
   PrintFormat("T003 panel: %s view (InpShowDetails %s); T002 baseline lookback %d closed bars (InpLookbackBars, the T002 EA window)",
               (InpShowDetails ? "DETAILS" : "COMPACT"), (InpShowDetails ? "true" : "false"), g_params.lookback);
   Print("================ T003 H4 bias (visual) ================");
   Print("Visual validation only. NO ORDER FUNCTIONS ARE PRESENT IN THIS EA.");
   Print("All rules are PROPOSALS and await client validation (not client answers).");
   if(g_hist)
      PrintFormat("HISTORICAL REVIEW: AsOfTime %s (broker/server time as shown by MT5, NOT UTC, NOT TradingView time). Only H4 bars closed by then are used; no live price; the picture is static.",
                  TimeToString(g_asof, TIME_DATE|TIME_MINUTES|TIME_SECONDS));
   else
      Print("LIVE mode (AsOfTime = 0): rebuild when an H4 bar closes; events already in the history at start are not reported as new.");

   g_h4.Configure(g_symbol, PERIOD_H4, H4_MIN_READY_BARS);

   //--- Init clears every velo_t003_ object left by a crashed previous instance (this prefix only).
   g_drawer.Init(InpColorBear, InpColorBull, InpColorLevel, InpLabelFontSize);
   g_panel.Init(InpShowPanel, (int)InpPanelCorner, InpPanelFontSize, InpPanelBgColor);

   if(!EventSetTimer(InpPollSeconds))
      Print("NOTICE: EventSetTimer failed; the picture only refreshes on incoming ticks.");
   else
      g_timer_active = true;

   Poll();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_timer_active)
     {
      EventKillTimer();
      g_timer_active = false;
     }
   g_panel.Destroy();
   g_drawer.ClearAll();      // velo_t003_ prefix only
   ChartRedraw(0);
   PrintFormat("T003 SESSION LOG (Experts only): %d NEW market event(s) and %d observed change(s) in this session, %d clear/recovery baseline(s).",
               g_since.sess_new, g_since.sess_changes, g_since.baselines);
   PrintFormat("T003 H4 bias stopped (reason %d). No orders were placed, modified or closed.", reason);
  }

//+------------------------------------------------------------------+
//| A resized chart lays the panel out again for the new size (the    |
//| same lines, no new evaluation, the map objects are not touched).  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
      g_panel.Relayout();
  }

void OnTick(void)  { Poll(); }
void OnTimer(void) { Poll(); }

//+------------------------------------------------------------------+
//| Poll: thin wrapper around H4LifeDecide / H4LifeOnCopy (T002).    |
//| New H4 bars start a rebuild in live mode only; a series that is  |
//| not ready removes the picture (state reported in the panel).     |
//+------------------------------------------------------------------+
void Poll(void)
  {
   bool new_bar = false;
   g_h4.Refresh(new_bar);
   SH4LifeOut o;
   H4LifeDecide(g_life, g_h4.IsReady(), "H4 series not ready: " + g_h4.StateName(),
                H4NewBarForLife(g_hist, new_bar), GetTickCount(), g_depth, o);
   ApplyLifeOut(o);
   if(!g_h4.IsReady())
     {
      RenderPanel();
      return;
     }
   if(o.attempt == H4_ATT_PROBE)
      HistoryProbe();
   else
      if(o.attempt == H4_ATT_BUILD)
         RebuildBias();
   if(g_dirty)
     {
      g_dirty = false;
      RenderPanel();
     }
  }

void ApplyLifeOut(const SH4LifeOut &o)
  {
   if(o.log_hist)
      PrintFormat("H4 history: %s", g_life.hist_text);
   if(o.do_clear)
     {
      ClearBiasState(o.clear_reason);
      PrintFormat("T003 picture cleared: %s", o.clear_reason);
     }
  }

//+------------------------------------------------------------------+
//| ClearBiasState: remove every T003 map object (the panel stays),   |
//| drop the evaluation and the consumer baseline. A rebuild after    |
//| this is a NEW baseline: nothing in the history is reported as new,|
//| and the values labelled 'since baseline' (NEW count, observed     |
//| changes) are zeroed (H3LSinceClear).                              |
//+------------------------------------------------------------------+
void ClearBiasState(const string reason)
  {
   g_n = 0;
   g_cursor = 0;
   g_n_new = 0;
   g_prev_valid = false;
   g_prev_setup = "";
   g_tc_mode = H3_TC_BASELINE;
   g_dis_key = "";
   g_cons_text = "";
   g_clear_reason = reason;
   //--- the values labelled 'since baseline' start again from zero: no history is NEW and no earlier observed change
   //--- is shown as if it belonged to the new baseline. The session totals are kept for the Experts log only.
   if(g_since.new_total > 0 || g_since.changes > 0)
      PrintFormat("T003 SESSION LOG (Experts only): clear/recovery; %d NEW event(s) and %d observed change(s) since the previous baseline are reset in the panel (session totals: %d NEW, %d changes).",
                  g_since.new_total, g_since.changes, g_since.sess_new, g_since.sess_changes);
   H3LSinceClear(g_since);
   g_nchanges = 0;
   ArrayResize(g_changes, 0);
   ArrayResize(g_new_ids, 0);
   ResetEval();
   H3VViewInit(g_view);
   g_drawer.Reset();
   g_dirty = true;
  }

bool HistoryProbe(void)
  {
   MqlRates probe[];
   datetime oldest = 0;
   bool newest_ok = false;
   int got = CopyClosedSet(probe, oldest, newest_ok);
   SH4LifeOut o;
   H4LifeOnCopy(g_life, H4_ATT_PROBE, got, oldest, true, g_depth, g_left, g_right, o);
   ApplyLifeOut(o);
   if(o.attempt == H4_ATT_BUILD)
      return(RebuildBias());
   return(false);
  }

//+------------------------------------------------------------------+
//| CopyClosedSet: THE single copy of closed H4 bars (same helper    |
//| logic as the T002 EA). Chronological (index 0 = oldest). Returns |
//| the bar count, 0 = no closed bar in range, <0 = failed.          |
//| LIVE: CopyRates(sym, H4, start_pos 1, count) = the most recent   |
//|   CLOSED bars (position 0, the forming bar, is skipped).         |
//| HISTORICAL: CopyRates(sym, tf, start_time, count): count bars    |
//|   whose newest is the bar at start_time; start_time is AsOfTime  |
//|   capped at the forming bar's open; the bars closed by AsOfTime  |
//|   are kept (H4ClosedCountAsOf), clipped to the newest g_depth.   |
//|   No quote/bid/ask is read here.                                 |
//+------------------------------------------------------------------+
int CopyClosedSet(MqlRates &out[], datetime &oldest, bool &newest_ok)
  {
   oldest = 0;
   newest_ok = false;
   ArraySetAsSeries(out, false);             // index 0 = oldest
   if(!g_hist)
     {
      int got = CopyRates(g_symbol, PERIOD_H4, 1, g_depth, out);
      g_set_closed = (got > 0 ? got : 0);
      if(got <= 0)
        {
         ResetLastError();
         return(got);
        }
      oldest = out[0].time;
      newest_ok = H4NewestOk(false, out[got - 1].time, g_h4.ClosedOpenTime());
      return(got);
     }
   MqlRates raw[];
   ArraySetAsSeries(raw, false);
   g_asof_eff = H4EffectiveAsOf(g_asof, g_h4.FormingOpenTime());
   int rc = CopyRates(g_symbol, PERIOD_H4, g_asof_eff, g_depth + 2, raw);
   if(rc <= 0)
     {
      ResetLastError();
      g_set_closed = 0;
      return(-1);
     }
   for(int i = 1; i < rc; i++)
      if(raw[i].time <= raw[i - 1].time)
        {
         g_set_closed = 0;
         return(-1);                         // unexpected order: never analyse it
        }
   int period = PeriodSeconds(PERIOD_H4);
   int closed = H4ClosedCountAsOf(raw, rc, g_asof_eff, period);
   g_set_closed = closed;
   if(closed <= 0)
      return(0);
   int start = H4AsOfSetStart(closed, g_depth);
   int cnt = closed - start;
   ArrayResize(out, cnt);
   for(int i2 = 0; i2 < cnt; i2++)
      out[i2] = raw[start + i2];
   oldest = out[0].time;
   newest_ok = H4NewestOk(true, out[cnt - 1].time, g_h4.ClosedOpenTime());
   return(cnt);
  }

//+------------------------------------------------------------------+
bool RebuildBias(void)
  {
   datetime oldest = 0;
   bool newest_ok = false;
   int got = CopyClosedSet(g_bars, oldest, newest_ok);
   SH4LifeOut o;
   H4LifeOnCopy(g_life, H4_ATT_BUILD, got, oldest, newest_ok, g_depth, g_left, g_right, o);
   ApplyLifeOut(o);
   if(!o.rebuilt)
      return(false);
   g_n = got;
   g_clear_reason = "";
   EvaluateAndDraw(o.log_rebuilt);
   return(true);
  }

//+------------------------------------------------------------------+
//| EvaluateAndDraw: replay (P11 evaluation), consume the new events |
//| (live), draw, log. Closed bars only; no price is read.           |
//+------------------------------------------------------------------+
void EvaluateAndDraw(const string was_cleared)
  {
   if(g_hist)
      H3Evaluate(g_bars, g_n, g_params, g_ev, g_tracks, g_events);
   else
      H3EvaluateLatest(g_bars, g_n, g_params, g_ev, g_tracks, g_events);
   if(was_cleared != "")
      PrintFormat("T003 picture rebuilt (was cleared: %s). New baseline: events already in the history are not reported as new.", was_cleared);
   if(!g_hist)
      ConsumeEvents();
   g_drawer.Draw(g_bars, g_n, g_params, g_ev, g_tracks, g_events, g_new_ids, g_n_new,
                 MathMax(0, MathMin(200, InpMaxEvents)), MathMax(0, MathMin(50, InpMaxFvgs)),
                 InpShowNonMarket, InpShowInvalidFvgs,
                 InpShowLiquidity, MathMax(0, MathMin(50, InpLiqMax)), InpShowDetails, g_view);
   g_tc_mode = H3_TC_BASELINE;
   if(!g_hist)
      TrackChanges();
   LogDisagreement();
   LogEvaluation();
   LogDetails();
   RunDiagnostics();
   ExportCandles();
   g_dirty = true;
  }

//+------------------------------------------------------------------+
//| RunDiagnostics: once per evaluation that is LIMITED_BY_HISTORY    |
//| (and once per last bar and reason): replays A and B are compared  |
//| again and the findings are logged (DIAG1..DIAG8) and kept for the |
//| panel. Behaviour neutral: the evaluation itself is not changed.   |
//+------------------------------------------------------------------+
void RunDiagnostics(void)
  {
   ArrayResize(g_diag_lines, 0);
   g_ndiag = 0;
   if(!InpDiagnostics || g_ev.reliable || g_n <= 0)
     {
      g_diag_key = "";
      return;
     }
   H3Diagnose(g_bars, g_n, g_params, g_ev, g_diag);
   g_ndiag = H3DiagLines(g_diag, g_diag_lines);
   string key = H3Tx(g_ev.last_time) + "|" + g_ev.reason + "|" + IntegerToString(g_n);
   if(key == g_diag_key)
      return;
   g_diag_key = key;
   PrintFormat("T003 DIAGNOSTICS for the LIMITED_BY_HISTORY evaluation at closed bar %s (all times are server times, YYYYMMDDHHMM; causes are HYPOTHESES until a real series is replayed):",
               H3VTime(g_ev.last_time));
   for(int i = 0; i < g_ndiag; i++)
      Print("T003 " + g_diag_lines[i]);
  }

//+------------------------------------------------------------------+
//| ExportCandles: writes the CLOSED-bar set the evaluation used     |
//| (g_bars, index 0 = oldest; replays A and B are subsets of it) to  |
//| MQL5/Files/velo_t003_diag_<symbol>_<last bar>.csv. Only when the  |
//| input is true. The file name follows the last bar; the file is    |
//| OVERWRITTEN whenever the analysed set changes. Key = symbol, as-of,|
//| last bar time, bar count, first bar time and an order-sensitive   |
//| content hash of times + OHLC (H3LExportKey): history added or     |
//| corrected with the SAME last candle is exported again. No series  |
//| is read here, no quote, no trading function.                      |
//+------------------------------------------------------------------+
void ExportCandles(void)
  {
   g_export_text = "";
   if(!InpExportCandles || g_n <= 0)
      return;
   string key = H3LExportKey(g_symbol, g_asof, g_bars, g_n, g_snapshot.digits);
   if(key == g_export_key)
      return;
   SH3Export x;
   x.source   = "EA XauUsdH4Bias (MT5 closed bars, server time)";
   x.symbol   = g_symbol;
   x.mode     = (g_hist ? "HISTORICAL" : "LIVE");
   x.asof     = g_asof;
   x.digits   = g_snapshot.digits;
   x.period   = g_params.period;
   x.left     = g_params.left;
   x.right    = g_params.right;
   x.lookback = g_params.lookback;
   x.rebuild  = g_params.rebuild;
   x.r_req    = g_ev.r_req;
   x.r_eff    = g_ev.r_eff;
   x.b_depth  = g_ev.b_depth;
   x.chk      = g_ev.chk;
   x.warm     = g_ev.warm;
   x.hard_cap = g_params.hard_cap;
   x.bars     = g_n;
   x.first    = g_bars[0].time;
   x.last     = g_bars[g_n - 1].time;
   x.flag     = H3FlagName(g_ev.flag);
   x.reason   = g_ev.reason;
   x.note     = g_ev.note;
   string name = H3CsvName(g_symbol, x.last);
   int h = FileOpen(name, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      PrintFormat("T003 EXPORT FAILED: cannot open %s for writing (error %d).", name, GetLastError());
      ResetLastError();
      return;
     }
   bool ok = (FileWriteString(h, H3CsvHeader(x) + "\n") > 0);
   for(int i = 0; i < g_n && ok; i++)
      ok = (FileWriteString(h, H3CsvRow(g_bars[i], g_snapshot.digits) + "\n") > 0);
   FileClose(h);
   if(!ok)
     {
      PrintFormat("T003 EXPORT FAILED: write error on %s (error %d); the file is incomplete.", name, GetLastError());
      ResetLastError();
      return;
     }
   g_export_key = key;
   g_export_text = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + name;
   PrintFormat("T003 EXPORT: %d closed H4 bars (%s .. %s, server time) written to %s (an earlier file with this name is overwritten; set key %s)",
               g_n, H3CsvTimeText(x.first), H3CsvTimeText(x.last), g_export_text, key);
   Print("T003 EXPORT: replay offline with: python3 tests/t003_replay_csv.py <this file>");
  }

//+------------------------------------------------------------------+
//| ConsumeEvents (live): the baseline cursor makes the history at   |
//| start/restart/recovery silent; only events of the latest closed  |
//| bar, when the states before and after it are both reliable and   |
//| A/B agree, are reported as NEW (H3ConsumeNew).                   |
//+------------------------------------------------------------------+
void ConsumeEvents(void)
  {
   if(!g_ev.reliable)
     {
      g_cons_text = "NOT_RELIABLE: " + g_ev.reason + " - no event is reported as new";
      return;
     }
   if(g_cursor == 0)
     {
      g_cursor = H3BaselineCursor(g_ev);
      g_cons_status = H3_C_BASELINE;
      g_cons_text = "BASELINE at closed bar " + H3VTime(g_cursor);
      PrintFormat("T003 BASELINE: closed bar %s; %d history event(s) are NOT reported as new.",
                  H3VTime(g_cursor), g_ev.ne);
      return;
     }
   SH3Event nev[];
   int nn = 0;
   int cs = H3ConsumeNew(g_ev, g_events, g_cursor, g_params.period, nev, nn);
   g_cons_status = cs;
   g_cons_text = H3ConsumeName(cs);
   if(cs == H3_C_OK)
     {
      for(int i = 0; i < nn; i++)
        {
         if(!nev[i].market)
           {
            PrintFormat("T003 observation (not a market event) at closed bar %s: %s", H3VTime(nev[i].bar_time), H3EventText(nev[i]));
            continue;
           }
         if(g_n_new >= NEW_IDS_MAX)
           {
            int keep = NEW_IDS_MAX / 2;
            for(int k = 0; k < keep; k++)
               g_new_ids[k] = g_new_ids[g_n_new - keep + k];
            g_n_new = keep;
           }
         ArrayResize(g_new_ids, g_n_new + 1, 32);
         g_new_ids[g_n_new] = H3EventId(nev[i].type, nev[i].bar_time, nev[i].ref);
         g_n_new++;
         H3LSinceNew(g_since);
         PrintFormat("T003 NEW EVENT (PROPOSAL rule) at closed bar %s: %s",
                     H3VTime(nev[i].bar_time), H3EventText(nev[i]));
        }
      g_cursor = g_ev.last_time;
      return;
     }
   if(cs == H3_C_NOTHING_NEW)
      return;
   //--- GAP or REDERIVED: the events of the latest bar are NOT reported as new; re-baseline
   PrintFormat("T003 consumer %s (%s): events of the latest closed bar are not reported as new; re-baselined at %s.",
               H3ConsumeName(cs), (g_ev.cause != "" ? g_ev.cause : "cursor older than the previous bar"),
               H3VTime(g_ev.last_time));
   g_cursor = g_ev.last_time;
  }

//+------------------------------------------------------------------+
void PushChange(const string text)
  {
   if(g_nchanges >= CHANGES_MAX)
     {
      for(int i = 1; i < g_nchanges; i++)
         g_changes[i - 1] = g_changes[i];
      g_nchanges = CHANGES_MAX - 1;
     }
   ArrayResize(g_changes, g_nchanges + 1, 8);
   g_changes[g_nchanges] = text;
   g_nchanges++;
   H3LSinceChange(g_since);
   Print("T003 " + text);
  }

//+------------------------------------------------------------------+
//| TrackChanges (live): T003 bias, replay-window T002 structure and  |
//| phase changes                                                     |
//| between two RELIABLE evaluations, reported as market changes ONLY |
//| when the consumer accepted the step as exactly the next closed    |
//| bar with the previous state reproduced (H3_C_OK, see              |
//| H3TrackChangesMode). After a REDERIVED step (window slid, depth   |
//| changed, A/B differ), a GAP (missed bars: the date is unknown) or |
//| a same-bar re-evaluation, a difference is logged as a             |
//| RE-DERIVATION and is NEVER shown as a market change.              |
//| (Before this fix every difference was reported as a change.)      |
//+------------------------------------------------------------------+
void TrackChanges(void)
  {
   if(!g_ev.reliable)
     {
      g_prev_valid = false;       // a change across an unreliable gap is not claimed
      return;
     }
   string bias = H3DirName(g_ev.st.dir);
   string t2 = g_ev.st.t2dir;
   string ph = (g_ev.st.dir == H3_NONE ? "-" : H3PhaseName(g_ev.st.phase));
   string when = H3VTime(g_ev.last_time);
   string su = (g_ev.st.dir == H3_NONE ? "-" : (g_ev.st.setup_id != "" ? g_ev.st.setup_id : "none"));
   int mode = H3TrackChangesMode(g_cons_status, g_prev_valid);
   g_tc_mode = mode;
   if(mode == H3_TC_REPORT)
     {
      if(bias != g_prev_bias)
         PushChange(StringFormat("BIAS CHANGED %s -> %s at closed bar %s (PROPOSAL)", g_prev_bias, bias, when));
      if(t2 != g_prev_t2)
         PushChange(StringFormat("REPLAY-WINDOW T002 structure CHANGED %s -> %s at closed bar %s", g_prev_t2, t2, when));
      if(ph != g_prev_phase && bias == g_prev_bias)
         PushChange(StringFormat("PHASE CHANGED %s -> %s at closed bar %s (PROPOSAL)", g_prev_phase, ph, when));
      if(su != g_prev_setup && bias == g_prev_bias)
         PushChange(StringFormat("SETUP CHANGED %s -> %s at closed bar %s (PROPOSAL)", g_prev_setup, su, when));
     }
   else
      if(mode == H3_TC_REDERIVE && (bias != g_prev_bias || t2 != g_prev_t2 || ph != g_prev_phase))
         PrintFormat("T003 RE-DERIVATION (consumer %s%s) at closed bar %s: bias %s -> %s, replay-window T002 structure %s -> %s, phase %s -> %s differ from the previous evaluation; "
                     "this comes from the rebuild or from missed bars and is NOT reported as a market change.",
                     H3ConsumeName(g_cons_status), (g_ev.cause != "" ? ", " + g_ev.cause : ""), when,
                     g_prev_bias, bias, g_prev_t2, t2, g_prev_phase, ph);
   g_prev_valid = true;
   g_prev_bias = bias;
   g_prev_t2 = t2;
   g_prev_phase = ph;
   g_prev_setup = su;
  }

//+------------------------------------------------------------------+
//| LogDisagreement: MODEL DISAGREEMENT in terms of the T002 BASELINE |
//| (baseline BULLISH vs T003 BEAR or baseline BEARISH vs T003 BULL;  |
//| MIXED / UNKNOWN / no bias never count)                            |
//| is logged ONCE per change of its state (the key has no bar count).|
//| A change is called a market change only when the consumer accepted|
//| the step (live, H3_TC_REPORT); at start, rebuild, gap and in      |
//| historical mode it is a STATE of the replay, not a market change. |
//| Nothing is logged for an unreliable evaluation (no new market     |
//| event, nothing proposal-derived).                                 |
//+------------------------------------------------------------------+
void LogDisagreement(void)
  {
   if(!g_ev.reliable)
     {
      g_dis_key = "";
      return;
     }
   string key = H3LDisagreeKey(g_view.dis);
   if(key == g_dis_key)
      return;
   string prev = g_dis_key;
   g_dis_key = key;
   if(prev == "" && key == "NONE")
      return;                                   // first evaluation without a disagreement: nothing to say
   string how = (!g_hist && g_tc_mode == H3_TC_REPORT
                 ? "CHANGE observed at the closed bar"
                 : "STATE of the replay (start / rebuild / historical; NOT reported as a market change)");
   if(g_view.dis.active)
      PrintFormat("T003 %s | %s | closed bar %s | (PROPOSAL rules, client validation pending)", H3LDisagreeText(g_view.dis, g_params.period),
                  how, H3VTime(g_ev.last_time));
   else
      PrintFormat("T003 MODEL DISAGREEMENT ended or not present (T002 baseline %s vs T003 %s) | %s | closed bar %s",
                  H4DirName(g_view.dis.t2dir), H3DirName(g_view.dis.bias), how, H3VTime(g_ev.last_time));
  }

//+------------------------------------------------------------------+
void LogEvaluation(void)
  {
   string txt = StringFormat("%s|%s|%s", H3FlagName(g_ev.flag), g_ev.reason, g_ev.reliable ? H3DirName(g_ev.st.dir) : "UNKNOWN");
   PrintFormat("T003 EVAL (PROPOSAL rules) closed bar %s | bias %s | phase %s | support %s | reason %s | depths R_req %d R_eff %d B %d warm %d check %d | bars %d | note %s",
               H3VTime(g_ev.last_time), g_ev.reliable ? H3DirName(g_ev.st.dir) : "UNKNOWN",
               (g_ev.reliable && g_ev.st.dir != H3_NONE) ? H3PhaseName(g_ev.st.phase) : "-",
               H3FlagName(g_ev.flag), g_ev.reason, g_ev.r_req, g_ev.r_eff, g_ev.b_depth, g_ev.warm, g_ev.chk,
               g_ev.n_avail, (g_ev.note != "" ? g_ev.note : "-"));
   if(txt != g_last_flag_text)
     {
      g_last_flag_text = txt;
      if(g_ev.flag == H3_FLAG_LIMITED)
         PrintFormat("T003 LIMITED_BY_HISTORY: %s - bias reported as UNKNOWN, no market event emitted, nothing proposal-derived is drawn.", g_ev.reason);
     }
   if(g_ev.reliable && !g_view.t2_consistent)
      Print("T003 WARNING: the replay-window T002 direction recomputed for the panel differs from the one in the replay state.");
   if(g_view.missing != "")
      PrintFormat("T003 NOTE: not located in the examined bars: %s", g_view.missing);
  }

//+------------------------------------------------------------------+
//| LogDetails: the long view goes to the Experts log (once per       |
//| evaluation, reliable evaluations only): the compact summary, the  |
//| T002 baseline versus the replay-window structure, the source      |
//| swings, the level pivots and the setup facts with their ids.      |
//| Plain Print: the texts hold ids and are never used as formats.    |
//+------------------------------------------------------------------+
void LogDetails(void)
  {
   if(!g_ev.reliable)
      return;
   SH3State st;
   H3StateCopy(g_ev.st, st);
   int dg = g_snapshot.digits;
   string lvl = (st.dir != H3_NONE && st.has_level ? DoubleToString(st.lv_price, dg) : "-");
   string snap = (g_view.ctx.valid ? DoubleToString(g_view.ctx.snap_price, dg) : "-");
   Print("T003 SUMMARY (PROPOSAL rules) | " + (g_hist ? "HISTORICAL as-of " + TimeToString(g_asof, TIME_DATE|TIME_MINUTES) : "LIVE") +
         " | last closed bar " + H3VTime(g_ev.last_time) + " | T003 bias " + H3DirName(st.dir) + " " +
         (st.dir == H3_NONE ? "-" : H3PhaseName(st.phase)) + " | " + H3LT2Name(g_view.t2_base_look) + " " +
         H4DirName(g_view.t2_base) + " | current level " + lvl + " | snapshot " + snap + " | READY " +
         (g_view.ctx.valid && g_view.ctx.ready ? "yes" : "no") + " | FVG " + (g_view.fvg_last != "" ? g_view.fvg_last : "none") +
         " | " + H3FlagName(g_ev.flag) + " " + IntegerToString(g_ev.r_eff) + "/" + IntegerToString(g_ev.b_depth));
   Print("T003 DETAIL structure: " + H3LT2Name(g_view.t2_base_look) + " = " + H4DirName(g_view.t2_base) + " (" +
         H3LStructureWords(g_view.t2_base) + "), " + IntegerToString(g_view.t2_base_bars) + " closed bars; replay-window structure = " +
         H4DirName(g_view.t2_cur) + " (" + H3LStructureWords(g_view.t2_cur) + ") since " + H3VTime(g_view.t2_since) +
         (g_view.t2_cur != g_view.t2_base ? " - DIFFERS from the baseline (the replay window is longer than the lookback)" : " - same as the baseline"));
   Print("T003 DETAIL T002 sources (replay window): " + g_view.t2_src_text);
   if(g_view.pivots_text != "")
      Print("T003 DETAIL level selected from: " + g_view.pivots_text);
   if(st.dir != H3_NONE && st.has_level)
      Print("T003 DETAIL current protecting level " + st.lv_id + " " + DoubleToString(st.lv_price, dg) + " known " + H3VTime(st.lv_known));
   if(g_view.ctx.valid)
     {
      Print("T003 DETAIL setup " + g_view.ctx.setup_id + " | " + g_view.ctx.direction + " | type " + g_view.ctx.stype + " | reason " +
            g_view.ctx.reason + " | phase " + g_view.ctx.phase + " | snapshot " + g_view.ctx.snap_id + " " + snap);
      if(g_view.ctx.fvg_id != "")
         Print("T003 DETAIL reconfirmation FVG " + g_view.ctx.fvg_id + " [" + DoubleToString(g_view.ctx.fvg_lower, dg) + " - " +
               DoubleToString(g_view.ctx.fvg_upper, dg) + "] confirmed " + H3VTime(g_view.ctx.fvg_conf));
     }
   if(g_view.liq_text != "")
      Print("T003 DETAIL historical liquidity (proposal): " + g_view.liq_text);
  }

//+------------------------------------------------------------------+
//| RenderPanel. Every line carries a priority (0 essential, higher   |
//| = dropped first when the chart is too small, see CH3Panel).       |
//| COMPACT (default): mode/date, T003 bias (prototype), the T002     |
//| baseline, the model disagreement, current level + snapshot, phase |
//| / READY, the FVG, reliability. InpShowDetails adds the long view. |
//+------------------------------------------------------------------+
void RenderPanel(void)
  {
   if(!InpShowPanel)
      return;
   int dg = g_snapshot.digits;
   g_panel.Begin();
   g_panel.Line("T003 H4 BIAS - PROPOSAL (client validation pending), visual only, NO TRADING", clrGold, 0);
   if(g_hist)
     {
      g_panel.Line(StringFormat("HISTORICAL as-of %s (broker/server time, NOT UTC, NOT TradingView) - static, closed bars only",
                                TimeToString(g_asof, TIME_DATE|TIME_MINUTES)), clrMagenta, 0);
      if(g_asof_eff != 0 && g_asof_eff < g_asof)
         g_panel.Line("as-of is after the forming H4 bar: the forming bar is NOT used", clrOrange, 1);
     }
   else
      g_panel.Line("LIVE - rebuilt when an H4 bar closes (forming bar never read)", clrLimeGreen, 0);
   if(!g_h4.IsReady() || !g_life.have_map)
     {
      g_panel.Line(StringFormat("H4 data: %s - %s", g_h4.StateName(), g_h4.Detail()), clrOrange, 0);
      g_panel.Line("picture: CLEARED (no T003 object is drawn)" + (g_clear_reason != "" ? " - " + g_clear_reason : ""), clrOrange, 0);
      if(g_hist && g_h4.IsReady() && !g_life.have_map)
         g_panel.Line(StringFormat("as-of set: %d closed H4 bar(s) found; as-of earlier than available history, or history still loading",
                                   g_set_closed), clrOrange, 1);
      if(g_life.hist_text != "")
         g_panel.Line(g_life.hist_text, clrOrange, 1);
      g_panel.End();
      return;
     }
   g_panel.Line(StringFormat("%s  last closed H4 bar: open %s (closed %s), %d bars copied", g_symbol,
                             H3VTime(g_ev.last_time), H3VTime(g_ev.last_time + g_params.period), g_n),
                g_hist ? clrMagenta : clrSilver, 0);
   if(g_life.hist_text != "")
      g_panel.Line(g_life.hist_text, g_life.hist_state == H4_HIST_COMPLETE ? clrSilver : clrOrange, 1);

   //--- reliability (support flag) with the depths: R used / B depth
   color fc = (g_ev.flag == H3_FLAG_CONVERGED ? clrLimeGreen : (g_ev.flag == H3_FLAG_SEEDED ? clrYellow : clrOrange));
   if(!g_ev.reliable)
     {
      g_panel.Line(StringFormat("reliability: %s %d/%d - %s", H3FlagName(g_ev.flag), g_ev.r_eff, g_ev.b_depth, g_ev.reason), fc, 0);
      g_panel.Line("T003 bias: UNKNOWN (not reliable). Nothing proposal-derived is drawn (no setup, no liquidity layer) and no market event is emitted.", clrOrange, 0);
      if(H3LReasonHelp(g_ev.reason) != "")
         g_panel.Line("reasons: " + H3LReasonHelp(g_ev.reason), clrOrange, 1);
      if(g_ev.note != "")
         g_panel.Line("note: " + g_ev.note, clrOrange, 2);
      if(!g_hist)
         g_panel.Line("consumer: " + g_cons_text, clrOrange, 2);
      if(InpShowDetails && InpDiagnostics && g_diag.valid && g_ndiag >= 8)
        {
         g_panel.Line("WHY (diagnostics; causes are hypotheses; all DIAG1..DIAG8 lines are in the Experts log):", clrGold, 3);
         g_panel.Line(g_diag_lines[0], clrSilver, 3);      // windows, warm-up ends, comparison zone
         g_panel.Line(g_diag_lines[3], clrOrange, 3);      // first differing field of the final states
         g_panel.Line(g_diag_lines[4], clrOrange, 3);      // first differing event in the zone
        }
      else
         if(InpDiagnostics && g_diag.valid)
            g_panel.Line("WHY: see the T003 DIAGNOSTICS lines in the Experts log (InpShowDetails shows three here)", clrSilver, 2);
      if(g_export_text != "")
         g_panel.Line("candles exported: " + g_export_text, clrSilver, 2);
      g_panel.End();
      return;
     }

   SH3State st;
   H3StateCopy(g_ev.st, st);
   string bias = H3DirName(st.dir);
   color bc = (st.dir == H3_BEAR ? InpColorBear : (st.dir == H3_BULL ? InpColorBull : clrSilver));

   //--- T003 prototype bias
   if(st.dir == H3_NONE)
      g_panel.Line(StringFormat("T003 bias (PROTOTYPE proposal): NONE (%s)", H3NoneReasonName(st.none_reason)), bc, 0);
   else
      g_panel.Line(StringFormat("T003 bias (PROTOTYPE proposal, not the client's direction): %s  since %s", bias, H3VTime(st.bias_start)), bc, 0);
   //--- the comparison structure: the T002 BASELINE (the T002 EA's window, InpLookbackBars)
   string bl = StringFormat("%s: %s (%s)", H3LT2Name(g_view.t2_base_look), H4DirName(g_view.t2_base), H3LStructureWords(g_view.t2_base));
   if(g_view.t2_base_bars < g_view.t2_base_look)
      bl += StringFormat(" [only %d bars exist]", g_view.t2_base_bars);
   g_panel.Line(bl, clrWhite, 0);
   if(g_view.dis.active)
      g_panel.Line(H3LDisagreeText(g_view.dis, g_params.period), clrOrangeRed, 0);
   else
      g_panel.Line(StringFormat("model disagreement: none (T002 baseline %s, T003 %s)", H4DirName(g_view.dis.t2dir), H3DirName(g_view.dis.bias)), clrSilver, 1);
   g_panel.Line("MODEL DISAGREEMENT (proposal) is stated in terms of the T002 BASELINE: T002 baseline BULLISH vs T003 BEAR or T002 baseline BEARISH vs T003 BULL only; MIXED / UNKNOWN / no bias never count", clrSilver, 3);
   if(g_view.t2_cur != g_view.t2_base)
      g_panel.Line(StringFormat("replay-window structure %s DIFFERS from the T002 baseline %s (the replay window is longer than the lookback %d)",
                                H4DirName(g_view.t2_cur), H4DirName(g_view.t2_base), g_view.t2_base_look), clrOrange, 1);
   else
      g_panel.Line(StringFormat("replay-window structure %s = the T002 baseline", H4DirName(g_view.t2_cur)), clrSilver, 4);
   if(!g_view.dis_consistent)
      g_panel.Line("WARNING: the bias rebuilt from the events differs from the replay state", clrRed, 1);
   if(!g_view.t2_consistent)
      g_panel.Line("WARNING: recomputed replay-window T002 direction differs from the replay state", clrRed, 1);
   //--- current level (solid) and snapshot (dashed, reference only)
   string lvl = "current level " + (st.dir != H3_NONE && st.has_level ? DoubleToString(st.lv_price, dg) + " (solid)" :
                                    (st.dir != H3_NONE ? "NOT defined" : "-"));
   if(g_view.ctx.valid)
      lvl += "  |  snapshot " + DoubleToString(g_view.ctx.snap_price, dg) + " (dashed, reference only)";
   g_panel.Line(lvl, clrWhite, 0);
   //--- phase and READY
   g_panel.Line(StringFormat("phase %s  |  READY %s", (st.dir == H3_NONE ? "-" : H3PhaseName(st.phase)),
                             (g_view.ctx.valid && g_view.ctx.ready ? "YES" : "no")),
                (g_view.ctx.valid && g_view.ctx.ready ? clrLime : clrGold), 0);
   //--- the FVG: the reconfirmation FVG, else the latest eligible one
   g_panel.Line("FVG: " + (g_view.fvg_last != "" ? g_view.fvg_last : "none eligible"), clrGold, 0);
   g_panel.Line(StringFormat("reliability: %s %d/%d (R used / B depth)%s", H3FlagName(g_ev.flag), g_ev.r_eff, g_ev.b_depth,
                             (g_ev.reason != "" ? " - " + g_ev.reason : "")), fc, 0);
   if(g_view.missing != "")
      g_panel.Line("not located: " + g_view.missing, clrOrange, 1);
   if(g_export_text != "")
      g_panel.Line("candles exported: " + g_export_text, clrSilver, 2);
   if(!InpShowDetails)
     {
      g_panel.Line("compact view. All details are in the Experts log (T003 SUMMARY / DETAIL). Input InpShowDetails = true shows the long view here.", clrDimGray, 5);
      g_panel.End();
      return;
     }

   //--- DETAILS (InpShowDetails = true): the long view, lowest priorities
   g_panel.Line(StringFormat("depths: R requested %d | R used %d | B depth %d | warm-up %d | check %d | bars available %d",
                             g_ev.r_req, g_ev.r_eff, g_ev.b_depth, g_ev.warm, g_ev.chk, g_ev.n_avail), clrSilver, 3);
   if(g_ev.note != "")
      g_panel.Line("note: " + g_ev.note + (StringFind(g_ev.note, "ORG_DIFF") >= 0 ? "   (ORG_DIFF is informational: the origin name differs between A and B; it is never a reason)" : ""), clrOrange, 3);
   g_panel.Line("--- STRUCTURE (PROPOSAL; the client confirmed how direction is DESCRIBED, N1, not these swings or this bias) ---", clrGold, 3);
   string t2line = StringFormat("replay-window structure (whole window, 2/2 swings): %s (%s)   since bar %s", st.t2dir,
                                H3LStructureWords(g_view.t2_cur), H3VTime(g_view.t2_since));
   if(!g_view.t2_exact)
      t2line += " (or earlier: the run reaches the start of the examined bars)";
   else
      if(g_view.t2_prev >= 0)
         t2line += StringFormat("   previous %s", H4DirName(g_view.t2_prev));
   g_panel.Line(t2line, clrWhite, 3);
   g_panel.Line("T002 sources (replay window): " + g_view.t2_src_text, clrSilver, 4);
   g_panel.Line("phase reason: " + H3VPhaseReason(st), bc, 3);
   if(g_view.dis_win.active != g_view.dis.active)
      g_panel.Line(StringFormat("information: the same test with the replay-window structure would %s a disagreement",
                                (g_view.dis_win.active ? "show" : "not show")), clrSilver, 4);
   for(int i = g_ev.ne - 1; i >= 0; i--)
     {
      int ty = g_events[i].type;
      if(ty == H3_EV_FLIP || ty == H3_EV_BREAK_SET || ty == H3_EV_SEED || ty == H3_EV_CONFLICT)
        {
         g_panel.Line(StringFormat("last bias event in the history: %s at closed bar %s", H3VEventLabel(g_events[i], false),
                                   H3VTime(g_events[i].bar_time)), clrGold, 3);
         break;
        }
     }
   for(int c = g_nchanges - 1; c >= 0; c--)
      g_panel.Line("observed live (since baseline): " + g_changes[c], clrAqua, 3);
   if(st.dir != H3_NONE && st.has_level)
     {
      g_panel.Line(StringFormat("CURRENT protecting level (PROPOSAL, decides FLIP): %s %s known %s", st.lv_id,
                                DoubleToString(st.lv_price, dg), H3VTime(st.lv_known)), clrWhite, 3);
      g_panel.Line("selected from: " + g_view.pivots_text, clrSilver, 4);
     }
   if(st.dir != H3_NONE && st.has_lint)
      g_panel.Line(StringFormat("internal liquidity (revision 14 proposal; per-level, not the historical liquidity layer): %d unconsumed level(s), most adverse %s %s",
                                st.li_n, st.li_id, DoubleToString(st.li_price, dg)), clrViolet, 4);

   //--- the SETUP, separate from the structure (read-only SH3SetupCtx)
   g_panel.Line("--- SETUP (PROPOSAL / PROTOTYPE; separate from the structure; the snapshot is a reference only) ---", clrGold, 3);
   if(!g_view.ctx.valid)
      g_panel.Line("SETUP: none (phase ACTIVE; no wick or sweep is waiting for a new FVG)", clrSilver, 3);
   else
     {
      g_panel.Line(StringFormat("SETUP %s", g_view.ctx.setup_id), clrGold, 3);
      g_panel.Line(StringFormat("  direction %s | type %s | reason %s | phase %s | READY %s (true only in RECONFIRMED; M15 is not built)",
                                g_view.ctx.direction, g_view.ctx.stype, g_view.ctx.reason, g_view.ctx.phase, (g_view.ctx.ready ? "YES" : "no")),
                   g_view.ctx.ready ? clrLime : clrGold, 3);
      g_panel.Line(StringFormat("  snapshot level (dashed, reference only): %s %s known %s", g_view.ctx.snap_id,
                                DoubleToString(g_view.ctx.snap_price, dg), H3VTime(g_view.ctx.snap_known)), clrGoldenrod, 4);
      g_panel.Line(StringFormat("  current level (solid, decides FLIP): %s %s", (g_view.ctx.live_id != "" ? g_view.ctx.live_id : "none"),
                                (g_view.ctx.live_id != "" ? DoubleToString(g_view.ctx.live_price, dg) : "-")), clrWhite, 4);
      if(st.has_wick)
         g_panel.Line(StringFormat("  wick: source_wick_time %s | known %s | detected_at %s | %s", H3VTime(st.wk_src),
                                   H3VTime(st.wk_known), H3VTime(st.wk_det),
                                   (st.wk_retro ? "RETROACTIVE (level known after the wick)" : "not retroactive")), clrOrange, 4);
      if(st.sweep_time != 0)
         g_panel.Line(StringFormat("  internal sweep (technical proposal): bar %s, wait from %s", H3VTime(st.sweep_time),
                                   H3VTime(st.wait_start)), clrViolet, 4);
      g_panel.Line(StringFormat("  eligible new FVGs: %d (invalid %d), %d drawn", g_view.fvg_total, g_view.fvg_invalid, g_view.fvg_shown), clrGold, 4);
      if(g_view.ctx.fvg_id != "")
         g_panel.Line(StringFormat("  reconfirmation FVG: %s [%s - %s] confirmed %s | valid from %s", g_view.ctx.fvg_id,
                                   DoubleToString(g_view.ctx.fvg_lower, dg), DoubleToString(g_view.ctx.fvg_upper, dg),
                                   H3VTime(g_view.ctx.fvg_conf), H3VTime(g_view.ctx.valid_from)), clrGold, 4);
      else
         g_panel.Line("  reconfirmation FVG: none", clrSilver, 4);
      if(st.pre != "")
         g_panel.Line("  PRE_WICK FVGs (older than the wick, ineligible): " + st.pre, clrSilver, 4);
     }
   g_panel.Line(StringFormat("entry-block flags, REPORTED ONLY (nothing acts on them): HOLD %s (client S3) | SWEEP_WAIT %s (technical proposal)",
                             (H3HoldBlock(st) ? "yes" : "no"), (H3SweepBlock(st) ? "yes" : "no")), clrSilver, 4);

   //--- events: history versus new
   g_panel.Line("--- EVENTS ---", clrGold, 4);
   if(g_hist)
      g_panel.Line(StringFormat("events in the history: %d, %d drawn (%d not drawn: limit, filter or outside the window)",
                                g_ev.ne, g_view.ev_shown, g_view.ev_hidden), clrSilver, 4);
   else
      g_panel.Line(StringFormat("events in the history: %d, %d drawn (%d not drawn) | NEW market events since the baseline: %d | consumer: %s",
                                g_ev.ne, g_view.ev_shown, g_view.ev_hidden, g_since.new_total, g_cons_text), clrSilver, 4);
   int listed = 0;
   for(int e = g_ev.ne - 1; e >= 0 && listed < 4; e--)
     {
      bool is_new = H3VIdInList(H3EventId(g_events[e].type, g_events[e].bar_time, g_events[e].ref), g_new_ids, g_n_new);
      g_panel.Line(StringFormat("  %s  bar %s  %s", (is_new ? "[NEW] " : "[hist]"), H3VTime(g_events[e].bar_time),
                                H3VEventLabel(g_events[e], false)), is_new ? clrLime : clrSilver, 4);
      listed++;
     }

   //--- historical liquidity (proposal)
   g_panel.Line("--- PROPOSAL - historical liquidity, not ERL / target / protecting level ---", clrGold, 4);
   if(!InpShowLiquidity)
      g_panel.Line("liquidity layer: OFF (input InpShowLiquidity)", clrSilver, 4);
   else
     {
      g_panel.Line(StringFormat("confirmed 2/2 swings not exceeded by a later wick: %d, %d drawn (nearest to the last close first; limit InpLiqMax %d). Fractal 2/2 and this definition are proposals: the client confirmed the concept (N2), not the algorithm",
                                g_view.liq_total, g_view.liq_shown, MathMax(0, MathMin(50, InpLiqMax))), clrSilver, 4);
      string rest = g_view.liq_text;
      int shown_l = 0;
      while(rest != "" && shown_l < 8)
        {
         int bar = StringFind(rest, "|");
         string one = (bar < 0 ? rest : StringSubstr(rest, 0, bar));
         rest = (bar < 0 ? "" : StringSubstr(rest, bar + 1));
         g_panel.Line("  liq " + one, clrLightSlateGray, 4);
         shown_l++;
        }
     }
   g_panel.End();
  }
//+------------------------------------------------------------------+
