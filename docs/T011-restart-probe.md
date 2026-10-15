# T011 restart probe (PREPARE -> restart MT5 -> RESTORE)

Scripts (diagnostic only, no input needed, no order, no position or symbol read): `src/XauUsdT011RestartPrepare.mq5`, `src/XauUsdT011RestartRestore.mq5`,
shared parameters `src/include/T011RestartProbe.mqh`. They use the existing, unchanged modules `ExitStateFile.mqh` / `ExitStateCodec.mqh` / `ExitActivation.mqh`.
Status: written and statically checked; MetaEditor compile and MT5 run UNVERIFIED (Codex compiles, the owner runs it).

## Steps for the owner (demo account)
1. Compile both scripts. Run `XauUsdT011RestartPrepare` on any chart. Expected log: `T011 RESTART PREPARE: OK saved VELO_T011_RESTART_PROBE.state ...`, request `X2R80-777000001`, 40 of 50 steps,
   close volume 0.40, step 0.01, status REQUEST_PENDING, send INTENT, no order map, generation 2. If the file already exists it STOPS and changes nothing.
2. Close MT5 completely and reopen it (log in to the same account).
3. Run `XauUsdT011RestartRestore` (the input dialog shows `InpCleanupProbeFile=false`: just press OK). Expected: all lines PASS, `0 failed`, verdict RECOVERY_REQUIRED with status NEEDS_RECONCILIATION
   (this is the correct restore of a persisted send intent without an order map), `reconcile_required 1`, `new_request_allowed 0`, `order map entries 0`, confirmations 0.
4. Cleanup: run `XauUsdT011RestartRestore` again with `InpCleanupProbeFile=true`. It deletes ONLY `VELO_T011_RESTART_PROBE.state` and `.tmp` and runs nothing else.
Send the Experts log lines starting `T011 RESTART`.

## What it checks after the restart
The saved generation, `request_id`, the position / direction / level / initial volume, the plan (40 of 50 steps, close volume 0.40), the volume step, confirmations 0 and executed steps 0
(nothing added, nothing confirmed), no invented order map, and that three repeated quotes at or above the 2R level produce RECONCILE_REQUIRED and no second request.

## What it does NOT prove
* It proves persistence across a restart of the TERMINAL only. It is not the restart of a trading EA (there is none), not the executor's persist-before-send protocol, not the real
  request -> order map, and not a reconciliation with the broker: the position is synthetic (a declared identifier, never looked up), the record is never compared with a snapshot, and no execution is confirmed.
* The identity is the real account server name and login read through `AccountInfoString(ACCOUNT_SERVER)` / `AccountInfoInteger(ACCOUNT_LOGIN)`; the symbol label is declared (`T011PROBE`).
* The guarantee limits of tasks/T011-exit-persistence.md apply unchanged (not atomic with the broker, not guaranteed atomic on disk).
