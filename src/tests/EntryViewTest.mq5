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
string g_ctx="";                    // what is on the chart right now (the rows and tooltips of the boxes), printed with every FAIL
void Check(const bool ok,const string message,const string detail="")
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else
     {
      g_fail++;
      Print("FAIL ",message);
      if(detail!="") Print("     detail: ",detail);
      if(g_ctx!="") Print("     chart : ",g_ctx);
     }
  }

bool Exists(const string name) {return(ObjectFind(0,name)>=0);}
string TextOf(const string name) {return(Exists(name) ? ObjectGetString(0,name,OBJPROP_TEXT) : "");}
long ColorOf(const string name) {return(Exists(name) ? ObjectGetInteger(0,name,OBJPROP_COLOR) : -1);}
bool Has(const string text,const string part) {return(StringFind(text,part)>=0);}

//--- all rows of a box joined (continuation rows, which start with two spaces, are glued to the previous row)
string BoxText(const string prefix)
  {
   string all="";
   for(int i=0;i<60;i++)
     {
      string name=prefix+StringFormat("%03d",i);
      if(!Exists(name)) break;
      string t=ObjectGetString(0,name,OBJPROP_TEXT);
      if(StringLen(t)>2 && StringSubstr(t,0,2)=="  " && all!="") all=StringSubstr(all,0,StringLen(all)-1)+" "+StringSubstr(t,2)+"\n";
      else all+=t+"\n";
     }
   return(all);
  }
string PanelText(void) {return(BoxText(EV_PANEL_PREFIX+"main_"));}
string LegendText(void) {return(BoxText(EV_PANEL_PREFIX+"leg_"));}

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

//--- helpers over the boxes: the row whose text starts with a string, its tooltip, the pixel width of a text in the box font
string RowName(const string prefix,const string start)
  {
   for(int i=0;i<60;i++)
     {
      string name=prefix+StringFormat("%03d",i);
      if(!Exists(name)) break;
      if(StringFind(ObjectGetString(0,name,OBJPROP_TEXT),start)==0) return(name);
     }
   return("");
  }
string TipOfRow(const string prefix,const string start)
  {
   string n=RowName(prefix,start);
   return(n=="" ? "" : ObjectGetString(0,n,OBJPROP_TOOLTIP));
  }
string T(const string marked) {return(EV_T(marked));}
//--- the real text and the real tooltip of the row that starts with a string (for the detail of a FAIL)
string RowInfo(const string prefix,const string start)
  {
   string n=RowName(prefix,start);
   if(n=="") return("no row starts with '"+start+"'");
   string tip=ObjectGetString(0,n,OBJPROP_TOOLTIP);
   return("row '"+ObjectGetString(0,n,OBJPROP_TEXT)+"' | tooltip("+IntegerToString(StringLen(tip))+" chars)='"+tip+"'");
  }
//--- every row of both boxes with the length of its tooltip
string DumpBoxes(void)
  {
   string all="";
   string prefixes[2]={EV_PANEL_PREFIX+"main_",EV_PANEL_PREFIX+"leg_"};
   for(int b=0;b<2;b++)
     {
      for(int i=0;i<60;i++)
        {
         string name=prefixes[b]+StringFormat("%03d",i);
         if(!Exists(name)) break;
         all+="["+ObjectGetString(0,name,OBJPROP_TEXT)+"](tip "+IntegerToString(StringLen(ObjectGetString(0,name,OBJPROP_TOOLTIP)))+")";
        }
      all+=" // ";
     }
   return(all);
  }

//--- the background exists, is a rectangle label, holds every row, every label ends inside it (measured with the real font: no cut text) and it fits the chart
bool BoxFits(const string prefix,const int chart_w,const int chart_h,const int font)
  {
   string bg=prefix+"bg";
   if(!Exists(bg) || (int)ObjectGetInteger(0,bg,OBJPROP_TYPE)!=OBJ_RECTANGLE_LABEL) return(false);
   int x=(int)ObjectGetInteger(0,bg,OBJPROP_XDISTANCE),y=(int)ObjectGetInteger(0,bg,OBJPROP_YDISTANCE);
   int w=(int)ObjectGetInteger(0,bg,OBJPROP_XSIZE),h=(int)ObjectGetInteger(0,bg,OBJPROP_YSIZE);
   if(x+w>chart_w || y+h>chart_h || y<0) return(false);
   int rows=0;
   TextSetFont("Consolas",-10*font,0,0);
   for(int i=0;i<60;i++)
     {
      string name=prefix+StringFormat("%03d",i);
      if(!Exists(name)) break;
      int lx=(int)ObjectGetInteger(0,name,OBJPROP_XDISTANCE),ly=(int)ObjectGetInteger(0,name,OBJPROP_YDISTANCE);
      uint tw=0,th=0;
      if(!TextGetSize(ObjectGetString(0,name,OBJPROP_TEXT),tw,th)) return(false);
      if(lx+(int)tw>x+w || ly<y || ly+(int)th>y+h) return(false);
      rows++;
     }
   return(rows>0);
  }
int BoxRows(const string prefix)
  {
   int n=0;
   for(int i=0;i<60;i++) {if(!Exists(prefix+StringFormat("%03d",i))) break; n++;}
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
   g_ctx=title+" :: "+DumpBoxes();
   string main=EV_PANEL_PREFIX+"main_";
   string ds=(dir==1 ? "BUY" : "SELL");
   color h4c=(dir==1 ? clrDodgerBlue : clrDarkOrange);
   int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0),ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   // ---- always: the mode, a SHORT panel, the legend with real swatches, no arrow objects, the manual drawing untouched
   Check(Has(panel,T("SIMULIM ~b PA URDHRA REAL~E")),title+": the first row says SIMULIM and PA URDHRA REALE");
   Check(StringFind(TextOf(main+"000"),T("SIMULIM"))==0 && Has(TipOfRow(main,T("SIMULIM")),"FAKE / READ_ONLY"),title+": the mode is the first row and its tooltip says FAKE / READ_ONLY");
   Check(Has(panel,"Vendimi: "),title+": the panel has a decision row");
   Check(Has(panel,T("Prototip ~m jo i validuar")),title+": the short note 'Prototip - jo i validuar'");
   Check(BoxRows(main)<=(kind==KIND_WAIT_CONTEXT ? 5 : 8),title+": the panel is short (5 rows without a plan, 8 with one)");
   Check(Has(LegendText(),T("LEGJEND~E")) && Has(LegendText(),"FVG e zgjedhur") && Has(LegendText(),"Thyerje M15") && Has(LegendText(),"Sweep") && Has(LegendText(),"E | SL | 2R | TP"),title+": the legend names every kind of mark");
   Check(BoxFits(main,cw,ch,9) && BoxFits(EV_PANEL_PREFIX+"leg_",cw,ch,8),title+": both boxes have a background that holds their rows, no text is cut, both fit the chart");
   Check(ObjectGetInteger(0,EV_PANEL_PREFIX+"main_bg",OBJPROP_YDISTANCE)+ObjectGetInteger(0,EV_PANEL_PREFIX+"main_bg",OBJPROP_YSIZE)<=ObjectGetInteger(0,EV_PANEL_PREFIX+"leg_bg",OBJPROP_YDISTANCE),title+": the panel and the legend do not overlap");
   Check(Exists(EV_PANEL_PREFIX+"leg_s1_ao") && ColorOf(EV_PANEL_PREFIX+"leg_s1_ao")==clrDodgerBlue && Exists(EV_PANEL_PREFIX+"leg_s1_bo") && ColorOf(EV_PANEL_PREFIX+"leg_s1_bo")==clrDarkOrange,title+": legend swatch H4 = a blue box and an orange box");
   Check(ColorOf(EV_PANEL_PREFIX+"leg_s2_ao")==clrSilver && ColorOf(EV_PANEL_PREFIX+"leg_s3_ao")==clrGold,title+": legend swatches: grey box = FVG M15, gold box = selected FVG");
   Check(Exists(EV_PANEL_PREFIX+"leg_s4_d0") && Exists(EV_PANEL_PREFIX+"leg_s4_d1") && Exists(EV_PANEL_PREFIX+"leg_s4_d2") && Exists(EV_PANEL_PREFIX+"leg_s4_g") && Exists(EV_PANEL_PREFIX+"leg_s5_d0") && Exists(EV_PANEL_PREFIX+"leg_s5_g"),title+": legend swatches: dashed line + dot (Sweep), solid line + dot (Thyerje M15)");
   Check((int)ObjectGetInteger(0,EV_PANEL_PREFIX+"leg_s4_g",OBJPROP_TYPE)==OBJ_RECTANGLE_LABEL && (int)ObjectGetInteger(0,EV_PANEL_PREFIX+"leg_s5_g",OBJPROP_TYPE)==OBJ_RECTANGLE_LABEL && ColorOf(EV_PANEL_PREFIX+"leg_s4_g")==clrSilver && ColorOf(EV_PANEL_PREFIX+"leg_s5_g")==clrWhite &&
         ObjectGetInteger(0,EV_PANEL_PREFIX+"leg_s4_g",OBJPROP_XSIZE)>=5,title+": the legend dots are small filled graphic squares, with no symbol font and no code point (the glyph showed as a box)");
   Check(StringFind(ObjectGetString(0,EV_PANEL_PREFIX+"leg_s4_g",OBJPROP_FONT),"Wingdings")<0 && ObjectGetString(0,EV_PANEL_PREFIX+"leg_s4_g",OBJPROP_TEXT)=="",title+": no label with a symbol font in the legend");
   Check(Exists(EV_PANEL_PREFIX+"leg_s6_e") && Exists(EV_PANEL_PREFIX+"leg_s6_s") && Exists(EV_PANEL_PREFIX+"leg_s6_r") && Exists(EV_PANEL_PREFIX+"leg_s6_t"),title+": legend swatch E | SL | 2R | TP = four labelled line samples");
   Check(CountArrowObjects()==0,title+": no entry arrow object (only the dots of the sweep and of the break exist)");
   Check(!Exists(EV_PREFIX+"entry_arrow") && CountPrefix(EV_PREFIX,OBJ_ARROW_BUY)==0 && CountPrefix(EV_PREFIX,OBJ_ARROW_SELL)==0,title+": no buy / sell arrow");
   Check(Exists("MANUAL_VIEW_TEST_LINE"),title+": the manual drawing is untouched");
   Check(Has(TipOfRow(main,T("Prototip")),"Konfirmuar: ") && Has(TipOfRow(main,T("Prototip")),"Prototip: "),title+": the confirmed and the temporary choices are explained in the tooltip",RowInfo(main,T("Prototip")));
   // ---- H4: direction, the arrow glyph in the gutter, the short state
   Check(Has(panel,"H4: "+ds+" | "),title+": H4 direction in two letters of text");
   Check(Exists(main+"s1_a0") && Exists(main+"s1_a1") && Exists(main+"s1_a2") && Exists(main+"s1_a3") && ColorOf(main+"s1_a0")==h4c && ColorOf(main+"s1_a1")==h4c && ColorOf(main+"s1_a2")==h4c && ColorOf(main+"s1_a3")==h4c,
         title+": the H4 arrow is drawn in the DIRECTION colour (blue BUY, orange SELL), not in the colour of the row text",
         "expected colour "+IntegerToString((int)h4c)+", got a0="+IntegerToString((int)ColorOf(main+"s1_a0"))+" a1="+IntegerToString((int)ColorOf(main+"s1_a1"))+" row text colour="+IntegerToString((int)ColorOf(RowName(main,"H4:"))));
   Check(Exists(main+"s1_a0") && Exists(main+"s1_a1") && (dir==-1 ? ObjectGetInteger(0,main+"s1_a1",OBJPROP_YDISTANCE)>ObjectGetInteger(0,main+"s1_a0",OBJPROP_YDISTANCE) : ObjectGetInteger(0,main+"s1_a1",OBJPROP_YDISTANCE)<ObjectGetInteger(0,main+"s1_a0",OBJPROP_YDISTANCE)),
         title+": the arrow points down for SELL and up for BUY (the head is below / above the stem)");
   Check(StringFind(DumpBoxes(),"?")<0,title+": no placeholder question marks in the boxes");
   Check(Exists(EV_PREFIX+"sweep_dot") && Exists(EV_PREFIX+"sweep_txt") && Exists(EV_PREFIX+"sweep_lvl"),title+": sweep mark, label and dashed level");
   Check(Has(TextOf(EV_PREFIX+"sweep_txt"),(dir==-1 ? "Sweep H4" : "Fitil H4")),title+": the sweep label names the event");
   Check((int)ObjectGetInteger(0,EV_PREFIX+"sweep_lvl",OBJPROP_STYLE)==STYLE_DASH,title+": the swept level is dashed");
   Check(Exists(EV_PREFIX+"h4fvg_0") && Has(TextOf(EV_PREFIX+"h4fvg_txt0"),"H4"),title+": H4 FVG zone with the label H4");
   Check(!ObjectGetInteger(0,EV_PREFIX+"h4fvg_0",OBJPROP_FILL) && ObjectGetInteger(0,EV_PREFIX+"h4fvg_0",OBJPROP_COLOR)==h4c,title+": H4 FVG is an outline in the direction colour");
   Check(CountPrefix(EV_PREFIX+"h4fvg_",OBJ_RECTANGLE)<=EV_MAX_H4_FVG,title+": the number of H4 zones is limited");
   if(kind==KIND_WAIT_CONTEXT)
     {
      Check(Has(panel,"Pret rikonfirmim") && Has(TipOfRow(main,"H4:"),"sweep i brendshem u pa") && !Has(panel,"SWEEP_WAIT"),title+": the phase is translated (short state in the row, the sentence in the tooltip)",RowInfo(main,"H4:"));
      Check(Has(TextOf(EV_PREFIX+"h4fvg_txt0"),"kandidat"),title+": before the reconfirmation the H4 FVG is a candidate");
      Check((int)ObjectGetInteger(0,EV_PREFIX+"h4fvg_0",OBJPROP_STYLE)==STYLE_DASH,title+": a candidate H4 FVG is dashed");
      Check(Has(panel,"Vendimi: PRET") && !Has(panel,"Vendimi: BLLOKUAR"),title+": the decision is PRET");
      Check(Has(panel,T("M15: N~e pritje")) && Has(TipOfRow(main,"M15:"),"Mungon: H4 rikonfirmim"),title+": M15 says Ne pritje and the tooltip says what is missing",RowInfo(main,"M15:"));
      Check(CountPrefix(EV_PREFIX+"m15fvg_",-1)==0 && !Exists(EV_PREFIX+"brk_line") && !Exists(EV_PREFIX+"entry") && !Exists(EV_PREFIX+"sl") && !Exists(EV_PREFIX+"tp"),title+": no M15 level, no zone, no plan line is invented");
      Check(CountGoldZones()==0,title+": nothing is gold");
      return;
     }
   Check(Has(TextOf(EV_PREFIX+"h4fvg_txt0"),"rikonfirmuar") && (int)ObjectGetInteger(0,EV_PREFIX+"h4fvg_0",OBJPROP_STYLE)==STYLE_SOLID,title+": the reconfirmed H4 FVG is solid and says so");
   Check(Has(panel,"H4: "+ds+" | Rikonfirmuar"),title+": the H4 row says Rikonfirmuar");
   // ---- M15
   Check(Exists(EV_PREFIX+"brk_line") && Exists(EV_PREFIX+"brk_dot") && Has(TextOf(EV_PREFIX+"brk_txt"),"Thyerje M15"),title+": M15 break line, candle mark and label 'Thyerje M15'");
   Check(!Has(TextOf(EV_PREFIX+"brk_txt"),"MSS") && Has(ObjectGetString(0,EV_PREFIX+"brk_line",OBJPROP_TOOLTIP),"NUK eshte MSS"),title+": the prototype break is not called a validated MSS");
   Check(CountGoldZones()==1 && ColorOf(EV_PREFIX+"m15fvg_0")==clrGold && Has(TextOf(EV_PREFIX+"m15fvg_txt0"),"ZGJEDHUR"),title+": exactly one gold M15 FVG, the one the plan bridge selected, drawn first");
   Check(Exists(EV_PREFIX+"m15fvg_1") && ColorOf(EV_PREFIX+"m15fvg_1")!=clrGold && Has(TextOf(EV_PREFIX+"m15fvg_txt1"),"kandidat"),title+": another M15 FVG is a plain candidate");
   Check(CountPrefix(EV_PREFIX+"m15fvg_",OBJ_RECTANGLE)<=EV_MAX_M15_FVG,title+": the number of M15 zones is limited");
   Check(Has(panel,T("M15: Pret kthim n~e FVG")),title+": the M15 row says Pret kthim ne FVG",RowInfo(main,"M15:"));
   Check(Has(TipOfRow(main,"M15:"),"Konfirmuar: "),title+": the M15 tooltip lists what is confirmed",RowInfo(main,"M15:"));
   Check(Has(TipOfRow(main,"M15:"),"thyerje M15"),title+": the M15 tooltip names the break",RowInfo(main,"M15:"));
   Check(Has(TipOfRow(main,"M15:"),T("Mungon: kthim n~e FVG")),title+": the M15 tooltip lists what is missing",RowInfo(main,"M15:"));
   // ---- plan: lines with labels and prices, short rows in the panel
   Check(Exists(EV_PREFIX+"entry") && Exists(EV_PREFIX+"sl") && Exists(EV_PREFIX+"tp") && Exists(EV_PREFIX+"entry_txt") && Exists(EV_PREFIX+"sl_txt") && Exists(EV_PREFIX+"tp_txt"),title+": entry, SL and TP lines with labels");
   Check(Has(TextOf(EV_PREFIX+"entry_txt"),"HYRJA LIMIT "+ds) && Has(TextOf(EV_PREFIX+"sl_txt"),"SL ") && Has(TextOf(EV_PREFIX+"tp_txt"),"TP"),title+": the labels carry the names and prices");
   if(kind==KIND_ACCEPTED_FAR)
      Check(Exists(EV_PREFIX+"r2") && Has(TextOf(EV_PREFIX+"r2_txt"),"2R ") && !Has(TextOf(EV_PREFIX+"tp_txt"),"= 2R"),title+": a TP beyond 2R has its own 2R line");
   else
      Check(!Exists(EV_PREFIX+"r2") && Has(TextOf(EV_PREFIX+"tp_txt"),"TP = 2R "),title+": when TP is 2R one line carries both names");
   Check(Has(panel,"PLAN "+ds+" LIMIT | E ") && Has(panel,"SL ") && Has(panel,"Lot 0.10 | Risk 100.00"),title+": the panel plan rows: E / SL / TP / lot / risk");
   Check(Has(TipOfRow(main,"PLAN"),"modaliteti: FAKE (virtuale)"),title+": the plan row tooltip names the FAKE mode");
   if(kind==KIND_BLOCKED)
     {
      Check(Has(panel,"Vendimi: BLLOKUAR | spread"),title+": blocked, with one or two words of reason");
      Check(Has(TipOfRow(main,"Vendimi:"),"spread shume i larte") && Has(TipOfRow(main,"Vendimi:"),"+1 arsye"),title+": the full reason is in the tooltip");
     }
   else
     {
      Check(Has(panel,"Vendimi: KERKESE VIRTUALE"),title+": virtual request");
      // the next step: the signal is handled; the kept plan stays and says so
      SEoOutcome again;
      EO_OutcomeInit(again);
      again.risk_label=out.risk_label;
      again.spb.signal_id=out.spb.signal_id;
      EO_Set(again,"ALREADY_HANDLED",out.spb.signal_id);
      view.Update(again,feed,false,true);
      string p2=PanelText();
      Check(Exists(EV_PREFIX+"entry") && Has(p2,"Vendimi: KERKESE VIRTUALE") && Has(TipOfRow(main,"Vendimi:"),"trajtuar me pare"),title+": the plan of a handled signal stays with its verdict");
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

//--- pure layout helpers: the same cases as tests/test_view_layout.py
void TestLayout(void)
  {
   string rows[];
   int n=EV_Wrap("SIMULIM - PA URDHRA REALE",40,rows);
   Check(n==1 && rows[0]=="SIMULIM - PA URDHRA REALE","layout: a short line is one row");
   n=EV_Wrap("M15 mungon: thyerja e nivelit M15; FVG M15 pas thyerjes; kthimi i cmimit ne FVG",30,rows);
   Check(n==3 && rows[0]=="M15 mungon: thyerja e nivelit" && rows[1]=="  M15; FVG M15 pas thyerjes;" && rows[2]=="  kthimi i cmimit ne FVG","layout: a long line wraps at words and indents the continuation");
   n=EV_Wrap("x aaaaaaaaaaaaaaaaaaaaaaaaa",10,rows);
   bool all_fit=true;
   string glued="";
   for(int i=0;i<n;i++) {if(StringLen(rows[i])>10) all_fit=false; string cell=rows[i]; StringTrimLeft(cell); glued+=cell;}
   Check(all_fit && glued=="xaaaaaaaaaaaaaaaaaaaaaaaaa","layout: a word longer than the width is cut and nothing is lost");
   string t[7]={"SIMULIM - PA URDHRA REALE","H4: ZBRITES (SELL) | sweep i brendshem u pa; pret qe cmimi te preke nje FVG H4 te ri","M15 konfirmuar: asgje ende","M15 mungon: setup H4 i rikonfirmuar",
                "VENDIMI: PRET - pret rikonfirmimin H4","Konfirmuar nga klienti: hyrja LIMIT ne skaj te FVG, seanca, lajmet, kufijte ditore.","E perkohshme (prototip): burimi H4, niveli M15 i thyer, SL, TP/2R"};
   int p[7]={0,1,1,1,0,3,3};
   bool keep[];
   int dropped=EV_Select(t,p,7,120,12,keep);
   bool all=true;
   for(int i=0;i<7;i++) if(!keep[i]) all=false;
   Check(dropped==0 && all,"layout: a wide chart keeps every line");
   dropped=EV_Select(t,p,7,120,6,keep);
   Check(dropped==2 && keep[0] && keep[1] && keep[2] && keep[3] && keep[4] && !keep[5] && !keep[6],"layout: low priorities leave first and the marker row counts");
   string t2[4]={"a","b","c","d"};
   int p2[4]={0,2,2,2};
   dropped=EV_Select(t2,p2,4,40,3,keep);
   Check(dropped==2 && keep[0] && keep[1] && !keep[2] && !keep[3],"layout: the later line of the same priority leaves first");
   dropped=EV_Select(t,p,7,20,2,keep);
   Check(keep[0] && keep[4] && !keep[1] && !keep[2] && !keep[3] && !keep[5] && !keep[6],"layout: priority 0 is never dropped even when nothing fits");
  }

//--- what the platform keeps of a long tooltip (so a tooltip test never guesses): prints the retained length for 100 / 200 / 255 / 400 characters
void TestTooltipLimit(CEoView &view)
  {
   string name=EV_PREFIX+"probe";
   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   int kept[4];
   int want[4]={100,200,255,400};
   for(int i=0;i<4;i++)
     {
      string t="";
      while(StringLen(t)<want[i]) t+="0123456789";
      t=StringSubstr(t,0,want[i]);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,t);
      kept[i]=StringLen(ObjectGetString(0,name,OBJPROP_TOOLTIP));
     }
   ObjectDelete(0,name);
   PrintFormat("TOOLTIP PROBE: set 100/200/255/400 characters, the platform kept %d/%d/%d/%d",kept[0],kept[1],kept[2],kept[3]);
   int expected=(kept[3]>=40 && kept[3]<EV_TIP_MAX ? kept[3] : EV_TIP_MAX);
   Check(view.TipMax()==expected,"tooltips: the view measured the same tooltip limit as this probe and clips to it","view "+IntegerToString(view.TipMax())+", probe "+IntegerToString(expected)+" (kept "+IntegerToString(kept[0])+"/"+IntegerToString(kept[1])+"/"+IntegerToString(kept[2])+"/"+IntegerToString(kept[3])+" of 100/200/255/400)");
   Check(view.TipMax()>=100,"tooltips: the terminal keeps at least 100 characters (the longest tooltip that carries a test fact is about 110)","view "+IntegerToString(view.TipMax()));
  }

//--- the SAME view instance sees a SELL snapshot and then a BUY snapshot that has the same time, phase and setup id: the marks must follow the direction; and a level / zone / event that
//--- changes while every count stays the same must be redrawn (this is the stale-marks case a fresh instance would hide)
void TestSameInstanceFlip(CEoView &view)
  {
   string main=EV_PANEL_PREFIX+"main_";
   CEoFeed sell,buy;
   SEoOutcome o1,o2;
   Build(sell,o1,-1,KIND_WAIT_CONTEXT);
   Build(buy,o2,1,KIND_WAIT_CONTEXT);
   view.Update(o1,sell,false,true);
   g_ctx="flip SELL->BUY :: "+DumpBoxes();
   bool sell_ok=(ColorOf(EV_PREFIX+"h4fvg_0")==clrDarkOrange && Has(TextOf(EV_PREFIX+"sweep_txt"),"Sweep H4") && ColorOf(main+"s1_a0")==clrDarkOrange);
   Check(sell_ok,"same instance: the SELL snapshot is drawn orange with a Sweep H4 label and an orange arrow","h4fvg_0 colour="+IntegerToString((int)ColorOf(EV_PREFIX+"h4fvg_0"))+" sweep text='"+TextOf(EV_PREFIX+"sweep_txt")+"'");
   view.Update(o2,buy,false,true);
   g_ctx="flip SELL->BUY :: "+DumpBoxes();
   Check(ColorOf(EV_PREFIX+"h4fvg_0")==clrDodgerBlue,"same instance: after SELL -> BUY (same time, phase, setup id) the H4 zone is BLUE, not the stale orange","h4fvg_0 colour="+IntegerToString((int)ColorOf(EV_PREFIX+"h4fvg_0")));
   Check(Has(TextOf(EV_PREFIX+"sweep_txt"),"Fitil H4") && !Has(TextOf(EV_PREFIX+"sweep_txt"),"Sweep H4"),"same instance: the sweep label follows the BUY wick setup","sweep text='"+TextOf(EV_PREFIX+"sweep_txt")+"'");
   Check(ColorOf(main+"s1_a0")==clrDodgerBlue && Has(TextOf(RowName(main,"H4:")),"H4: BUY"),"same instance: the H4 row and its arrow follow the BUY direction",RowInfo(main,"H4:"));
   view.Update(o1,sell,false,true);
   g_ctx="flip BUY->SELL :: "+DumpBoxes();
   Check(ColorOf(EV_PREFIX+"h4fvg_0")==clrDarkOrange && Has(TextOf(EV_PREFIX+"sweep_txt"),"Sweep H4"),"same instance: BUY -> SELL redraws too");
   // ---- levels / zones / events change, no count changes
   CEoFeed a;
   SEoOutcome oa;
   Build(a,oa,1,KIND_ACCEPTED_2R);
   view.Update(oa,a,false,true);
   double z0=ObjectGetDouble(0,EV_PREFIX+"h4fvg_0",OBJPROP_PRICE,0);
   double m0=ObjectGetDouble(0,EV_PREFIX+"m15fvg_0",OBJPROP_PRICE,0);
   double b0=ObjectGetDouble(0,EV_PREFIX+"brk_line",OBJPROP_PRICE,0);
   double l0=ObjectGetDouble(0,EV_PREFIX+"sweep_lvl",OBJPROP_PRICE,0);
   a.dv_tracks[0].lower+=g_u; a.dv_tracks[0].upper+=g_u;
   a.f[0].lower+=0.1*g_u; a.f[0].upper+=0.1*g_u;
   a.broken.price+=0.5*g_u;
   a.dv_ev.st.snap_price+=0.7*g_u;
   view.Update(oa,a,false,true);
   g_ctx="levels changed :: "+DumpBoxes();
   Check(MathAbs(ObjectGetDouble(0,EV_PREFIX+"h4fvg_0",OBJPROP_PRICE,0)-(z0+g_u))<1e-6*g_mid,"same instance: an H4 zone that moves without a change of count is redrawn","before "+DoubleToString(z0,5)+" after "+DoubleToString(ObjectGetDouble(0,EV_PREFIX+"h4fvg_0",OBJPROP_PRICE,0),5));
   Check(MathAbs(ObjectGetDouble(0,EV_PREFIX+"m15fvg_0",OBJPROP_PRICE,0)-(m0+0.1*g_u))<1e-6*g_mid,"same instance: an M15 zone that moves is redrawn");
   Check(MathAbs(ObjectGetDouble(0,EV_PREFIX+"brk_line",OBJPROP_PRICE,0)-(b0+0.5*g_u))<1e-6*g_mid,"same instance: the break level that moves is redrawn");
   Check(MathAbs(ObjectGetDouble(0,EV_PREFIX+"sweep_lvl",OBJPROP_PRICE,0)-(l0+0.7*g_u))<1e-6*g_mid,"same instance: the wick level that moves is redrawn");
   // an event that changes (the pivot named by the internal sweep) moves the swept level
   CEoFeed c;
   SEoOutcome oc;
   Build(c,oc,-1,KIND_WAIT_CONTEXT);
   view.Update(oc,c,false,true);
   double s0=ObjectGetDouble(0,EV_PREFIX+"sweep_lvl",OBJPROP_PRICE,0);
   c.dv_events[0].ref="IH"+H4TimeStamp(c.hbars[4].time);
   c.hbars[4].high=c.hbars[4].high+3.0*g_u;
   view.Update(oc,c,false,true);
   Check(MathAbs(ObjectGetDouble(0,EV_PREFIX+"sweep_lvl",OBJPROP_PRICE,0)-s0)>0.5*g_u,
         "same instance: an event that names another pivot redraws the swept level","before "+DoubleToString(s0,5)+" after "+DoubleToString(ObjectGetDouble(0,EV_PREFIX+"sweep_lvl",OBJPROP_PRICE,0),5));
  }

//--- the request mode follows the transport: REAL (DEMO) says so everywhere, FAKE says virtual
void TestRequestMode(CEoView &view)
  {
   CEoFeed feed;
   SEoOutcome out;
   string main=EV_PANEL_PREFIX+"main_";
   Build(feed,out,1,KIND_ACCEPTED_2R);
   view.Update(out,feed,true,true);
   string panel=PanelText();
   Check(Has(panel,"Vendimi: KERKESE REALE") && !Has(panel,"KERKESE VIRTUALE"),"request mode: a request through the REAL transport is called REALE, never virtual");
   Check(Has(TipOfRow(main,"PLAN"),"modaliteti: REAL (DEMO)") && !Has(TipOfRow(main,"PLAN"),"modaliteti: FAKE") && Has(panel,T("ATENCION ~b REAL (DEMO)")) && !Has(panel,T("SIMULIM ~b")),"request mode: the first row says REAL (DEMO), never SIMULIM");
   SEoOutcome again;
   EO_OutcomeInit(again);
   again.spb.signal_id=out.spb.signal_id;
   EO_Set(again,"ALREADY_HANDLED",out.spb.signal_id);
   view.Update(again,feed,true,true);
   panel=PanelText();
   Check(Has(panel,"Vendimi: KERKESE REALE") && Has(TipOfRow(main,"Vendimi:"),"trajtuar me pare") && !Has(panel,"KERKESE VIRTUALE"),"request mode: the kept plan of a handled signal keeps the REAL mode");
   Build(feed,out,1,KIND_ACCEPTED_2R);
   out.spb.signal_id="SYNTHETIC_SIGNAL_2";
   view.Update(out,feed,false,true);
   panel=PanelText();
   Check(Has(panel,"Vendimi: KERKESE VIRTUALE") && Has(TipOfRow(main,"PLAN"),"modaliteti: FAKE (virtuale)") && !Has(panel,"KERKESE REALE") && Has(panel,T("SIMULIM ~b PA URDHRA REAL~E")),"request mode: the FAKE transport is called virtual and the first row says SIMULIM");
  }

//--- wide, narrow and short charts: no cut text, no overlap, the mode and the decision always visible
void TestSizes(CEoView &view)
  {
   int sizes_w[3]={1400,380,900};
   int sizes_h[3]={800,520,300};
   string names[3]={"wide chart 1400 x 800","narrow chart 380 x 520","short chart 900 x 300"};
   for(int z=0;z<3;z++)
     {
      for(int dir=-1;dir<=1;dir+=2)
        {
         int kinds[3]={KIND_WAIT_CONTEXT,KIND_ACCEPTED_2R,KIND_BLOCKED};
         string kn[3]={"waiting","accepted","blocked"};
         for(int q=0;q<3;q++)
           {
            CEoFeed feed;
            SEoOutcome out;
            Build(feed,out,dir,kinds[q]);
            view.TestSize(sizes_w[z],sizes_h[z]);
            view.Update(out,feed,false,true);
            string title=names[z]+(dir==1 ? " BUY " : " SELL ")+kn[q];
            g_ctx=title+" :: "+DumpBoxes();
            string main=EV_PANEL_PREFIX+"main_",leg=EV_PANEL_PREFIX+"leg_";
            Check(BoxFits(main,sizes_w[z],sizes_h[z],9) && BoxFits(leg,sizes_w[z],sizes_h[z],8),title+": no text is cut and both boxes fit the chart");
            long main_end=ObjectGetInteger(0,main+"bg",OBJPROP_YDISTANCE)+ObjectGetInteger(0,main+"bg",OBJPROP_YSIZE);
            Check(main_end<=ObjectGetInteger(0,leg+"bg",OBJPROP_YDISTANCE),title+": the panel and the legend do not overlap");
            string panel=PanelText();
            Check(Has(panel,T("SIMULIM ~b PA URDHRA REAL~E")) && Has(panel,"Vendimi: "),title+": the mode and the decision rows are always visible");
            if(sizes_h[z]<400) Check(Has(panel,"(+") || BoxRows(main)<=8,title+": a short chart drops the low-priority rows and says how many");
           }
        }
     }
   view.TestSize(0,0);
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
   Check((int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0)>=900 && (int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0)>=500,"the chart is large enough for the scenarios (900 x 500 px); the narrow and short charts are simulated by TestSize");
   Check(EV_T("~e~c~E~C~b~m")==ShortToString(0x00EB)+ShortToString(0x00E7)+ShortToString(0x00CB)+ShortToString(0x00C7)+ShortToString(0x2022)+ShortToString(0x2014),"the text markers become the Albanian letters, the bullet and the dash");
   TestLayout();
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
   TestRequestMode(view);
   TestSameInstanceFlip(view);
   TestSizes(view);
   TestTooltipLimit(view);
   view.Destroy();
   Check(CountPrefix(EV_PREFIX,-1)==0,"Destroy removes every object of the component");
   Check(Exists("MANUAL_VIEW_TEST_LINE"),"the manual drawing survives Destroy");
   ObjectDelete(0,"MANUAL_VIEW_TEST_LINE");
   ChartRedraw(0);
   PrintFormat("EntryViewTest finished: %d passed, %d failed. SYNTHETIC; compile and run were UNVERIFIED until this log exists.",g_pass,g_fail);
  }
