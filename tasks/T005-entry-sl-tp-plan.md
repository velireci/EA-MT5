# T005 - entry, SL/TP and minimum 2R: plan, corrected, and the pure geometry step

Status: 2026-10-14. Part 1 (sections A-C, tensions) is the corrected plan. Part 2 (section D) is the IMPLEMENTED pure geometry helper: src/include/TradeGeometry.mqh, not wired to any EA or order. No order, volume or risk code exists. MetaEditor compile and MT5 run: UNVERIFIED.
Correction history: the first version of this plan (5447ef3) said the entry edge and the SL principle were not defined and proposed asking the client. Codex checked the original sources and found that wrong; this version fixes it. Do NOT ask the client again whether the entry is at the start/middle/end of the FVG or whether the SL follows the broken structure.
Sources: docs/STRATEGY_SPEC.md, docs/DECISIONS.md, docs/OPEN_QUESTIONS.md, tasks/T004-m15-confirmation.md, docs/reference/strategy-review.md, and (read directly by the parent for the quotes below) inputs/client-E27N93/pergjigjet.json and specifikimi.txt. Photos and private CSVs were not opened by this writer.

## Client statements that define entry, SL and profit (verbatim, with location)
- inputs/client-E27N93/pergjigjet.json line 187 (state.answers.own_words) and inputs/client-E27N93/specifikimi.txt line 24 ("Entry rule in the trader's own words"): "Entry eshte te fillimi i FVG ne M15 dhe Stop Loss ne piken me te lart te struktures se thyer ne M15 ne rastin e Sell ose ne piken me te ulet te struktures se thyer ne M15 ne rastin e Buy dhe Profit eshte Likujditeti i jashten sic e thash dhe me siper"
  = Entry is at the beginning of the FVG on M15; Stop Loss at the highest point of the broken M15 structure for a Sell, the lowest point of the broken M15 structure for a Buy; Profit is the external liquidity as said above.
- pergjigjet.json line 189 (state.answers.pd_level), repeated in specifikimi.txt line 26: "E vendos Entry ne fvg, stop los ne piken me te lart te struktures se thyer nese jemi Sell dhe ne piken me te ulet te struktures se thyer nese jemi Buy. Profit tek likuiditeti i rradhes"
- Earlier wording for the target: pergjigjet.json line 29 / 290 (photo note): "... Profit tek likuiditeti i rradhes sic eshte shenur dhe ne foto me 2 pjes"; pergjigjet.json line 209 (tp_level): "Profit eshte tek thyerja e struktures se rradhes qe quhet dhe si likujditet i rradhes".
- The client therefore uses two wordings for the profit: "Likujditeti i jashten" (external liquidity, ERL; own_words) and "likuiditeti i rradhes" / "likujditet i rradhes" (next liquidity; pd_level, tp_level, photo notes). This plan cites both and does NOT decide which universal target algorithm applies (C5).
- The structured field sl_method = "?" (pergjigjet.json line 206; specifikimi.txt "Stop loss placement: UNKNOWN") is an unanswered form field. It does NOT cancel the written answers above.

## Supported visual interpretation (relayed by Codex; not a citation, not additional client validation)
Codex viewed the three original photos (this writer and the parent did not). Relayed: in the two SELL examples the drawn entry appears at the LOWER edge of the small local M15 FVG; in the (unactivated) BUY example it appears at the UPPER edge. Reading: "the first edge met on the return" (SELL lower, BUY upper). This is the supported way to read "fillimi i FVG" as a price; it is an interpretation of drawings, no price from the photos is used, and it is not a separate client statement.

## A. Explicitly defined by the client
| # | Statement | Source | What it does NOT define |
|---|---|---|---|
| A1 | Execution is a LIMIT order; the entry is "te fillimi i FVG ne M15" (the beginning of the M15 FVG) after the M15 structure break, on the return to the FVG | pergjigjet.json:187 and specifikimi.txt:24 (quoted above); "Order execution: limit order at a level"; pd_level (:189) "E vendos Entry ne fvg" | The choice among SEVERAL M15 FVGs; any offset (the questionnaire field "Pending order distance from reference" is UNKNOWN; no value is invented, zero is NOT confirmed). The edge reading "SELL lower / BUY upper" rests on the relayed visual interpretation above |
| A2 | SL principle: the extreme of the BROKEN M15 structure: SELL = its highest point, BUY = its lowest point | pergjigjet.json:187 and :189 (pd_level); specifikimi.txt:24 and :26; STRATEGY_SPEC Explicit answers | Which algorithm identifies the whole broken M15 structure (swing choice, T004's latest-fractal level is only a proposal); any buffer/offset (none stated; zero is NOT confirmed) |
| A3 | Final profit at the external liquidity / next liquidity (two wordings cited above) | pergjigjet.json:187 ("Likujditeti i jashten"), :189 ("likuiditeti i rradhes"), :209 | Which single algorithm selects the target when several levels exist; whether it updates; E6/N7: the last HH is the target of that BUY example only, not a universal rule |
| A4 | N6: if the structural/ERL target gives less than 2R, TP is set at 2R (may lie beyond the ERL); the trade is NOT skipped for that reason; a farther target is NOT shortened to 2R | DECISIONS N6 (2026-10-13); Q07 | R, SL, entry/fill price and cost handling (stated in N6 itself) |
| A5 | Close 80% of INITIAL volume at 2R; remaining 20% to final TP or SL; no trailing stop | specifikimi.txt Partial 1 at 2R / 80% / initial volume / Trailing: No; STRATEGY_SPEC | Whether "2R" is measured from entry or fill; the volume step rounding; screenshot levels differ from 2R and "no level is adopted without confirmation" (STRATEGY_SPEC conflicts) |
| A6 | Cancel pending orders on direction change, opposite signal, session end, avoided news | specifikimi.txt Pending order lines | Exact trigger moments; pending order EXPIRY is UNKNOWN; open-position behaviour at those events is UNKNOWN |
| A7 | One entry per signal; "new signal" = each new candle meeting the conditions | specifikimi.txt; STRATEGY_SPEC | Identity of a distinct FVG/MSS setup; re-entry and cooldown UNKNOWN |
| A8 | Risk statements: 1% per trade (method/base unknown); up to 2 open positions; 2% combined open risk; 10-lot cap; skip on risk/broker conflict; daily loss 2% of start-of-day balance, closed results only | specifikimi.txt Risk; STRATEGY_SPEC | Sizing method and base ("do not implement sizing until confirmed"); whether pending orders reserve risk |
| A9 | Max SL distance 50 USD of gold price movement; skip if SL too large | specifikimi.txt | The unit is stored as gold-price units; client confirmation of the unit is open. NOT enforced by the geometry helper |
| A10 | Break-even trigger 2R; SL to "entry plus costs"; prose "+0.2%" | specifikimi.txt; STRATEGY_SPEC conflicts | Conflict OPEN: entry plus costs versus +0.2%; the base of 0.2% |

## B. Existing technical proposals (UNVALIDATED, not rules)
- T002 H4 swing 2/2, trend, interval, FVG states FRESH/TOUCHED/INVALID, IRL candidates, nearest-first selection, ERL taken.
- T003 P1-P14 (target candidate P13 is display-only).
- T004 M15 latest-fractal level, A-at/after-BOS FVG timing, all same-direction FVGs kept as candidates, RETURN_OBSERVED as a fact, T002-touch sources AFTER_LOSS / FIRST_ONLY, OD1-OD6. The relayed 2026.09.18 owner observation shows these proposals behaving in sequence; it chooses no entry price, SL or risk.

## C. Still not explicitly defined (open; no value invented)
"Blocks D" = blocks the geometry helper (none do, because E, S, T are inputs). "Ask" = a client question is justified only if it truly blocks a later step; no question is queued now for the points the client already answered.
| # | Open decision | Why it changes the result | Blocks D? | Ask the client? |
|---|---|---|---|---|
| C1 | WHICH M15 FVG becomes the entry FVG when several qualify (the edge is NOT the question: A1) | Decides entry, R and fill probability | No (E is an input) | Only when the order step needs it; T004 keeps all candidates and selects none |
| C2 | WHICH algorithm identifies the WHOLE broken M15 structure whose extreme is the SL (the principle is NOT the question: A2); and whether any buffer/offset exists (none stated; zero NOT confirmed) | Sets SL and R, hence 2R, the 50 limit and volume | No (S is an input) | Only with Q04 (the M15 swing definition); not as a stand-alone question |
| C3 | Definition of R: entry-to-SL only, or including spread/commission/slippage | A 2R TP and the 80% point move by the cost amount | Partly: the helper reports R_geom and COSTS_NOT_MODELLED | Later, with C10 |
| C4 | 2R measured from which price (limit price, fill, entry plus costs) | Moves TP and the partial point | Partly: the helper measures from the supplied E | Later |
| C5 | Structural/ERL target algorithm when several exist ("Likujditeti i jashten" versus "likuiditeti i rradhes"); updates | Decides whether 2R or the structure is TP | No (T is an input) | Only if T003 P13 is not accepted |
| C6 | Sizing base, risk per trade, capital, account kind | Volume and risk | Not in D (no sizing) | Yes, blocks sizing |
| C7 | Conflicts: daily trade limit 2 vs 3; +0.2% vs entry plus costs; 50-unit meaning | Gate logic, post-partial SL | No | Later, one batch |
| C8 | Pending expiry; same-setup re-entry; cooldown; opposite signal with an open trade | Order lifetime and duplicates | No | Yes, blocks order management |
| C9 | T002 vs T003 direction priority when they disagree | Whether a setup exists | No | Yes, blocks any setup-to-order link |
| C10 | After the 80% partial: breakeven SL, trigger, remainder behaviour when TP equals 2R | Result of the remaining 20% | No (D stops at the 2R point and flags the coincidence) | Later |
| C11 | Broker constraints on the target account (stops level, freeze level, tick size, volume rules, filling, spread limit, hedging/netting, manual trades) | Order acceptance, 80/20 feasibility | Parameters are passed in; real values UNVERIFIED | No; read from the account |
| C12 | Open positions at session end/news | Exposure | No | Later |

## D. Pure trade-geometry helper (IMPLEMENTED; contract fixed before code)
Files: src/include/TradeGeometry.mqh (MQL5), tests/t005_geometry_reference.py (Python mirror), tests/t005_geometry_fixtures.py (hand-computed table, shared), tests/test_t005_geometry.py (20 unit tests), src/tests/T005_GeometryTest.mq5 (MT5 script mirroring the table; its fixture block is checked equal to the Python table), tools/t005-static-checks.sh + tools/t005-static-check.py. Evidence: reports/T005-verification.md.

Inputs: direction (BUY/SELL); E_raw; S_raw; optional T_raw; symbol parameters tick_size, digits (0..8), point, stops_level (points); optional bid and ask (only together). The module does NOT choose entry, SL, FVG or target, does not read T004 facts, has no sizing/volume and no order function.

ROUNDING CONTRACT (conventions are PROPOSALS for review, not client answers):
1. E and S are converted to INTEGER ticks first: nearest tick; an exact half tick goes UP (for E and S, BUY and SELL alike, so BUY and SELL are not mirror images at an exact half tick). Tolerance 1e-6 tick for "on the grid" and "half tick".
2. E_out and S_out are reported on the grid. R_geom = |E_out - S_out| and level_2R = E_out +/- 2*R_geom are computed from exactly those reported integer ticks. 2R is never computed from one SL while another SL is reported (mutation-checked).
3. Target T rounds AWAY from the entry (BUY up, SELL down; a value already on the grid is unchanged), so rounding cannot undercut the 2R minimum. TARGET cases judged on ticks after normalization: NONE (no target), NEARER, EQUAL, FARTHER than 2R.
4. TP per N6 = the farther of the normalized target and level_2R: farther target kept (never shortened), nearer or missing target gives level_2R (never skipped). partial_price = level_2R, label "PARTIAL_AT_2R (client answer: 80% of initial volume)"; no volume is computed. tp_equals_2r flags the coincidence of TP and the partial point; the remainder's behaviour stays unspecified (C10).
5. R_geom is a plain price distance, distinct from any cost-adjusted R. Costs are not handled: label COSTS_NOT_MODELLED, no cost-adjusted value. R_geom is not claimed to be the client's final R (C3/C4).
6. Stops: min distance = stops_level * point; SL distance below it is BELOW_STOPS_LEVEL (equal is allowed). TP distance is also checked but cannot fail first (TP >= 2R >= R).
7. Pending distance, only when bid and ask are supplied: BUY limit must be below Ask, SELL limit above Bid, by > 0 and >= the stops distance; otherwise PENDING_TOO_CLOSE (pending_check TOO_CLOSE). Without quotes pending_check = NOT_CHECKED and status stays OK.
8. Statuses, first failing check wins in this order: INVALID_DIRECTION; INVALID_INPUT (non-finite, tick/point <= 0, bad digits/stops_level, then tick/digits compatibility [tag INCOMPATIBLE_TICK_DIGITS: tick_size must be >= 10^-digits and an integer multiple of 10^-digits within 1e-6; 0.001 with digits 2 and 0.015 with digits 2 are rejected, 0.01/0.05/0.25 with 2, 1 with 0, 0.5 with 1 accepted; point stays independent], non-positive prices, bid > ask, only one of bid/ask, range [NUMERIC_OVERFLOW: price/tick_size <= MAX_TICKS 1e12 in both languages, far below 2^53]); then normalization and INVALID_INPUT again if E_out or S_out is not finite [NUMERIC_OVERFLOW] or not > 0 [NONPOSITIVE_PRICE]; ZERO_RISK (E_out == S_out); SL_WRONG_SIDE (strictly wrong side after normalization; equality is ZERO_RISK); INVALID_INPUT if level_2R / R_geom is not finite or level_2R <= 0 [e.g. SELL 100/160]; INVALID_INPUT if the normalized target is not finite or <= 0; TARGET_WRONG_SIDE (normalized target not strictly beyond E_out); INVALID_INPUT if TP / partial is not finite or <= 0; BELOW_STOPS_LEVEL (distances must be finite); PENDING_TOO_CLOSE (gap must be finite); OK. Every non-OK status carries a reason. On the positivity / overflow INVALID_INPUT failures no geometry is reported (computed false, every numeric and tick field 0). ZERO_RISK / SL_WRONG_SIDE keep E_out / S_out. Numeric fields are only meant for status OK.
Unenforced open items: the "50 stop-distance" limit (unit unconfirmed; a 100 USD stop is NOT rejected, tested), freeze level, spread limit, volume rules, hedging/netting.

What the module deliberately does NOT decide: the entry FVG among several (C1), the broken-structure algorithm or SL buffer (C2), cost-inclusive R (C3), fill price (C4), target selection (C5), sizing and risk (C6), the 50-unit limit (C7), expiry/re-entry (C8), T002/T003 priority (C9), post-partial SL (C10), session/news handling (C12).

Assumptions needing review: half-tick-up and target-away conventions; the 1e-6 tolerances; digits limited to 0..8 (NormalizeDouble); a limit exactly at the market (distance 0) counts as too close; a normalized target equal to E_out is a wrong-side target.

## Tensions found between documents
1. specifikimi.txt and pergjigjet.json list "Stop loss placement" (sl_method = "?") as UNKNOWN while the same files hold the client's written SL principle (:187, :189). The written answer governs the principle; only the structure-identification algorithm and buffer remain open (C2).
2. STRATEGY_SPEC summarises the SL as "a relevant M15 structural high/low"; the client's words say "the broken structure" (te struktures se thyer). These are different selections (the broken structure versus any relevant swing). Prefer the client's words.
3. docs/reference/strategy-review.md (reviewer table) says "Limit order at the beginning of the M15 FVG" with "exact boundary undefined". The words "fillimi i FVG" are the CLIENT's own (pergjigjet.json:187, specifikimi.txt:24), not a reviewer interpretation. What remains undefined is the choice among several FVGs and any offset; the price-edge reading (SELL lower, BUY upper) is a supported visual interpretation only.
4. Break-even at 2R with "entry plus costs" versus prose "+0.2%": already an OPEN conflict. A TP at 2R and the 80% partial at 2R coincide, so the remainder behaviour needs C10.
5. The client uses "Likujditeti i jashten" (external, :187) and "likuiditeti i rradhes" (next, :189, :209) for the profit; these may or may not be the same level (C5).
6. docs/OPEN_QUESTIONS.md header says all entries are open as of 2026-10-07 while Q04/Q07 carry later notes; stale header only.

## Stays blocked
Any order placement, limit price choice, SL placement, volume and risk sizing, pending-order lifecycle (expiry, cancel triggers, duplicates, restart recovery), post-partial management, daily/loss gates and news/session actions: all need C1, C2, C6, C8, C9, C10 or C12 as applicable. Q04 stays open and the T004 sources stay unselected by default.
