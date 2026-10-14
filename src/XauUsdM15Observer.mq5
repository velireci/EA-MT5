// Read-only T004 prototype. Closed-bar REPLAY facts, NOT trading signals.
#property strict
#property version "1.01"
#include "include/TimeframeWatcher.mqh"
#include "include/H4M15Bridge.mqh"
#include "include/M15Timeline.mqh"

enum ENUM_M4_SOURCE {M4_SOURCE_UNSELECTED=0,M4_T003_RECONF_PROPOSAL=1};
enum ENUM_M4_SELECTOR {M4_LEVEL_UNSELECTED=0,M4_LATEST_FRACTAL_PROPOSAL=1};
enum ENUM_M4_TIMING {M4_TIMING_UNSELECTED=0,M4_A_AFTER_BOS_PROPOSAL=1};
input ENUM_M4_SOURCE InpContextSource=M4_SOURCE_UNSELECTED;
input ENUM_M4_SELECTOR InpM15Level=M4_LEVEL_UNSELECTED;
input ENUM_M4_TIMING InpFvgTiming=M4_TIMING_UNSELECTED;
input datetime InpAsOfTime=0;                 // 0 live; otherwise broker/server time
input int InpH4RebuildBars=2000;
input int InpH4LookbackBars=300;
input int InpH4LeftBars=2;
input int InpH4RightBars=2;
input int InpM15ReplayBars=512;
input int InpM15LookbackBars=300;
input int InpM15LeftBars=2;
input int InpM15RightBars=2;
input int InpMaxFvgs=6;
input int InpRecentLogEvents=5;
input int InpPollSeconds=2;

CTimeframeWatcher g_h4,g_m15;
SH3Params g_params;
SM4State g_state;
SM4Candidate g_fvgs[];
SM4Event g_events[];
SM4TimelineInfo g_info;
SM4Selection g_current;
MqlRates g_mbars[],g_hbars[];
SM4ContextUpdate g_updates[];
datetime g_cut=0,g_replay_start=0;
bool g_built=false;
string g_problem="",g_h4_status="-",g_t2="UNKNOWN",g_h4_bias="UNKNOWN";
int g_h4_depth=0;
uint g_duration=0;
string PREFIX="velo_t004_";

string Stamp(const datetime t) {return(t>0 ? TimeToString(t,TIME_DATE|TIME_MINUTES) : "-");}
void Clear(const string reason)
  {
   if(g_problem!=reason) Print("T004 CLEARED: ",reason,". REPLAY only, no NEW events or orders.");
   g_problem=reason;
   M4ResetReplay(g_state,g_fvgs,g_events,g_info,g_built,g_cut);
   g_info.status=reason;
   g_current.status="DISABLED";M4NoLevel(g_current.level);
   g_h4_status="-";g_t2="UNKNOWN";g_h4_bias="UNKNOWN";
   ObjectsDeleteAll(0,PREFIX);
  }

int CopyClosed(const ENUM_TIMEFRAMES tf,const datetime cut,const int want,MqlRates &out[])
  {
   MqlRates raw[];ArraySetAsSeries(raw,false);
   int n=CopyRates(_Symbol,tf,cut,want+2,raw);
   ArrayResize(out,0);
   if(n<=0) {ResetLastError();return(-1);}
   int period=PeriodSeconds(tf);
   int closed=H4ClosedCountAsOf(raw,n,cut,period);
   int start=(closed>want ? closed-want : 0);
   for(int i=0;i<n;i++)
      if(i>0 && raw[i].time<=raw[i-1].time) return(-1);
   ArrayResize(out,closed-start);
   for(int i=start;i<closed;i++)
     {
      if(!MathIsValidNumber(raw[i].high) || !MathIsValidNumber(raw[i].low) ||
         !MathIsValidNumber(raw[i].close) || raw[i].low<=0 || raw[i].high<raw[i].low ||
         raw[i].close<raw[i].low || raw[i].close>raw[i].high) return(-1);
      out[i-start]=raw[i];
     }
   return(ArraySize(out));
  }

void Snapshot(const int n,const datetime known)
  {
   SH3Eval ev;SH3Track tracks[];SH3Event events[];
   H3Evaluate(g_hbars,n,g_params,ev,tracks,events);
   SH3SetupCtx c;H3SetupContext(ev.st,tracks,ev.nt,c);
   int k=ArraySize(g_updates);ArrayResize(g_updates,k+1,64);
   g_updates[k].known=known;
   M4ContextFromH3(c,ev.reliable,g_updates[k].context,InpContextSource==M4_T003_RECONF_PROPOSAL);
   g_h4_depth=ev.r_eff;
   g_h4_bias=H3ReportedDirection(ev);
   g_h4_status=g_h4_bias+" / "+H3PhaseName(ev.st.phase)+" / "+H3FlagName(ev.flag);
  }

bool Build(const datetime cut)
  {
   uint began=GetTickCount();
   int want=InpM15ReplayBars+InpM15LookbackBars;
   int nm=CopyClosed(PERIOD_M15,cut,want,g_mbars);
   if(nm<want) {Clear("M15 history loading: "+IntegerToString(nm)+" / "+IntegerToString(want));return(false);}
   if(InpAsOfTime==0 && g_mbars[nm-1].time!=g_m15.ClosedOpenTime())
     {Clear("M15 boundary changed during copy");return(false);}
   int first=nm-InpM15ReplayBars;
   g_replay_start=g_mbars[first].time;
   int extra=(int)((cut-g_replay_start+14399)/14400)+2;
   int depth=(int)MathMin(10000,MathMax(g_params.rebuild,3*g_params.lookback)+extra);
   int nh=CopyClosed(PERIOD_H4,cut,depth,g_hbars);
   if(nh<=0) {Clear("H4 copy not ready");return(false);}
   if(InpAsOfTime==0 && g_hbars[nh-1].time!=g_h4.ClosedOpenTime())
     {Clear("H4 boundary changed during copy");return(false);}
   int initial=H4ClosedCountAsOf(g_hbars,nh,g_replay_start,14400);
   if(initial<g_params.rebuild)
     {Clear("H4 replay history loading: "+IntegerToString(initial)+" / "+IntegerToString(g_params.rebuild));return(false);}
   ArrayResize(g_updates,0);
   Snapshot(initial,g_replay_start);
   for(int i=initial;i<nh;i++)
     {
      datetime known=g_hbars[i].time+14400;
      if(known>cut) break;
      Snapshot(i+1,known);           // prefix only, never the final H4 state for earlier M15
     }
   MqlRates base[];ArrayResize(base,g_params.lookback);
   ArrayCopy(base,g_hbars,0,nh-g_params.lookback,g_params.lookback);
   SH4Swing sw[];int amb=0;
   int ns=H4FindSwings(base,ArraySize(base),g_params.left,g_params.right,14400,sw,amb);
   g_t2=H4DirName(H4DeriveDirection(sw,ns));
   int policy=(InpFvgTiming==M4_A_AFTER_BOS_PROPOSAL ? M4_A_AT_OR_AFTER_BREAK : M4_POLICY_UNSET);
   M4ReplayTimeline(g_mbars,nm,g_updates,ArraySize(g_updates),g_replay_start,cut,
                    InpM15Level==M4_LATEST_FRACTAL_PROPOSAL,policy,InpM15LeftBars,InpM15RightBars,
                    InpM15LookbackBars,g_state,g_fvgs,g_events,g_info);
   if(g_info.status!="OK") {Clear("timeline "+g_info.status);return(false);}
   // NEXT-bar candidate uses the complete closed prefix, including consumption
   // by the last processed bar (not the pre-bar selection used for that bar).
   M4SelectSwingProposal(g_mbars,nm,g_state.context.direction,g_current,
                         g_state.has_context && InpM15Level==M4_LATEST_FRACTAL_PROPOSAL &&
                         policy==M4_A_AT_OR_AFTER_BREAK,InpM15LeftBars,InpM15RightBars,InpM15LookbackBars);
   g_duration=GetTickCount()-began;
   g_cut=cut;g_built=true;g_problem="";
   PrintFormat("T004 REPLAY SUMMARY | cut %s | M15 phase %s | H4 %s | T002 %s | replay %d bars from %s | %d facts | %u ms. No NEW events, no orders.",
               Stamp(cut),g_state.phase,g_h4_status,g_t2,g_info.processed,Stamp(g_replay_start),ArraySize(g_events),g_duration);
   Print("T004 REPLAY CONTEXT | ",g_state.context.setup," | H4 FVG ",g_state.context.fvg,
         " | eligible ",Stamp(g_state.context.valid_from)," | selected source ",g_state.context.source);
   int ne=ArraySize(g_events);
   for(int i=(int)MathMax(0,ne-InpRecentLogEvents);i<ne;i++)
      Print("T004 REPLAY FACT | ",g_events[i].type," bar ",Stamp(g_events[i].time),
            " known ",Stamp(g_events[i].known)," ref ",g_events[i].ref);
   return(true);
  }

void Line(const int i,const string text,const color c,const int width,const int height)
  {
   if(12+i*17+17>height) return;
   string name=PREFIX+"p"+IntegerToString(i);
   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,14);ObjectSetInteger(0,name,OBJPROP_YDISTANCE,12+i*17);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");ObjectSetString(0,name,OBJPROP_TOOLTIP,text);
   int chars=(width-20)/7;
   ObjectSetString(0,name,OBJPROP_TEXT,(StringLen(text)>chars ? StringSubstr(text,0,chars-3)+"..." : text));
  }

void Draw()
  {
   ObjectsDeleteAll(0,PREFIX);
   if(g_built)
     {
      int drawn=0;
      for(int i=ArraySize(g_fvgs)-1;i>=0 && drawn<InpMaxFvgs;i--)
        {
         if(g_fvgs[i].invalid) continue;
         string name=PREFIX+"f"+IntegerToString(i);
         ObjectCreate(0,name,OBJ_RECTANGLE,0,g_fvgs[i].confirmed-2700,g_fvgs[i].lower,g_cut,g_fvgs[i].upper);
         ObjectSetInteger(0,name,OBJPROP_COLOR,(g_state.context.direction>0 ? clrDodgerBlue : clrTomato));
         ObjectSetInteger(0,name,OBJPROP_FILL,false);ObjectSetInteger(0,name,OBJPROP_BACK,true);
         ObjectSetInteger(0,name,OBJPROP_STYLE,(g_fvgs[i].returned ? STYLE_DASH : STYLE_SOLID));
         ObjectSetString(0,name,OBJPROP_TOOLTIP,"M15 FVG PROPOSAL "+g_fvgs[i].id+(g_fvgs[i].returned ? " RETURN OBSERVED (not entry)" : " awaiting return"));
         drawn++;
        }
      if(g_info.bos_price>0)
        {
         ObjectCreate(0,PREFIX+"bos",OBJ_TREND,0,g_state.bos_time,g_info.bos_price,g_cut,g_info.bos_price);
         ObjectSetInteger(0,PREFIX+"bos",OBJPROP_RAY_RIGHT,false);
         ObjectSetInteger(0,PREFIX+"bos",OBJPROP_COLOR,clrOrange);
         ObjectSetString(0,PREFIX+"bos",OBJPROP_TOOLTIP,"BROKEN M15 LEVEL PROPOSAL, not client-validated MSS");
        }
      if(g_state.phase=="WAIT_BREAK" && g_current.level.valid)
        {
         datetime end=(g_cut>g_current.level.known ? g_cut : g_current.level.known+900);
         ObjectCreate(0,PREFIX+"level",OBJ_TREND,0,g_current.level.known,g_current.level.price,end,g_current.level.price);
         ObjectSetInteger(0,PREFIX+"level",OBJPROP_RAY_RIGHT,false);
         ObjectSetInteger(0,PREFIX+"level",OBJPROP_STYLE,STYLE_DASH);
         ObjectSetInteger(0,PREFIX+"level",OBJPROP_COLOR,clrGold);
         ObjectSetString(0,PREFIX+"level",OBJPROP_TOOLTIP,"NEXT-BAR LEVEL PROPOSAL "+g_current.level.id+" known "+Stamp(g_current.level.known));
        }
     }
   int width=(int)MathMax(220,MathMin(650,ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-20));
   int height=(int)MathMax(60,MathMin(255,ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS)-20));
   string bg=PREFIX+"bg";ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,8);ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,8);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,width);ObjectSetInteger(0,bg,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'16,20,26');ObjectSetInteger(0,bg,OBJPROP_BORDER_COLOR,clrDimGray);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   Line(0,"T004 T003-RECONFIRMATION -> M15 PROPOSAL - NO TRADING",clrYellow,width,height);
   Line(1,(InpAsOfTime>0 ? "HISTORICAL server as-of " : "LIVE closed-bar REPLAY ")+Stamp(g_cut),clrAqua,width,height);
   Line(2,"Source "+EnumToString(InpContextSource),clrSilver,width,height);
   Line(3,"M15 level "+EnumToString(InpM15Level),clrSilver,width,height);
   Line(4,"FVG timing "+EnumToString(InpFvgTiming),clrSilver,width,height);
   if(!g_built) {Line(5,g_problem,clrOrange,width,height);ChartRedraw();return;}
   Line(5,"H4 "+g_h4_status+" (depth "+IntegerToString(g_h4_depth)+")",clrWhite,width,height);
   Line(6,"M15 "+g_state.phase+" | "+(g_state.phase=="WAIT_BREAK" ? "NEXT "+(g_current.level.valid ? DoubleToString(g_current.level.price,_Digits) : "none") : "BOS "+DoubleToString(g_info.bos_price,_Digits)),clrYellow,width,height);
   Line(7,"Context "+(g_state.has_context ? g_state.context.setup : "none ready/selected"),clrWhite,width,height);
   Line(8,"H4 FVG "+g_state.context.fvg+" | from "+Stamp(g_state.context.valid_from),clrWhite,width,height);
   Line(9,"Replay "+IntegerToString(g_info.processed)+" M15 bars from "+Stamp(g_replay_start),clrSilver,width,height);
   Line(10,"FVG candidates "+IntegerToString(ArraySize(g_fvgs))+" | facts "+IntegerToString(ArraySize(g_events)),clrSilver,width,height);
   bool disagree=(g_t2=="BULLISH" && g_h4_bias=="BEAR") || (g_t2=="BEARISH" && g_h4_bias=="BULL");
   Line(11,(disagree ? "MODEL DISAGREEMENT: " : "T002 baseline: ")+g_t2+" | T003 prototype "+g_h4_bias,(disagree ? clrTomato : clrSilver),width,height);
   Line(12,"REPLAY facts only. RETURN_OBSERVED is NOT entry permission.",clrOrange,width,height);
   ChartRedraw();
  }

void Poll()
  {
   bool h=false,m=false;
   bool hr=g_h4.Refresh(h),mr=g_m15.Refresh(m);
   if(!hr || !mr)
     {Clear("series not ready: H4 "+g_h4.StateName()+" M15 "+g_m15.StateName());Draw();return;}
   datetime cut=g_m15.FormingOpenTime();
   if(InpAsOfTime>0 && InpAsOfTime<cut) cut=InpAsOfTime;
   if(!M4TimelineNeedsBuild(InpAsOfTime>0,g_built,cut,g_cut,h,m)) return;
   Build(cut);Draw();
  }

int OnInit()
  {
   // On a timeframe change MT5 can retain globals from the preceding instance.
   M4ResetReplay(g_state,g_fvgs,g_events,g_info,g_built,g_cut);
   g_problem="initialising";g_h4_status="-";g_t2="UNKNOWN";g_h4_bias="UNKNOWN";
   g_replay_start=0;g_h4_depth=0;g_duration=0;
   ZeroMemory(g_current);g_current.status="DISABLED";
   ArrayResize(g_mbars,0);ArrayResize(g_hbars,0);ArrayResize(g_updates,0);
   ObjectsDeleteAll(0,PREFIX);
   if(InpAsOfTime<0 || InpH4LookbackBars<50 || InpH4LookbackBars>1000 ||
      InpH4RebuildBars<3*InpH4LookbackBars || InpH4RebuildBars>5000 ||
      InpH4LeftBars<1 || InpH4LeftBars>10 || InpH4RightBars<1 || InpH4RightBars>10 ||
      InpM15LeftBars<1 || InpM15LeftBars>10 || InpM15RightBars<1 || InpM15RightBars>10 ||
      InpM15LookbackBars<InpM15LeftBars+InpM15RightBars+1 || InpM15LookbackBars>1000 ||
      InpM15ReplayBars<16 || InpM15ReplayBars>5000 || InpPollSeconds<1 || InpPollSeconds>60 ||
      InpMaxFvgs<0 || InpMaxFvgs>30 || InpRecentLogEvents<0 || InpRecentLogEvents>20)
     {Print("T004 INIT FAILED: invalid inputs (see docs/T004-m15.md).");return(INIT_PARAMETERS_INCORRECT);}
   H3ParamsDefault(g_params);g_params.rebuild=InpH4RebuildBars;g_params.lookback=InpH4LookbackBars;
   g_params.left=InpH4LeftBars;g_params.right=InpH4RightBars;
   g_h4.Configure(_Symbol,PERIOD_H4,3);g_m15.Configure(_Symbol,PERIOD_M15,3);
   Print("T004 read-only observer. Three explicit proposal opt-ins, no order functions. All events are REPLAY, never NEW.");
   Print("T004 currently connects T003 RECONFIRMED contexts only; ordinary H4 touch integration remains unfinished.");
   if(!EventSetTimer(InpPollSeconds)) return(INIT_FAILED);
   Poll();return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason) {EventKillTimer();ObjectsDeleteAll(0,PREFIX);ChartRedraw();PrintFormat("T004 observer stopped (reason %d). No orders were sent, changed or closed.",reason);}
void OnTimer() {Poll();}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {if(id==CHARTEVENT_CHART_CHANGE) Draw();}
