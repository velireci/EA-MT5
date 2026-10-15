# T012 - kufijte ditore (kontroll i paster + integrim vetem-vezhgim ne preview)

Moduli i paster: src/include/DailyLimits.mqh (verifikuar nga Codex dhe pronari: Python 14/0, MetaEditor 0/0, MT5 DailyLimitsTest 604/0). Rregullat, kontrollet e konsistences dhe renditja e arsyeve: tasks/T012-daily-limits.md. T011 mbetet pjeserisht i hapur (ekzekutuesi, harta reale request->order, restart-i, politikat e daljes).

## Preview v1.04 (integrimi)
Parazgjedhja InpDailySource=DAILY_SRC_MANUAL: kontrolli ditor NUK vleresohet dhe preview sillet saktesisht si 1.03. DAILY_SRC_SNAPSHOT vlereson DL_Check me inputet e shprehura (asgje nuk lexohet nga llogaria apo historiku):
- InpDailySnapshotDay (dita e Tiranes yyyymmdd e shifrave), InpDailyBalanceStart (balanca ne fillim te dites, e furnizuar; <=0 = e panjohur), InpDailyResultKnown + InpDailyClosedResult (rezultati i mbyllur i ROBOTIT sot; pa floating, pa tregti manuale; "i panjohur" nuk behet zero), InpDailyWins, InpDailyConsecutiveLosses (-1 = e panjohur).
- Numri i trade-ve dhe kufiri i trade-ve rperdorin inputet ekzistuese InpTradesToday dhe InpMaxTrades (nje fakt = nje burim). InpMaxTrades=-1 mbetet POLICY_UNSET: kufiri 2 kundrejt 3 NUK zgjidhet.
- Ora UTC merret me TimeGMT() si te T009 (ora e PC-se); ne Strategy Tester refuzohet (DAILY_UTC_UNAVAILABLE_IN_TESTER). Dita e Tiranes vjen nga T009 (SP_Evaluate brenda DL_Check), pa kopjuar DST.
- Rezultati perfundimtar: preview_ok = DG_FinalPreview(loss_check=="OK", permit.allow, daily_evaluated, daily.entry_allowed). Nje BLOCK ditor bllokon gjithmone; MANUAL nuk ndryshon asgje; asnje BLOCK ditor nuk mund te lejoje dicka qe kontrollet ekzistuese e bllokojne. T007 dhe filtrat T008-T010 nuk ndryshojne (kontrolluar me krahasim rreshtash me 78726c4).
- Shfaqen: rreshti log "T012 DAILY ... allowed primary reasons tirane_day snapshot_day cancel_pending_due daily_limit_reached ...", arsyet "DAILY: ..." ne rezultatin T008 dhe rreshti "DAILY" ne panel. cancel_pending_due eshte vetem flamur diagnostik: asnje urdher ne pritje nuk anulohet, asnje pozicion nuk mbyllet, preview nuk perdor OrderSend/CTrade.
- Nuk perdoret fitimi 3.57 i proves manuale; rezultatet e pjesshme, kostot dhe breakeven nuk klasifikohen ketu.

## Prova hipotetike e bllokimit ditor
Skedari src/presets/XauUsdTradePreview_T012_hypothetical_daily_block.set (te gjitha inputet; politikat e tjera UNKNOWN/unset). Para nisjes: (1) vendos InpEntry/InpStopLoss ne nivele qe kalojne kontrollet T008 per kuoten aktuale (blloku ditor vleresohet pas planit dhe proves se brokerit); (2) vendos InpDailySnapshotDay = data e sotme e Tiranes yyyymmdd (15.10.2026 = 20261015; nje dite tjeter jep STALE_SNAPSHOT_DAY, qe eshte gjithashtu prove e vlefshme bllokimi). Pritet: "T012 DAILY ... allowed=0 primary=DAILY_LOSS_LIMIT reasons=DAILY_LOSS_LIMIT|POLICY_UNSET:max_trades_per_day cancel_pending_due=1", pastaj "T008 PREVIEW RESULT BLOCK". Rezultati -250.00 dhe balanca 10000 jane vlera TESTI, jo fakte. Nderro InpDailyClosedResult ne -199.99 per te pare qe nuk bllokon nga humbja (arsyet e tjera mbeten), ose ne -200.00 per te pare barazimin.
Dergo rreshtat "T012 DAILY" dhe "T008 PREVIEW RESULT".

## Testet
tests/test_t012_gate.py (Python), src/tests/T012_GateTest.mq5 (MQL5, nga i njejti gjenerator fixture-sh), tools/t012-gate-static-checks.sh (statik). Nuk jane kompiluar/ekzekutuar ne MT5 (UNVERIFIED).

## Kufizime
Preview mbetet foto statike ne OnInit; figurat jane aq te vertetat sa i jep pronari; nuk ka reset real, persistence, anulim, lidhje me EA tregtimi; sesioni T009 dhe daily nuk kombinohen me njeri-tjetrin pervec permes rezultatit perfundimtar te preview; pyetjet e hapura te klientit (2 vs 3 trade, trajtimi i pjesshmeve/kostove/breakeven, kontabilizimi i humbjes 2%) mbeten te hapura.
