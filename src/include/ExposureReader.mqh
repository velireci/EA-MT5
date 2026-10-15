// T018 EXPOSURE READER core (mirror of tests/exposure_reference.py): READ-ONLY account exposure of THIS EA for the entry gate, over an abstract port (the terminal reads are in ExposureReaderReal.mqh).
// Ownership is the magic number ONLY and only on a HEDGING account (netting / exchange merge positions, so a manual trade cannot be separated: UNKNOWN). A position / order of another magic is counted as
// foreign information and never owned. Risk = loss at the stop from the BROKER calculation (calc port); a missing SL, price or volume, an unreadable calculation, an incomplete list or an UNSET pending
// policy never becomes zero: the value is UNKNOWN (-1) and the gate blocks. Whether an owned pending order reserves a position (EX_PEND_*) and whether its risk is part of the existing risk (EX_RISK_*) are two SEPARATE owner decisions, never defaulted; an UNSET risk policy makes the risk UNKNOWN as soon as an owned pending order exists. Every list is read twice and a difference means it changed while it was read: UNKNOWN. No order function here.
#ifndef VELO_EXPOSURE_READER_MQH
#define VELO_EXPOSURE_READER_MQH

#define EX_MAX 64
#define EX_PEND_UNSET 0
#define EX_PEND_COUNT 1
#define EX_PEND_IGNORE 2
#define EX_RISK_UNSET 0
#define EX_RISK_INCLUDE 1
#define EX_RISK_EXCLUDE 2
#define EX_HEDGING 2

struct SExItem
  {
   ulong ticket;
   string symbol;
   long magic;
   int kind;                    // 0 buy side, 1 sell side, other = unknown
   double volume;
   double price;
   double sl;
  };

class CExPort
  {
public:
   virtual void Account(bool &ok,int &margin_mode)=0;
   virtual void Positions(SExItem &p[],int &n,bool &complete)=0;           // every open position of the account
   virtual void Orders(SExItem &o[],int &n,bool &complete)=0;              // every active pending order of the account
   virtual bool Calc(const bool buy,const string symbol,const double volume,const double open,const double sl,double &profit)=0;   // OrderCalcProfit; false = not obtained
  };

struct SExResult
  {
   bool ok;                     // the counts are trustworthy
   string reason;
   long open_positions;         // owned positions (+ owned pending when the policy is COUNT); -1 = unknown
   long pending;
   long foreign_positions;
   long foreign_pending;
   bool risk_known;
   double existing_risk;        // -1 = unknown
   string risk_reason;
  };

void EX_ResultInit(SExResult &r)
  {
   r.ok=false;
   r.reason="";
   r.open_positions=-1;
   r.pending=-1;
   r.foreign_positions=0;
   r.foreign_pending=0;
   r.risk_known=false;
   r.existing_risk=-1.0;
   r.risk_reason="";
  }

long EX_GatePositions(const SExResult &r) {return(r.ok ? r.open_positions : -1);}
double EX_GateRisk(const SExResult &r) {return((r.ok && r.risk_known) ? r.existing_risk : -1.0);}

bool EX_Usable(const SExItem &i) {return(i.sl>0.0 && MathIsValidNumber(i.sl) && i.price>0.0 && MathIsValidNumber(i.price) && i.volume>0.0 && MathIsValidNumber(i.volume));}

bool EX_SameItem(const SExItem &a,const SExItem &b)
  {
   return(a.ticket==b.ticket && a.symbol==b.symbol && a.magic==b.magic && a.kind==b.kind && a.volume==b.volume && a.price==b.price && a.sl==b.sl);
  }

bool EX_SameList(const SExItem &a[],const int na,const SExItem &b[],const int nb)
  {
   if(na!=nb) return(false);
   for(int i=0;i<na;i++)
      if(!EX_SameItem(a[i],b[i])) return(false);
   return(true);
  }

void EX_Compute(const long magic,const string symbol,const int pend_policy,const int risk_policy,CExPort *port,SExResult &r)
  {
   EX_ResultInit(r);
   if(magic<=0 || symbol=="" || (pend_policy!=EX_PEND_COUNT && pend_policy!=EX_PEND_IGNORE) ||
      (risk_policy!=EX_RISK_UNSET && risk_policy!=EX_RISK_INCLUDE && risk_policy!=EX_RISK_EXCLUDE)) {r.reason="INPUT_UNSET"; return;}
   bool acc_ok=false;
   int mode=-1;
   port.Account(acc_ok,mode);
   if(!acc_ok) {r.reason="ACCOUNT_UNREADABLE"; return;}
   if(mode!=EX_HEDGING) {r.reason="OWNERSHIP_NOT_SEPARABLE"; return;}
   // two COMPLETE snapshots, each positions THEN orders, compared afterwards: a pending order that is filled between the reads (it leaves the orders and appears among the positions) can never be missed by both lists
   SExItem pos[],pos2[],ord[],ord2[];
   int np=0,np2=0,no=0,no2=0;
   bool pc=false,pc2=false,oc=false,oc2=false;
   port.Positions(pos,np,pc);
   port.Orders(ord,no,oc);
   port.Positions(pos2,np2,pc2);
   port.Orders(ord2,no2,oc2);
   if(!pc || !pc2 || np<0 || np>EX_MAX || np2<0 || np2>EX_MAX) {r.reason="POSITIONS_INCOMPLETE"; return;}
   if(!oc || !oc2 || no<0 || no>EX_MAX || no2<0 || no2>EX_MAX) {r.reason="ORDERS_INCOMPLETE"; return;}
   if(!EX_SameList(pos,np,pos2,np2)) {r.reason="POSITIONS_CHANGED"; return;}
   if(!EX_SameList(ord,no,ord2,no2)) {r.reason="ORDERS_CHANGED"; return;}
   SExItem own[];
   ArrayResize(own,0);
   int nown=0;
   for(int i=0;i<np;i++)
     {
      if(pos[i].magic!=magic) {r.foreign_positions++; continue;}
      if(pos[i].kind!=0 && pos[i].kind!=1) {r.reason="POSITION_TYPE_UNKNOWN"; return;}
      ArrayResize(own,nown+1);
      own[nown]=pos[i];
      nown++;
     }
   int nown_pos=nown;
   int nown_ord=0;
   for(int i=0;i<no;i++)
     {
      if(ord[i].magic!=magic) {r.foreign_pending++; continue;}
      if(ord[i].kind!=0 && ord[i].kind!=1) {r.reason="ORDER_TYPE_UNKNOWN"; return;}
      ArrayResize(own,nown+1);
      own[nown]=ord[i];
      nown++;
      nown_ord++;
     }
   r.ok=true;
   r.reason="OK";
   r.pending=nown_ord;
   r.open_positions=nown_pos+(pend_policy==EX_PEND_COUNT ? nown_ord : 0);
   double total=0.0;
   r.risk_known=true;
   if(nown_ord>0 && risk_policy==EX_RISK_UNSET)
     {
      r.risk_known=false;
      r.risk_reason="PENDING_RISK_POLICY_UNSET: "+IntegerToString(nown_ord)+" owned pending order(s)";
     }
   int nrisk=(risk_policy==EX_RISK_INCLUDE ? nown : nown_pos);
   for(int i=0;i<nrisk && r.risk_known;i++)
     {
      string what=(i<nown_pos ? "position " : "order ")+IntegerToString((long)own[i].ticket);
      if(!EX_Usable(own[i])) {r.risk_known=false; r.risk_reason=what+": no usable SL / price / volume"; break;}
      double profit=0.0;
      if(!port.Calc(own[i].kind==0,own[i].symbol,own[i].volume,own[i].price,own[i].sl,profit) || !MathIsValidNumber(profit))
        {r.risk_known=false; r.risk_reason=what+": broker calculation not obtained"; break;}
      total+=MathMax(0.0,-profit);                       // a stop already past break-even carries no risk
     }
   r.existing_risk=(r.risk_known ? total : -1.0);
  }
#endif
