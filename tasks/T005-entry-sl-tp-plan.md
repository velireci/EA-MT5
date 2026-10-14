# T005 - entry, SL/TP and minimum 2R: planning document

Status: PLANNING ONLY, 2026-10-14. Nothing here is implemented, validated or approved. Written from existing documents; no client answer was added. No orders, no sizing, no code in this document.
Sources checked: docs/STRATEGY_SPEC.md (Explicit answers, Explicit conflicts, Engineering requirements, T003 section D, N1-N7), docs/DECISIONS.md, docs/OPEN_QUESTIONS.md (Q05, Q07-Q11), tasks/T004-m15-confirmation.md, docs/reference/strategy-review.md (sections D, conflicts, chart table), inputs/client-E27N93/specifikimi.txt and pergjigjet.json (text only; photos and private CSVs not opened).

## A. Explicitly defined by the client
| # | Statement | Source | What it does NOT define |
|---|---|---|---|
| A1 | Execution is a LIMIT order at a level; entry "at the FVG" after the M15 structure break, on the return to the M15 FVG | specifikimi.txt "Order execution" and "Pending order reference"; STRATEGY_SPEC Explicit answers; DECISIONS 2026-10-07, S5/N4 | Which edge/price of the FVG (beginning, midpoint, offset); which FVG when several; "Pending order distance from reference" is UNKNOWN (clarifyWithClient pd_dist) |
| A2 | SL: "highest point of the broken structure if SELL, lowest point if BUY" (own words, pd_level); spec summary: "relevant M15 structural high/low" | pergjigjet.json state/answers/pd_level; STRATEGY_SPEC Explicit answers; strategy-review.md D | Which swing is "the broken structure"; buffer; the questionnaire field "Stop loss placement" is still UNKNOWN (sl_method) |
| A3 | Final TP at the next liquidity / next structure break ("likuiditeti i rradhes") | specifikimi.txt "Take profit level"; example photo notes; STRATEGY_SPEC | How the target is chosen when several levels exist; whether it updates; E6/N7: the last HH is the target of that BUY example only, not a universal rule |
| A4 | N6: if the structural/ERL target gives less than 2R, TP is set at 2R (may lie beyond the ERL); the trade is NOT skipped for that reason; a farther target is NOT shortened to 2R | DECISIONS N6 (2026-10-13); Q07 | R, SL, entry/fill price and cost handling (stated in N6 itself) |
| A5 | Close 80% of INITIAL volume at 2R; remaining 20% to final TP or SL; no trailing stop | specifikimi.txt Partial 1 at 2R / 80% / based on initial volume / Trailing: No; STRATEGY_SPEC | Whether "2R" is measured from entry or fill; volume step rounding of the 80% split; screenshot levels differ from 2R and "no level is adopted without confirmation" (STRATEGY_SPEC conflicts) |
| A6 | Cancel pending orders on direction change, opposite signal, session end, avoided news | specifikimi.txt Pending order lines; pergjigjet.json pd_* = cancel | Exact trigger moments; pending order EXPIRY is UNKNOWN (pd_expiry); open-position behaviour at those events is UNKNOWN |
| A7 | One entry per signal; "new signal" = each new candle meeting the conditions | specifikimi.txt; STRATEGY_SPEC | Identity of a distinct FVG/MSS setup is unresolved; re-entry and cooldown UNKNOWN |
| A8 | Risk statements: 1% per trade (introductory fact, method/base unknown); up to 2 open positions; 2% combined open risk; 10-lot cap; skip the trade on risk/broker conflict; daily loss 2% of start-of-day balance, closed results only | specifikimi.txt Risk section; STRATEGY_SPEC | Sizing method and base (size_method, capital, account_kind UNKNOWN: "do not implement sizing until confirmed"); whether pending orders reserve risk |
| A9 | Max SL distance 50 USD of gold price movement; skip if SL too large | specifikimi.txt | Unit stored as gold-price units; client confirmation of the unit is open |
| A10 | Break-even trigger 2R; SL to "entry plus costs"; prose "+0.2%" | specifikimi.txt; STRATEGY_SPEC conflicts | Conflict is OPEN: entry plus costs versus +0.2%; the base of 0.2% |

## B. Existing technical proposals (UNVALIDATED, not rules)
- T002: H4 swing 2/2, trend, interval, FVG states FRESH/TOUCHED/INVALID, IRL candidates, nearest-first selection, ERL taken (tasks/T002-h4-map.md).
- T003: P1-P14 (body break, level selection, ratchet, wick event, new FVG after the wick, reconfirmation, target candidate P13 display-only).
- T004: M15 latest-fractal level, A-at/after-BOS FVG timing, all same-direction FVGs kept as candidates, RETURN_OBSERVED as a fact, T002-touch sources AFTER_LOSS / FIRST_ONLY, OD1-OD6 (record end, later touches, re-touch, nearest-first reference price, windows, no expiry) (tasks/T004-m15-confirmation.md).
- The relayed 2026.09.18 owner observation shows these proposals behaving in sequence. It chooses no entry price, SL or risk, and does not decide T002 versus T003.

## C. Missing decisions that affect the result
Blocks = blocks the geometry step in section D. "Ask" = a single question is justified only if it truly blocks a later step.
| # | Missing decision | Why it changes the result | Blocks D? | Ask the client? |
|---|---|---|---|---|
| C1 | Limit price: which FVG edge/offset, and which FVG among several candidates | Sets entry, R and fill probability (example 3: price reached the FVG limit without touching, no trade) | No (entry is an input) | Yes, before order code: "On a bearish M15 FVG, is the sell limit at the lower edge, the upper edge or the middle of the gap?" |
| C2 | "Broken structure" high/low for SL: which swing, buffer | Sets SL and R, thus TP, the 50 limit and volume | No (SL is an input) | Yes, before order code (with Q04): which swing the SL sits at, and with what buffer |
| C3 | Definition of R: entry-to-SL only, or including spread/commission/slippage; fill price vs limit price | A 2R TP and the 80% point move by the cost amount | Partly: D uses the raw geometric distance as an explicit, labelled placeholder | Later, with C10 |
| C4 | 2R measured from which price (limit price, actual fill, entry plus costs) | Moves TP and partial point | Partly: D takes the reference price as an input | Later |
| C5 | Structural/ERL target when several exist; updates | Decides whether 2R or the structure is the TP | No (target is an input) | Only if T003 P13 is not accepted |
| C6 | Sizing base, risk per trade (1% method/base, costs), capital, account kind | Volume and risk | Not in D (no sizing) | Yes, blocks sizing |
| C7 | Conflicts: daily trade limit 2 vs 3; loss stop 2 never fires before max trades 2; +0.2% vs entry plus costs; 50-unit meaning | Gate logic and post-partial SL | No | Later, one batch for the risk step |
| C8 | Pending order expiry; same-setup re-entry; cooldown; opposite signal with an open trade | Order lifetime and duplicates | No | Yes, blocks order management |
| C9 | T002 vs T003 direction priority when they disagree | Decides whether a setup exists at all | No for D | Yes, blocks any setup-to-order link; not decided by the observation |
| C10 | After the 80% partial: breakeven SL, trigger, and whether the remainder gets SL at entry plus costs or +0.2% | Result of the remaining 20% | No (D stops at the 2R point) | Later |
| C11 | Broker constraints on the target account: stops level, freeze level, tick size, volume min/max/step, filling mode, spread limit and action, hedging vs netting, manual trades on the same account | Order acceptance, 80/20 split feasibility, ownership | Parameters are passed in; real values are UNVERIFIED (not a client question) | No; read from the account |
| C12 | Behaviour for open positions at session end/news | Exposure | No | Later |

## D. Proposed next step (ONE bounded step, for review): pure trade-geometry module
Scope: a side-effect-free, replay-safe module (Python reference first, then MQL5, then tests), no order, volume or risk code, no time or tick input.

Inputs, all explicit: direction (BUY/SELL); entry price E and SL price S (supplied, NOT chosen by the module, NOT derived from T004 facts); structural target price T (or "none"); symbol parameters: tick size, point, digits, stops level in points; optional current bid/ask for the pending-order distance check.

Computes, for BUY and SELL by one mirrored formula set:
1. R_raw = |E - S| (raw geometric distance, labelled placeholder for the client's R; costs excluded, see C3).
2. Price at 2R = E + 2*R_raw (BUY) or E - 2*R_raw (SELL), measured from the supplied E (C4 placeholder).
3. TP = the farther of T and the 2R price in the trade direction (N6). T beyond 2R is kept; T nearer or missing gives the 2R price; the trade is never skipped for that reason.
4. Partial point = the 2R price (80% of initial volume per the client answer). The module reports the point, not volumes.
5. Tick-size rounding: a stated direction, TP rounded away from entry (never shortening below 2R), SL rounded away from entry; each rounded value is reported with its raw value. The direction is a proposed convention in the module header, to be reviewed.
6. Broker validation: SL on the correct side of E; |E-S| > 0; E-to-SL and E-to-TP distances at least the stops level (limit price versus market only if bid/ask are supplied, else NOT_CHECKED).
7. Explicit statuses: OK, INVALID_DIRECTION, INVALID_GEOMETRY (zero or wrong-side SL), INVALID_INPUT (non-positive or non-finite values, bad tick size), STOPS_LEVEL_VIOLATION, MARKET_DISTANCE_NOT_CHECKED, TARGET_NEARER_THAN_2R (informational: TP set to 2R), TARGET_BEYOND_2R (informational).

Deliberately does NOT decide: entry price or FVG edge (C1), SL swing or buffer (C2), cost-inclusive R (C3), fill price (C4), target selection (C5), sizing and risk (C6), the 50-unit limit (C7; it can be added later as an input threshold once the unit is confirmed), expiry or re-entry (C8), T002/T003 priority (C9), post-partial SL (C10), freeze level and modification checks (no order modification exists), hedging/netting (C11).

Support in existing decisions: N6 (TP rule, never skipped, never shortened) and the 80% at 2R answer fully support steps 3 and 4. R as |E-S| and measuring from E are the likely reading but N6 says they are NOT defined, so they enter only as labelled placeholders. If review rejects placeholders, the smaller supported part is steps 3-4 expressed in terms of an externally supplied R distance, plus step 6.

Tests needed (Python and MQL5 mirror): BUY/SELL mirror symmetry; target nearer than, equal to, and farther than 2R; missing target; rounding at exact tick multiples and between ticks, both directions; SL on the wrong side or equal to E; NaN/negative/zero tick size; stops level exactly at and one point inside the limit; bid/ask omitted versus supplied; determinism (same inputs, same outputs); no input mutation.

Acceptance evidence, kept separate: (1) Python unit tests with hand-derived values; (2) MetaEditor compile 0/0 with logs; (3) the MQL5 test script run by the owner in MT5 with the logged pass/fail count; (4) static check that the module contains no trading API, time or price-feed call. None of this validates the strategy; a geometry module with placeholders says nothing about entry quality.

## Stays blocked
Any order placement, limit price choice, SL placement, volume and risk sizing, pending-order lifecycle (expiry, cancel triggers, duplicates, restart recovery), post-partial management, daily/loss gates and news/session actions: all need C1, C2, C6, C8, C9, C10 or C12 as applicable. Q04 stays open and the T004 sources stay unselected by default.

## Contradictions or tensions found between documents
1. specifikimi.txt and pergjigjet.json list "Stop loss placement" as UNKNOWN, while the same files hold the client's own text for SL (highest/lowest point of the broken structure). The text gives a broad placement; the structured field is an open question. Treat A2 as broad placement only.
2. STRATEGY_SPEC summarises the SL as "a relevant M15 structural high/low"; the client's words say "the broken structure". These are not the same level selection (the broken swing versus any relevant swing).
3. strategy-review.md describes the entry as "at the beginning of the M15 FVG", but the questionnaire says only "limit order at a level" and "pending order distance" is UNKNOWN. "Beginning" is a reviewer reading, not a client statement.
4. Break-even at 2R with "entry plus costs" versus prose "+0.2%": already an OPEN conflict. Also, N6 notes that a TP at 2R and the 80% partial at 2R coincide, so the remainder behaviour needs C10.
5. docs/OPEN_QUESTIONS.md header says all entries are open as of 2026-10-07, while Q04 and Q07 carry later notes; this is a stale header only, not edited here.
