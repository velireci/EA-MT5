// T011 DEMO OPEN-POSITION GUARD: the locked decision sequence of XauUsdT011DemoOpenPosition.mq5, separated from the terminal so that it can be tested with a fake port.
// Not general infrastructure: it exists only for that one demo-only step. Mirrors tests/t011_demo_open_reference.py.
// SEQUENCE (all of it INSIDE the instance lock): acquire -> an open-intent file of this account + magic must NOT exist -> no position with this magic and symbol is visible ->
// no pending order with this magic and symbol is visible -> read-only pre-check of the request -> the open INTENT is written and read back -> ONE send -> release.
// The scan for an existing position / order therefore happens after the lock is taken and is never based on an earlier look.
// UNCERTAIN OUTCOME: the absence of a visible position right after a send proves nothing (the request may have been accepted and not shown yet), and a restart can happen at any time.
// The intent file is written BEFORE the send and is NEVER removed by any code: whatever the outcome, the next run is blocked while the file exists (even a half-written one),
// until the owner has inspected the terminal (positions, orders, history) and removed the file BY HAND. No retry, no automatic clean-up, no automatic reconciliation.
// Limits: the lock protects one terminal only; the intent file lives in this terminal's MQL5/Files folder.
#ifndef VELO_DEMO_OPEN_GUARD_MQH
#define VELO_DEMO_OPEN_GUARD_MQH

#include "ExitStateFile.mqh"
#include "ExitInstanceLock.mqh"

class COpenPort
  {
public:
   virtual int CountPositions(void)=0;          // positions with this magic and symbol; -1 = unreadable
   virtual int CountOrders(void)=0;             // pending orders with this magic and symbol; -1 = unreadable
   virtual bool PreCheck(void)=0;               // read-only validation of the request (OrderCheck in the real port)
   virtual void Send(string &detail)=0;         // THE ONLY trading call; the real port prints its result into `detail`
  };

struct SOpenOutcome
  {
   bool sent;
   int sends;
   string status;       // BLOCKED / SENT
   string reason;
  };

string OPG_IntentName(const long login,const long magic)
  {
   return("VELO_T011_DEMO_OPEN_INTENT_"+IntegerToString(login)+"_"+IntegerToString(magic)+".txt");
  }

string OPG_LockKey(const long login,const long magic)
  {
   return("VELO_T011_LOCK_OPEN_"+IntegerToString(login)+"_"+IntegerToString(magic));
  }

// the intent text: what is about to be sent, with a checksum; ASCII only
string OPG_IntentText(const long login,const string server,const string symbol,const long magic,const int direction,const double volume,const double sl,const double tp,
                      const int filling,const long deviation)
  {
   string b="VELO_T011_OPEN_INTENT\nVERSION=1\nLOGIN="+IntegerToString(login)+"\nSERVER="+ESC_Escape(server)+"\nSYMBOL="+ESC_Escape(symbol)+"\nMAGIC="+IntegerToString(magic)+
            "\nDIRECTION="+IntegerToString(direction)+"\nVOLUME="+DoubleToString(volume,8)+"\nSL="+DoubleToString(sl,8)+"\nTP="+DoubleToString(tp,8)+
            "\nFILLING="+IntegerToString(filling)+"\nDEVIATION="+IntegerToString(deviation)+"\nSTATE=INTENT_WRITTEN_BEFORE_THE_SEND\nEND\n";
   return(b+"CRC="+StringFormat("%08X",ESC_Crc32(b))+"\n");
  }

void OPG_Block(SOpenOutcome &o,const string reason)
  {
   o.status="BLOCKED";
   o.reason=reason;
  }

// Returns true only when ONE request was sent.
bool OPG_Run(COpenPort &port,const string lock_key,const string intent_name,const string intent_text,SOpenOutcome &o)
  {
   o.sent=false;
   o.sends=0;
   o.status="BLOCKED";
   o.reason="";
   bool held=false;
   string why;
   if(!EL_Acquire(lock_key,held,why)) {OPG_Block(o,why); return(false);}
   // ---- everything below is inside the lock
   if(ESF_Exists(intent_name))
     {
      string old="";
      ESF_ReadAll(intent_name,old);
      OPG_Block(o,"OPEN_INTENT_EXISTS: "+intent_name+" is present, so an earlier run may have sent a request that is not visible yet. Nothing is sent. Inspect the terminal (positions, orders, history) and remove the file BY HAND only after you have reconciled it; no code removes it. Content: "+old);
      EL_Release(lock_key,held);
      return(false);
     }
   int np=port.CountPositions();
   if(np<0) {OPG_Block(o,"POSITIONS_UNREADABLE"); EL_Release(lock_key,held); return(false);}
   if(np>0) {OPG_Block(o,"A_POSITION_WITH_THIS_MAGIC_ALREADY_EXISTS: this step never opens a second one"); EL_Release(lock_key,held); return(false);}
   int no=port.CountOrders();
   if(no<0) {OPG_Block(o,"ORDERS_UNREADABLE"); EL_Release(lock_key,held); return(false);}
   if(no>0) {OPG_Block(o,"AN_ORDER_WITH_THIS_MAGIC_ALREADY_EXISTS: this step never opens while an order is pending"); EL_Release(lock_key,held); return(false);}
   if(!port.PreCheck()) {OPG_Block(o,"PRECHECK_FAILED: nothing persisted, nothing sent"); EL_Release(lock_key,held); return(false);}
   string back="";
   if(!ESF_WriteAll(intent_name,intent_text) || !ESF_ReadAll(intent_name,back) || back!=intent_text)
     {
      OPG_Block(o,"OPEN_INTENT_NOT_VERIFIED: the intent could not be written and read back; nothing is sent (a partial file, if any, keeps blocking until removed by hand)");
      EL_Release(lock_key,held);
      return(false);
     }
   string detail="";
   o.sends=1;
   port.Send(detail);
   o.sent=true;
   o.status="SENT";
   o.reason="ONE request sent; the open intent stays on disk and blocks the next run until it is reconciled by hand. "+detail;
   EL_Release(lock_key,held);
   return(true);
  }
#endif
