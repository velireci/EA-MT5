# T002 - H4 structure map (visual prototype)

Status: READY. Implementing agent: mql5-builder (single writer). Review: Codex after implementation.
Branch: `claude/t002-h4-map`, based on the T001 head `56c9570` (PR velireci/EA-MT5#1 is open and NOT merged).

## Objective
A visual-only EA that draws, on an H4-based map of the chart symbol: confirmed swings, trend direction, the structural interval, H4 fair value gaps (FVG) with their state, the ERL candidate, and the nearest IRL candidate with an IRL -> ERL link. Nothing here trades.

## Provenance of every rule (do not blur these)
A. CLIENT ANSWERS (submission XAU-20261006-E27N93, relayed as confirmed by the owner on 2026-10-07; original wording in inputs/client-E27N93/pergjigjet.json for the IRL/ERL narrative):
- Direction and context zones come from H4 only.
- Only setups in the trend direction, IRL -> ERL. ERL -> IRL is excluded.
- IRL in this strategy is an H4 FVG; a wick touch is enough.
- IRL is not the entry. After the touch a structure confirmation is needed; entry is at the M15 FVG after the break.
- The H4 FVG nearest to price on the way back is chosen first. If confirmation is missing, price may reach the next zone.
- ERL is the structural destination/target.

B. OWNER DECISIONS (2026-10-07, this task assignment):
- The owner authorised mechanical rules for the parts the client selects visually.
- The mechanics below are for a visual prototype only.
- Not in scope: M5/M15, entries, sizing, SL/TP, news, trade management.

C. PROPOSED ALGORITHMIC RULES (developer proposals awaiting the client's visual validation; NOT client answers; label them "proposed" everywhere, including the chart legend):
- Everything under "Mechanical rules" below.
- Specifically unvalidated: swing definition (2/2 fractal), the direction test, the interval choice, FVG containment in the interval, FVG invalidation by close, ERL "taken" rule, nearest-zone ordering.

D. STILL OPEN (do not implement, do not record as decided): exact M5/M15 confirmation relation; policy when the target is under 2R. A recommendation to skip below 2R exists but is NOT an approved decision.

## Mechanical rules (PROPOSED)
All logic uses CLOSED H4 bars only. The forming bar is never read by the H4 logic. Bar index 0 = oldest in the analysed window.
1. Swings. LeftBars=2, RightBars=2 (inputs). Swing high at i: High[i] strictly greater than High of the 2 closed bars before and the 2 after. Swing low: Low[i] strictly lower, same windows. Equal values do not qualify. Store pivot_time (open time of bar i) and confirm_time (close time of bar i+RightBars, i.e. open time + period seconds). A pivot is not available before confirm_time. A bar that qualifies as both high and low is AMBIGUOUS and is used neither for direction nor for the interval.
2. Direction. Last two confirmed swing highs and last two confirmed swing lows (non-ambiguous): lower highs + lower lows = BEARISH; higher highs + higher lows = BULLISH; any other combination, or equal values = MIXED; fewer than two of either = UNKNOWN. MIXED/UNKNOWN: no active IRL -> ERL setup is declared.
3. Interval. BEARISH: low L = latest confirmed swing low; high H = latest confirmed swing high whose pivot_time precedes L. BULLISH: high H = latest confirmed swing high; L = latest confirmed swing low preceding H. If the chronological pair is missing or H <= L: RANGE_UNDEFINED. ERL for SELL = L (low of interval); ERL for BUY = H. Show range_known_time = confirm_time of the later pivot.
4. ERL taken. After range_known_time, a closed H4 bar whose wick touches or crosses the ERL (SELL: Low <= ERL; BUY: High >= ERL) marks it TAKEN. TAKEN is never restored to untouched. Closed bars only, so it can lag the live price by up to one bar (document).
5. FVG. Triples of consecutive closed bars A, B, C. Bullish: Low(C) > High(A), zone [High(A), Low(C)]. Bearish: High(C) < Low(A), zone [High(C), Low(A)]. Confirmed at the close of C (confirm_time). No displacement or size filter.
6. FVG state, evaluated over closed bars after C only. INVALID: bearish FVG when a close is strictly above the upper bound; bullish FVG when a close is strictly below the lower bound (equality does not invalidate). TOUCHED: not invalid and a bar's wick range intersects the zone (inclusive). Otherwise FRESH. INVALID takes precedence over TOUCHED. A touch does not remove the zone. No re-use limit is defined.
7. IRL candidates. BEARISH direction: bearish FVGs fully inside [L, H]. BULLISH: bullish FVGs fully inside [L, H]. FVGs not fully inside (including partial overlap) are drawn separately as OUTSIDE and are never classified as active IRL. INVALID zones are not candidates. Whether the FVG must also have formed inside the swing leg in time is not decided; price containment only.
8. Visual selection. SELL: valid candidates whose lower bound is above the current price, ordered by lower bound ascending. BUY: candidates whose upper bound is below price, ordered by upper bound descending. If price is inside a zone it is shown as INSIDE and listed first; never skipped to pick a farther one. Ties/overlaps: order by distance, then newer confirm_time first, then ID ascending; zones are never merged. ID = stable string derived from the open time of bar A and the type (e.g. `F202610061200U`). Current price = Bid.
9. IRL -> ERL link is drawn only when direction is BULLISH/BEARISH, the interval is valid, the ERL is not TAKEN, and at least one candidate exists.

## Deliverables
- `src/XauUsdH4Map.mq5` (EA, inputs include LeftBars, RightBars, LookbackBars (default 300, clamp 50..1000), panel switch, colours simple), `src/include/H4Structure.mqh` (pure logic, no chart objects, no trading), `src/include/H4MapDrawer.mqh` (objects).
- T001 files stay unchanged; reuse `TimeframeWatcher.mqh`/`SymbolSnapshot.mqh` where useful.
- Object prefix `velo_t002_` only; delete only objects with that prefix, in Init and Deinit. Never touch manual drawings or `velo_t001_` objects.
- H4 logic recomputed on a new H4 bar and on init; only the price-vs-zone state refreshed at most once per second.
- Panel with the line "proposed H4 model - client validation pending", direction, interval, ERL state, nearest IRL, counts.
- No order/position API of any kind.
- `tools/t002-static-checks.sh` (+ reuse T001 python checkers), `tests/t002_reference_test.py` (controlled-data cases below), `src/tests/T002_LogicTest.mq5` script that runs the same cases inside MT5 (not run here).
- `reports/T002-verification.md`, updates to docs/STATE.md, STRATEGY_SPEC.md, DECISIONS.md, MT5 visual-check instructions.

## Required cases
Unconfirmed swing; equal highs/lows; MIXED trend; missing interval; bullish and bearish FVG; touch without invalidation; invalidation by close (and equality not invalidating); ERL taken; no use of bars after time T (analysis of a prefix must equal analysis of the full series restricted to what was knowable at T); reload without duplicate objects (MT5 check).

## Completion evidence
Compile only if MetaEditor is really available, otherwise UNVERIFIED. T001 compile evidence says nothing about this code. Python reference tests verify the proposed algorithm, not the MQL5 source. MT5 visual checks are owner-observed and separate.
