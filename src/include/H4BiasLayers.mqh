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
  };

void H3LRunInit(SH3LRun &r)
  {
   r.active = false;
   r.since  = 0;
   r.bars   = 0;
   r.exact  = true;
   r.t2dir  = H4_DIR_UNKNOWN;
   r.bias   = H3_NONE;
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

string H3LDisagreeText(const SH3LRun &r, const int period)
  {
   if(!r.active)
      return("");
   string s = "MODEL DISAGREEMENT - client validation pending: T002 " + H4DirName(r.t2dir) + " (" +
              H3LStructureWords(r.t2dir) + ") vs T003 prototype bias " + H3DirName(r.bias) + ", since closed bar " +
              H3LTime(r.since) + " (known " + H3LTime(r.since + (datetime)period) + "), " + IntegerToString(r.bars) +
              " closed bar(s)";
   if(!r.exact)
      s += " (or earlier: the run reaches the start of the trusted bars)";
   return(s);
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
      s += "AB_STRUCTURE_DIFF = replays A and B differ in the STRUCTURE (bias, level, extreme, interior). ";
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

#endif // VELO_H4_BIAS_LAYERS_MQH
