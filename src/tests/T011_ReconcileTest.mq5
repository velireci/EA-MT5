// T011 test script: reconciliation of the 2R partial-close request against a caller-supplied snapshot. Mirrors
// tests/test_t011_reconcile.py; the fixtures below are the hand-written scenario table of tests/t011_reconcile_fixtures.py.
// NOT YET COMPILED OR RUN in MT5 (UNVERIFIED). Pure: no broker read, no order, no retry, no clock, no persistence.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/ExitReconciliation.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
// BEGIN GENERATED FIXTURES (tests/t011_reconcile_fixtures.py emit_mql)
#define NROWS 122
#define MAXE 4
string R_SCN[]={"BUY_FULL_FILL_ONE_EXECUTION","BUY_FULL_FILL_ONE_EXECUTION","SELL_FULL_FILL_ONE_EXECUTION","SELL_FULL_FILL_ONE_EXECUTION","BUY_FULL_FILL_TWO_EXECUTIONS","BUY_FULL_FILL_TWO_EXECUTIONS","BUY_FULL_FILL_FOUR_EXECUTIONS","BUY_FULL_FILL_FOUR_EXECUTIONS","BUY_CONFIRMED_AGAIN_IS_NOT_COUNTED_AGAIN","BUY_CONFIRMED_AGAIN_IS_NOT_COUNTED_AGAIN","BUY_CONFIRMED_AGAIN_IS_NOT_COUNTED_AGAIN","BUY_PARTIAL_FILLS_THEN_FULL","BUY_PARTIAL_FILLS_THEN_FULL","BUY_PARTIAL_FILLS_THEN_FULL","BUY_PARTIAL_FILLS_THEN_FULL","BUY_PARTIAL_FILLS_THEN_FULL","SELL_PARTIAL_FILLS_THEN_FULL","SELL_PARTIAL_FILLS_THEN_FULL","SELL_PARTIAL_FILLS_THEN_FULL","BUY_PARTIAL_REPORT_THEN_SNAPSHOT_FULL","BUY_PARTIAL_REPORT_THEN_SNAPSHOT_FULL","BUY_PARTIAL_REPORT_THEN_SNAPSHOT_FULL","BUY_DUPLICATE_EXECUTION_COUNTED_ONCE","BUY_DUPLICATE_EXECUTION_COUNTED_ONCE","SELL_DUPLICATE_EXECUTION_COUNTED_ONCE","SELL_DUPLICATE_EXECUTION_COUNTED_ONCE","BUY_THREE_COPIES_OF_ONE_EXECUTION","BUY_THREE_COPIES_OF_ONE_EXECUTION","BUY_EXECUTION_ID_CONFLICT_VOLUME","BUY_EXECUTION_ID_CONFLICT_VOLUME","BUY_EXECUTION_ID_CONFLICT_REQUEST","BUY_EXECUTION_ID_CONFLICT_REQUEST","BUY_UNLINKED_EXECUTION_IGNORED","BUY_UNLINKED_EXECUTION_IGNORED","BUY_TIMEOUT_THEN_LATE_FILL","BUY_TIMEOUT_THEN_LATE_FILL","BUY_TIMEOUT_THEN_LATE_FILL","BUY_TIMEOUT_THEN_LATE_FILL","BUY_TIMEOUT_THEN_LATE_FILL","BUY_TIMEOUT_THEN_LATE_FILL","BUY_TIMEOUT_THEN_LATE_FILL","SELL_TIMEOUT_THEN_LATE_FILL","SELL_TIMEOUT_THEN_LATE_FILL","SELL_TIMEOUT_THEN_LATE_FILL","SELL_TIMEOUT_THEN_LATE_FILL","BUY_TIMEOUT_THEN_PARTIAL_LATE_FILL_STAYS_FOR_RECONCILIATION","BUY_TIMEOUT_THEN_PARTIAL_LATE_FILL_STAYS_FOR_RECONCILIATION","BUY_TIMEOUT_THEN_PARTIAL_LATE_FILL_STAYS_FOR_RECONCILIATION","BUY_TIMEOUT_THEN_PARTIAL_LATE_FILL_STAYS_FOR_RECONCILIATION","BUY_TIMEOUT_THEN_SNAPSHOT_WITHOUT_FILL","BUY_TIMEOUT_THEN_SNAPSHOT_WITHOUT_FILL","BUY_TIMEOUT_THEN_SNAPSHOT_WITHOUT_FILL","BUY_TIMEOUT_THEN_SNAPSHOT_WITHOUT_FILL","BUY_REJECTED_THEN_FILL_EVIDENCE","BUY_REJECTED_THEN_FILL_EVIDENCE","BUY_REJECTED_THEN_FILL_EVIDENCE","BUY_VOLUME_DROP_ALONE_INCOMPLETE","BUY_VOLUME_DROP_ALONE_INCOMPLETE","BUY_VOLUME_DROP_ALONE_INCOMPLETE","BUY_VOLUME_DROP_ALONE_INCOMPLETE","BUY_VOLUME_DROP_ALONE_COMPLETE_BLOCKS","BUY_VOLUME_DROP_ALONE_COMPLETE_BLOCKS","SELL_VOLUME_DROP_ALONE_PENDING_STAYS","SELL_VOLUME_DROP_ALONE_PENDING_STAYS","BUY_MANUAL_EXTRA_CLOSE_AFTER_FULL_FILL","BUY_MANUAL_EXTRA_CLOSE_AFTER_FULL_FILL","BUY_MANUAL_PARTIAL_UNDO_AFTER_FULL_FILL","BUY_MANUAL_PARTIAL_UNDO_AFTER_FULL_FILL","BUY_MANUAL_CHANGE_DURING_PARTIAL_INCOMPLETE_IS_UNKNOWN","BUY_MANUAL_CHANGE_DURING_PARTIAL_INCOMPLETE_IS_UNKNOWN","BUY_MANUAL_CHANGE_DURING_PARTIAL_COMPLETE_BLOCKS","BUY_MANUAL_CHANGE_DURING_PARTIAL_COMPLETE_BLOCKS","BUY_VOLUME_OFF_GRID","BUY_VOLUME_OFF_GRID","BUY_WRONG_POSITION","BUY_WRONG_POSITION","BUY_WRONG_POSITION","BUY_WRONG_POSITION","SELL_WRONG_REQUEST_ID","SELL_WRONG_REQUEST_ID","BUY_STEP_CHANGED","BUY_STEP_CHANGED","SELL_STEP_CHANGED_SAME_VOLUME","SELL_STEP_CHANGED_SAME_VOLUME","BUY_POSITION_MISSING","BUY_POSITION_MISSING","BUY_POSITION_MISSING_NO_PROOF","BUY_POSITION_MISSING_NO_PROOF","BUY_POSITION_MISSING_NO_PROOF","BUY_OVERFILL","BUY_OVERFILL","BUY_EXECUTION_OFF_GRID","BUY_EXECUTION_OFF_GRID","BUY_ALREADY_BLOCKED_SNAPSHOT_CHANGES_NOTHING","BUY_ALREADY_BLOCKED_SNAPSHOT_CHANGES_NOTHING","BUY_ALREADY_BLOCKED_SNAPSHOT_CHANGES_NOTHING","BUY_NO_REQUEST_BEFORE_2R","BUY_NO_REQUEST_BEFORE_2R","BUY_NO_REQUEST_SPLIT_POLICY_UNSET","BUY_NO_REQUEST_SPLIT_POLICY_UNSET","BUY_NO_REQUEST_VOLUME_MISMATCH_BEFORE_REQUEST","BUY_NO_REQUEST_VOLUME_MISMATCH_BEFORE_REQUEST","BUY_INVALID_SNAPSHOTS_CHANGE_NOTHING","BUY_INVALID_SNAPSHOTS_CHANGE_NOTHING","BUY_INVALID_SNAPSHOTS_CHANGE_NOTHING","BUY_INVALID_SNAPSHOTS_CHANGE_NOTHING","BUY_INVALID_SNAPSHOTS_CHANGE_NOTHING","BUY_INVALID_SNAPSHOTS_CHANGE_NOTHING","BUY_INVALID_SNAPSHOTS_CHANGE_NOTHING","BUY_INVALID_SNAPSHOTS_CHANGE_NOTHING","BUY_DONE_THEN_CONSISTENT_SNAPSHOT","BUY_DONE_THEN_CONSISTENT_SNAPSHOT","BUY_DONE_THEN_CONSISTENT_SNAPSHOT","BUY_DONE_THEN_MANUAL_CHANGE","BUY_DONE_THEN_MANUAL_CHANGE","BUY_DONE_THEN_MANUAL_CHANGE","BUY_DONE_THEN_FEWER_EXECUTIONS","BUY_DONE_THEN_FEWER_EXECUTIONS","BUY_DONE_THEN_FEWER_EXECUTIONS","BUY_DONE_THEN_UNKNOWN_EVIDENCE","BUY_DONE_THEN_UNKNOWN_EVIDENCE","BUY_DONE_THEN_UNKNOWN_EVIDENCE"};
int R_KIND[]={0,2,0,2,0,2,0,2,0,2,2,0,2,2,2,2,0,2,2,0,1,2,0,2,0,2,0,2,0,2,0,2,0,2,0,1,0,0,1,2,0,0,1,0,2,0,1,2,0,0,1,2,2,0,1,2,0,1,2,2,0,2,0,2,0,2,0,2,0,2,0,2,0,2,0,2,2,0,0,2,0,2,0,2,0,2,0,1,2,0,2,0,2,0,1,2,0,2,0,2,0,2,0,2,2,2,2,2,2,2,0,2,2,0,2,2,0,2,2,0,2,2};
long R_POS[]={7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,0,7,7,7,7,7,7,7,7,7,7,7,7,7,7,0,7,7,0,7,7,7,0,7,7,7,0,7,7,7,0,7,7,7,0,7,7,0,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,8,7,7,7,7,7,7,7,7,7,7,7,0,7,7,7,7,7,7,0,7,7,7,7,7,7,7,7,7,7,7,7,7,0,7,7,7,7,7,7,7,7,7,7,7,7,7};
int R_DIR[]={1,0,-1,0,1,0,1,0,1,0,0,1,0,0,0,0,-1,0,0,1,0,0,1,0,-1,0,1,0,1,0,1,0,1,0,1,0,1,1,0,0,1,-1,0,-1,0,1,0,0,1,1,0,0,0,1,0,0,1,0,0,0,1,0,-1,0,1,0,1,0,1,0,1,0,1,0,1,0,0,1,-1,0,1,0,-1,0,1,0,1,0,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,0,0,0,0,0,0,0,1,0,0,1,0,0,1,0,0,1,0,0};
double R_LEVEL[]={2000.0,0.0,1990.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,0.0,2000.0,0.0,0.0,0.0,0.0,1990.0,0.0,0.0,2000.0,0.0,0.0,2000.0,0.0,1990.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,2000.0,0.0,0.0,2000.0,1990.0,0.0,1990.0,0.0,2000.0,0.0,0.0,2000.0,2000.0,0.0,0.0,0.0,2000.0,0.0,0.0,2000.0,0.0,0.0,0.0,2000.0,0.0,1990.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,0.0,2000.0,1990.0,0.0,2000.0,0.0,1990.0,0.0,2000.0,0.0,2000.0,0.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2000.0,0.0,0.0,2000.0,0.0,0.0,2000.0,0.0,0.0,2000.0,0.0,0.0};
double R_BID[]={2000.0,0.0,1989.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,0.0,2000.0,0.0,0.0,0.0,0.0,1989.0,0.0,0.0,2000.0,0.0,0.0,2000.0,0.0,1989.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2001.0,2002.0,0.0,0.0,2003.0,1989.0,0.0,1988.0,0.0,2000.0,0.0,0.0,2001.0,2000.0,0.0,0.0,0.0,2000.0,0.0,0.0,2000.0,0.0,0.0,0.0,2000.0,0.0,1989.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,0.0,2001.0,1989.0,0.0,2000.0,0.0,1989.0,0.0,2000.0,0.0,2000.0,0.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,0.0,1999.0,0.0,2000.0,0.0,2000.0,0.0,2000.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2000.0,0.0,0.0,2000.0,0.0,0.0,2000.0,0.0,0.0,2000.0,0.0,0.0};
double R_ASK[]={2000.3,0.0,1989.4,0.0,2000.3,0.0,2000.3,0.0,2000.3,0.0,0.0,2000.3,0.0,0.0,0.0,0.0,1989.4,0.0,0.0,2000.3,0.0,0.0,2000.3,0.0,1989.4,0.0,2000.3,0.0,2000.3,0.0,2000.3,0.0,2000.3,0.0,2000.3,0.0,2001.3,2002.3,0.0,0.0,2003.3,1989.4,0.0,1988.4,0.0,2000.3,0.0,0.0,2001.3,2000.3,0.0,0.0,0.0,2000.3,0.0,0.0,2000.3,0.0,0.0,0.0,2000.3,0.0,1989.4,0.0,2000.3,0.0,2000.3,0.0,2000.3,0.0,2000.3,0.0,2000.3,0.0,2000.3,0.0,0.0,2001.3,1989.4,0.0,2000.3,0.0,1989.4,0.0,2000.3,0.0,2000.3,0.0,0.0,2000.3,0.0,2000.3,0.0,2000.3,0.0,0.0,1999.3,0.0,2000.3,0.0,2000.3,0.0,2000.3,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2000.3,0.0,0.0,2000.3,0.0,0.0,2000.3,0.0,0.0,2000.3,0.0,0.0};
double R_VINIT[]={0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.0,0.5,0.0,0.0,0.0,0.0,0.5,0.0,0.0,0.5,0.0,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.5,0.0,0.0,0.5,0.5,0.0,0.5,0.0,0.5,0.0,0.0,0.5,0.5,0.0,0.0,0.0,0.5,0.0,0.0,0.5,0.0,0.0,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.0,0.5,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.0,0.5,0.0,0.5,0.0,0.5,0.0,0.0,0.5,0.0,0.07,0.0,0.5,0.0,0.5,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.5,0.0,0.0,0.5,0.0,0.0,0.5,0.0,0.0,0.5,0.0,0.0};
double R_VCUR[]={0.5,0.1,0.5,0.1,0.5,0.1,0.5,0.1,0.5,0.1,0.1,0.5,0.4,0.2,0.2,0.1,0.5,0.2,0.1,0.5,0.0,0.1,0.5,0.1,0.5,0.3,0.5,0.3,0.5,0.3,0.5,0.3,0.5,0.1,0.5,0.0,0.5,0.5,0.0,0.1,0.1,0.5,0.0,0.5,0.1,0.5,0.0,0.35,0.5,0.5,0.0,0.5,0.5,0.5,0.0,0.1,0.5,0.0,0.1,0.1,0.5,0.1,0.5,0.2,0.5,0.07,0.5,0.15,0.5,0.3,0.5,0.3,0.5,0.105,0.5,0.1,0.1,0.5,0.5,0.1,0.5,0.1,0.5,0.1,0.5,0.1,0.5,0.0,0.1,0.5,0.05,0.5,0.425,0.5,0.0,0.1,0.5,0.5,0.07,0.07,0.45,0.1,0.5,0.1,0.0,0.1,0.1,0.1,0.1,0.1,0.5,0.1,0.1,0.5,0.1,0.07,0.5,0.1,0.4,0.5,0.1,0.5};
double R_VMIN[]={0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.0,0.01,0.0,0.0,0.0,0.0,0.01,0.0,0.0,0.01,0.0,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.01,0.0,0.0,0.01,0.01,0.0,0.01,0.0,0.01,0.0,0.0,0.01,0.01,0.0,0.0,0.0,0.01,0.0,0.0,0.01,0.0,0.0,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.0,0.01,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.01,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.01,0.0,0.0,0.01,0.0,0.0,0.01,0.0,0.0,0.01,0.0,0.0};
double R_STEP[]={0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.001,0.01,0.001,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.0,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01,0.01};
double R_VMAX[]={100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,0.0,100.0,0.0,0.0,0.0,0.0,100.0,0.0,0.0,100.0,0.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,100.0,0.0,0.0,100.0,100.0,0.0,100.0,0.0,100.0,0.0,0.0,100.0,100.0,0.0,0.0,0.0,100.0,0.0,0.0,100.0,0.0,0.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,0.0,100.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,100.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,100.0,0.0,0.0,100.0,0.0,0.0,100.0,0.0,0.0,100.0,0.0,0.0};
double R_RVOL[]={0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.1,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.3,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0};
string R_RID[]={"","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","X2R80-7","","X2R80-7","X2R80-7","X2R80-7","X2R80-7","","X2R80-7","X2R80-7","","X2R80-7","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","","","X2R80-7","X2R80-7","","","X2R80-7","","X2R80-7","","X2R80-7","X2R80-7","","","X2R80-7","X2R80-7","X2R80-7","","X2R80-7","X2R80-7","","X2R80-7","X2R80-7","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","X2R80-7","","","X2R80-8","","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","X2R80-7","","X2R80-7","","X2R80-7","","X2R80-7","","","X2R80-7","X2R80-7","X2R80-7","X2R80-7","X2R80-7","X2R80-7","","X2R80-7","X2R80-7","","X2R80-7","X2R80-7","","X2R80-7","X2R80-7","","X2R80-7","X2R80-7"};
int R_RKIND[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,3,0,0,0,3,0,0,0,3,0,0,0,2,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int R_FOUND[]={1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
int R_COMP[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int R_NEX[]={0,1,0,1,0,2,0,4,0,1,1,0,1,2,2,3,0,1,2,0,0,2,0,2,0,2,0,3,0,2,0,2,0,2,0,0,0,0,0,1,0,0,0,0,1,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,1,0,1,1,0,0,1,0,1,0,1,0,1,0,0,0,0,2,0,1,0,0,1,0,0,0,0,0,1,0,0,0,0,1,1,0,1,0,1,1,0,1,1,0,1,1,0,1,0};
string E_ID[]={"","","","","e1","","","","","","","","e1","","","","","","","","e1","e2","","","","","","","e1","e2","e3","e4","","","","","e1","","","","e1","","","","","","","","e1","","","","e1","e2","","","e1","e2","","","e1","e2","e3","","","","","","e1","","","","e1","e2","","","","","","","","","","","e1","e2","","","","","","","e1","e1","","","","","","","e1","e1","","","","","","","e1","e1","e1","","","","","","e1","e1","","","","","","","e1","e1","","","","","","","o1","e1","","","","","","","","","","","","","","","","","","","","","","","e1","","","","","","","","","","","","","","","","","","","","e1","","","","","","","","","","","","e1","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","e1","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","e1","","","","","","","","e1","","","","","","","","e1","","","","","","","","e1","","","","","","","","e1","","","","","","","","e1","","","","e1","","","","","","","","","","","","e1","","","","","","","","e1","","","","","","","","e1","","","","","","","","e1","","","","","","","","","","","","","","","","","","","","e1","e2","","","","","","","e1","","","","","","","","","","","","e1","","","","","","","","","","","","","","","","","","","","","","","","e1","","","","","","","","","","","","","","","","","","","","","","","","e1","","","","","","","","e1","","","","","","","","e1","","","","e1","","","","","","","","e1","","","","e1","","","","","","","","e1","","","","e1","","","","","","","","e1","","","","","","",""};
string E_REQ[]={"","","","","X2R80-7","","","","","","","","X2R80-7","","","","","","","","X2R80-7","X2R80-7","","","","","","","X2R80-7","X2R80-7","X2R80-7","X2R80-7","","","","","X2R80-7","","","","X2R80-7","","","","","","","","X2R80-7","","","","X2R80-7","X2R80-7","","","X2R80-7","X2R80-7","","","X2R80-7","X2R80-7","X2R80-7","","","","","","X2R80-7","","","","X2R80-7","X2R80-7","","","","","","","","","","","X2R80-7","X2R80-7","","","","","","","X2R80-7","X2R80-7","","","","","","","X2R80-7","X2R80-7","","","","","","","X2R80-7","X2R80-7","X2R80-7","","","","","","X2R80-7","X2R80-7","","","","","","","X2R80-7","X2R80-9","","","","","","","X2R80-9","X2R80-7","","","","","","","","","","","","","","","","","","","","","","","X2R80-7","","","","","","","","","","","","","","","","","","","","X2R80-7","","","","","","","","","","","","X2R80-7","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","X2R80-7","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","","X2R80-7","","","","","","","","X2R80-7","","","","","","","","X2R80-7","","","","","","","","X2R80-7","","","","","","","","X2R80-7","","","","","","","","X2R80-7","","","","X2R80-7","","","","","","","","","","","","X2R80-7","","","","","","","","X2R80-7","","","","","","","","X2R80-7","","","","","","","","X2R80-7","","","","","","","","","","","","","","","","","","","","X2R80-7","X2R80-7","","","","","","","X2R80-7","","","","","","","","","","","","X2R80-7","","","","","","","","","","","","","","","","","","","","","","","","X2R80-7","","","","","","","","","","","","","","","","","","","","X2R80-7","","","","X2R80-7","","","","","","","","X2R80-7","","","","","","","","X2R80-7","","","","X2R80-7","","","","","","","","X2R80-7","","","","X2R80-7","","","","","","","","X2R80-7","","","","X2R80-7","","","","","","","","X2R80-7","","","","","","",""};
double E_VOL[]={0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.25,0.15,0.0,0.0,0.0,0.0,0.0,0.0,0.1,0.1,0.1,0.1,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.1,0.0,0.0,0.0,0.1,0.2,0.0,0.0,0.1,0.2,0.0,0.0,0.1,0.2,0.1,0.0,0.0,0.0,0.0,0.0,0.3,0.0,0.0,0.0,0.3,0.1,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.1,0.3,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.2,0.2,0.0,0.0,0.0,0.0,0.0,0.0,0.2,0.2,0.2,0.0,0.0,0.0,0.0,0.0,0.2,0.1,0.0,0.0,0.0,0.0,0.0,0.0,0.2,0.2,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.15,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.1,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.1,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.04,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.1,0.0,0.0,0.0,0.0,0.0,0.0,0.075,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.1,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0};
string X_DEC[]={"","CONFIRMED","","CONFIRMED","","CONFIRMED","","CONFIRMED","","CONFIRMED","CONFIRMED","","PARTIAL","PARTIAL","PARTIAL","CONFIRMED","","PARTIAL","CONFIRMED","","","CONFIRMED","","CONFIRMED","","PARTIAL","","PARTIAL","","BLOCK","","BLOCK","","CONFIRMED","","","","","","CONFIRMED","","","","","CONFIRMED","","","PARTIAL","","","","NOT_EXECUTED","UNKNOWN","","","CONFIRMED","","","UNKNOWN","UNKNOWN","","BLOCK","","UNKNOWN","","BLOCK","","BLOCK","","UNKNOWN","","BLOCK","","BLOCK","","BLOCK","BLOCK","","","BLOCK","","BLOCK","","BLOCK","","BLOCK","","","BLOCK","","BLOCK","","BLOCK","","","BLOCK","","UNKNOWN","","UNKNOWN","","UNKNOWN","","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","INVALID_INPUT","CONFIRMED","","CONFIRMED","CONFIRMED","","CONFIRMED","BLOCK","","CONFIRMED","PARTIAL","","CONFIRMED","UNKNOWN"};
string X_STATE[]={"REQUEST_PENDING","DONE","REQUEST_PENDING","DONE","REQUEST_PENDING","DONE","REQUEST_PENDING","DONE","REQUEST_PENDING","DONE","DONE","REQUEST_PENDING","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","DONE","REQUEST_PENDING","NEEDS_RECONCILIATION","DONE","REQUEST_PENDING","NEEDS_RECONCILIATION","DONE","REQUEST_PENDING","DONE","REQUEST_PENDING","NEEDS_RECONCILIATION","REQUEST_PENDING","NEEDS_RECONCILIATION","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","DONE","REQUEST_PENDING","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","DONE","DONE","REQUEST_PENDING","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","DONE","REQUEST_PENDING","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","REQUEST_PENDING","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","REQUEST_PENDING","NEEDS_RECONCILIATION","DONE","REQUEST_PENDING","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","BLOCKED","BLOCKED","BLOCKED","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","NEEDS_RECONCILIATION","BLOCKED","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","BLOCKED","REQUEST_PENDING","BLOCKED","BLOCKED","IDLE","IDLE","IDLE","IDLE","NEEDS_RECONCILIATION","NEEDS_RECONCILIATION","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","DONE","REQUEST_PENDING","DONE","DONE","REQUEST_PENDING","DONE","BLOCKED","REQUEST_PENDING","DONE","NEEDS_RECONCILIATION","REQUEST_PENDING","DONE","NEEDS_RECONCILIATION"};
long X_LINKED[]={0,40,0,40,0,40,0,40,0,40,40,0,10,30,30,40,0,30,40,0,0,40,0,40,0,20,0,20,0,0,0,0,0,40,0,0,0,0,0,40,0,0,0,0,40,0,0,15,0,0,0,0,0,0,0,40,0,0,0,0,0,0,0,0,0,40,0,40,0,10,0,10,0,40,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,50,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,40,0,40,40,0,40,40,0,40,10,0,40,0};
int X_DUP[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int X_UNL[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int X_CHG[]={0,1,0,1,0,1,0,1,0,1,0,0,1,1,0,1,0,1,1,0,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,0,0,0,0,1,0,0,0,0,1,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,1,0,1,0,0,0,1,0,1,0,1,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,0,1,1,0,1,1,0,1,1};
int X_CONF[]={0,1,0,1,0,1,0,1,0,1,1,0,0,0,0,1,0,0,1,0,0,1,0,1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,1,0,1,1,0,1,1,0,1,1};
// END GENERATED FIXTURES
bool SamePlan(const SEaState &a,const SEaState &b)
  {
   return(a.initial_steps==b.initial_steps && a.request_steps==b.request_steps && a.request_id==b.request_id && a.volume_step==b.volume_step &&
          a.position_id==b.position_id && a.close_volume==b.close_volume);
  }
bool SameState(const SEaState &a,const SEaState &b)
  {
   return(a.status==b.status && a.bound==b.bound && a.position_id==b.position_id && a.direction==b.direction && a.level==b.level &&
          a.volume_initial==b.volume_initial && a.volume_step==b.volume_step && a.request_id==b.request_id && a.request_steps==b.request_steps &&
          a.close_volume==b.close_volume && a.initial_steps==b.initial_steps && a.executed_steps==b.executed_steps &&
          a.confirmations==b.confirmations && a.duplicates_ignored==b.duplicates_ignored && a.reason==b.reason);
  }
void RunRows(void)
  {
   SEaState st;
   EA_StateInit(st);
   string cur="";
   int n=0;
   for(int i=0;i<NROWS;i++)
     {
      if(R_SCN[i]!=cur)
        {
         cur=R_SCN[i];
         EA_StateInit(st);
         n=0;
        }
      n++;
      string tag=StringFormat("%s #%d: ",cur,n);
      if(R_KIND[i]==0)
        {
         SEaResult r;
         EA_OnQuote(st,(ulong)R_POS[i],R_DIR[i],R_LEVEL[i],R_BID[i],R_ASK[i],R_VINIT[i],R_VCUR[i],R_VMIN[i],R_STEP[i],R_VMAX[i],r);
         Check(EA_StateName(st.status)==X_STATE[i],tag+"quote: state "+EA_StateName(st.status)+" expected "+X_STATE[i]);
         Check(r.action==EA_ACT_NONE || X_STATE[i]=="REQUEST_PENDING",tag+"quote: no unexpected request");
        }
      if(R_KIND[i]==1)
        {
         SEaResult r;
         EA_OnReport(st,R_RID[i],(ENUM_EA_REPORT)R_RKIND[i],R_RVOL[i],R_STEP[i],r);
         Check(EA_StateName(st.status)==X_STATE[i],tag+"report: state "+EA_StateName(st.status)+" expected "+X_STATE[i]);
        }
      if(R_KIND[i]==2)
        {
         SErSnapshot snap;
         ER_SnapshotInit(snap,R_FOUND[i]==1,(ulong)R_POS[i],R_RID[i],R_STEP[i],R_VCUR[i],R_COMP[i]==1);
         for(int k=0;k<R_NEX[i];k++)
            ER_AddExec(snap,E_ID[i*MAXE+k],E_REQ[i*MAXE+k],E_VOL[i*MAXE+k]);
         SEaState before=st;
         SErOutcome o;
         bool ok=ER_Reconcile(st,snap,o);
         Check(ER_DecisionName(o.decision)==X_DEC[i],tag+"decision "+ER_DecisionName(o.decision)+" expected "+X_DEC[i]+" ("+o.reason+")");
         Check(ok==(X_DEC[i]=="CONFIRMED"),tag+"return value matches the decision");
         Check(EA_StateName(st.status)==X_STATE[i],tag+"state "+EA_StateName(st.status)+" expected "+X_STATE[i]);
         Check(o.linked_steps==X_LINKED[i] && o.duplicates==X_DUP[i] && o.unlinked==X_UNL[i],tag+"linked steps, duplicates, unlinked");
         Check((int)o.changed==X_CHG[i],tag+"changed flag");
         Check(st.confirmations==X_CONF[i],tag+"confirmations");
         Check(SamePlan(before,st),tag+"the 80/20 plan is unchanged");
         if(X_DEC[i]!="CONFIRMED" && X_DEC[i]!="NOT_EXECUTED")
            Check(o.reason!="",tag+"reason reported");
         if(X_DEC[i]=="INVALID_INPUT" || ((X_DEC[i]=="UNKNOWN" || X_DEC[i]=="NOT_EXECUTED") && before.status!=EA_ST_DONE))
            Check(SameState(before,st),tag+"no state change for this decision");
        }
     }
  }
void TestDirect(void)
  {
   double nan=MathSqrt(-1.0);
   double inf=MathExp(1000.0);
   SEaState st,before;
   SEaResult r;
   SErOutcome o;
   SErSnapshot snap;
   // invalid snapshots change nothing
   for(int k=0;k<9;k++)
     {
      EA_StateInit(st);
      EA_OnQuote(st,7,1,2000.0,2000.0,2000.3,0.5,0.5,0.01,0.01,100.0,r);
      before=st;
      ER_SnapshotInit(snap,true,7,"X2R80-7",0.01,0.1,false);
      ER_AddExec(snap,"e1","X2R80-7",0.4);
      if(k==0) snap.position_id=0;
      if(k==1) snap.request_id="";
      if(k==2) snap.volume_step=nan;
      if(k==3) snap.volume_step=0.0;
      if(k==4) snap.volume_current=inf;
      if(k==5) snap.volume_current=0.0;
      if(k==6) snap.exec[0].volume=nan;
      if(k==7) snap.exec[0].exec_id="";
      if(k==8) snap.n_exec=17;
      ER_Reconcile(st,snap,o);
      Check(o.decision==ER_INVALID_INPUT && SameState(before,st),StringFormat("invalid snapshot variant %d is INVALID_INPUT and changes nothing",k));
     }
   // 16 executions are accepted, the 17th cannot be added
   EA_StateInit(st);
   EA_OnQuote(st,7,1,2000.0,2000.0,2000.3,0.5,0.5,0.01,0.01,100.0,r);
   ER_SnapshotInit(snap,true,7,"X2R80-7",0.01,0.1,false);
   bool added=true;
   for(int i=0;i<15;i++)
      added=added && ER_AddExec(snap,"e"+IntegerToString(i),"X2R80-7",0.02);
   added=added && ER_AddExec(snap,"e15","X2R80-7",0.1);
   Check(added && snap.n_exec==16 && !ER_AddExec(snap,"e16","X2R80-7",0.01),"16 executions fit, the 17th is refused");
   Check(ER_Reconcile(st,snap,o) && o.decision==ER_CONFIRMED && o.linked_steps==40 && st.status==EA_ST_DONE,"16 executions summing to the request confirm it");
   // idempotence: the same partial snapshot twice changes nothing the second time
   EA_StateInit(st);
   EA_OnQuote(st,7,1,2000.0,2000.0,2000.3,0.5,0.5,0.01,0.01,100.0,r);
   ER_SnapshotInit(snap,true,7,"X2R80-7",0.01,0.4,false);
   ER_AddExec(snap,"e1","X2R80-7",0.1);
   ER_Reconcile(st,snap,o);
   before=st;
   ER_Reconcile(st,snap,o);
   Check(o.decision==ER_PARTIAL && !o.changed && SameState(before,st),"the same partial snapshot twice: second time changes nothing");
   // a late fill after a timeout is accepted only through the snapshot: quotes and plain reports cannot unblock
   EA_StateInit(st);
   EA_OnQuote(st,7,1,2000.0,2000.0,2000.3,0.5,0.5,0.01,0.01,100.0,r);
   EA_OnReport(st,"X2R80-7",EA_REP_TIMEOUT,0.0,0.01,r);
   EA_OnQuote(st,7,1,2000.0,2005.0,2005.3,0.5,0.1,0.01,0.01,100.0,r);
   EA_OnReport(st,"X2R80-7",EA_REP_FULL,0.4,0.01,r);
   Check(st.status==EA_ST_NEEDS_RECONCILIATION && st.confirmations==0,"after a timeout a quote and a plain report cannot unblock");
   ER_SnapshotInit(snap,true,7,"X2R80-7",0.01,0.1,false);
   ER_AddExec(snap,"e1","X2R80-7",0.4);
   Check(ER_Reconcile(st,snap,o) && st.status==EA_ST_DONE && st.confirmations==1,"the late fill is accepted through the snapshot");
  }
void OnStart()
  {
   RunRows();
   TestDirect();
   PrintFormat("T011 RECONCILE TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
