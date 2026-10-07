//+------------------------------------------------------------------+
//| H4Structure.mqh                                                  |
//|                                                                  |
//| T002 - PURE LOGIC for the H4 structure map. No chart objects, no |
//| trading API, no series access: every function works on an array  |
//| of CLOSED bars (index 0 = oldest) that the caller provides.      |
//|                                                                  |
//| ALL RULES HERE ARE PROPOSED (developer proposals awaiting the    |
//| client's visual validation, see tasks/T002-h4-map.md section C). |
//| They are not client answers and not trading rules.               |
//|                                                                  |
//| No look-ahead: H4Analyze() reads only bars[0..n-1]. Analysing a  |
//| prefix (smaller n) gives what was knowable at that time.         |
//|                                                                  |
//| Verification status: mirrored by tests/t002_reference_test.py    |
//| (a Python MODEL) and src/tests/T002_LogicTest.mq5. Neither the   |
//| MQL5 compilation nor the MQL5 test has been run.                 |
//+------------------------------------------------------------------+
#ifndef VELO_H4_STRUCTURE_MQH
#define VELO_H4_STRUCTURE_MQH

//--- direction
#define H4_DIR_UNKNOWN   0
#define H4_DIR_MIXED     1
#define H4_DIR_BULLISH   2
#define H4_DIR_BEARISH   3

//--- interval
#define H4_RNG_NONE      0   // direction is not trending, no interval attempted
#define H4_RNG_UNDEFINED 1   // trending but chronological pair missing or H <= L
#define H4_RNG_VALID     2

//--- ERL
#define H4_ERL_NA        0
#define H4_ERL_UNTOUCHED 1
#define H4_ERL_TAKEN     2

//--- FVG state
#define H4_FVG_FRESH     0
#define H4_FVG_TOUCHED   1
#define H4_FVG_INVALID   2

//--- FVG class
#define H4_CLS_NONE      0   // invalid, or no valid trending interval
#define H4_CLS_IRL       1   // right type, fully inside the interval (candidate)
#define H4_CLS_OUTSIDE   2   // right type, not fully inside (never a candidate)
#define H4_CLS_OPPOSITE  3   // type against the trend direction

struct SH4Swing
  {
   string            id;            // S<yyyymmddhhmm of pivot bar><H|L>
   bool              is_high;
   int               index;         // index in the analysed array
   datetime          pivot_time;    // open time of the pivot bar
   datetime          confirm_time;  // close time of bar index+RightBars
   double            price;
  };

struct SH4Fvg
  {
   string            id;            // F<yyyymmddhhmm of bar A><U|D>
   bool              bullish;
   int               index_a;
   datetime          time_a;
   datetime          confirm_time;  // close time of bar C
   double            lower;
   double            upper;
   int               state;         // H4_FVG_*
   int               cls;           // H4_CLS_*
  };

struct SH4Result
  {
   int               direction;
   int               range_state;
   double            range_high;
   double            range_low;
   datetime          range_known_time;
   double            erl_price;
   int               erl_state;
   datetime          erl_taken_time;
   int               ambiguous;
  };

//+------------------------------------------------------------------+
//| names                                                            |
//+------------------------------------------------------------------+
string H4DirName(const int v)
  {
   switch(v)
     {
      case H4_DIR_BULLISH: return("BULLISH");
      case H4_DIR_BEARISH: return("BEARISH");
      case H4_DIR_MIXED:   return("MIXED");
     }
   return("UNKNOWN");
  }

string H4RangeName(const int v)
  {
   switch(v)
     {
      case H4_RNG_VALID:     return("VALID");
      case H4_RNG_UNDEFINED: return("UNDEFINED");
     }
   return("NONE");
  }

string H4ErlName(const int v)
  {
   switch(v)
     {
      case H4_ERL_UNTOUCHED: return("UNTOUCHED");
      case H4_ERL_TAKEN:     return("TAKEN");
     }
   return("NA");
  }

string H4FvgStateName(const int v)
  {
   switch(v)
     {
      case H4_FVG_TOUCHED: return("TOUCHED");
      case H4_FVG_INVALID: return("INVALID");
     }
   return("FRESH");
  }

string H4ClassName(const int v)
  {
   switch(v)
     {
      case H4_CLS_IRL:      return("IRL");
      case H4_CLS_OUTSIDE:  return("OUTSIDE");
      case H4_CLS_OPPOSITE: return("OPPOSITE");
     }
   return("NONE");
  }

//--- yyyymmddhhmm from the raw time value (no time zone conversion)
string H4TimeStamp(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return(StringFormat("%04d%02d%02d%02d%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min));
  }

//+------------------------------------------------------------------+
//| 1. swings                                                        |
//+------------------------------------------------------------------+
int H4FindSwings(const MqlRates &bars[], const int n, const int left, const int right,
                 const int period_seconds, SH4Swing &swings[], int &ambiguous)
  {
   ArrayResize(swings, 0);
   ambiguous = 0;
   int count = 0;
   for(int i = left; i < n - right; i++)
     {
      bool is_h = true;
      bool is_l = true;
      for(int j = i - left; j <= i + right; j++)
        {
         if(j == i)
            continue;
         if(!(bars[i].high > bars[j].high))
            is_h = false;
         if(!(bars[i].low < bars[j].low))
            is_l = false;
        }
      if(is_h && is_l)
        {
         ambiguous++;     // used neither for direction nor for the interval
         continue;
        }
      if(!is_h && !is_l)
         continue;
      ArrayResize(swings, count + 1, 64);
      swings[count].is_high      = is_h;
      swings[count].index        = i;
      swings[count].pivot_time   = bars[i].time;
      swings[count].confirm_time = bars[i + right].time + period_seconds;
      swings[count].price        = (is_h ? bars[i].high : bars[i].low);
      swings[count].id           = StringFormat("S%s%s", H4TimeStamp(bars[i].time), is_h ? "H" : "L");
      count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| 2. direction (last two highs and last two lows)                  |
//+------------------------------------------------------------------+
int H4DeriveDirection(const SH4Swing &swings[], const int ns)
  {
   double h1 = 0, h2 = 0, l1 = 0, l2 = 0;
   int nh = 0, nl = 0;
   for(int i = ns - 1; i >= 0; i--)
     {
      if(swings[i].is_high)
        {
         if(nh == 0)
            h2 = swings[i].price;
         else
            if(nh == 1)
               h1 = swings[i].price;
         nh++;
        }
      else
        {
         if(nl == 0)
            l2 = swings[i].price;
         else
            if(nl == 1)
               l1 = swings[i].price;
         nl++;
        }
     }
   if(nh < 2 || nl < 2)
      return(H4_DIR_UNKNOWN);
   if(h2 < h1 && l2 < l1)
      return(H4_DIR_BEARISH);
   if(h2 > h1 && l2 > l1)
      return(H4_DIR_BULLISH);
   return(H4_DIR_MIXED);
  }

//+------------------------------------------------------------------+
//| 3. interval                                                      |
//+------------------------------------------------------------------+
void H4DeriveInterval(const SH4Swing &swings[], const int ns, const int direction, SH4Result &res)
  {
   res.range_state      = H4_RNG_NONE;
   res.range_high       = 0.0;
   res.range_low        = 0.0;
   res.range_known_time = 0;
   if(direction != H4_DIR_BEARISH && direction != H4_DIR_BULLISH)
      return;

   bool bear = (direction == H4_DIR_BEARISH);
   //--- anchor = latest swing low (bearish) / latest swing high (bullish)
   int anchor = -1;
   for(int i = ns - 1; i >= 0; i--)
      if(swings[i].is_high == !bear)
        {
         anchor = i;
         break;
        }
   res.range_state = H4_RNG_UNDEFINED;
   if(anchor < 0)
      return;
   //--- partner = latest swing of the other kind whose pivot precedes the anchor
   int partner = -1;
   for(int i = ns - 1; i >= 0; i--)
      if(swings[i].is_high == bear && swings[i].pivot_time < swings[anchor].pivot_time)
        {
         partner = i;
         break;
        }
   if(partner < 0)
      return;
   int hi = (bear ? partner : anchor);
   int lo = (bear ? anchor : partner);
   if(swings[hi].price <= swings[lo].price)
      return;
   res.range_state      = H4_RNG_VALID;
   res.range_high       = swings[hi].price;
   res.range_low        = swings[lo].price;
   res.range_known_time = (swings[hi].pivot_time > swings[lo].pivot_time
                           ? swings[hi].confirm_time : swings[lo].confirm_time);
  }

//+------------------------------------------------------------------+
//| 4. ERL taken - first closed bar opening at/after known_time whose |
//|    wick touches or crosses the ERL. Returns its open time or 0.  |
//+------------------------------------------------------------------+
datetime H4ErlTakenTime(const MqlRates &bars[], const int n, const double erl_price,
                        const bool is_sell, const datetime known_time)
  {
   for(int i = 0; i < n; i++)
     {
      if(bars[i].time < known_time)
         continue;
      if(is_sell && bars[i].low <= erl_price)
         return(bars[i].time);
      if(!is_sell && bars[i].high >= erl_price)
         return(bars[i].time);
     }
   return(0);
  }

//+------------------------------------------------------------------+
//| 5. FVG detection                                                 |
//+------------------------------------------------------------------+
int H4FindFvgs(const MqlRates &bars[], const int n, const int period_seconds, SH4Fvg &fvgs[])
  {
   ArrayResize(fvgs, 0);
   int count = 0;
   for(int a = 0; a + 2 < n; a++)
     {
      int c = a + 2;
      bool bull = (bars[c].low > bars[a].high);
      bool bear = (bars[c].high < bars[a].low);
      if(!bull && !bear)
         continue;
      ArrayResize(fvgs, count + 1, 64);
      fvgs[count].bullish      = bull;
      fvgs[count].index_a      = a;
      fvgs[count].time_a       = bars[a].time;
      fvgs[count].confirm_time = bars[c].time + period_seconds;
      fvgs[count].lower        = (bull ? bars[a].high : bars[c].high);
      fvgs[count].upper        = (bull ? bars[c].low  : bars[a].low);
      fvgs[count].state        = H4_FVG_FRESH;
      fvgs[count].cls          = H4_CLS_NONE;
      fvgs[count].id           = StringFormat("F%s%s", H4TimeStamp(bars[a].time), bull ? "U" : "D");
      count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| 6. FVG state over closed bars after C only                       |
//+------------------------------------------------------------------+
void H4EvalFvgStates(const MqlRates &bars[], const int n, SH4Fvg &fvgs[], const int nf)
  {
   for(int k = 0; k < nf; k++)
     {
      bool touched = false;
      bool invalid = false;
      for(int i = fvgs[k].index_a + 3; i < n; i++)
        {
         if(fvgs[k].bullish)
           {
            if(bars[i].close < fvgs[k].lower)
               invalid = true;
           }
         else
           {
            if(bars[i].close > fvgs[k].upper)
               invalid = true;
           }
         if(bars[i].low <= fvgs[k].upper && bars[i].high >= fvgs[k].lower)
            touched = true;
        }
      fvgs[k].state = (invalid ? H4_FVG_INVALID : (touched ? H4_FVG_TOUCHED : H4_FVG_FRESH));
     }
  }

//+------------------------------------------------------------------+
//| 7. classification (price containment only, inclusive edges)      |
//+------------------------------------------------------------------+
void H4ClassifyFvgs(SH4Fvg &fvgs[], const int nf, const SH4Result &res)
  {
   for(int k = 0; k < nf; k++)
     {
      fvgs[k].cls = H4_CLS_NONE;
      if(fvgs[k].state == H4_FVG_INVALID)
         continue;
      if(res.range_state != H4_RNG_VALID)
         continue;
      bool want_bull = (res.direction == H4_DIR_BULLISH);
      if(fvgs[k].bullish != want_bull)
         fvgs[k].cls = H4_CLS_OPPOSITE;
      else
         if(fvgs[k].lower >= res.range_low && fvgs[k].upper <= res.range_high)
            fvgs[k].cls = H4_CLS_IRL;
         else
            fvgs[k].cls = H4_CLS_OUTSIDE;
     }
  }

//+------------------------------------------------------------------+
//| Single analysis entry point. Reads bars[0..n-1] only.            |
//+------------------------------------------------------------------+
void H4Analyze(const MqlRates &bars[], const int n, const int left, const int right,
               const int period_seconds, SH4Swing &swings[], int &ns,
               SH4Fvg &fvgs[], int &nf, SH4Result &res)
  {
   ZeroMemory(res);
   res.direction   = H4_DIR_UNKNOWN;
   res.range_state = H4_RNG_NONE;
   res.erl_state   = H4_ERL_NA;
   ns = 0;
   nf = 0;
   if(n < 1 || left < 1 || right < 1)
     {
      ArrayResize(swings, 0);
      ArrayResize(fvgs, 0);
      return;
     }
   int amb = 0;
   ns = H4FindSwings(bars, n, left, right, period_seconds, swings, amb);
   res.ambiguous = amb;
   res.direction = H4DeriveDirection(swings, ns);
   H4DeriveInterval(swings, ns, res.direction, res);
   if(res.range_state == H4_RNG_VALID)
     {
      bool is_sell = (res.direction == H4_DIR_BEARISH);
      res.erl_price      = (is_sell ? res.range_low : res.range_high);
      res.erl_taken_time = H4ErlTakenTime(bars, n, res.erl_price, is_sell, res.range_known_time);
      res.erl_state      = (res.erl_taken_time != 0 ? H4_ERL_TAKEN : H4_ERL_UNTOUCHED);
     }
   nf = H4FindFvgs(bars, n, period_seconds, fvgs);
   H4EvalFvgStates(bars, n, fvgs, nf);
   H4ClassifyFvgs(fvgs, nf, res);
  }

//+------------------------------------------------------------------+
//| 8. visual selection against a price (cheap; may run every second)|
//|    Fills order[] with FVG indexes, nearest first. Returns count. |
//+------------------------------------------------------------------+
bool H4PriceInsideZone(const SH4Fvg &f, const double price)
  {
   return(f.lower <= price && price <= f.upper);
  }

//--- true if candidate a sorts before candidate b
bool H4SelBefore(const SH4Fvg &fa, const double da, const SH4Fvg &fb, const double db)
  {
   if(da != db)
      return(da < db);
   if(fa.confirm_time != fb.confirm_time)
      return(fa.confirm_time > fb.confirm_time);   // newer first
   return(StringCompare(fa.id, fb.id) < 0);        // then ID ascending
  }

int H4SelectIrl(const SH4Fvg &fvgs[], const int nf, const SH4Result &res,
                const double price, int &order[])
  {
   ArrayResize(order, 0);
   if(res.range_state != H4_RNG_VALID)
      return(0);
   if(res.direction != H4_DIR_BEARISH && res.direction != H4_DIR_BULLISH)
      return(0);
   bool sell = (res.direction == H4_DIR_BEARISH);
   double dist[];
   ArrayResize(dist, 0);
   int cnt = 0;
   for(int k = 0; k < nf; k++)
     {
      if(fvgs[k].cls != H4_CLS_IRL)
         continue;
      double d;
      if(H4PriceInsideZone(fvgs[k], price))
         d = 0.0;
      else
         if(sell && fvgs[k].lower > price)
            d = fvgs[k].lower - price;
         else
            if(!sell && fvgs[k].upper < price)
               d = price - fvgs[k].upper;
            else
               continue;
      //--- insertion sort keeps the order stable and deterministic
      ArrayResize(order, cnt + 1, 32);
      ArrayResize(dist, cnt + 1, 32);
      int pos = cnt;
      while(pos > 0 && H4SelBefore(fvgs[k], d, fvgs[order[pos - 1]], dist[pos - 1]))
        {
         order[pos] = order[pos - 1];
         dist[pos]  = dist[pos - 1];
         pos--;
        }
      order[pos] = k;
      dist[pos]  = d;
      cnt++;
     }
   return(cnt);
  }

//+------------------------------------------------------------------+
//| Canonical one-line summary. Same format as the Python model's    |
//| summary(); used by src/tests/T002_LogicTest.mq5.                 |
//+------------------------------------------------------------------+
string H4Summary(const SH4Swing &swings[], const int ns, const SH4Fvg &fvgs[], const int nf,
                 const SH4Result &res, const double price)
  {
   string sw = "";
   for(int i = 0; i < ns; i++)
      sw += (i > 0 ? "," : "") + StringFormat("%s@%I64d:%.2f", swings[i].id,
                                              (long)swings[i].confirm_time, swings[i].price);
   string fv = "";
   for(int k = 0; k < nf; k++)
      fv += (k > 0 ? "," : "") + StringFormat("%s:%s:%s:%.2f:%.2f", fvgs[k].id,
                                              H4FvgStateName(fvgs[k].state), H4ClassName(fvgs[k].cls),
                                              fvgs[k].lower, fvgs[k].upper);
   int order[];
   int cnt = H4SelectIrl(fvgs, nf, res, price, order);
   string sel = "";
   for(int j = 0; j < cnt; j++)
      sel += (j > 0 ? "," : "") + fvgs[order[j]].id;
   return(StringFormat("DIR=%s;RNG=%s;H=%.2f;L=%.2f;K=%I64d;ERL=%s;ERLP=%.2f;TT=%I64d;AMB=%d;SW=%s;FV=%s;SEL=%s",
                       H4DirName(res.direction), H4RangeName(res.range_state),
                       res.range_high, res.range_low, (long)res.range_known_time,
                       H4ErlName(res.erl_state), res.erl_price, (long)res.erl_taken_time,
                       res.ambiguous, sw, fv, sel));
  }

#endif // VELO_H4_STRUCTURE_MQH
