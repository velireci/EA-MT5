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
// CALENDAR READ (thin reader in the EA calls these two pure helpers; TECHNICAL PROPOSALS, conservative, for Codex to confirm):
// 1) NF_QueryRange(now,from,to): the calendar query is WIDENED to whole server days so that USD HIGH events with undefined time
//    (all-day / no-time / tentative; their stored time may sit at a day boundary of ANOTHER time zone) cannot fall outside the
//    query and be missed before time_mode is examined:  from = floor_day(now-1800) - 86400,  to = floor_day(now+1800) + 2*86400 - 1
//    (integer server-time seconds, floor_day(t)=t-(t mod 86400) with a non-negative remainder; i.e. one extra day each side).
//    Over-blocking is the safe direction. The BLOCK window itself stays exactly [event-1800,event+1800] for defined-time events;
//    a defined-time event in the widened range but outside the window does NOT block. Invalid when now<=0, from<0 or
//    to>NF_MAX_DATETIME (3000-12-31 23:59:59).
// 2) NF_ClassifyCalendarRead(ret,last_error,array_size): the RETURN TYPE of CalendarValueHistory is DISPUTED (a 2019 release post
//    lists bool, Codex reports an int count; the official page was unreachable here). The reader stores the result as int, so
//    bool (true=1,false=0) and a count both work. Rules, in order: array_size<0 -> ERROR; last_error!=0 -> ERROR; ret<0 -> ERROR;
//    ret==0 -> OK only if array_size==0 (no events), else ERROR (inconsistent); ret>array_size -> ERROR (events missing =
//    incomplete); ret==array_size -> OK; ret==1 with array_size>1 -> OK ONLY because a bool true is 1 (never hides events: more
//    events present than reported is not a loss); any other ret<array_size -> ERROR (partial). Only NF_Q_OK may reach NF_NewsEvaluate
//    as a successful query.
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
#define NF_DAY_SECONDS 86400
#define NF_MAX_DATETIME 32535215999
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
long NF_FloorDay(const long t)
  {
   long r=t%NF_DAY_SECONDS;
   if(r<0) r+=NF_DAY_SECONDS;
   return(t-r);
  }
bool NF_QueryRange(const datetime now,datetime &range_from,datetime &range_to)
  {
   range_from=0;range_to=0;
   if((long)now<=0) return(false);
   long lo=NF_FloorDay((long)now-NF_WINDOW_SECONDS)-NF_DAY_SECONDS;
   long hi=NF_FloorDay((long)now+NF_WINDOW_SECONDS)+2*NF_DAY_SECONDS-1;
   if(lo<0 || hi>NF_MAX_DATETIME) return(false);
   range_from=(datetime)lo;range_to=(datetime)hi;
   return(true);
  }
int NF_ClassifyCalendarRead(const int ret,const int last_error,const int array_size)
  {
   if(array_size<0 || last_error!=0 || ret<0) return(NF_Q_ERROR);
   if(ret==0) return(array_size==0 ? NF_Q_OK : NF_Q_ERROR);
   if(ret>array_size) return(NF_Q_ERROR);
   if(ret==array_size || ret==1) return(NF_Q_OK);
   return(NF_Q_ERROR);
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
