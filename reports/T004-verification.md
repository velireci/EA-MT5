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

NOT RUN: actual MT5 T004_SelectorTest. No real M15 CSV is available; synthetic paths are not client-chart agreement. More history can reveal an older still-unbroken swing, so the reported lookback is a limit rather than a history-convergence claim.
