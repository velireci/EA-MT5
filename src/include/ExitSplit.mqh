// T011 pure 80/20 exit-volume split. Mirrors tests/t011_split_reference.py (that file documents the contract in full).
// NOT a trading rule engine: no order, no trading API, no account/symbol read, no clock, no price. Every number is an argument.
// Not wired to any EA. No BE, costs, trailing or 2R detection.
//
// Client statement (STRATEGY_SPEC section 8): at 2R close 80% of the INITIAL volume, the remaining 20% runs to TP or SL.
// The volume grid validation is the T006 one and is REUSED: PS_GridSteps and PS_MAX_STEPS from PositionSizing.mqh, not copied.
// Split = integer arithmetic on steps: N=initial steps; exact only when N%5==0; close=4N/5, remaining=N/5 (sum is N).
// EXACT OR NOTHING: not exactly splittable, or remainder below volume_min -> ES_SPLIT_POLICY_UNSET. No rounding, no full close,
// no skipping the partial exit is invented here; that policy is an open client/owner decision.
// Statuses, first failure wins, fixed reason tags: see the Python reference header.
#ifndef VELO_EXIT_SPLIT_MQH
#define VELO_EXIT_SPLIT_MQH

#include "PositionSizing.mqh"

#define ES_CLOSE_NUM 4
#define ES_CLOSE_DEN 5

enum ENUM_ES_STATUS
  {
   ES_OK=0,
   ES_INVALID_INPUT,
   ES_SPLIT_POLICY_UNSET
  };

struct SEsResult
  {
   ENUM_ES_STATUS status;
   string reason;
   long initial_steps;
   long min_steps;
   long max_steps;
   long close_steps;
   long remaining_steps;
   double close_volume;
   double remaining_volume;
   double close_percent;
  };

string ES_StatusName(const ENUM_ES_STATUS s)
  {
   switch(s)
     {
      case ES_OK: return("OK");
      case ES_INVALID_INPUT: return("INVALID_INPUT");
      case ES_SPLIT_POLICY_UNSET: return("SPLIT_POLICY_UNSET");
     }
   return("UNKNOWN");
  }

void ES_Reset(SEsResult &r)
  {
   r.status=ES_OK;
   r.reason="";
   r.initial_steps=0;
   r.min_steps=0;
   r.max_steps=0;
   r.close_steps=0;
   r.remaining_steps=0;
   r.close_volume=0.0;
   r.remaining_volume=0.0;
   r.close_percent=0.0;
  }

bool ES_Fail(SEsResult &r,const ENUM_ES_STATUS status,const string reason)
  {
   r.status=status;
   r.reason=reason;
   return(false);
  }

// Returns true when status == ES_OK. Inputs are by value; nothing outside `out` is touched.
bool ES_Split(const double volume_initial,const double volume_min,const double volume_step,const double volume_max,SEsResult &out)
  {
   ES_Reset(out);
   if(!TG_Finite(volume_min) || volume_min<=0.0)
      return(ES_Fail(out,ES_INVALID_INPUT,StringFormat("INVALID_VOLUME_MIN: %.10g must be finite and > 0",volume_min)));
   if(!TG_Finite(volume_step) || volume_step<=0.0)
      return(ES_Fail(out,ES_INVALID_INPUT,StringFormat("INVALID_VOLUME_STEP: %.10g must be finite and > 0",volume_step)));
   if(!TG_Finite(volume_max) || volume_max<=0.0)
      return(ES_Fail(out,ES_INVALID_INPUT,StringFormat("INVALID_VOLUME_MAX: %.10g must be finite and > 0",volume_max)));
   if(!TG_Finite(volume_initial) || volume_initial<=0.0)
      return(ES_Fail(out,ES_INVALID_INPUT,StringFormat("INVALID_INITIAL: %.10g must be finite and > 0",volume_initial)));
   if(volume_max<volume_min)
      return(ES_Fail(out,ES_INVALID_INPUT,StringFormat("VOLUME_MAX_BELOW_MIN: volume_max %.10g < volume_min %.10g",volume_max,volume_min)));
   double max_x=volume_max/volume_step;
   double init_x=volume_initial/volume_step;
   if(!TG_Finite(max_x) || !TG_Finite(init_x) || max_x>PS_MAX_STEPS || init_x>PS_MAX_STEPS)
      return(ES_Fail(out,ES_INVALID_INPUT,"STEP_RANGE: volume_max/volume_step or volume_initial/volume_step is not finite or > 1e9 steps"));
   long min_steps=PS_GridSteps(volume_min,volume_step);
   long max_steps=PS_GridSteps(volume_max,volume_step);
   long n=PS_GridSteps(volume_initial,volume_step);
   if(min_steps<0)
      return(ES_Fail(out,ES_INVALID_INPUT,StringFormat("VOLUME_NOT_ON_GRID: volume_min %.10g is not a multiple of step %.10g",volume_min,volume_step)));
   if(max_steps<0)
      return(ES_Fail(out,ES_INVALID_INPUT,StringFormat("VOLUME_NOT_ON_GRID: volume_max %.10g is not a multiple of step %.10g",volume_max,volume_step)));
   if(n<0)
      return(ES_Fail(out,ES_INVALID_INPUT,StringFormat("VOLUME_NOT_ON_GRID: volume_initial %.10g is not a multiple of step %.10g",volume_initial,volume_step)));
   if(n<min_steps)
      return(ES_Fail(out,ES_INVALID_INPUT,StringFormat("INITIAL_BELOW_MIN: %I64d steps < minimum %I64d steps",n,min_steps)));
   if(n>max_steps)
      return(ES_Fail(out,ES_INVALID_INPUT,StringFormat("INITIAL_ABOVE_MAX: %I64d steps > maximum %I64d steps",n,max_steps)));
   out.initial_steps=n;
   out.min_steps=min_steps;
   out.max_steps=max_steps;
   if(n%ES_CLOSE_DEN!=0)
      return(ES_Fail(out,ES_SPLIT_POLICY_UNSET,StringFormat("NOT_EXACT_80_20: %I64d steps cannot be split exactly 80/20; no rounding policy is defined",n)));
   long rem=n/ES_CLOSE_DEN;
   long close=rem*ES_CLOSE_NUM;
   if(rem<min_steps)
      return(ES_Fail(out,ES_SPLIT_POLICY_UNSET,StringFormat("REMAINDER_BELOW_MIN: remainder %I64d steps < minimum %I64d steps; no full-close or skip policy is defined",rem,min_steps)));
   out.close_steps=close;
   out.remaining_steps=rem;
   out.close_volume=(double)close*volume_step;
   out.remaining_volume=(double)rem*volume_step;
   out.close_percent=(double)close/(double)n;
   return(true);
  }
#endif
