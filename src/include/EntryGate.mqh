// T015 ENTRY GATE (mirror of tests/entry_gate_reference.py; read its header for the full contract): the ONE place where a T014 plan, the existing checks and the entry executor meet.
//   plan (T014, plan_ready) + TP_CheckPermit (data, session, news, spread, exposure, limits, duplicates) + PB_CheckLoss (broker loss) + the T012 daily result
//   -> ONE decision. Only when EVERY check allows is an executor permit (SEnPermit) built FOR THAT PLAN (canonical digest) and stamped with the decision time. Any block builds no permit and the
//   executor is not called: no intent, no lock, no Send, no registered signal use (TP_CheckPermit is used, never TP_Authorize).
// It copies no rule. In THIS path a daily result that is missing, not evaluated, not called or not allowing BLOCKS; the preview's MANUAL exception (daily not evaluated = no condition) is never used and the
// T007 allow alone never reaches the executor. Every check input carries the plan digest it was computed for and the instant it was observed: another plan, a future instant or an instant older than
// max_age BLOCKS; max_age <= 0 is UNSET = BLOCK. The durable duplicate guard stays in EN_Place (one record per signal): this module has NO state, writes nothing and reads no clock (now is an argument;
// EG_Submit reads the transport clock once). Unresolved policies stay UNSET = BLOCK through TP_CheckPermit. No real transport is used or included here.
#ifndef VELO_ENTRY_GATE_MQH
#define VELO_ENTRY_GATE_MQH

#include "EntryExecutor.mqh"
#include "SetupPlanBridge.mqh"
#include "BrokerLossCheck.mqh"
#include "DailyBridge.mqh"

struct SEgConfig
  {
   long max_age;                 // seconds a check may be old; <= 0 = UNSET = BLOCK
  };

void EG_ConfigInit(SEgConfig &c) {c.max_age=-1;}

struct SEgChecks
  {
   bool permit_inputs;           // false = the snapshot / limits are missing
   STpSnapshot snap;
   long snap_time;
   string snap_digest;
   STpLimits lim;
   bool calc_ok;                 // the broker loss estimate (OrderCalcProfit) was obtained
   double profit;
   double tolerance;
   double risk_budget;
   long loss_time;
   string loss_digest;
   bool daily_present;           // the T012 bridge result exists (the daily check was evaluated for this path)
   SDbResult daily;
   long daily_time;
   string daily_digest;
  };

struct SEgDecision
  {
   bool allow;
   string reasons;               // all blocking reasons, joined with " | "
   string loss_check;
   SEnPermit permit;
  };

void EG_DecisionInit(SEgDecision &d)
  {
   d.allow=false;
   d.reasons="";
   d.loss_check="";
   EN_PermitInit(d.permit);
  }

void EG_Add(SEgDecision &d,const string reason) {d.reasons+=(d.reasons=="" ? "" : " | ")+reason;}

void EG_Fresh(SEgDecision &d,const string name,const long t,const string digest,const string want,const long now,const long max_age)
  {
   if(!(t>0 && t<=now)) EG_Add(d,name+"_TIME_INVALID");
   else
      if(now-t>max_age) EG_Add(d,name+"_STALE");
   if(digest!=want) EG_Add(d,name+"_FOR_ANOTHER_PLAN");
  }

void EG_Decide(const SEgConfig &g,const SSpbResult &spb,const SEgChecks &c,const string &reg_ids[],const int reg_count,const long now,SEgDecision &d)
  {
   EG_DecisionInit(d);
   if(!(g.max_age>0)) {EG_Add(d,"INPUT_UNSET: gate_max_age"); return;}
   if(!spb.plan_ready) {EG_Add(d,"PLAN_NOT_READY: "+spb.reason); return;}
   string digest=EN_PlanDigest(spb.plan);
   if(digest=="") {EG_Add(d,"PLAN_INVALID"); return;}
   if(!(now>0)) {EG_Add(d,"NOW_UNSET"); return;}
   EG_Fresh(d,"SNAPSHOT",c.snap_time,c.snap_digest,digest,now,g.max_age);
   EG_Fresh(d,"LOSS_CHECK",c.loss_time,c.loss_digest,digest,now,g.max_age);
   EG_Fresh(d,"DAILY",c.daily_time,c.daily_digest,digest,now,g.max_age);
   d.loss_check=PB_CheckLoss(c.calc_ok,c.profit,spb.plan.risk_model,c.risk_budget,c.tolerance);
   STpPlan guarded=spb.plan;
   if(d.loss_check!="OK") EG_Add(d,"BROKER_LOSS_CHECK:"+d.loss_check);
   else guarded.risk_model=PB_PermitRisk(c.profit,spb.plan.risk_model);
   STpPermit tpermit;
   if(!c.permit_inputs) EG_Add(d,"PERMIT_INPUT_MISSING");
   else
     {
      TP_CheckPermit(guarded,c.snap,c.lim,reg_ids,reg_count,tpermit);
      if(!tpermit.allow)
         for(int i=0;i<tpermit.reason_count;i++) EG_Add(d,"PERMIT:"+tpermit.reasons[i]);
     }
   if(!c.daily_present) EG_Add(d,"DAILY_NOT_EVALUATED");
   else
      if(!c.daily.dl_called) EG_Add(d,"DAILY_NOT_CALLED: "+c.daily.primary);
      else
         if(!c.daily.entry_allowed) EG_Add(d,"DAILY_BLOCK: "+c.daily.primary);
   if(d.reasons!="") return;
   d.allow=true;
   EN_PermitFrom(spb.plan,tpermit,now,d.permit);
  }

// A block never reaches the executor. `res` is the executor result, or REFUSED "GATE_BLOCKED: ...".
void EG_Submit(const SEgConfig &g,const SEnConfig &cfg,CEnTransport *tr,CEnStore *store,SEnRuntime &rt,const SSpbResult &spb,const SEgChecks &c,const string &reg_ids[],const int reg_count,
               SEnResult &res,SEgDecision &d)
  {
   long now=tr.ServerTime();
   EG_Decide(g,spb,c,reg_ids,reg_count,now,d);
   if(!d.allow) {EN_Res(res,EN_R_REFUSED,"GATE_BLOCKED: "+d.reasons); return;}
   EN_Place(cfg,tr,store,rt,spb.plan,d.permit,res);
  }
#endif
