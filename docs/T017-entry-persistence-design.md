# T017 proposal: persistent records for FAKE entry execution

Status: owner approved; implemented on base 761bd8e. FAKE transport remains fixed. Codex verification below; owner-relayed MT5 EntryPersistenceTest on e2d20db: 99 passed / 0 failed (2026-10-15 20:38:57.500, XAUUSD.fx M15). No trade or merge.

## Goal
Keep the entry executor's existing per-signal records across EA recreation, without importing real trading code into the FAKE orchestrator. A repeated signal must remain consumed even if the orchestrator baseline is deliberately bypassed in a regression test.

## Options and decision requested
1. Recommended: extract the existing file store, isolate FAKE storage, and wire it into the FAKE orchestrator in one tested block. This directly addresses loss of entry records at restart.
2. Extraction alone: smaller change, but the orchestrator still loses its records. Defer only if the owner wants to stop before any persistent FAKE state.

No strategic input is selected. Real entry execution and automatic T011 registration remain separate work.

## Design
- Move the existing CEnRealStore implementation from EntryTransportReal.mqh to EntryStateFile.mqh. Keep its public class/API and behavior compatible. EntryTransportReal includes the new header; existing consumers continue compiling.
- EntryStateFile includes only the existing store interface, file primitives and lock primitives. Its transitive includes contain no OrderSend, OrderCheck, CTrade or real transport. Do not copy the entry codec or execution state machine.
- Add a small FAKE storage adapter with a fixed VELO_T016_FAKE_ physical filename namespace and a separate lock namespace. Logical executor names remain unchanged. Reject paths, traversal or unsupported names; never access existing T011, T012 or ordinary T013 records. No user input can select real transport or switch the namespace.
- The FAKE adapter delegates to the extracted file store. The orchestrator uses this adapter in place of CEnFakeStore; tests of the decision core may continue using the memory fake.
- EN_Place still creates the intent, verifies its readback, sends once and stores its result. Existing records in every state still prevent a second placement. Errors, corruption, leftover temporary files and failed writes/readbacks must prevent a new send.
- Preserve the existing file-write protocol. Do not claim atomicity with the broker or guaranteed disk atomicity. A failed write does not prove that old bytes remain unchanged. No repair, migration, retry, record pruning or production cleanup is added.
- Preserve the baseline and context rules verified at fe53c06. No H4/M15, geometry, risk, gate, daily or exit-policy rule changes.

## Restart boundary
Only executor records become persistent. The fake broker's order list and the orchestrator's handled list, baseline and halt flag remain in memory. Do not fabricate orders after restart or query the real broker to confirm a virtual ticket. This is durable signal consumption, not full orchestrator-state recovery, proof of real fills or readiness for real transport.

## Verification before implementation completion
Write regressions first and observe the missing-persistence failure.
- BUY and SELL: EN_Place with fake transport and file-backed FAKE store; recreate transport, runtime and store; repeat the same plan and permit; expect DUPLICATE with zero additional sends.
- Existing INTENT, PRECHECK_REFUSED, REJECTED, PLACED, FILLED, CANCEL_UNCERTAIN, CANCELLED, EXPIRED, RECOVERY_REQUIRED and BLOCKED records all remain consumed across recreated stores.
- Corrupt/unreadable records, leftover temporary file, failed intent write/readback and failed lock: zero sends; report the actual failure without assuming disk rollback.
- FAKE and ordinary storage names and locks remain distinct for the same logical key. FAKE operations cannot modify ordinary/T011/T012 records; traversal is refused.
- Static checks: no real transport/trading API reachable from the FAKE EA, one compatible CEnRealStore definition, no transport selector, namespace fixed; negative controls remove each critical boundary and must fail.
- Compile affected entry programs with MetaEditor, each 0 errors / 0 warnings. Run the relevant Python integration regressions.
- Add one MQL5 script covering real terminal sandbox file I/O plus fake execution, using an exclusive self-test prefix. It may remove only its own test files before/after the test; no orders or real positions are used. Owner runs it and relays the final line.

## Outside this block
Real order activation, broker reconciliation of FAKE tickets, recovery of all orchestrator state, cross-terminal locks, real account exposure calculation, T011 automatic registration, strategy choices and unconnected glue refactors.

## Self-review
The store extraction preserves the existing interface. Namespace separation is mandatory before connecting file storage to FAKE execution. Restart claims are limited to per-signal records. All missing strategic policies continue blocking. No production record is deleted or migrated.

## Implementation and verification (Codex)
- Extracted CEnRealStore into src/include/EntryStateFile.mqh. Normalized body comparisons against 761bd8e confirm both the file-store implementation and CEnRealTransport are unchanged. Static hashes pin these bodies.
- CEnFakeFileStore maps valid logical entry names to fixed VELO_T016_FAKE_ physical names. SELFTEST uses VELO_T017_SELFTEST_. Invalid paths, suffixes, non-ASCII names and oversized names fail closed. The adapter rejects nested acquisition and wrong-key release.
- XauUsdEntryOrchestrator v1.01 uses CEnFakeFileStore and still uses only CEoTerminalFake. No real transport is included, selected or called. Market/balance reads remain read-only; only isolated FAKE entry records are written.
- Nine new Python tests use real temporary disk I/O and the existing entry executor. BUY/SELL replay, all ten consumed states, corruption, leftover temporary files, unreadable files, contention, invalid names, namespace separation and injected write/readback failures pass. A separate Python process sees DUPLICATE with zero sends and zero reconstructed virtual orders.
- The first restart regressions failed against the former in-memory store (BUY and SELL both sent again). The implemented store passes.
- 137 targeted Python tests pass across entry_store, eo, spb, entry_gate and entry_executor. This is not a claim that the entire remote project suite was run in the local source export.
- EntryPersistenceTest, XauUsdEntryOrchestrator, EntryExecutorRealCompile, EntryOrchestratorTest and EntryExecutorTest each compile in MetaEditor with 0 errors / 0 warnings.
- New entry-persistence-static-checks.py passes with nine negative controls and traverses 37 reachable source files from the EA and MQL test, finding no trading API or real transport. Existing orchestrator, bridge, executor and gate static scripts pass; their Git-base sections were SKIPPED because the local export lacks Git objects.
- Protected-file pins exclude EntryTransportReal where the compatible extraction is intentional. The gate's stale SetupPlanBridge pin is also removed because that API was deliberately refactored in fe53c06. New exact-body checks protect the extracted store/transport behavior.
- Independent review found no actionable functional issue. The stale EA comment about memory-only records was corrected.

## Owner evidence
Owner-relayed log: 2026.10.15 20:38:57.500, EntryPersistenceTest-e2d20db (XAUUSD.fx,M15): T017 ENTRY PERSISTENCE TEST finished: 99 passed, 0 failed. Codex did not execute this MT5 run. It writes and removes only its exact SELFTEST files and uses fake transport; no real orders or positions are used. This run verifies terminal file/lock behavior. It is not a full MT5 restart of the orchestrator EA, nor complete recovery of baseline/halt/fake-order state.
