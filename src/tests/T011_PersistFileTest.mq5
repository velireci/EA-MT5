// T011 persistence FILE test (controlled, sandbox): ExitStateFile.mqh over the terminal's MQL5/Files folder. Uses files named VELO_T011_PERSIST_SELFTEST_*.state
// (+ ".tmp") that belong ONLY to this test; it deletes them before and after. It touches no other file, sends no order, reads no broker data and uses no
// clock. Verifies the real behaviour of FileOpen / FileWriteArray / FileReadArray / FileMove / FileDelete that the Python model only assumes (UNVERIFIED until the
// owner runs it). It does NOT prove atomicity: it checks the protocol steps and the detection of damage.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/ExitStateFile.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
#define FN "VELO_T011_PERSIST_SELFTEST_A.state"
#define FN2 "VELO_T011_PERSIST_SELFTEST_B.state"
#define POS 987654
SEsIdentity Ident()
  {
   SEsIdentity i;
   i.server="MetaQuotes-Demo";
   i.login=5001234;
   i.symbol="XAUUSD.r";
   i.position_id=POS;
   return(i);
  }
void Clean(const string name)
  {
   if(FileIsExist(name)) FileDelete(name);
   if(FileIsExist(name+ESF_TMP_SUFFIX)) FileDelete(name+ESF_TMP_SUFFIX);
  }
void Pending(SEaState &s)
  {
   EA_StateInit(s);
   SEaResult r;
   EA_OnQuote(s,POS,1,4310.5,4310.6,4310.9,0.5,0.5,0.01,0.01,100.0,r);
  }
void MakeRec(SEsRecord &r,const int gen,const SEaState &s,const int phase)
  {
   ESC_RecordInit(r);
   r.generation=gen;
   r.id=Ident();
   r.state=s;
   r.send_phase=phase;
   if(phase==ESC_SEND_MAPPED)
     {
      r.n_orders=1;
      r.orders[0]=111222;
     }
  }
void TestRaw(void)
  {
   Clean(FN);
   string text="LINE1\nLINE2=%0041\n",back;
   Check(ESF_WriteAll(FN,text),"raw write");
   Check(ESF_ReadAll(FN,back) && back==text,"raw read returns exactly the bytes written");
   Check(ESF_WriteAll(FN,""),"empty write");
   Check(ESF_ReadAll(FN,back) && back=="","an empty file reads back empty");
   Clean(FN);
  }
void TestSaveLoad(void)
  {
   Clean(FN);
   SEsIdentity id=Ident();
   SEaState st;
   SEsRestore o;
   ESF_Load(FN,id,st,o);
   Check(o.verdict==ESC_RECOVERY_REQUIRED && st.status==EA_ST_BLOCKED && !o.new_request_allowed,"missing file: RECOVERY_REQUIRED and blocked");
   string why;
   Check(ESF_InitFresh(FN,id,why),"init fresh creates the IDLE record ("+why+")");
   Check(!ESF_InitFresh(FN,id,why),"init fresh never overwrites");
   ESF_Load(FN,id,st,o);
   Check(o.verdict==ESC_USABLE_IDLE && o.new_request_allowed && o.generation==1,"IDLE restored from the real file");
   SEaState p;
   Pending(p);
   SEsRecord r;
   MakeRec(r,3,p,ESC_SEND_INTENT);
   Check(!ESF_Save(FN,r,why),"a generation that is not the next is refused ("+why+")");
   MakeRec(r,2,p,ESC_SEND_INTENT);
   Check(ESF_Save(FN,r,why),"PENDING + INTENT saved and verified ("+why+")");
   Check(!FileIsExist(FN+ESF_TMP_SUFFIX),"no temporary file is left after a save");
   ESF_Load(FN,id,st,o);
   Check(o.verdict==ESC_RECOVERY_REQUIRED && st.status==EA_ST_NEEDS_RECONCILIATION && o.n_orders==0,"intent without a map restores as an uncertain send");
   MakeRec(r,3,p,ESC_SEND_MAPPED);
   Check(ESF_Save(FN,r,why),"PENDING + MAPPED saved over the previous generation ("+why+")");
   ESF_Load(FN,id,st,o);
   Check(o.verdict==ESC_USABLE_REQUEST && st.status==EA_ST_REQUEST_PENDING && o.n_orders==1 && o.orders[0]==111222 && o.generation==3,"pending request with its order map restored");
   SEaResult res;
   Check(!EA_OnQuote(st,POS,1,4310.5,4320.0,4320.3,0.5,0.5,0.01,0.01,100.0,res) && res.event==EA_EV_IGNORED,"after the restart no second request is produced");
   SEsIdentity other=id;
   other.position_id=POS+1;
   ESF_Load(FN,other,st,o);
   Check(o.verdict==ESC_RECOVERY_REQUIRED && StringFind(o.reason,"IDENTITY_MISMATCH")>=0,"another identity is rejected");
   other=id;
   other.login=1;
   ESF_Load(FN,other,st,o);
   Check(o.verdict==ESC_RECOVERY_REQUIRED,"another account is rejected");
   Clean(FN);
  }
void TestDamage(void)
  {
   Clean(FN);
   SEsIdentity id=Ident();
   SEaState p,st;
   SEsRestore o;
   Pending(p);
   SEsRecord r;
   string why,text;
   MakeRec(r,1,p,ESC_SEND_MAPPED);
   Check(ESF_Save(FN,r,why),"a first record with generation 1 can hold a request ("+why+")");
   ESC_Encode(r,text,why);
   int n=StringLen(text);
   int cuts[4];
   cuts[0]=0;
   cuts[1]=1;
   cuts[2]=n/2;
   cuts[3]=n-1;
   for(int i=0;i<4;i++)
     {
      ESF_WriteAll(FN,StringSubstr(text,0,cuts[i]));
      ESF_Load(FN,id,st,o);
      Check(o.verdict==ESC_RECOVERY_REQUIRED && st.status==EA_ST_BLOCKED && !o.new_request_allowed,"file truncated to "+IntegerToString(cuts[i])+" characters: blocked, no request");
     }
   string edited=text;
   StringReplace(edited,"STATUS=1","STATUS=0");
   ESF_WriteAll(FN,edited);
   ESF_Load(FN,id,st,o);
   Check(o.verdict==ESC_RECOVERY_REQUIRED && StringFind(o.reason,"CRC_MISMATCH")>=0,"an edited file is rejected by the checksum");
   Check(!ESF_Save(FN,r,why),"saving over a damaged file is refused ("+why+")");
   ESF_WriteAll(FN,text);
   ESF_WriteAll(FN+ESF_TMP_SUFFIX,StringSubstr(text,0,n/2));
   ESF_Load(FN,id,st,o);
   Check(o.verdict==ESC_RECOVERY_REQUIRED && StringFind(o.reason,"LEFTOVER_TMP")>=0 && st.status==EA_ST_BLOCKED,"a leftover temporary file blocks the restart");
   MakeRec(r,2,p,ESC_SEND_MAPPED);
   Check(!ESF_Save(FN,r,why) && StringFind(why,"LEFTOVER_TMP")>=0,"and blocks a new save until recovered");
   FileDelete(FN+ESF_TMP_SUFFIX);
   Check(ESF_Save(FN,r,why),"after the operator removes it the save works ("+why+")");
   Clean(FN);
  }
void TestIsolation(void)
  {
   Clean(FN);
   Clean(FN2);
   SEsIdentity id=Ident();
   string why;
   Check(ESF_InitFresh(FN,id,why) && ESF_InitFresh(FN2,id,why),"two test files are independent");
   FileDelete(FN);
   Check(FileIsExist(FN2) && !FileIsExist(FN),"deleting one does not touch the other");
   Check(ESF_FileName(5001234,POS)=="VELO_T011_EXIT_5001234_987654.state","production file name is per login and position (never the test names)");
   Clean(FN);
   Clean(FN2);
  }
void OnStart()
  {
   Print("T011 PERSIST FILE TEST: sandbox files VELO_T011_PERSIST_SELFTEST_* only; no order, no broker read.");
   TestRaw();
   TestSaveLoad();
   TestDamage();
   TestIsolation();
   Clean(FN);
   Clean(FN2);
   Check(!FileIsExist(FN) && !FileIsExist(FN2) && !FileIsExist(FN+ESF_TMP_SUFFIX),"the test leaves no file behind");
   PrintFormat("T011 PERSIST FILE TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
