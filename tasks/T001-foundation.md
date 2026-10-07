# T001 — MT5 foundation

Status: READY. Owner: Claude Code implementing agent. Review: Codex after implementation.

## Objective
Build a minimal MQL5 EA foundation that reads the intended symbol and H1/H4/M15 data, reports readiness and compiles when MetaEditor is available. No strategy decisions or order execution in this task.

## Inputs
Read AGENTS.md, docs/STATE.md and relevant parts of docs/STRATEGY_SPEC.md. Consult original evidence only if needed. Do not re-review all images for this infrastructure task.

## Deliverables
- Source under src/, with a clearly named main .mq5 file and only useful helper modules.
- OnInit, OnDeinit and OnTick; configurable magic number for later stages.
- Symbol specification inspection; H1/H4/M15 OHLC access and new-bar detection.
- Explicit separation of current forming bar and completed bars; history-readiness checks.
- Concise logs when status changes and a simple chart status display.
- No OrderSend, trading CTrade calls or any order/position modification.
- README instructions for installation, compilation and inspecting logs in MT5.
- Focused verification record in reports/T001-verification.md and updated docs/STATE.md.

## Completion evidence
1. Main EA compiles without errors; record warnings and resolution. If compiler unavailable, implementation may be handed off but compilation remains UNVERIFIED.
2. On a supported MT5 chart, readiness is truthful while history loads; no uninitialized/out-of-range data used.
3. H1/H4/M15 new-bar events are reported once per timeframe and current/closed bars are identified correctly.
4. Restart/reload initializes cleanly and does not generate log spam.
5. No order/position is sent, modified or closed.

Do not mark runtime cases passed without observing them. Give the owner precise checks if you cannot run MT5.

## Follow-up
After implementation, hand the changed files and evidence to Codex. Q01-Q04 are needed for the following visual strategy stage, not for completing this foundation.
