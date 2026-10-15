// T013 entry REAL transport and REAL store: the ONLY file that calls the trading API for ENTRY orders (OrderSend for a pending LIMIT, OrderSend TRADE_ACTION_REMOVE to cancel, OrderCheck for the read-only
// pre-check) and the only one that touches terminal files / the lock for the entry records. NEVER included by a test or by EntryExecutor.mqh, NEVER executed in this stage: it is compiled by
// src/tests/EntryExecutorRealCompile.mq5 (which calls none of its methods) so that Codex can check the syntax. Real activation needs the explicit authorisation phrase, a DEMO account and the owner's
// instruction (all enforced in EntryExecutor.mqh BEFORE Send is reached).
// API FACTS (UNVERIFIED: the official pages could not be opened from the build environment): OrderSend returning true means the request passed the basic checks and was sent, NOT that it was
// placed; the outcome is in MqlTradeResult.retcode (10008 placed, 10009 done) with `order`; a pending order uses TRADE_ACTION_PENDING with ORDER_TYPE_BUY_LIMIT / SELL_LIMIT, price, sl, tp,
// type_time (ORDER_TIME_GTC / ORDER_TIME_SPECIFIED + expiration), type_filling, magic, comment; active orders are read with OrderSelect / OrderGet*, history orders with HistoryOrderSelect /
// HistoryOrderGet* (ORDER_STATE_*, ORDER_POSITION_ID). Codex / the owner must verify every line against the official pages before any demo run.
#ifndef VELO_ENTRY_TRANSPORT_REAL_MQH
#define VELO_ENTRY_TRANSPORT_REAL_MQH

#include "EntryTransport.mqh"
#include "ExitStateFile.mqh"
#include "ExitInstanceLock.mqh"

class CEnRealStore : public CEnStore
  {
   bool              m_held;
public:
   CEnRealStore(void) {m_held=false;}
   virtual bool Lock(const string key)
     {
      string why;
      return(EL_Acquire(key,m_held,why));
     }
   virtual void Unlock(const string key) {EL_Release(key,m_held);}
   virtual bool Exists(const string name) {return(ESF_Exists(name));}
   virtual bool Read(const string name,string &text) {return(ESF_ReadAll(name,text));}
   virtual bool Write(const string name,const string text)
     {
      string tmp=name+ESF_TMP_SUFFIX;
      if(ESF_Exists(tmp)) return(false);                 // a leftover temporary file: recover by hand first
      if(!ESF_WriteAll(tmp,text)) {FileDelete(tmp); return(false);}
      string back;
      if(!ESF_ReadAll(tmp,back) || back!=text) {FileDelete(tmp); return(false);}
      ResetLastError();
      if(!FileMove(tmp,0,name,FILE_REWRITE)) {FileDelete(tmp); return(false);}
      return(ESF_ReadAll(name,back) && back==text);
     }
  };

class CEnRealTransport : public CEnTransport
  {
private:
   int MapType(const long t)
     {
      if(t==ORDER_TYPE_BUY_LIMIT) return(EN_TYPE_BUY_LIMIT);
      if(t==ORDER_TYPE_SELL_LIMIT) return(EN_TYPE_SELL_LIMIT);
      return(EN_TYPE_OTHER);
     }
   ENUM_EN_ORDER_STATE MapState(const long s)
     {
      if(s==ORDER_STATE_PLACED || s==ORDER_STATE_STARTED || s==ORDER_STATE_REQUEST_ADD || s==ORDER_STATE_REQUEST_MODIFY || s==ORDER_STATE_REQUEST_CANCEL) return(EN_OS_ACTIVE);
      if(s==ORDER_STATE_FILLED) return(EN_OS_FILLED);
      if(s==ORDER_STATE_CANCELED) return(EN_OS_CANCELED);
      if(s==ORDER_STATE_EXPIRED) return(EN_OS_EXPIRED);
      if(s==ORDER_STATE_REJECTED) return(EN_OS_REJECTED);
      return(EN_OS_OTHER);
     }
   void Blank(const ulong ticket,SEnOrder &o)
     {
      o.found=false;
      o.ticket=ticket;
      o.symbol="";
      o.type=EN_TYPE_OTHER;
      o.state=EN_OS_OTHER;
      o.price=0.0;
      o.sl=0.0;
      o.tp=0.0;
      o.volume=0.0;
      o.magic=0;
      o.comment="";
      o.time_setup=0;
      o.expiration=0;
      o.position_id=0;
     }
   // the order selected by OrderSelect (active)
   void FromActive(const ulong ticket,SEnOrder &o)
     {
      o.found=true;
      o.ticket=ticket;
      o.symbol=OrderGetString(ORDER_SYMBOL);
      o.type=MapType(OrderGetInteger(ORDER_TYPE));
      o.state=MapState(OrderGetInteger(ORDER_STATE));
      o.price=OrderGetDouble(ORDER_PRICE_OPEN);
      o.sl=OrderGetDouble(ORDER_SL);
      o.tp=OrderGetDouble(ORDER_TP);
      o.volume=OrderGetDouble(ORDER_VOLUME_CURRENT);
      o.magic=OrderGetInteger(ORDER_MAGIC);
      o.comment=OrderGetString(ORDER_COMMENT);
      o.time_setup=OrderGetInteger(ORDER_TIME_SETUP);
      o.expiration=OrderGetInteger(ORDER_TIME_EXPIRATION);
      o.position_id=(ulong)OrderGetInteger(ORDER_POSITION_ID);
     }
   // the order selected by HistoryOrderSelect / HistoryOrderGetTicket (history)
   void FromHistory(const ulong ticket,SEnOrder &o)
     {
      o.found=true;
      o.ticket=ticket;
      o.symbol=HistoryOrderGetString(ticket,ORDER_SYMBOL);
      o.type=MapType(HistoryOrderGetInteger(ticket,ORDER_TYPE));
      o.state=MapState(HistoryOrderGetInteger(ticket,ORDER_STATE));
      o.price=HistoryOrderGetDouble(ticket,ORDER_PRICE_OPEN);
      o.sl=HistoryOrderGetDouble(ticket,ORDER_SL);
      o.tp=HistoryOrderGetDouble(ticket,ORDER_TP);
      o.volume=HistoryOrderGetDouble(ticket,ORDER_VOLUME_INITIAL);
      o.magic=HistoryOrderGetInteger(ticket,ORDER_MAGIC);
      o.comment=HistoryOrderGetString(ticket,ORDER_COMMENT);
      o.time_setup=HistoryOrderGetInteger(ticket,ORDER_TIME_SETUP);
      o.expiration=HistoryOrderGetInteger(ticket,ORDER_TIME_EXPIRATION);
      o.position_id=(ulong)HistoryOrderGetInteger(ticket,ORDER_POSITION_ID);
     }
   // false = the request has a value that maps to no known constant; it is never turned into a default
   bool Fill(const SEnRequest &req,MqlTradeRequest &r)
     {
      ZeroMemory(r);
      r.action=TRADE_ACTION_PENDING;
      r.symbol=req.symbol;
      r.volume=req.volume;
      if(req.type==EN_TYPE_BUY_LIMIT) r.type=ORDER_TYPE_BUY_LIMIT;
      else
         if(req.type==EN_TYPE_SELL_LIMIT) r.type=ORDER_TYPE_SELL_LIMIT;
         else return(false);
      r.price=req.price;
      r.sl=req.sl;
      r.tp=req.tp;
      r.magic=(ulong)req.magic;
      r.comment=req.comment;
      if(req.expiry_mode==EN_EXP_GTC) r.type_time=ORDER_TIME_GTC;
      else
         if(req.expiry_mode==EN_EXP_SECONDS)
           {
            r.type_time=ORDER_TIME_SPECIFIED;
            r.expiration=(datetime)req.expiration;
           }
         else return(false);
      if(req.filling==EN_FILL_RETURN) r.type_filling=ORDER_FILLING_RETURN;
      else
         if(req.filling==EN_FILL_IOC) r.type_filling=ORDER_FILLING_IOC;
         else
            if(req.filling==EN_FILL_FOK) r.type_filling=ORDER_FILLING_FOK;
            else return(false);
      return(true);
     }
public:
   virtual bool IsReal(void) {return(true);}
   virtual long ServerTime(void) {return((long)TimeTradeServer());}
   virtual void ReadAccount(SEnAccount &a)
     {
      ResetLastError();
      a.login=AccountInfoInteger(ACCOUNT_LOGIN);
      a.server=AccountInfoString(ACCOUNT_SERVER);
      a.demo=(AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO);
      a.trade_allowed=(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)!=0 && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)!=0 && AccountInfoInteger(ACCOUNT_TRADE_EXPERT)!=0 &&
                       MQLInfoInteger(MQL_TRADE_ALLOWED)!=0);
      a.margin_mode=(int)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      a.read_ok=(a.login>0 && a.server!="" && GetLastError()==0);
     }
   virtual void ReadSymbol(const string symbol,SEnSymbol &s)
     {
      ResetLastError();
      s.vol_min=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      s.vol_step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      s.vol_max=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      s.tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      s.digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      s.point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      s.stops_level=(int)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
      s.trade_ok=(SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE)==SYMBOL_TRADE_MODE_FULL);
      s.read_ok=(GetLastError()==0 && s.vol_min>0.0 && s.vol_step>0.0 && s.vol_max>0.0 && s.tick_size>0.0 && s.digits>=0 && s.point>0.0 && s.stops_level>=0);
     }
   virtual void ReadQuote(const string symbol,SEnQuote &q)
     {
      MqlTick t;
      ResetLastError();
      q.read_ok=SymbolInfoTick(symbol,t);
      q.bid=(q.read_ok ? t.bid : 0.0);
      q.ask=(q.read_ok ? t.ask : 0.0);
      q.time=(q.read_ok ? (long)t.time : 0);
     }
   virtual void ListOrders(const string symbol,const long since,SEnOrderList &l)
     {
      l.complete=true;
      l.n=0;
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         ulong t=OrderGetTicket(i);
         if(t==0) {l.complete=false; continue;}
         if(OrderGetString(ORDER_SYMBOL)!=symbol) continue;
         if(l.n>=EN_MAX_ORDERS) {l.complete=false; break;}
         FromActive(t,l.o[l.n]);
         l.n++;
        }
      ResetLastError();
      if(!HistorySelect((datetime)since,(datetime)(ServerTime()+86400))) {l.complete=false; return;}
      for(int i=HistoryOrdersTotal()-1;i>=0;i--)
        {
         ulong t=HistoryOrderGetTicket(i);
         if(t==0) {l.complete=false; continue;}
         if(HistoryOrderGetString(t,ORDER_SYMBOL)!=symbol) continue;
         if(l.n>=EN_MAX_ORDERS) {l.complete=false; break;}
         FromHistory(t,l.o[l.n]);
         l.n++;
        }
     }
   virtual void ReadOrder(const ulong ticket,SEnOrder &o)
     {
      Blank(ticket,o);
      ResetLastError();
      if(OrderSelect(ticket)) {FromActive(ticket,o); return;}
      if(HistoryOrderSelect(ticket)) FromHistory(ticket,o);
     }
   virtual bool PreCheck(const SEnRequest &req)
     {
      MqlTradeRequest r;
      if(!Fill(req,r)) return(false);
      MqlTradeCheckResult c;
      ZeroMemory(c);
      ResetLastError();
      bool ok=OrderCheck(r,c);
      return(ok && (c.retcode==0 || c.retcode==TRADE_RETCODE_DONE));
     }
   virtual void Send(const SEnRequest &req,SEnSendResult &res)
     {
      res.returned_true=false;
      res.have_result=false;
      res.retcode=0;
      res.order=0;
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
     }
   virtual void Cancel(const ulong ticket,SEnCancelResult &res)
     {
      res.returned_true=false;
      res.have_result=false;
      res.retcode=0;
      MqlTradeRequest r;
      ZeroMemory(r);
      r.action=TRADE_ACTION_REMOVE;
      r.order=ticket;
      MqlTradeResult s;
      ZeroMemory(s);
      ResetLastError();
      bool ok=OrderSend(r,s);
      res.returned_true=ok;
      res.have_result=true;
      res.retcode=(int)s.retcode;
     }
  };
#endif
