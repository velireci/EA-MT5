# T004 - H4 to M15 confirmation foundation

Status: first round verified in MT5 by the owner (49/0 at 51884ec); selector 37/0 and timeline 19/0 relayed; fourth round (ordinary H4 touch source) implemented; at 78879cd the owner relayed T004_OrdinaryTest 79/0 in MT5, Codex relayed 94 Python tests and 0/0 compiles of EA v1.02, OrdinaryTest and TimelineTest; the MT5 run of the UPDATED TimelineTest is PENDING; one owner historical EA observation relayed (reports/T004-verification.md), not client validation. Base 6676a01; branch codex/t004-m15-confirmation. Owner authorised Codex as sole writer on 2026-10-14 while Claude is paused. No changes to T001-T003 source or existing tests/tools. No merge or trading.

## Confirmed flow
H4 context/FVG -> wick touch allowed -> wait for the touching H4 candle to close -> new M15 structure break -> M15 FVG -> return. After a liquidity event the existing requirement for a new H4 FVG stands. M5 is removed. Sources: DECISIONS S5/E6/N4/N5.

## This delivery
A pure chronological M15 observer, a T003 context adapter, an explicit externally supplied M15 level interface, Python/MQL5 behavior tests and an installation/handoff guide. No new visual EA or live series orchestration in this round. It is NOT an entry engine.

The M15 structural-swing selector and exact FVG/BOS timing remain Q04. Default FVG timing policy is UNSET and observes no BOS/FVG pipeline until explicitly selected. A supplied level is labelled a proposed candidate, never client-validated structure. No automatic choice between T002 direction and T003 bias. The H3 adapter requires the caller to select T003 as a prototype source explicitly. Ordinary H4 FVG touches can use the generic context API when an upstream observer supplies the same fields.

## Temporal contract and technical proposals
- Input MqlRates are chronological, CLOSED M15 bars, period 900. A bar is usable only when open >= max(H4 valid_from, context observation time) and open+900 <= asof. The M15 bar ending exactly at the H4 touching close is excluded; the one opening then can be used after its own close.
- A context includes setup ID, explicit direction source, direction, H4 FVG ID/bounds/confirmation and H4 valid_from. Its confirmation cannot be later than valid_from. Unknown/unreliable/not-ready/unselected contexts clear the observer. Changing source/direction/setup/FVG/bounds/confirmation/valid_from starts a new epoch; replaying the same snapshot does not.
- Context timestamps and bars must be observed monotonically. Duplicate identical last bars produce nothing. A changed duplicate or an out-of-order bar blocks the epoch as REPLAY_REQUIRED. A missing M15 interval emits DATA_GAP, discards M15 progress and starts a fresh contiguous segment with no BOS on the gap bar. Full replay is required to repair revised/out-of-order data.
- BOS candidate (proposal): close strictly beyond a supplied level known at bar open. Wick/equality do not qualify. The caller owns active structural-level selection; the observer does not infer a swing or treat any recent high as structural.
- The only opt-in timing proposal implemented: FVG candle A opens at/after the BOS candle, all three M15 bars are contiguous and after activation. Default UNSET blocks the pipeline. Three-bar gap reuses the existing mathematical definition. No size filter.
- All qualifying same-direction FVGs are retained as candidates; none is silently selected as an entry. C cannot count as its own return. Later wick intersection counts once; strict close beyond the far edge invalidates before touch. Multiple candidates may report return in one bar. RETURN_OBSERVED is a fact, not permission to trade.
- No arbitrary expiry, SL, entry edge, target, risk or execution rule. Context invalidation/replacement clears candidates. Session-level live baseline and restart persistence are outside this pure observer; a live caller must baseline replayed events and revoke stale contexts.

## Acceptance
SELL/BUY mirrors; H4/M15 boundary; future/unclosed data; missing or future level; explicit policy/source gate; wick/equality/body distinction; FVG causality and no self-touch; invalidation before touch; multiple candidates; duplicate/revised/out-of-order data; gaps; context loss/replacement; T003 ready/reliability/source adapter; prefix determinism. Compile MQL5 module via its script in MetaEditor. Distinguish Python, compilation, supplemental execution and real MT5 results.

## Remaining integration
Automatic M15 structural level selection and chosen timing policy need separate review. H4 normal-flow touch observer, chronological multi-timeframe orchestration, live baselining and chart display are not supplied here. T003 bias can disagree with HH/HL structure; this task does not resolve it. No order-ready flag exists.

## Second bounded round: experimental swing candidate (Q04 stays open)
The owner authorised continuing after the 49/0 MT5 run. Implement an additive, explicitly disabled-by-default candidate selector. Reuse the existing strict Left/Right swing mathematics (default 2/2, configurable 1..10); do not claim that a fractal is the client's structural swing. Alternatives considered: external level only (first round, no automatic candidate), latest confirmed unbroken swing (this isolated proposal), a multi-leg structural selector (not selected because no client definition is available).

BUY considers swing highs; SELL considers swing lows. At the evaluated M15 bar's open, use ONLY the earlier closed-bar prefix. Select the latest confirmed swing of that side whose price has not already been exceeded by a prior body close. Wick and equality do not consume it. Older eligible swings can be selected if a newer one was consumed. No level means no BOS candidate.

Search a bounded lookback (default 300, at least Left+Right+1, at most 1000) within the last contiguous M15 segment. Report the actual window start, pivot/confirmation and ambiguous count. Never create a swing across missing intervals. Short history, malformed input and no level are distinct statuses. More history may reveal an older candidate: bounded coverage is not full-history certainty. No new A/B guarantee is claimed.

The selector neither mutates the H4/M15 observer nor selects direction. Caller passes the result to M4Step only after selecting source and FVG timing. Pre-context M15 swings may provide a level, but the BOS bar must still open after context activation. This round includes synthetic full-path tests selector -> BOS -> FVG -> return for both directions. No live EA, order permission or client-approved MSS claim.

## Third bounded round: chronological read-only EA
Owner ran SelectorTest-786568a in MT5: 37 passed, 0 failed. Continue with a separate XauUsdM15Observer EA and pure timeline helper. No earlier logic is changed. Only the T003 RECONFIRMED flow is connected in this round; ordinary H4 touch setups remain separate unfinished integration.

Build a timeline of T003 context evaluations using the H4 prefix closed at each snapshot time, never the final H4 state for earlier M15 bars. Initial activation uses the replay's first observed M15 open (a truncated replay, not original eligibility). For equal closing times apply H4 changes BEFORE M15; a newly ready context cannot authorise the M15 candle inside the touching H4 bar. Flush later H4 changes through the as-of even when no M15 bar closes then. Source, swing and timing are three explicit opt-ins, all unselected by default.

Historical mode uses broker/server as-of and no live price. Live mode repeats the closed-data replay once per new M15/H4 boundary and after clear/recovery. All displayed events/logs are labelled REPLAY, never NEW or trade signals. No live alert/baseline guarantee is claimed. On desync/copy failure clear owned objects and results. Only prefix velo_t004_ is owned. Report actual copied/replayed windows, H4 reliability and direction disagreement. Draw candidate FVGs, proposed broken/current levels and a short panel. No trading functions, risk/SL/TP, calendar or M5.

## Fourth bounded round: ordinary H4 FVG-touch source (PROPOSAL, default UNSELECTED)
Goal: connect the ordinary H4 FVG touch to the unchanged M15 mechanism, as a source DISTINCT from the T003 RECONFIRMED one. T001-T003 logic and tests are untouched (byte-identical to 6676a01). No orders, SL/TP, risk or M5. Replays only.

### Decision inventory (reused versus missing)
Reused, with sources:
- IRL = H4 FVG, wick touch enough, trend-direction setups only, IRL -> ERL, nearest zone first then the next if confirmation is missing: DECISIONS 2026-10-07 client answers; STRATEGY_SPEC section "H4 map" A; N4/S5.
- Touch counts at the CLOSE of the touching H4 candle, then an M15 structure break: S5/N4; T003 P6 (touch at the close, INVALID wins on the same bar).
- FVG definition (three closed candles, confirmed at close of C), states FRESH/TOUCHED/INVALID (close strictly beyond the far edge), a touch does not remove a zone and no re-use limit exists: T002 proposal rules 5 and 6 (tasks/T002-h4-map.md; src/include/H4Structure.mqh H4FindFvgs/H4EvalFvgStates).
- IRL candidate = same-direction FVG fully inside the interval; setup active only with a trending direction, valid interval, UNTOUCHED ERL and a selectable candidate; nearest-first order: T002 (H4ClassifyFvgs, H4SetupActive, H4SelectIrl). Direction = T002 direction (HH+HL / LH+LL, N1). No new zone or direction rule.
- Known-before principle (evaluate bar t against the state known BEFORE t; no later candle classifies the past): T003 P3/N3 and section 13 rules; reused as pre/post states.
- A recorded context keeps living while the recorded FVG stays valid; an FVG invalidated by a close beyond the far edge is lost; a later touch of ANOTHER valid FVG can record again; no expiry by bar count: T003 P6/P7, 11.5 (RECONF_LOST keeps the setup), R15.
- M15 mechanism (BOS, FVG formation, return) unchanged. Source/swing/timing remain three opt-ins.
Missing, therefore isolated as TECHNICAL PROPOSALS (not client answers, not blocking; listed as open decisions):
- OD1 How an ordinary record ends. T002 is stateless, T003 has its own setup. Proposal: a record holds while the SAME FVG is a valid IRL candidate with active setup under the post-close state (same trend direction, FVG not INVALID, interval valid, ERL UNTOUCHED, FVG still inside the interval). Any failure revokes at that H4 close (reasons TREND_CHANGE, FVG_INVALID, INTERVAL_LOST, ERL_TAKEN, NOT_IRL, FVG_NOT_IN_WINDOW, HISTORY_PARTIAL). Strict: a new H4 swing that moves the interval can revoke an in-progress M15 sequence. A lenient alternative (judge IRL membership only at the touch) is NOT implemented.
- OD2 While a record is open, later touches (same or other FVG) change nothing and valid_from stays at the first recorded touch (T003 analogy, not a client statement).
- OD3 Re-touch after a loss. Two explicit opt-ins: AFTER_LOSS (any valid IRL candidate, including one recorded before; follows T002 "no re-use limit") and FIRST_ONLY (an FVG id can be recorded at most once per scan). The client has not said whether a zone may be used again.
- OD4 Touch selection with several candidates: T002 nearest-first, reference price = close of the last bar closed before the touching candle (T002's historical selection price convention). A candidate whose far edge is closed through on the touching candle is skipped.
- OD5 Sliding analysis window (default 300 closed H4 bars, T002 lookback convention) and a bounded warm-up scan before the replay start (default 120 closes). A record whose touch lies before the warm-up is not seen; partial windows never record. Bounded coverage, not a history-convergence guarantee.
- OD6 No arbitrary expiry. A record can stay open arbitrarily long; the M15 observer then keeps its own epoch.
T001-T003 findings (reported, not changed): T002 FVG states are computed over the whole analysed prefix, so reusing them per prefix window (as here) is consistent; T002 H4SelectIrl never offers a zone that lies on the far side of the selection price (SELL: below it, BUY: above it), so such a zone cannot be recorded either. T002 can disagree with T003 bias; the disagreement is flagged and not resolved.

### Implementation
src/include/H4TouchContext.mqh (pure, mirrors tests/t004_ordinary_reference.py): M4OrdinaryScan, M4OrdSurvival, M4DirectionAgreement. EA XauUsdM15Observer v1.02: ENUM_M4_SOURCE gains M4_T002_TOUCH_AFTER_LOSS_PROPOSAL and M4_T002_TOUCH_FIRST_ONLY_PROPOSAL (both PROPOSAL, default stays UNSELECTED), input InpOrdinaryWarmBars. Source ids T002_H4_TOUCH_PROPOSAL versus T003_PROTOTYPE; setup ids T002TOUCH-<stamp>-<fvg>. One source per run; the other is shown (T003 view at touch and now, agreement label) but never prioritised. The v1.01 restart fix (M4ResetReplay resets state AND built/cut; OnInit and Clear reset everything incl. the new fields) is preserved.

### Acceptance and evidence
tests/test_t004_ordinary.py (27 tests) and src/tests/T004_OrdinaryTest.mq5 (mirror, not compiled or run): activation only at the touching close; FVG confirmed by the touching candle unusable, the candle opening at the confirmation usable; wick/close-through/equality; ERL taken before the touch; revocation (FVG invalid with replacement at the same close, ERL taken, trend change); re-touch policies; prefix determinism for every cut; M15 bar ending at the close excluded (with a negative control), the one opening then usable; H4 revocation before the M15 return at the same close; replacement clears progress; later H4 updates beyond as-of ignored; source distinction and disagreement flag; default-unselected gate; restart regression (existing test). tools/t004-static-checks.sh. See reports/T004-verification.md for what was executed here versus relayed.
