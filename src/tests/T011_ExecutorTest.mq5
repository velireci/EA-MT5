// T011 executor test (FAKE transport only): EX_Process over ExitExecutor.mqh with CFakeTransport, the real ExitStateFile (sandbox file VELO_T011_EXEC_SELFTEST_A.state, deleted
// before and after), ExitActivation and ExitRestartFlow. Mirrors tests/test_t011_executor.py; the fixtures below are the hand-written scenario table of
// tests/t011_executor_fixtures.py (equality is tested). NEVER includes the real transport; no terminal read of positions, no order, no new trade. NOT YET COMPILED OR RUN (UNVERIFIED).
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/ExitExecutor.mqh"
#include "../include/ExitTransportFake.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
// BEGIN GENERATED FIXTURES (tests/t011_executor_fixtures.py emit_mql)
#define NROWS 89
#define PLAN_TWEAK_FIRST 39
string R_NAME[]={"REGRESSION_FILLING_INVALID_ZERO_SENDS_NO_NEW_INTENT","REGRESSION_FILTER_POLICY_INVALID_ZERO_SENDS_NO_NEW_INTENT","REGRESSION_FILTER_STATE_INVALID_ZERO_SENDS_NO_NEW_INTENT","REGRESSION_DIRECTION_INVALID_ZERO_SENDS_NO_NEW_INTENT","REGRESSION_SAVE_FAULT_INVALID_ZERO_SENDS_NO_NEW_INTENT","REGRESSION_LEVEL_OFF_GRID_BY_0_004_ZERO_SENDS_NO_NEW_INTENT","REGRESSION_TP_OFF_GRID_BY_0_004_ZERO_SENDS_NO_NEW_INTENT","REGRESSION_LEVEL_NOISY_NOT_REPRESENTABLE_ZERO_SENDS_NO_NEW_INTENT","REGRESSION_PRICE_ON_GRID_WITH_BINARY_NOISE_IS_ACCEPTED","PLAN_PLAN_LEVEL_CHANGED_ZERO_SENDS_NO_INTENT","PLAN_PLAN_TP_CHANGED_ZERO_SENDS_NO_INTENT","PLAN_PLAN_DIRECTION_CHANGED_ZERO_SENDS_NO_INTENT","PLAN_PLAN_INITIAL_VOLUME_CHANGED_ZERO_SENDS_NO_INTENT","PLAN_PLAN_MIN_CHANGED_ZERO_SENDS_NO_INTENT","PLAN_PLAN_STEP_CHANGED_ZERO_SENDS_NO_INTENT","PLAN_PLAN_MAX_CHANGED_ZERO_SENDS_NO_INTENT","RECORD_WITHOUT_A_PLAN_IS_NEVER_FILLED_IN","OLD_VERSION_1_RECORD_IS_NOT_MIGRATED","REGISTER_THE_PLAN_FOR_AN_OWNED_POSITION","REGISTER_BLOCKED_DISABLED_WRITES_NOTHING","REGISTER_BLOCKED_FILLING_INVALID_WRITES_NOTHING","REGISTER_BLOCKED_MAGIC_ZERO_WRITES_NOTHING","REGISTER_BLOCKED_TP_UNSET_WRITES_NOTHING","REGISTER_BLOCKED_TP_EQUALS_2R_WRITES_NOTHING","REGISTER_BLOCKED_TP_BEFORE_2R_WRITES_NOTHING","REGISTER_BLOCKED_TP_OFF_GRID_BY_0_004_WRITES_NOTHING","REGISTER_BLOCKED_LEVEL_OFF_GRID_BY_0_004_WRITES_NOTHING","REGISTER_BLOCKED_LEVEL_NOISY_NOT_REPRESENTABLE_WRITES_NOTHING","REGISTER_BLOCKED_REAL_NOT_AUTHORISED_WRITES_NOTHING","REGISTER_BLOCKED_REAL_AUTHORISED_BUT_NOT_DEMO_WRITES_NOTHING","REGISTER_BLOCKED_ACCOUNT_UNREADABLE_WRITES_NOTHING","REGISTER_BLOCKED_LOGIN_MISMATCH_WRITES_NOTHING","REGISTER_BLOCKED_NETTING_WRITES_NOTHING","REGISTER_BLOCKED_SYMBOL_UNREADABLE_WRITES_NOTHING","REGISTER_BLOCKED_POSITION_NOT_FOUND_WRITES_NOTHING","REGISTER_BLOCKED_POSITION_MAGIC_OTHER_WRITES_NOTHING","REGISTER_BLOCKED_POSITION_SYMBOL_OTHER_WRITES_NOTHING","REGISTER_BLOCKED_POSITION_DIRECTION_OTHER_WRITES_NOTHING","REGISTER_BLOCKED_POSITION_VOLUME_CHANGED_WRITES_NOTHING","REGISTER_BLOCKED_SPLIT_UNSET_WRITES_NOTHING","REGISTER_NEVER_OVERWRITES_AN_EXISTING_FILE","REGISTER_SAVE_FAILS_BEFORE_WRITE_IS_RECOVERY","REGISTER_SAVE_FALSE_BUT_THE_MOVE_HAPPENED_IS_RECOVERY","NO_FILE_MEANS_NO_AUTOMATIC_START_FROM_SCRATCH","ACCEPTED_FILLED_IS_SENT_ONCE_AND_MAPPED","ACCEPTED_PARTIAL_FILL_RESPONSE_IS_ONLY_MAPPED_NOT_DONE","ACCEPTED_PLACED_RESPONSE_IS_ONLY_MAPPED","REAL_TRANSPORT_FULLY_AUTHORISED_ON_DEMO_PASSES_THE_GATE","QUOTE_BELOW_THE_LEVEL_IS_NO_REQUEST","UNCERTAIN_TIMEOUT_NO_ORDER_IS_RECOVERY_WITHOUT_RETRY","UNCERTAIN_FALSE_NO_RESULT_IS_RECOVERY_WITHOUT_RETRY","UNCERTAIN_TRUE_BUT_NO_ORDER_IS_RECOVERY_WITHOUT_RETRY","UNCERTAIN_REJECT_10006_IS_RECOVERY_WITHOUT_RETRY","UNCERTAIN_RETCODE_UNKNOWN_WITH_ORDER_IS_RECOVERY_WITHOUT_RETRY","INTENT_SAVE_FAILS_BEFORE_ANY_WRITE_ZERO_SENDS","INTENT_SAVE_FALSE_BUT_THE_MOVE_HAPPENED_ZERO_SENDS_AND_THE_DISK_IS_NOT_ASSUMED","MAP_SAVE_FAILS_BEFORE_WRITE_ONE_SEND_INTENT_STAYS","MAP_SAVE_FALSE_BUT_THE_MOVE_HAPPENED_STILL_RECOVERY","RESTART_AFTER_INTENT_IS_NOT_IDLE_NO_SEND","STORED_PENDING_WITH_MAP_IS_NOT_IDLE_NO_SEND","STORED_DONE_IS_NOT_IDLE_NO_SEND","MISSING_FILE_IS_RECOVERY_NO_SEND","BLOCK_DISABLED_ZERO_SENDS","BLOCK_MAGIC_ZERO_ZERO_SENDS","BLOCK_FILLING_UNSET_ZERO_SENDS","BLOCK_DEVIATION_UNSET_ZERO_SENDS","BLOCK_FILTER_POLICY_UNSET_ZERO_SENDS","BLOCK_FILTERS_NEEDED_BUT_BLOCKED_ZERO_SENDS","BLOCK_TP_UNSET_ZERO_SENDS","BLOCK_TP_EQUALS_2R_ZERO_SENDS","BLOCK_TP_BEFORE_2R_ZERO_SENDS","BLOCK_TP_OFF_TICK_GRID_ZERO_SENDS","BLOCK_REAL_NOT_AUTHORISED_ZERO_SENDS","BLOCK_REAL_AUTHORISED_BUT_NOT_DEMO_ZERO_SENDS","BLOCK_REAL_WRONG_PHRASE_ZERO_SENDS","BLOCK_ACCOUNT_UNREADABLE_ZERO_SENDS","BLOCK_LOGIN_MISMATCH_ZERO_SENDS","BLOCK_TRADING_NOT_ALLOWED_ZERO_SENDS","BLOCK_NETTING_ZERO_SENDS","BLOCK_SYMBOL_UNREADABLE_ZERO_SENDS","BLOCK_SYMBOL_NOT_TRADABLE_ZERO_SENDS","BLOCK_POSITION_NOT_FOUND_ZERO_SENDS","BLOCK_POSITION_MAGIC_OTHER_ZERO_SENDS","BLOCK_POSITION_SYMBOL_OTHER_ZERO_SENDS","BLOCK_POSITION_DIRECTION_OTHER_ZERO_SENDS","BLOCK_POSITION_VOLUME_CHANGED_ZERO_SENDS","BLOCK_PRECHECK_FAILS_ZERO_SENDS","BLOCK_LEVEL_OFF_TICK_GRID_ZERO_SENDS","BLOCK_SPLIT_UNSET_ZERO_SENDS"};
int R_START[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,6,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,5,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,4,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int R_TWEAK[]={30,31,32,33,34,35,36,38,37,39,40,41,42,43,44,45,0,0,0,1,30,2,7,8,9,36,35,38,10,11,14,15,17,18,20,21,22,23,24,27,0,0,0,0,0,0,0,13,28,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,6,7,8,9,29,10,11,12,14,15,16,17,18,19,20,21,22,23,24,25,26,27};
int R_RESP[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,0,0,3,4,5,6,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int R_FAULT[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,0,0,0,0,0,0,0,0,0,0,0,1,2,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int R_FAULTNO[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,1,1,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int X_SENDS[]={0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,1,1,1,1,1,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int X_GEN[]={1,1,1,1,1,1,1,1,3,1,1,1,1,1,1,1,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,3,3,3,3,1,2,2,2,2,2,1,2,2,3,2,3,4,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
int X_ORDERS[]={0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0,1,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int R_REG[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int X_PLAN[]={1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
string X_FINAL[]={"BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","SENT_MAPPED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","REGISTERED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","SENT_MAPPED","SENT_MAPPED","SENT_MAPPED","SENT_MAPPED","NO_REQUEST","RECOVERY_REQUIRED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","NOT_IDLE","NOT_IDLE","NOT_IDLE","RECOVERY_REQUIRED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED"};
string X_DISK[]={"IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","REQUEST_PENDING","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","CORRUPT","IDLE","","","","","","","","","","","","","","","","","","","","","","IDLE","","IDLE","","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","IDLE","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","IDLE","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","DONE","","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE"};
string X_REASON[]={"INVALID_INPUT: filling","INVALID_INPUT: exit_filter_policy","INVALID_INPUT: exit_filter_state","INVALID_INPUT: direction","INVALID_INPUT: test_save_fault","PLAN_NOT_ON_SYMBOL_GRID: level_2R","PLAN_NOT_ON_SYMBOL_GRID: TP","PLAN_NOT_REPRESENTABLE_IN_RECORD","","PLAN_CHANGED: level_2R","PLAN_CHANGED: tp","PLAN_CHANGED: direction","PLAN_CHANGED: initial_volume","PLAN_CHANGED: volume_min","PLAN_CHANGED: volume_step","PLAN_CHANGED: volume_max","PLAN_MISSING","LOAD_UNUSABLE: UNSUPPORTED_VERSION: 1","","DISABLED","INVALID_INPUT: filling","INPUT_UNSET: ea_magic","TP_UNKNOWN","TP_EQUALS_2R","TP_BEFORE_2R","PLAN_NOT_ON_SYMBOL_GRID: TP","PLAN_NOT_ON_SYMBOL_GRID: level_2R","PLAN_NOT_REPRESENTABLE_IN_RECORD","REAL_NOT_AUTHORISED","REAL_REQUIRES_DEMO_ACCOUNT","ACCOUNT_UNREADABLE","ACCOUNT_IDENTITY_MISMATCH","UNSUPPORTED_ACCOUNT_MODE","SYMBOL_UNREADABLE","POSITION_NOT_FOUND","OWNERSHIP_NOT_PROVEN","OWNERSHIP_NOT_PROVEN","OWNERSHIP_NOT_PROVEN","POSITION_VOLUME_DIFFERS_FROM_THE_PLAN","REGISTRATION_REFUSED","ALREADY_EXISTS","REGISTRATION_SAVE_FAILED","REGISTRATION_SAVE_FAILED","LOAD_UNUSABLE","","","","","","SEND_UNCERTAIN","SEND_UNCERTAIN","SEND_UNCERTAIN","SEND_UNCERTAIN","SEND_UNCERTAIN","INTENT_SAVE_FAILED","INTENT_SAVE_FAILED","MAP_NOT_SAVED","MAP_NOT_SAVED","","","","LOAD_UNUSABLE","DISABLED","INPUT_UNSET: ea_magic","INPUT_UNSET: filling","INPUT_UNSET: deviation","INPUT_UNSET: exit_filter_policy","EXIT_FILTERS_NOT_CLEAR","TP_UNKNOWN","TP_EQUALS_2R","TP_BEFORE_2R","PLAN_NOT_ON_SYMBOL_GRID: TP","REAL_NOT_AUTHORISED","REAL_REQUIRES_DEMO_ACCOUNT","REAL_NOT_AUTHORISED","ACCOUNT_UNREADABLE","ACCOUNT_IDENTITY_MISMATCH","TRADING_NOT_ALLOWED","UNSUPPORTED_ACCOUNT_MODE","SYMBOL_UNREADABLE_OR_NOT_TRADABLE","SYMBOL_UNREADABLE_OR_NOT_TRADABLE","POSITION_NOT_FOUND","OWNERSHIP_NOT_PROVEN","OWNERSHIP_NOT_PROVEN","OWNERSHIP_NOT_PROVEN","RECONCILE_REQUIRED","PRECHECK_FAILED","PLAN_NOT_ON_SYMBOL_GRID: level_2R","SPLIT_POLICY_UNSET"};
// END GENERATED FIXTURES
#define FN "VELO_T011_EXEC_SELFTEST_A.state"
#define K_IDLE 0
#define K_MISSING 1
#define K_PEND_INTENT 2
#define K_PEND_MAP 3
#define K_DONE_MAP 4
#define K_IDLE_NO_PLAN 5
#define K_OLD_V1 6
#define PZ "PLAN_SET=0\nPLAN_TP=0.000000000000\nPLAN_VOL_MIN=0.000000000000\nPLAN_VOL_STEP=0.000000000000\nPLAN_VOL_MAX=0.000000000000\nPLAN_RPOL=0\nPLAN_E_SRC=0.000000000000\nPLAN_S_SRC=0.000000000000\nPLAN_E_OUT=0.000000000000\nPLAN_S_OUT=0.000000000000\n"
SEsIdentity Ident()
  {
   SEsIdentity i;
   i.server="MetaQuotes-Demo";
   i.login=5001234;
   i.symbol="XAUUSD";
   i.position_id=7;
   return(i);
  }
void Clean(void)
  {
   if(FileIsExist(FN)) FileDelete(FN);
   if(FileIsExist(FN+ESF_TMP_SUFFIX)) FileDelete(FN+ESF_TMP_SUFFIX);
  }
bool ReasonOk(const string expected,const string reason)
  {
   if(expected=="") return(true);
   return(StringFind(reason,expected)>=0);
  }
void PendingState(SEaState &s)
  {
   EA_StateInit(s);
   SEaResult r;
   EA_OnQuote(s,7,1,2000.0,2000.0,2000.3,0.5,0.5,0.01,0.01,100.0,r);
  }
// the stored record of `kind`; a REGISTERED IDLE record carries the plan of the given inputs when from_inputs (and the codec can store them), otherwise the default plan
void Prepare(const int kind,const SExConfig &cfg,CFakeTransport &t,const SExQuote &q,const bool from_inputs)
  {
   Clean();
   if(kind==K_MISSING) return;
   SEsRecord rec;
   ESC_RecordInit(rec);
   rec.id=Ident();
   string text,why;
   if(kind==K_IDLE_NO_PLAN || kind==K_OLD_V1)
     {
      EA_StateInit(rec.state);
      rec.generation=1;
     }
   else
      if(kind==K_IDLE)
        {
         EA_StateInit(rec.state);
         rec.generation=1;
         rec.state.bound=true;
         rec.state.position_id=7;
         rec.state.direction=(from_inputs ? q.direction : 1);
         rec.state.level=(from_inputs ? q.level_2r : 2000.0);
         rec.state.volume_initial=(from_inputs ? q.volume_initial : 0.5);
         rec.plan_set=true;
         rec.plan_rpol=ESC_RPOL_TYPED;
         rec.plan_tp=(from_inputs ? cfg.tp_price : 2010.0);
         rec.plan_vol_min=(from_inputs ? t.symbol.vol_min : 0.01);
         rec.plan_vol_step=(from_inputs ? t.symbol.vol_step : 0.01);
         rec.plan_vol_max=(from_inputs ? t.symbol.vol_max : 100.0);
         if(from_inputs && !ESC_Encode(rec,text,why))     // inputs the codec cannot store: the default plan
           {
            rec.state.direction=1;
            rec.state.level=2000.0;
            rec.state.volume_initial=0.5;
            rec.plan_tp=2010.0;
            rec.plan_vol_min=0.01;
            rec.plan_vol_step=0.01;
            rec.plan_vol_max=100.0;
           }
        }
      else
        {
         PendingState(rec.state);
         rec.plan_set=true;
         rec.plan_rpol=ESC_RPOL_TYPED;
         rec.plan_tp=2010.0;
         rec.plan_vol_min=0.01;
         rec.plan_vol_step=0.01;
         rec.plan_vol_max=100.0;
         SEaResult r;
         if(kind==K_PEND_INTENT) {rec.generation=2; rec.send_phase=ESC_SEND_INTENT;}
         else
           {
            rec.generation=(kind==K_PEND_MAP ? 3 : 4);
            rec.send_phase=ESC_SEND_MAPPED;
            rec.map_complete=true;
            rec.n_orders=1;
            rec.orders[0]=501;
            if(kind==K_DONE_MAP) EA_OnReport(rec.state,"X2R80-7",EA_REP_FULL,0.4,0.01,r);
           }
        }
   if(!ESC_Encode(rec,text,why)) {Print("FAIL fixture record not encodable: ",why); g_fail++; return;}
   if(kind==K_OLD_V1)
     {
      string body=StringSubstr(text,0,StringFind(text,"CRC="));
      StringReplace(body,PZ,"");
      StringReplace(body,"VERSION=3","VERSION=1");
      text=body+"CRC="+StringFormat("%08X",ESC_Crc32(body))+"\n";
     }
   ESF_WriteAll(FN,text);
  }
void Response(CFakeTransport &t,const int i)
  {
   SExSendResult r;
   r.returned_true=true;
   r.have_result=true;
   r.retcode=10009;
   r.order=501;
   r.deal=1001;
   r.volume=0.4;
   r.price=2000.0;
   if(i==1) {r.retcode=10010; r.volume=0.1;}
   if(i==2) {r.retcode=10008; r.deal=0; r.volume=0.0; r.price=0.0;}
   if(i==3) {r.returned_true=false; r.retcode=10012; r.order=0; r.deal=0; r.volume=0.0; r.price=0.0;}
   if(i==4) {r.returned_true=false; r.have_result=false; r.retcode=0; r.order=0; r.deal=0; r.volume=0.0; r.price=0.0;}
   if(i==5) {r.order=0;}
   if(i==6) {r.retcode=10006; r.order=0; r.deal=0; r.volume=0.0; r.price=0.0;}
   if(i==7) {r.retcode=10099; r.deal=0; r.volume=0.0; r.price=0.0;}
   t.response=r;
  }
// the same tweak ids, in the same order, as TWEAKS of tests/t011_executor_fixtures.py
void Setup(const int tweak,const int resp,SExConfig &cfg,CFakeTransport &t,SExQuote &q)
  {
   EX_ConfigInit(cfg);
   cfg.enabled=true;
   cfg.r_policy=EX_RPOL_TYPED;                  // the legacy rows use the typed diagnostic level; UNSET would block them all
   cfg.ea_magic=777;
   cfg.filling=EX_FILL_IOC;
   cfg.deviation=20;
   cfg.filter_policy=EX_POL_IGNORE;
   cfg.filter_state=EX_FS_CLEAR;
   cfg.tp_set=true;
   cfg.tp_price=2010.0;
   Response(t,resp);
   q.direction=1;
   q.level_2r=2000.0;
   q.bid=2000.0;
   q.ask=2000.3;
   q.volume_initial=0.5;
   switch(tweak)
     {
      case 1: cfg.enabled=false; break;
      case 2: cfg.ea_magic=0; break;
      case 3: cfg.filling=EX_FILL_UNSET; break;
      case 4: cfg.deviation=-1; break;
      case 5: cfg.filter_policy=EX_POL_UNSET; break;
      case 6: cfg.filter_policy=EX_POL_NEEDS_CLEAR; cfg.filter_state=EX_FS_BLOCKED; break;
      case 7: cfg.tp_set=false; break;
      case 8: cfg.tp_price=2000.0; break;
      case 9: cfg.tp_price=1990.0; break;
      case 10: t.real=true; break;
      case 11: t.real=true; cfg.real_authorised=true; cfg.authorisation=EX_AUTH_PHRASE; t.account.demo=false; break;
      case 12: t.real=true; cfg.real_authorised=true; cfg.authorisation="yes"; break;
      case 13: t.real=true; cfg.real_authorised=true; cfg.authorisation=EX_AUTH_PHRASE; break;
      case 14: t.account.read_ok=false; break;
      case 15: t.account.login=1; break;
      case 16: t.account.trade_allowed=false; break;
      case 17: t.account.margin_mode=0; break;
      case 18: t.symbol.read_ok=false; break;
      case 19: t.symbol.close_allowed=false; break;
      case 20: t.position.found=false; break;
      case 21: t.position.magic=0; break;
      case 22: t.position.symbol="EURUSD"; break;
      case 23: t.position.type=1; break;
      case 24: t.position.volume=0.4; break;
      case 25: t.precheck_ok=false; break;
      case 26: q.level_2r=2000.005; break;
      case 27: q.volume_initial=0.52; t.position.volume=0.52; break;
      case 28: q.bid=1999.0; q.ask=1999.3; break;
      case 29: cfg.tp_price=2010.005; break;
      case 30: cfg.filling=(ENUM_EX_FILLING)99; break;
      case 31: cfg.filter_policy=(ENUM_EX_FILTER_POLICY)99; break;
      case 32: cfg.filter_state=(ENUM_EX_FILTER_STATE)99; break;
      case 33: q.direction=5; break;
      case 34: cfg.test_save_fault=(ENUM_EX_SAVE_FAULT)99; break;
      case 35: q.level_2r=4000.004; q.bid=4000.004; q.ask=4000.3; cfg.tp_price=4010.0; break;
      case 36: cfg.tp_price=2010.004; break;
      case 37: q.level_2r=2000.1; q.bid=2000.1; q.ask=2000.4; cfg.tp_price=2010.3; break;
      case 38: q.level_2r=3999.9100000000003; q.bid=3999.9100000000003; q.ask=3999.94; cfg.tp_price=4010.0; break;
      case 39: q.level_2r=2000.5; q.bid=2000.5; q.ask=2000.8; break;
      case 40: cfg.tp_price=2011.0; break;
      case 41: q.direction=-1; t.position.type=1; cfg.tp_price=1990.0; q.bid=1999.7; q.ask=2000.0; break;
      case 42: q.volume_initial=0.6; t.position.volume=0.6; break;
      case 43: t.symbol.vol_min=0.02; break;
      case 44: t.symbol.vol_step=0.001; break;
      case 45: t.symbol.vol_max=50.0; break;
     }
  }
string DiskStatus(int &generation,int &orders,int &plan)
  {
   generation=0;
   orders=0;
   plan=0;
   string text,why;
   SEsRecord rec;
   if(!FileIsExist(FN) || !ESF_ReadAll(FN,text)) return("");
   if(!ESC_Decode(text,rec,why)) return("CORRUPT");
   generation=rec.generation;
   orders=rec.n_orders;
   plan=(rec.plan_set ? 1 : 0);
   return(EA_StateName(rec.state.status));
  }
void RunRows(void)
  {
   for(int i=0;i<NROWS;i++)
     {
      string tag=R_NAME[i]+": ";
      SExConfig cfg;
      CFakeTransport t;
      SExQuote q;
      Setup(R_TWEAK[i],R_RESP[i],cfg,t,q);
      Prepare(R_START[i],cfg,t,q,R_TWEAK[i]<PLAN_TWEAK_FIRST);
      if(R_FAULT[i]!=0)
        {
         cfg.test_save_fault=(ENUM_EX_SAVE_FAULT)R_FAULT[i];
         cfg.test_fault_save_no=R_FAULTNO[i];
        }
      SExRuntime rt;
      EX_RuntimeInit(rt);
      SExResult res;
      if(R_REG[i]==1) EX_Register(cfg,GetPointer(t),rt,FN,Ident(),q,res);
      else EX_Process(cfg,GetPointer(t),rt,FN,Ident(),q,res);
      Print(tag,EX_FinalName(res.final_state)," sends ",t.sends," | ",res.reason);
      Check(EX_FinalName(res.final_state)==X_FINAL[i],tag+"final "+EX_FinalName(res.final_state));
      Check(t.sends==X_SENDS[i],tag+"sends "+IntegerToString(t.sends));
      Check(res.sends==t.sends,tag+"the executor counts the sends the transport saw");
      Check(ReasonOk(X_REASON[i],res.reason),tag+"reason contains '"+X_REASON[i]+"' got '"+res.reason+"'");
      int g,n,pl;
      string disk=DiskStatus(g,n,pl);
      Check(disk==X_DISK[i],tag+"status on disk '"+disk+"'");
      Check(g==X_GEN[i] && n==X_ORDERS[i],tag+"generation "+IntegerToString(g)+" and order map entries "+IntegerToString(n));
      Check(pl==X_PLAN[i],tag+"authorised plan on disk "+IntegerToString(pl));
      Check(!FileIsExist(FN+ESF_TMP_SUFFIX),tag+"no temporary file is left");
      if(t.sends>0) Check(t.last_request.position==9 && t.last_request.position!=7 && t.last_request.volume==0.4,tag+"the request carries the position TICKET (not the identifier) and the planned volume");
     }
  }
void TestDuplicateAndUncertainSequences(void)
  {
   SExConfig cfg;
   CFakeTransport t;
   SExQuote q;
   SExResult a,b,c;
   Setup(0,0,cfg,t,q);
   Prepare(K_IDLE,cfg,t,q,true);
   SExRuntime rt;
   EX_RuntimeInit(rt);
   EX_Process(cfg,GetPointer(t),rt,FN,Ident(),q,a);
   EX_Process(cfg,GetPointer(t),rt,FN,Ident(),q,b);
   SExRuntime rt2;
   EX_RuntimeInit(rt2);
   EX_Process(cfg,GetPointer(t),rt2,FN,Ident(),q,c);
   Check(a.final_state==EX_SENT_MAPPED && b.final_state==EX_BLOCKED && c.final_state==EX_NOT_IDLE && t.sends==1,"repeated calls (same or new instance): exactly one send");
   CFakeTransport t2;
   Setup(0,3,cfg,t2,q);                 // uncertain: timeout
   Prepare(K_IDLE,cfg,t2,q,true);
   EX_RuntimeInit(rt);
   EX_Process(cfg,GetPointer(t2),rt,FN,Ident(),q,a);
   EX_Process(cfg,GetPointer(t2),rt,FN,Ident(),q,b);
   EX_RuntimeInit(rt2);
   EX_Process(cfg,GetPointer(t2),rt2,FN,Ident(),q,c);
   Check(a.final_state==EX_RECOVERY_REQUIRED && b.final_state==EX_BLOCKED && c.final_state==EX_NOT_IDLE && t2.sends==1,"an uncertain response: one send, no retry in this run, none after a restart");
   // the flow reports the uncertain send before reading anything
   SErfInput in;
   ERF_InputInit(in);
   SErfResult fr;
   ERF_Run(FN,Ident(),in,fr);
   Check(fr.final_state==ERF_RECOVERY_REQUIRED && !fr.snapshot_called && StringFind(fr.reason,"NO_MAP")>=0,"after an uncertain send the restart flow stops at NO_MAP and reads nothing");
   Clean();
  }
void TestRegistrationRestartBeforeTwoR(void)
  {
   SExConfig cfg;
   CFakeTransport t;
   SExQuote q;
   SExResult r;
   Setup(0,0,cfg,t,q);
   Clean();
   SExRuntime rt;
   EX_RuntimeInit(rt);
   int g,n,pl;
   Check(EX_Register(cfg,GetPointer(t),rt,FN,Ident(),q,r) && DiskStatus(g,n,pl)=="IDLE" && g==1 && pl==1 && t.sends==0,"registration stores the bound IDLE record with the authorised plan, no send");
   string before,after;
   ESF_ReadAll(FN,before);
   SExQuote below=q;
   below.bid=1999.0;
   below.ask=1999.3;
   bool ok=true;
   for(int k=0;k<3;k++)
     {
      SExRuntime fresh;
      EX_RuntimeInit(fresh);            // a restart before 2R: a new instance each time
      EX_Process(cfg,GetPointer(t),fresh,FN,Ident(),below,r);
      if(r.final_state!=EX_NO_REQUEST) ok=false;
     }
   ESF_ReadAll(FN,after);
   Check(ok && t.sends==0 && before==after,"restart before 2R: no request, no send, the file is unchanged");
   SExRuntime rt2;
   EX_RuntimeInit(rt2);
   EX_Process(cfg,GetPointer(t),rt2,FN,Ident(),q,r);
   Check(r.final_state==EX_SENT_MAPPED && t.sends==1 && DiskStatus(g,n,pl)=="REQUEST_PENDING" && g==3 && n==1 && pl==1,"the plan matches: the unchanged flow sends exactly once and the plan survives the INTENT and MAP records");
   Clean();
   // a registered plan, then every parameter changed in turn: BLOCKED, zero sends, the file untouched
   Setup(0,0,cfg,t,q);
   EX_RuntimeInit(rt);
   EX_Register(cfg,GetPointer(t),rt,FN,Ident(),q,r);
   ESF_ReadAll(FN,before);
   int changes[7]={39,40,41,42,43,44,45};
   for(int k=0;k<7;k++)
     {
      SExConfig c2;
      CFakeTransport t2;
      SExQuote q2;
      Setup(changes[k],0,c2,t2,q2);
      SExRuntime fresh;
      EX_RuntimeInit(fresh);
      EX_Process(c2,GetPointer(t2),fresh,FN,Ident(),q2,r);
      ESF_ReadAll(FN,after);
      Check(r.final_state==EX_BLOCKED && StringFind(r.reason,"PLAN_CHANGED")>=0 && t2.sends==0 && before==after,"plan change "+IntegerToString(changes[k])+": BLOCKED, zero sends, no INTENT written");
     }
   Clean();
  }
void BuildRaw(SXaRaw &r,const bool filled)
  {
   XA_RawInit(r);
   r.api_ok=true;
   r.symbol_ok=true;
   r.vol_step=0.01;
   r.vol_min=0.01;
   r.vol_max=100.0;
   r.margin_ok=true;
   r.margin_mode=XA_MARGIN_HEDGING;
   r.n_pos=1;
   r.pos_ticket=9;
   r.pos_type=XA_POS_BUY;
   r.pos_symbol="XAUUSD";
   r.hist_ok=true;
   r.deals_truncated=false;
   r.deal[0].ticket=100;
   r.deal[0].order=400;
   r.deal[0].position_id=7;
   r.deal[0].entry=XA_ENTRY_IN;
   r.deal[0].type=XA_DEAL_BUY;
   r.deal[0].volume=0.5;
   r.n_deals=1;
   r.n_orders=1;
   r.ord[0].ticket=501;
   r.ord[0].position_id=7;
   if(filled)
     {
      r.pos_volume=0.1;
      r.deal[1].ticket=1001;
      r.deal[1].order=501;
      r.deal[1].position_id=7;
      r.deal[1].entry=XA_ENTRY_OUT;
      r.deal[1].type=XA_DEAL_SELL;
      r.deal[1].volume=0.4;
      r.n_deals=2;
      r.ord[0].where=XA_WHERE_HISTORY;
      r.ord[0].state=XA_ORD_FILLED;
      r.ord[0].vol_initial=0.4;
      r.ord[0].vol_current=0.0;
     }
   else
     {
      r.pos_volume=0.5;
      r.ord[0].where=XA_WHERE_ACTIVE;
      r.ord[0].state=XA_ORD_PLACED;
      r.ord[0].vol_initial=0.4;
      r.ord[0].vol_current=0.4;
     }
  }
void TestDoneOnlyFromTheReconciliation(void)
  {
   SExConfig cfg;
   CFakeTransport t;
   SExQuote q;
   SExResult a;
   Setup(0,0,cfg,t,q);                  // the response says "done": still not DONE
   Prepare(K_IDLE,cfg,t,q,true);
   SExRuntime rt;
   EX_RuntimeInit(rt);
   EX_Process(cfg,GetPointer(t),rt,FN,Ident(),q,a);
   int g,n,pl;
   Check(a.final_state==EX_SENT_MAPPED && DiskStatus(g,n,pl)=="REQUEST_PENDING","a 'done' response only maps the order; the record is still REQUEST_PENDING");
   SXaRaw not_yet,filled;
   BuildRaw(not_yet,false);
   BuildRaw(filled,true);
   SErfResult fr;
   EX_Reconcile(FN,Ident(),GetPointer(t),not_yet,not_yet,fr);
   Check(fr.final_state==ERF_STILL_OPEN && !fr.saved,"reconciliation without the fill in the history: STILL_OPEN");
   EX_Reconcile(FN,Ident(),GetPointer(t),filled,filled,fr);
   Check(fr.final_state==ERF_DONE && fr.saved && fr.state.confirmations==1 && DiskStatus(g,n,pl)=="DONE","reconciliation with complete evidence: DONE, saved, one confirmation");
   Check(t.sends==1,"one send in the whole sequence");
   Clean();
  }
// the grid tolerance is floating-point noise only (mirrors Grid.CASES of tests/test_t011_executor.py)
void TestGrid(void)
  {
   Check(!EX_OnGrid(4000.004,0.01),"4000.004 with a tick of 0.01 is NOT on the grid (a real offset of 0.4 tick)");
   Check(!EX_OnGrid(2010.004,0.01) && !EX_OnGrid(2000.005,0.01),"2010.004 and 2000.005 are not on the grid");
   Check(EX_OnGrid(4000.0,0.01) && EX_OnGrid(2000.1,0.01),"exact grid prices are on the grid");
   Check(EX_OnGrid(3999.9100000000003,0.01),"a price on the grid with binary noise (399991 * 0.01) is on the grid");
   Check(EX_OnGrid(0.1+0.2,0.1),"0.1 + 0.2 is on a grid of 0.1");
   double nan=MathSqrt(-1.0);
   double inf=MathExp(1000.0);
   Check(!EX_OnGrid(nan,0.01) && !EX_OnGrid(inf,0.01) && !EX_OnGrid(-1.0,0.01) && !EX_OnGrid(0.0,0.01),"non-finite and non-positive prices are never on the grid");
   Check(!EX_OnGrid(1.0,0.0) && !EX_OnGrid(1.0,nan) && !EX_OnGrid(1.0,-0.01) && !EX_OnGrid(1e300,0.01),"a non-finite or non-positive tick, or an absurd price, is never on the grid");
   int bad=0;
   double ticks[4]={0.01,0.1,0.00001,0.5};
   double bases[4]={100.0,2000.0,4000.0,100000.0};
   double fracs[5]={0.001,0.01,0.25,0.4,0.5};
   for(int a=0;a<4;a++)
      for(int b=0;b<4;b++)
        {
         double k=MathRound(bases[b]/ticks[a]);
         if(!EX_OnGrid(k*ticks[a],ticks[a])) bad++;
         for(int c=0;c<5;c++)
            if(EX_OnGrid(k*ticks[a]+fracs[c]*ticks[a],ticks[a])) bad++;
        }
   Check(bad==0,"every real offset of at least 1/1000 tick is refused at several prices and ticks ("+IntegerToString(bad)+" wrong)");
  }
void OnStart()
  {
   Print("T011 EXECUTOR TEST: fake transport only; sandbox file VELO_T011_EXEC_SELFTEST_A.state; no order, no position read, no new trade.");
   TestGrid();
   RunRows();
   TestRegistrationRestartBeforeTwoR();
   TestDuplicateAndUncertainSequences();
   TestDoneOnlyFromTheReconciliation();
   Clean();
   Check(!FileIsExist(FN) && !FileIsExist(FN+ESF_TMP_SUFFIX),"the test leaves no file behind");
   PrintFormat("T011 EXECUTOR TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
