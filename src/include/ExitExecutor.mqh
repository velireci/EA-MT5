// T011 partial-close EXECUTOR: DETACHED (no signal, no trading-EA hook) and DISABLED by default. Mirrors tests/t011_executor_reference.py (its header documents the gates,
// the protocol and the limits in full). Protocol, existing modules only: request from ExitActivation (EA_OnQuote, the ONLY producer) -> INTENT saved by ExitStateFile and
// independently re-loaded -> AT MOST ONE transport Send per request -> order-ticket map saved -> ExitRestartFlow reconciles; DONE comes only from the reconciliation.
// EVERY UNCERTAINTY IS RECOVERY_REQUIRED, never a send or a resend: a save that returns false does NOT prove the old file is still on disk, so the position is latched in
// memory, nothing is sent (or nothing more), and the next ESF_Load decides after a restart. Returned-true from the transport is NOT a fill proof.
// The transport is the abstract seam of ExitTransport.mqh. This header never includes the real transport and has no trading call of its own except tr.Send(...).
// NOT PROTECTED: parallel writers (two instances / terminals on the same folder): there is no lock mechanism.
#ifndef VELO_EXIT_EXECUTOR_MQH
#define VELO_EXIT_EXECUTOR_MQH

#include "ExitStateFile.mqh"
#include "ExitRestartFlow.mqh"
#include "ExitTransport.mqh"

#define EX_AUTH_PHRASE "I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE"

enum ENUM_EX_FILLING
  {
   EX_FILL_UNSET=0,
   EX_FILL_FOK,
   EX_FILL_IOC,
   EX_FILL_RETURN
  };

enum ENUM_EX_FILTER_POLICY
  {
   EX_POL_UNSET=0,
   EX_POL_IGNORE,
   EX_POL_NEEDS_CLEAR
  };

enum ENUM_EX_FILTER_STATE
  {
   EX_FS_UNKNOWN=0,
   EX_FS_CLEAR,
   EX_FS_BLOCKED
  };

enum ENUM_EX_SAVE_FAULT
  {
   EX_SAVE_NONE=0,
   EX_SAVE_BEFORE,            // TEST ONLY: the save returns false without writing
   EX_SAVE_AFTER              // TEST ONLY: the save really happens and still returns false (the move happened, the read-back "failed")
  };

enum ENUM_EX_FINAL
  {
   EX_BLOCKED=0,
   EX_RECOVERY_REQUIRED,
   EX_NOT_IDLE,
   EX_NO_REQUEST,
   EX_SENT_MAPPED
  };

struct SExConfig
  {
   bool enabled;                       // default false
   bool real_authorised;               // default false
   string authorisation;               // must equal EX_AUTH_PHRASE for a real transport
   long ea_magic;                      // > 0, mandatory
   ENUM_EX_FILLING filling;            // mandatory, UNSET blocks
   long deviation;                     // mandatory, -1 = UNSET blocks
   ENUM_EX_FILTER_POLICY filter_policy;   // mandatory, UNSET blocks
   ENUM_EX_FILTER_STATE filter_state;     // supplied by the caller
   bool tp_set;
   double tp_price;
   ENUM_EX_SAVE_FAULT test_save_fault;    // TEST ONLY
   int test_fault_save_no;                // TEST ONLY: 1 = the INTENT save, 2 = the MAP save
  };

struct SExQuote
  {
   int direction;                      // 1 = BUY position, -1 = SELL position
   double level_2r;
   double bid;
   double ask;
   double volume_initial;
  };

struct SExRuntime
  {
   bool latched;
   int send_calls;
   int save_calls;
  };

struct SExResult
  {
   ENUM_EX_FINAL final_state;
   string reason;
   int sends;
   ulong order_ticket;
  };

string EX_FinalName(const ENUM_EX_FINAL f)
  {
   switch(f)
     {
      case EX_BLOCKED: return("BLOCKED");
      case EX_RECOVERY_REQUIRED: return("RECOVERY_REQUIRED");
      case EX_NOT_IDLE: return("NOT_IDLE");
      case EX_NO_REQUEST: return("NO_REQUEST");
      case EX_SENT_MAPPED: return("SENT_MAPPED");
     }
   return("UNKNOWN");
  }

void EX_ConfigInit(SExConfig &c)
  {
   c.enabled=false;
   c.real_authorised=false;
   c.authorisation="";
   c.ea_magic=0;
   c.filling=EX_FILL_UNSET;
   c.deviation=-1;
   c.filter_policy=EX_POL_UNSET;
   c.filter_state=EX_FS_UNKNOWN;
   c.tp_set=false;
   c.tp_price=0.0;
   c.test_save_fault=EX_SAVE_NONE;
   c.test_fault_save_no=0;
  }

void EX_RuntimeInit(SExRuntime &rt)
  {
   rt.latched=false;
   rt.send_calls=0;
   rt.save_calls=0;
  }

bool EX_OnGrid(const double x,const double tick)
  {
   double r=x/tick;
   return(MathAbs(r-MathRound(r))<=1e-6*MathMax(1.0,MathAbs(r)));
  }

// test hook aside, exactly ESF_Save: false does not mean "nothing was written"
bool EX_Save(const SExConfig &cfg,SExRuntime &rt,const string name,const SEsRecord &rec,string &reason)
  {
   rt.save_calls++;
   if(cfg.test_save_fault!=EX_SAVE_NONE && cfg.test_fault_save_no==rt.save_calls)
     {
      if(cfg.test_save_fault==EX_SAVE_AFTER)
        {
         string w;
         ESF_Save(name,rec,w);
        }
      reason="TEST_SAVE_FAULT";
      return(false);
     }
   return(ESF_Save(name,rec,reason));
  }

// Returns true only for SENT_MAPPED.
bool EX_Process(const SExConfig &cfg,CExitTransport *tr,SExRuntime &rt,const string name,const SEsIdentity &id,const SExQuote &q,SExResult &res)
  {
   res.final_state=EX_BLOCKED;
   res.reason="";
   res.sends=0;
   res.order_ticket=0;
   if(!cfg.enabled) {res.reason="DISABLED: the executor is off by default"; return(false);}
   if(cfg.ea_magic<=0) {res.reason="INPUT_UNSET: ea_magic"; return(false);}
   if(cfg.filling==EX_FILL_UNSET) {res.reason="INPUT_UNSET: filling"; return(false);}
   if(cfg.deviation<0) {res.reason="INPUT_UNSET: deviation"; return(false);}
   if(cfg.filter_policy==EX_POL_UNSET) {res.reason="INPUT_UNSET: exit_filter_policy"; return(false);}
   if(cfg.filter_policy==EX_POL_NEEDS_CLEAR && cfg.filter_state!=EX_FS_CLEAR) {res.reason="EXIT_FILTERS_NOT_CLEAR"; return(false);}
   if(!cfg.tp_set) {res.reason="TP_UNKNOWN"; return(false);}
   if(rt.latched) {res.reason="LATCHED: an earlier uncertainty on this executor; restart and recover first"; return(false);}
   if(rt.send_calls>=1) {res.reason="DUPLICATE_CALL: a send was already made by this executor instance"; return(false);}
   SExAccount acct;
   tr.ReadAccount(acct);
   if(tr.IsReal())
     {
      if(!(cfg.real_authorised && cfg.authorisation==EX_AUTH_PHRASE)) {res.reason="REAL_NOT_AUTHORISED"; return(false);}
      if(!acct.read_ok || !acct.demo) {res.reason="REAL_REQUIRES_DEMO_ACCOUNT"; return(false);}
     }
   if(!acct.read_ok) {res.reason="ACCOUNT_UNREADABLE"; return(false);}
   if(acct.login!=id.login || acct.server!=id.server) {res.reason="ACCOUNT_IDENTITY_MISMATCH"; return(false);}
   if(!acct.trade_allowed) {res.reason="TRADING_NOT_ALLOWED"; return(false);}
   if(acct.margin_mode!=2) {res.reason="UNSUPPORTED_ACCOUNT_MODE: only HEDGING"; return(false);}
   SExSymbol sym;
   tr.ReadSymbol(id.symbol,sym);
   if(!sym.read_ok || !sym.close_allowed || sym.tick_size<=0.0) {res.reason="SYMBOL_UNREADABLE_OR_NOT_TRADABLE"; return(false);}
   if(!EX_OnGrid(q.level_2r,sym.tick_size)) {res.reason="PLAN_NOT_ON_SYMBOL_GRID: level_2R is refused, not rounded"; return(false);}
   if(!EX_OnGrid(cfg.tp_price,sym.tick_size)) {res.reason="PLAN_NOT_ON_SYMBOL_GRID: TP is refused, not rounded"; return(false);}
   if(MathAbs(cfg.tp_price-q.level_2r)<sym.tick_size/2.0) {res.reason="TP_EQUALS_2R: the interaction is an open decision"; return(false);}
   if((q.direction==1 && cfg.tp_price<q.level_2r) || (q.direction==-1 && cfg.tp_price>q.level_2r)) {res.reason="TP_BEFORE_2R: inconsistent with the minimum of 2R"; return(false);}
   SExPosition pos;
   tr.FindPosition(id.position_id,pos);
   if(!pos.found || pos.ticket==0 || pos.identifier!=id.position_id) {res.reason="POSITION_NOT_FOUND"; return(false);}
   if(pos.symbol!=id.symbol || pos.magic!=cfg.ea_magic || pos.type!=(q.direction==1 ? 0 : 1))
     {
      res.reason="OWNERSHIP_NOT_PROVEN: symbol, magic or direction differ from the record / configuration";
      return(false);
     }
   SEaState st;
   SEsRestore o;
   ESF_Load(name,id,st,o);
   if(o.generation==0)
     {
      res.final_state=EX_RECOVERY_REQUIRED;
      res.reason="LOAD_UNUSABLE: "+o.reason;
      return(false);
     }
   if(o.verdict!=ESC_USABLE_IDLE)
     {
      res.final_state=EX_NOT_IDLE;
      res.reason="The record is not IDLE ("+ESC_VerdictName(o.verdict)+"): no send; use the restart flow";
      return(false);
     }
   SEaResult r;
   bool request=EA_OnQuote(st,id.position_id,q.direction,q.level_2r,q.bid,q.ask,q.volume_initial,pos.volume,sym.vol_min,sym.vol_step,sym.vol_max,r);
   if(!request)
     {
      if(r.event==EA_EV_OK)
        {
         res.final_state=EX_NO_REQUEST;
         res.reason="the 2R level is not reached";
         return(false);
        }
      res.reason=EA_EventName(r.event)+": "+r.reason;
      return(false);
     }
   SExSendRequest req;
   req.action=EX_ACTION_DEAL;
   req.symbol=id.symbol;
   req.volume=r.request_volume;
   req.type=(q.direction==1 ? 1 : 0);
   req.position=pos.ticket;
   req.magic=cfg.ea_magic;
   req.deviation=cfg.deviation;
   req.filling=(int)cfg.filling;
   req.price=(q.direction==1 ? q.bid : q.ask);
   req.comment=r.request_id;
   if(!tr.PreCheck(req)) {res.reason="PRECHECK_FAILED: nothing persisted, nothing sent"; return(false);}
   int gen=o.generation+1;
   SEsRecord rec;
   ESC_RecordInit(rec);
   rec.generation=gen;
   rec.id=id;
   rec.state=st;
   rec.send_phase=ESC_SEND_INTENT;
   string why;
   if(!EX_Save(cfg,rt,name,rec,why))
     {
      rt.latched=true;
      res.final_state=EX_RECOVERY_REQUIRED;
      res.reason="INTENT_SAVE_FAILED: "+why+"; the file may or may not hold the new record; nothing is sent";
      return(false);
     }
   SEaState st2;
   SEsRestore o2;
   ESF_Load(name,id,st2,o2);
   if(!(o2.verdict==ESC_RECOVERY_REQUIRED && o2.generation==gen && o2.n_orders==0 && st2.request_id==st.request_id && StringFind(o2.reason,"SEND_UNCERTAIN")>=0))
     {
      rt.latched=true;
      res.final_state=EX_RECOVERY_REQUIRED;
      res.reason="INTENT_NOT_VERIFIED: the re-load does not show the saved intent; nothing is sent";
      return(false);
     }
   if(rt.send_calls>=1)
     {
      rt.latched=true;
      res.final_state=EX_RECOVERY_REQUIRED;
      res.reason="DUPLICATE_CALL_GUARD: unreachable unless the gates above were bypassed; nothing more is sent";
      return(false);
     }
   rt.send_calls++;
   SExSendResult sr;
   tr.Send(req,sr);
   res.sends=rt.send_calls;
   bool accepted=(sr.returned_true && sr.have_result && (sr.retcode==10008 || sr.retcode==10009 || sr.retcode==10010) && sr.order>0);
   if(!accepted)
     {
      rt.latched=true;
      res.final_state=EX_RECOVERY_REQUIRED;
      res.reason=StringFormat("SEND_UNCERTAIN: returned_true=%d result=%d retcode=%d order=%I64u; no retry, no resend, the intent stays on disk",(int)sr.returned_true,(int)sr.have_result,sr.retcode,sr.order);
      return(false);
     }
   res.order_ticket=sr.order;
   SEsRecord mapped;
   ESC_RecordInit(mapped);
   mapped.generation=gen+1;
   mapped.id=id;
   mapped.state=st;
   mapped.send_phase=ESC_SEND_MAPPED;
   mapped.map_complete=true;
   mapped.n_orders=1;
   mapped.orders[0]=sr.order;
   if(!EX_Save(cfg,rt,name,mapped,why))
     {
      rt.latched=true;
      res.final_state=EX_RECOVERY_REQUIRED;
      res.reason=StringFormat("MAP_NOT_SAVED: %s; order ticket %I64u must be recorded by hand; the intent (or the map) is what the next load shows",why,sr.order);
      return(false);
     }
   res.final_state=EX_SENT_MAPPED;
   res.reason=StringFormat("sent once; order %I64u mapped; run the restart flow to reconcile (returned true is not a fill proof)",sr.order);
   return(true);
  }

// DONE only from the existing flow (read-only on the terminal for the real transport; fixtures otherwise)
bool EX_Reconcile(const string name,const SEsIdentity &id,CExitTransport *tr,const SXaRaw &raw_a,const SXaRaw &raw_b,SErfResult &res)
  {
   SErfInput in;
   ERF_InputInit(in);
   in.live=tr.IsReal();
   in.raw_a=raw_a;
   in.raw_b=raw_b;
   return(ERF_Run(name,id,in,res));
  }
#endif
