// T011 restart flow: LOAD -> identity check -> snapshot -> ER_Reconcile -> SAVE, in one place. Mirrors tests/t011_flow_reference.py (its header documents the gates,
// their order and the limits in full). It COMPOSES the existing pieces and adds no state machine and no validation of its own: ExitStateFile / ExitStateCodec (load,
// identity check, record validation, save), ExitSnapshotAdapter (the read-only snapshot) and ExitReconciliation (the transition). It sends no order, produces NO request in
// any path, retries nothing and never invents an order map. The file is never proof of execution: DONE can only come from ER_Reconcile on a READY snapshot.
// Gates: unusable LOAD / other identity -> RECOVERY_REQUIRED before any read; stored BLOCKED -> BLOCKED; stored IDLE -> NOTHING_TO_RECONCILE; a request-bearing record without
// order tickets -> RECOVERY_REQUIRED (NO_MAP) before any read; only a READY adapter verdict reaches ER_Reconcile; the new state is saved with generation + 1 only when it
// changed, and a failed save is RECOVERY_REQUIRED with the state that IS on disk (never the unsaved one).
// LIMITS: not atomic with the broker nor guaranteed atomic on disk (tasks/T011-exit-persistence.md). The live terminal read (in.live) is UNVERIFIED and exercised only
// through fixtures; in.test_fail_save exists for tests only (it makes the save step fail without writing).
#ifndef VELO_EXIT_RESTART_FLOW_MQH
#define VELO_EXIT_RESTART_FLOW_MQH

#include "ExitStateFile.mqh"
#include "ExitSnapshotAdapter.mqh"

enum ENUM_ERF_FINAL
  {
   ERF_DONE=0,
   ERF_STILL_OPEN,
   ERF_BLOCKED,
   ERF_RECOVERY_REQUIRED,
   ERF_NOTHING_TO_RECONCILE
  };

struct SErfInput
  {
   bool live;                 // true = read the terminal (XA_ReadAndBuild); false = use raw_a / raw_b (fixtures)
   SXaRaw raw_a;
   SXaRaw raw_b;              // the second read of the stability check (identical to raw_a for a stable read)
   bool test_fail_save;       // TEST ONLY
  };

struct SErfResult
  {
   ENUM_ERF_FINAL final_state;
   string reason;
   bool snapshot_called;
   bool reconcile_called;
   bool save_needed;
   bool saved;
   string decision;
   string adapter_verdict;
   SEaState state;            // safe to use: reconciled and saved, or the state that is on disk
   int generation;            // the generation on disk after the flow
   bool request_produced;     // always false
  };

string ERF_FinalName(const ENUM_ERF_FINAL f)
  {
   switch(f)
     {
      case ERF_DONE: return("DONE");
      case ERF_STILL_OPEN: return("STILL_OPEN");
      case ERF_BLOCKED: return("BLOCKED");
      case ERF_RECOVERY_REQUIRED: return("RECOVERY_REQUIRED");
      case ERF_NOTHING_TO_RECONCILE: return("NOTHING_TO_RECONCILE");
     }
   return("UNKNOWN");
  }

void ERF_InputInit(SErfInput &in)
  {
   in.live=false;
   XA_RawInit(in.raw_a);
   XA_RawInit(in.raw_b);
   in.test_fail_save=false;
  }

void ERF_ResultInit(SErfResult &r)
  {
   r.final_state=ERF_RECOVERY_REQUIRED;
   r.reason="";
   r.snapshot_called=false;
   r.reconcile_called=false;
   r.save_needed=false;
   r.saved=false;
   r.decision="";
   r.adapter_verdict="";
   EA_StateInit(r.state);
   r.generation=0;
   r.request_produced=false;
  }

void ERF_FillRecord(SEsRecord &rec,const int generation,const SEsIdentity &id,const SEaState &st,const SEsRestore &o)
  {
   ESC_RecordInit(rec);
   rec.generation=generation;
   rec.id=id;
   rec.state=st;
   rec.send_phase=ESC_SEND_MAPPED;
   rec.map_complete=o.map_complete;
   rec.n_orders=o.n_orders;
   for(int i=0;i<o.n_orders;i++)
      rec.orders[i]=o.orders[i];
  }

string ERF_Text(const SErfResult &r)
  {
   return("final "+ERF_FinalName(r.final_state)+" | snapshot_called "+(string)r.snapshot_called+" adapter "+r.adapter_verdict+" | reconcile_called "+(string)r.reconcile_called+
          " decision "+r.decision+" | save_needed "+(string)r.save_needed+" saved "+(string)r.saved+" | state "+EA_StateName(r.state.status)+" confirmations "+
          IntegerToString(r.state.confirmations)+" | generation on disk "+IntegerToString(r.generation)+" | request_produced "+(string)r.request_produced+" | "+r.reason);
  }

// Returns true when the flow ended in DONE.
bool ERF_Run(const string name,const SEsIdentity &id,const SErfInput &in,SErfResult &res)
  {
   ERF_ResultInit(res);
   SEaState st;
   SEsRestore o;
   ESF_Load(name,id,st,o);
   res.state=st;
   res.generation=o.generation;
   // 1 LOAD (the identity check is part of the restore): unusable -> nothing is read or written
   if(o.generation==0)
     {
      res.reason="LOAD_UNUSABLE: "+o.reason;
      return(false);
     }
   // 2 stored BLOCKED / IDLE
   if(o.verdict==ESC_USABLE_BLOCKED)
     {
      res.final_state=ERF_BLOCKED;
      res.reason="BLOCKED restored as stored; nothing is read or written";
      return(false);
     }
   if(o.verdict==ESC_USABLE_IDLE)
     {
      res.final_state=ERF_NOTHING_TO_RECONCILE;
      res.reason="IDLE: there is no request to reconcile; no request is produced here";
      return(false);
     }
   // 3 the order map must exist before anything is read
   if(o.n_orders==0)
     {
      res.reason="NO_MAP: the record holds no order ticket; the snapshot is not read and no map is invented. "+o.reason;
      return(false);
     }
   SXaMap mp;
   XA_MapInit(mp,st.request_id,st.position_id,id.symbol,o.map_complete);
   for(int i=0;i<o.n_orders;i++)
      XA_MapAdd(mp,o.orders[i]);
   // 4 snapshot: only READY may continue
   SErSnapshot snap;
   SXaResult xr;
   if(in.live)
     {
      SXaRaw first;
      XA_ReadAndBuild(st,mp,snap,xr,first);
     }
   else
      XA_Build(st,mp,in.raw_a,XA_RawEqual(in.raw_a,in.raw_b),snap,xr);
   res.snapshot_called=true;
   res.adapter_verdict=XA_VerdictName(xr.verdict);
   if(xr.verdict==XA_UNKNOWN)
     {
      res.final_state=ERF_STILL_OPEN;
      res.reason="SNAPSHOT_UNKNOWN: "+xr.reason;
      return(false);
     }
   if(xr.verdict==XA_BLOCK)
     {
      res.final_state=ERF_BLOCKED;
      res.reason="SNAPSHOT_BLOCK: "+xr.reason;
      return(false);
     }
   // 5 reconcile (the same SEaState); the loaded state is kept as the disk truth
   SEaState disk;
   disk=st;
   SEsRecord before,after;
   ERF_FillRecord(before,o.generation,id,st,o);
   string text_before,text_after,why;
   bool ok_before=ESC_Encode(before,text_before,why);
   SErOutcome out;
   ER_Reconcile(st,snap,out);
   res.reconcile_called=true;
   res.decision=ER_DecisionName(out.decision);
   if(out.decision==ER_INVALID_INPUT)
     {
      res.state=disk;
      res.reason="RECONCILE_INVALID_INPUT: "+out.reason;
      return(false);
     }
   ERF_FillRecord(after,o.generation,id,st,o);
   bool ok_after=ESC_Encode(after,text_after,why);
   res.save_needed=!(ok_before && ok_after && text_before==text_after);
   // 6 SAVE with the next generation, only when the state changed
   if(res.save_needed)
     {
      if(!ok_after)
        {
         res.state=disk;
         res.reason="SAVE_FAILED: the reconciled state cannot be encoded ("+why+"); it was NOT persisted";
         return(false);
        }
      bool saved=false;
      string save_why="";
      if(in.test_fail_save)
         save_why="TEST_SAVE_FAILURE";
      else
         if(o.generation>=ESC_MAX_GEN)
            save_why="GENERATION_EXHAUSTED";
         else
           {
            SEsRecord next;
            ERF_FillRecord(next,o.generation+1,id,st,o);
            saved=ESF_Save(name,next,save_why);
           }
      if(!saved)
        {
         res.state=disk;
         res.reason="SAVE_FAILED: "+save_why+"; the reconciled state was NOT persisted";
         return(false);
        }
      res.saved=true;
      res.generation=o.generation+1;
     }
   res.state=st;
   res.final_state=(st.status==EA_ST_DONE ? ERF_DONE : (st.status==EA_ST_BLOCKED ? ERF_BLOCKED : ERF_STILL_OPEN));
   res.reason="RECONCILED: "+res.decision+(out.reason!="" ? " "+out.reason : "");
   return(res.final_state==ERF_DONE);
  }
#endif
