// T010 pure news and spread filters. NO calendar, quote, clock, symbol, account or trading calls: every input is supplied.
// Results feed ONLY the T007 permit snapshot (news_state / spread_state). They never send, modify, cancel or close anything.
//
// NEWS (USD + HIGH importance only). Time basis: SERVER time. `now` must be TimeTradeServer() and event times are the MT5
// calendar values' time compared in the same server-time sense (NOT UTC, NOT Tirane; T009 keeps its own UTC basis).
// Window: [event-1800s, event+1800s], both boundaries INCLUDED (one second outside does not block).
// Decision: any relevant event in the window -> BLOCKED. Else any unreadable / incomplete / undefined-time relevant event, or a
// query that failed / is not ready / is unsupported in the tester -> UNKNOWN. Only a successful query with no such event -> CLEAR.
// BLOCKED wins over UNKNOWN as the reason (more informative); both end as a block in the permit. Other currencies or
// importance other than HIGH never block. An event whose record could not be fetched (fetch_ok=false) is UNKNOWN because its
// currency / importance cannot be known.
//
// SPREAD: spread_points=(ask-bid)/point. Maximum is an input in points with NO default: NF_SPREAD_UNSET (-1.0) = unset policy.
// 0 is a valid threshold (only a zero spread passes), so 0 cannot be the sentinel; -1 follows the T007 limits convention.
// Any other negative, NaN or infinity threshold is INVALID. Invalid quote (non-finite, bid<=0, ask<=0, ask<bid, point<=0) is
// UNKNOWN. spread > threshold blocks; spread == threshold is ALLOWED; only floating-point noise is tolerated:
// tolerance = 16*DBL_EPSILON*(max(ask,bid)/point + max(1,threshold)) -- the first term covers the rounding of the two
// quotes, the second the rounding of the division. A real 0.001-point excess is far above it.
// Spread statuses are the filter's own detail; the permit sees CLEAR / BLOCKED / UNKNOWN (unset, invalid threshold and invalid
// quote map to UNKNOWN, i.e. permit reason SPREAD_UNKNOWN). The action after a spread block is NOT decided here.
#ifndef VELO_NEWS_SPREAD_FILTERS_MQH
#define VELO_NEWS_SPREAD_FILTERS_MQH
#include "TradePlanning.mqh"
#define NF_WINDOW_SECONDS 1800
#define NF_SPREAD_UNSET (-1.0)
#define NF_NOISE_ULPS 16.0
#define NF_CLEAR 1
#define NF_BLOCKED 2
#define NF_UNKNOWN 3
#define NF_IMP_NONE 0
#define NF_IMP_LOW 1
#define NF_IMP_MODERATE 2
#define NF_IMP_HIGH 3
#define NF_Q_OK 0
#define NF_Q_ERROR 1
#define NF_Q_NOT_READY 2
#define NF_Q_TESTER 3
struct SNfEvent
  {
   datetime time;     // server time of the event
   bool time_ok;      // false = no/all-day/tentative time mode or otherwise undefined
   string currency;   // from the event's country
   int importance;    // NF_IMP_*
   bool fetch_ok;     // false = the event record or its country could not be read
   string name;
  };
struct SNfNews
  {
   int state;         // NF_CLEAR / NF_BLOCKED / NF_UNKNOWN
   string status;     // CLEAR | BLOCKED_WINDOW | UNKNOWN_*
   int blocking;      // relevant events inside the window
   int unknown;       // relevant-or-unreadable events that could not be decided
   datetime nearest_time;
   string nearest_name;
  };
struct SNfSpread
  {
   int state;
   string status;     // CLEAR | BLOCKED | POLICY_UNSET | INVALID_THRESHOLD | INVALID_QUOTE
   double spread_points;
   double tolerance;
  };
string NF_StateName(const int s) {return(s==NF_CLEAR ? "CLEAR" : s==NF_BLOCKED ? "BLOCKED" : "UNKNOWN");}
int NF_ToNewsState(const int s) {return(s==NF_CLEAR ? TP_NEWS_CLEAR : s==NF_BLOCKED ? TP_NEWS_BLOCKED : TP_NEWS_UNKNOWN);}
int NF_ToSpreadState(const int s) {return(s==NF_CLEAR ? TP_SPREAD_CLEAR : s==NF_BLOCKED ? TP_SPREAD_BLOCKED : TP_SPREAD_UNKNOWN);}
bool NF_Finite(const double v) {return(MathIsValidNumber(v));}
bool NF_InWindow(const datetime now,const datetime event_time)
  {
   long d=(long)now-(long)event_time;
   return(d>=-NF_WINDOW_SECONDS && d<=NF_WINDOW_SECONDS);
  }
void NF_NewsEvaluate(const datetime now,const SNfEvent &events[],const int count,const int query_status,SNfNews &out)
  {
   out.state=NF_UNKNOWN;out.status="UNKNOWN_INVALID_INPUT";out.blocking=0;out.unknown=0;out.nearest_time=0;out.nearest_name="";
   if(now<=0 || count<0 || count>ArraySize(events)) return;
   if(query_status==NF_Q_TESTER) {out.status="UNKNOWN_TESTER_UNSUPPORTED";return;}
   if(query_status==NF_Q_NOT_READY) {out.status="UNKNOWN_CALENDAR_NOT_READY";return;}
   if(query_status!=NF_Q_OK) {out.status="UNKNOWN_CALENDAR_ERROR";return;}
   long best=0;
   for(int i=0;i<count;i++)
     {
      if(!events[i].fetch_ok) {out.unknown++;continue;}
      if(events[i].currency!="USD" || events[i].importance!=NF_IMP_HIGH) continue;
      if(!events[i].time_ok || events[i].time<=0) {out.unknown++;continue;}
      if(!NF_InWindow(now,events[i].time)) continue;
      long dist=(long)now-(long)events[i].time;
      if(dist<0) dist=-dist;
      if(out.blocking==0 || dist<best) {best=dist;out.nearest_time=events[i].time;out.nearest_name=events[i].name;}
      out.blocking++;
     }
   if(out.blocking>0) {out.state=NF_BLOCKED;out.status="BLOCKED_WINDOW";return;}
   if(out.unknown>0) {out.state=NF_UNKNOWN;out.status="UNKNOWN_EVENT_DATA";return;}
   out.state=NF_CLEAR;out.status="CLEAR";
  }
bool NF_SpreadWithin(const double spread,const double threshold,const double tolerance)
  {
   return(spread<=threshold+tolerance);
  }
void NF_SpreadEvaluate(const double bid,const double ask,const double point,const double max_points,SNfSpread &out)
  {
   out.state=NF_UNKNOWN;out.status="INVALID_QUOTE";out.spread_points=0;out.tolerance=0;
   if(NF_Finite(max_points) && max_points==NF_SPREAD_UNSET) {out.status="POLICY_UNSET";return;}
   if(!NF_Finite(max_points) || max_points<0) {out.status="INVALID_THRESHOLD";return;}
   if(!NF_Finite(bid) || !NF_Finite(ask) || !NF_Finite(point) || bid<=0 || ask<=0 || ask<bid || point<=0) return;
   double spread=(ask-bid)/point;
   double tol=NF_NOISE_ULPS*DBL_EPSILON*(MathMax(MathAbs(ask),MathAbs(bid))/point+MathMax(1.0,max_points));
   if(!NF_Finite(spread) || !NF_Finite(tol)) return;
   out.spread_points=spread;out.tolerance=tol;
   if(NF_SpreadWithin(spread,max_points,tol)) {out.state=NF_CLEAR;out.status="CLEAR";}
   else {out.state=NF_BLOCKED;out.status="BLOCKED";}
  }
#endif
