# Open questions

All entries below are OPEN as of 2026-10-07. Ask only the questions needed for the active stage. Full Albanian conversation worksheet: docs/reference/client-clarifications-SQ.md.

| ID | Stage | Decision needed |
|---|---|---|
| Q01 | Direction | Swing selection, H1/H4 roles, disagreement and bias change |
| Q02 | H4 FVG | Gap definition, choice among zones, eligibility, revisit and invalidation |
| Q03 | H4 return | Required touch/penetration/sweep and allowed time for M15 setup |
| Q04 | M15 | MSS swing, wick/close confirmation (M5 removed from the confirmation by the client on 2026-10-13: M15 only; see docs/STRATEGY_SPEC.md), associated FVG and formation timing |
| Q05 | Entry/exit levels | CORRECTED 2026-10-14: the client already wrote the entry at the beginning of the M15 FVG ("fillimi i FVG") and the SL at the extreme of the broken M15 structure (pergjigjet.json:187,189; specifikimi.txt:24,26); see tasks/T005-entry-sl-tp-plan.md. Still open: which FVG among several, the algorithm identifying the whole broken structure, any buffer/offset (none stated, zero NOT confirmed), target selection and updates |
| Q06 | Filter | Objective range classification demonstrated by accepted/rejected examples |
| Q07 | Management | 80% at 2R versus chart levels, exact meaning of +0.2%, target nearer than 2R (ANSWERED 2026-10-13 by the client, relayed by the owner: minimum 2R; see docs/STRATEGY_SPEC.md; R, SL and cost definitions still open) |
| Q08 | Sizing | 1% method/base/costs, capital/account kind, max 2 or 3 trades, stop-distance units |
| Q09 | Orders | Expiry, repeated setup/re-entry, cooldown, opposite open-position signal, spread rejection |
| Q10 | Daily state | Stop-after-win event, total-trade result, loss-streak reset, realized loss accounting |
| Q11 | Exposure/hours | Pending risk reservation/manual exposure, end-of-hours action, news-position action |
| Q12 | Evidence | Filled BUY+SELL sequences, timestamps, indicator links/settings, test dates and acceptance |

Technical verification list: actual symbol/volume constraints, hedging/netting, broker candle alignment, server time/DST, news dataset/provider, allowed partial-volume fallback. Record findings; ask client only where a choice changes behavior.
