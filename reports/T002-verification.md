# T002 verification record - H4 structure map (visual prototype)

Branch `claude/t002-h4-map`, based on the T001 head `56c9570` (PR velireci/EA-MT5#1 open, NOT merged). Rules are PROPOSED (tasks/T002-h4-map.md section C); they are not client answers.

## 1. Evidence, by kind
| Evidence | Status | Who/what |
|---|---|---|
| MQL5 compilation of `XauUsdH4Map.mq5` and `T002_LogicTest.mq5` | `44fddaa` and `9aeb8f7`: **0 errors, 0 warnings** (Codex, MetaEditor). After review round 2 (section 9): **UNVERIFIED** | No MetaEditor in my environment. The 0/0 covers `44fddaa` only; the T001 compile says nothing about this code. |
| Python reference model tests (`tests/t002_reference_test.py`) | PASS, 65 passed / 0 failed | Run by the implementing agent and again by me. They verify the ALGORITHM MODEL, not the MQL5 source. |
| Static checks (`tools/t002-static-checks.sh`) | PASS, exit 0 | Run by the agent and by me; includes negative controls (injected `OrderSend`/`MqlTradeRequest`/`CTrade`/`PositionClose`, unbalanced parentheses, format-string mismatch, altered generated data) all detected. Not a compilation. |
| T001 static checks and T001 files | unchanged / PASS | `git diff 56c9570 -- <T001 files>` is empty; `tools/t001-static-checks.sh` still passes. |
| MQL5 logic test script `src/tests/T002_LogicTest.mq5` | WRITTEN, NOT RUN | Compares the MQL5 logic with strings produced by the Python model on the same 31 cases. Only a run in MT5 shows that the two agree. |
| Drawing, panel, reload without duplicates | NOT OBSERVED | Owner check in MT5 (section 4). |
| Codex review | round 1 on `44fddaa` (5 findings, section 8); round 2 on `9aeb8f7` (2 findings, section 9); round 3 pending | |

## 2. What the Python tests cover (65 checks)
Unconfirmed swing; equal highs/lows; ambiguous outside bar; MIXED (equal and expanding) and UNKNOWN; missing interval (no preceding high, H<=L, bullish mirror); bullish and bearish FVG, including Low(C)==High(A) forming none; touch without invalidation; invalidation by close, equality not invalidating (both types); ERL taken (equality, touch before it was knowable, never restored); SELL ordering, price inside a zone, overlap/newer-first, ID tie-break, BUY mirror; no look-ahead (3 series, every prefix from 8 bars, compared with the full analysis restricted to what was knowable at T, plus a poison test with garbage bars after the prefix); ID uniqueness and determinism.
Not covered by automation: reload without duplicate objects, the drawer, the EA, the panel.

## 3. Equivalence risk between Python model and MQL5
The MQL5 was written by mirroring the Python; no known difference. Least certain: `%.2f` against `DoubleToString`; struct-array copy semantics; `D'...'` literals against `calendar.timegm`. Unchecked against the MQL5 documentation: `ObjectsDeleteAll` with a prefix, `ObjectSetInteger` with a time modifier, `CopyRates` into a non-series array, struct-with-string array assignment. Compile first; expect possible small fixes.

## 4. Visual check in MT5 (owner)
1. Copy `src/` into `MQL5/Experts/` keeping the folder layout; compile `src/XauUsdH4Map.mq5` and `src/tests/T002_LogicTest.mq5`. Note every warning.
2. Drag `T002_LogicTest` on any chart; the Experts log must end with `0 failed`. Report the whole log.
3. Attach `XauUsdH4Map` to an XAUUSD chart (any timeframe; the map uses H4 closed bars). Algo Trading may stay off; the EA has no order functions.
4. Expect: panel starting with "proposed H4 model - client validation pending"; SH/SL labels at the pivot with their confirmation time; direction; interval lines; ERL line (dashed when TAKEN); FVG rectangles with state labels; nearest IRL with a link to the ERL only when direction, interval and ERL are valid.
5. Compare against H4 candles by hand: a swing marked on the pivot candle but confirmed two H4 candles later; a FVG at three consecutive candles with a true gap between wicks; INVALID only after a close beyond the far edge.
6. Reload test: change an input, then remove and re-attach. Count objects named `velo_t002_*` (Ctrl+B): the number must not grow. Draw a manual line first: it must survive. Run T001 on another chart: its `velo_t001_*` objects must be untouched.
7. Leave it through one H4 close: the map recomputes once and the log prints one `H4 MAP recomputed` line.
8. Send the Experts log and a screenshot. These are the owner's observations, not mine.

## 5. Ambiguities in the task text, resolved minimally (owner/Codex to confirm)
1. ERL "taken" uses closed bars whose open time is >= range_known_time.
2. Containment in the interval is inclusive of the edges.
3. Added classes OPPOSITE (wrong-type FVG) and NONE (invalid, or no valid interval); only valid same-type FVGs inside the interval become IRL or OUTSIDE.
4. The link needs a selectable candidate (one ahead of price or INSIDE); a candidate behind price gives no link.
5. INVALID zones are hidden by default and shown dimmed with `InpShowInvalid`.
6. If all candidates are behind price: no link, the panel says "none".
7. Distance for ordering is 0 when price is inside, otherwise the gap to the near edge; price exactly on an edge counts as inside. Current price = Bid.
8. "Missing interval" cannot occur with real alternating bars; those tests use synthetic swing lists.
9. With no size filter an ordinary trend produces many FVGs: expect a busy chart (a point for the client).
10. TAKEN can lag the live price by up to one bar (closed bars only). Shown in the panel.
11. Styling choices: dashed ERL when taken, gold zone when INSIDE.
12. The EA works on the chart symbol only (no symbol input).

## 6. Points awaiting client validation
Swing definition 2/2; the direction test; which swing pair is the interval; whether an FVG must be inside the interval in price only or also in time; whether the same-direction FVG outside the interval can matter; FVG with no size filter; invalidation by close; whether touched zones stay eligible; ERL taken rule; nearest-first ordering with Bid. Open and not implemented: M5/M15 confirmation relation; policy below 2R.

## 7. Limits
Nothing here shows the EA is verified end to end, correct against the client's charts, live-ready or profitable. Compilation, MT5 behaviour, and agreement with the client's marked examples are all still unproven.

## 8. Review round 1 (Codex on `44fddaa`) and the fixes
Codex reported on `44fddaa`: compile 0/0 for both files, Python 65/65, MQL5 script and drawings NOT run in MT5. Five findings, fixed by the implementing agent (mql5-builder) without changing any strategy proposal:
1. History shorter than LookbackBars was accepted and never refreshed. Now: states INSUFFICIENT / PARTIAL (refreshing) / PARTIAL (no more on server) / COMPLETE, shown in the panel and logged once per change. A map built on partial history is re-checked with one `CopyRates` at most every 3 s and rebuilt only if more bars or an older first bar arrived; after 20 checks without progress it stops until the next H4 bar. No `Sleep`, no loop.
2. Stale map. When the H4 series is not ready, the copy fails, history is insufficient or the newest bar does not match the watcher, the map state is disabled and every `velo_t002_` object except the panel labels is deleted (swings, FVG, labels, ERL, range, link, INSIDE highlight). One log line on each clear and on rebuild, so it is visible with the panel off.
3. ERL TAKEN: the panel and zone labels no longer say "-> ERL" for an inactive setup; candidates show as "candidate (inactive: ERL TAKEN)" and the link stays absent. The same condition (`H4SetupActive`) drives the link and the panel.
4. Check 11 normalises CRLF/LF on both sides; negative control for altered data kept; a CRLF-copy equivalence control added.
5. Install paths: the EA goes under `MQL5/Experts/velo_src/`, the test script `T002_LogicTest.mq5` is a script (has `OnStart`) and goes under `MQL5/Scripts/velo_src/tests/` with `include/` next to it as a sibling (the relative include is kept). Section 4 step 1 above is superseded by this. Layout NOT tested in MT5.

Evidence for the fixes (my environment, after the change):
- `python3 tests/t002_reference_test.py`: 96 passed, 0 failed (31 new checks for history states, refresh decision, map transitions, `H4SetupActive`, panel wording for TAKEN versus UNTOUCHED). Model only.
- `bash tools/t002-static-checks.sh`: exit 0, negative controls 13a-13g detected; `bash tools/t001-static-checks.sh`: exit 0.
- **The changed MQL5 is UNCOMPILED. Codex's 0/0 on `44fddaa` is not inherited.** Constructs Codex's earlier compile did not exercise: a local `MqlRates` array with `ArraySetAsSeries`+`CopyRates` in `HistoryProbe`, `ArrayResize(g_order,0)`, `const SH4Result &` parameter, `datetime` parameters in the new helpers, `StringFind` in the test script, the new `#define H4_HIST_*`/`H4_ACT_*`, a `GetTickCount` subtraction for retry gating.
- Not observed in MT5: the throttle, clear/rebuild, panel wording, and the install layout. These are the owner's steps.
- Decisions beyond the findings: retries of a failed rebuild have only the 3 s throttle (no attempt cap); the 20-check cap applies to incomplete-history re-checks only; an inactive candidate keeps its fill and rank label without the gold INSIDE colour.

## 9. Review round 2 (Codex on `9aeb8f7`) and the fixes
Codex on `9aeb8f7`: EA and T002_LogicTest 0 errors, 0 warnings; static checks PASS; 96 Python tests PASS; MQL5 execution and drawings NOT run in MT5. Two findings, fixed by mql5-builder, strategy proposals unchanged:
1. After 20 checks without progress the EA stopped until the next H4 candle and said "no more on server" without evidence. Now it switches to a slower cadence (30 s) and shows "loading stalled; retrying"; when history arrives the map is rebuilt at that poll, without a new H4 bar, and the status and 3 s cadence return. The "no more on server" claim and the `exhausted` flag are removed from production code (only negative assertions remain in tests/checks). Complete history is never re-checked.
2. In the probe, `CopyRates <= 0` with an active map clears it (drawings removed, dynamic state off), does NOT increment the stall counter, and recovery goes through the normal no-map retry; the rebuild is logged with the clear reason.

Structure: the lifecycle decisions of Poll/HistoryProbe/RecomputeMap now live in pure functions (`H4LifeDecide` before a copy, `H4LifeOnCopy` after it, state `SH4Life`) in `H4Structure.mqh`; the EA functions are thin wrappers (CopyRates, drawing, logging) calling them. Statically checked wiring: CHECK 14.

Evidence (my environment): `python3 tests/t002_reference_test.py` 132 passed, 0 failed, including 16 scenarios driven through a Python model of the step functions with a scripted fake data source over simulated time: (a) history arrives after the 20th check (rebuild without a new bar, 30 s cadence, stalled text then cleared), (a2) stalled then partial progress, (b) history before the 20th check, (c/c2/c3) probe or build failure with an existing map (cleared, stall counter unchanged, recovery and rebuild logged), (d) series not ready then ready, (e1-e3) insufficient history, (f) newest-bar mismatch, (g) complete history, one copy in 600 s, (h) new bar resets the stall state, (i) `GetTickCount` wrap-around. `bash tools/t002-static-checks.sh` exit 0 (CHECK 11 with CRLF normalisation, negative controls 13a-13g, 14f); `bash tools/t001-static-checks.sh` exit 0. `src/tests/T002_LogicTest.mq5` mirrors the scenarios with the transcripts generated from the Python model (not run).

What this proves: the model of the step functions behaves as specified for scripted inputs. What it does not prove: MT5 behaviour, real `CopyRates`/`GetTickCount` semantics, the real watcher's `new_bar` reporting after not-ready periods, drawing cleanup, or that the MQL5 equals the Python model (only a compile and run of the script show that). The wrapper code itself is covered only by the CHECK 14 grep and a Python twin.

**The changed MQL5 is UNCOMPILED; the 0/0 on `9aeb8f7` is not inherited.** New constructs for Codex to watch: structs with `string` members passed as `&`/`const &` parameters, `uint` returned from unsigned subtraction, a string literal ternary as an argument; in the test script `int a[] = {...}` inside `case` blocks, an `ulong &` out-parameter, `(uint)(ulong % (ulong)4294967296)`, casts of large constants to `uint`, multi-declarator globals, transcript strings below 1800 characters (MQL5 literal limit unchecked).

Decisions beyond the two items: once stalled, the no-map retry also uses the 30 s cadence; a successful copy with nothing new counts as one idle check even after a failed copy; a complete-history build resets the stall counter; not-ready resets the counter and refreshes the status text.
