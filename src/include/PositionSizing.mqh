// T006 pure position sizing. NOT a trading rule and NOT wired to any EA or order.
// Mirror of tests/t006_sizing_reference.py. No order function, no trading API, no account/symbol/broker read, no live
// price, no clock: every number is an ARGUMENT supplied by the caller. Not wired to an EA.
//
// SUPPLIED BY THE CALLER (this module chooses none of it):
//  geo          the STgResult of TradeGeometry (TG_Compute). Only status, computed, e_ticks and s_ticks are read. No
//               price is normalized or validated again: stop_ticks = |e_ticks - s_ticks| of the verified geometry.
//  risk_budget  monetary risk in ACCOUNT currency. The module does NOT choose the base of the 1% (balance, equity, ...)
//               and does NOT apply the 1% anywhere (open item).
//  tick_value   value of ONE tick for ONE LOT in ACCOUNT currency, exactly as the caller passes it (e.g. the broker's
//               SYMBOL_TRADE_TICK_VALUE when already in account currency). No currency conversion here.
//  volume_min, volume_step, volume_max   broker volume parameters in lots. volume_step = 0.01 is NEVER assumed.
//  cap_lots     per-trade cap in lots, an INPUT: the client number 10 is passed by the caller, no default is hidden here.
//
// LINEAR MODEL (a model with the supplied parameters, NOT a guarantee of the broker's real loss):
//  loss_per_lot_at_SL = stop_ticks * tick_value ; volume_raw = risk_budget / loss_per_lot_at_SL.
//  Costs (spread, commission, slippage), contract changes and profit-currency conversion are outside the model:
//  COSTS_NOT_MODELLED. The realized risk reported is a model figure, not a promise.
//
// ROUNDING (the only adjustment this module ever makes): the volume is rounded DOWN to a whole number of steps n.
//  risk_per_step = volume_step * loss_per_lot_at_SL (computed once, double)
//  n = floor(risk_budget / risk_per_step + EPS_STEPS)                      EPS_STEPS = 1e-6 step (float noise on an exact fit; ONLY here)
//  while n > 0 and n * risk_per_step > risk_budget: n -= 1                the SAME expression as the reported risk
//  volume_out = n * volume_step ; risk_realized = n * risk_per_step
//  So risk_realized <= risk_budget ALWAYS holds for the double expression, identically in Python and MQL5. In exact real
//  arithmetic of the (binary inexact) inputs it can exceed the budget by float rounding only (relative ~1e-15). A fit that
//  is exact in decimal but lands 1 ulp above the budget in binary loses ONE step (conservative; never rounded up). The
//  integer steps_rounded is authoritative; volume_out may carry binary noise (3*0.1), so the caller normalizes it to
//  the volume digits at the order stage, not here.
//  The volume is NEVER raised to volume_min and NEVER reduced or clamped to volume_max or cap_lots. There is no
//  reduced_to_limit field: a limit conflict is always a SKIP status and then volume_out = 0.
//
// LIMITS (integer steps, after the rounding, first conflict wins):
//  n < min_steps -> SKIP_BELOW_MIN_VOLUME (includes n = 0) ; n > max_steps -> SKIP_ABOVE_MAX_VOLUME (broker maximum,
//  checked BEFORE the cap) ; n > cap_steps -> SKIP_ABOVE_CAP, x = cap_lots/volume_step,
//  cap_steps = floor(x + PS_CAP_ULPS*DBL_EPSILON*max(1,x)): the cap need NOT be on the step grid, it is only a comparison
//  bound and never a volume. CAP RULE: the 1e-6 step PS_EPS_STEPS is NOT used for the cap; it is ~10^9 times larger than
//  binary noise and would round a cap genuinely below a step boundary UP (0.29999995/0.1 = 2.9999995 -> 3). The cap
//  tolerance is a few ulps of x: it absorbs division noise (0.3/0.1 = 2.9999999999999996 -> 3) but not a real shortfall.
//  The comparison is in integer steps; volume_out = n*step may carry binary noise above a cap exactly on the grid
//  (0.30000000000000004 for cap 0.3), accepted and documented. Never reduced to fit the cap (SKIP). Max and cap are NOT merged into one
//  smaller limit. A cap below volume_min is valid input: every sizing is then a SKIP.
//
// STATUSES, first failure wins, in this order (INVALID_INPUT reasons start with a fixed tag):
//  1 GEOMETRY_NOT_OK (geo.status != TG_OK or not geo.computed; nothing is recomputed)
//  2 INVALID_INPUT: INVALID_STOP_TICKS (e/s ticks beyond +/-1e13 or |e-s| == 0), INVALID_RISK_BUDGET, INVALID_TICK_VALUE,
//    INVALID_VOLUME_MIN, INVALID_VOLUME_STEP, INVALID_VOLUME_MAX, INVALID_CAP (each non-finite or <= 0), VOLUME_MAX_BELOW_MIN
//    (equal allowed), STEP_RANGE (volume_max/step or cap/step non-finite or > 1e9), VOLUME_NOT_ON_GRID (volume_min or
//    volume_max is not an integer >= 1 multiple of the step: x=value/step, k=floor(x+0.5), k>=1 and
//    |x-k|<=PS_GRID_ULPS*DBL_EPSILON*max(1,x); min first. NOT the 1e-6 step: it is ~10^9 times larger than binary noise and would
//    accept max 0.29999995/step 0.1 as 3 steps (0.3 ABOVE the maximum) or min 0.30000005 (0.3 BELOW the minimum)), NUMERIC_OVERFLOW (loss per lot,
//    risk per step or volume_raw not finite or <= 0, or risk_budget/risk_per_step > 1e15)
//  3 SKIP_BELOW_MIN_VOLUME -> SKIP_ABOVE_MAX_VOLUME -> SKIP_ABOVE_CAP
//  4 OK
// Nothing is coerced: an input off the grid is rejected, never rounded.
// OUTPUT ON FAILURE: GEOMETRY_NOT_OK and INVALID_INPUT report no number (computed false, every numeric field 0). A SKIP
// keeps the DIAGNOSTIC fields (computed true, stop_ticks, loss_per_lot, risk_per_step, volume_raw, steps_rounded, min/max/cap
// steps) but volume_out, risk_realized and the rounding fields are 0. Act only on a status OK result.
// NOT handled here (open): the base of the 1%, costs, the combined 2% risk and pending reservation, the 2-position and
// 2-vs-3-trades limits, the 80/20 partial volume rounding, the 50 stop-distance limit, order placement, EA wiring.
#ifndef VELO_POSITION_SIZING_MQH
#define VELO_POSITION_SIZING_MQH

#include "TradeGeometry.mqh"

#define PS_EPS_STEPS 1e-6
#define PS_GRID_ULPS 4.0
#define PS_CAP_ULPS 4.0
#define PS_MAX_STEPS 1e9
#define PS_MAX_RAW_STEPS 1e15
#define PS_MAX_STOP_TICKS 1e13

enum ENUM_PS_STATUS
  {
   PS_OK=0,
   PS_INVALID_INPUT,
   PS_GEOMETRY_NOT_OK,
   PS_SKIP_BELOW_MIN_VOLUME,
   PS_SKIP_ABOVE_MAX_VOLUME,
   PS_SKIP_ABOVE_CAP
  };

struct SPsResult
  {
   ENUM_PS_STATUS status;
   string reason;
   bool computed;
   long stop_ticks;
   double loss_per_lot;
   double risk_per_step;
   double volume_raw;
   long steps_rounded;
   long min_steps;
   long max_steps;
   long cap_steps;
   double volume_out;
   double risk_realized;
   bool step_rounded;
   double volume_rounding_loss;
   double risk_unused;
  };

string PS_StatusName(const ENUM_PS_STATUS s)
  {
   switch(s)
     {
      case PS_OK: return("OK");
      case PS_INVALID_INPUT: return("INVALID_INPUT");
      case PS_GEOMETRY_NOT_OK: return("GEOMETRY_NOT_OK");
      case PS_SKIP_BELOW_MIN_VOLUME: return("SKIP_BELOW_MIN_VOLUME");
      case PS_SKIP_ABOVE_MAX_VOLUME: return("SKIP_ABOVE_MAX_VOLUME");
      case PS_SKIP_ABOVE_CAP: return("SKIP_ABOVE_CAP");
     }
   return("UNKNOWN");
  }

string PS_CostsLabel() {return("COSTS_NOT_MODELLED");}
string PS_ModelLabel() {return("LINEAR_MODEL (loss per lot at SL = stop ticks * tick value; not the broker real loss)");}
string PS_NoReductionLabel() {return("NO_REDUCTION_TO_LIMIT (a limit conflict is a SKIP; volume is never raised to min or clamped to max/cap)");}

void PS_Reset(SPsResult &r)
  {
   r.status=PS_OK;
   r.reason="";
   r.computed=false;
   r.stop_ticks=0;
   r.loss_per_lot=0.0;
   r.risk_per_step=0.0;
   r.volume_raw=0.0;
   r.steps_rounded=0;
   r.min_steps=0;
   r.max_steps=0;
   r.cap_steps=0;
   r.volume_out=0.0;
   r.risk_realized=0.0;
   r.step_rounded=false;
   r.volume_rounding_loss=0.0;
   r.risk_unused=0.0;
  }

bool PS_Fail(SPsResult &r,const ENUM_PS_STATUS status,const string reason)
  {
   r.status=status;
   r.reason=reason;
   return(false);
  }

// Integer number of steps when value is a >= 1 multiple of step within a few ulps (PS_GRID_ULPS), else -1.
long PS_GridSteps(const double value,const double step)
  {
   double x=value/step;
   double k=MathFloor(x+0.5);
   if(k<1.0 || MathAbs(x-k)>PS_GRID_ULPS*DBL_EPSILON*MathMax(1.0,x)) return(-1);
   return((long)k);
  }

// Returns true when status == PS_OK. All inputs are by value or const; nothing outside `out` is touched.
bool PS_Compute(const STgResult &geo,const double risk_budget,const double tick_value,
                const double volume_min,const double volume_step,const double volume_max,const double cap_lots,
                SPsResult &out)
  {
   PS_Reset(out);
   // 1 geometry: taken as given, never recomputed
   if(geo.status!=TG_OK || !geo.computed)
      return(PS_Fail(out,PS_GEOMETRY_NOT_OK,StringFormat("GEOMETRY_NOT_OK: geometry status %s computed %d",TG_StatusName(geo.status),(int)geo.computed)));
   // 2 validation, fixed order, before any computation
   long e_t=geo.e_ticks;
   long s_t=geo.s_ticks;
   if(MathAbs((double)e_t)>PS_MAX_STOP_TICKS || MathAbs((double)s_t)>PS_MAX_STOP_TICKS)
      return(PS_Fail(out,PS_INVALID_INPUT,"INVALID_STOP_TICKS: geometry ticks are not integers within +/-1e13"));
   long stop_ticks=(e_t>s_t ? e_t-s_t : s_t-e_t);
   if(stop_ticks<=0)
      return(PS_Fail(out,PS_INVALID_INPUT,StringFormat("INVALID_STOP_TICKS: stop distance is %I64d ticks, must be > 0",stop_ticks)));
   if(!TG_Finite(risk_budget) || risk_budget<=0.0)
      return(PS_Fail(out,PS_INVALID_INPUT,StringFormat("INVALID_RISK_BUDGET: %.10g must be finite and > 0",risk_budget)));
   if(!TG_Finite(tick_value) || tick_value<=0.0)
      return(PS_Fail(out,PS_INVALID_INPUT,StringFormat("INVALID_TICK_VALUE: %.10g must be finite and > 0",tick_value)));
   if(!TG_Finite(volume_min) || volume_min<=0.0)
      return(PS_Fail(out,PS_INVALID_INPUT,StringFormat("INVALID_VOLUME_MIN: %.10g must be finite and > 0",volume_min)));
   if(!TG_Finite(volume_step) || volume_step<=0.0)
      return(PS_Fail(out,PS_INVALID_INPUT,StringFormat("INVALID_VOLUME_STEP: %.10g must be finite and > 0",volume_step)));
   if(!TG_Finite(volume_max) || volume_max<=0.0)
      return(PS_Fail(out,PS_INVALID_INPUT,StringFormat("INVALID_VOLUME_MAX: %.10g must be finite and > 0",volume_max)));
   if(!TG_Finite(cap_lots) || cap_lots<=0.0)
      return(PS_Fail(out,PS_INVALID_INPUT,StringFormat("INVALID_CAP: %.10g must be finite and > 0",cap_lots)));
   if(volume_max<volume_min)
      return(PS_Fail(out,PS_INVALID_INPUT,StringFormat("VOLUME_MAX_BELOW_MIN: volume_max %.10g < volume_min %.10g",volume_max,volume_min)));
   double max_x=volume_max/volume_step;
   double cap_x=cap_lots/volume_step;
   if(!TG_Finite(max_x) || !TG_Finite(cap_x) || max_x>PS_MAX_STEPS || cap_x>PS_MAX_STEPS)
      return(PS_Fail(out,PS_INVALID_INPUT,"STEP_RANGE: volume_max/volume_step or cap_lots/volume_step is not finite or > 1e9 steps"));
   long min_steps=PS_GridSteps(volume_min,volume_step);
   if(min_steps<0)
      return(PS_Fail(out,PS_INVALID_INPUT,StringFormat("VOLUME_NOT_ON_GRID: volume_min %.10g is not a multiple of step %.10g",volume_min,volume_step)));
   long max_steps=PS_GridSteps(volume_max,volume_step);
   if(max_steps<0)
      return(PS_Fail(out,PS_INVALID_INPUT,StringFormat("VOLUME_NOT_ON_GRID: volume_max %.10g is not a multiple of step %.10g",volume_max,volume_step)));
   long cap_steps=(long)MathFloor(cap_x+PS_CAP_ULPS*DBL_EPSILON*MathMax(1.0,cap_x));

   // linear model
   double loss_per_lot=(double)stop_ticks*tick_value;
   double risk_per_step=volume_step*loss_per_lot;
   if(!TG_Finite(loss_per_lot) || loss_per_lot<=0.0 || !TG_Finite(risk_per_step) || risk_per_step<=0.0)
      return(PS_Fail(out,PS_INVALID_INPUT,"NUMERIC_OVERFLOW: loss per lot or risk per step is not finite and > 0"));
   double volume_raw=risk_budget/loss_per_lot;
   double raw_steps=risk_budget/risk_per_step;
   if(!TG_Finite(volume_raw) || !TG_Finite(raw_steps) || raw_steps>PS_MAX_RAW_STEPS)
      return(PS_Fail(out,PS_INVALID_INPUT,"NUMERIC_OVERFLOW: raw volume is not finite or > 1e15 steps"));

   // ROUND DOWN (the only adjustment)
   long n=(long)MathFloor(raw_steps+PS_EPS_STEPS);
   while(n>0 && (double)n*risk_per_step>risk_budget)
      n--;

   out.computed=true;
   out.stop_ticks=stop_ticks;
   out.loss_per_lot=loss_per_lot;
   out.risk_per_step=risk_per_step;
   out.volume_raw=volume_raw;
   out.steps_rounded=n;
   out.min_steps=min_steps;
   out.max_steps=max_steps;
   out.cap_steps=cap_steps;
   // LIMITS: a conflict is a skip, never a reduction
   if(n<min_steps)
      return(PS_Fail(out,PS_SKIP_BELOW_MIN_VOLUME,StringFormat("SKIP_BELOW_MIN_VOLUME: %I64d steps rounded down from raw volume %.10g, minimum is %I64d steps",n,volume_raw,min_steps)));
   if(n>max_steps)
      return(PS_Fail(out,PS_SKIP_ABOVE_MAX_VOLUME,StringFormat("SKIP_ABOVE_MAX_VOLUME: %I64d steps rounded down from raw volume %.10g, broker maximum is %I64d steps",n,volume_raw,max_steps)));
   if(n>cap_steps)
      return(PS_Fail(out,PS_SKIP_ABOVE_CAP,StringFormat("SKIP_ABOVE_CAP: %I64d steps rounded down from raw volume %.10g, cap is %I64d steps",n,volume_raw,cap_steps)));
   out.volume_out=(double)n*volume_step;
   out.risk_realized=(double)n*risk_per_step;
   out.step_rounded=(MathAbs(raw_steps-(double)n)>PS_EPS_STEPS);
   out.volume_rounding_loss=(out.step_rounded ? MathMax(0.0,volume_raw-out.volume_out) : 0.0);
   out.risk_unused=MathMax(0.0,risk_budget-out.risk_realized);
   return(true);
  }

#endif
