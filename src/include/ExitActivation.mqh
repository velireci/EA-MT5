// T011 pure 2R partial-close activation state machine. Mirrors tests/t011_activation_reference.py (its header documents every
// transition in full). NOT a trading module: no order, no trading API, no account/symbol read, no clock, no persistence, no
// retry. Every number is an argument; the state (SEaState) is an in-memory object OWNED BY THE CALLER: no guarantee after a
// restart, not atomic, not shared. Not wired to any EA. No BE, costs or trailing.
//
// Client statement (STRATEGY_SPEC section 8): at 2R close 80% of the INITIAL volume. Technical convention (for review, not a client
// rule): BUY reaches 2R when Bid >= level_2R, SELL when Ask <= level_2R; level_2R is supplied (T005 partial_price).
// The split is ES_Split (ExitSplit.mqh, which reuses PS_GridSteps of T006): NOT copied here.
// States: IDLE -> REQUEST_PENDING -> DONE; NEEDS_RECONCILIATION (rejected, timeout, partial execution, volume mismatch) and
// BLOCKED (wrong id/volume, identity change, report without request) are stop states: every later event changes nothing.
#ifndef VELO_EXIT_ACTIVATION_MQH
#define VELO_EXIT_ACTIVATION_MQH

#include "ExitSplit.mqh"

enum ENUM_EA_STATE
  {
   EA_ST_IDLE=0,
   EA_ST_REQUEST_PENDING,
   EA_ST_DONE,
   EA_ST_NEEDS_RECONCILIATION,
   EA_ST_BLOCKED
  };

enum ENUM_EA_EVENT
  {
   EA_EV_OK=0,
   EA_EV_INVALID_INPUT,
   EA_EV_SPLIT_POLICY_UNSET,
   EA_EV_IGNORED,
   EA_EV_DUPLICATE_IGNORED,
   EA_EV_RECONCILE_REQUIRED,
   EA_EV_BLOCKED
  };

enum ENUM_EA_ACTION
  {
   EA_ACT_NONE=0,
   EA_ACT_REQUEST_PARTIAL_CLOSE
  };

enum ENUM_EA_REPORT
  {
   EA_REP_FULL=0,
   EA_REP_PARTIAL,
   EA_REP_REJECTED,
   EA_REP_TIMEOUT
  };

struct SEaState
  {
   ENUM_EA_STATE status;
   bool bound;
   ulong position_id;
   int direction;
   double level;
   double volume_initial;
   double volume_step;           // the grid of the request: reports, duplicates and the remainder check use THIS step
   string request_id;
   long request_steps;
   double close_volume;
   long initial_steps;
   long executed_steps;
   int confirmations;
   int duplicates_ignored;
   string reason;
  };

struct SEaResult
  {
   ENUM_EA_EVENT event;
   ENUM_EA_ACTION action;
   string reason;
   string request_id;
   double request_volume;
   long request_steps;
  };

string EA_StateName(const ENUM_EA_STATE s)
  {
   switch(s)
     {
      case EA_ST_IDLE: return("IDLE");
      case EA_ST_REQUEST_PENDING: return("REQUEST_PENDING");
      case EA_ST_DONE: return("DONE");
      case EA_ST_NEEDS_RECONCILIATION: return("NEEDS_RECONCILIATION");
      case EA_ST_BLOCKED: return("BLOCKED");
     }
   return("UNKNOWN");
  }

string EA_EventName(const ENUM_EA_EVENT e)
  {
   switch(e)
     {
      case EA_EV_OK: return("OK");
      case EA_EV_INVALID_INPUT: return("INVALID_INPUT");
      case EA_EV_SPLIT_POLICY_UNSET: return("SPLIT_POLICY_UNSET");
      case EA_EV_IGNORED: return("IGNORED");
      case EA_EV_DUPLICATE_IGNORED: return("DUPLICATE_IGNORED");
      case EA_EV_RECONCILE_REQUIRED: return("RECONCILE_REQUIRED");
      case EA_EV_BLOCKED: return("BLOCKED");
     }
   return("UNKNOWN");
  }

string EA_ActionName(const ENUM_EA_ACTION a) {return(a==EA_ACT_REQUEST_PARTIAL_CLOSE ? "REQUEST_PARTIAL_CLOSE" : "NONE");}

string EA_RequestId(const ulong position_id) {return(StringFormat("X2R80-%I64u",position_id));}

void EA_StateInit(SEaState &s)
  {
   s.status=EA_ST_IDLE;
   s.bound=false;
   s.position_id=0;
   s.direction=0;
   s.level=0.0;
   s.volume_initial=0.0;
   s.volume_step=0.0;
   s.request_id="";
   s.request_steps=0;
   s.close_volume=0.0;
   s.initial_steps=0;
   s.executed_steps=0;
   s.confirmations=0;
   s.duplicates_ignored=0;
   s.reason="";
  }

void EA_ResultInit(SEaResult &r,const ENUM_EA_EVENT ev,const string reason)
  {
   r.event=ev;
   r.action=EA_ACT_NONE;
   r.reason=reason;
   r.request_id="";
   r.request_volume=0.0;
   r.request_steps=0;
  }

// sets the state reason and fills the result in one place (state changes happen at the call site, before this)
void EA_Set(SEaState &s,SEaResult &r,const ENUM_EA_EVENT ev,const string reason)
  {
   s.reason=reason;
   EA_ResultInit(r,ev,reason);
  }

bool EA_PositiveFinite(const double x) {return(TG_Finite(x) && x>0.0);}

void EA_DoneQuote(SEaState &s,const double volume_current,const double volume_step,SEaResult &r)
  {
   if(volume_step!=s.volume_step)
     {
      s.status=EA_ST_NEEDS_RECONCILIATION;
      EA_Set(s,r,EA_EV_RECONCILE_REQUIRED,StringFormat("STEP_CHANGED: volume step %.10g is not the step %.10g of the request; reconcile with the broker",volume_step,s.volume_step));
      return;
     }
   long cur=PS_GridSteps(volume_current,volume_step);
   long expected=s.initial_steps-s.request_steps;
   if(cur!=expected)
     {
      s.status=EA_ST_NEEDS_RECONCILIATION;
      EA_Set(s,r,EA_EV_RECONCILE_REQUIRED,StringFormat("VOLUME_MISMATCH_AFTER_DONE: actual volume %.10g is not the expected remainder (%I64d steps)",volume_current,expected));
      return;
     }
   EA_ResultInit(r,EA_EV_IGNORED,"IGNORED: partial close is DONE");
  }

// One quote. Returns true when a request to close the partial volume was produced (result.action).
bool EA_OnQuote(SEaState &s,const ulong position_id,const int direction,const double level_2r,const double bid,const double ask,
                const double volume_initial,const double volume_current,const double volume_min,const double volume_step,
                const double volume_max,SEaResult &r)
  {
   EA_ResultInit(r,EA_EV_OK,"");
   // 1 input validation: nothing changes
   if(position_id==0)
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,"INVALID_POSITION_ID: must be an integer > 0");
      return(false);
     }
   if(direction!=1 && direction!=-1)
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,"INVALID_DIRECTION: must be BUY (1) or SELL (-1)");
      return(false);
     }
   if(!EA_PositiveFinite(level_2r))
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,StringFormat("INVALID_LEVEL: %.10g must be finite and > 0",level_2r));
      return(false);
     }
   if(!EA_PositiveFinite(bid))
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,StringFormat("INVALID_BID: %.10g must be finite and > 0",bid));
      return(false);
     }
   if(!EA_PositiveFinite(ask))
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,StringFormat("INVALID_ASK: %.10g must be finite and > 0",ask));
      return(false);
     }
   if(ask<bid)
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,StringFormat("INVALID_QUOTE: ask %.10g < bid %.10g",ask,bid));
      return(false);
     }
   if(!EA_PositiveFinite(volume_initial))
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,StringFormat("INVALID_VOLUME_INITIAL: %.10g must be finite and > 0",volume_initial));
      return(false);
     }
   if(!EA_PositiveFinite(volume_current))
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,StringFormat("INVALID_VOLUME_CURRENT: %.10g must be finite and > 0",volume_current));
      return(false);
     }
   // 1b the volume parameters are validated on EVERY quote (ExitSplit), BEFORE anything is bound or changed
   SEsResult sp;
   ES_Split(volume_initial,volume_min,volume_step,volume_max,sp);
   if(sp.status==ES_INVALID_INPUT)
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,"SPLIT_"+sp.reason);
      return(false);
     }
   // 2 stop states change nothing
   if(s.status==EA_ST_NEEDS_RECONCILIATION)
     {
      EA_ResultInit(r,EA_EV_RECONCILE_REQUIRED,"RECONCILE_REQUIRED: "+s.reason);
      return(false);
     }
   if(s.status==EA_ST_BLOCKED)
     {
      EA_ResultInit(r,EA_EV_BLOCKED,"BLOCKED: "+s.reason);
      return(false);
     }
   // 3 identity: the first valid quote binds position, direction, level and initial volume
   if(!s.bound)
     {
      s.bound=true;
      s.position_id=position_id;
      s.direction=direction;
      s.level=level_2r;
      s.volume_initial=volume_initial;
      s.request_id="";
     }
   else
      if(s.position_id!=position_id || s.direction!=direction || s.level!=level_2r || s.volume_initial!=volume_initial)
        {
         s.status=EA_ST_BLOCKED;
         EA_Set(s,r,EA_EV_BLOCKED,"IDENTITY_CHANGED: position, direction, level_2R or initial volume differs from the bound values");
         return(false);
        }
   // 4 pending: quotes are ignored
   if(s.status==EA_ST_REQUEST_PENDING)
     {
      EA_ResultInit(r,EA_EV_IGNORED,"IGNORED: request "+s.request_id+" is pending");
      return(false);
     }
   if(s.status==EA_ST_DONE)
     {
      EA_DoneQuote(s,volume_current,volume_step,r);
      return(false);
     }
   // 5 IDLE
   bool reached=(direction==1 ? bid>=level_2r : ask<=level_2r);
   if(!reached)
      return(false);
   if(sp.status==ES_SPLIT_POLICY_UNSET)
     {
      EA_ResultInit(r,EA_EV_SPLIT_POLICY_UNSET,sp.reason);
      return(false);
     }
   long cur=PS_GridSteps(volume_current,volume_step);
   if(cur!=sp.initial_steps)
     {
      s.status=EA_ST_NEEDS_RECONCILIATION;
      EA_Set(s,r,EA_EV_RECONCILE_REQUIRED,StringFormat("VOLUME_MISMATCH_BEFORE_REQUEST: actual volume %.10g is not the initial volume %.10g (%I64d steps); the plan is not changed",
                                                       volume_current,volume_initial,sp.initial_steps));
      return(false);
     }
   s.status=EA_ST_REQUEST_PENDING;
   s.request_id=EA_RequestId(position_id);
   s.request_steps=sp.close_steps;
   s.initial_steps=sp.initial_steps;
   s.close_volume=sp.close_volume;
   s.volume_step=volume_step;
   s.reason="";
   EA_ResultInit(r,EA_EV_OK,"");
   r.action=EA_ACT_REQUEST_PARTIAL_CLOSE;
   r.request_id=s.request_id;
   r.request_volume=sp.close_volume;
   r.request_steps=sp.close_steps;
   return(true);
  }

// One execution report supplied by the caller. Returns true when the report was accepted as the (first) full confirmation.
bool EA_OnReport(SEaState &s,const string request_id,const ENUM_EA_REPORT kind,const double executed_volume,const double volume_step,SEaResult &r)
  {
   EA_ResultInit(r,EA_EV_OK,"");
   if(request_id=="")
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,"INVALID_REQUEST_ID: must be a non-empty string");
      return(false);
     }
   if((int)kind<(int)EA_REP_FULL || (int)kind>(int)EA_REP_TIMEOUT)
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,"INVALID_REPORT_KIND");
      return(false);
     }
   if(!TG_Finite(executed_volume) || executed_volume<0.0)
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,StringFormat("INVALID_EXECUTED_VOLUME: %.10g must be finite and >= 0",executed_volume));
      return(false);
     }
   if(!EA_PositiveFinite(volume_step))
     {
      EA_ResultInit(r,EA_EV_INVALID_INPUT,StringFormat("INVALID_VOLUME_STEP: %.10g must be finite and > 0",volume_step));
      return(false);
     }
   if(s.status==EA_ST_NEEDS_RECONCILIATION)
     {
      EA_ResultInit(r,EA_EV_RECONCILE_REQUIRED,"RECONCILE_REQUIRED: "+s.reason);
      return(false);
     }
   if(s.status==EA_ST_BLOCKED)
     {
      EA_ResultInit(r,EA_EV_BLOCKED,"BLOCKED: "+s.reason);
      return(false);
     }
   if(s.status==EA_ST_IDLE)
     {
      s.status=EA_ST_BLOCKED;
      EA_Set(s,r,EA_EV_BLOCKED,"REPORT_WITHOUT_REQUEST: no request exists for "+request_id);
      return(false);
     }
   if(request_id!=s.request_id)
     {
      s.status=EA_ST_BLOCKED;
      EA_Set(s,r,EA_EV_BLOCKED,"WRONG_REQUEST_ID: "+request_id+" is not "+s.request_id);
      return(false);
     }
   if(volume_step!=s.volume_step)
     {
      s.status=EA_ST_BLOCKED;
      EA_Set(s,r,EA_EV_BLOCKED,StringFormat("STEP_CHANGED: report step %.10g is not the step %.10g of the request; the volume is not compared on another grid",volume_step,s.volume_step));
      return(false);
     }
   long steps=0;
   if(executed_volume>0.0)
      steps=PS_GridSteps(executed_volume,s.volume_step);
   if(steps<0)
     {
      s.status=EA_ST_BLOCKED;
      EA_Set(s,r,EA_EV_BLOCKED,StringFormat("VOLUME_NOT_ON_GRID: executed volume %.10g is not a multiple of step %.10g",executed_volume,volume_step));
      return(false);
     }
   if(s.status==EA_ST_DONE)
     {
      if(kind==EA_REP_FULL && steps==s.request_steps)
        {
         s.duplicates_ignored++;
         EA_ResultInit(r,EA_EV_DUPLICATE_IGNORED,"DUPLICATE_IGNORED: confirmation already counted");
         return(false);
        }
      s.status=EA_ST_BLOCKED;
      EA_Set(s,r,EA_EV_BLOCKED,"CONFLICTING_REPORT_AFTER_DONE");
      return(false);
     }
   // REQUEST_PENDING
   if(kind==EA_REP_FULL)
     {
      if(steps!=s.request_steps)
        {
         s.status=EA_ST_BLOCKED;
         EA_Set(s,r,EA_EV_BLOCKED,StringFormat("VOLUME_MISMATCH: FULL confirmation of %I64d steps, requested %I64d",steps,s.request_steps));
         return(false);
        }
      s.status=EA_ST_DONE;
      s.executed_steps=steps;
      if(s.confirmations<1)                       // ONE confirmation per request
         s.confirmations=1;
      s.reason="";
      EA_ResultInit(r,EA_EV_OK,"");
      return(true);
     }
   if(kind==EA_REP_PARTIAL)
     {
      if(!(steps>0 && steps<s.request_steps))
        {
         s.status=EA_ST_BLOCKED;
         EA_Set(s,r,EA_EV_BLOCKED,StringFormat("VOLUME_MISMATCH: PARTIAL execution of %I64d steps is outside (0, %I64d)",steps,s.request_steps));
         return(false);
        }
      s.status=EA_ST_NEEDS_RECONCILIATION;
      s.executed_steps=steps;
      EA_Set(s,r,EA_EV_RECONCILE_REQUIRED,StringFormat("PARTIAL_EXECUTION: %I64d of %I64d steps executed; reconcile with the broker, no automatic retry",steps,s.request_steps));
      return(false);
     }
   s.status=EA_ST_NEEDS_RECONCILIATION;
   EA_Set(s,r,EA_EV_RECONCILE_REQUIRED,StringFormat("%s: request %s not confirmed; reconcile with the broker, no automatic retry",
                                                    (kind==EA_REP_REJECTED ? "REJECTED" : "TIMEOUT"),s.request_id));
   return(false);
  }
#endif
