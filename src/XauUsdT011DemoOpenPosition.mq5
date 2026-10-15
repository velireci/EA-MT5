//+------------------------------------------------------------------+
//| XauUsdT011DemoOpenPosition.mq5                                   |
//| T011 DEMO-ONLY SEPARATE STEP: opens ONE test position with an    |
//| explicit volume and SL / TP distances and the robot's magic, so that the demo|
//| harness has an OWNED position (a manual position is never        |
//| adopted). DISABLED BY DEFAULT. The owner authorises it separately|
//| AFTER Codex has reviewed this file. It is not a strategy, not a  |
//| signal and not an entry rule; it writes no state file.           |
//| Contains the only OrderSend outside ExitTransportReal.mqh.        |
//| Gates: enabled, the phrase I_AUTHORISE_T011_DEMO_OPEN_POSITION,  |
//| DEMO account, HEDGING, trading allowed, volume/SL/TP/direction/  |
//| magic/filling/deviation all set and on the symbol grid, the 80/20|
//| split realisable, SL and TP on the correct side, OrderCheck ok,  |
//| no open position of this magic on the symbol, instance lock.     |
//| UNVERIFIED: not compiled or run by the author.                   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs
#property version "1.00"
#property description "T011 demo-only: opens ONE test position. Disabled by default. Demo accounts only."
#include "include/ExitExecutor.mqh"
#include "include/ExitInstanceLock.mqh"

#define OP_AUTH_PHRASE "I_AUTHORISE_T011_DEMO_OPEN_POSITION"
enum ENUM_OP_DIRECTION {OP_DIR_UNSET=0,OP_DIR_BUY=1,OP_DIR_SELL=-1};

input bool InpEnabled=false;                            // false = nothing happens. The owner sets true only after Codex's review
input string InpAuthorisation="";                       // type I_AUTHORISE_T011_DEMO_OPEN_POSITION deliberately
input long InpEaMagic=0;                                // magic of the test position (> 0)
input string InpSymbol="";                              // must equal the chart symbol
input ENUM_OP_DIRECTION InpDirection=OP_DIR_UNSET;
input double InpVolume=0;                               // explicit volume, on the symbol volume grid, with a realisable 80/20 split
input double InpStopLossDistance=0;                     // explicit SL distance from the entry price in price units (> 0, a multiple of the tick size); the SL is placed on the losing side
input double InpTakeProfitDistance=0;                   // explicit TP distance from the entry price in price units (> 0, a multiple of the tick size); keep it larger than the level distance you will use in the harness
input ENUM_EX_FILLING InpFilling=EX_FILL_UNSET;
input long InpDeviation=-1;

void Stop(const string reason)
  {
   Print("T011 DEMO OPEN POSITION: STOP ",reason,". Nothing was sent.");
  }

void OnStart()
  {
   Print("T011 DEMO OPEN POSITION: demo-only separate step, disabled by default; opens ONE test position; not a strategy or a signal.");
   if(!InpEnabled) {Stop("DISABLED (InpEnabled = false)"); return;}
   if(InpAuthorisation!=OP_AUTH_PHRASE) {Stop("REAL_NOT_AUTHORISED: the phrase is missing or wrong"); return;}
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO) {Stop("NOT_A_DEMO_ACCOUNT"); return;}
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {Stop("UNSUPPORTED_ACCOUNT_MODE: only HEDGING"); return;}
   if(!(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)!=0 && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)!=0 && AccountInfoInteger(ACCOUNT_TRADE_EXPERT)!=0 && MQLInfoInteger(MQL_TRADE_ALLOWED)!=0))
     {Stop("TRADING_NOT_ALLOWED"); return;}
   if(InpEaMagic<=0) {Stop("INPUT_UNSET: magic"); return;}
   if(InpSymbol=="" || InpSymbol!=_Symbol) {Stop("INPUT_UNSET_OR_WRONG: symbol must be set and equal to the chart symbol"); return;}
   if(InpDirection==OP_DIR_UNSET) {Stop("INPUT_UNSET: direction"); return;}
   if((int)InpFilling<(int)EX_FILL_FOK || (int)InpFilling>(int)EX_FILL_RETURN) {Stop("INPUT_UNSET_OR_INVALID: filling"); return;}
   if(InpDeviation<0) {Stop("INPUT_UNSET: deviation"); return;}
   double vmin=SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MIN),vstep=SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_STEP),vmax=SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MAX);
   double tick=SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_SIZE);
   if(!(vmin>0.0 && vstep>0.0 && vmax>=vmin && tick>0.0)) {Stop("SYMBOL_PARAMETERS_UNREADABLE"); return;}
   if(!EX_Finite(InpVolume) || InpVolume<vmin || InpVolume>vmax || !EX_OnGrid(InpVolume,vstep)) {Stop("INPUT_UNSET_OR_OFF_GRID: volume"); return;}
   if(!EX_OnGrid(InpStopLossDistance,tick) || !EX_OnGrid(InpTakeProfitDistance,tick)) {Stop("INPUT_UNSET_OR_OFF_GRID: SL or TP distance"); return;}
   SEsResult sp;
   ES_Split(InpVolume,vmin,vstep,vmax,sp);
   if(sp.status!=ES_OK) {Stop("SPLIT_NOT_REALISABLE: "+ES_StatusName(sp.status)+" "+sp.reason); return;}
   MqlTick t;
   if(!SymbolInfoTick(InpSymbol,t) || !(t.bid>0.0) || !(t.ask>0.0)) {Stop("QUOTE_UNAVAILABLE"); return;}
   bool buy=(InpDirection==OP_DIR_BUY);
   int pdigits=(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS);
   double sl=NormalizeDouble(buy ? t.ask-InpStopLossDistance : t.bid+InpStopLossDistance,pdigits);
   double tp=NormalizeDouble(buy ? t.ask+InpTakeProfitDistance : t.bid-InpTakeProfitDistance,pdigits);
   if(!EX_OnGrid(sl,tick) || !EX_OnGrid(tp,tick) || sl<=0.0 || tp<=0.0) {Stop("SL_OR_TP_NOT_ON_THE_TICK_GRID_OR_NOT_POSITIVE"); return;}
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk!=0 && PositionGetString(POSITION_SYMBOL)==InpSymbol && PositionGetInteger(POSITION_MAGIC)==InpEaMagic)
        {Stop("A_POSITION_WITH_THIS_MAGIC_ALREADY_EXISTS: this step never opens a second one"); return;}
     }
   bool held=false;
   string why;
   string key="VELO_T011_LOCK_OPEN_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+IntegerToString(InpEaMagic);
   if(!EL_Acquire(key,held,why)) {Stop(why); return;}
   MqlTradeRequest r;
   ZeroMemory(r);
   r.action=TRADE_ACTION_DEAL;
   r.symbol=InpSymbol;
   r.volume=InpVolume;
   r.type=(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   r.price=(buy ? t.ask : t.bid);
   r.sl=sl;
   r.tp=tp;
   r.deviation=(ulong)InpDeviation;
   r.magic=(ulong)InpEaMagic;
   r.comment="T011DEMO";
   r.type_filling=(InpFilling==EX_FILL_FOK ? ORDER_FILLING_FOK : (InpFilling==EX_FILL_IOC ? ORDER_FILLING_IOC : ORDER_FILLING_RETURN));
   MqlTradeCheckResult c;
   ZeroMemory(c);
   ResetLastError();
   bool checked=OrderCheck(r,c);
   if(!(checked && (c.retcode==0 || c.retcode==TRADE_RETCODE_DONE)))
     {
      EL_Release(key,held);
      Stop(StringFormat("ORDERCHECK_FAILED: returned %d retcode %d",(int)checked,(int)c.retcode));
      return;
     }
   MqlTradeResult s;
   ZeroMemory(s);
   ResetLastError();
   bool sent=OrderSend(r,s);
   PrintFormat("T011 DEMO OPEN POSITION: ONE request sent | OrderSend returned %d (not a fill proof) | retcode %d | order %I64u | deal %I64u | volume %.8g | price %.8g",(int)sent,(int)s.retcode,s.order,s.deal,s.volume,s.price);
   EL_Release(key,held);
   // read-only: find the new position by magic and symbol and print what the harness needs
   int found=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || PositionGetString(POSITION_SYMBOL)!=InpSymbol || PositionGetInteger(POSITION_MAGIC)!=InpEaMagic) continue;
      found++;
      int digits=(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS);
      PrintFormat("T011 DEMO OPEN POSITION: position ticket %I64u | POSITION_IDENTIFIER %I64d (use this in the harness) | open price %s | volume %s | SL %s | TP %s | magic %I64d",
                  tk,PositionGetInteger(POSITION_IDENTIFIER),DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN),digits),DoubleToString(PositionGetDouble(POSITION_VOLUME),2),
                  DoubleToString(PositionGetDouble(POSITION_SL),digits),DoubleToString(PositionGetDouble(POSITION_TP),digits),PositionGetInteger(POSITION_MAGIC));
     }
   if(found!=1) Print("T011 DEMO OPEN POSITION: UNCERTAIN: ",found," positions with this magic and symbol are visible; do NOT run the harness; inspect the terminal by hand. Nothing is retried.");
   Print("T011 DEMO OPEN POSITION: no state file was written; no retry exists; run the harness REGISTER step next only after reading the lines above.");
  }
