# T002 verification record - H4 structure map (visual prototype)

Branch `claude/t002-h4-map`, based on the T001 head `56c9570` (PR velireci/EA-MT5#1 open, NOT merged). Rules are PROPOSED (tasks/T002-h4-map.md section C); they are not client answers.

## 1. Evidence, by kind
| Evidence | Status | Who/what |
|---|---|---|
| MQL5 compilation of `XauUsdH4Map.mq5` and `T002_LogicTest.mq5` | **UNVERIFIED** | No MetaEditor here. The T001 compile (0/0 on `763227d`) says nothing about this code. |
| Python reference model tests (`tests/t002_reference_test.py`) | PASS, 65 passed / 0 failed | Run by the implementing agent and again by me. They verify the ALGORITHM MODEL, not the MQL5 source. |
| Static checks (`tools/t002-static-checks.sh`) | PASS, exit 0 | Run by the agent and by me; includes negative controls (injected `OrderSend`/`MqlTradeRequest`/`CTrade`/`PositionClose`, unbalanced parentheses, format-string mismatch, altered generated data) all detected. Not a compilation. |
| T001 static checks and T001 files | unchanged / PASS | `git diff 56c9570 -- <T001 files>` is empty; `tools/t001-static-checks.sh` still passes. |
| MQL5 logic test script `src/tests/T002_LogicTest.mq5` | WRITTEN, NOT RUN | Compares the MQL5 logic with strings produced by the Python model on the same 31 cases. Only a run in MT5 shows that the two agree. |
| Drawing, panel, reload without duplicates | NOT OBSERVED | Owner check in MT5 (section 4). |
| Codex review | pending | |

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
