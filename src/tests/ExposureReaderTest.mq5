// T018 exposure-reader test (scripted FAKE port only, no terminal read): mirrors tests/test_exposure.py (the scenario names are pinned equal by a Python test).
// NOT YET COMPILED OR RUN (UNVERIFIED): Codex compiles it, the owner runs it in MT5.
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/ExposureReader.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
#define MAGIC 777

void Item(SExItem &i,const ulong ticket,const long magic,const int kind,const double vol,const double price,const double sl)
  {
   i.ticket=ticket;
   i.symbol="XAUUSD";
   i.magic=magic;
   i.kind=kind;
   i.volume=vol;
   i.price=price;
   i.sl=sl;
  }

class CFakePort : public CExPort
  {
public:
   bool account_ok;
   int margin_mode;
   SExItem pos[EX_MAX+2];
   int n_pos;
   bool pos_complete;
   SExItem ord[EX_MAX+2];
   int n_ord;
   bool ord_complete;
   ulong calc_fail_ticket;
   int calls;
   int order_reads;
   CFakePort(void)
     {
      account_ok=true;
      margin_mode=EX_HEDGING;
      n_pos=0;
      n_ord=0;
      pos_complete=true;
      ord_complete=true;
      calc_fail_ticket=0;
      calls=0;
      order_reads=0;
     }
   void AddPos(const ulong t,const long magic=MAGIC,const int kind=0,const double vol=0.1,const double price=100.0,const double sl=99.0)
     {
      if(n_pos<EX_MAX+2) {Item(pos[n_pos],t,magic,kind,vol,price,sl); n_pos++;}
     }
   void AddOrd(const ulong t,const long magic=MAGIC,const int kind=0,const double vol=0.1,const double price=100.0,const double sl=99.0)
     {
      if(n_ord<EX_MAX+2) {Item(ord[n_ord],t,magic,kind,vol,price,sl); n_ord++;}
     }
   virtual void Account(bool &ok,int &mode) {ok=account_ok; mode=margin_mode;}
   virtual void Positions(SExItem &p[],int &n,bool &complete)
     {
      ArrayResize(p,n_pos);
      for(int i=0;i<n_pos;i++) p[i]=pos[i];
      n=n_pos;
      complete=pos_complete;
     }
   virtual void Orders(SExItem &o[],int &n,bool &complete)
     {
      order_reads++;
      ArrayResize(o,n_ord);
      for(int i=0;i<n_ord;i++) o[i]=ord[i];
      n=n_ord;
      complete=ord_complete;
     }
   virtual bool Calc(const bool buy,const string symbol,const double volume,const double open,const double sl,double &profit)
     {
      calls++;
      profit=0.0;
      if(volume<=0.0) return(false);
      profit=volume*(buy ? (sl-open) : (open-sl))*100.0;     // scripted broker: profit at the stop
      return(true);
     }
  };

class CFailPort : public CFakePort
  {
public:
   virtual bool Calc(const bool buy,const string symbol,const double volume,const double open,const double sl,double &profit)
     {
      calls++;
      profit=0.0;
      if(MathAbs(sl-98.0)<0.000001) return(false);            // the item marked with sl 98 has no broker calculation
      profit=volume*(buy ? (sl-open) : (open-sl))*100.0;
      return(true);
     }
  };

bool Near(const double a,const double b) {return(MathAbs(a-b)<0.000001);}

void Scenario_inputs_unset_block(void)
  {
   for(int k=0;k<5;k++)
     {
      CFakePort p;
      p.AddPos(1);
      SExResult r;
      long magic=(k==0 ? 0 : k==1 ? -1 : MAGIC);
      string symbol=(k==2 ? "" : "XAUUSD");
      int policy=(k==3 ? EX_PEND_UNSET : k==4 ? 9 : EX_PEND_COUNT);
      EX_Compute(magic,symbol,policy,GetPointer(p),r);
      Check(!r.ok && r.reason=="INPUT_UNSET" && EX_GatePositions(r)==-1 && EX_GateRisk(r)==-1.0 && p.calls==0,StringFormat("unset input case %d blocks, no calculation",k));
     }
  }

void Scenario_account_not_separable(void)
  {
   int modes[3]={0,1,7};
   for(int k=0;k<3;k++)
     {
      CFakePort p;
      p.AddPos(1);
      p.margin_mode=modes[k];
      SExResult r;
      EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(p),r);
      Check(!r.ok && r.reason=="OWNERSHIP_NOT_SEPARABLE" && EX_GatePositions(r)==-1,StringFormat("margin mode %d: ownership not separable, unknown",modes[k]));
     }
   CFakePort q;
   q.account_ok=false;
   SExResult s;
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(q),s);
   Check(!s.ok && s.reason=="ACCOUNT_UNREADABLE","an unreadable account is unknown");
  }

void Scenario_ownership_by_magic(void)
  {
   CFakePort p;
   p.AddPos(1);
   p.AddPos(2,0);
   p.AddPos(3,778);
   p.AddPos(4);
   p.AddOrd(5,0);
   SExResult r;
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(p),r);
   Check(r.ok && r.open_positions==2 && r.foreign_positions==2 && r.foreign_pending==1 && r.pending==0,"only the EA magic is owned; manual / other-EA items are foreign information");
   Check(p.calls==2,"foreign items are never evaluated");
  }

void Scenario_pending_policy(void)
  {
   CFakePort p;
   p.AddPos(1);
   p.AddOrd(2);
   p.AddOrd(3,MAGIC,1,0.1,100.0,101.0);
   p.AddOrd(4,0);
   SExResult r;
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(p),r);
   Check(r.ok && r.open_positions==3 && r.pending==2 && r.foreign_pending==1,"COUNT: owned pending orders reserve positions");
   CFakePort q;
   q.AddPos(1);
   q.AddOrd(2);
   q.ord_complete=false;
   SExResult s;
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_IGNORE,GetPointer(q),s);
   Check(s.ok && s.open_positions==1 && s.pending==0 && q.order_reads==0,"IGNORE: orders are neither read nor counted");
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(q),s);
   Check(!s.ok && s.reason=="ORDERS_INCOMPLETE","COUNT with an incomplete order list is unknown");
  }

void Scenario_risk_from_broker(void)
  {
   CFakePort p;
   p.AddPos(1);
   p.AddPos(2,MAGIC,1,0.2,100.0,101.0);
   p.AddPos(3,MAGIC,0,0.1,100.0,100.5);
   SExResult r;
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(p),r);
   Check(r.ok && r.risk_known && Near(r.existing_risk,30.0) && Near(EX_GateRisk(r),30.0),"risk = loss at the stop from the broker calculation; a stop past break-even carries none");
   CFakePort q;
   q.AddPos(1);
   q.AddOrd(2,MAGIC,1,0.3,100.0,101.0);
   SExResult s;
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(q),s);
   Check(s.risk_known && Near(s.existing_risk,40.0),"owned pending orders add their risk at their own price");
   CFakePort e;
   SExResult t;
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(e),t);
   Check(t.ok && t.open_positions==0 && t.risk_known && t.existing_risk==0.0,"nothing owned: zero is a KNOWN value");
  }

void Scenario_risk_unknown_never_zero(void)
  {
   for(int k=0;k<5;k++)
     {
      CFailPort p;
      if(k==0) p.AddPos(1,MAGIC,0,0.1,100.0,0.0);
      if(k==1) p.AddPos(1,MAGIC,0,0.1,100.0,EMPTY_VALUE);
      if(k==2) p.AddPos(1,MAGIC,0,0.0,100.0,99.0);
      if(k==3) {p.AddPos(1); p.AddPos(2,MAGIC,0,0.1,100.0,98.0);}
      if(k==4) p.AddOrd(1,MAGIC,0,0.1,100.0,0.0);
      SExResult r;
      EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(p),r);
      Check(r.ok && !r.risk_known && r.existing_risk==-1.0 && EX_GateRisk(r)==-1.0 && r.risk_reason!="",StringFormat("risk case %d is unknown, never zero",k));
     }
   CFakePort q;
   q.AddPos(1,MAGIC,0,0.1,100.0,0.0);
   SExResult s;
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_IGNORE,GetPointer(q),s);
   Check(s.open_positions==1,"the count stays known when only the risk is unknown");
  }

void Scenario_lists_incomplete(void)
  {
   CFakePort p;
   p.AddPos(1);
   p.pos_complete=false;
   SExResult r;
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(p),r);
   Check(!r.ok && r.reason=="POSITIONS_INCOMPLETE" && EX_GatePositions(r)==-1 && EX_GateRisk(r)==-1.0,"an incomplete position list is unknown");
   CFakePort q;
   for(int i=1;i<=EX_MAX+1;i++) q.AddPos(i);
   SExResult s;
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(q),s);
   Check(!s.ok && s.reason=="POSITIONS_INCOMPLETE","a list beyond the capacity is unknown");
   CFakePort u;
   u.AddPos(1,MAGIC,5);
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(u),s);
   Check(!s.ok && s.reason=="POSITION_TYPE_UNKNOWN","an unknown position type is unknown");
   CFakePort v;
   v.AddOrd(1,MAGIC,5);
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(v),s);
   Check(!s.ok && s.reason=="ORDER_TYPE_UNKNOWN","an unknown order type is unknown");
   CFakePort w;
   for(int i=1;i<=EX_MAX+1;i++) w.AddOrd(i);
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(w),s);
   Check(!s.ok && s.reason=="ORDERS_INCOMPLETE","an order list beyond the capacity is unknown");
  }

void Scenario_gate_mapping(void)
  {
   CFakePort p;
   p.AddPos(1);
   p.AddOrd(2);
   SExResult r;
   EX_Compute(MAGIC,"XAUUSD",EX_PEND_COUNT,GetPointer(p),r);
   Check(EX_GatePositions(r)==2 && r.pending==1,"the gate gets positions + reserved pending");
   SExResult bad;
   EX_ResultInit(bad);
   Check(EX_GatePositions(bad)==-1 && EX_GateRisk(bad)==-1.0,"a result that was never computed is unknown");
  }

void OnStart()
  {
   Print("T018 EXPOSURE READER TEST: scripted fake port only; no terminal read, no order, no file.");
   Scenario_inputs_unset_block();
   Scenario_account_not_separable();
   Scenario_ownership_by_magic();
   Scenario_pending_policy();
   Scenario_risk_from_broker();
   Scenario_risk_unknown_never_zero();
   Scenario_lists_incomplete();
   Scenario_gate_mapping();
   PrintFormat("T018 EXPOSURE READER TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
