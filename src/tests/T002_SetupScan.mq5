//+------------------------------------------------------------------+
//|                                          T002_SetupScan.mq5      |
//|                                                                  |
//|  T002 - DIAGNOSTIC SCRIPT. Scans the H4 history of the chart     |
//|  symbol with the EXISTING T002 logic (src/include/H4Structure.   |
//|  mqh, unchanged) and lists moments at which the proposed model   |
//|  would show an ACTIVE setup:                                     |
//|    - direction BULLISH or BEARISH                                |
//|    - structural interval VALID                                   |
//|    - ERL not TAKEN (UNTOUCHED)                                   |
//|    - at least one selectable IRL candidate                       |
//|    - H4SetupActive() is true                                     |
//|                                                                  |
//|  It sends, modifies and closes nothing. It reads only the H4     |
//|  series of the chart symbol. Every rule shown is a PROPOSAL of   |
//|  the T002 model awaiting the client's visual validation; a hit   |
//|  here is not a trading signal and not a client-confirmed setup.  |
//|                                                                  |
//|  How a moment is built (identical to the EA's historical mode):  |
//|    - moment k = the close of closed H4 bar k, so the as-of time  |
//|      is open(k) + 4 h in broker/server time                      |
//|    - only the newest InpLookbackBars closed bars up to bar k are |
//|      analysed (bars after k are never copied into the window)    |
//|    - the price used for the IRL selection is the close of bar k  |
//|      (the last closed bar of that moment); no live price is read |
//|    - the window length, swing parameters and clamps equal those  |
//|      of src/XauUsdH4Map.mq5, so setting that EA's InpAsOfTime to |
//|      the printed time (same Left/Right/Lookback, same symbol,    |
//|      history at least as deep) reproduces the result             |
//|                                                                  |
//|  Consecutive qualifying moments are grouped into runs. The       |
//|  first moment of each run is reported with full detail together  |
//|  with the run length; at most InpMaxReport runs are listed,      |
//|  newest first.                                                   |
//|                                                                  |
//|  This is a SCRIPT (OnStart): it belongs under MQL5/Scripts/, NOT |
//|  under Experts. Copy the whole repository src/ folder to         |
//|    <terminal data folder>/MQL5/Scripts/velo_src/                 |
//|  so that these paths sit side by side:                           |
//|    MQL5/Scripts/velo_src/tests/T002_SetupScan.mq5                |
//|    MQL5/Scripts/velo_src/include/H4Structure.mqh                 |
//|  (the include is relative to this file). See                     |
//|  docs/T002-setup-scan.md. Install layout NOT tested in MT5.      |
//|                                                                  |
//|  Status when written: NOT compiled and NOT run by the author     |
//|  (no MetaEditor available). Compilation and execution evidence   |
//|  must come from whoever compiles and runs it.                    |
//+------------------------------------------------------------------+
#property copyright "velireci"
#property version   "1.00"
#property description "T002 diagnostic: scans H4 history for moments with an active proposed setup. Read-only."
#property script_show_inputs

#include "../include/H4Structure.mqh"

input int InpLeftBars     = 2;      // Swing: closed bars on the left (1..10), as in the EA
input int InpRightBars    = 2;      // Swing: closed bars on the right (1..10), as in the EA
input int InpLookbackBars = 300;    // Closed H4 bars per window (clamped 50..1000), as in the EA
input int InpScanBars     = 2000;   // Newest closed H4 bars to use as evaluation moments (clamped 1..20000)
input int InpMaxReport    = 5;      // Runs to report, newest first (clamped 1..50)

//--- One run of consecutive qualifying moments; details of its first moment.
struct SScanRun
  {
   datetime          asof;          // as-of time of the first moment (server time)
   datetime          last_open;     // open time of the last closed bar of that moment
   int               direction;     // H4_DIR_*
   double            range_high;
   double            range_low;
   datetime          range_known;
   double            erl_price;
   int               erl_state;     // H4_ERL_*
   int               selectable;    // number of selectable IRL candidates
   string            irl_id;        // nearest selectable candidate
   double            irl_lower;
   double            irl_upper;
   int               irl_state;     // H4_FVG_*
   bool              irl_inside;    // price inside that zone
   double            price;         // close of the last closed bar of that moment
   string            evidence;      // why the direction is what it is
   int               length;        // consecutive qualifying moments in this run
   datetime          last_asof;     // as-of time of the last moment of the run
  };

//+------------------------------------------------------------------+
string StampText(const datetime t)
  {
   return(TimeToString(t, TIME_DATE|TIME_MINUTES|TIME_SECONDS));
  }

//+------------------------------------------------------------------+
void OnStart(void)
  {
   int left     = MathMax(1, MathMin(10, InpLeftBars));
   int right    = MathMax(1, MathMin(10, InpRightBars));
   int lookback = MathMax(50, MathMin(1000, InpLookbackBars));
   int scan     = MathMax(1, MathMin(20000, InpScanBars));
   int maxrep   = MathMax(1, MathMin(50, InpMaxReport));
   if(left != InpLeftBars || right != InpRightBars || lookback != InpLookbackBars)
      PrintFormat("T002 SCAN NOTICE: inputs clamped to Left=%d Right=%d Lookback=%d (same clamps as the EA)",
                  left, right, lookback);

   string sym      = _Symbol;
   int    period_s = PeriodSeconds(PERIOD_H4);
   int    digits   = _Digits;

   Print("================ T002 SETUP SCAN (diagnostic, read-only) ================");
   Print("All rules are PROPOSED (client validation pending). No order function is used.");
   PrintFormat("Symbol %s | H4 | Left=%d Right=%d Lookback=%d | scan up to %d moments | report up to %d runs",
               sym, left, right, lookback, scan, maxrep);

   //--- closed bars only: start position 1 skips the forming bar; index 0 = oldest
   int want = scan + lookback - 1;
   MqlRates all[];
   ArraySetAsSeries(all, false);
   int got = CopyRates(sym, PERIOD_H4, 1, want, all);
   if(got <= 0)
     {
      PrintFormat("T002 SCAN RESULT: NO RESULT. CopyRates returned %d (error %d). The H4 history may still be loading: open an H4 chart of %s, wait, and run again.",
                  got, GetLastError(), sym);
      ResetLastError();
      return;
     }
   for(int i = 1; i < got; i++)
      if(all[i].time <= all[i - 1].time)
        {
         PrintFormat("T002 SCAN RESULT: NO RESULT. The copied bars are not strictly ascending in time at index %d; treated as a failed copy.", i);
         return;
        }
   PrintFormat("History: %d closed H4 bars copied (requested %d), from %s to %s (open times, server time)",
               got, want, StampText(all[0].time), StampText(all[got - 1].time));
   if(got < want)
      PrintFormat("NOTE: the history is shorter than requested. Only the bars available are scanned; run again after more history has loaded if you need earlier moments.");
   if(got < lookback)
     {
      PrintFormat("T002 SCAN RESULT: ZERO moments evaluated. Only %d closed H4 bars are available and one window needs %d. Searched nothing.",
                  got, lookback);
      return;
     }

   MqlRates        win[];
   SH4Swing        swings[];
   SH4Fvg          fvgs[];
   int             order[];
   SH4Result       res;
   SH4DirEvidence  ev;
   SScanRun        runs[];
   int             nruns = 0;

   int  moments = 0, guard_fail = 0;
   int  c_dir = 0, c_rng = 0, c_erl = 0, c_sel = 0, c_act = 0;
   bool prev_hit = false;
   datetime first_asof = 0, last_asof_all = 0;

   for(int k = lookback - 1; k < got; k++)
     {
      //--- the window holds bars up to k only: bars after k never enter the analysis
      ArrayCopy(win, all, 0, k - lookback + 1, lookback);
      datetime asof = win[lookback - 1].time + (datetime)period_s;
      if(H4ClosedCountAsOf(win, lookback, asof, period_s) != lookback)
        {
         guard_fail++;
         prev_hit = false;
         continue;
        }
      moments++;
      if(first_asof == 0)
         first_asof = asof;
      last_asof_all = asof;

      int ns = 0, nf = 0;
      H4Analyze(win, lookback, left, right, period_s, swings, ns, fvgs, nf, res);
      double price = win[lookback - 1].close;

      bool trending = (res.direction == H4_DIR_BULLISH || res.direction == H4_DIR_BEARISH);
      bool rng_ok   = (trending && res.range_state == H4_RNG_VALID);
      bool erl_ok   = (rng_ok && res.erl_state == H4_ERL_UNTOUCHED);
      int  sel      = H4SelectIrl(fvgs, nf, res, price, order);
      bool sel_ok   = (erl_ok && sel > 0);
      bool active   = (sel_ok && H4SetupActive(res, sel));

      if(trending)
         c_dir++;
      if(rng_ok)
         c_rng++;
      if(erl_ok)
         c_erl++;
      if(sel_ok)
         c_sel++;
      if(active)
         c_act++;

      if(active)
        {
         if(prev_hit && nruns > 0)
           {
            runs[nruns - 1].length++;
            runs[nruns - 1].last_asof = asof;
           }
         else
           {
            ArrayResize(runs, nruns + 1);
            int z = order[0];
            H4DirectionEvidence(swings, ns, digits, ev);
            runs[nruns].asof        = asof;
            runs[nruns].last_open   = win[lookback - 1].time;
            runs[nruns].direction   = res.direction;
            runs[nruns].range_high  = res.range_high;
            runs[nruns].range_low   = res.range_low;
            runs[nruns].range_known = res.range_known_time;
            runs[nruns].erl_price   = res.erl_price;
            runs[nruns].erl_state   = res.erl_state;
            runs[nruns].selectable  = sel;
            runs[nruns].irl_id      = fvgs[z].id;
            runs[nruns].irl_lower   = fvgs[z].lower;
            runs[nruns].irl_upper   = fvgs[z].upper;
            runs[nruns].irl_state   = fvgs[z].state;
            runs[nruns].irl_inside  = H4PriceInsideZone(fvgs[z], price);
            runs[nruns].price       = price;
            runs[nruns].evidence    = ev.verdict;
            runs[nruns].length      = 1;
            runs[nruns].last_asof   = asof;
            nruns++;
           }
        }
      prev_hit = active;
     }

   PrintFormat("Searched %d moments (as-of %s to %s, server time); %d skipped by the as-of guard.",
               moments, StampText(first_asof), StampText(last_asof_all), guard_fail);
   PrintFormat("Funnel (cumulative): trending direction %d | + valid interval %d | + ERL not TAKEN %d | + selectable IRL %d | + H4SetupActive %d",
               c_dir, c_rng, c_erl, c_sel, c_act);

   if(nruns == 0)
     {
      PrintFormat("T002 SCAN RESULT: ZERO moments found. No moment among the %d searched met all conditions (trending direction, valid interval, ERL not TAKEN, selectable IRL candidate, H4SetupActive). See the funnel above for where moments dropped out.",
                  moments);
      return;
     }

   PrintFormat("T002 SCAN RESULT: %d qualifying moments in %d run(s). Listing up to %d run(s), newest first; each line is the FIRST moment of a run.",
               c_act, nruns, maxrep);
   int shown = 0;
   for(int r = nruns - 1; r >= 0 && shown < maxrep; r--)
     {
      shown++;
      PrintFormat("MOMENT %d/%d  AsOfTime (server time) = %s  | last closed H4 bar opened %s | price used (close of that bar) = %s",
                  shown, nruns, StampText(runs[r].asof), StampText(runs[r].last_open),
                  DoubleToString(runs[r].price, digits));
      PrintFormat("   direction %s | interval H %s  L %s (known from %s) | ERL %s %s",
                  H4DirName(runs[r].direction),
                  DoubleToString(runs[r].range_high, digits), DoubleToString(runs[r].range_low, digits),
                  StampText(runs[r].range_known),
                  DoubleToString(runs[r].erl_price, digits), H4ErlName(runs[r].erl_state));
      PrintFormat("   selectable IRL %d | nearest %s %s [%s - %s] %s | H4SetupActive true",
                  runs[r].selectable, runs[r].irl_id, H4FvgStateName(runs[r].irl_state),
                  DoubleToString(runs[r].irl_lower, digits), DoubleToString(runs[r].irl_upper, digits),
                  runs[r].irl_inside ? "price INSIDE" : "ahead of price");
      PrintFormat("   direction evidence: %s", runs[r].evidence);
      PrintFormat("   run: %d consecutive H4 moment(s), the last at %s",
                  runs[r].length, StampText(runs[r].last_asof));
      PrintFormat("   reproduce in the EA: InpAsOfTime = %s (broker/server time), InpLeftBars=%d, InpRightBars=%d, InpLookbackBars=%d, symbol %s",
                  StampText(runs[r].asof), left, right, lookback, sym);
     }
   PrintFormat("T002 SETUP SCAN finished. Read-only; nothing was sent, modified or closed.");
  }
//+------------------------------------------------------------------+
