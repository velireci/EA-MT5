// T013 entry executor SEAMS: the data structures, the abstract terminal transport and the abstract store (files + lock) the entry executor talks to. No terminal call here.
// Implementations: EntryTransportFake.mqh (tests, in memory, counts every send / cancel) and EntryTransportReal.mqh (the only file that calls OrderSend; never included by a test and
// never executed in this stage). Mirrors the FakeTransport / FakeStore of tests/entry_reference.py.
#ifndef VELO_ENTRY_TRANSPORT_MQH
#define VELO_ENTRY_TRANSPORT_MQH

#define EN_MAX_ORDERS 64
#define EN_MAX_SNAP 32

#define EN_TYPE_BUY_LIMIT 0
#define EN_TYPE_SELL_LIMIT 1
#define EN_TYPE_OTHER 2

#define EN_FILL_UNSET 0
#define EN_FILL_RETURN 1
#define EN_FILL_IOC 2
#define EN_FILL_FOK 3

#define EN_EXP_UNSET 0
#define EN_EXP_GTC 1
#define EN_EXP_SECONDS 2

enum ENUM_EN_ORDER_STATE
  {
   EN_OS_ACTIVE=0,
   EN_OS_FILLED,
   EN_OS_CANCELED,
   EN_OS_EXPIRED,
   EN_OS_REJECTED,
   EN_OS_OTHER
  };

struct SEnAccount
  {
   bool read_ok;
   long login;
   string server;
   bool demo;
   bool trade_allowed;
   int margin_mode;
  };

struct SEnSymbol
  {
   bool read_ok;
   double vol_min;
   double vol_step;
   double vol_max;
   double tick_size;
   int digits;
   double point;
   int stops_level;
   bool trade_ok;
  };

struct SEnQuote
  {
   bool read_ok;
   double bid;
   double ask;
   long time;
  };

struct SEnOrder
  {
   bool found;
   ulong ticket;
   string symbol;
   int type;                     // EN_TYPE_*
   ENUM_EN_ORDER_STATE state;
   double price;
   double sl;
   double tp;
   double volume;
   long magic;
   string comment;
   long time_setup;
   long expiration;
   ulong position_id;
  };

struct SEnOrderList
  {
   bool complete;
   int n;
   SEnOrder o[EN_MAX_ORDERS];
  };

struct SEnRequest
  {
   int type;
   string symbol;
   double volume;
   double price;
   double sl;
   double tp;
   int expiry_mode;
   long expiration;
   int filling;
   long magic;
   string comment;
  };

struct SEnSendResult
  {
   bool returned_true;           // what OrderSend returned: NOT a placement proof
   bool have_result;
   int retcode;
   ulong order;
  };

struct SEnCancelResult
  {
   bool returned_true;
   bool have_result;
   int retcode;
  };

class CEnTransport
  {
public:
   virtual bool IsReal(void)=0;
   virtual long ServerTime(void)=0;
   virtual void ReadAccount(SEnAccount &a)=0;
   virtual void ReadSymbol(const string symbol,SEnSymbol &s)=0;
   virtual void ReadQuote(const string symbol,SEnQuote &q)=0;
   virtual void ListOrders(const string symbol,const long since,SEnOrderList &l)=0;   // active pending orders AND recent history orders of the symbol; complete=false when truncated / unreadable
   virtual void ReadOrder(const ulong ticket,SEnOrder &o)=0;                           // active or history
   virtual bool PreCheck(const SEnRequest &req)=0;                                     // read-only validation; true = acceptable
   virtual void Send(const SEnRequest &req,SEnSendResult &res)=0;                      // THE ONLY placement call
   virtual void Cancel(const ulong ticket,SEnCancelResult &res)=0;                     // THE ONLY cancellation call
  };

class CEnStore
  {
public:
   virtual bool Lock(const string key)=0;
   virtual void Unlock(const string key)=0;
   virtual bool Exists(const string name)=0;
   virtual bool Read(const string name,string &text)=0;
   virtual bool Write(const string name,const string text)=0;                          // atomic replace; false on ANY failure
  };
#endif
