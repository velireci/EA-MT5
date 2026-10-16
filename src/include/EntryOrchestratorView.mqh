//+------------------------------------------------------------------+
//| EntryOrchestratorView.mqh                                        |
//|                                                                  |
//| CHART VIEW of the decision the entry orchestrator already took.  |
//| It READS the outcome of the step, the M15 observer state and the |
//| H4 evaluation the feed already computed for its last snapshot;   |
//| it recomputes no signal, reads no future bar, invents no level   |
//| and sends nothing. Inputs are const; the EA calls Update() AFTER |
//| the decision step and only when the owner asked for the view     |
//| (InpChartView). On or off, the plans, blocks and FAKE requests   |
//| are the same.                                                    |
//|                                                                  |
//| WHAT IS DRAWN (every mark has a short label; colour never carries|
//| the meaning alone; the legend is on the chart):                  |
//|  H4  FVG zones   outline blue (bullish) / orange (bearish), label|
//|                  "H4 ...": solid = reconfirmed, dashed = candidate|
//|                  dotted grey = invalid. From the tracks of the   |
//|                  T003 evaluation of the build.                   |
//|  H4  sweep       dashed line at the swept level + a mark and a   |
//|                  label at the sweep candle. The level of an      |
//|                  internal sweep is the pivot bar named by the    |
//|                  decision's own event id (a lookup of that bar's |
//|                  high / low, not a new swing computation); the   |
//|                  level of a wick setup is the recorded snapshot. |
//|                  If a piece is missing it is NOT drawn.          |
//|  M15 break       line + mark at the candle that closed beyond the|
//|                  level, label "Thyerje M15" (prototype BOS, never|
//|                  called a validated MSS).                        |
//|  M15 FVG zones   outline; GOLD only for the FVG the plan bridge  |
//|                  really selected (spb.candidate_id).             |
//|  Plan            LIMIT entry, SL, 2R, TP with labels and prices; |
//|                  TP = 2R is one line with both names. No arrows. |
//| Text is Albanian WITHOUT diacritics (the sources are ASCII).     |
//| Objects: prefix velo_t016v_ only; manual drawings are untouched. |
//| The view is NOT evidence that the prototype matches the client's |
//| strategy. NOT YET COMPILED OR SEEN IN MT5 (UNVERIFIED).          |
//+------------------------------------------------------------------+
#ifndef VELO_ENTRY_ORCHESTRATOR_VIEW_MQH
#define VELO_ENTRY_ORCHESTRATOR_VIEW_MQH

#include "EntryOrchestratorFeed.mqh"

#define EV_PREFIX        "velo_t016v_"
#define EV_PANEL_PREFIX  "velo_t016v_pnl_"
#define EV_MAX_H4_FVG    4
#define EV_MAX_M15_FVG   4
#define EV_TIP_MAX       250     // a tooltip is clipped here; the facts that matter come first

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
   bool     real;          // the request mode when the plan was built: true = REAL (DEMO) transport, false = FAKE (virtual)
   string   signal_id;
   string   setup;
   string   verdict;       // PRET / BLLOKUAR / PLAN GATI / KERKESE VIRTUALE at the step that built the plan
   string   reason;
   datetime t0;
  };

void EV_PlanInit(SEvPlan &p)
  {
   p.have=false;
   p.direction=0;
   p.entry=0.0; p.sl=0.0; p.tp=0.0; p.level_2r=0.0; p.volume=0.0; p.risk=0.0;
   p.tp_is_2r=false;
   p.real=false;
   p.signal_id="";
   p.setup="";
   p.verdict="";
   p.reason="";
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

string EV_Hm(const datetime t)
  {
   return(TimeToString(t,TIME_DATE|TIME_MINUTES));
  }

string EV_DirectionText(const int direction)
  {
   if(direction==1) return("BUY");
   if(direction==-1) return("SELL");
   return("?");
  }

string EV_H4DirectionText(const int dir)
  {
   if(dir==H3_BULL) return("NGRITES (BUY)");
   if(dir==H3_BEAR) return("ZBRITES (SELL)");
   return("PA DREJTIM");
  }

//--- what the T003 phase means and what it waits for (words of H3VPhaseReason, no new rule)
string EV_H4PhaseText(const int phase,const bool has_setup)
  {
   if(phase==H3_PH_SWEEP_WAIT) return("sweep i brendshem u pa; pret qe cmimi te preke nje FVG H4 te ri");
   if(phase==H3_PH_HOLD) return("fitil mbi nivelin mbrojtes pa mbyllje; pret prekjen e nje FVG H4 te ri");
   if(phase==H3_PH_RECONFIRMED) return("FVG H4 u prek: setup i RIKONFIRMUAR");
   if(has_setup) return("setup aktiv");
   return("pa setup; pret sweep ose fitil mbi nivelin");
  }

//--- what the M15 observer waits for, from its own phase
string EV_M15PhaseText(const string phase,const bool has_context)
  {
   if(!has_context || phase=="WAIT_CONTEXT") return("pret setup H4 te rikonfirmuar (pa te, M15 nuk fillon)");
   if(phase=="WAIT_BREAK") return("pret thyerjen e nivelit M15");
   if(phase=="WAIT_FVG") return("thyerja u pa; pret nje FVG M15");
   if(phase=="WAIT_RETURN") return("FVG M15 ekziston; pret kthimin e cmimit ne te");
   if(phase=="RETURN_OBSERVED") return("cmimi u kthye ne FVG; pa hyrje te vonuar");
   if(phase=="REPLAY_REQUIRED") return("histori e rishikuar; pret rindertim");
   if(phase=="WAIT_POLICY") return("pret politiken e kohes se FVG");
   return("faza "+phase);
  }

//--- the first reason of a " | " joined list
string EV_FirstReason(const string reasons)
  {
   int k=StringFind(reasons," | ");
   if(k<0) return(reasons);
   return(StringSubstr(reasons,0,k));
  }

int EV_ReasonCount(const string reasons)
  {
   if(reasons=="") return(0);
   int n=1,from=0;
   while(true)
     {
      int k=StringFind(reasons," | ",from);
      if(k<0) break;
      n++;
      from=k+3;
     }
   return(n);
  }

bool EV_Starts(const string text,const string prefix)
  {
   return(StringFind(text,prefix)==0);
  }

//--- short Albanian meaning of a technical reason code (the code itself stays in the Experts log)
string EV_ReasonShort(const string code)
  {
   if(EV_Starts(code,"CONTEXT_LOST_OR_NOT_READY")) return("pret rikonfirmimin H4 (nje FVG H4 te preket)");
   if(EV_Starts(code,"PHASE_NOT_WAIT_RETURN")) return("M15 nuk ka ende FVG qe pret kthim");
   if(EV_Starts(code,"NO_ELIGIBLE_CANDIDATE")) return("asnje FVG M15 e pranueshme");
   if(EV_Starts(code,"AMBIGUOUS_CANDIDATES")) return("disa FVG M15, zgjedhja nuk eshte e qarte");
   if(EV_Starts(code,"HISTORICAL_OR_REPLAYED_CANDIDATE")) return("sinjal i vjeter (para nisjes); nuk perdoret");
   if(EV_Starts(code,"REPLAY_REQUIRED")) return("histori e rishikuar; pret rindertim");
   if(EV_Starts(code,"RETURN_ALREADY_OBSERVED") || EV_Starts(code,"CANDIDATE_RETURN_ALREADY_OBSERVED")) return("cmimi u kthye ne FVG para planit; pa hyrje te vonuar");
   if(EV_Starts(code,"CANDIDATE_INVALIDATED")) return("FVG M15 u be e pavlefshme");
   if(EV_Starts(code,"CONTEXT_SOURCE_MISMATCH") || EV_Starts(code,"TIMING_MISMATCH") || EV_Starts(code,"SELECTION_UNSET")) return("zgjedhjet e konfigurimit nuk perputhen");
   if(EV_Starts(code,"FUTURE_DATA") || EV_Starts(code,"BROKEN_LEVEL_MISMATCH") || EV_Starts(code,"CANDIDATE_")) return("te dhenat M15 nuk jane konsistente");
   if(EV_Starts(code,"SESSION_CLOSED")) return("jashte seances se tregtimit");
   if(EV_Starts(code,"SESSION_UNKNOWN")) return("seanca e panjohur");
   if(EV_Starts(code,"NEWS_BLOCK")) return("lajme USD me ndikim te larte");
   if(EV_Starts(code,"NEWS_UNKNOWN")) return("kalendari i lajmeve nuk lexohet");
   if(EV_Starts(code,"SPREAD_BLOCK")) return("spread shume i larte");
   if(EV_Starts(code,"SPREAD_UNKNOWN")) return("spread i panjohur");
   if(EV_Starts(code,"MAX_POSITIONS_REACHED")) return("kufiri i pozicioneve te hapura");
   if(EV_Starts(code,"MAX_TRADES_REACHED")) return("kufiri ditor i tregtive");
   if(EV_Starts(code,"COMBINED_RISK_EXCEEDED")) return("risku i kombinuar tejkalon kufirin");
   if(EV_Starts(code,"DAILY_WIN_STOP")) return("limiti ditor: fitore e arritur");
   if(EV_Starts(code,"CONSECUTIVE_LOSSES_STOP")) return("limiti ditor: humbje radhazi");
   if(EV_Starts(code,"DAILY_LOSS_LIMIT")) return("limiti ditor i humbjes");
   if(EV_Starts(code,"BALANCE_START_UNSET")) return("balanca e fillimit te dites mungon");
   if(EV_Starts(code,"BALANCE_DAY_MISMATCH")) return("balanca e ruajtur eshte per dite tjeter");
   if(EV_Starts(code,"HISTORY_")) return("historia ditore nuk eshte e plote");
   if(EV_Starts(code,"CLASSIFICATION_") || EV_Starts(code,"INCONSISTENT_COUNTERS")) return("numeruesit ditore te dhene nuk jane konsistente");
   if(EV_Starts(code,"INPUT_UNSET") || EV_Starts(code,"NOW_UNSET")) return("hyrje e paplotesuar per porten");
   if(EV_Starts(code,"INVALID_UTC") || EV_Starts(code,"UNSUPPORTED_YEAR") || EV_Starts(code,"STALE_SNAPSHOT_DAY")) return("ora ose dita e portes ditore nuk eshte e vlefshme");
   if(EV_Starts(code,"DAILY_")) return("porta ditore nuk lejon");
   if(EV_Starts(code,"POLICY_UNSET")) return("kufi i paplotesuar ne konfigurim");
   if(EV_Starts(code,"INVALID_SNAPSHOT")) return("te dhena te pavlefshme per porten");
   if(EV_Starts(code,"DATA_")) return("konteksti H4/M15 nuk eshte gati");
   if(EV_Starts(code,"DUPLICATE_SIGNAL")) return("sinjal i dyfishte");
   if(EV_Starts(code,"BROKER_LOSS_CHECK")) return("humbja e matur nga brokeri nuk perputhet me planin");
   if(EV_Starts(code,"PERMIT")) return("lejimi i planit nuk eshte i vlefshem");
   if(EV_Starts(code,"PLAN_")) return("plani nuk eshte i vlefshem");
   if(EV_Starts(code,"REGISTRY_")) return("regjistri i sinjaleve");
   if(EV_Starts(code,"PRE_SEND_RESERVATION_FAILED")) return("rezervimi i sinjalit deshtoi");
   if(EV_Starts(code,"QUOTE_") || EV_Starts(code,"BALANCE_") || EV_Starts(code,"ACCOUNT_")) return("kuota ose balanca nuk lexohen sic duhet");
   return("arsye teknike (shih Experts)");
  }

bool EV_IsWaitingReason(const string code)
  {
   return(EV_Starts(code,"CONTEXT_LOST_OR_NOT_READY") || EV_Starts(code,"PHASE_NOT_WAIT_RETURN") || EV_Starts(code,"NO_ELIGIBLE_CANDIDATE") ||
          EV_Starts(code,"HISTORICAL_OR_REPLAYED_CANDIDATE") || EV_Starts(code,"REPLAY_REQUIRED") || EV_Starts(code,"RETURN_ALREADY_OBSERVED") ||
          EV_Starts(code,"CANDIDATE_RETURN_ALREADY_OBSERVED"));
  }

//--- the decision of the step as ONE of PRET / BLLOKUAR / PLAN GATI / KERKESE VIRTUALE with a short reason
void EV_Verdict(const SEoOutcome &o,const SEvPlan &kept,const bool real,string &label,string &reason)
  {
   string s=o.status;
   label="PRET";
   reason="";
   if(s=="EXECUTOR")
     {
      if(o.request)
        {
         if(real) {label="KERKESE REALE"; reason="plan i pranuar; kerkese REALE (DEMO) e derguar te brokeri"; return;}
         label="KERKESE VIRTUALE";
         reason="plan i pranuar; kerkese FAKE, asgje nuk shkon te brokeri";
         return;
        }
      label="PLAN GATI";
      reason="plani kaloi porten, por ekzekutuesi nuk vendosi kerkese (shih Experts)";
      return;
     }
   if(s=="GATE_BLOCKED")
     {
      int n=EV_ReasonCount(o.dec.reasons);
      label="BLLOKUAR";
      reason="plani u ndertua, porta nuk lejon: "+EV_ReasonShort(EV_FirstReason(o.dec.reasons))+(n>1 ? " (+"+IntegerToString(n-1)+" arsye te tjera)" : "");
      return;
     }
   if(s=="ALREADY_HANDLED")
     {
      if(kept.have && kept.verdict!="") {label=kept.verdict; reason=kept.reason+" (trajtuar me pare)"; return;}
      reason="sinjali u trajtua me pare; nuk dergohet perseri";
      return;
     }
   if(s=="NO_PLAN")
     {
      if(EV_IsWaitingReason(o.reason)) {label="PRET"; reason=EV_ReasonShort(o.reason); return;}
      label="BLLOKUAR";
      reason="plan nuk ndertohet: "+EV_ReasonShort(o.reason);
      return;
     }
   if(s=="FEED_NOT_OK") {reason="te dhenat H4/M15 nuk jane gati"; return;}
   if(s=="MARKET_NOT_READY") {reason="kuota ose simboli nuk lexohen"; return;}
   if(s=="RISK_BASE_NOT_READY") {reason="balanca per riskun nuk lexohet"; return;}
   if(s=="HALTED") {label="BLLOKUAR"; reason="mbrojtja e ndali sistemin (shih Experts)"; return;}
   if(s=="CONFIG_UNSET") {label="BLLOKUAR"; reason="konfigurim i paplote (shih Experts)"; return;}
   if(s=="SIMULATION_REFUSED") {label="BLLOKUAR"; reason="politika SIMULATION lejohet vetem me hyrje FAKE"; return;}
   if(s=="PROBE_FAILED") {label="BLLOKUAR"; reason="humbja nga brokeri nuk u mat; plani ndalet"; return;}
   if(s=="RESERVATION_FAILED") {label="BLLOKUAR"; reason="rezervimi deshtoi; asgje nuk u vendos"; return;}
   reason="gjendje "+s;
  }

color EV_VerdictColor(const string label)
  {
   if(label=="KERKESE VIRTUALE" || label=="KERKESE REALE" || label=="PLAN GATI") return(clrLimeGreen);
   if(label=="BLLOKUAR") return(clrOrangeRed);
   return(clrWhite);
  }

//--- "IH201610161200" / "IL..." (the id of an internal swing level) -> pivot open time, kind letter
bool EV_ParseInteriorId(const string id,datetime &pivot,bool &is_high)
  {
   if(StringLen(id)!=14) return(false);
   string kind=StringSubstr(id,0,2);
   if(kind!="IH" && kind!="IL") return(false);
   string st=StringSubstr(id,2,12);
   pivot=StringToTime(StringSubstr(st,0,4)+"."+StringSubstr(st,4,2)+"."+StringSubstr(st,6,2)+" "+StringSubstr(st,8,2)+":"+StringSubstr(st,10,2));
   if(pivot<=0) return(false);
   is_high=(kind=="IH");
   return(true);
  }

//--- value of a key in "k=v;k=v" (the event details)
string EV_Detail(const string detail,const string key)
  {
   string needle=key+"=";
   int k=StringFind(detail,needle);
   if(k<0 || (k>0 && StringGetCharacter(detail,k-1)!=';')) return("");
   int from=k+StringLen(needle);
   int e=StringFind(detail,";",from);
   return(e<0 ? StringSubstr(detail,from) : StringSubstr(detail,from,e-from));
  }

//--- the sources are ASCII; the markers below become the Albanian letters at the moment a text reaches the chart (box rows and tooltips):
//---   ~e = e-diaeresis, ~c = c-cedilla, ~E = capital E-diaeresis, ~C = capital C-cedilla, ~b = bullet, ~m = em dash
string EV_T(const string text)
  {
   if(StringFind(text,"~")<0) return(text);
   string r=text;
   StringReplace(r,"~e",ShortToString(0x00EB));
   StringReplace(r,"~c",ShortToString(0x00E7));
   StringReplace(r,"~E",ShortToString(0x00CB));
   StringReplace(r,"~C",ShortToString(0x00C7));
   StringReplace(r,"~b",ShortToString(0x2022));
   StringReplace(r,"~m",ShortToString(0x2014));
   return(r);
  }

//--- direction word and the SHORT states of the panel rows (the full explanations go to the tooltips)
string EV_DirWord(const int dir)
  {
   if(dir==H3_BULL) return("BUY");
   if(dir==H3_BEAR) return("SELL");
   return("pa drejtim");
  }

string EV_H4Short(const int phase,const bool has_setup,const bool reliable)
  {
   if(!reliable) return("I pasigurt");
   if(phase==H3_PH_RECONFIRMED) return("Rikonfirmuar");
   if(phase==H3_PH_SWEEP_WAIT || phase==H3_PH_HOLD) return("Pret rikonfirmim");
   if(has_setup) return("Setup aktiv");
   return("Pa setup");
  }

string EV_M15Short(const string phase,const bool has_context)
  {
   if(!has_context || phase=="WAIT_CONTEXT") return("N~e pritje");
   if(phase=="WAIT_BREAK") return("Pret thyerje");
   if(phase=="WAIT_FVG") return("Pret FVG");
   if(phase=="WAIT_RETURN") return("Pret kthim n~e FVG");
   if(phase=="RETURN_OBSERVED") return("U kthye n~e FVG");
   if(phase=="REPLAY_REQUIRED") return("Rindertim");
   return("N~e pritje");
  }

//--- a few words for the decision row; the full sentence stays in the tooltip
string EV_ReasonTiny(const string code)
  {
   if(EV_Starts(code,"SPREAD_")) return("spread");
   if(EV_Starts(code,"NEWS_")) return("lajme");
   if(EV_Starts(code,"SESSION_")) return("seanca");
   if(EV_Starts(code,"COMBINED_RISK")) return("risku");
   if(EV_Starts(code,"MAX_POSITIONS") || EV_Starts(code,"MAX_TRADES")) return("kufi");
   if(EV_Starts(code,"DAILY_") || EV_Starts(code,"CONSECUTIVE_") || EV_Starts(code,"BALANCE_") || EV_Starts(code,"HISTORY_") || EV_Starts(code,"INCONSISTENT") || EV_Starts(code,"CLASSIFICATION_")) return("porta ditore");
   if(EV_Starts(code,"POLICY_UNSET") || EV_Starts(code,"INVALID_SNAPSHOT") || EV_Starts(code,"INPUT_UNSET")) return("konfigurim");
   if(EV_Starts(code,"BROKER_LOSS")) return("humbja");
   if(EV_Starts(code,"DUPLICATE")) return("dyfishte");
   return("shih tooltip");
  }

//--- LAYOUT (pure; mirrored by tests/view_layout_reference.py): word wrap of one panel line to the characters that fit, continuation rows indented by two spaces
int EV_Wrap(const string text,const int width_in,string &rows[])
  {
   int width=(width_in<8 ? 8 : width_in);
   ArrayResize(rows,0);
   if(StringLen(text)<=width) {ArrayResize(rows,1); rows[0]=text; return(1);}
   string words[];
   int nw=StringSplit(text,' ',words);
   string cur="";
   int n=0;
   for(int k=0;k<nw;k++)
     {
      string w=words[k];
      if(w=="") continue;
      string indent=(n==0 ? "" : "  ");
      int room=width-StringLen(indent);
      string cand=(cur=="" ? w : cur+" "+w);
      if(StringLen(cand)<=room) {cur=cand; continue;}
      if(cur!="")
        {
         ArrayResize(rows,n+1);
         rows[n]=indent+cur;
         n++;
         cur="";
         room=width-2;
        }
      while(StringLen(w)>room)
        {
         ArrayResize(rows,n+1);
         rows[n]=(n==0 ? "" : "  ")+StringSubstr(w,0,room);
         n++;
         w=StringSubstr(w,room);
         room=width-2;
        }
      cur=w;
     }
   if(cur!="") {ArrayResize(rows,n+1); rows[n]=(n==0 ? "" : "  ")+cur; n++;}
   return(n);
  }

//--- which lines stay when the chart has only max_rows rows: the lines with the HIGHEST priority number leave first (the later one of equal priority first); priority 0 never leaves;
//--- a dropped line is announced by one marker row, which counts in max_rows. Returns the number of dropped lines.
int EV_Select(const string &texts[],const int &prio[],const int n,const int width,const int max_rows,bool &keep[])
  {
   ArrayResize(keep,n);
   int rows[];
   ArrayResize(rows,n);
   string tmp[];
   int total=0;
   for(int i=0;i<n;i++)
     {
      keep[i]=true;
      rows[i]=EV_Wrap(texts[i],width,tmp);
      total+=rows[i];
     }
   int dropped=0;
   while(total+(dropped>0 ? 1 : 0)>max_rows)
     {
      int pick=-1;
      for(int i=0;i<n;i++)
         if(keep[i] && prio[i]>0 && (pick<0 || prio[i]>=prio[pick])) pick=i;
      if(pick<0) break;
      keep[pick]=false;
      total-=rows[pick];
      dropped++;
     }
   return(dropped);
  }

//--- swatch kinds (real graphic objects placed beside the legend labels; MQL objects render the same on every machine)
#define SW_NONE        0
#define SW_H4          1
#define SW_M15         2
#define SW_GOLD        3
#define SW_SWEEP       4
#define SW_BREAK       5
#define SW_PLAN        6
#define SW_ARROW_DOWN  7
#define SW_ARROW_UP    8

//--- a text box with a background, fitted to the chart: its own objects (OBJ_RECTANGLE_LABEL + OBJ_LABEL), all anchored at the upper left corner of the chart. The size of a character and of a row is
//--- MEASURED with the real font (TextGetSize), so the text is not cut on a high-DPI screen; a gutter at the left of the rows holds a swatch or a glyph. test_w / test_h are used only by the
//--- MT5 test to simulate a narrow or a short chart (0 = the real chart).
class CEvBox
  {
private:
   string   m_prefix;
   long     m_chart;
   int      m_font;
   int      m_pad;
   int      m_gutter_x10;
   int      m_lh;
   int      m_char_px;
   color    m_bgc;
   string   m_text[];
   color    m_clr[];
   int      m_prio[];
   int      m_sw[];
   color    m_swc[];
   string   m_tip[];
   int      m_n;
   int      m_made;
   int      m_test_w;
   int      m_test_h;
   int      m_tip_max;        // characters of a tooltip that the terminal keeps (measured once; EV_TIP_MAX at most)

   void Put(const string name,const ENUM_OBJECT type)
     {
      if(ObjectFind(m_chart,name)>=0) return;
      if(!ObjectCreate(m_chart,name,type,0,0,0)) {ResetLastError(); return;}
      ObjectSetInteger(m_chart,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(m_chart,name,OBJPROP_BACK,false);
     }
   void Metrics(void)
     {
      uint w=0,h=0;
      TextSetFont("Consolas",-10*m_font,0,0);
      if(TextGetSize("MMMMMMMMMM",w,h) && w>0 && h>0) {m_char_px=(int)MathCeil(w/10.0); m_lh=(int)h+3;}
      else {m_char_px=(int)MathMax(6.0,MathCeil(m_font*0.95)); m_lh=m_font+8;}
     }
   //--- how many characters of a tooltip the terminal really keeps: set 400, read back; a clipped tooltip then loses its tail, never its start
   void MeasureTip(void)
     {
      string probe=m_prefix+"probe";
      m_tip_max=EV_TIP_MAX;
      if(!ObjectCreate(m_chart,probe,OBJ_LABEL,0,0,0)) {ResetLastError(); return;}
      string t="";
      while(StringLen(t)<400) t+="0123456789";
      ObjectSetString(m_chart,probe,OBJPROP_TOOLTIP,t);
      int kept=StringLen(ObjectGetString(m_chart,probe,OBJPROP_TOOLTIP));
      ObjectDelete(m_chart,probe);
      if(kept>=40 && kept<m_tip_max) m_tip_max=kept;
     }
   int  TextWidth(const string text)
     {
      uint w=0,h=0;
      TextSetFont("Consolas",-10*m_font,0,0);
      if(TextGetSize(text,w,h) && w>0) return((int)w);
      return(StringLen(text)*m_char_px);
     }
   void Fill(const string name,const int x,const int y,const int w,const int h,const color fill,const color border)
     {
      Put(name,OBJ_RECTANGLE_LABEL);
      ObjectSetInteger(m_chart,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(m_chart,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(m_chart,name,OBJPROP_XSIZE,(int)MathMax(1.0,(double)w));
      ObjectSetInteger(m_chart,name,OBJPROP_YSIZE,(int)MathMax(1.0,(double)h));
      ObjectSetInteger(m_chart,name,OBJPROP_BGCOLOR,fill);
      ObjectSetInteger(m_chart,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,border);
     }
   //--- an outline box: a filled rectangle with the background inside it
   void Outline(const string name,const int x,const int y,const int w,const int h,const color c,const int thick)
     {
      Fill(name+"o",x,y,w,h,c,c);
      Fill(name+"i",x+thick,y+thick,w-2*thick,h-2*thick,m_bgc,m_bgc);
     }
   //--- a small filled square used as a dot (stable on every machine: no symbol font, no code point)
   void Dot(const string name,const int x,const int y,const int d,const color c)
     {
      Fill(name,x,y,d,d,c,c);
     }
   //--- an arrow made of rectangles: a stem and a three-row head
   void Arrow(const string n,const int x,const int y,const bool down,const color c)
     {
      int stem=(int)MathMax(4.0,(double)(m_lh-14));
      int ty=y+2;
      if(down)
        {
         Fill(n+"a0",x+4,ty,3,stem,c,c);
         Fill(n+"a1",x,ty+stem,11,2,c,c);
         Fill(n+"a2",x+2,ty+stem+2,7,2,c,c);
         Fill(n+"a3",x+4,ty+stem+4,3,2,c,c);
        }
      else
        {
         Fill(n+"a1",x+4,ty,3,2,c,c);
         Fill(n+"a2",x+2,ty+2,7,2,c,c);
         Fill(n+"a3",x,ty+4,11,2,c,c);
         Fill(n+"a0",x+4,ty+6,3,stem,c,c);
        }
     }
   void Swatch(const int kind,const int row,const int x,const int y,const color dir_clr)
     {
      string n=m_prefix+"s"+IntegerToString(row)+"_";
      int u=m_lh;
      int bh=u-6;
      int by=y+3;
      if(kind==SW_H4)
        {
         Outline(n+"a",x,by,(int)(u*0.9),bh,clrDodgerBlue,2);
         Outline(n+"b",x+(int)(u*1.1),by,(int)(u*0.9),bh,clrDarkOrange,2);
        }
      else if(kind==SW_M15) Outline(n+"a",x,by,(int)(u*1.3),bh,clrSilver,1);
      else if(kind==SW_GOLD) Outline(n+"a",x,by,(int)(u*1.3),bh,clrGold,3);
      else if(kind==SW_SWEEP || kind==SW_BREAK)
        {
         int ly=y+u/2-1;
         if(kind==SW_SWEEP)
           {
            for(int k=0;k<3;k++) Fill(n+"d"+IntegerToString(k),x+k*(int)(u*0.55),ly,(int)(u*0.35),2,clrSilver,clrSilver);
           }
         else Fill(n+"d0",x,ly,(int)(u*1.6),2,clrWhite,clrWhite);
         Dot(n+"g",x+(int)(u*1.65),y+u/2-3,6,(kind==SW_SWEEP ? clrSilver : clrWhite));
        }
      else if(kind==SW_PLAN)
        {
         int ly=y+u/2-1;
         Fill(n+"e",x,ly,(int)(u*0.55),3,clrDodgerBlue,clrDodgerBlue);
         Fill(n+"s",x+(int)(u*0.7),ly,(int)(u*0.55),3,clrRed,clrRed);
         Fill(n+"r",x+(int)(u*1.4),ly,(int)(u*0.55),3,clrLimeGreen,clrLimeGreen);
         Fill(n+"t",x+(int)(u*2.1),ly,(int)(u*0.55),3,clrLimeGreen,clrLimeGreen);
        }
      else if(kind==SW_ARROW_DOWN) Arrow(n,x,y,true,dir_clr);
      else if(kind==SW_ARROW_UP) Arrow(n,x,y,false,dir_clr);
     }

public:
   CEvBox(void)
     {
      m_prefix=EV_PANEL_PREFIX;
      m_chart=0;
      m_font=9;
      m_pad=5;
      m_gutter_x10=0;
      m_lh=15;
      m_char_px=7;
      m_bgc=C'16,20,28';
      m_n=0;
      m_made=0;
      m_test_w=0;
      m_test_h=0;
      m_tip_max=EV_TIP_MAX;
     }
   int  TipMax(void) const {return(m_tip_max);}
   void Init(const string prefix,const int font,const int gutter_x10)
     {
      m_prefix=prefix;
      m_chart=ChartID();
      m_font=font;
      m_gutter_x10=gutter_x10;
      m_n=0;
      m_made=0;
      Metrics();
      ObjectsDeleteAll(m_chart,m_prefix);
      MeasureTip();
     }
   void TestSize(const int w,const int h) {m_test_w=w; m_test_h=h;}
   int  LineHeight(void) {Metrics(); return(m_lh);}
   void Begin(void) {m_n=0;}
   //--- text with the ~ markers; swatch kind SW_*; tip = the long explanation (hover); priority as in EV_Select
   void Line(const string text,const color clr,const int priority,const int swatch=0,const string tip="",const color swatch_clr=clrNONE)
     {
      ArrayResize(m_text,m_n+1);
      ArrayResize(m_clr,m_n+1);
      ArrayResize(m_prio,m_n+1);
      ArrayResize(m_sw,m_n+1);
      ArrayResize(m_swc,m_n+1);
      ArrayResize(m_tip,m_n+1);
      m_text[m_n]=EV_T(text);
      m_clr[m_n]=clr;
      m_prio[m_n]=priority;
      m_sw[m_n]=swatch;
      m_swc[m_n]=(swatch_clr==clrNONE ? clr : swatch_clr);      // the symbol keeps ITS colour (e.g. the H4 direction), whatever the colour of the text
      m_tip[m_n]=EV_T(EV_Clip(tip,m_tip_max));
      m_n++;
     }
   //--- draws the lines that fit; returns the pixel height of the box. from_bottom: the box sits on the lower edge of the chart, else its top is top_px.
   int  Render(const int max_rows,const int top_px,const bool from_bottom)
     {
      Metrics();
      int chart_w=(m_test_w>0 ? m_test_w : (int)ChartGetInteger(m_chart,CHART_WIDTH_IN_PIXELS,0));
      int chart_h=(m_test_h>0 ? m_test_h : (int)ChartGetInteger(m_chart,CHART_HEIGHT_IN_PIXELS,0));
      int gut=(m_gutter_x10*m_lh)/10;
      int max_w=(chart_w<300 ? chart_w-12 : (int)MathMax(260.0,chart_w*0.72));
      int width_chars=(int)MathMax(16.0,(double)((max_w-2*m_pad-gut)/m_char_px));
      bool keep[];
      int dropped=EV_Select(m_text,m_prio,m_n,width_chars,max_rows,keep);
      string rows[];
      color rclr[];
      int rline[];
      int nr=0;
      for(int i=0;i<m_n;i++)
        {
         if(!keep[i]) continue;
         string parts[];
         int np=EV_Wrap(m_text[i],width_chars,parts);
         for(int k=0;k<np;k++)
           {
            ArrayResize(rows,nr+1);
            ArrayResize(rclr,nr+1);
            ArrayResize(rline,nr+1);
            rows[nr]=parts[k];
            rclr[nr]=m_clr[i];
            rline[nr]=i;
            nr++;
           }
        }
      if(dropped>0)
        {
         ArrayResize(rows,nr+1);
         ArrayResize(rclr,nr+1);
         ArrayResize(rline,nr+1);
         rows[nr]=StringFormat("(+%d te fshehura)",dropped);
         rclr[nr]=C'170,170,170';
         rline[nr]=-1;
         nr++;
        }
      int widest=0;
      for(int i=0;i<nr;i++) widest=(int)MathMax((double)widest,(double)TextWidth(rows[i]));
      int w_px=widest+gut+2*m_pad+2;
      if(w_px>chart_w-12) w_px=chart_w-12;
      int h_px=nr*m_lh+2*m_pad;
      int y=(from_bottom ? chart_h-h_px-6 : top_px);
      if(y<0) y=0;
      ObjectsDeleteAll(m_chart,m_prefix+"s");                    // the swatches are redrawn below
      string bg=m_prefix+"bg";
      Fill(bg,6,y,w_px,h_px,m_bgc,C'80,86,98');
      for(int i=0;i<nr;i++)
        {
         string name=m_prefix+StringFormat("%03d",i);
         int ry=y+m_pad+i*m_lh;
         Put(name,OBJ_LABEL);
         ObjectSetInteger(m_chart,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
         ObjectSetInteger(m_chart,name,OBJPROP_XDISTANCE,6+m_pad+gut);
         ObjectSetInteger(m_chart,name,OBJPROP_YDISTANCE,ry);
         ObjectSetInteger(m_chart,name,OBJPROP_FONTSIZE,m_font);
         ObjectSetString(m_chart,name,OBJPROP_FONT,"Consolas");
         ObjectSetString(m_chart,name,OBJPROP_TEXT,rows[i]);
         ObjectSetString(m_chart,name,OBJPROP_TOOLTIP,(rline[i]>=0 ? m_tip[rline[i]] : ""));
         ObjectSetInteger(m_chart,name,OBJPROP_COLOR,rclr[i]);
         // the swatch sits beside the FIRST row of its line
         if(rline[i]>=0 && m_sw[rline[i]]!=SW_NONE && (i==0 || rline[i-1]!=rline[i]))
            Swatch(m_sw[rline[i]],i,6+m_pad,ry,m_swc[rline[i]]);
        }
      for(int i=nr;i<m_made;i++)
        {
         string old=m_prefix+StringFormat("%03d",i);
         if(ObjectFind(m_chart,old)>=0) ObjectDelete(m_chart,old);
        }
      m_made=nr;
      return(h_px);
     }
   void Destroy(void)
     {
      ObjectsDeleteAll(m_chart,m_prefix);
      m_made=0;
      m_n=0;
     }
  };

//--- a digest of everything the marks are drawn from (the content, not only the counts): two snapshots that differ in the direction, a level, an event or a zone must redraw
string EV_Px(const double v) {return(MathIsValidNumber(v) ? DoubleToString(v,8) : "n");}
string EV_FeedSig(const CEoFeed &feed)
  {
   string g="";
   if(feed.dv_have)
     {
      g+="H4|"+IntegerToString(feed.dv_ev.st.dir)+"|"+IntegerToString(feed.dv_ev.st.phase)+"|"+feed.dv_ev.st.setup_id+"|"+feed.dv_ev.st.setup_type+"|"+IntegerToString((long)feed.dv_ev.st.sweep_time)+"|"+
         IntegerToString((long)feed.dv_ev.st.wk_src)+"|"+EV_Px(feed.dv_ev.st.snap_price)+"|"+IntegerToString((long)feed.dv_ev.st.snap_known)+"|"+feed.dv_ev.st.rec_id+"|"+IntegerToString(feed.dv_n)+"|"+(feed.dv_ev.reliable ? "1" : "0")+";";
      for(int i=0;i<ArraySize(feed.dv_tracks);i++)
         g+=feed.dv_tracks[i].id+","+EV_Px(feed.dv_tracks[i].lower)+","+EV_Px(feed.dv_tracks[i].upper)+","+IntegerToString((long)feed.dv_tracks[i].time_a)+","+IntegerToString((long)feed.dv_tracks[i].conf)+","+(feed.dv_tracks[i].invalid ? "1" : "0")+";";
      for(int j=0;j<ArraySize(feed.dv_events);j++)
         g+=IntegerToString(feed.dv_events[j].type)+","+IntegerToString((long)feed.dv_events[j].bar_time)+","+feed.dv_events[j].ref+","+feed.dv_events[j].detail+";";
     }
   if(feed.dv_have && feed.dv_n>0 && ArraySize(feed.hbars)>=feed.dv_n)
      g+="|bar|"+IntegerToString((long)feed.hbars[feed.dv_n-1].time)+","+EV_Px(feed.hbars[feed.dv_n-1].high)+","+EV_Px(feed.hbars[feed.dv_n-1].low)+","+EV_Px(feed.hbars[feed.dv_n-1].close);
   g+="|M15|"+IntegerToString(feed.st.context.direction)+"|"+feed.st.context.setup+"|"+IntegerToString((long)feed.st.bos_time)+"|"+feed.st.bos_level+"|"+(feed.broken.valid ? "1" : "0")+","+feed.broken.id+","+
      EV_Px(feed.broken.price)+","+IntegerToString((long)feed.broken.known)+";";
   for(int k=0;k<ArraySize(feed.f);k++)
      g+=feed.f[k].id+","+EV_Px(feed.f[k].lower)+","+EV_Px(feed.f[k].upper)+","+IntegerToString((long)feed.f[k].confirmed)+","+(feed.f[k].returned ? "1" : "0")+","+(feed.f[k].invalid ? "1" : "0")+";";
   return(g);
  }

class CEoView
  {
private:
   bool            m_on;
   long            m_chart;
   int             m_digits;
   CEvBox          m_panel;
   CEvBox          m_legend;
   string          m_signature;
   SEvPlan         m_plan;
   int             m_test_h;         // MT5 test only: simulated chart height (0 = the real chart)
   int             m_n_objects;      // marks drawn by the last redraw (the panel and the legend are not counted)

   bool Ensure(const string name,const ENUM_OBJECT type)
     {
      if(ObjectFind(m_chart,name)>=0) return(true);
      if(!ObjectCreate(m_chart,name,type,0,0,0)) {ResetLastError(); return(false);}
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
      m_n_objects++;
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
      ObjectSetString(m_chart,name,OBJPROP_TOOLTIP,EV_T(tip));
     }
   //--- outline only (no fill): the candles stay readable under the zone
   void Zone(const string name,const datetime t1,const double p1,const datetime t2,const double p2,const color clr,const int width,const ENUM_LINE_STYLE style,const string tip)
     {
      if(!Ensure(name,OBJ_RECTANGLE)) return;
      ObjectSetInteger(m_chart,name,OBJPROP_TIME,0,t1);
      ObjectSetDouble(m_chart,name,OBJPROP_PRICE,0,p1);
      ObjectSetInteger(m_chart,name,OBJPROP_TIME,1,t2);
      ObjectSetDouble(m_chart,name,OBJPROP_PRICE,1,p2);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(m_chart,name,OBJPROP_FILL,false);
      ObjectSetInteger(m_chart,name,OBJPROP_BACK,false);
      ObjectSetInteger(m_chart,name,OBJPROP_WIDTH,width);
      ObjectSetInteger(m_chart,name,OBJPROP_STYLE,style);
      ObjectSetString(m_chart,name,OBJPROP_TOOLTIP,EV_T(tip));
     }
   void Note(const string name,const datetime t,const double p,const string text,const color clr,const ENUM_ANCHOR_POINT anchor,const string tip)
     {
      if(!Ensure(name,OBJ_TEXT)) return;
      ObjectSetInteger(m_chart,name,OBJPROP_TIME,0,t);
      ObjectSetDouble(m_chart,name,OBJPROP_PRICE,0,p);
      ObjectSetString(m_chart,name,OBJPROP_TEXT,EV_T(text));
      ObjectSetString(m_chart,name,OBJPROP_TOOLTIP,EV_T(tip));
      ObjectSetString(m_chart,name,OBJPROP_FONT,"Arial");
      ObjectSetInteger(m_chart,name,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(m_chart,name,OBJPROP_ANCHOR,anchor);
     }
   //--- a small dot at a candle (NOT an entry arrow); the label next to it carries the meaning
   void Dot(const string name,const datetime t,const double p,const color clr,const string tip)
     {
      if(!Ensure(name,OBJ_ARROW)) return;
      ObjectSetInteger(m_chart,name,OBJPROP_ARROWCODE,159);
      ObjectSetInteger(m_chart,name,OBJPROP_TIME,0,t);
      ObjectSetDouble(m_chart,name,OBJPROP_PRICE,0,p);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(m_chart,name,OBJPROP_WIDTH,3);
      ObjectSetString(m_chart,name,OBJPROP_TOOLTIP,EV_T(tip));
     }
   //--- delete the marks of this component; the panel and the legend labels (EV_PANEL_PREFIX) and every other prefix stay
   void ClearObjects(void)
     {
      for(int i=ObjectsTotal(m_chart,0,-1)-1;i>=0;i--)
        {
         string name=ObjectName(m_chart,i,0,-1);
         if(StringFind(name,EV_PREFIX)!=0) continue;
         if(StringFind(name,EV_PANEL_PREFIX)==0) continue;
         ObjectDelete(m_chart,name);
        }
      m_n_objects=0;
     }
   //--- the plan of this step, or the kept plan of the same signal; dropped as soon as its H4 setup is no longer the live context
   void TrackPlan(const SEoOutcome &out,const CEoFeed &feed,const bool real)
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
         m_plan.real=real;
         m_plan.signal_id=out.spb.signal_id;
         m_plan.setup=feed.st.context.setup;
         EV_Verdict(out,m_plan,real,m_plan.verdict,m_plan.reason);
         m_plan.t0=(feed.st.bos_time>0 ? feed.st.bos_time : feed.cut-8*900);
         return;
        }
      if(m_plan.have && out.status=="ALREADY_HANDLED" && out.spb.signal_id==m_plan.signal_id) return;      // the kept plan of the handled signal
      if(m_plan.have && (!feed.st.has_context || feed.st.context.setup!=m_plan.setup)) EV_PlanInit(m_plan);
     }
   //--- index of the closed H4 bar with this open time, or -1 (the bars of the last snapshot only)
   int FindH4Bar(const CEoFeed &feed,const datetime t)
     {
      for(int i=feed.dv_n-1;i>=0;i--)
        {
         if(feed.hbars[i].time==t) return(i);
         if(feed.hbars[i].time<t) break;
        }
      return(-1);
     }
   //--- H4: the sweep (level + candle) and the FVG zones of the T003 evaluation the build already computed
   void DrawH4(const CEoFeed &feed)
     {
      if(!feed.dv_have) return;
      if(feed.dv_ev.st.dir==H3_NONE || feed.dv_ev.st.setup_id=="") return;               // no setup: nothing is invented
      int dir=feed.dv_ev.st.dir;
      color dc=(dir==H3_BULL ? clrDodgerBlue : clrDarkOrange);
      datetime end=feed.cut+16*900;
      //--- sweep
      bool is_internal=(feed.dv_ev.st.setup_type=="SWEEP");
      datetime sweep_t=(is_internal ? feed.dv_ev.st.sweep_time : feed.dv_ev.st.wk_src);
      string what=(is_internal ? "Sweep H4" : "Fitil H4");
      string tip=(is_internal ? "Sweep H4: u mor likuiditeti i brendshem (swing i brendshem)" : "Fitil H4: fitil mbi nivelin mbrojtes, pa mbyllje matane tij");
      double level=0.0;
      datetime level_from=0;
      if(is_internal)
        {
         datetime pivot=0;
         bool is_high=false;
         for(int j=0;j<ArraySize(feed.dv_events);j++)
           {
            if(feed.dv_events[j].type!=H3_EV_INT_SWEEP || feed.dv_events[j].bar_time!=sweep_t) continue;
            if(EV_Detail(feed.dv_events[j].detail,"setup")!="1") continue;
            if(!EV_ParseInteriorId(feed.dv_events[j].ref,pivot,is_high)) continue;
            int pi=FindH4Bar(feed,pivot);
            if(pi<0) continue;
            level=(is_high ? feed.hbars[pi].high : feed.hbars[pi].low);
            level_from=pivot;
            break;
           }
        }
      else
        {
         if(MathIsValidNumber(feed.dv_ev.st.snap_price) && feed.dv_ev.st.snap_price>0.0)
           {
            level=feed.dv_ev.st.snap_price;
            level_from=(feed.dv_ev.st.snap_known>0 && feed.dv_ev.st.snap_known<sweep_t ? feed.dv_ev.st.snap_known : sweep_t-4*14400);
           }
        }
      int si=(sweep_t>0 ? FindH4Bar(feed,sweep_t) : -1);
      if(si>=0)
        {
         double mark=(dir==H3_BEAR ? feed.hbars[si].high : feed.hbars[si].low);
         Dot(EV_PREFIX+"sweep_dot",sweep_t,mark,dc,tip+" | "+EV_Hm(sweep_t));
         Note(EV_PREFIX+"sweep_txt",sweep_t,mark,what,dc,(dir==H3_BEAR ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER),tip+" | "+EV_Hm(sweep_t));
         if(level>0.0)
            Segment(EV_PREFIX+"sweep_lvl",level_from,level,sweep_t+14400,level,dc,1,STYLE_DASH,"Niveli i "+what+" "+EV_Price(level,m_digits));
        }
      //--- FVG zones: the reconfirmed one first, then the newest candidates, then the newest invalid one; at most EV_MAX_H4_FVG
      int nt=ArraySize(feed.dv_tracks);
      bool used[];
      ArrayResize(used,nt);
      for(int i=0;i<nt;i++) used[i]=false;
      int shown=0;
      for(int pass=0;pass<3;pass++)
        {
         int limit=(pass==2 ? 1 : EV_MAX_H4_FVG);
         int taken=0;
         while(shown<EV_MAX_H4_FVG && taken<limit)
           {
            int pick=-1;
            for(int i=0;i<nt;i++)
              {
               if(used[i]) continue;
               bool is_rec=(feed.dv_ev.st.phase==H3_PH_RECONFIRMED && feed.dv_tracks[i].id==feed.dv_ev.st.rec_id);
               bool ok=(pass==0 ? is_rec : (pass==1 ? (!is_rec && !feed.dv_tracks[i].invalid) : (!is_rec && feed.dv_tracks[i].invalid)));
               if(!ok) continue;
               if(pick<0 || feed.dv_tracks[i].conf>feed.dv_tracks[pick].conf) pick=i;
              }
            if(pick<0) break;
            used[pick]=true;
            bool rec=(pass==0);
            bool inv=(pass==2);
            string state=(rec ? "rikonfirmuar" : (inv ? "i pavlefshem" : "kandidat"));
            Zone(EV_PREFIX+"h4fvg_"+IntegerToString(shown),feed.dv_tracks[pick].time_a,feed.dv_tracks[pick].lower,end,feed.dv_tracks[pick].upper,(inv ? clrDimGray : dc),
                 (rec ? 2 : 1),(rec ? STYLE_SOLID : (inv ? STYLE_DOT : STYLE_DASH)),"FVG H4 "+state+" "+EV_Price(feed.dv_tracks[pick].lower,m_digits)+" - "+EV_Price(feed.dv_tracks[pick].upper,m_digits)+" | "+feed.dv_tracks[pick].id);
            Note(EV_PREFIX+"h4fvg_txt"+IntegerToString(shown),feed.dv_tracks[pick].time_a,feed.dv_tracks[pick].upper,"H4 "+state,(inv ? clrDimGray : dc),ANCHOR_LEFT_LOWER,
                 "FVG H4 "+state+" | "+feed.dv_tracks[pick].id);
            shown++;
            taken++;
           }
        }
     }
   //--- M15: the break of the level and the FVG zones of the observer; GOLD only for the FVG the plan bridge selected
   void DrawM15(const SEoOutcome &out,const CEoFeed &feed)
     {
      if(!feed.st.has_context) return;
      int d=feed.st.context.direction;
      datetime end=feed.cut+16*900;
      if(feed.st.bos_time>0 && feed.broken.valid && feed.broken.id==feed.st.bos_level)
        {
         Segment(EV_PREFIX+"brk_line",feed.broken.known,feed.broken.price,feed.st.bos_time+900,feed.broken.price,clrWhite,2,STYLE_SOLID,
                 "Thyerje M15: qiriu "+EV_Hm(feed.st.bos_time)+" mbylli matane nivelit "+EV_Price(feed.broken.price,m_digits)+". Prototip BOS, NUK eshte MSS i vleresuar nga klienti. "+feed.broken.id);
         Dot(EV_PREFIX+"brk_dot",feed.st.bos_time,feed.broken.price,clrWhite,"Qiriu qe konfirmoi thyerjen M15 "+EV_Hm(feed.st.bos_time));
         Note(EV_PREFIX+"brk_txt",feed.st.bos_time,feed.broken.price,"Thyerje M15 "+EV_Price(feed.broken.price,m_digits),clrWhite,(d==1 ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER),
              "Prototip BOS, jo MSS i vleresuar nga klienti");
        }
      //--- the selected FVG first (it is never dropped), then the newest others
      int nf=ArraySize(feed.f);
      bool used[];
      ArrayResize(used,nf);
      for(int i=0;i<nf;i++) used[i]=false;
      int shown=0;
      for(int i=0;i<nf;i++)
        {
         if(out.spb.candidate_id=="" || feed.f[i].id!=out.spb.candidate_id) continue;
         DrawM15Zone(feed,i,true,shown,end);
         used[i]=true;
         shown++;
         break;
        }
      for(int pass=0;pass<2;pass++)
        {
         while(shown<EV_MAX_M15_FVG)
           {
            int pick=-1;
            for(int i=0;i<nf;i++)
              {
               if(used[i]) continue;
               if((pass==0) == feed.f[i].invalid) continue;                  // pass 0: not invalid; pass 1: invalid
               if(pick<0 || feed.f[i].confirmed>feed.f[pick].confirmed) pick=i;
              }
            if(pick<0) break;
            used[pick]=true;
            DrawM15Zone(feed,pick,false,shown,end);
            shown++;
            if(pass==1) break;
           }
        }
     }
   void DrawM15Zone(const CEoFeed &feed,const int i,const bool chosen,const int slot,const datetime end)
     {
      string state=(feed.f[i].invalid ? "i pavlefshem" : (chosen ? "ZGJEDHUR nga plani" : (feed.f[i].returned ? "kandidat, cmimi u kthye" : "kandidat")));
      color clr=(chosen ? clrGold : (feed.f[i].invalid ? clrDimGray : clrSilver));
      datetime left=feed.f[i].confirmed-2700;
      Zone(EV_PREFIX+"m15fvg_"+IntegerToString(slot),left,feed.f[i].lower,end,feed.f[i].upper,clr,(chosen ? 3 : 1),(feed.f[i].invalid ? STYLE_DOT : STYLE_SOLID),
           "FVG M15 "+state+" "+EV_Price(feed.f[i].lower,m_digits)+" - "+EV_Price(feed.f[i].upper,m_digits)+" | "+feed.f[i].id);
      Note(EV_PREFIX+"m15fvg_txt"+IntegerToString(slot),left,feed.f[i].lower,"M15 FVG "+state,clr,ANCHOR_LEFT_UPPER,"FVG M15 "+state+" | "+feed.f[i].id);
     }
   //--- the plan: entry, SL, 2R, TP as lines with labels and prices; no arrows
   void DrawPlan(const CEoFeed &feed)
     {
      if(!m_plan.have) return;
      datetime t0=m_plan.t0;
      datetime end=feed.cut+16*900;
      bool buy=(m_plan.direction==1);
      color pc=(buy ? clrDodgerBlue : clrDarkOrange);
      string ds=EV_DirectionText(m_plan.direction);
      Segment(EV_PREFIX+"entry",t0,m_plan.entry,end,m_plan.entry,pc,2,STYLE_SOLID,"Hyrja LIMIT "+ds+" "+EV_Price(m_plan.entry,m_digits)+" (skaji i FVG)");
      Segment(EV_PREFIX+"sl",t0,m_plan.sl,end,m_plan.sl,clrRed,2,STYLE_SOLID,"SL "+EV_Price(m_plan.sl,m_digits)+" (zgjedhje e perkohshme e prototipit)");
      Segment(EV_PREFIX+"tp",t0,m_plan.tp,end,m_plan.tp,clrLimeGreen,2,STYLE_SOLID,"TP "+EV_Price(m_plan.tp,m_digits)+(m_plan.tp_is_2r ? " = 2R" : "")+" (zgjedhje e perkohshme e prototipit)");
      if(!m_plan.tp_is_2r)
         Segment(EV_PREFIX+"r2",t0,m_plan.level_2r,end,m_plan.level_2r,clrLimeGreen,1,STYLE_DOT,"Niveli 2R "+EV_Price(m_plan.level_2r,m_digits));
      Note(EV_PREFIX+"entry_txt",end,m_plan.entry,"HYRJA LIMIT "+ds+" "+EV_Price(m_plan.entry,m_digits),pc,ANCHOR_LEFT,
           "Vol "+DoubleToString(m_plan.volume,2)+" | risku i modeluar "+DoubleToString(m_plan.risk,2)+" | modaliteti: "+(m_plan.real ? "REAL (DEMO)" : "FAKE (virtuale)"));
      Note(EV_PREFIX+"sl_txt",end,m_plan.sl,"SL "+EV_Price(m_plan.sl,m_digits),clrRed,(buy ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER),"Stop loss");
      Note(EV_PREFIX+"tp_txt",end,m_plan.tp,(m_plan.tp_is_2r ? "TP = 2R " : "TP ")+EV_Price(m_plan.tp,m_digits),clrLimeGreen,(buy ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER),"Target");
      if(!m_plan.tp_is_2r)
         Note(EV_PREFIX+"r2_txt",end,m_plan.level_2r,"2R "+EV_Price(m_plan.level_2r,m_digits),clrLimeGreen,(buy ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER),"Niveli 2R");
     }
   //--- the legend (bottom left) and the panel (top left): boxes with a background, laid out for the space the chart has; the legend first, the panel takes the rest of the height.
   //--- The panel rows are SHORT; the full sentences, ids and the temporary choices are in the tooltips of the rows.
   void DrawPanels(const SEoOutcome &out,const CEoFeed &feed,const bool real_entry,const bool mgmt_read_only)
     {
      int chart_h=(m_test_h>0 ? m_test_h : (int)ChartGetInteger(m_chart,CHART_HEIGHT_IN_PIXELS,0));
      int lh=m_legend.LineHeight();
      color grey=C'170,170,170';
      m_legend.Begin();
      m_legend.Line("LEGJEND~E",clrSilver,0,SW_NONE,"Cdo shenje ka nje etikete te shkurter; forma e vijes dhe e kutise e ndan kuptimin, jo vetem ngjyra.");
      m_legend.Line("H4",grey,1,SW_H4,"FVG H4: kuti blu (setup ngrit~es) ose portokalli (setup zbrit~es). Vije e plote = rikonfirmuar, e ndrydhur = kandidat, me pika = i pavlefshem.");
      m_legend.Line("FVG M15",grey,2,SW_M15,"FVG M15 kandidat (gri). Me pika = i pavlefshem. Kufiri i trashe ari = FVG e zgjedhur nga plani.");
      m_legend.Line("FVG e zgjedhur",grey,3,SW_GOLD,"Ari i takon vetem FVG-se qe zgjodhi ura e planit (spb.candidate_id).");
      m_legend.Line("Sweep",grey,4,SW_SWEEP,"Vije e ndrydhur + pike: niveli i sweep-it H4 dhe qiriu ku ndodhi (Sweep H4 ose Fitil H4).");
      m_legend.Line("Thyerje M15",grey,5,SW_BREAK,"Vije + pike: qiriu qe konfirmoi thyerjen e nivelit M15. Prototip BOS, jo MSS i vleresuar nga klienti.");
      m_legend.Line("E | SL | 2R | TP",grey,6,SW_PLAN,"Vija te etiketuara drejtperdrejt ne grafik me cmim: hyrja LIMIT (E), SL, 2R, TP. Kur TP = 2R eshte nje vije.");
      int leg_rows=(int)MathMax(2.0,MathMin(7.0,(double)((chart_h/3)/lh)));
      int leg_px=m_legend.Render(leg_rows,0,true);
      int main_rows=(int)MathMax(4.0,(double)((chart_h-leg_px-40)/lh));
      m_panel.Begin();
      //--- priority 0 never leaves: the mode and the decision; larger numbers leave first when the chart is small
      bool real_mode=(real_entry || !mgmt_read_only);
      if(real_mode) m_panel.Line("ATENCION ~b REAL (DEMO) ~b URDHRA REAL~E",clrRed,0,SW_NONE,"Eshte zgjedhur transport real: ky NUK eshte simulimi FAKE/READ_ONLY.");
      else m_panel.Line("SIMULIM ~b PA URDHRA REAL~E",clrOrange,0,SW_NONE,"FAKE / READ_ONLY: asnje porosi reale nuk dergohet te brokeri.");
      //--- H4
      int h4dir=(feed.dv_have ? feed.dv_ev.st.dir : H3_NONE);
      color dcol=(h4dir==H3_BULL ? clrDodgerBlue : (h4dir==H3_BEAR ? clrDarkOrange : clrWhite));
      if(feed.dv_have)
        {
         bool has_setup=(feed.dv_ev.st.dir!=H3_NONE && feed.dv_ev.st.setup_id!="");
         string h4tip=EV_H4DirectionText(h4dir)+". "+EV_H4PhaseText(feed.dv_ev.st.phase,has_setup)+(feed.dv_ev.reliable ? "" : ". Historia H4 nuk konvergon ("+feed.dv_ev.reason+")");
         m_panel.Line("H4: "+EV_DirWord(h4dir)+" | "+EV_H4Short(feed.dv_ev.st.phase,has_setup,feed.dv_ev.reliable),(feed.dv_ev.st.phase==H3_PH_RECONFIRMED ? clrLimeGreen : clrWhite),1,
                      (h4dir==H3_BEAR ? SW_ARROW_DOWN : (h4dir==H3_BULL ? SW_ARROW_UP : SW_NONE)),h4tip,dcol);
        }
      else m_panel.Line("H4: pa vler~esim",grey,1,SW_NONE,"Nuk ka vleresim T003 per kete grafik (feed jo gati ose burimi nuk eshte T003).");
      //--- M15: a short state; what is confirmed and what is missing is in the tooltip
      string done="",missing="";
      if(feed.st.has_context) done+="H4";
      else missing+="H4 rikonfirmim";
      if(feed.st.has_context && feed.st.bos_time>0)
         done+=(done=="" ? "" : "; ")+"thyerje M15 "+StringSubstr(EV_Hm(feed.st.bos_time),11)+(feed.broken.valid && feed.broken.id==feed.st.bos_level ? " @"+EV_Price(feed.broken.price,m_digits) : "");
      else missing+=(missing=="" ? "" : "; ")+"thyerje M15";
      int nvalid=0;
      bool returned=false;
      for(int i=0;i<ArraySize(feed.f);i++)
        {
         if(feed.f[i].invalid) continue;
         nvalid++;
         if(feed.f[i].returned) returned=true;
        }
      if(feed.st.has_context && feed.st.bos_time>0 && nvalid>0) done+=(done=="" ? "" : "; ")+"FVG M15 x"+IntegerToString(nvalid)+(out.spb.candidate_id!="" ? " (zgjedhur)" : "");
      else missing+=(missing=="" ? "" : "; ")+"FVG M15";
      if(returned) done+=(done=="" ? "" : "; ")+"kthim n~e FVG";
      else missing+=(missing=="" ? "" : "; ")+"kthim n~e FVG";
      m_panel.Line("M15: "+EV_M15Short(feed.st.phase,feed.st.has_context),(feed.st.has_context ? clrWhite : grey),1,SW_NONE,
                   "Konfirmuar: "+(done=="" ? "asgje" : done)+". Mungon: "+(missing=="" ? "asgje" : missing)+".");
      //--- the plan, when one exists: short rows
      if(m_plan.have)
        {
         string mode=(m_plan.real ? "REAL (DEMO)" : "FAKE (virtuale)");
         color pcol=(m_plan.direction==1 ? clrDodgerBlue : clrDarkOrange);
         string ptip="modaliteti: "+mode+" | sinjali "+m_plan.signal_id+(out.risk_label!="" ? " | "+out.risk_label+" 1%" : "")+". Hyrja = konfirmuar; SL, TP/2R, risku = prototip.";
         m_panel.Line("PLAN "+EV_DirectionText(m_plan.direction)+" LIMIT | E "+EV_Price(m_plan.entry,m_digits),pcol,1,SW_NONE,ptip);
         m_panel.Line("SL "+EV_Price(m_plan.sl,m_digits)+" | "+(m_plan.tp_is_2r ? "TP = 2R " : "2R "+EV_Price(m_plan.level_2r,m_digits)+" | TP ")+EV_Price(m_plan.tp,m_digits),pcol,1,SW_NONE,ptip);
         m_panel.Line("Lot "+DoubleToString(m_plan.volume,2)+" | Risk "+DoubleToString(m_plan.risk,2),grey,2,SW_NONE,ptip);
        }
      //--- the decision
      string label,reason;
      EV_Verdict(out,m_plan,real_entry,label,reason);
      string tiny="";
      if(label=="BLLOKUAR" || (label=="PRET" && out.status!="NO_PLAN" && out.status!="ALREADY_HANDLED"))
        {
         if(out.status=="GATE_BLOCKED") tiny=EV_ReasonTiny(EV_FirstReason(out.dec.reasons));
         else if(out.status=="NO_PLAN") tiny=EV_ReasonTiny(out.reason);
         else if(out.status=="FEED_NOT_OK") tiny="feed";
         else if(out.status=="MARKET_NOT_READY") tiny="kuota";
         else if(out.status=="RISK_BASE_NOT_READY") tiny="balanca";
         else if(out.status=="HALTED") tiny="mbrojtje";
         else if(out.status=="CONFIG_UNSET" || out.status=="SIMULATION_REFUSED") tiny="konfigurim";
         else if(out.status=="PROBE_FAILED") tiny="matja e humbjes";
         else if(out.status=="RESERVATION_FAILED") tiny="rezervim";
        }
      m_panel.Line("Vendimi: "+label+(tiny!="" ? " | "+tiny : ""),EV_VerdictColor(label),0,SW_NONE,reason+" [kodi: "+out.status+" "+EV_Clip(out.reason,60)+"]");
      m_panel.Line("Prototip ~m jo i validuar",grey,3,SW_NONE,"Konfirmuar: hyrja LIMIT, seanca, lajmet, limitet. Prototip: burimi H4, niveli M15, FVG, SL, TP/2R, risku 1%.");
      m_panel.Render(main_rows,16,false);
     }

public:
   CEoView(void)
     {
      m_on=false;
      m_chart=0;
      m_digits=2;
      m_signature="";
      m_n_objects=0;
      m_test_h=0;
      EV_PlanInit(m_plan);
     }
   //--- MT5 test only: simulate a chart of this size for the boxes (0, 0 = the real chart)
   void TestSize(const int w,const int h) {m_test_h=h; m_panel.TestSize(w,h); m_legend.TestSize(w,h);}
   int  MarkCount(void) const {return(m_n_objects);}
   int  TipMax(void) const {return(m_panel.TipMax());}
   void Init(void)
     {
      m_on=true;
      m_chart=ChartID();
      m_digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
      m_panel.Init(EV_PANEL_PREFIX+"main_",9,12);
      m_legend.Init(EV_PANEL_PREFIX+"leg_",8,38);
      ObjectsDeleteAll(m_chart,EV_PREFIX);                      // this component's own prefix only
     }
   //--- called by the EA after the decision step; reads only
   void Update(const SEoOutcome &out,const CEoFeed &feed,const bool real_entry,const bool mgmt_read_only)
     {
      if(!m_on) return;
      TrackPlan(out,feed,real_entry);
      string sig=out.status+"|"+out.reason+"|"+EV_Hm(feed.cut)+"|"+feed.st.phase+"|"+out.spb.candidate_id+"|"+
                 (m_plan.have ? IntegerToString(m_plan.direction)+","+EV_Px(m_plan.entry)+","+EV_Px(m_plan.sl)+","+EV_Px(m_plan.tp)+","+EV_Px(m_plan.level_2r)+","+(m_plan.tp_is_2r ? "1" : "0")+","+m_plan.signal_id : "-")+"|"+
                 EV_FeedSig(feed);
      if(sig!=m_signature)
        {
         m_signature=sig;
         ClearObjects();
         DrawH4(feed);
         DrawM15(out,feed);
         DrawPlan(feed);
        }
      DrawPanels(out,feed,real_entry,mgmt_read_only);
      ChartRedraw(m_chart);
     }
   void Destroy(void)
     {
      if(!m_on) return;
      m_panel.Destroy();
      m_legend.Destroy();
      ObjectsDeleteAll(m_chart,EV_PREFIX);
      ChartRedraw(m_chart);
      m_on=false;
     }
  };
#endif
