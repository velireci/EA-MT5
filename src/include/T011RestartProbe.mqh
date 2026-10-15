// T011 restart PROBE: the shared, fully filled-in test parameters of XauUsdT011RestartPrepare.mq5 and XauUsdT011RestartRestore.mq5. Diagnostic only.
// A SYNTHETIC position identifier (declared, not a real position) and fixed plan numbers are used so the owner supplies no input. The files are named
// VELO_T011_RESTART_PROBE.state (+ ".tmp"): never the production name (ESF_FileName) and never the names of T011_PersistFileTest. Nothing here reads or changes a
// position, order or symbol; the only terminal reads are the account SERVER name and LOGIN (the identity stored in the record). No order API, no retry, no clock.
#ifndef VELO_T011_RESTART_PROBE_MQH
#define VELO_T011_RESTART_PROBE_MQH

#include "ExitStateFile.mqh"

#define RP_FILE "VELO_T011_RESTART_PROBE.state"
#define RP_POSITION 777000001            // declared probe position identifier: NOT a real position
#define RP_SYMBOL "T011PROBE"            // declared probe symbol label: no market data is read
#define RP_DIRECTION 1
#define RP_LEVEL 4310.5
#define RP_BID 4310.6
#define RP_ASK 4310.9
#define RP_VOLUME_INITIAL 0.5
#define RP_VOLUME_MIN 0.01
#define RP_VOLUME_STEP 0.01
#define RP_VOLUME_MAX 100.0
#define RP_EXPECT_INITIAL_STEPS 50
#define RP_EXPECT_REQUEST_STEPS 40
#define RP_EXPECT_CLOSE_VOLUME 0.4
#define RP_EXPECT_GENERATION 2

// false when the account identity cannot be read (nothing is stored or restored then)
bool RP_Identity(SEsIdentity &id,string &reason)
  {
   reason="";
   ResetLastError();
   id.server=AccountInfoString(ACCOUNT_SERVER);
   id.login=AccountInfoInteger(ACCOUNT_LOGIN);
   id.symbol=RP_SYMBOL;
   id.position_id=(ulong)RP_POSITION;
   if(id.server=="" || id.login<=0)
     {
      reason=StringFormat("ACCOUNT_IDENTITY_UNAVAILABLE: server '%s' login %I64d (error %d)",id.server,id.login,GetLastError());
      return(false);
     }
   return(true);
  }

// one quote of the probe plan at `bid` (ask = bid + 0.3); returns EA_OnQuote's answer
bool RP_Quote(SEaState &s,SEaResult &r,const double bid)
  {
   return(EA_OnQuote(s,(ulong)RP_POSITION,RP_DIRECTION,RP_LEVEL,bid,bid+(RP_ASK-RP_BID),RP_VOLUME_INITIAL,RP_VOLUME_INITIAL,RP_VOLUME_MIN,RP_VOLUME_STEP,RP_VOLUME_MAX,r));
  }
#endif
