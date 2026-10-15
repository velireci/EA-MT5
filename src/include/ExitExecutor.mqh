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
#include "TradeGeometry.mqh"

#define EX_AUTH_PHRASE "I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE"

enum ENUM_EX_FILLING
  {
   EX_FILL_UNSET=0,
   EX_FILL_FOK,
   EX_FILL_IOC,
   EX_FILL_RETURN
  };

enum ENUM_EX_R_POLICY
  {
   EX_RPOL_UNSET=0,           // blocks everywhere
   EX_RPOL_TYPED,             // the diagnostic typed level of the demo harness (no E / S basis)
   EX_RPOL_R_GEOM             // R_GEOM: level 2R = TG_Compute over the open price (read once) and the INITIAL SL asserted by the owner; not the client's final R (costs open, C3/C4)
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
   EX_SENT_MAPPED,
   EX_REGISTERED
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
   ENUM_EX_R_POLICY r_policy;             // mandatory, UNSET blocks
   bool sl_initial_set;                   // R_GEOM: the initial stop ASSERTED by the owner (variant (a)): accepted at registration only while the live SL equals it
   double sl_initial;
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
      case EX_REGISTERED: return("REGISTERED");
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
   c.r_policy=EX_RPOL_UNSET;
   c.sl_initial_set=false;
   c.sl_initial=0.0;
  }

void EX_RuntimeInit(SExRuntime &rt)
  {
   rt.latched=false;
   rt.send_calls=0;
   rt.save_calls=0;
  }

bool EX_Finite(const double x) {return(x==x && x-x==0.0);}

// Exactly on the tick grid up to FLOATING-POINT NOISE only (eight machine epsilons relative to the number of ticks). A real difference such as 0.004 with a tick of 0.01
// is refused. Non-finite or non-positive inputs are never on the grid.
bool EX_OnGrid(const double x,const double tick)
  {
   if(!EX_Finite(x) || !EX_Finite(tick) || x<=0.0 || tick<=0.0) return(false);
   double r=x/tick;
   if(!EX_Finite(r) || MathAbs(r)>1e12) return(false);
   return(MathAbs(r-MathRound(r))<=8.0*DBL_EPSILON*MathMax(1.0,MathAbs(r)));
  }

// The ONLY place where the 2R level is derived: TG_Compute over E and S (no 2R arithmetic in this module). stops_level 0: the stops check judges an order, not a risk basis.
bool EX_Geometry(const SExSymbol &sym,const int direction,const double e,const double s,const double tp,STgResult &out)
  {
   return(TG_Compute(direction==1 ? TG_BUY : TG_SELL,e,s,true,tp,sym.tick_size,sym.digits,sym.point,0,false,0.0,0.0,out));
  }

// the grid / representation / TP-versus-2R checks of a plan whose level is already known (identical for the typed and the R_GEOM level); "" = acceptable
string EX_PlanRefusal(const double level,const SExConfig &cfg,const SExSymbol &sym,const int direction,const bool with_volume,const double volume)
  {
   string exact;
   if(!EX_OnGrid(level,sym.tick_size)) return("PLAN_NOT_ON_SYMBOL_GRID: level_2R is refused, not rounded");
   if(!EX_OnGrid(cfg.tp_price,sym.tick_size)) return("PLAN_NOT_ON_SYMBOL_GRID: TP is refused, not rounded");
   if(!ESC_Fnum(level,exact) || !ESC_Fnum(cfg.tp_price,exact) || (with_volume && !ESC_Fnum(volume,exact)))
      return("PLAN_NOT_REPRESENTABLE_IN_RECORD: level_2R, TP or the initial volume does not round-trip through 12 decimals; nothing is rounded or persisted");
   if(MathAbs(cfg.tp_price-level)<sym.tick_size/2.0) return("TP_EQUALS_2R: the interaction is an open decision");
   if((direction==1 && cfg.tp_price<level) || (direction==-1 && cfg.tp_price>level)) return("TP_BEFORE_2R: inconsistent with the minimum of 2R");
   return("");
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
   if((int)cfg.filling<(int)EX_FILL_UNSET || (int)cfg.filling>(int)EX_FILL_RETURN) {res.reason="INVALID_INPUT: filling is not a known value"; return(false);}
   if((int)cfg.filter_policy<(int)EX_POL_UNSET || (int)cfg.filter_policy>(int)EX_POL_NEEDS_CLEAR) {res.reason="INVALID_INPUT: exit_filter_policy is not a known value"; return(false);}
   if((int)cfg.filter_state<(int)EX_FS_UNKNOWN || (int)cfg.filter_state>(int)EX_FS_BLOCKED) {res.reason="INVALID_INPUT: exit_filter_state is not a known value"; return(false);}
   if((int)cfg.test_save_fault<(int)EX_SAVE_NONE || (int)cfg.test_save_fault>(int)EX_SAVE_AFTER) {res.reason="INVALID_INPUT: test_save_fault is not a known value"; return(false);}
   if(q.direction!=1 && q.direction!=-1) {res.reason="INVALID_INPUT: direction must be 1 (BUY) or -1 (SELL)"; return(false);}
   if((int)cfg.r_policy<(int)EX_RPOL_UNSET || (int)cfg.r_policy>(int)EX_RPOL_R_GEOM) {res.reason="INVALID_INPUT: r_policy is not a known value"; return(false);}
   if(cfg.ea_magic<=0) {res.reason="INPUT_UNSET: ea_magic"; return(false);}
   if(cfg.r_policy==EX_RPOL_UNSET) {res.reason="INPUT_UNSET: r_policy"; return(false);}
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
   string why;
   if(cfg.r_policy!=EX_RPOL_R_GEOM)                    // typed diagnostic level: judged now; R_GEOM: judged after the level is derived from the stored basis
     {
      why=EX_PlanRefusal(q.level_2r,cfg,sym,q.direction,false,0.0);
      if(why!="") {res.reason=why; return(false);}
     }
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
   if(!o.plan_set)
     {
      res.final_state=EX_RECOVERY_REQUIRED;
      res.reason="PLAN_MISSING: the IDLE record carries no authorised plan (an unregistered or old record); it is never filled in from the current inputs";
      return(false);
     }
   if((int)o.plan_rpol!=(int)cfg.r_policy)
     {
      res.reason="PLAN_CHANGED: r_policy differs from the authorised plan; nothing is persisted or sent";
      return(false);
     }
   double level=q.level_2r;
   if(cfg.r_policy==EX_RPOL_R_GEOM)
     {
      // the level is DERIVED from the STORED E and S (never from the live SL, never from the quote's level input) and must equal the stored level
      if(!cfg.sl_initial_set) {res.reason="INPUT_UNSET: initial_sl"; return(false);}
      if(cfg.sl_initial!=o.plan_s_src) {res.reason="PLAN_CHANGED: initial_sl differs from the authorised plan; nothing is persisted or sent"; return(false);}
      STgResult geo;
      EX_Geometry(sym,q.direction,o.plan_e_src,o.plan_s_src,cfg.tp_price,geo);
      if(geo.status!=TG_OK) {res.reason="GEOMETRY_REFUSED: "+TG_StatusName(geo.status)+": "+geo.reason; return(false);}
      if(geo.e_out!=o.plan_e_out || geo.s_out!=o.plan_s_out) {res.reason="PLAN_CHANGED: normalized basis differs from the authorised plan; nothing is persisted or sent"; return(false);}
      level=geo.level_2r;                         // compared with the stored level below, with the other plan fields
      why=EX_PlanRefusal(level,cfg,sym,q.direction,false,0.0);
      if(why!="") {res.reason=why; return(false);}
     }
   string changed="";
   if(st.direction!=q.direction) changed="direction";
   else
      if(st.level!=level) changed="level_2R";
      else
         if(st.volume_initial!=q.volume_initial) changed="initial_volume";
         else
            if(o.plan_tp!=cfg.tp_price) changed="tp";
            else
               if(o.plan_vol_min!=sym.vol_min) changed="volume_min";
               else
                  if(o.plan_vol_step!=sym.vol_step) changed="volume_step";
                  else
                     if(o.plan_vol_max!=sym.vol_max) changed="volume_max";
   if(changed!="")
     {
      res.reason="PLAN_CHANGED: "+changed+" differs from the authorised plan; nothing is persisted or sent";
      return(false);
     }
   SEaResult r;
   bool request=EA_OnQuote(st,id.position_id,q.direction,level,q.bid,q.ask,q.volume_initial,pos.volume,sym.vol_min,sym.vol_step,sym.vol_max,r);
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
   rec.plan_set=o.plan_set;
   rec.plan_tp=o.plan_tp;
   rec.plan_vol_min=o.plan_vol_min;
   rec.plan_vol_step=o.plan_vol_step;
   rec.plan_vol_max=o.plan_vol_max;
   rec.plan_rpol=o.plan_rpol;
   rec.plan_e_src=o.plan_e_src;
   rec.plan_s_src=o.plan_s_src;
   rec.plan_e_out=o.plan_e_out;
   rec.plan_s_out=o.plan_s_out;
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
   mapped.plan_set=o.plan_set;
   mapped.plan_tp=o.plan_tp;
   mapped.plan_vol_min=o.plan_vol_min;
   mapped.plan_vol_step=o.plan_vol_step;
   mapped.plan_vol_max=o.plan_vol_max;
   mapped.plan_rpol=o.plan_rpol;
   mapped.plan_e_src=o.plan_e_src;
   mapped.plan_s_src=o.plan_s_src;
   mapped.plan_e_out=o.plan_e_out;
   mapped.plan_s_out=o.plan_s_out;
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

// REGISTRATION of the authorised plan (explicit; the executor never starts a file by itself). Stores the bound IDLE state (direction, level 2R, initial volume) and the plan block
// (TP, volume min / step / max). Never adopts a manual or unproven position (magic == the configured magic > 0, symbol, direction, volume equal to the plan's initial volume),
// never overwrites, never rounds. Returns true only for REGISTERED.
bool EX_Register(const SExConfig &cfg,CExitTransport *tr,SExRuntime &rt,const string name,const SEsIdentity &id,const SExQuote &q,SExResult &res)
  {
   res.final_state=EX_BLOCKED;
   res.reason="";
   res.sends=0;
   res.order_ticket=0;
   if(!cfg.enabled) {res.reason="DISABLED: the executor is off by default"; return(false);}
   if((int)cfg.filling<(int)EX_FILL_UNSET || (int)cfg.filling>(int)EX_FILL_RETURN) {res.reason="INVALID_INPUT: filling is not a known value"; return(false);}
   if((int)cfg.filter_policy<(int)EX_POL_UNSET || (int)cfg.filter_policy>(int)EX_POL_NEEDS_CLEAR) {res.reason="INVALID_INPUT: exit_filter_policy is not a known value"; return(false);}
   if((int)cfg.filter_state<(int)EX_FS_UNKNOWN || (int)cfg.filter_state>(int)EX_FS_BLOCKED) {res.reason="INVALID_INPUT: exit_filter_state is not a known value"; return(false);}
   if((int)cfg.test_save_fault<(int)EX_SAVE_NONE || (int)cfg.test_save_fault>(int)EX_SAVE_AFTER) {res.reason="INVALID_INPUT: test_save_fault is not a known value"; return(false);}
   if(q.direction!=1 && q.direction!=-1) {res.reason="INVALID_INPUT: direction must be 1 (BUY) or -1 (SELL)"; return(false);}
   if((int)cfg.r_policy<(int)EX_RPOL_UNSET || (int)cfg.r_policy>(int)EX_RPOL_R_GEOM) {res.reason="INVALID_INPUT: r_policy is not a known value"; return(false);}
   if(cfg.ea_magic<=0) {res.reason="INPUT_UNSET: ea_magic"; return(false);}
   if(cfg.r_policy==EX_RPOL_UNSET) {res.reason="INPUT_UNSET: r_policy"; return(false);}
   if(!cfg.tp_set) {res.reason="TP_UNKNOWN"; return(false);}
   if(rt.latched) {res.reason="LATCHED: an earlier uncertainty on this executor; restart and recover first"; return(false);}
   SExAccount acct;
   tr.ReadAccount(acct);
   if(tr.IsReal())
     {
      if(!(cfg.real_authorised && cfg.authorisation==EX_AUTH_PHRASE)) {res.reason="REAL_NOT_AUTHORISED"; return(false);}
      if(!acct.read_ok || !acct.demo) {res.reason="REAL_REQUIRES_DEMO_ACCOUNT"; return(false);}
     }
   if(!acct.read_ok) {res.reason="ACCOUNT_UNREADABLE"; return(false);}
   if(acct.login!=id.login || acct.server!=id.server) {res.reason="ACCOUNT_IDENTITY_MISMATCH"; return(false);}
   if(acct.margin_mode!=2) {res.reason="UNSUPPORTED_ACCOUNT_MODE: only HEDGING"; return(false);}
   SExSymbol sym;
   tr.ReadSymbol(id.symbol,sym);
   if(!sym.read_ok || sym.tick_size<=0.0) {res.reason="SYMBOL_UNREADABLE"; return(false);}
   string why;
   if(cfg.r_policy!=EX_RPOL_R_GEOM)
     {
      why=EX_PlanRefusal(q.level_2r,cfg,sym,q.direction,true,q.volume_initial);
      if(why!="") {res.reason=why; return(false);}
     }
   SExPosition pos;
   tr.FindPosition(id.position_id,pos);
   if(!pos.found || pos.ticket==0 || pos.identifier!=id.position_id) {res.reason="POSITION_NOT_FOUND"; return(false);}
   if(pos.symbol!=id.symbol || pos.magic!=cfg.ea_magic || pos.type!=(q.direction==1 ? 0 : 1))
     {
      res.reason="OWNERSHIP_NOT_PROVEN: a manual or foreign position is never adopted (symbol, magic or direction differ)";
      return(false);
     }
   double level=q.level_2r;
   double e_src=0.0,s_src=0.0,e_out=0.0,s_out=0.0;
   if(cfg.r_policy==EX_RPOL_R_GEOM)
     {
      // E = the open price read ONCE now; S = the initial SL ASSERTED by the owner, accepted only while the live SL still equals it (variant (a)); nothing is read from history
      if(!cfg.sl_initial_set) {res.reason="INPUT_UNSET: initial_sl"; return(false);}
      if(!(EX_Finite(pos.price_open) && pos.price_open>0.0)) {res.reason="ENTRY_UNAVAILABLE: the open price of the position is not readable"; return(false);}
      if(!(pos.sl>0.0 && MathAbs(pos.sl-cfg.sl_initial)<sym.tick_size/2.0))
        {
         res.reason="INITIAL_SL_NOT_PROVEN: the live SL differs from the asserted initial SL (or is absent); it may have been moved, so the initial SL is unproven";
         return(false);
        }
      if(!(EX_OnGrid(pos.price_open,sym.tick_size) && EX_OnGrid(cfg.sl_initial,sym.tick_size))) {res.reason="BASE_NOT_ON_SYMBOL_GRID: the open price or the asserted SL is refused, not rounded"; return(false);}
      STgResult geo;
      EX_Geometry(sym,q.direction,pos.price_open,cfg.sl_initial,cfg.tp_price,geo);
      if(geo.status!=TG_OK) {res.reason="GEOMETRY_REFUSED: "+TG_StatusName(geo.status)+": "+geo.reason; return(false);}
      if(MathAbs(geo.e_out-pos.price_open)>ESC_BASIS_TOL*MathMax(1.0,pos.price_open) || MathAbs(geo.s_out-cfg.sl_initial)>ESC_BASIS_TOL*MathMax(1.0,cfg.sl_initial))
        {
         res.reason="BASE_CHANGED_BY_NORMALIZATION: the normalized entry / stop differs from the declared one; nothing is rounded or persisted";
         return(false);
        }
      level=geo.level_2r;
      e_src=pos.price_open;
      s_src=cfg.sl_initial;
      e_out=geo.e_out;
      s_out=geo.s_out;
      why=EX_PlanRefusal(level,cfg,sym,q.direction,true,q.volume_initial);
      if(why!="") {res.reason=why; return(false);}
     }
   if(pos.volume!=q.volume_initial) {res.reason="POSITION_VOLUME_DIFFERS_FROM_THE_PLAN: the initial volume must equal the volume of the position"; return(false);}
   SEsResult sp;
   ES_Split(q.volume_initial,sym.vol_min,sym.vol_step,sym.vol_max,sp);
   if(sp.status!=ES_OK)
     {
      res.reason="REGISTRATION_REFUSED: the 80/20 split is not realisable ("+ES_StatusName(sp.status)+"): "+sp.reason;
      return(false);
     }
   if(ESF_Exists(name) || ESF_Exists(name+ESF_TMP_SUFFIX)) {res.reason="ALREADY_EXISTS: a state file exists; registration never overwrites"; return(false);}
   SEsRecord rec;
   ESC_RecordInit(rec);
   rec.generation=1;
   rec.id=id;
   rec.state.bound=true;
   rec.state.position_id=id.position_id;
   rec.state.direction=q.direction;
   rec.state.level=level;
   rec.state.volume_initial=q.volume_initial;
   rec.plan_set=true;
   rec.plan_tp=cfg.tp_price;
   rec.plan_vol_min=sym.vol_min;
   rec.plan_vol_step=sym.vol_step;
   rec.plan_vol_max=sym.vol_max;
   rec.plan_rpol=(int)cfg.r_policy;
   rec.plan_e_src=e_src;
   rec.plan_s_src=s_src;
   rec.plan_e_out=e_out;
   rec.plan_s_out=s_out;
   if(!EX_Save(cfg,rt,name,rec,why))
     {
      rt.latched=true;
      res.final_state=EX_RECOVERY_REQUIRED;
      res.reason="REGISTRATION_SAVE_FAILED: "+why+"; the file may or may not exist; nothing else is done";
      return(false);
     }
   SEaState st2;
   SEsRestore o2;
   ESF_Load(name,id,st2,o2);
   if(!(o2.verdict==ESC_USABLE_IDLE && o2.generation==1 && o2.plan_set && o2.plan_tp==cfg.tp_price && st2.direction==q.direction && st2.level==level && o2.plan_rpol==(int)cfg.r_policy &&
        o2.plan_e_src==e_src && o2.plan_s_src==s_src && o2.plan_e_out==e_out && o2.plan_s_out==s_out &&
        st2.volume_initial==q.volume_initial && o2.plan_vol_min==sym.vol_min && o2.plan_vol_step==sym.vol_step && o2.plan_vol_max==sym.vol_max))
     {
      rt.latched=true;
      res.final_state=EX_RECOVERY_REQUIRED;
      res.reason="REGISTRATION_NOT_VERIFIED: the re-load does not show the registered plan";
      return(false);
     }
   res.final_state=EX_REGISTERED;
   res.reason="registered: the authorised plan is stored; a request may only be made against exactly this plan";
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
