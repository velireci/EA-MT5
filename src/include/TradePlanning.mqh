// T007 pure trade planning, permit checks and pending-cancel decision. NOT a trading rule, NOT an order and NOT wired to any EA.
// Mirror of tests/t007_planning_reference.py (read its header for the full contract). No order function, no trading API, no
// account/symbol/broker read, no live price, no clock, no file or persistence: every value is an ARGUMENT supplied by the caller.
//
// PART 1 TRADE PLAN (TP_BuildPlan). The caller chooses signal_id, setup_id, direction, E, SL, the optional target, the risk budget
//  (the base of the 1% is NOT chosen here), tick_value and the symbol/volume parameters. The part only CALLS TG_Compute (T005) and
//  then PS_Compute (T006) with the geometry result as the sizing input; it copies no formula and no normalization and it never
//  selects an FVG, swing, target, the 1% base or the T002/T003 priority.
//  Statuses, first failure wins: INVALID_INPUT (stage INPUT; INVALID_SIGNAL_ID then INVALID_SETUP_ID; empty or blank id),
//  GEOMETRY_REFUSED (stage GEOMETRY; under_status/under_reason = the T005 status and reason), SIZING_REFUSED (stage SIZING;
//  under_status/under_reason = the T006 status and reason, including SKIP_*), OK (stage COMPLETE). An OK plan carries the
//  normalized e_out, s_out, tp, level_2r, partial_price (PARTIAL_AT_2R, client answer 80%, NO volume split), r_geom, volume_out
//  and risk_model (= T006 risk_realized, LINEAR_MODEL, COSTS_NOT_MODELLED) and the label PLAN_ONLY / NOT_AN_ORDER. On any refusal
//  every numeric field is 0 and reason names the stage.
//
// PART 2 PERMIT CHECKS (TP_CheckPermit pure, TP_Authorize = check + registration). Inputs: the plan (must be OK), a SNAPSHOT
//  supplied by the caller (no clock, no feed inside), the LIMITS (each a value or UNSET) and a caller-owned in-memory registry of
//  used signal_ids. Output: ALLOW/BLOCK, the primary (first) reason and ALL blocking reasons in this FIXED order, one tag at most
//  per group:
//   1 PLAN_NOT_OK  2 data: DATA_UNRELIABLE (state READY, reliability flag false) | DATA_NOT_READY | DATA_UNKNOWN
//   3 session: SESSION_CLOSED | SESSION_UNKNOWN  4 news: NEWS_BLOCK | NEWS_UNKNOWN  5 spread: SPREAD_BLOCK | SPREAD_UNKNOWN
//   6 registry: REGISTRY_INVALID | DUPLICATE_SIGNAL | REGISTRY_FULL
//   7 positions: POLICY_UNSET:max_positions | INVALID_SNAPSHOT:max_positions | INVALID_SNAPSHOT:open_positions | MAX_POSITIONS_REACHED
//   8 trades: POLICY_UNSET:max_trades_per_day | INVALID_SNAPSHOT:max_trades_per_day | INVALID_SNAPSHOT:trades_today | MAX_TRADES_REACHED
//   9 risk: POLICY_UNSET:combined_risk_cap | INVALID_SNAPSHOT:combined_risk_cap | INVALID_SNAPSHOT:existing_risk | COMBINED_RISK_EXCEEDED
//  A state outside the documented values gives INVALID_SNAPSHOT:data_state / session_state / news_state / spread_state. Every
//  uncertainty blocks (fail closed). A limit that is UNSET ALWAYS gives POLICY_UNSET:<name>: this module never invents the
//  2-vs-3 trades, what counts as a win, the pending-order risk reservation or the manual-trade handling.
//  BOUNDARIES (PROPOSALS for review, not client answers): open_positions < max_positions allows, == blocks; trades_today <
//  max_trades_per_day allows, == blocks; existing_risk + plan risk_model <= combined_risk_cap allows (exactly at the cap is ALLOWED),
//  tolerance only binary noise (TP_RISK_ULPS = 4 ulps of max(1, cap)). The combined-risk comparison is skipped when the plan is
//  not OK (PLAN_NOT_OK already blocks). ALLOW is a PERMIT RESULT ONLY, never an executed order.
//  REGISTRY: caller-owned string array (its size is the capacity) plus a count, in memory only. NOT atomic, NOT persistent, no broker
//  or restart recovery. TP_Authorize records plan.signal_id ONLY on ALLOW (a BLOCK never consumes the id). At capacity a new id is
//  BLOCKED with REGISTRY_FULL, never dropped silently; a count outside 0..capacity is REGISTRY_INVALID. A duplicate is checked
//  before capacity.
//
// PART 3 PENDING CANCEL DECISION (TP_CancelDecision). Inputs: pending exists + its signal_id, position exists, and explicit external
//  events as a bitmask: DIRECTION_CHANGE 1, OPPOSITE_SIGNAL 2, SESSION_END 4, NEWS_BLOCK 8, DAILY_LIMIT 16. Output: a cancel REQUEST
//  for the PENDING order only. Order of checks: unknown event bits (or a negative mask) -> INVALID_INPUT (INVALID_EVENTS), even
//  without a pending; no pending -> NO_PENDING (an open position alone never gives a cancel request); pending with a blank id ->
//  INVALID_INPUT (INVALID_PENDING_SIGNAL_ID); mask 0 -> NO_EVENT; else CANCEL_REQUEST with the reasons in the fixed order above.
//  positions_untouched is ALWAYS true: this decision never cancels or closes an open position. No expiry by time or candles, no
//  cooldown, no re-entry, nothing is sent.
//
// NOT decided here (open): the base of the 1%, costs, the combined 2% numbers, the 2-vs-3 trades, win/loss counting, pending risk
// reservation, manual-trade ownership, session/news/spread sources and thresholds, time handling, order placement, 80/20 volume
// split, expiry, cooldown, re-entry, restart recovery, EA wiring. NOT wired to any EA.
#ifndef VELO_TRADE_PLANNING_MQH
#define VELO_TRADE_PLANNING_MQH

#include "TradeGeometry.mqh"
#include "PositionSizing.mqh"

#define TP_RISK_ULPS 4.0
#define TP_MAX_REASONS 12

#define TP_DATA_READY 1
#define TP_DATA_NOT_READY 2
#define TP_DATA_UNKNOWN 3
#define TP_SESSION_OPEN 1
#define TP_SESSION_CLOSED 2
#define TP_SESSION_UNKNOWN 3
#define TP_NEWS_CLEAR 1
#define TP_NEWS_BLOCKED 2
#define TP_NEWS_UNKNOWN 3
#define TP_SPREAD_CLEAR 1
#define TP_SPREAD_BLOCKED 2
#define TP_SPREAD_UNKNOWN 3

#define TP_EV_DIRECTION_CHANGE 1
#define TP_EV_OPPOSITE_SIGNAL 2
#define TP_EV_SESSION_END 4
#define TP_EV_NEWS_BLOCK 8
#define TP_EV_DAILY_LIMIT 16
#define TP_EV_ALL 31

enum ENUM_TP_STATUS
  {
   TP_OK=0,
   TP_INVALID_INPUT,
   TP_GEOMETRY_REFUSED,
   TP_SIZING_REFUSED
  };

enum ENUM_TP_STAGE
  {
   TP_STAGE_INPUT=0,
   TP_STAGE_GEOMETRY,
   TP_STAGE_SIZING,
   TP_STAGE_COMPLETE
  };

enum ENUM_TP_CANCEL
  {
   TP_CANCEL_REQUEST=0,
   TP_CANCEL_NO_PENDING,
   TP_CANCEL_NO_EVENT,
   TP_CANCEL_INVALID_INPUT
  };

struct STpPlan
  {
   ENUM_TP_STATUS status;
   ENUM_TP_STAGE stage;
   string reason;
   string under_status;
   string under_reason;
   string signal_id;
   string setup_id;
   int direction;
   double e_out;
   double s_out;
   double tp;
   double level_2r;
   double partial_price;
   double r_geom;
   double volume_out;
   double risk_model;
   bool tp_equals_2r;
  };

struct STpSnapshot
  {
   int data_state;
   bool data_reliable;
   int session_state;
   int news_state;
   int spread_state;
   long open_positions;
   long trades_today;
   double existing_risk;
  };

struct STpLimits
  {
   bool max_positions_set;
   long max_positions;
   bool max_trades_set;
   long max_trades;
   bool risk_cap_set;
   double risk_cap;
  };

struct STpPermit
  {
   bool allow;
   string primary_reason;
   string reasons[12];
   int reason_count;
   bool registered;
  };

struct STpCancel
  {
   ENUM_TP_CANCEL status;
   string reason;
   string reasons[5];
   int reason_count;
   bool cancel_pending;
   string pending_signal_id;
   bool position_present;
   bool positions_untouched;
  };

string TP_StatusName(const ENUM_TP_STATUS s)
  {
   switch(s)
     {
      case TP_OK: return("OK");
      case TP_INVALID_INPUT: return("INVALID_INPUT");
      case TP_GEOMETRY_REFUSED: return("GEOMETRY_REFUSED");
      case TP_SIZING_REFUSED: return("SIZING_REFUSED");
     }
   return("UNKNOWN");
  }

string TP_StageName(const ENUM_TP_STAGE s)
  {
   switch(s)
     {
      case TP_STAGE_INPUT: return("INPUT");
      case TP_STAGE_GEOMETRY: return("GEOMETRY");
      case TP_STAGE_SIZING: return("SIZING");
      case TP_STAGE_COMPLETE: return("COMPLETE");
     }
   return("UNKNOWN");
  }

string TP_CancelStatusName(const ENUM_TP_CANCEL s)
  {
   switch(s)
     {
      case TP_CANCEL_REQUEST: return("CANCEL_REQUEST");
      case TP_CANCEL_NO_PENDING: return("NO_PENDING");
      case TP_CANCEL_NO_EVENT: return("NO_EVENT");
      case TP_CANCEL_INVALID_INPUT: return("INVALID_INPUT");
     }
   return("UNKNOWN");
  }

string TP_PlanLabel() {return("PLAN_ONLY / NOT_AN_ORDER");}
string TP_PermitLabel() {return("PERMIT_ONLY / NOT_AN_ORDER");}
string TP_CancelLabel() {return("CANCEL_REQUEST_ONLY / NOT_SENT");}
string TP_PartialLabel() {return("PARTIAL_AT_2R (client answer: 80% of initial volume; no volume split here)");}
string TP_RiskLabel() {return("LINEAR_MODEL, COSTS_NOT_MODELLED");}

bool TP_IsBlank(const string s)
  {
   string t=s;
   StringTrimLeft(t);
   StringTrimRight(t);
   return(StringLen(t)==0);
  }

// ----------------------------------------------------------------------------------------------- part 1: plan
void TP_PlanReset(STpPlan &p,const string signal_id,const string setup_id,const int direction)
  {
   p.status=TP_OK;
   p.stage=TP_STAGE_COMPLETE;
   p.reason="";
   p.under_status="";
   p.under_reason="";
   p.signal_id=signal_id;
   p.setup_id=setup_id;
   p.direction=direction;
   p.e_out=0.0;
   p.s_out=0.0;
   p.tp=0.0;
   p.level_2r=0.0;
   p.partial_price=0.0;
   p.r_geom=0.0;
   p.volume_out=0.0;
   p.risk_model=0.0;
   p.tp_equals_2r=false;
  }

bool TP_PlanRefuse(STpPlan &p,const ENUM_TP_STATUS status,const ENUM_TP_STAGE stage,const string reason)
  {
   p.status=status;
   p.stage=stage;
   p.reason=reason;
   return(false);
  }

// Returns true when status == TP_OK. Nothing outside `out` is touched.
bool TP_BuildPlan(const string signal_id,const string setup_id,const int direction,const double e_raw,const double s_raw,
                  const bool has_target,const double t_raw,const double risk_budget,const double tick_value,
                  const double tick_size,const int digits,const double point,const int stops_level,
                  const bool has_quote,const double bid,const double ask,
                  const double volume_min,const double volume_step,const double volume_max,const double cap_lots,
                  STpPlan &out)
  {
   TP_PlanReset(out,signal_id,setup_id,direction);
   if(TP_IsBlank(signal_id))
      return(TP_PlanRefuse(out,TP_INVALID_INPUT,TP_STAGE_INPUT,"INVALID_SIGNAL_ID: signal_id must be a non-empty string"));
   if(TP_IsBlank(setup_id))
      return(TP_PlanRefuse(out,TP_INVALID_INPUT,TP_STAGE_INPUT,"INVALID_SETUP_ID: setup_id must be a non-empty string"));
   STgResult geo;
   TG_Compute(direction,e_raw,s_raw,has_target,t_raw,tick_size,digits,point,stops_level,has_quote,bid,ask,geo);
   if(geo.status!=TG_OK)
     {
      out.under_status=TG_StatusName(geo.status);
      out.under_reason=geo.reason;
      return(TP_PlanRefuse(out,TP_GEOMETRY_REFUSED,TP_STAGE_GEOMETRY,
                           StringFormat("GEOMETRY_REFUSED: geometry %s: %s",out.under_status,geo.reason)));
     }
   SPsResult siz;
   PS_Compute(geo,risk_budget,tick_value,volume_min,volume_step,volume_max,cap_lots,siz);
   if(siz.status!=PS_OK)
     {
      out.under_status=PS_StatusName(siz.status);
      out.under_reason=siz.reason;
      return(TP_PlanRefuse(out,TP_SIZING_REFUSED,TP_STAGE_SIZING,
                           StringFormat("SIZING_REFUSED: sizing %s: %s",out.under_status,siz.reason)));
     }
   out.e_out=geo.e_out;
   out.s_out=geo.s_out;
   out.tp=geo.tp;
   out.level_2r=geo.level_2r;
   out.partial_price=geo.partial_price;
   out.r_geom=geo.r_geom;
   out.volume_out=siz.volume_out;
   out.risk_model=siz.risk_realized;
   out.tp_equals_2r=geo.tp_equals_2r;
   return(true);
  }

// --------------------------------------------------------------------------------------------- part 2: permit
bool TP_CountOk(const long v) {return(v>=0);}
bool TP_MoneyOk(const double v) {return(TG_Finite(v) && v>=0.0);}

void TP_AddReason(STpPermit &p,const string tag)
  {
   if(p.reason_count>=TP_MAX_REASONS) return;
   p.reasons[p.reason_count]=tag;
   p.reason_count++;
  }

string TP_ReasonsText(const STpPermit &p)
  {
   string s="";
   for(int i=0;i<p.reason_count;i++)
      s+=(i>0 ? "|" : "")+p.reasons[i];
   return(s);
  }

// Pure: nothing is changed except `out`. Returns true when the decision is ALLOW.
bool TP_CheckPermit(const STpPlan &plan,const STpSnapshot &snap,const STpLimits &lim,
                    const string &reg_ids[],const int reg_count,STpPermit &out)
  {
   out.allow=false;
   out.primary_reason="";
   out.reason_count=0;
   out.registered=false;
   for(int i=0;i<TP_MAX_REASONS;i++) out.reasons[i]="";
   bool plan_ok=(plan.status==TP_OK);
   if(!plan_ok) TP_AddReason(out,"PLAN_NOT_OK");
   // data
   if(snap.data_state==TP_DATA_READY)
     {
      if(!snap.data_reliable) TP_AddReason(out,"DATA_UNRELIABLE");
     }
   else if(snap.data_state==TP_DATA_NOT_READY) TP_AddReason(out,"DATA_NOT_READY");
   else if(snap.data_state==TP_DATA_UNKNOWN) TP_AddReason(out,"DATA_UNKNOWN");
   else TP_AddReason(out,"INVALID_SNAPSHOT:data_state");
   // session, news, spread
   if(snap.session_state==TP_SESSION_CLOSED) TP_AddReason(out,"SESSION_CLOSED");
   else if(snap.session_state==TP_SESSION_UNKNOWN) TP_AddReason(out,"SESSION_UNKNOWN");
   else if(snap.session_state!=TP_SESSION_OPEN) TP_AddReason(out,"INVALID_SNAPSHOT:session_state");
   if(snap.news_state==TP_NEWS_BLOCKED) TP_AddReason(out,"NEWS_BLOCK");
   else if(snap.news_state==TP_NEWS_UNKNOWN) TP_AddReason(out,"NEWS_UNKNOWN");
   else if(snap.news_state!=TP_NEWS_CLEAR) TP_AddReason(out,"INVALID_SNAPSHOT:news_state");
   if(snap.spread_state==TP_SPREAD_BLOCKED) TP_AddReason(out,"SPREAD_BLOCK");
   else if(snap.spread_state==TP_SPREAD_UNKNOWN) TP_AddReason(out,"SPREAD_UNKNOWN");
   else if(snap.spread_state!=TP_SPREAD_CLEAR) TP_AddReason(out,"INVALID_SNAPSHOT:spread_state");
   // registry
   int capacity=ArraySize(reg_ids);
   if(reg_count<0 || reg_count>capacity) TP_AddReason(out,"REGISTRY_INVALID");
   else if(!TP_IsBlank(plan.signal_id))
     {
      bool dup=false;
      for(int i=0;i<reg_count;i++)
         if(reg_ids[i]==plan.signal_id) {dup=true; break;}
      if(dup) TP_AddReason(out,"DUPLICATE_SIGNAL");
      else if(reg_count>=capacity) TP_AddReason(out,"REGISTRY_FULL");
     }
   // positions
   if(!lim.max_positions_set) TP_AddReason(out,"POLICY_UNSET:max_positions");
   else if(!TP_CountOk(lim.max_positions)) TP_AddReason(out,"INVALID_SNAPSHOT:max_positions");
   else if(!TP_CountOk(snap.open_positions)) TP_AddReason(out,"INVALID_SNAPSHOT:open_positions");
   else if(snap.open_positions>=lim.max_positions) TP_AddReason(out,"MAX_POSITIONS_REACHED");
   // trades
   if(!lim.max_trades_set) TP_AddReason(out,"POLICY_UNSET:max_trades_per_day");
   else if(!TP_CountOk(lim.max_trades)) TP_AddReason(out,"INVALID_SNAPSHOT:max_trades_per_day");
   else if(!TP_CountOk(snap.trades_today)) TP_AddReason(out,"INVALID_SNAPSHOT:trades_today");
   else if(snap.trades_today>=lim.max_trades) TP_AddReason(out,"MAX_TRADES_REACHED");
   // combined risk
   if(!lim.risk_cap_set) TP_AddReason(out,"POLICY_UNSET:combined_risk_cap");
   else if(!TP_MoneyOk(lim.risk_cap)) TP_AddReason(out,"INVALID_SNAPSHOT:combined_risk_cap");
   else if(!TP_MoneyOk(snap.existing_risk)) TP_AddReason(out,"INVALID_SNAPSHOT:existing_risk");
   else if(plan_ok && snap.existing_risk+plan.risk_model>lim.risk_cap+TP_RISK_ULPS*DBL_EPSILON*MathMax(1.0,lim.risk_cap))
      TP_AddReason(out,"COMBINED_RISK_EXCEEDED");
   if(out.reason_count>0)
     {
      out.primary_reason=out.reasons[0];
      return(false);
     }
   out.allow=true;
   return(true);
  }

// check + registration: plan.signal_id is recorded in the caller-owned registry ONLY when the decision is ALLOW.
bool TP_Authorize(const STpPlan &plan,const STpSnapshot &snap,const STpLimits &lim,
                  string &reg_ids[],int &reg_count,STpPermit &out)
  {
   if(!TP_CheckPermit(plan,snap,lim,reg_ids,reg_count,out))
      return(false);
   reg_ids[reg_count]=plan.signal_id;
   reg_count++;
   out.registered=true;
   return(true);
  }

// --------------------------------------------------------------------------------------------- part 3: cancel
// Returns true when status == TP_CANCEL_REQUEST. A request object only: nothing is sent, no position is touched.
bool TP_CancelDecision(const bool pending_exists,const string pending_signal_id,const bool position_exists,
                       const int events,STpCancel &out)
  {
   out.status=TP_CANCEL_NO_PENDING;
   out.reason="";
   out.reason_count=0;
   for(int i=0;i<5;i++) out.reasons[i]="";
   out.cancel_pending=false;
   out.pending_signal_id="";
   out.position_present=position_exists;
   out.positions_untouched=true;
   if(events<0 || (events & ~TP_EV_ALL)!=0)
     {
      out.status=TP_CANCEL_INVALID_INPUT;
      out.reason=StringFormat("INVALID_EVENTS: %d is not a mask of the five known events",events);
      return(false);
     }
   if(!pending_exists)
     {
      out.status=TP_CANCEL_NO_PENDING;
      out.reason="NO_PENDING: no pending order, nothing to cancel";
      return(false);
     }
   if(TP_IsBlank(pending_signal_id))
     {
      out.status=TP_CANCEL_INVALID_INPUT;
      out.reason="INVALID_PENDING_SIGNAL_ID: a pending order needs a non-empty signal_id";
      return(false);
     }
   out.pending_signal_id=pending_signal_id;
   if(events==0)
     {
      out.status=TP_CANCEL_NO_EVENT;
      out.reason="NO_EVENT: no cancel event";
      return(false);
     }
   string names="";
   if((events & TP_EV_DIRECTION_CHANGE)!=0) {out.reasons[out.reason_count]="DIRECTION_CHANGE"; out.reason_count++;}
   if((events & TP_EV_OPPOSITE_SIGNAL)!=0) {out.reasons[out.reason_count]="OPPOSITE_SIGNAL"; out.reason_count++;}
   if((events & TP_EV_SESSION_END)!=0) {out.reasons[out.reason_count]="SESSION_END"; out.reason_count++;}
   if((events & TP_EV_NEWS_BLOCK)!=0) {out.reasons[out.reason_count]="NEWS_BLOCK"; out.reason_count++;}
   if((events & TP_EV_DAILY_LIMIT)!=0) {out.reasons[out.reason_count]="DAILY_LIMIT"; out.reason_count++;}
   for(int i=0;i<out.reason_count;i++)
      names+=(i>0 ? "," : "")+out.reasons[i];
   out.status=TP_CANCEL_REQUEST;
   out.reason="CANCEL_REQUEST: "+names;
   out.cancel_pending=true;
   return(true);
  }

string TP_CancelReasonsText(const STpCancel &c)
  {
   string s="";
   for(int i=0;i<c.reason_count;i++)
      s+=(i>0 ? "|" : "")+c.reasons[i];
   return(s);
  }

#endif
