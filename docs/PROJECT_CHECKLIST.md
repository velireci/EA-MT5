# Checklist qendrore e projektit

Përditësuar më 16.10.2026, me evidencën e fundit të pronarit në 03:00 (Europe/Tirane). Programuar ≠ provuar në broker ≠ validuar nga klienti. Përqindja 85% e diskutuar është vetëm vlerësim orientues, jo matje e checklist-it.

## Statusi aktual — simulimi në Tauro është aktiv

Kjo përmbledhje zëvendëson statuset historike më poshtë. [x] vlen vetëm për bllokun e përshkruar.

### E ndërtuar dhe e verifikuar
- [x] Zinxhiri H4/M15 → plan → portë → ekzekutues është lidhur; hyrjet aktuale janë FAKE dhe menaxhimi READ_ONLY.
- [x] Persistence/rikuperimi T017: pronari EntryPersistenceTest-e2d20db 99/0.
- [x] Ekspozimi T018: pronari ExposureReaderTest-3318578 53/0.
- [x] Regjistrimi automatik dhe driver-i T011 janë brenda orkestruesit; nuk kërkohet ExitManager i veçantë kur aktivizohet rruga e integruar. Prova e këtij integrimi mbetet sintetike.
- [x] Lifecycle, vëzhgimi i mbetjes pas DONE dhe outbox i njoftimeve: pronari EntryLifecycleTest-be6d868 277/0, 16.10.2026 02:16:00. Njoftimet në preset janë OFF; nuk provohet dërgim push real.
- [x] Anulimi sipas drejtimit/sinjalit të kundërt është ndërtuar me prova sintetike; jo provë brokeri.
- [x] Politika SIMULATION_1PCT_CURRENT_BALANCE në a74b4b8: 1% e balancës aktuale, vetëm FAKE/READ_ONLY; nuk ndryshon klasifikimin ose portat reale.
- [x] Codex a74b4b8: testi dhe EA-ja kompilohen secili 0 errors / 0 warnings; 55 teste Python fokale kaluan. Skripti shell statik nuk u riekzekutua nga Codex sepse procesi u bllokua nga mjedisi; rezultati i Claude mbetet i përcjellë.
- [x] Pronari EntryOrchestratorTest-a74b4b8 në XAUUSD.fx M15: 185 passed / 0 failed, 16.10.2026 02:48:48.
- [x] Preseti i plotë simulation është dorëzuar dhe nisur në Tauro. Nuk ka më CONFIG_UNSET: risk_budget ose ACCOUNT_NOT_DEMO për këtë rrugë simulimi.
- [x] Diagnostika vetëm-lexim 11e827e: Codex EA 0 errors / 0 warnings dhe 55 teste Python fokale kaluan; pronari e nisi me presetin simulation.
- [x] Log-u Tauro 02:58:57 dhe 03:00:03: connected=1, exposure OK, feed.problem bosh, timeline=OK; H3 BEAR / SWEEP_WAIT / ready=0 / eval_reliable=1, konvergjencë 2000 vs 1700; M15 WAIT_CONTEXT. Cut përparoi 00:45 → 01:00. Në këto snapshot-e mungon rikonfirmimi H4; nuk është pengesë UNSET ose histori e pangarkuar.
- [x] Prova e mëparshme manuale BUY e T011 konfirmoi një pjesëmbyllje dhe reconcile; nuk zëvendëson ciklin automatik të orkestruesit.

### Puna aktive dhe çfarë mungon
- [x] Zinxhiri pas planit me numrat Tauro (sintetik, vetëm në teste; kërkon kompilim/MT5 UNVERIFIED): record balance LOAD → bridge → porta → ekzekutuesi FAKE, BUY/SELL, cap 200, mungesa/dita e gabuar e rekordit, lajmet/spread-i/seanca me zero dërgime. Preseti simulation ka offset=0 të matur (jo default universal). Leximi real i historisë, kalendarit, spread-it dhe orës së PC mbetet evidencë terminali.
- [ ] Vëzhgimi i një setup-i të ri H4/M15 deri te plani, porta dhe kërkesa FAKE në Tauro. Deri në log-un e 03:00: virtual requests=0, lifecycle open=0; kjo rrugë në treg ende nuk është provuar.
- [ ] Kontroll i përbashkët i pengesave pas planit: balanca ditore T012, numëruesit manualë, offset-i i serverit, spread-i, lajmet, seanca dhe combined risk cap. Preseti i plotë nuk provon të dhënat reale të këtyre burimeve.
- [ ] CAPTURE real i balancës fillestare dhe verifikimi i historikut ditor; LOAD pa rekord dhe testet sintetike nuk mjaftojnë.
- [ ] Përgjigjja e Tauro: portali etiketon 358175 DEMO, por MT5 në JMFinancial-Server raporton REAL. Konfirmimi me email është në pritje. Simulimi lejohet; transportet reale mbeten të çaktivizuara.
- [ ] Cikli i plotë me urdhra në broker: sinjal → LIMIT → mbushje → regjistrim → partial → reconcile/restart. Nuk është provuar nga orkestruesi.
- [ ] Prova automatike e mëparshme SELL mbetet INCONCLUSIVE: SL e mbylli para aktivizimit të manager-it.
- [ ] Krahasimi i sinjaleve dhe sjelljes me shembujt e klientit. T011/T012 dhe roboti i plotë nuk shpallen të përfunduar nga kalimi i testeve.

### Para LIVE
- [ ] Sqarimet e mbetura të klientit në listën B D1–D13 të EA_INTEGRATION_PLAN.md, me D9 si lidhje teknike tashmë të ndërtuar: baza/kostot e riskut, 2/3 trade, pending, përkufizimet H4/MSS/FVG/SL/target, BE/+0.2%/TP=2R dhe klasifikimi ditor.
- [ ] Konfirmimi ose zëvendësimi i çdo zgjedhjeje të përkohshme të presetit.
- [ ] Auditimi dhe prova e plotë e transportit në llogarinë e synuar, pastaj autorizimi i veçantë. Politika simulation nuk autorizon live.

**Ritmi:** një paketë e lidhur dhe një raund MT5. Evidenca MT5 është e përcjellë nga pronari; kompilimet dhe 55 testet fokale më sipër u kryen nga Codex. Asnjë tregti ose njoftim real në këto ndryshime dokumentimi.

## Baza e ndërtuar — shënime historike (statuset e vjetra zëvendësohen nga përmbledhja më sipër)

H4 → M15 → FVG → kthim është ndërtuar dhe vëzhguar në replay. T005 u dorëzua te 67f02e5; Codex Python 39/0, MetaEditor 0/0; pronari MT5 572/0. T006 (sizing i pastër me buxhet risku të dhënë) te 559794a: Codex Python 47/0 dhe MetaEditor 0/0; pronari MT5 14.10.2026 18:42:14: 710 passed, 0 failed (të përcjella, jo ekzekutim i Claude). Moduli i pastër është verifikuar; integrimi me brokerin jo. T007 (plan i pastër, kontrolle lejeje dhe kërkesë anulimi, pa urdhra) është programuar me teste Python 34/0 të ekzekutuara nga Claude dhe kontrolle statike; kompilimi MetaEditor dhe MT5 janë UNVERIFIED dhe moduli nuk është i lidhur. Robot që hap dhe menaxhon urdhra: ende jo.

T010–T012 (dega PR#4, evidencë e përcjellë nga Codex dhe pronari, jo ekzekutime të Claude): filtrat e lajmeve/spread-it, ndarja 80/20 me aktivizim dhe pajtim, kufijtë ditorë, faktet e historikut dhe ura faktet → kontroll ditor janë module të pastra; ura te 1761b51 ka Codex Python 12/0, MetaEditor 0/0 dhe pronari MT5 323/0 (15.10.2026 11:49:58). Asnjë nuk është i lidhur me lejen ose EA; politikat strategjike mbeten të hapura (shih fund).

## T001 — Themelet
- [x] Themelet dhe kompilimi 0/0 në versionin e provuar.
- [x] Vëzhgim i pjesshëm demo nga pronari.
- [ ] Mbyllja e të gjitha kontrolleve të pranimit të themeleve.
Status: pjesërisht verifikuar, jo i shpallur përfundimisht i mbyllur.

## T002 — Harta H4
- [x] Strukturë, FVG, IRL/ERL dhe hartë vizuale.
- [x] MT5 LogicTest 208/0; Python 197/0; kompilim 0/0.
- [x] SetupScan: 529 momente në 147 seri.
- [x] Setup historik me kontroll manual të kufijve.
- [x] Heqje/rivendosje dhe ruajtje e vijës manuale.
- [x] Rindërtim LIVE në candle të re H4 i vëzhguar; nuk duhet pritur përsëri për këtë kontroll.
- [ ] Përputhja e të dhënave të brokerit me TradingView.
- [ ] Validimi nga klienti i përzgjedhjes mekanike të strukturës dhe zonave.
Status: implementuar me prova teknike; validimi i strategjisë mbetet i hapur.

## T003 — Bias, likuiditet dhe rikonfirmim
- [x] Logjika, EA vizuale dhe likuiditeti i brendshëm sipas propozimeve.
- [x] Te 6676a01: MT5 LogicTest 484/0/5 deferred; LayersTest 105/0; kompilim 0/0.
- [x] Python 476/0/5 deferred dhe regresion privat në dy momente historike.
- [x] Wick-u i 25 shtatorit regjistrohet pa FLIP; krahasim me përshkrimin e shembullit.
- [x] Shfaqet mospërputhja T002/T003.
- [x] Paneli vizual 1.13 (bb7c4b0, korrigjim i lexueshmërisë; rreshta ≤60 karaktere): Codex kompilim 0/0; MT5 LayersTest 111/0; fotoja e pronarit konfirmon titullin, BEAR dhe datat të plota (të përcjella, jo prova të mia). Bartur në PR#4 vetëm për panelin; shkaku (kufi 63 karaktere i etiketës) është përputhja më e mirë me prerjet, jo fakt i dokumentuar.
- [ ] Vendimi për burimin e drejtimit kur modelet kundërshtohen.
- [ ] Validimi i rregullave mekanike nga klienti.
- [ ] Pjesët e shtyra dhe kontrollet e gjera të lifecycle/vizatimit, përfshirë P12/P13 sipas scope-it të tyre.
Status: implementuar si prototip; deferred nuk janë PASS dhe CONVERGED nuk është validim klienti.

## T004 — Konteksti H4 te konfirmimi M15
- [x] Observer, selector dhe timeline kronologjik.
- [x] MT5: Logic 49/0, Selector 37/0, Timeline i parë 19/0.
- [x] Korrigjimi i rifillimit dhe prova M15 → H4 → M15 te eedbe92.
- [x] Rruga T003 RECONFIRMED e vëzhguar deri te RETURN_OBSERVED.
- [x] Rruga e zakonshme e prekjes H4 e implementuar te 78879cd.
- [x] Codex: Python 94/0 dhe EA/Ordinary/Timeline kompilim 0/0.
- [x] Pronari: MT5 OrdinaryTest 79/0.
- [x] Replay 18.09: kontekst 04:00 → BOS njohur 06:45 → FVG 08:00 → kthim njohur 10:00 → invalidim 11:30 → mbyllje H4 12:00.
- [ ] Ekzekutimi MT5 i TimelineTest me regresionin e ri të reset-it (19/0 është versioni më i vjetër).
- [ ] Validimi i selector-it, kohës së FVG-së dhe politikave OD1–OD6.
- [ ] Verifikimi më i gjerë LIVE/recovery dhe integrimi me përzgjedhjen përfundimtare të strategjisë.
Status: dy rrugë replay të vëzhguara; pa leje hyrjeje dhe pa urdhra.

## T005 — Gjeometria hyrje / SL / TP — MODULI I VERIFIKUAR
- [x] Planifikimi te 5447ef3.
- [x] Kontrolli i burimeve: klienti tha “fillimi i FVG ne M15”; SL te ekstremi i strukturës së thyer.
- [x] U dërgua udhëzimi i korrigjuar te Claude për modul të pastër me E/SL/target të furnizuara.
- [x] Dorëzimi te 67f02e5.
- [x] Rishikimi dhe korrigjimi i formulave/normalizimit.
- [x] Codex Python 39/0 dhe kompilim 0/0; pronari MT5 572/0.
- [ ] Lidhja me zgjedhjen konkrete të FVG-së, strukturës dhe targetit, vetëm pas zgjidhjes së propozimeve përkatëse.
Status: moduli i pastër i verifikuar, pa përzgjedhje sinjalesh, sizing ose urdhra.

## Të gjitha fushat ende të panisura

Rend pune i propozuar, jo task-e zyrtare të rinumëruara. Fusha 2 është nisur me modulin e pastër T006; fushat 3, 4, 6, 8, 9 dhe 10 vetëm me pjesët e pastra të T007 (pa lidhje, pa urdhra). Në repo te 5447ef3 u gjetën vetëm T001–T005; numërimi i mëparshëm i raundeve të ardhshme nuk ishte verifikuar. Një fushë mund të ndahet në disa raunde.

### 1. Zgjedhja e sinjalit për hyrje — PA NISUR
- [ ] Cila FVG M15 zgjidhet kur ka disa
- [ ] Përcaktimi mekanik i strukturës për SL
- [ ] Përzgjedhja e targetit dhe burimit të drejtimit

### 2. Risku dhe madhësia e pozicionit — NISUR (vetëm moduli i pastër T006, i verifikuar; jo i lidhur)
- [x] Moduli i pastër PositionSizing (model linear: stop ticks × tick value; rrumbullakim vetëm poshtë në volume step; SKIP nën min / mbi max / mbi cap, pa ngritje apo kufizim automatik): Codex Python 47/0; shih tasks/T006-position-sizing.md
- [x] Kompilimi MetaEditor 0/0 (Codex) dhe MT5 T006_SizingTest 710/0 (pronari, 14.10.2026 18:42:14, të përcjella te 559794a)
- [ ] Baza e 1% (balance/equity/...), kostot dhe konvertimi i valutës të llogarisë — hapur; moduli merr buxhetin e riskut nga thirrësi
- [ ] Marrja e tick value, volume step, min/max nga brokeri real (Tauro XAUUSD.r/USD e paverifikuar)
- [ ] Risku i kombinuar 2%, rezervimi nga pending, limiti 2 pozicione
- [ ] Rrumbullakimi i volumit për 80% / 20% dhe mbetja kur TP = 2R
Status: moduli i pastër i sizing-ut i verifikuar (Python, MetaEditor, MT5); 10 lotet dhe buxheti vijnë si input, asnjë vendim klienti nuk u shtua; asgjë nga brokeri real nuk është verifikuar.

### 3. Vendosja e urdhrave limit — NISUR (vetëm plani i pastër T007; asnjë urdhër)
- [x] Plani i pastër PLAN_ONLY / NOT_AN_ORDER: E, SL, TP, 2R, pika e pjesshme, volumi dhe risku i modelit nga T005 + T006, me refuzime të përhapura (Python 34/0 të ekzekutuara nga Claude; MetaEditor/MT5 UNVERIFIED; shih tasks/T007-trade-planning.md)
- [ ] Çmimet e normalizuara dhe stops/freeze levels nga brokeri real (T005 kontrollon stops level vetëm me parametra të furnizuar; freeze level jo)
- [x] Mbrojtja e dublikimit të signal_id në regjistër në memorie (regjistrohet vetëm në ALLOW, mbushja bllokon; Python)
- [ ] Identiteti i sinjalit që mbijeton restart-in dhe parandalimi atomik i dublikimeve (regjistri aktual nuk është atomik, as i qëndrueshëm)
- [ ] Përgjigjet e serverit, refuzimet dhe fill-et e pjesshme

### 4. Jeta e urdhrit në pritje — NISUR (vetëm vendimi i pastër T007; asnjë anulim real)
- [x] Kërkesë anulimi vetëm për pending nga pesë ngjarje të dhëna (ndryshim drejtimi, sinjal i kundërt, fund seance, lajm, limit ditor); pozicionet gjithmonë të paprekura (Python; MetaEditor/MT5 UNVERIFIED)
- [ ] Skadimi dhe ri-hyrja në të njëjtin setup
- [ ] Anulimi në ndryshim drejtimi/sinjal të kundërt
- [ ] Anulimi në fund seance dhe përpara lajmeve

### 5. Menaxhimi 80% / 20% — NISUR (T011: një cikël real demo i përcjellë nga pronari; jo i përfunduar)
- [x] Ndarja 80/20 në hapa të plotë, aktivizimi në 2R si makinë gjendjesh dhe pajtimi me snapshot (module të pastra; shih T011 më poshtë)
- [x] Ekzekutuesi që regjistron biletat, harta kërkesë→urdhër dhe rinisja: provuar në UNË cikël real demo (të përcjella nga pronari: BUY 0.05, urdhri mbyllës 58913523110, DONE, ALREADY_DONE pas rihapjes së MT5, sends 0). Jo SELL, jo rrugë dështimi, jo llogari live.
- [ ] Mbyllja e 80% në 2R në broker: u provua në prag DIAGNOSTIK 4140.00 (jo aktivizim strategjik në 2R); politika kur ndarja nuk realizohet (SPLIT_POLICY_UNSET) mbetet vendim klienti
- [ ] Pajtimi i entry plus kosto me +0.2%
- [x] Vendim: mbetja pas pjesëmbylljes mbahet deri te TP/SL, pa trailing (vendosur; BE dhe pajtimi +0.2% mbeten të hapura në rreshtin më sipër; asnjë modul i ri për mbetjen)

### 6. Kufijtë ditorë dhe ekspozimi — NISUR (vetëm kontrolli i pastër T007; kufijtë vijnë si numra ose UNSET)
- [x] Kontrolli i pozicioneve, trade/ditë dhe riskut të kombinuar me kufij të furnizuar; kufi UNSET bllokon (POLICY_UNSET); kufijtë e testit (3, 5, 5000) janë arbitrarë, jo të klientit (Python)
- [ ] Pajtimi i kufirit 2 apo 3 trade
- [x] Kontrolli i pastër ditor (fitore ≥1, 2 humbje radhazi, −2%, kufi i furnizuar) dhe ura nga faktet e historikut; politikat UNSET bllokojnë (T012 më poshtë)
- [ ] Ndalimi pas fitoreje/humbjeve dhe kufiri ditor si politikë e pranuar: formula e rezultatit, përkufizimi trade/win/loss/breakeven, balance_start
- [ ] Pending risk dhe ndarja nga tregtitë manuale

### 7. Rikuperimi dhe siguria operative — PA NISUR
- [ ] Rindërtimi nga pozicionet, urdhrat dhe historiku
- [ ] Restart/reconnect pa urdhra ose dalje të dyfishta
- [ ] Ruajtja e fazës së pjesshmes dhe numëruesve

### 8. Orari i tregtimit — NISUR (vetëm një flamur seance i furnizuar)
- [x] Kontrolli i pastër bllokon kur gjendja e seancës e furnizuar është CLOSED ose UNKNOWN; asnjë orë nuk lexohet brenda modulit (Python)
- [ ] Europe/Tirane me DST dhe koha e serverit
- [ ] 00:00–20:30 dhe mbyllja e së premtes
- [ ] Sjellja e pozicioneve në fund seance

### 9. Filtri i lajmeve dhe spread-it — NISUR (vetëm flamuj të furnizuar)
- [x] Kontrolli i pastër bllokon në NEWS/SPREAD BLOCKED ose UNKNOWN të furnizuar; nuk ka kalendar, burim lajmesh apo prag spread-i (Python)
- [ ] Lajmet USD high impact, 30 minuta para/pas
- [ ] Të dhëna lajmesh për testimin historik
- [ ] Pragu i spread-it dhe veprimi kur bllokohet

### 10. Integrimi i robotit — NISUR (vetëm zinxhiri i pastër; jo i lidhur me EA)
- [x] Zinxhiri i pastër gjeometri → sizing → plan → leje → kërkesë anulimi, BUY dhe SELL, testuar në Python; pa urdhra
- [ ] Kompilimi MetaEditor dhe ekzekutimi MT5 i T007_PlanningTest — UNVERIFIED
- [ ] Lidhja e sinjalit me sizing, urdhra dhe menaxhim
- [ ] Përparësia kur disa ngjarje ndodhin bashkë
- [ ] Rishikimi i pavarur dhe kompilimi final

### 11. Testimi i plotë — PA NISUR
- [ ] Tester me kosto dhe cilësi të deklaruar të të dhënave
- [ ] Prova demo BUY/SELL dhe skenarë dështimi
- [ ] Krahasimi me shembujt e klientit dhe regresionet

### 12. Pranimi dhe dorëzimi — PA NISUR
- [ ] Përcaktimi i tolerancave dhe kritereve të pranimit
- [ ] Udhëzues instalimi, inputet dhe kufizimet
- [ ] Miratimi i klientit/pronarit për versionin e dorëzuar

## Dokumentimi dhe vendimet
- [x] Auditimi i burimeve të hyrjes dhe SL-së.
- [x] Referenca qendrore lokale: STRATEGY_SPEC.md.
- [x] Kjo checklist dhe pamja vizuale lokale.
- [x] Integrimi i strategjisë qendrore, checklist-it dhe pamjes vizuale në docs/.
- [ ] Përditësimi i checklist-it pas çdo dorëzimi me SHA, provën dhe hapin tjetër.
- [ ] Mbyllja e konflikteve vërtet bllokuese, pasi të kërkohet në burimet ekzistuese.

## Rregulli i përditësimit

Një kuti shënohet vetëm me provë konkrete. Për testin ruaj versionin, rezultatin dhe kush e ekzekutoi. Mos fshi pikat e hapura kur një test sintetik kalon. Asnjë PR nuk deklarohet i bashkuar këtu; nuk është dhënë miratim merge ose aktivizimi tregtimi. PROJECT_PROGRESS.html është snapshot i kësaj checklist-e, jo monitor automatik. Përditëso të dyja bashkë.


## Kontrolli i kompleksitetit
- [x] Kontroll i kufizuar vetëm me lexim: pa arsye për rishkrim masiv; dublikim i vogël vizatimi dhe optimizime të mundshme pa nevojë të matur.
- [x] Defektet numerike T005 të këtij kontrolli u korrigjuan dhe u verifikuan te 67f02e5.
- [ ] Pastrim vetëm kur ndryshimi i ardhshëm ose matja e performancës e justifikon.


## T007 — module të pastra të verifikuara
- [x] Plan, lejim dhe kërkesë anulimi; pa urdhra.
- [x] Codex Python43/0 dhe kompilim0/0.
- [x] Pronari MT5 PlanningTest-40fede0:1092 passed/0failed.

## T008 — pamje brokeri vetëm me lexim
- [x] Kandidat manual me E/SL/target dhe risk monetar të furnizuar; ripërdor T005–T007.
- [x] Parametrat realë të simbolit dhe kontrolli me OrderCalcProfit; politikat e panjohura bllokojnë.
- [x] Codex Python8 të reja; T006/T007/T008 së bashku98 kalojnë; EA/test kompilim0/0.
- [x] Pronari: T008 helper v1.00 te da2a24c,19/0; v1.01 i përditësuar në pritje.
- [ ] Pronari: EA default INPUT_UNSET dhe preview me kandidat manual në broker.
Status: integrim vetëm për kontroll, jo sinjal ose urdhër; risku dhe ekspozimi i jashtëm nuk lexohen automatikisht.

- [x] T008 v1.01 korrigjim: vlera efektive e loss tick nga broker probe, Python10pass, kompilim EA/test0/0.
- [ ] Pronari: helper dhe preview v1.01 pas mospërputhjes property/model.

## T008 — përfundimi i provës së kufizuar
- [x] Owner MT5 helper4b6a5b5:25/0.
- [x] Preview brokeri BUY hipotetik:model/broker8.98EUR,.01lot,buxhet10EUR; unknown-policy BLOCK.

## T009 — orari dhe identiteti i ditës
- [x] Moduli UTC→Tirane, DST, orari, flag-uFriday dhe day_key/midnightUTC; pa reset llogarie.
- [x] Python6 teste të reja me oracle të pavarur IANA; EA/test kompilim0/0.
- [ ] Pronari: MT5 T009_SessionTest.
- [ ] Pronari: preview opsional SESSION_TIRANE_CLOCK, verifikimi i UTC/Tirane dhe portës së seancës.
Mbetet: orari nuk dërgon ende anulime ose mbyllje; persistence/catchup/lajmet të pandërtuara.

## T010 — lajmet dhe spread-i
- [x] Filtra të pastër (lajme USD high ±30 min, serveri; spread me prag të furnizuar, -1 = UNSET) me lexues të hollë kalendari në EA; MANUAL mbetet parazgjedhja.
- [ ] Verifikimi MT5/live i kalendarit dhe pragu i spread-it (vendim i hapur).

## T011 — daljet 80/20 (module + një cikël real demo i përcjellë; T011 NUK është i mbyllur)
- [x] PROVA REALE DEMO (të përcjella nga pronari, jo ekzekutim i Claude, pa log të bashkëngjitur): opener 68da9b2 BUY 0.05 magic 777, position id 58913478802; harness 2bec28d REGISTER pa dërgim, ACTIVATE një kërkesë, urdhri mbyllës 58913523110; RECONCILE READY/CONFIRMED/DONE, confirmations 1, generation 4; pas mbylljes dhe rihapjes së MT5 ALREADY_DONE, sends 0, pa rishkrim; mbetja 0.01 u mbyll manualisht nga pronari; skedarët state/intent nuk u fshinë. Pragu 4140.00 ishte diagnostik. Provon vetëm këtë cikël (BUY, 0.05, një llogari demo).
- [x] ExitSplit: Codex Python 9/0, MetaEditor 0/0, pronari MT5 SplitTest 234/0 (e3abea2).
- [x] ExitActivation: Codex Python 12/0, MetaEditor 0/0, pronari MT5 1010/0 (d83426a).
- [x] ExitReconciliation: pronari MT5 951/0, Codex kompilim 0/0 (të përcjella).
- [x] ExitSnapshotAdapter (vetëm lexim, ca3bd57): Codex Python 10/0, MetaEditor AdapterTest/diagnostik 0/0; pronari MT5 15.10.2026 10:42:58: 391 passed, 0 failed (të përcjella). Në atë commit nuk provonte hartën reale as pajtimin real; ZËVENDËSUAR nga prova reale demo më lart.
- [x] Ruajtja/rikthimi i gjendjes pas restart (ExitStateCodec + ExitStateFile, protokoll ruaj-para-dërgimit, pa urdhra): Python 29 teste OK dhe kontrolle statike; T011_PersistTest 395/0 (të përcjella nga pronari te 0356f39) dhe PersistFile 31/0; kompilimi Codex 0/0 (të përcjella). Nuk ka garanci atomike me brokerin.
- [x] Rrjedha e restart-it LOAD → identitet → snapshot → ER_Reconcile → SAVE (ExitRestartFlow; pa urdhra, pa kërkesë të re, pa retry): Python 11 teste OK; T011_FlowTest 261/0 (MT5, pronari) dhe Codex 0/0 (të përcjella). Provat e pronarit (restart MT5 12/0) janë vetëm për restart të terminalit.
- [x] Lidhja e ekzekutuesit me ciklin e kuotave dhe 2R automatik (R_GEOM): shkruar dhe testuar vetëm me transport fake (Python 519 OK, kontrolle statike ALL PASS); kompilimi Codex 16 skedarë 0/0 dhe MT5 PersistTest 509/0, ExecutorTest 750/0, GeomTest 345/0, DriverTest 26/0 (të përcjella); nuk është provuar me broker real; D1 (InpRPolicy UNSET bllokon, vetëm R_GEOM, pa kosto) dhe D2 variant (a) të miratuara nga pronari; shih docs/T011-exit-manager.md
- [ ] Prova demo SELL e ExitManager-it (paketa e presete-ve gati për rishikim Codex, magic 778, 0.05; kritere: zero kërkesa para nivelit, max një në nivel, pajtim nga brokeri, restart pa dërgim të dytë; nëse çmimi nuk e arrin nivelin = provë në pritje) — NUK është ekzekutuar
- [x] T012 ruajtja e balancës në fillim të ditës Tirane (DailyBalanceStore: LOAD vetëm-lexim, CAPTURE i shprehur me kyçje, WINDOW_EMPTY kushtor, OWNER_ASSERTED i veçantë, ACCOUNT_BALANCE): shkruar dhe testuar vetëm me port fake (Python 535 OK, kontrolle statike ALL PASS); evidencë e përcjellë: Codex kompilim 0/0 dhe MT5 T012_BalanceStoreTest@94070b5 611/0 (LOAD real 17:15:11: NONE/NO_RECORD, asnjë skedar i krijuar; CAPTURE real i paprovuar; nuk është lidhur me preview/lejen); pa lidhje me lejen; formula, 80/20 dhe 2/3 të pazgjidhura (reports/T012-balance-store.md)
- [ ] Hapat e hapur: korroborimi historik i SL fillestar, R me kosto, jetëgjatësia pas DONE (mbetja), rrugët e dështimit në broker real, rregulli i mbajtjes së skedarëve state/intent, kontrolli i modalitetit të llogarisë live, leximi i faqeve zyrtare API, politikat e daljes (vendime klienti). T011 mbetet pjesërisht i hapur.
- [ ] T011: ExitManager nuk armatoset më pa provë të pozicionit real (SELL 58917658014 u mbyll nga SL para armatosjes; prova automatike INCONCLUSIVE); korrigjim në sandbox, kompilimi/MT5 UNVERIFIED, DriverTest@7697b4f MT5 64/0, Codex 0/0; ExitManager@3215e0a 17:13:28 e refuzoi SELL 58917658014 të mbyllur (armed 0, POSITION_NOT_FOUND, pa dërgim, rekord i paprekur); prova automatike SELL mbetet INCONCLUSIVE, 2R automatik i paprovuar me broker real; provë e re kërkon rishikim Codex dhe autorizim të pronarit
- [x] T012: BalanceStore lidhur vetëm-lexim me preview (HISTORY_BRIDGE): burim i shprehur MANUAL(parazgjedhje)/STORE, vetëm DBS_Load, pa fallback manual dhe pa balancën aktuale, origjina WINDOW_EMPTY/OWNER_ASSERTED në diagnostikë; sandbox, Python 562 OK; kompilimi/MT5 UNVERIFIED; CAPTURE real i paprovuar; formula/klasifikimi/2-3 mbeten inpute
- [x] T013: ekzekutuesi i hyrjes LIMIT (vetëm transport/store fake; validim → leje e lidhur me planin → intent → një tentativë → lidhje e rezultatit → rikuperim/anulim pa ridërgim); Python 56 teste + 31 mutantë, kontrolle statike; kompilimi dhe MT5 UNVERIFIED; transporti real nuk ekzekutohet; i palidhur me sinjalin dhe me T011 (docs/T013-entry-executor.md)
- [x] T014: ura kandidat T004 → STpPlan (TP_BuildPlan): çdo zgjedhje e shprehur, UNSET bllokon, WAIT_RETURN vetëm si kandidat pending, RETURN_OBSERVED/invalid/historik/i ardhshëm nuk bëhen sinjal, ID të qëndrueshme; pa leje, pa urdhër; sandbox, kompilimi/MT5 UNVERIFIED (docs/T014-setup-plan-bridge.md)
- [x] T013 (e përcjellë): ekzekutuesi i hyrjes LIMIT — Codex 0/0 + 62 Python, MT5 EntryExecutorTest 170/0; transporti real i paprovuar
- [x] T015: porta e hyrjes (plani T014 + TP_CheckPermit + kontrolli i humbjes së brokerit + rezultati ditor T012 i detyrueshëm → leje vetëm për të njëjtin plan → EntryExecutor); bllokimi nuk thërret ekzekutuesin; pa regjistrim sinjali; sandbox me transport fake, kompilimi/MT5 UNVERIFIED (docs/T015-entry-gate.md)
- [x] T016: orkestruesi FAKE i korrigjuar: rikuperimi i të dhënave rinis baseline, M4ContextEqual krahason kontekstin e plotë, sizing-u përdor sondën e brokerit pas gjeometrisë. Codex: 128 Python OK, pesë kompilime 0 errors / 0 warnings, kontrollet statike me 23 kontrolle negative kalojnë; kontrollet e bazës Git u kapërcyen në eksportin lokal.
- [x] T016: pronari MT5 në fe53c06, XAUUSD.fx M15: EntryOrchestratorTest 97/0 (19:05:58), SetupPlanBridgeTest 77/0 (19:06:09), 15.10.2026. Evidencë e përcjellë; FAKE vetëm, pa provë live të EA-së dhe pa integrim T011.
- [x] T018: lexuesi i ekspozimit dhe korrigjimet u verifikuan në c009dbf: Codex dy kompilime 0/0, 115 teste Python të zinxhirit kalojnë; pronari MT5 15.10.2026 20:57:51.401, XAUUSD.fx M15: ExposureReaderTest 53 passed / 0 failed. Evidencë e përcjellë. Transporti mbetet FAKE; leximi real nga EA kërkon ende vëzhgim.
- [x] T017: ruajtje në disk për rekordet FAKE, namespace i veçuar dhe kyçje; transporti mbetet FAKE. Codex: 137 Python OK, pesë kompilime 0/0, kontrolle statike me 9 kontrolle negative të reja.
- [x] T017: pronari MT5 në e2d20db, XAUUSD.fx M15, 15.10.2026 20:38:57.500: EntryPersistenceTest 99 passed / 0 failed. Evidencë e përcjellë. Nuk pretendohet rikuperim i plotë i orkestruesit ose ekzekutim real.
- [x] T014 (e përcjellë): Codex 0/0 + 27 Python, MT5 SetupPlanBridgeTest 77/0

## T012 — kufijtë ditorë
- [x] DailyLimits (pronari MT5 604/0) dhe DailyPreviewGate (200/0); preview hipotetik DAILY_LOSS_LIMIT i konfirmuar nga pronari.
- [x] DailyHistory vetëm fakte: HistoryTest 196/0; diagnostiku real READY me 2 deal-e manuale të përjashtuara (pronari). complete=false, formula UNSET, balance_start UNKNOWN mbeten të hapura në atë shtresë.
- [x] Ura faktet → DL_Check (1761b51): Codex Python 12/0, MetaEditor 0/0, pronari MT5 323 passed/0 failed (15.10.2026 11:49:58). Moduli i pastër; jo i lidhur me lejen ose EA.
- [x] Burimi HISTORY_BRIDGE në preview v1.05 (DH_ReadAndBuild → DB_Check → rezultati final; MANUAL dhe DAILY_SNAPSHOT të ruajtura; preset vetëm-lexim). Sandbox: Python 19 + kontrolle statike; kompilimi i preview dhe ekzekutimi në demo — UNVERIFIED.
- [ ] Vendime klienti/pronari: formula e rezultatit; përkufizimi trade/win/loss/breakeven dhe pjesëmbyllje; 2 apo 3 trade; si merret balance_start; pronësia (mbyllje manuale, magic i përbashkët, pozicione nga dita e mëparshme); kush pohon complete; DST i brokerit.
- [ ] Teknike të hapura: reset në mesnatë, persistence/restart, lidhja me lejen. T012 NUK është i mbyllur.

