# T003 - H4 direction change and reconfirmation (specification draft)

Status: DRAFT. NOT started. This file is a reviewable specification only: no MQL5, no tests and no tools exist for it yet, and none may be described as implemented or passed. Implementation needs the owner's explicit go after Codex's review of this text.
Builds on T002 (PR velireci/EA-MT5#2, draft, not merged) and keeps T002's behaviour and tests unchanged.
Out of scope: M5/M15 logic, entries, sizing, SL/TP, 2R policy, news, trade management, handling of positions that are already open.

## 1. Provenance (never blur these)
A. CLIENT STATEMENTS, text clarifications of 2026-10-13 relayed by the owner (also in docs/DECISIONS.md and docs/STRATEGY_SPEC.md):
- S1. A change from bearish to bullish direction requires a break of the relevant H4 structural level. In the client's picture the first marked level is enough; breaking the higher high as well is not required. Picture prices are examples. "First level" is not automatically the nearest high or any small swing; the algorithmic choice is still to be formalised.
- S2. The pass must be with the body. A wick-only pass does not confirm a direction change and may be a liquidity grab.
- S3. SELL: after a wick above the structural level the robot stops NEW entries from the previous setup and waits for reconfirmation. Silent about positions that are already open.
- S4. SELL reconfirmation needs a NEW bearish H4 FVG formed AFTER the wick; a pre-wick FVG is not enough even if touched again.
- S5. After the new H4 FVG: wait for the touch (wick touch allowed); wait for the close of the touching candle "per the rule documented earlier"; then a new M15 structure break; entry at the M15 FVG after the break. H4 FVG/IRL is context, not entry; trend-direction setups only, IRL -> ERL.
- S6. Open: the role of M5 in M15 confirmation; the policy when the ERL target is below 2R. Not decided here.
Screenshots are illustrations. No price, date or candle index may be hard-coded, and where a text clarification exists it wins over how arrows or shapes might be read. The zone drawn in the client's screenshot must not be assumed to be the "new FVG after the wick"; that was confirmed separately in text (S4).

B. EARLIER AUTHORISED DECISION: the owner's authorisation (2026-10-07) to create mechanical rules, as proposals awaiting visual validation, for what the client selects visually. The T002 proposals (2/2 swings, confirmed pivots, direction test, FVG definition and states, closed bars only) stay as they are.

C. PROPOSALS of this task (section 3 onward): developer proposals, NOT client answers, to be labelled "proposed" in any drawing or log.

D. OPEN questions that affect implementation: section 8.

## 2. Terms
- Closed bars only, chronological, as in T002. The forming bar is never read by this logic.
- Pivot time = open time of the pivot candle. Confirmation time = close of the 2nd bar to its right (T002). A swing, and anything derived from it, is unknown before its confirmation time. Marks placed at the pivot must show the confirmation time so they do not suggest earlier knowledge.
- Body break (proposal P1): an H4 candle CLOSE strictly beyond the level (SELL context: close > S; BUY context: close < S). Equality is not a break.
- Wick only (P1): high > S (BUY: low < S) with the close not beyond S.
- Event time: a bar's events are known at that bar's close (open time + period).

## 3. Proposals
P1. Body versus wick as in section 2. Both are evaluated per closed bar; a body break takes precedence over wick-only for the same bar.

P2. Structural level (formalises "the relevant level"). SELL context (bearish bias): consider the confirmed, non-ambiguous swing lows in order. A "lower low" is one strictly below the confirmed low immediately before it; equality is not lower. Take the latest lower low (index j) and the low before it (j-1). The structural high S is the HIGHEST confirmed swing high whose pivot lies strictly between those two lows. Consequences: swing highs inside the leg that are not its top, and corrective higher lows after the last lower low, never become the level; the higher high before the leg is not used (S1: not required). If a bound or the high is missing, or any bar after S's pivot up to now has a high above S, the level is UNDEFINED ("no evidence"; the previous level is kept if one exists). The level is known from max(confirmation of S's pivot, confirmation of the lower low); only bars opening at or after that time can produce events against it. BUY context is the mirror: latest higher high, structural low S = LOWEST confirmed swing low strictly between that high and the high before it.

P3. Bias layer with hysteresis, next to T002's swing-based direction (which is unchanged and still displayed; the two may disagree). States: NONE (no evidence) -> BIAS_BEARISH / BIAS_BULLISH when T002's direction is BEARISH / BULLISH and a level is defined. Once in a bias, it is kept until a body break of its level (S1/S2), whatever T002's direction says (including MIXED). A level may be re-derived while the bias is ACTIVE; it is frozen during HOLD and RECONFIRMED. After a flip the new bias has no level until P2 yields one; no reversal can fire without a level.

P4. Wick event. A wick-only bar against the level moves ACTIVE -> HOLD. Record wick_bar (index, open time) and wick_known_time (its close). From wick_known_time new entries from the previous setup are blocked (S3). The structure is not cancelled: the bias stays (a wick is not a direction change, S2).

P5. Eligible new FVG (S4), SELL: a bearish H4 FVG (T002 definition) whose candle A is the wick candle or later, hence candle C closes after the wick; no candle before the wick candle takes part. Pre-wick FVGs are marked PRE_WICK and are ineligible for reconfirmation even if touched again. BUY: bullish FVG, same timing.

P6. Reconfirmation, per eligible FVG and on closed bars after its candle C, with T002's state rules: INVALID when a close is strictly beyond its far edge (SELL: close above the upper bound); TOUCHED when a bar's wick range intersects the zone; INVALID wins on the same bar. The touch counts at the CLOSE of the touching candle (D2). A touched, still valid eligible FVG moves HOLD -> RECONFIRMED_H4 and records its ID. If several are eligible, T002's nearest-first ordering decides which is shown first; each can be reached in turn.

P7. Transitions that interrupt the wait: a body break (HOLD or RECONFIRMED) flips the bias and discards the reconfirmation progress; another wick-only bar restarts HOLD from the LATEST wick (earlier eligible FVGs become PRE_WICK, since they now precede the latest wick); the recorded FVG becoming INVALID returns RECONFIRMED -> HOLD; an eligible FVG becoming INVALID before touch is dropped, and with none left HOLD continues waiting. RECONFIRMED_H4 only means "H4 context ready, awaiting a new M15 structure break"; the M15 phase is not part of T003.

P8. BUY mirrors every rule. It is a proposal: the client's clarification was given for SELL.

P9. Live and historical share one pure replay over closed bars: `bars[0..n-1]` -> bias state, level, events with their times, eligible FVGs. Live applies it on init and on each new closed H4 bar over the configured lookback; historical applies the same function to the bars closed by AsOfTime (T002's as-of filter). The replay is causal: state at bar t uses only swings confirmed by t and bars up to t. A given window is deterministic, but the starting state is NONE at the window start, so a longer or shorter lookback can give a different early state; reports must state the window.

## 4. States and transitions (SELL naming; BUY by mirror)
| From | Event on closed bar t (level S known) | To | Notes |
|---|---|---|---|
| NONE | T002 direction BEARISH and S defined | BIAS_BEARISH (ACTIVE) | level locked and re-derived each bar while ACTIVE |
| ACTIVE | close_t > S | BIAS_BULLISH (ACTIVE, no level yet) | direction change confirmed with the body |
| ACTIVE | high_t > S and close_t <= S | HOLD (w = t, S frozen) | new entries from the previous setup blocked |
| HOLD | close_t > S | BIAS_BULLISH | reconfirmation discarded |
| HOLD | high_t > S and close_t <= S | HOLD (w = t) | restart from the latest wick |
| HOLD | an eligible FVG is touched, not invalid, at close_t | RECONFIRMED_H4 (FVG id) | M15 phase not implemented |
| RECONFIRMED | close_t > S | BIAS_BULLISH | discarded |
| RECONFIRMED | high_t > S and close_t <= S | HOLD (w = t) | restart |
| RECONFIRMED | recorded FVG becomes INVALID | HOLD | wait for another eligible FVG |
Order inside one bar: update swings from the prefix; test events of bar t against the level held before t; update FVG eligibility and states with bar t; then re-derive the level if ACTIVE.

## 5. What is cancelled and what is kept after a wick
- Blocked/cancelled: new entries from the previous setup; the eligibility of every pre-wick FVG; any pending M15 setup derived from them (a requirement for the later M15 task, nothing exists now).
- Kept: the bias (a wick is not a direction change); T002's swings and FVG states and their drawings (pre-wick FVGs shown as PRE_WICK); the frozen level S.
- Not decided: positions already open (S3 is silent, D4); ERL/target after a flip.

## 6. Live and historical behaviour
- No candle after the evaluation time is read. In historical mode the evaluation time is AsOfTime (broker/server time as shown by MT5, not UTC, not TradingView time; equality with the client's chart is not assumed).
- Marks at the pivot carry the confirmation time. The wick mark carries the wick bar time and the time it became known.
- Closed-bar rule consequence: a wick on the forming bar is not an event until that bar closes, so the block of new entries can lag by up to one H4 bar. Whether the forming bar's high must block immediately is open (D1).

## 7. Acceptance criteria (for the later implementation)
1. Every rule above is traceable to S1-S6 or labelled proposed; no price, date or index is hard-coded.
2. Level selection follows P2, including: minor swings and corrective lows never become the level, and the higher high before the leg is never required.
3. A close beyond the level changes the bias; a wick alone never does, in either direction.
4. After a wick, no pre-wick FVG can reconfirm; a post-wick FVG can, only after its own touch closes.
5. The replay is causal, and live and historical use the same function; as-of results do not depend on bars after the as-of time.
6. T002 behaviour and tests are unchanged; no order or position API; no M15/M5 code.
7. Drawings and panel show the bias, the level (with pivot and confirmation times), the wick event (bar time and known time), and eligible versus PRE_WICK FVGs, and state when the bias and T002's direction disagree. Labels must not hide the panel or candles (the owner observed overlapping labels in T002).
8. Compilation, tests, script runs and MT5 observation reported separately and attributed.

## 8. Open questions that affect implementation
- D1. Intrabar wick blocking versus closed-bar only (up to one H4 bar of delay).
- D2. The "rule documented earlier" for the close of the touching candle was not found in the repository documents. The proposal reuses T002's closed-bar touch rule (the touching H4 candle counts at its close). Needs the client's confirmation, including whether a lower-timeframe candle is meant.
- D3. Whether a post-wick FVG must lie inside T002's interval; how the ERL/target is chosen after a flip.
- D4. Positions already open when a wick or flip occurs.
- D5. M5 role; the policy below 2R. A recommendation to skip below 2R exists and is NOT an approved decision.
- D6. Whether the frozen level should be re-derived after a new lower low during the wait; whether the BUY mirror is what the client wants; how long RECONFIRMED stays valid (Q03).

## 9. Tests the implementation must include (none exist yet; none are claimed)
Controlled-data cases, pure logic first (same style as T002):
1. Break by close versus wick only (both directions; equality is not a break).
2. A correction that does not change the bias (T002 direction MIXED while the bias stays, no level break).
3. A wick that blocks new entries (HOLD entered, block time = the wick bar's close).
4. A pre-wick FVG that is not eligible, even when touched again after the wick.
5. A new FVG after the wick: A = wick candle accepted, A before the wick rejected; touch then close.
6. Repeated events: a second wick restarts HOLD; invalidation before the touch; invalidation after RECONFIRMED; body break during HOLD and during RECONFIRMED; direction flip while waiting.
7. Level selection: minor swings ignored, the leg's top chosen, the higher high before the leg not required, undefined when a bound is missing or the level was already touched.
8. Historical analysis: results at as-of time T identical when later bars are replaced by garbage; the replay on a prefix equals the full replay restricted to what was knowable at T, for many T; replay window effects reported.
9. Lifecycle and reload: no duplicate objects, clear/rebuild as in T002.
10. BUY mirror cases.
