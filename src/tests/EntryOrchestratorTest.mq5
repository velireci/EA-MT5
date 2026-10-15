// T016 entry-orchestrator test (FAKE transport, FAKE store and a SCRIPTED market port): the T004 observer state (driven with closed M15 bars) -> SetupPlanBridge -> EntryGate -> EntryExecutor, BUY and SELL up
// to a FAKE request; blocks without a request; baseline: replay, restart, data defect and context change never create a signal; real data only; the broker probe sizes the plan; an uncertain outcome halts.
// Mirrors tests/test_eo.py (the scenario names are pinned equal by a Python test). NEVER includes a real transport; no terminal read, no file, no order, no trade.
// NOT YET COMPILED OR RUN (UNVERIFIED): Codex compiles it, the owner runs it in MT5.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/EntryOrchestrator.mqh"
#include "../include/EntryTransportFake.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
bool Has(const string text,const string part) {return(StringFind(text,part)>=0);}
bool Starts(const string text,const string part) {return(StringFind(text,part)==0);}
#define START 14400

class CObs
  {
public:
   SM4State st;
   SM4Candidate f[];
   SM4Event ev[];
   SM4Level lvl;
   void Make(const int direction,const int nbars,const string setup="H4SET1")
     {
      M4Init(st,f,ev,M4_A_AT_OR_AFTER_BREAK);
      SM4Context c;
      M4ContextInit(c);
      c.setup=setup;
      c.direction=direction;
      c.source="T003_PROTOTYPE";
      c.fvg="H4F1";
      c.lower=80;
      c.upper=120;
      c.confirmed=START;
      c.valid_from=START;
      c.ready=true;
      c.reliable=true;
      c.selected=true;
      M4SetContext(c,START,st,f,ev);
      lvl.valid=true;
      lvl.id=(direction==-1 ? "L-SELL" : "L-BUY");
      lvl.price=98.0;
      lvl.known=START;
      double rows[9];
      if(direction==-1)
        {
         double r[9]={101,95,96, 96,89,90, 93,87,88};
         ArrayCopy(rows,r);
        }
      else
        {
         double r[9]={100,94,99, 104,98,103, 108,102,107};
         ArrayCopy(rows,r);
        }
      for(int i=0;i<nbars && i<3;i++) Step(i,rows[3*i],rows[3*i+1],rows[3*i+2],i==0);
     }
   string Step(const int i,const double high,const double low,const double close,const bool with_level)
     {
      MqlRates r;
      ZeroMemory(r);
      r.time=START+i*900;
      r.open=close;
      r.high=high;
      r.low=low;
      r.close=close;
      SM4Level none;
      M4NoLevel(none);
      if(with_level) return(M4Step(r,r.time+900,lvl,st,f,ev));
      return(M4Step(r,r.time+900,none,st,f,ev));
     }
   datetime Cut(void) {return(st.last_asof);}
  };

class CFakeMarket : public CEoMarket
  {
public:
   CEnFakeTransport *tr;
   SEoSymbol sym;
   SEoQuote q;
   double eff_tick;
   int calls;
   int fail_call;
   int session,news,spread;
   bool daily_present;
   SDbResult daily;
   CFakeMarket(void)
     {
      tr=NULL;
      eff_tick=1.0;
      calls=0;
      fail_call=0;
      session=TP_SESSION_OPEN;
      news=TP_NEWS_CLEAR;
      spread=TP_SPREAD_CLEAR;
      daily_present=true;
      daily.entry_allowed=true;
      daily.primary="";
      daily.n_reasons=0;
      daily.dl_called=true;
      daily.closed_result=0.0;
      daily.cancel_pending_due=false;
      daily.daily_limit_reached=false;
      daily.day_key=20261015;
     }
   void Setup(CEnFakeTransport *transport,const int dir)
     {
      tr=transport;
      sym.read_ok=true;
      sym.tick_size=0.01;
      sym.digits=2;
      sym.point=0.01;
      sym.stops_level=0;
      sym.vol_min=0.01;
      sym.vol_step=0.01;
      sym.vol_max=100.0;
      sym.reported_tick_value=2.0;           // the REPORTED value differs from the broker's effective one (1.0)
      sym.trade_ok=true;
      q.read_ok=true;
      q.bid=(dir==1 ? 108.0 : 90.0);
      q.ask=q.bid+0.3;
      q.time=tr.now;
     }
   virtual long Now(void) {return(tr.now);}
   virtual void Symbol(SEoSymbol &s) {s=sym;}
   virtual void Quote(SEoQuote &x) {x=q;}
   virtual bool CalcProfit(const bool buy,const double volume,const double e,const double s,double &profit)
     {
      calls++;
      profit=0.0;
      if(fail_call>0 && calls==fail_call) return(false);
      profit=-volume*MathRound(MathAbs(e-s)/sym.tick_size)*eff_tick;
      return(true);
     }
   virtual void Filters(int &sess,int &nw,int &spr) {sess=session; nw=news; spr=spread;}
   virtual bool Daily(const STpPlan &plan,SDbResult &r)
     {
      r=daily;
      return(daily_present);
     }
  };

void Sel(SSpbSelection &s)
  {
   SPB_SelectionInit(s);
   s.context_source="T003_PROTOTYPE";
   s.swing_selector=SPB_SWING_LATEST_FRACTAL_PROPOSAL;
   s.timing_policy=M4_A_AT_OR_AFTER_BREAK;
   s.candidate_selector=SPB_CAND_SOLE_ELIGIBLE;
   s.entry_edge=SPB_EDGE_NEAR_SIDE;
   s.sl_rule=SPB_SL_BROKEN_LEVEL_PRICE;
   s.sl_buffer_set=true;
   s.sl_buffer=0.5;
   s.target_rule=SPB_TGT_NONE_2R_MINIMUM;
   s.live_after=START;
  }

class CW
  {
public:
   CEnFakeTransport t;
   CEnFakeStore s;
   CFakeMarket mk;
   COrchestrator o;
   SEoConfig cfg;
   SEoOutcome out;
   int dir;
   void Init(const int direction)
     {
      dir=direction;
      mk.Setup(GetPointer(t),dir);
      t.quote.bid=mk.q.bid;
      t.quote.ask=mk.q.ask;
      t.quote.time=t.now;
      EO_ConfigInit(cfg);
      Sel(cfg.sel);
      cfg.risk_budget=100.0;
      cfg.lot_cap=10.0;
      cfg.model_tolerance=0.01;
      cfg.max_quote_age=30;
      cfg.open_positions=0;
      cfg.trades_today=0;
      cfg.existing_risk=0.0;
      cfg.max_positions=2;
      cfg.max_trades=3;
      cfg.risk_cap=1000.0;
      cfg.gate.max_age=60;
      cfg.exec.enabled=true;
      cfg.exec.ea_magic=777;
      cfg.exec.symbol="XAUUSD";
      cfg.exec.filling=EN_FILL_RETURN;
      cfg.exec.expiry_mode=EN_EXP_GTC;
      cfg.exec.permit_max_age=60;
      cfg.exec.quote_max_age=30;
     }
   void StepObs(CObs &ob,const bool feed_ok=true)
     {
      o.Step(cfg,GetPointer(mk),feed_ok,ob.st,ob.f,ob.lvl,ob.Cut(),GetPointer(t),GetPointer(s),out);
     }
   void StepWith(COrchestrator &orch,CObs &ob)
     {
      orch.Step(cfg,GetPointer(mk),true,ob.st,ob.f,ob.lvl,ob.Cut(),GetPointer(t),GetPointer(s),out);
     }
   // the early build sets the baseline, the build with the confirmed FVG candidate is the first real signal
   void Live(const int nb_first=2)
     {
      CObs a;
      a.Make(dir,nb_first);
      StepObs(a);
      CObs b;
      b.Make(dir,3);
      StepObs(b);
     }
   bool Untouched(void) {return(t.sends==0 && s.lock_calls==0 && s.writes==0 && s.n_files==0 && !out.request);}
  };

void ToFakeRequest(const int dir)
  {
   CW w;
   w.Init(dir);
   w.Live();
   Check(w.out.status=="EXECUTOR" && w.out.request && w.out.res.outcome==EN_R_PLACED && w.out.label==EO_FAKE_LABEL,StringFormat("dir %d: the chain reaches one FAKE request, labelled as such",dir));
   Check(w.t.sends==1 && w.t.last_request.type==(dir==1 ? EN_TYPE_BUY_LIMIT : EN_TYPE_SELL_LIMIT) && w.t.last_request.price==w.out.spb.plan.e_out && w.t.last_request.sl==w.out.spb.plan.s_out &&
         w.t.last_request.tp==w.out.spb.plan.tp && w.t.last_request.volume==w.out.spb.plan.volume_out,StringFormat("dir %d: the virtual request is exactly the plan",dir));
   Check(w.out.dec.permit.digest==EN_PlanDigest(w.out.spb.plan) && w.o.signals==1,StringFormat("dir %d: the permit is for this plan",dir));
   CObs a;
   a.Make(dir,2);
   Check(w.o.baseline==(long)a.Cut(),StringFormat("dir %d: the baseline is the cut of the first build",dir));
  }

void Scenario_buy_to_fake_request(void) {ToFakeRequest(1);}
void Scenario_sell_to_fake_request(void) {ToFakeRequest(-1);}

void Scenario_replay_baseline_no_signal(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CW w;
      w.Init(dir);
      CObs ob;
      ob.Make(dir,3);                                   // the candidate already exists when the EA starts
      w.StepObs(ob);
      Check(w.out.status=="NO_PLAN" && Starts(w.out.reason,"HISTORICAL_OR_REPLAYED_CANDIDATE") && w.Untouched() && w.o.baseline==(long)ob.Cut(),StringFormat("dir %d: the replay at start is never a signal",dir));
     }
  }

void Scenario_restart_no_double(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CW w;
      w.Init(dir);
      w.Live();
      bool first=w.out.request;
      CObs ob;
      ob.Make(dir,3);
      w.StepObs(ob);
      bool again=(w.out.status=="ALREADY_HANDLED" && w.t.sends==1);
      COrchestrator fresh;
      w.StepWith(fresh,ob);
      bool restart=(w.out.status=="NO_PLAN" && Starts(w.out.reason,"HISTORICAL") && w.t.sends==1);
      COrchestrator forced;
      forced.baseline=1;
      forced.rebase=false;
      forced.key="T003_PROTOTYPE|H4SET1|H4F1";
      forced.have_key=true;
      w.StepWith(forced,ob);
      Check(first && again && restart && w.out.res.outcome==EN_R_DUPLICATE && w.t.sends==1,StringFormat("dir %d: a repeat, a restart and even a lost baseline never send the same signal twice",dir));
     }
  }

void Scenario_defect_rebases(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CW w;
      w.Init(dir);
      CObs o1;
      o1.Make(dir,2);
      w.StepObs(o1);
      CObs none;
      w.StepObs(none,false);
      bool lost=(w.out.status=="FEED_NOT_OK");
      CObs o2;
      o2.Make(dir,3);                                    // the candidate was confirmed while the data was missing
      w.StepObs(o2);
      Check(lost && w.out.status=="NO_PLAN" && Starts(w.out.reason,"HISTORICAL") && w.Untouched(),StringFormat("dir %d: a data defect does not revive a candidate formed during the outage",dir));
     }
  }

void Scenario_context_change_rebases(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CW w;
      w.Init(dir);
      CObs o1;
      o1.Make(dir,2);
      w.StepObs(o1);
      CObs o2;
      o2.Make(dir,3,"H4SET2");
      w.StepObs(o2);
      bool changed=(w.out.status=="NO_PLAN" && Starts(w.out.reason,"HISTORICAL") && w.Untouched());
      CObs o3;
      o3.Make(dir,3);
      SM4Context c=o3.st.context;
      c.ready=false;
      M4SetContext(c,o3.Cut()+900,o3.st,o3.f,o3.ev);     // the context is lost
      w.StepObs(o3);
      bool lostctx=(w.out.status=="NO_PLAN" && w.o.key=="");
      CObs o4;
      o4.Make(dir,3);
      w.StepObs(o4);
      Check(changed && lostctx && Starts(w.out.reason,"HISTORICAL") && w.Untouched(),StringFormat("dir %d: a changed or lost context restarts the baseline",dir));
     }
   CW v;
   v.Init(1);
   CObs hi;
   hi.Make(1,3);
   v.StepObs(hi);
   long high=v.o.baseline;
   v.o.Defect();
   CObs lo;
   lo.Make(1,2);
   v.StepObs(lo);
   Check(v.o.baseline==high,"the baseline never moves backwards");
  }

void Scenario_unset_inputs_block(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      string names[4]={"risk_budget","lot_cap","model_tolerance","max_quote_age"};
      for(int k=0;k<4;k++)
        {
         CW w;
         w.Init(dir);
         if(k==0) w.cfg.risk_budget=-1.0;
         if(k==1) w.cfg.lot_cap=0.0;
         if(k==2) w.cfg.model_tolerance=-1.0;
         if(k==3) w.cfg.max_quote_age=0;
         w.Live();
         Check(w.out.status=="CONFIG_UNSET" && Has(w.out.reason,names[k]) && w.Untouched(),StringFormat("dir %d unset %s: BLOCK, no request",dir,names[k]));
        }
      CW v;
      v.Init(dir);
      SPB_SelectionInit(v.cfg.sel);
      v.Live();
      Check(v.out.status=="NO_PLAN" && Starts(v.out.reason,"SELECTION_UNSET") && v.Untouched(),StringFormat("dir %d: the default T014 selection is all unset",dir));
     }
  }

void Scenario_market_missing_blocks(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      for(int k=0;k<12;k++)
        {
         CW w;
         w.Init(dir);
         string status="MARKET_NOT_READY";
         if(k==0) w.mk.sym.read_ok=false;
         if(k==1) w.mk.sym.trade_ok=false;
         if(k==2) w.mk.sym.reported_tick_value=0.0;
         if(k==3) w.mk.q.read_ok=false;
         if(k==4) w.mk.q.time=w.t.now-31;
         if(k==5) w.mk.q.time=w.t.now+5;
         if(k==6) {w.mk.fail_call=2; status="GATE_BLOCKED";}
         if(k==7) {w.mk.session=TP_SESSION_UNKNOWN; status="GATE_BLOCKED";}
         if(k==8) {w.mk.news=TP_NEWS_UNKNOWN; status="GATE_BLOCKED";}
         if(k==9) {w.mk.spread=TP_SPREAD_UNKNOWN; status="GATE_BLOCKED";}
         if(k==10) {w.mk.daily_present=false; status="GATE_BLOCKED";}
         if(k==11) {w.mk.daily.entry_allowed=false; w.mk.daily.primary="DAILY_LOSS_LIMIT"; status="GATE_BLOCKED";}
         w.Live();
         Check(w.out.status==status && w.Untouched(),StringFormat("dir %d missing data case %d: never zero or CLEAR, no request",dir,k));
        }
     }
  }

void Scenario_gate_blocks_no_request(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      string frag[7]={"INVALID_SNAPSHOT:open_positions","INVALID_SNAPSHOT:trades_today","INVALID_SNAPSHOT:existing_risk","POLICY_UNSET:max_positions","POLICY_UNSET:max_trades_per_day",
                      "POLICY_UNSET:combined_risk_cap","MAX_POSITIONS_REACHED"};
      for(int k=0;k<7;k++)
        {
         CW w;
         w.Init(dir);
         if(k==0) w.cfg.open_positions=-1;
         if(k==1) w.cfg.trades_today=-1;
         if(k==2) w.cfg.existing_risk=-1.0;
         if(k==3) w.cfg.max_positions=-1;
         if(k==4) w.cfg.max_trades=-1;
         if(k==5) w.cfg.risk_cap=-1.0;
         if(k==6) w.cfg.open_positions=2;
         w.Live();
         Check(w.out.status=="GATE_BLOCKED" && Has(w.out.dec.reasons,frag[k]) && w.Untouched(),StringFormat("dir %d exposure / limit case %d: unknown or unset stays a block",dir,k));
        }
     }
   CW w;
   w.Init(-1);
   w.mk.session=TP_SESSION_CLOSED;
   CObs o1;
   o1.Make(-1,2);
   w.StepObs(o1);
   CObs o2;
   o2.Make(-1,3);
   w.StepObs(o2);
   bool blocked=(w.out.status=="GATE_BLOCKED" && w.Untouched());
   w.mk.session=TP_SESSION_OPEN;
   w.StepObs(o2);
   Check(blocked && w.out.request && w.t.sends==1,"a blocked attempt is retried at the next build and places once");
  }

void Scenario_probe_uses_effective_tick(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CW w;
      w.Init(dir);
      w.Live();
      STpPlan direct,reported;
      STpPlan pl=w.out.spb.plan;
      TP_BuildPlan(w.out.spb.signal_id,w.out.spb.setup_id,dir,pl.e_out,pl.s_out,false,0.0,100.0,1.0,0.01,2,0.01,0,true,w.mk.q.bid,w.mk.q.ask,0.01,0.01,100.0,10.0,direct);
      TP_BuildPlan(w.out.spb.signal_id,w.out.spb.setup_id,dir,pl.e_out,pl.s_out,false,0.0,100.0,2.0,0.01,2,0.01,0,true,w.mk.q.bid,w.mk.q.ask,0.01,0.01,100.0,10.0,reported);
      Check(pl.volume_out==direct.volume_out && pl.volume_out!=reported.volume_out && w.mk.calls==2,StringFormat("dir %d: the plan is sized with the effective tick value of the probe",dir));
      CW v;
      v.Init(dir);
      v.mk.fail_call=1;
      v.Live();
      Check(v.out.status=="PROBE_FAILED" && v.Untouched(),StringFormat("dir %d: a failed probe blocks without a property fallback",dir));
     }
  }

void Scenario_halt_after_uncertainty(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CW w;
      w.Init(dir);
      w.t.send_mode=EN_SM_UNCERTAIN_NOT_CREATED;
      w.Live();
      bool first=(w.out.res.outcome==EN_R_RECOVERY && !w.out.request && w.t.sends==1 && w.o.halted!="");
      CObs ob;
      ob.Make(dir,3);
      w.StepObs(ob);
      Check(first && w.out.status=="HALTED" && w.t.sends==1,StringFormat("dir %d: an uncertain outcome halts the layer; nothing is resent",dir));
     }
  }

void OnStart()
  {
   Print("T016 ENTRY ORCHESTRATOR TEST: fake transport, fake store and a scripted market; no file, no terminal read, no order, no trade.");
   Scenario_buy_to_fake_request();
   Scenario_sell_to_fake_request();
   Scenario_replay_baseline_no_signal();
   Scenario_restart_no_double();
   Scenario_defect_rebases();
   Scenario_context_change_rebases();
   Scenario_unset_inputs_block();
   Scenario_market_missing_blocks();
   Scenario_gate_blocks_no_request();
   Scenario_probe_uses_effective_tick();
   Scenario_halt_after_uncertainty();
   PrintFormat("T016 ENTRY ORCHESTRATOR TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
