// T004 round 4: ORDINARY H4 FVG-touch context source. TECHNICAL PROPOSAL, not a client rule.
// Pure logic: closed H4 bars in, chronological context updates out. No series, clock, price or
// trading API. Mirrors tests/t004_ordinary_reference.py. Reuses T002 (H4Structure.mqh) UNCHANGED:
// swings, trend, interval, FVG FRESH/TOUCHED/INVALID, IRL class, nearest-first order, ERL state,
// H4SetupActive. Adds only the bookkeeping T002 (stateless drawing) does not have.
//
// Rules (see docs/T004-m15.md for which are reused and which are proposals):
//  * At every H4 close j: post = last `window` closed bars ending at j, pre = ending at j-1.
//    The final H4 state is never used for an earlier moment.
//  * A touch is judged against the state known BEFORE the touching candle opens (pre): trending,
//    valid interval, ERL untouched, FVG is an IRL candidate. So the FVG's candle C closed at or
//    before the touching candle's open. The wick range must intersect the zone (inclusive).
//  * Recorded at the CLOSE of the touching candle (valid_from = known). Requires the same FVG to
//    still be a valid IRL candidate with an active setup in post (a close strictly beyond the far
//    edge on the touching candle itself = INVALID wins).
//  * Several touched candidates: T002 nearest-first order, reference price = close of the last bar
//    closed before the touching candle.
//  * An open record is not changed by later touches. It is revoked at the first close where it no
//    longer holds. No expiry by bar count is invented.
//  * After revocation a later touch can record again. AFTER_LOSS: any valid IRL candidate (T002:
//    no re-use limit). FIRST_ONLY: an FVG id is recorded at most once per scan.
//  * RETOUCH_UNSET (default): contexts are produced unselected, the observer blocks.
#ifndef VELO_H4_TOUCH_CONTEXT_MQH
#define VELO_H4_TOUCH_CONTEXT_MQH
#include "M15Timeline.mqh"
#include "H4Structure.mqh"

#define M4_RETOUCH_UNSET 0
#define M4_RETOUCH_AFTER_LOSS 1
#define M4_RETOUCH_FIRST_ONLY 2
#define M4_H4_PERIOD 14400
#define M4_SRC_T002_TOUCH "T002_H4_TOUCH_PROPOSAL"
#define M4_SRC_T003 "T003_PROTOTYPE"

struct SM4OrdInfo
  {
   string status;
   int steps;
   int opened;
   int closed;
   int replaced;
  };

// Display flag only. Never resolves a disagreement between sources.
string M4DirectionAgreement(const int direction,const string other)
  {
   int o=0;
   if(StringFind(other,"BULL")==0) o=1;
   else if(StringFind(other,"BEAR")==0) o=-1;
   if(direction==0 || o==0)
      return("NO_DIRECTION");
   return(direction==o ? "AGREE" : "DISAGREE");
  }

// "" while the record holds, else the reason. Order is only a labelling priority.
string M4OrdSurvival(const int direction,const string fvg_id,const SH4Fvg &fvgs[],const int nf,
                      const SH4Result &res,const bool reliable)
  {
   if(!reliable)
      return("HISTORY_PARTIAL");
   if(res.direction!=(direction>0 ? H4_DIR_BULLISH : H4_DIR_BEARISH))
      return("TREND_CHANGE");
   int k=-1;
   for(int i=0;i<nf;i++)
      if(fvgs[i].id==fvg_id) {k=i;break;}
   if(k<0)
      return("FVG_NOT_IN_WINDOW");
   if(fvgs[k].state==H4_FVG_INVALID)
      return("FVG_INVALID");
   if(res.range_state!=H4_RNG_VALID)
      return("INTERVAL_LOST");
   if(res.erl_state!=H4_ERL_UNTOUCHED)
      return("ERL_TAKEN");
   if(fvgs[k].cls!=H4_CLS_IRL)
      return("NOT_IRL");
   return("");
  }

void M4OrdSlice(const MqlRates &src[],const int from,const int to_excl,MqlRates &dst[])
  {
   int c=to_excl-from;
   ArrayResize(dst,c);
   for(int i=0;i<c;i++)
      dst[i]=src[from+i];
  }

bool M4OrdBarsValid(const MqlRates &h4[],const int n)
  {
   for(int i=0;i<n;i++)
     {
      if(h4[i].time<=0 || (long)h4[i].time%M4_H4_PERIOD!=0 || !MathIsValidNumber(h4[i].high) ||
         !MathIsValidNumber(h4[i].low) || !MathIsValidNumber(h4[i].close) || h4[i].low<=0 ||
         h4[i].high<h4[i].low || h4[i].close<h4[i].low || h4[i].close>h4[i].high ||
         (i>0 && h4[i].time<=h4[i-1].time))
         return(false);
     }
   return(true);
  }

// h4[0..n-1]: chronological CLOSED H4 bars. The close of every bar j >= max(scan_from,1) is one step.
// Updates are appended in chronological order, at most one per H4 close; notes[] runs in parallel.
void M4OrdinaryScan(const MqlRates &h4[],const int n,const int scan_from,const int left,const int right,
                     const int window,const int retouch,
                     SM4ContextUpdate &updates[],string &notes[],SM4OrdInfo &info)
  {
   ArrayResize(updates,0);ArrayResize(notes,0);
   info.status="INVALID_INPUT";info.steps=0;info.opened=0;info.closed=0;info.replaced=0;
   if(n<0 || n>ArraySize(h4) || scan_from<0 || left<1 || left>10 || right<1 || right>10 ||
      window<50 || window>1000 || retouch<0 || retouch>2)
      return;
   if(!M4OrdBarsValid(h4,n))
     {info.status="INVALID_H4";return;}
   bool gate=(retouch!=M4_RETOUCH_UNSET);
   bool held=false;
   int hdir=0;
   string hfvg="";
   string recorded[];
   int nrec=0;
   MqlRates pre[],post[];
   SH4Swing swp[],swa[];
   SH4Fvg fvp[],fva[];
   SH4Result resp,resa;
   int nsp=0,nfp=0,nsa=0,nfa=0;
   int start=(scan_from>1 ? scan_from : 1);
   for(int j=start;j<n;j++)
     {
      datetime known=h4[j].time+M4_H4_PERIOD;
      int pre_from=(j>window ? j-window : 0);
      int post_from=(j+1>window ? j+1-window : 0);
      int npre=j-pre_from,npost=j+1-post_from;
      bool reliable=(npre>=window && npost>=window && npre>=2*(left+right)+3);
      M4OrdSlice(h4,post_from,j+1,post);
      H4Analyze(post,npost,left,right,M4_H4_PERIOD,swp,nsp,fvp,nfp,resp);
      string lost="";
      if(held)
        {
         lost=M4OrdSurvival(hdir,hfvg,fvp,nfp,resp,reliable);
         if(lost!="") held=false;
        }
      bool opened=false;
      int pick=-1;
      if(!held && reliable)
        {
         M4OrdSlice(h4,pre_from,j,pre);
         H4Analyze(pre,npre,left,right,M4_H4_PERIOD,swa,nsa,fva,nfa,resa);
         int order[];
         int cnt=H4SelectIrl(fva,nfa,resa,pre[npre-1].close,order);
         if(H4SetupActive(resa,cnt))
           {
            for(int q=0;q<cnt && !opened;q++)
              {
               int k=order[q];
               if(retouch==M4_RETOUCH_FIRST_ONLY)
                 {
                  bool seen=false;
                  for(int r=0;r<nrec;r++)
                     if(recorded[r]==fva[k].id) {seen=true;break;}
                  if(seen) continue;
                 }
               if(!(h4[j].low<=fva[k].upper && h4[j].high>=fva[k].lower))
                  continue;
               if(M4OrdSurvival(fva[k].bullish ? 1 : -1,fva[k].id,fvp,nfp,resp,reliable)!="")
                  continue;
               pick=k;opened=true;
              }
           }
        }
      if(opened || lost!="")
        {
         int u=ArraySize(updates);
         ArrayResize(updates,u+1,32);ArrayResize(notes,u+1,32);
         updates[u].known=known;
         M4ContextInit(updates[u].context);
         if(opened)
           {
            SM4Context c;
            M4ContextInit(c);
            c.direction=(fva[pick].bullish ? 1 : -1);
            c.setup="T002TOUCH-"+H4TimeStamp(known)+"-"+fva[pick].id;
            c.source=M4_SRC_T002_TOUCH;
            c.fvg=fva[pick].id;
            c.lower=fva[pick].lower;c.upper=fva[pick].upper;
            c.confirmed=fva[pick].confirm_time;c.valid_from=known;
            c.ready=true;c.reliable=true;c.selected=gate;
            updates[u].context=c;
            notes[u]=(lost!="" ? "REPLACE after "+lost : "OPEN");
            held=true;hdir=c.direction;hfvg=c.fvg;
            ArrayResize(recorded,nrec+1,16);
            recorded[nrec]=c.fvg;nrec++;
            info.opened++;
            if(lost!="") info.replaced++;
           }
         else
           {
            notes[u]="CLOSE "+lost;
            info.closed++;
           }
        }
      info.steps++;
     }
   info.status=(info.steps>0 ? "OK" : "EMPTY");
  }
#endif
