// T011 TICK DRIVER: the thin wiring between a quote loop and the EXISTING executor. Mirrors tests/t011_driver_reference.py. It has NO state machine of its own (the only state is the
// record on disk, owned by ExitStateCodec / ExitActivation / ExitReconciliation) and no trading call: every request still comes from EX_Process -> EA_OnQuote -> the transport seam.
// DISABLED by default (SExConfig.enabled). It never opens, adopts or modifies a position and has no signal code.
// RULES
//  * ONE lock (ExitInstanceLock, key EL_Key(login, position)) wraps everything that reads or changes the record or could send: init/recovery, a tick that reaches the level, the reconcile
//    timer and the explicit registration. Any failure to take the lock = zero sends and no I/O.
//  * ETD_Init runs the RECOVERY (the existing restart flow ERF_Run through EX_Reconcile) BEFORE any quote is allowed: a request-bearing record is reconciled and never arms the tick path.
//    Only a USABLE_IDLE record that carries an R_GEOM plan arms it. A missing / unusable / older-version file arms nothing and is never created or changed here.
//  * ETD_Tick never calls EX_Process for a record that is not IDLE (it re-loads the record under the lock first); below the level it does no I/O at all (the same comparison as
//    EA_OnQuote: BUY Bid >= level, SELL Ask <= level, the level cached from the record; EA_OnQuote remains the authority).
//  * After a send, an uncertainty or a latch the tick path is disarmed; the timer only reconciles (read-only terminal reads + the flow's own save), it never produces a request.
//  * REGISTRATION is a separate explicit call (ETD_Register, used by its own script); OnInit never registers a position.
// LIMITS: the lock protects one terminal only; the semantics of the terminal calls are UNVERIFIED until the owner runs the MQL5 tests; the driver is not an EA by itself.
#ifndef VELO_EXIT_TICK_DRIVER_MQH
#define VELO_EXIT_TICK_DRIVER_MQH

#include "ExitExecutor.mqh"
#include "ExitInstanceLock.mqh"

// the direction and the R policy as the two entry points (the EA and the registration script) expose them: UNSET blocks, only the known values pass; the typed diagnostic policy is not selectable
enum ENUM_ETD_DIRECTION
  {
   ETD_DIR_UNSET=0,
   ETD_DIR_BUY=1,
   ETD_DIR_SELL=-1
  };

enum ENUM_ETD_RPOLICY
  {
   ETD_RPOL_UNSET=0,
   ETD_RPOL_R_GEOM=2          // equals EX_RPOL_R_GEOM: R_GEOM from the open price (read once) and the owner-asserted initial SL; costs are NOT modelled; not the client's final R
  };

struct SEtdState
  {
   bool armed;                // the tick path may call EX_Process (only after a successful init of an IDLE R_GEOM record)
   int direction;
   double level;              // cached from the record at init, for the cheap pre-filter only
   bool reconcile_due;        // a request-bearing record exists that the timer must reconcile
   string reason;
   int process_calls;         // EX_Process calls made by this driver (tests)
   int lock_failures;
  };

void ETD_StateInit(SEtdState &s)
  {
   s.armed=false;
   s.direction=0;
   s.level=0.0;
   s.reconcile_due=false;
   s.reason="NOT_INITIALISED";
   s.process_calls=0;
   s.lock_failures=0;
  }

// ---- registration (explicit; the caller is a separate script)
bool ETD_Register(const SExConfig &cfg,CExitTransport *tr,SExRuntime &rt,const string name,const SEsIdentity &id,const SExQuote &q,SExResult &res)
  {
   string key=EL_Key(id.login,id.position_id);
   bool held=false;
   string why;
   if(!EL_Acquire(key,held,why))
     {
      res.final_state=EX_BLOCKED;
      res.reason=why;
      res.sends=0;
      res.order_ticket=0;
      return(false);
     }
   bool ok=EX_Register(cfg,tr,rt,name,id,q,res);
   EL_Release(key,held);
   return(ok);
  }

// ---- init: recovery first, then (only for an IDLE R_GEOM record) arming. Returns true when the tick path is armed.
bool ETD_Init(const SExConfig &cfg,CExitTransport *tr,const string name,const SEsIdentity &id,const SXaRaw &raw_a,const SXaRaw &raw_b,SEtdState &s,SErfResult &flow)
  {
   ETD_StateInit(s);
   ERF_ResultInit(flow);
   if(!cfg.enabled)
     {
      s.reason="INIT_DISABLED: the driver is off by default; nothing is read, locked or armed";
      return(false);
     }
   string key=EL_Key(id.login,id.position_id);
   bool held=false;
   string why;
   if(!EL_Acquire(key,held,why))
     {
      s.lock_failures++;
      s.reason="INIT_LOCK_FAILED: "+why+"; nothing is read, nothing can be sent";
      return(false);
     }
   SEaState st;
   SEsRestore o;
   ESF_Load(name,id,st,o);
   if(o.generation==0)
     {
      s.reason="INIT_LOAD_UNUSABLE: "+o.reason+"; the file is never created or changed here (registration is a separate action)";
      EL_Release(key,held);
      return(false);
     }
   if(o.verdict!=ESC_USABLE_IDLE)
     {
      // RECOVERY BEFORE ACTIVATION: a request-bearing / blocked / done record goes through the existing flow; it never arms the tick path
      EX_Reconcile(name,id,tr,raw_a,raw_b,flow);
      s.reconcile_due=(flow.final_state==ERF_STILL_OPEN);
      s.reason="INIT_RECOVERY: "+ERF_FinalName(flow.final_state)+": "+flow.reason;
      EL_Release(key,held);
      return(false);
     }
   if(!o.plan_set || (int)o.plan_rpol!=(int)EX_RPOL_R_GEOM || cfg.r_policy!=EX_RPOL_R_GEOM)
     {
      s.reason="INIT_PLAN_NOT_R_GEOM: the record carries no R_GEOM plan or the configured policy differs; nothing is armed";
      EL_Release(key,held);
      return(false);
     }
   s.armed=true;
   s.direction=st.direction;
   s.level=st.level;
   s.reason="ARMED";
   EL_Release(key,held);
   return(true);
  }

// ---- one quote. Returns true only for SENT_MAPPED.
bool ETD_Tick(const SExConfig &cfg,CExitTransport *tr,SExRuntime &rt,const string name,const SEsIdentity &id,const SExQuote &q,SEtdState &s,SExResult &res)
  {
   res.final_state=EX_BLOCKED;
   res.reason="";
   res.sends=0;
   res.order_ticket=0;
   if(!s.armed) {res.reason="NOT_ARMED: "+s.reason; return(false);}
   // below the level: no lock, no file, no terminal read (EA_OnQuote stays the authority once the level is reached)
   if(s.direction==1 ? !(q.bid>=s.level) : !(q.ask<=s.level))
     {
      res.final_state=EX_NO_REQUEST;
      res.reason="the 2R level is not reached";
      return(false);
     }
   string key=EL_Key(id.login,id.position_id);
   bool held=false;
   string why;
   if(!EL_Acquire(key,held,why))
     {
      s.lock_failures++;
      res.reason="TICK_LOCK_FAILED: "+why+"; zero sends";
      return(false);
     }
   SEaState st;
   SEsRestore o;
   ESF_Load(name,id,st,o);
   if(o.generation==0 || o.verdict!=ESC_USABLE_IDLE)
     {
      s.armed=false;
      s.reason="RECORD_NOT_IDLE: the record changed or needs reconciliation; EX_Process is not called";
      res.reason=s.reason;
      EL_Release(key,held);
      return(false);
     }
   s.process_calls++;
   bool sent=EX_Process(cfg,tr,rt,name,id,q,res);
   if(sent)
     {
      s.armed=false;
      s.reconcile_due=true;
      s.reason="SENT: reconcile on the timer";
     }
   else
      if(res.final_state==EX_RECOVERY_REQUIRED || res.final_state==EX_NOT_IDLE || rt.latched)
        {
         s.armed=false;
         s.reason="DISARMED: "+res.reason;
        }
   EL_Release(key,held);
   return(sent);
  }

// ---- timer: reconcile only (read + the flow's own save); never a request
bool ETD_Timer(CExitTransport *tr,const string name,const SEsIdentity &id,const SXaRaw &raw_a,const SXaRaw &raw_b,SEtdState &s,SErfResult &flow)
  {
   ERF_ResultInit(flow);
   if(!s.reconcile_due) return(false);
   string key=EL_Key(id.login,id.position_id);
   bool held=false;
   string why;
   if(!EL_Acquire(key,held,why))
     {
      s.lock_failures++;
      s.reason="TIMER_LOCK_FAILED: "+why;
      return(false);
     }
   EX_Reconcile(name,id,tr,raw_a,raw_b,flow);
   s.reconcile_due=(flow.final_state==ERF_STILL_OPEN);
   s.reason="TIMER: "+ERF_FinalName(flow.final_state)+": "+flow.reason;
   EL_Release(key,held);
   return(true);
  }
#endif
