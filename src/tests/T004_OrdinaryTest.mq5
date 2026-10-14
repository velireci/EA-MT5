// T004 round 4 test script: ordinary H4 FVG-touch source. Mirrors tests/test_t004_ordinary.py.
// Expectations are hand-derived (see tests/t004_ordinary_fixtures.py). NOT YET COMPILED OR RUN in MT5.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/H4TouchContext.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
// BEGIN GENERATED FIXTURES (tests/t004_ordinary_fixtures.py emit_mql)
datetime T0=1767571200;
double BASE_H[]={2093.0,2097.0,2101.0,2105.0,2101.0,2097.0,2093.0,2079.0,2075.0,2071.0,2067.0,2065.0,2069.0,2073.0,2077.0,2089.0,2093.0,2097.0,2093.0,2089.0,2085.0,2081.0,2077.0,2073.0,2069.0,2065.0,2061.0,2057.0,2053.0,2049.0,2053.0,2057.0,2061.0,2065.0,2069.0,2073.0,2077.0,2081.0,2077.0,2073.0,2069.0,2057.0,2053.0,2049.0,2045.0,2041.0,2037.0,2033.0,2037.0,2041.0};
double BASE_L[]={2083.0,2087.0,2091.0,2095.0,2091.0,2087.0,2083.0,2069.0,2065.0,2061.0,2057.0,2055.0,2059.0,2063.0,2067.0,2079.0,2083.0,2087.0,2083.0,2079.0,2075.0,2071.0,2067.0,2063.0,2059.0,2055.0,2051.0,2047.0,2043.0,2039.0,2043.0,2047.0,2051.0,2055.0,2059.0,2063.0,2067.0,2071.0,2067.0,2063.0,2059.0,2047.0,2043.0,2039.0,2035.0,2031.0,2027.0,2023.0,2027.0,2031.0};
double BASE_C[]={2088.0,2092.0,2096.0,2100.0,2096.0,2092.0,2088.0,2074.0,2070.0,2066.0,2062.0,2060.0,2064.0,2068.0,2072.0,2084.0,2088.0,2092.0,2088.0,2084.0,2080.0,2076.0,2072.0,2068.0,2064.0,2060.0,2056.0,2052.0,2048.0,2044.0,2048.0,2052.0,2056.0,2060.0,2064.0,2068.0,2072.0,2076.0,2072.0,2068.0,2064.0,2052.0,2048.0,2044.0,2040.0,2036.0,2032.0,2028.0,2032.0,2036.0};
double R_TOUCH[]={2054.0,2045.0,2050.0};
double R_REPLACE[]={2054.0,2045.0,2050.0,2058.0,2049.0,2052.0,2063.0,2056.0,2062.0};
double R_ERL[]={2054.0,2045.0,2050.0,2040.0,2022.0,2030.0};
double R_TREND[]={2054.0,2045.0,2050.0,2095.0,2050.0,2055.0,2056.0,2048.0,2052.0,2054.0,2046.0,2050.0};
double R_RETOUCH[]={2054.0,2045.0,2050.0,2081.0,2046.0,2055.0,2060.0,2047.0,2052.0,2058.0,2048.0,2050.0,2066.0,2049.0,2057.0,2072.0,2050.0,2058.0,2066.0,2051.0,2056.0,2062.0,2052.0,2054.0,2056.0,2053.0,2055.0};
double R_CONFIRM[]={2052.0,2048.0,2050.0,2049.0,2038.0,2040.0,2044.0,2036.0,2040.0,2046.0,2041.0,2043.0};
double R_BEYOND_ALL[]={2065.0,2045.0,2064.0};
double R_BEYOND_NEAREST[]={2062.0,2045.0,2060.0};
double R_EQUAL_EDGE[]={2062.0,2045.0,2059.0};
double R_NO_TOUCH[]={2052.0,2045.0,2050.0};
double R_ERL_FIRST[]={2040.0,2022.0,2030.0,2056.0,2045.0,2050.0};
// END GENERATED FIXTURES
#define H4S 14400
#define WINDOW 50
#define Z1 "F202601111200"
#define Z2 "F202601111600"
datetime CloseOf(const int index) {return(T0+(index+1)*H4S);}
void Build(const double &rows[],const bool buy,MqlRates &out[])
  {
   int nb=ArraySize(BASE_H),nr=ArraySize(rows)/3;
   ArrayResize(out,nb+nr);
   for(int i=0;i<nb+nr;i++)
     {
      double h=(i<nb ? BASE_H[i] : rows[3*(i-nb)]);
      double l=(i<nb ? BASE_L[i] : rows[3*(i-nb)+1]);
      double c=(i<nb ? BASE_C[i] : rows[3*(i-nb)+2]);
      ZeroMemory(out[i]);
      out[i].time=T0+i*H4S;
      out[i].high=(buy ? 4200.0-l : h);
      out[i].low=(buy ? 4200.0-h : l);
      out[i].close=(buy ? 4200.0-c : c);
      out[i].open=out[i].close;
     }
  }
void Scan(const MqlRates &b[],const int n,const int retouch,SM4ContextUpdate &u[],string &notes[],SM4OrdInfo &info)
  {
   M4OrdinaryScan(b,n,50,2,2,WINDOW,retouch,u,notes,info);
  }
string Fvg(const bool buy,const string z) {return(z+(buy ? "U" : "D"));}
void MakeM15(MqlRates &b[],const datetime base,const int d)
  {
   double h[]={96,98,100,97,96,101,107,110,109};
   double l[]={90,91,92,90,89,95,100,103,102};
   double c[]={93,94,95,93,92,100.5,105,108,104};
   ArrayResize(b,9);
   for(int i=0;i<9;i++)
     {
      ZeroMemory(b[i]); b[i].time=base+i*900;
      b[i].high=(d>0 ? h[i] : 200-l[i]); b[i].low=(d>0 ? l[i] : 200-h[i]);
      b[i].close=(d>0 ? c[i] : 200-c[i]); b[i].open=b[i].close;
     }
  }
int Count(const SM4Event &e[],const string type)
  {
   int n=0;
   for(int i=0;i<ArraySize(e);i++) if(e[i].type==type) n++;
   return(n);
  }
int Find(const SM4Event &e[],const string type)
  {
   for(int i=0;i<ArraySize(e);i++) if(e[i].type==type) return(i);
   return(-1);
  }
void Replay(const MqlRates &m[],const SM4ContextUpdate &u[],const int nu,const datetime start,const datetime asof,
             SM4State &s,SM4Candidate &f[],SM4Event &e[],SM4TimelineInfo &info)
  {
   M4ReplayTimeline(m,9,u,nu,start,asof,true,M4_A_AT_OR_AFTER_BREAK,2,2,300,s,f,e,info);
  }
void Touch(const bool buy)
  {
   string tag=(buy ? "BUY " : "SELL ");
   MqlRates b[];SM4ContextUpdate u[];string notes[];SM4OrdInfo info;
   Build(R_TOUCH,buy,b);
   Scan(b,50,M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==0,tag+"nothing recorded before the touching candle exists");
   Scan(b,51,M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==1 && notes[0]=="OPEN",tag+"one record at the touching candle");
   if(ArraySize(u)!=1) return;
   SM4Context c=u[0].context;
   Check(u[0].known==CloseOf(50) && c.valid_from==CloseOf(50),tag+"recorded at the CLOSE of the touching candle");
   Check(c.direction==(buy ? 1 : -1) && c.fvg==Fvg(buy,Z2) && c.source==M4_SRC_T002_TOUCH,tag+"nearest IRL zone, ordinary source id");
   Check(c.lower==(buy ? 2141.0 : 2053.0) && c.upper==(buy ? 2147.0 : 2059.0),tag+"zone bounds");
   Check(c.confirmed==T0+43*H4S && c.confirmed<=b[50].time,tag+"FVG known before the touching candle opens");
   Check(c.ready && c.reliable && c.selected,tag+"flags");
   // other single-bar cases
   Build(R_NO_TOUCH,buy,b);Scan(b,ArraySize(b),M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==0,tag+"wick short of the zone is no touch");
   Build(R_BEYOND_ALL,buy,b);Scan(b,ArraySize(b),M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==0,tag+"close beyond both far edges is not a touch");
   Build(R_BEYOND_NEAREST,buy,b);Scan(b,ArraySize(b),M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==1 && u[0].context.fvg==Fvg(buy,Z1),tag+"invalidated nearest skipped, next zone recorded");
   Build(R_EQUAL_EDGE,buy,b);Scan(b,ArraySize(b),M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==1 && u[0].context.fvg==Fvg(buy,Z2),tag+"close equal to far edge is not invalid");
   Build(R_ERL_FIRST,buy,b);Scan(b,ArraySize(b),M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==0,tag+"no setup when ERL was taken before the touch");
  }
void Confirm(const bool buy)
  {
   string tag=(buy ? "BUY " : "SELL ");
   MqlRates b[];SM4ContextUpdate u[];string notes[];SM4OrdInfo info;
   Build(R_CONFIRM,buy,b);
   Scan(b,53,M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==0,tag+"FVG confirmed by candle C cannot be touched by C");
   Scan(b,54,M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==1 && u[0].context.confirmed==b[53].time && u[0].known==b[53].time+H4S,
         tag+"candle opening exactly at the confirmation can touch");
  }
void Revocation(const bool buy)
  {
   string tag=(buy ? "BUY " : "SELL ");
   MqlRates b[];SM4ContextUpdate u[];string notes[];SM4OrdInfo info;
   Build(R_REPLACE,buy,b);
   Scan(b,52,M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==1,tag+"open record unchanged by a later touch of another zone");
   Scan(b,ArraySize(b),M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==2 && notes[1]=="REPLACE after FVG_INVALID" && u[1].known==CloseOf(52) &&
         u[1].context.fvg==Fvg(buy,Z1) && u[1].context.valid_from==CloseOf(52),tag+"invalidated FVG replaced at the same close");
   Check(info.opened==2 && info.closed==0 && info.replaced==1,tag+"replace counters");
   Build(R_ERL,buy,b);Scan(b,ArraySize(b),M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==2 && notes[1]=="CLOSE ERL_TAKEN" && u[1].known==CloseOf(51) && !u[1].context.ready,tag+"ERL taken revokes");
   Build(R_TREND,buy,b);
   Scan(b,53,M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==1,tag+"spike candle alone does not revoke");
   Scan(b,ArraySize(b),M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==2 && notes[1]=="CLOSE TREND_CHANGE" && u[1].known==CloseOf(53),tag+"trend change revokes when the swing is confirmed");
   Build(R_RETOUCH,buy,b);
   Scan(b,ArraySize(b),M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==3 && notes[2]=="OPEN" && u[2].known==CloseOf(58) && u[2].context.fvg==Fvg(buy,Z2) &&
         u[2].context.setup!=u[0].context.setup,tag+"re-touch after loss records again (AFTER_LOSS)");
   Scan(b,58,M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Check(ArraySize(u)==2,tag+"no reopen while the trend is not active");
   Scan(b,ArraySize(b),M4_RETOUCH_FIRST_ONLY,u,notes,info);
   Check(ArraySize(u)==2 && notes[1]=="CLOSE TREND_CHANGE",tag+"FIRST_ONLY never records the same FVG twice");
   // prefix determinism
   SM4ContextUpdate fu[];string fn[];SM4OrdInfo fi;
   for(int policy=1;policy<=2;policy++)
     {
      Scan(b,ArraySize(b),policy,fu,fn,fi);
      bool same=true;
      for(int k=50;k<=ArraySize(b) && same;k++)
        {
         Scan(b,k,policy,u,notes,info);
         datetime horizon=b[k-1].time+H4S;
         int expect=0;
         for(int i=0;i<ArraySize(fu);i++) if(fu[i].known<=horizon) expect++;
         if(ArraySize(u)!=expect) same=false;
         for(int i=0;i<ArraySize(u) && i<expect;i++)
            if(u[i].known!=fu[i].known || !M4ContextEqual(u[i].context,fu[i].context)) same=false;
        }
      Check(same,tag+"prefix determinism, policy "+IntegerToString(policy));
     }
  }
void Chain(const bool buy)
  {
   string tag=(buy ? "BUY " : "SELL ");
   int d=(buy ? 1 : -1);
   MqlRates b[],m[];SM4ContextUpdate u[],x[];string notes[];SM4OrdInfo info;
   SM4State s;SM4Candidate f[];SM4Event e[];SM4TimelineInfo ti;
   Build(R_TOUCH,buy,b);Scan(b,51,M4_RETOUCH_AFTER_LOSS,u,notes,info);
   datetime T=u[0].known;
   MakeM15(m,T,d);Replay(m,u,1,T,T+8100,s,f,e,ti);
   Check(ti.status=="OK" && ti.processed==9 && s.phase=="RETURN_OBSERVED" && ti.bos_price==100,tag+"full path after the touching close");
   Check(s.context.source==M4_SRC_T002_TOUCH && StringFind(s.context.setup,"T002TOUCH-")==0,tag+"ordinary source label");
   MakeM15(m,T-5400,d);Replay(m,u,1,T-5400,T+2700,s,f,e,ti);
   Check(s.phase=="WAIT_BREAK" && Count(e,"BOS_CANDIDATE")==0,tag+"M15 bar ending exactly at the touching close is excluded");
   ArrayResize(x,1);x[0]=u[0];x[0].known=T-H4S;x[0].context.valid_from=T-H4S;
   Replay(m,x,1,T-5400,T+2700,s,f,e,ti);
   Check(Count(e,"BOS_CANDIDATE")==1,tag+"control: a context valid from the candle OPEN would have broken");
   MakeM15(m,T-4500,d);Replay(m,u,1,T-4500,T+3600,s,f,e,ti);
   int bi=Find(e,"BOS_CANDIDATE");
   Check(Count(e,"BOS_CANDIDATE")==1 && bi>=0 && e[bi].time==T && e[bi].known==T+900,
         tag+"M15 bar opening at the close is usable after its own close");
   Build(R_ERL,buy,b);Scan(b,ArraySize(b),M4_RETOUCH_AFTER_LOSS,u,notes,info);
   datetime Tr=u[1].known;
   MakeM15(m,Tr-8100,d);Replay(m,u,2,Tr-8100,Tr,s,f,e,ti);
   Check(s.phase=="WAIT_CONTEXT" && Count(e,"RETURN_OBSERVED")==0,tag+"H4 revocation wins at the same close as the M15 return");
   Replay(m,u,1,Tr-8100,Tr,s,f,e,ti);
   Check(s.phase=="RETURN_OBSERVED",tag+"control: without revocation the return is observed");
   Build(R_REPLACE,buy,b);Scan(b,ArraySize(b),M4_RETOUCH_AFTER_LOSS,u,notes,info);
   Tr=u[1].known;
   MakeM15(m,Tr-8100,d);Replay(m,u,2,Tr-8100,Tr,s,f,e,ti);
   Check(s.phase=="WAIT_BREAK" && s.context.fvg==Fvg(buy,Z1) && ArraySize(f)==0 &&
         Count(e,"CONTEXT_OPEN")==2 && Count(e,"CONTEXT_CLOSED")==1 && Count(e,"RETURN_OBSERVED")==0,
         tag+"replacement at the close clears progress and excludes that candle");
   Build(R_RETOUCH,buy,b);Scan(b,ArraySize(b),M4_RETOUCH_AFTER_LOSS,u,notes,info);
   datetime first=u[0].known;
   MakeM15(m,first,d);Replay(m,u,3,first,first+8100,s,f,e,ti);
   Check(s.phase=="RETURN_OBSERVED" && s.context.setup==u[0].context.setup,tag+"later H4 updates beyond as-of are not used");
   // default gate
   Build(R_TOUCH,buy,b);Scan(b,51,M4_RETOUCH_UNSET,u,notes,info);
   Check(ArraySize(u)==1 && !u[0].context.selected,tag+"default policy leaves the context unselected");
   MakeM15(m,T,d);Replay(m,u,1,T,T+8100,s,f,e,ti);
   Check(s.phase=="WAIT_CONTEXT" && Count(e,"CONTEXT_OPEN")==0,tag+"unselected ordinary source blocks the observer");
  }
void OnStart()
  {
   Touch(false);Touch(true);
   Confirm(false);Confirm(true);
   Revocation(false);Revocation(true);
   Chain(false);Chain(true);
   MqlRates b[];SM4ContextUpdate u[];string notes[];SM4OrdInfo info;
   Build(R_TOUCH,false,b);
   M4OrdinaryScan(b,51,50,2,2,49,1,u,notes,info);
   Check(info.status=="INVALID_INPUT","window below 50 is invalid");
   M4OrdinaryScan(b,51,50,2,2,WINDOW,3,u,notes,info);
   Check(info.status=="INVALID_INPUT","unknown retouch policy is invalid");
   MqlRates bad[];ArrayCopy(bad,b);bad[10].time=bad[9].time;
   M4OrdinaryScan(bad,51,50,2,2,WINDOW,1,u,notes,info);
   Check(info.status=="INVALID_H4" && ArraySize(u)==0,"non-chronological H4 yields no updates");
   M4OrdinaryScan(b,51,10,2,2,WINDOW,1,u,notes,info);
   Check(ArraySize(u)==1,"earlier partial windows add nothing");
   M4OrdinaryScan(b,51,50,2,2,60,1,u,notes,info);
   Check(ArraySize(u)==0,"51 bars cannot satisfy a 60-bar window");
   Check(M4DirectionAgreement(-1,"BULL")=="DISAGREE" && M4DirectionAgreement(1,"BEAR")=="DISAGREE" &&
         M4DirectionAgreement(-1,"BEAR")=="AGREE" && M4DirectionAgreement(1,"BULLISH")=="AGREE" &&
         M4DirectionAgreement(1,"UNKNOWN")=="NO_DIRECTION" && M4DirectionAgreement(0,"BULL")=="NO_DIRECTION",
         "direction agreement label flags, never resolves");
   Check(M4_SRC_T002_TOUCH!=M4_SRC_T003,"source ids are distinct");
   PrintFormat("T004 ORDINARY TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
