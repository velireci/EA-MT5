# T005 verification: pure trade-geometry helper

Date: 2026-10-14. Branch codex/t004-m15-confirmation, base 5447ef3 (changes uncommitted when written). Evidence is separated by source. Nothing here validates the strategy, an entry price, a stop or profitability; the helper is not wired to any EA or order.

## Executed in this session (Claude, Linux, Python 3.13; no MetaEditor, no MT5)
| Check | Command | Result |
|---|---|---|
| T005 geometry unit tests | `cd tests && python3 -m unittest test_t005_geometry` | 34 tests OK (after the validation fix) |
| T004 tests unchanged | `cd tests && python3 -m unittest test_t004 test_t004_selector test_t004_timeline test_t004_ordinary` | 94 tests OK |
| Both together | same command with test_t005_geometry added | 128 tests OK |
| T002 / T003 reference | `python3 tests/t002_reference_test.py`, `python3 tests/t003_reference_test.py` | T002 197 passed, 0 failed; T003 476 passed, 0 failed, 5 deferred (deferred are not passes) |
| Static checks | `bash tools/t001-static-checks.sh`, `t002`, `t003`, `t003-visual`, `t004` | t001, t002, t003-visual, t004 ALL PASS. t003: ONE FAIL, CHECK 12 ("a tracked file other than the T003-owned ones differs from HEAD"): it is triggered only by this step's intentional UNCOMMITTED documentation edits (docs/OPEN_QUESTIONS.md, docs/reference/strategy-review.md, tasks/T005-entry-sl-tp-plan.md); the same check's code-path comparison against the base commit PASSES and every other t003 check passes. It should pass again once the parent commits the documents; rerun it after the commit |
| T005 static checks | `bash tools/t005-static-checks.sh` | ALL PASS: no trading API, no quote/tick/series/clock, no volume identifier, contract labels in code, status parity with the reference, balanced syntax, format strings, ASCII, includes resolve, T001-T004 paths identical to 5447ef3, 13 negative controls detected |

What the unit tests contain: 49 hand-computed cases (BUY and SELL computed separately, derivations in tests/t005_geometry_fixtures.py), including target nearer / equal / farther / none, normalization that changes E and S (R and 2R follow the reported prices), exact half ticks, target rounding away, ticks 0.01 / 0.05 / 0.5 / 1.0, zero-risk and wrong-side geometry, target on the wrong side, stops-level boundary, bid/ask present and absent, coincident TP and partial, invalid input, non-finite values, determinism and no mutation, a 4000-sample invariant sweep (|E_out-S_out| = R_geom, level_2R = E_out +/- 2*R_geom, E/S/R/2R/TP on the grid, TP never nearer than 2R), and a BUY/SELL reflection property away from ties.
Mutation-style checks (Python): seven independent defective implementations (2R from the RAW stop, no normalization, target rounded toward the entry, target rounded to nearest, TP shortened to 2R, half tick rounded down, wrong SELL sign) are each caught by the hand table; the raw-stop defect is caught specifically by the rounding cases and is invisible to the non-rounding cases.

## Validation fix (Codex review of 5c3af40; both languages, same rules)
Two defects reproduced by Codex are fixed identically in Python and MQL5: (1) incompatible tick_size/digits (0.001 with digits 2) is now INVALID_INPUT, tag INCOMPATIBLE_TICK_DIGITS: q = tick_size*10^digits must be finite, floor(q+0.5) >= 1, |q-floor(q+0.5)| <= 1e-6 (0.01/0.05/0.25 with 2, 1 with 0, 0.5 with 1 accepted; 0.001 and 0.015 with 2 rejected; `point` stays independent of digits). (2) Non-positive or non-finite results are INVALID_INPUT with tag NONPOSITIVE_PRICE or NUMERIC_OVERFLOW: E_out/S_out right after normalization, then (after ZERO_RISK/SL_WRONG_SIDE) level_2R/R_geom, the normalized target, TP/partial, SL/TP points and the pending gap. Range guard MAX_TICKS = 1e12 (same in both; also applied to bid/ask), far below 2^53. No new status name was added (reuse of INVALID_INPUT with tags); on these failures nothing is reported (computed false, all numeric/tick fields 0). Order is in tasks/T005-entry-sl-tp-plan.md item 8.
Regressions: 14 new table cases (tick/digits x4 + 0.25 ok, SELL 100/160, BUY 0.6/0.4, SELL entry and SELL target rounding to 0, 2R exactly 0 and just positive, huge/tiny-tick, range limit, E_out = inf), validation tests, an on-grid sweep (about 147000 integer-tick prices over 8 tick/digits pairs: NormalizeDouble/round never changes an on-grid price), failure-order tests, and GuardMutationTests (removing the compatibility, E/S positivity, level/target/TP positivity, range or finite guards is detected). The 49 earlier hand-computed cases are unchanged and still pass. tools/t005-static-checks.sh gained a `guards` check (tags, guard tests and equal MAX_TICKS in both files) and 3 negative controls. The MQL5 test script mirrors the new fixtures (X_WHY reason tags, no-geometry check) and adds NaN/inf/DBL_MAX, 0.015 and an on-grid sweep, all UNRUN.

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
