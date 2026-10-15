// T011 executor FAKE transport: scripted answers, no terminal call, counts every send. The only transport the automatic tests use.
#ifndef VELO_EXIT_TRANSPORT_FAKE_MQH
#define VELO_EXIT_TRANSPORT_FAKE_MQH

#include "ExitTransport.mqh"

class CFakeTransport : public CExitTransport
  {
public:
   bool real;                       // claims to be the real transport, to test the authorisation gates; its Send is still fake
   SExAccount account;
   SExSymbol symbol;
   SExPosition position;
   bool precheck_ok;
   SExSendResult response;
   int sends;
   SExSendRequest last_request;
   CFakeTransport(void)
     {
      real=false;
      account.read_ok=true;
      account.login=5001234;
      account.server="MetaQuotes-Demo";
      account.demo=true;
      account.trade_allowed=true;
      account.margin_mode=2;
      symbol.read_ok=true;
      symbol.vol_min=0.01;
      symbol.vol_step=0.01;
      symbol.vol_max=100.0;
      symbol.tick_size=0.01;
      symbol.close_allowed=true;
      position.found=true;
      position.ticket=9;
      position.identifier=7;
      position.symbol="XAUUSD";
      position.magic=777;
      position.type=0;
      position.volume=0.5;
      precheck_ok=true;
      response.returned_true=false;
      response.have_result=false;
      response.retcode=0;
      response.order=0;
      response.deal=0;
      response.volume=0.0;
      response.price=0.0;
      sends=0;
     }
   virtual bool IsReal(void) {return(real);}
   virtual void ReadAccount(SExAccount &a) {a=account;}
   virtual void ReadSymbol(const string name,SExSymbol &s) {s=symbol;}
   virtual void FindPosition(const ulong identifier,SExPosition &p) {p=position;}
   virtual bool PreCheck(const SExSendRequest &req) {return(precheck_ok);}
   virtual void Send(const SExSendRequest &req,SExSendResult &res)
     {
      sends++;
      last_request=req;
      res=response;
     }
  };
#endif
