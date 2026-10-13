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

D. STILL OPEN (not implemented, not decided): exact M5/M15 confirmation relation; policy when the target is below 2R. A suggestion to skip below 2R exists and is NOT an approved decision. Also open inside the proposal: whether an IRL FVG must also lie inside the swing leg in time; size filters for FVG; reuse limits; whether TAKEN should use live price.

## H4 direction change and reconfirmation (T003 draft, revision 2) - four kinds of content, kept apart
Sources: the client's text clarifications and the BUY example of 2026-10-13, relayed by the owner. Client screenshots are ILLUSTRATIONS: no price, date or candle index in them is a rule, and where a text clarification exists it takes priority over how arrows or shapes might be read. The screenshots are not stored in the repository. Full text, state table, acceptance criteria and tests: tasks/T003-h4-bias-change.md (nothing implemented).

A. CLIENT STATEMENTS (DECISIONS.md, 2026-10-13):
- S1. A change from bearish to bullish needs a break of the relevant H4 structural level; in the client's first picture the first marked level is enough and the higher high need not be broken. "First level" is not automatically the nearest high or a small swing; its algorithmic choice is still to be formalised.
- S2. The pass must be with the body; a wick-only pass does not confirm a change and may be a liquidity grab.
- S3. SELL: after a wick above the structural level the robot stops NEW entries from the previous setup and waits for reconfirmation. Silent about open positions.
- S4. SELL reconfirmation needs a NEW bearish H4 FVG formed AFTER the wick; a pre-wick FVG is not enough even if touched again.
- S5. After the new H4 FVG: the touch is at that H4 FVG (wick allowed) and we wait for the close of the H4 candle that touched it (an earlier client clarification relayed by the owner; original wording not in the repository); then a new M15 structure break; entry at the M15 FVG after the break. H4 FVG/IRL is context, not entry; trend-direction setups only, IRL -> ERL.
- S6. Open: M5 role; policy below 2R.
- E1-E5 (BUY example, H4): price rising with two consecutive BOS; in the circled part price looked as if it had broken the structure down but was only a liquidity grab; after the grab the next H4 FVG formed; price touched it and then made another BOS up; the red arrow is the expected rise; the client said the entry is at the FVG and the target is the top of the third broken structure.
  Limits (owner's instructions): evidence on the BUY side for wick/grab versus confirmed structure change; "two/third BOS" is the order in this example, not a condition (no fixed number of BOS); the green zone is the H4 FVG formed after the grab; the arrow is an expectation, not a signal; "entry at the FVG" does not cancel S5 (H4 is context, entry is at the M15 FVG after the break); the target is the top of the broken structure in this example only, not a universal ERL rule; the BUY/SELL mirror details are NOT client confirmations.

B. AUTHORISED EARLIER DECISIONS: the owner's authorisation (2026-10-07) to propose mechanical rules for what the client selects visually, as proposals awaiting visual validation; the T002 proposals (swing 2/2, direction test, interval, FVG states, ERL taken, ordering) stand unchanged and unvalidated.

C. PROPOSED, NOT CLIENT ANSWERS (T003 P1-P12; labelled "proposed" everywhere):
- P1 Body = H4 close strictly beyond the level (equality is not a break); high beyond with the close not beyond = wick-only; "level crossed without a confirmed change" means wick-only.
- P2 Structural level (bearish context): the highest confirmed swing high between the latest lower low and the low before it; minor swings inside the leg and corrective lows do not become the level; missing bounds or an already-touched level = undefined. Mirror for bullish. Validated only by visual comparison with the client's examples (T003 section 10), never claimed validated.
- P3 Bias layer with hysteresis next to T002's direction: kept until a body break, whatever T002 says.
- P4/P5/P6/P7 Wick event with its known time and the entry block; an eligible FVG has candle A on the wick candle or later (working interpretation, see F1); touch counts at the close of the touching H4 candle (client information); transitions for repeated wicks, body breaks and invalidations.
- P8 BUY mirror (a proposal; the BUY example supports only the distinction in E1-E5).
- P9 One causal replay over closed bars for live and historical.
- P10 Bias from the history of breaks, so that a window starting mid-trend can give a bias even when T002 shows MIXED at the evaluation time; no bar after the evaluation time.
- P11 Continuity: anchored window that is not cut under an active state, bars identified by time, restart equivalence, LIMITED_BY_HISTORY, and window-caused changes reported as RE-DERIVATION, never as a market event.
- P12 Intrabar block (Codex's technical proposal, awaiting the owner's decision): a strict crossing of the held level by the forming H4 candle blocks new entries immediately and only restricts; the direction change is confirmed only by an H4 close beyond the level. At the close: wick-only becomes the closed-bar HOLD; a body break ends the block in the flip; equality is not a crossing. Live only; historical mode cannot reproduce it.

D. STILL OPEN:
- F1 exact time definition of "new FVG after the wick"; F2 M5/M15 relation; F3 policy below 2R (a skip recommendation is NOT an approved decision); F4 positions already open; F5 ERL selection and reconfirmation validity (inside T002's interval or not, how long it stays valid, re-deriving the frozen level, target rule); F6 whether an intrabar block is wanted; F7 how an entry module treats LIMITED_BY_HISTORY.
- Resolved: the touch rule is client information (S5), no longer a question.

## Approval policy
Record client-confirmed additions with date and source in DECISIONS.md and then update this specification. Developer proposals must be visibly labeled PROPOSED and confined to visual/experimental work until confirmed. A platform constraint may require a documented client choice; it is not permission to silently change strategy.
