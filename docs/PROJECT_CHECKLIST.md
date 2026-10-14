# Checklist qendrore e projektit

Përditësuar më 14.10.2026. Pamje e evidencës së njohur, jo kontroll i ri i GitHub. Nuk matet përqindja nga numri i testeve. Programuar ≠ testuar plotësisht ≠ validuar nga klienti.

## Ku jemi

H4 → M15 → FVG → kthim është ndërtuar dhe vëzhguar në replay. T005 u dorëzua te 67f02e5; Codex Python 39/0, MetaEditor 0/0; pronari MT5 572/0. T006 (sizing i pastër me buxhet risku të dhënë) te 559794a: Codex Python 47/0 dhe MetaEditor 0/0; pronari MT5 14.10.2026 18:42:14: 710 passed, 0 failed (të përcjella, jo ekzekutim i Claude). Moduli i pastër është verifikuar; integrimi me brokerin jo. T007 (plan i pastër, kontrolle lejeje dhe kërkesë anulimi, pa urdhra) është programuar me teste Python 34/0 të ekzekutuara nga Claude dhe kontrolle statike; kompilimi MetaEditor dhe MT5 janë UNVERIFIED dhe moduli nuk është i lidhur. Robot që hap dhe menaxhon urdhra: ende jo.

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

### 5. Menaxhimi 80% / 20% — PA NISUR
- [ ] Mbyllja e 80% në 2R dhe kufijtë e volumit
- [ ] Pajtimi i entry plus kosto me +0.2%
- [ ] Mbetja deri te TP/SL, pa trailing

### 6. Kufijtë ditorë dhe ekspozimi — NISUR (vetëm kontrolli i pastër T007; kufijtë vijnë si numra ose UNSET)
- [x] Kontrolli i pozicioneve, trade/ditë dhe riskut të kombinuar me kufij të furnizuar; kufi UNSET bllokon (POLICY_UNSET); kufijtë e testit (3, 5, 5000) janë arbitrarë, jo të klientit (Python)
- [ ] Pajtimi i kufirit 2 apo 3 trade
- [ ] Ndalimi pas fitoreje/humbjeve dhe kufiri ditor
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
- [ ] Pronari: T008_BrokerLossTest në MT5.
- [ ] Pronari: EA default INPUT_UNSET dhe preview me kandidat manual në broker.
Status: integrim vetëm për kontroll, jo sinjal ose urdhër; risku dhe ekspozimi i jashtëm nuk lexohen automatikisht.
