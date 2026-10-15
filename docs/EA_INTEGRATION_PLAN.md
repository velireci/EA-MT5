# Plani minimal i integrimit të EA-së së plotë (vetëm plan; pa kod)

Baza: 041c09a. T011/T012 të ngrira (pa zgjerime). Çdo gjë më poshtë është propozim pune, jo vendim klienti. Vendimet strategjike mbeten të hapura dhe nuk zgjidhen në heshtje: kur një hyrje mungon, EA bllokon (UNSET = BLOCK), siç punojnë politikat T012.

Dy fakte nga kodi që e formësojnë rendin:
- `M4Step` ka fazat WAIT_CONTEXT, WAIT_POLICY, WAIT_BREAK, WAIT_FVG, **WAIT_RETURN**, RETURN_OBSERVED. WAIT_RETURN = ekzistojnë FVG M15 kandidate që çmimi s'i ka rikthyer akoma; RETURN_OBSERVED = rikthimi ka ndodhur tashmë (fakt replay). Urdhri LIMIT i klientit ("fillimi i FVG") duhet të ekzistojë PARA kthimit, pra kandidati për urdhër është WAIT_RETURN; RETURN_OBSERVED nuk është kurrë shkas hyrjeje dhe s'përdoret si i tillë.
- Asnjë kod nuk vendos urdhër hyrjeje. `ExitTransportReal` dërgon vetëm mbyllje (DEAL); `XauUsdT011DemoOpenPosition` është mjet prove (hyrje tregu, e çaktivizuar, jo motor sinjalesh) dhe nuk përdoret.

## Zinxhiri: ripërdorimi, mungesa, natyra, kriteri

| # | Lidhja | Ripërdoret | Çfarë mungon konkretisht | Natyra | Kriteri që e mbyll |
|---|---|---|---|---|---|
| 1 | **H4 → kontekst** (drejtim, FVG H4, prekje, mbyllja e H4) | `H4Structure` (swing, FVG), `H4Bias` (`H3SetupContext` → `SH3SetupCtx`, besueshmëria), `H4TouchContext` (burimi T002 prekje), `M4ContextFromH3` (vetëm T003) | (a) një ushqyes live i H4 të mbyllura brenda EA-së (sot ekziston vetëm në EA vëzhguese të lidhura me grafikun dhe vizatues); (b) zgjedhja e burimit T002-prekje / T003-rikonfirmuar dhe politika kur kundërshtohen; (c) adapter i prekjes T002 → `SM4Context` jashtë observer EA | (a) teknike; **(b) vendim strategjik** (Q01–Q03; spec §4–5, §12) | Një `SM4Context` me etiketë burimi të shprehur, i prodhuar nga H4 live, i barabartë me replay-n offline në të njëjtat bare; politika e burimit e regjistruar në DECISIONS dhe e dhënë si input pa parazgjedhje |
| 2 | **Konfirmimi M15** (MSS, FVG M15) | `M4SetContext`, `M4Step`, `M4ReplayTimeline`, `M4SelectSwingProposal` (vetëm propozim), kandidatët `SM4Candidate` | (a) zgjedhja e swing-ut M15 për MSS; (b) kohëzimi i FVG (A/B/C, forming/closed); (c) zgjedhja mes disa FVG M15; (d) identiteti i setup-it dhe i kandidatit që mbijeton restart-in | **(a)(b)(c) vendime strategjike** (Q04, spec §6; sot vetëm propozime T004); (d) teknike por varet nga (c) | Vendimet (a)–(c) regjistruar; një `SSetupCandidate` live (WAIT_RETURN, kandidati i zgjedhur, niveli i thyer, kohët e njohura) i barabartë me replay; asnjë përdorim i RETURN_OBSERVED si shkas |
| 3 | **Hyrja / SL / TP** | `SM4Candidate.lower/upper`, `SM4Level.price`, `TG_Compute` (normalizim, 2R, rasti TP<2R sipas N6) | (a) skaji i FVG si hyrje: teksti i klientit thotë "fillimi", skaji BUY=sipër / SELL=poshtë është interpretim vizual (Codex); (b) SL = ekstremi i strukturës së thyer: çfarë përbën "gjithë strukturën" dhe buffer/offset; (c) algoritmi i targetit (likuiditet i jashtëm/radhës); (d) njësia e kufirit 50 të SL | **(a) ka tekst klienti, kërkon konfirmim të interpretimit; (b)(c)(d) vendime strategjike** (spec §6–7, Q05) | Një funksion pur `(setup, kandidat, nivel, hartë H4) → (E, S, T, has_target)` me arsye refuzimi dhe pa parazgjedhje të fshehta, me fixtures të shkruara me dorë; çdo UNSET bllokon |
| 4 | **TradePlanning** | `TP_BuildPlan` → `STpPlan` (përdor `TG_Compute`), `SymbolSnapshot`, leximet e brokerit nga T008 | (a) `signal_id`/`setup_id` të qëndrueshëm (një hyrje për sinjal; ri-hyrja e hapur); (b) baza e 1% risk (buxheti sot është input `InpRiskBudget`, jo i derivuar nga llogaria); (c) kostot në R | (a) teknike pas #2(d); **(b)(c) vendime strategjike** (Q08, C3/C4) | `STpPlan` OK nga hyrje reale (kuota/simboli i brokerit), ose refuzim me arsye; buxheti i riskut vjen nga një politikë e shprehur |
| 5 | **Kontrollet e lejes** | `TP_CheckPermit`/`TP_Authorize` (`STpSnapshot`, `STpLimits`), `SessionPolicy`, `NewsSpreadFilters`, `BrokerLossCheck`, `DailyHistory`→`DailyBridge`→`DailyLimits`, `DailyBalanceStore` (LOAD) | (a) ndërtuesi live i `STpSnapshot` nga llogaria (pozicione/pending të EA-së sipas magic, risku ekzistues, tregti sot) — sot preview e merr nga inpute; (b) politikat: formula e rezultatit, klasifikimi, 2 apo 3 trade, rezervimi për pending, veprimi në lajme/fund seance, pragu i spread-it; (c) bilanci i fillimit të ditës: CAPTURE real i paprovuar | (a) teknike; **(b) vendime strategjike/pronari**; (c) provë reale e mbetur | `STpPermit.allow` nga burime reale në demo, me çdo politikë të pazgjidhur duke bllokuar me arsye konkrete; CAPTURE real provuar nga pronari |
| 6 | **Ekzekutimi i hyrjes** (urdhër LIMIT) | Modeli: sedra abstrakte + fake + real (`ExitTransport*`), `ExitInstanceLock`, `ESC_*`/`ESF_*` (rekord me CRC, shkrim/lexim), modeli intent-para-dërgimit (`DemoOpenGuard`), `TP_CancelDecision` (vendimi i anulimit, pa veprim) | **Gjithçka e hyrjes mungon**: dërgim `TRADE_ACTION_PENDING` (limit, SL, TP, magic, skadim), `OrderCheck`, intent i ruajtur para dërgimit, një dërgim për `signal_id`, harta urdhër→deal→pozicion, anulimi i pending sipas ngjarjeve, rikuperimi pas restart-it, kufizimet e brokerit (stops level, freeze, filling, expiry) | Kodi **teknik**; skadimi/ri-hyrja/cooldown janë **vendime strategjike** (Q09) dhe hyjnë si input UNSET=BLOCK | Ekzekutues hyrjeje me transport fake: zero dërgime për çdo pasiguri, një dërgim për sinjal, rikuperim pas restart-it pa dërgim të dytë, testet Python + MQL5 si te T011; pastaj një provë demo e autorizuar nga pronari |
| 7 | **Menaxhimi T011** | `ETD_Register/Init/Tick/Timer`, `EX_Register`/`EX_Process`, hapi 80/20 në 2R, `ExitInstanceLock` | (a) regjistrim automatik pas mbushjes (sot regjistrimi është veprim i shprehur i veçantë dhe SL fillestar jepet nga pronari; ky rregull duhet të ndryshohet me autorizim të pronarit që SL të vijë nga plani i ruajtur); (b) ndarja nga pozicionet manuale/EA-të e tjera (magic; hedging); (c) +0.2%/break-even, TP=2R si TP përfundimtar | (a)(b) teknike por **kërkojnë autorizim pronari** (ndryshojnë një rregull të vendosur); **(c) vendim strategjik i hapur** | Pas një mbushjeje fake: rekord IDLE R_GEOM me S nga plani, tick në 2R dërgon një herë; prova SELL demo e automatikes e përsëritur dhe e përfunduar (ende INCONCLUSIVE sot) |

Kufij ndër-lidhës (jo hapa të veçantë): një orkestrator OnInit/OnTick/OnTimer me bare të reja dhe ruajtje të gjendjes së setup-it nëpër restart; një bërthamë e pastër e pavarur nga vizatuesit; vlerësimi në Strategy Tester (spec §14) kërkon politikë ore për T012, sepse preview/store sot refuzojnë testerin (`TimeGMT`).

## Rendi i punës (i shkurtër)

1. **Ekzekutuesi i hyrjes LIMIT me transport fake** (lidhja 6) — i pavarur nga çdo vendim strategjik.
2. Në paralel, pa bllokuar #1, një paketë e vetme vendimesh për pronarin/klientin, vetëm ato që bllokojnë #2–#4: burimi i kontekstit (D1), swing M15 (D2), FVG: zgjedhja dhe kohëzimi (D3), SL ekstrem + buffer (D4), targeti (D5), skadimi/ri-hyrja (D6), baza e riskut (D7).
3. Bërthama e setup-it live (lidhjet 1–2) pas D1–D3; funksioni E/S/T (lidhja 3) pas D4–D5.
4. Ndërtuesi live i `STpSnapshot` + CAPTURE real të provuar (lidhja 5).
5. Regjistrimi automatik pas mbushjes dhe orkestratori (lidhja 7 + kufijtë).
6. Prova demo e plotë e autorizuar nga pronari (një setup real; automatikja SELL e pambyllur si kriter).

## Hapi i parë i propozuar: ekzekutuesi i hyrjes LIMIT (fake transport)

Pse ky: është kodi më i madh që mungon plotësisht, nuk varet nga asnjë vendim strategjik (merr një `STpPlan` + `STpPermit` të dhënë), ripërdor modelin e provuar të T011 (seam + fake + intent + lock + rikuperim) dhe është i nevojshëm sido që të zgjidhen D1–D7. Nuk është modul diagnostik.

Skica minimale (pa kod ende): sedra e re `CEntryTransport` (nuk prek `ExitTransport`); `EN_Place(plan, permit, cfg)` që refuzon pa `permit.allow`, pa skadim të shprehur, me kuotë/stops level të pavlefshme; intent i ruajtur para dërgimit; një dërgim për `signal_id`; çdo pasiguri → zero dërgime dhe gjendje RECOVERY; `EN_Reconcile` urdhër→pozicion; `EN_Cancel` vetëm nga `TP_CancelDecision` dhe vetëm për pending-et e EA-së (magic); pa menaxhim të pozicionit (kjo mbetet T011), pa auto-hapje, pa adoptim manual, i çaktivizuar si parazgjedhje, pa transport real të përdorur nga testet.

Kriteri i përfundimit: Python + MQL5 me fake: (i) zero dërgime pa permit/skadim/intent të ruajtur; (ii) një dërgim për sinjal, përsëritja nuk dërgon; (iii) rikuperimi pas restart-it në çdo pikë të dështimit nuk dërgon të dytin; (iv) anulimi prek vetëm pending-et e EA-së; (v) skedarët e rinj kompilohen 0/0 te Codex dhe testet kalojnë në MT5 të pronarit; mbetet UNVERIFIED çdo semantikë e `OrderSend` pending derisa pronari të autorizojë një provë demo.

Pyetje për pronarin vetëm për këtë hap: të autorizohet ndërtimi i ekzekutuesit të hyrjes (jo aktivizimi) dhe të konfirmohet që regjistrimi automatik pas mbushjes (lidhja 7a) do të diskutohet veçmas më vonë.

## Gjendja e integrimit (15.10.2026, mbi 21f7ade) dhe lista e vetme e vendimeve që bllokojnë

**Ndërtuar dhe në EA-në `XauUsdEntryOrchestrator.mq5` (transport FAKE i fiksuar):** H4/M15 → SetupPlanBridge → EntryGate → EntryExecutor (T014–T016), rekordet e hyrjeve në disk (T017), ekspozimi i llogarisë vetëm-lexim (T018), cikli i jetës (T019): indeks + flamur ndalese të ruajtur, reconcile në nisje dhe në çdo timer, anulim i pending-it të provuar vetëm për ngjarje të dalë E të aktivizuar nga pronari, mbushje e raportuar FILLED_UNMANAGED. Baseline rindërtohet në çdo nisje.

**Lidhja mbushje → T011 (15.10.2026, mbi f349aae):** mbushja raportohet tani me inputet e sakta të skriptit të regjistrimit eksplicit T011 (`FILLED_UNMANAGED ... T011_REGISTRATION_INPUTS ...`), me diagnostikë vetëm për gjeometrinë e planit (`PLANNED_GEOMETRY`) dhe `LIVE_CHECK_REQUIRED`; çmimi real i mbushjes mund ta ndryshojë nivelin 2R; raporti është at-least-once dhe nuk shkruan asgjë të T011. Regjistrimi AUTOMATIK nuk është ndërtuar: kërkon ndryshimet K1–K8 më poshtë dhe vendimet 17–21 të listës. Transporti real mbetet i çaktivizuar. Tiketat FAKE nuk lidhen kurrë me pozicione reale.

**Vendimet që bllokojnë (çdo rresht = një input që sot është UNSET dhe bllokon; asnjë nuk është zgjedhur nga Claude):**

| # | Vendimi | Input / vendi | Pyetja |
|---|---|---|---|
| 1 | Burimi i kontekstit H4 dhe politika kur kundërshtohen | `InpContextSource` | Q01–Q03 |
| 2 | Swing-u M15 për MSS | `InpM15Level` | Q04 |
| 3 | Kohëzimi i FVG M15 (forming/mbyllur) | `InpFvgTiming` | Q04 |
| 4 | Cili FVG kur ka disa | `InpCandidate` | Q04 |
| 5 | Skaji i FVG si hyrje (afër/larg) | `InpEntryEdge` | Q05 |
| 6 | SL: ekstremi i strukturës së thyer + buffer | `InpSlRule`, `InpSlBuffer` | Q05 |
| 7 | Targeti përtej minimumit 2R | `InpTargetRule` | Q05, Q07 |
| 8 | Baza e 1% (balancë/equity/fillim dite), kostot, kapaku i lotit | `InpRiskBudget`, `InpLotCap` | Q08 |
| 9 | Kufijtë: 2 apo 3 trade, kufiri i kombinuar i riskut, pozicione maksimale | `InpMaxPositions`, `InpMaxTrades`, `InpCombinedRiskCap` | Q08 |
| 10 | A rezervon një pending pozicion; a hyn risku i tij në riskun ekzistues | `InpPendingPolicy`, `InpPendingRiskPolicy` | Q11 |
| 11 | Orari i seancës, mbyllja e së Premtes, veprimi në fund të orarit | `InpSessionClock` + minutat | Q11 |
| 12 | Dritarja e lajmeve dhe veprimi mbi pending/pozicion | `InpNewsCalendar` | Q11 |
| 13 | Pragu i spread-it dhe refuzimi | `InpMaxSpreadPoints` | Q09 |
| 14 | Rezultati ditor: formula, klasifikimi trade/win/loss, humbje radhazi, rivendosja | `InpDailyResultFormula`, `InpDailyClassification`, `InpTradesToday`, `InpDailyWins`, `InpDailyConsecutiveLosses` | Q10 |
| 15 | Skadimi i pending-it, ri-hyrja, cooldown, sinjal i kundërt | `InpExpiryMode`, `InpExpirySeconds` (+ asgjë tjetër ende) | Q09 |
| 16 | Cilat ngjarje anulojnë pending-in: fund seance, lajm, kufi ditor; si dhe zhvlerësimi i FVG / ndryshimi i drejtimit (nuk ka ende ngjarje) | `InpCancelOnSessionEnd`, `InpCancelOnNewsBlock`, `InpCancelOnDailyLimit` | Q09, Q11 |
| 17 | Menaxhimi pas mbushjes: 80% në 2R kundrejt niveleve, kuptimi i +0.2%/break-even, TP | T011 (jashtë EA-së së hyrjes) | Q07 |
| 18 | **TP dhe 2R:** rregulli i targetit `NONE_2R_MINIMUM` jep TP = nivelit 2R (TG_Compute); T011 refuzon TP = 2R të llogaritur nga çmimi REAL i hapjes. Barazia me 2R të planit nuk provon barazi pas mbushjes; kërkohet kontroll live. Ose një algoritëm targeti PËRTEJ 2R (vendim 7), ose rregull T011 për 20% e mbetur kur TP = 2R | `InpTargetRule` / T011 | Q05, Q07 |
| 19 | Marrëveshja K1–K3: burimi i SL-së fillestare (rekordi i planit në vend të pronarit), regjistruesi (orkestruesi, jo skripti), autorizimi i qëndrueshëm (fraza si input i EA-së) | kontrata T011 e regjistrimit | Q07 |
| 20 | K7: niveli 2R i menaxhuar del nga çmimi REAL i hapjes (mund të jetë më i mirë se limiti i planit); cili qeveris: plani apo hapja reale | T011 R_GEOM | Q07 |
| 21 | K8: çfarë ndodh kur regjistrimi refuzohet ose mungon (pozicion pa menaxhim): vetëm alarm, apo ndalim i hyrjeve të reja | politikë | Q07, Q11 |
| 22 | Aktivizimi i transportit real / prova demo me tregti | vendim i veçantë i pronarit | - |

Pa 1–9 EA-ja nuk prodhon plan; pa 10–14 porta bllokon; 15 dhe 16 nuk ndalojnë hyrjen, por pa to një pending mbetet pa skadim dhe pa anulim automatik; 17–22 janë të ndara nga hyrja (18 është vendimi që bllokon edhe regjistrimin automatik).

## Mbushje → T011: çfarë ndryshon saktësisht (nuk është ndërtuar; pret vendimet 17–21)

**Kontrata sot (e paprekur):** regjistrimi është skripti eksplicit `XauUsdT011ExitRegister.mq5` (çaktivizuar si parazgjedhje; EA-ja e menaxhimit nuk regjistron kurrë). Pronari ASSERTON SL-në fillestare; `EX_Register` e pranon vetëm ndërsa SL-ja LIVE e pozicionit është e barabartë me të; çmimi i hapjes lexohet një herë; pozicioni gjendet sipas POSITION_IDENTIFIER, magic = i konfiguruari (>0), simbol, drejtim, volum = volumi i planit; llogari hedging; për çdo transport "real" kërkohet fraza e autorizimit + llogari demo; rekordi nuk mbishkruhet kurrë; një kyçje për pozicion (`EL_Key`, vetëm brenda një terminali); EA-ja e menaxhimit e armos vetëm pas `ETD_PositionProof`.

**Ndryshimet që do të kërkonte regjistrimi automatik nga orkestruesi:**
- **K1 – burimi i SL-së:** SL-ja e asertuar vjen nga rekordi i ekzekutuesit (i shkruar me CRC para dërgimit), jo nga pronari në momentin e regjistrimit. Prova e barazisë me SL-në LIVE mbetet e detyrueshme (nuk zbutet).
- **K2 – kush regjistron:** orkestruesi thërret `ETD_Register` me një `CExitTransport` vetëm-lexim (ReadAccount/ReadSymbol/FindPosition real; Send/PreCheck të refuzuar dhe të numëruar), që raporton `IsReal()=true` që porta e autorizimit dhe kontrolli i llogarisë demo të mbeten; rregulli "vetëm skripti regjistron" ndryshon.
- **K3 – autorizimi:** fraza `EX_AUTH_PHRASE` bëhet input i qëndrueshëm i orkestruesit në vend të shkrimit për çdo regjistrim.
- **K4 – qëndrueshmëria (teknike, rrjedh nga K1–K3):** hyrja e indeksit të lifecycle mbahet derisa rekordi T011 të lexohet mbrapsht dhe të përputhet fushë për fushë (regjistrim idempotent: një rekord ekzistues pranohet vetëm nëse përputhet, nuk mbishkruhet); prova e ndërprerjes: mbushja e ruajtur pa regjistrim rimerret në nisje (si raporti sot).
- **K5 – konkurrenca (teknike):** rendi i kyçjeve indeks → pozicion; i njëjti kufizim "vetëm një terminal"; EA-ja e menaxhimit duhet të ekzekutohet në grafik veçmas.
- **K6 – TP/2R:** shih vendimin 18 (sot çdo plan `NONE_2R_MINIMUM` do të dështonte në regjistrim).
- **K7 – çmimi i hapjes:** T011 e nxjerr R_GEOM nga çmimi real i hapjes; plani e llogariti nga limiti.
- **K8 – dështimi i regjistrimit:** pozicioni mbetet me SL/TP të brokerit por pa 80/20; politika e reagimit është vendim (vendimi 21).

Deri te vendimet: mbushja raportohet me inputet e sakta dhe regjistrimi bëhet nga pronari me skriptin eksplicit; asgjë tjetër nuk ndryshon.


**Codex correction, 15.10.2026 (on 6ef9533):** planned TP/2R diagnostics require live verification, without definitive T011 refusal. BUY/SELL improved-fill regressions failed before the correction. Targeted Python: 74 passed. Lifecycle test and orchestrator EA: each compiled with 0 errors / 0 warnings. Lifecycle static checks and the new negative control passed; Git-base comparisons skipped in this source export. Owner MT5 rerun pending; automatic T011 registration remains unimplemented.
