//+------------------------------------------------------------------+
//|                                          T003_LayersTest.mq5     |
//|                                                                  |
//|  T003 visual layers - MT5 script that tests the PURE helpers of  |
//|  src/include/H4BiasLayers.mqh on synthetic bars (generic units,  |
//|  no real prices): the MODEL DISAGREEMENT definition and run, the |
//|  bias timeline rebuilt from the events, the T002 source swings   |
//|  and the HISTORICAL LIQUIDITY selection, the T002 BASELINE       |
//|  (lookback window, equal to the T002 EA on the same bars, differs|
//|  from the replay window), the panel wrap / size / line budget,   |
//|  the stable label slot, the CSV export key (partial history that |
//|  grows with the same last candle) and the since-baseline reset.  |
//|                                                                  |
//|  STATUS: written; NOT compiled with MetaEditor and NOT run in    |
//|  MT5. It was run only through the C++ transliteration of         |
//|  tools/t003-xlate-check.sh (NOT MetaEditor). A PASS shows that   |
//|  the helpers do what the proposal says; it says nothing about    |
//|  the client's strategy. The disagreement definition and the      |
//|  liquidity algorithm are PROPOSALS.                              |
//|                                                                  |
//|  This is a SCRIPT (OnStart): MQL5/Scripts/velo_src/tests/ next   |
//|  to MQL5/Scripts/velo_src/include/ (same layout as              |
//|  T003_LogicTest.mq5).                                            |
//+------------------------------------------------------------------+
#property copyright "velireci"
#property version   "1.00"

#include "../include/H4BiasLayers.mqh"

#define T3_PERIOD 14400

int g_pass = 0;
int g_fail = 0;

void Check(const bool cond, const string label)
  {
   if(cond)
     {
      g_pass++;
      PrintFormat("  PASS %s", label);
     }
   else
     {
      g_fail++;
      PrintFormat("  FAIL %s", label);
     }
  }

datetime LBase(void) { return(D'2026.01.05 00:00'); }

//--- turning points (index, price): (0,100) (6,110) (12,104) (18,114) (24,108) (30,118) (36,112) (39,115);
//--- flat at 115 after bar 39. Highs rise 110, 114, 118 and lows rise 104, 108, 112: HH+HL.
double LPrice(const int i)
  {
   int ix[] = {0, 6, 12, 18, 24, 30, 36, 39};
   double px[] = {100.0, 110.0, 104.0, 114.0, 108.0, 118.0, 112.0, 115.0};
   if(i >= 39)
      return(115.0);
   for(int k = 1; k < 8; k++)
     {
      if(i <= ix[k])
        {
         double f = (double)(i - ix[k - 1]) / (double)(ix[k] - ix[k - 1]);
         return(px[k - 1] + f * (px[k] - px[k - 1]));
        }
     }
   return(115.0);
  }

void LBuild(const int nw, MqlRates &bars[])
  {
   ArrayResize(bars, nw);
   for(int i = 0; i < nw; i++)
     {
      double p = LPrice(i);
      bars[i].time  = LBase() + (datetime)(i * T3_PERIOD);
      bars[i].open  = p;
      bars[i].high  = p + 0.5;
      bars[i].low   = p - 0.3;
      bars[i].close = p;
     }
  }

datetime LT(const int idx) { return(LBase() + (datetime)(idx * T3_PERIOD)); }

void LEv(SH3Event &events[], int &ne, const int type, const int bar_idx, const string detail)
  {
   H3AddEvent(events, ne, type, LT(bar_idx), "ref", detail);
  }

void TestDefinition(void)
  {
   Print("--- disagreement definition (proposal): only BULLISH vs BEAR and BEARISH vs BULL");
   Check(H3LDisagree(H4_DIR_BULLISH, H3_BEAR), "BULLISH vs BEAR disagrees");
   Check(H3LDisagree(H4_DIR_BEARISH, H3_BULL), "BEARISH vs BULL disagrees");
   Check(!H3LDisagree(H4_DIR_BULLISH, H3_BULL), "BULLISH vs BULL agrees");
   Check(!H3LDisagree(H4_DIR_BEARISH, H3_BEAR), "BEARISH vs BEAR agrees");
   Check(!H3LDisagree(H4_DIR_MIXED, H3_BEAR), "MIXED vs BEAR is NOT a disagreement");
   Check(!H3LDisagree(H4_DIR_MIXED, H3_BULL), "MIXED vs BULL is NOT a disagreement");
   Check(!H3LDisagree(H4_DIR_UNKNOWN, H3_BEAR), "UNKNOWN vs BEAR is NOT a disagreement");
   Check(!H3LDisagree(H4_DIR_UNKNOWN, H3_BULL), "UNKNOWN vs BULL is NOT a disagreement");
   Check(!H3LDisagree(H4_DIR_BULLISH, H3_NONE), "BULLISH vs no bias is NOT a disagreement");
   Check(!H3LDisagree(H4_DIR_BEARISH, H3_NONE), "BEARISH vs no bias is NOT a disagreement");
   Check(H3LStructureWords(H4_DIR_BULLISH) == "HH+HL" && H3LStructureWords(H4_DIR_BEARISH) == "LH+LL",
         "the client's words (N1): BULLISH = HH+HL, BEARISH = LH+LL");
  }

void TestBiasTimeline(void)
  {
   Print("--- bias timeline rebuilt from the bias-setting events (no event after the bar is read)");
   SH3Event ev[];
   int ne = 0;
   LEv(ev, ne, H3_EV_BREAK_SET, 10, "dir=BEAR;from=NONE;known=x;t002=y");
   LEv(ev, ne, H3_EV_CONFLICT, 12, "up=a;dn=b");
   LEv(ev, ne, H3_EV_WICK, 14, "dir=BULL;lvl=x;sw=1");
   LEv(ev, ne, H3_EV_SETUP_ENDED, 15, "dir=BULL;reason=REPLACED");
   LEv(ev, ne, H3_EV_FLIP, 32, "dir=BULL;from=BEAR;known=z");
   Check(H3LBiasAtBar(ev, ne, LT(9)) == H3_NONE, "before the first event: no bias");
   Check(H3LBiasAtBar(ev, ne, LT(10)) == H3_BEAR, "at the bar of BREAK_SET: BEAR (state after its close)");
   Check(H3LBiasAtBar(ev, ne, LT(14)) == H3_BEAR, "a WICK / CONFLICT / SETUP_ENDED event does not change the bias");
   Check(H3LBiasAtBar(ev, ne, LT(31)) == H3_BEAR, "BEAR until the flip");
   Check(H3LBiasAtBar(ev, ne, LT(32)) == H3_BULL, "FLIP to BULL at its bar");
   Check(H3LBiasAtBar(ev, ne, LT(39)) == H3_BULL, "BULL afterwards");
   SH3Event ev2[];
   int n2 = 0;
   LEv(ev2, n2, H3_EV_SEED, 3, "dir=BULL;t002=y");
   Check(H3LBiasAtBar(ev2, n2, LT(3)) == H3_BULL, "SEED sets the bias");
  }

void TestSources(void)
  {
   Print("--- T002 source swings (two latest highs and lows known at the last bar)");
   MqlRates bars[];
   LBuild(40, bars);
   SH4Swing sw[];
   int amb = 0;
   int ns = H4FindSwings(bars, 40, 2, 2, T3_PERIOD, sw, amb);
   Check(ns == 6, "fixture: 6 swings (highs at 6, 18, 30; lows at 12, 24, 36)");
   if(ns != 6)
      return;
   int nk = H3KnownCount(sw, ns, 2, 39);
   int h2 = 0, h1 = 0, l2 = 0, l1 = 0;
   int c = H3LT2Sources(sw, nk, h2, h1, l2, l1);
   Check(c == 4 && sw[h2].index == 30 && sw[h1].index == 18 && sw[l2].index == 36 && sw[l1].index == 24,
         "sources: highs 30 (latest) and 18, lows 36 (latest) and 24");
   Check(sw[h2].price > sw[h1].price && sw[l2].price > sw[l1].price, "HH and HL in the fixture");
   Check(H4DeriveDirection(sw, nk) == H4_DIR_BULLISH, "T002 reads BULLISH at the last bar");
   int nk2 = H3KnownCount(sw, ns, 2, 20);
   c = H3LT2Sources(sw, nk2, h2, h1, l2, l1);
   Check(c == 3 && sw[h2].index == 18 && sw[h1].index == 6 && sw[l2].index == 12 && l1 == -1,
         "at bar 20 only 3 sources exist (low 24 not known yet): l1 = -1");
   Check(sw[h2].confirm_time == LT(18 + 2) + T3_PERIOD, "confirmation time = close of the second bar to the right");
  }

void TestRun(void)
  {
   Print("--- disagreement run: since-when and closed bars, by absolute times");
   MqlRates bars[];
   LBuild(40, bars);
   SH4Swing sw[];
   int amb = 0;
   int ns = H4FindSwings(bars, 40, 2, 2, T3_PERIOD, sw, amb);
   SH3Event ev[];
   int ne = 0;
   LEv(ev, ne, H3_EV_BREAK_SET, 0, "dir=BEAR;from=NONE");
   SH3LRun r;
   H3LDisagreeRun(bars, 40, sw, ns, 2, 0, ev, ne, r);
   Check(r.active && r.t2dir == H4_DIR_BULLISH && r.bias == H3_BEAR, "BULLISH T002 vs BEAR bias is active");
   Check(r.since == LT(26) && r.bars == 14 && r.exact, "run starts at bar 26 (T002 BULLISH from the 4th swing), 14 bars, exact");
   string tx = H3LDisagreeText(r, T3_PERIOD);
   Check(StringFind(tx, "MODEL DISAGREEMENT - client validation pending") == 0, "text starts with the required wording");
   Check(StringFind(tx, "14 closed bar(s)") > 0 && StringFind(tx, "HH+HL") > 0, "text carries the bar count and the client's words");
   //--- the same run one bar earlier: same key (logged once per change, the bar count is not part of the key)
   H3LDisagreeRun(bars, 39, sw, ns, 2, 0, ev, ne, r);
   string k39 = H3LDisagreeKey(r);
   SH3LRun r40;
   H3LDisagreeRun(bars, 40, sw, ns, 2, 0, ev, ne, r40);
   Check(r.active && r.bars == 13 && k39 == H3LDisagreeKey(r40), "one bar earlier: 13 bars, same key (no new log line)");
   //--- trusted region: the run reaches it -> not exact
   H3LDisagreeRun(bars, 40, sw, ns, 2, 30, ev, ne, r);
   Check(r.active && r.bars == 10 && r.since == LT(30) && !r.exact, "warm-up 30: only the trusted 10 bars are claimed, exact = false");
   Check(StringFind(H3LDisagreeText(r, T3_PERIOD), "or earlier") > 0, "an inexact run says 'or earlier'");
   //--- the bias flips to BULL at bar 32: no disagreement at the last bar
   SH3Event evb[];
   int nb = 0;
   LEv(evb, nb, H3_EV_BREAK_SET, 0, "dir=BEAR;from=NONE");
   LEv(evb, nb, H3_EV_FLIP, 32, "dir=BULL;from=BEAR");
   H3LDisagreeRun(bars, 40, sw, ns, 2, 0, evb, nb, r);
   Check(!r.active && r.bars == 0 && H3LDisagreeText(r, T3_PERIOD) == "" && H3LDisagreeKey(r) == "NONE",
         "bias BULL agrees with BULLISH T002: no disagreement, no text");
   H3LDisagreeRun(bars, 33, sw, ns, 2, 0, evb, nb, r);
   Check(!r.active, "at bar 32 (the flip bar) the bias already agrees (state after the close)");
   H3LDisagreeRun(bars, 32, sw, ns, 2, 0, evb, nb, r);
   Check(r.active && r.bars == 6 && r.since == LT(26), "before the flip (last bar 31): active, bars 26..31 = 6");
   //--- T002 UNKNOWN (fewer swings known) is not a disagreement even against BEAR
   H3LDisagreeRun(bars, 21, sw, ns, 2, 0, ev, ne, r);
   Check(!r.active && r.t2dir == H4_DIR_UNKNOWN, "T002 UNKNOWN with a BEAR bias: not a disagreement");
   //--- no future information: the tail beyond nw is garbage in one copy, the result is identical
   MqlRates bad[];
   LBuild(40, bad);
   for(int i = 30; i < 40; i++)
     {
      bad[i].high = 500.0 + i;
      bad[i].low  = -500.0 - i;
      bad[i].close = 500.0;
     }
   //--- the swing list of the 40-bar series is given to BOTH calls: only the helpers' own bounds (nw) can hide the tail
   SH3LRun ra;
   SH3LRun rb;
   H3LDisagreeRun(bars, 30, sw, ns, 2, 0, ev, ne, ra);
   H3LDisagreeRun(bad, 30, sw, ns, 2, 0, ev, ne, rb);
   Check(ra.active && ra.since == rb.since && ra.bars == rb.bars && ra.t2dir == rb.t2dir && ra.bias == rb.bias,
         "bars after the evaluation window do not change the run (no future information)");
   int sa[];
   int sb[];
   int ta = 0, tb = 0;
   int ca = H3LLiquidity(bars, 30, sw, ns, 2, 6, sa, ta);
   int cb = H3LLiquidity(bad, 30, sw, ns, 2, 6, sb, tb);
   Check(ca == cb && ta == tb, "bars after the evaluation window do not change the liquidity layer");
  }

void TestLiquidity(void)
  {
   Print("--- historical liquidity (proposal): unexceeded confirmed swings, nearest to the last close first");
   MqlRates bars[];
   LBuild(40, bars);
   SH4Swing sw[];
   int amb = 0;
   int ns = H4FindSwings(bars, 40, 2, 2, T3_PERIOD, sw, amb);
   int sel[];
   int total = 0;
   int n = H3LLiquidity(bars, 40, sw, ns, 2, 6, sel, total);
   Check(total == 4 && n == 4, "unexceeded: SH 118@30, SL 104@12, SL 108@24, SL 112@36 (SH 110@6 and 114@18 were exceeded by later highs)");
   if(n == 4)
     {
      Check(sw[sel[0]].index == 36 && sw[sel[1]].index == 30 && sw[sel[2]].index == 24 && sw[sel[3]].index == 12,
            "order: nearest to the last close (115) first: 36, 30, 24, 12");
     }
   n = H3LLiquidity(bars, 40, sw, ns, 2, 2, sel, total);
   Check(n == 2 && total == 4 && sw[sel[0]].index == 36 && sw[sel[1]].index == 30, "limit 2: the two nearest; total still 4");
   n = H3LLiquidity(bars, 40, sw, ns, 2, 0, sel, total);
   Check(n == 0 && total == 4, "limit 0: nothing selected");
   //--- a swing that is not yet confirmed at the last bar is excluded (SL at 36 needs bar 38)
   n = H3LLiquidity(bars, 38, sw, ns, 2, 6, sel, total);
   Check(total == 3, "last bar 37: the swing low at 36 is not confirmed yet, 3 candidates");
   //--- strictness: an equal high is a touch, a higher high (a wick) is an exceed
   MqlRates b2[];
   LBuild(40, b2);
   b2[38].high = b2[30].high;
   n = H3LLiquidity(b2, 40, sw, ns, 2, 6, sel, total);
   Check(total == 4, "a later high EQUAL to the swing high does not exceed it");
   b2[38].high = b2[30].high + 0.01;
   n = H3LLiquidity(b2, 40, sw, ns, 2, 6, sel, total);
   Check(total == 3, "a later wick above the swing high exceeds it (the close is irrelevant)");
   MqlRates b3[];
   LBuild(40, b3);
   b3[37].low = b3[24].low - 0.01;
   SH4Swing sw3[];
   int ns3 = H4FindSwings(b3, 40, 2, 2, T3_PERIOD, sw3, amb);
   int s3[];
   n = H3LLiquidity(b3, 40, sw3, ns3, 2, 6, s3, total);
   bool has24 = false;
   for(int w = 0; w < n; w++)
      if(sw3[s3[w]].index == 24)
         has24 = true;
   Check(total == 3 && !has24, "a later wick below the swing low at 24 exceeds it (bar 37 is the new swing low; 36 is no swing any more)");
   //--- a higher bar right of the old pivot: that pivot is no swing any more, the higher bar is the swing
   MqlRates b4[];
   LBuild(40, b4);
   b4[31].high = b4[30].high + 1.0;
   SH4Swing sw4[];
   int ns4 = H4FindSwings(b4, 40, 2, 2, T3_PERIOD, sw4, amb);
   n = H3LLiquidity(b4, 40, sw4, ns4, 2, 6, sel, total);
   bool has31 = false;
   for(int q = 0; q < n; q++)
      if(sw4[sel[q]].index == 31)
         has31 = true;
   Check(total == 4 && has31, "fixture with a higher bar at 31: the swing high moves to 31 and is unexceeded");
  }

void TestReasons(void)
  {
   Print("--- A/B reason help text");
   string s = H3LReasonHelp("AB_STRUCTURE_DIFF+AB_SETUP_DIFF+ANCHOR_IN_WARMUP");
   Check(StringFind(s, "AB_STRUCTURE_DIFF =") >= 0 && StringFind(s, "AB_SETUP_DIFF =") >= 0 &&
         StringFind(s, "ANCHOR_IN_WARMUP =") >= 0 && StringFind(s, "AB_EVENT_DIFF") < 0, "only the reasons present are explained");
   Check(H3LReasonHelp("converged at depth 1000 vs 700") == "", "a converged text has no reason help");
  }

void TestShortNames(void)
  {
   Print("--- short deterministic object-name part (chart object names are limited in length)");
   string a = H3LShort("INTERNAL_SWEEP@202610021200#SH202610010400_202610020800_202610010000");
   string b = H3LShort("INTERNAL_SWEEP@202610021200#SH202610010400_202610020800_202610010000");
   string c = H3LShort("INTERNAL_SWEEP@202610021204#SH202610010400_202610020800_202610010000");
   Check(StringLen(a) == 8 && a == b, "8 characters and deterministic");
   Check(a != c, "different ids give different parts");
   Check(StringLen("velo_t003_ev_" + "202610021200" + "_" + a) <= 63, "the longest event object name fits 63 characters");
   Check(StringLen("velo_t003_snap_lbl_" + a) <= 63 && StringLen("velo_t003_lvl_lbl_" + a) <= 63, "level / snapshot names fit 63 characters");
  }

//--- the bias rebuilt from the events must equal the replay's own bias at EVERY examined bar (so the disagreement
//--- run, which uses the events, cannot drift from the real state). Synthetic random walk (generic units, a
//--- deterministic generator, no real prices); the real H3Replay is used on prefixes (it is causal).
void TestTimelineAgainstReplay(void)
  {
   Print("--- bias timeline versus the real replay (synthetic random walk)");
   int n = 420;
   MqlRates bars[];
   ArrayResize(bars, n);
   long seed = 12345;
   double c = 1000.0;
   for(int i = 0; i < n; i++)
     {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      double r1 = (double)((seed >> 8) % 2001) / 1000.0 - 1.0;
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      double r2 = (double)((seed >> 8) % 1001) / 1000.0;
      double o = c;
      c = c + r1 * 9.0 + (i % 90 < 45 ? 0.6 : -0.6);
      bars[i].time  = LBase() + (datetime)(i * T3_PERIOD);
      bars[i].open  = o;
      bars[i].close = c;
      bars[i].high  = (o > c ? o : c) + r2 * 3.0;
      bars[i].low   = (o < c ? o : c) - r2 * 3.0;
     }
   SH3Params p;
   H3ParamsDefault(p);
   p.lookback = 50;
   SH3Rep full;
   SH3Track ftr[];
   SH3Event fev[];
   string fkeys[];
   H3Replay(bars, n, p, full, ftr, fev, fkeys, false);
   int nflip = 0;
   int nset = 0;
   for(int i = 0; i < full.ne; i++)
     {
      if(fev[i].type == H3_EV_FLIP)
         nflip++;
      if(fev[i].type == H3_EV_BREAK_SET || fev[i].type == H3_EV_SEED)
         nset++;
     }
   Check(nset >= 1 && nflip >= 1, "fixture is not vacuous: the replay sets a bias and flips at least once");
   int bad = 0;
   int checked = 0;
   int seen_bull = 0;
   int seen_bear = 0;
   for(int k = 60; k <= n; k += 3)
     {
      SH3Rep pre;
      SH3Track ptr[];
      SH3Event pev[];
      string pkeys[];
      H3Replay(bars, k, p, pre, ptr, pev, pkeys, false);
      int from_events = H3LBiasAtBar(fev, full.ne, bars[k - 1].time);
      if(from_events != pre.st.dir)
         bad++;
      if(pre.st.dir == H3_BULL)
         seen_bull++;
      if(pre.st.dir == H3_BEAR)
         seen_bear++;
      checked++;
     }
   Check(bad == 0 && checked > 100, "events-derived bias equals the replay bias at every sampled bar");
   Check(seen_bull > 0 && seen_bear > 0, "both BULL and BEAR occur in the fixture (the check is not one-sided)");
   //--- the run at the end of the series: consistent with the replay state and with the T002 direction text
   SH4Swing sw[];
   int amb = 0;
   int ns = H4FindSwings(bars, n, p.left, p.right, p.period, sw, amb);
   SH3LRun r;
   H3LDisagreeRun(bars, n, sw, ns, p.right, H3WarmUp(p), fev, full.ne, r);
   Check(r.bias == full.st.dir && H4DirName(r.t2dir) == full.st.t2dir, "the run reports the replay's bias and T002 direction at the last bar");
   //--- brute force over the whole fixture: the run length equals the number of consecutive disagreeing bars
   int brute = 0;
   for(int t = n - 1; t >= H3WarmUp(p); t--)
     {
      int d2 = H4DeriveDirection(sw, H3KnownCount(sw, ns, p.right, t));
      if(!H3LDisagree(d2, H3LBiasAtBar(fev, full.ne, bars[t].time)))
         break;
      brute++;
     }
   Check((r.active ? r.bars : 0) == brute, "the run length equals an independent count of consecutive disagreeing bars");
   //--- how often the two layers disagree on this fixture (information for the report, not a pass criterion)
   int dis_bars = 0;
   int bias_bars = 0;
   for(int t2 = H3WarmUp(p); t2 < n; t2++)
     {
      int b2 = H3LBiasAtBar(fev, full.ne, bars[t2].time);
      if(b2 != H3_NONE)
         bias_bars++;
      if(H3LDisagree(H4DeriveDirection(sw, H3KnownCount(sw, ns, p.right, t2)), b2))
         dis_bars++;
     }
   PrintFormat("  INFO fixture: %d trusted bars with a bias, %d of them in MODEL DISAGREEMENT (synthetic, not market-like)", bias_bars, dis_bars);
  }

//--- deterministic synthetic random walk (generic units, no real prices); the same generator as the timeline test
void LWalk(const int n, const long seed0, MqlRates &bars[])
  {
   ArrayResize(bars, n);
   long seed = seed0;
   double c = 1000.0;
   for(int i = 0; i < n; i++)
     {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      double r1 = (double)((seed >> 8) % 2001) / 1000.0 - 1.0;
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      double r2 = (double)((seed >> 8) % 1001) / 1000.0;
      double o = c;
      c = c + r1 * 9.0 + (i % 90 < 45 ? 0.6 : -0.6);
      bars[i].time  = LBase() + (datetime)(i * T3_PERIOD);
      bars[i].open  = o;
      bars[i].close = c;
      bars[i].high  = (o > c ? o : c) + r2 * 3.0;
      bars[i].low   = (o < c ? o : c) - r2 * 3.0;
     }
  }

//--- the T002 EA's result for the last `lookback` bars of rates[0..n_end-1]: H4Analyze on exactly that copy
int LT2EaDirection(const MqlRates &rates[], const int n_end, const int lookback, const int left, const int right, int &used)
  {
   used = (n_end < lookback ? n_end : lookback);
   MqlRates seg[];
   ArrayResize(seg, used);
   for(int i = 0; i < used; i++)
      seg[i] = rates[n_end - used + i];
   SH4Swing sw[];
   SH4Fvg fv[];
   int ns = 0, nf = 0;
   SH4Result res;
   H4Analyze(seg, used, left, right, T3_PERIOD, sw, ns, fv, nf, res);
   return(res.direction);
  }

void TestBaseline(void)
  {
   Print("--- T002 baseline (lookback N): window selection, equal to the T002 EA on the same bars, differs from the replay window");
   Check(H3LBaselineBars(500, 300) == 300 && H3LBaselineBars(300, 300) == 300 && H3LBaselineBars(100, 300) == 100 &&
         H3LBaselineBars(0, 300) == 0 && H3LBaselineBars(10, 0) == 0, "window selection: the last min(N, bars) bars");
   MqlRates bars[];
   LBuild(40, bars);
   int nb = 0;
   int whole = H3LBaselineDir(bars, 40, 40, 2, 2, T3_PERIOD, nb);
   Check(whole == H4_DIR_BULLISH && nb == 40, "lookback = window length: BULLISH (same as the replay-window structure)");
   int short20 = H3LBaselineDir(bars, 40, 20, 2, 2, T3_PERIOD, nb);
   Check(short20 == H4_DIR_UNKNOWN && nb == 20, "lookback 20 on the same bars: only ONE swing high inside -> UNKNOWN (differs from the longer window)");
   int sw_ok = 1;
   int lbs[] = {10, 15, 20, 25, 30, 39, 40, 60};
   for(int k = 0; k < 8; k++)
     {
      int used = 0;
      int ea = LT2EaDirection(bars, 40, lbs[k], 2, 2, used);
      int bd = H3LBaselineDir(bars, 40, lbs[k], 2, 2, T3_PERIOD, nb);
      if(ea != bd || used != nb)
         sw_ok = 0;
     }
   Check(sw_ok == 1, "baseline == the T002 EA (H4Analyze on the last N bars) for 8 lookbacks on the fixture");
   //--- random walk: equal to the T002 EA at many end positions and lookbacks; and different from the whole window sometimes
   MqlRates w[];
   LWalk(420, 777, w);
   int bad = 0;
   int differs = 0;
   int samples = 0;
   int checked = 0;
   for(int e = 80; e <= 420; e += 7)
     {
      for(int lb = 0; lb < 3; lb++)
        {
         int look = (lb == 0 ? 50 : (lb == 1 ? 120 : 300));
         int used = 0;
         int ea = LT2EaDirection(w, e, look, 2, 2, used);
         int bd = H3LBaselineDir(w, e, look, 2, 2, T3_PERIOD, nb);
         if(ea != bd || used != nb)
            bad++;
         checked++;
        }
      int nbw = 0;
      int win_dir = H3LBaselineDir(w, e, e, 2, 2, T3_PERIOD, nbw);
      int b20 = H3LBaselineDir(w, e, 20, 2, 2, T3_PERIOD, nb);
      if(win_dir != b20)
         differs++;
      samples++;
     }
   Check(bad == 0 && checked > 100, "random walk: baseline equals the T002 EA at every sampled end bar (50, 120, 300)");
   Check(differs > 0, "random walk: the replay-window direction differs from the lookback-20 baseline at some bars (the distinction is real)");
   PrintFormat("  INFO random walk: replay-window direction differs from the lookback-20 baseline at %d of %d sampled end bars (synthetic)", differs, samples);
   //--- no future information: bars after n_end are ignored
   MqlRates bad_tail[];
   LWalk(420, 777, bad_tail);
   for(int i = 300; i < 420; i++)
     {
      bad_tail[i].high = 9000.0 + i;
      bad_tail[i].low = -9000.0 - i;
     }
   Check(H3LBaselineDir(w, 300, 120, 2, 2, T3_PERIOD, nb) == H3LBaselineDir(bad_tail, 300, 120, 2, 2, T3_PERIOD, nb),
         "bars after the end position do not change the baseline (no future information)");
   //--- the disagreement run in terms of the baseline
   SH4Swing sw[];
   int amb = 0;
   int ns = H4FindSwings(bars, 40, 2, 2, T3_PERIOD, sw, amb);
   SH3Event ev[];
   int ne = 0;
   LEv(ev, ne, H3_EV_BREAK_SET, 0, "dir=BEAR;from=NONE");
   SH3LRun rw;
   H3LDisagreeRun(bars, 40, sw, ns, 2, 0, ev, ne, rw);
   SH3LRun r40;
   H3LDisagreeRunBase(bars, 40, 40, 2, 2, T3_PERIOD, 0, ev, ne, r40);
   Check(rw.active && r40.active && r40.since == rw.since && r40.bars == rw.bars && r40.t2dir == H4_DIR_BULLISH && r40.lookback == 40,
         "baseline lookback 40 (= the window): same run as the replay-window structure (since bar 26, 14 bars)");
   SH3LRun r30;
   H3LDisagreeRunBase(bars, 40, 30, 2, 2, T3_PERIOD, 0, ev, ne, r30);
   Check(r30.active && r30.since == LT(26) && r30.bars == 14, "baseline lookback 30: BULLISH from the same bar, 14 bars");
   SH3LRun r20;
   H3LDisagreeRunBase(bars, 40, 20, 2, 2, T3_PERIOD, 0, ev, ne, r20);
   Check(!r20.active && r20.t2dir == H4_DIR_UNKNOWN && rw.active,
         "baseline lookback 20 is UNKNOWN: NO model disagreement, although the replay-window structure (BULLISH) would be one");
   string tx = H3LDisagreeText(r40, T3_PERIOD);
   Check(StringFind(tx, "MODEL DISAGREEMENT - client validation pending: T002 baseline (lookback 40) BULLISH") == 0,
         "the text names the T002 BASELINE and its lookback");
   string tw = H3LDisagreeText(rw, T3_PERIOD);
   Check(StringFind(tw, "T002 replay-window structure BULLISH") > 0 && StringFind(tw, "baseline") < 0,
         "the replay-window variant is named 'replay-window structure', never 'baseline'");
   Check(H3LDisagreeShort(r40) == "MODEL DISAGREEMENT: baseline BULLISH vs T003 BEAR, 14 bars" && H3LDisagreeShort(r20) == "" &&
         StringFind(H3LDisagreeShort(rw), "replay-window BULLISH") > 0, "the short chart text names the baseline / replay-window source");
   Check(H3LT2Name(300) == "T002 baseline (lookback 300)" && H3LT2Name(0) == "T002 replay-window structure", "the two names are distinct");
   //--- run in terms of the baseline against independent brute-force counts on the random walk: a SHORT lookback (20,
   //--- the trusted region starts at 50) so that the baseline differs from the whole-prefix direction
   SH3Rep full;
   SH3Track ftr[];
   SH3Event fev[];
   string fkeys[];
   SH3Params p;
   H3ParamsDefault(p);
   p.lookback = 50;
   H3Replay(w, 420, p, full, ftr, fev, fkeys, false);
   int mism = 0;
   int total_run = 0;
   int pre_differs = 0;
   int ends = 0;
   for(int en = 120; en <= 420; en += 5)
     {
      SH3LRun rb;
      H3LDisagreeRunBase(w, en, 20, p.left, p.right, p.period, H3WarmUp(p), fev, full.ne, rb);
      int brute = 0;
      bool stop1 = false;
      int brute_pre = 0;
      bool stop2 = false;
      for(int t = en - 1; t >= H3WarmUp(p); t--)
        {
         int nbb = 0;
         int bias_t = H3LBiasAtBar(fev, full.ne, w[t].time);
         if(!stop1)
           {
            if(H3LDisagree(H3LBaselineDir(w, t + 1, 20, p.left, p.right, p.period, nbb), bias_t))
               brute++;
            else
               stop1 = true;
           }
         if(!stop2)
           {
            if(H3LDisagree(H3LBaselineDir(w, t + 1, t + 1, p.left, p.right, p.period, nbb), bias_t))
               brute_pre++;
            else
               stop2 = true;
           }
        }
      if((rb.active ? rb.bars : 0) != brute)
         mism++;
      if(brute != brute_pre)
         pre_differs++;
      total_run += brute;
      ends++;
     }
   Check(mism == 0 && ends > 50, "baseline run length equals an independent count at every sampled end bar (lookback 20)");
   Check(total_run > 0 && pre_differs > 0, "the check is not vacuous: runs exist and the whole-prefix direction would give other run lengths at some end bars");
   PrintFormat("  INFO random walk: %d end bars, summed baseline run length %d, whole-prefix run length differs at %d (synthetic)", ends, total_run, pre_differs);
  }

string NoSpaces(const string text)
  {
   string r = "";
   for(int i = 0; i < StringLen(text); i++)
      if(StringSubstr(text, i, 1) != " ")
         r += StringSubstr(text, i, 1);
   return(r);
  }

void TestPanelBudget(void)
  {
   Print("--- panel: wrap, size and line budget (the lowest priority lines are dropped, the font is never shrunk)");
   string pieces[];
   int np = H3LWrap("short text", 40, pieces);
   Check(np == 1 && pieces[0] == "short text", "a short line is one piece");
   string longt = "T003 PROTOTYPE bias BEAR phase SWEEP_WAIT origin BREAK since 2026.10.01 12:00 and a long tail of words that must wrap";
   np = H3LWrap(longt, 40, pieces);
   int okw = 1;
   string joined = "";
   for(int i = 0; i < np; i++)
     {
      if(StringLen(pieces[i]) > 40)
         okw = 0;
      if(i > 0 && StringSubstr(pieces[i], 0, 2) != "  ")
         okw = 0;
      string pc = (i > 0 ? StringSubstr(pieces[i], 2) : pieces[i]);
      joined += (joined != "" ? " " : "") + pc;
     }
   Check(np > 1 && okw == 1 && joined == longt, "a long line wraps at spaces, continuation rows are indented and no word is lost");
   string very_long = "";
   for(int w = 0; w < 120; w++)
      very_long += "word" + IntegerToString(w) + " ";
   np = H3LWrap(very_long, 40, pieces);
   int too_wide = 0;
   for(int i2 = 0; i2 < np; i2++)
      if(StringLen(pieces[i2]) > 40)
         too_wide++;
   Check(np > 12 && too_wide == 0, "a very long explanation wraps into more than 12 rows and no row exceeds the width (no unwrapped remainder)");
   np = H3LWrap("T003 H4 BIAS - PROPOSAL (client validation pending), visual only, NO TRADING", 30, pieces);
   too_wide = 0;
   for(int i3 = 0; i3 < np; i3++)
      if(StringLen(pieces[i3]) > 30)
         too_wide++;
   Check(np == 3 && too_wide == 0, "the 76-character title wraps at spaces into 3 rows of at most 30 columns");
   Check(H3LPanelRows(300, 16, 6, 8) == 17 && H3LPanelRows(120, 16, 6, 8) == 5 && H3LPanelRows(10, 16, 6, 8) == 1,
         "rows from the chart height: 300 px -> 17, 120 px -> 5, tiny chart -> at least 1");
   int c_wide = H3LPanelCols(2400, 7.0, 6, 8, 50);
   int c_mid = H3LPanelCols(500, 7.0, 6, 8, 50);
   int c_tiny = H3LPanelCols(200, 7.0, 6, 8, 50);
   Check(c_wide > c_mid && c_mid > c_tiny && c_tiny >= 20 && c_wide == 60, "columns follow the chart width (20..60) and shrink with it; a huge chart is capped at the label limit");
   Check(H3LPanelCols(5000, 7.0, 6, 8, 100) <= 60 && H3LPanelCols(1600, 7.0, 6, 8, 50) <= 60, "the column count never exceeds the label limit on any chart width");
   Check((c_mid + 2) * 7 <= 500 - 16, "the columns never need more width than the chart has left after the margins");
   // regression (owner photo of 6de979c): the title was shown as '... visual onl' and the bias line as '... BEA', both cut at exactly 63
   // characters, with the date missing. Every row text is at most H3L_LABEL_MAX_CHARS and nothing is lost in the wrapping.
   string rl[3];
   rl[0] = "T003 H4 BIAS - PROPOSAL (client validation pending), visual only, NO TRADING";
   rl[1] = "T003 bias (PROTOTYPE proposal, not the client's direction): BEAR  since 2026.10.01 12:00";
   rl[2] = "HISTORICAL as-of 2026.10.06 00:00 (broker/server time, NOT UTC, NOT TradingView) - static, closed bars only";
   int widths[] = {200, 400, 700, 1000, 1600, 2400, 5000};
   int bad_len = 0, bad_join = 0, bad_tok = 0;
   for(int wi = 0; wi < 7; wi++)
     {
      int cols = H3LPanelCols(widths[wi], 7.0, 6, 8, 55);
      for(int ri = 0; ri < 3; ri++)
        {
         int n2 = H3LWrap(rl[ri], cols, pieces);
         string all = "", flat2 = "";
         for(int q = 0; q < n2; q++)
           {
            if(StringLen(pieces[q]) > 60 || StringLen(pieces[q]) > (cols > 8 ? cols : 8))
               bad_len++;
            string pc2 = (q > 0 ? StringSubstr(pieces[q], 2) : pieces[q]);
            all += (all != "" ? " " : "") + pc2;
            flat2 += "|" + pieces[q] + "|";
           }
         if(NoSpaces(all) != NoSpaces(rl[ri]))           // only spaces may differ: a word longer than the row is cut, the rest is kept
            bad_join++;
         string toks[];
         int nt = (ri == 0 ? 3 : (ri == 1 ? 4 : 3));
         if(ri == 0) {ArrayResize(toks, 3); toks[0] = "visual"; toks[1] = "only,"; toks[2] = "TRADING";}
         if(ri == 1) {ArrayResize(toks, 4); toks[0] = "BEAR"; toks[1] = "since"; toks[2] = "2026.10.01"; toks[3] = "12:00";}
         if(ri == 2) {ArrayResize(toks, 3); toks[0] = "2026.10.06"; toks[1] = "00:00"; toks[2] = "TradingView)";}
         for(int tk = 0; tk < nt; tk++)
            if(StringFind(flat2, " " + toks[tk]) < 0 && StringFind(flat2, "|" + toks[tk]) < 0 && StringFind(flat2, "|  " + toks[tk]) < 0)
               bad_tok++;
        }
     }
   Check(bad_len == 0, "regression: no panel row is longer than 60 characters at any chart width (title, bias line, as-of line)");
   Check(bad_join == 0, "regression: the wrapped title, the bias line with BEAR and the full date and the as-of line lose no character (the pieces rejoin to the original apart from spaces)");
   Check(bad_tok == 0, "regression: the words visual only, NO TRADING, BEAR, 2026.10.01, 12:00 stay whole words at every width");
   //--- budget
   int pr[] = {0, 0, 1, 2, 3, 3};
   int rw[] = {1, 1, 1, 2, 1, 1};
   bool keep[];
   int hid = 0;
   int kept = H3LPanelBudget(100, pr, rw, 6, keep, hid);
   Check(kept == 6 && hid == 0, "everything fits: nothing is dropped, no marker");
   kept = H3LPanelBudget(5, pr, rw, 6, keep, hid);
   Check(kept == 3 && hid == 3 && keep[0] && keep[1] && keep[2] && !keep[3] && !keep[4] && !keep[5],
         "5 rows for 7: one row is kept for the marker, the priority 0 and 1 lines stay, the lowest priorities go");
   kept = H3LPanelBudget(1, pr, rw, 6, keep, hid);
   Check(kept == 0 && hid == 6, "a one-row panel keeps only the marker");
   //--- property: kept lines are never less important than a dropped line; the kept rows plus the marker fit
   long seed = 4242;
   int viol = 0;
   int cases = 0;
   for(int cs = 0; cs < 300; cs++)
     {
      int n = 3 + cs % 12;
      int pp[];
      int rr[];
      ArrayResize(pp, n);
      ArrayResize(rr, n);
      int tot = 0;
      for(int i = 0; i < n; i++)
        {
         seed = (seed * 1103515245 + 12345) & 0x7fffffff;
         pp[i] = (int)((seed >> 8) % 5);
         seed = (seed * 1103515245 + 12345) & 0x7fffffff;
         rr[i] = 1 + (int)((seed >> 8) % 3);
         tot += rr[i];
        }
      int avail = 1 + (cs * 7) % (tot + 3);
      bool kp[];
      int hd = 0;
      int kc = H3LPanelBudget(avail, pp, rr, n, kp, hd);
      int usedr = 0;
      int maxk = -1;
      int mind = 99;
      int cnt = 0;
      for(int j = 0; j < n; j++)
        {
         if(kp[j])
           {
            usedr += rr[j];
            cnt++;
            if(pp[j] > maxk)
               maxk = pp[j];
           }
         else
            if(pp[j] < mind)
               mind = pp[j];
        }
      if(cnt != kc || hd != n - kc)
         viol++;
      if(hd > 0 && (usedr + 1 > avail || (maxk >= 0 && mind < 99 && maxk > mind)))
         viol++;
      if(hd == 0 && tot > avail)
         viol++;
      cases++;
     }
   Check(viol == 0 && cases == 300, "300 random cases: the kept rows fit, the dropped lines are always the least important");
   //--- the compact default fits a small chart: 10 essential rows need a 240 px chart at font 9
   Check(H3LPanelRows(240, 16, 6, 8) >= 10, "a 240 px high chart holds the 10 rows of the compact view at font 9 (line height 16)");
  }

void TestLabelSlot(void)
  {
   Print("--- chart labels: the slot is stable (time and rank in the same bar only)");
   datetime t0 = LT(10);
   int a = H3LLabelSlot(t0, T3_PERIOD, 0, 3);
   int b = H3LLabelSlot(t0, T3_PERIOD, 0, 3);
   Check(a == b, "the same bar and rank give the same slot (deterministic, not random)");
   int distinct = 1;
   for(int i = 0; i < 3; i++)
      if(H3LLabelSlot(LT(10 + i), T3_PERIOD, 0, 3) == H3LLabelSlot(LT(10 + (i + 1) % 3), T3_PERIOD, 0, 3))
         distinct = 0;
   Check(distinct == 1, "three neighbouring bars use three different lanes");
   Check(H3LLabelSlot(t0, T3_PERIOD, 0, 3) != H3LLabelSlot(t0, T3_PERIOD, 1, 3) &&
         H3LLabelSlot(t0, T3_PERIOD, 1, 3) != H3LLabelSlot(t0, T3_PERIOD, 2, 3), "events of the same bar get different slots by their rank");
   int mx = 0;
   for(int k = 0; k < 40; k++)
      for(int s = 0; s < 9; s++)
        {
         int v = H3LLabelSlot(LT(k), T3_PERIOD, s, 3);
         if(v > mx)
            mx = v;
        }
   Check(mx <= 8 && H3LLabelSlot(LT(5), T3_PERIOD, -4, 3) >= 0 && H3LLabelSlot(LT(5), T3_PERIOD, 2, 0) >= 0,
         "slots stay within 0..8 (3 lanes x 3 ranks); bad arguments are tolerated");
  }

void TestExportKey(void)
  {
   Print("--- CSV export key: a change of the analysed set is detected even when the last candle is the same");
   MqlRates full[];
   LBuild(60, full);
   //--- PARTIAL history that grows: 40 bars -> 60 bars, the last candle is identical
   MqlRates p40[];
   ArrayResize(p40, 40);
   for(int j = 0; j < 40; j++)
      p40[j] = full[20 + j];
   MqlRates p60[];
   ArrayResize(p60, 60);
   for(int j2 = 0; j2 < 60; j2++)
      p60[j2] = full[j2];
   string k40 = H3LExportKey("XAUUSD", 0, p40, 40, 2);
   string k60 = H3LExportKey("XAUUSD", 0, p60, 60, 2);
   Check(p40[39].time == p60[59].time && k40 != k60, "history grows with the same last candle: the key changes");
   Check(StringFind(k40, "|40|") > 0 && StringFind(k60, "|60|") > 0, "the key carries the bar count");
   Check(H3LBarsHash(p40, 40, 2) != H3LBarsHash(p60, 60, 2) && StringLen(H3LBarsHash(p40, 40, 2)) == 16, "the content hash differs (16 hex digits)");
   //--- same count and last candle, one OLDER bar corrected
   MqlRates fixed[];
   ArrayResize(fixed, 40);
   for(int j3 = 0; j3 < 40; j3++)
      fixed[j3] = p40[j3];
   fixed[7].high = fixed[7].high + 0.25;
   Check(H3LExportKey("XAUUSD", 0, fixed, 40, 2) != k40, "one older bar corrected (same count, same first and last time): the key changes");
   //--- the last bar's own values change (the candle closed differently after a data fix)
   MqlRates lastfix[];
   ArrayResize(lastfix, 40);
   for(int j4 = 0; j4 < 40; j4++)
      lastfix[j4] = p40[j4];
   lastfix[39].close = lastfix[39].close - 0.5;
   Check(H3LExportKey("XAUUSD", 0, lastfix, 40, 2) != k40, "the last candle's values corrected: the key changes");
   //--- order sensitive: two bars swapped
   MqlRates swapped[];
   ArrayResize(swapped, 40);
   for(int j5 = 0; j5 < 40; j5++)
      swapped[j5] = p40[j5];
   MqlRates tmp = swapped[10];
   swapped[10] = swapped[11];
   swapped[11] = tmp;
   Check(H3LBarsHash(swapped, 40, 2) != H3LBarsHash(p40, 40, 2), "the hash is order sensitive");
   //--- identical set: same key; other as-of / symbol: other key
   MqlRates same[];
   ArrayResize(same, 40);
   for(int j6 = 0; j6 < 40; j6++)
      same[j6] = p40[j6];
   Check(H3LExportKey("XAUUSD", 0, same, 40, 2) == k40, "an identical set gives the identical key (no rewrite)");
   Check(H3LExportKey("XAUUSD", LT(30), same, 40, 2) != k40 && H3LExportKey("XAUUSD.r", 0, same, 40, 2) != k40, "as-of and symbol are part of the key");
   //--- a change below the exported precision is not content
   same[5].high = same[5].high + 0.0004;
   Check(H3LExportKey("XAUUSD", 0, same, 40, 2) == k40, "a change below the exported decimals (2) does not rewrite the file");
   same[5].high = same[5].high + 0.01;
   Check(H3LExportKey("XAUUSD", 0, same, 40, 2) != k40, "a change of one exported unit (0.01) does");
   Check(StringFind(H3LExportKey("XAUUSD", 0, same, 0, 2), "empty") > 0, "an empty set has an explicit key");
  }

void TestSince(void)
  {
   Print("--- since-baseline values: a clear / recovery zeroes them and reports no history as NEW");
   SH3LSince s;
   H3LSinceInit(s);
   H3LSinceNew(s);
   H3LSinceNew(s);
   H3LSinceNew(s);
   H3LSinceChange(s);
   H3LSinceChange(s);
   Check(s.new_total == 3 && s.changes == 2 && s.sess_new == 3 && s.sess_changes == 2 && s.baselines == 0, "counted since the baseline and for the session");
   H3LSinceClear(s);
   Check(s.new_total == 0 && s.changes == 0, "clear / recovery: the values labelled 'since baseline' are zero");
   Check(s.sess_new == 3 && s.sess_changes == 2 && s.baselines == 1, "the session totals stay (Experts log only)");
   H3LSinceNew(s);
   Check(s.new_total == 1 && s.sess_new == 4, "counting restarts from the new baseline");
   //--- the consumer after a recovery: the history of the first evaluation is the baseline, nothing is NEW
   MqlRates w[];
   LWalk(420, 12345, w);
   SH3Params p;
   H3ParamsDefault(p);
   p.lookback = 50;
   SH3Eval ev;
   SH3Track tr[];
   SH3Event evs[];
   H3EvaluateLatest(w, 420, p, ev, tr, evs);
   Check(ev.ne > 3, "fixture is not vacuous: the evaluation holds history events");
   SH3Event nev[];
   int nn = 0;
   datetime cursor = 0;
   int st = H3ConsumeNew(ev, evs, cursor, p.period, nev, nn);
   Check(ev.reliable == false || (st == H3_C_GAP && nn == 0), "no baseline yet (cursor 0): the history events are NOT delivered as new (GAP, re-baseline)");
   if(ev.reliable)
     {
      cursor = H3BaselineCursor(ev);
      st = H3ConsumeNew(ev, evs, cursor, p.period, nev, nn);
      Check(st == H3_C_NOTHING_NEW && nn == 0, "after the baseline at the last closed bar: nothing is NEW although the history has events");
     }
   else
      PrintFormat("  INFO the fixture evaluation is not reliable (%s): the baseline step is not exercised here", ev.reason);
  }

void OnStart(void)
  {
   Print("T003 LAYERS TEST (PROPOSAL helpers; model/helper check, NOT a strategy validation)");
   TestDefinition();
   TestBiasTimeline();
   TestSources();
   TestRun();
   TestLiquidity();
   TestReasons();
   TestShortNames();
   TestTimelineAgainstReplay();
   TestBaseline();
   TestPanelBudget();
   TestLabelSlot();
   TestExportKey();
   TestSince();
   PrintFormat("T003 LAYERS TEST finished: %d passed, %d failed", g_pass, g_fail);
  }
