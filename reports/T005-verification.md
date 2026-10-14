# T005 verification: pure trade-geometry helper

Date: 2026-10-14. Branch codex/t004-m15-confirmation, base 5447ef3 (changes uncommitted when written). Evidence is separated by source. Nothing here validates the strategy, an entry price, a stop or profitability; the helper is not wired to any EA or order.

## Executed in this session (Claude, Linux, Python 3.13; no MetaEditor, no MT5)
| Check | Command | Result |
|---|---|---|
| T005 geometry unit tests | `cd tests && python3 -m unittest test_t005_geometry` | 20 tests OK |
| T004 tests unchanged | `cd tests && python3 -m unittest test_t004 test_t004_selector test_t004_timeline test_t004_ordinary` | 94 tests OK |
| Both together | same command with test_t005_geometry added | 114 tests OK |
| T002 / T003 reference | `python3 tests/t002_reference_test.py`, `python3 tests/t003_reference_test.py` | T002 197 passed, 0 failed; T003 476 passed, 0 failed, 5 deferred (deferred are not passes) |
| Static checks | `bash tools/t001-static-checks.sh`, `t002`, `t003`, `t003-visual`, `t004` | t001, t002, t003-visual, t004 ALL PASS. t003: ONE FAIL, CHECK 12 ("a tracked file other than the T003-owned ones differs from HEAD"): it is triggered only by this step's intentional UNCOMMITTED documentation edits (docs/OPEN_QUESTIONS.md, docs/reference/strategy-review.md, tasks/T005-entry-sl-tp-plan.md); the same check's code-path comparison against the base commit PASSES and every other t003 check passes. It should pass again once the parent commits the documents; rerun it after the commit |
| T005 static checks | `bash tools/t005-static-checks.sh` | ALL PASS: no trading API, no quote/tick/series/clock, no volume identifier, contract labels in code, status parity with the reference, balanced syntax, format strings, ASCII, includes resolve, T001-T004 paths identical to 5447ef3, 13 negative controls detected |

What the unit tests contain: 49 hand-computed cases (BUY and SELL computed separately, derivations in tests/t005_geometry_fixtures.py), including target nearer / equal / farther / none, normalization that changes E and S (R and 2R follow the reported prices), exact half ticks, target rounding away, ticks 0.01 / 0.05 / 0.5 / 1.0, zero-risk and wrong-side geometry, target on the wrong side, stops-level boundary, bid/ask present and absent, coincident TP and partial, invalid input, non-finite values, determinism and no mutation, a 4000-sample invariant sweep (|E_out-S_out| = R_geom, level_2R = E_out +/- 2*R_geom, E/S/R/2R/TP on the grid, TP never nearer than 2R), and a BUY/SELL reflection property away from ties.
Mutation-style checks (Python): seven independent defective implementations (2R from the RAW stop, no normalization, target rounded toward the entry, target rounded to nearest, TP shortened to 2R, half tick rounded down, wrong SELL sign) are each caught by the hand table; the raw-stop defect is caught specifically by the rounding cases and is invisible to the non-rounding cases.

## NOT run (UNVERIFIED)
- MetaEditor compilation of src/include/TradeGeometry.mqh and src/tests/T005_GeometryTest.mq5 (MetaEditor is not available here). The MQL5 was written by hand and mirrored from the Python reference; compile errors or warnings are possible.
- Execution of T005_GeometryTest.mq5 in MT5. The Python tests prove the contract of the Python reference; the MQL5 fixture block is only checked for textual equality with the generated Python table.
- Behaviour with real broker symbol parameters (tick size, digits, stops level) of the target account.

## Relayed from owner or Codex
Nothing relayed for T005 yet.

## Conventions needing review (proposals, not client answers)
Half tick rounds up for E and S; target rounds away from the entry; 1e-6 tolerances; digits 0..8; a limit at the market (distance 0) is too close; a normalized target equal to E_out is on the wrong side. Unenforced: the 50 stop-distance limit (unit unconfirmed), freeze level, spread, volume.

## Document correction recorded with this step
tasks/T005-entry-sl-tp-plan.md at 5447ef3 wrongly treated the entry edge and the SL principle as undefined. The client wrote them (pergjigjet.json:187, :189; specifikimi.txt:24, :26). Corrected in tasks/T005-entry-sl-tp-plan.md, docs/OPEN_QUESTIONS.md Q05, docs/reference/strategy-review.md and docs/STATE.md. reports/T004-verification.md needed no change (it says only that the observation fixes no entry price or SL, which is true).
The photo-based reading (SELL entry at the lower FVG edge, BUY at the upper) was relayed by Codex, who viewed the photos; the writers of this change did not.
