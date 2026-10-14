#property strict
#include "../include/SessionPolicy.mqh"
int passed=0,failed=0;
void Check(const bool ok,const string label)
  {if(ok) {passed++;Print("PASS ",label);} else {failed++;Print("FAIL ",label);}}
void At(const datetime utc,const bool opened,const bool friday,const int offset,const int day,const string label)
  {
   SSessionPolicy r;
   bool ok=SP_Evaluate(utc,0,1230,62,true,1260,r);
   Check(ok && r.status=="OK",label+" valid");
   Check(r.entry_open==opened && r.cancel_pending_due==!opened,label+" session");
   Check(r.friday_close_due==friday,label+" Friday close request");
   Check(r.offset_seconds==offset && r.day_key==day,label+" offset/day");
  }
void OnStart()
  {
   At(D'2026.10.14 18:29:59',true,false,7200,20261014,"summer before end");
   At(D'2026.10.14 18:30:00',false,false,7200,20261014,"summer exact end");
   At(D'2026.01.14 19:29:59',true,false,3600,20260114,"winter before end");
   At(D'2026.01.14 19:30:00',false,false,3600,20260114,"winter exact end");
   At(D'2026.10.13 22:00:00',true,false,7200,20261014,"local midnight");
   At(D'2026.10.16 18:59:59',false,false,7200,20261016,"before Friday close");
   At(D'2026.10.16 19:00:00',false,true,7200,20261016,"Friday close due");
   At(D'2026.10.17 10:00:00',false,false,7200,20261017,"Saturday no catchup");
   At(D'2026.10.18 10:00:00',false,false,7200,20261018,"Sunday");
   At(D'2026.03.29 00:59:59',false,false,3600,20260329,"spring before");
   At(D'2026.03.29 01:00:00',false,false,7200,20260329,"spring at");
   At(D'2026.10.25 00:59:59',false,false,7200,20261025,"autumn before");
   At(D'2026.10.25 01:00:00',false,false,3600,20261025,"autumn at");
   SSessionPolicy r;
   SP_Evaluate(D'2026.10.13 22:00:00',0,1230,62,true,1260,r);
   Check(r.midnight_utc==D'2026.10.13 22:00:00',"summer day starts at UTC22");
   SP_Evaluate(D'2026.10.25 12:00:00',0,1230,62,true,1260,r);
   Check(r.midnight_utc==D'2026.10.24 22:00:00',"autumn transition midnight uses prechange offset");
   SP_Evaluate(D'2026.03.29 12:00:00',0,1230,62,true,1260,r);
   Check(r.midnight_utc==D'2026.03.28 23:00:00',"spring transition midnight uses prechange offset");
   bool changed=false;
   Check(SP_DayChanged(D'2026.10.13 21:59:59',D'2026.10.13 22:00:00',changed) && changed,"local day rollover");
   Check(SP_DayChanged(D'2026.10.14 00:00:00',D'2026.10.14 12:00:00',changed) && !changed,"same local day");
   Check(!SP_DayChanged(D'2026.10.14 12:00:00',D'2026.10.14 00:00:00',changed) && !changed,"backward input invalid");
   Check(!SP_Evaluate(D'1995.01.01',0,1230,62,true,1260,r) && r.status=="UNSUPPORTED_YEAR","unsupported year");
   Check(!SP_Evaluate(D'2026.10.14',1300,1200,62,true,1260,r),"overnight config unsupported");
   Check(!SP_Evaluate(D'2026.10.14',0,1441,62,true,1260,r),"invalid end");
   Check(!SP_Evaluate(D'2026.10.14',0,1230,128,true,1260,r),"invalid mask");
   Check(!SP_Evaluate(D'2026.10.14',0,1230,62,true,1440,r),"invalid Friday time");
   Check(SP_Evaluate(D'2026.10.14 12:00:00',0,1230,0,true,1260,r) && !r.entry_open,"empty weekday mask blocks");
   Check(SP_Evaluate(D'2026.10.16 19:00:00',0,1440,62,true,1260,r) && !r.entry_open && r.friday_close_due,"Friday cutoff overrides later session end");
   PrintFormat("T009 SESSION TEST finished: %d passed, %d failed",passed,failed);
  }
