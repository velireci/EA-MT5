//+------------------------------------------------------------------+
//| H4BiasLayers.mqh                                                 |
//|                                                                  |
//| T003 visual layers - PURE helpers (no chart object, no series    |
//| access, no clock, no trading API). They READ the closed-bar      |
//| window, the T002 swings and the replay events that the caller    |
//| already holds, and WRITE only into their own output arguments.   |
//| They never touch SH3State / SH3Eval and never call the T003      |
//| logic: nothing here can change the bias (H4Bias.mqh).            |
//|                                                                  |
//| EVERYTHING HERE IS A PROPOSAL / PROTOTYPE (tasks/T003-h4-bias-   |
//| change.md), awaiting the client:                                 |
//|  1. MODEL DISAGREEMENT between the T002 direction and the T003   |
//|     bias. Definition (technical proposal): it exists ONLY when   |
//|     the T002 direction is BULLISH (HH+HL) and the T003 bias is   |
//|     BEAR, or the T002 direction is BEARISH (LH+LL) and the T003  |
//|     bias is BULL. T002 MIXED / UNKNOWN, or no T003 bias (NONE),  |
//|     is NOT a disagreement.                                       |
//|  2. HISTORICAL LIQUIDITY (N2): confirmed 2/2 swing highs / lows  |
//|     that no later closed bar has exceeded by a WICK (high above  |
//|     a swing high / low below a swing low, strictly). The client  |
//|     confirmed the CONCEPT of historical liquidity (N2), NOT this |
//|     algorithm: fractal 2/2 and the mechanical definition are     |
//|     proposals. NOT an ERL, NOT a target, NOT a protecting level, |
//|     never used by the bias.                                      |
//|                                                                  |
//|  3. T002 BASELINE (lookback N). The MODEL DISAGREEMENT is stated |
//|     in terms of the T002 BASELINE: the T002 direction computed   |
//|     from the LAST N closed bars (N = InpLookbackBars, the T002   |
//|     EA's window; 2/2 swings, H4DeriveDirection). The direction   |
//|     of the whole replay window is a DIFFERENT thing and is named |
//|     'replay-window structure'; it can differ from the baseline.  |
//|  4. Panel line budget, wrapping, label slot, export key/hash and |
//|     the since-baseline counters: pure text/number helpers.       |
//|                                                                  |
//| Mirrored run: src/tests/T003_LayersTest.mq5 (MQL5 script) and    |
//| tools/t003-xlate-check.sh (C++ transliteration, NOT MetaEditor). |
//| Not compiled with MetaEditor, not run in MT5.                    |
//+------------------------------------------------------------------+
#ifndef VELO_H4_BIAS_LAYERS_MQH
#define VELO_H4_BIAS_LAYERS_MQH

#include "H4Bias.mqh"

//--- result of the disagreement scan (derived from the replay by ABSOLUTE bar times; no future information)
struct SH3LRun
  {
   bool              active;       // MODEL DISAGREEMENT at the last examined closed bar
   datetime          since;       // open time of the first bar of the current disagreement run
   int               bars;        // closed bars in the run (including the last one)
   bool              exact;       // false: the run reaches the first trusted bar ("or earlier")
   int               t2dir;       // H4_DIR_* of T002 at the last bar
   int               bias;        // H3_BULL / H3_BEAR / H3_NONE at the last bar (from the events)
   int               lookback;    // > 0: t2dir is the T002 BASELINE of the last `lookback` bars; 0: replay-window structure
  };

void H3LRunInit(SH3LRun &r)
  {
   r.active = false;
   r.since  = 0;
   r.bars   = 0;
   r.exact  = true;
   r.t2dir  = H4_DIR_UNKNOWN;
   r.bias   = H3_NONE;
   r.lookback = 0;
  }

string H3LTime(const datetime t)
  {
   if(t <= 0)
      return("-");
   return(TimeToString(t, TIME_DATE | TIME_MINUTES));
  }

//--- the client's words for a T002 direction (N1): rising = HH and HL, falling = LH and LL
string H3LStructureWords(const int t2dir)
  {
   if(t2dir == H4_DIR_BULLISH)
      return("HH+HL");
   if(t2dir == H4_DIR_BEARISH)
      return("LH+LL");
   if(t2dir == H4_DIR_MIXED)
      return("neither HH+HL nor LH+LL");
   return("fewer than two highs or two lows known");
  }

//--- MODEL DISAGREEMENT (technical proposal, see the header): only a BULLISH / BEARISH T002 direction against
//--- the OPPOSITE T003 bias. MIXED, UNKNOWN and "no bias" never count.
bool H3LDisagree(const int t2dir, const int bias)
  {
   if(t2dir == H4_DIR_BULLISH && bias == H3_BEAR)
      return(true);
   if(t2dir == H4_DIR_BEARISH && bias == H3_BULL)
      return(true);
   return(false);
  }

//--- the T003 bias after the close of the bar that opens at bar_open, rebuilt from the bias-setting events of
//--- the replay (BREAK_SET, SEED, FLIP carry dir=...); events are in chronological order. H3_NONE before the
//--- first one. No event after bar_open is read.
int H3LBiasAtBar(const SH3Event &events[], const int ne, const datetime bar_open)
  {
   int bias = H3_NONE;
   for(int i = 0; i < ne; i++)
     {
      if(events[i].bar_time > bar_open)
         break;
      int ty = events[i].type;
      if(ty != H3_EV_BREAK_SET && ty != H3_EV_SEED && ty != H3_EV_FLIP)
         continue;
      if(StringFind(events[i].detail, "dir=BULL") == 0)
         bias = H3_BULL;
      else
         if(StringFind(events[i].detail, "dir=BEAR") == 0)
            bias = H3_BEAR;
     }
   return(bias);
  }

//--- the disagreement run that ends at the LAST bar of win[0..nw-1] (the replay window): since-when and for how
//--- many closed bars. Only bars from index `warm` on (the trusted region) are claimed; a run that reaches it is
//--- reported with exact = false. T002 at bar t uses only swings confirmed by the close of bar t.
void H3LDisagreeRun(const MqlRates &win[], const int nw, const SH4Swing &sw[], const int ns, const int right,
                    const int warm, const SH3Event &events[], const int ne, SH3LRun &r)
  {
   H3LRunInit(r);
   if(nw < 1)
      return;
   int last = nw - 1;
   r.t2dir = H4DeriveDirection(sw, H3KnownCount(sw, ns, right, last));
   r.bias  = H3LBiasAtBar(events, ne, win[last].time);
   if(!H3LDisagree(r.t2dir, r.bias))
      return;
   int stop = (warm < last ? warm : last);
   r.active = true;
   r.bars   = 1;
   r.since  = win[last].time;
   bool ended = false;
   for(int t = last - 1; t >= stop; t--)
     {
      int d2 = H4DeriveDirection(sw, H3KnownCount(sw, ns, right, t));
      int b2 = H3LBiasAtBar(events, ne, win[t].time);
      if(!H3LDisagree(d2, b2))
        {
         ended = true;
         break;
        }
      r.bars++;
      r.since = win[t].time;
     }
   r.exact = ended;
  }

//--- T002 BASELINE window (technical proposal): the last min(lookback, n_end) bars of win[0..n_end-1], exactly the
//--- bars the T002 EA (XauUsdH4Map.mq5) analyses: it copies the `lookback` most recent CLOSED bars, finds the 2/2
//--- swings in them and derives the direction from the last two highs and lows (H4Analyze = H4FindSwings +
//--- H4DeriveDirection). Returns the number of bars used (fewer than lookback only when fewer exist).
int H3LBaselineBars(const int n_end, const int lookback)
  {
   if(n_end < 1 || lookback < 1)
      return(0);
   return(n_end < lookback ? n_end : lookback);
  }

//--- the T002 direction of that window (nbars = bars used). Same functions and inputs as the T002 EA.
int H3LBaselineDir(const MqlRates &win[], const int n_end, const int lookback, const int left, const int right,
                   const int period, int &nbars)
  {
   nbars = H3LBaselineBars(n_end, lookback);
   if(nbars < 1 || left < 1 || right < 1)
      return(H4_DIR_UNKNOWN);
   int start = n_end - nbars;
   MqlRates seg[];
   ArrayResize(seg, nbars);
   ArrayCopy(seg, win, 0, start, nbars);
   SH4Swing sw[];
   int amb = 0;
   int ns = H4FindSwings(seg, nbars, left, right, period, sw, amb);
   return(H4DeriveDirection(sw, ns));
  }

//--- MODEL DISAGREEMENT run in terms of the T002 BASELINE: at every examined bar t the baseline is the T002
//--- direction of the `lookback` closed bars that end at t (what the T002 EA would show with that last bar), against
//--- the T003 bias after the close of t. Only bars from index `warm` on are claimed (exact = false when the run
//--- reaches it). Nothing after the last bar is read.
void H3LDisagreeRunBase(const MqlRates &win[], const int nw, const int lookback, const int left, const int right,
                        const int period, const int warm, const SH3Event &events[], const int ne, SH3LRun &r)
  {
   H3LRunInit(r);
   r.lookback = lookback;
   if(nw < 1)
      return;
   int last = nw - 1;
   int nb = 0;
   r.t2dir = H3LBaselineDir(win, nw, lookback, left, right, period, nb);
   r.bias  = H3LBiasAtBar(events, ne, win[last].time);
   if(!H3LDisagree(r.t2dir, r.bias))
      return;
   int stop = (warm < last ? warm : last);
   r.active = true;
   r.bars   = 1;
   r.since  = win[last].time;
   bool ended = false;
   for(int t = last - 1; t >= stop; t--)
     {
      int d2 = H3LBaselineDir(win, t + 1, lookback, left, right, period, nb);
      int b2 = H3LBiasAtBar(events, ne, win[t].time);
      if(!H3LDisagree(d2, b2))
        {
         ended = true;
         break;
        }
      r.bars++;
      r.since = win[t].time;
     }
   r.exact = ended;
  }

//--- the name of the T002 direction source in a text: the baseline (with its lookback) or the replay window
string H3LT2Name(const int lookback)
  {
   if(lookback > 0)
      return("T002 baseline (lookback " + IntegerToString(lookback) + ")");
   return("T002 replay-window structure");
  }

string H3LDisagreeText(const SH3LRun &r, const int period)
  {
   if(!r.active)
      return("");
   string s = "MODEL DISAGREEMENT - client validation pending: T002 " +
              (r.lookback > 0 ? "baseline (lookback " + IntegerToString(r.lookback) + ") " : "replay-window structure ") +
              H4DirName(r.t2dir) + " (" +
              H3LStructureWords(r.t2dir) + ") vs T003 prototype bias " + H3DirName(r.bias) + ", since closed bar " +
              H3LTime(r.since) + " (known " + H3LTime(r.since + (datetime)period) + "), " + IntegerToString(r.bars) +
              " closed bar(s)";
   if(!r.exact)
      s += " (or earlier: the run reaches the start of the trusted bars)";
   return(s);
  }

//--- the SHORT chart text of the disagreement (the full text is the object tooltip and the Experts line)
string H3LDisagreeShort(const SH3LRun &r)
  {
   if(!r.active)
      return("");
   return("MODEL DISAGREEMENT: " + (r.lookback > 0 ? "baseline " : "replay-window ") + H4DirName(r.t2dir) + " vs T003 " +
          H3DirName(r.bias) + ", " + IntegerToString(r.bars) + (r.exact ? "" : "+") + " bars");
  }

//--- the key that decides when the disagreement is logged: once per change (the bar count is NOT part of it).
//--- An inexact run has no fixed start, so its start is left out.
string H3LDisagreeKey(const SH3LRun &r)
  {
   if(!r.active)
      return("NONE");
   return(H4DirName(r.t2dir) + "|" + H3DirName(r.bias) + "|" + (r.exact ? H3Tx(r.since) : "earlier"));
  }

//--- the two latest known swing highs and lows used by H4DeriveDirection (T002): window swing indexes, -1 when
//--- absent. h2 / l2 = the latest, h1 / l1 = the one before. Returns how many of the four exist.
int H3LT2Sources(const SH4Swing &sw[], const int nk, int &h2i, int &h1i, int &l2i, int &l1i)
  {
   h2i = -1;
   h1i = -1;
   l2i = -1;
   l1i = -1;
   for(int i = nk - 1; i >= 0; i--)
     {
      if(sw[i].is_high)
        {
         if(h2i < 0)
            h2i = i;
         else
            if(h1i < 0)
               h1i = i;
        }
      else
        {
         if(l2i < 0)
            l2i = i;
         else
            if(l1i < 0)
               l1i = i;
        }
     }
   int c = 0;
   if(h2i >= 0)
      c++;
   if(h1i >= 0)
      c++;
   if(l2i >= 0)
      c++;
   if(l1i >= 0)
      c++;
   return(c);
  }

//--- HISTORICAL LIQUIDITY (proposal): the confirmed swings (confirmed by the close of the last bar) that no LATER
//--- closed bar has exceeded by a wick: high > swing high for a swing high, low < swing low for a swing low
//--- (strict: an equal value is a touch, not an exceed). Closed bars of the window only; no live price.
//--- Selection: the maxn swings NEAREST to the close of the last closed bar (ties: the more recent pivot).
//--- sel[] receives window swing indexes, nearest first; total = all unexceeded swings. Returns the selected count.
//--- Read-only: nothing here can reach the bias.
int H3LLiquidity(const MqlRates &win[], const int nw, const SH4Swing &sw[], const int ns, const int right,
                 const int maxn, int &sel[], int &total)
  {
   ArrayResize(sel, 0);
   total = 0;
   if(nw < 1 || maxn < 0)
      return(0);
   int nk = H3KnownCount(sw, ns, right, nw - 1);
   int cand[];
   int nc = 0;
   for(int i = 0; i < nk; i++)
     {
      bool exceeded = false;
      for(int j = sw[i].index + 1; j < nw; j++)
        {
         if(sw[i].is_high)
           {
            if(win[j].high > sw[i].price)
              {
               exceeded = true;
               break;
              }
           }
         else
           {
            if(win[j].low < sw[i].price)
              {
               exceeded = true;
               break;
              }
           }
        }
      if(exceeded)
         continue;
      ArrayResize(cand, nc + 1, 64);
      cand[nc] = i;
      nc++;
     }
   total = nc;
   int want = (maxn < nc ? maxn : nc);
   if(want <= 0)
      return(0);
   bool used[];
   ArrayResize(used, nc);
   for(int u = 0; u < nc; u++)
      used[u] = false;
   double ref = win[nw - 1].close;
   for(int k = 0; k < want; k++)
     {
      int best = -1;
      double bd = 0.0;
      for(int c = 0; c < nc; c++)
        {
         if(used[c])
            continue;
         double dd = MathAbs(sw[cand[c]].price - ref);
         if(best < 0 || dd < bd || (dd == bd && sw[cand[c]].pivot_time > sw[cand[best]].pivot_time))
           {
            best = c;
            bd = dd;
           }
        }
      used[best] = true;
      ArrayResize(sel, k + 1);
      sel[k] = cand[best];
     }
   return(want);
  }

//--- a short, deterministic, clock-free text (8 hex digits, FNV-1a) of a long logic id. Chart object names are
//--- limited in length (63 characters in MT5), and ids such as an event id (type, time, level id) can be longer, so
//--- an object name uses this hash instead of the id. The same id always gives the same name (no duplicates on a
//--- redraw), and nothing is read back from the name.
string H3LShort(const string s)
  {
   ulong h = 2166136261;
   int len = StringLen(s);
   for(int i = 0; i < len; i++)
     {
      h = h ^ (ulong)StringGetCharacter(s, i);
      h = (h * 16777619) & 0xFFFFFFFF;
     }
   string digits = "0123456789abcdef";
   string out = "";
   for(int k = 7; k >= 0; k--)
      out += StringSubstr(digits, (int)((h >> (4 * k)) & 15), 1);
   return(out);
  }

//--- what each A/B reason means (diagnostics for the panel); ORG_DIFF is informational and never a reason
string H3LReasonHelp(const string reason)
  {
   string s = "";
   if(StringFind(reason, "AB_STRUCTURE_DIFF") >= 0)
      s += "AB_STRUCTURE_DIFF = replays A and B differ in the STRUCTURE (bias, level, extreme, unconsumed internal levels). ";
   if(StringFind(reason, "AB_SETUP_DIFF") >= 0)
      s += "AB_SETUP_DIFF = they differ in the SETUP (wick/sweep record, FVG tracks). ";
   if(StringFind(reason, "AB_EVENT_DIFF") >= 0)
      s += "AB_EVENT_DIFF = they differ in the events of the compared zone. ";
   if(StringFind(reason, "ANCHOR_IN_WARMUP") >= 0)
      s += "ANCHOR_IN_WARMUP = the bar the state depends on lies in the warm-up. ";
   if(StringFind(reason, "ANCHOR_HISTORY_MISSING") >= 0)
      s += "ANCHOR_HISTORY_MISSING = the history lacks a bar the state depends on. ";
   return(s);
  }


//+------------------------------------------------------------------+
//| PANEL: wrapping, size and line budget (pure; no chart access)    |
//+------------------------------------------------------------------+
//--- text -> pieces of at most maxchars (the first) / maxchars-2 (continuations, indented by 2). Cuts at a space
//--- when one lies in the second half of the line. Returns the number of pieces (>= 1, at most 13).
int H3LWrap(const string text, const int maxchars, string &out[])
  {
   ArrayResize(out, 0);
   int mc = (maxchars < 8 ? 8 : maxchars);
   string rest = text;
   bool first = true;
   int n = 0;
   for(int guard = 0; guard < 80; guard++)
     {
      int avail = (first ? mc : mc - 2);
      if(StringLen(rest) <= avail)
        {
         ArrayResize(out, n + 1);
         out[n] = (first ? "" : "  ") + rest;
         return(n + 1);
        }
      int cut = -1;
      for(int i = avail; i > avail / 2; i--)
         if(StringGetCharacter(rest, i) == ' ')
           {
            cut = i;
            break;
           }
      if(cut < 0)
         cut = avail;
      ArrayResize(out, n + 1);
      out[n] = (first ? "" : "  ") + StringSubstr(rest, 0, cut);
      n++;
      rest = StringSubstr(rest, cut);
      while(StringLen(rest) > 0 && StringGetCharacter(rest, 0) == ' ')
         rest = StringSubstr(rest, 1);
      first = false;
     }
   ArrayResize(out, n + 1);
   out[n] = "  " + rest;
   return(n + 1);
  }

//--- text rows that fit under the chart height (at least 1): the panel never grows beyond the chart
int H3LPanelRows(const int height_px, const int line_h, const int pad, const int margin)
  {
   if(line_h < 1)
      return(1);
   int r = (height_px - 2 * margin - 2 * pad) / line_h;
   return(r < 1 ? 1 : r);
  }

//--- characters per row: share_pct percent of the chart width, never more than the width left after the margins,
//--- between 20 and 140 (a font is never shrunk to fit: lines are wrapped here and dropped by H3LPanelBudget)
int H3LPanelCols(const int width_px, const double char_w, const int pad, const int margin, const int share_pct)
  {
   if(char_w <= 0.0)
      return(20);
   int by_share = (int)((width_px * share_pct / 100.0 - 2.0 * pad) / char_w);
   int by_room  = (int)((width_px - 2.0 * margin - 2.0 * pad) / char_w);
   int c = (by_share < by_room ? by_share : by_room);
   if(c < 20)
      c = 20;
   if(c > 140)
      c = 140;
   return(c);
  }

//--- which lines stay. prio[i]: 0 = essential, larger = less important; rows[i] = text rows of line i after
//--- wrapping. When everything fits, all stay. Otherwise one row is kept for a "hidden lines" marker and the lines
//--- are taken in the order (prio, position) until the first one that does not fit: so the dropped lines are always
//--- the LOWEST priority ones (and, within a priority, the LAST ones). Returns the number of lines kept; hidden
//--- receives the number of lines dropped.
int H3LPanelBudget(const int rows_avail, const int &prio[], const int &rows[], const int n, bool &keep[], int &hidden)
  {
   ArrayResize(keep, n);
   hidden = 0;
   int total = 0;
   for(int i = 0; i < n; i++)
     {
      keep[i] = false;
      total += (rows[i] < 1 ? 1 : rows[i]);
     }
   if(total <= rows_avail)
     {
      for(int a = 0; a < n; a++)
         keep[a] = true;
      return(n);
     }
   int budget = rows_avail - 1;
   int used = 0;
   int kept = 0;
   for(int round = 0; round < n; round++)
     {
      int best = -1;
      for(int j = 0; j < n; j++)
        {
         if(keep[j])
            continue;
         if(best < 0 || prio[j] < prio[best])
            best = j;
        }
      if(best < 0)
         break;
      int need = (rows[best] < 1 ? 1 : rows[best]);
      if(used + need > budget)
         break;
      keep[best] = true;
      used += need;
      kept++;
     }
   hidden = n - kept;
   return(kept);
  }

//+------------------------------------------------------------------+
//| CHART LABELS: stable slot                                        |
//+------------------------------------------------------------------+
//--- the vertical slot of a label: a function of the bar time (one of `lanes` lanes by the bar's position in time)
//--- and of seq (the label's rank among the labels of the SAME bar, counted in the logic's own event order). Not
//--- of the draw order, of the number of labels drawn or of any random value: a redraw never shuffles the labels.
int H3LLabelSlot(const datetime t, const int period, const int seq, const int lanes)
  {
   int ln = (lanes < 1 ? 1 : lanes);
   int pd = (period < 1 ? 1 : period);
   long idx = (long)t / (long)pd;
   int lane = (int)(idx % ln);
   int s = (seq < 0 ? 0 : seq);
   return((s % 3) * ln + lane);
  }

//+------------------------------------------------------------------+
//| CSV export key: the export is rewritten when the analysed set    |
//| changes, even if the last bar time is the same                   |
//+------------------------------------------------------------------+
ulong H3LHashStep(const ulong h0, const long v)
  {
   ulong h = h0;
   for(int k = 0; k < 8; k++)
     {
      h = h ^ (ulong)((v >> (8 * k)) & 255);
      h = h * (ulong)1099511628211;
     }
   return(h);
  }

long H3LScaled(const double price, const double scale)
  {
   return((long)(price * scale + (price >= 0.0 ? 0.5 : -0.5)));
  }

//--- order-sensitive 64-bit FNV-1a over the count and, for every bar, time and open/high/low/close (rounded to
//--- `digits` decimals). 16 hex digits. Volume and spread are not part of the exported analysis and not hashed.
string H3LBarsHash(const MqlRates &rates[], const int n, const int digits)
  {
   double scale = 1.0;
   for(int d = 0; d < digits && d < 12; d++)
      scale *= 10.0;
   ulong h = (((ulong)0xcbf29ce4) << 32) | (ulong)0x84222325;
   h = H3LHashStep(h, (long)n);
   for(int i = 0; i < n; i++)
     {
      h = H3LHashStep(h, (long)rates[i].time);
      h = H3LHashStep(h, H3LScaled(rates[i].open, scale));
      h = H3LHashStep(h, H3LScaled(rates[i].high, scale));
      h = H3LHashStep(h, H3LScaled(rates[i].low, scale));
      h = H3LHashStep(h, H3LScaled(rates[i].close, scale));
     }
   string digs = "0123456789abcdef";
   string out = "";
   for(int k = 15; k >= 0; k--)
      out += StringSubstr(digs, (int)((h >> (4 * k)) & 15), 1);
   return(out);
  }

//--- the export cache key: symbol | as-of | last bar time | bar count | first bar time | content hash. The CSV is
//--- written again whenever ANY part changes (history added or corrected with the last candle unchanged included).
string H3LExportKey(const string symbol, const datetime asof, const MqlRates &rates[], const int n, const int digits)
  {
   if(n < 1)
      return(symbol + "|" + IntegerToString((long)asof) + "|empty");
   return(symbol + "|" + IntegerToString((long)asof) + "|" + IntegerToString((long)rates[n - 1].time) + "|" +
          IntegerToString(n) + "|" + IntegerToString((long)rates[0].time) + "|" + H3LBarsHash(rates, n, digits));
  }

//+------------------------------------------------------------------+
//| SINCE-BASELINE counters (live). A baseline (start, restart,      |
//| recovery after a clear) is a NEW baseline: nothing in the history |
//| is NEW, and the values labelled "since baseline" start at zero.  |
//| The session_* values are only for the Experts log, never for the |
//| panel.                                                           |
//+------------------------------------------------------------------+
struct SH3LSince
  {
   int               new_total;      // NEW market events since the current baseline
   int               changes;        // observed bias / phase changes since the current baseline
   int               sess_new;       // NEW market events since the EA started (Experts log only)
   int               sess_changes;   // observed changes since the EA started (Experts log only)
   int               baselines;      // number of clears / recoveries since the EA started
  };

void H3LSinceInit(SH3LSince &s)
  {
   s.new_total    = 0;
   s.changes      = 0;
   s.sess_new     = 0;
   s.sess_changes = 0;
   s.baselines    = 0;
  }

void H3LSinceNew(SH3LSince &s)
  {
   s.new_total++;
   s.sess_new++;
  }

void H3LSinceChange(SH3LSince &s)
  {
   s.changes++;
   s.sess_changes++;
  }

//--- clear / recovery: the since-baseline values are zeroed, the session totals stay (Experts log only)
void H3LSinceClear(SH3LSince &s)
  {
   s.new_total = 0;
   s.changes   = 0;
   s.baselines++;
  }

#endif // VELO_H4_BIAS_LAYERS_MQH
