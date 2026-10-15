//+------------------------------------------------------------------+
//| XauUsdT012BalanceStore.mq5                                       |
//| T012 DAY-BALANCE STORE script. DEFAULT = LOAD: strictly         |
//| READ-ONLY, never creates a file. A capture needs an explicit     |
//| action AND InpConfirmCapture = true. Base = ACCOUNT_BALANCE.     |
//| WINDOW_EMPTY is a CONDITIONAL proof over a history the owner     |
//| declares complete (InpHistoryComplete) with an explicit server   |
//| offset; it is not a guarantee of the terminal. OWNER_ASSERTED is |
//| a separate, explicit source (amount + day) and is never promoted.|
//| Never overwrites, never deletes, no order, no policy, no EA.     |
//| Does not touch any T011 file. UNVERIFIED: not compiled or run.   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs
#property version "1.00"
#property description "T012 day-balance store. Default: read-only LOAD."
#include "include/DailyBalanceStore.mqh"

enum ENUM_DBS_ACTION
  {
   DBS_ACT_LOAD=0,                   // read-only (default)
   DBS_ACT_CAPTURE_WINDOW_EMPTY,     // explicit: store the balance if the day window is proven empty
   DBS_ACT_CAPTURE_OWNER_ASSERTED    // explicit: store the amount the owner states for the current Tirane day
  };

input ENUM_DBS_ACTION InpAction=DBS_ACT_LOAD;          // LOAD never creates a file. A capture is an explicit action
input bool InpConfirmCapture=false;                    // must be true for any capture
input long InpEaMagic=0;                               // only to satisfy the history facts' configuration (> 0) for WINDOW_EMPTY; the emptiness check covers EVERY magic and every deal type
input int InpServerOffsetSeconds=2147483647;           // WINDOW_EMPTY: broker server offset from UTC in seconds (multiple of 900); 2147483647 = unset = refused
input bool InpHistoryComplete=false;                   // WINDOW_EMPTY: the OWNER asserts that the history held by the terminal is complete; false = refused
input double InpOwnerAmount=0;                         // OWNER_ASSERTED: the balance at the start of the day, as the owner states it (> 0)
input int InpOwnerDay=0;                               // OWNER_ASSERTED: the Tirane day it is for (yyyymmdd); must be the current Tirane day

void OnStart()
  {
   Print("T012 BALANCE STORE: default LOAD is read-only. A capture is explicit; the file is never overwritten or deleted; base = ACCOUNT_BALANCE; no order, no policy.");
   if(MQLInfoInteger(MQL_TESTER)) {Print("T012 BALANCE STORE: STOP TESTER_UNAVAILABLE: TimeGMT, the account and the history are not real in the Strategy Tester. Nothing was read or written."); return;}
   if(!DBS_ActionKnown((int)InpAction)) {PrintFormat("T012 BALANCE STORE: STOP unknown InpAction %d (only 0, 1, 2 are accepted). Nothing was read or written.",(int)InpAction); return;}
   CDbsRealPort port(InpEaMagic,InpServerOffsetSeconds==DBS_OFFSET_UNSET ? 0 : InpServerOffsetSeconds,InpHistoryComplete,_Symbol);
   SDbsResult res;
   if((int)InpAction==(int)DBS_ACT_LOAD)
      DBS_Load(port,res);
   else
     {
      if(!InpConfirmCapture) {Print("T012 BALANCE STORE: STOP InpConfirmCapture is false. Nothing was read or written."); return;}
      SDbsAsserts a;
      a.complete=InpHistoryComplete;
      a.offset=InpServerOffsetSeconds;
      if((int)InpAction==(int)DBS_ACT_CAPTURE_WINDOW_EMPTY)
        {
         if(InpEaMagic<=0) {Print("T012 BALANCE STORE: STOP InpEaMagic must be > 0 (history configuration). Nothing was written."); return;}
         DBS_Capture(port,DBS_SRC_WE,a,InpOwnerAmount,InpOwnerDay,res);
        }
      else
         if((int)InpAction==(int)DBS_ACT_CAPTURE_OWNER_ASSERTED)
            DBS_Capture(port,DBS_SRC_OA,a,InpOwnerAmount,InpOwnerDay,res);
         else
           {
            Print("T012 BALANCE STORE: STOP unknown InpAction. Nothing was read or written.");
            return;
           }
     }
   PrintFormat("T012 BALANCE STORE RESULT: action %s | status %s | known %d | day %d | amount %s | source %s | written %d | existed %d | %s",EnumToString(InpAction),DBS_StatusName(res.status),(int)res.balance.known,
               res.balance.day,DoubleToString(res.balance.amount,2),res.source,(int)res.written,(int)res.existed,res.reason);
   Print("T012 BALANCE STORE: nothing was deleted or overwritten. A damaged, partial or foreign file blocks the data until the owner removes it by hand.");
  }
