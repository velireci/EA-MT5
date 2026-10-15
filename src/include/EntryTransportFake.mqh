// T013 FAKE transport and FAKE store (tests only): in memory, no terminal call, no file. Scripted answers; every send / cancel is counted. Mirrors FakeTransport / FakeStore of tests/entry_reference.py.
#ifndef VELO_ENTRY_TRANSPORT_FAKE_MQH
#define VELO_ENTRY_TRANSPORT_FAKE_MQH

#include "EntryTransport.mqh"

#define EN_SM_PLACED 0
#define EN_SM_REJECTED 1
#define EN_SM_UNCERTAIN_CREATED 2
#define EN_SM_UNCERTAIN_NOT_CREATED 3
#define EN_SM_PLACED_UNREADABLE 4
#define EN_SM_PLACED_MODIFIED 5
#define EN_SM_PLACED_OTHER_TICKET 6
#define EN_SM_PARTIAL_CODES 7
#define EN_SM_UNKNOWN_CODE_WITH_ORDER 8
#define EN_SM_RETURNS_OLD_TICKET 9

#define EN_CM_OK 0
#define EN_CM_LOST 1
#define EN_CM_FAILS 2
#define EN_CM_NOT_EFFECTIVE 3

class CEnFakeTransport : public CEnTransport
  {
public:
   bool real;
   long now;
   SEnAccount account;
   SEnSymbol symbol;
   SEnQuote quote;
   SEnOrder orders[EN_MAX_ORDERS];
   int n_orders;
   bool list_complete;
   bool precheck_ok;
   int send_mode;
   int cancel_mode;
   int sends;
   int cancels;
   SEnRequest last_request;
   ulong next_ticket;
   ulong hidden[8];
   int n_hidden;
   CEnFakeTransport(void)
     {
      real=false;
      now=1000000;
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
      symbol.digits=2;
      symbol.point=0.01;
      symbol.stops_level=0;
      symbol.trade_ok=true;
      quote.read_ok=true;
      quote.bid=2000.0;
      quote.ask=2000.3;
      quote.time=now;
      n_orders=0;
      list_complete=true;
      precheck_ok=true;
      send_mode=EN_SM_PLACED;
      cancel_mode=EN_CM_OK;
      sends=0;
      cancels=0;
      next_ticket=9000;
      n_hidden=0;
     }
   void Hide(const ulong t) {if(n_hidden<8) {hidden[n_hidden]=t; n_hidden++;}}
   void Unhide(void) {n_hidden=0;}
   bool IsHidden(const ulong t)
     {
      for(int i=0;i<n_hidden;i++)
         if(hidden[i]==t) return(true);
      return(false);
     }
   void AddOrder(const SEnOrder &o)
     {
      if(n_orders<EN_MAX_ORDERS) {orders[n_orders]=o; n_orders++;}
     }
   int IndexOf(const ulong t)
     {
      for(int i=0;i<n_orders;i++)
         if(orders[i].ticket==t) return(i);
      return(-1);
     }
   virtual bool IsReal(void) {return(real);}
   virtual long ServerTime(void) {return(now);}
   virtual void ReadAccount(SEnAccount &a) {a=account;}
   virtual void ReadSymbol(const string name,SEnSymbol &s) {s=symbol;}
   virtual void ReadQuote(const string name,SEnQuote &q) {q=quote;}
   virtual void ListOrders(const string name,const long since,SEnOrderList &l)
     {
      l.complete=list_complete;
      l.n=0;
      for(int i=0;i<n_orders && l.n<EN_MAX_ORDERS;i++)
         if(orders[i].symbol==name && !IsHidden(orders[i].ticket))
           {
            l.o[l.n]=orders[i];
            l.n++;
           }
     }
   virtual void ReadOrder(const ulong ticket,SEnOrder &o)
     {
      int k=IndexOf(ticket);
      if(k>=0 && !IsHidden(ticket)) {o=orders[k]; return;}
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
   virtual bool PreCheck(const SEnRequest &req) {return(precheck_ok);}
   virtual void Send(const SEnRequest &req,SEnSendResult &res)
     {
      sends++;
      last_request=req;
      res.returned_true=false;
      res.have_result=false;
      res.retcode=0;
      res.order=0;
      if(send_mode==EN_SM_REJECTED) {res.returned_true=true; res.have_result=true; res.retcode=10013; return;}
      if(send_mode==EN_SM_UNCERTAIN_NOT_CREATED) return;
      if(send_mode==EN_SM_PARTIAL_CODES) {res.returned_true=true; res.have_result=true; res.retcode=10031; return;}
      if(send_mode==EN_SM_RETURNS_OLD_TICKET && n_orders>0) {res.returned_true=true; res.have_result=true; res.retcode=10008; res.order=orders[0].ticket; return;}
      next_ticket++;
      SEnOrder o;
      o.found=true;
      o.ticket=next_ticket;
      o.symbol=req.symbol;
      o.type=req.type;
      o.state=EN_OS_ACTIVE;
      o.price=req.price;
      o.sl=req.sl;
      o.tp=req.tp;
      o.volume=req.volume;
      o.magic=req.magic;
      o.comment=req.comment;
      o.time_setup=now;
      o.expiration=req.expiration;
      o.position_id=0;
      if(send_mode==EN_SM_PLACED_MODIFIED) o.sl=req.sl+1.0;
      AddOrder(o);
      if(send_mode==EN_SM_UNCERTAIN_CREATED) return;
      if(send_mode==EN_SM_PLACED_UNREADABLE) Hide(o.ticket);
      res.returned_true=true;
      res.have_result=true;
      res.retcode=(send_mode==EN_SM_UNKNOWN_CODE_WITH_ORDER ? 10031 : 10008);
      res.order=(send_mode==EN_SM_PLACED_OTHER_TICKET ? o.ticket+500 : o.ticket);
     }
   virtual void Cancel(const ulong ticket,SEnCancelResult &res)
     {
      cancels++;
      res.returned_true=false;
      res.have_result=false;
      res.retcode=0;
      int k=IndexOf(ticket);
      if(k>=0 && orders[k].state==EN_OS_ACTIVE)
        {
         if(cancel_mode==EN_CM_OK || cancel_mode==EN_CM_LOST) orders[k].state=EN_OS_CANCELED;
         if(cancel_mode==EN_CM_OK || cancel_mode==EN_CM_NOT_EFFECTIVE) {res.returned_true=true; res.have_result=true; res.retcode=10009; return;}
         if(cancel_mode==EN_CM_LOST) return;
        }
      res.returned_true=true;
      res.have_result=true;
      res.retcode=10013;
     }
  };

class CEnFakeStore : public CEnStore
  {
public:
   string names[8];
   string texts[8];
   int n_files;
   string held[8];
   int n_held;
   int lock_calls;
   int unlock_calls;
   int writes;
   int fail_write_at;          // the n-th write call fails (0 = none)
   int readback_differs_at;    // the n-th write call is stored with an extra character
   bool deny_lock;
   string unreadable;
   CEnFakeStore(void)
     {
      n_files=0;
      n_held=0;
      lock_calls=0;
      unlock_calls=0;
      writes=0;
      fail_write_at=0;
      readback_differs_at=0;
      deny_lock=false;
      unreadable="";
     }
   int Find(const string name)
     {
      for(int i=0;i<n_files;i++)
         if(names[i]==name) return(i);
      return(-1);
     }
   void Put(const string name,const string text)
     {
      int k=Find(name);
      if(k<0 && n_files<8) {k=n_files; n_files++; names[k]=name;}
      if(k>=0) texts[k]=text;
     }
   string Get(const string name)
     {
      int k=Find(name);
      return(k>=0 ? texts[k] : "");
     }
   bool Holds(void) {return(n_held>0);}
   virtual bool Lock(const string key)
     {
      lock_calls++;
      if(deny_lock) return(false);
      for(int i=0;i<n_held;i++)
         if(held[i]==key) return(false);
      if(n_held>=8) return(false);
      held[n_held]=key;
      n_held++;
      return(true);
     }
   virtual void Unlock(const string key)
     {
      unlock_calls++;
      for(int i=0;i<n_held;i++)
         if(held[i]==key)
           {
            held[i]=held[n_held-1];
            n_held--;
            return;
           }
     }
   virtual bool Exists(const string name) {return(Find(name)>=0);}
   virtual bool Read(const string name,string &text)
     {
      text="";
      if(name==unreadable) return(false);
      int k=Find(name);
      if(k<0) return(false);
      text=texts[k];
      return(true);
     }
   virtual bool Write(const string name,const string text)
     {
      writes++;
      if(writes==fail_write_at) return(false);
      Put(name,text+(writes==readback_differs_at ? "X" : ""));
      return(true);
     }
  };
#endif
