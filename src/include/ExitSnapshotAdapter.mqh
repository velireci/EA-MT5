// T011 READ-ONLY snapshot adapter: feeds ExitReconciliation (SErSnapshot) from what the MT5 terminal shows about positions, orders and deals.
// Mirrors tests/t011_adapter_reference.py (its header documents the identity chain and the six completeness proofs in full).
// Two layers: (1) XA_Build, a PURE core over already-read raw data (fully tested with fixtures); (2) the thin MT5 reader XA_ReadRaw /
// XA_ReadAndBuild, the ONLY place that calls terminal APIs, all of them reads (UNVERIFIED: not compiled against the live terminal here,
// the API semantics are from memory of the MQL5 documentation, which could not be opened from the build environment).
// NOTHING here sends, modifies, cancels or closes anything, and the adapter NEVER writes SEaState (it only reads request_id, position_id,
// direction and status): the caller applies ER_Reconcile on a READY snapshot; UNKNOWN / BLOCK are verdicts the caller must honour.
//
// IDENTITY CHAIN (what is provable): request_id (ours) exists in no MT5 field and is NOT matched to a comment or to magic/volume.
//   request_id --(map supplied by the executor, SXaMap)--> order tickets --DEAL_ORDER--> exit deals --DEAL_POSITION_ID--> position identifier.
// The executor that records the order tickets at send time is NOT built: without its map (or with a map without order tickets) the
// verdict is UNKNOWN. The position is found by POSITION_IDENTIFIER, never by assuming ticket == identifier.
// executions_complete is set only when all six proofs hold (see the reference header); account modes other than HEDGING block.
#ifndef VELO_EXIT_SNAPSHOT_ADAPTER_MQH
#define VELO_EXIT_SNAPSHOT_ADAPTER_MQH

#include "ExitReconciliation.mqh"

#define XA_MAX_DEALS 64
#define XA_MAX_ORDERS 8
// mirrors of terminal enum values; the MQL5 test checks them against the real constants
#define XA_ENTRY_IN 0
#define XA_ENTRY_OUT 1
#define XA_ENTRY_INOUT 2
#define XA_ENTRY_OUT_BY 3
#define XA_DEAL_BUY 0
#define XA_DEAL_SELL 1
#define XA_POS_BUY 0
#define XA_POS_SELL 1
#define XA_ORD_PLACED 1
#define XA_ORD_CANCELED 2
#define XA_ORD_PARTIAL 3
#define XA_ORD_FILLED 4
#define XA_ORD_REJECTED 5
#define XA_ORD_EXPIRED 6
#define XA_MARGIN_NETTING 0
#define XA_MARGIN_EXCHANGE 1
#define XA_MARGIN_HEDGING 2
#define XA_WHERE_NONE 0
#define XA_WHERE_ACTIVE 1
#define XA_WHERE_HISTORY 2

enum ENUM_XA_VERDICT
  {
   XA_READY=0,
   XA_UNKNOWN,
   XA_BLOCK
  };

struct SXaMap
  {
   string request_id;
   ulong position_id;
   string symbol;
   int n_orders;
   ulong order[XA_MAX_ORDERS];
   bool orders_complete;
  };

struct SXaRawDeal
  {
   ulong ticket;
   ulong order;
   ulong position_id;
   int entry;
   int type;
   double volume;
  };

struct SXaRawOrder
  {
   ulong ticket;
   int where;
   int state;
   double vol_initial;
   double vol_current;
   ulong position_id;
  };

struct SXaRaw
  {
   bool api_ok;
   string api_error;
   bool symbol_ok;
   double vol_step;
   double vol_min;
   double vol_max;
   bool margin_ok;
   int margin_mode;
   int n_pos;
   ulong pos_ticket;
   int pos_type;
   double pos_volume;
   string pos_symbol;
   bool hist_ok;
   bool deals_truncated;
   int n_deals;
   SXaRawDeal deal[XA_MAX_DEALS];
   int n_orders;
   SXaRawOrder ord[XA_MAX_ORDERS];
  };

struct SXaResult
  {
   ENUM_XA_VERDICT verdict;
   string reason;
   bool complete;
   string proof;
   int linked_deals;
   int duplicate_deals;
   int excluded_entries;
   int excluded_other;
  };

string XA_VerdictName(const ENUM_XA_VERDICT v)
  {
   switch(v)
     {
      case XA_READY: return("READY");
      case XA_UNKNOWN: return("UNKNOWN");
      case XA_BLOCK: return("BLOCK");
     }
   return("?");
  }

void XA_MapInit(SXaMap &m,const string request_id,const ulong position_id,const string symbol,const bool orders_complete)
  {
   m.request_id=request_id;
   m.position_id=position_id;
   m.symbol=symbol;
   m.n_orders=0;
   m.orders_complete=orders_complete;
   for(int i=0;i<XA_MAX_ORDERS;i++)
      m.order[i]=0;
  }

bool XA_MapAdd(SXaMap &m,const ulong order_ticket)
  {
   if(m.n_orders>=XA_MAX_ORDERS)
      return(false);
   m.order[m.n_orders]=order_ticket;
   m.n_orders++;
   return(true);
  }

void XA_RawInit(SXaRaw &r)
  {
   r.api_ok=true;
   r.api_error="";
   r.symbol_ok=false;
   r.vol_step=0.0;
   r.vol_min=0.0;
   r.vol_max=0.0;
   r.margin_ok=false;
   r.margin_mode=-1;
   r.n_pos=0;
   r.pos_ticket=0;
   r.pos_type=-1;
   r.pos_volume=0.0;
   r.pos_symbol="";
   r.hist_ok=false;
   r.deals_truncated=false;
   r.n_deals=0;
   for(int i=0;i<XA_MAX_DEALS;i++)
     {
      r.deal[i].ticket=0;
      r.deal[i].order=0;
      r.deal[i].position_id=0;
      r.deal[i].entry=-1;
      r.deal[i].type=-1;
      r.deal[i].volume=0.0;
     }
   r.n_orders=0;
   for(int k=0;k<XA_MAX_ORDERS;k++)
     {
      r.ord[k].ticket=0;
      r.ord[k].where=XA_WHERE_NONE;
      r.ord[k].state=0;
      r.ord[k].vol_initial=0.0;
      r.ord[k].vol_current=0.0;
      r.ord[k].position_id=0;
     }
  }

// two reads are the same read (stability)
bool XA_RawEqual(const SXaRaw &a,const SXaRaw &b)
  {
   if(a.api_ok!=b.api_ok || a.api_error!=b.api_error || a.symbol_ok!=b.symbol_ok || a.vol_step!=b.vol_step || a.vol_min!=b.vol_min ||
      a.vol_max!=b.vol_max || a.margin_ok!=b.margin_ok || a.margin_mode!=b.margin_mode || a.n_pos!=b.n_pos || a.pos_ticket!=b.pos_ticket ||
      a.pos_type!=b.pos_type || a.pos_volume!=b.pos_volume || a.pos_symbol!=b.pos_symbol || a.hist_ok!=b.hist_ok ||
      a.deals_truncated!=b.deals_truncated || a.n_deals!=b.n_deals || a.n_orders!=b.n_orders)
      return(false);
   for(int i=0;i<a.n_deals && i<XA_MAX_DEALS;i++)
      if(a.deal[i].ticket!=b.deal[i].ticket || a.deal[i].order!=b.deal[i].order || a.deal[i].position_id!=b.deal[i].position_id ||
         a.deal[i].entry!=b.deal[i].entry || a.deal[i].type!=b.deal[i].type || a.deal[i].volume!=b.deal[i].volume)
         return(false);
   for(int k=0;k<a.n_orders && k<XA_MAX_ORDERS;k++)
      if(a.ord[k].ticket!=b.ord[k].ticket || a.ord[k].where!=b.ord[k].where || a.ord[k].state!=b.ord[k].state ||
         a.ord[k].vol_initial!=b.ord[k].vol_initial || a.ord[k].vol_current!=b.ord[k].vol_current || a.ord[k].position_id!=b.ord[k].position_id)
         return(false);
   return(true);
  }

void XA_Fail(SXaResult &r,const ENUM_XA_VERDICT v,const string reason)
  {
   r.verdict=v;
   r.reason=reason;
   r.complete=false;
   r.proof="";
   r.linked_deals=0;
   r.duplicate_deals=0;
   r.excluded_entries=0;
   r.excluded_other=0;
  }

bool XA_InMap(const SXaMap &m,const ulong order_ticket)
  {
   for(int i=0;i<m.n_orders;i++)
      if(m.order[i]==order_ticket)
         return(true);
   return(false);
  }

bool XA_SameDeal(const SXaRawDeal &a,const SXaRawDeal &b)
  {
   return(a.ticket==b.ticket && a.order==b.order && a.position_id==b.position_id && a.entry==b.entry && a.type==b.type && a.volume==b.volume);
  }

// The margin mode read: ok only when the terminal reported no error for THIS read; the value (0 = netting included) is never a failure signal.
void XA_ModeRead(const long value,const int error_code,int &mode,bool &ok)
  {
   ok=(error_code==0);
   mode=(ok ? (int)value : -1);
  }

bool XA_FinalOrderState(const int s)
  {
   return(s==XA_ORD_CANCELED || s==XA_ORD_FILLED || s==XA_ORD_REJECTED || s==XA_ORD_EXPIRED);
  }

// Builds the snapshot for ER_Reconcile. Returns true when the verdict is READY. The state is only READ.
bool XA_Build(const SEaState &st,const SXaMap &mp,const SXaRaw &raw,const bool stable,SErSnapshot &snap,SXaResult &res)
  {
   XA_Fail(res,XA_UNKNOWN,"");
   if(st.status==EA_ST_BLOCKED)
     {
      XA_Fail(res,XA_BLOCK,"ALREADY_BLOCKED: "+st.reason);
      return(false);
     }
   if(!st.bound || st.request_id=="" || st.status==EA_ST_IDLE)
     {
      XA_Fail(res,XA_UNKNOWN,"NO_REQUEST: there is no request to reconcile");
      return(false);
     }
   if(mp.request_id=="")
     {
      XA_Fail(res,XA_UNKNOWN,"NO_MAP: the executor identity map is missing");
      return(false);
     }
   if(mp.request_id!=st.request_id)
     {
      XA_Fail(res,XA_BLOCK,"MAP_REQUEST_MISMATCH: the map names "+mp.request_id+", the state has "+st.request_id);
      return(false);
     }
   if(mp.position_id!=st.position_id)
     {
      XA_Fail(res,XA_BLOCK,StringFormat("MAP_POSITION_MISMATCH: the map names position %I64u, the state has %I64u",mp.position_id,st.position_id));
      return(false);
     }
   if(mp.n_orders<=0)
     {
      XA_Fail(res,XA_UNKNOWN,"NO_ORDER_TICKETS: the map names no order ticket, so no deal can be linked to the request");
      return(false);
     }
   bool map_ok=(mp.n_orders<=XA_MAX_ORDERS);
   for(int i=0;map_ok && i<mp.n_orders;i++)
     {
      if(mp.order[i]==0)
         map_ok=false;
      for(int j=0;map_ok && j<i;j++)
         if(mp.order[j]==mp.order[i])
            map_ok=false;
     }
   if(!map_ok)
     {
      XA_Fail(res,XA_UNKNOWN,StringFormat("MAP_INVALID: order tickets must be distinct positive integers, at most %d",XA_MAX_ORDERS));
      return(false);
     }
   if(!raw.api_ok)
     {
      XA_Fail(res,XA_UNKNOWN,"API_ERROR: "+raw.api_error);
      return(false);
     }
   if(!raw.symbol_ok || !TG_Finite(raw.vol_step) || raw.vol_step<=0.0 || !TG_Finite(raw.vol_min) || raw.vol_min<=0.0 || !TG_Finite(raw.vol_max) || raw.vol_max<=0.0)
     {
      XA_Fail(res,XA_UNKNOWN,"SYMBOL_PARAMETERS_UNAVAILABLE: the real volume step, minimum and maximum could not be read");
      return(false);
     }
   if(!raw.margin_ok)
     {
      XA_Fail(res,XA_UNKNOWN,"ACCOUNT_MODE_UNAVAILABLE");
      return(false);
     }
   if(raw.margin_mode!=XA_MARGIN_HEDGING)
     {
      XA_Fail(res,XA_BLOCK,StringFormat("UNSUPPORTED_ACCOUNT_MODE: margin mode %d; only HEDGING separates our position from other trades",raw.margin_mode));
      return(false);
     }
   if(!raw.hist_ok)
     {
      XA_Fail(res,XA_UNKNOWN,"HISTORY_UNAVAILABLE: the history of the position could not be selected");
      return(false);
     }
   if(raw.deals_truncated || raw.n_deals>XA_MAX_DEALS || raw.n_orders>XA_MAX_ORDERS)
     {
      XA_Fail(res,XA_UNKNOWN,StringFormat("CAPACITY: more than %d deals or %d orders; the list is not truncated silently",XA_MAX_DEALS,XA_MAX_ORDERS));
      return(false);
     }
   if(!stable)
     {
      XA_Fail(res,XA_UNKNOWN,"READ_UNSTABLE: two consecutive reads differ (position, deals or orders changed while reading)");
      return(false);
     }
   if(raw.n_pos>1)
     {
      XA_Fail(res,XA_BLOCK,StringFormat("AMBIGUOUS_POSITION: %d open positions share the identifier %I64u",raw.n_pos,mp.position_id));
      return(false);
     }
   bool found=(raw.n_pos==1);
   if(found)
     {
      if(raw.pos_symbol!=mp.symbol)
        {
         XA_Fail(res,XA_BLOCK,"SYMBOL_MISMATCH: position symbol "+raw.pos_symbol+" is not "+mp.symbol);
         return(false);
        }
      int want=(st.direction==1 ? XA_POS_BUY : XA_POS_SELL);
      if(raw.pos_type!=want)
        {
         XA_Fail(res,XA_BLOCK,StringFormat("DIRECTION_MISMATCH: position type %d does not match the state direction %d",raw.pos_type,st.direction));
         return(false);
        }
      if(!TG_Finite(raw.pos_volume) || raw.pos_volume<=0.0)
        {
         XA_Fail(res,XA_UNKNOWN,"POSITION_VOLUME_INVALID");
         return(false);
        }
     }
   // ---- deals: de-duplicated by ticket, only exit deals of a mapped order count
   int lk[XA_MAX_DEALS];                       // indexes of the linked deals
   int nl=0,dup=0,ex_entry=0,ex_other=0;
   bool has_entry_in=false;
   int wrong=(st.direction==1 ? XA_DEAL_SELL : XA_DEAL_BUY);
   for(int i=0;i<raw.n_deals;i++)
     {
      if(raw.deal[i].position_id!=mp.position_id)
        {
         XA_Fail(res,XA_UNKNOWN,StringFormat("READ_INCONSISTENT: deal %I64u belongs to position %I64u, not %I64u",raw.deal[i].ticket,raw.deal[i].position_id,mp.position_id));
         return(false);
        }
      int same=-1;
      for(int j=0;j<i;j++)
         if(raw.deal[j].ticket==raw.deal[i].ticket)
           {
            same=j;
            break;
           }
      if(same>=0)
        {
         if(XA_SameDeal(raw.deal[same],raw.deal[i]))
           {
            dup++;
            continue;
           }
         XA_Fail(res,XA_UNKNOWN,StringFormat("READ_INCONSISTENT: deal ticket %I64u appears twice with different content",raw.deal[i].ticket));
         return(false);
        }
      if(raw.deal[i].entry==XA_ENTRY_IN)
        {
         has_entry_in=true;
         ex_entry++;
         continue;
        }
      if(raw.deal[i].entry!=XA_ENTRY_OUT)
        {
         ex_entry++;
         continue;
        }
      if((raw.deal[i].type!=XA_DEAL_BUY && raw.deal[i].type!=XA_DEAL_SELL) || raw.deal[i].type!=wrong)
        {
         XA_Fail(res,XA_BLOCK,StringFormat("DEAL_DIRECTION_MISMATCH: exit deal %I64u has type %d against a position with direction %d",raw.deal[i].ticket,raw.deal[i].type,st.direction));
         return(false);
        }
      if(!XA_InMap(mp,raw.deal[i].order))
        {
         ex_other++;
         continue;
        }
      if(!TG_Finite(raw.deal[i].volume) || raw.deal[i].volume<=0.0)
        {
         XA_Fail(res,XA_UNKNOWN,StringFormat("READ_INCONSISTENT: deal %I64u has an invalid volume",raw.deal[i].ticket));
         return(false);
        }
      lk[nl]=i;
      nl++;
     }
   if(nl>ER_MAX_EXEC)
     {
      XA_Fail(res,XA_UNKNOWN,StringFormat("CAPACITY: %d linked executions exceed the %d of a snapshot; not truncated",nl,ER_MAX_EXEC));
      return(false);
     }
   // ---- completeness: everything must be proven
   string missing="";
   if(!mp.orders_complete)
      missing+=(missing!="" ? "; " : "")+"the executor does not assert that the order ticket list is complete";
   for(int m=0;m<mp.n_orders;m++)
     {
      ulong t=mp.order[m];
      int oi=-1;
      for(int q=0;q<raw.n_orders;q++)
         if(raw.ord[q].ticket==t)
           {
            oi=q;
            break;
           }
      if(oi<0 || raw.ord[oi].where==XA_WHERE_NONE)
        {
         missing+=(missing!="" ? "; " : "")+StringFormat("order %I64u not found",t);
         continue;
        }
      if(raw.ord[oi].where!=XA_WHERE_HISTORY || !XA_FinalOrderState(raw.ord[oi].state))
        {
         missing+=(missing!="" ? "; " : "")+StringFormat("order %I64u is not final in the history",t);
         continue;
        }
      double executed=raw.ord[oi].vol_initial-raw.ord[oi].vol_current;
      long e_steps=(MathAbs(executed)<raw.vol_step/2.0 ? 0 : PS_GridSteps(executed,raw.vol_step));
      long d_steps=0;
      for(int a=0;a<nl;a++)
         if(raw.deal[lk[a]].order==t)
           {
            long k=PS_GridSteps(raw.deal[lk[a]].volume,raw.vol_step);
            d_steps+=(k>0 ? k : 0);
           }
      if(e_steps<0 || e_steps!=d_steps)
         missing+=(missing!="" ? "; " : "")+StringFormat("order %I64u executed volume does not match its deals",t);
      if(e_steps!=0 && raw.ord[oi].position_id!=mp.position_id)
        {
         XA_Fail(res,XA_BLOCK,StringFormat("ORDER_POSITION_MISMATCH: order %I64u executed on position %I64u, not %I64u",t,raw.ord[oi].position_id,mp.position_id));
         return(false);
        }
     }
   if(!has_entry_in)
      missing+=(missing!="" ? "; " : "")+"the opening deal of the position is not in the history list";
   bool complete=(missing=="");
   ER_SnapshotInit(snap,found,mp.position_id,st.request_id,raw.vol_step,(found ? raw.pos_volume : 0.0),complete);
   for(int a=0;a<nl;a++)
      ER_AddExec(snap,StringFormat("%I64u",raw.deal[lk[a]].ticket),st.request_id,raw.deal[lk[a]].volume);
   res.verdict=XA_READY;
   res.reason="";
   res.complete=complete;
   res.proof=(complete ? "complete: all six proofs hold" : missing);
   res.linked_deals=nl;
   res.duplicate_deals=dup;
   res.excluded_entries=ex_entry;
   res.excluded_other=ex_other;
   return(true);
  }

// ======================= THE ONLY TERMINAL READS (UNVERIFIED against the live terminal) =======================
// Reads positions by IDENTIFIER, the deals of that position (HistorySelectByPosition), the mapped orders (active, then history), the real
// volume parameters and the account margin mode. Every failure is recorded in raw.api_ok / api_error; nothing is truncated silently.
void XA_ReadRaw(const SXaMap &mp,SXaRaw &raw)
  {
   XA_RawInit(raw);
   ResetLastError();
   double v=0.0;
   raw.symbol_ok=SymbolInfoDouble(mp.symbol,SYMBOL_VOLUME_STEP,v);
   raw.vol_step=v;
   raw.symbol_ok=raw.symbol_ok && SymbolInfoDouble(mp.symbol,SYMBOL_VOLUME_MIN,v);
   raw.vol_min=v;
   raw.symbol_ok=raw.symbol_ok && SymbolInfoDouble(mp.symbol,SYMBOL_VOLUME_MAX,v);
   raw.vol_max=v;
   // AccountInfoInteger(ACCOUNT_MARGIN_MODE) RETURNS the value (there is no by-reference overload). The error state is isolated for this
   // read alone, and the value is judged separately in XA_Build: 0 is a VALID value (retail netting), which the adapter blocks as unsupported.
   ResetLastError();
   long mm=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   XA_ModeRead(mm,GetLastError(),raw.margin_mode,raw.margin_ok);
   // open positions, matched by IDENTIFIER (the ticket may differ)
   int total=PositionsTotal();
   for(int i=0;i<total;i++)
     {
      ulong t=PositionGetTicket(i);
      if(t==0)
        {
         raw.api_ok=false;
         raw.api_error="PositionGetTicket failed, error "+IntegerToString(GetLastError());
         break;
        }
      long id=0;
      if(!PositionGetInteger(POSITION_IDENTIFIER,id))
        {
         raw.api_ok=false;
         raw.api_error="POSITION_IDENTIFIER unreadable, error "+IntegerToString(GetLastError());
         break;
        }
      if((ulong)id!=mp.position_id)
         continue;
      raw.n_pos++;
      long ty=0;
      double pv=0.0;
      string ps="";
      if(!PositionGetInteger(POSITION_TYPE,ty) || !PositionGetDouble(POSITION_VOLUME,pv) || !PositionGetString(POSITION_SYMBOL,ps))
        {
         raw.api_ok=false;
         raw.api_error="position properties unreadable, error "+IntegerToString(GetLastError());
         break;
        }
      raw.pos_ticket=t;
      raw.pos_type=(int)ty;
      raw.pos_volume=pv;
      raw.pos_symbol=ps;
     }
   if(PositionsTotal()!=total)
     {
      raw.api_ok=false;
      raw.api_error="the number of open positions changed while reading";
     }
   // the history of this position: orders and deals
   raw.hist_ok=HistorySelectByPosition(mp.position_id);
   if(raw.hist_ok)
     {
      int nd=HistoryDealsTotal();
      if(nd>XA_MAX_DEALS)
        {
         raw.deals_truncated=true;
         nd=XA_MAX_DEALS;
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
         long o=0,p=0,e=0,ty=0;
         double vol=0.0;
         if(!HistoryDealGetInteger(dt,DEAL_ORDER,o) || !HistoryDealGetInteger(dt,DEAL_POSITION_ID,p) || !HistoryDealGetInteger(dt,DEAL_ENTRY,e) ||
            !HistoryDealGetInteger(dt,DEAL_TYPE,ty) || !HistoryDealGetDouble(dt,DEAL_VOLUME,vol))
           {
            raw.api_ok=false;
            raw.api_error="deal properties unreadable, error "+IntegerToString(GetLastError());
            break;
           }
         raw.deal[raw.n_deals].ticket=dt;
         raw.deal[raw.n_deals].order=(ulong)o;
         raw.deal[raw.n_deals].position_id=(ulong)p;
         raw.deal[raw.n_deals].entry=(int)e;
         raw.deal[raw.n_deals].type=(int)ty;
         raw.deal[raw.n_deals].volume=vol;
         raw.n_deals++;
        }
     }
   // the mapped orders: active first, then the history
   for(int k=0;k<mp.n_orders && k<XA_MAX_ORDERS;k++)
     {
      ulong ot=mp.order[k];
      raw.ord[k].ticket=ot;
      raw.n_orders++;
      long st=0,pid=0;
      double vi=0.0,vc=0.0;
      if(OrderSelect(ot))
        {
         raw.ord[k].where=XA_WHERE_ACTIVE;
         if(OrderGetInteger(ORDER_STATE,st))
            raw.ord[k].state=(int)st;
         continue;
        }
      if(HistoryOrderSelect(ot))
        {
         if(!HistoryOrderGetInteger(ot,ORDER_STATE,st) || !HistoryOrderGetDouble(ot,ORDER_VOLUME_INITIAL,vi) ||
            !HistoryOrderGetDouble(ot,ORDER_VOLUME_CURRENT,vc) || !HistoryOrderGetInteger(ot,ORDER_POSITION_ID,pid))
           {
            raw.api_ok=false;
            raw.api_error="history order properties unreadable, error "+IntegerToString(GetLastError());
            break;
           }
         raw.ord[k].where=XA_WHERE_HISTORY;
         raw.ord[k].state=(int)st;
         raw.ord[k].vol_initial=vi;
         raw.ord[k].vol_current=vc;
         raw.ord[k].position_id=(ulong)pid;
        }
     }
  }

// two reads, compared: a difference is UNKNOWN (READ_UNSTABLE), never a guess. `raw_out` is the first read (for diagnostics).
bool XA_ReadAndBuild(const SEaState &st,const SXaMap &mp,SErSnapshot &snap,SXaResult &res,SXaRaw &raw_out)
  {
   SXaRaw second;
   XA_ReadRaw(mp,raw_out);
   XA_ReadRaw(mp,second);
   return(XA_Build(st,mp,raw_out,XA_RawEqual(raw_out,second),snap,res));
  }
#endif
