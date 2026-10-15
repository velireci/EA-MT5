# T011 restart flow: LOAD -> identity -> snapshot -> ER_Reconcile -> SAVE

Status: written and tested with fixtures (Python here; MQL5 test and diagnostic not compiled or run). No order, no `CTrade`, no retry, no policy change, no new trade.
Files: `src/include/ExitRestartFlow.mqh` (`ERF_Run`), `src/tests/T011_FlowTest.mq5`, `src/XauUsdT011FlowDiag.mq5`, `tests/t011_flow_{reference,fixtures}.py`,
`tests/test_t011_flow.py`, `tools/t011-flow-static-checks.sh`. It composes the unchanged `ExitStateFile` / `ExitStateCodec`, `ExitSnapshotAdapter`, `ExitReconciliation`;
it adds no state machine and copies no validation.

## Flow and gates (each stops the flow)
1. LOAD (`ESF_Load`): an unusable record or another identity (server / login / symbol / position are compared inside the restore) -> `RECOVERY_REQUIRED`
   "LOAD_UNUSABLE: ..."; nothing is read from the terminal and the file is not written.
2. Stored BLOCKED -> `BLOCKED` (no read, no write). Stored IDLE -> `NOTHING_TO_RECONCILE` (never a request).
3. A request-bearing record with no order ticket (an uncertain send, or DONE without a map) -> `RECOVERY_REQUIRED` "NO_MAP" before any read. The map is exactly the stored one.
4. Snapshot (`XA_Build` on fixtures, `XA_ReadAndBuild` live): only `READY` reaches the reconciliation. `UNKNOWN` -> `STILL_OPEN` (reason kept); `BLOCK` -> `BLOCKED` (no reconciliation, no write).
5. `ER_Reconcile` on the restored `SEaState`: DONE only comes from here (CONFIRMED needs `executions_complete`); the file never proves execution; confirmations stay 1.
6. SAVE (`ESF_Save`) with generation + 1 only when the reconciled state differs from the loaded one (compared through the codec text). If the save fails, the result is
   `RECOVERY_REQUIRED`, `saved=false`, and the state handed to the caller is the one that IS on disk, never the unsaved one. A rerun repeats the reconciliation (idempotent).

No path produces a request (`request_produced` is always false; the header does not call `EA_OnQuote` and has no request action). `test_fail_save` exists only for tests.

## Tests
* Python `tests/test_t011_flow.py`: 20 scenario rows (with map / without map / damaged / missing / other identity / stored BLOCKED / stored IDLE / late fill / duplicate deal / incomplete history /
  partial fill / nothing executed / DONE re-proved and DONE without evidence / adapter UNKNOWN, unstable and BLOCK / save failure), sequences (late fill over three runs, save failure then rerun,
  injected file faults), gates that never call the adapter or the reconciliation, 15 mutants, source-level order and single-call-site checks, MQL fixture equality.
* MQL5 `T011_FlowTest.mq5`: the same rows and sequences over the real modules and a sandbox file `VELO_T011_FLOW_SELFTEST_A.state`.
* `XauUsdT011FlowDiag.mq5`: all parameters filled in, no input; a narrated run on a synthetic request (declared position 7, order 501, real account server / login, fixture terminal data,
  own file `VELO_T011_FLOW_DIAG.state`, removed at the end). Expected log lines "T011 FLOW DIAG [1..4]": STILL_OPEN, RECOVERY_REQUIRED (save fails, disk unchanged), DONE saved as generation 4, DONE unchanged.

## Gaps and limits (reported, nothing extended)
* The existing APIs were enough; no verified module changed. Observations: `SEsRestore` does not expose the send phase (the flow derives MAPPED from the stored order tickets, which the validation ties together);
  the adapter's BLOCK is reported but not persisted (a later run re-evaluates it).
* The reconciliation's own contract applies: a stored DONE that cannot be re-proved (a snapshot that is READY but not conclusive) is demoted to NEEDS_RECONCILIATION and saved, with its confirmation count kept.
  That is `ER_Reconcile`'s behaviour; it is flagged here for review, not changed.
* The live terminal read (`in.live`) is UNVERIFIED and is not run by any test or diagnostic; everything else in the snapshot step is exercised through fixtures.
* Not atomic with the broker or guaranteed atomic on disk; a crash between the reconciliation and the save is repaired by the next run. The executor that sends the request and records the order tickets is still not built.
* This is not the restart of a trading EA and not a real reconciliation with the broker.
