# T003 visual EA - installation and use

> INTEGRATION NOTE (2026-10-13, PROPOSAL / PROTOTYPE, awaiting the client): the EA and the drawer were rewritten for the revision 10 prototype of `src/include/H4Bias.mqh` (commit `2837527`, NOT changed by this round): STRUCTURE (bias, CURRENT protecting level) and SETUP (setup_id, snapshot, wick/sweep record, FVG tracks) are shown apart; the protecting level follows the ratchet and is not held fixed; the snapshot is a reference only. The T003 bias is a developer proposal and is never presented as the client's confirmed direction. New: the T002 source swings, MODEL DISAGREEMENT, the SETUP block with the ready flag, and a HISTORICAL LIQUIDITY layer (a proposal). Relayed evidence (Codex / owner, NOT my runs): `T003_LogicTest.mq5` with `H4Bias.mqh` at `2837527` compiled with 0 errors, 0 warnings (Codex) and ran in MT5 with "404 passed, 0 failed, 5 deferred" (owner; deferred are not passes); that is a test of the logic against the Python model, not an agreement with the client's strategy. THIS integration (the EA, the drawer, `H4BiasLayers.mqh`) is NOT compiled in MetaEditor and NOT observed on a chart.

`src/XauUsdH4Bias.mq5` is a SEPARATE Expert Advisor next to the T001 foundation EA and the T002 map EA. It draws the T003 bias logic (`src/include/H4Bias.mqh`) on an XAUUSD chart so the owner can compare it with the client's examples (task section 10). It contains no trading function at all: it cannot send, modify or close an order, and it opens no M5/M15 series.

STATUS (read this first)
- Every rule it shows is a PROPOSAL (tasks/T003-h4-bias-change.md), not a confirmed client rule. The panel says so. A picture that "looks right" is an observation, not a validation.
- An earlier version of the EA was compiled by Codex at `abd4c1b` (0 errors, 0 warnings, relayed) and observed once by the owner on XAUUSD H4 (relayed, section 9): LIVE and historical both gave LIMITED_BY_HISTORY (a different, older logic). THIS version (integration with the revision 10 prototype, the diagnostics and the export of section 9, the layers of sections 6-7) is NOT compiled and NOT observed (UNVERIFIED). Evidence so far: static checks (`bash tools/t003-visual-static-checks.sh`) and a C++ transliteration run of the pure helpers (`bash tools/t003-xlate-check.sh`, NOT MetaEditor). The next step is Codex's compile of `XauUsdH4Bias.mq5`, then the owner's observation.
- Out of scope, not drawn: the intrabar overlay (P12), the target (P13), M5/M15, entries, orders, positions.

## 1. Files to copy
Copy the whole repository `src/` folder to `<terminal data folder>/MQL5/Experts/velo_src/` (File > Open Data Folder in MT5). After copying, `MQL5/Experts/velo_src/XauUsdH4Bias.mq5` sits next to `MQL5/Experts/velo_src/include/`, because the include lines are relative to the EA file. Files used by this EA:

| File | Role |
|---|---|
| `XauUsdH4Bias.mq5` | the EA (inputs, live/historical flow, panel text) |
| `include/H4BiasDrawer.mqh` | chart objects and the panel (prefix `velo_t003_`) |
| `include/H4BiasLayers.mqh` | NEW: PURE helpers of the visual layers (MODEL DISAGREEMENT, the T002 source swings, the historical liquidity selection, short object-name parts). No chart, series, file, clock or trading call; it never changes the bias |
| `include/H4Bias.mqh` | T003 logic (revision 10 prototype), unchanged by this round |
| `include/H4Structure.mqh` | T002 swings, FVGs, direction, copy helpers, unchanged |
| `include/SymbolSnapshot.mqh`, `include/TimeframeWatcher.mqh` | T001 helpers, unchanged |

The tests `src/tests/T003_LogicTest.mq5` (the logic) and `src/tests/T003_LayersTest.mq5` (the pure helpers of `H4BiasLayers.mqh`) are SCRIPTS and are installed separately under `MQL5/Scripts/velo_src/tests/` with `include/` as their sibling (as for T002). They are not needed by the EA. `T003_LayersTest.mq5` has been run only through the C++ transliteration (57 passed, 0 failed; NOT MetaEditor, NOT MT5); in MT5 it is written but not compiled or run.

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
| InpShowLiquidity | true | draw the HISTORICAL LIQUIDITY layer (section 6.4). Off = nothing of it is computed or drawn |
| InpLiqMax | 6 | most liquidity levels drawn (0..50), the NEAREST to the last closed bar's close first |

The picture needs at least 3*L = 900 closed H4 bars (defaults). With less history the panel shows LIMITED_BY_HISTORY with the reason (for example `SHORT_HISTORY`), the bias is UNKNOWN and nothing proposal-derived is drawn.

## 4. Live mode (InpAsOfTime = 0)
Attach to an XAUUSD H4 chart. The logic is replayed when an H4 bar CLOSES; the forming bar is never read and no price is used. At start, restart, input change or recovery from a data problem the current history is the BASELINE: its events are drawn dimmed/coloured by type and are NOT reported as new. Events produced by bars that close after the baseline are drawn larger, in green, prefixed `>> NEW`, listed `[NEW]` in the panel and logged as `T003 NEW EVENT`. If the evaluation is not reliable, or the previous bar's state cannot be reproduced, nothing is reported as new and the log says why (`T003 consumer ...`). Bias, T002 direction, phase and setup changes seen while running are logged (`BIAS CHANGED`, `T002 DIRECTION CHANGED`, `PHASE CHANGED`, `SETUP CHANGED`) and the last four are shown in the panel. Only MARKET events are reported as `NEW`; observations (CONTINUATION, INTERNAL_BREAK, NONE_WICK, CONFLICT, the diagnostic SNAPSHOT_CROSSED) are logged as `T003 observation (not a market event)`. MODEL DISAGREEMENT (section 6.2) is logged once per change.
When the H4 series is not ready or a copy fails, all `velo_t003_` map objects are removed and the panel states the reason; when the data returns, the picture is rebuilt from a new baseline.

## 5. Historical mode (InpAsOfTime > 0)
Set InpAsOfTime in SERVER time (the time axis of the MT5 chart). Only bars closed by that time are used, no live price is read, new bars do not change the picture, and no event is marked NEW (the panel lists the latest events with their bar times). The panel shows the as-of time and the last closed H4 bar used. To compare with a client example pick an as-of time just before the event, then a few bars later, and record what changes. A changed input re-initialises the EA.

## 6. Reading the picture
Everything is a PROPOSAL / PROTOTYPE. When the support flag is LIMITED_BY_HISTORY NOTHING proposal-derived is drawn (no structure, no setup, no liquidity layer, no disagreement) and no market event is raised: only the reliability part of the panel remains (6.6).

### 6.1 T002 structure (the market structure as T002 reads it, a proposal)
- Panel: `T002 structure (2/2 swings, proposal): BULLISH (HH+HL) | BEARISH (LH+LL) | MIXED | UNKNOWN`, since which bar, the previous direction, and `T002 sources`: the two latest confirmed swing highs (`H-latest`, `H-prev`) and the two latest swing lows (`L-latest`, `L-prev`), each with price, PIVOT time and CONFIRMATION time (`known`, the close of the second bar to the right).
- Chart: a white text mark `T002 <tag> SH|SL price pivot <time> known <time>` near each of these four pivots (shifted a little away from the candle), and `T002 structure ...` above the last closed bar. The words HH+HL / LH+LL are the client's description of direction (N1); WHICH swings count is NOT confirmed (the 2/2 fractal is a proposal).

### 6.2 T003 prototype bias, the protecting level, MODEL DISAGREEMENT
- `T003 PROTOTYPE bias (PROPOSAL, NOT the client's confirmed direction): BULL|BEAR phase ... origin ... since ...` and the phase reason (panel); the same bias is written under the last closed bar.
- CURRENT protecting level: a SOLID line from its pivot to the right edge, label `CURRENT protecting level (PROPOSAL) <price> known <time> - decides FLIP`. It follows the revision 10 ratchet, so it can move. The swings it was selected from are marked `S`, `LL`/`HH`, `prevLL`/`prevHH` with `known <confirmation time>`.
- MODEL DISAGREEMENT (technical definition, a PROPOSAL): it exists ONLY when T002 is BULLISH (HH+HL) and the T003 bias is BEAR, or T002 is BEARISH (LH+LL) and the T003 bias is BULL. T002 MIXED or UNKNOWN, or no T003 bias, is NOT a disagreement. When it exists the panel line and an orange label next to the last closed bar read `MODEL DISAGREEMENT - client validation pending: T002 <dir> (<HH+HL|LH+LL>) vs T003 prototype bias <BULL|BEAR>, since closed bar <open time> (known <close time>), <n> closed bar(s)`; a dotted vertical line marks the start. The start and the count are derived from the replay by ABSOLUTE bar times (the T002 direction known at each bar versus the bias after each bar's close); a run that reaches the start of the trusted bars says `or earlier`. It is logged ONCE per change (`T003 MODEL DISAGREEMENT ...`); at start, rebuild, gap and in historical mode it is labelled a STATE, not a market change. It is a finding about the proposal (the bias holds until a close beyond the protecting level, tasks section 13.6), not an error.

### 6.3 SETUP (separate from the structure)
- Panel block `SETUP`: `setup_id`, direction, type (WICK or SWEEP), reason (STRUCT or INTERNAL), phase (ACTIVE = no setup, HOLD, SWEEP_WAIT, RECONFIRMED), `READY yes/no` (true only in RECONFIRMED; M15 is not built, so READY is not an entry), the SNAPSHOT level, the current level, the wick record (`source_wick_time | known | detected_at | retroactive`), the internal sweep, the number of eligible new FVGs and the reconfirmation FVG with its bounds, confirmation time and valid-from. PRE_WICK FVGs (older than the wick) are listed as ineligible. The two entry-block flags are REPORTED ONLY.
- Chart: the SNAPSHOT of the protecting level at the creation of the setup is a DASHED goldenrod line labelled `snapshot (reference only) <price> known <time>` (`= current level` when it is the same level); the CURRENT level is the SOLID line (6.2). The snapshot never decides a flip. `WICK ...` and `detected_at` marks, `INTERNAL SWEEP` mark, eligible FVG rectangles (gold, filled = reconfirmation FVG), `SETUP (PROPOSAL) <type> <reason> phase ... ready ...` under the last bar. SETUP_ENDED events (reasons INVALIDATED_BY_FLIP, REPLACED) appear as event texts; SNAPSHOT_CROSSED is a diagnostic and appears only with InpShowNonMarket.

### 6.4 HISTORICAL LIQUIDITY layer (PROPOSAL - historical liquidity, not ERL / target / protecting level)
- What: the confirmed 2/2 swing highs and lows (the T002 swing function, confirmation time known at the evaluation) that NO later closed bar has exceeded by a WICK: a later `high` above a swing high, or a later `low` below a swing low (strictly; an equal value is a touch). Closed bars only, no live price. Drawn as thin DOTTED lines from the pivot time to the right edge with a small label `liq SH|SL <price> (pivot <time>)` at the pivot; the panel lists them (`liq SH|SL price pivot ... known ...`).
- Limit: at most `InpLiqMax` (default 6), chosen as the levels NEAREST to the close of the last closed bar (ties: the more recent pivot). The panel says how many unexceeded swings exist in total. `InpShowLiquidity = false` switches the layer off.
- It does NOT change the bias, is NOT an ERL, a target or a protecting level, and is not fed to `H4Bias.mqh` (it lives in the drawer and `H4BiasLayers.mqh`; static checks forbid any write into the state). The client confirmed the CONCEPT of historical liquidity (N2); the 2/2 fractal and this mechanical definition are PROPOSALS, as is the choice of the nearest levels. An old liquidity level is not a reason to keep a direction (N2).

### 6.5 Events
`NEW` markers, the last events and the counts as in section 4. Event texts above the bar show type and direction (`FLIP BULL->BEAR`, `WICK BEAR retro`, `SETUP_ENDED REPLACED`, ...).

### 6.6 A/B reliability
`support: CONVERGED | SEEDED | LIMITED_BY_HISTORY - reason`, the depths (R requested/used, B depth, warm-up, check depth, bars available) and the note. Reasons: `AB_STRUCTURE_DIFF` (replays A and B differ in the structure), `AB_SETUP_DIFF` (in the setup), `AB_EVENT_DIFF` (in the events of the compared zone), `ANCHOR_IN_WARMUP`, `ANCHOR_HISTORY_MISSING`. `ORG_DIFF A=.. B=..` in the note is INFORMATIONAL (the origin name differs; never a reason). When LIMITED the bias is UNKNOWN, the DIAG lines (section 9) explain why, and nothing else is drawn. SEEDED = a reliable state whose origin is the T002 seed. CONVERGED = A and B agree.

### 6.7 Objects
Only objects whose name starts with `velo_t003_` are created or deleted (the panel uses `velo_t003_pnl_`). Manual objects and the T001/T002 objects are never touched. Object names use times and a short hash of long ids (chart object names are limited in length; MT5's limit is believed to be 63 characters, NOT verified here). Running T002 and T003 on the same chart is possible but their panels may overlap; use the corner inputs.

## 7. What to send back
1. The MetaEditor compile log (full text).
2. The Experts log from attaching the EA until a few minutes after (the `T003 ...` lines, any `NOTICE`, `INIT FAILED` or `picture cleared` line, and the `T003 DIAG1..DIAG8` lines when the support flag is LIMITED_BY_HISTORY).
3. Screenshots of the whole chart with the panel visible, in live mode and for each as-of time used in historical mode, together with the as-of value, the MT5 build and the broker/server name. Take one with the liquidity layer ON and one with `InpShowLiquidity = false` if the chart looks crowded.
4. For each client example (task section 10, V1-V8; V9 needs the target, which is not drawn): the candle (by server time) the robot used for the level versus the candle the client marked, and what the robot reported for the wick/sweep, the FVG and the touch. Say who observed it. Mark "same / different / robot undefined"; do not write "validated".
5. For a LIMITED_BY_HISTORY case: set `InpExportCandles = true` (and `InpDiagnostics` stays true), attach the EA live on XAUUSD H4 (and/or set `InpAsOfTime`, for example 2026.10.06 00:00), and send back (a) the `velo_t003_diag_XAUUSD_<last bar>.csv` file(s) from `MQL5\Files`, (b) the Experts log with the `T003 DIAG` and `T003 EXPORT` lines, (c) a screenshot with the panel visible. The CSV is price data of the broker's own XAUUSD H4 chart: send it only through the owner's usual private channel and do not publish it.
6. For MODEL DISAGREEMENT, SETUP and the liquidity layer: see section 7a.
7. Any behaviour that looks wrong: object overlap, a panel that is cut off or hides candles, a missing object, a long delay on attach (the first rebuild replays up to 1000 bars four times).

## 7a. Comparing the robot with the client's examples (an observation, not a validation)
For each client example (task section 10) set `InpAsOfTime` (server time) to the close of a candle just BEFORE the client's event, then 1, 2, 4 and 8 candles later, take a screenshot each time and note, by the candle's server time:
1. T002 structure and its four source swings: are they the swings the client marks as HH/HL or LH/LL (same candle, different candle, not marked)?
2. T003 bias and the CURRENT protecting level: is it the level the client uses (same candle / different / undefined)? Did the level move (ratchet) between the screenshots? Which candle would the client call the wick, the grab, the change?
3. MODEL DISAGREEMENT: does it appear? Since when and for how many bars? In the client's example is the T002 reading or the T003 bias closer to what the client calls the direction? (Write what you see; do not call either right.)
4. SETUP: setup_id, phase and reason; snapshot versus current level; source_wick_time, known, detected_at; whether the FVG the client marks is among the eligible new FVGs and which one is the reconfirmation FVG; whether READY appears when the client would expect the next step.
5. HISTORICAL LIQUIDITY: are the red lines the client draws among the liquidity levels (same pivot / different / missing)? Which drawn levels would the client NOT call liquidity? Does a level the client keeps for days appear here?
6. LIMITED_BY_HISTORY: copy the support line and the DIAG lines; nothing else is drawn then, which is expected.
Mark each as "same / different / robot undefined / client not stated". Never write "validated". Send the Experts log, the screenshots and the compile log (section 7).

## 8. Reading a change notice
`BIAS CHANGED`, `T002 DIRECTION CHANGED`, `PHASE CHANGED` and `SETUP CHANGED` (panel "observed live" and Experts log) appear ONLY when the new closed bar followed the previous evaluated bar directly and the previous state was reproduced by the new window (consumer status OK, the same step that makes an event NEW). If bars were missed (consumer GAP), the window slid or the depth changed (REDERIVED) or the same bar was evaluated twice, a difference is logged as `T003 RE-DERIVATION (consumer ...)` with the cause and is NOT a market change. Before the diagnostics round every difference between two reliable evaluations was shown as a change (reporting defect, fixed; reports/T003-verification.md section 10.3).

## 9. Diagnostics and candle export (LIMITED_BY_HISTORY)
Why: the owner's observation (relayed) was LIMITED_BY_HISTORY with `AB_STATE_DIFF+AB_EVENT_DIFF+ANCHOR_IN_WARMUP` at R=1000 live and at 1000 and 2000 bars as of 2026.10.06 00:00. The panel and the log now say WHY, and the exact candles can be written to a file and replayed offline in the Python model.

Experts log, once per last closed bar and reason (`T003 DIAG1` .. `T003 DIAG8`; all times are server times as YYYYMMDDHHMM):
- DIAG1 verdict and reasons, the whole series, the A window (start, bars, warm-up end), the B window (start, bars, warm-up end) and the comparison-zone start (= B's warm-up end, events dated from there are compared);
- DIAG2 / DIAG3 the final state of A and of B: direction/phase, origin (BREAK or SEED) with its reference time and the bias start, the protecting level (id, price, known time, the three pivot times), the anchor and WHICH reference binds it (`origin`, `lv_pivot`, `lv_ext`, `lv_prev`, `wick`, `sweep`);
- DIAG4 the FIRST differing field in the explicit order `BIAS>LV>EX>LI>BS>SU>PH>SRC>WAIT>REC>RSN>EL` (the first five are the STRUCTURE key, the rest the SETUP key) with both values (for EL also the first differing FVG track); an `ORG_DIFF` is shown as provenance only;
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
- The integration of the revision 10 prototype, MODEL DISAGREEMENT, the SETUP block and the liquidity layer are UNVERIFIED in MetaEditor and on a chart. The pure helpers were run only in a C++ transliteration (tools/t003-xlate-check.sh).
- The liquidity layer, its nearest-first choice, the disagreement definition and the fractal 2/2 swings are technical proposals. The client confirmed the concept of historical liquidity and the wording HH+HL / LH+LL, not these algorithms.
- Chart object names are short (hash of long ids) because MT5 limits their length (believed 63 characters; not verified). The previous drawer built names from full event ids; they could have exceeded that limit, which was never observed because the only observed run was LIMITED_BY_HISTORY (nothing drawn).
