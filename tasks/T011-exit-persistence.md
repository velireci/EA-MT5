# T011 persistence and restart recovery of the 2R partial-close state

Status: pure codec + thin file layer + tests written. Python tested here; MetaEditor compile, the MT5 pure test and the MT5 sandbox file test are UNVERIFIED
(Codex compiles, the owner runs `T011_PersistTest` and `T011_PersistFileTest`). No order API, no retry, no EA wiring, strategy policies unchanged.
T011 stays PARTLY OPEN: the executor that sends the request and records the order tickets is still not built.

## Goal
A restart must not produce a second 80% partial-close request. The activation / reconciliation contract (`SEaState`, `EA_OnQuote`, `EA_OnReport`,
`ER_Reconcile`) is unchanged; this layer only stores and restores that state.

## Dependency report (before expanding scope)
No verified module needed a change. `SEaState` already holds every field a restore needs (status, bound, position, direction, level, initial volume, volume
step, request id, request steps, close volume, initial steps, executed steps, confirmations, duplicates, reason), so the request plan, the phase and the
"confirmation counted once" fact are all in it. What `SEaState` does NOT hold, and the new record therefore adds: the identity (server, login, symbol, position),
a send phase (NONE / INTENT / MAPPED), the executor's order tickets and their completeness flag, and a generation counter. The adapter's `SXaMap` is rebuilt from
the record by the future executor; `XA_MAX_ORDERS` (8) is mirrored by `ESC_MAX_ORDERS` and checked statically. Untouched: ExitSplit, ExitActivation, ExitReconciliation,
ExitSnapshotAdapter, DailyBridge, the preview.

## Design
* `ExitStateCodec.mqh` (pure): `ESC_Encode` / `ESC_Decode` / `ESC_Validate` / `ESC_Restore` / `ESC_Crc32`. Mirror: `tests/t011_persist_reference.py`.
* `ExitStateFile.mqh` (the only file code): `ESF_Save`, `ESF_Load`, `ESF_InitFresh`, `ESF_FileName`, raw read / write. Mirror (with injected faults): `FileStore`.
* Format: text, `VELO_EXIT_STATE`, `VERSION=1`, fixed field order, `END`, `CRC=<CRC-32 hex>`; strings escaped; doubles with 12 decimals only when they round-trip exactly
  (otherwise the encode is refused - the activation compares level / volume with `==`, so the executor must pass values normalised to the symbol); identifiers at most 18 digits.
* Validation (encode and decode): identity, enum ranges, every cross-field relation per status (request id = `X2R80-<position>`, 80% steps of a multiple-of-5 plan, volumes = steps x step,
  PENDING has no execution or confirmation, DONE has exactly one confirmation and the requested steps, IDLE has no request data, a request needs a persisted send intent, MAPPED needs an order ticket).
* Restore verdicts: `USABLE_IDLE`, `USABLE_REQUEST` (state as stored, `reconcile_required`, never a new request), `USABLE_BLOCKED`, `RECOVERY_REQUIRED` (missing, corrupt, truncated, other version,
  other identity, leftover temp file, invalid combination, uncertain send). An unusable restore returns a BLOCKED state (an uncertain send returns NEEDS_RECONCILIATION), so `EA_OnQuote` cannot
  produce a request; no map is invented; there is no retry.
* The file is never proof of execution: after restoring a request the next step is reconciliation (adapter snapshot + `ER_Reconcile`). Confirmations are restored as stored and are not incremented.

## Protocol the future executor MUST follow (persist before send)
1. At position registration: `ESF_InitFresh` (IDLE, generation 1). A missing file later is RECOVERY_REQUIRED, never "start over".
2. `EA_OnQuote` returns the request -> build the record (state PENDING, send phase INTENT, generation + 1) -> `ESF_Save` MUST return true -> only then send the order. If the save fails, do not send.
3. After the order is accepted: record the order ticket(s) (send phase MAPPED, same state) and save. A crash between 2 and 3 restores as an uncertain send: RECOVERY_REQUIRED, reconciliation without a map is UNKNOWN, an owner decides.
4. Every state change (`EA_OnReport`, `ER_Reconcile`) is saved before it is acted on. A stored IDLE proves nothing about what was sent later unless step 2 was followed.

## Real limits of the guarantee
* Not atomic with the broker: a request can reach the broker and the process die before step 3. That is detected as an uncertain send only if step 2 was persisted.
* Not guaranteed atomic on the file system: the temp file + read-back + `FileMove` reduces, but does not remove, the window; a leftover temp file is treated as RECOVERY_REQUIRED and never promoted automatically.
* A file restored from an older backup is a valid older generation and cannot be detected.
* No clock, no lock between two terminals using the same folder, no encryption; the checksum detects damage and accidental edits, not malicious ones.
* `FileMove`, flush semantics and the `MQL5/Files` sandbox behaviour are the terminal's; they are checked only by running `T011_PersistFileTest` (not run).

## Tests
* Python `tests/test_t011_persist.py`: round trip of real activation states, every truncation and every single-character change rejected, fresh-CRC field edits, unrepresentable doubles,
  45 scenario rows (version, identity, impossible combinations, uncertain send), restart with a pending request, confirmation preserved over repeated restore / save / reconcile, the file protocol with
  injected faults, 17 mutants, and equality of the MQL5 fixture block with the generator.
* MQL5 `src/tests/T011_PersistTest.mq5` (pure, same rows + real `EA_OnQuote` / `EA_OnReport` / `ER_Reconcile` flows) and `src/tests/T011_PersistFileTest.mq5` (sandbox files named `VELO_T011_PERSIST_SELFTEST_*`, deleted before and after).
* `tools/t011-persist-static-checks.sh`.

## Update (base 129a267): format VERSION 2 and the authorised plan
The record now carries the authorised plan block (`PLAN_SET`, `PLAN_TP`, `PLAN_VOL_MIN`, `PLAN_VOL_STEP`, `PLAN_VOL_MAX`) next to the bound state's direction / level / initial volume; see docs/T011-executor-contract.md section 10. VERSION 1 records are rejected (UNSUPPORTED_VERSION), never migrated.
