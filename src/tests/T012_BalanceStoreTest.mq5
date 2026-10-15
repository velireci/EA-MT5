// T012 day-balance store test (FAKE port only; in-memory files, no real file, no account read, no order). DBS_Load / DBS_Capture over DailyBalanceStore.mqh with CDbsPort test double.
// Mirrors tests/test_t012_balance.py; the rows below are the generated scenario table of tests/t012_balance_fixtures.py (equality is tested). NOT YET COMPILED OR RUN (UNVERIFIED).
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/DailyBalanceStore.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
#define NF 24
#define K_MISSING 0
#define K_VALID_WE 1
#define K_VALID_OA 2
#define K_CRC 3
#define K_TRUNC 4
#define K_EMPTY 5
#define K_BAD_VERSION 6
#define K_BAD_ENUM 7
#define K_AMOUNT_ZERO 8
#define K_OTHER_LOGIN 9
#define K_OTHER_SERVER 10
#define K_OTHER_CURRENCY 11
#define K_DAY_INSIDE_PREV 12
#define K_OUTSIDE_DAY 13
#define K_WE_NOT_COMPLETE 14
#define K_COMPLETE_BIG 15
#define K_OFFSET_BIG 16
#define K_DAY_BIG 17
// BEGIN GENERATED FIXTURES (tests/t012_balance_fixtures.py emit_mql)
#define NROWS 70
#define MAXSET 6
#define T_START 1792015200
#define T_END 1792101600
#define T_DAY 20261015
string R_NAME[]={"LOAD_MISSING_FILE_IS_NONE_AND_NOTHING_IS_CREATED","LOAD_VALID_WINDOW_EMPTY","LOAD_VALID_OWNER_ASSERTED_STAYS_DISTINCT","LOAD_RESTART_INSIDE_THE_DAY_KEEPS_THE_STORED_AMOUNT","LOAD_NEXT_DAY_DOES_NOT_CARRY_THE_OLD_BALANCE","LOAD_RECORD_OF_ANOTHER_DAY_IN_TODAYS_FILE","LOAD_DAMAGED_CRC","LOAD_TRUNCATED","LOAD_EMPTY_FILE","LOAD_OLD_VERSION","LOAD_UNKNOWN_SOURCE","LOAD_ZERO_AMOUNT","LOAD_INSTANT_OUTSIDE_THE_DAY","LOAD_WINDOW_EMPTY_WITHOUT_THE_COMPLETE_ASSERTION","LOAD_COMPLETE_FLAG_4294967297_WITH_A_VALID_CRC_IS_REFUSED","LOAD_OFFSET_ABOVE_32_BITS_WITH_A_VALID_CRC_IS_REFUSED","LOAD_DAY_ABOVE_32_BITS_WITH_A_VALID_CRC_IS_REFUSED","LOAD_OTHER_LOGIN","LOAD_OTHER_SERVER","LOAD_OTHER_CURRENCY","LOAD_FILE_EXISTS_BUT_CANNOT_BE_READ","LOAD_ACCOUNT_UNREADABLE","LOAD_CURRENCY_UNKNOWN","CAPTURE_WE_EMPTY_WINDOW_AT_00_00_05","CAPTURE_WE_EMPTY_WINDOW_AT_15_00","CAPTURE_WE_ONE_DEAL_IN_THE_WINDOW_IS_MID_DAY","CAPTURE_WE_ANY_DEAL_OF_ANY_MAGIC_OR_TYPE_COUNTS","CAPTURE_WE_HISTORY_UNKNOWN","CAPTURE_WE_HISTORY_BLOCK","CAPTURE_WE_HISTORY_NOT_COMPLETE","CAPTURE_WE_COMPLETE_NOT_ASSERTED_NOTHING_IS_READ","CAPTURE_WE_OFFSET_NOT_ASSERTED","CAPTURE_WE_OFFSET_INVALID","CAPTURE_WE_BALANCE_UNREADABLE","CAPTURE_WE_BALANCE_ZERO","CAPTURE_WE_BALANCE_NEGATIVE","CAPTURE_WE_BALANCE_CHANGES_BETWEEN_THE_TWO_READS","CAPTURE_WE_SECOND_BALANCE_READ_FAILS","CAPTURE_WE_MIDNIGHT_CROSSED_WITHIN_THE_SPAN","CAPTURE_WE_ACQUISITION_TOO_SLOW","CAPTURE_WE_CLOCK_GOES_BACKWARDS","CAPTURE_WE_HISTORY_OF_ANOTHER_DAY","CAPTURE_WE_HISTORY_WINDOW_ENDS_BEFORE_THE_INSTANT","CAPTURE_WE_HISTORY_WINDOW_STARTS_AFTER_THE_INSTANT","CAPTURE_WE_ACCOUNT_UNREADABLE","CAPTURE_WE_LOCK_HELD_NOTHING_IS_READ_OR_WRITTEN","CAPTURE_WE_EXISTING_VALID_IS_RETURNED_NOT_OVERWRITTEN","CAPTURE_WE_EXISTING_OWNER_VALUE_IS_NEVER_REPLACED_BY_A_PROOF","CAPTURE_WE_EXISTING_DAMAGED_IS_NEVER_OVERWRITTEN","CAPTURE_WE_EXISTING_TRUNCATED_IS_NEVER_OVERWRITTEN","CAPTURE_WE_EXISTING_EMPTY_PARTIAL_IS_NEVER_OVERWRITTEN","CAPTURE_WE_EXISTING_OF_ANOTHER_ACCOUNT_IS_NEVER_OVERWRITTEN","CAPTURE_WE_EXISTING_WITH_ANOTHER_CURRENCY","CAPTURE_WE_EXISTING_UNREADABLE_IS_NEVER_OVERWRITTEN","CAPTURE_WE_WRITE_FAILS_WITH_A_PARTIAL_FILE","CAPTURE_WE_WRITE_FAILS_WITHOUT_A_FILE","CAPTURE_WE_READBACK_DIFFERS","CAPTURE_WE_READBACK_UNREADABLE","CAPTURE_WE_NEXT_DAY_STARTS_FROM_ZERO_AND_LEAVES_THE_OLD_FILE_ALONE","CAPTURE_OA_EXPLICIT_AMOUNT","CAPTURE_OA_DOES_NOT_NEED_AN_EMPTY_WINDOW_BUT_STAYS_DISTINCT","CAPTURE_OA_AMOUNT_MISSING","CAPTURE_OA_AMOUNT_NEGATIVE","CAPTURE_OA_AMOUNT_NOT_EXACT","CAPTURE_OA_DAY_NOT_THE_CURRENT_ONE","CAPTURE_OA_EXISTING_WINDOW_EMPTY_RECORD_IS_NOT_REPLACED","CAPTURE_OA_EXISTING_DAMAGED_IS_NOT_REPLACED","CAPTURE_OA_LOCK_HELD","CAPTURE_OA_WRITE_FAILS","CAPTURE_OA_READBACK_DIFFERS"};
int R_OP[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,2};
int R_START[]={0,1,2,1,1,12,3,4,5,6,7,8,13,14,15,16,17,9,10,11,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,9,11,1,0,0,0,0,1,0,0,0,0,0,0,1,3,0,0,0};
int S_N[]={0,0,0,3,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,2,4,3,3,3,3,3,1,1,2,3,4,4,3,3,4,4,4,3,3,3,3,3,2,2,2,2,2,2,2,3,3,3,3,3,6,1,2,1,1,1,2,1,1,2,2,2};
int S_KEY[]={-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4,6,13,-1,-1,-1,22,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,23,-1,-1,-1,-1,-1,0,-1,-1,-1,-1,-1,2,-1,-1,-1,-1,-1,18,19,-1,-1,-1,-1,18,19,13,14,-1,-1,18,19,12,-1,-1,-1,18,19,12,-1,-1,-1,18,19,7,-1,-1,-1,18,19,7,-1,-1,-1,18,19,8,-1,-1,-1,19,-1,-1,-1,-1,-1,18,-1,-1,-1,-1,-1,18,19,-1,-1,-1,-1,18,19,3,-1,-1,-1,18,19,4,6,-1,-1,18,19,4,6,-1,-1,18,19,6,-1,-1,-1,18,19,5,-1,-1,-1,18,19,13,14,-1,-1,18,19,13,14,-1,-1,18,19,13,14,-1,-1,18,19,9,-1,-1,-1,18,19,11,-1,-1,-1,18,19,10,-1,-1,-1,18,19,0,-1,-1,-1,18,19,15,-1,-1,-1,18,19,-1,-1,-1,-1,18,19,-1,-1,-1,-1,18,19,-1,-1,-1,-1,18,19,-1,-1,-1,-1,18,19,-1,-1,-1,-1,18,19,-1,-1,-1,-1,18,19,-1,-1,-1,-1,18,19,23,-1,-1,-1,18,19,16,-1,-1,-1,18,19,16,-1,-1,-1,18,19,17,-1,-1,-1,18,19,17,-1,-1,-1,18,19,22,9,10,11,20,-1,-1,-1,-1,-1,20,12,-1,-1,-1,-1,20,-1,-1,-1,-1,-1,20,-1,-1,-1,-1,-1,20,-1,-1,-1,-1,-1,20,21,-1,-1,-1,-1,20,-1,-1,-1,-1,-1,20,-1,-1,-1,-1,-1,20,15,-1,-1,-1,-1,20,16,-1,-1,-1,-1,20,17,-1,-1,-1,-1};
double S_VAL[]={0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,5000.0,5000.0,40000.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,54000.0,54003.0,0.0,0.0,1.0,7200.0,1.0,0.0,0.0,0.0,1.0,7200.0,7.0,0.0,0.0,0.0,1.0,7200.0,1.0,0.0,0.0,0.0,1.0,7200.0,2.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,7200.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,7201.0,0.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,-5.0,-5.0,0.0,0.0,1.0,7200.0,1000.5,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,86398.0,86403.0,0.0,0.0,1.0,7200.0,100.0,221.0,0.0,0.0,1.0,7200.0,100.0,99.0,0.0,0.0,1.0,7200.0,-1.0,0.0,0.0,0.0,1.0,7200.0,-86395.0,0.0,0.0,0.0,1.0,7200.0,100.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,0.0,0.0,0.0,0.0,1.0,7200.0,1.0,0.0,0.0,0.0,1.0,7200.0,1.0,0.0,0.0,0.0,1.0,7200.0,2.0,0.0,0.0,0.0,1.0,7200.0,1.0,0.0,0.0,0.0,1.0,7200.0,2.0,0.0,0.0,0.0,1.0,7200.0,1.0,1.0,86400.0,86400.0,1234.5,0.0,0.0,0.0,0.0,0.0,1234.5,9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,-3.0,0.0,0.0,0.0,0.0,0.0,1234.5678901234567,0.0,0.0,0.0,0.0,0.0,1234.5,-1.0,0.0,0.0,0.0,0.0,1234.5,0.0,0.0,0.0,0.0,0.0,1234.5,0.0,0.0,0.0,0.0,0.0,1234.5,0.0,0.0,0.0,0.0,0.0,1234.5,2.0,0.0,0.0,0.0,0.0,1234.5,1.0,0.0,0.0,0.0,0.0};
string X_STATUS[]={"NONE","USABLE","USABLE","USABLE","NONE","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","UNKNOWN","UNKNOWN","USABLE","USABLE","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","USABLE","USABLE","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","BLOCK","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","USABLE","USABLE","USABLE","UNKNOWN","UNKNOWN","UNKNOWN","UNKNOWN","USABLE","BLOCK","UNKNOWN","UNKNOWN","UNKNOWN"};
string X_REASON[]={"NO_RECORD","","","","NO_RECORD","WRONG_DAY_IN_RECORD","DAMAGED: CRC_MISMATCH","DAMAGED","DAMAGED: EMPTY","UNSUPPORTED_VERSION","BAD_ENUM","INVALID_AMOUNT","INVALID_INSTANT","INVALID_WINDOW_EMPTY_EVIDENCE","DAMAGED","DAMAGED","DAMAGED","WRONG_ACCOUNT","WRONG_ACCOUNT","WRONG_ACCOUNT","FILE_UNREADABLE","ACCOUNT_UNREADABLE","ACCOUNT_UNREADABLE","","","MID_DAY_NOT_PROVEN","MID_DAY_NOT_PROVEN","HISTORY_NOT_READY","HISTORY_NOT_READY","HISTORY_NOT_COMPLETE","HISTORY_COMPLETE_NOT_ASSERTED","OFFSET_NOT_ASSERTED","OFFSET_INVALID","BALANCE_UNREADABLE","BALANCE_UNREADABLE","BALANCE_UNREADABLE","BALANCE_CHANGED_DURING_ACQUISITION","BALANCE_UNREADABLE","DAY_CHANGED_DURING_ACQUISITION","ACQUISITION_TOO_SLOW","CLOCK_WENT_BACKWARDS","HISTORY_DAY_DIFFERS","HISTORY_DOES_NOT_COVER_THE_INSTANT","HISTORY_DOES_NOT_COVER_THE_INSTANT","ACCOUNT_UNREADABLE","LOCK_FAILED","ALREADY_CAPTURED","ALREADY_CAPTURED","DAMAGED","DAMAGED","DAMAGED","WRONG_ACCOUNT","WRONG_ACCOUNT","FILE_UNREADABLE","WRITE_FAILED","WRITE_FAILED","READBACK_FAILED","READBACK_FAILED","","","","OWNER_AMOUNT_INVALID","OWNER_AMOUNT_INVALID","OWNER_AMOUNT_INVALID","OWNER_DAY_MISMATCH","ALREADY_CAPTURED","DAMAGED","LOCK_FAILED","WRITE_FAILED","READBACK_FAILED"};
string X_SOURCE[]={"","WINDOW_EMPTY","OWNER_ASSERTED","WINDOW_EMPTY","","","","","","","","","","","","","","","","","","","","WINDOW_EMPTY","WINDOW_EMPTY","","","","","","","","","","","","","","","","","","","","","","WINDOW_EMPTY","OWNER_ASSERTED","","","","","","","","","","","WINDOW_EMPTY","OWNER_ASSERTED","OWNER_ASSERTED","","","","","WINDOW_EMPTY","","","",""};
double X_AMOUNT[]={0.0,999.0,777.0,999.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1000.0,1000.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,999.0,777.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1000.0,1234.5,1234.5,0.0,0.0,0.0,0.0,999.0,0.0,0.0,0.0,0.0};
int X_WRITES[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0,0,0,1,1};
int X_READS[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,2,1,1,1,0,0,0,1,1,1,2,2,2,2,2,2,2,2,0,0,0,0,0,0,0,0,0,0,2,2,2,2,2,0,0,0,0,0,0,0,0,0,0,0};
string X_DISK[]={"MISSING","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","NEW","NEW","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","SAME","SAME","SAME","SAME","SAME","SAME","SAME","SAME","PARTIAL","MISSING","NEW","NEW","NEWDAY","NEW","NEW","MISSING","MISSING","MISSING","MISSING","SAME","SAME","MISSING","MISSING","NEW"};
// END GENERATED FIXTURES
#define OFF 7200
class CFakePort : public CDbsPort
  {
public:
   double            s[NF];
   string            f_name[4];
   string            f_text[4];
   int               nf;
   int               now_calls,bal_calls,writes,locks_ok,unlocks;
   bool              held,after_write,has_start;
   string            start_text;
   CFakePort(void)
     {
      for(int i=0;i<NF;i++)
         s[i]=0.0;
      s[0]=1.0;
      s[1]=5001234.0;
      s[3]=1.0;
      s[4]=1000.0;
      s[5]=1.0;
      s[6]=1000.0;
      s[8]=1.0;
      s[13]=5.0;
      s[14]=7.0;
      s[15]=1.0;
      s[19]=(double)DBS_OFFSET_UNSET;
      nf=0;
      now_calls=0;
      bal_calls=0;
      writes=0;
      locks_ok=0;
      unlocks=0;
      held=false;
      after_write=false;
      has_start=false;
      start_text="";
     }
   int Find(const string name)
     {
      for(int i=0;i<nf;i++)
         if(f_name[i]==name) return(i);
      return(-1);
     }
   void Put(const string name,const string text)
     {
      int i=Find(name);
      if(i<0)
        {
         i=nf;
         nf++;
         f_name[i]=name;
        }
      f_text[i]=text;
     }
   virtual void ReadAccount(SDbsAccount &a)
     {
      a.read_ok=(s[0]!=0.0);
      a.login=(long)s[1];
      a.server="MetaQuotes-Demo";
      a.currency=(s[2]!=0.0 ? "" : "EUR");
     }
   virtual bool ReadBalance(double &amount)
     {
      bal_calls++;
      bool first=(bal_calls==1);
      amount=(first ? s[4] : s[6]);
      return(first ? s[3]!=0.0 : s[5]!=0.0);
     }
   virtual long NowUtc(void)
     {
      now_calls++;
      double off=(now_calls==1 ? s[13] : s[14]);
      return((long)T_START+(long)off+(long)s[22]*86400);
     }
   virtual void ReadHistory(const long utc,SDbsHist &h)
     {
      int v=(int)s[7];
      h.verdict=(v==0 ? DH_READY : (v==1 ? DH_UNKNOWN : DH_BLOCK));
      h.complete=(s[8]!=0.0);
      h.day_key=T_DAY+(int)s[9];
      h.window_start=(long)T_START+(long)s[10];
      h.window_end=(long)T_END+(long)s[11];
      h.deals_in_window=(int)s[12];
     }
   virtual bool Lock(const string key)
     {
      if(s[15]==0.0) return(false);
      held=true;
      locks_ok++;
      return(true);
     }
   virtual void Unlock(const string key)
     {
      unlocks++;
      held=false;
     }
   virtual bool Exists(const string name) {return(Find(name)>=0);}
   virtual bool ReadFile(const string name,string &text)
     {
      text="";
      int i=Find(name);
      if(i<0 || s[23]!=0.0) return(false);
      if(after_write)
        {
         if(s[17]==2.0) return(false);
         if(s[17]==1.0) {text=f_text[i]+"x"; return(true);}
        }
      text=f_text[i];
      return(true);
     }
   virtual bool WriteFile(const string name,const string text)
     {
      writes++;
      after_write=true;
      if(s[16]==1.0) {Put(name,StringSubstr(text,0,StringLen(text)/2)); return(false);}
      if(s[16]==2.0) return(false);
      Put(name,text);
      return(true);
     }
  };
string Reseal(const string text,const string old,const string repl)
  {
   string body=StringSubstr(text,0,StringFind(text,"CRC="));
   StringReplace(body,old,repl);
   return(body+"CRC="+StringFormat("%08X",ESC_Crc32(body))+"\n");
  }
string Enc(const long login,const string server,const string currency,const int day,const double amount,const string source,const int comp,const int off,const long tf,const long tl)
  {
   SDbsRecord r;
   r.login=login;
   r.server=server;
   r.currency=currency;
   r.day=day;
   r.amount=amount;
   r.source=source;
   r.complete_asserted=comp;
   r.offset=off;
   r.t_first=tf;
   r.t_last=tl;
   string text,why;
   if(!DBS_Encode(r,text,why)) {Print("FAIL fixture record not encodable: ",why); g_fail++; return("");}
   return(text);
  }
// the file that exists before the operation (kind K_MISSING = no file)
void MakeStart(const int kind,CFakePort &port)
  {
   if(kind==K_MISSING) return;
   long L=5001234;
   string S="MetaQuotes-Demo",C="EUR";
   string text=Enc(L,S,C,T_DAY,999.0,DBS_SRC_WE,1,OFF,T_START+3600,T_START+3602);
   switch(kind)
     {
      case K_VALID_WE: break;
      case K_VALID_OA: text=Enc(L,S,C,T_DAY,777.0,DBS_SRC_OA,0,0,T_START+3600,T_START+3600); break;
      case K_CRC: StringReplace(text,"AMOUNT=999.000000000000","AMOUNT=998.000000000000"); break;
      case K_TRUNC: text=StringSubstr(text,0,StringLen(text)/2); break;
      case K_EMPTY: text=""; break;
      case K_BAD_VERSION: text=Reseal(text,"VERSION=1","VERSION=2"); break;
      case K_BAD_ENUM: text=Reseal(text,"SOURCE=WINDOW_EMPTY","SOURCE=SOMETHING"); break;
      case K_AMOUNT_ZERO: text=Reseal(text,"AMOUNT=999.000000000000","AMOUNT=0.000000000000"); break;
      case K_OTHER_LOGIN: text=Enc(1,S,C,T_DAY,999.0,DBS_SRC_WE,1,OFF,T_START+3600,T_START+3602); break;
      case K_OTHER_SERVER: text=Enc(L,"Other-Server",C,T_DAY,999.0,DBS_SRC_WE,1,OFF,T_START+3600,T_START+3602); break;
      case K_OTHER_CURRENCY: text=Enc(L,S,"USD",T_DAY,999.0,DBS_SRC_WE,1,OFF,T_START+3600,T_START+3602); break;
      case K_DAY_INSIDE_PREV: text=Enc(L,S,C,T_DAY-1,999.0,DBS_SRC_WE,1,OFF,T_START-7200,T_START-7198); break;
      case K_OUTSIDE_DAY: text=Reseal(text,"T_FIRST_UTC="+IntegerToString(T_START+3600)+"\nT_LAST_UTC="+IntegerToString(T_START+3602),"T_FIRST_UTC="+IntegerToString(T_END+10)+"\nT_LAST_UTC="+IntegerToString(T_END+12)); break;
      case K_WE_NOT_COMPLETE: text=Reseal(text,"HISTORY_COMPLETE_ASSERTED=1","HISTORY_COMPLETE_ASSERTED=0"); break;
      case K_COMPLETE_BIG: text=Reseal(text,"HISTORY_COMPLETE_ASSERTED=1","HISTORY_COMPLETE_ASSERTED=4294967297"); break;       // 2^32 + 1: would be 1 after a narrowing cast
      case K_OFFSET_BIG: text=Reseal(text,"SERVER_OFFSET_SECONDS=7200","SERVER_OFFSET_SECONDS="+IntegerToString((long)7200+4294967296)); break;
      case K_DAY_BIG: text=Reseal(text,"DAY="+IntegerToString(T_DAY),"DAY="+IntegerToString((long)T_DAY+4294967296)); break;
     }
   port.Put(DBS_FileName(L,T_DAY),text);
   port.has_start=true;
   port.start_text=text;
  }
string DiskClass(CFakePort &port,const string expected)
  {
   long L=5001234;
   string name=DBS_FileName(L,T_DAY);
   SDbsRecord rec;
   string why;
   if(expected=="NEWDAY")
     {
      int i2=port.Find(DBS_FileName(L,T_DAY+1));
      int i1=port.Find(name);
      if(i2>=0 && i1>=0 && port.f_text[i1]==port.start_text && DBS_Decode(port.f_text[i2],rec,why) && rec.day==T_DAY+1) return("NEWDAY");
      return("BAD");
     }
   int i=port.Find(name);
   if(i<0) return("MISSING");
   if(port.has_start && port.f_text[i]==port.start_text) return("SAME");
   return(DBS_Decode(port.f_text[i],rec,why) ? "NEW" : "PARTIAL");
  }
// an EMPTY expectation means "no condition on the text" (as in the Python table); a non-empty one must really be found in the reason
bool ReasonOk(const string expected,const string reason)
  {
   if(expected=="") return(true);
   return(StringFind(reason,expected)>=0);
  }
void TestReasonOk(void)
  {
   Check(ReasonOk("",""),"empty expectation / empty reason: no condition");
   Check(ReasonOk("","anything"),"empty expectation / some text: no condition");
   Check(ReasonOk("MISSING","DAMAGED: MISSING field"),"a present text is found");
   Check(!ReasonOk("MISSING","DAMAGED: other"),"an absent text fails");
   Check(!ReasonOk("MISSING",""),"a non-empty expectation fails against an empty reason");
  }
void RunRows(void)
  {
   for(int i=0;i<NROWS;i++)
     {
      string tag=R_NAME[i]+": ";
      CFakePort port;
      for(int k=0;k<S_N[i];k++)
         port.s[S_KEY[i*MAXSET+k]]=S_VAL[i*MAXSET+k];
      MakeStart(R_START[i],port);
      SDbsResult res;
      if(R_OP[i]==0) DBS_Load(port,res);
      else
        {
         SDbsAsserts a;
         a.complete=(port.s[18]!=0.0);
         a.offset=(int)port.s[19];
         if(R_OP[i]==1) DBS_Capture(port,DBS_SRC_WE,a,0.0,0,res);
         else DBS_Capture(port,DBS_SRC_OA,a,port.s[20],T_DAY+(int)port.s[21],res);
        }
      Print(tag,DBS_StatusName(res.status)," | ",res.reason);
      Check(DBS_StatusName(res.status)==X_STATUS[i],tag+"status "+DBS_StatusName(res.status));
      Check(ReasonOk(X_REASON[i],res.reason),tag+"reason contains '"+X_REASON[i]+"' got '"+res.reason+"'");
      Check(res.source==X_SOURCE[i] && res.balance.amount==X_AMOUNT[i],tag+"source '"+res.source+"' and amount "+DoubleToString(res.balance.amount,6));
      Check(port.writes==X_WRITES[i] && port.bal_calls==X_READS[i],tag+"writes "+IntegerToString(port.writes)+" and balance reads "+IntegerToString(port.bal_calls));
      string dc=DiskClass(port,X_DISK[i]);
      Check(dc==X_DISK[i],tag+"file afterwards "+dc);
      Check(res.balance.known==(res.status==DBS_USABLE),tag+"known only when usable");
      if(res.status==DBS_USABLE) Check(res.balance.day==T_DAY+(int)port.s[22],tag+"the balance carries its Tirane day");
      else Check(res.balance.amount==0.0 && !res.balance.known,tag+"an unusable result carries no amount");
      Check(!port.held && port.locks_ok==port.unlocks,tag+"the lock is released");
      // the preview feed: poisoned "manual" values must not survive; only a USABLE record gives a known balance, with its origin in the text
      SDbBalance fb;
      fb.known=true;
      fb.day=123;
      fb.amount=55.0;
      string ftxt=DBS_ForBridge(res,fb);
      if(res.status==DBS_USABLE)
         Check(fb.known && fb.day==res.balance.day && fb.amount==res.balance.amount && StringFind(ftxt,res.source)>=0 && StringFind(ftxt,"STORE_USABLE")==0,tag+"bridge feed: a usable record is a known balance and keeps its origin");
      else
         Check(!fb.known && fb.day==0 && fb.amount==0.0 && StringFind(ftxt,"STORE_"+DBS_StatusName(res.status))==0,tag+"bridge feed: anything else is an unknown balance and no earlier value survives");
      if(R_OP[i]==0) Check(port.writes==0 && port.locks_ok==0 && port.nf==(port.has_start ? 1 : 0),tag+"LOAD is read-only and lock-free and creates nothing");
      if(R_OP[i]!=0 && res.status==DBS_USABLE && X_DISK[i]=="NEW")
        {
         SDbsRecord rec;
         string why;
         int fi=port.Find(DBS_FileName(5001234,T_DAY));
         Check(fi>=0 && DBS_Decode(port.f_text[fi],rec,why) && rec.amount==res.balance.amount && rec.source==res.source,tag+"the stored record equals the result");
        }
     }
  }
void TestCodec(void)
  {
   string t1=Enc(5001234,"MetaQuotes-Demo","EUR",T_DAY,1000.0,DBS_SRC_WE,1,OFF,T_START+5,T_START+7);
   SDbsRecord r;
   string why;
   Check(t1!="" && DBS_Decode(t1,r,why) && r.login==5001234 && r.server=="MetaQuotes-Demo" && r.currency=="EUR" && r.day==T_DAY && r.amount==1000.0 && r.source==DBS_SRC_WE &&
         r.complete_asserted==1 && r.offset==OFF && r.t_first==T_START+5 && r.t_last==T_START+7,"codec: round trip of a WINDOW_EMPTY record");
   string t2=Enc(5001234,"A B=C%","E/R",T_DAY,1234.5,DBS_SRC_OA,0,0,T_START+5,T_START+5);
   SDbsRecord r2;
   string t2b;
   Check(t2!="" && DBS_Decode(t2,r2,why) && r2.server=="A B=C%" && r2.currency=="E/R" && DBS_Encode(r2,t2b,why) && t2b==t2,"codec: escaping round trip and canonical text of an OWNER_ASSERTED record");
   double nan=MathSqrt(-1.0);
   double inf=MathExp(1000.0);
   SDbsRecord bad;
   string text;
   bad=r;
   bad.amount=0.0;
   Check(!DBS_Encode(bad,text,why),"codec: amount 0 is never written");
   bad=r;
   bad.amount=-1.0;
   Check(!DBS_Encode(bad,text,why),"codec: negative amount is never written");
   bad=r;
   bad.amount=nan;
   Check(!DBS_Encode(bad,text,why),"codec: NaN is never written");
   bad=r;
   bad.amount=inf;
   Check(!DBS_Encode(bad,text,why),"codec: infinity is never written");
   bad=r;
   bad.amount=1.0000000000001234;
   Check(!DBS_Encode(bad,text,why),"codec: an amount that is not exact with 12 decimals is never written");
   bad=r;
   bad.complete_asserted=0;
   Check(!DBS_Encode(bad,text,why),"codec: WINDOW_EMPTY without the complete assertion is never written");
   bad=r;
   bad.offset=7201;
   Check(!DBS_Encode(bad,text,why),"codec: an invalid server offset is never written");
   bad=r;
   bad.t_last=T_START+5+121;
   Check(!DBS_Encode(bad,text,why),"codec: an acquisition longer than the limit is never written");
   bad=r;
   bad.t_first=T_START-5;
   Check(!DBS_Encode(bad,text,why),"codec: an instant outside the Tirane day is never written");
   bad=r2;
   bad.complete_asserted=1;
   Check(!DBS_Encode(bad,text,why),"codec: OWNER_ASSERTED with a complete assertion is never written");
   bool all_cut_rejected=true;
   for(int cut=0;cut<StringLen(t1)-1;cut+=7)
      if(DBS_Decode(StringSubstr(t1,0,cut),r,why)) all_cut_rejected=false;
   Check(all_cut_rejected,"codec: every truncation is rejected");
   string edited=t1;
   StringReplace(edited,"AMOUNT=1000","AMOUNT=1001");
   Check(!DBS_Decode(edited,r,why),"codec: an accidental edit is detected by the CRC");
   string forged=Reseal(t1,"AMOUNT=1000.000000000000","AMOUNT=2000.000000000000");
   Check(DBS_Decode(forged,r,why) && r.amount==2000.0,"codec: a deliberate edit with a recomputed CRC is ACCEPTED (documented limit: the CRC is not protection against editing)");
  }
void TestActions(void)
  {
   Check(DBS_ActionKnown(0) && DBS_ActionKnown(1) && DBS_ActionKnown(2),"the three declared actions are accepted");
   Check(!DBS_ActionKnown(99) && !DBS_ActionKnown(-1) && !DBS_ActionKnown(3) && !DBS_ActionKnown(2147483647) && !DBS_ActionKnown(-2147483647),"enum 99, -1 and every other value are refused before any read or write");
  }
void TestIdempotentAndMidnight(void)
  {
   CFakePort p1;
   p1.s[18]=1.0;
   p1.s[19]=(double)OFF;
   SDbsAsserts a;
   a.complete=true;
   a.offset=OFF;
   SDbsResult r1,r2;
   DBS_Capture(p1,DBS_SRC_WE,a,0.0,0,r1);
   p1.now_calls=0;
   p1.bal_calls=0;
   p1.s[4]=4242.0;
   p1.s[6]=4242.0;
   DBS_Capture(p1,DBS_SRC_WE,a,0.0,0,r2);
   Check(r1.status==DBS_USABLE && r2.status==DBS_USABLE && r1.balance.amount==1000.0 && r2.balance.amount==1000.0 && p1.writes==1 && p1.bal_calls==0 && StringFind(r2.reason,"ALREADY_CAPTURED")>=0,
         "a second capture returns the stored record unchanged and writes nothing, whatever the balance is now");
   // terminal closed at midnight, restarted at 09:00 with night deals: UNKNOWN, nothing subtracted, nothing written
   CFakePort p2;
   p2.s[13]=9.0*3600.0;
   p2.s[14]=9.0*3600.0+2.0;
   p2.s[12]=2.0;
   p2.s[4]=1100.0;
   p2.s[6]=1100.0;
   DBS_Capture(p2,DBS_SRC_WE,a,0.0,0,r1);
   Check(r1.status==DBS_UNKNOWN && !r1.balance.known && r1.balance.amount==0.0 && p2.writes==0 && p2.nf==0 && StringFind(r1.reason,"MID_DAY_NOT_PROVEN")>=0,"the midnight-closure case stays UNKNOWN: no reconstruction, no write");
  }
void OnStart()
  {
   Print("T012 BALANCE STORE TEST: fake port, in-memory files; no real file, no account read, no order.");
   TestReasonOk();
   RunRows();
   TestCodec();
   TestActions();
   TestIdempotentAndMidnight();
   PrintFormat("T012 BALANCE STORE TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
