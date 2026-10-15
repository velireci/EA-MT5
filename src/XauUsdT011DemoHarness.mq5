//+------------------------------------------------------------------+
//| XauUsdT011DemoHarness.mq5                                        |
//| T011 DEMO HARNESS (script). DISABLED BY DEFAULT (InpStep = NONE).|
//| One step per run: STATUS (read-only) / REGISTER / ACTIVATE /     |
//| RECONCILE, over the existing T011 modules. Real trading call     |
//| only in ACTIVATE, and only with: the authorisation phrase, a     |
//| DEMO account, InpConfirmSendOnce = true, a registered plan, a    |
//| record that is IDLE, a position found by identifier with the     |
//| configured magic, and every mandatory parameter set.             |
//| No H4/M15 signal, no strategy, no live trading. The test         |
//| parameters are DIAGNOSTIC, chosen by the owner for this one test.|
//| Nothing here deletes a record or clears RECOVERY_REQUIRED.       |
//| NOT protected between different terminals (see ExitInstanceLock).|
//| UNVERIFIED: not compiled or run by the author.                   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs
#property version "1.00"
#property description "T011 demo harness. Disabled by default. Demo accounts only."
#include "include/DemoHarness.mqh"
#include "include/ExitTransportReal.mqh"

input ENUM_DM_STEP InpStep=DM_STEP_NONE;               // NONE = disabled. STATUS = read-only. REGISTER / ACTIVATE / RECONCILE act (one step per run)
input string InpAuthorisation="";                       // type the phrase I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE deliberately; empty = every acting step is refused
input bool InpConfirmSendOnce=false;                    // ACTIVATE only: must be true, otherwise ACTIVATE is refused (it is the only step that can send one trading request)
input long InpEaMagic=0;                                // magic number of the demo position (> 0). 0 = unset = refused. A manual position (magic 0) is never adopted
input long InpPositionId=0;                             // POSITION_IDENTIFIER of the demo position (not the ticket). 0 = unset
input string InpSymbol="";                              // symbol of the position; must equal the position's symbol. Empty = unset
input ENUM_DM_DIRECTION InpDirection=DM_DIR_UNSET;      // direction of the position; UNSET = refused
input double InpLevel2R=-1;                             // DIAGNOSTIC level that arms the test partial close (BUY: bid >= level, SELL: ask <= level), on the tick grid. -1 = unset
input double InpTpPrice=-1;                             // TP of the plan: strictly beyond the level (TP == level is refused). -1 = unset
input double InpVolumeInitial=0;                        // initial volume of the position; must equal the position volume; 80/20 must be realisable. 0 = unset
input ENUM_EX_FILLING InpFilling=EX_FILL_UNSET;         // filling of the closing request; UNSET = refused (a test parameter, not a strategy decision)
input long InpDeviation=-1;                             // deviation in points of the closing request; -1 = unset = refused
input ENUM_EX_FILTER_POLICY InpFilterPolicy=EX_POL_UNSET;   // exit behaviour towards spread / news / session filters; UNSET = refused
input ENUM_EX_FILTER_STATE InpFilterState=EX_FS_UNKNOWN;    // state of those filters supplied by the owner (used only with NEEDS_CLEAR)

void OnStart()
  {
   Print("T011 DEMO HARNESS: step ",EnumToString(InpStep),". Disabled by default; demo accounts only; no signal, no strategy; the real transport is used only after every gate.");
   SDmParams p;
   DM_ParamsInit(p);
   p.step=InpStep;
   p.authorisation=InpAuthorisation;
   p.confirm_send_once=InpConfirmSendOnce;
   p.magic=InpEaMagic;
   p.position_id=InpPositionId;
   p.symbol=InpSymbol;
   p.direction=InpDirection;
   p.level_2r=InpLevel2R;
   p.tp_price=InpTpPrice;
   p.volume_initial=InpVolumeInitial;
   p.filling=InpFilling;
   p.deviation=InpDeviation;
   p.filter_policy=InpFilterPolicy;
   p.filter_state=InpFilterState;
   p.use_lock=true;
   SDmQuote quote;
   quote.read_ok=false;
   quote.bid=0.0;
   quote.ask=0.0;
   if(InpSymbol!="" && (InpStep==DM_STEP_ACTIVATE || InpStep==DM_STEP_STATUS))
     {
      MqlTick tick;
      if(SymbolInfoTick(InpSymbol,tick))
        {
         quote.read_ok=true;
         quote.bid=tick.bid;
         quote.ask=tick.ask;
        }
      if(InpStep==DM_STEP_STATUS)
         PrintFormat("T011 DEMO HARNESS: quote %s bid %s ask %s | tick size %s | digits %d | a BUY level is reached when bid >= level, a SELL level when ask <= level. For the test choose a level on the tick grid at or just below the BUY bid (above the SELL ask) so that the activation is reached at once; the TP must stay strictly beyond it.",
                     InpSymbol,DoubleToString(tick.bid,(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS)),DoubleToString(tick.ask,(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS)),
                     DoubleToString(SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_SIZE),(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS)),(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS));
     }
   CRealTransport transport;
   SXaRaw unused_a,unused_b;
   XA_RawInit(unused_a);
   XA_RawInit(unused_b);
   SDmResult res;
   bool ok=DM_Run(p,GetPointer(transport),quote,unused_a,unused_b,res);
   PrintFormat("T011 DEMO HARNESS RESULT: step %s | ok %d | status %s | sends %d | file %s | %s",EnumToString(InpStep),(int)ok,res.status,res.sends,res.file,res.detail);
   Print("T011 DEMO HARNESS: nothing was deleted or cleaned. A RECOVERY_REQUIRED record stays until the owner and Codex decide; the lock is per terminal only.");
  }
