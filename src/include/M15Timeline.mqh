// Pure timeline: supplied causal H4 snapshots -> closed M15 prefix replay.
#ifndef VELO_M15_TIMELINE_MQH
#define VELO_M15_TIMELINE_MQH
#include "M15SwingProposal.mqh"

struct SM4ContextUpdate
  {
   datetime known;
   SM4Context context;
  };

struct SM4TimelineInfo
  {
   string status;
   int processed;
   double bos_price;
   SM4Selection selection;
  };

bool M4TimelineNeedsBuild(const bool historical,const bool built,const datetime cut,const datetime previous,
                           const bool h4_changed,const bool m15_changed)
  {
   return(!built || cut!=previous || (!historical && (h4_changed || m15_changed)));
  }

// MT5 may preserve globals on a chart-period reinitialisation. Reset the result
// AND its successful-copy cache together; otherwise historical mode can skip Build.
void M4ResetReplay(SM4State &state,SM4Candidate &f[],SM4Event &events[],SM4TimelineInfo &info,
                    bool &built,datetime &cut)
  {
   M4Init(state,f,events);
   ZeroMemory(info);
   info.status="RESET";info.selection.status="DISABLED";
   built=false;cut=0;
  }

void M4ReplayTimeline(const MqlRates &bars[],const int n,const SM4ContextUpdate &updates[],const int nu,
                       const datetime replay_from,const datetime asof,const bool selector,const int policy,
                       const int left,const int right,const int lookback,
                       SM4State &state,SM4Candidate &f[],SM4Event &events[],SM4TimelineInfo &info)
  {
   M4Init(state,f,events,policy);
   info.status="INVALID_INPUT"; info.processed=0; info.bos_price=0;
   info.selection.status="DISABLED"; M4NoLevel(info.selection.level);
   info.selection.pivot=0;info.selection.window_start=0;info.selection.used=0;info.selection.ambiguous=0;
   if(n<0 || n>ArraySize(bars) || nu<0 || nu>ArraySize(updates) || replay_from<=0 || asof<=0)
      return;
   // The caller provides chronological arrays. Do not inspect contexts after the cut.
   int un=0;
   for(int i=0;i<nu;i++)
     {
      if(updates[i].known>asof) break;
      if(updates[i].known<=0 || (i>0 && updates[i].known<=updates[i-1].known))
        {info.status="INVALID_UPDATES";return;}
      un++;
     }
   int bn=0;
   for(int i=0;i<n;i++)
     {
      if(bars[i].time+M4_PERIOD>asof) break;
      if(bars[i].time<=0 || (long)bars[i].time%M4_PERIOD!=0 ||
         !MathIsValidNumber(bars[i].high) || !MathIsValidNumber(bars[i].low) ||
         !MathIsValidNumber(bars[i].close) || bars[i].low<=0 || bars[i].high<bars[i].low ||
         bars[i].close<bars[i].low || bars[i].close>bars[i].high || (i>0 && bars[i].time<=bars[i-1].time))
        {info.status="INVALID_M15";return;}
      bn++;
     }
   int first=0;
   while(first<bn && bars[first].time<replay_from) first++;
   datetime observed=(first<bn ? bars[first].time : asof);
   int j=0;
   while(j<un && updates[j].known<=observed) j++;
   if(j>0) M4SetContext(updates[j-1].context,observed,state,f,events);
   for(int i=first;i<bn;i++)
     {
      datetime close=bars[i].time+M4_PERIOD;
      // H4 updates take priority at equal close times, including revocation.
      while(j<un && updates[j].known<=close)
        {
         M4SetContext(updates[j].context,updates[j].known,state,f,events);
         j++;
        }
      M4SelectSwingProposal(bars,i,state.context.direction,info.selection,
                            selector && state.has_context,left,right,lookback);
      datetime previous=state.bos_time;
      M4Step(bars[i],close,info.selection.level,state,f,events);
      if(state.bos_time==0) info.bos_price=0;
      else if(previous==0) info.bos_price=info.selection.level.price;
      info.processed++;
     }
   while(j<un)
     {
      M4SetContext(updates[j].context,updates[j].known,state,f,events);
      if(state.bos_time==0) info.bos_price=0;
      j++;
     }
   info.status=(info.processed>0 ? "OK" : "EMPTY");
  }
#endif
