# T004 verification - first bounded round

Date: 2026-10-14. Writer: Codex, explicitly authorised by owner while Claude is paused. Parent: 6676a01. Branch: codex/t004-m15-confirmation. Technical proposals, no merge, no trading.

## Implemented
New pure M15 observer, explicit external level interface, T003 context adapter, Python reference and MQL5 synthetic script. No existing source, tests or tools changed. No new visual EA, automatic M15 swing selector or live multi-timeframe orchestration.

## Evidence
- Python unittest: 33 tests passed, 0 failures. Tests use hand-derived BUY/SELL fixtures and exercise real observer behavior, not mocks.
- TDD: initial activation behavior failed before implementation; malformed-revision and observation-clock regressions were separately reproduced as failing assertions before their fixes.
- MetaEditor final compilation: 0 errors, 0 warnings, 2954 ms. Log: reports/T004-MetaEditor.txt. Compilation is not MT5 execution.
- Independent read-only review identified two connected temporal defects: malformed revisions were rejected without clearing stale candidates; then the replay-required branch failed to advance observation time. Both have regression tests in Python/MQL5 and are corrected. The reviewer checked both fixes, independently reran the 33 Python tests and reported no outstanding findings in this bounded review.
- MT5 first-round script at 51884ec: owner supplied `2026.10.14 14:21:21.639 T004_LogicTest-51884ec (XAUUSD,H4) T004 LOGIC TEST finished: 49 passed, 0 failed`. Observed by owner, relayed here; not an execution by Codex. This does not validate the later selector script.
- C++ transliteration: NOT RUN in this environment (no C++ compiler found); not required in place of the real MetaEditor compilation and not substituted with Python.
- Existing T001-T003 source is preserved. Existing suites were not rerun because their source/tests are unchanged; their earlier evidence remains baseline evidence, not a new T004 run.

## Coverage and limits
H4/M15 time boundary; late observation; source/policy default gates; missing/future level; wick/equal/body; BUY/SELL FVG creation, return and invalidation; no self-touch; multiple candidates; context replacement/loss; duplicate/revised/out-of-order/gapped input; prefix determinism; T003 adapter with the real H3SetupContext API in the MQL5 test.

Python tests do not prove MQL5 runtime equivalence. The MQL5 script has hand-written expectations and compiled successfully but awaits the owner running it in MT5. No private CSV was used: the available real CSV contains H4, not M15, and was not relabelled into M15 or published.

Q04 remains open: the actual structural M15 swing and the association/timing of the FVG. The module accepts an explicit proposed active level and an opt-in A-at/after-BOS timing policy. Default gates block. T003/T002 direction disagreement remains unresolved. The observer cannot emit permission to trade.

## Baseline T003 evidence carried forward
6676a01: Codex compiled EA/LogicTest/LayersTest each 0/0; owner ran LogicTest 484/0/5 and LayersTest 105/0. Historical Sept 26 as-of observation: BEAR / SWEEP_WAIT / CONVERGED, protecting level 4371.20, setup SWEEP@202609251200. These are attributed observations, not client validation.

## Second round: isolated experimental swing selector
Added M15SwingProposal.mqh, T004_SelectorTest.mq5 and separate Python reference/tests. Existing M15Confirmation.mqh, H4M15Bridge.mqh and T004_LogicTest.mq5 are unchanged from owner-tested 51884ec. No earlier project code is changed.

The disabled-by-default proposal selects the latest confirmed unbroken side fractal from a bounded contiguous closed-bar prefix. BUY -> high, SELL -> low. Strict body closes consume; wick/equality do not. Reuses H4FindSwings mathematics with period 900, preserving absolute pivot/confirmation times. It does NOT establish the client's structural level or automatically resolve Q04. No integration into a running EA and no entry permission.

Executed by Codex:
- Python: 56 tests passed, 0 failures (33 observer + 23 selector); initial missing-selector assertions failed before implementation.
- MetaEditor T004_SelectorTest: 0 errors, 0 warnings, 2170 ms. Log: reports/T004-Selector-MetaEditor.txt.
- Independent read-only review found no actionable selector defect and independently ran the then-current 54 tests successfully. Two suggested coverage additions (post-gap recovery and asymmetric Left/Right) were added; final 56-test result is Codex's run.
- Literal BUY/SELL full paths: pre-context swing -> post-H4-close BOS candidate -> eligible FVG -> subsequent return. Stale pre-context body-broken levels do not create a fresh BOS. Covered prefix/future exclusion, ambiguity/ties, window identity, latest versus highest, fallback, lookback boundaries, invalid input, gaps and configuration.

Owner MT5 T004_SelectorTest-786568a: 37 passed, 0 failed, log supplied `2026.10.14 14:32:33.054`. Observed by owner and relayed here, not run by Codex. No real M15 CSV is available; synthetic paths are not client-chart agreement. More history can reveal an older still-unbroken swing, so the reported lookback is a limit rather than a history-convergence claim.

## Third round: chronological observer EA (runtime pending)
Added pure M15Timeline.mqh, a separate Python timeline reference/tests, T004_TimelineTest.mq5 and XauUsdM15Observer.mq5. Existing core observer/bridge/selector and earlier tests remain unchanged. Only T003 RECONFIRMED contexts are integrated; ordinary H4 FVG touch contexts are not yet supplied by this EA.

Executed by Codex:
- Python 66 tests passed, 0 failures (33 observer + 23 selector + 10 timeline). Timeline failures were observed before implementation, and the same-M15-cut H4 rebuild case failed before the lifecycle helper fix.
- MetaEditor T004_TimelineTest: 0 errors, 0 warnings, 2475 ms.
- MetaEditor XauUsdM15Observer: 0 errors, 0 warnings, 10538 ms.
- Independent read-only review found missing current-level drawing. Corrected it using a fresh NEXT-bar selection over all copied closed M15 bars (including consumption by the latest bar); no stale pre-bar selection is plotted. Reviewer verified the fix, the rebuild helper and reran all 66 Python tests successfully, with no outstanding concrete finding.
- Scan of the new EA/timeline/test found no trading API, live price or clock-based price input. CopyRates/TimeframeWatcher feed closed bars; GetTickCount is used only for replay duration. ObjectsDeleteAll is limited to velo_t004_.

Temporal behavior: initial context uses the H4 prefix closed by replay start, later snapshots use H4 prefixes at each close. Equal-close H4 updates precede M15, and final H4 updates are flushed even without an M15 bar. Full replay is repeated on new M15/H4 boundaries and after recovery. All events are REPLAY facts, never NEW notifications or entry permission. Initial truncated replay does not claim original M15 setup history.

NOT RUN: actual MT5 TimelineTest, EA attach/display, historical snapshot observation, live timer/data-loading/clear-recovery, object ownership and runtime cost. The 10538 ms above is compilation time, not replay cost. Same-cut unannounced historical revisions require re-attachment or the next live boundary; historical mode is static after a successful copy. No private M15 CSV or client-example matching is claimed. Compile logs accompany the sources.

## Owner observations and chart-period restart fix
Owner supplied TimelineTest-cfa5f00 result: 19 passed, 0 failed (2026.10.14 14:53:42.369). EA historical attach was observed at as-of 2026.10.06 00:00: H4 BEAR / RECONFIRMED / CONVERGED at depth 2000; M15 RETURN_OBSERVED; BOS 4152.00; H4 FVG F202609280000D eligible 2026.09.30 12:00; 512 M15 bars from 09.28 05:00, 8 candidates and 69 facts. The terminal log reports replay duration 3531 ms. These are owner-terminal observations, not a client match or proof of all lifecycle cases.

Actual defect: changing chart period H4 -> M15 at log 14:57:45 called OnInit again, which reset M4 state but retained global successful-build cache and old cut. Historical same-cut polling skipped Build. Screenshot showed WAIT_CONTEXT, no context and 0 facts alongside stale BOS 4152.00/H4 metadata. The terminal log had restart messages without a subsequent REPLAY SUMMARY. No market event or broker-price change caused this mismatch.

EA v1.01 fix: M4ResetReplay resets state/results AND built/cut together; OnInit also clears display metadata, current selection, copied arrays and owned objects before configuring watchers. Clear uses the same reset. OnDeinit logs its reason. Strategy rules are unchanged. A failing Python restart regression was reproduced, then fixed; final Python 67/0. Independent read-only review verified the fix and reran 67/0. Three MQL5 assertions added to TimelineTest; their actual MT5 run and the chart-period switch retest remain pending. The earlier 19/0 does not cover the changed script.
