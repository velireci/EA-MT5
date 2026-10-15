// T011 executor REAL-transport COMPILE CHECK ONLY. It includes ExitTransportReal.mqh so that MetaEditor can check the syntax and constructs the class, but it calls NONE of
// its methods: no account read, no position read, no OrderCheck, no OrderSend. Nothing here can send, modify or close anything. Not an automatic test; not part of any test run.
#property strict
#property version "1.00"
#property description "T011 real transport compile check only. Calls nothing."
#include "../include/ExitTransportReal.mqh"

void OnStart()
  {
   CRealTransport transport;
   Print("T011 EXECUTOR REAL COMPILE CHECK: the real transport class compiles; none of its methods is called; nothing was read, checked or sent.");
  }
