# T008 — kontrolli i planit me brokerin, pa urdhra

EA: src/XauUsdTradePreview.mq5. Test: src/tests/T008_BrokerLossTest.mq5. Kërkon header-at ekzistues në src/include si më parë. Është kandidat manual, jo zgjedhje automatike H4/M15. Funksionon pa aktivizuar Algo Trading; nuk dërgon, modifikon ose anulon urdhra.

1. Ekzekuto BrokerLossTest nga Scripts dhe ruaj rezultatin.
2. Vendos EA nga Experts në simbolin që dëshiron të verifikosh. Inputet fillestare japin INPUT_UNSET; kjo është e pritshme.
3. Furnizo drejtimin, signal/setup IDs, çmimin limit, SL, buxhetin MONETAR në valutën që raporton paneli, dhe target opsional. Nuk ka bazë automatike 1% dhe nuk përdoret çmimi live si hyrje automatike.
4. Parametrat e simbolit, kufijtë e volumit, quote dhe loss-side tick value lexohen nga terminali. Nëse plani refuzohet, logu tregon arsyen. BUY limit duhet poshtë Ask; SELL sipër Bid. Mos ndrysho SL strategjike thjesht për të marrë OK.
5. Snapshot-i i politikave është i jashtëm: InpDataState, SessionState, NewsState, SpreadState dhe SignalUnused janë UNKNOWN si parazgjedhje. CLEAR do të thotë se thirrësi e ka verifikuar, jo se EA e lexoi nga sistemi. BLOCK do të thotë i bllokuar; për SignalUnused do të thotë sinjal i përdorur. Numrat e pozicioneve/trade-ve/riskut dhe kufijtë monetarë jepen shprehimisht; -1 nuk është zero dhe mbetet e panjohur/policy unset.
6. Për testin e lidhjes mund të përdoren vlera hipotetike, por duhen etiketuar si të tilla; nuk bëhen vendime të klientit. Mos deklaro se gjendja e lajmeve/seancës/ekspozimit u verifikua automatikisht.
7. EA përdor OrderCalcProfit për vlerësimin e humbjes për volumin/çmimet e planit. Humbja duhet të jetë negative si profit dhe të mos kalojë buxhetin. Diferenca ndaj modelit lejohet deri në InpModelTolerance (parazgjedhje1%, konventë diagnostike e ndryshueshme). Për riskun e kombinuar përdoret maksimumi mes modelit dhe brokerit; plani origjinal ruhet për raportim. Kostot, slippage, margin/freeze/filling dhe ekzekutimi nuk validohen këtu.
8. Kontrolli kryhet një herë në OnInit. Paneli është snapshot statik; rifresko duke ndryshuar inputet/rivendosur EA. Quote kërkon terminal të lidhur dhe moshë jo mbi InpMaxQuoteAgeSeconds (30 si konventë diagnostike). Nuk pretendohet monitorim live ose leje ekzekutimi.

Loget: T008 SYMBOL, T008 BROKER LOSS, T008 PREVIEW RESULT/BLOCK. PREVIEW CHECKS PASS nuk është urdhër dhe nuk konfirmon strategjinë.

Dokumentacioni i API-ve: [OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit), [SymbolInfoTick](https://www.mql5.com/en/docs/marketinformation/symbolinfotick), [Symbol properties](https://www.mql5.com/en/docs/constants/environment_state/marketinfoconstants).

## v1.01 — probe i brokerit
Prova reale da2a24c tregoi model10 EUR kundrejt broker89.79 EUR për .1 lot, E4000/SL3990. Mbrojtja e buxhetit bllokoi saktë. Tani EA normalizon përmes TG, llogarit humbjen me OrderCalcProfit në volume_min dhe nxjerr vlerën efektive për tick/lot për këtë kandidat. Vlera e simbolit ruhet vetëm në diagnostikë, pa fallback. T005/T006/T007 nuk ndryshojnë. Prova përfundimtare te volumi i propozuar ruhet: diferenca tani kontrollon shkallëzimin e vlerësimit të brokerit, jo përputhjen me property. Nëse probe nuk është i vlefshëm, bllokon. Nuk shtohet përshtatje automatike ose urdhër. Log i ri T008 BROKER PROBE.
