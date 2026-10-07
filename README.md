# XAUUSD MT5 robot — projekti XAU-20261006-E27N93

Robot MQL5 për MetaTrader 5. Ndërtohet me hapa (tasks). Hapi aktual: **T001 — foundation**.

- Udhëzimet e përbashkëta: [AGENTS.md](AGENTS.md) · pika e hyrjes për Claude Code: [CLAUDE.md](CLAUDE.md)
- Gjendja e tanishme: [docs/STATE.md](docs/STATE.md)
- Specifikimi (I PAPLOTË): [docs/STRATEGY_SPEC.md](docs/STRATEGY_SPEC.md) · pyetjet e hapura: [docs/OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md)
- Udhëzuesi i nisjes: [README-START-SQ.md](README-START-SQ.md)

## ⚠️ Çfarë bën dhe çfarë NUK bën ndërtimi i tanishëm

`src/XauUsdFoundation.mq5` është **vetëm vëzhgues**. Ai:

- lexon simbolin dhe specifikimin e brokerit (digits, point, tick size/value, contract size, volume min/max/step, stops/freeze level, spread, filling mode, netting/hedging),
- mban nën vëzhgim seritë **H4**, **H1** dhe **M15**,
- raporton **gatishmërinë e historikut** në mënyrë të vërtetë derisa të dhënat ngarkohen,
- ndan në mënyrë të prerë **candle-in që po formohet** (indeks 0) nga **candle-i i mbyllur** (indeks 1),
- nxjerr **një event për candle të re, një herë për timeframe**,
- shkruan në log vetëm kur statusi ndryshon, dhe vizaton një panel statusi në grafik.

Ai **NUK** përmban `OrderSend`, `CTrade`, as asnjë funksion që hap, ndryshon ose mbyll pozicione/urdhra. **NUK** ka logjikë strategjie: drejtimi, FVG, MSS, risku dhe daljet mbeten të hapura (Q01–Q12). `InpMagicNumber` ruhet vetëm për hapat e ardhshëm.

## Instalimi në MT5

1. Në MetaTrader 5: **File → Open Data Folder**. Hapet dosja e të dhënave (ajo që përmban `MQL5\`).
2. Kopjo skedarët:
   - `src/XauUsdFoundation.mq5` → `MQL5\Experts\XauUsdFoundation.mq5`
   - `src/include/*.mqh` → `MQL5\Include\Velo\` (krijoje dosjen `Velo`)
3. Nëse i ruan include-et në `MQL5\Include\Velo\`, zëvendëso në fillim të `XauUsdFoundation.mq5`:

   ```mql5
   #include "include/SymbolSnapshot.mqh"      →  #include <Velo\SymbolSnapshot.mqh>
   #include "include/TimeframeWatcher.mqh"    →  #include <Velo\TimeframeWatcher.mqh>
   #include "include/StatusPanel.mqh"         →  #include <Velo\StatusPanel.mqh>
   ```

   **Më e thjeshtë:** kopjo të gjithë dosjen `src/` siç është në `MQL5\Experts\Velo\`, që `Experts\Velo\XauUsdFoundation.mq5` dhe `Experts\Velo\include\*.mqh` të qëndrojnë bashkë. Atëherë `#include "include/..."` punon pa ndryshim. Ky është rruga e rekomanduar.

## Kompilimi

1. Në MT5 shtyp **F4** (hapet MetaEditor), ose hap MetaEditor drejtpërdrejt.
2. Në Navigator hap `Experts\Velo\XauUsdFoundation.mq5`.
3. Shtyp **F7** (Compile). Rezultati shfaqet në tab-in **Errors**.
4. Duhet: `0 errors`. Shëno çdo *warning* dhe si u zgjidh në `reports/T001-verification.md`.

Nga command line (Windows, zëvendëso shtegun e instalimit):

```
"C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:"C:\Users\<user>\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Experts\Velo\XauUsdFoundation.mq5" /log:"%TEMP%\mql5_compile.log"
```

Pastaj hap `%TEMP%\mql5_compile.log` dhe kopjo përmbajtjen në raportin e verifikimit.

## Nisja dhe leximi i logeve

1. Hap një grafik **XAUUSD.r** (ose simbolin e vërtetë të Tauro) — timeframe-i i grafikut nuk ka rëndësi; EA-ja lexon H4/H1/M15 vetë.
2. Tërhiq `XauUsdFoundation` nga Navigator në grafik. **AutoTrading mund të mbetet i fikur** — ky ndërtim nuk tregton.
3. Inputet kryesore:
   - `InpSymbolName` — bosh = simboli i grafikut; vendos `XAUUSD.r` për ta fiksuar.
   - `InpMinBarsH4 / H1 / M15` — thellësia minimale e historikut para se timeframe-i të quhet READY.
   - `InpShowPanel`, `InpPanelCorner` (`Top left` / `Top right`), `InpLogNewBars`, `InpPollSeconds` — diagnostikë.
4. Loget: dritarja **Toolbox → Experts**. Me klik të djathtë → *Open* hapet dosja `MQL5\Logs\` me skedarin `<data>.log`.
5. Në fillim do të shohësh `STATUS ... LOADING/NO_HISTORY` derisa historiku vjen, pastaj `DATA READY: H4, H1 and M15 all synchronised`. Më pas vetëm `NEW BAR M15 ...` / `NEW BAR H1 ...` / `NEW BAR H4 ...`.
6. Për të mbushur historikun më shpejt: hap grafikët H4, H1, M15 të të njëjtit simbol dhe rrotullo pas me `Home`, ose rrit `Tools → Options → Charts → Max bars in chart`.

## Verifikimi

Evidenca reale e këtij hapi është në [reports/T001-verification.md](reports/T001-verification.md). Kompilimi dhe sjellja në MT5 janë shënuar **UNVERIFIED** derisa t'i kryejë pronari — kontejneri i zhvillimit nuk ka MetaEditor.

Kontrollet statike (pa API tregtimi, balanca sintaksore, include-et, pa API MQL4, handler-at, specifikuesit e formatit, vetëm-ASCII) ri-ekzekutohen me:

```
bash tools/t001-static-checks.sh
```

Këto **nuk** janë kompilator dhe **nuk** zëvendësojnë testimin në MT5 — lista e kontrolleve që duhet t'i bëjë pronari është në §5 të raportit.

## Shënim për skedarët e vjetër në repo

`MQL5/Experts/MA_Crossover_EA.mq5` dhe `jessy` ishin në repo përpara këtij projekti dhe **nuk janë pjesë e tij**. `MA_Crossover_EA.mq5` është një EA i ndryshëm që **vërtet tregton** (MA crossover). Mos e ngatërro me `src/XauUsdFoundation.mq5` dhe mos e nis në të njëjtin llogari pa vendim të qartë.
