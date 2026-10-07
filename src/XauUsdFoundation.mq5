//+------------------------------------------------------------------+
//|                                        XauUsdFoundation.mq5      |
//|                                                                  |
//|  Submission XAU-20261006-E27N93 - task T001 (foundation).        |
//|                                                                  |
//|  What this build does:                                           |
//|    - resolves the working symbol and reads its broker spec       |
//|    - keeps H4, H1 and M15 series under observation               |
//|    - reports history readiness truthfully while data loads       |
//|    - separates the FORMING bar from the last CLOSED bar          |
//|    - fires one new-bar event per timeframe per new bar           |
//|    - logs only when the status changes, and draws a chart panel  |
//|                                                                  |
//|  What this build deliberately does NOT do:                       |
//|    - no OrderSend / OrderSendAsync, no CTrade, no Trade library  |
//|    - no position or order modification of any kind               |
//|    - no strategy decision: direction, FVG, MSS, risk and exit    |
//|      rules are still open (docs/OPEN_QUESTIONS.md Q01-Q12)       |
//+------------------------------------------------------------------+
//--- MetaEditor parses #property version as "major.minor" and expects a
//--- major of at least 1, so the T001 stage is recorded in the description
//--- instead of in the version string. The empty #property link is dropped
//--- for the same reason: an empty value is not a valid property value.
#property copyright   "velireci"
#property version     "1.00"
#property description "T001 foundation (stage 1 of the XAUUSD robot): symbol and H4/H1/M15 data readiness only."
#property description "Contains no order functions and no strategy logic."

#include "include/SymbolSnapshot.mqh"
#include "include/TimeframeWatcher.mqh"
#include "include/StatusPanel.mqh"

//--- The panel grows downwards from its corner, so only the upper two
//--- corners lay out correctly. The lower ones are deliberately not offered.
enum ENUM_PANEL_CORNER
  {
   PANEL_TOP_LEFT  = 0,  // Top left
   PANEL_TOP_RIGHT = 1   // Top right
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "Identity"
input long             InpMagicNumber   = 20261006;            // Magic number (reserved for later stages, unused here)
input string           InpSymbolName    = "";                  // Symbol ("" = chart symbol; client named XAUUSD.r)
input string           InpSymbolHint    = "XAUUSD";            // Informational name check only (no trading effect)

input group "History requirements"
input int              InpMinBarsH4     = 200;                 // Minimum H4 bars before H4 counts as ready
input int              InpMinBarsH1     = 300;                 // Minimum H1 bars before H1 counts as ready
input int              InpMinBarsM15    = 500;                 // Minimum M15 bars before M15 counts as ready

input group "Diagnostics"
input bool             InpShowPanel     = true;                // Draw the status panel on the chart
input ENUM_PANEL_CORNER InpPanelCorner  = PANEL_TOP_LEFT;       // Panel corner
input bool             InpLogNewBars    = true;                // Log each new bar per timeframe
input int              InpPollSeconds   = 1;                   // Timer poll interval in seconds

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
#define TF_COUNT 3

string            g_symbol    = "";
SSymbolSnapshot   g_snapshot;
CTimeframeWatcher g_watchers[TF_COUNT];
CStatusPanel      g_panel;

string            g_last_status_signature = "";
bool              g_last_all_ready        = false;
bool              g_last_connected        = true;
bool              g_timer_active          = false;
uint              g_last_panel_paint      = 0;
bool              g_panel_painted         = false;

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
void PollStatus(void);
void RenderPanel(const bool all_ready, const bool force);

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string DeinitReasonText(const int reason)
  {
   switch(reason)
     {
      case REASON_PROGRAM:     return("EA stopped by itself");
      case REASON_REMOVE:      return("removed from the chart");
      case REASON_RECOMPILE:   return("recompiled");
      case REASON_CHARTCHANGE: return("symbol or period changed");
      case REASON_CHARTCLOSE:  return("chart closed");
      case REASON_PARAMETERS:  return("inputs changed");
      case REASON_ACCOUNT:     return("account changed");
      case REASON_TEMPLATE:    return("template applied");
      case REASON_INITFAILED:  return("OnInit returned an error");
      case REASON_CLOSE:       return("terminal closed");
      default:                 return(StringFormat("reason %d", reason));
     }
  }

bool AllSeriesReady(void)
  {
   for(int i = 0; i < TF_COUNT; i++)
      if(!g_watchers[i].IsReady())
         return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   g_last_status_signature = "";
   g_last_all_ready        = false;
   g_timer_active          = false;
   g_last_panel_paint      = 0;
   g_panel_painted         = false;

   g_symbol = (StringLen(InpSymbolName) > 0 ? InpSymbolName : _Symbol);

   if(!SymbolSnapshotLoad(g_symbol, g_snapshot))
     {
      PrintFormat("T001 INIT FAILED: symbol '%s' unusable - %s", g_symbol, g_snapshot.problem);
      return(INIT_FAILED);
     }

   if(InpMinBarsH4 < 3 || InpMinBarsH1 < 3 || InpMinBarsM15 < 3)
     {
      Print("T001 INIT FAILED: minimum bar inputs must be 3 or more (two bars are read per timeframe).");
      return(INIT_FAILED);
     }
   if(InpPollSeconds < 1)
     {
      Print("T001 INIT FAILED: poll interval must be at least 1 second.");
      return(INIT_FAILED);
     }

   Print("================ T001 foundation ================");
   Print("Build: data and readiness only. NO ORDER FUNCTIONS ARE PRESENT IN THIS EA.");
   PrintFormat("Magic number %s is stored for later stages and is not used by this build.",
               IntegerToString(InpMagicNumber));
   Print(SymbolSnapshotReport(g_snapshot));

   if(StringLen(InpSymbolHint) > 0 && StringFind(g_symbol, InpSymbolHint) < 0)
      PrintFormat("NOTICE: working symbol '%s' does not contain '%s'. Informational only - confirm the chart is the intended one.",
                  g_symbol, InpSymbolHint);
   if(g_snapshot.trade_mode != SYMBOL_TRADE_MODE_FULL)
      PrintFormat("NOTICE: symbol trade mode is %s. Recorded for later stages; this build does not trade.",
                  SymbolTradeModeText(g_snapshot.trade_mode));

   //--- H4 context, H1 context, M15 signal series (client answers: M15 signal, H4 closed context, H1 also used).
   g_watchers[0].Configure(g_symbol, PERIOD_H4,  InpMinBarsH4);
   g_watchers[1].Configure(g_symbol, PERIOD_H1,  InpMinBarsH1);
   g_watchers[2].Configure(g_symbol, PERIOD_M15, InpMinBarsM15);

   g_panel.Init("velo_t001_", InpShowPanel,
                InpPanelCorner == PANEL_TOP_RIGHT ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER);

   g_last_connected = (TerminalInfoInteger(TERMINAL_CONNECTED) != 0);
   if(!g_last_connected)
      Print("NOTICE: terminal is not connected to the server; history cannot be completed yet.");

   if(!EventSetTimer(InpPollSeconds))
      Print("NOTICE: EventSetTimer failed; readiness will only refresh on incoming ticks.");
   else
      g_timer_active = true;

   //--- First poll so the panel and the log show the real state immediately.
   PollStatus();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_timer_active)
     {
      EventKillTimer();
      g_timer_active = false;
     }
   g_panel.Destroy();
   PrintFormat("T001 foundation stopped: %s. No orders were placed, modified or closed.",
               DeinitReasonText(reason));
  }

//+------------------------------------------------------------------+
//| OnTick - diagnostics only, no trading                            |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   PollStatus();
  }

//+------------------------------------------------------------------+
//| OnTimer - keeps readiness honest on a quiet market               |
//+------------------------------------------------------------------+
void OnTimer(void)
  {
   PollStatus();
  }

//+------------------------------------------------------------------+
//| PollStatus                                                       |
//|                                                                  |
//| Refreshes all three series, reports new bars, logs the status    |
//| only when it changes and repaints the panel.                     |
//+------------------------------------------------------------------+
void PollStatus(void)
  {
   bool connected = (TerminalInfoInteger(TERMINAL_CONNECTED) != 0);
   if(connected != g_last_connected)
     {
      PrintFormat("Terminal connection changed: %s", connected ? "CONNECTED" : "DISCONNECTED");
      g_last_connected = connected;
     }

   string signature   = "";
   bool   any_new_bar = false;

   for(int i = 0; i < TF_COUNT; i++)
     {
      bool new_bar = false;
      g_watchers[i].Refresh(new_bar);
      if(new_bar)
         any_new_bar = true;

      if(new_bar && InpLogNewBars)
        {
         MqlRates closed;
         //--- A new bar means the previous one is now final: log that closed bar.
         if(g_watchers[i].GetClosedBar(closed))
            PrintFormat("NEW BAR %s - closed bar %s O=%s H=%s L=%s C=%s V=%d | forming bar now %s%s",
                        g_watchers[i].PeriodName(),
                        TimeToString(closed.time, TIME_DATE|TIME_MINUTES),
                        DoubleToString(closed.open,  g_snapshot.digits),
                        DoubleToString(closed.high,  g_snapshot.digits),
                        DoubleToString(closed.low,   g_snapshot.digits),
                        DoubleToString(closed.close, g_snapshot.digits),
                        (int)closed.tick_volume,
                        TimeToString(g_watchers[i].FormingOpenTime(), TIME_DATE|TIME_MINUTES),
                        g_watchers[i].SkippedBars() > 0
                           ? StringFormat(" | WARNING %d bar(s) closed unobserved", g_watchers[i].SkippedBars())
                           : "");
        }

      //--- State plus the closed-bar time only. The bar count deliberately
      //--- stays out: it climbs on every poll while history downloads, which
      //--- would turn each poll into a STATUS line.
      signature += StringFormat("%s=%s:%d|",
                                g_watchers[i].PeriodName(),
                                g_watchers[i].StateName(),
                                (int)g_watchers[i].ClosedOpenTime());
     }

   bool all_ready = AllSeriesReady();

   //--- Readiness transitions are the events worth a log line.
   bool readiness_changed = (all_ready != g_last_all_ready);
   if(readiness_changed)
     {
      g_last_all_ready = all_ready;
      if(all_ready)
         Print("DATA READY: H4, H1 and M15 all synchronised. Foundation is observing only; no trading logic is wired.");
      else
        {
         Print("DATA NOT READY: at least one timeframe lost readiness. Details below.");
         for(int i = 0; i < TF_COUNT; i++)
            if(!g_watchers[i].IsReady())
               PrintFormat("  %s %s - %s",
                           g_watchers[i].PeriodName(),
                           g_watchers[i].StateName(),
                           g_watchers[i].Detail());
        }
     }

   //--- Status log, but only on a real change (keeps the log free of spam).
   bool signature_changed = (signature != g_last_status_signature);
   if(signature_changed)
     {
      g_last_status_signature = signature;
      if(!all_ready)
         for(int i = 0; i < TF_COUNT; i++)
            if(!g_watchers[i].IsReady())
               PrintFormat("STATUS %s %s - %s",
                           g_watchers[i].PeriodName(),
                           g_watchers[i].StateName(),
                           g_watchers[i].Detail());
     }

   RenderPanel(all_ready, signature_changed || readiness_changed || any_new_bar);
  }

//+------------------------------------------------------------------+
//| RenderPanel                                                      |
//+------------------------------------------------------------------+
void RenderPanel(const bool all_ready, const bool force)
  {
   if(!InpShowPanel)
      return;

   //--- XAUUSD can deliver hundreds of ticks per second. Repaint on a real
   //--- change, otherwise at most twice per second. Unsigned arithmetic makes
   //--- the GetTickCount wrap-around harmless.
   uint now = GetTickCount();
   if(!force && g_panel_painted && (now - g_last_panel_paint) < 500)
      return;
   g_last_panel_paint = now;
   g_panel_painted    = true;

   g_panel.Begin();
   g_panel.Line("T001 FOUNDATION - observing only, no trading", clrSilver);
   g_panel.Line(StringFormat("symbol %s  digits %d  spread %d pts  mode %s",
                             g_symbol, g_snapshot.digits, (int)SymbolInfoInteger(g_symbol, SYMBOL_SPREAD),
                             AccountMarginModeText(g_snapshot.margin_mode)),
                clrSilver);
   g_panel.Line(StringFormat("server time %s   data %s",
                             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                             all_ready ? "READY" : "NOT READY"),
                all_ready ? clrLimeGreen : clrOrange);

   for(int i = 0; i < TF_COUNT; i++)
     {
      bool ready = g_watchers[i].IsReady();
      g_panel.Line(g_watchers[i].StatusLine(g_snapshot.digits),
                   ready ? clrLimeGreen : clrOrange);
     }

   if(all_ready)
     {
      MqlRates m15_forming;
      if(g_watchers[2].GetFormingBar(m15_forming))
         g_panel.Line(StringFormat("M15 forming bar is NOT final: O=%s H=%s L=%s C=%s (still changing)",
                                   DoubleToString(m15_forming.open,  g_snapshot.digits),
                                   DoubleToString(m15_forming.high,  g_snapshot.digits),
                                   DoubleToString(m15_forming.low,   g_snapshot.digits),
                                   DoubleToString(m15_forming.close, g_snapshot.digits)),
                      clrGold);
     }

   g_panel.Line("strategy rules Q01-Q12 still open - no entry logic in this build", clrSilver);
   g_panel.End();
  }
//+------------------------------------------------------------------+
