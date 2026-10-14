// T005 pure trade geometry. NOT a trading rule and NOT wired to any EA or order.
// Mirror of tests/t005_geometry_reference.py. No order function, no volume/sizing, no live price, tick or clock.
//
// The caller supplies direction, entry E, stop S and an optional target T (explicit placeholders from the
// caller's point of view). This module does NOT select entry, SL, FVG or target and does not read T004 facts.
//
// CONTRACT (conventions marked PROPOSAL are for review, they are not client answers):
//  1. Validate inputs.
//  2. E and S go to integer ticks FIRST: nearest tick, an exact half tick goes UP (PROPOSAL; applies to E and S
//     for BUY and SELL alike, so BUY/SELL are not mirror images at an exact half tick; tolerance 1e-6 tick).
//  3. Everything else is computed from those integer ticks: R_geom = |E_out - S_out|,
//     level_2R = E_out +/- 2*R_geom. The reported E_out and S_out are exactly the values used, so 2R is never
//     computed from one SL while another SL is reported.
//  4. Target T rounds AWAY from the entry (BUY up, SELL down; PROPOSAL, rounding can never undercut 2R).
//  5. TP = the farther of the normalized target and level_2R (client N6): a nearer or missing target gives
//     level_2R, a farther target is kept. Target cases NONE / NEARER / EQUAL / FARTHER are judged on ticks.
//  6. partial_price = level_2R (client answer: 80% of INITIAL volume at 2R). No volume is computed.
//     tp_equals_2r reports the coincidence of TP and the partial point; the remainder's behaviour is unspecified.
//  7. Costs (spread, commission, slippage) are NOT modelled: COSTS_NOT_MODELLED. R_geom is a price distance and
//     is NOT the client's final R definition (open items C3/C4).
// Statuses (first failing check wins, in this order): INVALID_DIRECTION, INVALID_INPUT, ZERO_RISK
//  (E_out == S_out), SL_WRONG_SIDE (strictly wrong side after normalization), TARGET_WRONG_SIDE (normalized
//  target not strictly beyond E_out), BELOW_STOPS_LEVEL (SL or TP distance < stops_level*point; TP distance
//  cannot be the first failure because TP >= 2R >= R), PENDING_TOO_CLOSE (only when bid/ask are supplied:
//  BUY limit must be below Ask, SELL limit above Bid, by > 0 and >= stops_level*point; else NOT_CHECKED).
// NOT enforced (open): the "50 stop-distance" limit (unit unconfirmed), freeze level, spread limit, volume.
// Only trust numeric fields when status == TG_OK; geometry fields are filled once `computed` is true so that a
// failed check can be explained.
#ifndef VELO_TRADE_GEOMETRY_MQH
#define VELO_TRADE_GEOMETRY_MQH

#define TG_BUY 1
#define TG_SELL -1
#define TG_EPS_TICKS 1e-6
#define TG_EPS_POINTS 1e-6
#define TG_MAX_TICKS 1e12

enum ENUM_TG_STATUS
  {
   TG_OK=0,
   TG_INVALID_DIRECTION,
   TG_INVALID_INPUT,
   TG_SL_WRONG_SIDE,
   TG_ZERO_RISK,
   TG_TARGET_WRONG_SIDE,
   TG_BELOW_STOPS_LEVEL,
   TG_PENDING_TOO_CLOSE
  };

enum ENUM_TG_TARGET
  {
   TG_TARGET_NONE=0,
   TG_TARGET_NEARER,
   TG_TARGET_EQUAL,
   TG_TARGET_FARTHER
  };

enum ENUM_TG_PENDING
  {
   TG_PEND_NOT_CHECKED=0,
   TG_PEND_PASSED,
   TG_PEND_TOO_CLOSE
  };

struct STgResult
  {
   ENUM_TG_STATUS status;
   string reason;
   int direction;
   double e_raw;
   double s_raw;
   double t_raw;
   bool has_target;
   bool computed;
   long e_ticks;
   long s_ticks;
   long t_ticks;
   long r_ticks;
   long two_r_ticks;
   long tp_ticks;
   double e_out;
   double s_out;
   double r_geom;
   double level_2r;
   double tp;
   ENUM_TG_TARGET target_case;
   bool tp_equals_2r;
   double partial_price;
   ENUM_TG_PENDING pending_check;
   double min_distance;
  };

string TG_StatusName(const ENUM_TG_STATUS s)
  {
   switch(s)
     {
      case TG_OK: return("OK");
      case TG_INVALID_DIRECTION: return("INVALID_DIRECTION");
      case TG_INVALID_INPUT: return("INVALID_INPUT");
      case TG_SL_WRONG_SIDE: return("SL_WRONG_SIDE");
      case TG_ZERO_RISK: return("ZERO_RISK");
      case TG_TARGET_WRONG_SIDE: return("TARGET_WRONG_SIDE");
      case TG_BELOW_STOPS_LEVEL: return("BELOW_STOPS_LEVEL");
      case TG_PENDING_TOO_CLOSE: return("PENDING_TOO_CLOSE");
     }
   return("UNKNOWN");
  }

string TG_TargetCaseName(const ENUM_TG_TARGET c)
  {
   switch(c)
     {
      case TG_TARGET_NONE: return("NONE");
      case TG_TARGET_NEARER: return("NEARER_THAN_2R");
      case TG_TARGET_EQUAL: return("EQUAL_TO_2R");
      case TG_TARGET_FARTHER: return("FARTHER_THAN_2R");
     }
   return("UNKNOWN");
  }

string TG_PendingName(const ENUM_TG_PENDING p)
  {
   switch(p)
     {
      case TG_PEND_NOT_CHECKED: return("NOT_CHECKED");
      case TG_PEND_PASSED: return("PASSED");
      case TG_PEND_TOO_CLOSE: return("TOO_CLOSE");
     }
   return("UNKNOWN");
  }

string TG_PartialLabel() {return("PARTIAL_AT_2R (client answer: 80% of initial volume)");}
string TG_CostsLabel() {return("COSTS_NOT_MODELLED");}
string TG_RLabel() {return("R_GEOM (price distance of normalized E and S; not the client final R, open C3/C4)");}
string TG_UnenforcedNote() {return("50 stop-distance limit NOT enforced (unit unconfirmed); freeze level, spread and volume not handled");}

bool TG_Finite(const double x) {return(x==x && MathAbs(x)<=DBL_MAX);}

// Nearest tick as an integer; an exact half tick goes up.
long TG_NearestTicks(const double price,const double tick)
  {
   double x=price/tick;
   double m=MathFloor(x);
   double f=x-m;
   if(MathAbs(f-0.5)<=TG_EPS_TICKS) return((long)m+1);
   return(f<0.5 ? (long)m : (long)m+1);
  }

// Tick rounded away from the entry: BUY up, SELL down; a value already on the grid stays.
long TG_AwayTicks(const double price,const double tick,const int direction)
  {
   double x=price/tick;
   double r=MathFloor(x+0.5);
   if(MathAbs(x-r)<=TG_EPS_TICKS) return((long)r);
   return(direction==TG_BUY ? (long)MathCeil(x) : (long)MathFloor(x));
  }

double TG_TicksToPrice(const long n,const double tick,const int digits)
  {
   return(NormalizeDouble((double)n*tick,digits));
  }

void TG_Reset(STgResult &r,const int direction,const double e_raw,const double s_raw,const bool has_target,const double t_raw)
  {
   r.status=TG_OK;
   r.reason="";
   r.direction=direction;
   r.e_raw=e_raw;
   r.s_raw=s_raw;
   r.t_raw=t_raw;
   r.has_target=has_target;
   r.computed=false;
   r.e_ticks=0;
   r.s_ticks=0;
   r.t_ticks=0;
   r.r_ticks=0;
   r.two_r_ticks=0;
   r.tp_ticks=0;
   r.e_out=0.0;
   r.s_out=0.0;
   r.r_geom=0.0;
   r.level_2r=0.0;
   r.tp=0.0;
   r.target_case=TG_TARGET_NONE;
   r.tp_equals_2r=false;
   r.partial_price=0.0;
   r.pending_check=TG_PEND_NOT_CHECKED;
   r.min_distance=0.0;
  }

bool TG_Fail(STgResult &r,const ENUM_TG_STATUS status,const string reason)
  {
   r.status=status;
   r.reason=reason;
   return(false);
  }

// Returns true when status == TG_OK. All inputs are by value; nothing outside `out` is touched.
bool TG_Compute(const int direction,const double e_raw,const double s_raw,
                const bool has_target,const double t_raw,
                const double tick_size,const int digits,const double point,const int stops_level,
                const bool has_quote,const double bid,const double ask,STgResult &out)
  {
   TG_Reset(out,direction,e_raw,s_raw,has_target,t_raw);
   if(direction!=TG_BUY && direction!=TG_SELL)
      return(TG_Fail(out,TG_INVALID_DIRECTION,"direction must be BUY or SELL"));
   if(!TG_Finite(e_raw) || !TG_Finite(s_raw) || !TG_Finite(tick_size) || !TG_Finite(point) ||
      (has_target && !TG_Finite(t_raw)) || (has_quote && (!TG_Finite(bid) || !TG_Finite(ask))))
      return(TG_Fail(out,TG_INVALID_INPUT,"non-finite price/parameter"));
   if(tick_size<=0.0 || point<=0.0)
      return(TG_Fail(out,TG_INVALID_INPUT,"tick_size and point must be > 0"));
   if(digits<0 || digits>8)
      return(TG_Fail(out,TG_INVALID_INPUT,"digits must be 0..8"));
   if(stops_level<0)
      return(TG_Fail(out,TG_INVALID_INPUT,"stops_level must be >= 0"));
   if(e_raw<=0.0 || s_raw<=0.0 || (has_target && t_raw<=0.0) || (has_quote && (bid<=0.0 || ask<=0.0)))
      return(TG_Fail(out,TG_INVALID_INPUT,"prices must be > 0"));
   if(has_quote && bid>ask)
      return(TG_Fail(out,TG_INVALID_INPUT,"bid is above ask"));
   double big=MathMax(MathAbs(e_raw),MathAbs(s_raw));
   if(has_target) big=MathMax(big,MathAbs(t_raw));
   if(big/tick_size>TG_MAX_TICKS)
      return(TG_Fail(out,TG_INVALID_INPUT,"price/tick_size is out of range"));

   int sign=(direction==TG_BUY ? 1 : -1);
   long e_t=TG_NearestTicks(e_raw,tick_size);
   long s_t=TG_NearestTicks(s_raw,tick_size);
   out.e_ticks=e_t;
   out.s_ticks=s_t;
   out.e_out=TG_TicksToPrice(e_t,tick_size,digits);
   out.s_out=TG_TicksToPrice(s_t,tick_size,digits);
   if(e_t==s_t)
      return(TG_Fail(out,TG_ZERO_RISK,"E_out equals S_out after normalization"));
   if(sign*(s_t-e_t)>0)
      return(TG_Fail(out,TG_SL_WRONG_SIDE,"SL is on the wrong side of the entry after normalization"));

   long r_t=(e_t>s_t ? e_t-s_t : s_t-e_t);
   long two_r_t=e_t+sign*2*r_t;
   out.computed=true;
   out.r_ticks=r_t;
   out.two_r_ticks=two_r_t;
   out.r_geom=TG_TicksToPrice(r_t,tick_size,digits);
   out.level_2r=TG_TicksToPrice(two_r_t,tick_size,digits);
   out.partial_price=out.level_2r;
   out.min_distance=stops_level*point;

   long tp_t=two_r_t;
   if(has_target)
     {
      long tn=TG_AwayTicks(t_raw,tick_size,direction);
      out.t_ticks=tn;
      if(sign*(tn-e_t)<=0)
        {
         out.tp_ticks=two_r_t;
         out.tp=out.level_2r;
         out.tp_equals_2r=true;
         return(TG_Fail(out,TG_TARGET_WRONG_SIDE,"target is not beyond the entry in the trade direction"));
        }
      if(sign*(tn-two_r_t)>0)
        {
         out.target_case=TG_TARGET_FARTHER;
         tp_t=tn;
        }
      else
         out.target_case=(tn==two_r_t ? TG_TARGET_EQUAL : TG_TARGET_NEARER);
     }
   out.tp_ticks=tp_t;
   out.tp=TG_TicksToPrice(tp_t,tick_size,digits);
   out.tp_equals_2r=(tp_t==two_r_t);

   double sl_points=(double)r_t*tick_size/point;
   long tp_dist=(tp_t>e_t ? tp_t-e_t : e_t-tp_t);
   double tp_points=(double)tp_dist*tick_size/point;
   if(sl_points<stops_level-TG_EPS_POINTS)
      return(TG_Fail(out,TG_BELOW_STOPS_LEVEL,StringFormat("SL distance %.10g points < stops level %d",sl_points,stops_level)));
   if(tp_points<stops_level-TG_EPS_POINTS)   // unreachable while the SL check passes; kept as a guard
      return(TG_Fail(out,TG_BELOW_STOPS_LEVEL,StringFormat("TP distance %.10g points < stops level %d",tp_points,stops_level)));

   if(has_quote)
     {
      double gap=((direction==TG_BUY ? ask-out.e_out : out.e_out-bid))/point;
      if(gap<=TG_EPS_POINTS || gap<stops_level-TG_EPS_POINTS)
        {
         out.pending_check=TG_PEND_TOO_CLOSE;
         return(TG_Fail(out,TG_PENDING_TOO_CLOSE,StringFormat("limit %.10g points from the market side; needs > 0 and >= %d",gap,stops_level)));
        }
      out.pending_check=TG_PEND_PASSED;
     }
   return(true);
  }

#endif
