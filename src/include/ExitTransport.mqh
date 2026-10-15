// T011 executor transport SEAM: the data structures and the abstract transport the executor talks to. No terminal call here. Two implementations exist:
// ExitTransportFake.mqh (tests, in-memory, counts every send) and ExitTransportReal.mqh (the only file that calls OrderSend; never included by a test, never
// executed in this stage). Mirrors the FakeTransport of tests/t011_executor_reference.py.
#ifndef VELO_EXIT_TRANSPORT_MQH
#define VELO_EXIT_TRANSPORT_MQH

#define EX_ACTION_DEAL 1

struct SExAccount
  {
   bool read_ok;
   long login;
   string server;
   bool demo;
   bool trade_allowed;
   int margin_mode;
  };

struct SExSymbol
  {
   bool read_ok;
   double vol_min;
   double vol_step;
   double vol_max;
   double tick_size;
   bool close_allowed;
  };

struct SExPosition
  {
   bool found;
   ulong ticket;
   ulong identifier;
   string symbol;
   long magic;
   int type;               // 0 = buy, 1 = sell
   double volume;
  };

struct SExSendRequest
  {
   int action;
   string symbol;
   double volume;
   int type;               // the order type of the CLOSING deal: 0 = buy, 1 = sell
   ulong position;         // the CURRENT position ticket (found from the identifier), not the identifier
   long magic;
   long deviation;
   int filling;
   double price;
   string comment;         // the request id, for humans only; never used as proof
  };

struct SExSendResult
  {
   bool returned_true;     // what OrderSend returned: NOT a fill proof
   bool have_result;
   int retcode;
   ulong order;
   ulong deal;
   double volume;
   double price;
  };

class CExitTransport
  {
public:
   virtual bool IsReal(void)=0;
   virtual void ReadAccount(SExAccount &a)=0;
   virtual void ReadSymbol(const string symbol,SExSymbol &s)=0;
   virtual void FindPosition(const ulong identifier,SExPosition &p)=0;
   virtual bool PreCheck(const SExSendRequest &req)=0;       // read-only validation of the request; true = acceptable
   virtual void Send(const SExSendRequest &req,SExSendResult &res)=0;     // THE ONLY trading call
  };
#endif
