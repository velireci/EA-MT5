// T011 demo open-position guard test (FAKE port only): OPG_Run from include/DemoOpenGuard.mqh with the real ExitStateFile layer (sandbox file VELO_T011_DEMOTEST_OPEN_INTENT.txt,
// deleted before and after BY THIS TEST ONLY) and the instance lock (terminal temporary global variable VELO_T011_LOCKTEST_OPEN, removed at the end). Mirrors tests/test_t011_demo.py (OpenGuard).
// NEVER includes the real transport; no order, no position read, no trade. NOT YET COMPILED OR RUN (UNVERIFIED).
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/DemoOpenGuard.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
#define FN "VELO_T011_DEMOTEST_OPEN_INTENT.txt"
#define KEY "VELO_T011_LOCKTEST_OPEN"
#define TXT "INTENT-TEXT"

class CFakePort : public COpenPort
  {
public:
   int               positions;
   int               orders;
   bool              precheck;
   int               sends;
   int               scans;
   bool              shows_position_after_send;
   bool              nested;          // run a second instance at the moment of this instance's scan (it arrives while the lock is held)
   bool              nested_sent;
   string            nested_reason;
   CFakePort(void) {positions=0; orders=0; precheck=true; sends=0; scans=0; shows_position_after_send=false; nested=false; nested_sent=false; nested_reason="";}
   virtual int CountPositions(void)
     {
      scans++;
      if(nested)
        {
         nested=false;
         CFakePort inner;
         SOpenOutcome oi;
         nested_sent=OPG_Run(inner,KEY,FN,TXT,oi);
         nested_reason=oi.reason;
         if(inner.sends!=0 || inner.scans!=0) nested_sent=true;
        }
      return(positions);
     }
   virtual int CountOrders(void) {return(orders);}
   virtual bool PreCheck(void) {return(precheck);}
   virtual void Send(string &detail)
     {
      sends++;
      detail="fake send";
      if(shows_position_after_send) positions++;
     }
  };

void Clean(void)
  {
   if(FileIsExist(FN)) FileDelete(FN);
  }
bool LockFree(void)
  {
   bool held=false;
   string why;
   bool got=EL_Acquire(KEY,held,why);
   EL_Release(KEY,held);
   return(got);
  }
bool Has(const string text,const string part) {return(StringFind(text,part)>=0);}

void TestOneRun(void)
  {
   Clean();
   CFakePort p;
   SOpenOutcome o;
   bool r=OPG_Run(p,KEY,FN,TXT,o);
   Check(r && o.sent && o.sends==1 && p.sends==1 && p.scans==1,"one run: scanned once inside the lock, ONE send");
   string back="";
   Check(ESF_Exists(FN) && ESF_ReadAll(FN,back) && back==TXT,"the intent was written before the send and stays on disk");
   Check(LockFree(),"the lock is released after the run");
  }
void TestTwoInstances(void)
  {
   Clean();
   CFakePort a,b;
   SOpenOutcome oa,ob;
   OPG_Run(a,KEY,FN,TXT,oa);
   OPG_Run(b,KEY,FN,TXT,ob);        // instance 2 saw "no position" earlier and takes the lock only now
   Check(oa.sent && !ob.sent && a.sends==1 && b.sends==0,"two instances that both saw no position: only ONE open");
   Check(Has(ob.reason,"OPEN_INTENT_EXISTS") && b.scans==0,"the second one is blocked inside the lock by the intent, before any scan or send");
   Clean();
   CFakePort c;
   c.positions=1;
   SOpenOutcome oc;
   OPG_Run(c,KEY,FN,TXT,oc);
   Check(!oc.sent && c.sends==0 && Has(oc.reason,"A_POSITION_WITH_THIS_MAGIC_ALREADY_EXISTS") && !ESF_Exists(FN),"a visible position blocks inside the lock and nothing is written");
   Clean();
   CFakePort d,n;
   d.nested=true;
   SOpenOutcome od;
   OPG_Run(d,KEY,FN,TXT,od);
   Check(od.sent && d.sends==1 && !d.nested_sent && Has(d.nested_reason,"INSTANCE_LOCK_HELD"),"an instance that arrives while the lock is held does nothing");
   Check(LockFree(),"the lock is free after the nested case");
  }
void TestBlocks(void)
  {
   Clean();
   CFakePort o1;
   o1.orders=1;
   SOpenOutcome r1;
   OPG_Run(o1,KEY,FN,TXT,r1);
   Check(!r1.sent && o1.sends==0 && Has(r1.reason,"AN_ORDER_WITH_THIS_MAGIC_ALREADY_EXISTS") && !ESF_Exists(FN),"a pending order blocks inside the lock");
   CFakePort u1,u2;
   u1.positions=-1;
   u2.orders=-1;
   SOpenOutcome r2,r3;
   OPG_Run(u1,KEY,FN,TXT,r2);
   OPG_Run(u2,KEY,FN,TXT,r3);
   Check(!r2.sent && !r3.sent && u1.sends==0 && u2.sends==0 && !ESF_Exists(FN),"unreadable positions or orders block");
   CFakePort pc;
   pc.precheck=false;
   SOpenOutcome r4;
   OPG_Run(pc,KEY,FN,TXT,r4);
   Check(!r4.sent && pc.sends==0 && !ESF_Exists(FN),"a failed pre-check persists nothing and sends nothing");
   Check(LockFree(),"every blocked run released the lock");
  }
void TestRestart(void)
  {
   Clean();
   CFakePort first;
   SOpenOutcome of;
   OPG_Run(first,KEY,FN,TXT,of);       // sent; no position is visible (uncertain response)
   Check(of.sent && first.positions==0,"the first run sent and shows no position (uncertain)");
   bool all_blocked=true;
   for(int i=0;i<3;i++)
     {
      CFakePort again;
      SOpenOutcome oa;
      OPG_Run(again,KEY,FN,TXT,oa);
      if(oa.sent || again.sends!=0 || !Has(oa.reason,"OPEN_INTENT_EXISTS")) all_blocked=false;
     }
   string back="";
   Check(all_blocked && ESF_ReadAll(FN,back) && back==TXT,"restarts stay blocked while the intent exists, which no code removes or rewrites");
   Clean();
   ESF_WriteAll(FN,"");
   CFakePort half;
   SOpenOutcome oh;
   OPG_Run(half,KEY,FN,TXT,oh);
   Check(!oh.sent && half.sends==0,"a half-written (empty) intent file also blocks");
  }
void TestIntentContent(void)
  {
   string t=OPG_IntentText(5001234,"Srv",  "XAUUSD",777,1,0.1,1995.0,2010.0,2,20);
   Check(Has(t,"VELO_T011_OPEN_INTENT") && Has(t,"MAGIC=777") && Has(t,"DIRECTION=1") && Has(t,"STATE=INTENT_WRITTEN_BEFORE_THE_SEND") && Has(t,"CRC="),"the intent text names what is about to be sent and carries a checksum");
   Check(OPG_IntentName(5001234,777)=="VELO_T011_DEMO_OPEN_INTENT_5001234_777.txt" && OPG_LockKey(5001234,777)=="VELO_T011_LOCK_OPEN_5001234_777","file and lock names are per account and magic");
  }
void OnStart()
  {
   Print("T011 DEMO OPEN GUARD TEST: fake port only; sandbox file VELO_T011_DEMOTEST_OPEN_INTENT.txt; test lock variable VELO_T011_LOCKTEST_OPEN; no order, no position read, no trade.");
   TestOneRun();
   TestTwoInstances();
   TestBlocks();
   TestRestart();
   TestIntentContent();
   Clean();
   GlobalVariableDel(KEY);
   Check(!FileIsExist(FN),"the test leaves no file behind");
   PrintFormat("T011 DEMO OPEN GUARD TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
