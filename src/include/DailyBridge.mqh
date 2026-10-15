// T012 BRIDGE from the history FACTS (DailyHistory.mqh) to the daily-limit check (DailyLimits.mqh). Mirrors tests/t012_bridge_reference.py (its header
// documents the contract in full). PURE: no terminal read, no account or history API, no clock, no order, no persistence, no real reset, no EA wiring.
// It chooses NO policy: the result formula and the trade / win / loss classification are EXPLICIT inputs; UNSET or an unsupported value blocks
// with its own reason; a missing balance, a balance of another day, an unready or incomplete history block. The deal count is never a trade count and
// a missing figure is never turned into zero. When every input and policy is defined, DL_Check (not copied) decides and its result is propagated.
// Only these members of SDhFacts are read: day_key, complete, n_pos, candidate_profit, candidate_profit_commission_swap,
// candidate_profit_commission_swap_fee.
#ifndef VELO_DAILY_BRIDGE_MQH
#define VELO_DAILY_BRIDGE_MQH

#include "DailyHistory.mqh"
#include "DailyLimits.mqh"

#define DB_MAX_REASONS 16
#define DB_UNSET "UNSET"
#define DB_FORMULA_PROFIT "PROFIT"
#define DB_FORMULA_PROFIT_COMMISSION_SWAP "PROFIT_COMMISSION_SWAP"
#define DB_FORMULA_PROFIT_COMMISSION_SWAP_FEE "PROFIT_COMMISSION_SWAP_FEE"
#define DB_CLASSIFICATION_CALLER "CALLER_CLASSIFIED"

struct SDbBalance
  {
   bool known;
   int day;
   double amount;
  };

struct SDbPolicy
  {
   string result_formula;
   string classification;
  };

struct SDbClassified
  {
   int trades;
   int wins;
   int consecutive_losses;
  };

struct SDbResult
  {
   bool entry_allowed;
   string primary;
   int n_reasons;
   string reasons[DB_MAX_REASONS];
   bool dl_called;
   double closed_result;
   bool cancel_pending_due;
   bool daily_limit_reached;
   int day_key;
  };

void DB_Add(SDbResult &r,const string reason)
  {
   if(r.n_reasons<DB_MAX_REASONS)
     {
      r.reasons[r.n_reasons]=reason;
      r.n_reasons++;
     }
  }

string DB_Joined(const SDbResult &r)
  {
   string s="";
   for(int i=0;i<r.n_reasons;i++)
      s+=(i>0 ? "|" : "")+r.reasons[i];
   return(s);
  }

string DB_PolicyReason(const string name,const string value,const bool supported)
  {
   if(value==DB_UNSET) return("POLICY_UNSET:"+name);
   if(!supported) return("POLICY_UNSUPPORTED:"+name);
   return("");
  }

// Returns entry_allowed.
bool DB_Check(const ENUM_DH_VERDICT verdict,const SDhFacts &facts,const datetime utc,const SDbBalance &balance,const SDbPolicy &policy,
              const SDbClassified &cls,const bool max_trades_set,const int max_trades,SDbResult &r)
  {
   r.entry_allowed=false;
   r.primary="";
   r.n_reasons=0;
   for(int i=0;i<DB_MAX_REASONS;i++)
      r.reasons[i]="";
   r.dl_called=false;
   r.closed_result=MathSqrt(-1.0);
   r.cancel_pending_due=false;
   r.daily_limit_reached=false;
   r.day_key=0;
   bool ready=(verdict==DH_READY);
   if(!ready)
      DB_Add(r,"HISTORY_NOT_READY:"+(verdict==DH_UNKNOWN ? "UNKNOWN" : (verdict==DH_BLOCK ? "BLOCK" : "?")));
   else
      if(!facts.complete)
         DB_Add(r,"HISTORY_INCOMPLETE");
   if(!balance.known)
      DB_Add(r,"BALANCE_START_UNSET");
   else
      if(ready && balance.day!=facts.day_key)
         DB_Add(r,"BALANCE_DAY_MISMATCH");
   bool f_profit=(policy.result_formula==DB_FORMULA_PROFIT);
   bool f_pcs=(policy.result_formula==DB_FORMULA_PROFIT_COMMISSION_SWAP);
   bool f_pcsf=(policy.result_formula==DB_FORMULA_PROFIT_COMMISSION_SWAP_FEE);
   string rf=DB_PolicyReason("result_formula",policy.result_formula,f_profit || f_pcs || f_pcsf);
   if(rf!="") DB_Add(r,rf);
   string cf=DB_PolicyReason("trade_classification",policy.classification,policy.classification==DB_CLASSIFICATION_CALLER);
   if(cf!="")
      DB_Add(r,cf);
   else
      if(ready && cls.trades>0 && facts.n_pos==0)
         DB_Add(r,"CLASSIFICATION_CONTRADICTS_FACTS:trades_without_positions");
   if(r.n_reasons>0)
     {
      r.primary=r.reasons[0];
      return(false);
     }
   double closed=(f_profit ? facts.candidate_profit : (f_pcs ? facts.candidate_profit_commission_swap : facts.candidate_profit_commission_swap_fee));
   r.closed_result=closed;
   SDlInput in;
   in.utc=utc;
   in.snapshot_day=facts.day_key;
   in.balance_start=balance.amount;
   in.closed_result=closed;
   in.trades_today=cls.trades;
   in.wins_today=cls.wins;
   in.consecutive_losses=cls.consecutive_losses;
   in.max_trades_set=max_trades_set;
   in.max_trades=max_trades;
   SDlResult d;
   DL_Check(in,d);
   r.dl_called=true;
   r.entry_allowed=d.entry_allowed;
   r.primary=d.primary;
   r.n_reasons=d.n_reasons;
   for(int j=0;j<d.n_reasons && j<DB_MAX_REASONS;j++)
      r.reasons[j]=d.reasons[j];
   r.cancel_pending_due=d.cancel_pending_due;
   r.daily_limit_reached=d.daily_limit_reached;
   r.day_key=d.day_key;
   return(r.entry_allowed);
  }

string DB_Text(const SDbResult &r)
  {
   return((r.entry_allowed ? "ENTRIES ALLOWED" : "ENTRIES BLOCKED")+" day "+IntegerToString(r.day_key)+" daily_check_called="+(string)r.dl_called+
          " reasons "+(r.n_reasons>0 ? DB_Joined(r) : "none")+" | cancel_pending_due="+(string)r.cancel_pending_due+" (diagnostic flag only)");
  }
#endif
