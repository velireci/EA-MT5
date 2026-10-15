// T011 pure reconciliation of the 2R partial-close request against a caller-supplied SNAPSHOT. Mirrors
// tests/t011_reconcile_reference.py (its header documents the decision order in full). NOT a trading module: no broker read, no order,
// no retry, no clock, no persistence, no restart guarantee. The snapshot is built by the caller.
//
// ONE SOURCE OF STATE: ER_Reconcile is a CONTROLLED TRANSITION on the SAME SEaState that ExitActivation.mqh owns; it returns a decision
// and applies the permitted transition only here: CONFIRMED -> DONE (the only way out of NEEDS_RECONCILIATION), PARTIAL -> NEEDS_RECONCILIATION,
// BLOCK -> BLOCKED, NOT_EXECUTED / UNKNOWN / INVALID_INPUT -> no change. It never produces a request and never changes the 80/20 plan.
// CONFIRMED needs executions_complete == true (a matching sum of volume does not make the list complete) and keeps confirmations at 1
// per request even when DONE is lost by a re-check and regained.
// Executed steps are recomputed from each snapshot (not accumulated); inside a snapshot an execution is identified by exec_id.
#ifndef VELO_EXIT_RECONCILIATION_MQH
#define VELO_EXIT_RECONCILIATION_MQH

#include "ExitActivation.mqh"

#define ER_MAX_EXEC 16

enum ENUM_ER_DECISION
  {
   ER_CONFIRMED=0,
   ER_PARTIAL,
   ER_NOT_EXECUTED,
   ER_UNKNOWN,
   ER_BLOCK,
   ER_INVALID_INPUT
  };

struct SErExec
  {
   string exec_id;
   string request_id;
   double volume;
  };

struct SErSnapshot
  {
   bool position_found;
   ulong position_id;
   string request_id;
   double volume_step;
   double volume_current;
   bool executions_complete;
   bool position_closed_proven;   // set by the adapter only when the history PROVES the position finished (never from the mere absence of the position)
   int n_exec;
   SErExec exec[ER_MAX_EXEC];
  };

struct SErOutcome
  {
   ENUM_ER_DECISION decision;
   string reason;
   long linked_steps;
   int duplicates;
   int unlinked;
   bool changed;
  };

string ER_DecisionName(const ENUM_ER_DECISION d)
  {
   switch(d)
     {
      case ER_CONFIRMED: return("CONFIRMED");
      case ER_PARTIAL: return("PARTIAL");
      case ER_NOT_EXECUTED: return("NOT_EXECUTED");
      case ER_UNKNOWN: return("UNKNOWN");
      case ER_BLOCK: return("BLOCK");
      case ER_INVALID_INPUT: return("INVALID_INPUT");
     }
   return("UNKNOWN_DECISION");
  }

void ER_SnapshotInit(SErSnapshot &s,const bool found,const ulong position_id,const string request_id,const double volume_step,
                     const double volume_current,const bool complete)
  {
   s.position_found=found;
   s.position_id=position_id;
   s.request_id=request_id;
   s.volume_step=volume_step;
   s.volume_current=volume_current;
   s.executions_complete=complete;
   s.position_closed_proven=false;
   s.n_exec=0;
   for(int i=0;i<ER_MAX_EXEC;i++)
     {
      s.exec[i].exec_id="";
      s.exec[i].request_id="";
      s.exec[i].volume=0.0;
     }
  }

// appends an execution; false when the list is full (the caller must then not call ER_Reconcile with a truncated list)
bool ER_AddExec(SErSnapshot &s,const string exec_id,const string request_id,const double volume)
  {
   if(s.n_exec>=ER_MAX_EXEC)
      return(false);
   s.exec[s.n_exec].exec_id=exec_id;
   s.exec[s.n_exec].request_id=request_id;
   s.exec[s.n_exec].volume=volume;
   s.n_exec++;
   return(true);
  }

void ER_Out(SErOutcome &o,const ENUM_ER_DECISION d,const string reason)
  {
   o.decision=d;
   o.reason=reason;
   o.linked_steps=0;
   o.duplicates=0;
   o.unlinked=0;
   o.changed=false;
  }

void ER_Block(SEaState &st,SErOutcome &o,const string reason,const long linked,const int dups,const int unl)
  {
   st.status=EA_ST_BLOCKED;
   st.reason=reason;
   ER_Out(o,ER_BLOCK,reason);
   o.linked_steps=linked;
   o.duplicates=dups;
   o.unlinked=unl;
   o.changed=true;
  }

// no permission to confirm: a DONE state loses its DONE, a partial fill goes to reconciliation, anything else keeps its status
void ER_NotDone(SEaState &st,SErOutcome &o,const bool done_before,const long linked,const string reason,const ENUM_ER_DECISION d,
                const int dups,const int unl)
  {
   ENUM_EA_STATE s0=st.status;
   long e0=st.executed_steps;
   if(done_before)
     {
      st.status=EA_ST_NEEDS_RECONCILIATION;
      st.reason=reason;
     }
   else
      if(d==ER_PARTIAL)
        {
         st.status=EA_ST_NEEDS_RECONCILIATION;
         st.executed_steps=linked;
         st.reason=reason;
        }
   ER_Out(o,d,reason);
   o.linked_steps=linked;
   o.duplicates=dups;
   o.unlinked=unl;
   o.changed=(s0!=st.status || e0!=st.executed_steps);
  }

// empty string when the snapshot is well formed, else the reason of INVALID_INPUT
string ER_Validate(const SErSnapshot &snap)
  {
   if(snap.position_closed_proven && snap.position_found)
      return("INVALID_SNAPSHOT: a position cannot be both found and proven closed");
   if(snap.position_id==0)
      return("INVALID_POSITION_ID: must be an integer > 0");
   if(snap.request_id=="")
      return("INVALID_REQUEST_ID: must be a non-empty string");
   if(!TG_Finite(snap.volume_step) || snap.volume_step<=0.0)
      return(StringFormat("INVALID_VOLUME_STEP: %.10g must be finite and > 0",snap.volume_step));
   if(!TG_Finite(snap.volume_current) || snap.volume_current<0.0 || (snap.position_found && snap.volume_current<=0.0))
      return(StringFormat("INVALID_VOLUME_CURRENT: %.10g must be finite and > 0 for a found position",snap.volume_current));
   if(snap.n_exec<0 || snap.n_exec>ER_MAX_EXEC)
      return(StringFormat("INVALID_EXECUTIONS: at most %d executions",ER_MAX_EXEC));
   for(int i=0;i<snap.n_exec;i++)
     {
      if(snap.exec[i].exec_id=="" || snap.exec[i].request_id=="")
         return("INVALID_EXECUTION: ids must be non-empty strings");
      if(!TG_Finite(snap.exec[i].volume) || snap.exec[i].volume<=0.0)
         return(StringFormat("INVALID_EXECUTION: volume %.10g must be finite and > 0",snap.exec[i].volume));
     }
   return("");
  }

// The ONLY answer for a position that is not open: an existing DONE (confirmations 1) whose linked executions still equal the request exactly, a complete list and a
// position the adapter PROVED closed from the history. Changes nothing, saves nothing, produces no request. false on any doubt (the caller then keeps POSITION_MISSING -> BLOCK).
bool ER_FinishedAfterDone(const SEaState &st,const SErSnapshot &snap,long &linked,int &dups,int &unl)
  {
   linked=0;
   dups=0;
   unl=0;
   if(st.status!=EA_ST_DONE || st.confirmations!=1 || !snap.position_closed_proven || !snap.executions_complete)
      return(false);
   for(int i=0;i<snap.n_exec;i++)
     {
      bool dup=false;
      for(int j=0;j<i;j++)
         if(snap.exec[j].exec_id==snap.exec[i].exec_id)
           {
            if(snap.exec[j].request_id!=snap.exec[i].request_id || snap.exec[j].volume!=snap.exec[i].volume)
               return(false);
            dup=true;
            break;
           }
      if(dup)
        {
         dups++;
         continue;
        }
      if(snap.exec[i].request_id!=st.request_id)
        {
         unl++;
         continue;
        }
      long k=PS_GridSteps(snap.exec[i].volume,st.volume_step);
      if(k<0)
         return(false);
      linked+=k;
     }
   return(linked==st.request_steps);
  }

// Judges the snapshot and applies the permitted transition to `st`. Returns true when the decision is CONFIRMED.
bool ER_Reconcile(SEaState &st,const SErSnapshot &snap,SErOutcome &o)
  {
   ER_Out(o,ER_UNKNOWN,"");
   string bad=ER_Validate(snap);
   if(bad!="")
     {
      ER_Out(o,ER_INVALID_INPUT,bad);
      return(false);
     }
   if(st.status==EA_ST_BLOCKED)
     {
      ER_Out(o,ER_BLOCK,"ALREADY_BLOCKED: "+st.reason);
      return(false);
     }
   if(!st.bound || st.request_id=="" || st.status==EA_ST_IDLE)
     {
      ER_Out(o,ER_UNKNOWN,"NO_REQUEST: there is no request to reconcile");
      return(false);
     }
   if(snap.position_id!=st.position_id)
     {
      ER_Block(st,o,StringFormat("WRONG_POSITION: snapshot position %I64u is not %I64u",snap.position_id,st.position_id),0,0,0);
      return(false);
     }
   if(snap.request_id!=st.request_id)
     {
      ER_Block(st,o,"WRONG_REQUEST_ID: snapshot request "+snap.request_id+" is not "+st.request_id,0,0,0);
      return(false);
     }
   if(snap.volume_step!=st.volume_step)
     {
      ER_Block(st,o,StringFormat("STEP_CHANGED: snapshot step %.10g is not the step %.10g of the request",snap.volume_step,st.volume_step),0,0,0);
      return(false);
     }
   if(!snap.position_found)
     {
      long fl=0;
      int fd=0,fu=0;
      if(ER_FinishedAfterDone(st,snap,fl,fd,fu))
        {
         ER_Out(o,ER_CONFIRMED,"ALREADY_DONE: POSITION_CLOSED_PROVEN_BY_HISTORY");
         o.linked_steps=fl;
         o.duplicates=fd;
         o.unlinked=fu;
         return(true);
        }
      ER_Block(st,o,"POSITION_MISSING: the position is not in the snapshot; DONE needs a matching position",0,0,0);
      return(false);
     }
   long linked=0;
   int dups=0,unl=0;
   for(int i=0;i<snap.n_exec;i++)
     {
      bool dup=false;
      for(int j=0;j<i;j++)
         if(snap.exec[j].exec_id==snap.exec[i].exec_id)
           {
            if(snap.exec[j].request_id==snap.exec[i].request_id && snap.exec[j].volume==snap.exec[i].volume)
              {
               dup=true;
               break;
              }
            ER_Block(st,o,"EXEC_ID_CONFLICT: execution "+snap.exec[i].exec_id+" appears with another request or volume",0,dups,unl);
            return(false);
           }
      if(dup)
        {
         dups++;
         continue;
        }
      if(snap.exec[i].request_id!=st.request_id)
        {
         unl++;
         continue;
        }
      long k=PS_GridSteps(snap.exec[i].volume,st.volume_step);
      if(k<0)
        {
         ER_Block(st,o,StringFormat("VOLUME_NOT_ON_GRID: execution %s volume %.10g is not a multiple of step %.10g",snap.exec[i].exec_id,snap.exec[i].volume,st.volume_step),0,dups,unl);
         return(false);
        }
      linked+=k;
     }
   long req=st.request_steps;
   if(linked>req)
     {
      ER_Block(st,o,StringFormat("OVERFILL: linked executions %I64d steps exceed the requested %I64d",linked,req),linked,dups,unl);
      return(false);
     }
   long cur=PS_GridSteps(snap.volume_current,st.volume_step);
   long expected=st.initial_steps-linked;
   bool complete=snap.executions_complete;
   bool done_before=(st.status==EA_ST_DONE);
   if(linked==req)
     {
      if(cur!=expected)
        {
         ER_Block(st,o,StringFormat("VOLUME_MISMATCH: position %.10g lot is not initial - requested (%I64d steps)",snap.volume_current,expected),linked,dups,unl);
         return(false);
        }
      if(!complete)
        {
         ER_NotDone(st,o,done_before,linked,"UNKNOWN: INCOMPLETE_EVIDENCE: the linked executions equal the request and the position matches, but the list is not declared complete (a sum of volume does not make it complete)",ER_UNKNOWN,dups,unl);
         return(false);
        }
      if(done_before)
        {
         ER_Out(o,ER_CONFIRMED,"ALREADY_DONE");
         o.linked_steps=linked;
         o.duplicates=dups;
         o.unlinked=unl;
         return(true);
        }
      st.status=EA_ST_DONE;
      st.executed_steps=linked;
      if(st.confirmations<1)                      // ONE confirmation per request, also when DONE was lost and is regained
         st.confirmations=1;
      st.reason="";
      ER_Out(o,ER_CONFIRMED,"");
      o.linked_steps=linked;
      o.duplicates=dups;
      o.unlinked=unl;
      o.changed=true;
      return(true);
     }
   if(linked>0 && cur==expected)
     {
      ER_NotDone(st,o,done_before,linked,StringFormat("PARTIAL_FILL: %I64d of %I64d steps executed; reconcile with the broker, no automatic retry",linked,req),ER_PARTIAL,dups,unl);
      return(false);
     }
   string what;
   if(linked>0)
      what=StringFormat("VOLUME_MISMATCH: position %.10g lot does not match %I64d linked steps",snap.volume_current,linked);
   else
      if(cur==st.initial_steps)
        {
         if(complete)
           {
            ER_NotDone(st,o,done_before,0,"NOT_EXECUTED: complete evidence shows no linked execution and an unchanged position",ER_NOT_EXECUTED,dups,unl);
            return(false);
           }
         what="INCOMPLETE_EVIDENCE: no linked execution seen, the list is not complete";
        }
      else
         what=StringFormat("VOLUME_CHANGED_WITHOUT_LINKED_EXECUTION: position %.10g lot, no linked execution (a volume drop alone proves nothing)",snap.volume_current);
   if(complete)
     {
      ER_Block(st,o,what,linked,dups,unl);
      return(false);
     }
   ER_NotDone(st,o,done_before,linked,"UNKNOWN: "+what,ER_UNKNOWN,dups,unl);
   return(false);
  }
#endif
