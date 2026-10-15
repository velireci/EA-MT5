# T016 Entry orchestrator EA (FAKE execution only)

Status: corrected after cf9d92a. Codex compiled the EA and four entry-chain tests with 0 errors / 0 warnings each. Owner-relayed revised MT5 tests passed: EntryOrchestratorTest 97/0 and SetupPlanBridgeTest 77/0 on fe53c06 (2026-10-15). FAKE execution only; not live-ready.

## What it is
One EA, `src/XauUsdEntryOrchestrator.mq5`, that wires the EXISTING flow end to end:
closed H4/M15 observer state (T004) -> `SPB_Build` (T014) -> broker probe + `EG_Submit` (T015: `TP_CheckPermit`, `PB_CheckLoss`, mandatory T012 daily result) -> `EN_Place` (T013) over a FAKE transport.
It is not a diagnostic panel. It draws nothing; it logs one status line and sets the chart comment.

## Fixed in this delivery
- The transport is the in-memory fake (`CEoTerminalFake : CEnFakeTransport`). T017 replaces the memory store with CEnFakeFileStore in a fixed isolated namespace; FAKE per-signal records now survive recreation. `EntryTransportReal.mqh` is not included and no input selects a transport (static check O3).
- Every virtual request is logged and returned with `EO_FAKE_LABEL` ("FAKE EXECUTION: a virtual request, nothing is sent to the terminal").
- Read-only market/account use: closed bars, symbol / quote / account properties, `OrderCalcProfit`, calendar, deal history, `DBS_Load` (LOAD only: no CAPTURE, no T011 file). T017 writes only isolated FAKE entry records.
- Chart symbol only (`_Symbol`, so `XAUUSD.fx` works); the Strategy Tester is refused.

## Layers
| Part | File | Tested by |
|---|---|---|
| Decision core `COrchestrator::Step` (baseline, two-pass plan, checks, executor, halt) | `src/include/EntryOrchestrator.mqh` | `src/tests/EntryOrchestratorTest.mq5`, `tests/test_eo.py` (+ mirror `tests/eo_reference.py`) |
| Feed replay glue + real read-only market | `src/include/EntryOrchestratorFeed.mqh` | compile only |
| EA, inputs, fake transport reads | `src/XauUsdEntryOrchestrator.mq5` | compile only |

## Rules implemented
- **Baseline.** The first successful build after the start, after any data defect, after the context was lost or CHANGED (all fields compared with `M4ContextEqual`, including bounds and validity times) sets `baseline = max(baseline, cut)`. A candidate confirmed at or before the baseline is historical (`live_after`), never a signal. The baseline never moves backwards. Replay, restart, outage and recovery cannot revive an old signal.
- **Order.** H4 updates are applied before M15 at the same boundary by the existing `M4ReplayTimeline`; only closed, confirmed data is used.
- **Geometry then sizing.** `SPB_Geometry` shares candidate validation with `SPB_Build` and calls the existing `TG_Compute`, without sizing a provisional plan. `OrderCalcProfit` over the minimum volume gives the EFFECTIVE tick (`PB_ProbeTickValue`); only then does one `SPB_Build` size the final plan. Zero, tiny or huge reported tick values cannot prevent the probe. A failed probe blocks (no property fallback). The final volume is checked again with `OrderCalcProfit` (`PB_CheckLoss` in the gate).
- **Evidence binding.** Snapshot, loss check and daily result carry the plan digest and one shared instant; the permit deadline is the oldest evidence + `InpGateMaxAgeSeconds`.
- **UNSET blocks.** Risk budget, lot cap, tolerance, quote age, selections, limits, filling, expiry, session / news / spread / daily sources default to UNSET/-1/false and block. A missing value is never zero or CLEAR.
- **Exposure and counters** (`InpOpenPositions`, `InpTradesToday`, `InpExistingRisk`, limits) are explicit inputs; nothing is accounted by this EA. Unknown = BLOCK.
- **Halt.** After `RECOVERY`, `BLOCKED` or `CANCEL_UNCERTAIN` the layer halts until restart + reconciliation. Handled signal ids are remembered; a fresh executor runtime is used per signal.
- **Retry.** A gate block does not consume the signal; the next closed-bar build retries it while it is still the sole WAIT_RETURN candidate and not historical.

## Dependencies reported (NOT changed; need a decision before expansion)
1. The observer's `Build`/`CopyClosed`/`Snapshot` glue lives inside `XauUsdM15Observer.mq5` (an EA). It was COPIED into `EntryOrchestratorFeed.mqh`; it should be extracted to a shared header and the observer switched to it (changes a protected file).
2. `ReadUsdCalendar` and the preview's daily/balance glue live inside `XauUsdTradePreview.mq5`; copied into the feed header (`EO_ReadUsdCalendar`, `CEoRealMarket::Daily`). Same extraction recommendation.
3. `M4TimelineInfo` keeps the broken level's price but not its `known` time; the feed re-derives the broken level with `M4SelectSwingProposal` at the BOS bar and `SPB_Build` verifies id/price/time. A timeline field would be cleaner.
4. Resolved by T017: file storage moved to EntryStateFile.mqh; the EA uses isolated CEnFakeFileStore without importing real transport. Only executor records persist; baseline/halt/fake orders remain in memory.
5. Resolved: `SPB_Geometry` prepares geometry without sizing; the original `SPB_Build` API remains compatible. One `EN_Place` per `SEnRuntime` forces a fresh runtime per signal and an orchestrator-level halt.
6. T011 management is not connected; exposure/counters are not derived from the account.

## Evidence
- Relayed (not my runs) for e8968bd, 15.10.2026: Codex two compiles 0 errors / 0 warnings and 82 Python tests; owner MT5 `EntryGateTest` 134 passed / 0 failed and `EntryExecutorTest` 170 / 0.
- Codex: 128 Python tests passed across test_eo, test_spb, test_entry_gate, test_entry_executor. New regressions failed before implementation; BUY and SELL are covered.
- Codex MetaEditor: EntryOrchestratorTest, XauUsdEntryOrchestrator, SetupPlanBridgeTest, EntryGateTest, EntryExecutorTest: each 0 errors / 0 warnings.
- Orchestrator/bridge static scripts passed, including 17 and 6 negative controls. Git-baseline sections were SKIPPED because the local source export has no Git objects.
- Market/quote failures mark the baseline for recovery. Full context comparison replaces IDs alone. Daily offset is checked within +/-50400 and on a 900-second grid before narrowing; 99999 and overflow-shaped values are rejected without a zero-offset fallback.
- Independent review of the correction found no actionable issues.
- Owner-relayed MT5 on fe53c06, XAUUSD.fx M15: EntryOrchestratorTest 97/0 at 19:05:58 and SetupPlanBridgeTest 77/0 at 19:06:09. These are owner runs, not Codex runs. No EA was attached and no trade was made by Codex.

## Next action
Revised MT5 tests have passed per the owner logs. T017 is implemented; owner-relayed MT5 EntryPersistenceTest on e2d20db passed 99/0 (see docs/T017-entry-persistence-design.md). The EA remains FAKE only. No real entry transport or T011 management integration was added. T017 adds isolated persistence of FAKE executor records only.

## T019 lifecycle (EA v1.04)
`src/include/EntryLifecycle.mqh` (+ Python mirror `tests/lifecycle_reference.py`, tests `tests/test_lifecycle.py`, MQL5 `src/tests/EntryLifecycleTest.mq5`, `tools/lifecycle-static-checks.sh`) closes the gap after the placement, reusing the executor (`EN_Reconcile`, `EN_Cancel`) and `TP_CancelDecision`:
- **Index + halt.** One CRC-protected file `VELO_T013_ENTRY_INDEX_<login>.state` (through the same fake file store) lists the signal ids that need attention and holds the halt flag. The id is indexed (saved and READ BACK) BEFORE the executor can create an intent or send: the gate calls the optional pre-send hook (`CEgPreSend`, implemented by `CLcGuard`) only after it allowed and before `EN_Place`. A failed save / read-back, a full index (32), a damaged index, a halted layer or a missing lock = `PRE_SEND_RESERVATION_FAILED`: zero sends, no intent, the signal is NOT consumed (a gate block never reserves). A reservation the executor refused before the intent is released again; a signal with a record stays indexed. A crash between the reservation and the intent leaves an id without a record, which the next start treats as unresolved and halts on. A damaged or unreadable file halts and is NEVER repaired or overwritten - at the start AND during the run: the EXISTING index is validated (readable, CRC, login) before every update (Reserve / Register / Halt / Settled / tick persist) and before every lifecycle action (a tick reconciles and cancels nothing on an unusable index); no file = the initial creation is allowed. `LC_Save` is the only writer; there is no repair, retry, deletion or migration. The lock stays owned after such a failure until the normal release.
- **Startup.** Every indexed signal is reconciled (never a send). An order that is provably active stays open; ended orders close their entry; anything unprovable (recovery, blocked, cancel-uncertain, missing/unusable record) halts, and the halt survives restarts. Under the FAKE transport the order book is empty after a restart, so a placed FAKE record is not provable and halts - nothing is turned into a broker fact. `InpAcknowledgeLifecycleHalt=true` at start is the owner's explicit acknowledgement: it clears the halt and drops the unresolved ids (their records stay, so the signals stay consumed).
- **Tick (every timer).** Reconcile again. A fill is recorded and reported `FILLED_UNMANAGED` (no T011 registration). Due events (session CLOSED, news BLOCKED, daily `cancel_pending_due`; UNKNOWN never asserts one) cancel an open pending order only for events enabled by `InpCancelOnSessionEnd` / `InpCancelOnNewsBlock` / `InpCancelOnDailyLimit` (all off). One cancel per fresh runtime; an unconfirmed cancel halts and is never retried. The filters are read at most every 10 s and only while an event is enabled and a signal is open.
- The orchestrator's executor halts (`HALTED after ...`) are persisted; other halts (a full handled list) are cured by the restart itself. The baseline is rebuilt at every start.
- **Exclusive ownership.** Before anything else the start takes `VELO_T013_LOCK_INDEX_<login>` through the existing store lock (a dedicated lock store, because the file store holds one lock at a time). Without it the instance neither reads nor writes the index and never reconciles, sends or cancels (the layer stays halted). Only the owner releases, and only its own key; a refused instance, a forged key and a second release do nothing; the lock is released in `OnDeinit` and on a failed start. A damaged index or a failed reservation does not release it (the owner does, at the end). Limits: the lock is a temporary terminal global variable, so it protects instances of ONE terminal only; an EA that dies without `OnDeinit` leaves it set until the terminal restarts (the safe direction: the next start is refused).
- Protected modules touched (reported): `EntryGate.mqh` (`CEgPreSend` + one optional parameter of `EG_Submit`; a NULL hook is the old behaviour) and `EntryOrchestrator.mqh` (the parameter is passed through; new status `RESERVATION_FAILED`). The entry protocol is unchanged.
