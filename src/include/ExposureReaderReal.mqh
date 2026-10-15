// T018 REAL READ-ONLY port for the exposure reader: PositionsTotal / PositionGet*, OrdersTotal / OrderGet*, ACCOUNT_MARGIN_MODE, OrderCalcProfit. No order function, no write. COMPILE-ONLY (it reads the terminal).
#ifndef VELO_EXPOSURE_READER_REAL_MQH
#define VELO_EXPOSURE_READER_REAL_MQH
#include "ExposureReader.mqh"

class CExRealPort : public CExPort
  {
public:
   virtual void Account(bool &ok,int &margin_mode)
     {
      ResetLastError();
      margin_mode=(int)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      ok=(AccountInfoInteger(ACCOUNT_LOGIN)>0 && GetLastError()==0);
     }
   // Every getter uses the overload that RETURNS a success flag: a failed getter must never become 0 (a magic of 0 would read as a manual position). Any failure, or a count that changed while the list was
   // read, makes the list INCOMPLETE (= unknown); the core additionally reads every list twice and compares.
   virtual void Positions(SExItem &p[],int &n,bool &complete)
     {
      n=0;
      complete=true;
      ArrayResize(p,0);
      int total=PositionsTotal();
      if(total<0 || total>EX_MAX) {complete=false; return;}
      ArrayResize(p,total);
      for(int i=0;i<total;i++)
        {
         ulong t=PositionGetTicket(i);
         if(t==0) {complete=false; return;}
         long type=-1,magic=-1;
         double volume=0.0,price=0.0,sl=0.0;
         string symbol="";
         bool got=(PositionGetString(POSITION_SYMBOL,symbol) && symbol!="" && PositionGetInteger(POSITION_MAGIC,magic) && magic>=0 && PositionGetInteger(POSITION_TYPE,type) &&
                   PositionGetDouble(POSITION_VOLUME,volume) && PositionGetDouble(POSITION_PRICE_OPEN,price) && PositionGetDouble(POSITION_SL,sl));
         if(!got) {complete=false; n=0; return;}
         p[n].ticket=t;
         p[n].symbol=symbol;
         p[n].magic=magic;
         p[n].kind=(type==POSITION_TYPE_BUY ? 0 : type==POSITION_TYPE_SELL ? 1 : 2);
         p[n].volume=volume;
         p[n].price=price;
         p[n].sl=sl;
         n++;
        }
      if(PositionsTotal()!=total) {complete=false; n=0;}      // the list changed while it was read
     }
   virtual void Orders(SExItem &o[],int &n,bool &complete)
     {
      n=0;
      complete=true;
      ArrayResize(o,0);
      int total=OrdersTotal();
      if(total<0 || total>EX_MAX) {complete=false; return;}
      ArrayResize(o,total);
      for(int i=0;i<total;i++)
        {
         ulong t=OrderGetTicket(i);
         if(t==0) {complete=false; return;}
         long type=-1,magic=-1;
         double volume=0.0,price=0.0,sl=0.0;
         string symbol="";
         bool got=(OrderGetString(ORDER_SYMBOL,symbol) && symbol!="" && OrderGetInteger(ORDER_MAGIC,magic) && magic>=0 && OrderGetInteger(ORDER_TYPE,type) &&
                   OrderGetDouble(ORDER_VOLUME_CURRENT,volume) && OrderGetDouble(ORDER_PRICE_OPEN,price) && OrderGetDouble(ORDER_SL,sl));
         if(!got) {complete=false; n=0; return;}
         bool buy=(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT);
         bool sell=(type==ORDER_TYPE_SELL_LIMIT || type==ORDER_TYPE_SELL_STOP || type==ORDER_TYPE_SELL_STOP_LIMIT);
         o[n].ticket=t;
         o[n].symbol=symbol;
         o[n].magic=magic;
         o[n].kind=(buy ? 0 : sell ? 1 : 2);
         o[n].volume=volume;
         o[n].price=price;
         o[n].sl=sl;
         n++;
        }
      if(OrdersTotal()!=total) {complete=false; n=0;}
     }
   virtual bool Calc(const bool buy,const string symbol,const double volume,const double open,const double sl,double &profit)
     {
      profit=0.0;
      ResetLastError();
      return(OrderCalcProfit(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,symbol,volume,open,sl,profit));
     }
  };
#endif
