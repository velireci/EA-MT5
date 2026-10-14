// T010 test script: pure news and spread filters. Mirrors tests/test_t010_filters.py; the fixtures below are the hand-derived
// tables of tests/t010_filters_fixtures.py. NOT YET COMPILED OR RUN in MT5 (UNVERIFIED).
// Tests the pure helpers only: no calendar, no quote, no clock, no order. The live calendar reader is NOT tested here.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/NewsSpreadFilters.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
// BEGIN GENERATED FIXTURES (tests/t010_filters_fixtures.py emit_mql)
#define NOW_T 1800000000
#define NAN_M -9.87654321e+250
#define INF_M 9.87654321e+250
#define NINF_M -9.87654321e+251
#define NNEWS 36
string N_NAME[]={"EMPTY_NO_ERROR","BEFORE_1800_INCLUDED","BEFORE_1799","BEFORE_1801_OUTSIDE","AFTER_1800_INCLUDED","AFTER_1799","AFTER_1801_OUTSIDE","AT_EVENT","EUR_HIGH_IGNORED","USD_MEDIUM_IGNORED","USD_LOW_IGNORED","USD_NONE_IGNORED","EUR_MEDIUM_IGNORED","FAR_USD_HIGH","SEVERAL_ONE_BLOCKS","TWO_OVERLAPPING_NEAREST","TWO_TIE_FIRST_WINS","UNKNOWN_AND_BLOCK_BLOCK_WINS","UNDEFINED_TIME_AND_BLOCK","FAR_AND_UNKNOWN","FETCH_FAILED_ALONE","FETCH_FAILED_EVEN_IF_FIELDS_SAY_EUR","INCOMPLETE_TWO_UNKNOWN","TIME_MODE_NOT_DATETIME","TIME_ZERO","TIME_ZERO_BUT_TIME_OK_FLAG","EUR_UNDEFINED_TIME_IRRELEVANT","USD_MEDIUM_TIME_ZERO_IRRELEVANT","QUERY_ERROR","QUERY_ERROR_WINS_OVER_EVENTS","CALENDAR_NOT_READY","TESTER_UNSUPPORTED","TESTER_UNSUPPORTED_WITH_EVENTS","INVALID_QUERY_STATUS","NOW_ZERO","NOW_NEGATIVE"};
int N_Q[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,2,3,3,9,0,0};
long N_NOW[]={1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,1800000000,0,-5};
string N_STATE[]={"CLEAR","BLOCKED","BLOCKED","CLEAR","BLOCKED","BLOCKED","CLEAR","BLOCKED","CLEAR","CLEAR","CLEAR","CLEAR","CLEAR","CLEAR","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","CLEAR","CLEAR","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN"};
string N_STATUS[]={"CLEAR","BLOCKED_WINDOW","BLOCKED_WINDOW","CLEAR","BLOCKED_WINDOW","BLOCKED_WINDOW","CLEAR","BLOCKED_WINDOW","CLEAR","CLEAR","CLEAR","CLEAR","CLEAR","CLEAR","BLOCKED_WINDOW","BLOCKED_WINDOW","BLOCKED_WINDOW","BLOCKED_WINDOW","BLOCKED_WINDOW","UNKNOWN_EVENT_DATA","UNKNOWN_EVENT_DATA","UNKNOWN_EVENT_DATA","UNKNOWN_EVENT_DATA","UNKNOWN_EVENT_DATA","UNKNOWN_EVENT_DATA","UNKNOWN_EVENT_DATA","CLEAR","CLEAR","UNKNOWN_CALENDAR_ERROR","UNKNOWN_CALENDAR_ERROR","UNKNOWN_CALENDAR_NOT_READY","UNKNOWN_TESTER_UNSUPPORTED","UNKNOWN_TESTER_UNSUPPORTED","UNKNOWN_CALENDAR_ERROR","UNKNOWN_INVALID_INPUT","UNKNOWN_INVALID_INPUT"};
int N_BLOCKING[]={0,1,1,0,1,1,0,1,0,0,0,0,0,0,1,2,2,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int N_UNKNOWN[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,2,1,1,1,0,0,0,0,0,0,0,0,0,0};
int N_HASNEAR[]={0,1,1,0,1,1,0,1,0,0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
long N_NEAR[]={0,1800,1799,0,-1800,-1799,0,0,0,0,0,0,0,0,600,-300,300,60,-60,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
string N_NEARNAME[]={"","A","A","","A","A","","A","","","","","","","NFP","B","A","A","A","","","","","","","","","","","","","","","","",""};
int N_EVFIRST[]={0,0,1,2,3,4,5,6,7,8,9,10,11,12,14,17,19,21,23,25,27,28,29,31,32,33,34,35,36,36,37,37,37,38,38,38};
int N_EVCOUNT[]={0,1,1,1,1,1,1,1,1,1,1,1,1,2,3,2,2,2,2,2,1,1,2,1,1,1,1,1,0,1,0,0,1,0,0,0};
#define NEV 38
int E_ZERO[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0};
long E_DELTA[]={1800,1799,1801,-1800,-1799,-1801,0,0,0,0,0,0,7200,-7200,7200,600,-9000,600,-300,300,-300,0,60,5,-60,7200,0,0,0,0,7200,0,0,0,0,0,0,7200};
int E_TIMEOK[]={1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,0,0,1,1,0,1,1,1};
string E_CUR[]={"USD","USD","USD","USD","USD","USD","USD","EUR","USD","USD","USD","EUR","USD","USD","USD","USD","USD","USD","USD","USD","USD","USD","USD","USD","USD","USD","USD","USD","EUR","USD","USD","USD","USD","USD","EUR","USD","USD","USD"};
int E_IMP[]={3,3,3,3,3,3,3,3,2,1,0,2,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,1,3,3,3,3,3,3,2,3,3};
int E_FETCH[]={1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,0,0,0,0,1,1,1,1,1,1,1,1};
string E_NAME[]={"A","A","EV","A","A","EV","A","EV","EV","EV","EV","EV","EV","EV","FAR","NFP","OLD","A","B","A","B","EV","A","EV","A","EV","EV","EV","EV","EV","EV","EV","EV","EV","EV","EV","EV","EV"};
#define NCLS 15
string C_NAME[]={"EMPTY_OK","NEGATIVE_RET","NEGATIVE_RET_WITH_VALUES","ZERO_RET_WITH_ERROR","ZERO_RET_BUT_VALUES","RET_ABOVE_SIZE_PARTIAL","RET_BELOW_SIZE_PARTIAL","RET_EQUALS_SIZE_3","RET_EQUALS_SIZE_1","RET_ONE_BUT_THREE_VALUES","RET_ONE_BUT_EMPTY","POSITIVE_RET_WITH_ERROR","RET_ONE_WITH_ERROR","NEGATIVE_ARRAY_SIZE","NEGATIVE_ARRAY_SIZE_POSITIVE_RET"};
int C_RET[]={0,-1,-1,0,0,3,2,3,1,1,1,3,1,0,1};
int C_ERR[]={0,0,0,4001,0,0,0,0,0,0,0,5,5,0,0};
int C_SIZE[]={0,0,3,0,2,2,3,3,1,3,0,3,3,-1,-1};
int C_WANT[]={0,1,1,1,1,1,1,0,0,1,1,1,1,1,1};
#define NRNG 14
string R_NAME[]={"MID_DAY","JUST_AFTER_MIDNIGHT","JUST_BEFORE_MIDNIGHT","EXACTLY_MIDNIGHT","FROM_EDGE_LOW","FROM_EDGE_HIGH","TO_EDGE_LOW","TO_EDGE_HIGH","NOW_ZERO","NOW_NEGATIVE","NOW_TOO_EARLY_FROM_NEGATIVE","NOW_EARLIEST_VALID","NOW_LATEST_VALID","NOW_OVERFLOW_BY_ONE_DAY"};
long R_NOW[]={1800000000,1799972200,1799970200,1799971200,1799972999,1799973000,1799969399,1799969400,0,-5,88199,88200,32535127799,32535127800};
int R_VALID[]={1,1,1,1,1,1,1,1,0,0,0,1,1,0};
long R_FROM[]={1799884800,1799798400,1799798400,1799798400,1799798400,1799884800,1799798400,1799798400,0,0,0,0,32534956800,0};
long R_TO[]={1800143999,1800143999,1800143999,1800143999,1800143999,1800143999,1800057599,1800143999,0,0,0,259199,32535215999,0};
#define NCOV 11
#define DAY_T 1799971200
string V_NAME[]={"COV_USD_HIGH_UNDEFINED_SAME_DAY_OUTSIDE_WINDOW","COV_USD_HIGH_UNDEFINED_PREVIOUS_DAY","COV_USD_HIGH_UNDEFINED_NEXT_DAY","COV_USD_HIGH_UNDEFINED_FIRST_SECOND_OF_RANGE","COV_USD_HIGH_UNDEFINED_BEFORE_RANGE","COV_USD_HIGH_UNDEFINED_LAST_SECOND_OF_RANGE","COV_USD_HIGH_UNDEFINED_AFTER_RANGE","COV_USD_HIGH_DEFINED_OUTSIDE_WINDOW","COV_USD_HIGH_DEFINED_INSIDE_WINDOW","COV_EUR_HIGH_UNDEFINED","COV_USD_MEDIUM_UNDEFINED"};
string V_STATE[]={"UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","CLEAR","UNKNOWN","CLEAR","CLEAR","BLOCKED","CLEAR","CLEAR"};
string V_STATUS[]={"UNKNOWN_EVENT_DATA","UNKNOWN_EVENT_DATA","UNKNOWN_EVENT_DATA","UNKNOWN_EVENT_DATA","CLEAR","UNKNOWN_EVENT_DATA","CLEAR","CLEAR","BLOCKED_WINDOW","CLEAR","CLEAR"};
int V_EVCOUNT[]={1,1,1,1,1,1,1,1,1,1,1};
int V_EVFIRST[]={0,1,2,3,4,5,6,7,8,9,10};
long VE_ANCHOR[]={0,-3600,90000,-86400,-86401,172799,172800,0,30600,0,0};
int VE_TIMEOK[]={0,0,0,0,0,0,0,1,1,0,0};
string VE_CUR[]={"USD","USD","USD","USD","USD","USD","USD","USD","USD","EUR","USD"};
int VE_IMP[]={3,3,3,3,3,3,3,3,3,3,2};
string VE_NAME[]={"ALLDAY","ALLDAY","ALLDAY","ALLDAY","ALLDAY","ALLDAY","ALLDAY","DEF","DEF","ALLDAY","ALLDAY"};
#define NSPR 35
string S_NAME[]={"BELOW","AT_THRESHOLD_BINARY_NOISE_ABOVE","AT_THRESHOLD_NOISE_2310","AT_THRESHOLD_NOISE_BELOW","AT_THRESHOLD_ONE_ULP_ABOVE_20","REAL_EXCESS_0_001_POINT","ABOVE_ONE_POINT","FAR_ABOVE","ZERO_SPREAD_THRESHOLD_20","ZERO_SPREAD_THRESHOLD_0","POSITIVE_SPREAD_THRESHOLD_0","POINT_0_001_AT_THRESHOLD","THRESHOLD_UNSET","THRESHOLD_NAN","THRESHOLD_INF","THRESHOLD_NEG_INF","THRESHOLD_NEGATIVE_HALF","THRESHOLD_NEGATIVE_TWO","UNSET_WINS_OVER_BAD_QUOTE","QUOTE_BID_NAN","QUOTE_ASK_NAN","QUOTE_BID_INF","QUOTE_ASK_INF","QUOTE_ASK_NEG_INF","QUOTE_BID_ZERO","QUOTE_BID_NEGATIVE","QUOTE_ASK_ZERO","QUOTE_ASK_NEGATIVE","QUOTE_ASK_BELOW_BID","QUOTE_BOTH_ZERO","POINT_ZERO","POINT_NEGATIVE","POINT_NAN","POINT_INF","SPREAD_OVERFLOW"};
double S_BID[]={2000.0,2000.0,2310.2,1950.4,1.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,100.0,2000.0,2000.0,2000.0,2000.0,2000.0,2000.0,-9.87654321e+250,-9.87654321e+250,2000.0,9.87654321e+250,2000.0,2000.0,0.0,-1.0,2000.0,2000.0,2000.1,0.0,2000.0,2000.0,2000.0,2000.0,1.0};
double S_ASK[]={2000.1,2000.2,2310.4,1950.6,21.000000000000004,2000.20001,2000.21,2005.0,2000.0,2000.0,2000.1,100.02,2000.1,2000.1,2000.1,2000.1,2000.1,2000.1,2000.1,2000.1,-9.87654321e+250,2000.1,9.87654321e+250,-9.87654321e+251,2000.1,2000.1,0.0,-1.0,2000.0,0.0,2000.1,2000.1,2000.1,2000.1,1e+308};
double S_POINT[]={0.01,0.01,0.01,0.01,1.0,0.01,0.01,0.01,0.01,0.01,0.01,0.001,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.0,-0.01,-9.87654321e+250,9.87654321e+250,1e-300};
double S_MAX[]={20.0,20.0,20.0,20.0,20.0,20.0,20.0,20.0,20.0,0.0,0.0,20.0,-1.0,-9.87654321e+250,9.87654321e+250,-9.87654321e+251,-0.5,-2.0,-1.0,20.0,20.0,20.0,20.0,20.0,20.0,20.0,20.0,20.0,20.0,20.0,20.0,20.0,20.0,20.0,20.0};
string S_STATE[]={"CLEAR","CLEAR","CLEAR","CLEAR","CLEAR","BLOCKED","BLOCKED","BLOCKED","CLEAR","CLEAR","BLOCKED","CLEAR","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN"};
string S_STATUS[]={"CLEAR","CLEAR","CLEAR","CLEAR","CLEAR","BLOCKED","BLOCKED","BLOCKED","CLEAR","CLEAR","BLOCKED","CLEAR","POLICY_UNSET","INVALID_THRESHOLD","INVALID_THRESHOLD","INVALID_THRESHOLD","INVALID_THRESHOLD","INVALID_THRESHOLD","POLICY_UNSET","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE","INVALID_QUOTE"};
// END GENERATED FIXTURES

double Real(const double v)
  {
   if(v==NAN_M) return(MathSqrt(-1.0));
   if(v==INF_M) return(MathExp(1000.0));
   if(v==NINF_M) return(-MathExp(1000.0));
   return(v);
  }
void RunNews(const int i)
  {
   SNfEvent ev[];
   int n=N_EVCOUNT[i];
   ArrayResize(ev,n);
   for(int k=0;k<n;k++)
     {
      int j=N_EVFIRST[i]+k;
      ev[k].time=(E_ZERO[j]==1 ? (datetime)0 : (datetime)(N_NOW[i]+E_DELTA[j]));
      ev[k].time_ok=(E_TIMEOK[j]==1);
      ev[k].currency=E_CUR[j];
      ev[k].importance=E_IMP[j];
      ev[k].fetch_ok=(E_FETCH[j]==1);
      ev[k].name=E_NAME[j];
     }
   SNfNews r;
   NF_NewsEvaluate((datetime)N_NOW[i],ev,n,N_Q[i],r);
   string tag="news "+N_NAME[i]+": ";
   Check(NF_StateName(r.state)==N_STATE[i] && r.status==N_STATUS[i],tag+"state "+NF_StateName(r.state)+" status "+r.status);
   Check(r.blocking==N_BLOCKING[i] && r.unknown==N_UNKNOWN[i],tag+"counts");
   long want=(N_HASNEAR[i]==1 ? N_NOW[i]+N_NEAR[i] : 0);
   Check((long)r.nearest_time==want && r.nearest_name==N_NEARNAME[i],tag+"nearest event");
   int tp=NF_ToNewsState(r.state);
   Check((r.state==NF_CLEAR && tp==TP_NEWS_CLEAR) || (r.state==NF_BLOCKED && tp==TP_NEWS_BLOCKED) ||
         (r.state==NF_UNKNOWN && tp==TP_NEWS_UNKNOWN),tag+"mapped to the T007 news state");
  }
void RunSpread(const int i)
  {
   SNfSpread r;
   NF_SpreadEvaluate(Real(S_BID[i]),Real(S_ASK[i]),Real(S_POINT[i]),Real(S_MAX[i]),r);
   string tag="spread "+S_NAME[i]+": ";
   Check(NF_StateName(r.state)==S_STATE[i] && r.status==S_STATUS[i],tag+"state "+NF_StateName(r.state)+" status "+r.status);
   int tp=NF_ToSpreadState(r.state);
   Check((r.state==NF_CLEAR && tp==TP_SPREAD_CLEAR) || (r.state==NF_BLOCKED && tp==TP_SPREAD_BLOCKED) ||
         (r.state==NF_UNKNOWN && tp==TP_SPREAD_UNKNOWN),tag+"mapped to the T007 spread state");
  }
void RunClassify(const int i)
  {
   Check(NF_ClassifyCalendarRead(C_RET[i],C_ERR[i],C_SIZE[i])==C_WANT[i],"calendar read classifier "+C_NAME[i]);
  }
void RunRange(const int i)
  {
   datetime range_from=1,range_to=1;
   bool ok=NF_QueryRange((datetime)R_NOW[i],range_from,range_to);
   string tag="query range "+R_NAME[i]+": ";
   if(R_VALID[i]==1) Check(ok && (long)range_from==R_FROM[i] && (long)range_to==R_TO[i],tag+TimeToString(range_from,TIME_DATE|TIME_SECONDS)+".."+TimeToString(range_to,TIME_DATE|TIME_SECONDS));
   else Check(!ok && (long)range_from==0 && (long)range_to==0,tag+"invalid");
  }
// Coverage: a fake calendar filtered by NF_QueryRange(NOW) (only events whose anchor lies inside the range are "returned"), then the pure rule.
void RunCoverage(const int i)
  {
   datetime range_from=0,range_to=0;
   bool ok=NF_QueryRange((datetime)(DAY_T+28800),range_from,range_to);
   SNfEvent ev[];
   int kept=0;
   ArrayResize(ev,V_EVCOUNT[i]);
   for(int k=0;k<V_EVCOUNT[i];k++)
     {
      int j=V_EVFIRST[i]+k;
      long t=DAY_T+VE_ANCHOR[j];
      if(!ok || t<(long)range_from || t>(long)range_to) continue;
      ev[kept].time=(datetime)t;
      ev[kept].time_ok=(VE_TIMEOK[j]==1);
      ev[kept].currency=VE_CUR[j];
      ev[kept].importance=VE_IMP[j];
      ev[kept].fetch_ok=true;
      ev[kept].name=VE_NAME[j];
      kept++;
     }
   SNfNews r;
   NF_NewsEvaluate((datetime)(DAY_T+28800),ev,kept,NF_Q_OK,r);
   Check(NF_StateName(r.state)==V_STATE[i] && r.status==V_STATUS[i],"coverage "+V_NAME[i]+": "+NF_StateName(r.state)+" "+r.status);
  }
void OnStart()
  {
   for(int i=0;i<NNEWS;i++) RunNews(i);
   for(int i=0;i<NSPR;i++) RunSpread(i);
   for(int i=0;i<NCLS;i++) RunClassify(i);
   for(int i=0;i<NRNG;i++) RunRange(i);
   for(int i=0;i<NCOV;i++) RunCoverage(i);
   Check(NF_WINDOW_SECONDS==1800 && NF_SPREAD_UNSET==-1.0,"constants");
   Check(NF_InWindow((datetime)NOW_T,(datetime)(NOW_T+1800)) && !NF_InWindow((datetime)NOW_T,(datetime)(NOW_T+1801)),"window upper edge");
   Check(NF_InWindow((datetime)NOW_T,(datetime)(NOW_T-1800)) && !NF_InWindow((datetime)NOW_T,(datetime)(NOW_T-1801)),"window lower edge");
   PrintFormat("T010 FILTERS TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
