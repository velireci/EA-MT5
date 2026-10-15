// T012 READ-ONLY daily history FACTS for the robot. Mirrors tests/t012_history_reference.py (its header documents the day window, the ownership
// rules, the facts and the verdicts in full). Two layers: (1) DH_Build, a PURE core over already-read raw data (tested with fixtures); (2) the thin
// MT5 reader DH_ReadRaw / DH_ReadAndBuild, the ONLY place that calls terminal APIs (all reads; UNVERIFIED against a live terminal).
// It collects FACTS and applies NO policy: no trade count (a deal is not a trade), no win / loss / breakeven, no choice of the daily result
// formula (result_formula is the constant UNSET; three candidates are printed side by side), no reconstruction of the balance at the start of the
// day (balance_start_known is always false). Unclassified data is never turned into zero or CLEAR: an UNKNOWN / BLOCK verdict carries no facts.
// Not wired to the real permit. No order, no modification, no persistence, no real reset.
// Ownership: position-level, from the OPENING deal's magic == the EA magic (explicit input, > 0); a magic number is not unique proof of the EA.
// The Tirane day comes from T009 (SP_Evaluate); deal times are SERVER time, converted with an explicit offset input.
#ifndef VELO_DAILY_HISTORY_MQH
#define VELO_DAILY_HISTORY_MQH

#include "ExitSnapshotAdapter.mqh"

#define DH_MAX_DEALS 200
#define DH_MAX_POS 32
#define DH_ENTRY_IN 0
#define DH_ENTRY_OUT 1
#define DH_ENTRY_INOUT 2
#define DH_ENTRY_OUT_BY 3
#define DH_DEAL_BUY 0
#define DH_DEAL_SELL 1
#define DH_MARGIN_HEDGING 2
#define DH_NCLASSES 5            // IN, OUT, INOUT, OUT_BY, OTHER

enum ENUM_DH_VERDICT
  {
   DH_READY=0,
   DH_UNKNOWN,
   DH_BLOCK
  };

struct SDhCfg
  {
   long ea_magic;
   datetime utc_in_day;
   int server_offset_seconds;
   bool history_complete_asserted;
  };

struct SDhRawDeal
  {
   ulong ticket;
   ulong position_id;
   long time;
   int entry;
   int type;
   long magic;
   double volume;
   double profit;
   double commission;
   double swap;
   double fee;
  };

struct SDhRawPos
  {
   ulong position_id;
   bool opened_known;
   long opened_magic;
   double open_volume_total;
   double closed_volume_total;
   bool is_open;
  };

struct SDhRaw
  {
   bool api_ok;
   string api_error;
   bool hist_ok;
   bool positions_ok;
   bool margin_ok;
   int margin_mode;
   double vol_step;
   bool deals_truncated;
   bool pos_truncated;
   int n_deals;
   SDhRawDeal deal[DH_MAX_DEALS];
   int n_pos;
   SDhRawPos pos[DH_MAX_POS];
  };

struct SDhCell
  {
   int count;
   double volume;
   double profit;
   double commission;
   double swap;
   double fee;
  };

struct SDhPosFact
  {
   ulong position_id;
   int n_in;
   int n_out;
   double volume_in;
   double volume_out;
   double profit;
   double commission;
   double swap;
   double fee;
   string state;
  };

struct SDhFacts
  {
   int day_key;
   long window_start;
   long window_end;
   int deals_in_window;
   int duplicates;
   int outside_window;
   int other_trade_deals;
   int exits_not_by_ea_magic;
   int nontrade_count;
   double nontrade_profit;
   double nontrade_commission;
   double nontrade_swap;
   double nontrade_fee;
   SDhCell cell[DH_NCLASSES];
   int n_pos;
   SDhPosFact pos[DH_MAX_POS];
   double candidate_profit;
   double candidate_profit_commission_swap;
   double candidate_profit_commission_swap_fee;
   string result_formula;
   bool balance_start_known;
   string balance_start_note;
   bool complete;
   string proof;
  };

string DH_VerdictName(const ENUM_DH_VERDICT v)
  {
   switch(v)
     {
      case DH_READY: return("READY");
      case DH_UNKNOWN: return("UNKNOWN");
      case DH_BLOCK: return("BLOCK");
     }
   return("?");
  }

string DH_ClassName(const int c)
  {
   switch(c)
     {
      case 0: return("IN");
      case 1: return("OUT");
      case 2: return("INOUT");
      case 3: return("OUT_BY");
     }
   return("OTHER");
  }

int DH_EntryClass(const int entry)
  {
   if(entry==DH_ENTRY_IN) return(0);
   if(entry==DH_ENTRY_OUT) return(1);
   if(entry==DH_ENTRY_INOUT) return(2);
   if(entry==DH_ENTRY_OUT_BY) return(3);
   return(4);
  }

void DH_RawInit(SDhRaw &r)
  {
   r.api_ok=true;
   r.api_error="";
   r.hist_ok=false;
   r.positions_ok=false;
   r.margin_ok=false;
   r.margin_mode=-1;
   r.vol_step=0.0;
   r.deals_truncated=false;
   r.pos_truncated=false;
   r.n_deals=0;
   r.n_pos=0;
   for(int i=0;i<DH_MAX_DEALS;i++)
     {
      r.deal[i].ticket=0;
      r.deal[i].position_id=0;
      r.deal[i].time=0;
      r.deal[i].entry=-1;
      r.deal[i].type=-1;
      r.deal[i].magic=0;
      r.deal[i].volume=0.0;
      r.deal[i].profit=0.0;
      r.deal[i].commission=0.0;
      r.deal[i].swap=0.0;
      r.deal[i].fee=0.0;
     }
   for(int k=0;k<DH_MAX_POS;k++)
     {
      r.pos[k].position_id=0;
      r.pos[k].opened_known=false;
      r.pos[k].opened_magic=0;
      r.pos[k].open_volume_total=0.0;
      r.pos[k].closed_volume_total=0.0;
      r.pos[k].is_open=false;
     }
  }

void DH_FactsInit(SDhFacts &f)
  {
   f.day_key=0;
   f.window_start=0;
   f.window_end=0;
   f.deals_in_window=0;
   f.duplicates=0;
   f.outside_window=0;
   f.other_trade_deals=0;
   f.exits_not_by_ea_magic=0;
   f.nontrade_count=0;
   f.nontrade_profit=0.0;
   f.nontrade_commission=0.0;
   f.nontrade_swap=0.0;
   f.nontrade_fee=0.0;
   for(int c=0;c<DH_NCLASSES;c++)
     {
      f.cell[c].count=0;
      f.cell[c].volume=0.0;
      f.cell[c].profit=0.0;
      f.cell[c].commission=0.0;
      f.cell[c].swap=0.0;
      f.cell[c].fee=0.0;
     }
   f.n_pos=0;
   f.candidate_profit=0.0;
   f.candidate_profit_commission_swap=0.0;
   f.candidate_profit_commission_swap_fee=0.0;
   f.result_formula="UNSET";
   f.balance_start_known=false;
   f.balance_start_note="NOT RECONSTRUCTED: current balance minus profit ignores deposits, withdrawals, credits and costs; supply it or read it in a separately verified step";
   f.complete=false;
   f.proof="";
  }

// two reads are the same read (stability)
bool DH_RawEqual(const SDhRaw &a,const SDhRaw &b)
  {
   if(a.api_ok!=b.api_ok || a.api_error!=b.api_error || a.hist_ok!=b.hist_ok || a.positions_ok!=b.positions_ok || a.margin_ok!=b.margin_ok ||
      a.margin_mode!=b.margin_mode || a.vol_step!=b.vol_step || a.deals_truncated!=b.deals_truncated || a.pos_truncated!=b.pos_truncated ||
      a.n_deals!=b.n_deals || a.n_pos!=b.n_pos)
      return(false);
   for(int i=0;i<a.n_deals && i<DH_MAX_DEALS;i++)
      if(a.deal[i].ticket!=b.deal[i].ticket || a.deal[i].position_id!=b.deal[i].position_id || a.deal[i].time!=b.deal[i].time ||
         a.deal[i].entry!=b.deal[i].entry || a.deal[i].type!=b.deal[i].type || a.deal[i].magic!=b.deal[i].magic ||
         a.deal[i].volume!=b.deal[i].volume || a.deal[i].profit!=b.deal[i].profit || a.deal[i].commission!=b.deal[i].commission ||
         a.deal[i].swap!=b.deal[i].swap || a.deal[i].fee!=b.deal[i].fee)
         return(false);
   for(int k=0;k<a.n_pos && k<DH_MAX_POS;k++)
      if(a.pos[k].position_id!=b.pos[k].position_id || a.pos[k].opened_known!=b.pos[k].opened_known || a.pos[k].opened_magic!=b.pos[k].opened_magic ||
         a.pos[k].open_volume_total!=b.pos[k].open_volume_total || a.pos[k].closed_volume_total!=b.pos[k].closed_volume_total ||
         a.pos[k].is_open!=b.pos[k].is_open)
         return(false);
   return(true);
  }

bool DH_SameDeal(const SDhRawDeal &a,const SDhRawDeal &b)
  {
   return(a.ticket==b.ticket && a.position_id==b.position_id && a.time==b.time && a.entry==b.entry && a.type==b.type && a.magic==b.magic &&
          a.volume==b.volume && a.profit==b.profit && a.commission==b.commission && a.swap==b.swap && a.fee==b.fee);
  }

bool DH_Fin(const double x) {return(x==x && x-x==0.0);}

// the Tirane day window [start,end) in UTC from T009; false when the instant is not supported
bool DH_DayWindow(const datetime utc,int &day,long &start,long &end)
  {
   SSessionPolicy a,b;
   if(!SP_Evaluate(utc,0,1230,62,true,1260,a) || a.status!="OK") return(false);
   start=(long)a.midnight_utc;
   if(!SP_Evaluate((datetime)(start+30*3600),0,1230,62,true,1260,b) || b.status!="OK") return(false);
   day=a.day_key;
   end=(long)b.midnight_utc;
   return(true);
  }

int DH_FindPos(const SDhRaw &raw,const ulong id)
  {
   for(int i=0;i<raw.n_pos;i++)
      if(raw.pos[i].position_id==id) return(i);
   return(-1);
  }

// Returns the verdict. `facts` is only meaningful (and only written) when the verdict is READY.
ENUM_DH_VERDICT DH_Build(const SDhCfg &cfg,const SDhRaw &raw,const bool stable,SDhFacts &facts,string &reason)
  {
   reason="";
   if(cfg.ea_magic<=0)
     {
      reason="INVALID_CONFIG: ea_magic must be an integer > 0 (0 is the magic of manual, mobile and web orders)";
      return(DH_UNKNOWN);
     }
   int off=cfg.server_offset_seconds;
   if(off%900!=0 || off>50400 || off<-50400)
     {
      reason="INVALID_CONFIG: server_offset_seconds must be a multiple of 900 and within +-14 h";
      return(DH_UNKNOWN);
     }
   int day=0;
   long start=0,end=0;
   if(!DH_DayWindow(cfg.utc_in_day,day,start,end))
     {
      reason="INVALID_CONFIG: utc_in_day is not a supported instant (T009)";
      return(DH_UNKNOWN);
     }
   if(!raw.api_ok) {reason="API_ERROR: "+raw.api_error; return(DH_UNKNOWN);}
   if(!raw.margin_ok) {reason="ACCOUNT_MODE_UNAVAILABLE"; return(DH_UNKNOWN);}
   if(raw.margin_mode!=DH_MARGIN_HEDGING)
     {
      reason=StringFormat("UNSUPPORTED_ACCOUNT_MODE: margin mode %d; only HEDGING separates robot positions from other trades",raw.margin_mode);
      return(DH_BLOCK);
     }
   if(!raw.hist_ok) {reason="HISTORY_UNAVAILABLE: the deal history could not be selected"; return(DH_UNKNOWN);}
   if(!raw.positions_ok) {reason="POSITIONS_UNAVAILABLE: the open positions could not be read"; return(DH_UNKNOWN);}
   if(!DH_Fin(raw.vol_step) || raw.vol_step<=0.0) {reason="SYMBOL_PARAMETERS_UNAVAILABLE: the real volume step could not be read"; return(DH_UNKNOWN);}
   if(raw.deals_truncated || raw.pos_truncated || raw.n_deals>DH_MAX_DEALS || raw.n_pos>DH_MAX_POS)
     {
      reason=StringFormat("CAPACITY: more than %d deals or %d positions; nothing is truncated silently",DH_MAX_DEALS,DH_MAX_POS);
      return(DH_UNKNOWN);
     }
   if(!stable) {reason="READ_UNSTABLE: two consecutive reads differ"; return(DH_UNKNOWN);}
   for(int i=0;i<raw.n_pos;i++)
      for(int j=0;j<i;j++)
         if(raw.pos[j].position_id==raw.pos[i].position_id)
           {
            reason=StringFormat("READ_INCONSISTENT: position %I64u described twice",raw.pos[i].position_id);
            return(DH_UNKNOWN);
           }
   SDhFacts f;
   DH_FactsInit(f);
   f.day_key=day;
   f.window_start=start;
   f.window_end=end;
   int idx[DH_MAX_POS];                       // pfacts index by raw position index; -1 = not touched
   for(int p=0;p<DH_MAX_POS;p++)
      idx[p]=-1;
   SDhPosFact pf[DH_MAX_POS];
   int npf=0;
   int pf_raw[DH_MAX_POS];
   for(int i=0;i<raw.n_deals;i++)
     {
      int same=-1;
      for(int j=0;j<i;j++)
         if(raw.deal[j].ticket==raw.deal[i].ticket)
           {
            same=j;
            break;
           }
      if(same>=0)
        {
         if(DH_SameDeal(raw.deal[same],raw.deal[i]))
           {
            f.duplicates++;
            continue;
           }
         reason=StringFormat("READ_INCONSISTENT: deal ticket %I64u appears twice with different content",raw.deal[i].ticket);
         return(DH_UNKNOWN);
        }
      if(!DH_Fin(raw.deal[i].volume) || !DH_Fin(raw.deal[i].profit) || !DH_Fin(raw.deal[i].commission) || !DH_Fin(raw.deal[i].swap) || !DH_Fin(raw.deal[i].fee))
        {
         reason=StringFormat("READ_INCONSISTENT: deal %I64u has a non-finite number",raw.deal[i].ticket);
         return(DH_UNKNOWN);
        }
      long utc=raw.deal[i].time-(long)off;
      if(!(utc>=start && utc<end))
        {
         f.outside_window++;
         continue;
        }
      f.deals_in_window++;
      if(raw.deal[i].type!=DH_DEAL_BUY && raw.deal[i].type!=DH_DEAL_SELL)
        {
         f.nontrade_count++;
         f.nontrade_profit+=raw.deal[i].profit;
         f.nontrade_commission+=raw.deal[i].commission;
         f.nontrade_swap+=raw.deal[i].swap;
         f.nontrade_fee+=raw.deal[i].fee;
         continue;
        }
      int pi=DH_FindPos(raw,raw.deal[i].position_id);
      if(pi<0 || !raw.pos[pi].opened_known)
        {
         reason=StringFormat("OWNERSHIP_UNPROVABLE: position %I64u of deal %I64u is not described or its opening deal was not found",raw.deal[i].position_id,raw.deal[i].ticket);
         return(DH_UNKNOWN);
        }
      if(raw.pos[pi].opened_magic!=cfg.ea_magic)
        {
         f.other_trade_deals++;
         continue;
        }
      int cls=DH_EntryClass(raw.deal[i].entry);
      f.cell[cls].count++;
      f.cell[cls].volume+=raw.deal[i].volume;
      f.cell[cls].profit+=raw.deal[i].profit;
      f.cell[cls].commission+=raw.deal[i].commission;
      f.cell[cls].swap+=raw.deal[i].swap;
      f.cell[cls].fee+=raw.deal[i].fee;
      if(cls!=0 && raw.deal[i].magic!=cfg.ea_magic)
         f.exits_not_by_ea_magic++;
      int q=idx[pi];
      if(q<0)
        {
         q=npf;
         idx[pi]=q;
         pf_raw[q]=pi;
         pf[q].position_id=raw.deal[i].position_id;
         pf[q].n_in=0; pf[q].n_out=0;
         pf[q].volume_in=0.0; pf[q].volume_out=0.0;
         pf[q].profit=0.0; pf[q].commission=0.0; pf[q].swap=0.0; pf[q].fee=0.0;
         pf[q].state="";
         npf++;
        }
      if(cls==0)
        {
         pf[q].n_in++;
         pf[q].volume_in+=raw.deal[i].volume;
        }
      else
        {
         pf[q].n_out++;
         pf[q].volume_out+=raw.deal[i].volume;
        }
      pf[q].profit+=raw.deal[i].profit;
      pf[q].commission+=raw.deal[i].commission;
      pf[q].swap+=raw.deal[i].swap;
      pf[q].fee+=raw.deal[i].fee;
     }
   // robot positions touched, sorted by position id, with their state from the all-time volumes
   for(int a=0;a<npf;a++)
      for(int b=a+1;b<npf;b++)
         if(pf[b].position_id<pf[a].position_id)
           {
            SDhPosFact tmp=pf[a]; pf[a]=pf[b]; pf[b]=tmp;
            int t2=pf_raw[a]; pf_raw[a]=pf_raw[b]; pf_raw[b]=t2;
           }
   for(int a=0;a<npf;a++)
     {
      int pi=DH_FindPos(raw,pf[a].position_id);
      double ov=raw.pos[pi].open_volume_total,cv=raw.pos[pi].closed_volume_total;
      long opened=(ov>0.0 ? PS_GridSteps(ov,raw.vol_step) : 0);
      long closed=(cv>0.0 ? PS_GridSteps(cv,raw.vol_step) : 0);
      if(opened<0 || closed<0 || opened==0)
        {
         reason=StringFormat("INCONSISTENT_POSITION_VOLUMES: position %I64u volumes are not on the step grid or no entry volume",pf[a].position_id);
         return(DH_UNKNOWN);
        }
      if(raw.pos[pi].is_open)
        {
         if(closed>=opened)
           {
            reason=StringFormat("INCONSISTENT_POSITION_VOLUMES: position %I64u is open but exits (%I64d steps) cover its entries (%I64d steps)",pf[a].position_id,closed,opened);
            return(DH_UNKNOWN);
           }
         pf[a].state=(closed==0 ? "OPEN_NO_EXIT" : "OPEN_PARTIALLY_CLOSED");
        }
      else
        {
         if(closed!=opened)
           {
            reason=StringFormat("INCONSISTENT_POSITION_VOLUMES: position %I64u is not open but exits (%I64d steps) differ from entries (%I64d steps)",pf[a].position_id,closed,opened);
            return(DH_UNKNOWN);
           }
         pf[a].state="CLOSED";
        }
      f.pos[f.n_pos]=pf[a];
      f.n_pos++;
     }
   for(int c=0;c<DH_NCLASSES;c++)
     {
      f.candidate_profit+=f.cell[c].profit;
      f.candidate_profit_commission_swap+=f.cell[c].profit+f.cell[c].commission+f.cell[c].swap;
      f.candidate_profit_commission_swap_fee+=f.cell[c].profit+f.cell[c].commission+f.cell[c].swap+f.cell[c].fee;
     }
   f.complete=cfg.history_complete_asserted;
   f.proof=(f.complete ? "the owner asserts the history is fully loaded; every detectable check passed" :
            "NOT asserted: the terminal cannot prove that the whole account history is loaded");
   facts=f;
   return(DH_READY);
  }

string DH_F(const double v) {return(DoubleToString(v+0.0,6));}

string DH_CellText(const SDhCell &c)
  {
   return(IntegerToString(c.count)+","+DH_F(c.volume)+","+DH_F(c.profit)+","+DH_F(c.commission)+","+DH_F(c.swap)+","+DH_F(c.fee));
  }

// the canonical text the tests compare (fixed order, six decimals)
string DH_FactsText(const SDhFacts &x)
  {
   string pos="";
   for(int i=0;i<x.n_pos;i++)
      pos+=(i>0 ? "," : "")+StringFormat("%I64u:%d:%d:",x.pos[i].position_id,x.pos[i].n_in,x.pos[i].n_out)+DH_F(x.pos[i].volume_in)+":"+DH_F(x.pos[i].volume_out)+":"+
           DH_F(x.pos[i].profit)+":"+DH_F(x.pos[i].commission)+":"+DH_F(x.pos[i].swap)+":"+DH_F(x.pos[i].fee)+":"+x.pos[i].state;
   return(StringFormat("day=%d;win=%I64d-%I64d;dw=%d;dup=%d;out=%d;other=%d;exnot=%d;nt=%d,",x.day_key,x.window_start,x.window_end,x.deals_in_window,x.duplicates,
                       x.outside_window,x.other_trade_deals,x.exits_not_by_ea_magic,x.nontrade_count)+
          DH_F(x.nontrade_profit)+","+DH_F(x.nontrade_commission)+","+DH_F(x.nontrade_swap)+","+DH_F(x.nontrade_fee)+
          ";IN="+DH_CellText(x.cell[0])+";OUT="+DH_CellText(x.cell[1])+";INOUT="+DH_CellText(x.cell[2])+";OUT_BY="+DH_CellText(x.cell[3])+";OTHER="+DH_CellText(x.cell[4])+
          ";pos="+pos+";cand="+DH_F(x.candidate_profit)+","+DH_F(x.candidate_profit_commission_swap)+","+DH_F(x.candidate_profit_commission_swap_fee)+
          ";formula="+x.result_formula+";bal="+(x.balance_start_known ? "1" : "0")+";complete="+(x.complete ? "1" : "0"));
  }

// ======================= THE ONLY TERMINAL READS (UNVERIFIED against the live terminal) =======================
// Order matters: the day's deals are copied FIRST (HistorySelect), then each distinct trade position is described with HistorySelectByPosition
// (which REPLACES the selected history), then the open positions are read. Every failure is recorded; nothing is truncated silently.
void DH_ReadRaw(const string symbol,const SDhCfg &cfg,SDhRaw &raw)
  {
   DH_RawInit(raw);
   int day=0;
   long start=0,end=0;
   if(!DH_DayWindow(cfg.utc_in_day,day,start,end))
     {
      raw.api_ok=false;
      raw.api_error="the day window is not supported (T009)";
      return;
     }
   ResetLastError();
   double step=0.0;
   if(SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP,step))
      raw.vol_step=step;
   ResetLastError();
   long mm=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   XA_ModeRead(mm,GetLastError(),raw.margin_mode,raw.margin_ok);
   datetime from_server=(datetime)(start+cfg.server_offset_seconds-3600);       // widened by one hour: the window is applied in DH_Build
   datetime to_server=(datetime)(end+cfg.server_offset_seconds+3600);
   raw.hist_ok=HistorySelect(from_server,to_server);
   if(raw.hist_ok)
     {
      int nd=HistoryDealsTotal();
      if(nd>DH_MAX_DEALS)
        {
         raw.deals_truncated=true;
         nd=DH_MAX_DEALS;
        }
      for(int i=0;i<nd;i++)
        {
         ulong dt=HistoryDealGetTicket(i);
         if(dt==0)
           {
            raw.api_ok=false;
            raw.api_error="HistoryDealGetTicket failed, error "+IntegerToString(GetLastError());
            break;
           }
         long pid=0,tm=0,en=0,ty=0,mg=0;
         double vo=0.0,pr=0.0,co=0.0,sw=0.0,fe=0.0;
         if(!HistoryDealGetInteger(dt,DEAL_POSITION_ID,pid) || !HistoryDealGetInteger(dt,DEAL_TIME,tm) || !HistoryDealGetInteger(dt,DEAL_ENTRY,en) ||
            !HistoryDealGetInteger(dt,DEAL_TYPE,ty) || !HistoryDealGetInteger(dt,DEAL_MAGIC,mg) || !HistoryDealGetDouble(dt,DEAL_VOLUME,vo) ||
            !HistoryDealGetDouble(dt,DEAL_PROFIT,pr) || !HistoryDealGetDouble(dt,DEAL_COMMISSION,co) || !HistoryDealGetDouble(dt,DEAL_SWAP,sw) ||
            !HistoryDealGetDouble(dt,DEAL_FEE,fe))
           {
            raw.api_ok=false;
            raw.api_error="deal properties unreadable, error "+IntegerToString(GetLastError());
            break;
           }
         raw.deal[raw.n_deals].ticket=dt;
         raw.deal[raw.n_deals].position_id=(ulong)pid;
         raw.deal[raw.n_deals].time=tm;
         raw.deal[raw.n_deals].entry=(int)en;
         raw.deal[raw.n_deals].type=(int)ty;
         raw.deal[raw.n_deals].magic=mg;
         raw.deal[raw.n_deals].volume=vo;
         raw.deal[raw.n_deals].profit=pr;
         raw.deal[raw.n_deals].commission=co;
         raw.deal[raw.n_deals].swap=sw;
         raw.deal[raw.n_deals].fee=fe;
         raw.n_deals++;
        }
     }
   // the distinct trade positions of those deals
   ulong ids[DH_MAX_POS];
   int nids=0;
   for(int i=0;i<raw.n_deals && raw.api_ok;i++)
     {
      if(raw.deal[i].type!=DH_DEAL_BUY && raw.deal[i].type!=DH_DEAL_SELL) continue;
      bool known=false;
      for(int j=0;j<nids;j++)
         if(ids[j]==raw.deal[i].position_id) {known=true; break;}
      if(known) continue;
      if(nids>=DH_MAX_POS)
        {
         raw.pos_truncated=true;
         break;
        }
      ids[nids]=raw.deal[i].position_id;
      nids++;
     }
   for(int k=0;k<nids && raw.api_ok;k++)
     {
      raw.pos[raw.n_pos].position_id=ids[k];
      if(HistorySelectByPosition(ids[k]))
        {
         int nd=HistoryDealsTotal();
         for(int i=0;i<nd;i++)
           {
            ulong dt=HistoryDealGetTicket(i);
            if(dt==0)
              {
               raw.api_ok=false;
               raw.api_error="HistoryDealGetTicket (position) failed, error "+IntegerToString(GetLastError());
               break;
              }
            long en=0,mg=0,ty=0;
            double vo=0.0;
            if(!HistoryDealGetInteger(dt,DEAL_ENTRY,en) || !HistoryDealGetInteger(dt,DEAL_MAGIC,mg) || !HistoryDealGetInteger(dt,DEAL_TYPE,ty) ||
               !HistoryDealGetDouble(dt,DEAL_VOLUME,vo))
              {
               raw.api_ok=false;
               raw.api_error="deal properties (position) unreadable, error "+IntegerToString(GetLastError());
               break;
              }
            if(ty!=DH_DEAL_BUY && ty!=DH_DEAL_SELL) continue;
            if(en==DH_ENTRY_IN)
              {
               if(!raw.pos[raw.n_pos].opened_known)
                 {
                  raw.pos[raw.n_pos].opened_known=true;
                  raw.pos[raw.n_pos].opened_magic=mg;
                 }
               raw.pos[raw.n_pos].open_volume_total+=vo;
              }
            else
               raw.pos[raw.n_pos].closed_volume_total+=vo;
           }
        }
      else
         raw.hist_ok=false;
      raw.n_pos++;
     }
   // which of them are still open (matched by IDENTIFIER)
   int total=PositionsTotal();
   raw.positions_ok=true;
   for(int i=0;i<total;i++)
     {
      ulong t=PositionGetTicket(i);
      long id=0;
      if(t==0 || !PositionGetInteger(POSITION_IDENTIFIER,id))
        {
         raw.positions_ok=false;
         break;
        }
      for(int k=0;k<raw.n_pos;k++)
         if(raw.pos[k].position_id==(ulong)id)
            raw.pos[k].is_open=true;
     }
   if(PositionsTotal()!=total)
      raw.positions_ok=false;
  }

// two reads, compared; the first read is returned in raw_out for diagnostics
ENUM_DH_VERDICT DH_ReadAndBuild(const string symbol,const SDhCfg &cfg,SDhFacts &facts,string &reason,SDhRaw &raw_out)
  {
   SDhRaw second;
   DH_ReadRaw(symbol,cfg,raw_out);
   DH_ReadRaw(symbol,cfg,second);
   return(DH_Build(cfg,raw_out,DH_RawEqual(raw_out,second),facts,reason));
  }
#endif
