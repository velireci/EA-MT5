// T012 pure daily-limit check. Mirrors tests/t012_daily_reference.py (its header documents rules, consistency checks and the reason order).
// NOT a trading module: no order, no cancellation, no account or position read, no clock, no persistence, no real reset, no EA wiring.
// Every number is an argument. Answers: are NEW ENTRIES blocked for the Tirane day of `utc`, and is a daily limit PROVEN reached
// (cancel_pending_due / daily_limit_reached). Existing positions are never touched. The Tirane day comes from T009 (SP_Evaluate); DST is
// not recomputed here.
// Client rules (STRATEGY_SPEC section 9): >=1 win, >=2 consecutive losses, closed result <= -2% of the balance at the start of the day,
// and the SUPPLIED trade limit. 2 versus 3 trades is not decided (a missing limit is POLICY_UNSET -> blocked). Partial exits, costs and
// breakeven are not classified here (the caller supplies wins / losses / trades). Floating results are not an input.
#ifndef VELO_DAILY_LIMITS_MQH
#define VELO_DAILY_LIMITS_MQH

#include "SessionPolicy.mqh"

#define DL_WIN_STOP_AT 1
#define DL_CONSECUTIVE_LOSS_STOP_AT 2
#define DL_LOSS_DIVISOR 50.0
#define DL_MAX_COUNT 100000
#define DL_MAX_REASONS 16

struct SDlInput
  {
   datetime utc;
   int snapshot_day;
   double balance_start;
   double closed_result;
   int trades_today;
   int wins_today;
   int consecutive_losses;
   bool max_trades_set;
   int max_trades;
  };

struct SDlResult
  {
   bool entry_allowed;
   string primary;
   int n_reasons;
   string reasons[DL_MAX_REASONS];
   bool cancel_pending_due;
   bool daily_limit_reached;
   int day_key;
  };

bool DL_Finite(const double x) {return(x==x && x-x==0.0);}
bool DL_Count(const int x) {return(x>=0 && x<=DL_MAX_COUNT);}

void DL_Add(SDlResult &r,const string reason)
  {
   if(r.n_reasons<DL_MAX_REASONS)
     {
      r.reasons[r.n_reasons]=reason;
      r.n_reasons++;
     }
  }

string DL_Joined(const SDlResult &r)
  {
   string s="";
   for(int i=0;i<r.n_reasons;i++)
      s+=(i>0 ? "|" : "")+r.reasons[i];
   return(s);
  }

// Returns entry_allowed.
bool DL_Check(const SDlInput &in,SDlResult &r)
  {
   r.entry_allowed=false;
   r.primary="";
   r.n_reasons=0;
   for(int i=0;i<DL_MAX_REASONS;i++)
      r.reasons[i]="";
   r.cancel_pending_due=false;
   r.daily_limit_reached=false;
   r.day_key=0;
   // ---- validity (T009 owns the Tirane day)
   SSessionPolicy sp;
   bool ok=SP_Evaluate(in.utc,0,1230,62,true,1260,sp);
   int day=0;
   if(ok && sp.status=="OK")
      day=sp.day_key;
   else
      if(sp.status=="UNSUPPORTED_YEAR")
         DL_Add(r,"UNSUPPORTED_YEAR");
      else
         DL_Add(r,"INVALID_UTC");
   if(in.snapshot_day<19960101 || in.snapshot_day>20991231)
      DL_Add(r,"INVALID_SNAPSHOT:snapshot_day");
   else
      if(day!=0 && in.snapshot_day!=day)
         DL_Add(r,"STALE_SNAPSHOT_DAY");
   if(!DL_Finite(in.balance_start) || in.balance_start<=0.0 || in.balance_start/DL_LOSS_DIVISOR<DBL_MIN)
      DL_Add(r,"INVALID_SNAPSHOT:balance_start");      // also when the 2% threshold would underflow: no limit is invented from it
   if(!DL_Finite(in.closed_result))
      DL_Add(r,"INVALID_SNAPSHOT:closed_result");
   bool t_ok=DL_Count(in.trades_today),w_ok=DL_Count(in.wins_today),l_ok=DL_Count(in.consecutive_losses);
   if(!t_ok) DL_Add(r,"INVALID_SNAPSHOT:trades_today");
   if(!w_ok) DL_Add(r,"INVALID_SNAPSHOT:wins_today");
   if(!l_ok) DL_Add(r,"INVALID_SNAPSHOT:consecutive_losses");
   if(in.max_trades_set && (in.max_trades<1 || in.max_trades>DL_MAX_COUNT))
      DL_Add(r,"INVALID_SNAPSHOT:max_trades_per_day");
   if(t_ok && w_ok && in.wins_today>in.trades_today)
      DL_Add(r,"INCONSISTENT_COUNTERS:wins_exceed_trades");
   if(t_ok && l_ok && in.consecutive_losses>in.trades_today)
      DL_Add(r,"INCONSISTENT_COUNTERS:losses_exceed_trades");
   if(t_ok && w_ok && l_ok && in.wins_today<=in.trades_today && in.consecutive_losses<=in.trades_today &&
      in.wins_today+in.consecutive_losses>in.trades_today)
      DL_Add(r,"INCONSISTENT_COUNTERS:wins_plus_losses_exceed_trades");
   r.day_key=day;
   if(r.n_reasons>0)
     {
      r.primary=r.reasons[0];
      return(false);
     }
   // ---- limits, fixed order
   bool limit=false;
   if(in.wins_today>=DL_WIN_STOP_AT)
     {
      DL_Add(r,"DAILY_WIN_STOP");
      limit=true;
     }
   if(in.consecutive_losses>=DL_CONSECUTIVE_LOSS_STOP_AT)
     {
      DL_Add(r,"CONSECUTIVE_LOSSES_STOP");
      limit=true;
     }
   double threshold=in.balance_start/DL_LOSS_DIVISOR;
   if(in.closed_result<0.0 && in.closed_result<=-threshold+4.0*DBL_EPSILON*threshold)      // tolerance RELATIVE to the threshold: always smaller than it
     {
      DL_Add(r,"DAILY_LOSS_LIMIT");
      limit=true;
     }
   if(in.max_trades_set && in.trades_today>=in.max_trades)
     {
      DL_Add(r,"MAX_TRADES_REACHED");
      limit=true;
     }
   if(!in.max_trades_set)
      DL_Add(r,"POLICY_UNSET:max_trades_per_day");
   r.cancel_pending_due=limit;
   r.daily_limit_reached=limit;
   r.entry_allowed=(r.n_reasons==0);
   if(r.n_reasons>0)
      r.primary=r.reasons[0];
   return(r.entry_allowed);
  }
#endif
