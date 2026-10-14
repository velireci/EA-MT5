//+------------------------------------------------------------------+
//| H4BiasDrawer.mqh                                                 |
//|                                                                  |
//| T003 visual layer - chart objects and the status panel for the   |
//| PROPOSED H4 bias logic (H4Bias.mqh). Draws only: it reads no     |
//| series, no price feed and calls no trading function.             |
//|                                                                  |
//| EVERYTHING DRAWN HERE IS A PROPOSAL / PROTOTYPE (tasks/T003-     |
//| h4-bias-change.md), awaiting the client's visual validation. It  |
//| is NOT a confirmed client rule and NOT a trading signal. The     |
//| T003 bias is never presented as the client's confirmed direction.|
//|                                                                  |
//| What is drawn (revision 10 structure / setup separation):        |
//|  1. T002 structure (HH+HL / LH+LL / MIXED / UNKNOWN) with its    |
//|     two source highs and two source lows (price, pivot time,     |
//|     confirmation time).                                          |
//|  2. T003 prototype bias, the CURRENT protecting level (solid     |
//|     line) and the swings it was selected from.                   |
//|  3. MODEL DISAGREEMENT (T002 BULLISH vs T003 BEAR or T002        |
//|     BEARISH vs T003 BULL only), since-when and for how many      |
//|     closed bars.                                                 |
//|  4. The SETUP, separate from the structure: setup_id, phase,     |
//|     the SNAPSHOT level (dashed line, reference only), the        |
//|     wick / sweep record, the eligible new FVGs, the              |
//|     reconfirmation FVG and the ready flag (SH3SetupCtx).         |
//|  5. HISTORICAL LIQUIDITY (proposal, not ERL / target / protecting|
//|     level): confirmed 2/2 swings not exceeded by a wick, dotted. |
//|     Computed by the pure helpers of H4BiasLayers.mqh; they never |
//|     reach the bias.                                              |
//| Nothing proposal-derived is drawn when the evaluation is         |
//| LIMITED_BY_HISTORY.                                              |
//|                                                                  |
//| Object naming: every object starts with the prefix velo_t003_    |
//| and its name is derived from a stable logic ID (absolute times), |
//| so a redraw or a reload never produces duplicates. The prefix    |
//| cannot collide with velo_t001_ or velo_t002_ (they differ at the |
//| seventh character). Only objects with the T003 prefix are ever   |
//| deleted: never an empty prefix, never another task's prefix,     |
//| never a manual object. The panel uses the sub-prefix             |
//| velo_t003_pnl_, which ClearMap() leaves alone.                   |
//|                                                                  |
//| Panel (compact by default): lines carry a priority; the panel is |
//| wrapped to the chart width and the lowest priority lines are     |
//| dropped when the chart height does not hold them (H3LPanel*).    |
//| Chart labels are short (full text in the object tooltip) and use |
//| a stable slot (H3LLabelSlot); only the text anchor is offset.    |
//|                                                                  |
//| Not compiled or run in this environment (no MetaEditor).         |
//+------------------------------------------------------------------+
#ifndef VELO_H4_BIAS_DRAWER_MQH
#define VELO_H4_BIAS_DRAWER_MQH

#include "H4Bias.mqh"
#include "H4BiasLayers.mqh"

#define H3V_PREFIX        "velo_t003_"
#define H3V_PANEL_PREFIX  "velo_t003_pnl_"

//--- corner of the panel (computed from the chart size; the labels always use the left-upper corner)
#define H3V_PNL_TOP_LEFT      0
#define H3V_PNL_TOP_RIGHT     1
#define H3V_PNL_BOTTOM_LEFT   2
#define H3V_PNL_BOTTOM_RIGHT  3

//--- what the last Draw() put on the chart (for the panel); no handle to any object
struct SH3View
  {
   int               fvg_total;       // eligible FVG tracks of the current wait
   int               fvg_invalid;
   int               fvg_shown;
   int               ev_total;        // events of the replay (history)
   int               ev_shown;
   int               ev_hidden;       // not drawn: over the limit, filtered, or outside the window
   int               t2_cur;          // H4_DIR_* of T002 at the last closed bar
   int               t2_prev;         // H4_DIR_* before the current run, -1 when unknown
   datetime          t2_since;        // open time of the first bar of the current run
   bool              t2_exact;        // false: the run reaches the start of the examined bars
   bool              t2_consistent;   // the recomputed T002 direction equals the one in the state
   string            pivots_text;
   string            missing;         // anything that could not be located (never invented)
   SH3LRun           dis;             // MODEL DISAGREEMENT run (T002 vs T003) at the last closed bar
   bool              dis_consistent;  // the bias rebuilt from the events equals the replay state's bias
   string            t2_src_text;     // the T002 source swings, in words
   int               liq_total;       // unexceeded confirmed swings (historical liquidity, proposal)
   int               liq_shown;
   string            liq_text;        // "|" separated one-line descriptions of the drawn levels
   string            setup_text;      // the setup in words (empty when no setup)
   bool              snap_drawn;
   SH3SetupCtx       ctx;             // read-only context of the live setup (H3SetupContext)
   int               t2_base;         // T002 BASELINE direction: the last `lookback` closed bars (the T002 EA's window)
   int               t2_base_look;    // the lookback of that baseline (InpLookbackBars, clamped)
   int               t2_base_bars;    // bars the baseline really used (fewer than the lookback only when fewer exist)
   SH3LRun           dis_win;         // informational: the same disagreement test with the replay-window structure
   string            fvg_last;        // the reconfirmation FVG, else the latest eligible FVG, with its status (panel)
  };

void H3VViewInit(SH3View &v)
  {
   v.fvg_total     = 0;
   v.fvg_invalid   = 0;
   v.fvg_shown     = 0;
   v.ev_total      = 0;
   v.ev_shown      = 0;
   v.ev_hidden     = 0;
   v.t2_cur        = H4_DIR_UNKNOWN;
   v.t2_prev       = -1;
   v.t2_since      = 0;
   v.t2_exact      = false;
   v.t2_consistent = true;
   v.pivots_text   = "";
   v.missing       = "";
   H3LRunInit(v.dis);
   v.dis_consistent = true;
   v.t2_src_text   = "";
   v.liq_total     = 0;
   v.liq_shown     = 0;
   v.liq_text      = "";
   v.setup_text    = "";
   v.snap_drawn    = false;
   v.t2_base       = H4_DIR_UNKNOWN;
   v.t2_base_look  = 0;
   v.t2_base_bars  = 0;
   H3LRunInit(v.dis_win);
   v.fvg_last      = "";
   SH3State s0;
   H3StateInit(s0);
   SH3Track t0[];
   H3SetupContext(s0, t0, 0, v.ctx);
  }

//+------------------------------------------------------------------+
//| pure helpers (no chart access)                                   |
//+------------------------------------------------------------------+
string H3VTime(const datetime t)
  {
   if(t <= 0)
      return("-");
   return(TimeToString(t, TIME_DATE | TIME_MINUTES));
  }

//--- object-name safe text: letters, digits and underscore only
string H3VSanitize(const string s)
  {
   string out = "";
   int len = StringLen(s);
   for(int i = 0; i < len; i++)
     {
      ushort c = StringGetCharacter(s, i);
      bool ok = ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_');
      if(ok)
         out += ShortToString(c);
      else
         out += "_";
     }
   return(out);
  }

//--- "yyyymmddhhmm" (the H4TimeStamp format) back to a time value; 0 when malformed
datetime H3VStampToTime(const string stamp)
  {
   if(StringLen(stamp) != 12)
      return(0);
   for(int i = 0; i < 12; i++)
     {
      ushort c = StringGetCharacter(stamp, i);
      if(c < '0' || c > '9')
         return(0);
     }
   MqlDateTime dt;
   dt.year        = (int)StringToInteger(StringSubstr(stamp, 0, 4));
   dt.mon         = (int)StringToInteger(StringSubstr(stamp, 4, 2));
   dt.day         = (int)StringToInteger(StringSubstr(stamp, 6, 2));
   dt.hour        = (int)StringToInteger(StringSubstr(stamp, 8, 2));
   dt.min         = (int)StringToInteger(StringSubstr(stamp, 10, 2));
   dt.sec         = 0;
   dt.day_of_week = 0;
   dt.day_of_year = 0;
   return(StructToTime(dt));
  }

//--- value of key in "k1=v1;k2=v2" (key must start the text or follow a ';'); "" when absent
string H3VDetailValue(const string detail, const string key)
  {
   string needle = key + "=";
   int nl = StringLen(needle);
   int from = 0;
   for(int guard = 0; guard < 32; guard++)
     {
      int p = StringFind(detail, needle, from);
      if(p < 0)
         return("");
      if(p == 0 || StringGetCharacter(detail, p - 1) == ';')
        {
         int e = StringFind(detail, ";", p);
         if(e < 0)
            e = StringLen(detail);
         return(StringSubstr(detail, p + nl, e - p - nl));
        }
      from = p + 1;
     }
   return("");
  }

//--- short chart label of an event; is_new marks an event reported after the baseline
string H3VEventLabel(const SH3Event &e, const bool is_new)
  {
   string s = (is_new ? ">> NEW " : "");
   s += H3EventName(e.type);
   string dir = H3VDetailValue(e.detail, "dir");
   if(e.type == H3_EV_FLIP)
      s += " " + H3VDetailValue(e.detail, "from") + "->" + dir;
   else
      if(e.type == H3_EV_BREAK_SET || e.type == H3_EV_SEED)
         s += " " + dir;
      else
         if(e.type == H3_EV_WICK)
           {
            s += " " + dir;
            if(H3VDetailValue(e.detail, "retro") == "1")
               s += " retro";
           }
         else
            if(e.type == H3_EV_SETUP_ENDED)
               s += " " + H3VDetailValue(e.detail, "reason");
   return(s);
  }

//--- the SHORT chart text of an event (the full event id and detail go to the object tooltip and the Experts log)
string H3VEventShort(const SH3Event &e, const bool is_new)
  {
   string s = (is_new ? "NEW " : "");
   string dir = H3VDetailValue(e.detail, "dir");
   string d = (dir == "BULL" ? " bull" : (dir == "BEAR" ? " bear" : ""));
   if(e.type == H3_EV_FLIP)
      return(s + "FLIP" + d);
   if(e.type == H3_EV_BREAK_SET)
      return(s + "SET" + d);
   if(e.type == H3_EV_SEED)
      return(s + "SEED" + d);
   if(e.type == H3_EV_WICK)
      return(s + "WICK" + d);
   if(e.type == H3_EV_NONE_WICK)
      return(s + "nWICK");
   if(e.type == H3_EV_CONFLICT)
      return(s + "CONFL");
   if(e.type == H3_EV_RECONFIRMED)
      return(s + "RECONF");
   if(e.type == H3_EV_RECONF_LOST)
      return(s + "RECONF-");
   if(e.type == H3_EV_INT_SWEEP)
      return(s + "SWEEP" + d);
   if(e.type == H3_EV_SETUP_ENDED)
      return(s + "END");
   if(e.type == H3_EV_SNAP_CROSSED)
      return(s + "SNAPX");
   if(e.type == H3_EV_CONTINUATION)
      return(s + "CONT");
   return(s + "IBRK");
  }

color H3VEventColor(const int type)
  {
   if(type == H3_EV_FLIP || type == H3_EV_BREAK_SET || type == H3_EV_SEED || type == H3_EV_CONFLICT)
      return(clrGold);
   if(type == H3_EV_WICK || type == H3_EV_NONE_WICK)
      return(clrOrange);
   if(type == H3_EV_RECONFIRMED || type == H3_EV_RECONF_LOST)
      return(clrAqua);
   if(type == H3_EV_SETUP_ENDED)
      return(clrPlum);
   if(type == H3_EV_INT_SWEEP || type == H3_EV_INT_BREAK)
      return(clrViolet);
   return(clrSilver);
  }

bool H3VIdInList(const string id, const string &ids[], const int n)
  {
   for(int i = 0; i < n; i++)
      if(ids[i] == id)
         return(true);
   return(false);
  }

//--- the phase with its reason, in words (a description of the replayed state, not a decision)
string H3VPhaseReason(const SH3State &st)
  {
   if(st.dir == H3_NONE)
      return("no bias (" + H3NoneReasonName(st.none_reason) + ")");
   if(st.phase == H3_PH_HOLD)
      return("HOLD: a wick crossed the protecting level (the snapshot of that moment) without a body close beyond it; HOLD from detected_at " +
             H3VTime(st.wk_det) + "; the setup waits for an eligible new FVG to be touched (the CURRENT level still decides a flip)");
   if(st.phase == H3_PH_SWEEP_WAIT)
      return("SWEEP_WAIT: interior swing taken at " + H3VTime(st.sweep_time) +
             "; waiting for an eligible new FVG to be touched (technical proposal)");
   if(st.phase == H3_PH_RECONFIRMED)
     {
      if(st.recon_reason == H3_RR_INTERNAL)
         return("RECONFIRMED (INTERNAL): eligible FVG " + st.rec_id + " touched after the interior sweep");
      return("RECONFIRMED (STRUCT): eligible FVG " + st.rec_id + " touched after the structural wick");
     }
   return("ACTIVE: no setup; protecting level " + (st.has_level ? "defined" : "NOT defined") + ", origin " + H3OriginName(st.origin));
  }

//--- the swing with this pivot time, or -1
int H3VFindSwing(const SH4Swing &sw[], const int ns, const datetime pivot_time)
  {
   for(int i = 0; i < ns; i++)
      if(sw[i].pivot_time == pivot_time)
         return(i);
   return(-1);
  }

//--- T002 direction over the examined bars: the current run (since the first bar whose close gave
//--- the same direction) and the direction before it. Same derivation as the replay's t2dir.
void H3VT2Run(const MqlRates &bars[], const int nw, const SH4Swing &sw[], const int ns, const int right,
              const int warm, const string state_t2dir, SH3View &v)
  {
   v.t2_cur   = H4_DIR_UNKNOWN;
   v.t2_prev  = -1;
   v.t2_since = 0;
   v.t2_exact = false;
   if(nw < 1)
      return;
   v.t2_cur = H4DeriveDirection(sw, H3KnownCount(sw, ns, right, nw - 1));
   v.t2_consistent = (H4DirName(v.t2_cur) == state_t2dir);
   int first = nw - 1;
   int stop = (warm < nw - 1 ? warm : nw - 1);
   for(int t = nw - 2; t >= stop; t--)
     {
      int d = H4DeriveDirection(sw, H3KnownCount(sw, ns, right, t));
      if(d != v.t2_cur)
        {
         v.t2_prev  = d;
         v.t2_exact = true;
         break;
        }
      first = t;
     }
   v.t2_since = bars[first].time;
  }

//+------------------------------------------------------------------+
//| the chart objects                                                |
//+------------------------------------------------------------------+
class CH3BiasDrawer
  {
private:
   string            m_prefix;
   string            m_panel_prefix;
   long              m_chart;
   int               m_font;
   color             m_clr_bear;
   color             m_clr_bull;
   color             m_clr_dim;
   color             m_clr_level;
   color             m_clr_t2;      // T002 structure marks
   color             m_clr_snap;    // snapshot (dashed, reference only)
   color             m_clr_liq;     // historical liquidity (dotted, thin)
   color             m_clr_dis;     // MODEL DISAGREEMENT

   bool              Ensure(const string name, const ENUM_OBJECT type)
     {
      if(ObjectFind(m_chart, name) >= 0)
         return(true);
      if(!ObjectCreate(m_chart, name, type, 0, 0, 0))
        {
         ResetLastError();
         return(false);
        }
      ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN, true);
      return(true);
     }

   void              Put(const string name, const int idx, const datetime t, const double p)
     {
      ObjectSetInteger(m_chart, name, OBJPROP_TIME, idx, t);
      ObjectSetDouble(m_chart, name, OBJPROP_PRICE, idx, p);
     }

   void              Segment(const string name, const datetime t1, const double p1,
                             const datetime t2, const double p2, const color clr,
                             const int width, const ENUM_LINE_STYLE style)
     {
      if(!Ensure(name, OBJ_TREND))
         return;
      Put(name, 0, t1, p1);
      Put(name, 1, t2, p2);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chart, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(m_chart, name, OBJPROP_STYLE, style);
      ObjectSetInteger(m_chart, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(m_chart, name, OBJPROP_BACK, false);
     }

   //--- a text label. Only the TEXT ANCHOR is placed by the caller (the price passed here is the label position,
   //--- never a level coordinate); `tip` is the full text shown as the object tooltip ("" = same as the text).
   void              Note(const string name, const datetime t, const double p, const string text,
                          const color clr, const ENUM_ANCHOR_POINT anchor, const int fontsize, const string tip = "")
     {
      if(!Ensure(name, OBJ_TEXT))
         return;
      Put(name, 0, t, p);
      ObjectSetString(m_chart, name, OBJPROP_TEXT, text);
      ObjectSetString(m_chart, name, OBJPROP_TOOLTIP, (tip != "" ? tip : text));
      ObjectSetString(m_chart, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(m_chart, name, OBJPROP_FONTSIZE, fontsize);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chart, name, OBJPROP_ANCHOR, anchor);
     }

   void              Rect(const string name, const datetime t1, const double p1,
                          const datetime t2, const double p2, const color clr,
                          const int width, const bool fill, const ENUM_LINE_STYLE style)
     {
      if(!Ensure(name, OBJ_RECTANGLE))
         return;
      Put(name, 0, t1, p1);
      Put(name, 1, t2, p2);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chart, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(m_chart, name, OBJPROP_STYLE, style);
      ObjectSetInteger(m_chart, name, OBJPROP_FILL, fill);
      ObjectSetInteger(m_chart, name, OBJPROP_BACK, true);
     }

   //--- text mark at a confirmed swing; the text carries the confirmation time
   string            Pivot(const SH4Swing &sw[], const int ns, const datetime pivot_time, const string tag,
                           const color clr, SH3View &v)
     {
      int k = H3VFindSwing(sw, ns, pivot_time);
      if(k < 0)
        {
         v.missing += (v.missing != "" ? "; " : "") + tag + " pivot " + H3VTime(pivot_time) + " not among the swings";
         return(tag + " pivot " + H3VTime(pivot_time) + " (swing not found)");
        }
      string txt = StringFormat("%s %s", tag, DoubleToString(sw[k].price, _Digits));
      string full = StringFormat("%s %s %s  pivot %s  known %s", tag, (sw[k].is_high ? "SH" : "SL"),
                                 DoubleToString(sw[k].price, _Digits), H3VTime(pivot_time), H3VTime(sw[k].confirm_time));
      Note(m_prefix + "pv_" + H3VSanitize(tag) + "_" + H4TimeStamp(pivot_time), pivot_time, sw[k].price, txt, clr,
           (sw[k].is_high ? ANCHOR_LOWER : ANCHOR_UPPER), m_font, full);
      return(StringFormat("%s %s %s pivot %s known %s", tag, (sw[k].is_high ? "SH" : "SL"),
                          DoubleToString(sw[k].price, _Digits), H3VTime(pivot_time), H3VTime(sw[k].confirm_time)));
     }

   string            T2Facts(const SH4Swing &sw[], const int k, const string tag)
     {
      if(k < 0)
         return(tag + " none");
      return(StringFormat("%s %s %s pivot %s known %s", tag, (sw[k].is_high ? "SH" : "SL"), DoubleToString(sw[k].price, _Digits),
                          H3VTime(sw[k].pivot_time), H3VTime(sw[k].confirm_time)));
     }

   //--- T002 source swing: a SHORT text mark near the pivot (the label anchor is shifted away from the bar by `off`;
   //--- the swing price itself is untouched) with the full facts (price, pivot time, confirmation time) in the
   //--- tooltip. Returns the same facts for the panel.
   string            T2Mark(const SH4Swing &sw[], const int k, const string tag, const double off, SH3View &v)
     {
      if(k < 0)
         return(tag + " none");
      string facts = T2Facts(sw, k, tag);
      Note(m_prefix + "t2_" + H3VSanitize(tag) + "_" + H4TimeStamp(sw[k].pivot_time), sw[k].pivot_time,
           sw[k].price + (sw[k].is_high ? off : -off), "T2 " + tag + " " + DoubleToString(sw[k].price, _Digits), m_clr_t2,
           (sw[k].is_high ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER), m_font - 1, "T002 source: " + facts);
      return(facts);
     }

public:
                     CH3BiasDrawer(void)
     {
      m_prefix       = H3V_PREFIX;
      m_panel_prefix = H3V_PANEL_PREFIX;
      m_chart        = 0;
      m_font         = 8;
      m_clr_bear     = clrTomato;
      m_clr_bull     = clrDodgerBlue;
      m_clr_dim      = clrDimGray;
      m_clr_level    = clrOrange;
      m_clr_t2       = clrWhite;
      m_clr_snap     = clrGoldenrod;
      m_clr_liq      = clrLightSlateGray;
      m_clr_dis      = clrOrangeRed;
     }

   string            PanelPrefix(void) const { return(m_panel_prefix); }

   void              Init(const color bear, const color bull, const color level, const int font_size)
     {
      m_chart     = ChartID();
      m_clr_bear  = bear;
      m_clr_bull  = bull;
      m_clr_level = level;
      m_font      = (font_size < 6 ? 6 : (font_size > 20 ? 20 : font_size));
      ClearAll();
     }

   //--- Delete EVERY object of this task (map and panel). Prefix only, and the prefix is never empty.
   void              ClearAll(void)
     {
      ObjectsDeleteAll(m_chart, m_prefix);
     }

   //--- Delete the map objects but keep the panel (sub-prefix velo_t003_pnl_).
   void              ClearMap(void)
     {
      for(int i = ObjectsTotal(m_chart, 0, -1) - 1; i >= 0; i--)
        {
         string name = ObjectName(m_chart, i, 0, -1);
         if(StringFind(name, m_prefix) != 0)
            continue;
         if(StringFind(name, m_panel_prefix) == 0)
            continue;
         ObjectDelete(m_chart, name);
        }
     }

   void              Reset(void)
     {
      ClearMap();
      ChartRedraw(m_chart);
     }

   //--- Redraw the whole T003 map from one RELIABLE evaluation. bars[0..n-1] are the closed bars the
   //--- evaluation was given; the examined window is the last ev.r_eff of them (replay A), from which the
   //--- swings and FVG geometry are recomputed with the same T002 functions. When the evaluation is not
   //--- reliable (LIMITED_BY_HISTORY) NOTHING proposal-derived is drawn (the panel reports the state).
   //--- Read-only with respect to the logic: ev, tracks and events are const, the state is only COPIED.
   void              Draw(const MqlRates &bars[], const int n, const SH3Params &p, const SH3Eval &ev,
                          const SH3Track &tracks[], const SH3Event &events[],
                          const string &new_ids[], const int n_new,
                          const int max_events, const int max_fvgs,
                          const bool show_nonmarket, const bool show_invalid,
                          const bool show_liq, const int liq_max, const bool show_t2src, SH3View &v)
     {
      ClearMap();
      H3VViewInit(v);
      v.ev_total  = ev.ne;
      v.fvg_total = ev.nt;
      if(!ev.reliable || !ev.has_state || n < 1 || ev.r_eff < 1)
        {
         ChartRedraw(m_chart);
         return;
        }
      int w0 = n - ev.r_eff;
      if(w0 < 0)
         w0 = 0;
      int nw = n - w0;
      MqlRates win[];
      ArrayResize(win, nw);
      ArrayCopy(win, bars, 0, w0, nw);
      SH4Swing sw[];
      SH4Fvg fv[];
      int amb = 0;
      int ns = H4FindSwings(win, nw, p.left, p.right, p.period, sw, amb);
      int nf = H4FindFvgs(win, nw, p.period, fv);
      datetime x_end = win[nw - 1].time + (datetime)(p.period * 6);
      datetime t_last = win[nw - 1].time;
      SH3State st;
      H3StateCopy(ev.st, st);                   // field-wise copy: the struct holds strings
      H3SetupContext(st, tracks, ev.nt, v.ctx); // read-only setup context (SH3SetupCtx)

      H3VT2Run(win, nw, sw, ns, p.right, H3WarmUp(p), st.t2dir, v);
      //--- T002 BASELINE: the direction of the last `lookback` closed bars (the T002 EA's window, same functions).
      //--- v.t2_cur above is the REPLAY-WINDOW structure (the whole window): a different thing, named so.
      v.t2_base_look = p.lookback;
      v.t2_base      = H3LBaselineDir(win, nw, p.lookback, p.left, p.right, p.period, v.t2_base_bars);
      //--- MODEL DISAGREEMENT in terms of the T002 BASELINE: from the replay events and the baseline at every bar,
      //--- by absolute bar times. The replay-window test is kept for information only.
      H3LDisagreeRunBase(win, nw, p.lookback, p.left, p.right, p.period, H3WarmUp(p), events, ev.ne, v.dis);
      H3LDisagreeRun(win, nw, sw, ns, p.right, H3WarmUp(p), events, ev.ne, v.dis_win);
      v.dis_consistent = (v.dis.bias == st.dir);

      //--- the average bar range, used to stack labels
      double rsum = 0.0;
      int rcnt = 0;
      double pmax = win[nw - 1].high;
      double pmin = win[nw - 1].low;
      for(int b = nw - 1; b >= 0 && rcnt < 30; b--)
        {
         rsum += (win[b].high - win[b].low);
         if(win[b].high > pmax)
            pmax = win[b].high;
         if(win[b].low < pmin)
            pmin = win[b].low;
         rcnt++;
        }
      double step = (rcnt > 0 ? rsum / rcnt * 0.6 : 0.0);

      //--- 0. T002 structure (HH+HL / LH+LL / MIXED / UNKNOWN) with its two source highs and two source lows
      int nk = H3KnownCount(sw, ns, p.right, nw - 1);
      int ih2 = -1, ih1 = -1, il2 = -1, il1 = -1;
      H3LT2Sources(sw, nk, ih2, ih1, il2, il1);
      string s1 = T2Facts(sw, ih2, "H-latest");
      string s2 = T2Facts(sw, ih1, "H-prev");
      string s3 = T2Facts(sw, il2, "L-latest");
      string s4 = T2Facts(sw, il1, "L-prev");
      v.t2_src_text = s1 + " | " + s2 + " | " + s3 + " | " + s4;
      if(show_t2src)
        {
         T2Mark(sw, ih2, "H-latest", step * 2.0, v);
         T2Mark(sw, ih1, "H-prev", step * 2.0, v);
         T2Mark(sw, il2, "L-latest", step * 2.0, v);
         T2Mark(sw, il1, "L-prev", step * 2.0, v);
        }
      Note(m_prefix + "t2_now", t_last, win[nw - 1].high + step * 1.2,
           StringFormat("T002 baseline(%d): %s", v.t2_base_look, H4DirName(v.t2_base)),
           m_clr_t2, ANCHOR_LOWER, m_font,
           H3LT2Name(v.t2_base_look) + ": " + H4DirName(v.t2_base) + " (" + H3LStructureWords(v.t2_base) + "), " +
           IntegerToString(v.t2_base_bars) + " closed bars; the replay-window structure is " + H4DirName(v.t2_cur) +
           ". Proposal 2/2 swings.");

      //--- 1. the CURRENT protecting level (solid) and the pivots it was selected from
      if(st.dir != H3_NONE)
        {
         color bc = (st.dir == H3_BEAR ? m_clr_bear : m_clr_bull);
         Note(m_prefix + "t3_now", t_last, win[nw - 1].low - step * 1.2,
              "T003 proto " + H3DirName(st.dir) + " " + H3PhaseName(st.phase),
              bc, ANCHOR_UPPER, m_font,
              "T003 PROTOTYPE bias " + H3DirName(st.dir) + " " + H3PhaseName(st.phase) +
              " (PROPOSAL, not the client's confirmed direction)");
        }
      if(st.dir != H3_NONE && st.has_level)
        {
         color lc = (st.dir == H3_BEAR ? m_clr_bear : m_clr_bull);
         Segment(m_prefix + "lvl_" + H3LShort(st.lv_id), st.lv_pivot, st.lv_price, x_end, st.lv_price, lc, 2, STYLE_SOLID);
         Note(m_prefix + "lvl_lbl_" + H3LShort(st.lv_id), x_end, st.lv_price,
              StringFormat("CURRENT %s", DoubleToString(st.lv_price, _Digits)),
              lc, ANCHOR_RIGHT_LOWER, m_font,
              StringFormat("CURRENT protecting level (PROPOSAL, solid) %s known %s - decides FLIP", DoubleToString(st.lv_price, _Digits),
                           H3VTime(st.lv_known)));
         string t1 = Pivot(sw, ns, st.lv_pivot, "S", lc, v);
         string t2 = Pivot(sw, ns, st.lv_ext, (st.dir == H3_BEAR ? "LL" : "HH"), m_clr_level, v);
         string t3 = Pivot(sw, ns, st.lv_prev, (st.dir == H3_BEAR ? "prevLL" : "prevHH"), m_clr_level, v);
         v.pivots_text = t1 + " | " + t2 + " | " + t3;
        }
      //--- the SNAPSHOT of the protecting level at the creation of the setup: dashed, REFERENCE ONLY
      if(st.dir != H3_NONE && st.setup_id != "" && st.snap_id != "")
        {
         datetime ts = H3VStampToTime(StringSubstr(st.snap_id, 2, 12));
         if(ts <= 0)
            ts = (st.snap_known > 0 ? st.snap_known : t_last);
         bool same = (st.has_level && st.snap_id == st.lv_id);
         Segment(m_prefix + "snap_" + H3LShort(st.setup_id), ts, st.snap_price, x_end, st.snap_price, m_clr_snap, 1, STYLE_DASH);
         Note(m_prefix + "snap_lbl_" + H3LShort(st.setup_id), x_end, st.snap_price,
              StringFormat("SNAPSHOT %s (ref)%s", DoubleToString(st.snap_price, _Digits), (same ? " =CURRENT" : "")),
              m_clr_snap, ANCHOR_RIGHT_UPPER, m_font,
              StringFormat("SNAPSHOT (dashed, reference only) %s known %s%s", DoubleToString(st.snap_price, _Digits),
                           H3VTime(st.snap_known), (same ? " = current level" : "")));
         v.snap_drawn = true;
        }
      //--- interior swing candidate (technical proposal P14); the time is part of its ID
      if(st.dir != H3_NONE && st.has_lint)
        {
         datetime ti = H3VStampToTime(StringSubstr(st.li_id, 2, 12));
         if(ti > 0)
           {
            Segment(m_prefix + "lint_" + H3LShort(st.li_id), ti, st.li_price, x_end, st.li_price, m_clr_dim, 1, STYLE_DOT);
            Note(m_prefix + "lint_lbl_" + H3LShort(st.li_id), x_end, st.li_price,
                 StringFormat("interior %s%s", DoubleToString(st.li_price, _Digits), (st.li_consumed ? " used" : "")),
                 m_clr_dim, ANCHOR_RIGHT_UPPER, m_font - 1,
                 StringFormat("interior candidate (P14 proposal, not the historical liquidity layer) %s%s",
                              DoubleToString(st.li_price, _Digits), (st.li_consumed ? " CONSUMED" : "")));
           }
         else
            v.missing += (v.missing != "" ? "; " : "") + "interior level time not parsable from " + st.li_id;
        }

      //--- 2. the wick and the internal sweep, with all their timestamps
      if(st.dir != H3_NONE && st.has_wick)
        {
         int iw = H3BarIndexByTime(win, nw, st.wk_src);
         if(iw >= 0)
           {
            double wp = (st.dir == H3_BEAR ? win[iw].high : win[iw].low);
            Note(m_prefix + "wick_" + H4TimeStamp(st.wk_src), st.wk_src, wp,
                 (st.wk_retro ? "WICK retro" : "WICK"),
                 clrOrange, (st.dir == H3_BEAR ? ANCHOR_LOWER : ANCHOR_UPPER), m_font,
                 StringFormat("WICK source_wick_time %s | known %s | detected_at %s%s", H3VTime(st.wk_src),
                              H3VTime(st.wk_known), H3VTime(st.wk_det), (st.wk_retro ? " RETROACTIVE" : "")));
            if(st.wk_det > 0)
               Note(m_prefix + "det_" + H4TimeStamp(st.wk_det), st.wk_det, (st.has_level ? st.lv_price : wp),
                    "det", clrOrange, (st.dir == H3_BEAR ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER), m_font - 1,
                    "detected_at " + H3VTime(st.wk_det));
           }
         else
            v.missing += (v.missing != "" ? "; " : "") + "wick bar " + H3VTime(st.wk_src) + " not in the examined bars";
        }
      if(st.dir != H3_NONE && st.sweep_time != 0)
        {
         int isw = H3BarIndexByTime(win, nw, st.sweep_time);
         if(isw >= 0)
           {
            double sp = (st.dir == H3_BEAR ? win[isw].high : win[isw].low);
            Note(m_prefix + "sweep_" + H4TimeStamp(st.sweep_time), st.sweep_time, sp,
                 "SWEEP", clrViolet, (st.dir == H3_BEAR ? ANCHOR_LOWER : ANCHOR_UPPER), m_font,
                 StringFormat("INTERNAL SWEEP (proposal) bar %s | wait from %s", H3VTime(st.sweep_time),
                              H3VTime(st.wait_start)));
           }
         else
            v.missing += (v.missing != "" ? "; " : "") + "sweep bar " + H3VTime(st.sweep_time) + " not in the examined bars";
        }
      //--- the SETUP as one label at its last bar (id, phase, reason, ready); the facts are in the panel too
      if(v.ctx.valid)
        {
         Note(m_prefix + "setup_lbl", t_last, win[nw - 1].low - step * 2.4,
              StringFormat("SETUP %s ready %s", v.ctx.phase, (v.ctx.ready ? "YES" : "no")),
              clrGold, ANCHOR_UPPER, m_font,
              StringFormat("SETUP (PROPOSAL) %s %s %s phase %s ready %s", v.ctx.setup_id, v.ctx.stype, v.ctx.reason, v.ctx.phase,
                           (v.ctx.ready ? "YES" : "no")));
        }

      //--- 3. eligible new FVGs (most recent first up to the limit) and the reconfirmation FVG
      int nt = ev.nt;
      bool chosen[];
      ArrayResize(chosen, nt);
      int shown = 0;
      for(int i = 0; i < nt; i++)
        {
         chosen[i] = false;
         if(tracks[i].invalid)
            v.fvg_invalid++;
        }
      for(int i2 = nt - 1; i2 >= 0 && shown < max_fvgs; i2--)
        {
         if(tracks[i2].invalid && !show_invalid)
            continue;
         chosen[i2] = true;
         shown++;
        }
      if(st.rec_id != "")
         for(int i3 = 0; i3 < nt; i3++)
            if(tracks[i3].id == st.rec_id)
               chosen[i3] = true;
      bool rec_set = false;
      for(int i4 = 0; i4 < nt; i4++)
        {
         if(!chosen[i4])
            continue;
         int fk = -1;
         for(int q = 0; q < nf; q++)
            if(fv[q].id == tracks[i4].id)
              {
               fk = q;
               break;
              }
         if(fk < 0)
           {
            v.missing += (v.missing != "" ? "; " : "") + "FVG " + tracks[i4].id + " geometry not found";
            continue;
           }
         bool is_rec = (st.rec_id != "" && tracks[i4].id == st.rec_id);
         color fc = (tracks[i4].invalid ? m_clr_dim : (fv[fk].bullish ? m_clr_bull : m_clr_bear));
         string status = (tracks[i4].invalid ? "INVALID" : (tracks[i4].recorded ? "TOUCHED" : "FRESH"));
         if(is_rec)
            Rect(m_prefix + "fvg_" + fv[fk].id, fv[fk].time_a, fv[fk].upper, x_end, fv[fk].lower, clrGold, 3, true, STYLE_SOLID);
         else
            Rect(m_prefix + "fvg_" + fv[fk].id, fv[fk].time_a, fv[fk].upper, x_end, fv[fk].lower, fc, 1, false,
                 tracks[i4].invalid ? STYLE_DOT : STYLE_SOLID);
         string lbl = StringFormat("FVG %s %s", (fv[fk].bullish ? "bull" : "bear"), (is_rec ? "RECONF" : status));
         string lbl_full = StringFormat("%s eligible FVG (proposal) %s %s [%s - %s]%s", (fv[fk].bullish ? "bull" : "bear"), fv[fk].id,
                                        status, DoubleToString(fv[fk].lower, _Digits), DoubleToString(fv[fk].upper, _Digits),
                                        (is_rec ? "  RECONFIRMATION FVG" : ""));
         Note(m_prefix + "fvgt_" + fv[fk].id, fv[fk].time_a, fv[fk].upper, lbl, (is_rec ? clrGold : fc),
              ANCHOR_LEFT_LOWER, m_font, lbl_full);
         if(is_rec || !rec_set)
            v.fvg_last = StringFormat("%s %s [%s - %s]%s", fv[fk].id, status, DoubleToString(fv[fk].lower, _Digits),
                                      DoubleToString(fv[fk].upper, _Digits), (is_rec ? " RECONFIRMATION" : ""));
         if(is_rec)
            rec_set = true;
         v.fvg_shown++;
        }

      //--- 4. the most recent events, history versus new
      int drawn = 0;
      for(int e = ev.ne - 1; e >= 0; e--)
        {
         if(!events[e].market && !show_nonmarket)
           {
            v.ev_hidden++;
            continue;
           }
         if(drawn >= max_events)
           {
            v.ev_hidden++;
            continue;
           }
         int ib = H3BarIndexByTime(win, nw, events[e].bar_time);
         if(ib < 0)
           {
            v.ev_hidden++;
            continue;
           }
         //--- STABLE vertical slot: the label's rank among the events of the SAME bar in the logic's own event order
         //--- (not the draw order, not the number of events drawn) and the bar's position in time. Only the label
         //--- position is offset; the event bar and every level keep their real coordinates.
         int seq = 0;
         for(int q2 = e - 1; q2 >= 0 && events[q2].bar_time == events[e].bar_time; q2--)
            seq++;
         int slot = H3LLabelSlot(events[e].bar_time, p.period, seq, 3);
         string eid = H3EventId(events[e].type, events[e].bar_time, events[e].ref);
         bool is_new = H3VIdInList(eid, new_ids, n_new);
         Note(m_prefix + "ev_" + H4TimeStamp(events[e].bar_time) + "_" + H3LShort(eid),
              events[e].bar_time, win[ib].high + step * (5.0 + slot * 1.0), H3VEventShort(events[e], is_new),
              (is_new ? clrLime : H3VEventColor(events[e].type)), ANCHOR_LOWER, (is_new ? m_font + 1 : m_font),
              H3VEventLabel(events[e], is_new) + " | bar " + H3VTime(events[e].bar_time) + " | " + H3EventText(events[e]));
         drawn++;
        }
      v.ev_shown = drawn;

      //--- 5. HISTORICAL LIQUIDITY (PROPOSAL - historical liquidity, not ERL / target / protecting level)
      if(show_liq && liq_max > 0)
        {
         int sel[];
         int tot = 0;
         int cnt = H3LLiquidity(win, nw, sw, ns, p.right, liq_max, sel, tot);
         v.liq_total = tot;
         for(int z = 0; z < cnt; z++)
           {
            int kz = sel[z];
            string kind = (sw[kz].is_high ? "SH" : "SL");
            string one = StringFormat("%s %s pivot %s known %s", kind, DoubleToString(sw[kz].price, _Digits),
                                      H3VTime(sw[kz].pivot_time), H3VTime(sw[kz].confirm_time));
            Segment(m_prefix + "liq_" + sw[kz].id, sw[kz].pivot_time, sw[kz].price, x_end, sw[kz].price, m_clr_liq, 1, STYLE_DOT);
            //--- a swing that already carries a level-pivot mark (S / LL / prevLL) keeps its dotted line but gets no
            //--- second text on the same spot (a rule of the swing, not of the draw order)
            bool marked = (st.dir != H3_NONE && st.has_level &&
                           (sw[kz].pivot_time == st.lv_pivot || sw[kz].pivot_time == st.lv_ext || sw[kz].pivot_time == st.lv_prev));
            if(!marked)
               Note(m_prefix + "liq_lbl_" + sw[kz].id, sw[kz].pivot_time, sw[kz].price,
                    StringFormat("liq %s", DoubleToString(sw[kz].price, _Digits)),
                    m_clr_liq, (sw[kz].is_high ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER), m_font - 1,
                    StringFormat("historical liquidity (proposal) %s %s (pivot %s, known %s)", kind, DoubleToString(sw[kz].price, _Digits),
                                 H3VTime(sw[kz].pivot_time), H3VTime(sw[kz].confirm_time)));
            v.liq_text += (v.liq_text != "" ? "|" : "") + one;
            v.liq_shown++;
           }
        }

      //--- 6. MODEL DISAGREEMENT: a line from the start of the run and the banner next to the last bar
      if(v.dis.active)
        {
         Segment(m_prefix + "dis_since", v.dis.since, pmin, v.dis.since, pmax, m_clr_dis, 1, STYLE_DOT);
         Note(m_prefix + "dis_lbl", t_last, win[nw - 1].high + step * 3.0,
              H3LDisagreeShort(v.dis),
              m_clr_dis, ANCHOR_RIGHT_LOWER, m_font, H3LDisagreeText(v.dis, p.period));
        }
      ChartRedraw(m_chart);
     }
  };

//+------------------------------------------------------------------+
//| the status panel: a background rectangle plus one label per line |
//+------------------------------------------------------------------+
class CH3Panel
  {
private:
   string            m_prefix;
   string            m_bg;
   long              m_chart;
   bool              m_enabled;
   int               m_corner;
   int               m_font;
   int               m_lh;
   double            m_cw;
   int               m_pad;
   int               m_margin;
   color             m_bgclr;
   string            m_rt[];       // the lines as given (text, colour, priority); wrapped and budgeted at layout time
   color             m_rc[];
   int               m_rp[];
   int               m_rn;
   string            m_lines[];    // the rows of the last layout
   color             m_clrs[];
   int               m_n;
   int               m_created;
   int               m_last_w;     // chart size of the last layout
   int               m_last_h;
   int               m_hidden;     // lines dropped by the last layout (lowest priority first)

   string            LabelName(const int i) const
     {
      return(StringFormat("%s%03d", m_prefix, i));
     }

   void              Push(const string text, const color clr)
     {
      ArrayResize(m_lines, m_n + 1, 32);
      ArrayResize(m_clrs, m_n + 1, 32);
      m_lines[m_n] = text;
      m_clrs[m_n]  = clr;
      m_n++;
     }

public:
                     CH3Panel(void)
     {
      m_prefix  = H3V_PANEL_PREFIX;
      m_bg      = H3V_PANEL_PREFIX + "bg";
      m_chart   = 0;
      m_enabled = false;
      m_corner  = H3V_PNL_TOP_LEFT;
      m_font    = 9;
      m_lh      = 16;
      m_cw      = 7.0;
      m_pad     = 6;
      m_margin  = 8;
      m_bgclr   = C'16,20,28';
      m_rn      = 0;
      m_n       = 0;
      m_created = 0;
      m_last_w  = 0;
      m_last_h  = 0;
      m_hidden  = 0;
     }

   int               Hidden(void) const { return(m_hidden); }

   //--- the configured font is kept (7..24): a panel that does not fit loses its LOWEST priority lines, its font is
   //--- never shrunk to an unreadable size
   void              Init(const bool enabled, const int corner, const int font_size, const color bg)
     {
      m_chart   = ChartID();
      m_enabled = enabled;
      m_corner  = corner;
      m_font    = (font_size < 7 ? 7 : (font_size > 24 ? 24 : font_size));
      m_lh      = (int)(m_font * 1.8);
      m_cw      = m_font * 0.78;
      m_bgclr   = bg;
      m_rn      = 0;
      m_n       = 0;
      m_created = 0;
      m_last_w  = 0;
      m_last_h  = 0;
      m_hidden  = 0;
      ObjectsDeleteAll(m_chart, m_prefix);        // panel sub-prefix only
     }

   void              Begin(void)
     {
      m_rn = 0;
     }

   //--- a line with a priority: 0 = essential (always wanted), higher = dropped first when the chart is too small
   void              Line(const string text, const color clr, const int prio)
     {
      if(!m_enabled)
         return;
      ArrayResize(m_rt, m_rn + 1, 32);
      ArrayResize(m_rc, m_rn + 1, 32);
      ArrayResize(m_rp, m_rn + 1, 32);
      m_rt[m_rn] = text;
      m_rc[m_rn] = clr;
      m_rp[m_rn] = prio;
      m_rn++;
     }

   //--- layout (wrap to the chart width, drop the lowest priority lines that do not fit the chart height) and draw
   void              End(void)
     {
      if(!m_enabled)
         return;
      int cw = (int)ChartGetInteger(m_chart, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(m_chart, CHART_HEIGHT_IN_PIXELS);
      m_last_w = cw;
      m_last_h = ch;
      int mc = H3LPanelCols(cw, m_cw, m_pad, m_margin, 55);
      int avail = H3LPanelRows(ch, m_lh, m_pad, m_margin);
      string piece[];
      string flat[];
      int owner[];
      int rows[];
      ArrayResize(rows, m_rn);
      int nf = 0;
      for(int a = 0; a < m_rn; a++)
        {
         int np = H3LWrap(m_rt[a], mc, piece);
         rows[a] = np;
         for(int b = 0; b < np; b++)
           {
            ArrayResize(flat, nf + 1, 64);
            ArrayResize(owner, nf + 1, 64);
            flat[nf] = piece[b];
            owner[nf] = a;
            nf++;
           }
        }
      bool keep[];
      int hidden = 0;
      H3LPanelBudget(avail, m_rp, rows, m_rn, keep, hidden);
      m_hidden = hidden;
      m_n = 0;
      for(int c = 0; c < nf; c++)
         if(keep[owner[c]])
            Push(flat[c], m_rc[owner[c]]);
      if(hidden > 0)
         Push(StringSubstr(StringFormat("... %d more line(s) hidden: chart too small (Experts log has all)", hidden), 0, mc), clrGold);
      int maxlen = 1;
      for(int i = 0; i < m_n; i++)
         if(StringLen(m_lines[i]) > maxlen)
            maxlen = StringLen(m_lines[i]);
      int w = (int)(maxlen * m_cw) + 2 * m_pad;
      int h = m_n * m_lh + 2 * m_pad;
      int x = m_margin;
      int y = m_margin;
      if(m_corner == H3V_PNL_TOP_RIGHT || m_corner == H3V_PNL_BOTTOM_RIGHT)
         x = cw - w - m_margin;
      if(m_corner == H3V_PNL_BOTTOM_LEFT || m_corner == H3V_PNL_BOTTOM_RIGHT)
         y = ch - h - m_margin;
      if(x < 0)
         x = 0;
      if(y < 0)
         y = 0;
      //--- the background must sit BELOW the labels: if it had to be created again, recreate the labels after it
      if(ObjectFind(m_chart, m_bg) < 0)
        {
         for(int k = 0; k < m_created; k++)
            ObjectDelete(m_chart, LabelName(k));
         m_created = 0;
         if(ObjectCreate(m_chart, m_bg, OBJ_RECTANGLE_LABEL, 0, 0, 0))
           {
            ObjectSetInteger(m_chart, m_bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(m_chart, m_bg, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(m_chart, m_bg, OBJPROP_HIDDEN, true);
            ObjectSetInteger(m_chart, m_bg, OBJPROP_BACK, false);
            ObjectSetInteger(m_chart, m_bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
           }
         else
            ResetLastError();
        }
      ObjectSetInteger(m_chart, m_bg, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart, m_bg, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart, m_bg, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chart, m_bg, OBJPROP_YSIZE, h);
      ObjectSetInteger(m_chart, m_bg, OBJPROP_BGCOLOR, m_bgclr);
      ObjectSetInteger(m_chart, m_bg, OBJPROP_COLOR, clrDimGray);
      for(int j = 0; j < m_n; j++)
        {
         string name = LabelName(j);
         if(ObjectFind(m_chart, name) < 0)
           {
            if(!ObjectCreate(m_chart, name, OBJ_LABEL, 0, 0, 0))
              {
               ResetLastError();
               continue;
              }
            ObjectSetInteger(m_chart, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(m_chart, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
            ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN, true);
            ObjectSetInteger(m_chart, name, OBJPROP_BACK, false);
            ObjectSetString(m_chart, name, OBJPROP_FONT, "Consolas");
            if(j + 1 > m_created)
               m_created = j + 1;
           }
         ObjectSetInteger(m_chart, name, OBJPROP_FONTSIZE, m_font);
         ObjectSetInteger(m_chart, name, OBJPROP_XDISTANCE, x + m_pad);
         ObjectSetInteger(m_chart, name, OBJPROP_YDISTANCE, y + m_pad + j * m_lh);
         ObjectSetString(m_chart, name, OBJPROP_TEXT, m_lines[j]);
         ObjectSetInteger(m_chart, name, OBJPROP_COLOR, m_clrs[j]);
        }
      for(int r = m_n; r < m_created; r++)
        {
         string nm2 = LabelName(r);
         if(ObjectFind(m_chart, nm2) >= 0)
            ObjectDelete(m_chart, nm2);
        }
      if(m_created > m_n)
         m_created = m_n;
      ChartRedraw(m_chart);
     }

   //--- chart resized (CHARTEVENT_CHART_CHANGE): lay the SAME lines out again for the new size. The chart objects of the
   //--- map are not touched and the logic is not re-run; nothing happens while the size is unchanged.
   void              Relayout(void)
     {
      if(!m_enabled || m_rn < 1)
         return;
      int cw = (int)ChartGetInteger(m_chart, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(m_chart, CHART_HEIGHT_IN_PIXELS);
      if(cw <= 0 || ch <= 0)
         return;
      if(cw == m_last_w && ch == m_last_h)
         return;
      End();
     }

   void              Destroy(void)
     {
      ObjectsDeleteAll(m_chart, m_prefix);        // panel sub-prefix only
      m_n = 0;
      m_rn = 0;
      m_created = 0;
      ChartRedraw(m_chart);
     }
  };

#endif // VELO_H4_BIAS_DRAWER_MQH
