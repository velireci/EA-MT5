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
#define RETRY_MS          3000   // throttle for history re-checks and failed rebuilds
#define HIST_MAX_NOPROG   20     // consecutive re-checks without new history, then stop (~60 s)

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
bool              g_have_map = false;
datetime          g_map_last_closed = 0;
uint              g_last_refresh    = 0;
bool              g_refreshed_once  = false;
bool              g_timer_active    = false;
double            g_price    = 0.0;

//--- history / map-lifecycle state
int               g_hist_state     = H4_HIST_COMPLETE;
int               g_hist_got       = 0;       // closed bars of the last CopyRates attempt
datetime          g_hist_oldest    = 0;       // oldest bar of the last CopyRates attempt
int               g_hist_noprog    = 0;       // consecutive re-checks without more history
bool              g_hist_exhausted = false;   // server has no more history (until next H4 bar)
uint              g_last_try       = 0;       // GetTickCount of the last (re)build attempt
bool              g_tried_once     = false;
string            g_hist_text      = "";      // shown in the panel, logged once per change
string            g_cleared_reason = "";      // non-empty after a clear, until rebuilt

void Poll(void);
bool RecomputeMap(void);
void RefreshPrice(const bool force);
void RenderPanel(void);
void ClearMapState(const string reason);
void SetHistoryStatus(const int state, const int got);
bool HistoryProbe(void);

//+------------------------------------------------------------------+
int OnInit(void)
  {
   g_have_map = false;
   g_refreshed_once = false;
   g_timer_active = false;
   g_n = g_ns = g_nf = g_sel = 0;
   g_map_last_closed = 0;
   g_price = 0.0;
   g_hist_state = H4_HIST_COMPLETE;
   g_hist_got = 0;
   g_hist_oldest = 0;
   g_hist_noprog = 0;
   g_hist_exhausted = false;
   g_last_try = 0;
   g_tried_once = false;
   g_hist_text = "";
   g_cleared_reason = "";
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
//| Poll: H4 logic only on init, a new H4 bar, or a throttled retry; |
//| price part <= 1 Hz. No Sleep, no loops: every re-check is one    |
//| CopyRates call at most every RETRY_MS.                           |
//+------------------------------------------------------------------+
void Poll(void)
  {
   bool new_bar = false;
   g_h4.Refresh(new_bar);
   if(!g_h4.IsReady())
     {
      //--- never leave the old map on the chart looking current
      ClearMapState("H4 series not ready: " + g_h4.StateName());
      g_hist_noprog = 0;
      g_hist_exhausted = false;   // retry after recovery
      RenderPanel();
      return;
     }
   uint now = GetTickCount();
   bool recomputed = false;
   if(new_bar)
     {
      //--- a new closed bar starts a fresh history assessment
      g_hist_noprog = 0;
      g_hist_exhausted = false;
      g_last_try = now;
      g_tried_once = true;
      recomputed = RecomputeMap();
     }
   else
      if(!g_tried_once)
        {
         g_last_try = now;
         g_tried_once = true;
         recomputed = RecomputeMap();
        }
      else
         if((now - g_last_try) >= RETRY_MS)
           {
            if(!g_have_map && !g_hist_exhausted)
              {
               //--- no map (history catching up / failed copy): throttled retry
               g_last_try = now;
               recomputed = RecomputeMap();
              }
            else
               if(g_have_map && H4RefreshDue(g_hist_state, g_hist_noprog, HIST_MAX_NOPROG))
                 {
                  //--- map built on partial history: rebuild only when more arrived
                  g_last_try = now;
                  recomputed = HistoryProbe();
                 }
           }
   RefreshPrice(recomputed);
  }

//+------------------------------------------------------------------+
//| ClearMapState: remove every map drawing and disable the dynamic  |
//| state. Logs once per transition (visible without the panel).     |
//+------------------------------------------------------------------+
void ClearMapState(const string reason)
  {
   bool had = g_have_map;
   g_have_map = false;
   g_sel = 0;
   g_n = g_ns = g_nf = 0;
   g_map_last_closed = 0;
   ArrayResize(g_order, 0);
   ZeroMemory(g_res);
   if(H4MapTransition(had, false) == H4_ACT_CLEAR)
     {
      g_drawer.Reset();       // swings, FVG, labels, ERL, range lines, link; panel stays
      g_cleared_reason = reason;
      PrintFormat("H4 MAP cleared: %s", reason);
     }
  }

//+------------------------------------------------------------------+
//| History status: panel text, logged once per change               |
//+------------------------------------------------------------------+
void SetHistoryStatus(const int state, const int got)
  {
   bool refreshing = H4RefreshDue(state, g_hist_noprog, HIST_MAX_NOPROG);
   string t = H4HistoryText(state, got, g_lookback, refreshing);
   g_hist_state = state;
   g_hist_got = got;
   if(t != g_hist_text)
     {
      g_hist_text = t;
      PrintFormat("H4 history: %s", t);
     }
  }

//+------------------------------------------------------------------+
//| HistoryProbe: re-copy and rebuild only if more history arrived   |
//| (more bars, or an older first bar). Gives up after               |
//| HIST_MAX_NOPROG consecutive checks without progress: that is the |
//| "server has no more history" detection.                          |
//+------------------------------------------------------------------+
bool HistoryProbe(void)
  {
   MqlRates probe[];
   ArraySetAsSeries(probe, false);
   int got = CopyRates(g_symbol, PERIOD_H4, 1, g_lookback, probe);
   if(got > 0 && H4HistoryImproved(g_hist_got, g_hist_oldest, got, probe[0].time))
     {
      g_hist_noprog = 0;
      return(RecomputeMap());
     }
   ResetLastError();
   g_hist_noprog++;
   SetHistoryStatus(g_hist_state, g_hist_got);   // refreshing -> "no more on server" when capped
   return(false);
  }

//+------------------------------------------------------------------+
//| RecomputeMap: copy CLOSED bars (shift 1 = skip the forming bar)  |
//+------------------------------------------------------------------+
bool RecomputeMap(void)
  {
   ArraySetAsSeries(g_bars, false);          // index 0 = oldest
   int got = CopyRates(g_symbol, PERIOD_H4, 1, g_lookback, g_bars);
   if(got <= 0)
     {
      ResetLastError();
      ClearMapState("CopyRates returned no closed H4 bars");
      return(false);
     }
   int hs = H4HistoryState(got, g_lookback, g_left, g_right);
   if(hs != H4_HIST_COMPLETE)
     {
      //--- progress bookkeeping for the throttled re-check
      if(g_hist_got == 0 || H4HistoryImproved(g_hist_got, g_hist_oldest, got, g_bars[0].time))
         g_hist_noprog = 0;
      else
         g_hist_noprog++;
      g_hist_exhausted = !H4RefreshDue(hs, g_hist_noprog, HIST_MAX_NOPROG);
     }
   g_hist_oldest = g_bars[0].time;
   SetHistoryStatus(hs, got);
   if(hs == H4_HIST_INSUFFICIENT)
     {
      ClearMapState(g_hist_text);
      return(false);
     }
   //--- the newest copied bar must be the closed bar the watcher reports,
   //--- otherwise the history is still catching up: retry (throttled)
   if(g_h4.ClosedOpenTime() != 0 && g_bars[got - 1].time != g_h4.ClosedOpenTime())
     {
      ClearMapState("newest copied bar does not match the watcher (history catching up)");
      return(false);
     }
   g_n = got;
   H4Analyze(g_bars, g_n, g_left, g_right, PeriodSeconds(PERIOD_H4),
             g_swings, g_ns, g_fvgs, g_nf, g_res);
   g_map_last_closed = g_bars[g_n - 1].time;
   g_drawer.DrawStatic(g_bars, g_n, PeriodSeconds(PERIOD_H4), g_swings, g_ns,
                       g_fvgs, g_nf, g_res, InpShowInvalid);
   int act = H4MapTransition(g_have_map, true);
   g_have_map = true;
   if(act == H4_ACT_REBUILT && g_cleared_reason != "")
     {
      PrintFormat("H4 MAP rebuilt (was cleared: %s)", g_cleared_reason);
      g_cleared_reason = "";
     }
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
   if(!g_have_map)
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
   if(!g_h4.IsReady() || !g_have_map)
     {
      g_panel.Line(StringFormat("H4 data: %s - %s", g_h4.StateName(), g_h4.Detail()), clrOrange);
      g_panel.Line(g_have_map ? "map: shown" : "map: CLEARED (no map is drawn)", clrOrange);
      if(g_hist_text != "")
         g_panel.Line(g_hist_text, clrOrange);
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
   if(g_hist_text != "")
      g_panel.Line(g_hist_text, g_hist_state == H4_HIST_COMPLETE ? clrSilver : clrOrange);

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
