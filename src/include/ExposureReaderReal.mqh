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
         p[n].ticket=t;
         p[n].symbol=PositionGetString(POSITION_SYMBOL);
         p[n].magic=PositionGetInteger(POSITION_MAGIC);
         long type=PositionGetInteger(POSITION_TYPE);
         p[n].kind=(type==POSITION_TYPE_BUY ? 0 : type==POSITION_TYPE_SELL ? 1 : 2);
         p[n].volume=PositionGetDouble(POSITION_VOLUME);
         p[n].price=PositionGetDouble(POSITION_PRICE_OPEN);
         p[n].sl=PositionGetDouble(POSITION_SL);
         n++;
        }
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
         o[n].ticket=t;
         o[n].symbol=OrderGetString(ORDER_SYMBOL);
         o[n].magic=OrderGetInteger(ORDER_MAGIC);
         long type=OrderGetInteger(ORDER_TYPE);
         bool buy=(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT);
         bool sell=(type==ORDER_TYPE_SELL_LIMIT || type==ORDER_TYPE_SELL_STOP || type==ORDER_TYPE_SELL_STOP_LIMIT);
         o[n].kind=(buy ? 0 : sell ? 1 : 2);
         o[n].volume=OrderGetDouble(ORDER_VOLUME_CURRENT);
         o[n].price=OrderGetDouble(ORDER_PRICE_OPEN);
         o[n].sl=OrderGetDouble(ORDER_SL);
         n++;
        }
     }
   virtual bool Calc(const bool buy,const string symbol,const double volume,const double open,const double sl,double &profit)
     {
      profit=0.0;
      ResetLastError();
      return(OrderCalcProfit(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,symbol,volume,open,sl,profit));
     }
  };
#endif
