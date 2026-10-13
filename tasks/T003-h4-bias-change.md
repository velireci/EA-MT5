# T003 - H4 direction change and reconfirmation (specification draft, revision 4)

Status: DRAFT. NOT started. This file is a reviewable specification only: no MQL5, no tests and no tools exist for it, and none may be described as implemented or passed. Implementation needs the owner's explicit go after Codex's review of this text.
Builds on T002 (PR velireci/EA-MT5#2, draft, not merged) and keeps T002's behaviour and tests unchanged.
Out of scope: M5/M15 logic, entries, sizing, SL/TP, the 2R policy, news, trade management, handling of positions that are already open.
Revision 2 (2026-10-13) added the client's BUY example, corrected the touch rule (now client information), and answered Codex's remarks on the level, the start of the bias, continuity across windows, and intrabar blocking. Revision 3 (2026-10-13) added the client's closing statement for the BUY example (E6): after the liquidity grab the new H4 FVG, the return and then an M15 structure break, with the last HH as the target of that example. Revision 4 (2026-10-13) answers Codex's review of revision 3: the level is taken from the state known before the evaluated candle (P2/P10, consumed candidate versus protecting level), the restart mechanism is chosen and justified (P11), internal liquidity gets its own event and wait instead of being forced into HOLD (P14, F8, V4), the precedence between a T002 seed and a break is defined (P10), and the tests that were stranded after section 10 are back in section 9.

## 1. Provenance (never blur these)
A. CLIENT STATEMENTS, text clarifications and examples relayed by the owner (also in docs/DECISIONS.md and docs/STRATEGY_SPEC.md):
- S1. A change from bearish to bullish direction requires a break of the relevant H4 structural level. In the client's first picture the first marked level is enough; breaking the higher high as well is not required. "First level" is not automatically the nearest high or any small swing; its algorithmic choice is still to be formalised.
- S2. The pass must be with the body. A wick-only pass does not confirm a direction change and may be a liquidity grab.
- S3. SELL: after a wick above the structural level the robot stops NEW entries from the previous setup and waits for reconfirmation. Silent about positions that are already open.
- S4. SELL reconfirmation needs a NEW bearish H4 FVG formed AFTER the wick; a pre-wick FVG is not enough even if touched again.
- S5. After the new H4 FVG: the touch happens at that H4 FVG (a wick touch is allowed) and we wait for the close of the H4 candle that touched it (an earlier client clarification relayed by the owner; its original wording is not in the repository); then a new M15 structure break; entry at the M15 FVG after the break. H4 FVG/IRL is context, not entry; setups only in the trend direction, IRL -> ERL.
- S6. Open: the role of M5 in M15 confirmation; the policy when the ERL target is below 2R.
- E1-E5. BUY example (second client screenshot, H4, explanation relayed by the owner): price was rising and the example shows two consecutive BOS. In the circled part price looked as if it had broken the structure downward but it was only a liquidity grab. After that grab the next H4 FVG formed (the green zone); price touched it and then made another BOS upward. The red arrow shows the rise the client expected. The client said: "Entry is made at the FVG and the target is the top of the third broken structure."
- E6. Closing statement for the same BUY example, third client screenshot (the client's words as relayed by the owner): "After the liquidity we have the main FVG where we expect price to return, and we have to wait for a structure break on M15. The target is the upper red line, at the last HH." It shows an INTERNAL liquidity grab without a confirmed change of the BUY trend; after the grab a new H4 FVG forms; we wait for the return/touch and then for an M15 structure break. The H4 FVG is the context, not a direct entry; the earlier rule stays (entry at the M15 FVG after the break, S5). The target of this example is the last HH, marked by the upper red line; it is not the local level labelled on the right-hand price axis of the picture.
Interpretation limits for E1-E6 (owner's instructions):
1. It is evidence, on the BUY side, for the difference between a wick / liquidity grab and a confirmed change of structure.
2. "Two BOS" and "third BOS" describe the order in this example. They are not a condition: the robot does not wait for a fixed number of BOS.
3. The green zone is the H4 FVG formed after the liquidity grab, per the client's explanation.
4. The arrow is an expectation, not an executed confirmation and not an entry signal.
5. The H4 screenshots do not show the M15 entry. "Entry at the FVG" (E5) does not cancel S5: H4 is the context and the entry is at the M15 FVG after the structure break. E6 confirms the sequence for BUY: new H4 FVG after the grab -> return/touch -> M15 structure break; it does not add an M5 role.
6. The target in this example is the last HH (E6; E5 called it the top of the third broken structure). Both describe this example. Neither is turned into a universal rule for choosing the ERL, and the last HH is not to be confused with the local level labelled on the price axis. Any algorithmic target choice is only the labelled proposal P13.
7. Prices, dates and candle indexes in the pictures are illustrations, never values to hard-code; where a text clarification exists it wins over how arrows or shapes might be read. The first screenshot's zone is not assumed to be "the new FVG after the wick"; that was confirmed separately in text (S4).
8. The BUY example (E1-E6) is client evidence, for BUY, of: the distinction between a liquidity grab and a confirmed change of structure; a new H4 FVG formed after the grab; the return/touch; the wait for an M15 structure break; entry at the M15 FVG per S5. The remaining details of the BUY/SELL mirror (P8: body-close rule for the flip, which FVG candle must follow the wick, hysteresis, the protected-level choice) are NOT client confirmations.
9. Internal liquidity is not the structural level. In E1-E6 the low that was grabbed is not assumed to be the protecting higher low; the automatic choice of the structural level stays a proposal for validation (P2, section 10). A price drawn in the picture is never assumed to be the level.
10. Not a fixed count: no condition of two or three BOS exists; the numbers describe the example.
The three screenshots are not stored in the repository.

B. EARLIER AUTHORISED DECISION: the owner's authorisation (2026-10-07) to create mechanical rules, as proposals awaiting visual validation, for what the client selects visually. The T002 proposals (2/2 swings, confirmed pivots, direction test, FVG definition and states, closed bars only) stay as they are.

C. TECHNICAL PROPOSALS (section 3; NOT client statements; each must be labelled "proposed" in drawings and logs). P1-P14 are developer proposals. In particular these three are technical proposals and not client answers: the intrabar block (P12, originates from Codex's review), candle A of the new FVG being allowed to be the wick candle (P5), and blocking entries when the history is insufficient (P11, fail-safe for the later execution task; the owner decides, F7).

D. OPEN questions that affect implementation: section 8.

## 2. Terms
- Closed bars only, chronological, as in T002. The forming bar is not read by the replay (the only exception is the restrictive overlay P12).
- Pivot time = open time of the pivot candle. Confirmation time = close of the 2nd bar to its right (T002). A swing, and anything derived from it, is unknown before its confirmation time. Marks at the pivot must show the confirmation time so they do not suggest earlier knowledge.
- Body break (P1): an H4 candle CLOSE strictly beyond the level (SELL context: close > S; BUY context: close < S). Equality is not a break.
- Wick only (P1): high > S (BUY: low < S) with the close not beyond S. "Level crossed without a confirmed change" means exactly this.
- A bar's events are known at that bar's close (open time + period).
- State known before bar t: the swings confirmed by the close of bar t-1 and the bars up to t-1. Levels, candidates and eligibility used to judge bar t come ONLY from this state; bar t is never used to decide whether a level exists.
- Candidate level: a level derived by P2/P10 from the state known before a bar.
- Consumed candidate: a candidate that a closed bar has already crossed and whose crossing event (wick or break) the state machine has processed.
- Protecting level: the consumed candidate kept FROZEN while the state is HOLD or RECONFIRMED; it is the reference for later wick/body tests. A consumed candidate is never selected again as a fresh candidate for the old bias, but the protecting level remains in force.

## 3. Proposals
P1. Body versus wick as in section 2. A body break takes precedence over wick-only for the same bar.

P2. Structural level (formalises "the relevant level"; still a proposal, not validated). SELL context: consider the confirmed, non-ambiguous swing lows in order. A "lower low" is strictly below the confirmed low immediately before it (equality is not lower). Take the latest lower low and the low before it. The structural high S is the HIGHEST confirmed swing high whose pivot lies strictly between them. Swing highs inside the leg that are not its top, and corrective higher lows after the last lower low, never become the level; the higher high before the leg is not used (S1). BUY context is the mirror: latest higher high, structural low S = LOWEST confirmed swing low strictly between that high and the high before it.
Timing (corrected): the candidate is derived from the state known before the evaluated bar t, never from a state that includes bar t. If bar t crosses the candidate, that is the event to process (P1/P4), not a reason to discard the level. A candidate is UNDEFINED ("no evidence") only if a bound or the high is missing, or if a closed bar between its pivot and t-1 already closed beyond it (a body break the machine handled earlier: a consumed candidate). Crossings of the candidate by a wick between its pivot and the moment it was first derived are handled when it is first derived: it is accepted and the state enters HOLD at once, dated by the latest such wick bar (known retroactively, using only bars up to now); a body close beyond it before that moment rejects the candidate. The level is known from max(confirmation of S's pivot, confirmation of the lower low); only bars opening at or after that time can produce events against it.
Consumed candidate versus protecting level: after a wick at bar t the candidate is consumed AND kept as the frozen protecting level of HOLD; it is not re-derived and not subject to the "already crossed" rejection while HOLD or RECONFIRMED lasts.
Validation is by the visual comparison of section 10, not by a pass/fail claim. Internal liquidity (for example an interior low of the structure) is not the structural level; it is handled by P14.

P3. Bias layer with hysteresis next to T002's swing-based direction (unchanged, still displayed; the two may disagree). States NONE -> BIAS_BEARISH / BIAS_BULLISH (see P10 for how the first bias is set). Once in a bias, it is kept until a body break of its level (S1/S2), whatever T002's direction says, including MIXED. The level may be re-derived while ACTIVE; it is frozen during HOLD and RECONFIRMED. After a flip the new bias has no level until P2 yields one; no reversal can fire without a level.

P4. Wick event (closed-bar). A wick-only bar against the level moves ACTIVE -> HOLD. Record the wick bar (index, open time) and wick_known_time (its close). From wick_known_time new entries from the previous setup are blocked (S3). The structure is not cancelled: the bias stays (a wick is not a direction change, S2).

P5. Eligible new FVG (S4), SELL: a bearish H4 FVG (T002 definition) whose candle A is the wick candle or later, so that candle C closes after the wick candle; no candle before the wick candle takes part. The exact time definition of "new FVG after the wick" is still OPEN (section 8, F1); this is only the working interpretation. Pre-wick FVGs are marked PRE_WICK and are ineligible even if touched again. BUY: a bullish FVG, same timing (consistent with E3, which says the zone formed after the grab).

P6. Reconfirmation, per eligible FVG and on closed bars after its candle C. The touch is at the H4 FVG and counts at the CLOSE of the H4 candle that touched it (client information, S5). The state rules are T002's proposals: INVALID when a close is strictly beyond the far edge, TOUCHED when the wick range intersects the zone, INVALID wins on the same bar. A touched, still valid eligible FVG moves HOLD -> RECONFIRMED_H4 and records its ID. With several eligible FVGs, T002's nearest-first ordering decides which is shown first, and each can be reached in turn (client: the nearest first, then the next one).

P7. Interrupting transitions: a body break (HOLD or RECONFIRMED) flips the bias and discards the reconfirmation progress; another wick-only bar restarts HOLD from the LATEST wick (earlier eligible FVGs become PRE_WICK); the recorded FVG becoming INVALID returns RECONFIRMED -> HOLD; an eligible FVG becoming INVALID before its touch is dropped, and with none left HOLD continues. RECONFIRMED_H4 only means "H4 context ready, awaiting a new M15 structure break"; the M15 phase is not part of T003.

P8. BUY mirrors every rule. This is a proposal. The client's BUY example (E1-E6) is evidence for BUY of the sequence grab without a confirmed change -> new H4 FVG after the grab -> return/touch -> M15 structure break, with entry at the M15 FVG (S5); it does not confirm the other mirrored details (body-close rule for the flip, which FVG candle must follow the wick, hysteresis, the choice of the protected level).

P9. Live and historical share one pure replay over closed bars: `bars[0..n-1]` -> bias state, level, events with their times, eligible FVGs. Live applies it on init and on each new closed H4 bar; historical applies the same function to the bars closed by AsOfTime (T002's as-of filter). The replay is causal: state at bar t uses only swings confirmed by t and bars up to t. Window handling is in P11.

P10. Starting the bias, with a defined precedence between the T002 seed and structural breaks. The replay scans the bars chronologically from the start of its window. At each bar t, in this order:
1. Break events of bar t against the structural levels known BEFORE t. Break candidates of the up kind: the P2 level of a downward leg (S_high) and the latest confirmed higher high; of the down kind: the P2 level of an upward leg (S_low) and the latest confirmed lower low. A body close beyond a known candidate is a real break: from NONE it sets the bias in that direction (origin BREAK), and in a bias it is the flip of P3. A level that was not yet known before t cannot be broken at t.
2. Only if the state is still NONE after step 1, the seed from T002: T002's direction evaluated on the prefix including bar t (BEARISH / BULLISH) sets the bias when its P2 level is defined (origin SEED_SWINGS). Because it is evaluated at every bar, a trend T002 saw earlier is kept by hysteresis even when T002 shows MIXED at the evaluation time.
Precedence: a break (an observed event on a closed bar against a level known earlier) outranks the seed (a structure-derived expectation). If a break and the seed point in opposite directions on the same bar, the break decides and T002's direction is shown as a disagreement.
Contradictions and missing evidence: if body breaks of BOTH kinds happen on the same bar (levels that overlap), the result is NONE with reason CONFLICT; if there is no usable break, no defined level and no seed, the result is NONE with reason NO_EVIDENCE. No direction is invented in either case.
A window that starts mid-trend with T002 saying MIXED can therefore still rebuild a bias from the breaks it contains, with its own level, using no bar after the evaluation time.

P11. Continuity across windows and restarts: chosen mechanism. Without stored state the previous anchor cannot be assumed known after a restart, so the mechanism does not rely on it.
Choice: REBUILD from a defined history, with no persisted state in T003. Reasons: (a) a stored state is a second source of truth that can be stale after offline gaps, a recompile, a manual change of the chart or revised history, and would need invalidation rules; (b) the replay is a deterministic function of the closed bars, so the same bars always give the same state, and a restart then reproduces the state when the rebuilt history reaches what the state depends on; (c) the persistence mechanisms of the platform (global variables, files) have not been verified in this project. Persistence may be added later only as a hint that the replay checks, never as the source of the state; that would be a separate decision.
Mechanism:
1. Defined history: on init and on every new closed bar the replay runs over the last REBUILD_BARS closed H4 bars (a proposed input; default not fixed by this draft; it must be at least the analysis lookback and is clamped to what the server has). Bars are identified by open time, never by index.
2. Dependency anchor of a state: the earliest bar it needs. For a BREAK-origin bias it is the earlier of the break bar and the pivots of its level (minus the 2/2 bars that confirm them), so older history cannot change it; for a HOLD or RECONFIRMED it is the earlier of the wick bar and the pivots of the frozen level; for a SEED_SWINGS bias it is the swings of the seed, which makes it weaker.
3. Support flag reported with every state: ANCHORED (the anchor lies inside the window, beyond a warm-up of at least 2*(Left+Right)+3 bars from the window start), SEEDED (origin SEED_SWINGS: derived from swings in the window and able to change if more history is added), or LIMITED_BY_HISTORY (the anchor falls in the warm-up zone or before the window).
4. LIMITED_BY_HISTORY reports the direction as UNKNOWN (limited by history): no bias, HOLD or flip is asserted from edge bars. T002's own direction is still shown. This is how insufficient history is reported without inventing a direction.
5. Expand-only during a session: the window start stays fixed at the start of the session and the window grows with each new bar. It is re-based (older bars dropped) only at a bar where the current state's anchor stays beyond the new warm-up zone; otherwise it keeps growing to a hard cap and then reports LIMITED_BY_HISTORY. This prevents an active HOLD from being lost because the window slid.
6. Any change of state that appears only because the window changed (re-base, extension, restart with a different depth) is reported as a RE-DERIVATION with its cause, never as FLIP, WICK or RECONFIRMED. A real change is raised only from a closed bar inside the window after the state was established.
7. Technical proposal (fail-safe for the later execution task, NOT a client statement, owner's decision, F7): while the state is LIMITED_BY_HISTORY an execution module should block new entries. T003 only reports the state.

P12. Intrabar block, Codex's technical proposal (not client-confirmed, not implemented). In live mode, when the high (SELL) or low (BUY) of the FORMING H4 candle crosses the held level strictly, new entries are blocked immediately and temporarily. The overlay can only block: it never changes the bias, never starts a HOLD, never enables an entry, never produces a reconfirmation. The direction change is confirmed only after the H4 close beyond the level. At that close:
- wick-only (the bar crossed the level but did not close beyond it): the overlay becomes the closed-bar HOLD of P4 (the block continues; the HOLD is dated by the closed bar, the overlay start is logged as an observation time);
- body break (close beyond the level): the overlay ends in the bias flip of P3; no HOLD is entered for the old bias;
- a crossing that exactly touches the level (equality) is not a crossing.
The forming bar is read only by this overlay and only to restrict. Historical mode (closed bars only, no ticks) cannot reproduce the overlay and says so; live and historical therefore differ in timing by design. The overlay reads the forming bar's high/low from the series, not a tick feed.

P13. Target candidate for display (proposal; E6 and E5 are one example, no universal rule). In the trend direction the ERL candidate shown for comparison is the latest confirmed higher high (BUY) / lower low (SELL) as defined in P10, kept apart from local levels (for example a swing created by the pullback). It is displayed only; T002's ERL (interval based) is unchanged and both may be shown. Open details: whether the candidate must still be untaken, must lie beyond price, how it is chosen when several qualify, and the relation to the 2R policy (F5, F3). Compared with the client's example by the section 10 protocol, never claimed validated.

P14. Internal liquidity grab (technical proposal; the sequence is client-confirmed in E1-E6, the detection and the wait are NOT). Client-confirmed flow, BUY side: internal liquidity grab without a confirmed change of trend -> new H4 FVG after the grab -> return/touch -> M15 structure break (entry at the M15 FVG). The proposal must not be mixed up with a break of the protecting level.
- Identification (BUY; SELL by mirror): with the protecting low S_low defined (P2), the interior liquidity candidate L_int is the lowest confirmed swing low whose pivot is after the pivot of the latest higher high that defines S_low (the corrective lows of the pullback). An INTERNAL_SWEEP event is raised at closed bar t, using the state before t, when low_t < L_int strictly and close_t >= L_int and low_t >= S_low (the protecting low is not crossed). Without a defined S_low or L_int nothing is raised ("no evidence"). A sweep that crosses S_low is not internal: it is the structural wick/break of P1/P4.
- Transition: ACTIVE -> SWEEP_WAIT (s = t). The bias does not change and no level is frozen. An eligible FVG is a bullish H4 FVG whose candle A is the sweep candle or later (the same working interpretation as P5, F1). When an eligible FVG is touched and still valid at the close of the touching H4 candle (client information, S5), SWEEP_WAIT -> RECONFIRMED_H4 (reason INTERNAL, FVG id); the M15 phase is outside T003.
- Precedence: while in SWEEP_WAIT the structural logic stays active. A wick through S_low moves to HOLD (P4) and a body break flips the bias (P1/P3); both supersede the wait. A further internal sweep restarts the wait from the latest sweep.
- Entries: whether the previous setup's new entries are blocked during SWEEP_WAIT is NOT stated by the client (S3 concerns the structural wick). The technical proposal is to block them, with a distinct reason code, for the owner/client to confirm (F8).
- What the proposal does not claim: it does not assume that the low grabbed in the client's picture is L_int or that it is not the protecting low; the classification is an observation of the section 10 comparison. A body close below L_int (an interior low) is neither an internal sweep nor a break of the protecting level here: it is recorded as an INTERNAL_BREAK observation with no state change, and what it should mean is open (F8).

## 4. States and transitions of the replay (SELL naming; BUY by mirror)
| From | Event on closed bar t (judged against the state known before t) | To | Notes |
|---|---|---|---|
| NONE | body break of a known structural level (P10 step 1) | BIAS in the break's direction | origin BREAK; level derived afterwards |
| NONE | no break, T002 direction BEARISH on the prefix and S defined (P10 step 2) | BIAS_BEARISH (ACTIVE) | origin SEED_SWINGS |
| NONE | breaks of both kinds, or no evidence | NONE | reason CONFLICT / NO_EVIDENCE |
| ACTIVE | close_t > S | BIAS_BULLISH (ACTIVE, no level yet) | direction change confirmed with the body |
| ACTIVE | high_t > S and close_t <= S | HOLD (w = t, S frozen) | the candidate is consumed and kept as the protecting level; new entries from the previous setup blocked |
| ACTIVE | internal sweep (P14) | SWEEP_WAIT (s = t) | no bias change, no frozen level |
| SWEEP_WAIT | eligible FVG touched and not invalid at close_t | RECONFIRMED_H4 (reason INTERNAL) | M15 phase not implemented |
| SWEEP_WAIT | wick through S / body break | HOLD / flip | structural logic supersedes |
| HOLD | close_t > S | BIAS_BULLISH | reconfirmation discarded |
| HOLD | high_t > S and close_t <= S | HOLD (w = t) | restart from the latest wick |
| HOLD | an eligible FVG is touched and not invalid at close_t | RECONFIRMED_H4 (FVG id) | M15 phase not implemented |
| RECONFIRMED | close_t > S | BIAS_BULLISH | discarded |
| RECONFIRMED | high_t > S and close_t <= S | HOLD (w = t) | restart |
| RECONFIRMED | recorded FVG becomes INVALID | HOLD or SWEEP_WAIT (by reason) | wait for another eligible FVG |
Order inside one bar t: (1) the state known before t gives the candidate/protecting level; (2) events of bar t are tested against it (break first, then wick, then internal sweep); (3) FVG eligibility and states are updated with bar t; (4) swings are updated from the prefix including t and the candidate for the NEXT bar is derived. The level used for bar t is never recomputed with bar t. The intrabar overlay (P12) sits outside this table.

## 5. What is cancelled and what is kept after a wick
- Blocked/cancelled: new entries from the previous setup; the eligibility of every pre-wick FVG; any pending M15 setup derived from them (a requirement for the later M15 task).
- Kept: the bias (a wick is not a direction change); T002's swings and FVG states and drawings (pre-wick FVGs shown as PRE_WICK); the frozen level S.
- Not decided: positions already open (S3 is silent); ERL/target after a flip.

## 6. Live and historical behaviour
- No candle after the evaluation time is read. In historical mode the evaluation time is AsOfTime (broker/server time as shown by MT5, not UTC, not TradingView time; equality with the client's chart is not assumed).
- Marks at the pivot carry the confirmation time. The wick mark carries the wick bar time and the time it became known.
- Live replay on each new closed bar; the overlay P12 is live only.

## 7. Acceptance criteria (for the later implementation)
1. Every rule is traceable to S1-S6 / E1-E6 or labelled proposed; no price, date or index is hard-coded.
2. Level selection follows P2: minor swings and corrective lows never become the level; the higher high before the leg is never required. The comparison with the client's examples (section 10) is reported without claiming validation.
3. A close beyond the level changes the bias; a wick alone never does, in either direction.
4. After a wick, no pre-wick FVG can reconfirm; a post-wick FVG can, only after the close of the H4 candle that touched it.
5. Start from a real break and from a wick (P2/P10). Controlled series; the level is the candidate known before the evaluated bar.
   - Case A (real break): a candidate S derived from swings confirmed before bar t; bar t closes beyond S. Expected: BODY_BREAK at t; from NONE the bias is set in the break's direction (origin BREAK), from a bias it flips; the level's pivot and confirmation times are reported. The result is the same when t is the last bar of the as-of set, and when bars after t are replaced by garbage. The level is not discarded because bar t is beyond it.
   - Case B (wick): bar t has its high beyond S and its close not beyond. Expected: from ACTIVE a WICK event at t and HOLD with the consumed candidate kept as the frozen protecting level (not re-derived, not rejected because it was crossed); from NONE no bias change and the candidate stays usable, so a later body close beyond it is a BODY_BREAK; a wick between the pivot and the first derivation of the level enters HOLD at once dated by that wick bar.
   - Case C (bias rebuilt from history): two successive body breaks upward, then a correction that makes a lower high and a higher low (T002 MIXED at the evaluation time) with no close beyond the protecting low. Expected: BIAS_BULLISH with the protecting low of the last up-leg as level; the same result when the window starts after the first break; the same result when bars after the evaluation time are replaced by garbage.
   - Case D (precedence): a break and a T002 seed pointing in opposite directions on the same bar: the break decides and the disagreement is shown. Breaks of both kinds on one bar: NONE (CONFLICT). No levels and no seed: NONE (NO_EVIDENCE).
6. Continuity (P11): see tests 12-15; a window change alone never produces a FLIP, WICK or RECONFIRMED event; insufficient history never produces an invented direction.
7. Live and historical use the same replay; as-of results do not depend on bars after the as-of time.
8. Internal liquidity (P14): detected only with a defined protecting low, never confused with a break of the protecting level, never flips the bias; the entry block during SWEEP_WAIT is labelled a technical proposal. Intrabar overlay (P12): never enables, never changes the bias, resolved at the close as defined; absent and labelled in historical mode.
9. T002 behaviour and tests unchanged; no order or position API; no M15/M5 code. The target candidate (P13), if built, is display only, kept apart from local levels, labelled proposed, and not used as a universal target rule.
10. Drawings and panel show the bias, the level (pivot and confirmation times), the wick event (bar time and known time), eligible versus PRE_WICK FVGs, the LIMITED_BY_HISTORY state, the intrabar block when active, and whether the bias and T002's direction disagree. Labels must not hide the panel or candles (the owner observed overlapping labels in T002).
11. Compilation, tests, script runs and MT5 observation reported separately and attributed.

## 8. Open questions that affect implementation
- F1. The exact time definition of "new FVG after the wick" (which of candles A, B, C must come after the wick; P5 is only a working interpretation).
- F2. The M5/M15 relation (S6).
- F3. The policy when the ERL target is below 2R (S6). A recommendation to skip below 2R exists and is NOT an approved decision.
- F4. Positions already open when a wick or a flip occurs.
- F5. ERL selection and the validity of a reconfirmation: how the ERL is chosen after a flip (the target in the client's BUY example, the last HH, is not a universal rule; P13 is only a display proposal), whether a post-wick FVG must lie inside T002's interval, how long RECONFIRMED stays valid, whether the frozen level is re-derived after a new extreme during the wait.
- F6. The intrabar overlay P12 is Codex's technical proposal and awaits the owner's decision; the client has not been asked whether an intrabar block is wanted at all.
- F7. Whether new entries are blocked while the state is LIMITED_BY_HISTORY. The fail-safe block is a technical proposal (P11), not a client statement; the owner decides for the execution task.
- F8. Internal liquidity (E1-E6): the client confirmed the flow internal liquidity -> new H4 FVG -> touch -> M15 break. NOT confirmed and open: how the interior liquidity is identified (P14 proposes the pullback lows after the latest higher high), whether new entries of the previous setup are blocked during the wait, what a body close below an interior low means, and whether the grabbed low in the client's picture is an interior low or the protecting low.
- Resolved (no longer open): the touch rule, now client information (S5).

## 9. Tests the implementation must include (none exist yet; none are claimed)
Controlled-data cases, pure logic first (same style as T002):
1. Break by close versus wick only (both directions; equality is not a break).
2. A correction that does not change the bias (T002 direction MIXED while the bias stays, no level break).
3. A wick that blocks new entries (HOLD entered; block time = the wick bar's close).
4. A pre-wick FVG that is not eligible, even when touched again after the wick.
5. A new FVG after the wick (A = wick candle accepted, A before the wick rejected); touch, then the close of the touching H4 candle.
6. Repeated events: a second wick restarts HOLD; invalidation before the touch; invalidation after RECONFIRMED; body break during HOLD and during RECONFIRMED; direction flip while waiting.
7. Level selection: minor swings ignored, the leg's top chosen, the higher high before the leg not required, undefined when a bound is missing or the candidate was already body-broken before the evaluated bar; a crossing by the evaluated bar itself never discards the level.
8. Historical analysis: results at as-of time T identical when later bars are replaced by garbage; the replay on a prefix equals the full replay restricted to what was knowable at T, for many T.
9. Lifecycle and reload: no duplicate objects, clear/rebuild as in T002.
10. BUY mirror cases, including a liquidity-grab-then-FVG-then-touch sequence like E1-E6 built from controlled data (not from the picture's prices).
11. Start from a real break and from a wick (acceptance cases A and B of criterion 5): the candidate comes from the state before the evaluated bar; a crossing is processed as an event, not used to discard the level; consumed candidate kept as the frozen protecting level in HOLD; wick before first derivation enters HOLD at once; wick from NONE does not set a bias and a later body close does.
12. Bias rebuilt from break history with T002 MIXED at the evaluation time (case C, including the shorter window) and the precedence/contradiction cases (case D).
13. Rebuild and restart (P11): replaying twice, and a restart that rebuilds from REBUILD_BARS, give the same state when the anchor lies inside the window; a state whose anchor falls in the warm-up zone is LIMITED_BY_HISTORY with direction UNKNOWN, never an invented bias, HOLD or flip.
14. Window slides forward bar by bar with an active HOLD: expand-only keeps the wick bar; re-base happens only when the anchor stays beyond the warm-up zone; a real flip is still detected after re-basing.
15. Window or history extension that adds older bars: states that change are reported as RE-DERIVATION (history extended) and not as a market event; states that do not depend on the new bars stay identical; a SEEDED state may change, an ANCHORED one does not.
16. Intrabar overlay: crossing blocks only; wick-only close turns it into HOLD; body-break close ends it in a flip; equality is not a crossing; no effect and an explicit note in historical mode.
17. Internal liquidity (P14): a sweep of an interior low with the protecting low not crossed raises INTERNAL_SWEEP and SWEEP_WAIT; the bias does not change; a wick through the protecting low gives HOLD instead and a body break gives a flip (structural logic supersedes); without a defined protecting low nothing is raised; a body close below an interior low is only an INTERNAL_BREAK observation. Controlled data only; the picture's levels are not used.
18. Target candidate (P13): the latest higher high is shown and a local level created by a pullback is not; the candidate changes when a newer higher high confirms; T002's ERL does not change. Controlled data only; no price from the pictures.
19. No fixed BOS count: sequences with one, two and three successive breaks give the same bias rule.

## 10. Visual comparison with the client's examples (a comparison, not a validation)
The client's three H4 screenshots (bearish-to-bullish expectation with the first marked level; BUY example with a liquidity grab, the post-grab FVG, its touch and a BOS; the BUY example again with the upper red line at the last HH) are illustrations; no price, date or index in them is used by the robot. To compare, the owner picks, in MT5 server time, an as-of time just before each event the client described, runs the historical mode (T002 map plus the T003 layer when it exists) and records:
- V1. Level: the candle (by time) the robot's level comes from versus the candle the client marked. Compared by candle, not by a price tolerance. Result: same / different / robot undefined.
- V2. Minor swings: whether the robot's level is a swing the client did not mark; list the swing pivot times the robot considered.
- V3. "First level": when the client marked the first lower level rather than the major high, whether the robot chose the major high.
- V4. Wick versus body: around the circled part of the BUY example record which event and state the robot reports (structural wick and HOLD, internal sweep and SWEEP_WAIT, or no event); the only requirement is that it does not flip without a body close beyond the protecting level. Which classification applies is an observation for validation, not a requirement. Around the client's break the robot must flip only after a close beyond the level.
- V5. New FVG: whether the FVG the client coloured green is among the robot's eligible FVGs; record its candles A, B, C against the wick candle (this evidence informs F1).
- V6. Touch: the robot's touching H4 candle and its close versus the client's candle.
- V7. Bias at an evaluation time where T002 says MIXED: the robot's bias versus the client's reading.
- V8. Internal liquidity (E1-E6): at as-of times around the grab, whether the swept low is the robot's L_int, the robot's protecting level, or neither; the state it reports (INTERNAL_SWEEP/SWEEP_WAIT, HOLD, or nothing); whether the post-grab FVG the client coloured is eligible and the touch matches (flow: internal liquidity -> new H4 FVG -> touch -> M15 break); and what a human would call the protecting level. No assumption that the grabbed low is the protecting low.
- V9. Target (E6): the candle of the client's last HH against the robot's P13 candidate and against T002's ERL; the local level on the price axis must not be reported as the target.
Each item is recorded as an observation with its source (owner/Codex) and never aggregated into "validated".
