//+------------------------------------------------------------------+
//|                                              XauUsdH4Map.mq5     |
//|                                                                  |
//|  Submission XAU-20261006-E27N93 - task T002 (H4 structure map).  |
//|                                                                  |
//|  VISUAL PROTOTYPE. Draws, from CLOSED H4 bars of the chart       |
//|  symbol: confirmed swings (marked at the pivot, text shows the   |
//|  confirmation time), direction, structural interval, ERL, H4     |
//|  FVGs with state, and the nearest IRL candidate with an          |
//|  IRL -> ERL link.                                                |
//|                                                                  |
//|  EVERY RULE IS PROPOSED (tasks/T002-h4-map.md section C): a      |
//|  developer proposal awaiting the client's visual validation, not |
//|  a client answer and not a trading rule.                         |
//|                                                                  |
//|  Does NOT: send, modify or close orders; use M5/M15; compute     |
//|  entries, stop loss, take profit or lot size.                    |
//|                                                                  |
//|  INSTALL (Expert Advisor, NOT a script): copy the whole          |
//|  repository src/ folder to                                       |
//|    <terminal data folder>/MQL5/Experts/velo_src/                 |
//|  so that MQL5/Experts/velo_src/XauUsdH4Map.mq5 sits next to      |
//|  MQL5/Experts/velo_src/include/ (the include lines of this file  |
//|  are relative to this file). Compile in MetaEditor, attach       |
//|  to an XAUUSD chart. The logic test is a separate SCRIPT and     |
//|  goes under MQL5/Scripts/ (see src/tests/T002_LogicTest.mq5).    |
//|  Install layout NOT tested in MT5.                               |
//|                                                                  |
//|  Verification status: NOT COMPILED here (no MetaEditor). The     |
//|  Python tests verify an algorithm MODEL, not this MQL5 source.   |
//|  src/tests/T002_LogicTest.mq5 has not been run.                  |
//+------------------------------------------------------------------+
#property copyright   "velireci"
#property version     "1.00"
#property description "T002 H4 structure map (visual prototype): proposed H4 model - client validation pending."
#property description "Contains no order functions and no trading logic."

#include "include/SymbolSnapshot.mqh"
#include "include/TimeframeWatcher.mqh"
#include "include/StatusPanel.mqh"
#include "include/H4Structure.mqh"
#include "include/H4MapDrawer.mqh"

enum ENUM_PANEL_CORNER
  {
   PANEL_TOP_LEFT  = 0,  // Top left
   PANEL_TOP_RIGHT = 1   // Top right
  };

input group "Proposed H4 model (client validation pending)"
input int              InpLeftBars      = 2;                   // Swing: closed bars on the left (1..10)
input int              InpRightBars     = 2;                   // Swing: closed bars on the right (1..10)
input int              InpLookbackBars  = 300;                 // Closed H4 bars analysed (clamped 50..1000)

input group "Display"
input bool             InpShowPanel     = true;                // Draw the status panel
input ENUM_PANEL_CORNER InpPanelCorner  = PANEL_TOP_LEFT;       // Panel corner
input bool             InpShowInvalid   = false;               // Also draw INVALID FVGs (dimmed)
input color            InpColorBear     = clrTomato;           // Bearish FVG / swing high colour
input color            InpColorBull     = clrDodgerBlue;       // Bullish FVG / swing low colour
input color            InpColorErl      = clrOrange;           // ERL and link colour
input int              InpPollSeconds   = 1;                   // Timer poll interval in seconds

#define H4_MIN_READY_BARS 60
#define REFRESH_MS        1000
//--- cadence constants (H4_RETRY_MS, H4_SLOW_RETRY_MS, H4_HIST_MAX_NOPROG) live in H4Structure.mqh

string            g_symbol = "";
SSymbolSnapshot   g_snapshot;
CTimeframeWatcher g_h4;
CStatusPanel      g_panel;
CH4MapDrawer      g_drawer;

int               g_left     = 2;
int               g_right    = 2;
int               g_lookback = 300;

MqlRates          g_bars[];
int               g_n        = 0;
SH4Swing          g_swings[];
int               g_ns       = 0;
SH4Fvg            g_fvgs[];
int               g_nf       = 0;
SH4Result         g_res;
int               g_order[];
int               g_sel      = 0;
datetime          g_map_last_closed = 0;
uint              g_last_refresh    = 0;
bool              g_refreshed_once  = false;
bool              g_timer_active    = false;
double            g_price    = 0.0;

//--- map lifecycle (history state, stall counter, cadence): decided by the
//--- pure step functions H4LifeDecide / H4LifeOnCopy in H4Structure.mqh
SH4Life           g_life;

void Poll(void);
bool RecomputeMap(void);
void RefreshPrice(const bool force);
void RenderPanel(void);
void ClearMapState(const string reason);
void ApplyLifeOut(const SH4LifeOut &o);
bool HistoryProbe(void);

//+------------------------------------------------------------------+
int OnInit(void)
  {
   H4LifeInit(g_life);
   g_refreshed_once = false;
   g_timer_active = false;
   g_n = g_ns = g_nf = g_sel = 0;
   g_map_last_closed = 0;
   g_price = 0.0;
   ZeroMemory(g_res);

   g_symbol = _Symbol;
   if(!SymbolSnapshotLoad(g_symbol, g_snapshot))
     {
      PrintFormat("T002 INIT FAILED: symbol '%s' unusable - %s", g_symbol, g_snapshot.problem);
      return(INIT_FAILED);
     }
   if(InpPollSeconds < 1)
     {
      Print("T002 INIT FAILED: poll interval must be at least 1 second.");
      return(INIT_FAILED);
     }

   g_left     = MathMax(1, MathMin(10, InpLeftBars));
   g_right    = MathMax(1, MathMin(10, InpRightBars));
   g_lookback = MathMax(50, MathMin(1000, InpLookbackBars));
   if(g_left != InpLeftBars || g_right != InpRightBars || g_lookback != InpLookbackBars)
      PrintFormat("NOTICE: inputs clamped to LeftBars=%d RightBars=%d LookbackBars=%d", g_left, g_right, g_lookback);

   Print("================ T002 H4 map ================");
   Print("Visual prototype. NO ORDER FUNCTIONS ARE PRESENT IN THIS EA.");
   Print("All H4 rules are PROPOSED and await client validation (not client answers).");

   g_h4.Configure(g_symbol, PERIOD_H4, H4_MIN_READY_BARS);

   //--- Init clears every velo_t002_ object left by a crashed previous instance.
   g_drawer.Init(InpColorBear, InpColorBull, InpColorErl);
   g_panel.Init(g_drawer.PanelPrefix(), InpShowPanel,
                InpPanelCorner == PANEL_TOP_RIGHT ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER);

   if(!EventSetTimer(InpPollSeconds))
      Print("NOTICE: EventSetTimer failed; the map only refreshes on incoming ticks.");
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
   g_drawer.ClearAll();      // velo_t002_ prefix only
   ChartRedraw(0);
   PrintFormat("T002 H4 map stopped (reason %d). No orders were placed, modified or closed.", reason);
  }

void OnTick(void)  { Poll(); }
void OnTimer(void) { Poll(); }

//+------------------------------------------------------------------+
//| Poll: thin wrapper. The decisions (clear when the series is not  |
//| ready, which copy to attempt and when, stall cadence, rebuild)   |
//| are made by H4LifeDecide / H4LifeOnCopy; this code only does the|
//| CopyRates, the drawing and the logging. No Sleep, no loops: each |
//| re-check is one CopyRates call, at most every H4_RETRY_MS (every |
//| H4_SLOW_RETRY_MS once loading has stalled; it never stops).      |
//+------------------------------------------------------------------+
void Poll(void)
  {
   bool new_bar = false;
   g_h4.Refresh(new_bar);
   SH4LifeOut o;
   H4LifeDecide(g_life, g_h4.IsReady(), "H4 series not ready: " + g_h4.StateName(),
                new_bar, GetTickCount(), g_lookback, o);
   ApplyLifeOut(o);
   if(!g_h4.IsReady())
     {
      RenderPanel();
      return;
     }
   bool recomputed = false;
   if(o.attempt == H4_ATT_PROBE)
      recomputed = HistoryProbe();
   else
      if(o.attempt == H4_ATT_BUILD)
         recomputed = RecomputeMap();
   RefreshPrice(recomputed);
  }

//+------------------------------------------------------------------+
//| ApplyLifeOut: log a history-text change, and on do_clear remove  |
//| every map drawing and disable the dynamic state (once per        |
//| transition, logged so it is visible without the panel).          |
//+------------------------------------------------------------------+
void ApplyLifeOut(const SH4LifeOut &o)
  {
   if(o.log_hist)
      PrintFormat("H4 history: %s", g_life.hist_text);
   if(o.do_clear)
     {
      ClearMapState(o.clear_reason);
      PrintFormat("H4 MAP cleared: %s", o.clear_reason);
     }
  }

//+------------------------------------------------------------------+
//| ClearMapState: wipe the map data and remove the map drawings     |
//| (swings, FVG, labels, ERL, range lines, link; the panel stays).  |
//| The have_map flag itself is owned by g_life.                     |
//+------------------------------------------------------------------+
void ClearMapState(const string reason)
  {
   g_sel = 0;
   g_n = g_ns = g_nf = 0;
   g_map_last_closed = 0;
   ArrayResize(g_order, 0);
   ZeroMemory(g_res);
   g_drawer.Reset();
  }

//+------------------------------------------------------------------+
//| HistoryProbe: re-copy; the decision (more history -> rebuild,    |
//| failed copy -> clear, nothing new -> count one idle check) is    |
//| taken by H4LifeOnCopy. A failed copy is NOT idle evidence.       |
//+------------------------------------------------------------------+
bool HistoryProbe(void)
  {
   MqlRates probe[];
   ArraySetAsSeries(probe, false);
   int got = CopyRates(g_symbol, PERIOD_H4, 1, g_lookback, probe);
   datetime oldest = 0;
   if(got > 0)
      oldest = probe[0].time;
   else
      ResetLastError();
   SH4LifeOut o;
   H4LifeOnCopy(g_life, H4_ATT_PROBE, got, oldest, true, g_lookback, g_left, g_right, o);
   ApplyLifeOut(o);
   if(o.attempt == H4_ATT_BUILD)
      return(RecomputeMap());
   return(false);
  }

//+------------------------------------------------------------------+
//| RecomputeMap: copy CLOSED bars (shift 1 = skip the forming bar). |
//| H4LifeOnCopy decides clear / rebuild; this analyses and draws.   |
//+------------------------------------------------------------------+
bool RecomputeMap(void)
  {
   ArraySetAsSeries(g_bars, false);          // index 0 = oldest
   int got = CopyRates(g_symbol, PERIOD_H4, 1, g_lookback, g_bars);
   datetime oldest = 0;
   bool newest_ok = false;
   if(got > 0)
     {
      oldest = g_bars[0].time;
      //--- the newest copied bar must be the closed bar the watcher reports,
      //--- otherwise the history is still catching up: retry (throttled)
      newest_ok = (g_h4.ClosedOpenTime() == 0 || g_bars[got - 1].time == g_h4.ClosedOpenTime());
     }
   else
      ResetLastError();
   SH4LifeOut o;
   H4LifeOnCopy(g_life, H4_ATT_BUILD, got, oldest, newest_ok, g_lookback, g_left, g_right, o);
   ApplyLifeOut(o);
   if(!o.rebuilt)
      return(false);
   g_n = got;
   H4Analyze(g_bars, g_n, g_left, g_right, PeriodSeconds(PERIOD_H4),
             g_swings, g_ns, g_fvgs, g_nf, g_res);
   g_map_last_closed = g_bars[g_n - 1].time;
   g_drawer.DrawStatic(g_bars, g_n, PeriodSeconds(PERIOD_H4), g_swings, g_ns,
                       g_fvgs, g_nf, g_res, InpShowInvalid);
   if(o.log_rebuilt != "")
      PrintFormat("H4 MAP rebuilt (was cleared: %s)", o.log_rebuilt);
   PrintFormat("H4 MAP recomputed: closed bar %s | %s | interval %s | ERL %s | swings %d | FVG %d (proposed model)",
               TimeToString(g_map_last_closed, TIME_DATE|TIME_MINUTES),
               H4DirName(g_res.direction), H4RangeName(g_res.range_state),
               H4ErlName(g_res.erl_state), g_ns, g_nf);
   return(true);
  }

//+------------------------------------------------------------------+
//| RefreshPrice: price-vs-zone only, at most once per second        |
//+------------------------------------------------------------------+
void RefreshPrice(const bool force)
  {
   if(!g_life.have_map)
     {
      RenderPanel();
      return;
     }
   uint now = GetTickCount();
   if(!force && g_refreshed_once && (now - g_last_refresh) < REFRESH_MS)
      return;
   g_last_refresh   = now;
   g_refreshed_once = true;

   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   if(bid > 0.0)
      g_price = bid;
   g_sel = H4SelectIrl(g_fvgs, g_nf, g_res, g_price, g_order);
   g_drawer.DrawDynamic(g_fvgs, g_nf, g_res, g_price, g_order, g_sel, InpShowInvalid);
   RenderPanel();
  }

//+------------------------------------------------------------------+
void RenderPanel(void)
  {
   if(!InpShowPanel)
      return;
   int dg = g_snapshot.digits;
   g_panel.Begin();
   g_panel.Line("proposed H4 model - client validation pending", clrGold);
   g_panel.Line("T002 H4 MAP - visual only, no trading", clrSilver);
   if(!g_h4.IsReady() || !g_life.have_map)
     {
      g_panel.Line(StringFormat("H4 data: %s - %s", g_h4.StateName(), g_h4.Detail()), clrOrange);
      g_panel.Line(g_life.have_map ? "map: shown" : "map: CLEARED (no map is drawn)", clrOrange);
      if(g_life.hist_text != "")
         g_panel.Line(g_life.hist_text, clrOrange);
      g_panel.End();
      return;
     }
   g_panel.Line(StringFormat("%s  bid %s  last closed H4 %s", g_symbol, DoubleToString(g_price, dg),
                             TimeToString(g_map_last_closed, TIME_DATE|TIME_MINUTES)), clrSilver);
   g_panel.Line(StringFormat("direction: %s   (swing %d/%d, lookback %d)", H4DirName(g_res.direction),
                             g_left, g_right, g_n), clrWhite);
   if(g_res.range_state == H4_RNG_VALID)
      g_panel.Line(StringFormat("interval: H %s  L %s  known %s", DoubleToString(g_res.range_high, dg),
                                DoubleToString(g_res.range_low, dg),
                                TimeToString(g_res.range_known_time, TIME_DATE|TIME_MINUTES)), clrWhite);
   else
      g_panel.Line(StringFormat("interval: %s", H4RangeName(g_res.range_state)), clrOrange);
   if(g_res.erl_state == H4_ERL_NA)
      g_panel.Line("ERL: n/a", clrSilver);
   else
      g_panel.Line(StringFormat("ERL %s: %s (closed bars; may lag live price by up to 1 bar)",
                                DoubleToString(g_res.erl_price, dg), H4ErlName(g_res.erl_state)),
                   g_res.erl_state == H4_ERL_TAKEN ? clrOrange : clrLimeGreen);
   bool active = H4SetupActive(g_res, g_sel);
   if(g_sel > 0)
     {
      int k = g_order[0];
      bool inside = H4PriceInsideZone(g_fvgs[k], g_price);
      string zone = StringFormat("%s %s [%s - %s]", g_fvgs[k].id, H4FvgStateName(g_fvgs[k].state),
                                 DoubleToString(g_fvgs[k].lower, dg), DoubleToString(g_fvgs[k].upper, dg));
      g_panel.Line(H4IrlPanelText(active, g_res.erl_state, zone, inside),
                   active ? clrLimeGreen : clrOrange);
     }
   else
      g_panel.Line("nearest IRL: none selectable (no active setup)", clrSilver);
   if(g_life.hist_text != "")
      g_panel.Line(g_life.hist_text, g_life.hist_state == H4_HIST_COMPLETE ? clrSilver : clrOrange);

   int fresh = 0, touched = 0, invalid = 0, irl = 0, outside = 0;
   for(int i = 0; i < g_nf; i++)
     {
      if(g_fvgs[i].state == H4_FVG_FRESH)
         fresh++;
      else
         if(g_fvgs[i].state == H4_FVG_TOUCHED)
            touched++;
         else
            invalid++;
      if(g_fvgs[i].cls == H4_CLS_IRL)
         irl++;
      else
         if(g_fvgs[i].cls == H4_CLS_OUTSIDE)
            outside++;
     }
   g_panel.Line(StringFormat("swings %d (ambiguous %d)  FVG %d: fresh %d touched %d invalid %d | IRL cand. %d outside %d selectable %d",
                             g_ns, g_res.ambiguous, g_nf, fresh, touched, invalid, irl, outside, g_sel),
                clrSilver);
   g_panel.End();
  }
//+------------------------------------------------------------------+
