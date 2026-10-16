//+------------------------------------------------------------------+
//| XauUsdEntryViewDemo.mq5                                          |
//| SYNTHETIC DEMONSTRATION of the chart view of the entry           |
//| orchestrator (EntryOrchestratorView.mqh). It does NOT evaluate   |
//| H4 or M15, produces NO signal, reads NO account and sends        |
//| NOTHING. It fills the same read-only inputs the EA hands to the  |
//| view with INVENTED numbers placed around the current price, so   |
//| the owner can look at the readability of the panel, the M15 and  |
//| the plan objects before a live setup exists. What it draws is    |
//| not a setup, not a plan of the robot and not a strategy example. |
//| Remove the script from the chart to delete its objects.          |
//| UNVERIFIED: not compiled here.                                   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs
#property version "1.00"
#property description "SYNTHETIC chart-view demo: invented numbers around the current price. No signal, no trading, no account read."
#include "include/EntryOrchestratorView.mqh"

enum ENUM_DEMO_OUTCOME {DEMO_FAKE_ACCEPTED=0,DEMO_GATE_BLOCKED=1,DEMO_WAITING_FOR_SETUP=2};
input int InpDirection=-1;                        // -1 = SELL, 1 = BUY (synthetic)
input ENUM_DEMO_OUTCOME InpOutcome=DEMO_FAKE_ACCEPTED;

void OnStart()
  {
   if(InpDirection!=1 && InpDirection!=-1) {Print("DEMO: InpDirection must be 1 or -1."); return;}
   MqlTick t;
   if(!SymbolInfoTick(_Symbol,t) || !(t.bid>0.0)) {Print("DEMO: no quote, nothing drawn."); return;}
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double u=t.bid*0.001;                           // synthetic unit: 0.1% of the price
   int d=InpDirection;
   datetime now=TimeCurrent();
   datetime cut=now-(now%900);
   CEoFeed feed;
   feed.keep_view=false;
   feed.dv_have=false;
   feed.cut=cut;
   M4ContextInit(feed.st.context);
   feed.st.has_context=(InpOutcome!=DEMO_WAITING_FOR_SETUP);
   feed.st.context.direction=d;
   feed.st.context.setup="SYNTHETIC_DEMO_SETUP";
   feed.st.bos_time=cut-6*900;
   feed.st.bos_level="SYNTHETIC_LEVEL";
   feed.st.phase=(InpOutcome==DEMO_WAITING_FOR_SETUP ? "WAIT_CONTEXT" : "WAIT_RETURN");
   M4NoLevel(feed.broken);
   feed.broken.valid=true;
   feed.broken.id="SYNTHETIC_LEVEL";
   feed.broken.price=t.bid-d*2.0*u;
   feed.broken.known=cut-14*900;
   ArrayResize(feed.f,1);
   feed.f[0].id="SYNTHETIC_FVG";
   feed.f[0].lower=t.bid+(d==1 ? -1.0 : 0.2)*u;
   feed.f[0].upper=t.bid+(d==1 ? -0.2 : 1.0)*u;
   feed.f[0].confirmed=cut-3*900;
   feed.f[0].returned=false;
   feed.f[0].invalid=false;
   feed.dg_have=true;
   feed.dg_valid=true;
   feed.dg_ready=true;
   feed.dg_reliable=true;
   feed.dg_state=true;
   feed.dg_ctx_ok=true;
   feed.dg_phase="RECONFIRMED";
   feed.dg_direction=(d==1 ? "BULL" : "BEAR");
   feed.dg_reason="SYNTHETIC";
   feed.dg_known=cut;
   SEoOutcome out;
   EO_OutcomeInit(out);
   out.risk_label="SIMULATION ONLY";
   if(InpOutcome==DEMO_WAITING_FOR_SETUP)
     {
      EO_Set(out,"NO_PLAN","CONTEXT_LOST_OR_NOT_READY");
     }
   else
     {
      double entry=(d==1 ? feed.f[0].upper : feed.f[0].lower);
      double risk_dist=1.0*u;
      out.spb.plan_ready=true;
      out.spb.candidate_id=feed.f[0].id;
      out.spb.signal_id="SYNTHETIC_SIGNAL";
      out.spb.plan.direction=d;
      out.spb.plan.e_out=entry;
      out.spb.plan.s_out=entry-d*risk_dist;
      out.spb.plan.tp=entry+d*2.0*risk_dist;
      out.spb.plan.level_2r=entry+d*2.0*risk_dist;
      out.spb.plan.tp_equals_2r=true;
      out.spb.plan.volume_out=0.10;
      out.spb.plan.risk_model=100.0;
      if(InpOutcome==DEMO_FAKE_ACCEPTED) {EO_Set(out,"EXECUTOR","SYNTHETIC"); out.request=true;}
      else {EO_Set(out,"GATE_BLOCKED","SYNTHETIC"); out.dec.reasons="SPREAD_BLOCK (synthetic)";}
     }
   CEoView view;
   view.Init();
   view.Update(out,feed,false,true);
   string label=EV_PREFIX+"demo_banner";
   ObjectCreate(0,label,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,label,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,label,OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,label,OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,label,OBJPROP_COLOR,clrRed);
   ObjectSetInteger(0,label,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,label,OBJPROP_TEXT,"SYNTHETIC DEMO - invented numbers around the current price; NOT a signal, NOT a plan of the robot");
   ChartRedraw(0);
   PrintFormat("DEMO: synthetic view drawn (%s, direction %d). Remove the script to delete the objects.",EnumToString(InpOutcome),d);
   while(!IsStopped()) Sleep(500);
   ObjectsDeleteAll(0,EV_PREFIX);                  // the view's own prefix and this banner only
   view.Destroy();
  }
