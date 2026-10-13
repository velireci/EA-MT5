//+------------------------------------------------------------------+
//|                                          T003_LayersTest.mq5     |
//|                                                                  |
//|  T003 visual layers - MT5 script that tests the PURE helpers of  |
//|  src/include/H4BiasLayers.mqh on synthetic bars (generic units,  |
//|  no real prices): the MODEL DISAGREEMENT definition and run, the |
//|  bias timeline rebuilt from the events, the T002 source swings   |
//|  and the HISTORICAL LIQUIDITY selection.                         |
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
   PrintFormat("T003 LAYERS TEST finished: %d passed, %d failed", g_pass, g_fail);
  }
