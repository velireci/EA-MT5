# T003 - H4 direction change and reconfirmation (specification draft, revision 2)

Status: DRAFT. NOT started. This file is a reviewable specification only: no MQL5, no tests and no tools exist for it, and none may be described as implemented or passed. Implementation needs the owner's explicit go after Codex's review of this text.
Builds on T002 (PR velireci/EA-MT5#2, draft, not merged) and keeps T002's behaviour and tests unchanged.
Out of scope: M5/M15 logic, entries, sizing, SL/TP, the 2R policy, news, trade management, handling of positions that are already open.
Revision 2 (2026-10-13) adds the client's BUY example, corrects the touch rule (now client information), and answers Codex's remarks on the level, the start of the bias, continuity across windows, and intrabar blocking.

## 1. Provenance (never blur these)
A. CLIENT STATEMENTS, text clarifications and examples relayed by the owner (also in docs/DECISIONS.md and docs/STRATEGY_SPEC.md):
- S1. A change from bearish to bullish direction requires a break of the relevant H4 structural level. In the client's first picture the first marked level is enough; breaking the higher high as well is not required. "First level" is not automatically the nearest high or any small swing; its algorithmic choice is still to be formalised.
- S2. The pass must be with the body. A wick-only pass does not confirm a direction change and may be a liquidity grab.
- S3. SELL: after a wick above the structural level the robot stops NEW entries from the previous setup and waits for reconfirmation. Silent about positions that are already open.
- S4. SELL reconfirmation needs a NEW bearish H4 FVG formed AFTER the wick; a pre-wick FVG is not enough even if touched again.
- S5. After the new H4 FVG: the touch happens at that H4 FVG (a wick touch is allowed) and we wait for the close of the H4 candle that touched it (an earlier client clarification relayed by the owner; its original wording is not in the repository); then a new M15 structure break; entry at the M15 FVG after the break. H4 FVG/IRL is context, not entry; setups only in the trend direction, IRL -> ERL.
- S6. Open: the role of M5 in M15 confirmation; the policy when the ERL target is below 2R.
- E1-E5. BUY example (second client screenshot, H4, explanation relayed by the owner): price was rising and the example shows two consecutive BOS. In the circled part price looked as if it had broken the structure downward but it was only a liquidity grab. After that grab the next H4 FVG formed (the green zone); price touched it and then made another BOS upward. The red arrow shows the rise the client expected. The client said: "Entry is made at the FVG and the target is the top of the third broken structure."
Interpretation limits for E1-E5 (owner's instructions):
1. It is evidence, on the BUY side, for the difference between a wick / liquidity grab and a confirmed change of structure.
2. "Two BOS" and "third BOS" describe the order in this example. They are not a condition: the robot does not wait for a fixed number of BOS.
3. The green zone is the H4 FVG formed after the liquidity grab, per the client's explanation.
4. The arrow is an expectation, not an executed confirmation and not an entry signal.
5. The H4 screenshot does not show the M15 entry. "Entry at the FVG" does not cancel S5: H4 is the context and the entry is at the M15 FVG after the structure break.
6. The target in the example is the top of the broken structure. It is not turned into a universal rule for choosing the ERL.
7. Prices, dates and candle indexes in the pictures are illustrations, never values to hard-code; where a text clarification exists it wins over how arrows or shapes might be read. The first screenshot's zone is not assumed to be "the new FVG after the wick"; that was confirmed separately in text (S4).
8. The BUY example is client evidence only for what is listed in point 1 and in E1-E5. The details of the BUY/SELL mirror (P8) are NOT client confirmations.
The screenshots are not stored in the repository.

B. EARLIER AUTHORISED DECISION: the owner's authorisation (2026-10-07) to create mechanical rules, as proposals awaiting visual validation, for what the client selects visually. The T002 proposals (2/2 swings, confirmed pivots, direction test, FVG definition and states, closed bars only) stay as they are.

C. TECHNICAL PROPOSALS: section 3. P1-P9 and P10-P12 are developer proposals, NOT client answers. P12 (intrabar block) originates from Codex's review. All must be labelled "proposed" in drawings and logs.

D. OPEN questions that affect implementation: section 8.

## 2. Terms
- Closed bars only, chronological, as in T002. The forming bar is not read by the replay (the only exception is the restrictive overlay P12).
- Pivot time = open time of the pivot candle. Confirmation time = close of the 2nd bar to its right (T002). A swing, and anything derived from it, is unknown before its confirmation time. Marks at the pivot must show the confirmation time so they do not suggest earlier knowledge.
- Body break (P1): an H4 candle CLOSE strictly beyond the level (SELL context: close > S; BUY context: close < S). Equality is not a break.
- Wick only (P1): high > S (BUY: low < S) with the close not beyond S. "Level crossed without a confirmed change" means exactly this.
- A bar's events are known at that bar's close (open time + period).

## 3. Proposals
P1. Body versus wick as in section 2. A body break takes precedence over wick-only for the same bar.

P2. Structural level (formalises "the relevant level"; still a proposal, not validated). SELL context: consider the confirmed, non-ambiguous swing lows in order. A "lower low" is strictly below the confirmed low immediately before it (equality is not lower). Take the latest lower low and the low before it. The structural high S is the HIGHEST confirmed swing high whose pivot lies strictly between them. Swing highs inside the leg that are not its top, and corrective higher lows after the last lower low, never become the level; the higher high before the leg is not used (S1). If a bound or the high is missing, or any bar after S's pivot up to now has a high above S, the level is UNDEFINED ("no evidence"; a previously held level is kept). The level is known from max(confirmation of S's pivot, confirmation of the lower low); only bars opening at or after that time can produce events against it. BUY context is the mirror: latest higher high, structural low S = LOWEST confirmed swing low strictly between that high and the high before it. Validation is by the visual comparison of section 10, not by a pass/fail claim.

P3. Bias layer with hysteresis next to T002's swing-based direction (unchanged, still displayed; the two may disagree). States NONE -> BIAS_BEARISH / BIAS_BULLISH (see P10 for how the first bias is set). Once in a bias, it is kept until a body break of its level (S1/S2), whatever T002's direction says, including MIXED. The level may be re-derived while ACTIVE; it is frozen during HOLD and RECONFIRMED. After a flip the new bias has no level until P2 yields one; no reversal can fire without a level.

P4. Wick event (closed-bar). A wick-only bar against the level moves ACTIVE -> HOLD. Record the wick bar (index, open time) and wick_known_time (its close). From wick_known_time new entries from the previous setup are blocked (S3). The structure is not cancelled: the bias stays (a wick is not a direction change, S2).

P5. Eligible new FVG (S4), SELL: a bearish H4 FVG (T002 definition) whose candle A is the wick candle or later, so that candle C closes after the wick candle; no candle before the wick candle takes part. The exact time definition of "new FVG after the wick" is still OPEN (section 8, F1); this is only the working interpretation. Pre-wick FVGs are marked PRE_WICK and are ineligible even if touched again. BUY: a bullish FVG, same timing (consistent with E3, which says the zone formed after the grab).

P6. Reconfirmation, per eligible FVG and on closed bars after its candle C. The touch is at the H4 FVG and counts at the CLOSE of the H4 candle that touched it (client information, S5). The state rules are T002's proposals: INVALID when a close is strictly beyond the far edge, TOUCHED when the wick range intersects the zone, INVALID wins on the same bar. A touched, still valid eligible FVG moves HOLD -> RECONFIRMED_H4 and records its ID. With several eligible FVGs, T002's nearest-first ordering decides which is shown first, and each can be reached in turn (client: the nearest first, then the next one).

P7. Interrupting transitions: a body break (HOLD or RECONFIRMED) flips the bias and discards the reconfirmation progress; another wick-only bar restarts HOLD from the LATEST wick (earlier eligible FVGs become PRE_WICK); the recorded FVG becoming INVALID returns RECONFIRMED -> HOLD; an eligible FVG becoming INVALID before its touch is dropped, and with none left HOLD continues. RECONFIRMED_H4 only means "H4 context ready, awaiting a new M15 structure break"; the M15 phase is not part of T003.

P8. BUY mirrors every rule. This is a proposal. The client's BUY example (E1-E5) supports the wick/grab-versus-structure distinction and the post-grab FVG; it does not confirm the other mirrored details.

P9. Live and historical share one pure replay over closed bars: `bars[0..n-1]` -> bias state, level, events with their times, eligible FVGs. Live applies it on init and on each new closed H4 bar; historical applies the same function to the bars closed by AsOfTime (T002's as-of filter). The replay is causal: state at bar t uses only swings confirmed by t and bars up to t. Window handling is in P11.

P10. Starting the bias from the history of breaks, not only from T002's direction at the evaluation time. The replay scans the bars chronologically from the start of its window; at every bar it evaluates T002's direction on the prefix up to that bar, so a trend that T002 saw earlier is kept by hysteresis even if T002 shows MIXED at the evaluation time. In addition, from NONE a bias is set by the first body break in the window of a structural level of either kind: a close above a structural high (the P2 level of a downward leg, or the latest confirmed higher high) sets BULLISH; a close below a structural low (the P2 level of an upward leg, or the latest confirmed lower low) sets BEARISH. A window that starts mid-trend with T002 saying MIXED can therefore still rebuild a bias from the breaks it contains, with its own level, using no bar after the evaluation time. Where the window holds no usable break or level, the answer is NONE ("no evidence").

P11. Continuity across windows, restarts and growing history. Goals: a sliding or expanding window, or an EA restart, must not lose or invent a bias or a HOLD, and a limit of the known history must be told apart from a real direction change.
- Anchored window: the analysis window start is min(lookback start, anchor start), where the anchor is the earliest bar the current state depends on (the bounding lows or the wick bar, minus the 2/2 bars needed to confirm them). Bars older than the lookback are not dropped while an active bias, HOLD or RECONFIRMED depends on them; the lookback then limits drawing, not the state.
- Bars are identified by open time, never by index.
- Restart: no persisted state is needed if the history reaches the anchor; the replay on the restored window is deterministic. If the history does not reach the anchor, the state is reported LIMITED_BY_HISTORY (what the window can say) and is NOT shown as a market event.
- Any change of state that appears only because the window changed (moved, expanded, restart) is reported as a RE-DERIVATION with its cause (history extended, window start moved), never as FLIP, WICK or RECONFIRMED.
- A real direction change is raised only from a closed bar inside the window after the state was established.
- Whether an entry module should treat LIMITED_BY_HISTORY as blocked is for the later execution task (open, F-list).

P12. Intrabar block, Codex's technical proposal (not client-confirmed, not implemented). In live mode, when the high (SELL) or low (BUY) of the FORMING H4 candle crosses the held level strictly, new entries are blocked immediately and temporarily. The overlay can only block: it never changes the bias, never starts a HOLD, never enables an entry, never produces a reconfirmation. The direction change is confirmed only after the H4 close beyond the level. At that close:
- wick-only (the bar crossed the level but did not close beyond it): the overlay becomes the closed-bar HOLD of P4 (the block continues; the HOLD is dated by the closed bar, the overlay start is logged as an observation time);
- body break (close beyond the level): the overlay ends in the bias flip of P3; no HOLD is entered for the old bias;
- a crossing that exactly touches the level (equality) is not a crossing.
The forming bar is read only by this overlay and only to restrict. Historical mode (closed bars only, no ticks) cannot reproduce the overlay and says so; live and historical therefore differ in timing by design. The overlay reads the forming bar's high/low from the series, not a tick feed.

## 4. States and transitions of the replay (SELL naming; BUY by mirror)
| From | Event on closed bar t (level S known) | To | Notes |
|---|---|---|---|
| NONE | T002 direction BEARISH on the prefix and S defined | BIAS_BEARISH (ACTIVE) | level re-derived each bar while ACTIVE |
| NONE | body break of a structural level (P10) | BIAS in the break's direction | level derived afterwards |
| ACTIVE | close_t > S | BIAS_BULLISH (ACTIVE, no level yet) | direction change confirmed with the body |
| ACTIVE | high_t > S and close_t <= S | HOLD (w = t, S frozen) | new entries from the previous setup blocked |
| HOLD | close_t > S | BIAS_BULLISH | reconfirmation discarded |
| HOLD | high_t > S and close_t <= S | HOLD (w = t) | restart from the latest wick |
| HOLD | an eligible FVG is touched and not invalid at close_t | RECONFIRMED_H4 (FVG id) | M15 phase not implemented |
| RECONFIRMED | close_t > S | BIAS_BULLISH | discarded |
| RECONFIRMED | high_t > S and close_t <= S | HOLD (w = t) | restart |
| RECONFIRMED | recorded FVG becomes INVALID | HOLD | wait for another eligible FVG |
Order inside one bar: update swings from the prefix; test events of bar t against the level held before t; update FVG eligibility and states with bar t; then re-derive the level if ACTIVE. The intrabar overlay (P12) sits outside this table.

## 5. What is cancelled and what is kept after a wick
- Blocked/cancelled: new entries from the previous setup; the eligibility of every pre-wick FVG; any pending M15 setup derived from them (a requirement for the later M15 task).
- Kept: the bias (a wick is not a direction change); T002's swings and FVG states and drawings (pre-wick FVGs shown as PRE_WICK); the frozen level S.
- Not decided: positions already open (S3 is silent); ERL/target after a flip.

## 6. Live and historical behaviour
- No candle after the evaluation time is read. In historical mode the evaluation time is AsOfTime (broker/server time as shown by MT5, not UTC, not TradingView time; equality with the client's chart is not assumed).
- Marks at the pivot carry the confirmation time. The wick mark carries the wick bar time and the time it became known.
- Live replay on each new closed bar; the overlay P12 is live only.

## 7. Acceptance criteria (for the later implementation)
1. Every rule is traceable to S1-S6 / E1-E5 or labelled proposed; no price, date or index is hard-coded.
2. Level selection follows P2: minor swings and corrective lows never become the level; the higher high before the leg is never required. The comparison with the client's examples (section 10) is reported without claiming validation.
3. A close beyond the level changes the bias; a wick alone never does, in either direction.
4. After a wick, no pre-wick FVG can reconfirm; a post-wick FVG can, only after the close of the H4 candle that touched it.
5. Bias rebuilt from history (P10): in the acceptance case below, the replay gives the expected bias although T002 says MIXED at the evaluation time, using no bar after it.
   Case: a series with two successive body breaks upward, then a correction that makes a lower high and a higher low (T002 MIXED at the evaluation time) with no close beyond the protecting low. Expected: BIAS_BULLISH with the protecting low of the last up-leg as level; the same expected result when the window starts after the first break and contains only the second one; the same result when bars after the evaluation time are replaced by garbage.
6. Continuity (P11): see tests 11-14; a window change alone never produces a FLIP, WICK or RECONFIRMED event.
7. Live and historical use the same replay; as-of results do not depend on bars after the as-of time.
8. Intrabar overlay (P12): never enables, never changes the bias, resolved at the close as defined; absent and labelled in historical mode.
9. T002 behaviour and tests unchanged; no order or position API; no M15/M5 code.
10. Drawings and panel show the bias, the level (pivot and confirmation times), the wick event (bar time and known time), eligible versus PRE_WICK FVGs, the LIMITED_BY_HISTORY state, the intrabar block when active, and whether the bias and T002's direction disagree. Labels must not hide the panel or candles (the owner observed overlapping labels in T002).
11. Compilation, tests, script runs and MT5 observation reported separately and attributed.

## 8. Open questions that affect implementation
- F1. The exact time definition of "new FVG after the wick" (which of candles A, B, C must come after the wick; P5 is only a working interpretation).
- F2. The M5/M15 relation (S6).
- F3. The policy when the ERL target is below 2R (S6). A recommendation to skip below 2R exists and is NOT an approved decision.
- F4. Positions already open when a wick or a flip occurs.
- F5. ERL selection and the validity of a reconfirmation: how the ERL is chosen after a flip (the target in the client's BUY example is not a universal rule), whether a post-wick FVG must lie inside T002's interval, how long RECONFIRMED stays valid, whether the frozen level is re-derived after a new extreme during the wait.
- F6. The intrabar overlay P12 is Codex's technical proposal and awaits the owner's decision; the client has not been asked whether an intrabar block is wanted at all.
- F7. How an entry module should treat LIMITED_BY_HISTORY.
- Resolved (no longer open): the touch rule, now client information (S5).

## 9. Tests the implementation must include (none exist yet; none are claimed)
Controlled-data cases, pure logic first (same style as T002):
1. Break by close versus wick only (both directions; equality is not a break).
2. A correction that does not change the bias (T002 direction MIXED while the bias stays, no level break).
3. A wick that blocks new entries (HOLD entered; block time = the wick bar's close).
4. A pre-wick FVG that is not eligible, even when touched again after the wick.
5. A new FVG after the wick (A = wick candle accepted, A before the wick rejected); touch, then the close of the touching H4 candle.
6. Repeated events: a second wick restarts HOLD; invalidation before the touch; invalidation after RECONFIRMED; body break during HOLD and during RECONFIRMED; direction flip while waiting.
7. Level selection: minor swings ignored, the leg's top chosen, the higher high before the leg not required, undefined when a bound is missing or the level was already touched.
8. Historical analysis: results at as-of time T identical when later bars are replaced by garbage; the replay on a prefix equals the full replay restricted to what was knowable at T, for many T.
9. Lifecycle and reload: no duplicate objects, clear/rebuild as in T002.
10. BUY mirror cases, including a liquidity-grab-then-FVG-then-touch sequence like E1-E5 built from controlled data (not from the picture's prices).
11. Bias rebuilt from break history with T002 MIXED at the evaluation time (the acceptance case of criterion 5, including the shorter window).
12. Window slides forward bar by bar with an active HOLD: the wick bar stays inside the anchored window and HOLD is not lost; a real flip is still detected after sliding.
13. Window expansion that adds older bars: states that change are reported as RE-DERIVATION (history extended), not as a market event; states that do not depend on the new bars stay identical.
14. Restart equivalence: replaying twice gives the same state; a window that does not reach the anchor yields LIMITED_BY_HISTORY, never an invented FLIP or HOLD.
15. Intrabar overlay: crossing blocks only; wick-only close turns it into HOLD; body-break close ends it in a flip; equality is not a crossing; no effect and an explicit note in historical mode.

## 10. Visual comparison with the client's examples (a comparison, not a validation)
The client's two H4 screenshots (bearish-to-bullish expectation with the first marked level; BUY example with a liquidity grab, the post-grab FVG, its touch and a BOS) are illustrations; no price, date or index in them is used by the robot. To compare, the owner picks, in MT5 server time, an as-of time just before each event the client described, runs the historical mode (T002 map plus the T003 layer when it exists) and records:
- V1. Level: the candle (by time) the robot's level comes from versus the candle the client marked. Compared by candle, not by a price tolerance. Result: same / different / robot undefined.
- V2. Minor swings: whether the robot's level is a swing the client did not mark; list the swing pivot times the robot considered.
- V3. "First level": when the client marked the first lower level rather than the major high, whether the robot chose the major high.
- V4. Wick versus body: around the circled part of the BUY example the robot must be in HOLD (wick only), not flipped; around the client's break the robot must flip only after a close beyond the level.
- V5. New FVG: whether the FVG the client coloured green is among the robot's eligible FVGs; record its candles A, B, C against the wick candle (this evidence informs F1).
- V6. Touch: the robot's touching H4 candle and its close versus the client's candle.
- V7. Bias at an evaluation time where T002 says MIXED: the robot's bias versus the client's reading.
Each item is recorded as an observation with its source (owner/Codex) and never aggregated into "validated".
