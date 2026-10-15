// T011 DEMO HARNESS core: wires the existing modules for ONE controlled demo test, step by step, behind explicit gates. Mirrors tests/t011_demo_reference.py.
//   registration of an OWNED position (explicit) -> stored authorised plan -> activation at the (diagnostic) 2R level -> INTENT -> ONE send -> order-ticket map -> reconciliation
//   -> save / restore. It adds no trading rule, no signal and no state machine: every step calls ExitExecutor.mqh (EX_Register / EX_Process / EX_Reconcile) or ExitStateFile.mqh.
// The parameters are DIAGNOSTIC TEST PARAMETERS chosen by the owner for this one test; they are not strategy rules. Every unset parameter blocks.
// DISABLED BY DEFAULT (step NONE). A real transport additionally needs the explicit authorisation phrase and a DEMO account (enforced by ExitExecutor.mqh before any trading call);
// ACTIVATE (the only step that can send) also needs confirm_send_once. Steps that act (REGISTER / ACTIVATE / RECONCILE) hold an instance lock (ExitInstanceLock.mqh) for their duration;
// STATUS is read-only. Nothing here deletes a record, clears a RECOVERY_REQUIRED or cleans anything automatically.
// This header never includes a transport: the caller passes a CExitTransport (the fake one in tests, the real one only in XauUsdT011DemoHarness.mq5).
#ifndef VELO_DEMO_HARNESS_MQH
#define VELO_DEMO_HARNESS_MQH

#include "ExitExecutor.mqh"
#include "ExitInstanceLock.mqh"

enum ENUM_DM_STEP
  {
   DM_STEP_NONE=0,
   DM_STEP_STATUS,
   DM_STEP_REGISTER,
   DM_STEP_ACTIVATE,
   DM_STEP_RECONCILE
  };

enum ENUM_DM_DIRECTION
  {
   DM_DIR_UNSET=0,
   DM_DIR_BUY=1,
   DM_DIR_SELL=-1
  };

struct SDmParams
  {
   ENUM_DM_STEP step;
   string authorisation;
   bool confirm_send_once;
   long magic;
   long position_id;
   string symbol;
   ENUM_DM_DIRECTION direction;
   double level_2r;                  // DIAGNOSTIC level at which the test partial close is armed (not a strategy 2R rule)
   double tp_price;
   double volume_initial;
   ENUM_EX_FILLING filling;
   long deviation;
   ENUM_EX_FILTER_POLICY filter_policy;
   ENUM_EX_FILTER_STATE filter_state;
   bool use_lock;
   string file_name;                 // "" = DM_File(login, position); tests pass their own name
   string lock_key;                  // "" = EL_Key(login, position); tests pass their own key
  };

struct SDmQuote
  {
   bool read_ok;
   double bid;
   double ask;
  };

struct SDmResult
  {
   string status;                    // DISABLED / BLOCKED / STATUS / REGISTERED / SENT_MAPPED / NO_REQUEST / NOT_IDLE / RECOVERY_REQUIRED / DONE / STILL_OPEN / ...
   string detail;
   int sends;
   string file;
  };

string DM_File(const long login,const long position_id)
  {
   return("VELO_T011_DEMO_"+IntegerToString(login)+"_"+IntegerToString(position_id)+".state");
  }

void DM_ParamsInit(SDmParams &p)
  {
   p.step=DM_STEP_NONE;
   p.authorisation="";
   p.confirm_send_once=false;
   p.magic=0;
   p.position_id=0;
   p.symbol="";
   p.direction=DM_DIR_UNSET;
   p.level_2r=-1.0;
   p.tp_price=-1.0;
   p.volume_initial=0.0;
   p.filling=EX_FILL_UNSET;
   p.deviation=-1;
   p.filter_policy=EX_POL_UNSET;
   p.filter_state=EX_FS_UNKNOWN;
   p.use_lock=true;
   p.file_name="";
   p.lock_key="";
  }

void DM_Set(SDmResult &r,const string status,const string detail)
  {
   r.status=status;
   r.detail=detail;
  }

// Returns true when the requested step completed as intended (REGISTERED, SENT_MAPPED, DONE, STATUS ...). raw_a / raw_b are used by RECONCILE only with a fake transport.
bool DM_Run(const SDmParams &p,CExitTransport *tr,const SDmQuote &quote,const SXaRaw &raw_a,const SXaRaw &raw_b,SDmResult &res)
  {
   res.status="DISABLED";
   res.detail="step NONE: the harness is off by default";
   res.sends=0;
   res.file="";
   if(p.step==DM_STEP_NONE) return(false);
   if(p.position_id<=0 || p.symbol=="") {DM_Set(res,"BLOCKED","INPUT_UNSET: position_id or symbol"); return(false);}
   SExAccount acct;
   tr.ReadAccount(acct);
   if(!acct.read_ok) {DM_Set(res,"BLOCKED","ACCOUNT_UNREADABLE"); return(false);}
   SEsIdentity id;
   id.server=acct.server;
   id.login=acct.login;
   id.symbol=p.symbol;
   id.position_id=(ulong)p.position_id;
   string name=(p.file_name!="" ? p.file_name : DM_File(acct.login,p.position_id));
   res.file=name;
   if(p.step==DM_STEP_STATUS)
     {
      SEaState st;
      SEsRestore o;
      ESF_Load(name,id,st,o);
      DM_Set(res,"STATUS",StringFormat("record %s | verdict %s | state %s | generation %d | plan_set %d (tp %.8g, volume min/step/max %.8g/%.8g/%.8g) | order map entries %d | confirmations %d | new_request_allowed %d | reconcile_required %d | %s",
                                       name,ESC_VerdictName(o.verdict),EA_StateName(st.status),o.generation,(int)o.plan_set,o.plan_tp,o.plan_vol_min,o.plan_vol_step,o.plan_vol_max,o.n_orders,
                                       st.confirmations,(int)o.new_request_allowed,(int)o.reconcile_required,o.reason));
      return(true);
     }
   SExConfig cfg;
   EX_ConfigInit(cfg);
   cfg.enabled=true;
   cfg.real_authorised=(p.authorisation==EX_AUTH_PHRASE);
   cfg.authorisation=p.authorisation;
   cfg.ea_magic=p.magic;
   cfg.filling=p.filling;
   cfg.deviation=p.deviation;
   cfg.filter_policy=p.filter_policy;
   cfg.filter_state=p.filter_state;
   cfg.tp_set=(p.tp_price>0.0);
   cfg.tp_price=p.tp_price;
   SExQuote q;
   q.direction=(int)p.direction;
   q.level_2r=p.level_2r;
   q.bid=quote.bid;
   q.ask=quote.ask;
   q.volume_initial=p.volume_initial;
   string key=(p.lock_key!="" ? p.lock_key : EL_Key(acct.login,(ulong)p.position_id));
   bool held=false;
   string why;
   if(p.use_lock && !EL_Acquire(key,held,why)) {DM_Set(res,"BLOCKED",why); return(false);}
   bool ok=false;
   SExRuntime rt;
   EX_RuntimeInit(rt);
   SExResult xr;
   if(p.step==DM_STEP_REGISTER)
     {
      ok=EX_Register(cfg,tr,rt,name,id,q,xr);
      DM_Set(res,EX_FinalName(xr.final_state),xr.reason);
     }
   else
      if(p.step==DM_STEP_ACTIVATE)
        {
         if(!p.confirm_send_once) DM_Set(res,"BLOCKED","ACTIVATE needs confirm_send_once = true: this is the only step that can send a trading request");
         else
            if(!quote.read_ok || !(quote.bid>0.0) || !(quote.ask>0.0)) DM_Set(res,"BLOCKED","QUOTE_UNAVAILABLE");
            else
              {
               ok=EX_Process(cfg,tr,rt,name,id,q,xr);
               DM_Set(res,EX_FinalName(xr.final_state),xr.reason);
               res.sends=xr.sends;
              }
        }
      else
         if(p.step==DM_STEP_RECONCILE)
           {
            SErfResult fr;
            ok=EX_Reconcile(name,id,tr,raw_a,raw_b,fr);
            DM_Set(res,ERF_FinalName(fr.final_state),ERF_Text(fr));
           }
   EL_Release(key,held);
   return(ok);
  }
#endif
