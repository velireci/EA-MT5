//+------------------------------------------------------------------+
//| XauUsdDailyHistoryDiag.mq5                                       |
//| T012 READ-ONLY diagnostic of the daily-history FACTS.            |
//| Reads the deal history and the open positions of ONE Tirane day  |
//| and prints separated facts. Nothing is sent, modified, cancelled |
//| or closed; no trade is created for the test. It selects NO       |
//| result formula, assigns NO win/loss/breakeven, counts NO trades  |
//| (a deal is not a trade) and does NOT reconstruct the balance at  |
//| the start of the day. UNVERIFIED: not compiled here.             |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs
#property version "1.00"
#property description "T012 read-only daily history facts. No trading, no policy."
#include "include/DailyHistory.mqh"

input string InpSymbol                 = "XAUUSD"; // Symbol of the robot (real volume step is read from it)
input long   InpEaMagic                = 0;        // Magic number of the EA: REQUIRED (> 0); 0 is the magic of manual orders and is refused
input long   InpUtcInDay               = 0;        // Any UTC instant inside the Tirane day to inspect (epoch seconds); 0 = now (TimeGMT, PC clock)
input int    InpServerOffsetSeconds    = 99999;    // Server time minus UTC in seconds (multiple of 900); 99999 = use TimeTradeServer()-TimeGMT() now (wrong if the broker DST changed inside the day)
input bool   InpHistoryCompleteAsserted = false;   // I confirm the terminal history tab shows ALL history (complete=true only then)

void OnStart()
  {
   Print("T012 HISTORY DIAG: READ-ONLY. Nothing is sent, modified, cancelled or closed. No result formula is selected; no trade, win or loss is counted.");
   SDhCfg cfg;
   cfg.ea_magic=InpEaMagic;
   datetime gmt=TimeGMT();
   cfg.utc_in_day=(InpUtcInDay>0 ? (datetime)InpUtcInDay : gmt);
   long off=InpServerOffsetSeconds;
   if(InpServerOffsetSeconds==99999)
     {
      off=(long)TimeTradeServer()-(long)gmt;
      long r=(off>=0 ? (off+450)/900 : -((-off+450)/900));
      PrintFormat("T012 HISTORY DIAG: server offset from TimeTradeServer()-TimeGMT() = %I64d s, rounded to %I64d s (check it against the broker; if the server DST changed inside the day, enter the offset by hand)",off,r*900);
      off=r*900;
     }
   cfg.server_offset_seconds=(int)off;
   cfg.history_complete_asserted=InpHistoryCompleteAsserted;
   int day=0;
   long ws=0,we=0;
   if(DH_DayWindow(cfg.utc_in_day,day,ws,we))
      PrintFormat("T012 HISTORY DIAG: Tirane day %d, UTC window [%s, %s), server window [%s, %s) at offset %d s (Europe/Tirane and DST from T009)",day,
                  TimeToString((datetime)ws,TIME_DATE|TIME_SECONDS),TimeToString((datetime)we,TIME_DATE|TIME_SECONDS),
                  TimeToString((datetime)(ws+cfg.server_offset_seconds),TIME_DATE|TIME_SECONDS),TimeToString((datetime)(we+cfg.server_offset_seconds),TIME_DATE|TIME_SECONDS),cfg.server_offset_seconds);
   SDhFacts facts;
   SDhRaw raw;
   string reason;
   ENUM_DH_VERDICT v=DH_ReadAndBuild(InpSymbol,cfg,facts,reason,raw);
   PrintFormat("T012 HISTORY DIAG: api_ok %s %s | history ok %s | positions ok %s | margin mode %d (%s) | volume step %.8g | deals read %d%s | positions described %d%s",
               (raw.api_ok ? "yes" : "NO"),raw.api_error,(raw.hist_ok ? "yes" : "NO"),(raw.positions_ok ? "yes" : "NO"),raw.margin_mode,
               (raw.margin_mode==DH_MARGIN_HEDGING ? "HEDGING, supported" : "NOT supported: blocks"),raw.vol_step,raw.n_deals,(raw.deals_truncated ? " (TRUNCATED)" : ""),
               raw.n_pos,(raw.pos_truncated ? " (TRUNCATED)" : ""));
   for(int i=0;i<raw.n_deals;i++)
     {
      long utc=raw.deal[i].time-(long)cfg.server_offset_seconds;
      string where=(utc>=ws && utc<we ? "inside the day" : "OUTSIDE the window");
      string kind=(raw.deal[i].type==DH_DEAL_BUY || raw.deal[i].type==DH_DEAL_SELL ? "trade deal" : "NON-TRADE deal (balance operation: kept apart)");
      PrintFormat("T012 HISTORY DIAG:   deal %I64u position %I64u time(server) %s entry %d type %d magic %I64d volume %.8g | profit %.2f commission %.2f swap %.2f fee %.2f | %s, %s",
                  raw.deal[i].ticket,raw.deal[i].position_id,TimeToString((datetime)raw.deal[i].time,TIME_DATE|TIME_SECONDS),raw.deal[i].entry,raw.deal[i].type,
                  raw.deal[i].magic,raw.deal[i].volume,raw.deal[i].profit,raw.deal[i].commission,raw.deal[i].swap,raw.deal[i].fee,where,kind);
     }
   for(int k=0;k<raw.n_pos;k++)
      PrintFormat("T012 HISTORY DIAG:   position %I64u opening deal found %s opening magic %I64d | all-time entry volume %.8g exit volume %.8g | currently open %s -> %s",
                  raw.pos[k].position_id,(raw.pos[k].opened_known ? "yes" : "NO"),raw.pos[k].opened_magic,raw.pos[k].open_volume_total,raw.pos[k].closed_volume_total,
                  (raw.pos[k].is_open ? "yes" : "no"),(raw.pos[k].opened_known && raw.pos[k].opened_magic==cfg.ea_magic ? "ROBOT position (magic of the opening deal)" : "NOT the robot's (excluded)"));
   PrintFormat("T012 HISTORY DIAG: VERDICT %s %s",DH_VerdictName(v),reason);
   if(v!=DH_READY)
     {
      Print("T012 HISTORY DIAG: no facts. UNKNOWN / BLOCK are verdicts, never zero or CLEAR; nothing is retried or guessed.");
      return;
     }
   PrintFormat("T012 HISTORY DIAG: deals inside the day %d (duplicates removed %d, outside the window %d) | other trade deals excluded (manual or other EA) %d | exits of robot positions not by the EA magic (e.g. manual close) %d",
               facts.deals_in_window,facts.duplicates,facts.outside_window,facts.other_trade_deals,facts.exits_not_by_ea_magic);
   for(int c=0;c<DH_NCLASSES;c++)
      PrintFormat("T012 HISTORY DIAG: robot deals, entry class %s: count %d volume %.8g | profit %.2f commission %.2f swap %.2f fee %.2f (separate fields)",DH_ClassName(c),
                  facts.cell[c].count,facts.cell[c].volume,facts.cell[c].profit,facts.cell[c].commission,facts.cell[c].swap,facts.cell[c].fee);
   PrintFormat("T012 HISTORY DIAG: NON-TRADE deals (deposits, withdrawals, credits, charges ...) kept apart: count %d profit %.2f commission %.2f swap %.2f fee %.2f",
               facts.nontrade_count,facts.nontrade_profit,facts.nontrade_commission,facts.nontrade_swap,facts.nontrade_fee);
   for(int i=0;i<facts.n_pos;i++)
      PrintFormat("T012 HISTORY DIAG: robot position %I64u: entry deals %d (volume %.8g), exit deals %d (volume %.8g) | profit %.2f commission %.2f swap %.2f fee %.2f | state %s | NOT classified as win/loss/breakeven",
                  facts.pos[i].position_id,facts.pos[i].n_in,facts.pos[i].volume_in,facts.pos[i].n_out,facts.pos[i].volume_out,facts.pos[i].profit,facts.pos[i].commission,
                  facts.pos[i].swap,facts.pos[i].fee,facts.pos[i].state);
   PrintFormat("T012 HISTORY DIAG: robot positions touched %d (this is NOT the number of trades: the number of deals is %d)",facts.n_pos,facts.cell[0].count+facts.cell[1].count+facts.cell[2].count+facts.cell[3].count+facts.cell[4].count);
   PrintFormat("T012 HISTORY DIAG: CANDIDATE results, none selected (result_formula=%s): profit only %.2f | profit+commission+swap %.2f | profit+commission+swap+fee %.2f",
               facts.result_formula,facts.candidate_profit,facts.candidate_profit_commission_swap,facts.candidate_profit_commission_swap_fee);
   PrintFormat("T012 HISTORY DIAG: balance at the start of the day: UNKNOWN. %s",facts.balance_start_note);
   PrintFormat("T012 HISTORY DIAG: complete=%s. %s",(facts.complete ? "true" : "false"),facts.proof);
   Print("T012 HISTORY DIAG: done. Read-only. Nothing here is connected to the real permit.");
  }
