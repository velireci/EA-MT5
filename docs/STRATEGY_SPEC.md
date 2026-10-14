# Strategjia e klientit — referenca qendrore

Përditësuar: 14 tetor 2026. Versioni 1. Klienti: dorëzimi XAU-20261006-E27N93.

Ky dokument bashkon informacionin e disponueshëm të klientit. Nuk është deklaratë se strategjia është plotësisht e formalizuar, implementuar ose validuar. Një hollësi që mungon mbetet e hapur; nuk plotësohet nga emri i një koncepti apo nga rezultati i një testi.

## 1. Si lexohet dhe përditësohet

- **K — Klienti:** tekst origjinal ose sqarim i klientit i përcjellë nga pronari; burimi shënohet.
- **I — Interpretim:** leximi ynë i tekstit/fotove. Nuk barazohet me konfirmim.
- **P — Propozim teknik:** mënyrë mekanike e zgjedhur për prototip, ende pa validim klienti.
- **H — Hapur/konflikt:** informacion që mungon ose dy pohime që duhen pajtuar.
- Përpara një pyetjeje të re: kërko rregullin këtu, pastaj tekstin origjinal dhe sqarimet më të reja. Fusha “?” në pyetësor nuk anulon një përgjigje të qartë me tekst.
- Sqarimi i ri shprehimor mund të zëvendësojë një përgjigje më të vjetër. Regjistro çfarë zëvendëson. Në konflikt të pazgjidhur mos zgjidh në heshtje.
- Teksti i klientit ka përparësi ndaj interpretimit të vizatimeve. Çmimet, datat dhe numri i BOS në një shembull nuk janë parametra të robotit.
- Ky dokument përmban kërkesat; docs/STATE.md përmban progresin; raportet përmbajnë provat; task-et përmbajnë detajet e implementimit. Një test që kalon nuk krijon rregull klienti.

## 2. Burimet dhe kufijtë

**B1:** përgjigjet origjinale inputs/client-E27N93/pergjigjet.json, dorëzuar 06.10.2026; në këtë workspace work/client-E27N93/pergjigjet.json. Fushat state.answers, state.examples dhe shënimet e fotove janë burime parësore. Lista automatike analysis.clarifyWithClient nuk është vendim klienti.

**B2:** specifikimi.txt nga i njëjti dorëzim: përmbledhje e përgjigjeve, fakte paraprake dhe kërkesa zhvilluesi. Nuk është përgjigje e dytë e pavarur. Seksionet “developer requirements” dhe “assumptions” nuk ngrihen në rregulla klienti.

**B3:** tri fotot origjinale: shembulli-1-sell-win.jpg, shembulli-2-sell-loss.jpg, shembulli-3-no-entry.jpg. U inspektuan në kontrollin e 14.10.2026. Vizatime, jo histori urdhrash/fill-esh.

**B4:** sqarimet e klientit të përcjella nga pronari në bisedë, të regjistruara në docs/DECISIONS.md: 07.10 dhe 13.10, S1–S5, E1–E6, N1–N7. Disa ruhen si përmbledhje e përcjellë, jo si citim origjinal. Datat e videove/analizave nuk duhen ngatërruar me kohën e candle-ve.

**B5:** kontrolli T005 i 14.10.2026, kontrolli i burimeve i regjistruar në historinë e këtij dokumenti, krahasoi B1–B3 me planin T005 te 5447ef3. Nuk u bë transkriptim i ri audio/video. Videot e përmendura në bisedë nuk pretendohet se janë analizuar plotësisht në këtë dokument.

## 3. Instrumenti dhe rrjedha e përgjithshme

**K, B1/B2:** robot automatik MT5/MQL5 për arin, brokeri i klientit Tauro, simboli i deklaruar XAUUSD.r, llogari USD. BUY dhe SELL; klienti thotë pasqyrim mes tyre. Synimi përfundimtar përfshin hapje, menaxhim dhe mbyllje, por aktivizimi i urdhrave është vendim i veçantë i pronarit.

Rrjedha e deklaruar, duke bashkuar sqarimet më të reja:

**Drejtimi H4 → zonë kryesore FVG H4 / IRL → prekje → mbyllja e H4 prekëse → thyerje strukture M15 → FVG M15 → urdhër limit te fillimi i saj → target likuiditeti / minimum 2R → menaxhimi 80/20.**

Pas wick-ut/marrjes së likuiditetit, rruga e rikonfirmimit kërkon FVG H4 të RE pas ngjarjes, pastaj të njëjtën rrjedhë prekje/mbyllje/M15. Kjo nuk e bën çdo FVG ekzistuese automatikisht të vlefshme.

## 4. Drejtimi, struktura dhe likuiditeti H4

**K, B4 N1:** rritës = HH dhe HL; rënës = LH dhe LL. Teksti i vjetër i B1 për H1/H4 dhe “HH dhe LH” nuk përdoret për të anuluar sqarimin më të ri: konteksti është H4 sipas vendimit të regjistruar më 07.10.

**K, B4 N2/N3:** struktura aktuale dhe likuiditeti historik janë të ndryshme. Vijat e kuqe shënojnë maja/funde/nivele. Nivelet e vjetra të paprekura mund të shërbejnë si zona likuiditeti pas disa ditësh; kjo nuk do të thotë se mbajnë domosdoshmërisht drejtimin e sotëm.

**K, B4 S1/S2:** kërkohet thyerja e nivelit strukturor përkatës me trup; wick-u i vetëm nuk konfirmon ndryshim dhe mund të jetë marrje likuiditeti. “Niveli i parë” në figurën e klientit ishte i mjaftueshëm në atë shembull; nuk përkthehet automatikisht si swing-u më i afërt.

**H/P:** përzgjedhja algoritmike e swing-eve strukturorë kundrejt atyre lokalë, përparësia e drejtimeve në konflikt dhe kriteri i saktë trup/close. Close rreptësisht përtej nivelit është interpretimi teknik aktual. Fractal 2/2, ratchet-i dhe bias-i me kujtesë nuk janë konfirmime klienti.

**K, B1:** nuk tregton në range. E përshkruan si të dallueshme me sy; algoritmi objektiv mbetet H.

## 5. FVG H4 dhe rikonfirmimi

**K, B4 07.10/N4:** vetëm setup-e në drejtimin e trendit, IRL → ERL. IRL këtu është FVG H4, jo çmimi i hyrjes. Zona më e afërt në rrugën e kthimit merret e para; nëse nuk ka konfirmim, çmimi mund të arrijë zonën tjetër.

**K, B4 S5/N4:** prekja mund të jetë me wick. Pritet mbyllja e candle-s H4 që preku zonën; pastaj kërkohet thyerje e re M15. M15 e mëparshme nuk autorizohet nga një prekje e mëvonshme.

**K, B4 S3/S4:** për SELL, pas wick-ut mbi nivelin strukturor ndalen hyrjet e REJA të setup-it të mëparshëm dhe pritet rikonfirmim. Duhet FVG H4 rënëse e RE pas wick-ut; riprekja e një FVG-je të vjetër nuk mjafton. Ky pohim nuk urdhëron mbylljen e pozicioneve ekzistuese.

**K, B4 E1–E6:** shembulli BUY mbështet sekuencën marrje likuiditeti → FVG e re H4 → kthim/prekje → thyerje M15. Targeti në atë shembull ishte HH i fundit/vija e kuqe e sipërme. Nuk krijon një numër të detyrueshëm BOS ose algoritëm universal targeti.

**H/P:** përkufizimi numerik i gap-it, renditja e zonave në raste të barabarta, candle A/B/C kundrejt wick-ut, jetëgjatësia, revokimi, ripërdorimi dhe identiteti i setup-it. Rregullat T002/T003 dhe OD1–OD6 të T004 janë propozime të dokumentuara, jo përgjigje klienti.

## 6. Konfirmimi M15 dhe hyrja

**K, B4 N5:** “Beje qe te thyhet vetem ne m15 qe mos ta ngaterrojm / Duke qen se dhe fvg e presim po ne m15”. M5 hiqet nga konfirmimi, jo kusht shtesë.

**K, B1 own_words:** “Entry eshte te fillimi i FVG ne M15”. Urdhri është LIMIT. Pritet kthimi te FVG M15 pas thyerjes së strukturës/MSS.

**I, B3:** hyrjet e vizatuara mbështesin skajin e parë në kthim: SELL skaji i poshtëm, BUY skaji i sipërm. Kjo është interpretim vizual i mbështetur; jo konfirmim numerik i OHLC-ve/offset-it.

**K, B1 shembulli 3:** nëse çmimi afrohet por nuk prek FVG-në/çmimin e pritur, tregtia nuk aktivizohet. Kjo nuk do të thotë domosdoshmërisht se setup-i ishte i pavlefshëm ose se urdhri nuk duhej vendosur.

**K, B1:** një hyrje për sinjal; “sinjal i ri” zgjedhur si çdo candle e re që plotëson kushtet. Candle e sinjalit është shënuar forming në pyetësor.

**H/P:** cilin swing M15 përdor MSS; cila FVG zgjidhet kur ka disa; formimi i A/B/C kundrejt BOS; çfarë njihet intrabar. Prototipi me close dhe A në/pas BOS nuk e mbyll automatikisht pyetjen forming/closed. RETURN_OBSERVED është fakt replay, jo urdhër hyrjeje.

## 7. Stop Loss, targeti dhe 2R

**K, B1 own_words/pd_level:** SELL: SL te pika më e lartë e strukturës së thyer M15. BUY: te pika më e ulët e strukturës së thyer M15. Fusha sl_method='?' nuk anulon këtë përgjigje.

**H:** identifikimi mekanik i gjithë strukturës së thyer; buffer ose offset. Mos supozo se niveli që u thye është gjithmonë vetë çmimi i SL-së. Mos e quaj buffer-in zero të konfirmuar.

**K, B1:** targeti është likuiditeti i jashtëm/i radhës, i përshkruar edhe si struktura e radhës. **H:** zgjedhja universale mes disa niveleve dhe përditësimi i targetit.

**K, B4 N6:** “Po ne raste kur target eshte me pak se 2R, minimumi do vendoset 2R”. Pra nuk e anashkalojmë trade-in vetëm për target nën 2R; minimumi mund të bjerë përtej ERL fillestare. Një target më i largët nuk shkurtohet nga ky minimum.

**I/H, B2 assumptions:** 1R si distanca fillestare hyrje–SL është supozim i shprehur, jo përkufizim i ri klienti. Kostot, çmimi limit kundrejt fill-it dhe rrumbullakimi duhen ndarë shprehimisht.

**K, B1:** kufi i distancës SL 50; fusha e eksportit e quan 50 USD lëvizje të çmimit të arit; trade-i anashkalohet kur SL tepër i madh. **H:** njësia duhet verifikuar, jo ngatërruar me 50 USD humbje llogarie.

## 8. Menaxhimi pas hyrjes

**K, B1:** në 2R mbyllet 80% e volumit FILLESTAR. 20% e mbetur vazhdon deri te TP ose SL. Pa trailing. Dalja e pjesshme numërohet si një trade.

**K, B1 mg_priority:** fillimisht mbyllja 80%, pastaj zhvendosja e SL-së, pastaj pritja për TP/SL.

**H — konflikt:** zgjedhja e strukturuar thotë SL te hyrja plus kostot; teksti thotë “stop loss tek +0.2%”. Baza dhe kuptimi i përqindjes nuk janë dhënë. Nuk zgjidhet në heshtje.

**H:** kur TP përfundimtar është vetë 2R, si bashkëvepron dalja 80% me mbylljen e mbetjes; rrumbullakimi i volumit; gjendja pas fill-eve të pjesshme. Vijat e ndërmjetme të fotove nuk identifikohen automatikisht si 2R.

## 9. Risku dhe kufijtë ditorë

| Rregulli | Burimi/statusi | Çfarë mbetet hapur |
|---|---|---|
| 1% risk për trade | K, fakt paraprak i konfirmuar në B2 | baza/metoda/kostot e sizing-ut; fusha size_method është ? |
| Maksimumi 2 pozicione njëkohësisht | K, B1 | trajtimi i pending dhe ekspozimit manual |
| Maksimumi 2% risk i kombinuar | K, B1 | llogaritja dhe rezervimi për pending |
| Kufiri 10 lote për trade | K, B1 | kufijtë realë të simbolit lexohen nga brokeri |
| Në konflikt madhësie/risku/brokeri: skip | K, B1 | mos e ngatërro me propozim uljeje automatike |
| Maksimumi 2 trade në ditë në përgjigjet e reja; 3 në faktet paraprake të konfirmuara | H, konflikt B1/B2 | cili kufi ka përparësi |
| Pas një fitoreje ndalon për ditën | K, B1 | klasifikimi i trade-it me dalje të pjesshme/kosto |
| Ndalon pas 2 humbjeve radhazi | K, B1 | në max 2 trade kufiri nuk sjell ndalim më të hershëm; nuk është kundërthënie më vete |
| Breakeven as fitore as humbje | K, B1 | kriteri financiar me kosto dhe pjesshme |
| Humbja ditore 2% e balance në fillim të ditës | K, B1 | mënyra e saktë e kontabilizimit/rikuperimit |
| Vetëm rezultatet e mbyllura, vetëm roboti; pa floating | K, B1 | nuk është garanci kufizimi absolut të humbjes së llogarisë |
| Në limit ditor: ndal hyrjet dhe anulo pending | K, B1 | nuk urdhëron mbylljen e pozicioneve ekzistuese |
| Reset në mesnatë, Shqipëri | K, B1 | implementim Europe/Tirane/DST |

Kapitali i planifikuar dhe lloji i llogarisë nuk janë plotësuar. Klienti tregton edhe manualisht. Mos ndrysho ose numëro tregti jashtë pronësisë së EA pa vendim të shprehur; kontrollo kufizimet e netting/hedging.

## 10. Orari, lajmet dhe urdhrat në pritje

**K, B1:** e hënë–e premte, 00:00–20:30 sipas orës së Shqipërisë, me ndryshimin sezonal të orës. Të premten kërkohet mbyllje në 21:00 dhe anulim pending.

**K, B1:** shmang lajmet USD me ndikim të lartë, 30 minuta para dhe 30 minuta pas. **H:** çfarë bëhet me pozicionet e hapura para lajmeve dhe në fundin e zakonshëm të seancës.

**K, B1:** pending anulohet në ndryshim drejtimi, sinjal të kundërt, fund seance dhe përpara lajmit të shmangur.

**H:** skadimi sipas candle-ve/kohës; cooldown; ri-hyrja në të njëjtin setup; sinjali i kundërt kur ka pozicion të hapur; identiteti i sinjalit në restart.

**K, B1:** zhvilluesi mund të zgjedhë prag spread për XAUUSD.r. **H:** veprimi pas bllokimit nga spread-i. Vlera kërkon matje, jo hamendje.

**K, B1:** njoftime push në telefon. Detajet e njoftimeve operative janë implementim, jo sinjal strategjie.

## 11. Shembujt dhe çfarë provojnë

| Shembulli | Informacioni i klientit | Kufiri |
|---|---|---|
| SELL fitues, B3 foto 1 | MSS M15, FVG, kthim për hyrje, SL sipër, profit te likuiditeti | nuk provon përzgjedhjen H4, fill-in ose kuptimin e çdo vije të ndërmjetme |
| SELL humbës, B3 foto 2 | kushtet u plotësuan, u prek SL, pastaj çmimi vazhdoi në drejtimin e pritur | mos zhvendos SL fillestare me informacionin e spike-ut të mëvonshëm; data e shkruar dhe grafiku duhen dalluar |
| BUY i paaktivizuar, B3 foto 3 | çmimi nuk arriti pikën e pritur/nuk preku FVG | mos e klasifiko si sinjal të pavlefshëm vetëm se nuk pati fill |
| BUY H4, B4 E1–E6 | likuiditet, FVG e re, kthim dhe konfirmim M15; target HH i fundit në shembull | jo numër universal BOS ose target universal |
| Dy wick-e të rrethuara, B4 N3 | klienti i quan marrje likuiditeti me vazhdim të drejtimit të mëparshëm | vazhdimi i mëvonshëm nuk mund të përdoret si informacion i disponueshëm më herët |

Grafikët TradingView TVC:GOLD, standard candles, ora e deklaruar Shqipëri. Të dhënat e Tauro/MetaQuotes nuk deklarohen identike me TradingView pa verifikim.

## 12. Prototipet tona — jo rregulla klienti

- T002: swing 2/2, drejtimi nga swing-et, intervali, klasifikimi/gjendjet FVG, renditja, ERL taken.
- T003: niveli mbrojtës, ratchet, bias me kujtesë, HOLD/SWEEP_WAIT/RECONFIRMED, politika e FVG-ve dhe besueshmëria A/B.
- T004: latest-unbroken-fractal M15, close rreptësisht përtej, A në/pas BOS, të gjithë kandidatët, burimet e dallueshme T002-touch/T003-reconfirmed dhe OD1–OD6.
- CONVERGED do të thotë marrëveshje në thellësitë e provuara, jo saktësi ndaj strategjisë së klientit.
- Kur T002 dhe T003 kundërshtohen, paneli e tregon. Përparësia nuk është zgjidhur nga testet.
- Testet dhe vëzhgimet MT5 dokumentohen veçmas. RETURN_OBSERVED nuk autorizon hyrje.

## 13. Regjistri i pyetjeve të reduktuara

Mos pyes më nga fillimi: timeframe-i i konfirmimit (M15), nëse H4 FVG është hyrje (jo), nëse wick touch mjafton (po, pastaj mbyllja H4), fillimi apo mesi i FVG (klienti tha fillimi), parimi strukturor i SL-së, minimumi nën 2R, 80% në 2R dhe mungesa e trailing-ut.

Pyetje të mundshme vetëm kur hapi përkatës bllokohet: zgjedhja mes FVG-ve M15; swing-et që përbëjnë strukturën; offset/buffer; targeti mes disa niveleve; përparësia T002/T003; sizing/kosto; 2 apo 3 trade; +0.2%; skadimi/ri-hyrja; pozicionet në lajme/fund seance. Para pyetjes kontrollo nëse shembulli ekzistues e zgjidh. Parametrat teknikë të brokerit lexohen nga llogaria, nuk pyeten si preferenca.

## 14. Testimi, pranimi dhe mirëmbajtja

**K, B1:** klienti raporton testim manual mbi 60 trade dhe 50–55% win rate, pa regjistër të dorëzuar. Këto janë pohime të klientit, jo rezultate të verifikuara. Periudha e krahasimit e kërkuar: nga përfundimi i robotit e tutje.

**H:** toleranca e hyrjes/kohës, përputhja e kërkuar e trade-ve, krahasimi me kostot, periudha e plotë e testimit dhe trajtimi i candle-s që prek SL e TP. Nuk premtohet profitabilitet nga kalimi i testeve të logjikës.

Pas çdo sqarimi: shto burimin dhe ndryshimin këtu; përditëso DECISIONS dhe pyetjen përkatëse; mbaj historinë e pikës së zëvendësuar. Mos kopjo logje të gjata ose të dhëna private çmimesh në këtë dokument. Përpara çdo raundi zhvillimi lexo seksionet përkatëse dhe STATE.

## 15. Historia e korrigjimeve

- 14.10.2026: u krijua referenca qendrore nga B1–B5 dhe sqarimet në bisedë.
- 14.10.2026: korrigjim i rëndësishëm ndaj planit T005 te 5447ef3 dhe përgjigjes së mëparshme të Codex: “fillimi i FVG ne M15” është tekst origjinal klienti. Përgjigjja me tekst për SL nuk anulohet nga fusha automatike e paplotësuar.

Referenca aktive në repo: docs/STRATEGY_SPEC.md. Checklist: [PROJECT_CHECKLIST.md](PROJECT_CHECKLIST.md); pamja: [PROJECT_PROGRESS.html](PROJECT_PROGRESS.html). Gjendja operative: [STATE.md](STATE.md).

Detajet teknike: [T003](../tasks/T003-h4-bias-change.md), [T004](../tasks/T004-m15-confirmation.md), [T005](../tasks/T005-entry-sl-tp-plan.md). Specifikimi i mëparshëm ruhet vetëm si [arkiv historik](reference/strategy-spec-archive-2026-10-14.md), jo kopje aktive.
