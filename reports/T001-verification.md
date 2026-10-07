# T001 — raporti i verifikimit

Data: 2026-10-07 · Degë: `claude/amazing-darwin-icpcjd` · Zbatoi: Claude Code (agjenti kryesor)
Task: [tasks/T001-foundation.md](../tasks/T001-foundation.md)

## 1. Evidenca e kompilimit

Kompilimi dhe testimi në MT5 janë dy evidenca të ndryshme. Këtu ndahen.

### 1a. Kompilimi

**Mjedisi im i zhvillimit nuk ka MetaEditor.** Komandat dhe rezultati faktik:

```
command -v metaeditor64.exe metaeditor64 metaeditor mql5 wine wine64 terminal64.exe
  → asnjë i gjetur
find / -iname 'metaeditor*' -not -path '/proc/*'
  → bosh
```

Pra unë nuk kam kompiluar asgjë, dhe nuk e shkruaj dot kompilimin si të verifikuar nga vetëja.

**Codex e kompiloi**, dhe ky është evidenca e vetme e kompilimit që ka ky projekt:

| Commit | Rezultati | Gjendja |
|---|---|---|
| `c810f90` | **0 errors, 1 warning** (warning 68, formati i `#property version`) | warning-u u rregullua në këtë raund |
| commit-i i tanishëm | **I PAKOMPILUAR** | kodi ndryshoi pas `c810f90`; duhet rikompilim |

Ndryshimet pas `c810f90` prekën `src/XauUsdFoundation.mq5` (blloku i `#property`) dhe `src/include/TimeframeWatcher.mqh` (kërkesa e historikut). **Asnjëra nuk është kompiluar.** Pritet `0 errors, 0 warnings`; njësoj duhet konfirmuar, jo supozuar.

### 1b. Testet në MT5

**Asnjë test në MT5 nuk është kryer, në asnjë commit.** Sjellja në runtime — gatishmëria gjatë ngarkimit, eventet e candle-ve, restart-i, mungesa faktike e urdhrave në një llogari — mbetet tërësisht e paverifikuar. Kontrollet janë në §5B.

Kompilimi i pastër **nuk** thotë asgjë për asnjërën prej tyre.

## 2. Çfarë u verifikua realisht (kontrolle statike, të ekzekutuara)

Skripti i kontrolleve u ekzekutuar mbi katër skedarët e burimit. Rezultati: **ALL STATIC CHECKS PASSED**.

| # | Kontrolli | Metoda | Rezultati |
|---|---|---|---|
| 1 | Pa API tregtimi në kod | hiqen komentet, pastaj `grep -E` për `OrderSend\|OrderSendAsync\|OrderClose\|OrderModify\|OrderDelete\|PositionClose\|PositionModify\|PositionOpen\|CTrade\|CPositionInfo\|COrderInfo\|MqlTradeRequest\|MqlTradeResult\|OrderCalcMargin\|OrderCalcProfit\|OnTradeTransaction\|PositionSelect\|OrderSelect\|#include <Trade` | PASS — zero përputhje në kod (vetëm një koment që e deklaron mungesën) |
| 2 | Balanca `{}`, `()`, `[]` | parser Python me komentet dhe string-literal-et e hequra | PASS për 4/4 skedarë |
| 3 | Include guards dhe zgjidhja e include-eve | numërim `#ifndef`/`#endif`; ekzistenca e shtegjeve | PASS 3/3 guards, 3/3 include-e zgjidhen |
| 4 | Pa API të stilit MQL4 | `grep -E` për `OrdersTotal()\|iBars(\|AccountBalance(\|MarketInfo(\|OrderType()\|Bid\|Ask\|start()\|init()\|deinit()` | PASS — zero përputhje |
| 5 | Handler-at MQL5 të detyrueshëm | `grep` për përkufizimet | PASS — `OnInit`, `OnDeinit`, `OnTick`, `OnTimer` |
| 6 | Specifikuesit e `StringFormat`/`PrintFormat` përputhen me argumentet | parser Python (`tools/t001-check-format-strings.py`) mbi të 24 thirrjet | PASS — 0 mospërputhje |
| 7 | Burimi vetëm ASCII | `LC_ALL=C grep -c '[^ -~\t]'` | PASS 4/4 — MetaEditor pa BOM nuk mund t'i shtrembërojë string-at |

Kontrollet janë të ri-ekzekutueshme: `bash tools/t001-static-checks.sh` (nga rrënja e repo-s). Ekzekutimi i fundit: `ALL STATIC CHECKS PASSED`, exit code `0`.

**Defekt në vetë kontrollet, gjetur nga Codex dhe i rregulluar.** Kontrolli 2 printonte `FAIL` por Python-i nuk dilte me kod gabimi dhe Bash-i nuk e përfshinte në rezultatin përfundimtar — pra një skedar me kllapa të pabalancuara jepte prapëseprapë `ALL STATIC CHECKS PASSED` dhe exit `0`. Pra kontrolli 2 ishte dekorativ.

E riprodhova përpara se ta rregulloja, me një kopje ku hoqa një kllapë mbyllëse nga `StatusPanel.mqh`:

| | Përpara rregullimit | Pas rregullimit |
|---|---|---|
| Rreshti i kontrollit 2 | `FAIL ... braces unbalanced by 1` | `FAIL ... braces unbalanced by +1` dhe `FAIL: 1 file(s) unbalanced` |
| Rezultati përfundimtar | `ALL STATIC CHECKS PASSED` | `STATIC CHECKS FAILED` |
| Exit code | `0` | `1` |

Rregullimi: logjika doli te `tools/t001-check-balance.py`, që kthen `1` kur ndonjë skedar është i pabalancuar, dhe Bash-i e përfshin me `|| FAIL=1`. Testi me kllapë të munguar u ri-ekzekutua pas rregullimit dhe jep exit `1`; pema e vërtetë jep exit `0`.

Kontrolli 4 (API i stilit MQL4) mbetet qëllimisht vetëm **WARN** dhe nuk e ndikon exit code-in: modelet e tij (p.sh. `Bid`, `Ask`) mund të japin përputhje të rreme.

Kontrolli 1 është evidenca e drejtpërdrejtë për pikën 5 të "Completion evidence" (asnjë urdhër i dërguar/ndryshuar/mbyllur): në kod nuk ekziston asnjë funksion që do ta bënte këtë. Pas kompilimit, pronari mund ta rikonfirmojë duke e nisur EA-në me **AutoTrading të fikur** — ndërtimi punon normalisht ashtu.

## 3. Rishikim i pavarur statik

U delegua një rishikim i dytë, **vetëm-lexim**, i katër skedarëve kundrejt T001 — korrektësi MQL5, kohëzimi i candle-ve, gatishmëria e historikut, eventet e candle-ve të reja, mungesa e tregtimit, cikli init/deinit. Rishikuesi punoi sipas përshkrimit të `.claude/agents/strategy-reviewer.md`.

Shënim i saktë për delegimin: përkufizimet e agjentëve të projektit (`.claude/agents/`) mbërritën në repo brenda kësaj sesioni, kështu që **nuk ishin të regjistruara** si agjentë të emërtuar në Claude Code. Rishikimi u krye nga një agjent i përgjithshëm vetëm-lexim me të njëjtin brief dhe të njëjtin model (opus). Në sesion të ri, `strategy-reviewer` do të jetë i thirrshëm me emër.

Gjetjet dhe veprimet e marrra: **§6**. Rishikim statik nuk provon sjellje në runtime.

## 4. Si është zgjidhur çdo kërkesë e T001 (në kod)

| Kërkesa e T001 | Ku | Mekanizmi |
|---|---|---|
| Burim nën `src/`, një `.mq5` kryesor i emërtuar qartë | `src/XauUsdFoundation.mq5` + 3 module në `src/include/` | — |
| `OnInit`, `OnDeinit`, `OnTick`; magic i konfigurueshëm | `src/XauUsdFoundation.mq5` | `InpMagicNumber`, ruhet dhe logohet, **nuk përdoret** në këtë ndërtim. `OnTimer` shtuar që gatishmëria të jetë e vërtetë edhe kur nuk vijnë tick-e |
| Inspektimi i specifikimit të simbolit | `src/include/SymbolSnapshot.mqh` | digits, point, tick size/value, contract size, volume min/max/step, stops/freeze level, spread (+float), trade mode, filling/expiration mask, netting vs hedging, valuta e llogarisë, serveri. `OnInit` dështon qëllimisht (`INIT_FAILED`) nëse digits/point/tick size/volume step mungojnë — hapat e ardhshëm pjesëtojnë me ato |
| Qasje OHLC H1/H4/M15 + zbulim i candle-s së re | `src/include/TimeframeWatcher.mqh` | tre instanca `CTimeframeWatcher` (H4, H1, M15). Candle e re = ndryshim i kohës së hapjes së candle-s që formohet |
| Ndarja e candle-s formuese nga ato të mbyllura | `TimeframeWatcher.mqh` | `GetFormingBar()` (indeks 0, "STILL CHANGING") kundrejt `GetClosedBar()` (indeks 1, final). Të dyja kthejnë `false` kur të dhënat nuk janë të gatshme |
| Kontrolle të gatishmërisë së historikut | `TimeframeWatcher::Refresh()` + `RequestHistory()` | Kërkesë eksplicite e thellësisë për secilin timeframe (`CopyTime` në pozicionin `m_min_bars - 1`), e kufizuar në 1 për 2000 ms, jo-bllokuese, lëshuar përpara kthimit për mungës historiku. Pastaj: `Bars()>0` → `Bars()>=min` → `SERIES_SYNCHRONIZED` → `CopyRates(...,0,2,...)==2` → renditja e dy elementeve përcaktohet nga timestamp-et, **nuk supozohet** → krahasim i pavarur me `SERIES_LASTBAR_DATE` → refuzim nëse candle-a formuese hapet në të ardhmen. Vetëm pas të gjithave `TF_STATE_READY` |
| Loge të përmbledhura kur statusi ndryshon | `PollStatus()` | nënshkrim statusi (state + bars + koha e candle-s së mbyllur për 3 TF); logohet vetëm kur ndryshon. Tranzicionet READY/NOT READY dhe lidhja me serverin logohen një herë |
| Panel i thjeshtë statusi | `src/include/StatusPanel.mqh` | `OBJ_LABEL` me prefiks `velo_t001_`; fshihen në `OnDeinit` dhe edhe në `Init()` (për rastin kur `OnDeinit` nuk u ekzekutua) |
| Pa `OrderSend`/`CTrade`/modifikim urdhrash | i gjithë `src/` | kontrolli 1 më sipër |
| README: instalim, kompilim, loge | [README.md](../README.md) | shtegjet e MT5, F7 / `metaeditor64.exe /compile`, `Toolbox → Experts`, `MQL5\Logs\` |

## 5. Kontrolle që mbeten (UNVERIFIED)

### 5A. Kompilimi

**C1 — Rikompilimi.** Në MetaEditor hap `XauUsdFoundation.mq5` → **F7**.
Prit: `0 errors, 0 warnings`. Codex mori `0 errors, 1 warning` në `c810f90`; warning 68 u rregullua në këtë raund duke çuar `#property version` në `"1.00"` dhe duke hequr `#property link ""` bosh. Shëno numrin e saktë të errors/warnings dhe tekstin e tyre këtu. Nëse warning 68 vazhdon, shkaku nuk ishte formati i version-it dhe duhet gjetur nga teksti i plotë i warning-ut.

Nga command line (Windows):

```
"C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:"...\Experts\Velo\XauUsdFoundation.mq5" /log:"%TEMP%\mql5_compile.log"
```

### 5B. Testet në MT5 (asnjë i kryer)

Kompilimi i pastër nuk i mbulon këto. **Mos i shëno si kaluar pa i vëzhguar.**

**C2 — Gatishmëria e vërtetë gjatë ngarkimit.** Pastro historikun (ose nis MT5 të pastër), hap një grafik XAUUSD.r dhe vendos EA-në.
Prit: në log `STATUS H4 NO_HISTORY/LOADING — …` dhe në panel `data NOT READY` me ngjyrë portokalli, derisa të vijë historiku; pastaj **një** rresht `DATA READY: H4, H1 and M15 all synchronised`. Paneli nuk duhet të shfaqë çmime OHLC përpara se timeframe-i të jetë READY.

Shto këtu edhe kontrollin e kërkesës së historikut: rreshtat `STATUS` duhet të tregojnë `N history request(s) sent` me N që rritet **ngadalë** (një kërkesë për çdo ~2 sekonda për timeframe), jo një për çdo tick. Terminali nuk duhet të ngrijë: kërkesa është jo-bllokuese, pa `Sleep` dhe pa cikle pritjeje.

**C3 — Eventet e candle-ve të reja.** Lëre të punojë ≥ 1 orë në treg të hapur.
Prit: saktësisht **një** rresht `NEW BAR M15 …` për çdo candle M15 (4 në një orë), **një** `NEW BAR H1 …` në kufirin e orës, `NEW BAR H4 …` vetëm në kufijtë H4. Koha e candle-s "closed bar" në atë rresht duhet të jetë candle-a e mëparshme, dhe "forming bar now" candle-a e re. Krahaso me grafikun: O/H/L/C e candle-s së mbyllur duhet të përputhen me candle-in e parafundit në grafik.

**C4 — Restart i pastër, pa log spam.** Hiq EA-në dhe vendose sërish; ndrysho një input (kjo shkakton reinit); shtyp F7 (recompile) ndërsa punon.
Prit: `T001 foundation stopped: …` një herë, pastaj blok i ri `=== T001 foundation ===`; **asnjë** `NEW BAR` i rremë menjëherë pas nisjes (baseline-i merret në heshtje); asnjë etiketë e mbetur në grafik; loget të qeta kur statusi nuk ndryshon (me `InpPollSeconds=1` dhe treg të qetë, dakika pa rreshta të reja).

**C5 — Asnjë veprim tregtimi.** Nise me **AutoTrading të fikur** dhe lëre të punojë.
Prit: punon normalisht; `Toolbox → Trade` dhe `History` pa ndryshim; `Journal` pa kërkesa tregtimi.

**C6 — Simboli i vërtetë.** Konfirmo emrin ekzakt të simbolit të Tauro (klienti shkroi `XAUUSD.r`) dhe shëno nga loget: digits, point, tick size/value, contract size, volume min/step, stops level, dhe nëse llogaria është `RETAIL_NETTING` apo `RETAIL_HEDGING`. Këto nevojiten për hapat e sizing/ekzekutimit dhe janë në listën teknike të `docs/OPEN_QUESTIONS.md`.

## 6. Gjetjet e rishikimit

Rishikuesi ngriti 4 defekte të konfirmuara, 2 pyetje dhe 2 risqe të patestuara. **Të 8-ta u verifikuan nga unë në kod dhe të 8-ta u rregulluan.** Çdo gjetje më poshtë e tregon shkakun dhe rregullimin.

| # | Sevëriteti | Gjetja (verifikuar) | Rregullimi |
|---|---|---|---|
| 1 | defect | `g_all_ready_logged` mbyllej përgjithmonë, kështu që logohej vetëm tranzicioni i **parë** në READY. Pas një rikuperimi NOT READY → READY, logu tregonte "DATA NOT READY" pa rresht rikuperimi. | Flamuri i hequr; tranzicioni logohet në **dy drejtimet**, i de-duplikuar vetëm nga `g_last_all_ready`. |
| 2 | defect | Nënshkrimi i statusit përfshinte `BarsAvailable()`, që rritet në çdo poll ndërsa historiku shkarkohet → një rresht `STATUS` **për çdo poll** gjatë ngarkimit (shteg i log spam-it, pika 4 e evidencës). | Nënshkrimi tani është vetëm `state` + koha e candle-s së mbyllur. Gjatë `LOADING` koha është 0, kështu që nënshkrimi qëndron i njëjtë dhe logohet **një** rresht për gjendje. Progresi numerik duket live në panel. |
| 3 | defect | `SERIES_LASTBAR_DATE` lexohej **pas** `CopyRates`. Nëse një candle hapet midis dy leximeve, raportohej `DESYNC` pa pasur problem — dhe me gjetjen 1 këtu dilte "DATA NOT READY" në kufijtë e candle-ve pa rresht rikuperimi. | Çifti `CopyRates` + `SERIES_LASTBAR_DATE` lexohet **dy herë** para se mospërputhja të quhet desync (`for(attempt = 0; attempt < 2 …)`). |
| 4 | defect (i vogël) | `(int)InpMagicNumber` e trunkonte në log çdo magic mbi 2^31-1, ndërsa inputi është `long`. | `IntegerToString(InpMagicNumber)` me `%s`. |
| 5 | question | Kur kalojnë shumë candle pa vëzhgim (fundjavë, rilidhje, kompjuteri në gjumë), nxirrej një event i vetëm dhe candle-t e ndërmjetme nuk raportoheshin fare. | `CTimeframeWatcher::SkippedBars()` i shtuar; rreshti `NEW BAR` shton `WARNING N bar(s) closed unobserved`. Numërimi bëhet me `Bars(symbol, period, start, stop)`. |
| 6 | question | `m_x/m_y` dhe `OBJPROP_YDISTANCE` ishin fikse pavarësisht `InpPanelCorner`, kështu që kornizat e poshtme rriteshin jashtë grafikut dhe kornizat e djathta rreshtoheshin çrregullt. | Inputi u ngushtua në një enum me vetëm `PANEL_TOP_LEFT` / `PANEL_TOP_RIGHT` (kornizat e poshtme nuk ofrohen më), dhe `OBJPROP_ANCHOR` caktohet sipas kornizës. Opsioni i gabuar u hoq, nuk u shtua kod layout-i i patestuar. |
| 7 | untested-risk | `.mq5` ishte UTF-8 pa BOM me 10 em-dash brenda string-ave. MetaEditor lexon skedar pa BOM në codepage-in e sistemit → mojibake në logun Experts. | Skedari u bë **vetëm ASCII**; kontrolli 7 statik e mban ashtu. |
| 8 | untested-risk | `OnTick` ripikturonte panelin dhe thërriste `ChartRedraw` në **çdo tick** — qindra shkrime objekti në sekondë në XAUUSD. | `RenderPanel(all_ready, force)`: ripikturon menjëherë kur ndryshon statusi/gatishmëria ose vjen candle e re, përndryshe maksimumi dy herë në sekondë (`GetTickCount`, aritmetikë `uint` që e bën wrap-around-in të padëmshëm). |

Gjetjet 9–14 të rishikuesit konfirmuan si korrekte: mungesën e API-t të tregtimit, kohëzimin e candle-ve (gating me `m_bars_valid`, renditja nga timestamp-et, forming/closed pa përzierje), gatishmërinë e historikut, eventet një-herë-për-candle me baseline në attach/recompile/parameter change, ciklin init/deinit, dhe përputhjen me API-n MQL5 pa përzierje MQL4. Ato konfirmime janë **lexim statik**, jo kompilim.

Pas rregullimeve, të 7 kontrollet statike u ri-ekzekutuar: **ALL STATIC CHECKS PASSED**.

### Raundi 2 — rishikimi i Codex në `c810f90` (me kompilim)

Codex kompiloi (`0 errors, 1 warning`) dhe ngriti 4 pika. Të 4-ta u verifikuan dhe u rregulluan.

| # | Gjetja | Rregullimi | Evidenca |
|---|---|---|---|
| 1 | Kërkesa e historikut nuk ishte eksplicite: mbahej vetëm te efekti anësor i `Bars()`, dhe nuk kishte thellësi të kërkuar për secilin timeframe përpara se të kthehej për mungës historiku | `CTimeframeWatcher::RequestHistory()`: `CopyTime(symbol, period, m_min_bars - 1, 1, ...)` — kërkon pikërisht thellësinë që i duhet atij timeframe-i, dhe thirret **përpara** kthimit me `NO_HISTORY`/`LOADING`. Pa `Sleep`, pa cikle pritjeje; i kufizuar në një kërkesë për 2000 ms për timeframe, pra jo për çdo tick. Numri i kërkesave duket në rreshtin `STATUS` | statike: kaluan; runtime: **UNVERIFIED** (C2) |
| 2 | Kontrolli 2 i `t001-static-checks.sh` nuk ndikonte exit code-in | `tools/t001-check-balance.py` me exit 1 + `\|\| FAIL=1` në Bash | **I TESTUAR**: kopje me kllapë të munguar → exit `1`, `STATIC CHECKS FAILED`; pema e vërtetë → exit `0`. Tabela në §2 |
| 3 | `#property version "0.01"` shkaktonte warning 68 | `#property version "1.00"`; hoq edhe `#property link ""` bosh, që është vlerë jo e vlefshme për një property; faza T001 kaloi te `#property description` | **UNVERIFIED** — kërkon rikompilim (C1) |
| 4 | Evidenca nuk dallonte kompilimin nga testet në MT5 | Raporti u rindërtua: §1a kompilimi, §1b testet në MT5, §5A rikompilimi, §5B testet | ky dokument |

## 7. Kufizime të njohura

- Paneli ofron vetëm kornizat e sipërme (`PANEL_TOP_LEFT` / `PANEL_TOP_RIGHT`); kornizat e poshtme janë hequr qëllimisht sepse paneli rritet nga lart-poshtë.
- `input group` kërkon MT5 build 2470+. Build-et më të vjetra duhet të heqin ato rreshta.
- `InpPollSeconds` nën 1 refuzohet në `OnInit`; timer-i është vetëm diagnostikë.
- Nuk ka test historik (Strategy Tester) në këtë hap: nuk ka logjikë vendimi për të testuar.

## 8. Çfarë NUK e provon kjo

- Nuk provon se kodi kompilohet. Asnjë kompilator MQL5 nuk u ekzekutua.
- Nuk provon sjellje në runtime: gatishmëri, eventet e candle-ve, restart, mungesa faktike e urdhrave në llogari.
- Nuk provon korrektësi strategjie. Nuk ka strategji në këtë ndërtim.
- Kontrollet statike dhe rishikimi vetëm-lexim mund të kapin vetëm gabime që duken në burim.

## 9. Konkluzioni

Zbatimi i T001 është i plotë në kod. Gjendja e evidencës, e ndarë:

| Evidenca | Gjendja |
|---|---|
| Kontrolle statike | **KALUAR** mbi kodin e tanishëm (exit `0`), dhe tani kontrolli 2 vërtet dështon kur duhet |
| Kompilim | **vetëm në `c810f90`**, nga Codex: 0 errors, 1 warning. Kodi i tanishëm është i PAKOMPILUAR |
| Teste në MT5 | **ASNJË**, në asnjë commit |

Veprimi i radhës për pronarin: C1 (rikompilim, pritet 0 errors / 0 warnings), pastaj C2–C6 në MT5, duke shkruar rezultatet faktike në §5.

Asnjë rregull tregtimi nuk u shpikur. Q01–Q12 mbeten të hapura dhe nuk nevojiten për këtë hap.
