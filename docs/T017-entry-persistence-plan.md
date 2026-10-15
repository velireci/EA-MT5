# T017 Entry Persistence Implementation Plan

> For agentic workers: execute inline using executing-plans; approved design is docs/T017-entry-persistence-design.md.

**Goal:** Keep FAKE per-signal executor records across recreated runtimes and stores, without importing real entry transport.

**Architecture:** Extract CEnRealStore unchanged into EntryStateFile.mqh. A fixed-namespace CEnFakeFileStore delegates file I/O and lock operations to it. EntryExecutor and the decision core remain unchanged.

**Tech Stack:** MQL5, existing ESF/EL primitives, Python unittest with temporary directories, MetaEditor.

## Constraints
FAKE only; ordinary/T011/T012 records untouched; no production cleanup or migration; no claim of broker/disk atomicity; restart coverage limited to executor records. Self-test files use VELO_T017_SELFTEST_ exclusively. Original CEnRealStore API remains compatible. Missing policies continue to block.

## Task 1: File storage and namespace boundary
Files: create src/include/EntryStateFile.mqh, tests/entry_store_reference.py, tests/test_entry_store.py; modify src/include/EntryTransportReal.mqh.

- [x] Write restart regressions using existing EntryExecutor reference and temporary disk storage: first placement sends once, recreated transport/runtime/store refuses the same signal with DUPLICATE and sends zero.
- [x] Run before implementation against the previous memory-only store and observe the second send.
- [x] Extract the existing file store verbatim. Add EFS_Name(name,lock,selftest) validating only ASCII alphanumeric/underscore logical names, .state suffix for files, and expected T013 ENTRY/LOCK prefixes. Map to fixed FAKE or SELFTEST physical namespaces; reject traversal and unsupported names.
- [x] CEnFakeFileStore implements CEnStore using that mapping and a private CEnRealStore. Record the acquired logical key so a second acquire or mismatched release cannot drop a held lock.
- [x] Add Python filesystem mirror for the namespace/file protocol, without copying the entry codec or state machine. Run BUY/SELL, all consumed states, corruption, leftover temporary files, lock contention, invalid paths, namespace isolation, and write/readback failures.

## Task 2: Orchestrator wiring and MQL integration test
Files: modify src/XauUsdEntryOrchestrator.mq5; create src/tests/EntryPersistenceTest.mq5 and tools/entry-persistence-static-checks.py; update affected static pins.

- [x] Replace only CEnFakeStore g_store with CEnFakeFileStore g_store and include EntryStateFile.mqh; preserve fixed FAKE transport.
- [x] MQL script uses fake transport plus real file-backed SELFTEST namespace. Create fresh store/transport/runtime for replay. Check BUY/SELL DUPLICATE, all stored states, corrupt file, temporary file, contention, invalid names, namespace separation and injected interface failures. Remove only exact self-test filenames.
- [x] Static traversal of includes rejects reachable trading APIs or real transport, checks compatible extraction and fixed EA wiring. Negative controls inject a real include, memory-only store, namespace alias, missing name guard, and missing held-lock guard.
- [x] Compile EntryPersistenceTest, EntryOrchestratorTest, XauUsdEntryOrchestrator, EntryExecutorTest and EntryExecutorRealCompile, all 0/0.
- [x] Run Python entry pipeline regressions and relevant static scripts; get independent code review and resolve findings.

## Task 3: Delivery
- [x] Record actual verification and the remaining owner MT5 run in STATE, checklist, progress and the T017 document.
- [ ] Commit and update existing branch with expected-head protection; no merge. Export EntryPersistenceTest EX5 for the owner (delivery action after verification).

## Self-review
The extracted store preserves existing behavior. FAKE path mapping rejects traversal and isolates files/locks. The test has separate objects for each restart. No fake ticket is reconciled against the real broker. A failed write never implies rollback. No implementation step selects a strategic policy or enables real transport.
