# T004 - H4 to M15 confirmation foundation

Status: FIRST BOUNDED ROUND IMPLEMENTED; MT5 execution pending. Base 6676a01; branch codex/t004-m15-confirmation. Owner authorised Codex as sole writer on 2026-10-14 while Claude is paused. No changes to T001-T003 source or existing tests/tools. No merge or trading.

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
