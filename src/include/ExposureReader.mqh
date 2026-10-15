// T018 EXPOSURE READER core (mirror of tests/exposure_reference.py): READ-ONLY account exposure of THIS EA for the entry gate, over an abstract port (the terminal reads are in ExposureReaderReal.mqh).
// Ownership is the magic number ONLY and only on a HEDGING account (netting / exchange merge positions, so a manual trade cannot be separated: UNKNOWN). A position / order of another magic is counted as
// foreign information and never owned. Risk = loss at the stop from the BROKER calculation (calc port); a missing SL, price or volume, an unreadable calculation, an incomplete list or an UNSET pending
// policy never becomes zero: the value is UNKNOWN (-1) and the gate blocks. Whether a pending order reserves a position is the owner's policy (EX_PEND_*), never defaulted. No order function here.
#ifndef VELO_EXPOSURE_READER_MQH
#define VELO_EXPOSURE_READER_MQH

#define EX_MAX 64
#define EX_PEND_UNSET 0
#define EX_PEND_COUNT 1
#define EX_PEND_IGNORE 2
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

void EX_Compute(const long magic,const string symbol,const int pend_policy,CExPort *port,SExResult &r)
  {
   EX_ResultInit(r);
   if(magic<=0 || symbol=="" || (pend_policy!=EX_PEND_COUNT && pend_policy!=EX_PEND_IGNORE)) {r.reason="INPUT_UNSET"; return;}
   bool acc_ok=false;
   int mode=-1;
   port.Account(acc_ok,mode);
   if(!acc_ok) {r.reason="ACCOUNT_UNREADABLE"; return;}
   if(mode!=EX_HEDGING) {r.reason="OWNERSHIP_NOT_SEPARABLE"; return;}
   SExItem pos[];
   int np=0;
   bool pc=false;
   port.Positions(pos,np,pc);
   if(!pc || np<0 || np>EX_MAX) {r.reason="POSITIONS_INCOMPLETE"; return;}
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
   if(pend_policy==EX_PEND_COUNT)
     {
      SExItem ord[];
      int no=0;
      bool oc=false;
      port.Orders(ord,no,oc);
      if(!oc || no<0 || no>EX_MAX) {r.reason="ORDERS_INCOMPLETE"; return;}
      for(int i=0;i<no;i++)
        {
         if(ord[i].magic!=magic) {r.foreign_pending++; continue;}
         if(ord[i].kind!=0 && ord[i].kind!=1) {r.reason="ORDER_TYPE_UNKNOWN"; return;}
         ArrayResize(own,nown+1);
         own[nown]=ord[i];
         nown++;
        }
     }
   r.ok=true;
   r.reason="OK";
   r.pending=(pend_policy==EX_PEND_COUNT ? nown-nown_pos : 0);
   r.open_positions=nown;
   double total=0.0;
   r.risk_known=true;
   for(int i=0;i<nown;i++)
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
