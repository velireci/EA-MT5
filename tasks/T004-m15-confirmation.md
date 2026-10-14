# T004 - H4 to M15 confirmation foundation

Status: FIRST BOUNDED ROUND VERIFIED IN MT5: owner 49 passed, 0 failed at 51884ec. Experimental selector round in progress. Base 6676a01; branch codex/t004-m15-confirmation. Owner authorised Codex as sole writer on 2026-10-14 while Claude is paused. No changes to T001-T003 source or existing tests/tools. No merge or trading.

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
