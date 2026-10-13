# T003 visual EA - installation and use

`src/XauUsdH4Bias.mq5` is a SEPARATE Expert Advisor next to the T001 foundation EA and the T002 map EA. It draws the T003 bias logic (`src/include/H4Bias.mqh`) on an XAUUSD chart so the owner can compare it with the client's examples (task section 10). It contains no trading function at all: it cannot send, modify or close an order, and it opens no M5/M15 series.

STATUS (read this first)
- Every rule it shows is a PROPOSAL (tasks/T003-h4-bias-change.md), not a confirmed client rule. The panel says so. A picture that "looks right" is an observation, not a validation.
- Compiled by Codex at `abd4c1b` (0 errors, 0 warnings, relayed) and observed once by the owner on XAUUSD H4 (relayed, section 9): LIVE and historical both gave LIMITED_BY_HISTORY. The diagnostics and the candle export of section 9 were added AFTER that observation: they are NOT compiled and NOT observed (UNVERIFIED). Static checks only: `bash tools/t003-visual-static-checks.sh`.
- Out of scope, not drawn: the intrabar overlay (P12), the target (P13), M5/M15, entries, orders, positions.

## 1. Files to copy
Copy the whole repository `src/` folder to `<terminal data folder>/MQL5/Experts/velo_src/` (File > Open Data Folder in MT5). After copying, `MQL5/Experts/velo_src/XauUsdH4Bias.mq5` sits next to `MQL5/Experts/velo_src/include/`, because the include lines are relative to the EA file. Files used by this EA:

| File | Role |
|---|---|
| `XauUsdH4Bias.mq5` | the EA (inputs, live/historical flow, panel text) |
| `include/H4BiasDrawer.mqh` | NEW: chart objects and the panel (prefix `velo_t003_`) |
| `include/H4Bias.mqh` | T003 logic, unchanged by this task |
| `include/H4Structure.mqh` | T002 swings, FVGs, direction, copy helpers, unchanged |
| `include/SymbolSnapshot.mqh`, `include/TimeframeWatcher.mqh` | T001 helpers, unchanged |

The logic test `src/tests/T003_LogicTest.mq5` is a SCRIPT and is installed separately under `MQL5/Scripts/velo_src/tests/` with `include/` as its sibling (as for T002). It is not needed by the EA.

## 2. Compile
Open `XauUsdH4Bias.mq5` in MetaEditor and press F7. Send back the full compile log (errors, warnings, the line "Result: ..."). If a line is rejected, send the exact message with its line number; do not edit the logic.

## 3. Inputs
| Input | Default | Meaning |
|---|---|---|
| InpLeftBars / InpRightBars | 2 / 2 | swing rule of T002 (clamped 1..10) |
| InpLookbackBars (L) | 300 | warm-up and A/B check depth, closed H4 bars (50..1000) |
| InpRebuildBars (R) | 1000 | closed bars replayed; raised to 3*L; copy capped at 5000 |
| InpAsOfTime | 0 | 0 = live. Otherwise BROKER/SERVER time as shown by MT5 (NOT UTC, NOT TradingView time) |
| InpDiagnostics | true | when the evaluation is LIMITED_BY_HISTORY: log DIAG1..DIAG8 in the Experts log (once per last bar and reason) and show three of them in the panel (section 9). Behaviour neutral |
| InpExportCandles | false | writes the closed-bar set of the evaluation to a CSV in the terminal's `MQL5/Files` folder (section 9). Off by default; closed bars only |
| InpShowPanel, InpPanelCorner | true, top left | status panel; four corners |
| InpPanelFontSize, InpPanelBgColor | 9, dark | panel font size (6..24) and background |
| InpLabelFontSize | 8 | font of the labels on the chart |
| InpMaxEvents | 12 | most recent events drawn (0..200) |
| InpMaxFvgs | 6 | most recent eligible FVGs drawn (0..50); the reconfirmation FVG is always drawn |
| InpShowNonMarket | false | also draw CONTINUATION, INTERNAL_BREAK, NONE_WICK, CONFLICT |
| InpShowInvalidFvgs | false | also draw INVALID eligible FVGs, dimmed |
| InpColorBear / Bull / Level | tomato / dodger blue / orange | colours |

The picture needs at least 3*L = 900 closed H4 bars (defaults). With less history the panel shows LIMITED_BY_HISTORY with the reason (for example `SHORT_HISTORY`), the bias is UNKNOWN and nothing proposal-derived is drawn.

## 4. Live mode (InpAsOfTime = 0)
Attach to an XAUUSD H4 chart. The logic is replayed when an H4 bar CLOSES; the forming bar is never read and no price is used. At start, restart, input change or recovery from a data problem the current history is the BASELINE: its events are drawn dimmed/coloured by type and are NOT reported as new. Events produced by bars that close after the baseline are drawn larger, in green, prefixed `>> NEW`, listed `[NEW]` in the panel and logged as `T003 NEW EVENT`. If the evaluation is not reliable, or the previous bar's state cannot be reproduced, nothing is reported as new and the log says why (`T003 consumer ...`). Bias, T002 direction and phase changes seen while running are logged (`BIAS CHANGED`, `T002 DIRECTION CHANGED`, `PHASE CHANGED`) and the last four are shown in the panel.
When the H4 series is not ready or a copy fails, all `velo_t003_` map objects are removed and the panel states the reason; when the data returns, the picture is rebuilt from a new baseline.

## 5. Historical mode (InpAsOfTime > 0)
Set InpAsOfTime in SERVER time (the time axis of the MT5 chart). Only bars closed by that time are used, no live price is read, new bars do not change the picture, and no event is marked NEW (the panel lists the latest events with their bar times). The panel shows the as-of time and the last closed H4 bar used. To compare with a client example pick an as-of time just before the event, then a few bars later, and record what changes. A changed input re-initialises the EA.

## 6. Reading the picture
- Panel (top): mode, `support: CONVERGED | SEEDED | LIMITED_BY_HISTORY - reason`, the depths (R requested/used, B depth, warm-up, check depth, bars available), T003 bias with phase, origin and start, the phase reason, T002 direction with the bar it began and the previous one, AGREE/DISAGREE, the protecting level with the three pivots it was selected from and their confirmation times, the wick (`source_wick_time | known | detected_at | retroactive`), the internal sweep, the eligible FVG count and the reconfirmation FVG, the two entry-block flags (REPORTED ONLY), the last events.
- Chart: protecting level line (solid ACTIVE, dashed FROZEN) with `PROTECTING LEVEL (proposal) price known <time>`; text marks `S`, `LL`/`HH`, `prevLL`/`prevHH` at the pivot candles showing `known <confirmation time>`; dotted interior-liquidity line; `WICK ...` and `detected_at` marks; `INTERNAL SWEEP` mark; eligible FVG rectangles (gold, filled = reconfirmation FVG); event texts above the bar.
- Support flags: CONVERGED = the replays at depth R and R-L agree; SEEDED = a reliable ACTIVE-like bias whose origin is the T002 seed; LIMITED_BY_HISTORY = not reliable, with the reason (`SHORT_HISTORY`, `AB_STATE_DIFF`, `AB_EVENT_DIFF`, `ANCHOR_IN_WARMUP`, `ANCHOR_HISTORY_MISSING`) - the bias is then reported as UNKNOWN and no event is emitted.
- Only objects whose name starts with `velo_t003_` are created or deleted (the panel uses `velo_t003_pnl_`). Manual objects and the T001/T002 objects are never touched. Running T002 and T003 on the same chart is possible but their panels may overlap; use the corner inputs.

## 7. What to send back
1. The MetaEditor compile log (full text).
2. The Experts log from attaching the EA until a few minutes after (the `T003 ...` lines, any `NOTICE`, `INIT FAILED` or `picture cleared` line, and the `T003 DIAG1..DIAG8` lines when the support flag is LIMITED_BY_HISTORY).
3. Screenshots of the whole chart with the panel visible, in live mode and for each as-of time used in historical mode, together with the as-of value, the MT5 build and the broker/server name.
4. For each client example (task section 10, V1-V8; V9 needs the target, which is not drawn): the candle (by server time) the robot used for the level versus the candle the client marked, and what the robot reported for the wick/sweep, the FVG and the touch. Say who observed it. Mark "same / different / robot undefined"; do not write "validated".
5. For a LIMITED_BY_HISTORY case: set `InpExportCandles = true` (and `InpDiagnostics` stays true), attach the EA live on XAUUSD H4 (and/or set `InpAsOfTime`, for example 2026.10.06 00:00), and send back (a) the `velo_t003_diag_XAUUSD_<last bar>.csv` file(s) from `MQL5\Files`, (b) the Experts log with the `T003 DIAG` and `T003 EXPORT` lines, (c) a screenshot with the panel visible. The CSV is price data of the broker's own XAUUSD H4 chart: send it only through the owner's usual private channel and do not publish it.
6. Any behaviour that looks wrong: object overlap, a panel that is cut off or hides candles, a missing object, a long delay on attach (the first rebuild replays up to 1000 bars four times).

## 8. Reading a change notice
`BIAS CHANGED`, `T002 DIRECTION CHANGED` and `PHASE CHANGED` (panel "observed live" and Experts log) appear ONLY when the new closed bar followed the previous evaluated bar directly and the previous state was reproduced by the new window (consumer status OK, the same step that makes an event NEW). If bars were missed (consumer GAP), the window slid or the depth changed (REDERIVED) or the same bar was evaluated twice, a difference is logged as `T003 RE-DERIVATION (consumer ...)` with the cause and is NOT a market change. Before the diagnostics round every difference between two reliable evaluations was shown as a change (reporting defect, fixed; reports/T003-verification.md section 10.3).

## 9. Diagnostics and candle export (LIMITED_BY_HISTORY)
Why: the owner's observation (relayed) was LIMITED_BY_HISTORY with `AB_STATE_DIFF+AB_EVENT_DIFF+ANCHOR_IN_WARMUP` at R=1000 live and at 1000 and 2000 bars as of 2026.10.06 00:00. The panel and the log now say WHY, and the exact candles can be written to a file and replayed offline in the Python model.

Experts log, once per last closed bar and reason (`T003 DIAG1` .. `T003 DIAG8`; all times are server times as YYYYMMDDHHMM):
- DIAG1 verdict and reasons, the whole series, the A window (start, bars, warm-up end), the B window (start, bars, warm-up end) and the comparison-zone start (= B's warm-up end, events dated from there are compared);
- DIAG2 / DIAG3 the final state of A and of B: direction/phase, origin (BREAK or SEED) with its reference time and the bias start, the protecting level (id, price, known time, the three pivot times, FROZEN), the anchor and WHICH reference binds it (`origin`, `lv_pivot`, `lv_ext`, `lv_prev`, `wick`, `sweep`);
- DIAG4 the FIRST differing field in the explicit order `BIAS>PH>ORG>NR>LV>FRZ>WK>SW>REC>RSN>EL` with both values (for EL also the first differing FVG track);
- DIAG5 the first differing EVENT in the zone (index, type, absolute time, id, both sides) or `count differs: nA vs nB` with the first extra event;
- DIAG6 / DIAG7 for A and B: whether the protecting level is UNDEFINED at the last bar, since which bar, how many bars, what began the run (FLIP, BREAK_SET, SEED, LEVEL_DROPPED), runs and bars without a level in the window, flips in the window and after the run began, and WHY there is no level (no candidate / candidate already closed beyond, with the bar);
- DIAG8 on how many of the common bars the A and B state keys differ, first and last such bar.
The causes named by these lines are what the two replays show; why the situation arises on a real series is a HYPOTHESIS until a real CSV is replayed.

CSV export (`InpExportCandles = true`): after each evaluation the EA writes the full closed-bar set it evaluated (replays A and B are subsets of it) to
`<terminal data folder>\MQL5\Files\velo_t003_diag_<symbol>_<open time of the last closed bar, YYYYMMDDHHMM>.csv`
(File > Open Data Folder, then MQL5\Files; the Experts log prints the full path as `T003 EXPORT: ...`). One file per symbol, as-of and last bar; in live mode a new file appears for each new H4 bar, so turn the input off after collecting what you need. The file holds `#` header lines (symbol, period, digits, live/historical mode, the AsOfTime input, first and last bar, left/right, lookback, rebuild input, r_req, r_eff, b_depth, check depth, warm-up, hard cap, the EA's own result flag and reason, note) and then the columns `time_epoch,time_server,open,high,low,close,tick_volume,spread,real_volume`. Only closed bars are written (the forming bar is never read). Nothing else is written and no trading function is involved.

Offline replay (Python 3, no MT5 needed): `python3 tests/t003_replay_csv.py <file.csv>` runs the Python model on the file with the header's parameters, prints the same DIAG lines and says `REPRODUCED` when the model's flag and reason equal the EA's (header). `NOT REPRODUCED` means the model and the MQL5 code disagree on this series: that is itself the finding. Options: `--rebuild`, `--lookback`, `--asof "YYYY.MM.DD HH:MM"` for offline experiments (no reproduction claim is made then). A file whose header says `source=SYNTHETIC` is test data, not market data.

## 10. Known limits
- The diagnostics and the export are UNVERIFIED in MT5 (not compiled). Their text is checked only against the Python model.
- The panel size is estimated from the font size (character width is approximated); a very large font or a narrow chart may cut a line. The panel is positioned when it is redrawn, not on chart resize.
- Tauro versus TradingView candle and time alignment is not verified.
- A restart loses the in-memory NEW markers and the list of observed changes; the history is always rebuilt from the bars.
