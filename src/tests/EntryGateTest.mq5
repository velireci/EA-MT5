// T015 entry-gate test (FAKE transport and FAKE store only): a T014-style plan + TP_CheckPermit data + the broker loss check + the T012 daily result -> one decision -> an executor permit for THAT plan, or no
// call to the executor at all. BUY and SELL, every block separately, the T012 result not bypassed, a permit for another / old plan, repetition without a second send.
// Mirrors tests/test_entry_gate.py (the scenario names are pinned equal by a Python test). NEVER includes a real transport; no terminal read, no file, no order, no trade.
// NOT YET COMPILED OR RUN (UNVERIFIED): Codex compiles it, the owner runs it in MT5.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/EntryGate.mqh"
#include "../include/EntryTransportFake.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
bool Has(const string text,const string part) {return(StringFind(text,part)>=0);}
bool Starts(const string text,const string part) {return(StringFind(text,part)==0);}

class CGw
  {
public:
   CEnFakeTransport t;
   CEnFakeStore s;
   SEnConfig cfg;
   SEgConfig g;
   SSpbResult spb;
   SEgChecks c;
   SEnRuntime rt;
   SEnResult r;
   SEgDecision dec;
   string reg[8];
   int reg_count;
   int dir;
   string Digest(void) {return(EN_PlanDigest(spb.plan));}
   void Init(const int direction)
     {
      dir=direction;
      SPB_ResultInit(spb);
      string setup=(dir==1 ? "S|T003_PROTOTYPE|H4SET1|H4F1|L-BUY" : "S|T003_PROTOTYPE|H4SET1|H4F1|L-SELL");
      string signal=setup+(dir==1 ? "|M15F14400U" : "|M15F14400D");
      TP_BuildPlan(signal,setup,dir,(dir==1 ? 102.0 : 93.0),(dir==1 ? 97.5 : 98.5),false,0.0,100.0,1.0,0.01,2,0.01,0,true,(dir==1 ? 108.0 : 90.0),(dir==1 ? 108.3 : 90.3),0.01,0.01,100.0,10.0,spb.plan);
      spb.plan_ready=(spb.plan.status==TP_OK);
      spb.setup_id=setup;
      spb.signal_id=signal;
      spb.candidate_id=(dir==1 ? "M15F14400U" : "M15F14400D");
      t.quote.bid=(dir==1 ? 108.0 : 90.0);
      t.quote.ask=(dir==1 ? 108.3 : 90.3);
      t.quote.time=t.now;
      EN_ConfigInit(cfg);
      cfg.enabled=true;
      cfg.ea_magic=777;
      cfg.symbol="XAUUSD";
      cfg.filling=EN_FILL_RETURN;
      cfg.expiry_mode=EN_EXP_GTC;
      cfg.permit_max_age=60;
      cfg.quote_max_age=30;
      EG_ConfigInit(g);
      g.max_age=60;
      EN_RuntimeInit(rt);
      reg_count=0;
      for(int i=0;i<8;i++) reg[i]="";
      FreshChecks();
     }
   void FreshChecks(void)
     {
      string dg=Digest();
      c.permit_inputs=true;
      c.snap.data_state=TP_DATA_READY;
      c.snap.data_reliable=true;
      c.snap.session_state=TP_SESSION_OPEN;
      c.snap.news_state=TP_NEWS_CLEAR;
      c.snap.spread_state=TP_SPREAD_CLEAR;
      c.snap.open_positions=0;
      c.snap.trades_today=0;
      c.snap.existing_risk=0.0;
      c.snap_time=t.now;
      c.snap_digest=dg;
      c.lim.max_positions_set=true;
      c.lim.max_positions=2;
      c.lim.max_trades_set=true;
      c.lim.max_trades=3;
      c.lim.risk_cap_set=true;
      c.lim.risk_cap=1000.0;
      c.calc_ok=true;
      c.profit=-spb.plan.risk_model;
      c.tolerance=0.01;
      c.risk_budget=100.0;
      c.loss_time=t.now;
      c.loss_digest=dg;
      c.daily_present=true;
      c.daily.entry_allowed=true;
      c.daily.primary="";
      c.daily.n_reasons=0;
      c.daily.dl_called=true;
      c.daily.closed_result=0.0;
      c.daily.cancel_pending_due=false;
      c.daily.daily_limit_reached=false;
      c.daily.day_key=20261015;
      c.daily_time=t.now;
      c.daily_digest=dg;
     }
   void Submit(void) {EG_Submit(g,cfg,GetPointer(t),GetPointer(s),rt,spb,c,reg,reg_count,r,dec);}
   void SubmitWith(SEnRuntime &runtime) {EG_Submit(g,cfg,GetPointer(t),GetPointer(s),runtime,spb,c,reg,reg_count,r,dec);}
   bool Untouched(const int reg0)
     {
      return(r.outcome==EN_R_REFUSED && Starts(r.reason,"GATE_BLOCKED") && t.sends==0 && rt.send_calls==0 && s.lock_calls==0 && s.writes==0 && s.n_files==0 && reg_count==reg0 &&
             !dec.permit.present && !dec.permit.allow);
     }
  };

#define N_BLOCKS 39
string BlockFrag(const int k)
  {
   string f[N_BLOCKS]={"PLAN_NOT_READY","PERMIT:PLAN_NOT_OK","PERMIT:DATA_NOT_READY","PERMIT:DATA_UNKNOWN","PERMIT:DATA_UNRELIABLE","PERMIT:SESSION_CLOSED","PERMIT:SESSION_UNKNOWN","PERMIT:NEWS_BLOCK",
                       "PERMIT:NEWS_UNKNOWN","PERMIT:SPREAD_BLOCK","PERMIT:SPREAD_UNKNOWN","PERMIT:MAX_POSITIONS_REACHED","PERMIT:MAX_TRADES_REACHED","PERMIT:COMBINED_RISK_EXCEEDED",
                       "PERMIT:POLICY_UNSET:max_positions","PERMIT:POLICY_UNSET:max_trades_per_day","PERMIT:POLICY_UNSET:combined_risk_cap","PERMIT:DUPLICATE_SIGNAL","PERMIT_INPUT_MISSING",
                       "BROKER_LOSS_CHECK:CALC_FAILED","BROKER_LOSS_CHECK:NOT_A_LOSS","BROKER_LOSS_CHECK:BUDGET_EXCEEDED","BROKER_LOSS_CHECK:MODEL_MISMATCH","BROKER_LOSS_CHECK:INVALID_INPUT",
                       "DAILY_NOT_EVALUATED","DAILY_NOT_CALLED","DAILY_BLOCK","DAILY_NOT_CALLED","SNAPSHOT_STALE","SNAPSHOT_TIME_INVALID","SNAPSHOT_TIME_INVALID","SNAPSHOT_FOR_ANOTHER_PLAN",
                       "LOSS_CHECK_STALE","LOSS_CHECK_TIME_INVALID","LOSS_CHECK_FOR_ANOTHER_PLAN","DAILY_STALE","DAILY_TIME_INVALID","DAILY_FOR_ANOTHER_PLAN","INPUT_UNSET: gate_max_age"};
   return(f[k]);
  }

void ApplyBlock(CGw &w,const int k)
  {
   switch(k)
     {
      case 0: w.spb.plan_ready=false; w.spb.reason="SELECTION_UNSET: entry_edge"; break;
      case 1: w.spb.plan.status=TP_GEOMETRY_REFUSED; break;
      case 2: w.c.snap.data_state=TP_DATA_NOT_READY; break;
      case 3: w.c.snap.data_state=TP_DATA_UNKNOWN; break;
      case 4: w.c.snap.data_reliable=false; break;
      case 5: w.c.snap.session_state=TP_SESSION_CLOSED; break;
      case 6: w.c.snap.session_state=TP_SESSION_UNKNOWN; break;
      case 7: w.c.snap.news_state=TP_NEWS_BLOCKED; break;
      case 8: w.c.snap.news_state=TP_NEWS_UNKNOWN; break;
      case 9: w.c.snap.spread_state=TP_SPREAD_BLOCKED; break;
      case 10: w.c.snap.spread_state=TP_SPREAD_UNKNOWN; break;
      case 11: w.c.snap.open_positions=2; break;
      case 12: w.c.snap.trades_today=3; break;
      case 13: w.c.snap.existing_risk=999.0; break;
      case 14: w.c.lim.max_positions_set=false; break;
      case 15: w.c.lim.max_trades_set=false; break;
      case 16: w.c.lim.risk_cap_set=false; break;
      case 17: w.reg[0]=w.spb.plan.signal_id; w.reg_count=1; break;
      case 18: w.c.permit_inputs=false; break;
      case 19: w.c.calc_ok=false; break;
      case 20: w.c.profit=5.0; break;
      case 21: w.c.profit=-150.0; break;
      case 22: w.c.profit=-w.spb.plan.risk_model*1.5; w.c.risk_budget=10000.0; break;
      case 23: w.c.tolerance=2.0; break;
      case 24: w.c.daily_present=false; break;
      case 25: w.c.daily.entry_allowed=false; w.c.daily.primary="BALANCE_START_UNSET"; w.c.daily.dl_called=false; break;
      case 26: w.c.daily.entry_allowed=false; w.c.daily.primary="DAILY_LOSS_LIMIT"; w.c.daily.dl_called=true; break;
      case 27: w.c.daily.entry_allowed=true; w.c.daily.dl_called=false; break;
      case 28: w.c.snap_time=w.t.now-61; break;
      case 29: w.c.snap_time=w.t.now+1; break;
      case 30: w.c.snap_time=0; break;
      case 31: w.c.snap_digest="other"; break;
      case 32: w.c.loss_time=w.t.now-61; break;
      case 33: w.c.loss_time=w.t.now+1; break;
      case 34: w.c.loss_digest=""; break;
      case 35: w.c.daily_time=w.t.now-61; break;
      case 36: w.c.daily_time=w.t.now+1; break;
      case 37: w.c.daily_digest="x"; break;
      case 38: w.g.max_age=0; break;
     }
  }

void Scenario_allow_all(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CGw w;
      w.Init(dir);
      Check(w.spb.plan_ready,StringFormat("dir %d: the test plan is ready",dir));
      w.Submit();
      Check(w.dec.allow && w.r.outcome==EN_R_PLACED && w.r.sends==1 && w.t.sends==1,StringFormat("dir %d: every check allowing places one order",dir));
      Check(w.t.last_request.type==(dir==1 ? EN_TYPE_BUY_LIMIT : EN_TYPE_SELL_LIMIT) && w.t.last_request.price==w.spb.plan.e_out && w.t.last_request.sl==w.spb.plan.s_out &&
            w.t.last_request.tp==w.spb.plan.tp && w.t.last_request.volume==w.spb.plan.volume_out,StringFormat("dir %d: the request is exactly the plan",dir));
      Check(w.dec.permit.present && w.dec.permit.allow && w.dec.permit.digest==w.Digest() && w.dec.permit.issued==w.t.now && w.dec.loss_check=="OK" && w.reg_count==0,
            StringFormat("dir %d: the permit is for this plan, stamped with the decision time; the gate registered nothing",dir));
      CGw v;
      v.Init(dir);
      STpPlan guarded=v.spb.plan;
      guarded.risk_model=PB_PermitRisk(v.c.profit,v.spb.plan.risk_model);
      STpPermit tpermit;
      TP_CheckPermit(guarded,v.c.snap,v.c.lim,v.reg,v.reg_count,tpermit);
      SEgDecision d2;
      EG_Decide(v.g,v.spb,v.c,v.reg,v.reg_count,v.t.now,d2);
      Check(tpermit.allow && d2.allow,StringFormat("dir %d: TP_CheckPermit alone allows and the gate allows",dir));
     }
  }

void Scenario_every_block(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      for(int k=0;k<N_BLOCKS;k++)
        {
         CGw w;
         w.Init(dir);
         ApplyBlock(w,k);
         int reg0=w.reg_count;
         w.Submit();
         Check(!w.dec.allow && Has(w.dec.reasons,BlockFrag(k)) && w.Untouched(reg0),StringFormat("dir %d block %d (%s): BLOCK, no permit, executor not called, no lock / intent / send / signal use",dir,k,BlockFrag(k)));
        }
      CGw x;
      x.Init(dir);
      x.c.risk_budget=10000.0;
      x.c.tolerance=0.05;
      x.c.profit=-x.spb.plan.risk_model*1.04;
      x.c.snap.existing_risk=100.0;
      x.c.lim.risk_cap=100.0+x.spb.plan.risk_model*1.02;
      EG_Decide(x.g,x.spb,x.c,x.reg,x.reg_count,x.t.now,x.dec);
      Check(x.dec.loss_check=="OK" && !x.dec.allow && Has(x.dec.reasons,"PERMIT:COMBINED_RISK_EXCEEDED"),StringFormat("dir %d: the larger broker loss feeds the exposure check",dir));
     }
  }

void Scenario_plan_not_ready(void)
  {
   CGw w;
   w.Init(1);
   w.spb.plan_ready=false;
   w.spb.reason="SELECTION_UNSET: entry_edge";
   EG_Decide(w.g,w.spb,w.c,w.reg,w.reg_count,w.t.now,w.dec);
   Check(w.dec.reasons=="PLAN_NOT_READY: SELECTION_UNSET: entry_edge" && w.dec.loss_check=="","a plan that is not ready never reaches the permit check");
   CGw z;
   z.Init(-1);
   EG_ConfigInit(z.g);
   EG_Decide(z.g,z.spb,z.c,z.reg,z.reg_count,z.t.now,z.dec);
   bool a=!z.dec.allow;
   SEgChecks empty;                                      // never initialised by the caller: every flag false, every time 0, every digest blank
   empty.permit_inputs=false;
   empty.snap.data_state=0;
   empty.snap.data_reliable=false;
   empty.snap.session_state=0;
   empty.snap.news_state=0;
   empty.snap.spread_state=0;
   empty.snap.open_positions=-1;
   empty.snap.trades_today=-1;
   empty.snap.existing_risk=-1.0;
   empty.snap_time=0;
   empty.snap_digest="";
   empty.lim.max_positions_set=false;
   empty.lim.max_positions=0;
   empty.lim.max_trades_set=false;
   empty.lim.max_trades=0;
   empty.lim.risk_cap_set=false;
   empty.lim.risk_cap=0.0;
   empty.calc_ok=false;
   empty.profit=0.0;
   empty.tolerance=-1.0;
   empty.risk_budget=-1.0;
   empty.loss_time=0;
   empty.loss_digest="";
   empty.daily_present=false;
   empty.daily.entry_allowed=false;
   empty.daily.primary="";
   empty.daily.n_reasons=0;
   empty.daily.dl_called=false;
   empty.daily.closed_result=0.0;
   empty.daily.cancel_pending_due=false;
   empty.daily.daily_limit_reached=false;
   empty.daily.day_key=0;
   empty.daily_time=0;
   empty.daily_digest="";
   z.g.max_age=60;
   EG_Submit(z.g,z.cfg,GetPointer(z.t),GetPointer(z.s),z.rt,z.spb,empty,z.reg,z.reg_count,z.r,z.dec);
   Check(a && !z.dec.allow && z.r.outcome==EN_R_REFUSED && z.t.sends==0 && z.s.lock_calls==0,"the default gate configuration and empty checks block");
  }

void Scenario_daily_not_bypassed(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      for(int k=0;k<3;k++)
        {
         CGw w;
         w.Init(dir);
         STpPermit tpermit;
         TP_CheckPermit(w.spb.plan,w.c.snap,w.c.lim,w.reg,w.reg_count,tpermit);          // T007 alone would allow
         bool t007=tpermit.allow;
         if(k==0) {w.c.daily.entry_allowed=false; w.c.daily.primary="DAILY_LOSS_LIMIT"; w.c.daily.dl_called=true;}
         if(k==1) {w.c.daily.entry_allowed=true; w.c.daily.dl_called=false;}
         if(k==2) w.c.daily_present=false;
         w.Submit();
         Check(t007 && !w.dec.allow && w.r.outcome==EN_R_REFUSED && w.t.sends==0 && w.s.writes==0,StringFormat("dir %d case %d: the T007 allow does not bypass the T012 result",dir,k));
        }
     }
  }

void Scenario_freshness_and_binding(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CGw w;
      w.Init(dir);
      w.t.now+=100;
      w.t.quote.time=w.t.now;
      w.Submit();
      Check(!w.dec.allow && Has(w.dec.reasons,"STALE") && w.t.sends==0,StringFormat("dir %d: old checks block after time passes",dir));
      CGw v;
      v.Init(dir);
      v.c.snap_digest=v.Digest()+"x";
      v.c.loss_digest="";
      v.c.daily_digest="y";
      v.Submit();
      Check(!v.dec.allow && Has(v.dec.reasons,"SNAPSHOT_FOR_ANOTHER_PLAN") && Has(v.dec.reasons,"LOSS_CHECK_FOR_ANOTHER_PLAN") && Has(v.dec.reasons,"DAILY_FOR_ANOTHER_PLAN") && v.t.sends==0,
            StringFormat("dir %d: checks computed for another plan block",dir));
     }
  }

void Scenario_permit_for_another_or_stale_plan(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CGw w;
      w.Init(dir);
      EG_Decide(w.g,w.spb,w.c,w.reg,w.reg_count,w.t.now,w.dec);
      STpPlan other=w.spb.plan;
      other.volume_out=other.volume_out+0.01;
      SEnRuntime r1;
      EN_RuntimeInit(r1);
      EN_Place(w.cfg,GetPointer(w.t),GetPointer(w.s),r1,other,w.dec.permit,w.r);
      bool a=(w.dec.allow && w.r.outcome==EN_R_REFUSED && Has(w.r.reason,"PERMIT_FOR_ANOTHER_PLAN") && w.t.sends==0);
      w.t.now+=100;
      w.t.quote.time=w.t.now;
      EN_Place(w.cfg,GetPointer(w.t),GetPointer(w.s),r1,w.spb.plan,w.dec.permit,w.r);
      Check(a && w.r.outcome==EN_R_REFUSED && Has(w.r.reason,"PERMIT_STALE") && w.t.sends==0,StringFormat("dir %d: a permit for another plan, and an old permit, are refused by the executor",dir));
     }
  }

void Scenario_repeat_without_second_send(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CGw w;
      w.Init(dir);
      w.Submit();
      bool first=(w.r.outcome==EN_R_PLACED && w.t.sends==1);
      SEnRuntime fresh;
      EN_RuntimeInit(fresh);
      w.SubmitWith(fresh);
      bool again=(w.dec.allow && w.r.outcome==EN_R_DUPLICATE && w.t.sends==1);
      w.Submit();
      Check(first && again && w.r.outcome==EN_R_REFUSED && Has(w.r.reason,"DUPLICATE_CALL") && w.t.sends==1,StringFormat("dir %d: a repeat after a restart and in the same runtime never sends again",dir));
     }
  }

void Scenario_blocks_leave_no_trace(void)
  {
   CGw w;
   w.Init(1);
   w.c.daily_present=false;
   w.Submit();
   bool a=w.Untouched(0);
   w.c.daily_present=true;
   w.Submit();
   Check(a && w.r.outcome==EN_R_PLACED && w.t.sends==1,"a block leaves no trace and a later allowed submit still places exactly once");
  }

void OnStart()
  {
   Print("T015 ENTRY GATE TEST: fake transport and fake store only; no file, no terminal read, no order, no trade.");
   Scenario_allow_all();
   Scenario_every_block();
   Scenario_plan_not_ready();
   Scenario_daily_not_bypassed();
   Scenario_freshness_and_binding();
   Scenario_permit_for_another_or_stale_plan();
   Scenario_repeat_without_second_send();
   Scenario_blocks_leave_no_trace();
   PrintFormat("T015 ENTRY GATE TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
