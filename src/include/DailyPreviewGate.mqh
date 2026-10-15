// T012 integration helpers for the OBSERVATION-ONLY preview (XauUsdTradePreview). Pure: no order, no cancellation, no account or history
// read, no clock (the caller passes the UTC instant), no persistence. Mirrors tests/t012_gate_reference.py.
//  * DG_Evaluate maps the preview's explicit inputs to DL_Check (DailyLimits.mqh, NOT copied): MANUAL (use_snapshot=false) evaluates nothing
//    and the preview behaves as before; DAILY_SNAPSHOT evaluates the supplied figures. Unknown figures (negative counters, unknown result,
//    unset balance) become invalid input -> BLOCK, never a limit.
//  * DG_FinalPreview combines the existing result with the daily gate: a daily BLOCK can only block, never allow, and MANUAL changes nothing.
// The cancel_pending_due flag it carries is DIAGNOSTIC: nothing is cancelled or closed anywhere.
#ifndef VELO_DAILY_PREVIEW_GATE_MQH
#define VELO_DAILY_PREVIEW_GATE_MQH

#include "DailyLimits.mqh"

// long counters of the preview inputs -> the int counters of DL_Check; anything out of range stays invalid (-1 / DL_MAX_COUNT+1)
int DG_Counter(const long value)
  {
   if(value<0 || value>DL_MAX_COUNT) return(-1);
   return((int)value);
  }

// Returns true when the daily gate was EVALUATED (use_snapshot). `out` is only meaningful then.
bool DG_Evaluate(const bool use_snapshot,const datetime utc,const int snapshot_day,const double balance_start,const bool result_known,
                 const double closed_result,const long trades_today,const long wins_today,const long consecutive_losses,const long max_trades,
                 SDlResult &out)
  {
   if(!use_snapshot)
     {
      out.entry_allowed=true;
      out.primary="";
      out.n_reasons=0;
      for(int i=0;i<DL_MAX_REASONS;i++)
         out.reasons[i]="";
      out.cancel_pending_due=false;
      out.daily_limit_reached=false;
      out.day_key=0;
      return(false);
     }
   SDlInput in;
   in.utc=utc;
   in.snapshot_day=snapshot_day;
   in.balance_start=balance_start;
   in.closed_result=(result_known ? closed_result : MathSqrt(-1.0));     // an unknown result is NaN -> INVALID_SNAPSHOT:closed_result
   in.trades_today=DG_Counter(trades_today);
   in.wins_today=DG_Counter(wins_today);
   in.consecutive_losses=DG_Counter(consecutive_losses);
   in.max_trades_set=(max_trades>=0);                                    // -1 = unset -> POLICY_UNSET, no default is chosen
   in.max_trades=(max_trades>DL_MAX_COUNT ? DL_MAX_COUNT+1 : (int)(max_trades<0 ? 0 : max_trades));
   DL_Check(in,out);
   return(true);
  }

// The final preview decision: the existing checks AND the daily gate when it was evaluated.
bool DG_FinalPreview(const bool loss_ok,const bool permit_allow,const bool daily_evaluated,const bool daily_allowed)
  {
   return(loss_ok && permit_allow && (!daily_evaluated || daily_allowed));
  }

string DG_Text(const bool evaluated,const SDlResult &d)
  {
   if(!evaluated) return("MANUAL (not evaluated)");
   return((d.entry_allowed ? "ENTRIES ALLOWED" : "ENTRIES BLOCKED")+" day "+IntegerToString(d.day_key)+" reasons "+(d.n_reasons>0 ? DL_Joined(d) : "none")+
          " | cancel_pending_due="+(string)d.cancel_pending_due+" (diagnostic flag only)");
  }
#endif
