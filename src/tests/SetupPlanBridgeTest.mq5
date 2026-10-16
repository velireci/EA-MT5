// T014 setup -> plan bridge test: one existing T004 candidate -> a TradePlanning plan, or one concrete blocking reason. The T004 observer (M4Init / M4SetContext / M4Step) is driven with closed M15 bars;
// no terminal read, no order, no permit, no file. Mirrors tests/test_spb.py (the scenario names are pinned equal by a Python test). NOT YET COMPILED OR RUN (UNVERIFIED): Codex compiles it, the owner runs it in MT5.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/SetupPlanBridge.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
#define START 14400

class CObs
  {
public:
   SM4State st;
   SM4Candidate f[];
   SM4Event ev[];
   SM4Level lvl;
   int dir;
   void Make(const int direction,const int policy=M4_A_AT_OR_AFTER_BREAK,const string setup="H4SET1",const string fvg="H4F1",const bool selected=true)
     {
      dir=direction;
      M4Init(st,f,ev,policy);
      SM4Context c;
      M4ContextInit(c);
      c.setup=setup;
      c.direction=direction;
      c.source="T003_PROTOTYPE";
      c.fvg=fvg;
      c.lower=80;
      c.upper=120;
      c.confirmed=START;
      c.valid_from=START;
      c.ready=true;
      c.reliable=true;
      c.selected=selected;
      M4SetContext(c,START,st,f,ev);
      lvl.valid=true;
      lvl.id=(direction==-1 ? "L-SELL" : "L-BUY");
      lvl.price=98.0;
      lvl.known=START;
      if(direction==-1)
        {
         Step(0,101,95,96,true);
         Step(1,96,89,90,false);
         Step(2,93,87,88,false);
        }
      else
        {
         Step(0,100,94,99,true);
         Step(1,104,98,103,false);
         Step(2,108,102,107,false);
        }
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
   datetime Asof(void) {return(st.last_asof+900);}
   void AddCandidate(const string id,const double lower,const double upper,const datetime confirmed,const bool returned=false)
     {
      int n=ArraySize(f);
      ArrayResize(f,n+1);
      f[n].id=id;
      f[n].lower=lower;
      f[n].upper=upper;
      f[n].confirmed=confirmed;
      f[n].returned=returned;
      f[n].invalid=false;
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

void Mkt(SSpbMarket &m,const int dir)
  {
   SPB_MarketInit(m);
   m.risk_budget=100.0;
   m.tick_value=1.0;
   m.tick_size=0.01;
   m.digits=2;
   m.point=0.01;
   m.stops_level=0;
   m.has_quote=true;
   m.bid=(dir==-1 ? 90.0 : 108.0);
   m.ask=(dir==-1 ? 90.3 : 108.3);
   m.vol_min=0.01;
   m.vol_step=0.01;
   m.vol_max=100.0;
   m.cap_lots=10.0;
  }

bool Has(const string text,const string part) {return(StringFind(text,part)>=0);}
bool Starts(const string text,const string part) {return(StringFind(text,part)==0);}

void Scenario_sell_plan(void)
  {
   CObs o;
   o.Make(-1);
   SSpbSelection s;
   Sel(s);
   SSpbMarket m;
   Mkt(m,-1);
   SSpbResult r;
   SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),r);
   Check(o.st.phase=="WAIT_RETURN" && r.plan_ready && r.plan.status==TP_OK && r.plan.direction==-1 && r.plan.e_out==93.0 && r.plan.s_out==98.5 && r.candidate_id=="M15F14400D","SELL: the near-side edge, the broken level plus the explicit buffer, candidate M15F14400D");
   STpPlan direct;
   TP_BuildPlan(r.signal_id,r.setup_id,-1,93.0,98.5,false,0.0,100.0,1.0,0.01,2,0.01,0,true,90.0,90.3,0.01,0.01,100.0,10.0,direct);
   Check(direct.e_out==r.plan.e_out && direct.s_out==r.plan.s_out && direct.tp==r.plan.tp && direct.volume_out==r.plan.volume_out && r.plan.volume_out>0.0 && r.plan.tp<r.plan.e_out && r.plan.e_out<r.plan.s_out,
         "SELL: the plan is exactly the TP_BuildPlan result for these inputs (nothing re-computed)");
  }

void Scenario_buy_plan(void)
  {
   CObs o;
   o.Make(1);
   SSpbSelection s;
   Sel(s);
   SSpbMarket m;
   Mkt(m,1);
   SSpbResult r;
   SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),r);
   Check(o.st.phase=="WAIT_RETURN" && r.plan_ready && r.plan.status==TP_OK && r.plan.direction==1 && r.plan.e_out==102.0 && r.plan.s_out==97.5 && r.candidate_id=="M15F14400U","BUY: the near-side edge, the broken level minus the explicit buffer, candidate M15F14400U");
   Check(r.plan.s_out<r.plan.e_out && r.plan.e_out<r.plan.tp && r.plan.volume_out>0.0,"BUY: stop below the entry below the target, volume from the sizing");
  }

void Scenario_explicit_rules(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CObs o;
      o.Make(dir);
      SSpbSelection s;
      Sel(s);
      SSpbMarket m;
      Mkt(m,dir);
      SSpbResult base,far,sup,buf,tgt;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),base);
      s.entry_edge=SPB_EDGE_FAR_SIDE;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),far);
      Check(far.plan_ready && far.plan.e_out==(dir==1 ? 100.0 : 95.0) && far.plan.e_out!=base.plan.e_out,StringFormat("dir %d: the far-side edge",dir));
      Sel(s);
      s.sl_rule=SPB_SL_SUPPLIED;
      s.sl_price=(dir==1 ? 96.0 : 99.0);
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),sup);
      Check(sup.plan_ready && sup.plan.s_out==s.sl_price,StringFormat("dir %d: a supplied stop price",dir));
      Sel(s);
      s.sl_buffer=0.0;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),buf);
      Check(buf.plan_ready && buf.plan.s_out==98.0,StringFormat("dir %d: an explicit buffer of 0.0 is a statement",dir));
      Sel(s);
      s.target_rule=SPB_TGT_SUPPLIED;
      s.target_price=(dir==1 ? 130.0 : 60.0);
      s.target_source="client example E1";
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),tgt);
      Check(tgt.plan_ready && tgt.plan.tp==s.target_price && Has(tgt.provenance,"client example E1"),StringFormat("dir %d: a supplied target with its source",dir));
     }
  }

void Scenario_unset_selections(void)
  {
   string names[17]={"context_source","swing_selector","timing_policy","candidate_selector","candidate_id","entry_edge","sl_rule","sl_buffer","sl_buffer","sl_buffer","sl_price","target_rule",
                     "target_price_and_source","target_price_and_source","live_after","swing_selector","entry_edge"};
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CObs o;
      o.Make(dir);
      SSpbMarket m;
      Mkt(m,dir);
      for(int k=0;k<17;k++)
        {
         SSpbSelection s;
         Sel(s);
         if(k==0) s.context_source="";
         if(k==1) s.swing_selector=SPB_SWING_UNSET;
         if(k==2) s.timing_policy=M4_POLICY_UNSET;
         if(k==3) s.candidate_selector=SPB_CAND_UNSET;
         if(k==4) {s.candidate_selector=SPB_CAND_EXPLICIT_ID; s.candidate_id="";}
         if(k==5) s.entry_edge=SPB_EDGE_UNSET;
         if(k==6) s.sl_rule=SPB_SL_UNSET;
         if(k==7) s.sl_buffer_set=false;
         if(k==8) s.sl_buffer=-0.1;
         if(k==9) s.sl_buffer=MathSqrt(-1.0);
         if(k==10) {s.sl_rule=SPB_SL_SUPPLIED; s.sl_price=0.0;}
         if(k==11) s.target_rule=SPB_TGT_UNSET;
         if(k==12) {s.target_rule=SPB_TGT_SUPPLIED; s.target_price=120.0; s.target_source="";}
         if(k==13) {s.target_rule=SPB_TGT_SUPPLIED; s.target_price=0.0; s.target_source="x";}
         if(k==14) s.live_after=0;
         if(k==15) s.swing_selector=99;
         if(k==16) s.entry_edge=7;
         SSpbResult r;
         SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),r);
         Check(!r.plan_ready && Starts(r.reason,"SELECTION_UNSET") && Has(r.reason,names[k]) && r.setup_id=="" && r.signal_id=="",StringFormat("dir %d unset case %d (%s): BLOCK with its name, no ids, no plan",dir,k,names[k]));
        }
      SSpbSelection z;
      SPB_SelectionInit(z);
      SSpbResult rz;
      SPB_Build(z,m,o.st,o.f,o.lvl,o.Asof(),rz);
      Check(!rz.plan_ready && Has(rz.reason,"context_source") && Has(rz.reason,"swing_selector") && Has(rz.reason,"timing_policy") && Has(rz.reason,"candidate_selector") && Has(rz.reason,"entry_edge") &&
            Has(rz.reason,"sl_rule") && Has(rz.reason,"target_rule") && Has(rz.reason,"live_after"),StringFormat("dir %d: the default selection is all unset",dir));
      SSpbSelection s2;
      Sel(s2);
      SSpbResult r2;
      SPB_Build(s2,m,o.st,o.f,o.lvl,0,r2);
      Check(!r2.plan_ready && Has(r2.reason,"asof"),StringFormat("dir %d: asof unset blocks",dir));
     }
  }

string OtherId(const int dir) {return(dir==1 ? "M15F15300U" : "M15F15300D");}

void Scenario_several_candidates(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CObs o;
      o.Make(dir);
      string first=o.f[0].id;
      double shift=(dir==1 ? 10.0 : -10.0);
      o.AddCandidate(OtherId(dir),o.f[0].lower+shift,o.f[0].upper+shift,o.f[0].confirmed+900);
      SSpbSelection s;
      Sel(s);
      SSpbMarket m;
      Mkt(m,dir);
      SSpbResult r;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof()+2000,r);
      Check(!r.plan_ready && Starts(r.reason,"AMBIGUOUS_CANDIDATES") && Has(r.reason,first) && Has(r.reason,OtherId(dir)),StringFormat("dir %d: several eligible candidates block; the first is never taken",dir));
      s.candidate_selector=SPB_CAND_EXPLICIT_ID;
      s.candidate_id=OtherId(dir);
      SSpbMarket m2;
      Mkt(m2,dir);
      m2.bid=(dir==1 ? 200.0 : 50.0);
      m2.ask=m2.bid+0.3;
      SSpbResult r2;
      SPB_Build(s,m2,o.st,o.f,o.lvl,o.Asof()+2000,r2);
      Check(r2.plan_ready && r2.candidate_id==OtherId(dir),StringFormat("dir %d: an explicit candidate id picks exactly that candidate",dir));
      s.candidate_id="NOPE";
      SSpbResult r3;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof()+2000,r3);
      Check(!r3.plan_ready && Starts(r3.reason,"CANDIDATE_NOT_FOUND"),StringFormat("dir %d: an unknown candidate id blocks",dir));
      CObs p;
      p.Make(dir);
      p.AddCandidate("M15F99999"+(dir==1 ? "U" : "D"),p.f[0].lower,p.f[0].upper,p.f[0].confirmed+900,true);
      Sel(s);
      SSpbResult r4;
      SPB_Build(s,m,p.st,p.f,p.lvl,p.Asof()+2000,r4);
      Check(r4.plan_ready && r4.candidate_id==p.f[0].id,StringFormat("dir %d: a returned candidate is not counted by the sole selector",dir));
     }
  }

void Scenario_invalidation(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CObs o;
      o.Make(dir);
      double shift=(dir==1 ? 10.0 : -10.0);
      o.AddCandidate(OtherId(dir),o.f[0].lower+shift,o.f[0].upper+shift,o.f[0].confirmed+900);
      o.f[0].invalid=true;
      SSpbSelection s;
      Sel(s);
      s.candidate_selector=SPB_CAND_EXPLICIT_ID;
      s.candidate_id=o.f[0].id;
      SSpbMarket m;
      Mkt(m,dir);
      SSpbResult r;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof()+2000,r);
      bool a=(!r.plan_ready && Starts(r.reason,"CANDIDATE_INVALIDATED"));
      Sel(s);
      SSpbMarket m2;
      Mkt(m2,dir);
      m2.bid=(dir==1 ? 200.0 : 50.0);
      m2.ask=m2.bid+0.3;
      SSpbResult r2;
      SPB_Build(s,m2,o.st,o.f,o.lvl,o.Asof()+2000,r2);
      bool b=(r2.plan_ready && r2.candidate_id==OtherId(dir));
      o.f[1].invalid=true;
      SSpbResult r3;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof()+2000,r3);
      Check(a && b && r3.reason=="NO_ELIGIBLE_CANDIDATE",StringFormat("dir %d: an invalidated candidate is never eligible",dir));
     }
   CObs q;
   q.Make(-1);
   q.Step(3,97,90,96,false);
   SSpbSelection s;
   Sel(s);
   SSpbMarket m;
   Mkt(m,-1);
   SSpbResult r;
   SPB_Build(s,m,q.st,q.f,q.lvl,q.Asof(),r);
   Check(q.f[0].invalid && !r.plan_ready && Starts(r.reason,"PHASE_NOT_WAIT_RETURN"),"a real invalidating bar removes the candidate and the phase");
  }

void Scenario_return_already_observed(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CObs o;
      o.Make(dir);
      if(dir==-1) o.Step(3,96,90,94,false);
      else o.Step(3,110,101,105,false);
      SSpbSelection s;
      Sel(s);
      SSpbMarket m;
      Mkt(m,dir);
      SSpbResult r;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),r);
      bool a=(o.st.phase=="RETURN_OBSERVED" && !r.plan_ready && Starts(r.reason,"RETURN_ALREADY_OBSERVED"));
      s.candidate_selector=SPB_CAND_EXPLICIT_ID;
      s.candidate_id=o.f[0].id;
      SSpbResult r2;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),r2);
      Check(a && !r2.plan_ready && Starts(r2.reason,"RETURN_ALREADY_OBSERVED"),StringFormat("dir %d: a return that already happened never becomes a delayed entry",dir));
     }
   CObs p;
   p.Make(-1);
   p.AddCandidate("M15F99999D",93.0,95.0,20000,true);
   SSpbSelection s;
   Sel(s);
   s.candidate_selector=SPB_CAND_EXPLICIT_ID;
   s.candidate_id="M15F99999D";
   SSpbMarket m;
   Mkt(m,-1);
   SSpbResult r;
   SPB_Build(s,m,p.st,p.f,p.lvl,p.Asof()+5000,r);
   Check(!r.plan_ready && Starts(r.reason,"CANDIDATE_RETURN_ALREADY_OBSERVED"),"a candidate flagged as returned is refused even while the phase says WAIT_RETURN");
  }

void Scenario_context_and_phase(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CObs o;
      o.Make(dir);
      SM4Context c=o.st.context;
      c.ready=false;
      M4SetContext(c,o.Asof()+900,o.st,o.f,o.ev);
      SSpbSelection s;
      Sel(s);
      SSpbMarket m;
      Mkt(m,dir);
      SSpbResult r;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),r);
      CObs u;
      u.Make(dir,M4_A_AT_OR_AFTER_BREAK,"H4SET1","H4F1",false);
      SSpbResult r2;
      SPB_Build(s,m,u.st,u.f,u.lvl,u.Asof(),r2);
      Check(r.reason=="CONTEXT_LOST_OR_NOT_READY" && r2.reason=="CONTEXT_LOST_OR_NOT_READY",StringFormat("dir %d: a lost or unselected context blocks",dir));
     }
   CObs o;
   o.Make(-1);
   SSpbSelection s;
   Sel(s);
   SSpbMarket m;
   Mkt(m,-1);
   s.context_source="T002_H4_TOUCH_PROPOSAL";
   SSpbResult r;
   SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),r);
   bool a=Starts(r.reason,"CONTEXT_SOURCE_MISMATCH");
   CObs w;
   w.Make(-1,M4_POLICY_UNSET);
   Sel(s);
   SSpbResult r2;
   SPB_Build(s,m,w.st,w.f,w.lvl,w.Asof(),r2);
   bool b=Starts(r2.reason,"TIMING_MISMATCH");
   o.Step(0,101,95,96,true);                                       // a revised bar: the observer demands a replay
   SSpbResult r3;
   SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),r3);
   Check(a && b && o.st.phase=="REPLAY_REQUIRED" && Starts(r3.reason,"REPLAY_REQUIRED"),"the source and the timing must match the selection; a replay-required observer yields nothing");
   CObs q;
   q.Make(-1);
   bool all=true;
   for(int k=0;k<5;k++)
     {
      SM4Level bad=q.lvl;
      if(k==0) bad.id="OTHER";
      if(k==1) bad.price=0.0;
      if(k==2) bad.known=0;
      if(k==3) bad.known=q.st.bos_time+900;
      if(k==4) bad.valid=false;
      SSpbResult rb;
      SPB_Build(s,m,q.st,q.f,bad,q.Asof(),rb);
      all=all && Starts(rb.reason,"BROKEN_LEVEL_MISMATCH");
     }
   Check(all,"the broken level must be the one the observer recorded");
   CObs z;
   z.Make(-1);
   z.f[0].id="M15F14400U";
   SSpbResult rz;
   SPB_Build(s,m,z.st,z.f,z.lvl,z.Asof(),rz);
   CObs y;
   y.Make(-1);
   y.AddCandidate(y.f[0].id,93.0,95.0,y.f[0].confirmed);
   SSpbResult ry;
   SPB_Build(s,m,y.st,y.f,y.lvl,y.Asof(),ry);
   Check(Starts(rz.reason,"CANDIDATE_DIRECTION_INCONSISTENT") && Starts(ry.reason,"CANDIDATE_IDS_NOT_UNIQUE"),"a candidate against the context direction and duplicate ids block");
  }

void Scenario_future_and_historical(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CObs o;
      o.Make(dir);
      SSpbSelection s;
      Sel(s);
      SSpbMarket m;
      Mkt(m,dir);
      datetime conf=o.f[0].confirmed;
      SSpbResult r;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.st.last_asof-1,r);
      bool a=Starts(r.reason,"FUTURE_DATA");
      CObs p;
      p.Make(dir);
      p.st.last_asof=conf-1;
      SSpbResult r2;
      SPB_Build(s,m,p.st,p.f,p.lvl,conf-1,r2);
      bool b=Starts(r2.reason,"FUTURE_DATA");
      CObs q;
      q.Make(dir);
      datetime asof=q.Asof();
      q.st.last_asof=asof+5;
      SSpbResult r3;
      SPB_Build(s,m,q.st,q.f,q.lvl,asof,r3);
      CObs w;
      w.Make(dir);
      w.st.bos_known=asof+5;
      SSpbResult r4;
      SPB_Build(s,m,w.st,w.f,w.lvl,asof,r4);
      bool c=(Starts(r3.reason,"FUTURE_DATA") && Starts(r4.reason,"FUTURE_DATA"));
      CObs h;
      h.Make(dir);
      SSpbResult r5,r6,r7;
      s.live_after=(long)conf;
      SPB_Build(s,m,h.st,h.f,h.lvl,h.Asof(),r5);
      s.live_after=(long)conf+1;
      SPB_Build(s,m,h.st,h.f,h.lvl,h.Asof(),r6);
      s.live_after=(long)conf-1;
      SPB_Build(s,m,h.st,h.f,h.lvl,h.Asof(),r7);
      Check(a && b && c && Starts(r5.reason,"HISTORICAL_OR_REPLAYED_CANDIDATE") && Starts(r6.reason,"HISTORICAL_OR_REPLAYED_CANDIDATE") && r7.plan_ready,
            StringFormat("dir %d: future observer data and historical / replayed candidates are not signals",dir));
     }
  }

void Scenario_identity_stability(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CObs o1,o2,o3;
      o1.Make(dir);
      o2.Make(dir);
      o3.Make(dir);
      if(dir==-1) o3.Step(3,92,90,91,false);
      else o3.Step(3,108,104,106,false);
      SSpbSelection s;
      Sel(s);
      SSpbMarket m;
      Mkt(m,dir);
      SSpbResult a,b,e3,c;
      SPB_Build(s,m,o1.st,o1.f,o1.lvl,o1.Asof(),a);
      SPB_Build(s,m,o2.st,o2.f,o2.lvl,o2.Asof()+12345,b);
      SPB_Build(s,m,o3.st,o3.f,o3.lvl,o3.Asof(),e3);
      SSpbSelection s2=s;
      s2.candidate_selector=SPB_CAND_EXPLICIT_ID;
      s2.candidate_id=o1.f[0].id;
      s2.entry_edge=SPB_EDGE_FAR_SIDE;
      s2.sl_buffer=1.0;
      SSpbMarket m2=m;
      m2.risk_budget=50.0;
      SPB_Build(s2,m2,o2.st,o2.f,o2.lvl,o2.Asof(),c);
      Check(o3.st.phase=="WAIT_RETURN" && a.plan_ready && b.plan_ready && e3.plan_ready && c.plan_ready && a.setup_id==b.setup_id && a.signal_id==b.signal_id && a.signal_id==e3.signal_id &&
            a.signal_id==c.signal_id && a.setup_id==c.setup_id && StringFind(a.signal_id,a.setup_id+"|M15F")==0,StringFormat("dir %d: a restart, a replay, another asof / selector / edge / buffer / risk keep the same ids",dir));
     }
   CObs o,p,q,r;
   o.Make(-1);
   p.Make(-1,M4_A_AT_OR_AFTER_BREAK,"H4SET2");
   q.Make(-1,M4_A_AT_OR_AFTER_BREAK,"H4SET1","H4F2");
   SSpbSelection s;
   Sel(s);
   SSpbMarket m;
   Mkt(m,-1);
   SSpbResult a,b,c;
   SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),a);
   SPB_Build(s,m,p.st,p.f,p.lvl,p.Asof(),b);
   SPB_Build(s,m,q.st,q.f,q.lvl,q.Asof(),c);
   o.AddCandidate("M15F15300D",93.0,95.0,o.f[0].confirmed+900);
   s.candidate_selector=SPB_CAND_EXPLICIT_ID;
   s.candidate_id="M15F15300D";
   SSpbResult e;
   SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof()+2000,e);
   Check(a.setup_id!=b.setup_id && a.setup_id!=c.setup_id && b.setup_id!=c.setup_id && e.setup_id==a.setup_id && e.signal_id!=a.signal_id,"another setup, another FVG or another candidate gives another id");
  }

void Scenario_plan_refused(void)
  {
   CObs o;
   o.Make(-1);
   SSpbSelection s;
   Sel(s);
   SSpbMarket m;
   Mkt(m,-1);
   m.risk_budget=0.0;
   SSpbResult r;
   SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),r);
   Mkt(m,-1);
   m.tick_size=0.0;
   SSpbResult r2;
   SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),r2);
   Check(!r.plan_ready && Starts(r.reason,"PLAN_REFUSED: ") && !r2.plan_ready && Starts(r2.reason,"PLAN_REFUSED: "),"a plan the builder refuses is a block with its reason");
  }

void Scenario_observer_untouched(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      CObs o;
      o.Make(dir);
      string phase=o.st.phase;
      datetime last=o.st.last_asof;
      int nf=ArraySize(o.f);
      int ne=ArraySize(o.ev);
      string id=o.f[0].id;
      bool ret=o.f[0].returned,inv=o.f[0].invalid;
      SSpbSelection s;
      Sel(s);
      SSpbMarket m;
      Mkt(m,dir);
      SSpbResult r;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),r);
      s.candidate_selector=SPB_CAND_UNSET;
      SPB_Build(s,m,o.st,o.f,o.lvl,o.Asof(),r);
      Check(o.st.phase==phase && o.st.last_asof==last && ArraySize(o.f)==nf && ArraySize(o.ev)==ne && o.f[0].id==id && o.f[0].returned==ret && o.f[0].invalid==inv,StringFormat("dir %d: the observer state is not changed by the bridge",dir));
     }
  }

// mirror of ReturnBeyondLevelAfterBos (tests/test_spb.py): after the BOS the price closes back beyond the level and later forms a near-side FVG.
// BUY rows below; SELL = the exact mirror around 98 (x -> 196 - x, high and low swapped). Steps: 5 base bars, then the LATER bars (first one touching or not).
void RbStep(CObs &o,const int dir,const int i,const double h,const double l,const double c)
  {
   if(dir==1) o.Step(i,h,l,c,i==0);
   else o.Step(i,196.0-l,196.0-h,196.0-c,i==0);
  }
void RbMake(CObs &o,const int dir,const int later,const bool touch_first)
  {
   o.Make(dir);                                            // the standard context; its own bars are replaced below
   M4Init(o.st,o.f,o.ev,M4_A_AT_OR_AFTER_BREAK);
   SM4Context c;
   M4ContextInit(c);
   c.setup="H4SET1"; c.direction=dir; c.source="T003_PROTOTYPE"; c.fvg="H4F1"; c.lower=80; c.upper=120;
   c.confirmed=START; c.valid_from=START; c.ready=true; c.reliable=true; c.selected=true;
   M4SetContext(c,START,o.st,o.f,o.ev);
   RbStep(o,dir,0,100,94,99);
   RbStep(o,dir,1,99,91,92);
   RbStep(o,dir,2,93,90,91);
   RbStep(o,dir,3,95,91.5,95);
   RbStep(o,dir,4,97,94,96.5);
   if(later<1) return;
   RbStep(o,dir,5,97.5,(touch_first ? 93.5 : 94.5),97);
   RbStep(o,dir,6,98,96.5,97.8);
   RbStep(o,dir,7,101,97.5,100.5);
   RbStep(o,dir,8,103,99,102.5);
  }

void Scenario_return_beyond_level(void)
  {
   for(int d=0;d<2;d++)
     {
      int dir=(d==0 ? 1 : -1);
      SSpbSelection s;
      Sel(s);
      SSpbMarket m;
      Mkt(m,dir);
      //--- the refused candidate: created by the observer, refused by the bridge
      CObs a;
      RbMake(a,dir,0,false);
      SSpbResult ra;
      SPB_Build(s,m,a.st,a.f,a.lvl,a.Asof(),ra);
      Check(a.st.phase=="WAIT_RETURN" && ArraySize(a.f)==1 && !ra.plan_ready && Has(ra.reason,"SL_WRONG_SIDE"),
            StringFormat("dir %d: after a return beyond the level the near-side candidate is created and its plan refused SL_WRONG_SIDE",dir));
      //--- a later valid FVG beside the untouched refused one: ambiguous, nothing chosen
      CObs b;
      RbMake(b,dir,4,false);
      SSpbResult rb;
      SPB_Build(s,m,b.st,b.f,b.lvl,b.Asof(),rb);
      Check(ArraySize(b.f)==2 && !b.f[0].returned && Starts(rb.reason,"AMBIGUOUS_CANDIDATES"),StringFormat("dir %d: the refused candidate stays eligible: a later valid one is ambiguous",dir));
      //--- the refused candidate is touched: the global phase no longer blocks the untouched second one, the touched one stays refused
      CObs c;
      RbMake(c,dir,4,true);
      SSpbResult rc,rid,rfirst;
      SPB_Build(s,m,c.st,c.f,c.lvl,c.Asof(),rc);
      SSpbSelection se=s;
      se.candidate_selector=SPB_CAND_EXPLICIT_ID;
      se.candidate_id=(ArraySize(c.f)==2 ? c.f[1].id : "");
      SPB_Build(se,m,c.st,c.f,c.lvl,c.Asof(),rid);
      se.candidate_id=(ArraySize(c.f)==2 ? c.f[0].id : "");
      SPB_Build(se,m,c.st,c.f,c.lvl,c.Asof(),rfirst);
      bool shape=(c.st.phase=="RETURN_OBSERVED" && ArraySize(c.f)==2 && c.f[0].returned && !c.f[0].invalid && !c.f[1].returned && !c.f[1].invalid);
      Check(shape && rc.plan_ready && rc.candidate_id==c.f[1].id && rid.plan_ready && rid.signal_id==rc.signal_id,
            StringFormat("dir %d: RETURN_OBSERVED with a valid untouched candidate builds that candidate (sole or explicit id)",dir));
      Check(shape && !rfirst.plan_ready && rfirst.reason=="CANDIDATE_RETURN_ALREADY_OBSERVED: "+c.f[0].id,StringFormat("dir %d: the touched candidate is never a delayed entry",dir));
      //--- only touched or invalid candidates left: the return still blocks
      if(ArraySize(c.f)==2) c.f[1].invalid=true;
      SSpbResult rd;
      SPB_Build(s,m,c.st,c.f,c.lvl,c.Asof(),rd);
      Check(Starts(rd.reason,"RETURN_ALREADY_OBSERVED"),StringFormat("dir %d: with no valid untouched candidate RETURN_OBSERVED still blocks",dir));
     }
  }

void OnStart()
  {
   Print("T014 SETUP PLAN BRIDGE TEST: the T004 observer with closed bars; no terminal read, no order, no permit, no file, no trade.");
   Scenario_sell_plan();
   Scenario_buy_plan();
   Scenario_explicit_rules();
   Scenario_unset_selections();
   Scenario_several_candidates();
   Scenario_invalidation();
   Scenario_return_already_observed();
   Scenario_context_and_phase();
   Scenario_future_and_historical();
   Scenario_identity_stability();
   Scenario_plan_refused();
   Scenario_observer_untouched();
   Scenario_return_beyond_level();
   PrintFormat("T014 SETUP PLAN BRIDGE TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
