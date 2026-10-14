// T004 pure M15 observer. PROPOSALS, not client-validated entry rules.
// Caller supplies CLOSED chronological M15 bars, explicit H4 source/context,
// and an active proposed structural level. No series, clock or trading API.
#ifndef VELO_M15_CONFIRMATION_MQH
#define VELO_M15_CONFIRMATION_MQH

#define M4_PERIOD 900
#define M4_POLICY_UNSET 0
#define M4_A_AT_OR_AFTER_BREAK 1

struct SM4Context
  {
   string setup;
   int direction;                   // +1 BUY, -1 SELL; explicitly selected source
   string source;
   string fvg;
   double lower;
   double upper;
   datetime confirmed;
   datetime valid_from;              // close of the H4 touching/reconfirming bar
   bool ready;
   bool reliable;
   bool selected;
  };

struct SM4Level
  {
   bool valid;
   string id;
   double price;
   datetime known;
  };

struct SM4Candidate
  {
   string id;
   double lower;
   double upper;
   datetime confirmed;
   bool returned;
   bool invalid;
  };

struct SM4Event
  {
   string type;
   datetime time;                   // source bar open (context events: observation time)
   datetime known;                  // earliest observation/close, never source bar open
   string ref;
  };

struct SM4State
  {
   int policy;
   string phase;
   bool has_context;
   SM4Context context;
   datetime active_from;
   datetime observed;
   datetime last_asof;
   bool has_last;
   MqlRates last;
   MqlRates recent[3];
   int recent_n;
   datetime bos_time;
   datetime bos_known;
   string bos_level;
  };

void M4ContextInit(SM4Context &c)
  {
   c.setup=""; c.direction=0; c.source=""; c.fvg="";
   c.lower=0; c.upper=0; c.confirmed=0; c.valid_from=0;
   c.ready=false; c.reliable=false; c.selected=false;
  }

void M4NoLevel(SM4Level &l)
  {
   l.valid=false; l.id=""; l.price=0; l.known=0;
  }

void M4ClearProgress(SM4State &s, SM4Candidate &f[])
  {
   ArrayResize(f,0);
   s.recent_n=0; s.bos_time=0; s.bos_known=0; s.bos_level="";
  }

void M4Init(SM4State &s, SM4Candidate &f[], SM4Event &events[],
            const int policy=M4_POLICY_UNSET)
  {
   s.policy=policy; s.phase="WAIT_CONTEXT"; s.has_context=false;
   M4ContextInit(s.context);
   s.active_from=0; s.observed=0; s.last_asof=0; s.has_last=false;
   M4ClearProgress(s,f);
   ArrayResize(events,0);
  }

void M4Event(SM4Event &events[],const string kind,const datetime when,
             const datetime known,const string ref)
  {
   int n=ArraySize(events);
   ArrayResize(events,n+1,32);
   events[n].type=kind; events[n].time=when; events[n].known=known; events[n].ref=ref;
  }

string M4ReplayRequired(SM4State &s,SM4Candidate &f[],SM4Event &events[],const datetime known)
  {
   if(known>s.last_asof)
      s.last_asof=known;
   M4ClearProgress(s,f);
   if(s.phase!="REPLAY_REQUIRED")
      M4Event(events,"REPLAY_REQUIRED",known,known,(s.has_context ? s.context.setup : ""));
   s.phase="REPLAY_REQUIRED";
   return(s.phase);
  }

bool M4ContextEqual(const SM4Context &a,const SM4Context &b)
  {
   return(a.setup==b.setup && a.direction==b.direction && a.source==b.source && a.fvg==b.fvg &&
          a.lower==b.lower && a.upper==b.upper && a.confirmed==b.confirmed && a.valid_from==b.valid_from &&
          a.ready==b.ready && a.reliable==b.reliable && a.selected==b.selected);
  }

// Re-applying the same snapshot does not restart or heal a REPLAY_REQUIRED epoch.
// The caller constructs a new observer and replays to repair revised history.
bool M4SetContext(const SM4Context &c,const datetime observed_at,SM4State &s,
                   SM4Candidate &f[],SM4Event &events[])
  {
   if(observed_at<s.last_asof)
     {
      M4ReplayRequired(s,f,events,s.last_asof);
      return(false);
     }
   s.last_asof=observed_at;
   bool good=(c.ready && c.reliable && c.selected && (c.direction==1 || c.direction==-1) &&
              c.setup!="" && c.source!="" && c.fvg!="" && MathIsValidNumber(c.lower) &&
              MathIsValidNumber(c.upper) && c.lower>0 && c.upper>c.lower && c.confirmed>0 &&
              c.confirmed<=c.valid_from && c.valid_from<=observed_at);
   if(good && s.has_context && M4ContextEqual(c,s.context))
      return(false);
   if(s.has_context)
      M4Event(events,"CONTEXT_CLOSED",observed_at,observed_at,s.context.setup);
   M4ClearProgress(s,f);
   s.has_last=false;
   s.has_context=good;
   M4ContextInit(s.context);
   if(good)
      s.context=c;
   s.observed=observed_at;
   s.active_from=(good ? (c.valid_from>observed_at ? c.valid_from : observed_at) : 0);
   s.phase=(good ? (s.policy==M4_A_AT_OR_AFTER_BREAK ? "WAIT_BREAK" : "WAIT_POLICY") : "WAIT_CONTEXT");
   if(good)
      M4Event(events,"CONTEXT_OPEN",observed_at,observed_at,c.setup);
   return(true);
  }

bool M4SameBar(const MqlRates &a,const MqlRates &b)
  {
   // Open/volume/spread are not consumed by this close/extreme-based observer.
   return(a.time==b.time && a.high==b.high && a.low==b.low && a.close==b.close);
  }

void M4PushBar(const MqlRates &bar,SM4State &s)
  {
   if(s.recent_n==3)
     {
      s.recent[0]=s.recent[1];
      s.recent[1]=s.recent[2];
      s.recent[2]=bar;
     }
   else
     {
      s.recent[s.recent_n]=bar;
      s.recent_n++;
     }
   s.last=bar; s.has_last=true;
  }

string M4Step(const MqlRates &bar,const datetime asof,const SM4Level &level,
               SM4State &s,SM4Candidate &f[],SM4Event &events[])
  {
   if(s.phase=="REPLAY_REQUIRED")
      return(s.phase);
   if(!s.has_context)
      return("WAIT_CONTEXT");
   if(bar.time<=0 || (long)bar.time%M4_PERIOD!=0)
      return("INVALID_BAR");
   if(bar.time<s.active_from)
      return("BEFORE_CONTEXT");
   if(bar.time+M4_PERIOD>asof)
      return("NOT_CLOSED");
   if(asof<s.last_asof)
      return(M4ReplayRequired(s,f,events,s.last_asof));
   // A malformed revision is still a revision: never retain the old FVG result.
   if(s.has_last && bar.time<=s.last.time)
     {
      if(bar.time==s.last.time && M4SameBar(bar,s.last))
        {
         s.last_asof=asof;
         return("DUPLICATE");
        }
      return(M4ReplayRequired(s,f,events,asof));
     }
   if(!MathIsValidNumber(bar.high) || !MathIsValidNumber(bar.low) || !MathIsValidNumber(bar.close) ||
      bar.low<=0 || bar.high<bar.low || bar.close<bar.low || bar.close>bar.high)
      return("INVALID_BAR");
   s.last_asof=asof;
   if(s.has_last)
     {
      if(bar.time!=s.last.time+M4_PERIOD)
        {
         M4ClearProgress(s,f);
         s.phase=(s.policy==M4_A_AT_OR_AFTER_BREAK ? "WAIT_BREAK" : "WAIT_POLICY");
         M4PushBar(bar,s);
         M4Event(events,"DATA_GAP",bar.time,bar.time+M4_PERIOD,s.context.setup);
         return("DATA_GAP");
        }
     }
   M4PushBar(bar,s);
   if(s.policy!=M4_A_AT_OR_AFTER_BREAK)
      return("WAIT_POLICY");
   int d=s.context.direction;
   if(s.bos_time==0)
     {
      bool usable=(level.valid && level.id!="" && MathIsValidNumber(level.price) &&
                   level.price>0 && level.known>0 && level.known<=bar.time);
      if(usable && d*(bar.close-level.price)>0)
        {
         s.bos_time=bar.time; s.bos_known=bar.time+M4_PERIOD; s.bos_level=level.id;
         s.phase="WAIT_FVG";
         M4Event(events,"BOS_CANDIDATE",bar.time,s.bos_known,level.id);
        }
     }
   int nf=ArraySize(f);
   for(int i=0;i<nf;i++)
     {
      if(f[i].invalid || bar.time<f[i].confirmed)
         continue;
      if((d>0 && bar.close<f[i].lower) || (d<0 && bar.close>f[i].upper))
        {
         f[i].invalid=true;
         M4Event(events,"FVG_INVALIDATED",bar.time,bar.time+M4_PERIOD,f[i].id);
        }
      else if(!f[i].returned && bar.low<=f[i].upper && bar.high>=f[i].lower)
        {
         f[i].returned=true;
         M4Event(events,"RETURN_OBSERVED",bar.time,bar.time+M4_PERIOD,f[i].id);
        }
     }
   if(s.bos_time>0 && s.recent_n==3)
     {
      MqlRates a=s.recent[0];
      bool gap=(d>0 ? bar.low>a.high : bar.high<a.low);
      if(a.time>=s.bos_time && gap)
        {
         int i=ArraySize(f);
         ArrayResize(f,i+1,16);
         f[i].id="M15F"+IntegerToString((long)a.time)+(d>0 ? "U" : "D");
         f[i].lower=(d>0 ? a.high : bar.high);
         f[i].upper=(d>0 ? bar.low : a.low);
         f[i].confirmed=bar.time+M4_PERIOD;
         f[i].returned=false; f[i].invalid=false;
         M4Event(events,"FVG_CANDIDATE",bar.time,bar.time+M4_PERIOD,f[i].id);
        }
     }
   if(s.bos_time>0)
     {
      bool any=false,returned=false;
      for(int i=0;i<ArraySize(f);i++)
         if(!f[i].invalid)
           {
            any=true;
            if(f[i].returned) returned=true;
           }
      s.phase=(returned ? "RETURN_OBSERVED" : (any ? "WAIT_RETURN" : "WAIT_FVG"));
     }
   return("PROCESSED");
  }
#endif
