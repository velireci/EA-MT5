// PUSH notifications for PROVEN facts of OWNED objects (mirror of Notifier in tests/lifecycle_reference.py). It decides, sends and cancels nothing in the market: it only turns what the lifecycle and the registrar
// observe into short texts. What counts as a fact: a pending order seen ACTIVE in the broker facts (never "OrderSend returned true"), a position that exists because a tracked order is FILLED, a partial close
// (the owned position's volume DECREASED while it is still there), a modification (its SL changed; the exit transport's position read has no TP), a final close (the position list is readable, stable and holds
// no such position), a pending removed (cancelled / expired). Ownership = the record's magic and symbol: a manual trade never reaches this class. Every event has a key and is announced once (polls and reconciles
// repeat the same facts); a failed send is retried by the next tick up to NT_MAX_TRIES and then dropped; a throttled send (RETRY_LATER) does not consume attempts. A failure never changes a decision and
// never resends an order. An event is REMEMBERED in an outbox the moment it is observed and is delivered at the end of every lifecycle tick (OnTick), so it survives the removal of its object from the index;
// nothing waits across a restart (the baseline only remembers). While `baseline` is true the facts are only remembered (a restart repeats nothing; an event that happened while the robot was down is not announced).
// The ONLY terminal call is SendNotification in CNtPushSink; the tests use a FAKE sink. Nothing is sent by the build.
#ifndef VELO_ENTRY_NOTIFY_MQH
#define VELO_ENTRY_NOTIFY_MQH

#include "EntryLifecycle.mqh"

#define NT_SENT 0
#define NT_RETRY_LATER 1
#define NT_FAILED 2
#define NT_MAX_TRIES 3
#define NT_MAX_KEYS 256
#define NT_MAX_POS 16
#define NT_MAX_OUTBOX 32

class CNtSink
  {
public:
   virtual int Send(const string text)=0;
  };

// the real receiver: the terminal's push notification (needs the MetaQuotes ID in the terminal options). MT5 allows at most 2 calls per second and 10 per minute: the sink keeps its own margin (>= 1 s apart, 8 per
// 60 s) and answers RETRY_LATER instead of calling the terminal when it would exceed it.
class CNtPushSink : public CNtSink
  {
public:
   ulong stamps[8];
   int n;
   CNtPushSink(void) {n=0;}
   virtual int Send(const string text)
     {
      ulong now=GetTickCount64();
      int keep=0;
      for(int i=0;i<n;i++)
         if(now-stamps[i]<60000) {stamps[keep]=stamps[i]; keep++;}
      n=keep;
      if(n>=8 || (n>0 && now-stamps[n-1]<1000)) return(NT_RETRY_LATER);
      ResetLastError();
      bool ok=SendNotification(text);
      stamps[n]=now;
      n++;
      return(ok ? NT_SENT : NT_FAILED);
     }
  };

class CNtNotifier : public CLcObserver
  {
public:
   CNtSink *sink;
   CEnStore *store;
   long magic;
   string symbol;
   string prefix;
   bool baseline;
   string done[NT_MAX_KEYS];
   int n_done;
   string tkey[NT_MAX_KEYS];
   int tcount[NT_MAX_KEYS];
   int n_t;
   string okey[NT_MAX_OUTBOX];
   string otext[NT_MAX_OUTBOX];
   int n_out;
   ulong lpid[NT_MAX_POS];
   double lvol[NT_MAX_POS];
   double lsl[NT_MAX_POS];
   int n_last;
   CNtNotifier(void) {sink=NULL; store=NULL; magic=0; symbol=""; prefix=""; baseline=false; n_done=0; n_t=0; n_last=0; n_out=0;}
   bool IsDone(const string key)
     {
      for(int i=0;i<n_done;i++)
         if(done[i]==key) return(true);
      return(false);
     }
   void MarkDone(const string key)
     {
      if(n_done>=NT_MAX_KEYS)
        {
         for(int i=1;i<n_done;i++) done[i-1]=done[i];      // the oldest key falls out
         n_done--;
        }
      done[n_done]=key;
      n_done++;
     }
   bool Load(const long login,const string sid,SEnRecord &rec)
     {
      string why;
      if(store==NULL) return(false);
      if(EN_Load(store,EN_FileName(login,sid),rec,why)!=1) return(false);
      return(rec.magic==magic && rec.symbol==symbol);
     }
   bool InOutbox(const string key)
     {
      for(int i=0;i<n_out;i++)
         if(okey[i]==key) return(true);
      return(false);
     }
   void OutboxRemove(const int k)
     {
      for(int i=k;i<n_out-1;i++) {okey[i]=okey[i+1]; otext[i]=otext[i+1];}
      n_out--;
     }
   // the event is REMEMBERED: queued for the receiver (sent at the end of the lifecycle tick), or only noted in the baseline
   void Emit(const string key,const string text)
     {
      if(IsDone(key) || InOutbox(key)) return;
      if(baseline) {MarkDone(key); return;}
      if(sink==NULL) return;
      if(n_out>=NT_MAX_OUTBOX) OutboxRemove(0);                 // the oldest waiting event falls out (bounded memory)
      okey[n_out]=key;
      otext[n_out]=StringSubstr(prefix+text,0,250);
      n_out++;
     }
   // deliver the waiting events in order: SENT settles; RETRY_LATER keeps the event and stops until the next tick without consuming an attempt; FAILED consumes an attempt and drops it after NT_MAX_TRIES
   virtual void OnTick(void)
     {
      if(sink==NULL) return;
      int i=0;
      while(i<n_out)
        {
         int st=sink.Send(otext[i]);
         if(st==NT_SENT) {MarkDone(okey[i]); OutboxRemove(i); continue;}
         if(st==NT_RETRY_LATER) return;
         int k=-1;
         for(int j=0;j<n_t;j++)
            if(tkey[j]==okey[i]) k=j;
         if(k<0 && n_t<NT_MAX_KEYS) {k=n_t; tkey[k]=okey[i]; tcount[k]=0; n_t++;}
         if(k>=0) tcount[k]++;
         if(k<0 || tcount[k]>=NT_MAX_TRIES) {MarkDone(okey[i]); OutboxRemove(i); continue;}
         i++;
        }
     }
   string Side(const SEnRecord &rec) {return(rec.direction==1 ? "BUY" : "SELL");}
   virtual void OnVerdict(const long login,const string sid,const int verdict,const int removed_kind)
     {
      if(verdict!=LC_V_OPEN && verdict!=LC_V_FILLED && verdict!=LC_V_CLOSED) return;
      SEnRecord rec;
      if(!Load(login,sid,rec)) return;
      if(verdict==LC_V_OPEN)
         Emit("placed|"+sid,StringFormat("PENDING PLACED %s %s %.2f SL %.2f TP %.2f vol %.2f (%s)",rec.symbol,Side(rec),rec.e,rec.s,rec.tp,rec.volume,sid));
      else
         if(verdict==LC_V_FILLED)
            Emit("filled|"+sid+"|"+IntegerToString((long)rec.position_id),StringFormat("POSITION OPENED %s %s vol %.2f SL %.2f TP %.2f pos %I64u (%s)",rec.symbol,Side(rec),rec.volume,rec.s,rec.tp,rec.position_id,sid));
         else
            if(removed_kind==1 || removed_kind==2)
               Emit("removed|"+sid,StringFormat("PENDING %s %s %s (%s)",(removed_kind==2 ? "EXPIRED" : "CANCELLED"),rec.symbol,Side(rec),sid));
     }
   void LastRemove(const int k)
     {
      for(int i=k;i<n_last-1;i++) {lpid[i]=lpid[i+1]; lvol[i]=lvol[i+1]; lsl[i]=lsl[i+1];}
      n_last--;
     }
   int LastIndex(const ulong pid)
     {
      for(int i=0;i<n_last;i++)
         if(lpid[i]==pid) return(i);
      return(-1);
     }
   virtual void OnPosition(const long login,const string sid,const ulong position_id,const double volume,const double sl)
     {
      SEnRecord rec;
      if(!Load(login,sid,rec)) return;
      int k=LastIndex(position_id);
      if(k<0)
        {
         if(n_last>=NT_MAX_POS) LastRemove(0);                // evict the oldest: a new position is never ignored
         lpid[n_last]=position_id;
         lvol[n_last]=volume;
         lsl[n_last]=sl;
         n_last++;                                            // the first observation is the opening (announced by the FILLED verdict)
         return;
        }
      if(volume<lvol[k]-1e-9)
         Emit(StringFormat("partial|%I64u|%.8f",position_id,volume),StringFormat("POSITION PARTIAL CLOSE %s %s vol %.2f -> %.2f (%s)",rec.symbol,Side(rec),lvol[k],volume,sid));
      if(MathAbs(sl-lsl[k])>1e-9)
         Emit(StringFormat("modified|%I64u|%.8f",position_id,sl),StringFormat("POSITION MODIFIED %s %s SL %.2f -> %.2f (%s)",rec.symbol,Side(rec),lsl[k],sl,sid));
      lvol[k]=volume;
      lsl[k]=sl;
     }
   virtual void OnClosed(const long login,const string sid,const ulong position_id)
     {
      SEnRecord rec;
      if(!Load(login,sid,rec)) return;
      Emit(StringFormat("closed|%I64u",position_id),StringFormat("POSITION CLOSED %s %s (%s)",rec.symbol,Side(rec),sid));
      int k=LastIndex(position_id);
      if(k>=0) LastRemove(k);                                 // the position is gone: its tracking entry is released
     }
  };
#endif
