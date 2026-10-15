# T013 - entry executor (pending LIMIT order), fake transport only

Status 2026-10-15: IMPLEMENTED in the sandbox on top of 6026989 (owner-approved as one block). Compile and MT5 run UNVERIFIED (Codex compiles, the owner runs `EntryExecutorTest` in MT5). The real transport exists but is never executed. T011/T012 frozen and untouched.

## What it is and what it is not
- Places AT MOST ONE pending LIMIT order per signal from an explicit T007 plan (`STpPlan`) and an explicit permit; links the result to the order it created; reconciles without ever sending again; cancels only an order proven to be the EA's.
- It does NOT choose signal, direction, FVG, entry, SL, TP or any policy, copies no TradePlanning logic (no `TP_BuildPlan` / `TP_CheckPermit` / `TG_Compute` call), reads no H4/M15 fact, and is not the demo opener. RETURN_OBSERVED is not an input.
- DISABLED by default; every mandatory input is UNSET = BLOCK (`ea_magic`, `symbol`, `filling`, `expiry_mode` (+ seconds), `permit_max_age`, `quote_max_age`). A real transport additionally needs the authorisation phrase and a demo account.

## Files
`src/include/EntryTransport.mqh` (structures, abstract `CEnTransport` and `CEnStore`), `EntryTransportFake.mqh` (tests), `EntryTransportReal.mqh` (the only OrderSend; compiled by `src/tests/EntryExecutorRealCompile.mq5`, never executed), `EntryExecutor.mqh` (codec + `EN_Place` / `EN_Reconcile` / `EN_Cancel`), `src/tests/EntryExecutorTest.mq5`, Python mirror `tests/entry_reference.py`, `tests/test_entry_executor.py`, `tools/entry-static-checks.sh`.

## Interfaces
- Plan: `STpPlan` must be a COMPLETE OK plan with ids, direction +-1, positive E/S/TP/volume and consistent geometry.
- Permit: `SEnPermit` built by `EN_PermitFrom(plan, STpPermit, issued)` right after the permit decision. It carries a canonical digest of exactly the order fields (signal, setup, direction, E, S, TP, volume). A missing, not-allowing, stale (older than `permit_max_age`), future-dated or other-plan permit is refused BEFORE any lock, read or file.
- Cancel: the `STpCancel` of `TP_CancelDecision`, with `status == TP_CANCEL_REQUEST` and `pending_signal_id == signal`.

## Placement sequence (zero sends until the send call)
config -> latch / one call per runtime -> plan -> server time -> permit -> account (real gate, hedging) -> LOCK per (login, signal) -> existing record of ANY state blocks -> symbol, quote freshness, grid, volume rules, side of the market -> complete order list (no identical pending, snapshot of existing tickets) -> INTENT saved and read back -> read-only pre-check -> ONE send -> classify -> save the outcome -> link proof.
Any uncertainty BEFORE the send gives zero sends. After the send call: definite reject (a listed retcode and no order) = REJECTED, one attempt; PLACED/DONE with an order ticket = candidate; ANYTHING else (no answer, unknown retcode, false without result) = one recorded attempt + RECOVERY_REQUIRED, latched, never retried. This is NOT "zero sends".
Link proof: the ticket of the response + the order read back with the WHOLE tuple (symbol, type, price, SL, TP, volume, magic, expiry) + the ticket was not in the pre-send snapshot. A comment, magic or volume alone never links an order. An unproven link is RECOVERY_REQUIRED, never PLACED.

## States (record `VELO_T013_ENTRY_<login>_<crc32(signal)>.state`, CRC-protected, generation counter, never deleted by the module)
INTENT, PRECHECK_REFUSED (terminal, zero sends), REJECTED (terminal), PLACED (linked, pending), FILLED (position id from the order), CANCEL_UNCERTAIN, CANCELLED, EXPIRED, RECOVERY_REQUIRED, BLOCKED (ambiguous / modified / identity changed / damaged). One signal = one record = at most one send, forever; a new attempt needs a new signal id.
Reconcile (never sends, never cancels): INTENT or RECOVERY without a proven ticket scans the order list: exactly one order with the whole tuple, not in the snapshot and not older than the intent is linked; none keeps RECOVERY_REQUIRED; more than one is BLOCKED (none chosen). A linked order is read back: ACTIVE stays (a modified one is BLOCKED and not touched), FILLED needs a position id, CANCELED / EXPIRED end the record, missing is RECOVERY_REQUIRED.
Cancel: needs the decision for this signal, a PLACED linked record, and the order read back as ACTIVE with the stored tuple and the EA magic; the intent (CANCEL_UNCERTAIN) is saved BEFORE the call; success is confirmed by reading the order; anything else stays CANCEL_UNCERTAIN and is resolved by reconcile; a second cancel needs reconcile first and a new runtime.

## Tests (fake only)
Python: 56 tests (BUY/SELL, unset inputs, plan and permit binding, terminal reads, lock, intent failures, pre-check, duplicates, reject, uncertain answers, unproven link incl. a response ticket that was in the snapshot, recovery by tuple, ambiguity, reconcile states, cancel proof and uncertainty, codec, digest, 31 mutants). MQL5 `EntryExecutorTest`: the same 20 scenarios (names pinned equal by a Python test). Static: `tools/entry-static-checks.sh` (one send / one cancel call site, step order, reconcile without send/cancel, no T011 executor/demo module, no TradePlanning logic, protected modules identical to 6026989, 7 negative controls).

## Limits / UNVERIFIED
OrderSend / OrderCheck of pending orders, order history fields (`ORDER_POSITION_ID`, states), retcode semantics and the file/lock layer are untested against a terminal; the lock protects one terminal; the CRC detects accidental damage only; `EN_TIME_TOL` (120 s) is a technical tolerance, not a strategy value; expiry, re-entry and cooldown policies are open client decisions (inputs, UNSET = BLOCK); the wiring to the signal chain, the live permit snapshot and the automatic registration of the T011 exit manager after a fill are NOT part of this block.
