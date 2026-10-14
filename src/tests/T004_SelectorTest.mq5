// Synthetic proposal tests. Not client strategy validation. No series or trading API.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/M15SwingProposal.mqh"

int g_pass=0,g_fail=0;
datetime START=14400;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }

void Fixture(MqlRates &b[],const int d=1)
  {
   double h[]={96,98,100,97,96,101,107,110,109};
   double l[]={90,91,92,90,89,95,100,103,102};
   double c[]={93,94,95,93,92,100.5,105,108,104};
   ArrayResize(b,9);
   for(int i=0;i<9;i++)
     {
      ZeroMemory(b[i]);
      b[i].time=START+i*M4_PERIOD;
      b[i].high=(d>0 ? h[i] : 200-l[i]);
      b[i].low=(d>0 ? l[i] : 200-h[i]);
      b[i].close=(d>0 ? c[i] : 200-c[i]);
      b[i].open=b[i].close;
     }
  }

void Context(SM4Context &c,const int d)
  {
   M4ContextInit(c);
   c.setup="S1"; c.direction=d; c.source="EXPLICIT_PROPOSAL";
   c.fvg="H4F1"; c.lower=80; c.upper=120;
   c.confirmed=START; c.valid_from=START+4500;
   c.ready=true; c.reliable=true; c.selected=true;
  }

void TestSelector()
  {
   MqlRates b[];
   Fixture(b);
   SM4Selection s;
   M4SelectSwingProposal(b,5,1,s);
   Check(s.status=="DISABLED" && !s.level.valid,"selector defaults to disabled");
   M4SelectSwingProposal(b,5,1,s,true);
   Check(s.status=="SELECTED" && s.level.price==100,"BUY selects known high 100");
   Check(s.pivot==START+1800 && s.level.known==START+4500,"pivot and confirm use absolute times");
   Check(s.window_start==START && s.used==5,"coverage is reported");
   string id=s.level.id;
   M4SelectSwingProposal(b,4,1,s,true);
   Check(s.status=="SHORT_HISTORY" && !s.level.valid,"unconfirmed swing is unavailable");
   M4SelectSwingProposal(b,6,1,s,true);
   Check(s.status=="NO_LEVEL" && !s.level.valid,"prior body break consumes high");
   b[5].close=99;
   M4SelectSwingProposal(b,6,1,s,true);
   Check(s.status=="SELECTED" && s.level.price==100,"prior wick does not consume high");
   b[5].close=100;
   M4SelectSwingProposal(b,6,1,s,true);
   Check(s.status=="SELECTED","equal close does not consume high");
   M4SelectSwingProposal(b,6,1,s,true,2,2,5);
   Check(s.status=="NO_LEVEL" && s.window_start==START+900 && s.used==5,"shorter window cannot recover uncovered left neighbors");
   Fixture(b);
   b[1].high=100;
   M4SelectSwingProposal(b,5,1,s,true);
   Check(s.status=="NO_LEVEL","tied high is not strict swing");
   Fixture(b);
   b[2].low=80;
   M4SelectSwingProposal(b,5,1,s,true);
   Check(s.status=="NO_LEVEL" && s.ambiguous==1,"ambiguous high and low excluded");
   Fixture(b);
   for(int i=3;i<9;i++) b[i].time+=900;
   M4SelectSwingProposal(b,5,1,s,true);
   Check(s.status=="SHORT_HISTORY","gap cannot supply missing right neighbors");
   Fixture(b);
   b[3].time=b[2].time;
   M4SelectSwingProposal(b,5,1,s,true);
   Check(s.status=="INVALID_INPUT","duplicate history timestamps rejected before gap trim");
   Fixture(b);
   b[3].close=200;
   M4SelectSwingProposal(b,5,1,s,true);
   Check(s.status=="INVALID_INPUT","malformed HLC rejected");
   Fixture(b);
   b[5].high=0; b[5].low=1; b[5].close=200;
   M4SelectSwingProposal(b,5,1,s,true);
   Check(s.status=="SELECTED" && s.level.id==id,"future malformed bar excluded from prefix");
   M4SelectSwingProposal(b,5,0,s,true);
   Check(s.status=="INVALID_INPUT","unknown direction cannot choose a level");
   M4SelectSwingProposal(b,10,1,s,true);
   Check(s.status=="INVALID_INPUT","prefix beyond array rejected");
   M4SelectSwingProposal(b,5,1,s,true,0,2,300);
   Check(s.status=="INVALID_INPUT","invalid Left rejected");
   M4SelectSwingProposal(b,5,1,s,true,2,11,300);
   Check(s.status=="INVALID_INPUT","invalid Right rejected");
   M4SelectSwingProposal(b,5,1,s,true,2,2,4);
   Check(s.status=="INVALID_INPUT","undersized lookback rejected");
   M4SelectSwingProposal(b,5,1,s,true,2,2,1001);
   Check(s.status=="INVALID_INPUT","excessive lookback rejected");
   Fixture(b,-1);
   M4SelectSwingProposal(b,5,-1,s,true);
   Check(s.status=="SELECTED" && s.level.price==100 && s.level.known==START+4500,"SELL mirrored confirmed low");
  }

void TestFallbackAndIdentity()
  {
   double h[]={104,106,110,105,104,95,96,100,97,96,104};
   double l[]={95,96,97,94,93,90,91,92,90,89,97};
   double c[]={100,101,102,99,98,93,94,95,93,92,103};
   MqlRates b[];
   ArrayResize(b,11);
   for(int i=0;i<11;i++)
     {
      ZeroMemory(b[i]); b[i].time=START+i*900;
      b[i].high=h[i]; b[i].low=l[i]; b[i].close=c[i]; b[i].open=c[i];
     }
   SM4Selection s;
   M4SelectSwingProposal(b,10,1,s,true);
   Check(s.status=="SELECTED" && s.level.price==100,"latest pivot chosen instead of highest price");
   M4SelectSwingProposal(b,11,1,s,true);
   Check(s.status=="SELECTED" && s.level.price==110,"older unbroken high can remain after newer consumed");
   Fixture(b);
   M4SelectSwingProposal(b,5,1,s,true);
   string id=s.level.id;
   datetime known=s.level.known;
   MqlRates prior[];
   ArrayResize(prior,11);
   for(int i=0;i<2;i++)
     {
      ZeroMemory(prior[i]); prior[i].time=START-1800+i*900;
      prior[i].high=94+i; prior[i].low=88+i; prior[i].close=90+i; prior[i].open=prior[i].close;
     }
   for(int i=0;i<9;i++) prior[i+2]=b[i];
   M4SelectSwingProposal(prior,7,1,s,true);
   Check(s.status=="SELECTED" && s.level.id==id && s.level.known==known,"window index shift preserves absolute level identity");
   Fixture(b);
   b[5].high=95; b[5].low=88; b[5].close=90;
   M4SelectSwingProposal(b,5,1,s,true,1,3,300);
   Check(s.status=="NO_LEVEL","asymmetric Right three has not yet confirmed the pivot");
   M4SelectSwingProposal(b,6,1,s,true,1,3,300);
   Check(s.status=="SELECTED" && s.level.price==100 && s.level.known==START+5400,
         "asymmetric Left one Right three confirms at actual right bar close");
   Fixture(b);
   ArrayResize(prior,10);
   for(int i=0;i<5;i++)
     {
      prior[i]=b[i]; prior[i+5]=b[i]; prior[i+5].time+=9000;
     }
   M4SelectSwingProposal(prior,9,1,s,true);
   Check(s.status=="SHORT_HISTORY","new segment after gap needs its own neighbors");
   M4SelectSwingProposal(prior,10,1,s,true);
   Check(s.status=="SELECTED" && s.window_start==START+9000 && s.used==5 && s.pivot==START+10800,
         "gap recovery selects only a newly confirmed post-gap swing");
  }

void TestFullFlow(const int d)
  {
   MqlRates b[];
   Fixture(b,d);
   SM4State state;
   SM4Candidate f[];
   SM4Event e[];
   M4Init(state,f,e,M4_A_AT_OR_AFTER_BREAK);
   SM4Context ctx;
   Context(ctx,d);
   M4SetContext(ctx,START+4500,state,f,e);
   SM4Selection s;
   for(int i=5;i<9;i++)
     {
      M4SelectSwingProposal(b,i,d,s,true);
      M4Step(b[i],b[i].time+900,s.level,state,f,e);
     }
   Check(state.phase=="RETURN_OBSERVED","selector to BOS to FVG to return path");
   Check(ArraySize(e)==4 && e[0].type=="CONTEXT_OPEN" && e[1].type=="BOS_CANDIDATE" &&
         e[2].type=="FVG_CANDIDATE" && e[3].type=="RETURN_OBSERVED","full path event sequence without entry permission");
   Check(e[1].known==START+5400 && e[2].known==START+7200 && e[3].known==START+8100,
         "full path respects confirmation closes");
   M4Init(state,f,e,M4_A_AT_OR_AFTER_BREAK);
   ctx.valid_from=START+5400;
   M4SetContext(ctx,START+5400,state,f,e);
   M4SelectSwingProposal(b,6,d,s,true);
   M4Step(b[6],b[6].time+900,s.level,state,f,e);
   Check(state.phase=="WAIT_BREAK","already broken pre-context level cannot infer new BOS");
  }

void OnStart()
  {
   Print("T004 experimental swing proposal tests: synthetic only, no trading.");
   TestSelector(); TestFallbackAndIdentity(); TestFullFlow(1); TestFullFlow(-1);
   PrintFormat("T004 SELECTOR TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
