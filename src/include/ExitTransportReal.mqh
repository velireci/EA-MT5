// T011 executor REAL transport: the ONLY file that calls the trading API (OrderSend; OrderCheck for the read-only pre-check). NEVER included by a test or by the executor
// core, NEVER executed in this stage: it is compiled by T011_ExecutorRealCompile.mq5 (which calls none of its methods) so that Codex can check the syntax. Real activation needs
// the explicit authorisation phrase of the executor, a DEMO account and a proven identity / ownership (all enforced in ExitExecutor.mqh BEFORE Send is reached).
// API FACTS (UNVERIFIED: the official pages https://www.mql5.com/en/docs/trading/ordersend and https://www.mql5.com/en/docs/constants/structures/mqltraderequest could not be opened from the
// build environment; only search-result snippets were seen): OrderSend returning true means the request passed the basic checks and was sent, NOT that it was executed; the outcome is in
// MqlTradeResult.retcode (10008 placed, 10009 done, 10010 done partially) with `order` / `deal`; MqlTradeRequest.position identifies the position being closed (on a hedging account the
// CURRENT position ticket, which is not the position identifier); a market close needs action, symbol, volume, type, position (hedging), type_filling and, for execution modes that need it,
// price and deviation. Codex / the owner must verify every line below against the official pages before any demo run.
#ifndef VELO_EXIT_TRANSPORT_REAL_MQH
#define VELO_EXIT_TRANSPORT_REAL_MQH

#include "ExitTransport.mqh"

class CRealTransport : public CExitTransport
  {
private:
   // false = the request has a value that maps to no known constant; it is never turned into a default (no unknown filling becomes RETURN)
   bool Fill(const SExSendRequest &req,MqlTradeRequest &r)
     {
      ZeroMemory(r);
      if(req.action!=EX_ACTION_DEAL) return(false);
      r.action=TRADE_ACTION_DEAL;
      r.symbol=req.symbol;
      r.volume=req.volume;
      if(req.type==0) r.type=ORDER_TYPE_BUY;
      else
         if(req.type==1) r.type=ORDER_TYPE_SELL;
         else return(false);
      r.position=req.position;
      r.magic=(ulong)req.magic;
      r.deviation=(ulong)req.deviation;
      r.price=req.price;
      r.comment=req.comment;
      if(req.filling==1) r.type_filling=ORDER_FILLING_FOK;
      else
         if(req.filling==2) r.type_filling=ORDER_FILLING_IOC;
         else
            if(req.filling==3) r.type_filling=ORDER_FILLING_RETURN;
            else return(false);
      return(true);
     }
public:
   virtual bool IsReal(void) {return(true);}
   virtual void ReadAccount(SExAccount &a)
     {
      ResetLastError();
      a.login=AccountInfoInteger(ACCOUNT_LOGIN);
      a.server=AccountInfoString(ACCOUNT_SERVER);
      long mode=AccountInfoInteger(ACCOUNT_TRADE_MODE);
      a.demo=(mode==ACCOUNT_TRADE_MODE_DEMO);
      a.trade_allowed=(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)!=0 && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)!=0 && AccountInfoInteger(ACCOUNT_TRADE_EXPERT)!=0 &&
                       MQLInfoInteger(MQL_TRADE_ALLOWED)!=0);
      long mm=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      a.margin_mode=(int)mm;
      a.read_ok=(a.login>0 && a.server!="" && GetLastError()==0);
     }
   virtual void ReadSymbol(const string symbol,SExSymbol &s)
     {
      ResetLastError();
      s.vol_min=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      s.vol_step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      s.vol_max=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      s.tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      long tm=SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
      s.close_allowed=(tm==SYMBOL_TRADE_MODE_FULL || tm==SYMBOL_TRADE_MODE_CLOSEONLY);
      s.read_ok=(GetLastError()==0 && s.vol_min>0.0 && s.vol_step>0.0 && s.vol_max>0.0 && s.tick_size>0.0);
     }
   virtual void FindPosition(const ulong identifier,SExPosition &p)
     {
      p.found=false;
      p.ticket=0;
      p.identifier=0;
      p.symbol="";
      p.magic=0;
      p.type=-1;
      p.volume=0.0;
      int matches=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(t==0) continue;
         if((ulong)PositionGetInteger(POSITION_IDENTIFIER)!=identifier) continue;
         matches++;
         p.ticket=t;
         p.identifier=identifier;
         p.symbol=PositionGetString(POSITION_SYMBOL);
         p.magic=PositionGetInteger(POSITION_MAGIC);
         p.type=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 0 : 1);
         p.volume=PositionGetDouble(POSITION_VOLUME);
        }
      p.found=(matches==1);                  // zero or ambiguous = not found
     }
   virtual bool PreCheck(const SExSendRequest &req)
     {
      MqlTradeRequest r;
      if(!Fill(req,r)) return(false);
      MqlTradeCheckResult c;
      ZeroMemory(c);
      ResetLastError();
      bool ok=OrderCheck(r,c);
      return(ok && (c.retcode==0 || c.retcode==TRADE_RETCODE_DONE));
     }
   virtual void Send(const SExSendRequest &req,SExSendResult &res)
     {
      res.returned_true=false;
      res.have_result=false;
      res.retcode=0;
      res.order=0;
      res.deal=0;
      res.volume=0.0;
      res.price=0.0;
      MqlTradeRequest r;
      if(!Fill(req,r)) return;                // an unmappable request is never sent
      MqlTradeResult s;
      ZeroMemory(s);
      ResetLastError();
      bool ok=OrderSend(r,s);
      res.returned_true=ok;
      res.have_result=true;
      res.retcode=(int)s.retcode;
      res.order=s.order;
      res.deal=s.deal;
      res.volume=s.volume;
      res.price=s.price;
     }
  };
#endif
