// Pure comparison of a supplied OrderCalcProfit estimate with model/budget.
// Technical diagnostic tolerance only, not a client risk rule. No trading calls.
#ifndef VELO_BROKER_LOSS_CHECK_MQH
#define VELO_BROKER_LOSS_CHECK_MQH
#include "TradePlanning.mqh"
double PB_PermitRisk(const double profit,const double model_loss)
  {
   if(!TG_Finite(profit) || !TG_Finite(model_loss) || profit>=0 || model_loss<=0) return(0);
   return(MathMax(-profit,model_loss));
  }
string PB_CheckLoss(const bool calc_ok,const double profit,const double model_loss,
                    const double budget,const double tolerance)
  {
   if(!calc_ok) return("CALC_FAILED");
   if(!TG_Finite(profit) || !TG_Finite(model_loss) || !TG_Finite(budget) || !TG_Finite(tolerance) ||
      model_loss<=0 || budget<=0 || tolerance<0 || tolerance>1) return("INVALID_INPUT");
   if(profit>=0) return("NOT_A_LOSS");
   double loss=-profit;
   if(TP_RiskExceeded(0,loss,budget)) return("BUDGET_EXCEEDED");
   double relative=MathAbs(loss-model_loss)/model_loss;
   if(!TG_Finite(relative) || relative>tolerance+4*DBL_EPSILON) return("MODEL_MISMATCH");
   return("OK");
  }
#endif
