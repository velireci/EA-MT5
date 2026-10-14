#property strict
#include "../include/BrokerLossCheck.mqh"
int passed=0,failed=0;
void Check(const bool ok,const string label)
  {
   if(ok) {passed++;Print("PASS ",label);} else {failed++;Print("FAIL ",label);}
  }
void OnStart()
  {
   Check(PB_CheckLoss(true,-100,100,100,.01)=="OK","matching BUY loss");
   Check(PB_CheckLoss(true,-5.25,5.25,5.25,.01)=="OK","matching SELL loss");
   Check(PB_CheckLoss(false,-100,100,100,.01)=="CALC_FAILED","failed calculation");
   Check(PB_CheckLoss(true,0,100,100,.01)=="NOT_A_LOSS","zero profit");
   Check(PB_CheckLoss(true,1,100,100,.01)=="NOT_A_LOSS","positive profit");
   Check(PB_CheckLoss(true,MathSqrt(-1.0),100,100,.01)=="INVALID_INPUT","NaN profit");
   Check(PB_CheckLoss(true,-100,100,100,-.1)=="INVALID_INPUT","negative tolerance");
   Check(PB_CheckLoss(true,-100,100,100,1.1)=="INVALID_INPUT","tolerance over1");
   Check(PB_CheckLoss(true,-100,0,100,.01)=="INVALID_INPUT","zero model");
   Check(PB_CheckLoss(true,-100,100,0,.01)=="INVALID_INPUT","zero budget");
   Check(PB_CheckLoss(true,-100.01,100,100,.1)=="BUDGET_EXCEEDED","budget before discrepancy");
   Check(PB_CheckLoss(true,-100,100,100,0)=="OK","exact budget");
   Check(PB_CheckLoss(true,-99,100,200,.01)=="OK","discrepancy at tolerance");
   Check(PB_CheckLoss(true,-98.99,100,200,.01)=="MODEL_MISMATCH","discrepancy beyond tolerance");
   Check(PB_CheckLoss(true,-1e308,1e308,1e308,.01)=="OK","extreme finite loss");
   Check(PB_CheckLoss(true,-10.05,10,11,.01)=="OK" && TP_RiskExceeded(90,PB_PermitRisk(-10.05,10),100),"broker estimate wins at combined cap");
   Check(PB_PermitRisk(-9.95,10)==10,"lower broker loss never lowers cap risk");
   Check(!TP_RiskExceeded(90,PB_PermitRisk(-10,10),100),"exact combined cap");
   Check(PB_PermitRisk(1,10)==0,"invalid permit risk");
   PrintFormat("T008 BROKER LOSS TEST finished: %d passed, %d failed",passed,failed);
  }
