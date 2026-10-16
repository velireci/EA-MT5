//+------------------------------------------------------------------+
//| EntryViewTest.mq5                                                |
//| SYNTHETIC test and screenshot helper for the chart view of the   |
//| entry orchestrator (include/EntryOrchestratorView.mqh).          |
//| It evaluates no H4 or M15, produces NO signal, reads NO account  |
//| and sends NOTHING. For each scenario it fills the same read-only|
//| inputs the EA hands to the view with INVENTED numbers placed     |
//| around the current price, calls CEoView.Update, and asserts what |
//| is on the chart (objects, texts, colours, absence of arrows and  |
//| of invented levels). With InpHoldSeconds > 0 every scenario stays|
//| on the chart for that long so the owner can take the screenshots.|
//| What it draws is NOT a setup, NOT a plan of the robot and NOT a  |
//| strategy example. It runs on a chart you do not mind clearing:   |
//| it deletes velo_t016v_ objects of that chart (and nothing else). |
//| UNVERIFIED: not compiled here.                                   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs
#property version "1.00"
#property description "SYNTHETIC test of the chart view: invented numbers around the current price. No signal, no trading, no account read."
#include "../include/EntryOrchestratorView.mqh"

input int InpHoldSeconds=0;         // seconds each scenario stays on the chart (for screenshots); 0 = run the assertions only

int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }

bool Exists(const string name) {return(ObjectFind(0,name)>=0);}
string TextOf(const string name) {return(Exists(name) ? ObjectGetString(0,name,OBJPROP_TEXT) : "");}
long ColorOf(const string name) {return(Exists(name) ? ObjectGetInteger(0,name,OBJPROP_COLOR) : -1);}
bool Has(const string text,const string part) {return(StringFind(text,part)>=0);}

//--- all panel lines joined (velo_t016v_pnl_000, 001, ...)
string PanelText(void)
  {
   string all="";
   for(int i=0;i<30;i++)
     {
      string name=EV_PANEL_PREFIX+StringFormat("%03d",i);
      if(!Exists(name)) break;
      all+=ObjectGetString(0,name,OBJPROP_TEXT)+"\n";
     }
   return(all);
  }

int CountPrefix(const string prefix,const int type)
  {
   int n=0;
   for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--)
     {
      string name=ObjectName(0,i,0,-1);
      if(StringFind(name,prefix)!=0) continue;
      if(type>=0 && (int)ObjectGetInteger(0,name,OBJPROP_TYPE)!=type) continue;
      n++;
     }
   return(n);
  }

int CountGoldZones(void)
  {
   int n=0;
   for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--)
     {
      string name=ObjectName(0,i,0,-1);
      if(StringFind(name,EV_PREFIX+"m15fvg_")!=0) continue;
      if((int)ObjectGetInteger(0,name,OBJPROP_TYPE)!=OBJ_RECTANGLE) continue;
      if(ObjectGetInteger(0,name,OBJPROP_COLOR)==clrGold) n++;
     }
   return(n);
  }

int CountArrowObjects(void)
  {
   int n=0;
   for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--)
     {
      string name=ObjectName(0,i,0,-1);
      if(StringFind(name,EV_PREFIX)!=0) continue;
      int t=(int)ObjectGetInteger(0,name,OBJPROP_TYPE);
      if(t==OBJ_ARROW_UP || t==OBJ_ARROW_DOWN || t==OBJ_ARROW_BUY || t==OBJ_ARROW_SELL || t==OBJ_ARROW_LEFT_PRICE || t==OBJ_ARROW_RIGHT_PRICE) n++;
     }
   return(n);
  }

#define KIND_WAIT_CONTEXT  0
#define KIND_ACCEPTED_2R   1
#define KIND_ACCEPTED_FAR  2
#define KIND_BLOCKED       3

datetime g_cut=0;
double g_mid=0.0;
double g_u=0.0;

//--- the invented inputs of the view for one scenario (BUY: dir=+1, SELL: dir=-1)
void Build(CEoFeed &feed,SEoOutcome &out,const int dir,const int kind)
  {
   datetime h4_now=g_cut-(g_cut%14400);
   feed.keep_view=true;
   feed.cut=g_cut;
   // ---- synthetic closed H4 bars (the bars of the last snapshot): 8 bars, index 7 = last closed
   ArrayResize(feed.hbars,8);
   for(int i=0;i<8;i++)
     {
      feed.hbars[i].time=h4_now-(8-i)*14400;
      feed.hbars[i].open=g_mid-dir*0.5*g_u;
      feed.hbars[i].close=g_mid;
      feed.hbars[i].high=g_mid+4.0*g_u+(i==3 ? 2.0*g_u : 0.0);
      feed.hbars[i].low=g_mid-4.0*g_u-(i==3 ? 2.0*g_u : 0.0);
     }
   feed.dv_have=true;
   feed.dv_n=8;
   H3StateInit(feed.dv_ev.st);
   feed.dv_ev.has_state=true;
   feed.dv_ev.reliable=true;
   feed.dv_ev.nt=3;
   feed.dv_ev.ne=1;
   feed.dv_ev.st.dir=(dir==1 ? H3_BULL : H3_BEAR);
   feed.dv_ev.st.setup_id="SYNTHETIC_SETUP";
   bool reconfirmed=(kind!=KIND_WAIT_CONTEXT);
   feed.dv_ev.st.phase=(reconfirmed ? H3_PH_RECONFIRMED : H3_PH_SWEEP_WAIT);
   bool internal=(dir==-1);                                  // SELL scenarios use the internal sweep, BUY ones the wick setup: both paths are exercised
   feed.dv_ev.st.setup_type=(internal ? "SWEEP" : "WICK");
   datetime sweep_t=feed.hbars[6].time;
   feed.dv_ev.st.sweep_time=sweep_t;
   feed.dv_ev.st.wk_src=sweep_t;
   feed.dv_ev.st.snap_id="SYNTHETIC_SNAP";
   feed.dv_ev.st.snap_price=g_mid+dir*3.0*g_u;
   feed.dv_ev.st.snap_known=feed.hbars[2].time;
   ArrayResize(feed.dv_tracks,3);
   feed.dv_tracks[0].id="H4F_REC"; feed.dv_tracks[0].lower=g_mid+dir*1.0*g_u-0.5*g_u; feed.dv_tracks[0].upper=g_mid+dir*1.0*g_u+0.5*g_u;
   feed.dv_tracks[0].time_a=feed.hbars[5].time; feed.dv_tracks[0].conf=feed.hbars[7].time; feed.dv_tracks[0].invalid=false; feed.dv_tracks[0].recorded=reconfirmed;
   feed.dv_tracks[1].id="H4F_CAND"; feed.dv_tracks[1].lower=g_mid-dir*1.0*g_u-0.5*g_u; feed.dv_tracks[1].upper=g_mid-dir*1.0*g_u+0.5*g_u;
   feed.dv_tracks[1].time_a=feed.hbars[6].time; feed.dv_tracks[1].conf=feed.hbars[7].time+14400; feed.dv_tracks[1].invalid=false; feed.dv_tracks[1].recorded=false;
   feed.dv_tracks[2].id="H4F_INV"; feed.dv_tracks[2].lower=g_mid-dir*3.0*g_u-0.5*g_u; feed.dv_tracks[2].upper=g_mid-dir*3.0*g_u+0.5*g_u;
   feed.dv_tracks[2].time_a=feed.hbars[4].time; feed.dv_tracks[2].conf=feed.hbars[6].time; feed.dv_tracks[2].invalid=true; feed.dv_tracks[2].recorded=false;
   feed.dv_ev.st.rec_id=(reconfirmed ? "H4F_REC" : "");
   ArrayResize(feed.dv_events,1);
   feed.dv_events[0].type=H3_EV_INT_SWEEP;
   feed.dv_events[0].bar_time=sweep_t;
   feed.dv_events[0].ref="IH"+H4TimeStamp(feed.hbars[3].time);          // the pivot bar named by the decision's own event id
   feed.dv_events[0].detail="dir=BEAR;lint=x;sweep=x;restart=0;setup=1;top=1";
   feed.dv_events[0].market=true;
   feed.dv_events[0].sig="";
   feed.dg_have=true; feed.dg_valid=true; feed.dg_ready=reconfirmed; feed.dg_reliable=true; feed.dg_state=true; feed.dg_ctx_ok=reconfirmed;
   feed.dg_phase=(reconfirmed ? "RECONFIRMED" : "SWEEP_WAIT"); feed.dg_direction=(dir==1 ? "BULL" : "BEAR"); feed.dg_reason="SYNTHETIC"; feed.dg_known=g_cut;
   // ---- M15 observer
   M4ContextInit(feed.st.context);
   M4NoLevel(feed.broken);
   ArrayResize(feed.f,0);
   feed.st.has_context=reconfirmed;
   feed.st.phase=(reconfirmed ? "WAIT_RETURN" : "WAIT_CONTEXT");
   feed.st.bos_time=0;
   feed.st.bos_level="";
   if(reconfirmed)
     {
      feed.st.context.direction=dir;
      feed.st.context.setup="SYNTHETIC_CTX";
      feed.st.bos_time=g_cut-6*900;
      feed.st.bos_level="SYNTHETIC_LEVEL";
      feed.broken.valid=true; feed.broken.id="SYNTHETIC_LEVEL"; feed.broken.price=g_mid-dir*2.0*g_u; feed.broken.known=g_cut-14*900;
      ArrayResize(feed.f,3);
      feed.f[0].id="M15F_CHOSEN"; feed.f[0].lower=g_mid+(dir==1 ? -1.0 : 0.2)*g_u; feed.f[0].upper=g_mid+(dir==1 ? -0.2 : 1.0)*g_u; feed.f[0].confirmed=g_cut-3*900; feed.f[0].returned=false; feed.f[0].invalid=false;
      feed.f[1].id="M15F_OTHER"; feed.f[1].lower=g_mid+(dir==1 ? 0.5 : -1.5)*g_u; feed.f[1].upper=g_mid+(dir==1 ? 1.5 : -0.5)*g_u; feed.f[1].confirmed=g_cut-2*900; feed.f[1].returned=false; feed.f[1].invalid=false;
      feed.f[2].id="M15F_INV"; feed.f[2].lower=g_mid+(dir==1 ? -3.0 : 2.0)*g_u; feed.f[2].upper=g_mid+(dir==1 ? -2.0 : 3.0)*g_u; feed.f[2].confirmed=g_cut-5*900; feed.f[2].returned=false; feed.f[2].invalid=true;
     }
   // ---- the outcome of the step
   EO_OutcomeInit(out);
   out.risk_label="SIMULATION ONLY";
   if(kind==KIND_WAIT_CONTEXT) {EO_Set(out,"NO_PLAN","CONTEXT_LOST_OR_NOT_READY"); return;}
   double entry=(dir==1 ? feed.f[0].upper : feed.f[0].lower);
   double risk_dist=1.0*g_u;
   out.spb.plan_ready=true;
   out.spb.candidate_id="M15F_CHOSEN";
   out.spb.signal_id="SYNTHETIC_SIGNAL";
   out.spb.plan.direction=dir;
   out.spb.plan.e_out=entry;
   out.spb.plan.s_out=entry-dir*risk_dist;
   out.spb.plan.level_2r=entry+dir*2.0*risk_dist;
   out.spb.plan.tp=(kind==KIND_ACCEPTED_FAR ? entry+dir*3.0*risk_dist : out.spb.plan.level_2r);
   out.spb.plan.tp_equals_2r=(kind!=KIND_ACCEPTED_FAR);
   out.spb.plan.volume_out=0.10;
   out.spb.plan.risk_model=100.0;
   if(kind==KIND_BLOCKED) {EO_Set(out,"GATE_BLOCKED","SYNTHETIC"); out.dec.reasons="SPREAD_BLOCK | NEWS_UNKNOWN";}
   else {EO_Set(out,"EXECUTOR","SYNTHETIC"); out.request=true;}
  }

void Hold(void)
  {
   ChartRedraw(0);
   for(int s=0;s<InpHoldSeconds*2 && !IsStopped();s++) Sleep(500);
  }

void RunScenario(CEoView &view,const int dir,const int kind,const string title)
  {
   CEoFeed feed;
   SEoOutcome out;
   Build(feed,out,dir,kind);
   view.Update(out,feed,false,true);
   string panel=PanelText();
   string ds=(dir==1 ? "BUY" : "SELL");
   color h4c=(dir==1 ? clrDodgerBlue : clrDarkOrange);
   // ---- always: the mode, the legend, no arrow objects, the manual drawing is untouched
   Check(Has(panel,"SIMULIM - PA URDHRA REALE"),title+": the panel says SIMULIM - PA URDHRA REALE");
   Check(Has(panel,"FAKE / READ_ONLY"),title+": the panel says FAKE / READ_ONLY");
   Check(Has(panel,"VENDIMI: "),title+": the panel has a decision line");
   Check(Has(TextOf(EV_PANEL_PREFIX+"leg0"),"LEGJENDA") && Has(TextOf(EV_PANEL_PREFIX+"leg4"),"ARTE"),title+": the legend is on the chart");
   Check(CountArrowObjects()==0,title+": no entry arrow object (only the dots of the sweep and of the break exist)");
   Check(!Exists(EV_PREFIX+"entry_arrow") && CountPrefix(EV_PREFIX,OBJ_ARROW_BUY)==0 && CountPrefix(EV_PREFIX,OBJ_ARROW_SELL)==0,title+": no buy / sell arrow");
   Check(Exists("MANUAL_VIEW_TEST_LINE"),title+": the manual drawing is untouched");
   Check(Has(panel,"Konfirmuar nga klienti") && Has(panel,"E perkohshme"),title+": the temporary choices are explained in words");
   // ---- H4
   Check(Has(panel,"H4: "+(dir==1 ? "NGRITES (BUY)" : "ZBRITES (SELL)")),title+": H4 direction in words");
   Check(Exists(EV_PREFIX+"sweep_dot") && Exists(EV_PREFIX+"sweep_txt") && Exists(EV_PREFIX+"sweep_lvl"),title+": sweep mark, label and dashed level");
   Check(Has(TextOf(EV_PREFIX+"sweep_txt"),(dir==-1 ? "Sweep H4" : "Fitil H4")),title+": the sweep label names the event");
   Check((int)ObjectGetInteger(0,EV_PREFIX+"sweep_lvl",OBJPROP_STYLE)==STYLE_DASH,title+": the swept level is dashed");
   Check(Exists(EV_PREFIX+"h4fvg_0") && Has(TextOf(EV_PREFIX+"h4fvg_txt0"),"H4"),title+": H4 FVG zone with the label H4");
   Check(!ObjectGetInteger(0,EV_PREFIX+"h4fvg_0",OBJPROP_FILL) && ObjectGetInteger(0,EV_PREFIX+"h4fvg_0",OBJPROP_COLOR)==h4c,title+": H4 FVG is an outline in the direction colour");
   Check(CountPrefix(EV_PREFIX+"h4fvg_",OBJ_RECTANGLE)<=EV_MAX_H4_FVG,title+": the number of H4 zones is limited");
   if(kind==KIND_WAIT_CONTEXT)
     {
      Check(Has(panel,"SWEEP_WAIT")==false && Has(panel,"sweep i brendshem u pa"),title+": the phase is translated (no raw code)");
      Check(Has(TextOf(EV_PREFIX+"h4fvg_txt0"),"kandidat"),title+": before the reconfirmation the H4 FVG is a candidate");
      Check((int)ObjectGetInteger(0,EV_PREFIX+"h4fvg_0",OBJPROP_STYLE)==STYLE_DASH,title+": a candidate H4 FVG is dashed");
      Check(Has(panel,"VENDIMI: PRET"),title+": the decision is PRET");
      Check(Has(panel,"M15 konfirmuar: asgje ende") && Has(panel,"M15 mungon: setup H4 i rikonfirmuar"),title+": M15 says what is missing");
      Check(CountPrefix(EV_PREFIX+"m15fvg_",-1)==0 && !Exists(EV_PREFIX+"brk_line") && !Exists(EV_PREFIX+"entry") && !Exists(EV_PREFIX+"sl") && !Exists(EV_PREFIX+"tp"),title+": no M15 level, no zone, no plan line is invented");
      Check(CountGoldZones()==0,title+": nothing is gold");
      return;
     }
   Check(Has(TextOf(EV_PREFIX+"h4fvg_txt0"),"rikonfirmuar") && (int)ObjectGetInteger(0,EV_PREFIX+"h4fvg_0",OBJPROP_STYLE)==STYLE_SOLID,title+": the reconfirmed H4 FVG is solid and says so");
   // ---- M15
   Check(Exists(EV_PREFIX+"brk_line") && Exists(EV_PREFIX+"brk_dot") && Has(TextOf(EV_PREFIX+"brk_txt"),"Thyerje M15"),title+": M15 break line, candle mark and label 'Thyerje M15'");
   Check(!Has(TextOf(EV_PREFIX+"brk_txt"),"MSS") && Has(ObjectGetString(0,EV_PREFIX+"brk_line",OBJPROP_TOOLTIP),"NUK eshte MSS"),title+": the prototype break is not called a validated MSS");
   Check(CountGoldZones()==1 && ColorOf(EV_PREFIX+"m15fvg_0")==clrGold && Has(TextOf(EV_PREFIX+"m15fvg_txt0"),"ZGJEDHUR"),title+": exactly one gold M15 FVG, the one the plan bridge selected, drawn first");
   Check(Exists(EV_PREFIX+"m15fvg_1") && ColorOf(EV_PREFIX+"m15fvg_1")!=clrGold && Has(TextOf(EV_PREFIX+"m15fvg_txt1"),"kandidat"),title+": another M15 FVG is a plain candidate");
   Check(CountPrefix(EV_PREFIX+"m15fvg_",OBJ_RECTANGLE)<=EV_MAX_M15_FVG,title+": the number of M15 zones is limited");
   Check(Has(panel,"M15 konfirmuar: ") && Has(panel,"thyerje M15") && Has(panel,"M15 mungon: kthimi i cmimit ne FVG"),title+": M15 confirmed / missing in words");
   // ---- plan
   Check(Exists(EV_PREFIX+"entry") && Exists(EV_PREFIX+"sl") && Exists(EV_PREFIX+"tp") && Exists(EV_PREFIX+"entry_txt") && Exists(EV_PREFIX+"sl_txt") && Exists(EV_PREFIX+"tp_txt"),title+": entry, SL and TP lines with labels");
   Check(Has(TextOf(EV_PREFIX+"entry_txt"),"HYRJA LIMIT "+ds) && Has(TextOf(EV_PREFIX+"sl_txt"),"SL ") && Has(TextOf(EV_PREFIX+"tp_txt"),"TP"),title+": the labels carry the names and prices");
   if(kind==KIND_ACCEPTED_FAR)
      Check(Exists(EV_PREFIX+"r2") && Has(TextOf(EV_PREFIX+"r2_txt"),"2R ") && !Has(TextOf(EV_PREFIX+"tp_txt"),"= 2R"),title+": a TP beyond 2R has its own 2R line");
   else
      Check(!Exists(EV_PREFIX+"r2") && Has(TextOf(EV_PREFIX+"tp_txt"),"TP = 2R "),title+": when TP is 2R one line carries both names");
   Check(Has(panel,"PLAN "+ds+" LIMIT: hyrja "),title+": the panel shows the plan");
   if(kind==KIND_BLOCKED)
      Check(Has(panel,"VENDIMI: BLLOKUAR") && Has(panel,"spread shume i larte") && Has(panel,"+1 arsye"),title+": blocked, with a short reason");
   else
     {
      Check(Has(panel,"VENDIMI: KERKESE VIRTUALE"),title+": virtual request");
      // the next step: the signal is handled; the kept plan stays and says so
      SEoOutcome again;
      EO_OutcomeInit(again);
      again.risk_label=out.risk_label;
      again.spb.signal_id=out.spb.signal_id;
      EO_Set(again,"ALREADY_HANDLED",out.spb.signal_id);
      view.Update(again,feed,false,true);
      string p2=PanelText();
      Check(Exists(EV_PREFIX+"entry") && Has(p2,"KERKESE VIRTUALE") && Has(p2,"trajtuar me pare"),title+": the plan of a handled signal stays with its verdict");
      view.Update(out,feed,false,true);
     }
   if(InpHoldSeconds>0)
     {
      string banner=EV_PREFIX+"test_banner";
      ObjectCreate(0,banner,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,banner,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
      ObjectSetInteger(0,banner,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0,banner,OBJPROP_XDISTANCE,10);
      ObjectSetInteger(0,banner,OBJPROP_YDISTANCE,20);
      ObjectSetInteger(0,banner,OBJPROP_COLOR,clrRed);
      ObjectSetInteger(0,banner,OBJPROP_FONTSIZE,10);
      ObjectSetString(0,banner,OBJPROP_TEXT,"SYNTHETIC TEST "+title+" - invented numbers, NOT a signal, NOT a plan of the robot");
      Hold();
      ObjectDelete(0,banner);
     }
  }

void OnStart()
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol,t) || !(t.bid>0.0)) {Print("VIEW TEST: no quote, nothing drawn."); return;}
   g_mid=t.bid;
   g_u=g_mid*0.001;
   datetime now=TimeCurrent();
   g_cut=now-(now%900);
   ObjectCreate(0,"MANUAL_VIEW_TEST_LINE",OBJ_HLINE,0,0,g_mid-20.0*g_u);       // a manual drawing that the view must never touch
   CEoView view;
   view.Init();
   RunScenario(view,-1,KIND_WAIT_CONTEXT,"WAIT_CONTEXT SELL (H4 BEAR, SWEEP_WAIT, M15 waiting)");
   RunScenario(view,1,KIND_WAIT_CONTEXT,"WAIT_CONTEXT BUY");
   RunScenario(view,1,KIND_ACCEPTED_2R,"BUY accepted, TP = 2R");
   RunScenario(view,-1,KIND_ACCEPTED_2R,"SELL accepted, TP = 2R");
   RunScenario(view,1,KIND_ACCEPTED_FAR,"BUY accepted, TP beyond 2R");
   RunScenario(view,-1,KIND_ACCEPTED_FAR,"SELL accepted, TP beyond 2R");
   RunScenario(view,1,KIND_BLOCKED,"BUY blocked by the gate");
   RunScenario(view,-1,KIND_BLOCKED,"SELL blocked by the gate");
   view.Destroy();
   Check(CountPrefix(EV_PREFIX,-1)==0,"Destroy removes every object of the component");
   Check(Exists("MANUAL_VIEW_TEST_LINE"),"the manual drawing survives Destroy");
   ObjectDelete(0,"MANUAL_VIEW_TEST_LINE");
   ChartRedraw(0);
   PrintFormat("EntryViewTest finished: %d passed, %d failed. SYNTHETIC; compile and run were UNVERIFIED until this log exists.",g_pass,g_fail);
  }
