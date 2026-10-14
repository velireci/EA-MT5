#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/M15Timeline.mqh"
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
      ZeroMemory(b[i]); b[i].time=START+i*900;
      b[i].high=(d>0 ? h[i] : 200-l[i]); b[i].low=(d>0 ? l[i] : 200-h[i]);
      b[i].close=(d>0 ? c[i] : 200-c[i]); b[i].open=b[i].close;
     }
  }
void Update(SM4ContextUpdate &u,const datetime known,const int d=1,const bool ready=true)
  {
   u.known=known; M4ContextInit(u.context);
   u.context.setup="S1"; u.context.direction=d; u.context.source="EXPLICIT_PROPOSAL";
   u.context.fvg="H4F1";u.context.lower=80;u.context.upper=120;
   u.context.confirmed=START;u.context.valid_from=START;
   u.context.ready=ready;u.context.reliable=true;u.context.selected=true;
  }
int Count(const SM4Event &e[],const string type)
  {
   int n=0;for(int i=0;i<ArraySize(e);i++) if(e[i].type==type) n++;
   return(n);
  }
void Run(const MqlRates &b[],const int n,const SM4ContextUpdate &u[],const int nu,const datetime cut,
          SM4State &s,SM4Candidate &f[],SM4Event &e[],SM4TimelineInfo &info,
          const bool selector=true,const int policy=M4_A_AT_OR_AFTER_BREAK)
  {
   M4ReplayTimeline(b,n,u,nu,START+4500,cut,selector,policy,2,2,300,s,f,e,info);
  }
void OnStart()
  {
   Check(M4TimelineNeedsBuild(false,true,START,START,true,false),"live H4 update at same M15 cut rebuilds");
   Check(!M4TimelineNeedsBuild(false,true,START,START,false,false),"unchanged live boundary does not replay again");
   Check(!M4TimelineNeedsBuild(true,true,START,START,true,true),"historical fixed cut stays static");
   Check(M4TimelineNeedsBuild(true,false,START,START,false,false),"clear or first load rebuilds historical view");
   MqlRates b[];
   SM4ContextUpdate u[];
   SM4State s;
   SM4Candidate f[];
   SM4Event e[];
   SM4TimelineInfo info;
   ArrayResize(u,2);
   for(int d=-1;d<=1;d+=2)
     {
      Fixture(b,d);Update(u[0],START,d);
      Run(b,9,u,1,START+8100,s,f,e,info);
      Check(info.status=="OK" && info.processed==4 && s.phase=="RETURN_OBSERVED","causal H4 to M15 full path both directions");
      Check(info.bos_price==100,"broken level retained separately from latest selection");
      Check(ArraySize(e)==4 && e[0].known==START+4500,"truncated replay starts observing context at replay start");
     }
   Fixture(b);Update(u[0],START+5400);
   u[0].context.valid_from=START+5400;
   Run(b,9,u,1,START+8100,s,f,e,info);
   Check(s.phase=="WAIT_BREAK" && Count(e,"BOS_CANDIDATE")==0,"H4 becoming ready excludes M15 bar inside touching H4");
   Update(u[0],START);Update(u[1],START+8100,1,false);
   Run(b,9,u,2,START+8100,s,f,e,info);
   Check(s.phase=="WAIT_CONTEXT" && Count(e,"RETURN_OBSERVED")==0,"H4 revocation wins at same close as potential return");
   Run(b,8,u,2,START+8100,s,f,e,info);
   Check(s.phase=="WAIT_CONTEXT","later H4 update applied without an M15 bar at that time");
   Update(u[0],START+7200);u[0].context.valid_from=START+7200;
   Run(b,9,u,1,START+8100,s,f,e,info);
   Check(s.phase=="WAIT_BREAK" && Count(e,"BOS_CANDIDATE")==0,"final H4 state cannot authorise earlier M15 break");
   Update(u[0],START);u[0].context.selected=false;
   Run(b,9,u,1,START+8100,s,f,e,info);
   Check(Count(e,"BOS_CANDIDATE")==0,"unselected H4 source blocks timeline");
   Update(u[0],START);
   Run(b,9,u,1,START+8100,s,f,e,info,false);
   Check(Count(e,"BOS_CANDIDATE")==0,"unselected level proposal blocks timeline");
   Run(b,9,u,1,START+8100,s,f,e,info,true,M4_POLICY_UNSET);
   Check(Count(e,"BOS_CANDIDATE")==0,"unselected timing blocks timeline");
   Update(u[1],START+9000,1,false);
   Run(b,9,u,2,START+7199,s,f,e,info);
   Check(s.phase=="WAIT_FVG" && info.processed==2,"future H4 update and unclosed M15 C excluded");
   Update(u[0],START+900);Update(u[1],START);
   Run(b,9,u,2,START+8100,s,f,e,info);
   Check(info.status=="INVALID_UPDATES" && ArraySize(e)==0,"invalid context chronology yields no partial observations");
   PrintFormat("T004 TIMELINE TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
