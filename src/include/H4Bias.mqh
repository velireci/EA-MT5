//+------------------------------------------------------------------+
//| H4Bias.mqh                                                       |
//|                                                                  |
//| T003 - PURE LOGIC for the H4 bias layer (direction change and    |
//| reconfirmation). No chart objects, no series access, no clock,   |
//| no trading API, no Sleep: every function works on an array of    |
//| CLOSED bars (index 0 = oldest) that the caller provides.         |
//|                                                                  |
//| ALL RULES HERE ARE PROPOSALS (tasks/T003-h4-bias-change.md rev.  |
//| 5, P1-P14) awaiting the client's visual validation. They are not |
//| client answers and not trading rules. Nothing here sends,        |
//| modifies or closes an order. The entries-block flags are only    |
//| REPORTED (the sweep-wait one is a technical proposal, F8).       |
//|                                                                  |
//| Builds on H4Structure.mqh (T002), which is reused unchanged:     |
//| swings, FVGs, direction.                                         |
//|                                                                  |
//| Identities (levels, FVGs, events) are built from ABSOLUTE times  |
//| only. Window indexes are used inside a replay and never appear   |
//| in an ID, in a comparison between replays or in a report.        |
//|                                                                  |
//| Verification status: mirrored by tests/t003_reference_test.py (a |
//| Python MODEL) and src/tests/T003_LogicTest.mq5. The MQL5 code    |
//| has NOT been compiled and the MQL5 test has NOT been run.        |
//+------------------------------------------------------------------+
//| AMBIGUITY n: marks every place where the task text is unclear and |
//| the minimal reading was taken (listed in the T003 report):       |
//|  1 RECONFIRMED(INTERNAL) freezes the level (P3); when its FVG is  |
//|  lost the level thaws and is re-derived at the end of that bar    |
//|  (used from the next; rev. 7); 2                                  |
//|  touches only in HOLD/SWEEP_WAIT; 3 which touched FVG is          |
//|  recorded; 4 no continuation/internal events on a wick bar or in  |
//|  HOLD/RECONFIRMED; 5 anchor: the references, located by EXISTING  |
//|  bars (Left bars before each, never time arithmetic), missing     |
//|  history -> LIMITED_BY_HISTORY, nothing invented (rev. 6); 6 flag |
//|  for NONE / seeded HOLD; 7 consumer gap; 8 internal events need a |
//|  level; 9 A/B compares events from B's trusted region; 10 seed    |
//|  'defined'; 11 ties; 12 'the low before it'; 13 HH/LL candidate;  |
//|  14 sweep-wait touch start; 15 flip bar scan; 16 retroactive scan |
//|  range; 17 CONFLICT unreachable; 18 NONE_WICK; 19 wick in         |
//|  SWEEP_WAIT freezes the then current level; 20 (rev. 7) a touch   |
//|  while no protecting level is defined is NOT recorded (20a).     |
//+------------------------------------------------------------------+
#ifndef VELO_H4_BIAS_MQH
#define VELO_H4_BIAS_MQH

#include "H4Structure.mqh"

//--- bias direction (also the sign used by the symmetric code)
#define H3_BULL            1
#define H3_BEAR           (-1)
#define H3_NONE            0

//--- phases of a bias
#define H3_PH_ACTIVE       0
#define H3_PH_HOLD         1
#define H3_PH_RECONFIRMED  2
#define H3_PH_SWEEP_WAIT   3

//--- origin of the bias
#define H3_ORG_NONE        0
#define H3_ORG_BREAK       1
#define H3_ORG_SEED        2

//--- why there is no bias
#define H3_NR_NO_EVIDENCE  0
#define H3_NR_CONFLICT     1

//--- reason of a RECONFIRMED state
#define H3_RR_NONE         0
#define H3_RR_STRUCT       1
#define H3_RR_INTERNAL     2

//--- event types
#define H3_EV_BREAK_SET    0
#define H3_EV_FLIP         1
#define H3_EV_SEED         2
#define H3_EV_CONFLICT     3
#define H3_EV_WICK         4
#define H3_EV_NONE_WICK    5
#define H3_EV_RECONFIRMED  6
#define H3_EV_RECONF_LOST  7
#define H3_EV_INT_SWEEP    8
#define H3_EV_CONTINUATION 9
#define H3_EV_INT_BREAK    10

//--- support flags (P11)
#define H3_FLAG_CONVERGED  0
#define H3_FLAG_SEEDED     1
#define H3_FLAG_LIMITED    2

//--- consumer status
#define H3_C_OK            0
#define H3_C_NOTHING_NEW   1
#define H3_C_NOT_RELIABLE  2
#define H3_C_REDERIVED     3
#define H3_C_GAP           4
#define H3_C_BASELINE      (-1)     // EA only: the baseline was set at this evaluation (no consume call)

//--- what the EA may do with a change between two evaluations (TrackChanges)
#define H3_TC_BASELINE     0        // no comparable previous snapshot: store it, report nothing
#define H3_TC_REPORT       1        // exactly the next closed bar and the previous state reproduced: a real change
#define H3_TC_REDERIVE     2        // rebuild difference, gap or same-bar re-evaluation: never a market change

//--- P10 resolver result
#define H3_R_NONE          0
#define H3_R_BREAK         1
#define H3_R_SEED          2
#define H3_R_CONFLICT      3

//--- parameters (all PROPOSED; small values must work in tests)
struct SH3Params
  {
   int               left;
   int               right;
   int               period;       // seconds
   int               lookback;     // L
   int               rebuild;      // R requested (never below 3*L)
   int               hard_cap;     // HARD_CAP
  };

//--- a level / extreme / interior candidate. idx is a window index: INTERNAL only
struct SH3Cand
  {
   string            id;
   double            price;
   datetime          pivot_time;
   datetime          ext_time;
   datetime          prev_time;
   datetime          known;
   int               idx;
  };

//--- eligible FVG being tracked; f indexes the FVG list of ONE replay: INTERNAL only
struct SH3Track
  {
   int               f;
   string            id;
   bool              invalid;
   bool              recorded;
  };

struct SH3Event
  {
   int               type;
   datetime          bar_time;     // open time of the bar whose close produced the event
   string            ref;          // level id / FVG id the event is about
   string            detail;
   bool              market;
  };

struct SH3State
  {
   int               dir;          // H3_BULL / H3_BEAR / H3_NONE
   int               origin;
   int               none_reason;
   int               phase;
   int               recon_reason;
   datetime          bias_start;
   datetime          origin_ref;
   bool              has_level;
   string            lv_id;
   double            lv_price;
   datetime          lv_pivot;
   datetime          lv_ext;
   datetime          lv_prev;
   datetime          lv_known;
   bool              frozen;
   bool              has_ext;
   string            ex_id;
   double            ex_price;
   bool              ex_consumed;
   bool              has_lint;
   string            li_id;
   double            li_price;
   bool              li_consumed;
   bool              has_wick;
   datetime          wk_src;
   datetime          wk_known;
   datetime          wk_det;
   bool              wk_retro;
   datetime          sweep_time;
   datetime          src_time;
   datetime          wait_start;
   string            rec_id;
   string            pre;
   string            t2dir;
  };

//--- result of one replay (scalars); the arrays travel beside it
struct SH3Rep
  {
   SH3State          st;
   int               nt;
   int               ne;
   int               n;
   string            key_before_last;
   datetime          last_time;
   //--- DIAGNOSTIC counters (behaviour neutral; never part of the state key)
   datetime          nolv_run_start;   // open time of the first bar of the current run of "bias without a level" (0 = none)
   int               nolv_run_bars;    // bars in that run
   string            nolv_cause;       // what started the run: FLIP / BREAK_SET / SEED / LEVEL_DROPPED
   int               nolv_total;       // bars with a bias and no level, whole replay
   int               nolv_runs;        // number of such runs
   int               n_flips;          // FLIP events in the replay
   datetime          last_flip;        // bar time of the last FLIP (0 = none)
   int               flips_after_run;  // FLIPs dated after the current run began (structurally 0)
  };

//--- result of the P11 evaluation (scalars)
struct SH3Eval
  {
   bool              has_state;
   bool              reliable;
   int               flag;
   string            reason;
   string            note;
   int               r_request;
   int               r_req;
   int               r_eff;
   int               b_depth;
   int               warm;
   int               chk;
   int               n_avail;
   string            key;
   string            key_prev;
   datetime          last_time;
   datetime          trusted_from;
   datetime          anchor;
   string            anchor_missing;   // "" or why the history lacks a bar the anchor needs
   bool              prev_ok;
   string            cause;
   SH3State          st;
   int               nt;
   int               ne;           // events carried: 0 unless reliable
  };

//+------------------------------------------------------------------+
//| names and small helpers                                          |
//+------------------------------------------------------------------+
void H3ParamsDefault(SH3Params &p)
  {
   p.left     = 2;
   p.right    = 2;
   p.period   = 14400;
   p.lookback = 300;
   p.rebuild  = 1000;
   p.hard_cap = 5000;
  }

int H3WarmUp(const SH3Params &p)
  {
   return(p.lookback);
  }

int H3CheckDepth(const SH3Params &p)
  {
   return(H3WarmUp(p));
  }

string H3DirName(const int d)
  {
   if(d == H3_BULL)
      return("BULL");
   if(d == H3_BEAR)
      return("BEAR");
   return("NONE");
  }

string H3PhaseName(const int v)
  {
   if(v == H3_PH_HOLD)
      return("HOLD");
   if(v == H3_PH_RECONFIRMED)
      return("RECONFIRMED");
   if(v == H3_PH_SWEEP_WAIT)
      return("SWEEP_WAIT");
   return("ACTIVE");
  }

string H3OriginName(const int v)
  {
   if(v == H3_ORG_BREAK)
      return("BREAK");
   if(v == H3_ORG_SEED)
      return("SEED");
   return("NONE");
  }

string H3NoneReasonName(const int v)
  {
   if(v == H3_NR_CONFLICT)
      return("CONFLICT");
   return("NO_EVIDENCE");
  }

string H3ReconReasonName(const int v)
  {
   if(v == H3_RR_STRUCT)
      return("STRUCT");
   if(v == H3_RR_INTERNAL)
      return("INTERNAL");
   return("");
  }

string H3EventName(const int v)
  {
   if(v == H3_EV_BREAK_SET)
      return("BREAK_SET");
   if(v == H3_EV_FLIP)
      return("FLIP");
   if(v == H3_EV_SEED)
      return("SEED");
   if(v == H3_EV_CONFLICT)
      return("CONFLICT");
   if(v == H3_EV_WICK)
      return("WICK");
   if(v == H3_EV_NONE_WICK)
      return("NONE_WICK");
   if(v == H3_EV_RECONFIRMED)
      return("RECONFIRMED");
   if(v == H3_EV_RECONF_LOST)
      return("RECONF_LOST");
   if(v == H3_EV_INT_SWEEP)
      return("INTERNAL_SWEEP");
   if(v == H3_EV_CONTINUATION)
      return("CONTINUATION");
   return("INTERNAL_BREAK");
  }

string H3FlagName(const int v)
  {
   if(v == H3_FLAG_CONVERGED)
      return("CONVERGED");
   if(v == H3_FLAG_SEEDED)
      return("SEEDED");
   return("LIMITED_BY_HISTORY");
  }

string H3ConsumeName(const int v)
  {
   if(v == H3_C_OK)
      return("OK");
   if(v == H3_C_NOTHING_NEW)
      return("NOTHING_NEW");
   if(v == H3_C_NOT_RELIABLE)
      return("NOT_RELIABLE");
   if(v == H3_C_REDERIVED)
      return("REDERIVED");
   if(v == H3_C_BASELINE)
      return("BASELINE");
   return("GAP");
  }

bool H3IsMarketEvent(const int type)
  {
   return(type == H3_EV_BREAK_SET || type == H3_EV_FLIP || type == H3_EV_SEED || type == H3_EV_WICK ||
          type == H3_EV_RECONFIRMED || type == H3_EV_RECONF_LOST || type == H3_EV_INT_SWEEP);
  }

string H3Tx(const datetime t)
  {
   if(t == 0)
      return("0");
   return(H4TimeStamp(t));
  }

string H3Pf(const double x)
  {
   return(DoubleToString(x, 2));
  }

//+------------------------------------------------------------------+
//| identities: ABSOLUTE times only (technical requirement a).       |
//| These functions take no index argument by design.                |
//+------------------------------------------------------------------+
string H3LevelId(const string kind, const datetime t_level, const datetime t_ext, const datetime t_prev)
  {
   return(kind + H4TimeStamp(t_level) + "_" + H4TimeStamp(t_ext) + "_" + H4TimeStamp(t_prev));
  }

string H3ExtId(const string kind, const datetime t_ext, const datetime t_prev)
  {
   return(kind + H4TimeStamp(t_ext) + "_" + H4TimeStamp(t_prev));
  }

string H3InteriorId(const string kind, const datetime t_int, const datetime t_ext)
  {
   return(kind + H4TimeStamp(t_int) + "_" + H4TimeStamp(t_ext));
  }

string H3EventId(const int type, const datetime bar_time, const string ref)
  {
   return(H3EventName(type) + "@" + H4TimeStamp(bar_time) + "#" + ref);
  }

string H3EventText(const SH3Event &e)
  {
   return(H3EventId(e.type, e.bar_time, e.ref) + "{" + e.detail + "}");
  }

//+------------------------------------------------------------------+
//| state initialisation (no ZeroMemory: the structs hold strings)   |
//+------------------------------------------------------------------+
void H3StateInit(SH3State &st)
  {
   st.dir          = H3_NONE;
   st.origin       = H3_ORG_NONE;
   st.none_reason  = H3_NR_NO_EVIDENCE;
   st.phase        = H3_PH_ACTIVE;
   st.recon_reason = H3_RR_NONE;
   st.bias_start   = 0;
   st.origin_ref   = 0;
   st.has_level    = false;
   st.lv_id        = "";
   st.lv_price     = 0.0;
   st.lv_pivot     = 0;
   st.lv_ext       = 0;
   st.lv_prev      = 0;
   st.lv_known     = 0;
   st.frozen       = false;
   st.has_ext      = false;
   st.ex_id        = "";
   st.ex_price     = 0.0;
   st.ex_consumed  = false;
   st.has_lint     = false;
   st.li_id        = "";
   st.li_price     = 0.0;
   st.li_consumed  = false;
   st.has_wick     = false;
   st.wk_src       = 0;
   st.wk_known     = 0;
   st.wk_det       = 0;
   st.wk_retro     = false;
   st.sweep_time   = 0;
   st.src_time     = 0;
   st.wait_start   = 0;
   st.rec_id       = "";
   st.pre          = "";
   st.t2dir        = "UNKNOWN";
  }

//--- field-wise copy (the structs hold strings: no memcpy, no ZeroMemory)
void H3StateCopy(const SH3State &src, SH3State &dst)
  {
   dst.dir          = src.dir;
   dst.origin       = src.origin;
   dst.none_reason  = src.none_reason;
   dst.phase        = src.phase;
   dst.recon_reason = src.recon_reason;
   dst.bias_start   = src.bias_start;
   dst.origin_ref   = src.origin_ref;
   dst.has_level    = src.has_level;
   dst.lv_id        = src.lv_id;
   dst.lv_price     = src.lv_price;
   dst.lv_pivot     = src.lv_pivot;
   dst.lv_ext       = src.lv_ext;
   dst.lv_prev      = src.lv_prev;
   dst.lv_known     = src.lv_known;
   dst.frozen       = src.frozen;
   dst.has_ext      = src.has_ext;
   dst.ex_id        = src.ex_id;
   dst.ex_price     = src.ex_price;
   dst.ex_consumed  = src.ex_consumed;
   dst.has_lint     = src.has_lint;
   dst.li_id        = src.li_id;
   dst.li_price     = src.li_price;
   dst.li_consumed  = src.li_consumed;
   dst.has_wick     = src.has_wick;
   dst.wk_src       = src.wk_src;
   dst.wk_known     = src.wk_known;
   dst.wk_det       = src.wk_det;
   dst.wk_retro     = src.wk_retro;
   dst.sweep_time   = src.sweep_time;
   dst.src_time     = src.src_time;
   dst.wait_start   = src.wait_start;
   dst.rec_id       = src.rec_id;
   dst.pre          = src.pre;
   dst.t2dir        = src.t2dir;
  }

void H3CandInit(SH3Cand &c)
  {
   c.id         = "";
   c.price      = 0.0;
   c.pivot_time = 0;
   c.ext_time   = 0;
   c.prev_time  = 0;
   c.known      = 0;
   c.idx        = -1;
  }

void H3CandCopy(const SH3Cand &src, SH3Cand &dst)
  {
   dst.id         = src.id;
   dst.price      = src.price;
   dst.pivot_time = src.pivot_time;
   dst.ext_time   = src.ext_time;
   dst.prev_time  = src.prev_time;
   dst.known      = src.known;
   dst.idx        = src.idx;
  }

void H3AddEvent(SH3Event &events[], int &ne, const int type, const datetime bar_time,
                const string ref, const string detail)
  {
   ArrayResize(events, ne + 1, 64);
   events[ne].type     = type;
   events[ne].bar_time = bar_time;
   events[ne].ref      = ref;
   events[ne].detail   = detail;
   events[ne].market   = H3IsMarketEvent(type);
   ne++;
  }

//+------------------------------------------------------------------+
//| swings known at a bar                                            |
//+------------------------------------------------------------------+
//--- number of swings confirmed by the close of bar `upto` (window index)
int H3KnownCount(const SH4Swing &sw[], const int ns, const int right, const int upto)
  {
   int c = 0;
   for(int i = 0; i < ns; i++)
     {
      if(sw[i].index + right <= upto)
         c++;
      else
         break;
     }
   return(c);
  }

//+------------------------------------------------------------------+
//| P2 / P14 candidates from the first nk swings, context d.         |
//| d=+1 bullish context: extremes are highs, level is a low.        |
//| d=-1 bearish context: extremes are lows, level is a high.        |
//| level: most adverse swing strictly between the previous extreme  |
//|        and the latest higher high / lower low (ties: earliest,   |
//|        AMBIGUITY 11). ext: that latest higher high / lower low.  |
//| lint: most adverse swing after the pivot of ext (interior).      |
//+------------------------------------------------------------------+
void H3DeriveLevel(const SH4Swing &sw[], const int nk, const int d,
                   bool &has_lvl, SH3Cand &lvl, bool &has_ex, SH3Cand &ex, bool &has_li, SH3Cand &li)
  {
   has_lvl = false;
   has_ex  = false;
   has_li  = false;
   H3CandInit(lvl);
   H3CandInit(ex);
   H3CandInit(li);
   bool ext_hi = (d > 0);
   int exts[];
   int oths[];
   ArrayResize(exts, 0);
   ArrayResize(oths, 0);
   int ne = 0;
   int no = 0;
   for(int i = 0; i < nk; i++)
     {
      if(sw[i].is_high == ext_hi)
        {
         ArrayResize(exts, ne + 1, 32);
         exts[ne] = i;
         ne++;
        }
      else
        {
         ArrayResize(oths, no + 1, 32);
         oths[no] = i;
         no++;
        }
     }
   int k = -1;
   for(int j = ne - 1; j > 0; j--)
     {
      if(d * sw[exts[j]].price > d * sw[exts[j - 1]].price)
        {
         k = j;
         break;
        }
     }
   if(k < 0)
      return;
   int e  = exts[k];
   int pe = exts[k - 1];
   has_ex      = true;
   ex.id         = H3ExtId((d > 0 ? "HH" : "LL"), sw[e].pivot_time, sw[pe].pivot_time);
   ex.price      = sw[e].price;
   ex.pivot_time = sw[e].pivot_time;
   ex.prev_time  = sw[pe].pivot_time;
   ex.known      = sw[e].confirm_time;
   ex.idx        = sw[e].index;
   //--- AMBIGUITY 12: "the low before it" is the immediately preceding extreme in the list, so a
   //--- minor swing of the extreme kind inside a leg bounds the interval and can define the level.
   //--- AMBIGUITY 11: equal prices -> the earliest pivot wins.
   int best = -1;
   for(int q = 0; q < no; q++)
     {
      int s = oths[q];
      if(sw[pe].pivot_time < sw[s].pivot_time && sw[s].pivot_time < sw[e].pivot_time)
        {
         if(best < 0 || d * sw[s].price < d * sw[best].price)
            best = s;
        }
     }
   if(best < 0)
      return;
   has_lvl        = true;
   lvl.id         = H3LevelId((d > 0 ? "SL" : "SH"), sw[best].pivot_time, sw[e].pivot_time, sw[pe].pivot_time);
   lvl.price      = sw[best].price;
   lvl.pivot_time = sw[best].pivot_time;
   lvl.ext_time   = sw[e].pivot_time;
   lvl.prev_time  = sw[pe].pivot_time;
   lvl.known      = (sw[best].confirm_time > sw[e].confirm_time ? sw[best].confirm_time : sw[e].confirm_time);
   lvl.idx        = sw[best].index;
   int bi = -1;
   for(int r = 0; r < no; r++)
     {
      int s2 = oths[r];
      if(sw[s2].pivot_time > sw[e].pivot_time)
        {
         if(bi < 0 || d * sw[s2].price < d * sw[bi].price)
            bi = s2;
        }
     }
   if(bi >= 0)
     {
      has_li        = true;
      li.id         = H3InteriorId((d > 0 ? "IL" : "IH"), sw[bi].pivot_time, sw[e].pivot_time);
      li.price      = sw[bi].price;
      li.pivot_time = sw[bi].pivot_time;
      li.ext_time   = sw[e].pivot_time;
      li.known      = sw[bi].confirm_time;
      li.idx        = sw[bi].index;
     }
  }

//+------------------------------------------------------------------+
//| scans (s = adverse sign: +1 means above the level is adverse)    |
//+------------------------------------------------------------------+
double H3AdverseExt(const MqlRates &bar, const int s)
  {
   if(s > 0)
      return(bar.high);
   return(bar.low);
  }

//--- bars i_from..i_to: body_broken, and the index of the last wick bar (-1 none)
void H3ScanLevel(const MqlRates &bars[], const int i_from, const int i_to, const double price,
                 const int s, bool &body_broken, int &wick_idx)
  {
   body_broken = false;
   wick_idx    = -1;
   for(int i = i_from; i <= i_to; i++)
     {
      if(s * (bars[i].close - price) > 0)
        {
         body_broken = true;
         wick_idx    = -1;
         return;
        }
      if(s * (H3AdverseExt(bars[i], s) - price) > 0)
         wick_idx = i;
     }
  }

bool H3CloseBeyondAny(const MqlRates &bars[], const int i_from, const int i_to, const double price, const int s)
  {
   for(int i = i_from; i <= i_to; i++)
     {
      if(s * (bars[i].close - price) > 0)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| state text (canonical; same format as the Python model)          |
//+------------------------------------------------------------------+
string H3WickText(const SH3State &st)
  {
   if(!st.has_wick)
      return("-");
   return(H3Tx(st.wk_src) + "/" + H3Tx(st.wk_known) + "/" + H3Tx(st.wk_det) + "/" + (st.wk_retro ? "1" : "0"));
  }

string H3TracksText(const SH3Track &tracks[], const int nt)
  {
   if(nt <= 0)
      return("-");
   string out = "";
   for(int i = 0; i < nt; i++)
     {
      string sname = "FRESH";
      if(tracks[i].invalid)
         sname = "INVALID";
      else
         if(tracks[i].recorded)
            sname = "RECORDED";
      if(i > 0)
         out += ",";
      out += tracks[i].id + ":" + sname;
     }
   return(out);
  }

//--- what replays A and B must agree on: no window index, no depth
string H3StateKey(const SH3State &st, const SH3Track &tracks[], const int nt)
  {
   string lv = "-";
   if(st.has_level)
      lv = st.lv_id + "@" + H3Pf(st.lv_price);
   string rec = "-";
   if(st.rec_id != "")
      rec = st.rec_id;
   string rsn = "-";
   if(st.recon_reason != H3_RR_NONE)
      rsn = H3ReconReasonName(st.recon_reason);
   string ph = "-";
   string nr = "-";
   if(st.dir != H3_NONE)
      ph = H3PhaseName(st.phase);
   else
      nr = H3NoneReasonName(st.none_reason);
   return("BIAS=" + H3DirName(st.dir) + ";PH=" + ph + ";ORG=" + H3OriginName(st.origin) + ";NR=" + nr +
          ";LV=" + lv + ";FRZ=" + (st.frozen ? "1" : "0") + ";WK=" + H3WickText(st) + ";SW=" + H3Tx(st.sweep_time) +
          ";REC=" + rec + ";RSN=" + rsn + ";EL=" + H3TracksText(tracks, nt));
  }

//--- S3 (client): new entries of the previous setup are blocked in HOLD
bool H3HoldBlock(const SH3State &st)
  {
   return(st.dir != H3_NONE && st.phase == H3_PH_HOLD);
  }

//--- TECHNICAL PROPOSAL (F8, not a client statement): block during SWEEP_WAIT.
//--- A separate flag so the owner decides; nothing here acts on it.
bool H3SweepBlock(const SH3State &st)
  {
   return(st.dir != H3_NONE && st.phase == H3_PH_SWEEP_WAIT);
  }

string H3StateText(const SH3State &st, const SH3Track &tracks[], const int nt)
  {
   return(H3StateKey(st, tracks, nt) + ";LI=" + (st.has_lint ? st.li_id : "-") + ";PRE=" + (st.pre != "" ? st.pre : "-") +
          ";T2=" + st.t2dir + ";BLKH=" + (H3HoldBlock(st) ? "1" : "0") + ";BLKS=" + (H3SweepBlock(st) ? "1" : "0"));
  }

string H3EventsText(const SH3Event &events[], const int ne, const datetime t_from)
  {
   string out = "";
   int cnt = 0;
   for(int i = 0; i < ne; i++)
     {
      if(events[i].bar_time >= t_from)
        {
         if(cnt > 0)
            out += "|";
         out += H3EventText(events[i]);
         cnt++;
        }
     }
   if(cnt == 0)
      return("-");
   return(out);
  }

string H3ReplayText(const SH3Rep &rep, const SH3Track &tracks[], const SH3Event &events[])
  {
   return("REPLAY;ST=" + H3StateText(rep.st, tracks, rep.nt) + ";EV=" + H3EventsText(events, rep.ne, 0));
  }

//+------------------------------------------------------------------+
//| P10 precedence for one bar in NONE (pure).                       |
//| A break outranks the seed; breaks of both kinds give CONFLICT    |
//| and the seed never overwrites a CONFLICT on that bar.            |
//+------------------------------------------------------------------+
int H3P10Resolve(const int n_up, const int n_dn, const int seed_dir, int &rdir)
  {
   rdir = H3_NONE;
   if(n_up > 0 && n_dn > 0)
      return(H3_R_CONFLICT);
   if(n_up > 0)
     {
      rdir = H3_BULL;
      return(H3_R_BREAK);
     }
   if(n_dn > 0)
     {
      rdir = H3_BEAR;
      return(H3_R_BREAK);
     }
   if(seed_dir != H3_NONE)
     {
      rdir = seed_dir;
      return(H3_R_SEED);
     }
   return(H3_R_NONE);
  }

//--- earliest time among open_t and the three pivot times of one candidate
datetime H3OriginRef(const datetime open_t, const SH3Cand &c)
  {
   datetime r = open_t;
   if(c.pivot_time != 0 && c.pivot_time < r)
      r = c.pivot_time;
   if(c.ext_time != 0 && c.ext_time < r)
      r = c.ext_time;
   if(c.prev_time != 0 && c.prev_time < r)
      r = c.prev_time;
   return(r);
  }

//+------------------------------------------------------------------+
//| FVG tracking                                                     |
//+------------------------------------------------------------------+
//--- P5 / P14: type = bias direction, candle A open time at or after the source time
//--- (the physical wick bar, or the sweep bar). Not detected_at.
bool H3FvgEligible(const SH4Fvg &f, const SH3State &st, const bool bull)
  {
   return(f.bullish == bull && f.time_a >= st.src_time);
  }

//--- AMBIGUITY 14: the sweep wait counts touches from the close of the sweep bar
//--- (wait_start); eligible FVGs have candle A at or after the sweep bar's open.
//--- (re)build the eligible FVG tracks for the current wait (P5 / P14).
//--- Eligible: type = bias direction, candle A open >= src_time, C closed by t.
void H3BuildTracks(const SH3State &st, SH3Track &tracks[], int &nt, const SH4Fvg &fv[], const int nf,
                   const MqlRates &bars[], const int t, const bool bull)
  {
   nt = 0;
   ArrayResize(tracks, 0);
   for(int fi = 0; fi < nf; fi++)
     {
      if(fv[fi].index_a + 2 > t)
         continue;
      if(!H3FvgEligible(fv[fi], st, bull))
         continue;
      bool invalid = false;
      for(int i = fv[fi].index_a + 3; i <= t; i++)
        {
         if(fv[fi].bullish)
           {
            if(bars[i].close < fv[fi].lower)
               invalid = true;
           }
         else
           {
            if(bars[i].close > fv[fi].upper)
               invalid = true;
           }
        }
      ArrayResize(tracks, nt + 1, 16);
      tracks[nt].f        = fi;
      tracks[nt].id       = fv[fi].id;
      tracks[nt].invalid  = invalid;
      tracks[nt].recorded = false;
      nt++;
     }
  }

double H3DistToZone(const SH4Fvg &f, const double price)
  {
   if(f.lower <= price && price <= f.upper)
      return(0.0);
   if(price < f.lower)
      return(f.lower - price);
   return(price - f.upper);
  }

//+------------------------------------------------------------------+
//| the replay (P9): one causal pass over closed bars                |
//+------------------------------------------------------------------+
//--- P10: start from NONE only.
//--- AMBIGUITY 13: an extreme candidate (latest HH / LL) is "the latest swing high above
//--- its immediate predecessor"; a candidate already crossed by a close since its pivot is
//--- consumed and ignored. AMBIGUITY 18: NONE_WICK is recorded for P2 levels only.
//--- AMBIGUITY 17: CONFLICT cannot occur with consumed candidates excluded (see report);
//--- the defensive branch stays and is tested through H3P10Resolve.
void H3NoneStep(const int t, const MqlRates &bars[], const SH4Swing &sw[], const int ns, const SH3Params &p,
                SH3State &st, SH3Event &events[], int &ne)
  {
   datetime open_t  = bars[t].time;
   datetime close_t = open_t + p.period;
   int nkb = H3KnownCount(sw, ns, p.right, t - 1);
   int nki = H3KnownCount(sw, ns, p.right, t);
   SH3Cand up[];
   SH3Cand dn[];
   ArrayResize(up, 0);
   ArrayResize(dn, 0);
   int nup = 0;
   int ndn = 0;
   for(int ci = 0; ci < 2; ci++)
     {
      int ctx = (ci == 0 ? H3_BEAR : H3_BULL);
      int s = -ctx;
      bool has_l, has_e, has_i;
      SH3Cand lvl, ex, lint;
      H3DeriveLevel(sw, nkb, ctx, has_l, lvl, has_e, ex, has_i, lint);
      if(has_l)
        {
         if(!H3CloseBeyondAny(bars, lvl.idx + 1, t - 1, lvl.price, s))
           {
            if(s * (bars[t].close - lvl.price) > 0)
              {
               if(s > 0)
                 {
                  ArrayResize(up, nup + 1, 8);
                  H3CandCopy(lvl, up[nup]);
                  nup++;
                 }
               else
                 {
                  ArrayResize(dn, ndn + 1, 8);
                  H3CandCopy(lvl, dn[ndn]);
                  ndn++;
                 }
              }
            else
               if(s * (H3AdverseExt(bars[t], s) - lvl.price) > 0)
                  H3AddEvent(events, ne, H3_EV_NONE_WICK, open_t, lvl.id,
                             "lvl=" + lvl.id + ";src=" + H4TimeStamp(open_t));
           }
        }
      if(has_e)
        {
         //--- favourable break of the latest HH (ctx=+1) / LL (ctx=-1)
         if(!H3CloseBeyondAny(bars, ex.idx + 1, t - 1, ex.price, ctx))
           {
            if(ctx * (bars[t].close - ex.price) > 0)
              {
               if(ctx > 0)
                 {
                  ArrayResize(up, nup + 1, 8);
                  H3CandCopy(ex, up[nup]);
                  nup++;
                 }
               else
                 {
                  ArrayResize(dn, ndn + 1, 8);
                  H3CandCopy(ex, dn[ndn]);
                  ndn++;
                 }
              }
           }
        }
     }
   //--- seed candidate (only used when step 1 produced neither a bias nor a conflict)
   //--- AMBIGUITY 10: see below
   int seed_dir = H3_NONE;
   SH3Cand seed_lvl;
   H3CandInit(seed_lvl);
   string t2n = H4DirName(H4DeriveDirection(sw, nki));
   if(nup == 0 && ndn == 0 && (t2n == "BEARISH" || t2n == "BULLISH"))
     {
      int d = (t2n == "BULLISH" ? H3_BULL : H3_BEAR);
      bool has_l2, has_e2, has_i2;
      SH3Cand lvl2, ex2, lint2;
      H3DeriveLevel(sw, nki, d, has_l2, lvl2, has_e2, ex2, has_i2, lint2);
      //--- AMBIGUITY 10: "defined" = not body-broken by a bar up to t-1 (P2 wording);
      //--- bar t closing beyond its own seed level is handled by the retroactive scan.
      if(has_l2 && !H3CloseBeyondAny(bars, lvl2.idx + 1, t - 1, lvl2.price, -d))
        {
         seed_dir = d;
         H3CandCopy(lvl2, seed_lvl);
        }
     }
   int rdir = H3_NONE;
   int res = H3P10Resolve(nup, ndn, seed_dir, rdir);
   st.none_reason = H3_NR_NO_EVIDENCE;
   if(res == H3_R_CONFLICT)
     {
      st.none_reason = H3_NR_CONFLICT;
      H3AddEvent(events, ne, H3_EV_CONFLICT, open_t, up[0].id + "+" + dn[0].id,
                 "up=" + up[0].id + ";dn=" + dn[0].id);
      return;
     }
   if(res == H3_R_BREAK)
     {
      int d2 = rdir;
      st.dir        = d2;
      st.origin     = H3_ORG_BREAK;
      st.phase      = H3_PH_ACTIVE;
      st.bias_start = close_t;
      if(d2 == H3_BULL)
        {
         st.origin_ref = H3OriginRef(open_t, up[0]);
         for(int a = 1; a < nup; a++)
           {
            datetime x = H3OriginRef(open_t, up[a]);
            if(x < st.origin_ref)
               st.origin_ref = x;
           }
         H3AddEvent(events, ne, H3_EV_BREAK_SET, open_t, up[0].id,
                    "dir=" + H3DirName(d2) + ";from=NONE;known=" + H4TimeStamp(up[0].known) + ";t002=" + t2n);
        }
      else
        {
         st.origin_ref = H3OriginRef(open_t, dn[0]);
         for(int b = 1; b < ndn; b++)
           {
            datetime y = H3OriginRef(open_t, dn[b]);
            if(y < st.origin_ref)
               st.origin_ref = y;
           }
         H3AddEvent(events, ne, H3_EV_BREAK_SET, open_t, dn[0].id,
                    "dir=" + H3DirName(d2) + ";from=NONE;known=" + H4TimeStamp(dn[0].known) + ";t002=" + t2n);
        }
      return;
     }
   if(res == H3_R_SEED)
     {
      int d3 = rdir;
      SH3Cand refs;
      H3CandInit(refs);
      refs.pivot_time = seed_lvl.pivot_time;
      refs.ext_time   = seed_lvl.ext_time;
      refs.prev_time  = seed_lvl.prev_time;
      //--- the swings the T002 direction used: last two highs and last two lows
      datetime lo = open_t;
      int nh = 0;
      int nl = 0;
      for(int i = nki - 1; i >= 0; i--)
        {
         if(sw[i].is_high)
           {
            if(nh < 2)
              {
               nh++;
               if(sw[i].pivot_time < lo)
                  lo = sw[i].pivot_time;
              }
           }
         else
           {
            if(nl < 2)
              {
               nl++;
               if(sw[i].pivot_time < lo)
                  lo = sw[i].pivot_time;
              }
           }
        }
      st.dir        = d3;
      st.origin     = H3_ORG_SEED;
      st.phase      = H3_PH_ACTIVE;
      st.bias_start = close_t;
      st.origin_ref = H3OriginRef(lo, refs);
      H3AddEvent(events, ne, H3_EV_SEED, open_t, seed_lvl.id,
                 "dir=" + H3DirName(d3) + ";t002=" + t2n);
     }
  }

//--- AMBIGUITY 15: after a flip the new bias has no level and origin BREAK; the level is
//--- derived at the end of the flip bar and the retroactive scan includes the flip bar.
void H3DoFlip(const int t, const MqlRates &bars[], const SH3Params &p, SH3State &st,
              SH3Track &tracks[], int &nt, SH3Event &events[], int &ne)
  {
   datetime open_t  = bars[t].time;
   datetime close_t = open_t + p.period;
   int old = st.dir;
   string ref = st.lv_id;
   datetime known = st.lv_known;
   SH3Cand c;
   H3CandInit(c);
   c.pivot_time = st.lv_pivot;
   c.ext_time   = st.lv_ext;
   c.prev_time  = st.lv_prev;
   st.origin_ref = H3OriginRef(open_t, c);
   st.dir          = -old;
   st.origin       = H3_ORG_BREAK;
   st.phase        = H3_PH_ACTIVE;
   st.recon_reason = H3_RR_NONE;
   st.bias_start   = close_t;
   st.has_level    = false;
   st.lv_id        = "";
   st.frozen       = false;
   st.has_ext      = false;
   st.has_lint     = false;
   st.has_wick     = false;
   st.wk_retro     = false;
   st.sweep_time   = 0;
   st.src_time     = 0;
   st.wait_start   = 0;
   st.rec_id       = "";
   nt = 0;
   ArrayResize(tracks, 0);
   H3AddEvent(events, ne, H3_EV_FLIP, open_t, ref,
              "dir=" + H3DirName(st.dir) + ";from=" + H3DirName(old) + ";known=" + H4TimeStamp(known));
  }

//--- common part of every HOLD start (wick at t, restart, retroactive).
//--- AMBIGUITY 19: a wick during SWEEP_WAIT starts HOLD with the then current level frozen (it
//--- was not frozen before). A wick during RECONFIRMED already meets a frozen level.
void H3StartHold(const int t, const MqlRates &bars[], const SH3Params &p, const SH4Fvg &fv[], const int nf,
                 SH3State &st, SH3Track &tracks[], int &nt, const datetime wk_src, const datetime wk_det,
                 const bool retro)
  {
   st.phase        = H3_PH_HOLD;
   st.frozen       = true;
   st.recon_reason = H3_RR_NONE;
   st.rec_id       = "";
   st.has_wick     = true;
   st.wk_src       = wk_src;
   st.wk_known     = wk_src + p.period;
   st.wk_det       = wk_det;
   st.wk_retro     = retro;
   st.sweep_time   = 0;
   st.src_time     = wk_src;
   st.wait_start   = wk_det;
   st.has_ext      = false;
   st.has_lint     = false;
   H3BuildTracks(st, tracks, nt, fv, nf, bars, t, st.dir == H3_BULL);
  }

void H3AddWickEvent(const datetime open_t, const SH3State &st, const bool restart, SH3Event &events[], int &ne)
  {
   H3AddEvent(events, ne, H3_EV_WICK, open_t, st.lv_id,
              "dir=" + H3DirName(st.dir) + ";lvl=" + st.lv_id + ";sw=" + H4TimeStamp(st.wk_src) +
              ";sk=" + H4TimeStamp(st.wk_known) + ";det=" + H4TimeStamp(st.wk_det) +
              ";retro=" + (st.wk_retro ? "1" : "0") + ";restart=" + (restart ? "1" : "0"));
  }

//--- step (2) of the order inside one bar. Returns true when the bias flipped.
bool H3BiasStep(const int t, const MqlRates &bars[], const SH3Params &p, const SH4Fvg &fv[], const int nf,
                SH3State &st, SH3Track &tracks[], int &nt, SH3Event &events[], int &ne)
  {
   datetime open_t  = bars[t].time;
   datetime close_t = open_t + p.period;
   int d  = st.dir;
   int s  = -d;
   int ph = st.phase;
   if(st.has_level)
     {
      double P = st.lv_price;
      if(s * (bars[t].close - P) > 0)
        {
         H3DoFlip(t, bars, p, st, tracks, nt, events, ne);
         return(true);
        }
      if(s * (H3AdverseExt(bars[t], s) - P) > 0)
        {
         bool restart = (ph == H3_PH_HOLD || ph == H3_PH_RECONFIRMED);
         H3StartHold(t, bars, p, fv, nf, st, tracks, nt, open_t, close_t, false);
         H3AddWickEvent(open_t, st, restart, events, ne);
         return(false);
        }
     }
   //--- AMBIGUITY 4: continuation / internal events and sweeps are produced only in ACTIVE and
   //--- SWEEP_WAIT (the state table lists them under ACTIVE) and never on a wick bar.
   if(ph != H3_PH_ACTIVE && ph != H3_PH_SWEEP_WAIT)
      return(false);
   if(st.has_ext && !st.ex_consumed && d * (bars[t].close - st.ex_price) > 0)
     {
      st.ex_consumed = true;
      H3AddEvent(events, ne, H3_EV_CONTINUATION, open_t, st.ex_id,
                 "dir=" + H3DirName(d) + ";ext=" + st.ex_id);
     }
   if(st.has_level && st.has_lint && !st.li_consumed)
     {
      if(s * (bars[t].close - st.li_price) > 0)
        {
         st.li_consumed = true;
         H3AddEvent(events, ne, H3_EV_INT_BREAK, open_t, st.li_id,
                    "dir=" + H3DirName(d) + ";lint=" + st.li_id);
        }
      else
         if(s * (H3AdverseExt(bars[t], s) - st.li_price) > 0)
           {
            bool restart2 = (ph == H3_PH_SWEEP_WAIT);
            st.phase      = H3_PH_SWEEP_WAIT;
            st.sweep_time = open_t;
            st.src_time   = open_t;
            st.wait_start = close_t;
            st.rec_id     = "";
            H3BuildTracks(st, tracks, nt, fv, nf, bars, t, d == H3_BULL);
            H3AddEvent(events, ne, H3_EV_INT_SWEEP, open_t, st.li_id,
                       "dir=" + H3DirName(d) + ";lint=" + st.li_id + ";sweep=" + H4TimeStamp(open_t) +
                       ";restart=" + (restart2 ? "1" : "0"));
           }
     }
   return(false);
  }

//--- step (3): FVG eligibility / invalidation / touch for bar t (revision 7).
//--- RECONFIRMED(INTERNAL) freezes the level known before bar t; when its FVG is lost the level
//--- thaws on this bar and the derive step (4) of the SAME bar re-derives it (used from bar
//--- t+1) unless another FVG is touched on this bar (frozen again). AMBIGUITY 1, P3/P14.
void H3FvgStep(const int t, const MqlRates &bars[], const SH4Fvg &fv[], const int nf,
               SH3State &st, SH3Track &tracks[], int &nt, SH3Event &events[], int &ne)
  {
   datetime open_t = bars[t].time;
   int d  = st.dir;
   int ph = st.phase;
   if(ph != H3_PH_HOLD && ph != H3_PH_SWEEP_WAIT && ph != H3_PH_RECONFIRMED)
      return;
   //--- AMBIGUITY 2: touches are evaluated only while the state is HOLD or SWEEP_WAIT; a touch
   //--- during RECONFIRMED is not remembered. After RECONF_LOST the fall-back and a new touch
   //--- may happen on the same bar (order: invalidate, fall back, then touch).
   //--- newly confirmed eligible FVG (candle C = bar t)
   int a = t - 2;
   if(a >= 0)
     {
      for(int fi = 0; fi < nf; fi++)
        {
         if(fv[fi].index_a == a && H3FvgEligible(fv[fi], st, d == H3_BULL))
           {
            ArrayResize(tracks, nt + 1, 16);
            tracks[nt].f        = fi;
            tracks[nt].id       = fv[fi].id;
            tracks[nt].invalid  = false;
            tracks[nt].recorded = false;
            nt++;
           }
        }
     }
   for(int k = 0; k < nt; k++)
     {
      int f = tracks[k].f;
      if(fv[f].index_a + 3 > t)
         continue;
      if(!tracks[k].invalid)
        {
         if(fv[f].bullish)
           {
            if(bars[t].close < fv[f].lower)
               tracks[k].invalid = true;
           }
         else
           {
            if(bars[t].close > fv[f].upper)
               tracks[k].invalid = true;
           }
        }
     }
   if(st.phase == H3_PH_RECONFIRMED)
     {
      for(int m = 0; m < nt; m++)
        {
         if(tracks[m].recorded && tracks[m].invalid)
           {
            tracks[m].recorded = false;
            int to_ph = (st.recon_reason == H3_RR_STRUCT ? H3_PH_HOLD : H3_PH_SWEEP_WAIT);
            H3AddEvent(events, ne, H3_EV_RECONF_LOST, open_t, tracks[m].id,
                       "fvg=" + tracks[m].id + ";to=" + H3PhaseName(to_ph));
            if(st.recon_reason == H3_RR_INTERNAL)
              {
               //--- THAW: the level was frozen by the internal reconfirmation only. The derive
               //--- step of THIS bar re-derives it from the closed bars up to t (used from t+1).
               st.frozen = false;
              }
            st.phase        = to_ph;
            st.recon_reason = H3_RR_NONE;
            st.rec_id       = "";
           }
        }
     }
   if(st.phase == H3_PH_HOLD || st.phase == H3_PH_SWEEP_WAIT)
     {
      //--- AMBIGUITY 3: if several eligible FVGs are touched on one bar, the one nearest to the
      //--- bar's close is recorded (T002 H4SelBefore: distance, newer confirmation, id).
      int best = -1;
      double bestd = 0.0;
      for(int q = 0; q < nt; q++)
        {
         //--- AMBIGUITY 20a (rev. 7): a touch while NO protecting level is defined is not
         //--- recorded (no trustworthy RECONFIRMED(INTERNAL) without a level to freeze); a later
         //--- touch with a level can record. HOLD always has a level.
         if(st.phase == H3_PH_SWEEP_WAIT && !st.has_level)
            break;
         if(tracks[q].invalid)
            continue;
         int g = tracks[q].f;
         if(fv[g].index_a + 3 > t)
            continue;
         if(bars[t].time >= st.wait_start && bars[t].low <= fv[g].upper && bars[t].high >= fv[g].lower)
           {
            double dd = H3DistToZone(fv[g], bars[t].close);
            if(best < 0 || H4SelBefore(fv[g], dd, fv[tracks[best].f], bestd))
              {
               best  = q;
               bestd = dd;
              }
           }
        }
      if(best >= 0)
        {
         //--- AMBIGUITY 1 (rev. 6): P3 says the level is frozen during HOLD and RECONFIRMED, also
         //--- when the reason is INTERNAL; SWEEP_WAIT keeps updating it (P14 proposal). At the
         //--- touch the level KNOWN BEFORE the touching candle is frozen: this bar's derive step
         //--- is skipped (frozen), so a swing confirmed by the touching candle cannot change it.
         int reason = (st.phase == H3_PH_HOLD ? H3_RR_STRUCT : H3_RR_INTERNAL);
         //--- the continuation / interior candidates are kept (unused while RECONFIRMED, refreshed
         //--- by the derive step of the thaw bar), so no event is lost on the bar after a thaw.
         if(reason == H3_RR_INTERNAL)
            st.frozen = true;
         st.phase        = H3_PH_RECONFIRMED;
         st.recon_reason = reason;
         st.rec_id       = tracks[best].id;
         tracks[best].recorded = true;
         H3AddEvent(events, ne, H3_EV_RECONFIRMED, open_t, tracks[best].id,
                    "fvg=" + tracks[best].id + ";reason=" + H3ReconReasonName(reason));
        }
     }
  }

//--- step (4): candidates for the NEXT bar from the prefix including bar t.
//--- AMBIGUITY 8: the interior level exists only together with a defined protecting level
//--- (P14), so INTERNAL_SWEEP / INTERNAL_BREAK are never raised for a bias without a level.
//--- AMBIGUITY 16: the retroactive scan covers the bars after the level's pivot up to and
//--- including bar t; detected_at = max(level known, wick known, bias start).
void H3DeriveStep(const int t, const MqlRates &bars[], const SH4Swing &sw[], const int ns, const SH3Params &p,
                  const SH4Fvg &fv[], const int nf, SH3State &st, SH3Track &tracks[], int &nt,
                  SH3Event &events[], int &ne)
  {
   if(st.dir == H3_NONE || st.frozen)
      return;
   datetime open_t = bars[t].time;
   int d = st.dir;
   int s = -d;
   int nki = H3KnownCount(sw, ns, p.right, t);
   bool has_l, has_e, has_i;
   SH3Cand lvl, ex, lint;
   H3DeriveLevel(sw, nki, d, has_l, lvl, has_e, ex, has_i, lint);
   //--- latest HH/LL (continuation)
   if(!has_e)
      st.has_ext = false;
   else
     {
      st.has_ext      = true;
      st.ex_id        = ex.id;
      st.ex_price     = ex.price;
      st.ex_consumed  = H3CloseBeyondAny(bars, ex.idx + 1, t, ex.price, d);
     }
   //--- protecting level
   if(!has_l)
     {
      st.has_level = false;
      st.has_lint  = false;
      return;
     }
   if(!(st.has_level && st.lv_id == lvl.id))
     {
      bool body;
      int wick_idx;
      H3ScanLevel(bars, lvl.idx + 1, t, lvl.price, s, body, wick_idx);
      if(body)
        {
         st.has_level = false;
         st.has_lint  = false;
         return;
        }
      st.has_level = true;
      st.lv_id     = lvl.id;
      st.lv_price  = lvl.price;
      st.lv_pivot  = lvl.pivot_time;
      st.lv_ext    = lvl.ext_time;
      st.lv_prev   = lvl.prev_time;
      st.lv_known  = lvl.known;
      if(wick_idx >= 0)
        {
         //--- retroactive wick: HOLD starts at detected_at, not at the wick
         datetime wk_src   = bars[wick_idx].time;
         datetime wk_known = wk_src + p.period;
         datetime det = lvl.known;
         if(wk_known > det)
            det = wk_known;
         if(st.bias_start > det)
            det = st.bias_start;
         H3StartHold(t, bars, p, fv, nf, st, tracks, nt, wk_src, det, det > wk_known);
         H3AddWickEvent(open_t, st, false, events, ne);
         return;
        }
     }
   //--- interior liquidity (needs the protecting level)
   if(!has_i)
      st.has_lint = false;
   else
     {
      st.has_lint     = true;
      st.li_id        = lint.id;
      st.li_price     = lint.price;
      st.li_consumed  = H3CloseBeyondAny(bars, lint.idx + 1, t, lint.price, s);
     }
  }

void H3ProcessBar(const int t, const MqlRates &bars[], const SH4Swing &sw[], const int ns, const SH4Fvg &fv[],
                  const int nf, const SH3Params &p, SH3State &st, SH3Track &tracks[], int &nt,
                  SH3Event &events[], int &ne)
  {
   if(st.dir == H3_NONE)
      H3NoneStep(t, bars, sw, ns, p, st, events, ne);
   else
     {
      bool flipped = H3BiasStep(t, bars, p, fv, nf, st, tracks, nt, events, ne);
      if(!flipped)
        {
         H3FvgStep(t, bars, fv, nf, st, tracks, nt, events, ne);
        }
     }
   H3DeriveStep(t, bars, sw, ns, p, fv, nf, st, tracks, nt, events, ne);
  }

//--- FVGs of the bias type older than the wick: reporting only (not part of the key)
string H3PreWickIds(const SH3State &st, const SH4Fvg &fv[], const int nf, const int n)
  {
   if(st.dir == H3_NONE || st.src_time == 0 || st.phase == H3_PH_ACTIVE)
      return("");
   string ids = "";
   int shown = 0;
   int cnt = 0;
   for(int k = nf - 1; k >= 0; k--)
     {
      if(fv[k].index_a + 2 > n - 1)
         continue;
      if(fv[k].bullish != (st.dir == H3_BULL))
         continue;
      if(fv[k].time_a < st.src_time)
        {
         cnt++;
         if(shown < 6)
           {
            if(shown > 0)
               ids += ",";
            ids += fv[k].id;
            shown++;
           }
        }
     }
   if(cnt == 0)
      return("");
   if(cnt > shown)
      ids += "+" + IntegerToString(cnt - shown);
   return(ids);
  }

//+------------------------------------------------------------------+
//| DIAGNOSTIC counters of a replay (behaviour neutral): flips and    |
//| runs of bars where a bias exists but has no protecting level.     |
//+------------------------------------------------------------------+
void H3DiagTrackBar(SH3Rep &rep, const SH3Event &events[], const int ne0, const datetime open_t)
  {
   bool has_flip = false;
   bool has_break = false;
   bool has_seed = false;
   for(int i = ne0; i < rep.ne; i++)
     {
      if(events[i].type == H3_EV_FLIP)
        {
         has_flip = true;
         rep.n_flips++;
         rep.last_flip = events[i].bar_time;
        }
      if(events[i].type == H3_EV_BREAK_SET)
         has_break = true;
      if(events[i].type == H3_EV_SEED)
         has_seed = true;
     }
   if(rep.st.dir != H3_NONE && !rep.st.has_level)
     {
      if(rep.nolv_run_start == 0)
        {
         rep.nolv_run_start = open_t;
         rep.nolv_run_bars  = 0;
         rep.nolv_runs++;
         if(has_flip)
            rep.nolv_cause = "FLIP";
         else
            if(has_break)
               rep.nolv_cause = "BREAK_SET";
            else
               if(has_seed)
                  rep.nolv_cause = "SEED";
               else
                  rep.nolv_cause = "LEVEL_DROPPED";
        }
      rep.nolv_run_bars++;
      rep.nolv_total++;
     }
   else
     {
      rep.nolv_run_start = 0;
      rep.nolv_run_bars  = 0;
      rep.nolv_cause     = "";
     }
  }

int H3DiagFlipsAfter(const SH3Rep &rep, const SH3Event &events[])
  {
   if(rep.nolv_run_start == 0)
      return(0);
   int c = 0;
   for(int i = 0; i < rep.ne; i++)
     {
      if(events[i].type == H3_EV_FLIP && events[i].bar_time > rep.nolv_run_start)
         c++;
     }
   return(c);
  }

//+------------------------------------------------------------------+
//| H3Replay: replay A or B. Reads bars[0..n-1] only. keys[] gets the |
//| state key after every bar when want_keys is true.                |
//+------------------------------------------------------------------+
void H3Replay(const MqlRates &bars[], const int n, const SH3Params &p, SH3Rep &rep,
              SH3Track &tracks[], SH3Event &events[], string &keys[], const bool want_keys)
  {
   H3StateInit(rep.st);
   rep.nt = 0;
   rep.ne = 0;
   rep.n  = n;
   rep.key_before_last = "";
   rep.last_time = 0;
   rep.nolv_run_start = 0;
   rep.nolv_run_bars = 0;
   rep.nolv_cause = "";
   rep.nolv_total = 0;
   rep.nolv_runs = 0;
   rep.n_flips = 0;
   rep.last_flip = 0;
   rep.flips_after_run = 0;
   ArrayResize(tracks, 0);
   ArrayResize(events, 0);
   ArrayResize(keys, 0);
   if(n < 1 || p.left < 1 || p.right < 1)
      return;
   SH4Swing sw[];
   SH4Fvg fv[];
   int amb = 0;
   int ns = H4FindSwings(bars, n, p.left, p.right, p.period, sw, amb);
   int nf = H4FindFvgs(bars, n, p.period, fv);
   if(want_keys)
      ArrayResize(keys, n);
   for(int t = 0; t < n; t++)
     {
      if(t == n - 1)
         rep.key_before_last = H3StateKey(rep.st, tracks, rep.nt);
      int ne0 = rep.ne;
      H3ProcessBar(t, bars, sw, ns, fv, nf, p, rep.st, tracks, rep.nt, events, rep.ne);
      if(want_keys)
         keys[t] = H3StateKey(rep.st, tracks, rep.nt);
      H3DiagTrackBar(rep, events, ne0, bars[t].time);
     }
   rep.flips_after_run = H3DiagFlipsAfter(rep, events);
   int nkf = H3KnownCount(sw, ns, p.right, n - 1);
   rep.st.t2dir = H4DirName(H4DeriveDirection(sw, nkf));
   rep.st.pre   = H3PreWickIds(rep.st, fv, nf, n);
   rep.last_time = bars[n - 1].time;
  }

//--- index of the bar that OPENS at exactly t in bars[0..n-1] (chronological), or -1
int H3BarIndexByTime(const MqlRates &bars[], const int n, const datetime t)
  {
   int lo = 0;
   int hi = n - 1;
   while(lo <= hi)
     {
      int mid = (lo + hi) / 2;
      if(bars[mid].time == t)
         return(mid);
      if(bars[mid].time < t)
         lo = mid + 1;
      else
         hi = mid - 1;
     }
   return(-1);
  }

//--- AMBIGUITY 5: the absolute reference times the state depends on. Frozen states (HOLD,
//--- RECONFIRMED): the source wick, the frozen level's pivots (only if a level exists) and the
//--- sweep that started an internal wait (0 in HOLD); the origin is ignored (literal task text).
//--- Otherwise: the origin reference, the level's pivots (if any) and the sweep.
int H3AnchorRefsNamed(const SH3State &st, datetime &refs[], string &names[])
  {
   ArrayResize(refs, 0);
   ArrayResize(names, 0);
   if(st.dir == H3_NONE)
      return(0);
   datetime lst[];
   string lnm[];
   int na = 0;
   ArrayResize(lst, 6);
   ArrayResize(lnm, 6);
   if(st.frozen)
     {
      if(st.has_wick)
        {
         lst[na] = st.wk_src;
         lnm[na] = "wick";
         na++;
        }
      if(st.has_level)
        {
         lst[na] = st.lv_pivot;
         lnm[na] = "lv_pivot";
         na++;
         lst[na] = st.lv_ext;
         lnm[na] = "lv_ext";
         na++;
         lst[na] = st.lv_prev;
         lnm[na] = "lv_prev";
         na++;
        }
      lst[na] = st.sweep_time;
      lnm[na] = "sweep";
      na++;
     }
   else
     {
      lst[na] = st.origin_ref;
      lnm[na] = "origin";
      na++;
      if(st.has_level)
        {
         lst[na] = st.lv_pivot;
         lnm[na] = "lv_pivot";
         na++;
         lst[na] = st.lv_ext;
         lnm[na] = "lv_ext";
         na++;
         lst[na] = st.lv_prev;
         lnm[na] = "lv_prev";
         na++;
        }
      if(st.sweep_time != 0)
        {
         lst[na] = st.sweep_time;
         lnm[na] = "sweep";
         na++;
        }
     }
   int nr = 0;
   for(int i = 0; i < na; i++)
     {
      if(lst[i] != 0)
        {
         ArrayResize(refs, nr + 1);
         ArrayResize(names, nr + 1);
         refs[nr]  = lst[i];
         names[nr] = lnm[i];
         nr++;
        }
     }
   return(nr);
  }

int H3AnchorRefs(const SH3State &st, datetime &refs[])
  {
   string nm[];
   return(H3AnchorRefsNamed(st, refs, nm));
  }

//--- FINDING 1: earliest bar time the state depends on, by EXISTING bars. Each reference is
//--- located by its absolute open time in the chronological series bars[0..n-1]; the bars that
//--- confirm it are the p.left EXISTING bars before it (index based), converted back to the
//--- absolute open time of that bar. Weekends and holes in the history never give a time that
//--- is not a bar. Returns 0 (not applicable) for NONE or without references. When the series
//--- lacks a needed bar (reference not found, or fewer than p.left bars before it) the result
//--- is 0 and 'missing' says why: nothing is substituted or invented.
datetime H3AnchorTime(const SH3State &st, const SH3Params &p, const MqlRates &bars[], const int n,
                      string &missing)
  {
   missing = "";
   if(st.dir == H3_NONE)
      return(0);
   datetime refs[];
   int nr = H3AnchorRefs(st, refs);
   datetime a = 0;
   for(int i = 0; i < nr; i++)
     {
      int ix = H3BarIndexByTime(bars, n, refs[i]);
      if(ix < 0)
        {
         missing = "ANCHOR_REF_NOT_IN_SERIES " + H4TimeStamp(refs[i]);
         return(0);
        }
      if(ix < p.left)
        {
         missing = "ANCHOR_NEEDS_" + IntegerToString(p.left) + "_BARS_BEFORE " + H4TimeStamp(refs[i]);
         return(0);
        }
      datetime c = bars[ix - p.left].time;
      if(a == 0 || c < a)
         a = c;
     }
   return(a);
  }

//--- DIAGNOSTIC twin of H3AnchorTime: the same anchor, plus WHICH reference gives it (the
//--- first one in the reference order on a tie). Returns the anchor (0 = not applicable or
//--- missing history, then 'missing' says why).
datetime H3AnchorBinding(const SH3State &st, const SH3Params &p, const MqlRates &bars[], const int n,
                         string &name, datetime &ref, string &missing)
  {
   name = "";
   ref = 0;
   missing = "";
   if(st.dir == H3_NONE)
      return(0);
   datetime refs[];
   string names[];
   int nr = H3AnchorRefsNamed(st, refs, names);
   datetime a = 0;
   for(int i = 0; i < nr; i++)
     {
      int ix = H3BarIndexByTime(bars, n, refs[i]);
      if(ix < 0)
        {
         missing = "ANCHOR_REF_NOT_IN_SERIES " + H4TimeStamp(refs[i]);
         name = "";
         ref = 0;
         return(0);
        }
      if(ix < p.left)
        {
         missing = "ANCHOR_NEEDS_" + IntegerToString(p.left) + "_BARS_BEFORE " + H4TimeStamp(refs[i]);
         name = "";
         ref = 0;
         return(0);
        }
      datetime c = bars[ix - p.left].time;
      if(a == 0 || c < a)
        {
         a = c;
         name = names[i];
         ref = refs[i];
        }
     }
   return(a);
  }

//--- P11 (ii)/(iii): why a rebuild is not reliable ("" = reliable). evA/evB are the
//--- event texts dated inside B's trusted region only.
//--- AMBIGUITY 9: events before B's trusted region (its first non-warm-up bar) are not
//--- compared; an event is compared by its full text (type, bar time, reference, details).
string H3AbReasons(const string keyA, const string keyB, const string evA, const string evB,
                   const int dirA, const datetime anchorA, const datetime trustedA, const string anchorMissing)
  {
   string why = "";
   if(keyA != keyB)
      why += "AB_STATE_DIFF";
   if(evA != evB)
     {
      if(why != "")
         why += "+";
      why += "AB_EVENT_DIFF";
     }
   if(dirA != H3_NONE && anchorMissing != "")
     {
      if(why != "")
         why += "+";
      why += "ANCHOR_HISTORY_MISSING";
     }
   else
      if(dirA != H3_NONE && anchorA < trustedA)
        {
         if(why != "")
            why += "+";
         why += "ANCHOR_IN_WARMUP";
        }
   return(why);
  }

//--- the state before the latest bar counts only if it was RELIABLE and the
//--- current window reproduces it
bool H3ConsumerPrevOk(const bool cur_reliable, const bool prev_reliable, const string cur_key_prev,
                      const string prev_key)
  {
   return(cur_reliable && prev_reliable && cur_key_prev == prev_key);
  }

//+------------------------------------------------------------------+
//| P11: stateless fixed-depth rebuild with the A/B depth check.     |
//| Reads bars_all[0..n_avail-1] only. When the result is RELIABLE   |
//| the full event log of replay A is returned in events[] (history);|
//| otherwise no event is returned.                                  |
//+------------------------------------------------------------------+
void H3Evaluate(const MqlRates &bars_all[], const int n_avail, const SH3Params &p, SH3Eval &ev,
                SH3Track &tracks[], SH3Event &events[])
  {
   ev.has_state    = false;
   ev.reliable     = false;
   ev.flag         = H3_FLAG_LIMITED;
   ev.reason       = "";
   ev.note         = "";
   ev.r_request    = p.rebuild;
   ev.r_req        = (p.rebuild > 3 * p.lookback ? p.rebuild : 3 * p.lookback);
   int cap_req     = (ev.r_req < p.hard_cap ? ev.r_req : p.hard_cap);
   ev.r_eff        = (cap_req < n_avail ? cap_req : n_avail);
   ev.warm         = H3WarmUp(p);
   ev.chk          = H3CheckDepth(p);
   ev.b_depth      = 0;
   ev.n_avail      = n_avail;
   ev.key          = "";
   ev.key_prev     = "";
   ev.last_time    = 0;
   ev.trusted_from = 0;
   ev.anchor       = 0;
   ev.anchor_missing = "";
   ev.prev_ok      = false;
   ev.cause        = "";
   ev.nt           = 0;
   ev.ne           = 0;
   H3StateInit(ev.st);
   ArrayResize(tracks, 0);
   ArrayResize(events, 0);
   string notes = "";
   if(p.rebuild < 3 * p.lookback)
      notes += "R raised to 3*L " + IntegerToString(ev.r_req);
   if(ev.r_req > p.hard_cap)
     {
      if(notes != "")
         notes += ";";
      notes += "request " + IntegerToString(ev.r_req) + " clamped to HARD_CAP " + IntegerToString(p.hard_cap);
     }
   if(n_avail <= 0)
     {
      ev.reason = "NO_BARS";
      ev.note   = notes;
      return;
     }
   if(n_avail < cap_req)
     {
      if(notes != "")
         notes += ";";
      notes += "reduced depth " + IntegerToString(ev.r_eff) + " of " + IntegerToString(ev.r_req);
     }
   ev.note = notes;
   if(ev.r_eff < 3 * p.lookback)
     {
      ev.reason = "SHORT_HISTORY";
      return;
     }
   //--- replay A over the last r_eff bars
   MqlRates winA[];
   ArrayResize(winA, ev.r_eff);
   ArrayCopy(winA, bars_all, 0, n_avail - ev.r_eff, ev.r_eff);
   SH3Rep repA;
   SH3Track trA[];
   SH3Event evA[];
   string keysA[];
   H3Replay(winA, ev.r_eff, p, repA, trA, evA, keysA, false);
   //--- replay B over the last r_eff - D bars (same final bar)
   ev.b_depth = ev.r_eff - ev.chk;
   MqlRates winB[];
   ArrayResize(winB, ev.b_depth);
   ArrayCopy(winB, bars_all, 0, n_avail - ev.b_depth, ev.b_depth);
   SH3Rep repB;
   SH3Track trB[];
   SH3Event evB[];
   string keysB[];
   H3Replay(winB, ev.b_depth, p, repB, trB, evB, keysB, false);
   datetime trusted_b = winB[ev.warm].time;
   datetime trusted_a = winA[ev.warm].time;
   string keyA = H3StateKey(repA.st, trA, repA.nt);
   string keyB = H3StateKey(repB.st, trB, repB.nt);
   //--- the anchor is located in the FULL available series (not only in window A)
   ev.anchor = H3AnchorTime(repA.st, p, bars_all, n_avail, ev.anchor_missing);
   string why = H3AbReasons(keyA, keyB, H3EventsText(evA, repA.ne, trusted_b), H3EventsText(evB, repB.ne, trusted_b),
                            repA.st.dir, ev.anchor, trusted_a, ev.anchor_missing);
   if(ev.anchor_missing != "")
      ev.note += (ev.note != "" ? ";" : "") + "missing history: " + ev.anchor_missing;
   ev.has_state    = true;
   ev.key          = keyA;
   ev.key_prev     = repA.key_before_last;
   ev.last_time    = repA.last_time;
   ev.trusted_from = trusted_b;
   ev.nt           = repA.nt;
   H3StateCopy(repA.st, ev.st);
   if(why == "")
     {
      ev.reliable = true;
      //--- AMBIGUITY 6: NONE and any HOLD / frozen RECONFIRMED are CONVERGED (also with a seed
      //--- origin); SEEDED is a reliable ACTIVE-like state whose origin is the T002 seed.
      if(repA.st.dir != H3_NONE && repA.st.origin == H3_ORG_SEED && !repA.st.frozen)
         ev.flag = H3_FLAG_SEEDED;
      else
         ev.flag = H3_FLAG_CONVERGED;
      ev.reason = "converged at depth " + IntegerToString(ev.r_eff) + " vs " + IntegerToString(ev.b_depth);
      ArrayResize(tracks, repA.nt);
      for(int i = 0; i < repA.nt; i++)
        {
         tracks[i].f        = trA[i].f;
         tracks[i].id       = trA[i].id;
         tracks[i].invalid  = trA[i].invalid;
         tracks[i].recorded = trA[i].recorded;
        }
      ArrayResize(events, repA.ne);
      for(int j = 0; j < repA.ne; j++)
        {
         events[j].type     = evA[j].type;
         events[j].bar_time = evA[j].bar_time;
         events[j].ref      = evA[j].ref;
         events[j].detail   = evA[j].detail;
         events[j].market   = evA[j].market;
        }
      ev.ne = repA.ne;
     }
   else
     {
      ev.flag   = H3_FLAG_LIMITED;
      ev.reason = why;
      //--- keep the diagnostic tracks for the report, but no event
      ArrayResize(tracks, repA.nt);
      for(int q = 0; q < repA.nt; q++)
        {
         tracks[q].f        = trA[q].f;
         tracks[q].id       = trA[q].id;
         tracks[q].invalid  = trA[q].invalid;
         tracks[q].recorded = trA[q].recorded;
        }
      ev.ne = 0;
     }
  }

//--- direction reported to a consumer: UNKNOWN unless RELIABLE
string H3ReportedDirection(const SH3Eval &ev)
  {
   if(!ev.reliable)
      return("UNKNOWN");
   return(H3DirName(ev.st.dir));
  }

string H3EvalText(const SH3Eval &ev, const SH3Track &tracks[], const SH3Event &events[])
  {
   string s = "EVAL;FLAG=" + H3FlagName(ev.flag) + ";REASON=" + ev.reason + ";DIR=" + H3ReportedDirection(ev) +
              ";DEPTHS=req:" + IntegerToString(ev.r_req) + ",eff:" + IntegerToString(ev.r_eff) +
              ",b:" + IntegerToString(ev.b_depth) + ",warm:" + IntegerToString(ev.warm) +
              ",chk:" + IntegerToString(ev.chk) + ";ANCH=" + H3Tx(ev.anchor) + ";NOTE=" + (ev.note != "" ? ev.note : "-");
   if(ev.reliable)
      s += ";ST=" + H3StateText(ev.st, tracks, ev.nt) + ";EV=" + H3EventsText(events, ev.ne, 0);
   else
      if(ev.has_state)
         s += ";DIAG=" + ev.key;
   return(s);
  }

//--- evaluation at the last bar plus the check of the state before it
void H3EvaluateLatest(const MqlRates &bars_all[], const int n, const SH3Params &p, SH3Eval &cur,
                      SH3Track &tracks[], SH3Event &events[])
  {
   H3Evaluate(bars_all, n, p, cur, tracks, events);
   SH3Eval prev;
   SH3Track ptr[];
   SH3Event pev[];
   H3Evaluate(bars_all, (n > 1 ? n - 1 : 0), p, prev, ptr, pev);
   cur.prev_ok = H3ConsumerPrevOk(cur.reliable, prev.reliable, cur.key_prev, prev.key);
   cur.cause = "";
   if(cur.reliable && !prev.reliable)
      cur.cause = "REDERIVATION:LIMITED_EXIT";
   else
      if(!cur.reliable && prev.reliable)
         cur.cause = "REDERIVATION:LIMITED_ENTER";
      else
         if(cur.reliable && prev.reliable && cur.key_prev != prev.key)
           {
            if(cur.r_eff != prev.r_eff)
               cur.cause = "REDERIVATION:DEPTH_CHANGED";
            else
               cur.cause = "REDERIVATION:WINDOW_SLID";
           }
  }

//+------------------------------------------------------------------+
//| DIAGNOSTICS (behaviour neutral). They EXPLAIN a P11 evaluation:   |
//| they re-run replays A and B and compare them, and never change    |
//| H3Evaluate. All times are ABSOLUTE (YYYYMMDDHHMM, server time of   |
//| the bars). Mirrored by diagnose()/diag_lines() in                 |
//| tests/t003_reference_test.py and tools/ replay of a real CSV.     |
//| Every cause named here is a HYPOTHESIS until a real series has    |
//| been replayed; the report only states what the replays show.      |
//+------------------------------------------------------------------+
#define H3_STATE_FIELD_COUNT 11

//--- the state key as an ORDERED list of (label, value); join of "label=value" with ";" == H3StateKey
void H3StateFields(const SH3State &st, const SH3Track &tracks[], const int nt, string &lab[], string &val[])
  {
   ArrayResize(lab, H3_STATE_FIELD_COUNT);
   ArrayResize(val, H3_STATE_FIELD_COUNT);
   string lv = "-";
   if(st.has_level)
      lv = st.lv_id + "@" + H3Pf(st.lv_price);
   string ph = "-";
   string nr = "-";
   if(st.dir != H3_NONE)
      ph = H3PhaseName(st.phase);
   else
      nr = H3NoneReasonName(st.none_reason);
   string rec = "-";
   if(st.rec_id != "")
      rec = st.rec_id;
   string rsn = "-";
   if(st.recon_reason != H3_RR_NONE)
      rsn = H3ReconReasonName(st.recon_reason);
   lab[0]  = "BIAS";
   val[0]  = H3DirName(st.dir);
   lab[1]  = "PH";
   val[1]  = ph;
   lab[2]  = "ORG";
   val[2]  = H3OriginName(st.origin);
   lab[3]  = "NR";
   val[3]  = nr;
   lab[4]  = "LV";
   val[4]  = lv;
   lab[5]  = "FRZ";
   val[5]  = (st.frozen ? "1" : "0");
   lab[6]  = "WK";
   val[6]  = H3WickText(st);
   lab[7]  = "SW";
   val[7]  = H3Tx(st.sweep_time);
   lab[8]  = "REC";
   val[8]  = rec;
   lab[9]  = "RSN";
   val[9]  = rsn;
   lab[10] = "EL";
   val[10] = H3TracksText(tracks, nt);
  }

string H3FieldMeaning(const string label)
  {
   if(label == "BIAS")
      return("dir");
   if(label == "PH")
      return("phase");
   if(label == "ORG")
      return("origin");
   if(label == "NR")
      return("none_reason");
   if(label == "LV")
      return("level id@price (id carries the pivot/ext/prev times)");
   if(label == "FRZ")
      return("frozen");
   if(label == "WK")
      return("wick src/known/detected/retro");
   if(label == "SW")
      return("sweep time");
   if(label == "REC")
      return("recorded FVG");
   if(label == "RSN")
      return("reconfirm reason");
   return("eligible FVG tracks");
  }

string H3FieldOrderText(void)
  {
   return("BIAS>PH>ORG>NR>LV>FRZ>WK>SW>REC>RSN>EL");
  }

//--- index of the first differing field in the explicit order, -1 when all are equal
int H3FirstDiffField(const string &va[], const string &vb[])
  {
   for(int i = 0; i < H3_STATE_FIELD_COUNT; i++)
     {
      if(va[i] != vb[i])
         return(i);
     }
   return(-1);
  }

string H3OneTrackText(const SH3Track &t)
  {
   string sname = "FRESH";
   if(t.invalid)
      sname = "INVALID";
   else
      if(t.recorded)
         sname = "RECORDED";
   return(t.id + ":" + sname);
  }

//--- first differing track of two lists: "track #i A=.. B=.. (counts na vs nb)" or ""
string H3TrackDiffText(const SH3Track &ta[], const int na, const SH3Track &tb[], const int nb)
  {
   int m = (na > nb ? na : nb);
   for(int i = 0; i < m; i++)
     {
      string xa = (i < na ? H3OneTrackText(ta[i]) : "-");
      string xb = (i < nb ? H3OneTrackText(tb[i]) : "-");
      if(xa != xb)
         return("track #" + IntegerToString(i) + " A=" + xa + " B=" + xb + " (counts " + IntegerToString(na) +
                " vs " + IntegerToString(nb) + ")");
     }
   return("");
  }

//--- why a bias of direction d has no protecting level at the end of bars[0..n-1]
string H3WhyNoLevel(const MqlRates &bars[], const int n, const SH3Params &p, const int d)
  {
   SH4Swing sw[];
   int amb = 0;
   int ns = H4FindSwings(bars, n, p.left, p.right, p.period, sw, amb);
   int nk = H3KnownCount(sw, ns, p.right, n - 1);
   bool has_l, has_e, has_i;
   SH3Cand lvl, ex, lint;
   H3DeriveLevel(sw, nk, d, has_l, lvl, has_e, ex, has_i, lint);
   if(!has_l)
     {
      if(!has_e)
         return("NO_CANDIDATE: no latest " + (d > 0 ? "HH" : "LL") + " in the swings known at the last bar");
      return("NO_CANDIDATE: " + ex.id + " found but no bounded swing between it and its predecessor");
     }
   int s = -d;
   for(int i = lvl.idx + 1; i < n; i++)
     {
      if(s * (bars[i].close - lvl.price) > 0)
         return("CONSUMED: candidate " + lvl.id + " price " + H3Pf(lvl.price) + " closed beyond at " + H4TimeStamp(bars[i].time));
     }
   return("CANDIDATE_DEFINED: " + lvl.id + " price " + H3Pf(lvl.price) + " (not consumed; check the freeze/derive order)");
  }

//--- one replay as seen by the diagnostics
struct SH3DiagSide
  {
   datetime          start;
   int               bars;
   datetime          warm_end;
   int               dir;
   int               phase;
   int               origin;
   datetime          origin_ref;
   datetime          bias_start;
   bool              has_level;
   string            lv_id;
   double            lv_price;
   datetime          lv_pivot;
   datetime          lv_ext;
   datetime          lv_prev;
   datetime          lv_known;
   bool              frozen;
   datetime          anchor;
   string            anchor_name;
   datetime          anchor_ref;
   string            anchor_missing;
   bool              nolv_now;
   datetime          nolv_since;
   int               nolv_bars;
   string            nolv_cause;
   int               nolv_total;
   int               nolv_runs;
   int               flips;
   datetime          last_flip;
   int               flips_after_run;
   string            nolv_why;
   int               n_events;
  };

struct SH3Diag
  {
   bool              valid;
   bool              reliable;
   string            reason;
   int               n_avail;
   int               r_eff;
   int               b_depth;
   int               warm;
   int               chk;
   datetime          series_first;
   datetime          series_last;
   SH3DiagSide       a;
   SH3DiagSide       b;
   datetime          zone_start;
   int               field_idx;        // first differing field in the explicit order, -1 = none
   string            field_label;
   string            field_a;
   string            field_b;
   string            track_diff;
   int               zone_na;
   int               zone_nb;
   int               event_idx;        // first differing event in the zone, -1 = none
   string            event_a;
   string            event_b;
   bool              event_count_diff;
   string            event_extra;
   string            event_extra_who;
   int               common_bars;
   int               common_diff;
   datetime          common_first_diff;
   datetime          common_last_diff;
  };

void H3DiagSideInit(SH3DiagSide &s)
  {
   s.start = 0;
   s.bars = 0;
   s.warm_end = 0;
   s.dir = H3_NONE;
   s.phase = H3_PH_ACTIVE;
   s.origin = H3_ORG_NONE;
   s.origin_ref = 0;
   s.bias_start = 0;
   s.has_level = false;
   s.lv_id = "";
   s.lv_price = 0.0;
   s.lv_pivot = 0;
   s.lv_ext = 0;
   s.lv_prev = 0;
   s.lv_known = 0;
   s.frozen = false;
   s.anchor = 0;
   s.anchor_name = "";
   s.anchor_ref = 0;
   s.anchor_missing = "";
   s.nolv_now = false;
   s.nolv_since = 0;
   s.nolv_bars = 0;
   s.nolv_cause = "";
   s.nolv_total = 0;
   s.nolv_runs = 0;
   s.flips = 0;
   s.last_flip = 0;
   s.flips_after_run = 0;
   s.nolv_why = "";
   s.n_events = 0;
  }

void H3DiagInit(SH3Diag &d)
  {
   d.valid = false;
   d.reliable = false;
   d.reason = "";
   d.n_avail = 0;
   d.r_eff = 0;
   d.b_depth = 0;
   d.warm = 0;
   d.chk = 0;
   d.series_first = 0;
   d.series_last = 0;
   H3DiagSideInit(d.a);
   H3DiagSideInit(d.b);
   d.zone_start = 0;
   d.field_idx = -1;
   d.field_label = "";
   d.field_a = "";
   d.field_b = "";
   d.track_diff = "";
   d.zone_na = 0;
   d.zone_nb = 0;
   d.event_idx = -1;
   d.event_a = "";
   d.event_b = "";
   d.event_count_diff = false;
   d.event_extra = "";
   d.event_extra_who = "";
   d.common_bars = 0;
   d.common_diff = 0;
   d.common_first_diff = 0;
   d.common_last_diff = 0;
  }

void H3DiagFillSide(const SH3Rep &rep, const MqlRates &win[], const int nwin, const MqlRates &bars_all[],
                    const int n_avail, const SH3Params &p, const int warm, SH3DiagSide &s)
  {
   H3DiagSideInit(s);
   s.start      = win[0].time;
   s.bars       = nwin;
   s.warm_end   = (nwin > warm ? win[warm].time : 0);
   s.dir        = rep.st.dir;
   s.phase      = rep.st.phase;
   s.origin     = rep.st.origin;
   s.origin_ref = rep.st.origin_ref;
   s.bias_start = rep.st.bias_start;
   s.has_level  = rep.st.has_level;
   s.lv_id      = rep.st.lv_id;
   s.lv_price   = rep.st.lv_price;
   s.lv_pivot   = rep.st.lv_pivot;
   s.lv_ext     = rep.st.lv_ext;
   s.lv_prev    = rep.st.lv_prev;
   s.lv_known   = rep.st.lv_known;
   s.frozen     = rep.st.frozen;
   s.anchor     = H3AnchorBinding(rep.st, p, bars_all, n_avail, s.anchor_name, s.anchor_ref, s.anchor_missing);
   s.nolv_now   = (rep.st.dir != H3_NONE && !rep.st.has_level);
   s.nolv_since = rep.nolv_run_start;
   s.nolv_bars  = rep.nolv_run_bars;
   s.nolv_cause = rep.nolv_cause;
   s.nolv_total = rep.nolv_total;
   s.nolv_runs  = rep.nolv_runs;
   s.flips      = rep.n_flips;
   s.last_flip  = rep.last_flip;
   s.flips_after_run = rep.flips_after_run;
   s.nolv_why   = (s.nolv_now ? H3WhyNoLevel(win, nwin, p, rep.st.dir) : "");
   s.n_events   = rep.ne;
  }

//--- ev is the result of H3Evaluate(bars_all, n_avail, p) on the same arguments
void H3Diagnose(const MqlRates &bars_all[], const int n_avail, const SH3Params &p, const SH3Eval &ev, SH3Diag &d)
  {
   H3DiagInit(d);
   d.valid    = ev.has_state;
   d.reliable = ev.reliable;
   d.reason   = ev.reason;
   d.n_avail  = n_avail;
   d.r_eff    = ev.r_eff;
   d.b_depth  = ev.b_depth;
   d.warm     = ev.warm;
   d.chk      = ev.chk;
   if(!d.valid)
      return;
   MqlRates winA[];
   ArrayResize(winA, ev.r_eff);
   ArrayCopy(winA, bars_all, 0, n_avail - ev.r_eff, ev.r_eff);
   MqlRates winB[];
   ArrayResize(winB, ev.b_depth);
   ArrayCopy(winB, bars_all, 0, n_avail - ev.b_depth, ev.b_depth);
   SH3Rep repA;
   SH3Track trA[];
   SH3Event evA[];
   string keysA[];
   H3Replay(winA, ev.r_eff, p, repA, trA, evA, keysA, true);
   SH3Rep repB;
   SH3Track trB[];
   SH3Event evB[];
   string keysB[];
   H3Replay(winB, ev.b_depth, p, repB, trB, evB, keysB, true);
   d.series_first = bars_all[0].time;
   d.series_last  = bars_all[n_avail - 1].time;
   H3DiagFillSide(repA, winA, ev.r_eff, bars_all, n_avail, p, ev.warm, d.a);
   H3DiagFillSide(repB, winB, ev.b_depth, bars_all, n_avail, p, ev.warm, d.b);
   d.zone_start = d.b.warm_end;
   //--- final states: first differing field in the explicit order
   string la[];
   string va[];
   string lb[];
   string vb[];
   H3StateFields(repA.st, trA, repA.nt, la, va);
   H3StateFields(repB.st, trB, repB.nt, lb, vb);
   d.field_idx = H3FirstDiffField(va, vb);
   if(d.field_idx >= 0)
     {
      d.field_label = la[d.field_idx];
      d.field_a     = va[d.field_idx];
      d.field_b     = vb[d.field_idx];
      if(d.field_label == "EL")
         d.track_diff = H3TrackDiffText(trA, repA.nt, trB, repB.nt);
     }
   //--- events dated inside B's trusted region (the comparison zone)
   string za[];
   string zb[];
   int nza = 0;
   int nzb = 0;
   for(int i = 0; i < repA.ne; i++)
     {
      if(evA[i].bar_time >= d.zone_start)
        {
         ArrayResize(za, nza + 1, 32);
         za[nza] = H3EventText(evA[i]);
         nza++;
        }
     }
   for(int j = 0; j < repB.ne; j++)
     {
      if(evB[j].bar_time >= d.zone_start)
        {
         ArrayResize(zb, nzb + 1, 32);
         zb[nzb] = H3EventText(evB[j]);
         nzb++;
        }
     }
   d.zone_na = nza;
   d.zone_nb = nzb;
   int mn = (nza < nzb ? nza : nzb);
   for(int k = 0; k < mn; k++)
     {
      if(za[k] != zb[k])
        {
         d.event_idx = k;
         d.event_a   = za[k];
         d.event_b   = zb[k];
         break;
        }
     }
   if(d.event_idx < 0 && nza != nzb)
     {
      d.event_count_diff = true;
      if(nza > nzb)
        {
         d.event_extra     = za[nzb];
         d.event_extra_who = "A";
        }
      else
        {
         d.event_extra     = zb[nza];
         d.event_extra_who = "B";
        }
     }
   //--- agreement of the state keys on the common bars (B's bars; A has chk more bars in front)
   int off = ev.r_eff - ev.b_depth;
   d.common_bars = ev.b_depth;
   for(int m = 0; m < ev.b_depth; m++)
     {
      if(keysA[m + off] != keysB[m])
        {
         d.common_diff++;
         if(d.common_first_diff == 0)
            d.common_first_diff = winB[m].time;
         d.common_last_diff = winB[m].time;
        }
     }
  }

string H3DiagTOrDash(const datetime t)
  {
   if(t == 0)
      return("-");
   return(H3Tx(t));
  }

string H3DiagDirPhase(const SH3DiagSide &s)
  {
   if(s.dir == H3_NONE)
      return("NONE");
   return(H3DirName(s.dir) + "/" + H3PhaseName(s.phase));
  }

string H3DiagSideLine(const string label, const SH3DiagSide &s)
  {
   string lv = "none";
   if(s.has_level)
      lv = s.lv_id + "@" + H3Pf(s.lv_price) + " known " + H3Tx(s.lv_known) + " pivots " + H3Tx(s.lv_pivot) + "/" +
           H3Tx(s.lv_ext) + "/" + H3Tx(s.lv_prev) + (s.frozen ? " FROZEN" : "");
   string anc = "-";
   if(s.anchor_missing != "")
      anc = "missing (" + s.anchor_missing + ")";
   else
      if(s.anchor != 0)
         anc = H3Tx(s.anchor) + " via " + s.anchor_name + "@" + H3Tx(s.anchor_ref);
   return(label + ": " + H3DiagDirPhase(s) + " origin " + H3OriginName(s.origin) + " ref " + H3DiagTOrDash(s.origin_ref) +
          " since " + H3DiagTOrDash(s.bias_start) + " | level " + lv + " | anchor " + anc);
  }

string H3DiagNoLevelLine(const string label, const SH3DiagSide &s)
  {
   if(!s.nolv_now)
     {
      if(s.dir == H3_NONE)
         return(label + ": no bias (NONE)");
      return(label + ": level defined at the last bar; bars without a level in the window " + IntegerToString(s.nolv_total) +
             " in " + IntegerToString(s.nolv_runs) + " run(s); flips " + IntegerToString(s.flips) + " (last " +
             H3DiagTOrDash(s.last_flip) + ")");
     }
   return(label + ": level UNDEFINED since " + H3Tx(s.nolv_since) + " (" + IntegerToString(s.nolv_bars) + " bars, started by " +
          s.nolv_cause + "); runs " + IntegerToString(s.nolv_runs) + ", bars without level " + IntegerToString(s.nolv_total) +
          "; flips in window " + IntegerToString(s.flips) + " (last " + H3DiagTOrDash(s.last_flip) +
          "), flips after the run began " + IntegerToString(s.flips_after_run) + "; why: " + s.nolv_why);
  }

//--- the diagnostic report, one line per array item (Experts log / replay tool / tests)
int H3DiagLines(const SH3Diag &d, string &lines[])
  {
   ArrayResize(lines, 0);
   if(!d.valid)
     {
      ArrayResize(lines, 1);
      lines[0] = "DIAG1 no replay ran: " + d.reason + " (bars available " + IntegerToString(d.n_avail) + ")";
      return(1);
     }
   ArrayResize(lines, 8);
   lines[0] = "DIAG1 " + (d.reliable ? "RELIABLE" : "LIMITED") + " reasons=" + (d.reliable ? "-" : d.reason) +
              " | series " + H3Tx(d.series_first) + ".." + H3Tx(d.series_last) + " (" + IntegerToString(d.n_avail) + " bars)" +
              " | A window " + H3Tx(d.a.start) + ".." + H3Tx(d.series_last) + " (" + IntegerToString(d.a.bars) +
              " bars) warm-up ends " + H3Tx(d.a.warm_end) +
              " | B window " + H3Tx(d.b.start) + ".." + H3Tx(d.series_last) + " (" + IntegerToString(d.b.bars) +
              " bars) warm-up ends " + H3Tx(d.b.warm_end) + " | comparison zone from " + H3Tx(d.zone_start);
   lines[1] = "DIAG2 " + H3DiagSideLine("A", d.a);
   lines[2] = "DIAG3 " + H3DiagSideLine("B", d.b);
   if(d.field_idx < 0)
      lines[3] = "DIAG4 final states A and B: all " + IntegerToString(H3_STATE_FIELD_COUNT) + " fields equal";
   else
     {
      lines[3] = "DIAG4 first differing field of " + H3FieldOrderText() + ": " + d.field_label + " (" +
                 H3FieldMeaning(d.field_label) + ") A=" + d.field_a + " B=" + d.field_b;
      if(d.track_diff != "")
         lines[3] += " | " + d.track_diff;
     }
   if(d.event_idx >= 0)
      lines[4] = "DIAG5 first differing event in the zone: #" + IntegerToString(d.event_idx) + " A=" + d.event_a + " B=" + d.event_b;
   else
      if(d.event_count_diff)
         lines[4] = "DIAG5 events in the zone: count differs: nA " + IntegerToString(d.zone_na) + " vs nB " +
                    IntegerToString(d.zone_nb) + " (first extra on " + d.event_extra_who + ": " + d.event_extra + ")";
      else
         lines[4] = "DIAG5 events in the zone: identical (" + IntegerToString(d.zone_na) + ")";
   lines[5] = "DIAG6 " + H3DiagNoLevelLine("A", d.a);
   lines[6] = "DIAG7 " + H3DiagNoLevelLine("B", d.b);
   if(d.common_diff == 0)
      lines[7] = "DIAG8 state keys agree on all " + IntegerToString(d.common_bars) + " common bars";
   else
      lines[7] = "DIAG8 state keys differ on " + IntegerToString(d.common_diff) + " of " + IntegerToString(d.common_bars) +
                 " common bars, first " + H3Tx(d.common_first_diff) + ", last " + H3Tx(d.common_last_diff);
   return(8);
  }

string H3DiagText(const SH3Diag &d)
  {
   string lines[];
   int n = H3DiagLines(d, lines);
   string out = "";
   for(int i = 0; i < n; i++)
     {
      if(i > 0)
         out += "\n";
      out += lines[i];
     }
   return(out);
  }

//+------------------------------------------------------------------+
//| TrackChanges decision (pure). A change of bias / T002 direction / |
//| phase between two RELIABLE evaluations is a market change only    |
//| when the consumer accepted the step as exactly the next closed    |
//| bar with the previous state reproduced (H3_C_OK). After a        |
//| REDERIVED, GAP or NOTHING_NEW step a difference comes from the    |
//| rebuild (or from missed bars with an unknown date) and is NEVER   |
//| reported as a market change.                                      |
//+------------------------------------------------------------------+
int H3TrackChangesMode(const int consume_status, const bool prev_valid)
  {
   if(consume_status == H3_C_BASELINE || !prev_valid)
      return(H3_TC_BASELINE);
   if(consume_status == H3_C_OK)
      return(H3_TC_REPORT);
   return(H3_TC_REDERIVE);
  }

//+------------------------------------------------------------------+
//| Candle export for the diagnostics (pure text building; the file   |
//| is written by the EA). Closed bars only: the caller passes the    |
//| closed-bar set the evaluation used.                               |
//+------------------------------------------------------------------+
struct SH3Export
  {
   string            source;          // who produced the file ("EA" / "SYNTHETIC ...")
   string            symbol;
   string            mode;            // LIVE / HISTORICAL
   datetime          asof;            // input AsOfTime (0 = live)
   int               digits;
   int               period;
   int               left;
   int               right;
   int               lookback;
   int               rebuild;         // R as given by the input
   int               r_req;
   int               r_eff;
   int               b_depth;
   int               chk;
   int               warm;
   int               hard_cap;
   int               bars;
   datetime          first;
   datetime          last;
   string            flag;
   string            reason;
   string            note;
  };

string H3CsvSafeSymbol(const string symbol)
  {
   string out = "";
   int n = StringLen(symbol);
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(symbol, i);
      bool ok = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '.' || c == '_' || c == '-';
      if(ok)
         out += ShortToString(c);
      else
         out += "_";
     }
   return(out);
  }

//--- documented name: velo_t003_diag_<symbol>_<open time of the last closed bar>.csv
string H3CsvName(const string symbol, const datetime last)
  {
   return("velo_t003_diag_" + H3CsvSafeSymbol(symbol) + "_" + H4TimeStamp(last) + ".csv");
  }

string H3CsvTimeText(const datetime t)
  {
   return(TimeToString(t, TIME_DATE | TIME_MINUTES));
  }

string H3CsvHeader(const SH3Export &x)
  {
   string h = "# velo_t003_diag v1\n";
   h += "# source=" + x.source + "\n";
   h += "# symbol=" + x.symbol + "\n";
   h += "# period=H4\n";
   h += "# period_seconds=" + IntegerToString(x.period) + "\n";
   h += "# digits=" + IntegerToString(x.digits) + "\n";
   h += "# mode=" + x.mode + "\n";
   h += "# asof_input=" + (x.asof == 0 ? "0" : H3CsvTimeText(x.asof)) + "\n";
   h += "# first_bar_open=" + H3CsvTimeText(x.first) + "\n";
   h += "# last_closed_bar_open=" + H3CsvTimeText(x.last) + "\n";
   h += "# bars=" + IntegerToString(x.bars) + "\n";
   h += "# left=" + IntegerToString(x.left) + "\n";
   h += "# right=" + IntegerToString(x.right) + "\n";
   h += "# lookback=" + IntegerToString(x.lookback) + "\n";
   h += "# rebuild_input=" + IntegerToString(x.rebuild) + "\n";
   h += "# r_req=" + IntegerToString(x.r_req) + "\n";
   h += "# r_eff=" + IntegerToString(x.r_eff) + "\n";
   h += "# b_depth=" + IntegerToString(x.b_depth) + "\n";
   h += "# check_depth=" + IntegerToString(x.chk) + "\n";
   h += "# warm_up=" + IntegerToString(x.warm) + "\n";
   h += "# hard_cap=" + IntegerToString(x.hard_cap) + "\n";
   h += "# result_flag=" + x.flag + "\n";
   h += "# result_reason=" + x.reason + "\n";
   h += "# note=" + (x.note != "" ? x.note : "-") + "\n";
   h += "time_epoch,time_server,open,high,low,close,tick_volume,spread,real_volume";
   return(h);
  }

string H3CsvRow(const MqlRates &b, const int digits)
  {
   return(IntegerToString((long)b.time) + "," + H3CsvTimeText(b.time) + "," + DoubleToString(b.open, digits) + "," +
          DoubleToString(b.high, digits) + "," + DoubleToString(b.low, digits) + "," + DoubleToString(b.close, digits) + "," +
          IntegerToString((long)b.tick_volume) + "," + IntegerToString((long)b.spread) + "," + IntegerToString((long)b.real_volume));
  }

//+------------------------------------------------------------------+
//| consumer (technical requirement b): cursor = open time of the    |
//| last bar already consumed. Init/restart sets the cursor to the   |
//| baseline (the last closed bar) so no historical event is        |
//| re-emitted; a re-evaluation at the same bar emits nothing; the   |
//| next closed bar emits its events once. Events are returned only  |
//| for the latest closed bar and only when the state before and     |
//| after it are both RELIABLE and A/B agree (ev.prev_ok).           |
//+------------------------------------------------------------------+
datetime H3BaselineCursor(const SH3Eval &ev)
  {
   return(ev.last_time);
  }

int H3ConsumeNew(const SH3Eval &ev, const SH3Event &events[], const datetime cursor, const int period,
                 SH3Event &out[], int &nout)
  {
   nout = 0;
   ArrayResize(out, 0);
   if(!ev.reliable)
      return(H3_C_NOT_RELIABLE);
   if(cursor >= ev.last_time)
      return(H3_C_NOTHING_NEW);
   //--- AMBIGUITY 7: events only for the latest closed bar; an older cursor emits nothing and
   //--- must be re-baselined by the caller (no catching up on missed bars).
   if(cursor == 0 || (long)cursor < (long)ev.last_time - (long)period)
      return(H3_C_GAP);
   if(!ev.prev_ok)
      return(H3_C_REDERIVED);
   for(int i = 0; i < ev.ne; i++)
     {
      if(events[i].bar_time > cursor)
        {
         ArrayResize(out, nout + 1, 8);
         out[nout].type     = events[i].type;
         out[nout].bar_time = events[i].bar_time;
         out[nout].ref      = events[i].ref;
         out[nout].detail   = events[i].detail;
         out[nout].market   = events[i].market;
         nout++;
        }
     }
   return(H3_C_OK);
  }

#endif
