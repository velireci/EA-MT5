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

## Approval policy
Record client-confirmed additions with date and source in DECISIONS.md and then update this specification. Developer proposals must be visibly labeled PROPOSED and confined to visual/experimental work until confirmed. A platform constraint may require a documented client choice; it is not permission to silently change strategy.
