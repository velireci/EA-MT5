# Strategy specification — draft

Status: PARTIAL. This document is not an approved complete trading algorithm.
Source: submission XAU-20261006-E27N93, schema 5. Original evidence is in inputs/client-E27N93/.
Read the full analysis in docs/reference/strategy-review.md only when a detail needs investigation.

## Intended sequence
H1/H4 directional assessment → selected H4 FVG → qualifying return into that area → M15 MSS with associated FVG → limit order → structural SL and liquidity TP → partial exit and stop management.

Direction/swing selection, zone selection, qualification and target selection require explicit rules. Do not treat this narrative as a complete implementation contract.

## Explicit answers relevant to development
- MT5, Tauro, XAUUSD.r, USD account; verify actual broker configuration.
- M15 signals; H4 completed-candle context. Narrative also uses H1.
- BUY and SELL, intended mirror rules; M15 forming-candle evaluation selected.
- Limit entry at an M15 FVG; SL at a relevant M15 structural high/low; final TP at liquidity.
- Cancel pending orders on direction change, opposite signal, session end and avoided news.
- One entry per signal; definition of distinct FVG/MSS setups unresolved.
- Close 80% of initial volume at 2R; remaining 20% until final TP/SL; no trailing.
- Two open positions, 2% combined open risk, 10-lot cap, skip sizing conflicts.
- Detailed daily trade limit: 2. Introductory confirmed fact: 3. OPEN conflict.
- Introductory confirmed risk: 1% per trade. Active sizing method/base unknown. OPEN.
- Stop after a win; two consecutive losses; breakeven neutral; partial exit counts as one trade. Event definitions and resets OPEN.
- Daily limit: 2%, start-of-day balance, closed results only, EA scope, stop entries/cancel pending orders.
- Monday-Friday 00:00-20:30 Europe/Tirane, local DST; daily reset midnight.
- Friday close 21:00. Normal session-end open-position behavior OPEN.
- High-impact USD news blackout: 30 minutes before/after. Existing-position behavior OPEN.
- Push notifications; client also trades manually.

## Explicit conflicts / unresolved units
- Stop after partial exit: entry plus costs versus prose “+0.2%”. Meaning OPEN.
- 50 stop-distance limit is stored as gold-price units; ask client to confirm unit.
- Screenshot levels may differ from the 2R partial answer; no level is adopted without confirmation.
- H1/H4 roles and swing labels in prose need clarification.

## Engineering requirements
Use account/broker-aware prices and volume calculations; check all order outcomes; prevent duplicate setup entries; recover state after restart; establish trade ownership and account hedging/netting behavior. No raw price-distance value represents account-dollar risk without a volume/contract calculation.

## H4 map (T002) - three kinds of content, kept apart
A. CLIENT ANSWERS relayed as confirmed by the owner (2026-10-07; see DECISIONS.md): direction and context zones from H4 only; only trend-direction setups, IRL -> ERL (ERL -> IRL excluded); IRL = H4 FVG, wick touch is enough; IRL is not the entry (structure confirmation after the touch, entry at the M15 FVG after the break); the H4 FVG nearest to price on the way back is chosen first, the next one may be reached if confirmation is missing; ERL is the structural destination.

B. OWNER DECISION (2026-10-07): mechanical rules may be proposed for what the client selects visually. They stay PROPOSED until the client validates them on charts.

C. PROPOSED (developer proposals, NOT client answers; implemented only as drawings in T002, full text in tasks/T002-h4-map.md):
- Swings: 2 closed bars left and right, strict comparison, equal values do not qualify; stored with pivot time and confirmation time (close of the 2nd bar to the right); a bar that is both high and low is AMBIGUOUS and unused.
- Direction: last two confirmed swing highs and lows; LH+LL bearish, HH+HL bullish, anything else (including ties) MIXED, fewer than two of either UNKNOWN. MIXED/UNKNOWN declares no setup.
- Interval: bearish = latest confirmed low and the latest confirmed high preceding it; bullish = latest confirmed high and the latest confirmed low preceding it; otherwise RANGE_UNDEFINED. ERL SELL = interval low, ERL BUY = interval high.
- ERL TAKEN: a closed H4 bar's wick touches/crosses it after the interval became knowable; never restored.
- FVG: three closed bars A,B,C; bullish Low(C) > High(A), bearish High(C) < Low(A); confirmed at close of C; no size/displacement filter.
- FVG state: INVALID on a close strictly beyond the far edge, TOUCHED on a wick intersecting the zone, else FRESH; touch does not remove the zone; no re-use limit.
- IRL candidate: valid same-direction FVG fully inside the interval (inclusive); others are OUTSIDE, never active IRL.
- Visual order: nearest zone ahead of Bid; INSIDE shown first and never skipped; ties by distance, newer confirmation, then ID; zones are never merged.
- Link IRL -> ERL drawn only with valid direction, valid interval, untouched ERL and a selectable candidate.

D. STILL OPEN (not implemented, not decided): the M5 item is SUPERSEDED by the client statement of 2026-10-13 (N5 below: M15 only, no M5); the target-below-2R item is answered in principle by N6 below (minimum 2R), with the mechanical definitions left to a later task. The older suggestion to skip setups below 2R was never an approved decision and is superseded as a recommendation. Also open inside the proposal: whether an IRL FVG must also lie inside the swing leg in time; size filters for FVG; reuse limits; whether TAKEN should use live price.

## H4 direction change and reconfirmation (T003 draft, revision 5) - four kinds of content, kept apart
Sources: the client's text clarifications and the BUY example of 2026-10-13, relayed by the owner. Client screenshots are ILLUSTRATIONS: no price, date or candle index in them is a rule, and where a text clarification exists it takes priority over how arrows or shapes might be read. The screenshots are not stored in the repository. Full text, state table, acceptance criteria and tests: tasks/T003-h4-bias-change.md (nothing implemented).

A. CLIENT STATEMENTS (DECISIONS.md, 2026-10-13):
- S1. A change from bearish to bullish needs a break of the relevant H4 structural level; in the client's first picture the first marked level is enough and the higher high need not be broken. "First level" is not automatically the nearest high or a small swing; its algorithmic choice is still to be formalised.
- S2. The pass must be with the body; a wick-only pass does not confirm a change and may be a liquidity grab.
- S3. SELL: after a wick above the structural level the robot stops NEW entries from the previous setup and waits for reconfirmation. Silent about open positions.
- S4. SELL reconfirmation needs a NEW bearish H4 FVG formed AFTER the wick; a pre-wick FVG is not enough even if touched again.
- S5. After the new H4 FVG: the touch is at that H4 FVG (wick allowed) and we wait for the close of the H4 candle that touched it (an earlier client clarification relayed by the owner; original wording not in the repository); then a new M15 structure break; entry at the M15 FVG after the break. H4 FVG/IRL is context, not entry; trend-direction setups only, IRL -> ERL.
- S6. (2026-10-13, earlier text) Open: M5 role; policy below 2R. SUPERSEDED the same day by N5 (M5 removed, M15 only) and N6 (minimum 2R), see the revision 11 section below. Kept for history.
- E1-E5 (BUY example, H4): price rising with two consecutive BOS; in the circled part price looked as if it had broken the structure down but was only a liquidity grab; after the grab the next H4 FVG formed; price touched it and then made another BOS up; the red arrow is the expected rise; the client said the entry is at the FVG and the target is the top of the third broken structure.
- E6 (same BUY example, third screenshot; the client's words as relayed): "After the liquidity we have the main FVG where we expect price to return, and we have to wait for a structure break on M15. The target is the upper red line, at the last HH." An INTERNAL liquidity grab without a confirmed change of the BUY trend; after it a new H4 FVG forms; wait for the return/touch and then an M15 structure break. H4 FVG is context, not a direct entry; entry stays at the M15 FVG after the break (S5). The target of this example is the last HH (the upper red line), not the local level labelled on the price axis; no prices are used.
  Limits (owner's instructions): evidence on the BUY side (E1-E6) for wick/grab versus confirmed structure change AND for the sequence new H4 FVG after the grab -> return/touch -> M15 structure break (this is no longer SELL-only evidence); "two/third BOS" is the order in this example, not a condition (no fixed number of BOS); the green zone is the H4 FVG formed after the grab; the arrow is an expectation, not a signal; "entry at the FVG" does not cancel S5 (H4 is context, entry is at the M15 FVG after the break); the target is the top of the broken structure / the last HH in this example only, not a universal ERL rule; internal liquidity is not the structural level and the grabbed low is not assumed to be the protecting low (automatic choice of the level stays a proposal for validation); no fixed count of BOS; the remaining BUY/SELL mirror details (body-close flip rule, which FVG candle must follow the wick, hysteresis, protected-level choice) are NOT client confirmations; M5 and the 2R policy stay open.

B. AUTHORISED EARLIER DECISIONS: the owner's authorisation (2026-10-07) to propose mechanical rules for what the client selects visually, as proposals awaiting visual validation; the T002 proposals (swing 2/2, direction test, interval, FVG states, ERL taken, ordering) stand unchanged and unvalidated.

C. PROPOSED, NOT CLIENT ANSWERS (T003 P1-P14; labelled "proposed" everywhere). Three of them are technical proposals and not client statements: the intrabar block (P12, from Codex's review), candle A of the new FVG being allowed to be the wick candle (P5), and blocking entries when the history is insufficient (P11, fail-safe for a later execution task):
- P1 Body = H4 close strictly beyond the level (equality is not a break); high beyond with the close not beyond = wick-only; "level crossed without a confirmed change" means wick-only.
- P2 Structural level (bearish context): the highest confirmed swing high between the latest lower low and the low before it; minor swings inside the leg and corrective lows do not become the level; missing bounds or an already body-broken candidate = undefined. Mirror for bullish. Timing: the candidate is derived from the state known before the evaluated bar; the evaluated bar crossing it is an event to process, never a reason to discard it. A consumed candidate (already crossed and processed) is kept as the frozen protecting level during HOLD. A wick that preceded the level's discovery keeps its source time and is detected at discovery (no HOLD in NONE). Internal liquidity (for example an interior low) is kept distinct from this level (P14). Validated only by visual comparison with the client's examples (T003 section 10), never claimed validated.
- P3 Bias layer with hysteresis next to T002's direction: once a bias exists, only a body close beyond the CURRENT protecting level reverses it, whatever T002 says; other breaks (latest HH/LL, interior levels) are continuation or internal events, not flips; a bias without a level cannot flip.
- P4/P5/P6/P7 Wick event with separate timestamps: source_wick_time (the physical wick), source_wick_known_time (its close) and detected_at (when the machine could first know it is a wick against a held level); HOLD and the entry block start at detected_at, with no claim about the past before it (a wick before the level was known is retroactive); the new FVG qualifies by its candle A being at or after source_wick_time (working interpretation, see F1) while touches count only from detected_at; the touch counts at the close of the touching H4 candle (client information); transitions for repeated wicks, flips and invalidations.
- P8 BUY mirror (a proposal; the BUY example E1-E6 supports the sequence grab -> new H4 FVG -> return/touch -> M15 break and the wick/grab distinction, not the other mirrored details).
- P13 Target candidate for display only: the latest confirmed higher high (BUY) / lower low (SELL), kept apart from local pullback levels; T002's ERL unchanged; compared with the client's example, never validated, never a universal target rule.
- P9 One causal replay over closed bars for live and historical.
- P10 Bias start, from NONE only: breaks against levels known before the bar come first; only if the state is still NONE and the bar produced no CONFLICT does the T002 seed apply; a break outranks the seed; breaks of both kinds on one bar give NONE (CONFLICT) and the seed does not overwrite it on that bar; no evidence gives NONE (NO_EVIDENCE); the several P10 candidates are ignored once a bias exists. No direction is invented.
- P11 History, restart and window, ONE mechanism: a stateless fixed-depth rebuild (no persisted state) with a depth-sensitivity check. REBUILD_BARS default 1000 (never below 3 x lookback), warm-up = lookback, check depth = warm-up, hard cap 5000 bars; the state is rebuilt over R_eff bars and over R_eff minus the check depth, and is RELIABLE only if both agree on the final state and the events in the shorter run's trusted region, the dependency anchor lies after the warm-up, and R_eff is at least 3 x lookback. Flags CONVERGED / SEEDED / LIMITED_BY_HISTORY: CONVERGED is evidence at the tested depth, not a guarantee that more or older history would not change the state. When not reliable (or the depth is not reached) the direction is reported UNKNOWN (limited by history) with no market event; depth-caused differences are RE-DERIVATION, never FLIP/WICK/RECONFIRMED/SWEEP. Failing entries closed when LIMITED is a technical proposal for the later execution task, not a client statement.
- P14 Internal liquidity grab (the flow internal liquidity -> new H4 FVG -> touch -> M15 break is client-confirmed; the detection and the wait are technical proposals): an interior low swept by a wick with the protecting low not crossed raises INTERNAL_SWEEP and a SWEEP_WAIT for a new FVG, without changing the bias; a crossing of the protecting low is the structural wick/break instead and supersedes; whether entries of the previous setup are blocked during the wait is not stated by the client.
- P12 Intrabar block (Codex's technical proposal, awaiting the owner's decision): a strict crossing of the held level by the forming H4 candle blocks new entries immediately and only restricts; the direction change is confirmed only by an H4 close beyond the level. At the close: wick-only becomes the closed-bar HOLD; a body break ends the block in the flip; equality is not a crossing. Live only; historical mode cannot reproduce it.

D. STILL OPEN:
- F1 exact time definition of "new FVG after the wick"; F2 M5/M15 relation (M5 part closed by N5; the M15 details stay Q04); F3 policy below 2R (answered in principle by N6, mechanics later; the skip recommendation was never approved and is superseded); F4 positions already open; F5 ERL selection and reconfirmation validity (inside T002's interval or not, how long it stays valid, re-deriving the frozen level, target rule); F6 whether an intrabar block is wanted; F7 whether new entries are blocked while the state is LIMITED_BY_HISTORY (the fail-safe block is a technical proposal); F8 how interior liquidity is identified, whether entries are blocked during the internal wait, what a body close below an interior low means, and whether the grabbed low in the client's picture is interior or protecting (no assumption).
- Resolved: the touch rule is client information (S5), no longer a question.

## H4 direction layers and the client text of 2026-10-13 (T003 revision 11, DOCUMENTS ONLY) - four kinds of content, kept apart
Source: text clarifications of the client relayed by the owner on 2026-10-13. The videos the client mentioned were NOT sent: nothing here claims they were seen or analysed. Photos stay illustrations. Full text, the layers, the comparison table, the scenarios and the open ambiguities: tasks/T003-h4-bias-change.md section 13 and reports/T003-verification.md section 15. No code was changed.

A. CLIENT STATEMENTS (relayed by the owner; DECISIONS.md rows of 2026-10-13, N1-N7):
- N1. Direction is understood only from structure: rising = HH and HL; falling = LH and LL. So HH+HL = bullish structure, LH+LL = bearish structure. Confirms how the client DESCRIBES direction. Does NOT confirm: using the two latest local swings; the 2/2 fractal as the definition of a structural swing; the ratchet; holding a bias until a historical level is broken.
- N2. Current structure and historical liquidity are different things. Red lines mark highs/lows and structure levels; if the market keeps falling and the red levels above stay unbroken for days, they can serve as liquidity zones when price returns. Four layers are distinguished (below). An old liquidity level is not a sufficient reason to keep the current direction frozen. The algorithm that tells a structural swing from a local swing is NOT given by the client and is not invented here.
- N3. The sky-blue bars are the main H4 FVGs. In two other examples the marked structure was bearish (LH and LL); the circled parts were called liquidity grabs, not a direction change, because the previous direction later continued. Earlier clarifications: a wick alone does not confirm a change; the client wants a break with the body. Our reading "close of the candle beyond the level" is a technical interpretation; it is not a licence to use any local level as the protecting level. What is known at the close of the candle that crosses a level must stay separate from what later candles confirm; a later candle never classifies the past event and never permits a past entry.
- N4. Flow kept: only trend-direction setups, IRL -> ERL; the IRL here is an H4 FVG and is NOT the entry; the H4 FVG touch may be by wick; wait for the close of the H4 candle that touched; then an M15 structure break; entry on the return to the M15 FVG after the break. After a wick / liquidity grab the client asked for a NEW H4 FVG; an FVG from before the event is not enough. BUY evidence too: liquidity -> new H4 FVG -> return/touch -> M15 break. The exact time of the three FVG candles relative to the event and the mechanical identification of the sweep remain technical proposals.
- N5. M5 is removed from the confirmation: 'Make it break only on M15 so we do not mix it up. Since we also wait for the FVG on M15.' REPLACES the earlier request for M5 identification/confirmation (history kept: S6 and F2 above, marked superseded). Structure confirmation for entry is M15 only; the entry FVG is M15; no M5 confirmation, filter or condition exists.
- N6. Minimum 2R: 'In cases where the target is less than 2R, the minimum will be set to 2R.' When the structural/ERL target gives less than 2R, TP is set at the 2R minimum (this can place TP beyond the initial ERL); the trade is NOT skipped only because the ERL is below 2R; a target farther than 2R is NOT shortened to 2R. The mechanical definitions of R, SL, entry/fill price and cost handling are NOT given and are specified in the relevant later task. Any earlier 'skip below 2R' suggestion is superseded as a recommendation (it was never an approved decision). Observation for that later task, not a question: the partial exit at 2R (section above) and a TP set at 2R coincide.
- N7. Examples are not constants. Prices and dates in the photos are evidence, not robot parameters. 'First/second/third BOS' describe the examples: no fixed BOS count. The last HH as target is confirmed in the BUY example; this does not formalise a universal ERL algorithm.

B. OWNER DECISIONS: (2026-10-13) this round is documents only; the text is relayed, the videos are not available; no M15, target, trading or code work starts. Earlier: the prototype authorisation (DECISIONS.md) is not a client answer.

C. TECHNICAL PROPOSALS (ours, unvalidated): T002 swing 2/2 and direction test; T003 P1-P14; the revision 10 prototype (ratchet, structure/setup separation, variant A, current level decides FLIP). N1-N7 do not turn any of them into a confirmed rule. In particular the ratchet and the bias hysteresis can hold a bias that contradicts the HH/HL or LH/LL structure of N1 (T003 section 13.6, report section 15.4): a finding about the proposal, by its design, not a client-approved behaviour.

D. STILL OPEN: which swings count as STRUCTURE versus local (N2); whether and how long a bias may be held against HH/HL or LH/LL (extends C1, the level-update question already asked); F1, F4, F5, F6, F7, F8; the M15 details (Q04); the mechanics of R/SL/entry/fill/costs for the 2R minimum (later task); the interaction of the 2R minimum with the partial exit and with the target selection.

Layers (T003 section 13.3): (1) CURRENT STRUCTURE for direction (HH/HL, LH/LL); (2) HISTORICAL LIQUIDITY LEVELS (unbroken old highs/lows, targets or return zones, not the direction); (3) H4 FVG ZONES (context/IRL, not the entry); (4) the SETUP awaiting confirmation (wick or sweep, new H4 FVG, touch, then M15). Layer (2) is not implemented as a separate layer.

## Approval policy
Record client-confirmed additions with date and source in DECISIONS.md and then update this specification. Developer proposals must be visibly labeled PROPOSED and confined to visual/experimental work until confirmed. A platform constraint may require a documented client choice; it is not permission to silently change strategy.
