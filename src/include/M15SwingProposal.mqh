// EXPERIMENTAL Q04 proposal: latest confirmed, unbroken Left/Right fractal.
// Default disabled. A selected fractal is NOT a client-validated structural level.
#ifndef VELO_M15_SWING_PROPOSAL_MQH
#define VELO_M15_SWING_PROPOSAL_MQH
#include "M15Confirmation.mqh"
#include "H4Structure.mqh"

struct SM4Selection
  {
   string status;
   SM4Level level;
   datetime pivot;
   datetime window_start;
   int used;
   int ambiguous;
  };

// bars[0..n-1] are ONLY the prefix closed BEFORE the evaluated bar opens.
// No forming/evaluated bar is included. This selector does not mutate the observer.
void M4SelectSwingProposal(const MqlRates &bars[],const int n,const int direction,SM4Selection &out,
                           const bool enabled=false,const int left=2,const int right=2,const int lookback=300)
  {
   out.status="DISABLED";
   M4NoLevel(out.level);
   out.pivot=0; out.window_start=0; out.used=0; out.ambiguous=0;
   if(!enabled)
      return;
   out.status="INVALID_INPUT";
   if((direction!=1 && direction!=-1) || n<0 || n>ArraySize(bars) || left<1 || left>10 ||
      right<1 || right>10 || lookback<left+right+1 || lookback>1000)
      return;
   if(n==0)
     {
      out.status="SHORT_HISTORY";
      return;
     }
   int start=(n>lookback ? n-lookback : 0);
   // Duplicate/backward times are not normal missing intervals.
   for(int i=start+1;i<n;i++)
      if(bars[i].time<=bars[i-1].time)
         return;
   for(int i=n-1;i>start;i--)
      if(bars[i].time-bars[i-1].time!=M4_PERIOD)
        {
         start=i;
         break;
        }
   int count=n-start;
   MqlRates window[];
   ArrayResize(window,count);
   for(int i=0;i<count;i++)
     {
      window[i]=bars[start+i];
      if(window[i].time<=0 || (long)window[i].time%M4_PERIOD!=0 ||
         !MathIsValidNumber(window[i].high) || !MathIsValidNumber(window[i].low) ||
         !MathIsValidNumber(window[i].close) || window[i].low<=0 || window[i].high<window[i].low ||
         window[i].close<window[i].low || window[i].close>window[i].high)
         return;
     }
   out.window_start=window[0].time;
   out.used=count;
   if(count<left+right+1)
     {
      out.status="SHORT_HISTORY";
      return;
     }
   SH4Swing swings[];
   int ns=H4FindSwings(window,count,left,right,M4_PERIOD,swings,out.ambiguous);
   for(int i=ns-1;i>=0;i--)
     {
      if(swings[i].is_high!=(direction>0))
         continue;
      bool consumed=false;
      for(int j=swings[i].index+1;j<count;j++)
         if(direction*(window[j].close-swings[i].price)>0)
           {
            consumed=true;
            break;
           }
      if(consumed)
         continue;
      out.pivot=swings[i].pivot_time;
      out.level.valid=true;
      out.level.id="M15S"+(direction>0 ? "H" : "L")+IntegerToString((long)out.pivot);
      out.level.price=swings[i].price;
      out.level.known=swings[i].confirm_time;
      out.status="SELECTED";
      return;
     }
   out.status="NO_LEVEL";
  }
#endif
