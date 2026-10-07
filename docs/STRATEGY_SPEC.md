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

## Approval policy
Record client-confirmed additions with date and source in DECISIONS.md and then update this specification. Developer proposals must be visibly labeled PROPOSED and confined to visual/experimental work until confirmed. A platform constraint may require a documented client choice; it is not permission to silently change strategy.
