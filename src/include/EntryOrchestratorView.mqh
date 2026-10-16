//+------------------------------------------------------------------+
//| EntryOrchestratorView.mqh                                        |
//|                                                                  |
//| CHART VIEW of the decision the entry orchestrator already took.  |
//| It READS the outcome of the step, the M15 observer state and the |
//| H4 evaluation the feed already computed; it recomputes nothing,  |
//| reads no future bar, invents no level and sends nothing. Every   |
//| input of this file is const or a copy owned by the view, and the |
//| EA calls Update() AFTER the decision step, only when the owner   |
//| asked for the view (InpChartView). With the view off, or on, the |
//| plans, blocks and FAKE requests are the same.                    |
//|                                                                  |
//| H4 layer: the EXISTING CH3BiasDrawer (T003 map, prefix velo_t003_)|
//| is called with the arrays of the LAST snapshot of the build. It  |
//| is the only owner of those objects; do not run the T003 EA on the|
//| same chart. M15 + plan + panel objects: prefix velo_t016v_ only; |
//| manual drawings are never touched.                               |
//|                                                                  |
//| Text is Albanian WITHOUT diacritics (the sources are ASCII).     |
//| Tags: [K] = confirmed by the client in the preset labels         |
//|       [P] = temporary simulation choice (DEMO-PROPOSAL / SIMULATION)|
//| The tags mirror the labels of src/presets/*_simulation_fake.set  |
//| (pinned by tests/test_view.py). The view is NOT evidence that the|
//| prototype matches the client's strategy.                         |
//|                                                                  |
//| NOT YET COMPILED OR SEEN IN MT5 (UNVERIFIED).                    |
//+------------------------------------------------------------------+
#ifndef VELO_ENTRY_ORCHESTRATOR_VIEW_MQH
#define VELO_ENTRY_ORCHESTRATOR_VIEW_MQH

#include "EntryOrchestratorFeed.mqh"
#include "H4BiasDrawer.mqh"
#include "StatusPanel.mqh"

#define EV_PREFIX        "velo_t016v_"
#define EV_PANEL_PREFIX  "velo_t016v_pnl_"
#define EV_TAG_CONFIRMED "[K]"
#define EV_TAG_PROPOSAL  "[P]"

//--- the plan the chart keeps after the step that built it (the orchestrator keeps only geometry once a signal is handled)
struct SEvPlan
  {
   bool     have;
   int      direction;
   double   entry;
   double   sl;
   double   tp;
   double   level_2r;
   double   volume;
   double   risk;
   bool     tp_is_2r;
   string   signal_id;
   string   setup;
   string   decision;      // Albanian one-liner of what the step did with the plan
   datetime t0;
  };

void EV_PlanInit(SEvPlan &p)
  {
   p.have=false;
   p.direction=0;
   p.entry=0.0; p.sl=0.0; p.tp=0.0; p.level_2r=0.0; p.volume=0.0; p.risk=0.0;
   p.tp_is_2r=false;
   p.signal_id="";
   p.setup="";
   p.decision="";
   p.t0=0;
  }

string EV_Clip(const string text,const int n)
  {
   if(StringLen(text)<=n) return(text);
   return(StringSubstr(text,0,n-3)+"...");
  }

string EV_Price(const double p,const int digits)
  {
   return(MathIsValidNumber(p) ? DoubleToString(p,digits) : "n/a");
  }

string EV_DirectionText(const int direction)
  {
   if(direction==1) return("BUY");
   if(direction==-1) return("SELL");
   return("?");
  }

string EV_H4DirectionText(const string direction)
  {
   if(direction=="BULL") return("ngritese (BUY)");
   if(direction=="BEAR") return("zbritese (SELL)");
   return("pa drejtim");
  }

//--- what the M15 observer waits for, from its own phase (no new rule)
string EV_M15PhaseText(const string phase,const bool has_context)
  {
   if(phase=="WAIT_CONTEXT" || !has_context) return("pret kontekst H4 te vlefshem");
   if(phase=="WAIT_BREAK") return("pret thyerjen e nivelit M15 (BOS)");
   if(phase=="WAIT_FVG") return("BOS u pa; pret FVG M15");
   if(phase=="WAIT_RETURN") return("FVG M15 ekziston; pret kthimin e cmimit ne FVG");
   if(phase=="RETURN_OBSERVED") return("cmimi u kthye ne FVG; pa hyrje te vonuar");
   if(phase=="REPLAY_REQUIRED") return("histori e rishikuar; pret rindertim");
   if(phase=="WAIT_POLICY") return("pret politiken e kohes se FVG");
   return("faza "+phase);
  }

//--- the decision of the step in words; the English status and reason stay in the last panel line
string EV_StatusText(const SEoOutcome &o)
  {
   string s=o.status;
   if(s=="FEED_NOT_OK") return("PRET te dhenat H4/M15 (feed jo gati)");
   if(s=="HALTED") return("NDALUAR nga mbrojtja: "+EV_Clip(o.reason,70));
   if(s=="CONFIG_UNSET") return("BLLOKUAR: konfigurim i paplote "+EV_Clip(o.reason,60));
   if(s=="MARKET_NOT_READY") return("PRET tregun (kuota/simboli): "+EV_Clip(o.reason,60));
   if(s=="SIMULATION_REFUSED") return("BLLOKUAR: politika SIMULATION lejohet vetem me hyrje FAKE");
   if(s=="RISK_BASE_NOT_READY") return("PRET bazen e riskut (balanca): "+EV_Clip(o.reason,60));
   if(s=="NO_PLAN")
     {
      if(StringFind(o.reason,"CONTEXT_LOST_OR_NOT_READY")==0) return("PRET setup H4 te rikonfirmuar; plan nuk ka");
      return("PA PLAN: "+EV_Clip(o.reason,76));
     }
   if(s=="ALREADY_HANDLED") return("Sinjali u trajtua me pare; nuk dergohet perseri");
   if(s=="PROBE_FAILED") return("Plani NDALOHET: matja e humbjes nga brokeri deshtoi");
   if(s=="GATE_BLOCKED") return("Plani u NDERTUA por porta e BLLOKON: "+EV_Clip(o.dec.reasons,60));
   if(s=="RESERVATION_FAILED") return("Rezervimi deshtoi; asgje nuk u vendos, sinjali mbetet i lire");
   if(s=="EXECUTOR")
     {
      if(o.request) return("Plani u PRANUA: kerkese FAKE (virtuale); asgje nuk shkon te brokeri");
      return("Ekzekutuesi nuk vendosi kerkese: "+EV_Clip(o.reason,60));
     }
   return(s+" "+EV_Clip(o.reason,70));
  }

//--- one chart object helper set (prefix velo_t016v_ only)
class CEoView
  {
private:
   bool            m_on;
   long            m_chart;
   int             m_digits;
   CStatusPanel    m_panel;
   CH3BiasDrawer   m_h4;
   SH3View         m_h4v;
   bool            m_h4_drawn;
   datetime        m_h4_cut;
   string          m_signature;
   SEvPlan         m_plan;

   bool Ensure(const string name,const ENUM_OBJECT type)
     {
      if(ObjectFind(m_chart,name)>=0) return(true);
      if(!ObjectCreate(m_chart,name,type,0,0,0)) {ResetLastError(); return(false);}
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
      return(true);
     }
   void Segment(const string name,const datetime t1,const double p1,const datetime t2,const double p2,const color clr,const int width,const ENUM_LINE_STYLE style,const string tip)
     {
      if(!Ensure(name,OBJ_TREND)) return;
      ObjectSetInteger(m_chart,name,OBJPROP_TIME,0,t1);
      ObjectSetDouble(m_chart,name,OBJPROP_PRICE,0,p1);
      ObjectSetInteger(m_chart,name,OBJPROP_TIME,1,t2);
      ObjectSetDouble(m_chart,name,OBJPROP_PRICE,1,p2);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(m_chart,name,OBJPROP_WIDTH,width);
      ObjectSetInteger(m_chart,name,OBJPROP_STYLE,style);
      ObjectSetInteger(m_chart,name,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(m_chart,name,OBJPROP_BACK,false);
      ObjectSetString(m_chart,name,OBJPROP_TOOLTIP,tip);
     }
   void Box(const string name,const datetime t1,const double p1,const datetime t2,const double p2,const color clr,const bool fill,const string tip)
     {
      if(!Ensure(name,OBJ_RECTANGLE)) return;
      ObjectSetInteger(m_chart,name,OBJPROP_TIME,0,t1);
      ObjectSetDouble(m_chart,name,OBJPROP_PRICE,0,p1);
      ObjectSetInteger(m_chart,name,OBJPROP_TIME,1,t2);
      ObjectSetDouble(m_chart,name,OBJPROP_PRICE,1,p2);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(m_chart,name,OBJPROP_FILL,fill);
      ObjectSetInteger(m_chart,name,OBJPROP_BACK,true);
      ObjectSetInteger(m_chart,name,OBJPROP_WIDTH,1);
      ObjectSetString(m_chart,name,OBJPROP_TOOLTIP,tip);
     }
   void Note(const string name,const datetime t,const double p,const string text,const color clr,const ENUM_ANCHOR_POINT anchor,const string tip)
     {
      if(!Ensure(name,OBJ_TEXT)) return;
      ObjectSetInteger(m_chart,name,OBJPROP_TIME,0,t);
      ObjectSetDouble(m_chart,name,OBJPROP_PRICE,0,p);
      ObjectSetString(m_chart,name,OBJPROP_TEXT,text);
      ObjectSetString(m_chart,name,OBJPROP_TOOLTIP,tip);
      ObjectSetString(m_chart,name,OBJPROP_FONT,"Arial");
      ObjectSetInteger(m_chart,name,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(m_chart,name,OBJPROP_ANCHOR,anchor);
     }
   //--- delete the M15 / plan objects of this component; the panel labels (EV_PANEL_PREFIX) and every other prefix stay
   void ClearObjects(void)
     {
      for(int i=ObjectsTotal(m_chart,0,-1)-1;i>=0;i--)
        {
         string name=ObjectName(m_chart,i,0,-1);
         if(StringFind(name,EV_PREFIX)!=0) continue;
         if(StringFind(name,EV_PANEL_PREFIX)==0) continue;
         ObjectDelete(m_chart,name);
        }
     }
   //--- the plan of this step, or the kept plan of the same signal; dropped as soon as its H4 setup is no longer the live context
   void TrackPlan(const SEoOutcome &out,const CEoFeed &feed)
     {
      bool pass2=(out.status=="GATE_BLOCKED" || out.status=="EXECUTOR" || out.status=="RESERVATION_FAILED");
      if(pass2 && out.spb.plan_ready && feed.st.has_context)
        {
         m_plan.have=true;
         m_plan.direction=out.spb.plan.direction;
         m_plan.entry=out.spb.plan.e_out;
         m_plan.sl=out.spb.plan.s_out;
         m_plan.tp=out.spb.plan.tp;
         m_plan.level_2r=out.spb.plan.level_2r;
         m_plan.volume=out.spb.plan.volume_out;
         m_plan.risk=out.spb.plan.risk_model;
         m_plan.tp_is_2r=out.spb.plan.tp_equals_2r;
         m_plan.signal_id=out.spb.signal_id;
         m_plan.setup=feed.st.context.setup;
         m_plan.decision=EV_StatusText(out);
         m_plan.t0=(feed.st.bos_time>0 ? feed.st.bos_time : feed.cut-8*900);
         return;
        }
      if(m_plan.have && out.status=="ALREADY_HANDLED" && out.spb.signal_id==m_plan.signal_id) return;      // the kept plan of the handled signal
      if(m_plan.have && (!feed.st.has_context || feed.st.context.setup!=m_plan.setup)) EV_PlanInit(m_plan);
     }
   void DrawH4(const CEoFeed &feed)
     {
      if(!feed.dv_have)
        {
         if(m_h4_drawn) {m_h4.ClearAll(); m_h4_drawn=false; m_h4_cut=0;}
         return;
        }
      if(m_h4_drawn && m_h4_cut==feed.cut) return;
      string no_ids[];
      ArrayResize(no_ids,0);
      m_h4.Draw(feed.hbars,feed.dv_n,feed.params,feed.dv_ev,feed.dv_tracks,feed.dv_events,no_ids,0,8,6,false,false,true,4,false,m_h4v);
      m_h4_drawn=true;
      m_h4_cut=feed.cut;
     }
   void DrawM15(const SEoOutcome &out,const CEoFeed &feed)
     {
      if(!feed.st.has_context) return;
      int d=feed.st.context.direction;
      color base=(d==1 ? clrDodgerBlue : clrTomato);
      datetime end=feed.cut+16*900;
      if(feed.st.bos_time>0 && feed.broken.valid && feed.broken.id==feed.st.bos_level)
        {
         Segment(EV_PREFIX+"bos_line",feed.broken.known,feed.broken.price,feed.st.bos_time,feed.broken.price,clrOrange,2,STYLE_SOLID,
                 "Niveli M15 i thyer (propozim, jo MSS i vleresuar nga klienti): "+feed.broken.id);
         Note(EV_PREFIX+"bos_txt",feed.st.bos_time,feed.broken.price,"BOS M15 (P) "+EV_Price(feed.broken.price,m_digits),clrOrange,(d==1 ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER),
              "Bari qe mbylli matane nivelit: "+TimeToString(feed.st.bos_time,TIME_DATE|TIME_MINUTES));
        }
      int shown=0;
      for(int i=ArraySize(feed.f)-1;i>=0 && shown<4;i--)
        {
         if(feed.f[i].invalid) continue;
         bool chosen=(out.spb.candidate_id!="" && feed.f[i].id==out.spb.candidate_id);
         datetime left=feed.f[i].confirmed-2700;
         string state=(feed.f[i].returned ? "cmimi u kthye" : "pret kthimin");
         Box(EV_PREFIX+"fvg_"+IntegerToString(shown),left,feed.f[i].lower,end,feed.f[i].upper,(chosen ? clrGold : clrDimGray),chosen,
             (chosen ? "FVG M15 i ZGJEDHUR (P): " : "FVG M15 kandidat (P): ")+feed.f[i].id+" | "+state);
         if(chosen) Note(EV_PREFIX+"fvg_txt",left,(d==1 ? feed.f[i].upper : feed.f[i].lower),"FVG M15 zgjedhur (P)",clrGold,(d==1 ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER),
                         "Skaji i ketij FVG percakton hyrjen LIMIT (zgjedhja e skajit: konfirmuar)");
         shown++;
        }
      if(m_plan.have)
        {
         color pc=(m_plan.direction==1 ? clrDodgerBlue : clrTomato);
         datetime t0=m_plan.t0;
         Segment(EV_PREFIX+"entry",t0,m_plan.entry,end,m_plan.entry,pc,2,STYLE_SOLID,"HYRJA LIMIT "+EV_DirectionText(m_plan.direction)+" "+EV_Price(m_plan.entry,m_digits));
         Segment(EV_PREFIX+"sl",t0,m_plan.sl,end,m_plan.sl,clrRed,2,STYLE_SOLID,"SL (P) "+EV_Price(m_plan.sl,m_digits));
         Segment(EV_PREFIX+"tp",t0,m_plan.tp,end,m_plan.tp,clrLimeGreen,2,STYLE_SOLID,"TP (P) "+EV_Price(m_plan.tp,m_digits)+(m_plan.tp_is_2r ? " = 2R" : ""));
         if(!m_plan.tp_is_2r)
            Segment(EV_PREFIX+"r2",t0,m_plan.level_2r,end,m_plan.level_2r,clrLimeGreen,1,STYLE_DOT,"Niveli 2R "+EV_Price(m_plan.level_2r,m_digits));
         Note(EV_PREFIX+"entry_txt",end,m_plan.entry,"LIMIT "+EV_DirectionText(m_plan.direction)+" "+EV_Price(m_plan.entry,m_digits)+"  vol "+DoubleToString(m_plan.volume,2),pc,ANCHOR_LEFT,
              "Hyrja LIMIT [K skaji]. Volumi "+DoubleToString(m_plan.volume,2)+" | risku i modeluar "+DoubleToString(m_plan.risk,2));
         Note(EV_PREFIX+"sl_txt",end,m_plan.sl,"SL "+EV_Price(m_plan.sl,m_digits),clrRed,ANCHOR_LEFT,"Stop loss (zgjedhje e perkohshme)");
         Note(EV_PREFIX+"tp_txt",end,m_plan.tp,"TP"+(m_plan.tp_is_2r ? " = 2R " : " ")+EV_Price(m_plan.tp,m_digits),clrLimeGreen,ANCHOR_LEFT,"Target (zgjedhje e perkohshme)");
        }
     }
   void DrawPanel(const SEoOutcome &out,const CEoFeed &feed,const bool real_entry,const bool mgmt_read_only)
     {
      m_panel.Begin();
      if(real_entry || !mgmt_read_only) m_panel.Line("!! TRANSPORT REAL I ZGJEDHUR - jo ky simulim FAKE/READ_ONLY !!",clrRed);
      else m_panel.Line("SIMULIM / FAKE / READ_ONLY - asnje porosi reale nuk dergohet",clrOrange);
      if(out.risk_label!="") m_panel.Line("Risku: "+out.risk_label+" (1% e balances aktuale) "+EV_TAG_PROPOSAL+" | prototip, jo strategji e vleresuar nga klienti",clrSilver);
      else m_panel.Line("Prototip simulimi, jo strategji e vleresuar nga klienti. "+EV_TAG_CONFIRMED+"=konfirmuar "+EV_TAG_PROPOSAL+"=zgjedhje e perkohshme",clrSilver);
      //--- H4: the T003 result the build already computed for the last snapshot
      if(feed.dg_have)
        {
         m_panel.Line("H4 "+EV_TAG_PROPOSAL+": "+EV_H4DirectionText(feed.dg_direction)+" | faza "+feed.dg_phase+" | rikonfirmuar "+(feed.dg_ready ? "PO" : "JO")+" | i besueshem "+(feed.dg_reliable ? "PO" : "JO"),
                      (feed.dg_ready && feed.dg_reliable ? clrLimeGreen : clrWhite));
         if(!feed.dg_reliable) m_panel.Line("  arsyeja: "+EV_Clip(feed.dg_reason,80),clrGray);
         if(m_h4v.setup_text!="") m_panel.Line("  setup H4: "+EV_Clip(m_h4v.setup_text,84),clrGray);
         if(m_h4v.fvg_last!="") m_panel.Line("  FVG H4: "+EV_Clip(m_h4v.fvg_last,84),clrGray);
         if(m_h4v.liq_text!="") m_panel.Line("  likuiditet: "+EV_Clip(m_h4v.liq_text,84),clrGray);
        }
      else m_panel.Line("H4 "+EV_TAG_PROPOSAL+": nuk ka vleresim T003 per kete grafik (feed jo gati ose burimi nuk eshte T003)",clrGray);
      //--- M15: the observer state
      m_panel.Line("M15 "+EV_TAG_PROPOSAL+": "+EV_M15PhaseText(feed.st.phase,feed.st.has_context),clrWhite);
      if(feed.st.has_context && feed.st.bos_time>0)
        {
         string lvl=(feed.broken.valid && feed.broken.id==feed.st.bos_level ? EV_Price(feed.broken.price,m_digits) : "n/a (niveli nuk riprodhohet)");
         m_panel.Line("  BOS "+TimeToString(feed.st.bos_time,TIME_DATE|TIME_MINUTES)+" thyen "+lvl+(out.spb.candidate_id!="" ? " | FVG zgjedhur "+EV_Clip(out.spb.candidate_id,40) : ""),clrGray);
        }
      //--- plan
      if(m_plan.have)
        {
         m_panel.Line("PLAN "+EV_DirectionText(m_plan.direction)+" LIMIT hyrja "+EV_Price(m_plan.entry,m_digits)+" "+EV_TAG_CONFIRMED+"skaji | SL "+EV_Price(m_plan.sl,m_digits)+" "+EV_TAG_PROPOSAL+
                      " | TP "+EV_Price(m_plan.tp,m_digits)+(m_plan.tp_is_2r ? " =2R " : " ")+EV_TAG_PROPOSAL,(m_plan.direction==1 ? clrDodgerBlue : clrTomato));
         m_panel.Line("  vol "+DoubleToString(m_plan.volume,2)+" | risku i modeluar "+DoubleToString(m_plan.risk,2)+" | sinjali "+EV_Clip(m_plan.signal_id,50),clrGray);
         m_panel.Line(m_plan.decision,clrWhite);
        }
      m_panel.Line(EV_StatusText(out),(out.request ? clrLimeGreen : (out.status=="GATE_BLOCKED" ? clrOrange : clrWhite)));
      m_panel.Line(out.status+" | "+EV_Clip(out.reason,90),clrDimGray);
      m_panel.End();
     }

public:
   CEoView(void)
     {
      m_on=false;
      m_chart=0;
      m_digits=2;
      m_h4_drawn=false;
      m_h4_cut=0;
      m_signature="";
      EV_PlanInit(m_plan);
     }
   void Init(void)
     {
      m_on=true;
      m_chart=ChartID();
      m_digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
      m_h4.Init(clrTomato,clrDodgerBlue,clrOrange,8);          // clears velo_t003_ objects left by a previous instance (that prefix only)
      H3VViewInit(m_h4v);
      m_panel.Init(EV_PANEL_PREFIX,true,CORNER_LEFT_UPPER);
      ObjectsDeleteAll(m_chart,EV_PREFIX);                      // this component's own prefix only
     }
   //--- called by the EA after the decision step; reads only
   void Update(const SEoOutcome &out,const CEoFeed &feed,const bool real_entry,const bool mgmt_read_only)
     {
      if(!m_on) return;
      TrackPlan(out,feed);
      DrawH4(feed);
      string sig=out.status+"|"+out.reason+"|"+TimeToString(feed.cut,TIME_DATE|TIME_MINUTES)+"|"+feed.st.phase+"|"+feed.st.bos_level+"|"+out.spb.candidate_id+"|"+
                 (m_plan.have ? EV_Price(m_plan.entry,m_digits)+EV_Price(m_plan.sl,m_digits)+EV_Price(m_plan.tp,m_digits)+m_plan.signal_id : "-")+"|"+IntegerToString(ArraySize(feed.f));
      if(sig!=m_signature)
        {
         m_signature=sig;
         ClearObjects();
         DrawM15(out,feed);
        }
      DrawPanel(out,feed,real_entry,mgmt_read_only);
      ChartRedraw(m_chart);
     }
   void Destroy(void)
     {
      if(!m_on) return;
      m_panel.Destroy();
      ObjectsDeleteAll(m_chart,EV_PREFIX);
      m_h4.ClearAll();
      ChartRedraw(m_chart);
      m_on=false;
     }
  };
#endif
