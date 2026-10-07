//+------------------------------------------------------------------+
//| H4MapDrawer.mqh                                                  |
//|                                                                  |
//| T002 - chart objects for the PROPOSED H4 structure map.          |
//| Draws only; reads no series and calls no trading function.       |
//|                                                                  |
//| Object naming: every object starts with the prefix (velo_t002_)  |
//| and its name is derived from the logic ID, so redrawing or       |
//| reloading never produces duplicates. Only objects with that      |
//| prefix are ever deleted. The panel labels use a sub-prefix       |
//| (velo_t002_pnl_) that ClearMap() leaves alone.                   |
//|                                                                  |
//| Not compiled or run in this environment (no MetaEditor).         |
//+------------------------------------------------------------------+
#ifndef VELO_H4_MAP_DRAWER_MQH
#define VELO_H4_MAP_DRAWER_MQH

#include "H4Structure.mqh"

class CH4MapDrawer
  {
private:
   string            m_prefix;
   string            m_panel_prefix;
   long              m_chart;
   datetime          m_x_end;        // right edge used by the last static draw
   int               m_period;
   color             m_clr_bear;
   color             m_clr_bull;
   color             m_clr_dim;
   color             m_clr_inside;
   color             m_clr_erl;
   color             m_clr_range;

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

   void              Note(const string name, const datetime t, const double p, const string text,
                          const color clr, const ENUM_ANCHOR_POINT anchor)
     {
      if(!Ensure(name, OBJ_TEXT))
         return;
      Put(name, 0, t, p);
      ObjectSetString(m_chart, name, OBJPROP_TEXT, text);
      ObjectSetString(m_chart, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(m_chart, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chart, name, OBJPROP_ANCHOR, anchor);
     }

   color             ZoneColor(const SH4Fvg &f, const bool inside) const
     {
      if(f.state == H4_FVG_INVALID || f.cls != H4_CLS_IRL)
         return(m_clr_dim);
      if(inside)
         return(m_clr_inside);
      return(f.bullish ? m_clr_bull : m_clr_bear);
     }

public:
                     CH4MapDrawer(void)
     {
      m_prefix       = "velo_t002_";
      m_panel_prefix = "velo_t002_pnl_";
      m_chart        = 0;
      m_x_end        = 0;
      m_period       = 14400;
      m_clr_bear     = clrTomato;
      m_clr_bull     = clrDodgerBlue;
      m_clr_dim      = clrDimGray;
      m_clr_inside   = clrGold;
      m_clr_erl      = clrOrange;
      m_clr_range    = clrSilver;
     }

   string            PanelPrefix(void) const { return(m_panel_prefix); }

   void              Init(const color bear, const color bull, const color erl)
     {
      m_chart     = ChartID();
      m_clr_bear  = bear;
      m_clr_bull  = bull;
      m_clr_erl   = erl;
      ClearAll();
     }

   //--- Delete EVERY object of this task (map and panel). Prefix only.
   void              ClearAll(void)
     {
      ObjectsDeleteAll(m_chart, m_prefix);
     }

   //--- Delete the map objects but keep the panel labels.
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

   //--- Remove every map object (swings, FVG rectangles and labels, range lines,
   //--- ERL line and label, IRL->ERL link; INSIDE highlighting lives on the FVG
   //--- rectangles and goes with them). Panel labels (velo_t002_pnl_) stay.
   void              Reset(void)
     {
      ClearMap();
      m_x_end = 0;
      ChartRedraw(m_chart);
     }

   //--- Redraw everything that depends on H4 logic only (new H4 bar / init).
   void              DrawStatic(const MqlRates &bars[], const int n, const int period_seconds,
                                const SH4Swing &swings[], const int ns,
                                const SH4Fvg &fvgs[], const int nf,
                                const SH4Result &res, const bool show_invalid)
     {
      ClearMap();
      if(n < 1)
         return;
      m_period = period_seconds;
      m_x_end  = bars[n - 1].time + (datetime)(period_seconds * 6);

      //--- swings, marked at the PIVOT time; the text carries the confirmation time
      for(int i = 0; i < ns; i++)
        {
         string txt = StringFormat("%s %s conf %s", swings[i].is_high ? "SH" : "SL",
                                   DoubleToString(swings[i].price, _Digits),
                                   TimeToString(swings[i].confirm_time, TIME_DATE|TIME_MINUTES));
         Note(m_prefix + "sw_" + swings[i].id, swings[i].pivot_time, swings[i].price, txt,
              swings[i].is_high ? m_clr_bear : m_clr_bull,
              swings[i].is_high ? ANCHOR_LOWER : ANCHOR_UPPER);
        }

      //--- structural interval and ERL
      if(res.range_state == H4_RNG_VALID)
        {
         Segment(m_prefix + "rng_hi", bars[0].time, res.range_high, m_x_end, res.range_high,
                 m_clr_range, 1, STYLE_DOT);
         Segment(m_prefix + "rng_lo", bars[0].time, res.range_low, m_x_end, res.range_low,
                 m_clr_range, 1, STYLE_DOT);
         Segment(m_prefix + "erl", res.range_known_time, res.erl_price, m_x_end, res.erl_price,
                 m_clr_erl, 2, res.erl_state == H4_ERL_TAKEN ? STYLE_DASH : STYLE_SOLID);
         Note(m_prefix + "erl_lbl", m_x_end, res.erl_price,
              StringFormat("ERL (proposed) %s  known %s", H4ErlName(res.erl_state),
                           TimeToString(res.range_known_time, TIME_DATE|TIME_MINUTES)),
              m_clr_erl, ANCHOR_RIGHT_LOWER);
        }

      //--- FVG zones; INVALID ones only on request
      for(int k = 0; k < nf; k++)
        {
         if(fvgs[k].state == H4_FVG_INVALID && !show_invalid)
            continue;
         string rn = m_prefix + "fvg_" + fvgs[k].id;
         if(!Ensure(rn, OBJ_RECTANGLE))
            continue;
         Put(rn, 0, fvgs[k].time_a, fvgs[k].upper);
         Put(rn, 1, m_x_end, fvgs[k].lower);
         ObjectSetInteger(m_chart, rn, OBJPROP_BACK, true);
        }
     }

   //--- Cheap refresh that depends on the current price (at most once per second).
   //--- order[0..cnt-1] are FVG indexes, nearest first (from H4SelectIrl).
   void              DrawDynamic(const SH4Fvg &fvgs[], const int nf, const SH4Result &res,
                                 const double price, const int &order[], const int cnt,
                                 const bool show_invalid)
     {
      bool active = H4SetupActive(res, cnt);
      for(int k = 0; k < nf; k++)
        {
         if(fvgs[k].state == H4_FVG_INVALID && !show_invalid)
            continue;
         string rn = m_prefix + "fvg_" + fvgs[k].id;
         if(ObjectFind(m_chart, rn) < 0)
            continue;
         int rank = 0;
         for(int j = 0; j < cnt; j++)
            if(order[j] == k)
              {
               rank = j + 1;
               break;
              }
         bool inside = (rank > 0 && H4PriceInsideZone(fvgs[k], price));
         //--- inactive candidates (ERL TAKEN) are listed but never highlighted
         bool irl    = (fvgs[k].cls == H4_CLS_IRL && fvgs[k].state != H4_FVG_INVALID);
         ObjectSetInteger(m_chart, rn, OBJPROP_COLOR, ZoneColor(fvgs[k], inside && active));
         ObjectSetInteger(m_chart, rn, OBJPROP_FILL, irl && rank > 0);
         ObjectSetInteger(m_chart, rn, OBJPROP_WIDTH, rank == 1 ? 2 : 1);
         ObjectSetInteger(m_chart, rn, OBJPROP_STYLE,
                          fvgs[k].state == H4_FVG_INVALID ? STYLE_DOT : STYLE_SOLID);

         string label = StringFormat("%s %s %s", fvgs[k].bullish ? "bull" : "bear",
                                     H4FvgStateName(fvgs[k].state), H4ClassName(fvgs[k].cls));
         if(rank > 0)
            label += StringFormat(" #%d%s", rank, inside ? " INSIDE" : "");
         if(rank > 0 && !active)
            label += StringFormat(" (inactive: ERL %s)", H4ErlName(res.erl_state));
         Note(m_prefix + "fvgt_" + fvgs[k].id, fvgs[k].time_a, fvgs[k].upper, label,
              ZoneColor(fvgs[k], inside && active), ANCHOR_LEFT_LOWER);
        }

      //--- IRL -> ERL link: only for an ACTIVE setup (H4SetupActive): trending
      //--- direction, valid interval, UNTOUCHED ERL, a selectable candidate.
      //--- With ERL TAKEN the link is deleted below and never drawn.
      string ln = m_prefix + "link";
      if(active)
        {
         int k0 = order[0];
         Segment(ln, fvgs[k0].confirm_time, (fvgs[k0].lower + fvgs[k0].upper) / 2.0,
                 m_x_end, res.erl_price, m_clr_erl, 1, STYLE_DASHDOT);
        }
      else
         if(ObjectFind(m_chart, ln) >= 0)
            ObjectDelete(m_chart, ln);
      ChartRedraw(m_chart);
     }
  };

#endif // VELO_H4_MAP_DRAWER_MQH
