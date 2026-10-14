// T004 adapter only: does not choose between T002 direction and T003 bias.
#ifndef VELO_H4_M15_BRIDGE_MQH
#define VELO_H4_M15_BRIDGE_MQH
#include "H4Bias.mqh"
#include "M15Confirmation.mqh"

// Default source selection is false. The caller must opt into T003_PROTOTYPE.
// Reliability comes from the matching evaluation, not merely the setup phase.
bool M4ContextFromH3(const SH3SetupCtx &h4,const bool reliable,SM4Context &out,
                     const bool selected_source=false)
  {
   M4ContextInit(out);
   out.setup=h4.setup_id;
   out.direction=(h4.direction=="BULL" ? 1 : (h4.direction=="BEAR" ? -1 : 0));
   out.source="T003_PROTOTYPE";
   out.fvg=h4.fvg_id;
   out.lower=h4.fvg_lower; out.upper=h4.fvg_upper;
   out.confirmed=h4.fvg_conf;
   out.valid_from=h4.valid_from;
   out.ready=(h4.valid && h4.ready && h4.phase=="RECONFIRMED");
   out.reliable=reliable; out.selected=selected_source;
   return(out.ready && out.reliable && out.selected && out.direction!=0 &&
          out.setup!="" && out.fvg!="" && MathIsValidNumber(out.lower) &&
          MathIsValidNumber(out.upper) && out.lower>0 && out.upper>out.lower &&
          out.confirmed>0 && out.valid_from>=out.confirmed);
  }
#endif
