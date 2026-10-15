// T013 compile probe ONLY: includes the executor and the REAL transport / store so that MetaEditor checks their syntax. It calls NONE of the real methods and sends nothing.
#property strict
#include "../include/EntryExecutor.mqh"
#include "../include/EntryTransportReal.mqh"
void OnStart()
  {
   Print("T013 ENTRY REAL COMPILE PROBE: nothing is executed, no order, no read, no file.");
  }
