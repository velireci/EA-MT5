//+------------------------------------------------------------------+
//| XauUsdSnapshotDiag.mq5                                           |
//| T011 READ-ONLY diagnostic of the snapshot adapter.               |
//| Nothing is sent, modified, cancelled or closed, and no trade is  |
//| created for the test: run it against a position and its orders   |
//| that ALREADY exist (for example a manual demo trade) and read    |
//| the Experts log. The request is SIMULATED in memory from the     |
//| typed initial volume; the order tickets are typed by you in      |
//| place of the future executor's identity map (without them the    |
//| verdict is UNKNOWN by design). UNVERIFIED: not compiled here.    |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs
#property version "1.00"
#property description "T003-T011 read-only diagnostic: reads positions, orders, deals and volume parameters. No trading."
#include "include/ExitSnapshotAdapter.mqh"

input string InpSymbol         = "XAUUSD";   // Symbol of the position
input ulong  InpPositionId     = 0;          // POSITION_IDENTIFIER of the position (NOT necessarily the ticket)
input int    InpDirection      = 1;          // Position direction: 1 = BUY, -1 = SELL
input double InpInitialVolume  = 0.0;        // Initial volume of the position before the partial close (lots)
input string InpOrderTickets   = "";         // Order tickets of the closing request, comma separated (the executor's map; empty = UNKNOWN)
input bool   InpOrdersComplete = false;      // Do you assert that this list holds EVERY order sent for the request?

int ParseTickets(const string text,SXaMap &mp)
  {
   string parts[];
   int n=StringSplit(text,',',parts);
   int added=0;
   for(int i=0;i<n;i++)
     {
      string p=parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(p=="")
         continue;
      ulong t=(ulong)StringToInteger(p);
      if(t==0 || !XA_MapAdd(mp,t))
        {
         PrintFormat("T011 DIAG: ticket '%s' ignored (zero, not a number, or more than %d tickets)",p,XA_MAX_ORDERS);
         continue;
        }
      added++;
     }
   return(added);
  }

void OnStart()
  {
   Print("T011 DIAG: READ-ONLY. Nothing is sent, modified, cancelled or closed. The request below is simulated in memory.");
   if(InpPositionId==0 || InpInitialVolume<=0.0 || (InpDirection!=1 && InpDirection!=-1))
     {
      Print("T011 DIAG: set InpPositionId, InpDirection (1/-1) and InpInitialVolume (> 0) first.");
      return;
     }
   double step=0.0,vmin=0.0,vmax=0.0;
   if(!SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_STEP,step) || !SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MIN,vmin) || !SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MAX,vmax))
     {
      PrintFormat("T011 DIAG: the volume parameters of %s could not be read (error %d).",InpSymbol,GetLastError());
      return;
     }
   PrintFormat("T011 DIAG: real volume parameters of %s: min %.8g step %.8g max %.8g",InpSymbol,vmin,step,vmax);
   // a simulated 2R request: level 1.0 reached by bid = ask = 1.0 for both directions
   SEaState st;
   EA_StateInit(st);
   SEaResult r;
   EA_OnQuote(st,InpPositionId,InpDirection,1.0,1.0,1.0,InpInitialVolume,InpInitialVolume,vmin,step,vmax,r);
   if(r.action!=EA_ACT_REQUEST_PARTIAL_CLOSE)
     {
      PrintFormat("T011 DIAG: no simulated request: %s %s",EA_EventName(r.event),r.reason);
      return;
     }
   PrintFormat("T011 DIAG: simulated request %s: close %.8g of %.8g (%I64d of %I64d steps). The 80/20 plan is the pure ExitSplit.",
               r.request_id,r.request_volume,InpInitialVolume,r.request_steps,st.initial_steps);
   SXaMap mp;
   XA_MapInit(mp,st.request_id,InpPositionId,InpSymbol,InpOrdersComplete);
   int nt=ParseTickets(InpOrderTickets,mp);
   PrintFormat("T011 DIAG: identity map (typed by you): request %s, position identifier %I64u, %d order ticket(s), orders_complete asserted: %s",
               mp.request_id,mp.position_id,nt,(mp.orders_complete ? "yes" : "no"));
   SErSnapshot snap;
   SXaResult res;
   SXaRaw raw;
   XA_ReadAndBuild(st,mp,snap,res,raw);
   // what the terminal showed
   PrintFormat("T011 DIAG: api_ok %s %s | symbol params ok %s | margin mode %d (%s) | open positions with this identifier: %d",
               (raw.api_ok ? "yes" : "NO"),raw.api_error,(raw.symbol_ok ? "yes" : "NO"),raw.margin_mode,
               (raw.margin_mode==XA_MARGIN_HEDGING ? "HEDGING, supported" : "NOT supported: blocks"),raw.n_pos);
   if(raw.n_pos==1)
      PrintFormat("T011 DIAG: position ticket %I64u (identifier %I64u) type %d symbol %s volume %.8g",raw.pos_ticket,InpPositionId,raw.pos_type,raw.pos_symbol,raw.pos_volume);
   PrintFormat("T011 DIAG: history ok %s, deals read %d%s",(raw.hist_ok ? "yes" : "NO"),raw.n_deals,(raw.deals_truncated ? " (TRUNCATED: more deals than the adapter capacity)" : ""));
   for(int i=0;i<raw.n_deals;i++)
     {
      string cls="excluded (entry or not an exit)";
      if(raw.deal[i].entry==XA_ENTRY_OUT)
         cls=(XA_InMap(mp,raw.deal[i].order) ? "LINKED to the request (exit deal of a mapped order)" : "excluded (exit deal of an order NOT in the map: manual, SL/TP or another request)");
      PrintFormat("T011 DIAG:   deal %I64u order %I64u position %I64u entry %d type %d volume %.8g -> %s",raw.deal[i].ticket,raw.deal[i].order,raw.deal[i].position_id,
                  raw.deal[i].entry,raw.deal[i].type,raw.deal[i].volume,cls);
     }
   for(int k=0;k<raw.n_orders;k++)
      PrintFormat("T011 DIAG:   order %I64u where %s state %d volume initial %.8g current %.8g position %I64u",raw.ord[k].ticket,
                  (raw.ord[k].where==XA_WHERE_HISTORY ? "history" : (raw.ord[k].where==XA_WHERE_ACTIVE ? "ACTIVE" : "NOT FOUND")),raw.ord[k].state,
                  raw.ord[k].vol_initial,raw.ord[k].vol_current,raw.ord[k].position_id);
   PrintFormat("T011 DIAG: ADAPTER VERDICT %s %s",XA_VerdictName(res.verdict),res.reason);
   if(res.verdict!=XA_READY)
     {
      Print("T011 DIAG: no snapshot. UNKNOWN / BLOCK are verdicts to act on; nothing is retried or guessed.");
      return;
     }
   PrintFormat("T011 DIAG: snapshot: position found %s, volume %.8g, REAL step %.8g, %d linked execution(s) (duplicates %d, entries excluded %d, other exits excluded %d)",
               (snap.position_found ? "yes" : "no"),snap.volume_current,snap.volume_step,snap.n_exec,res.duplicate_deals,res.excluded_entries,res.excluded_other);
   PrintFormat("T011 DIAG: executions_complete = %s. Proof: %s",(res.complete ? "TRUE" : "false"),res.proof);
   SErOutcome o;
   ER_Reconcile(st,snap,o);                               // on the simulated state only
   PrintFormat("T011 DIAG: reconcile WOULD decide %s (%s) on the SIMULATED state: %s",ER_DecisionName(o.decision),EA_StateName(st.status),o.reason);
   Print("T011 DIAG: done. Read-only.");
  }
