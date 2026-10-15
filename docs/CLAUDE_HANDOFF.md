# Claude handoff — integration delivery

## Latest resume point and owner direction
Implementation: c009dbfd2c4be216d9067cffc46dc67f72e4d405, branch codex/t004-m15-confirmation, PR #4. T018 owner-relayed MT5 on 2026-10-15 20:57:51.401, XAUUSD.fx M15: ExposureReaderTest 53 passed / 0 failed. Codex: two compiles 0/0, 115 targeted Python tests pass; exposure static checks pass with Git-base sections skipped. T018 test block is verified; real ACCOUNT_READ observation is not yet done. No new technical implementation started after this result.

The owner explicitly asks for faster delivery and fewer fragmented rounds. Continue building the existing EA with coupled integration work in ONE package: lifecycle/restart recovery and the entry-to-management connection, reusing the existing exposure reader and modules where their contracts allow. First inspect existing dependencies, then implement the technical work that does not require strategic decisions. Keep real transport disabled and preserve the stored-SL/ownership contracts; any change to those requires explicit owner agreement. Do not silently authorise trades, select UNSET strategy policies, fabricate broker evidence, or map FAKE tickets to real positions.

Write and run focused regressions during implementation, fix all findings in the same delivery, compile affected programs, and provide ONE consolidated owner MT5 round. Reuse existing files; add a file only when implementation or verification needs it. Update existing STATE/checklist/progress together at the end. Gather genuinely blocking strategic questions in ONE list instead of interrupting for each. Do not run broad unrelated suites or create repeated diagnostic packages. The target is the integrated EA, not completing an arbitrary count of T-numbers.

## Earlier verified base (historical)
Branch: codex/t004-m15-confirmation, PR #4, remote ea-mt5. Implementation HEAD before this documentation handoff: e2d20db03e032fba773ca40add7cec751817768d. This handoff commit changes documentation only.

The owner asked to return to Claude to continue building the EA. Continue from STATE and the integration plan; do not repeat the completed T011 diagnostic cycle without a concrete dependency or regression.

## Verified blocks
- fe53c06: corrected T016 market/quote recovery baseline, full context comparison, and broker-probed sizing. Owner MT5 2026-10-15: EntryOrchestratorTest 97/0 at 19:05:58; SetupPlanBridgeTest 77/0 at 19:06:09, XAUUSD.fx M15.
- e2d20db: T017 persistent per-signal FAKE records. CEnRealStore extracted unchanged into EntryStateFile.mqh; CEnFakeFileStore isolates FAKE filenames and locks and guards paths/lock ownership; orchestrator v1.01 still uses fixed fake transport.
- Codex: 137 targeted Python tests, five MetaEditor compilations each 0 errors / 0 warnings, new static checker with nine negative controls and four entry-chain static scripts passed. Git-base sections were skipped in the local source export, not verified there. Normalized old store/real transport bodies matched 761bd8e; static hashes protect them. Independent review found no functional issue.
- Owner MT5: 2026.10.15 20:38:57.500 EntryPersistenceTest-e2d20db (XAUUSD.fx,M15): T017 ENTRY PERSISTENCE TEST finished: 99 passed, 0 failed. This is relayed owner evidence, not a Codex MT5 execution.

## Exact boundary
Only executor records persist. Baseline, halt flag and fake order book remain in memory. Do not reconstruct fake orders as broker facts or claim full orchestrator recovery, real pending execution, or complete EA readiness. No trade or merge was made. No next implementation block was started after T017.

## Continue building
Read docs/STATE.md, docs/EA_INTEGRATION_PLAN.md, docs/T016-entry-orchestrator.md and docs/T017-entry-persistence-design.md. Select the next bounded technical integration block toward the full EA. Keep unresolved strategic choices UNSET=BLOCK; do not invent entry/SL/target, risk-cost, daily classification, or exit policies. Real transport activation/demo trading remains a separate owner decision. T011 automatic management and live exposure accounting remain unconnected.

Avoid broad unrelated suites and repeated diagnostic packages. Use focused regressions, compile affected MQL5 files, document actual evidence and give the owner only the MT5 runs needed for the changed block.
