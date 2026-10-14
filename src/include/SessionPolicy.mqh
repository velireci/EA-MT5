// Pure UTC session snapshot. Client hours: Mon-Fri00:00-20:30 Tirane, Friday21:00 close.
// Boundary convention [start,end), Friday close >=cutoff; flags only, never orders.
// EU recurrence current at2026-10-14, supported UTC/local years1996..2099.
// Source: https://data.iana.org/time-zones/tzdb/europe . No claim of immutable future law.
#ifndef VELO_SESSION_POLICY_MQH
#define VELO_SESSION_POLICY_MQH
struct SSessionPolicy
  {
   string status;
   datetime utc;
   datetime local_time; // encoded civil time, not UTC
   int offset_seconds;
   int day_key;
   datetime midnight_utc;
   bool entry_open;
   bool cancel_pending_due;
   bool friday_close_due; // Friday only; no weekend catchup/persistence
  };
datetime SP_Edge(const int year,const int month)
  {
   MqlDateTime d;ZeroMemory(d);d.year=year;d.mon=month;d.day=31;d.hour=1;
   datetime t=StructToTime(d);TimeToStruct(t,d);
   return(t-d.day_of_week*86400);
  }
int SP_Offset(const datetime utc)
  {
   MqlDateTime d;ZeroMemory(d);TimeToStruct(utc,d);
   return(utc>=SP_Edge(d.year,3) && utc<SP_Edge(d.year,10) ? 7200 : 3600);
  }
bool SP_Evaluate(const datetime utc,const int start_minute,const int end_minute,const int weekday_mask,
                 const bool friday_enabled,const int friday_minute,SSessionPolicy &out)
  {
   out.status="INVALID_INPUT";out.utc=utc;out.local_time=0;out.offset_seconds=0;out.day_key=0;
   out.midnight_utc=0;out.entry_open=false;out.cancel_pending_due=false;out.friday_close_due=false;
   if(utc<=0 || start_minute<0 || start_minute>=end_minute || end_minute>1440 || weekday_mask<0 ||
      weekday_mask>127 || friday_minute<0 || friday_minute>=1440) return(false);
   MqlDateTime d;ZeroMemory(d);
   if(!TimeToStruct(utc,d)) return(false);
   if(d.year<1996 || d.year>2099) {out.status="UNSUPPORTED_YEAR";return(false);}
   int offset=SP_Offset(utc);
   datetime local=utc+offset;
   if(!TimeToStruct(local,d)) return(false);
   if(d.year<1996 || d.year>2099) {out.status="UNSUPPORTED_YEAR";return(false);}
   int minute=d.hour*60+d.min;
   bool close=(friday_enabled && d.day_of_week==5 && minute>=friday_minute);
   out.status="OK";out.local_time=local;out.offset_seconds=offset;
   out.day_key=d.year*10000+d.mon*100+d.day;
   out.entry_open=((weekday_mask & (1<<d.day_of_week))!=0 && minute>=start_minute && minute<end_minute && !close);
   out.cancel_pending_due=!out.entry_open;
   out.friday_close_due=close;
   d.hour=0;d.min=0;d.sec=0;
   datetime midnight=StructToTime(d);
   out.midnight_utc=midnight-SP_Offset(midnight-3600);
   return(true);
  }
bool SP_DayChanged(const datetime previous,const datetime current,bool &changed)
  {
   changed=false;
   if(current<previous) return(false);
   SSessionPolicy a,b;
   if(!SP_Evaluate(previous,0,1230,62,true,1260,a) || !SP_Evaluate(current,0,1230,62,true,1260,b)) return(false);
   changed=(a.day_key!=b.day_key);
   return(true);
  }
#endif
