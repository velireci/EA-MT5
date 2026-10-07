# T001 — raporti i verifikimit

Data: 2026-10-07 · Degë: `claude/amazing-darwin-icpcjd` · Zbatoi: Claude Code (agjenti kryesor)
Task: [tasks/T001-foundation.md](../tasks/T001-foundation.md)
Versioni i testuar: `763227d494115126a801d7e9cebe48a49977eb76`. Kodi nën `src/` dhe `tools/` nuk ka ndryshuar që nga ai commit; commit-et pasardhës prekin vetëm dokumentimin.

**Kush e prodhoi çfarë.** Ky dokument regjistron rezultate; nuk i prodhoi të gjitha vetë.

| Evidenca | Prodhuar nga |
|---|---|
| Kompilimi në MetaEditor | **Codex** |
| Ri-ekzekutimi i pavarur i kontrolleve statike | **Codex** |
| Vëzhgimet në MT5 (MetaQuotes-Demo) | **Pronari** |
| Kodi, kontrollet statike (ekzekutimi i parë) dhe ky dokument | Claude Code. Nuk kam kompiluar dhe nuk kam vëzhguar asnjë rezultat në MT5. |

Rezultatet e Codex-it dhe të pronarit më janë përcjellë në bisedë si përmbledhje. Loget e papërpunuara të kompilimit, ekstrakti i Journal-it dhe screenshot-et nuk janë bashkëngjitur në repo.

## 1. Evidenca e kompilimit dhe e testimit

Kompilimi dhe testimi në MT5 janë evidenca të ndryshme dhe raportohen veçmas.

### 1a. Kompilimi (Codex)

| Commit | Rezultati | Gjendja |
|---|---|---|
| `c810f90` | 0 errors, 1 warning (warning 68, formati i `#property version`) | warning-u u rregullua në `763227d` |
| `763227d` | **0 errors, 0 warnings** | warning 68 nuk shfaqet më |

Codex e kompiloi `763227d` në MetaEditor. Ky është kompilimi i vetëm i kodit aktual.

Mjedisi im i zhvillimit nuk ka MetaEditor, prandaj nuk kam kompiluar vetë:

```
command -v metaeditor64.exe metaeditor64 metaeditor mql5 wine wine64 terminal64.exe
  → asnjë i gjetur
find / -iname 'metaeditor*' -not -path '/proc/*'
  → bosh
```

Kompilimi provon sintaksën dhe tipat. Nuk thotë asgjë për sjelljen në runtime.

### 1b. Testet në MT5 (pronari)

Mjedisi: llogari **MetaQuotes-Demo**, simboli **XAUUSD**, valuta e llogarisë **EUR**, modaliteti i pozicioneve **RETAIL_HEDGING**, data 2026.10.07. Numri i build-it të MT5 nuk është regjistruar.

Rezultatet janë **pjesërisht të vëzhguara**, jo të gjitha të kaluara. §5 ndan për secilin kontroll çfarë u vëzhgua nga çfarë mbetet e paprovuar. Kufijtë e evidencës janë në §8.

## 2. Çfarë u verifikua realisht (kontrolle statike, të ekzekutuara)

Skripti i kontrolleve u ekzekutuar mbi katër skedarët e burimit. Rezultati: **ALL STATIC CHECKS PASSED**.

| # | Kontrolli | Metoda | Rezultati |
|---|---|---|---|
| 1 | Pa API tregtimi në kod | hiqen komentet, pastaj `grep -E` për `OrderSend\|OrderSendAsync\|OrderClose\|OrderModify\|OrderDelete\|PositionClose\|PositionModify\|PositionOpen\|CTrade\|CPositionInfo\|COrderInfo\|MqlTradeRequest\|MqlTradeResult\|OrderCalcMargin\|OrderCalcProfit\|OnTradeTransaction\|PositionSelect\|OrderSelect\|#include <Trade` | PASS — zero përputhje në kod (vetëm një koment që e deklaron mungesën) |
| 2 | Balanca `{}`, `()`, `[]` | parser Python me komentet dhe string-literal-et e hequra | PASS për 4/4 skedarë |
| 3 | Include guards dhe zgjidhja e include-eve | numërim `#ifndef`/`#endif`; ekzistenca e shtegjeve | PASS 3/3 guards, 3/3 include-e zgjidhen |
| 4 | Pa API të stilit MQL4 | `grep -E` për `OrdersTotal()\|iBars(\|AccountBalance(\|MarketInfo(\|OrderType()\|Bid\|Ask\|start()\|init()\|deinit()` | PASS — zero përputhje |
| 5 | Handler-at MQL5 të detyrueshëm | `grep` për përkufizimet | PASS — `OnInit`, `OnDeinit`, `OnTick`, `OnTimer` |
| 6 | Specifikuesit e `StringFormat`/`PrintFormat` përputhen me argumentet | parser Python (`tools/t001-check-format-strings.py`) mbi 29 thirrjet | PASS — 0 mospërputhje |
| 7 | Burimi vetëm ASCII | `LC_ALL=C grep -c '[^ -~\t]'` | PASS 4/4 — MetaEditor pa BOM nuk mund t'i shtrembërojë string-at |

Kontrollet janë të ri-ekzekutueshme: `bash tools/t001-static-checks.sh` (nga rrënja e repo-s). Ekzekutimi i fundit: `ALL STATIC CHECKS PASSED`, exit code `0`.

**Ri-ekzekutim i pavarur (Codex, `763227d`):** kontrollet statike → **PASS**. Kontrolli i balancës u provua edhe mbi një skedar qëllimisht të gabuar dhe dështoi siç duhet. Unë e kisha provuar më parë me një kopje pa një kllapë mbyllëse (tabela më poshtë).

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
| Loge të përmbledhura kur statusi ndryshon | `PollStatus()` | nënshkrim statusi = gjendja + koha e candle-s së mbyllur për secilin nga 3 TF (numri i bar-eve nuk hyn në nënshkrim). `STATUS` logohet vetëm kur ndryshon nënshkrimi, pra kur ndryshon gjendja. Numëruesi i kërkesave të historikut dhe progresi `N/M bars` rifreskohen në panel, jo në log. Tranzicionet READY/NOT READY dhe lidhja me serverin logohen një herë |
| Panel i thjeshtë statusi | `src/include/StatusPanel.mqh` | `OBJ_LABEL` me prefiks `velo_t001_`; fshihen në `OnDeinit` dhe edhe në `Init()` (për rastin kur `OnDeinit` nuk u ekzekutua) |
| Pa `OrderSend`/`CTrade`/modifikim urdhrash | i gjithë `src/` | kontrolli 1 më sipër |
| README: instalim, kompilim, loge | [README.md](../README.md) | shtegjet e MT5, F7 / `metaeditor64.exe /compile`, `Toolbox → Experts`, `MQL5\Logs\` |

## 5. Kontrollet C1–C6: gjendja sipas evidencës

Asnjë kontroll nuk shënohet automatikisht si kaluar. C1 është kaluar. C2–C6 janë vëzhguar vetëm pjesërisht dhe secili ka pjesën e paprovuar të shënuar.

| Kontrolli | Gjendja | Burimi |
|---|---|---|
| C1 Kompilimi | **KALUAR** | Codex, `763227d`: 0 errors, 0 warnings |
| C2 Gatishmëria gjatë ngarkimit | **PJESËRISHT** | pronari |
| C3 Eventet e candle-ve të reja | **PJESËRISHT** | pronari |
| C4 Restart i pastër | **PJESËRISHT** | pronari |
| C5 Asnjë veprim tregtimi | **PJESËRISHT** (Algo Trading i fikur) | pronari |
| C6 Simboli i vërtetë (Tauro) | **JO E KRYER për Tauro**; vetëm 3 fakte nga demo | pronari |

### C1 — Kompilimi: KALUAR

Codex e kompiloi `763227d` në MetaEditor: `0 errors, 0 warnings`. Warning 68, që Codex e kishte marrë në `c810f90`, nuk shfaqet më; rregullimi ishte `#property version "1.00"` dhe heqja e `#property link ""` bosh. Teksti i plotë i logut të kompilimit nuk është bashkëngjitur këtu.

Nga command line (Windows):

```
"C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:"...\Experts\Velo\XauUsdFoundation.mq5" /log:"%TEMP%\mql5_compile.log"
```

### C2 — Gatishmëria e vërtetë gjatë ngarkimit: PJESËRISHT

**Pritja.** Gjatë ngarkimit paneli tregon `data NOT READY` me ngjyrë portokalli dhe, për çdo timeframe që nuk është gati, një rresht me gjendjen, thellësinë `N/M bars` dhe numëruesin `K history request(s) sent`. Këto rreshta janë **në panel**, që rifreskohet kur ndryshon statusi ose më së shumti dy herë në sekondë. Në log, `STATUS <TF> <GJENDJA> - ...` shkruhet **vetëm kur ndryshon gjendja** (p.sh. NO_HISTORY → LOADING), me vlerën e numëruesit në atë moment; numëruesi nuk shkruhet në log me çdo rritje. Kur të tria timeframe-et bëhen gati del **një** rresht `DATA READY: H4, H1 and M15 all synchronised`. Paneli nuk shfaq çmime OHLC për një timeframe para se ai të jetë READY. Terminali nuk duhet të ngrijë: kërkesa e historikut është jo-bllokuese, pa `Sleep` dhe pa cikle pritjeje.

**Vëzhguar (pronari):**
- H4, H1 dhe M15 arritën `DATA READY`.
- Me minimumin H4 përkohësisht 1000000: H4 LOADING dhe data NOT READY, ndërsa H1 dhe M15 mbetën READY. Pas kthimit në 200: data READY.

**Paprovuar:**
- Shkarkimi nga një terminal pa historik nuk u testua. Provimi me 1000000 ushtron shtegun e kërkesës (`Bars() < min`), por jo një shkarkim real, dhe rezultati i kërkesës (numëruesi, ritmi) nuk u raportua.
- Kufizimi i kërkesave në 2000 ms u rishikua vetëm në kod (`RequestHistory()`, `m_request_interval_ms = 2000`). Frekuenca nuk u mat në runtime; nuk ka evidencë se numëruesi rritet afërsisht një herë në 2 sekonda.
- Nuk u raportua nëse paneli i fshehu çmimet OHLC para READY, as vlera e numëruesit në panel.
- Mungesa e ngrirjes së terminalit gjatë ngarkimit nuk u raportua.

### C3 — Eventet e candle-ve të reja: PJESËRISHT

**Pritja.** Një `NEW BAR` për candle të re për timeframe; candle-a e mbyllur në atë rresht është e mëparshmja dhe candle-a "forming" është e reja; O/H/L/C e candle-s së mbyllur përputhen me grafikun. Kontrolli kërkon të punojë ≥ 1 orë në treg të hapur.

**Vëzhguar (pronari, 2026.10.07):**
- Eventet M15 në 15:30 dhe 15:45, dhe H4/H1/M15 në 16:00, u raportuan pa përsëritje gjatë vëzhgimit.
- OHLC e candle-ve të mbyllura u krahasua me Data Window dhe përputhej për M15 15:45, H1 15:00 dhe H4 12:00 (candle-t që mbyllen në 16:00).

**Paprovuar:**
- Kohëzgjatja ≥ 1 orë e kërkuar nga kontrolli nuk është dokumentuar; evidenca mbulon dritaren 15:30–16:00.
- OHLC e eventit M15 të 15:30 (candle 15:15) nuk u krahasua.
- Shtegu `WARNING N bar(s) closed unobserved` (fundjavë, rilidhje, terminal i pezulluar) nuk u ushtrua.
- Mbrojtja kundër `DESYNC` të rremë kur një candle hapet mes dy leximeve nuk u ushtrua në mënyrë të dukshme: nuk u raportua as prania as mungesa e `DESYNC` në 16:00.

### C4 — Restart i pastër, pa log spam: PJESËRISHT

**Pritja.** `T001 foundation stopped: …` një herë, pastaj blok i ri `=== T001 foundation ===`; asnjë `NEW BAR` i rremë menjëherë pas nisjes (baseline-i merret në heshtje); asnjë etiketë e mbetur në grafik; log i qetë kur statusi nuk ndryshon.

**Vëzhguar (pronari):**
- Ndryshimi i parametrave shkaktoi ndalim me `inputs changed`, rinisje dhe `DATA READY`, pa `NEW BAR` të rremë në pamjen e dhënë (ekstrakt, jo logu i plotë).

**Paprovuar:**
- Heqja dhe vendosja përsëri e EA-së, rikompilimi (F7) gjatë punës, mbyllja e grafikut dhe rinisja e terminalit.
- Mungesa e etiketave të mbetura në grafik pas reload.
- Mungesa e log spam-it gjatë një periudhe të gjatë: vlerësuar vetëm nga ekstrakti, jo nga numërim rreshtash në kohë.

### C5 — Asnjë veprim tregtimi: PJESËRISHT

**Pritja.** EA punon normalisht; skeda Trade dhe History pa ndryshim; Journal pa kërkesa tregtimi.

**Vëzhguar (pronari):** Algo Trading ishte i fikur; skeda Trade ishte bosh; gjatë vëzhgimit nuk u raportuan kërkesa tregtimi në Journal.

**Kufizime:**
- Mesazhi i vetë EA-së (`No orders were placed, modified or closed`) **nuk** është provë e pavarur: është tekst që e shkruan vetë kodi.
- Me Algo Trading të fikur terminali bllokon dërgimin e urdhrave nga EA-të. Mungesa e urdhrave në këtë test nuk tregon vetë se EA nuk do të tregtonte po të ishte i lejuar. Evidenca që EA nuk ka aftësi tregtimi është tjetër: mungesa e çdo funksioni tregtimi në kod (kontrolli statik 1, ri-ekzekutuar nga Codex) dhe fakti që kompilohet pa asnjë `#include <Trade...>`.
- Test me Algo Trading të ndezur nuk është bërë.

### C6 — Simboli i vërtetë: JO E KRYER për Tauro

**Pritja.** Emri ekzakt i simbolit të Tauro (klienti shkroi `XAUUSD.r`) dhe, nga logu i `OnInit`: digits, point, tick size/value, contract size, volume min/step, stops level, netting ose hedging. Këto nevojiten për sizing/ekzekutim dhe janë në listën teknike të `docs/OPEN_QUESTIONS.md`.

**Vëzhguar (pronari, MetaQuotes-Demo, jo Tauro):** simboli `XAUUSD`, valuta e llogarisë `EUR`, modaliteti `RETAIL_HEDGING`. Vetëm këto tri fakte; digits, point, tick size/value, contract size, volume dhe stops level nuk u raportuan për asnjë broker.

**E hapur:**
- Specifikimet e Tauro nuk janë konfirmuar: emri i simbolit (`XAUUSD.r`?), digits, tick value, contract size, volume min/step, stops level dhe netting/hedging i llogarisë së vërtetë.
- Demo-ja ka valutë EUR; klienti ka deklaruar llogari USD. Dallimi ka rëndësi për sizing-un (Q08) dhe nuk ndikon në vlerësimin e T001.
- `RETAIL_HEDGING` vlen për këtë demo, jo për llogarinë e klientit. Ndarja e pozicioneve nuk supozohet pa e verifikuar te Tauro (AGENTS.md).

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
| 1 | Kërkesa e historikut nuk ishte eksplicite: mbahej vetëm te efekti anësor i `Bars()`, dhe nuk kishte thellësi të kërkuar për secilin timeframe përpara se të kthehej për mungës historiku | `CTimeframeWatcher::RequestHistory()`: `CopyTime(symbol, period, m_min_bars - 1, 1, ...)` — kërkon pikërisht thellësinë që i duhet atij timeframe-i, dhe thirret **përpara** kthimit me `NO_HISTORY`/`LOADING`. Pa `Sleep`, pa cikle pritjeje; i kufizuar në një kërkesë për 2000 ms për timeframe, pra jo për çdo tick. Numëruesi `K history request(s) sent` rifreskohet në panel; në log del vetëm brenda rreshtit `STATUS` që shkruhet kur ndryshon gjendja | statike: kaluan; kompilim: kaloi (Codex, 0/0); runtime: **pjesërisht** — shtegu LOADING u ushtrua (H4 minimum 1000000), ritmi 2000 ms nuk u mat, shkarkimi nga terminal pa historik nuk u testua (C2) |
| 2 | Kontrolli 2 i `t001-static-checks.sh` nuk ndikonte exit code-in | `tools/t001-check-balance.py` me exit 1 + `\|\| FAIL=1` në Bash | **I TESTUAR**: kopje me kllapë të munguar → exit `1`, `STATIC CHECKS FAILED`; pema e vërtetë → exit `0`. Tabela në §2. Codex e provoi pavarësisht: kontrolli i balancës dështoi mbi një skedar qëllimisht të gabuar |
| 3 | `#property version "0.01"` shkaktonte warning 68 | `#property version "1.00"`; hoq edhe `#property link ""` bosh, që është vlerë jo e vlefshme për një property; faza T001 kaloi te `#property description` | kompilim: **KALOI** — Codex, `763227d`: 0 warnings (C1) |
| 4 | Evidenca nuk dallonte kompilimin nga testet në MT5 | Raporti u rindërtua: §1a kompilimi, §1b testet në MT5, §5A rikompilimi, §5B testet | ky dokument |

### Korrigjime të këtij dokumenti

- **C2.** Versioni i mëparshëm thoshte se rreshtat `STATUS` tregojnë `N history request(s) sent` me N që rritet ngadalë. Kjo ishte e gabuar. `STATUS` logohet vetëm kur ndryshon gjendja (nënshkrimi është gjendja + koha e candle-s së mbyllur), kështu që numëruesi nuk rritet në log. Ai rifreskohet në panel. U korrigjuan C2 në §5, rreshti përkatës në §4 dhe tabela e raundit 2.
- **Numri i thirrjeve të formatit (§2).** Thoshte 24 thirrje `StringFormat`/`PrintFormat`; numri nuk ishte numëruar. Numërimi i vërtetë është 29.
- **Nënshkrimi i statusit (§4).** Rreshti thoshte se nënshkrimi përfshin numrin e bar-eve; këtë e hoqa në raundin 1 (gjetja 2).
- Fjalët e gabuara për C2 janë edhe te mesazhi i commit-it `763227d` dhe te komenti në PR #1 ("request count is visible in the STATUS line"). Historia e git-it dhe komenti nuk u ndryshuan.

## 7. Kufizime të njohura

- Paneli ofron vetëm kornizat e sipërme (`PANEL_TOP_LEFT` / `PANEL_TOP_RIGHT`); kornizat e poshtme janë hequr qëllimisht sepse paneli rritet nga lart-poshtë.
- `input group` kërkon MT5 build 2470+. Build-et më të vjetra duhet të heqin ato rreshta.
- `InpPollSeconds` nën 1 refuzohet në `OnInit`; timer-i është vetëm diagnostikë.
- Nuk ka test historik (Strategy Tester) në këtë hap: nuk ka logjikë vendimi për të testuar.

## 8. Kufijtë e evidencës

- Kompilimi (Codex, 0 errors, 0 warnings) provon sintaksën dhe tipat; nuk provon sjellje.
- Shkarkimi nga një terminal pa historik nuk u testua.
- Kufizimi i kërkesave në 2000 ms u rishikua në kod; frekuenca nuk u mat në runtime.
- Specifikimet e Tauro nuk janë konfirmuar. Testi u bë në MetaQuotes-Demo (XAUUSD, EUR, RETAIL_HEDGING).
- Mungesa e veprimeve tregtare u vëzhgua (Trade bosh, Journal pa kërkesa) me Algo Trading të fikur. Mesazhi i vetë EA-së nuk është provë e pavarur.
- Evidenca nga MT5 vjen nga raporti i pronarit dhe nga ekstrakte; nuk ka numërim të plotë logu dhe as matje kohore.
- Nuk provon korrektësi strategjie: ky ndërtim nuk ka strategji.
- Kontrollet statike dhe rishikimi vetëm-lexim kapin vetëm gabime që duken në burim.

## 9. Konkluzioni

Zbatimi i T001 është i plotë në kod. Gjendja e evidencës për `763227d`:

| Evidenca | Gjendja |
|---|---|
| Kompilim | **KALUAR** (Codex): 0 errors, 0 warnings |
| Kontrolle statike | **KALUAR** (Claude Code, pastaj Codex i pavarur); kontrolli i balancës dështon siç duhet mbi skedar të gabuar |
| Teste në MT5 | **PJESËRISHT VËZHGUAR** nga pronari në MetaQuotes-Demo; C2–C6 kanë secili pjesë të paprovuar (§5) |
| Specifikimet e Tauro | **E HAPUR** |

Kundrejt "Completion evidence" të `tasks/T001-foundation.md`:

| # | Kriteri | Gjendja |
|---|---|---|
| 1 | Kompilim pa errors; warning-ët e regjistruar | **PLOTËSUAR** (0 errors, 0 warnings, Codex) |
| 2 | Gatishmëria e vërtetë gjatë ngarkimit të historikut | **PJESËRISHT**: gjendja LOADING u vëzhgua me minimum të ngritur; shkarkimi real nga terminal pa historik jo |
| 3 | Eventet e candle-ve të reja një herë për timeframe; candle e formuar dhe e mbyllur të identifikuara saktë | **VËZHGUAR në një dritare të kufizuar** (15:30–16:00); OHLC e krahasuar për tri candle |
| 4 | Restart/reload i pastër, pa log spam | **PJESËRISHT**: vetëm ndryshimi i parametrave, sipas ekstraktit |
| 5 | Asnjë urdhër i dërguar, ndryshuar ose mbyllur | **VËZHGUAR** me Algo Trading të fikur (kufizimet në C5); kodi nuk përmban funksione tregtimi |

Nuk e shënoj T001 si të mbyllur: vendimi nëse boshllëqet më sipër pranohen ose kërkohen teste shtesë i takon pronarit dhe rishikimit të Codex-it.

Asnjë rregull tregtimi nuk u shpikur. Q01–Q12 mbeten të hapura dhe nuk nevojiten për këtë hap.
