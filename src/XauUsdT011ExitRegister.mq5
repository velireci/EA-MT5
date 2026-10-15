//+------------------------------------------------------------------+
//| XauUsdT011ExitRegister.mq5                                       |
//| T011 EXPLICIT REGISTRATION of the exit plan of ONE existing,     |
//| owned position (script). DISABLED BY DEFAULT (InpEnabled=false). |
//| It is the only way to create the state file read by the tick-path |
//| EA XauUsdT011ExitManager.mq5: the EA never registers anything.   |
//| The 2R level is DERIVED (TG_Compute, R_GEOM): entry = the open   |
//| price of the position read once now; stop = the INITIAL stop the |
//| owner asserts here, accepted only while the position's live SL   |
//| still equals it. R_GEOM is a price distance, NOT the client's    |
//| final R (costs open); InpRPolicy = UNSET blocks. A manual or     |
//| foreign position (other magic / symbol / direction) is never     |
//| adopted. Never overwrites a file. Sends NO request.              |
//| One lock (per terminal only) around the registration.            |
//| UNVERIFIED: not compiled or run by the author.                   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs
#property version "1.00"
#property description "T011 explicit exit-plan registration. Disabled by default. Demo accounts only."
#include "include/ExitTickDriver.mqh"
#include "include/ExitTransportReal.mqh"

input bool InpEnabled=false;                            // false = nothing happens
input string InpAuthorisation="";                       // type I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE deliberately (the real transport reads the account and the position)
input ENUM_ETD_RPOLICY InpRPolicy=ETD_RPOL_UNSET;       // UNSET = refused. R_GEOM = price distance |open price - initial SL|; not the final client R (costs open)
input long InpEaMagic=0;                                // magic of the owned position (> 0); a manual position (magic 0) is never adopted
input long InpPositionId=0;                             // POSITION_IDENTIFIER (not the ticket); 0 = unset
input string InpSymbol="";                              // must equal the chart symbol
input ENUM_ETD_DIRECTION InpDirection=ETD_DIR_UNSET;    // exactly BUY or SELL; UNSET = refused
input double InpInitialSl=0;                            // the INITIAL stop, asserted by the owner; must equal the live SL of the position now. 0 = unset
input double InpTpPrice=0;                              // TP of the plan, strictly beyond the derived 2R level (TP == 2R or before it is refused). 0 = unset
input double InpVolumeInitial=0;                        // initial volume = the volume of the position; the 80/20 split must be realisable. 0 = unset

void Stop(const string reason)
  {
   Print("T011 EXIT REGISTER: STOP ",reason,". Nothing was registered.");
  }

void OnStart()
  {
   Print("T011 EXIT REGISTER: explicit registration; disabled by default; sends no request; the tick-path EA never registers.");
   if(!InpEnabled) {Stop("DISABLED (InpEnabled = false)"); return;}
   if((int)InpDirection!=(int)ETD_DIR_BUY && (int)InpDirection!=(int)ETD_DIR_SELL) {Stop("INPUT_UNSET_OR_INVALID: direction must be exactly BUY or SELL"); return;}
   if((int)InpRPolicy!=(int)ETD_RPOL_R_GEOM) {Stop("INPUT_UNSET: InpRPolicy (R_GEOM is the only implemented value; it does not settle the client's final R or the costs)"); return;}
   if(InpPositionId<=0) {Stop("INPUT_UNSET: position id"); return;}
   if(InpSymbol=="" || InpSymbol!=_Symbol) {Stop("INPUT_UNSET_OR_WRONG: symbol must be set and equal to the chart symbol"); return;}
   SExConfig cfg;
   EX_ConfigInit(cfg);
   cfg.enabled=true;
   cfg.r_policy=EX_RPOL_R_GEOM;
   cfg.real_authorised=(InpAuthorisation==EX_AUTH_PHRASE);
   cfg.authorisation=InpAuthorisation;
   cfg.ea_magic=InpEaMagic;
   cfg.sl_initial_set=(InpInitialSl>0.0);
   cfg.sl_initial=InpInitialSl;
   cfg.tp_set=(InpTpPrice>0.0);
   cfg.tp_price=InpTpPrice;
   SExQuote q;
   q.direction=(int)InpDirection;
   q.level_2r=0.0;                          // ignored in R_GEOM: the level is derived
   q.bid=0.0;
   q.ask=0.0;
   q.volume_initial=InpVolumeInitial;
   CRealTransport transport;
   SExAccount acct;
   transport.ReadAccount(acct);
   if(!acct.read_ok) {Stop("ACCOUNT_UNREADABLE"); return;}
   SEsIdentity id;
   id.server=acct.server;
   id.login=acct.login;
   id.symbol=InpSymbol;
   id.position_id=(ulong)InpPositionId;
   string name=ESF_FileName(acct.login,(ulong)InpPositionId);
   SExRuntime rt;
   EX_RuntimeInit(rt);
   SExResult res;
   bool ok=ETD_Register(cfg,GetPointer(transport),rt,name,id,q,res);
   PrintFormat("T011 EXIT REGISTER RESULT: ok %d | %s | file %s | %s",(int)ok,EX_FinalName(res.final_state),name,res.reason);
   Print("T011 EXIT REGISTER: nothing was deleted or overwritten. The record must be read back by STATUS before the EA is enabled; the lock is per terminal only.");
  }
