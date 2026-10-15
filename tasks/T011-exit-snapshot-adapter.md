# T011 part 4 - read-only snapshot adapter for the reconciliation

Branch `codex/t004-m15-confirmation` (PR #4), base `848a456`. Writer: Claude. Relayed (Codex / owner, NOT my runs): owner 2026-10-15 MT5 ActivationTest 1010/0 and ReconcileTest 951/0; Codex compiled both 0/0. Codex reviews and compiles the new files; the owner runs MT5.

Scope: build the `SErSnapshot` that ExitReconciliation judges from MT5 positions, orders, deals and the real volume parameters. READ-ONLY: no order, modification, cancellation or closing, no trade created for a test. Verified modules (ExitSplit, ExitActivation, ExitReconciliation) are NOT changed to hide a data limit.

## How the identities are linked - what is provable and what is not
| Identity | Source | Statement |
|---|---|---|
| our `request_id` (`X2R80-<position id>`) | ExitActivation | exists in NO MT5 field. It is never compared with a broker comment; magic and volume are never accepted as proof. |
| position identifier | `POSITION_IDENTIFIER`, `DEAL_POSITION_ID`, `ORDER_POSITION_ID` | the stable id of a position. The adapter finds the position by IDENTIFIER and never assumes ticket == identifier (the base fixture has ticket 9, identifier 7). `state.position_id` must be that identifier (documented requirement for the future executor). |
| order ticket | `DEAL_ORDER` of a deal | the ticket of the order that produced the deal. |
| deal ticket | `DEAL_TICKET` | identifies an execution; used for de-duplication. |

The only provable chain is: `request_id` --(executor's map)--> order ticket(s) --`DEAL_ORDER`--> exit deal --`DEAL_POSITION_ID`--> position identifier.
**The exact gap:** the part of the executor that records the order ticket(s) returned when it sends the closing order, together with the request id, does not exist yet. Its identity map (`SXaMap`: request id, position identifier, symbol, every order ticket, and its assertion `orders_complete`) is therefore an INPUT of the adapter. Without a map, or with a map without order tickets, the verdict is UNKNOWN and no alternative link (comment, magic, volume, time) is invented. The owner's diagnostic script takes the tickets as typed inputs for the same reason.

## What counts
Only EXIT deals (`DEAL_ENTRY_OUT`) of a mapped order on that position, of the side opposite to the position, are linked executions, de-duplicated by deal ticket (same ticket and content = one; same ticket with different content = UNKNOWN). Entries (`IN`), `INOUT`, `OUT_BY`, exit deals of unmapped orders (manual trades, SL/TP, other requests) are excluded and counted; their effect on the position volume is judged by the reconciliation (a volume drop alone never confirms).

## Verdicts
READY (snapshot built), UNKNOWN (API error, symbol parameters or history unavailable, deal list truncated or over capacity - 64 deals, 16 linked executions - unstable read, no state request, no map or no order ticket, invalid map), BLOCK (account mode other than HEDGING, ambiguous position identifier, symbol or direction mismatch, exit deal on the wrong side, map naming another request or position, an order that executed on another position, an already blocked state). Nothing is truncated silently. The adapter NEVER writes the activation state: the caller applies `ER_Reconcile` on READY and must honour UNKNOWN / BLOCK (no retry, no guess); there is deliberately no setter in the verified modules.

## Hedging / netting
HEDGING: supported (positions are separate; selected by identifier). NETTING, EXCHANGE or any other value: BLOCK - all trades of the symbol share one position there, so our fills cannot be separated from other trades (AGENTS.md: verify netting/hedging before assuming separation).

## `executions_complete`
Set only when all six are proven (otherwise READY with `complete=false` and the missing proofs listed, so the reconciliation can only say PARTIAL / UNKNOWN / NOT_EXECUTED, never CONFIRMED): (1) the executor asserts the order ticket list is complete; (2) every mapped order is in the HISTORY in a final state (FILLED, CANCELED, REJECTED, EXPIRED), none active or missing; (3) per mapped order the linked deals sum to its executed volume (`ORDER_VOLUME_INITIAL - ORDER_VOLUME_CURRENT`) in volume steps; (4) a mapped order that executed belongs to this position; (5) the opening (IN) deal is in the list, so the history reaches back to the open; (6) two consecutive reads are identical (`XA_RawEqual`). The assertion in (1) is the executor's claim and cannot be proven from MT5.
The snapshot's `volume_step` is the REAL broker step read now (not copied from the state), so a changed step reaches the reconciliation, which blocks it. Position volume is the real `POSITION_VOLUME`.

## Layers and files
Pure core `XA_Build` (tested): `src/include/ExitSnapshotAdapter.mqh`, mirrored by `tests/t011_adapter_reference.py`; fixtures `tests/t011_adapter_fixtures.py`; tests `tests/test_t011_adapter.py`, `src/tests/T011_AdapterTest.mq5`. The terminal reads exist only in `XA_ReadRaw` / `XA_ReadAndBuild` (read-only whitelist, checked by `tools/t011-adapter-static-checks.sh`) and in the owner's diagnostic script `src/XauUsdSnapshotDiag.mq5` (reads an EXISTING position; the request is simulated in memory from the typed initial volume).
Limits: terminal API semantics (HistorySelectByPosition, DEAL_ORDER, ORDER_POSITION_ID, ORDER_VOLUME_*, final order states) are from memory of the MQL5 documentation, which could not be opened from the build environment, and were never run against a terminal; deleted or not-yet-downloaded history cannot be detected beyond the six proofs; no restart guarantee, no persistence, no EA wiring, no retry.
