// T014 SETUP -> PLAN bridge (mirror of tests/spb_reference.py; read its header for the full contract): turns ONE existing T004 candidate into a T007 plan request and calls the existing plan builder
// (TP_BuildPlan). PURE: no terminal read, no clock (asof and live_after are arguments), no order, no permit, no execution record, no file. It does NOT detect H4 / M15 structure (the T004 observer
// state SM4State / SM4Candidate / SM4Level is the input), it does NOT copy the geometry or sizing formulas, and it chooses NOTHING: every selection is EXPLICIT and an unset one is a BLOCK with its name.
// Output: a plan (plan_ready) or ONE concrete blocking reason. A plan is NOT a trade permission: the permit checks and the entry executor are separate steps.
// WAIT_RETURN is the only phase that can yield a candidate for a PENDING order; RETURN_OBSERVED (a return already happened) never creates a delayed entry.
// Identities are deterministic from the observer's own identities: setup_id = "S|source|context.setup|context.fvg|broken level id", signal_id = setup_id + "|" + candidate id (the candidate id carries the
// time of its first candle and the direction). A restart or a replay of the same bars gives the SAME ids, so the entry executor's one-record-per-signal rule keeps blocking.
// OPEN CLIENT DECISIONS that stay explicit inputs (nothing here is a client rule): the swing selector, the FVG timing, the candidate selector, the entry edge (the client text says "the beginning of the
// FVG"; NEAR_SIDE = the edge the price meets first on the return, BUY upper / SELL lower, is an interpretation), the SL source (BROKEN_LEVEL_PRICE +/- an explicit buffer is a PROPOSAL: the exact extreme of
// the broken structure is not defined) and the target (NONE_2R_MINIMUM means only the client's 2R minimum; a supplied target needs a stated source).
#ifndef VELO_SETUP_PLAN_BRIDGE_MQH
#define VELO_SETUP_PLAN_BRIDGE_MQH

#include "TradePlanning.mqh"
#include "M15Confirmation.mqh"

#define SPB_SWING_UNSET 0
#define SPB_SWING_LATEST_FRACTAL_PROPOSAL 1
#define SPB_SWING_SUPPLIED 2
#define SPB_CAND_UNSET 0
#define SPB_CAND_EXPLICIT_ID 1
#define SPB_CAND_SOLE_ELIGIBLE 2
#define SPB_EDGE_UNSET 0
#define SPB_EDGE_NEAR_SIDE 1
#define SPB_EDGE_FAR_SIDE 2
#define SPB_SL_UNSET 0
#define SPB_SL_BROKEN_LEVEL_PRICE 1
#define SPB_SL_SUPPLIED 2
#define SPB_TGT_UNSET 0
#define SPB_TGT_NONE_2R_MINIMUM 1
#define SPB_TGT_SUPPLIED 2

struct SSpbSelection
  {
   string context_source;       // must equal the source of the observer context; blank = UNSET
   int swing_selector;          // SPB_SWING_*; recorded in the provenance (the swing is chosen by the caller of the observer)
   int timing_policy;           // must equal the observer policy and be M4_A_AT_OR_AFTER_BREAK
   int candidate_selector;      // SPB_CAND_*
   string candidate_id;         // SPB_CAND_EXPLICIT_ID only
   int entry_edge;              // SPB_EDGE_*
   int sl_rule;                 // SPB_SL_*
   bool sl_buffer_set;          // SPB_SL_BROKEN_LEVEL_PRICE: the buffer must be stated (0.0 is a statement)
   double sl_buffer;
   double sl_price;             // SPB_SL_SUPPLIED
   int target_rule;             // SPB_TGT_*
   double target_price;         // SPB_TGT_SUPPLIED
   string target_source;        // SPB_TGT_SUPPLIED: where the target comes from (non-blank)
   long live_after;             // a candidate confirmed at or before this instant is historical / replayed; 0 = UNSET
  };

void SPB_SelectionInit(SSpbSelection &s)
  {
   s.context_source="";
   s.swing_selector=SPB_SWING_UNSET;
   s.timing_policy=M4_POLICY_UNSET;
   s.candidate_selector=SPB_CAND_UNSET;
   s.candidate_id="";
   s.entry_edge=SPB_EDGE_UNSET;
   s.sl_rule=SPB_SL_UNSET;
   s.sl_buffer_set=false;
   s.sl_buffer=0.0;
   s.sl_price=0.0;
   s.target_rule=SPB_TGT_UNSET;
   s.target_price=0.0;
   s.target_source="";
   s.live_after=0;
  }

struct SSpbMarket
  {
   double risk_budget;
   double tick_value;
   double tick_size;
   int digits;
   double point;
   int stops_level;
   bool has_quote;
   double bid;
   double ask;
   double vol_min;
   double vol_step;
   double vol_max;
   double cap_lots;
  };

void SPB_MarketInit(SSpbMarket &m)
  {
   m.risk_budget=-1.0;
   m.tick_value=-1.0;
   m.tick_size=0.0;
   m.digits=-1;
   m.point=0.0;
   m.stops_level=-1;
   m.has_quote=false;
   m.bid=0.0;
   m.ask=0.0;
   m.vol_min=0.0;
   m.vol_step=0.0;
   m.vol_max=0.0;
   m.cap_lots=0.0;
  }

struct SSpbResult
  {
   bool plan_ready;
   string reason;
   string setup_id;
   string signal_id;
   string candidate_id;
   string provenance;
   STpPlan plan;
   double e_raw,s_raw,target_raw;
   bool has_target;
  };

void SPB_ResultInit(SSpbResult &r)
  {
   r.plan_ready=false;
   r.reason="";
   r.setup_id="";
   r.signal_id="";
   r.candidate_id="";
   r.provenance="";
   r.e_raw=0.0; r.s_raw=0.0; r.target_raw=0.0; r.has_target=false;
   TP_PlanReset(r.plan,"","",0);
  }

bool SPB_Fin(const double x) {return(x==x && x-x==0.0);}

bool SPB_Blank(const string s)
  {
   string t=s;
   StringTrimLeft(t);
   StringTrimRight(t);
   return(t=="");
  }

void SPB_Block(SSpbResult &r,const string reason)
  {
   SPB_ResultInit(r);
   r.reason=reason;
  }

// the names of the selections that are still UNSET (or unknown), "" when every one is stated
string SPB_Unset(const SSpbSelection &s,const datetime asof)
  {
   string bad="";
   if(SPB_Blank(s.context_source)) bad+=(bad=="" ? "" : ", ")+"context_source";
   if(s.swing_selector!=SPB_SWING_LATEST_FRACTAL_PROPOSAL && s.swing_selector!=SPB_SWING_SUPPLIED) bad+=(bad=="" ? "" : ", ")+"swing_selector";
   if(s.timing_policy!=M4_A_AT_OR_AFTER_BREAK) bad+=(bad=="" ? "" : ", ")+"timing_policy";
   if(s.candidate_selector!=SPB_CAND_EXPLICIT_ID && s.candidate_selector!=SPB_CAND_SOLE_ELIGIBLE) bad+=(bad=="" ? "" : ", ")+"candidate_selector";
   else
      if(s.candidate_selector==SPB_CAND_EXPLICIT_ID && SPB_Blank(s.candidate_id)) bad+=(bad=="" ? "" : ", ")+"candidate_id";
   if(s.entry_edge!=SPB_EDGE_NEAR_SIDE && s.entry_edge!=SPB_EDGE_FAR_SIDE) bad+=(bad=="" ? "" : ", ")+"entry_edge";
   if(s.sl_rule!=SPB_SL_BROKEN_LEVEL_PRICE && s.sl_rule!=SPB_SL_SUPPLIED) bad+=(bad=="" ? "" : ", ")+"sl_rule";
   else
      if(s.sl_rule==SPB_SL_BROKEN_LEVEL_PRICE && !(s.sl_buffer_set && SPB_Fin(s.sl_buffer) && s.sl_buffer>=0.0)) bad+=(bad=="" ? "" : ", ")+"sl_buffer";
      else
         if(s.sl_rule==SPB_SL_SUPPLIED && !(SPB_Fin(s.sl_price) && s.sl_price>0.0)) bad+=(bad=="" ? "" : ", ")+"sl_price";
   if(s.target_rule!=SPB_TGT_NONE_2R_MINIMUM && s.target_rule!=SPB_TGT_SUPPLIED) bad+=(bad=="" ? "" : ", ")+"target_rule";
   else
      if(s.target_rule==SPB_TGT_SUPPLIED && !(SPB_Fin(s.target_price) && s.target_price>0.0 && !SPB_Blank(s.target_source))) bad+=(bad=="" ? "" : ", ")+"target_price_and_source";
   if(!(s.live_after>0)) bad+=(bad=="" ? "" : ", ")+"live_after";
   if(!(asof>0)) bad+=(bad=="" ? "" : ", ")+"asof";
   return(bad);
  }

string SPB_SetupId(const SM4State &st,const SM4Level &broken)
  {
   return("S|"+st.context.source+"|"+st.context.setup+"|"+st.context.fvg+"|"+broken.id);
  }

bool SPB_Prepare(const SSpbSelection &sel,const SSpbMarket &mkt,const SM4State &st,const SM4Candidate &f[],const SM4Level &broken,const datetime asof,SSpbResult &out)
  {
   SPB_ResultInit(out);
   string bad=SPB_Unset(sel,asof);
   if(bad!="") {SPB_Block(out,"SELECTION_UNSET: "+bad); return(false);}
   if(!st.has_context || st.phase=="WAIT_CONTEXT" || !(st.context.ready && st.context.reliable && st.context.selected) || (st.context.direction!=1 && st.context.direction!=-1))
     {SPB_Block(out,"CONTEXT_LOST_OR_NOT_READY"); return(false);}
   if(st.context.source!=sel.context_source)
     {SPB_Block(out,"CONTEXT_SOURCE_MISMATCH: the observer runs on "+st.context.source+", the selection names "+sel.context_source); return(false);}
   if(st.policy!=sel.timing_policy) {SPB_Block(out,"TIMING_MISMATCH: the observer policy differs from the selected timing"); return(false);}
   if(st.phase=="REPLAY_REQUIRED") {SPB_Block(out,"REPLAY_REQUIRED: a revised history never becomes a signal"); return(false);}
   if(st.phase=="RETURN_OBSERVED") {SPB_Block(out,"RETURN_ALREADY_OBSERVED: the price already came back; no delayed entry"); return(false);}
   if(st.phase!="WAIT_RETURN") {SPB_Block(out,"PHASE_NOT_WAIT_RETURN: "+st.phase); return(false);}
   if(st.last_asof>asof || st.context.valid_from>asof || st.bos_known>asof) {SPB_Block(out,"FUTURE_DATA: the observer holds data newer than asof"); return(false);}
   if(!broken.valid || SPB_Blank(broken.id) || broken.id!=st.bos_level || !(SPB_Fin(broken.price) && broken.price>0.0) || !(broken.known>0 && broken.known<=st.bos_time))
     {SPB_Block(out,"BROKEN_LEVEL_MISMATCH: the supplied level is not the one the observer recorded"); return(false);}
   if(broken.known>asof) {SPB_Block(out,"FUTURE_DATA: the broken level is newer than asof"); return(false);}
   int n=ArraySize(f);
   for(int i=0;i<n;i++)
     {
      if(SPB_Blank(f[i].id)) {SPB_Block(out,"CANDIDATE_IDS_NOT_UNIQUE"); return(false);}
      for(int j=i+1;j<n;j++)
         if(f[j].id==f[i].id) {SPB_Block(out,"CANDIDATE_IDS_NOT_UNIQUE"); return(false);}
     }
   int pick=-1;
   if(sel.candidate_selector==SPB_CAND_EXPLICIT_ID)
     {
      for(int i=0;i<n;i++)
         if(f[i].id==sel.candidate_id) pick=i;
      if(pick<0) {SPB_Block(out,"CANDIDATE_NOT_FOUND: "+sel.candidate_id); return(false);}
      if(f[pick].invalid) {SPB_Block(out,"CANDIDATE_INVALIDATED: "+f[pick].id); return(false);}
      if(f[pick].returned) {SPB_Block(out,"CANDIDATE_RETURN_ALREADY_OBSERVED: "+f[pick].id); return(false);}
     }
   else
     {
      int ne=0;
      string ids="";
      for(int i=0;i<n;i++)
         if(!f[i].invalid && !f[i].returned)
           {
            ne++;
            pick=i;
            ids+=(ids=="" ? "" : ",")+f[i].id;
           }
      if(ne==0) {SPB_Block(out,"NO_ELIGIBLE_CANDIDATE"); return(false);}
      if(ne>1) {SPB_Block(out,"AMBIGUOUS_CANDIDATES: "+ids+"; none is chosen"); return(false);}
     }
   int d=st.context.direction;
   if(!(SPB_Fin(f[pick].lower) && SPB_Fin(f[pick].upper) && f[pick].lower>0.0 && f[pick].lower<f[pick].upper)) {SPB_Block(out,"CANDIDATE_BOUNDS_INVALID: "+f[pick].id); return(false);}
   string last=StringSubstr(f[pick].id,StringLen(f[pick].id)-1,1);
   if(last!=(d==1 ? "U" : "D")) {SPB_Block(out,"CANDIDATE_DIRECTION_INCONSISTENT: "+f[pick].id); return(false);}
   if(f[pick].confirmed>asof) {SPB_Block(out,"FUTURE_DATA: the candidate is newer than asof"); return(false);}
   if((long)f[pick].confirmed<=sel.live_after) {SPB_Block(out,"HISTORICAL_OR_REPLAYED_CANDIDATE: formed at or before the live baseline"); return(false);}
   double e;
   if(sel.entry_edge==SPB_EDGE_NEAR_SIDE) e=(d==1 ? f[pick].upper : f[pick].lower);
   else e=(d==1 ? f[pick].lower : f[pick].upper);
   double s;
   if(sel.sl_rule==SPB_SL_BROKEN_LEVEL_PRICE) s=(d==1 ? broken.price-sel.sl_buffer : broken.price+sel.sl_buffer);
   else s=sel.sl_price;
   bool has_target=(sel.target_rule==SPB_TGT_SUPPLIED);
   double t=(has_target ? sel.target_price : 0.0);
   string setup=SPB_SetupId(st,broken);
   string signal=setup+"|"+f[pick].id;
   string prov="source="+sel.context_source+" swing="+(sel.swing_selector==SPB_SWING_SUPPLIED ? "SUPPLIED" : "LATEST_FRACTAL_PROPOSAL")+" timing=A_AT_OR_AFTER_BREAK candidate="+
               (sel.candidate_selector==SPB_CAND_EXPLICIT_ID ? "EXPLICIT_ID" : "SOLE_ELIGIBLE")+":"+f[pick].id+" edge="+(sel.entry_edge==SPB_EDGE_NEAR_SIDE ? "NEAR_SIDE" : "FAR_SIDE")+
               " sl="+(sel.sl_rule==SPB_SL_SUPPLIED ? "SUPPLIED" : "BROKEN_LEVEL_PRICE")+" target="+(has_target ? "SUPPLIED:"+sel.target_source : "NONE_2R_MINIMUM");
   out.setup_id=setup;
   out.signal_id=signal;
   out.candidate_id=f[pick].id;
   out.provenance=prov;
   out.e_raw=e; out.s_raw=s; out.has_target=has_target; out.target_raw=t;
   return(true);
  }

// Candidate/geometry only: never sizes a provisional plan using a reported tick value.
bool SPB_Geometry(const SSpbSelection &sel,const SSpbMarket &mkt,const SM4State &st,const SM4Candidate &f[],const SM4Level &broken,const datetime asof,SSpbResult &out,STgResult &geo)
  {
   if(!SPB_Prepare(sel,mkt,st,f,broken,asof,out)) return(false);
   if(!TG_Compute(st.context.direction,out.e_raw,out.s_raw,out.has_target,out.target_raw,mkt.tick_size,mkt.digits,mkt.point,mkt.stops_level,mkt.has_quote,mkt.bid,mkt.ask,geo))
     {
      out.reason="GEOMETRY_REFUSED: "+geo.reason;
      return(false);
     }
   return(true);
  }

void SPB_Build(const SSpbSelection &sel,const SSpbMarket &mkt,const SM4State &st,const SM4Candidate &f[],const SM4Level &broken,const datetime asof,SSpbResult &out)
  {
   if(!SPB_Prepare(sel,mkt,st,f,broken,asof,out)) return;
   if(!TP_BuildPlan(out.signal_id,out.setup_id,st.context.direction,out.e_raw,out.s_raw,out.has_target,out.target_raw,mkt.risk_budget,mkt.tick_value,mkt.tick_size,mkt.digits,mkt.point,mkt.stops_level,mkt.has_quote,mkt.bid,mkt.ask,
                    mkt.vol_min,mkt.vol_step,mkt.vol_max,mkt.cap_lots,out.plan))
     {
      out.reason="PLAN_REFUSED: "+out.plan.reason;
      return;
     }
   out.plan_ready=true;
  }
#endif
