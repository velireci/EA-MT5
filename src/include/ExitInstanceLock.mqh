// T011 INSTANCE LOCK: keeps two instances of the demo harness / open-position script from acting on the same account + position at the SAME time inside ONE terminal.
// Mechanism: a TEMPORARY terminal global variable (it does not survive a terminal restart) used as a mutex through GlobalVariableSetOnCondition, which the
// documentation (search snippets only; the official page could not be opened) describes as atomic within one client terminal and as failing, without creating the
// variable, when it does not exist. Acquire = create the temporary variable if it is missing, then SetOnCondition(key, 1, 0). Release = set it back to 0, and only by the instance that holds it.
// LIMITS (do not overstate): (1) the lock is per TERMINAL: two different terminals (even on the same computer or the same account) have separate global variables and separate MQL5/Files
// folders, so NOTHING here protects between terminals - the owner must run one terminal against an account for this test; (2) a script that dies without releasing leaves the lock held until
// the terminal restarts or the owner resets the variable by hand: that blocks (the safe direction) and nothing deletes it automatically; (3) the initial value of a new temporary variable
// and the SetOnCondition semantics are UNVERIFIED until T011_DemoHarnessTest runs in MT5; (4) it does not protect against a manual action of the owner in the terminal.
#ifndef VELO_EXIT_INSTANCE_LOCK_MQH
#define VELO_EXIT_INSTANCE_LOCK_MQH

string EL_Key(const long login,const ulong position_id)
  {
   return("VELO_T011_LOCK_"+IntegerToString(login)+"_"+IntegerToString((long)position_id));
  }

// true = this caller now holds the lock. `held` is the caller's own flag (release is only allowed when it is true).
bool EL_Acquire(const string key,bool &held,string &reason)
  {
   held=false;
   reason="";
   if(key=="") {reason="LOCK_KEY_EMPTY"; return(false);}
   if(!GlobalVariableCheck(key))
      GlobalVariableTemp(key);
   if(!GlobalVariableCheck(key)) {reason="LOCK_VARIABLE_NOT_AVAILABLE"; return(false);}
   ResetLastError();
   if(!GlobalVariableSetOnCondition(key,1.0,0.0))
     {
      reason=StringFormat("INSTANCE_LOCK_HELD: another instance holds %s in this terminal (or the lock variable is in an unexpected state; error %d); nothing is done",key,GetLastError());
      return(false);
     }
   held=true;
   return(true);
  }

void EL_Release(const string key,bool &held)
  {
   if(!held) return;
   GlobalVariableSet(key,0.0);
   held=false;
  }
#endif
