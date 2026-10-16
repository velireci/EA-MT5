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
   SEoBalance bal;
   int balance_calls;
   int balance_advance;
   CFakeMarket(void)
     {
      balance_calls=0;
      balance_advance=0;
      bal.read_ok=true;
      bal.amount=10000.0;
      bal.time=0;
      bal.demo=true;
      bal.trade_mode=0;
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
      bal.time=tr.now;
     }
   virtual void Balance(SEoBalance &b) {balance_calls++; if(balance_advance!=0) {tr.now+=balance_advance; bal.time=tr.now;} b=bal;}
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
      hook=NULL;
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
   CEgPreSend *hook;
   void StepObs(CObs &ob,const bool feed_ok=true)
     {
      o.Step(cfg,GetPointer(mk),feed_ok,ob.st,ob.f,ob.lvl,ob.Cut(),GetPointer(t),GetPointer(s),out,hook);
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
      forced.previous_context=ob.st.context;
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
         if(k==2) w.mk.sym.tick_size=0.0;
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

void Scenario_market_recovery_rebases(void)
  {
   for(int dir=-1;dir<=1;dir+=2)
      for(int k=0;k<2;k++)
        {
         CW w;
         w.Init(dir);
         CObs before,after;
         before.Make(dir,2);
         after.Make(dir,3);
         w.StepObs(before);
         if(k==0) w.mk.sym.read_ok=false; else w.mk.q.read_ok=false;
         w.StepObs(after);
         bool blocked=(w.out.status=="MARKET_NOT_READY" && w.Untouched());
         w.mk.sym.read_ok=true;
         w.mk.q.read_ok=true;
         w.StepObs(after);
         Check(blocked && w.Untouched() && w.o.baseline==after.Cut(),StringFormat("dir %d market %d: recovery rebases without reviving a candidate",dir,k));
        }
  }

void Scenario_context_fields_rebase(void)
  {
   for(int dir=-1;dir<=1;dir+=2)
      for(int k=0;k<4;k++)
        {
         CW w;
         w.Init(dir);
         CObs before,after;
         before.Make(dir,2);
         after.Make(dir,3);
         w.StepObs(before);
         if(k==0) after.st.context.lower=81;
         if(k==1) after.st.context.upper=119;
         if(k==2) after.st.context.confirmed=START-1;
         if(k==3) {after.st.context.confirmed=START-1; after.st.context.valid_from=START-1;}
         w.StepObs(after);
         Check(w.Untouched() && w.o.baseline==after.Cut(),StringFormat("dir %d context field %d: same IDs still rebase",dir,k));
        }
  }

void Scenario_probe_independent_of_property(void)
  {
   double reported[3]={0.0,0.000001,1000000000.0};
   for(int dir=-1;dir<=1;dir+=2)
      for(int k=0;k<3;k++)
        {
         CW w;
         w.Init(dir);
         w.mk.sym.reported_tick_value=reported[k];
         w.Live();
         Check(w.out.request && w.t.sends==1 && w.mk.calls==2 && w.out.spb.plan.volume_out==(dir==1 ? 0.22 : 0.18),StringFormat("dir %d reported value %g: geometry then probe then sizing",dir,reported[k]));
        }
  }

void TestOffsetValidation(void)
  {
   long values[7]={7200,-50400,50400,99999,7201,4294974496,-50401};
   for(int i=0;i<7;i++)
     {
      int offset=123;
      bool ok=EO_OffsetSeconds(values[i],offset);
      Check(ok==(i<3) && (ok ? offset==values[i] : offset==123),StringFormat("offset %I64d: validate before narrowing",values[i]));
     }
  }

// scripted pre-send hook
class CResHook : public CEgPreSend
  {
public:
   CEnFakeTransport *tr;
   CEnFakeStore *st;
   bool ok;
   int calls;
   int settled;
   long sends_at;
   int writes_at;
   int locks_at;
   int files_at;
   CResHook(void) {tr=NULL; st=NULL; ok=true; calls=0; settled=0; sends_at=-1; writes_at=-1; locks_at=-1; files_at=-1;}
   virtual bool Reserve(const string signal_id,string &reason)
     {
      calls++;
      sends_at=tr.sends;
      writes_at=st.writes;
      locks_at=st.lock_calls;
      files_at=st.n_files;
      reason=(ok ? "" : "INDEX_NOT_SAVED");
      return(ok);
     }
   virtual void Settled(const string signal_id,const SEnResult &res) {settled++;}
  };

void Scenario_reservation_before_every_send(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CW w;
      w.Init(dir);
      CResHook h;
      h.tr=GetPointer(w.t);
      h.st=GetPointer(w.s);
      h.ok=false;
      w.hook=GetPointer(h);
      w.Live();
      string id=w.out.spb.signal_id;
      Check(w.out.status=="RESERVATION_FAILED" && !w.out.request && h.calls==1 && h.sends_at==0 && h.writes_at==0 && h.locks_at==0 && h.files_at==0 && w.Untouched() && !w.o.Handled(id),
            StringFormat("dir %d: a refused reservation places nothing and does not consume the signal",dir));
      h.ok=true;
      CObs b;
      b.Make(dir,3);
      w.StepObs(b);
      Check(w.out.request && w.t.sends==1 && h.settled==1 && w.o.Handled(id),StringFormat("dir %d: the signal is retried at the next build and places once",dir));
      CW x;
      x.Init(dir);
      x.mk.session=TP_SESSION_CLOSED;
      CResHook hb;
      hb.tr=GetPointer(x.t);
      hb.st=GetPointer(x.s);
      x.hook=GetPointer(hb);
      x.Live();
      Check(x.out.status=="GATE_BLOCKED" && hb.calls==0 && hb.settled==0 && x.Untouched(),StringFormat("dir %d: a gate block never reaches the hook",dir));
     }
  }

void Scenario_risk_budget_from_current_balance(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CW w;
      w.Init(dir);
      w.cfg.risk_source=EO_RISK_SOURCE_DEMO_BALANCE_PCT;
      w.cfg.risk_budget=-1.0;                                  // the explicit amount is NOT the fallback
      w.Live();
      Check(w.out.status=="EXECUTOR" && w.out.request && w.out.risk_budget==100.0 && w.out.risk_base==10000.0,StringFormat("dir %d: 1%% of a 10000 balance = 100, one value for the plan and the loss check",dir));
      CW ref;
      ref.Init(dir);
      ref.Live();
      Check(w.out.spb.plan.volume_out==ref.out.spb.plan.volume_out && w.out.spb.plan.risk_model==ref.out.spb.plan.risk_model,StringFormat("dir %d: the plan equals the plan of the explicit amount 100",dir));
      CW h;
      h.Init(dir);
      h.cfg.risk_source=EO_RISK_SOURCE_DEMO_BALANCE_PCT;
      h.cfg.risk_budget=-1.0;
      h.mk.bal.amount=5000.0;
      h.Live();
      Check(h.out.request && h.out.risk_budget==50.0 && h.out.spb.plan.risk_model<=50.0 && h.out.spb.plan.volume_out<w.out.spb.plan.volume_out,StringFormat("dir %d: the budget follows the balance (half the balance, half the budget)",dir));
      Check(w.mk.balance_calls>=2,StringFormat("dir %d: the balance is read at every step",dir));
      CW e;
      e.Init(dir);
      e.mk.bal.read_ok=false;
      e.Live();
      Check(e.out.status=="EXECUTOR" && e.mk.balance_calls==0,StringFormat("dir %d: the explicit-amount source never reads the balance",dir));
      CW u;
      u.Init(dir);
      u.cfg.risk_source=7;
      u.Live();
      Check(u.out.status=="CONFIG_UNSET" && Has(u.out.reason,"risk_source") && u.Untouched(),StringFormat("dir %d: an unknown source value is UNSET",dir));
     }
  }

void Scenario_risk_base_failure_blocks(void)
  {
   string label[7]={"unreadable","zero","negative","not a number","infinite","not demo","stale"};
   for(int d=0;d<2;d++)
      for(int k=0;k<7;k++)
        {
         int dir=(d==0 ? 1 : -1);
         CW w;
         w.Init(dir);
         w.cfg.risk_source=EO_RISK_SOURCE_DEMO_BALANCE_PCT;
         w.cfg.risk_budget=100.0;                               // an explicit amount exists: it must NOT be used as a fallback
         if(k==0) w.mk.bal.read_ok=false;
         if(k==1) w.mk.bal.amount=0.0;
         if(k==2) w.mk.bal.amount=-5.0;
         if(k==3) w.mk.bal.amount=MathSqrt(-1.0);
         if(k==4) w.mk.bal.amount=MathPow(10.0,400.0);
         if(k==5) w.mk.bal.demo=false;
         if(k==6) w.mk.bal.time=w.t.now-1000;
         w.Live();
         Check(w.out.status=="RISK_BASE_NOT_READY" && !w.out.request && w.t.sends==0,StringFormat("%s dir %d: blocked with no fallback",label[k],dir));
        }
  }

void Scenario_cached_feed_market_recheck(void)
  {
   for(int dir=-1;dir<=1;dir+=2)
     {
      CW w;
      w.Init(dir);
      CObs before,after;
      before.Make(dir,2); after.Make(dir,3);
      w.StepObs(before);
      w.mk.q.time=w.t.now-31;
      w.StepObs(after);
      bool stale=(w.out.status=="MARKET_NOT_READY" && w.Untouched());
      w.mk.q.time=w.t.now;
      w.StepObs(after);
      Check(stale && w.out.status=="NO_PLAN" && Starts(w.out.reason,"HISTORICAL") && w.o.baseline==after.Cut() && w.Untouched(),StringFormat("dir %d: fresh quote rechecks cached bars without reviving an outage candidate",dir));
      CW g;
      g.Init(dir);
      g.StepObs(before);
      g.mk.spread=TP_SPREAD_BLOCKED;
      g.StepObs(after);
      bool blocked=(g.out.status=="GATE_BLOCKED" && g.Untouched());
      g.mk.spread=TP_SPREAD_CLEAR;
      g.StepObs(after);
      bool placed=(g.out.request && g.t.sends==1);
      for(int i=0;i<3;i++) g.StepObs(after);
      Check(blocked && placed && g.out.status=="ALREADY_HANDLED" && g.t.sends==1,StringFormat("dir %d: a cleared gate on cached bars sends once, repeated timer checks never duplicate",dir));
      g.StepObs(after,false);
      Check(g.out.status=="FEED_NOT_OK" && g.t.sends==1,StringFormat("dir %d: failed feed blocks cached state",dir));
     }
  }

void Scenario_facts_expose_direction_only_when_known(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CW w;
      w.Init(dir);
      CObs a;
      a.Make(dir,2);
      w.StepObs(a);
      bool early=(w.o.facts.valid && w.o.facts.ctx_direction==dir && w.o.facts.signal_direction==0);
      CObs b;
      b.Make(dir,3);
      w.StepObs(b);
      bool signal=(w.o.facts.valid && w.o.facts.ctx_direction==dir && w.o.facts.signal_direction==dir && w.o.facts.signal_id!="");
      w.StepObs(b,false);
      bool lost=(!w.o.facts.valid && w.o.facts.ctx_direction==0 && w.o.facts.signal_direction==0);
      Check(early && signal && lost,StringFormat("dir %d: the step publishes the known context, the live signal, and nothing when the data is not confirmed",dir));
     }
  }

void Scenario_balance_clock_and_reasons(void)
  {
   for(int dir=-1;dir<=1;dir+=2)
     {
      CW good;
      good.Init(dir);
      good.cfg.risk_source=EO_RISK_SOURCE_DEMO_BALANCE_PCT;
      good.cfg.risk_budget=-1.0;
      good.mk.balance_advance=1;
      good.Live();
      Check(good.out.request && good.t.sends==1 && good.out.risk_budget==100.0,StringFormat("dir %d: a balance read crossing a second stays valid against the later clock",dir));
      string codes[6]={"BALANCE_READ_FAILED","ACCOUNT_NOT_DEMO","BALANCE_INVALID_AMOUNT","BALANCE_TIME_INVALID","BALANCE_FROM_FUTURE","BALANCE_STALE"};
      for(int k=0;k<6;k++)
        {
         CW w;
         w.Init(dir);
         w.cfg.risk_source=EO_RISK_SOURCE_DEMO_BALANCE_PCT;
         if(k==0) w.mk.bal.read_ok=false;
         if(k==1) w.mk.bal.demo=false;
         if(k==2) w.mk.bal.amount=0.0;
         if(k==3) w.mk.bal.time=0;
         if(k==4) w.mk.bal.time=w.t.now+1;
         if(k==5) w.mk.bal.time=w.t.now-31;
         w.Live();
         Check(w.out.status=="RISK_BASE_NOT_READY" && Starts(w.out.reason,codes[k]) && Has(w.out.reason,"read_ok=") && Has(w.out.reason,"demo=") && Has(w.out.reason,"age=") && w.Untouched(),StringFormat("dir %d: %s blocks with specific diagnostics and no fallback",dir,codes[k]));
        }
      for(int k=0;k<2;k++)
        {
         CW slow;
         slow.Init(dir);
         slow.cfg.risk_source=EO_RISK_SOURCE_DEMO_BALANCE_PCT;
         slow.mk.balance_advance=(k==0 ? 31 : -1);
         CObs ob;
         ob.Make(dir,2);
         slow.StepObs(ob);
         Check(slow.Untouched() && (k==0 ? slow.out.status=="MARKET_NOT_READY" && Starts(slow.out.reason,"QUOTE_EXPIRED_DURING_BALANCE_READ") : slow.out.status=="RISK_BASE_NOT_READY" && Starts(slow.out.reason,"RISK_CLOCK_INVALID")),StringFormat("dir %d: slow read or backwards clock %d blocks",dir,k));
        }
     }
  }

// ---- SIMULATION_1PCT_CURRENT_BALANCE (account 358175: the portal says DEMO, MT5 reports REAL): the same 1% whatever the classification, ONLY with the FAKE transport, no fallback
void Scenario_simulation_budget_any_classification(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      int modes[3]={2,0,1};
      bool demos[3]={false,true,false};
      for(int k=0;k<3;k++)
        {
         CW w;
         w.Init(dir);
         w.cfg.risk_source=EO_RISK_SOURCE_SIMULATION_BALANCE_PCT;
         w.cfg.risk_budget=-1.0;
         w.mk.bal.demo=demos[k];
         w.mk.bal.trade_mode=modes[k];
         w.Live();
         CW ref;
         ref.Init(dir);
         ref.Live();
         Check(w.out.status=="EXECUTOR" && w.out.request && w.out.risk_budget==100.0 && w.out.risk_base==10000.0 && w.out.risk_label=="SIMULATION ONLY" && w.out.account_mode==modes[k] &&
               w.out.spb.plan.volume_out==ref.out.spb.plan.volume_out,StringFormat("dir %d mode %d: 1%% of the current balance, the label and the raw account mode, the plan of the explicit 100",dir,modes[k]));
        }
      CW h;
      h.Init(dir);
      h.cfg.risk_source=EO_RISK_SOURCE_SIMULATION_BALANCE_PCT;
      h.cfg.risk_budget=-1.0;
      h.mk.bal.amount=5000.0;
      h.mk.bal.demo=false;
      h.mk.bal.trade_mode=2;
      h.Live();
      Check(h.out.request && h.out.risk_budget==50.0,StringFormat("dir %d: the budget follows the balance",dir));
      CW u;                                                    // the DEMO policy is unchanged
      u.Init(dir);
      u.cfg.risk_source=EO_RISK_SOURCE_DEMO_BALANCE_PCT;
      u.cfg.risk_budget=-1.0;
      u.mk.bal.demo=false;
      u.mk.bal.trade_mode=2;
      u.Live();
      Check(u.out.status=="RISK_BASE_NOT_READY" && Starts(u.out.reason,"ACCOUNT_NOT_DEMO") && u.Untouched(),StringFormat("dir %d: the DEMO policy still refuses a non-demo account",dir));
     }
  }

void Scenario_simulation_failures_and_real_transport(void)
  {
   string label[8]={"unreadable","zero","negative","not a number","infinite","time invalid","future","stale"};
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      for(int k=0;k<8;k++)
        {
         CW w;
         w.Init(dir);
         w.cfg.risk_source=EO_RISK_SOURCE_SIMULATION_BALANCE_PCT;
         w.cfg.risk_budget=100.0;                               // an explicit amount exists: it must NOT be used as a fallback
         w.mk.bal.demo=false;
         w.mk.bal.trade_mode=2;
         if(k==0) w.mk.bal.read_ok=false;
         if(k==1) w.mk.bal.amount=0.0;
         if(k==2) w.mk.bal.amount=-5.0;
         if(k==3) w.mk.bal.amount=MathSqrt(-1.0);
         if(k==4) w.mk.bal.amount=MathPow(10.0,400.0);
         if(k==5) w.mk.bal.time=0;
         if(k==6) w.mk.bal.time=w.t.now+5;
         if(k==7) w.mk.bal.time=w.t.now-1000;
         w.Live();
         Check(w.out.status=="RISK_BASE_NOT_READY" && !w.out.request && w.t.sends==0 && Has(w.out.reason,"account_mode=2 SIMULATION ONLY") && !Has(w.out.reason,"ACCOUNT_NOT_DEMO"),
               StringFormat("%s dir %d: blocked with no fallback, raw account mode and label in the reason",label[k],dir));
        }
      CW r;                                                     // a real transport is refused before anything is read or sent
      r.Init(dir);
      r.cfg.risk_source=EO_RISK_SOURCE_SIMULATION_BALANCE_PCT;
      r.cfg.risk_budget=-1.0;
      r.t.real=true;
      r.mk.bal.demo=false;
      r.mk.bal.trade_mode=2;
      r.Live();
      Check(r.out.status=="SIMULATION_REFUSED" && !r.out.request && r.mk.balance_calls==0 && r.t.sends==0 && r.out.risk_label=="SIMULATION ONLY",StringFormat("dir %d: a real transport is refused before the balance is read",dir));
      CW g;                                                     // the executor's real-transport gates are untouched: a real transport on a non-demo account is refused
      g.Init(dir);
      g.t.real=true;
      g.t.account.demo=false;
      g.cfg.exec.real_authorised=true;
      g.cfg.exec.authorisation=EN_AUTH_PHRASE;
      g.Live();
      Check(!g.out.request && g.t.sends==0 && Has(g.out.reason,"REAL_REQUIRES_DEMO_ACCOUNT"),StringFormat("dir %d: the entry executor still refuses a real transport on a non-demo account",dir));
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
   Scenario_market_recovery_rebases();
   Scenario_context_fields_rebase();
   Scenario_probe_independent_of_property();
   Scenario_reservation_before_every_send();
   Scenario_risk_budget_from_current_balance();
   Scenario_risk_base_failure_blocks();
   Scenario_cached_feed_market_recheck();
   Scenario_balance_clock_and_reasons();
   Scenario_facts_expose_direction_only_when_known();
   Scenario_simulation_budget_any_classification();
   Scenario_simulation_failures_and_real_transport();
   TestOffsetValidation();
   PrintFormat("T016 ENTRY ORCHESTRATOR TEST finished: %d passed, %d failed",g_pass,g_fail);
  }


