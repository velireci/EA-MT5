// Controlled synthetic tests. No market data, files, series or trading API.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/H4M15Bridge.mqh"

int g_pass=0,g_fail=0;
datetime START=14400;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }

SM4Context Context(const int direction=-1)
  {
   SM4Context c;
   M4ContextInit(c);
   c.setup="S1"; c.direction=direction; c.source="EXPLICIT_PROPOSAL";
   c.fvg="H4F1"; c.lower=80; c.upper=120;
   c.confirmed=START; c.valid_from=START;
   c.ready=true; c.reliable=true; c.selected=true;
   return(c);
  }

MqlRates Bar(const int i,const double high,const double low,const double close)
  {
   MqlRates b;
   ZeroMemory(b);
   b.time=START+i*M4_PERIOD; b.open=close; b.high=high; b.low=low; b.close=close;
   return(b);
  }

SM4Level Level(const string id="L",const double price=98,const datetime known=14400)
  {
   SM4Level l;
   l.valid=true; l.id=id; l.price=price; l.known=known;
   return(l);
  }

void New(SM4State &s,SM4Candidate &f[],SM4Event &e[],const int d=-1,const int policy=M4_A_AT_OR_AFTER_BREAK)
  {
   M4Init(s,f,e,policy);
   SM4Context c=Context(d);
   M4SetContext(c,START,s,f,e);
  }

string Push(const int i,const double h,const double l,const double c,SM4State &s,
              SM4Candidate &f[],SM4Event &e[],const bool supplied=false,const double price=98,
              const datetime known=14400)
  {
   MqlRates b=Bar(i,h,l,c);
   SM4Level lv=Level("L",price,known);
   lv.valid=supplied;
   return(M4Step(b,b.time+M4_PERIOD,lv,s,f,e));
  }

void Sell(SM4State &s,SM4Candidate &f[],SM4Event &e[])
  {
   New(s,f,e);
   Push(0,101,95,96,s,f,e,true);
   Push(1,96,89,90,s,f,e);
   Push(2,93,87,88,s,f,e);
  }

int Count(const SM4Event &e[],const string type)
  {
   int n=0;
   for(int i=0;i<ArraySize(e);i++) if(e[i].type==type) n++;
   return(n);
  }

void TestBoundaries()
  {
   SM4State s;
   SM4Candidate f[];
   SM4Event e[];
   New(s,f,e);
   Check(s.phase=="WAIT_BREAK","ready context activates at H4 close");
   MqlRates b=Bar(-1,101,95,96);
   SM4Level lv=Level();
   Check(M4Step(b,START,lv,s,f,e)=="BEFORE_CONTEXT","M15 ending at H4 close is excluded");
   b=Bar(0,101,95,96);
   Check(M4Step(b,START+899,lv,s,f,e)=="NOT_CLOSED" && !s.has_last,"forming bar does not advance");
   Check(M4Step(b,START+900,lv,s,f,e)=="PROCESSED" && s.phase=="WAIT_FVG","bar opening at H4 close works after own close");
   New(s,f,e,-1,M4_POLICY_UNSET);
   Push(0,101,95,96,s,f,e,true);
   Check(s.phase=="WAIT_POLICY" && Count(e,"BOS_CANDIDATE")==0,"unset policy blocks BOS pipeline");
   New(s,f,e);
   Push(0,101,95,96,s,f,e);
   Check(s.phase=="WAIT_BREAK","no external level means no inferred BOS");
   Push(1,101,95,96,s,f,e,true,98,START+1800);
   Check(s.phase=="WAIT_BREAK","level confirmed by crossing bar is too late");
   New(s,f,e);
   Push(0,101,95,99,s,f,e,true);
   Push(1,100,95,98,s,f,e,true);
   Check(s.phase=="WAIT_BREAK","wick and equal close are not body break");
   Push(2,99,95,97,s,f,e,true);
   Check(s.phase=="WAIT_FVG" && Count(e,"BOS_CANDIDATE")==1,"strict close records one BOS candidate");
  }

void TestFvg()
  {
   SM4State s;
   SM4Candidate f[];
   SM4Event e[];
   Sell(s,f,e);
   Check(s.phase=="WAIT_RETURN" && ArraySize(f)==1,"SELL three closed bars form one candidate");
   Check(ArraySize(f)>0 && f[0].lower==93 && f[0].upper==95,"SELL gap bounds are hand-derived 93 to 95");
   Check(Count(e,"RETURN_OBSERVED")==0,"candle C cannot count as its own return");
   Check(ArraySize(e)==3 && e[1].known==START+900 && e[2].known==START+2700,"events become known only at their closes");
   Push(3,94,86,90,s,f,e);
   Check(s.phase=="RETURN_OBSERVED","next bar wick overlap records a return fact");
   Push(4,94,86,90,s,f,e);
   Check(Count(e,"RETURN_OBSERVED")==1,"repeat overlaps do not re-emit the same return");
   Sell(s,f,e);
   Push(3,97,90,96,s,f,e);
   Check(s.phase=="WAIT_FVG" && Count(e,"RETURN_OBSERVED")==0 && Count(e,"FVG_INVALIDATED")==1,
         "close beyond far edge invalidates before wick touch");
   New(s,f,e,1);
   Push(0,105,99,104,s,f,e,true,102);
   Push(1,111,104,110,s,f,e);
   Push(2,113,107,112,s,f,e);
   Check(ArraySize(f)==1 && f[0].lower==105 && f[0].upper==107,"BUY mirrored gap bounds 105 to 107");
   Push(3,114,106,110,s,f,e);
   Check(s.phase=="RETURN_OBSERVED","BUY mirrored return fact");
   New(s,f,e);
   Push(0,101,95,96,s,f,e);
   Push(1,96,89,90,s,f,e);
   Push(2,93,87,88,s,f,e,true,89);
   Check(s.phase=="WAIT_FVG" && ArraySize(f)==0,"FVG whose A preceded BOS is not eligible");
   Sell(s,f,e);
   Push(3,88,84,85,s,f,e);
   Check(ArraySize(f)==2 && f[1].lower==88 && f[1].upper==89,"second candidate is retained without selecting an entry");
   Push(4,94,86,88,s,f,e);
   Check(Count(e,"RETURN_OBSERVED")==2,"one bar can report returns to both distinct FVG candidates");
   Sell(s,f,e);
   Push(3,96,90,95,s,f,e);
   Check(s.phase=="RETURN_OBSERVED" && !f[0].invalid,"close exactly at far edge is not invalidation");
   New(s,f,e,1);
   Push(0,105,99,104,s,f,e,true,102);
   Push(1,111,104,110,s,f,e);
   Push(2,113,107,112,s,f,e);
   Push(3,110,103,104,s,f,e);
   Check(s.phase=="WAIT_FVG" && Count(e,"RETURN_OBSERVED")==0,"BUY invalidation also wins over touch");
  }

void TestLifecycle()
  {
   SM4State s;
   SM4Candidate f[];
   SM4Event e[];
   Sell(s,f,e);
   MqlRates b=Bar(2,93,87,88);
   SM4Level lv;
   M4NoLevel(lv);
   int n=ArraySize(e);
   Check(M4Step(b,START+2700,lv,s,f,e)=="DUPLICATE" && ArraySize(e)==n,"same closed bar is idempotent");
   b.high=94;
   Check(M4Step(b,START+2700,lv,s,f,e)=="REPLAY_REQUIRED" && ArraySize(f)==0,"changed last HLC discards stale candidates");
   SM4Context c=Context();
   M4SetContext(c,START+2700,s,f,e);
   Check(s.phase=="REPLAY_REQUIRED","same context cannot heal revised data");
   Sell(s,f,e);
   b=Bar(1,96,89,90);
   Check(M4Step(b,START+3600,lv,s,f,e)=="REPLAY_REQUIRED","out of order requires full replay");
   Sell(s,f,e);
   Check(Push(4,94,86,90,s,f,e,true)=="DATA_GAP" && s.phase=="WAIT_BREAK" && ArraySize(f)==0,
         "gap resets M15 progress and skips BOS on gap bar");
   New(s,f,e);
   Check(Push(0,90,95,96,s,f,e)=="INVALID_BAR" && !s.has_last,"invalid HLC cannot advance");
   Sell(s,f,e);
   c=Context();
   M4SetContext(c,START+2700,s,f,e);
   Check(s.phase=="WAIT_RETURN","unchanged context keeps M15 progress");
   c.fvg="H4F2"; c.valid_from=START+2700;
   M4SetContext(c,START+2700,s,f,e);
   Check(s.phase=="WAIT_BREAK" && ArraySize(f)==0,"changed H4 FVG resets the epoch");
   c.reliable=false;
   M4SetContext(c,START+2700,s,f,e);
   Check(s.phase=="WAIT_CONTEXT" && !s.has_context,"lost H4 reliability revokes M15 context");
   New(s,f,e);
   c=Context(); c.source="";
   M4SetContext(c,START,s,f,e);
   Check(!s.has_context,"empty direction source cannot activate");
   c=Context(); c.confirmed=START+900;
   M4SetContext(c,START,s,f,e);
   Check(!s.has_context,"future H4 confirmation cannot activate");
   c=Context(); c.selected=false;
   M4SetContext(c,START,s,f,e);
   Check(!s.has_context,"unselected direction source cannot activate");
   for(int i=1;i<=2;i++)
     {
      Sell(s,f,e);
      b=Bar(i,86,87,88);
      Check(M4Step(b,START+2700,lv,s,f,e)=="REPLAY_REQUIRED" && ArraySize(f)==0,
            "malformed revision of consumed bar clears stale progress");
      Check(Push(3,94,86,90,s,f,e)=="REPLAY_REQUIRED" && Count(e,"RETURN_OBSERVED")==0,
            "later valid bar cannot use candidates after malformed revision");
     }
   Sell(s,f,e);
   b=Bar(2,86,87,88);
   M4Step(b,START+3600,lv,s,f,e);
   c=Context(); c.setup="S2";
   M4SetContext(c,START+2700,s,f,e);
   Check(s.phase=="REPLAY_REQUIRED" && s.last_asof==START+3600,
         "revision observation clock cannot be bypassed by an older replacement context");
  }

void TestBridge()
  {
   SH3SetupCtx h;
   ZeroMemory(h);
   h.valid=true; h.ready=true; h.phase="RECONFIRMED";
   h.setup_id="SWEEP1"; h.direction="BEAR"; h.fvg_id="H4F1";
   h.fvg_lower=80; h.fvg_upper=120; h.fvg_conf=START; h.valid_from=START;
   SM4Context c;
   Check(!M4ContextFromH3(h,true,c),"adapter defaults to unselected prototype source");
   Check(M4ContextFromH3(h,true,c,true) && c.direction==-1 && c.source=="T003_PROTOTYPE",
         "explicit source selection adapts ready SELL context");
   h.direction="BULL";
   Check(M4ContextFromH3(h,true,c,true) && c.direction==1,"adapter maps BUY explicitly");
   Check(!M4ContextFromH3(h,false,c,true),"adapter rejects unreliable evaluation");
   h.phase="SWEEP_WAIT";
   Check(!M4ContextFromH3(h,true,c,true),"sweep alone cannot start M15");
   h.phase="RECONFIRMED"; h.fvg_id="";
   Check(!M4ContextFromH3(h,true,c,true),"missing recorded H4 FVG blocks adapter");
   SH3State hs;
   H3StateInit(hs);
   hs.dir=H3_BEAR; hs.phase=H3_PH_RECONFIRMED;
   hs.setup_id="REAL_CONTEXT_API"; hs.setup_type="SWEEP";
   hs.rec_id="H4REC"; hs.rec_from=START+3600; hs.wait_start=START;
   SH3Track tracks[];
   ArrayResize(tracks,1);
   tracks[0].recorded=true; tracks[0].invalid=false; tracks[0].id="H4REC";
   tracks[0].lower=80; tracks[0].upper=120; tracks[0].conf=START;
   H3SetupContext(hs,tracks,1,h);
   Check(M4ContextFromH3(h,true,c,true) && c.valid_from==START+3600,
         "real T003 context API preserves touching-close valid_from");
   SM4State s;
   SM4Candidate f[];
   SM4Event e[];
   M4Init(s,f,e,M4_A_AT_OR_AFTER_BREAK);
   M4SetContext(c,START+3600,s,f,e);
   MqlRates b=Bar(3,101,95,96);
   SM4Level lv=Level();
   Check(M4Step(b,START+3600,lv,s,f,e)=="BEFORE_CONTEXT",
         "T003 reconfirmation does not retroactively allow the last M15 bar inside H4");
   b=Bar(4,101,95,96);
   Check(M4Step(b,START+4500,lv,s,f,e)=="PROCESSED" && s.phase=="WAIT_FVG",
         "T003 bridge starts only with M15 opening at touching close");
  }

void OnStart()
  {
   Print("T004 M15 observer tests: synthetic PROPOSALS, no trading, no series API.");
   TestBoundaries(); TestFvg(); TestLifecycle(); TestBridge();
   PrintFormat("T004 LOGIC TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
