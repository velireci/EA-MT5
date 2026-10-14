# T010 - filtri i lajmeve USD dhe i spread-it

Preview EA v1.03 shton dy burime automatike, secili me zgjedhje te vecante. Parazgjedhja ne te dyja eshte MANUAL: sjellja e vjeter nuk ndryshon. Rezultati i filtrave ushqen vetem snapshot-in e lejes T007; asnje urdher, anulim apo pozicion nuk preket. Preview mbetet foto statike ne OnInit.

## Inputet
- InpNewsSource: NEWS_SRC_MANUAL (InpNewsState) ose NEWS_SRC_CALENDAR_AUTO (kalendari MT5, vetem USD me ndikim HIGH, 30 minuta para dhe pas, kufijte perfshihen, ore SERVERI = TimeTradeServer; jo UTC/Tirane). Ne Strategy Tester: UNKNOWN/BLOCK.
- InpSpreadSource: SPREAD_SRC_MANUAL (InpSpreadState) ose SPREAD_SRC_QUOTE_AUTO me InpMaxSpreadPoints (pike). -1 = prag i pa vendosur (POLICY_UNSET, bllokon). 0 lejon vetem spread zero. Nuk ka vlere te supozuar: pragu kerkon matje.
- Gabim/kalendar jo gati/ngjarje pa kohe ose e palexueshme = UNKNOWN (bllokon), kurre CLEAR.

## Si provohet
1. Compile (MetaEditor) XauUsdTradePreview.mq5 dhe src/tests/T010_FiltersTest.mq5.
2. Ekzekuto T010_FiltersTest nga Scripts; dergo rreshtin "T010 FILTERS TEST finished: N passed, M failed" (te gjitha PASS).
3. Preview me burime MANUAL (inputet T008) - duhet te jape te njejtin rezultat si 1.02.
4. Preview me InpNewsSource=NEWS_SRC_CALENDAR_AUTO, InpSpreadSource=SPREAD_SRC_QUOTE_AUTO, InpMaxSpreadPoints = nje prag provues; dergo rreshtat "T010 CALENDAR", "T010 NEWS", "T010 SPREAD" dhe "T008 PREVIEW RESULT". Prove e dobishme: nje moment brenda 30 minutave nga nje lajm USD HIGH, dhe nje jashte; pastaj nje prag nen/mbi spread-in aktual.
5. Dergo gjithashtu nese ppyetja e kalendarit ktheu ok=0 ne nje dritare pa lajme (do te tregonte UNKNOWN pa arsye).
