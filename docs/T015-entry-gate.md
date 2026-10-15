# T015 - entry gate (T014 plan + existing checks + T012 daily result -> entry executor)

Status 2026-10-15: IMPLEMENTED in the sandbox on top of 7833a10 (one integration block; fake transport and fake store only; no real transport). Compile and MT5 run UNVERIFIED (Codex compiles `EntryGateTest.mq5`, the owner runs it in MT5). Not wired to any EA, demo or live data; T011/T012/T013/T014/TradePlanning untouched. RELAYED for T014 at 7833a10 (not my runs): Codex compile 0/0 and 27 Python tests; owner MT5 `SetupPlanBridgeTest` 77/0 (15.10.2026 18:19:29).

## What it does
`EG_Decide(gate config, T014 result, checks, registry, now) -> SEgDecision` and `EG_Submit(...)` (reads the transport clock once, decides, calls `EN_Place` ONLY after an allowing decision). The decision combines, without copying a rule:
1. the T014 plan (`plan_ready` must be true; a not-ready plan never reaches `TP_CheckPermit`),
2. `TP_CheckPermit` (data, session, news, spread, exposure incl. the larger broker loss, position / trade / risk limits, duplicate signals in the caller-owned registry) - never `TP_Authorize`, so nothing is registered by a decision,
3. `PB_CheckLoss` (the existing broker-loss comparison; `PB_PermitRisk` feeds the exposure check as the preview does),
4. the T012 daily result (`SDbResult`): in this path a result that is missing, not evaluated, whose daily check was not called, or that does not allow BLOCKS. The preview's MANUAL exception ("not evaluated = no condition") and `DG_FinalPreview` are not used, and the T007 allow alone never reaches the executor.
Only when EVERY check allows is an executor permit (`SEnPermit`) built by `EN_PermitFrom` FOR THAT PLAN (canonical digest of signal, setup, direction, E, S, TP, volume) and stamped with the decision time. A block builds no permit; the executor is not called: no intent, no lock, no record, no Send, no signal use registered.

## Binding and freshness
The snapshot, the broker-loss result and the daily result each carry the plan digest they were computed for and the instant they were observed. Another plan, an unset or future instant, or an instant older than `max_age` BLOCKS (`SNAPSHOT_*`, `LOSS_CHECK_*`, `DAILY_*` reasons). `max_age <= 0` is UNSET = BLOCK. The executor re-checks the permit (digest and age) and the quote at placement time, so an old decision still cannot place.

## Repetition
The durable guard stays in `EN_Place` (one record per signal, any state): the gate has no state, writes nothing and creates no second state machine. A second submit with the same plan after a restart gives DUPLICATE with no second send; in the same runtime DUPLICATE_CALL.

## Unresolved policies
Unset limits (`POLICY_UNSET:*` from `TP_CheckPermit`), an unset gate age, an unset daily policy (the T012 bridge blocks with its own reasons) all BLOCK. Nothing is defaulted.

## Tests
Python `tests/test_entry_gate.py` (14 tests, 16 mutants; the real T014 bridge builds the plans) and MQL5 `src/tests/EntryGateTest.mq5` (8 scenarios, names pinned equal; 39 separate blocks x BUY / SELL, all allowing checks, T012 not bypassed, permit for another / old plan, repetition without a second send). `tools/entry-gate-static-checks.sh`: one `TP_CheckPermit` / `PB_CheckLoss` / `EN_Place` / `EN_PermitFrom`, no registration, no state / file / clock / real transport, order of the checks, T012 mandatory, permit only after every check, executor only after an allowing decision, protected modules identical to 7833a10, 7 negative controls.

## Open / UNVERIFIED
Compile and MT5 of the new files; the live builders of the snapshot (positions / pending / exposure from the account), of the broker-loss estimate (`OrderCalcProfit`) and of the daily result (`DailyHistory` + balance store with a real CAPTURE) do not exist yet; the real transport and the demo are not part of this block.

## Correction after the Codex review of 9950ab7 (EntryGateTest compile 0/0, 14 Python tests OK; one regression reproduced)
Regression (BUY and SELL): gate `max_age` 5 s, snapshot / loss / daily 4 s old, executor `permit_max_age` 60 s, the fake PreCheck advancing the clock by 10 s gave PLACED with one send although the evidence was 14 s old. Cause: the gate stamped the permit with the NEW decision time, which extended the life of the old evidence, and `EN_Place` only knew the permit age.
Fix (no new module, no new state): `SEnPermit` has `valid_until` (0 = no extra deadline, the old behaviour). The gate sets it to `min(snapshot, loss, daily instant) + max_age`, i.e. never beyond the OLDEST evidence. `EN_PermitRefusal` refuses a permit used after `valid_until` (`PERMIT_EVIDENCE_EXPIRED`); because the executor judges the permit again right before `Send`, evidence that expires during the PreCheck gives ABORTED_BEFORE_SEND with ZERO sends.
Two different refusals, now tested apart: (1) the INITIAL block (gate blocks, or the permit is already past its deadline when it reaches the executor): no lock, no intent, no file, no record; (2) the refusal AFTER the PreCheck: the intent was already saved, so the record becomes PRECHECK_REFUSED (2 writes) and the signal is consumed (a new signal id is needed).
Regressions written first: `EvidenceExpiry` in `tests/test_entry_gate.py` (deadline of the oldest evidence for several age mixes, expiry during the PreCheck, still-valid cases including the exact edge, initial block versus post-PreCheck refusal, old behaviour without a deadline; 3 new gate mutants + an executor mutant) and `Scenario_evidence_expiry_during_precheck` in `src/tests/EntryGateTest.mq5` (names pinned equal). `EntryExecutor.mqh` changed by this correction (two lines in the struct and its init, one check), so the protected lists of the static scripts no longer include it.
