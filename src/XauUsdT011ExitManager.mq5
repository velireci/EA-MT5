//+------------------------------------------------------------------+
//| XauUsdT011ExitManager.mq5                                        |
//| T011 TICK-PATH EA for ONE already REGISTERED, owned position:    |
//| the existing executor wired to the quote loop. DISABLED BY       |
//| DEFAULT (InpEnabled=false). It never registers (see              |
//| XauUsdT011ExitRegister.mq5), never opens, adopts or modifies a   |
//| position, has no signal and no strategy code.                    |
//| OnInit: recovery of the stored record FIRST (the restart flow);  |
//| only an IDLE R_GEOM record arms the quotes. OnTick: below the    |
//| level no I/O; at the level EX_Process (the only request source,  |
//| BUY Bid >= 2R, SELL Ask <= 2R). OnTimer: reconciliation only.    |
//| ONE lock (per terminal only) for OnInit, OnTick and OnTimer;     |
//| any lock failure = zero sends. Real sending needs: the phrase,   |
//| a DEMO account, InpConfirmAutoSend = true and the plan matching. |
//| UNVERIFIED: not compiled or run by the author.                   |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"
#property description "T011 exit manager (tick path). Disabled by default. Demo accounts only."
#include "include/ExitTickDriver.mqh"
#include "include/ExitTransportReal.mqh"

input bool InpEnabled=false;                            // false = inert: nothing is read, locked or armed
input string InpAuthorisation="";                       // type I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE deliberately; empty = the executor refuses every real request
input bool InpConfirmAutoSend=false;                    // must be true: this EA may send ONE closing request on its own when the level is reached
input ENUM_ETD_RPOLICY InpRPolicy=ETD_RPOL_UNSET;       // UNSET = refused. R_GEOM only; it does not settle the client's final R or the costs
input long InpEaMagic=0;                                // magic of the owned position (> 0)
input long InpPositionId=0;                             // POSITION_IDENTIFIER of the registered position
input string InpSymbol="";                              // must equal the chart symbol
input ENUM_ETD_DIRECTION InpDirection=ETD_DIR_UNSET;    // exactly BUY or SELL
input double InpInitialSl=0;                            // the INITIAL stop asserted at registration; must equal the stored one (a different value blocks)
input double InpTpPrice=0;                              // the TP of the registered plan (a different value blocks)
input double InpVolumeInitial=0;                        // the initial volume of the registered plan (a different value blocks)
input ENUM_EX_FILLING InpFilling=EX_FILL_UNSET;         // filling of the closing request; UNSET = refused
input long InpDeviation=-1;                             // deviation of the closing request in points; -1 = refused
input ENUM_EX_FILTER_POLICY InpFilterPolicy=EX_POL_UNSET;   // exit behaviour towards spread / news / session filters; UNSET = refused
input ENUM_EX_FILTER_STATE InpFilterState=EX_FS_UNKNOWN;    // state of those filters supplied by the owner (used only with NEEDS_CLEAR)
input int InpTimerSeconds=60;                           // reconcile period while a record waits for the history (>= 10)

CRealTransport g_transport;
SExConfig g_cfg;
SEsIdentity g_id;
SEtdState g_state;
SExRuntime g_rt;
string g_name="";
bool g_active=false;
string g_last="";

void Say(const string text)
  {
   if(text==g_last) return;
   g_last=text;
   Print("T011 EXIT MANAGER: ",text);
  }

int Refuse(const string reason)
  {
   Print("T011 EXIT MANAGER: STOP ",reason,". Inert: nothing is read, locked, armed or sent.");
   g_active=false;
   return(INIT_PARAMETERS_INCORRECT);
  }

int OnInit()
  {
   g_active=false;
   ETD_StateInit(g_state);
   EX_RuntimeInit(g_rt);
   if(!InpEnabled)
     {
      Print("T011 EXIT MANAGER: disabled (InpEnabled = false). Inert.");
      return(INIT_SUCCEEDED);
     }
   if(InpAuthorisation!=EX_AUTH_PHRASE) return(Refuse("REAL_NOT_AUTHORISED: the phrase is missing or wrong"));
   if(!InpConfirmAutoSend) return(Refuse("InpConfirmAutoSend is false: this EA may send a closing request on its own, so it must be confirmed"));
   if((int)InpRPolicy!=(int)ETD_RPOL_R_GEOM) return(Refuse("INPUT_UNSET: InpRPolicy"));
   if((int)InpDirection!=(int)ETD_DIR_BUY && (int)InpDirection!=(int)ETD_DIR_SELL) return(Refuse("INPUT_UNSET_OR_INVALID: direction must be exactly BUY or SELL"));
   if(InpEaMagic<=0 || InpPositionId<=0) return(Refuse("INPUT_UNSET: magic or position id"));
   if(InpSymbol=="" || InpSymbol!=_Symbol) return(Refuse("INPUT_UNSET_OR_WRONG: symbol must be set and equal to the chart symbol"));
   if(!(InpInitialSl>0.0) || !(InpTpPrice>0.0) || !(InpVolumeInitial>0.0)) return(Refuse("INPUT_UNSET: initial SL, TP or volume"));
   if(InpTimerSeconds<10) return(Refuse("INPUT_INVALID: InpTimerSeconds must be >= 10"));
   EX_ConfigInit(g_cfg);
   g_cfg.enabled=true;
   g_cfg.r_policy=EX_RPOL_R_GEOM;
   g_cfg.real_authorised=true;
   g_cfg.authorisation=InpAuthorisation;
   g_cfg.ea_magic=InpEaMagic;
   g_cfg.filling=InpFilling;
   g_cfg.deviation=InpDeviation;
   g_cfg.filter_policy=InpFilterPolicy;
   g_cfg.filter_state=InpFilterState;
   g_cfg.sl_initial_set=true;
   g_cfg.sl_initial=InpInitialSl;
   g_cfg.tp_set=true;
   g_cfg.tp_price=InpTpPrice;
   SExAccount acct;
   g_transport.ReadAccount(acct);
   if(!acct.read_ok) return(Refuse("ACCOUNT_UNREADABLE"));
   g_id.server=acct.server;
   g_id.login=acct.login;
   g_id.symbol=InpSymbol;
   g_id.position_id=(ulong)InpPositionId;
   g_name=ESF_FileName(acct.login,(ulong)InpPositionId);
   SXaRaw ra,rb;                          // unused: the real transport reads the terminal itself (live)
   XA_RawInit(ra);
   XA_RawInit(rb);
   SErfResult flow;
   bool armed=ETD_Init(g_cfg,GetPointer(g_transport),g_name,g_id,ra,rb,g_state,flow);
   PrintFormat("T011 EXIT MANAGER INIT: armed %d | direction %d | level 2R %.8g (derived from the stored E and S) | reconcile_due %d | %s",(int)armed,g_state.direction,g_state.level,(int)g_state.reconcile_due,g_state.reason);
   g_active=true;                         // the timer / tick handlers decide from g_state; an unarmed state sends nothing
   if(g_state.reconcile_due) EventSetTimer(InpTimerSeconds);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

void OnTick()
  {
   if(!g_active || !g_state.armed) return;
   MqlTick t;
   if(!SymbolInfoTick(InpSymbol,t) || !(t.bid>0.0) || !(t.ask>0.0)) return;
   SExQuote q;
   q.direction=(int)InpDirection;
   q.level_2r=0.0;                          // ignored in R_GEOM: the level is derived from the stored E and S
   q.bid=t.bid;
   q.ask=t.ask;
   q.volume_initial=InpVolumeInitial;
   SExResult res;
   bool sent=ETD_Tick(g_cfg,GetPointer(g_transport),g_rt,g_name,g_id,q,g_state,res);
   if(res.final_state!=EX_NO_REQUEST)
      Say(StringFormat("%s | sends %d | %s",EX_FinalName(res.final_state),res.sends,res.reason));
   if(sent) EventSetTimer(InpTimerSeconds);
  }

void OnTimer()
  {
   if(!g_active) return;
   if(!g_state.reconcile_due)
     {
      EventKillTimer();
      return;
     }
   SXaRaw ra,rb;
   XA_RawInit(ra);
   XA_RawInit(rb);
   SErfResult flow;
   if(ETD_Timer(GetPointer(g_transport),g_name,g_id,ra,rb,g_state,flow))
      Say(StringFormat("TIMER %s | decision %s | saved %d | %s",ERF_FinalName(flow.final_state),flow.decision,(int)flow.saved,flow.reason));
   if(!g_state.reconcile_due) EventKillTimer();
  }
