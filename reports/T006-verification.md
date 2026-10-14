# T006 verification: pure position-sizing helper

Date: 2026-10-14. Branch codex/t004-m15-confirmation, on top of 25dbb10 (changes UNCOMMITTED when written). Evidence is separated by source. Nothing here validates the strategy, the base of the 1%, the broker's real loss, costs or profitability; the helper is not wired to any EA or order.

## Executed in this session (Claude, Linux, Python 3.13; no MetaEditor, no MT5)
| Check | Command | Result |
|---|---|---|
| T006 unit tests | `cd tests && python3 -m unittest test_t006_sizing` | 37 tests OK |
| T004 + T005 + T006 together | `cd tests && python3 -m unittest test_t004 test_t004_selector test_t004_timeline test_t004_ordinary test_t005_geometry test_t006_sizing` | 170 tests OK (T004 94 + T005 39 + T006 37) |
| T004 + T005 without T006 | same without test_t006_sizing | 133 tests OK (T005 geometry tests unchanged) |
| T002 / T003 reference | `python3 tests/t002_reference_test.py`, `python3 tests/t003_reference_test.py` | T002 197 passed, 0 failed; T003 476 passed, 0 failed, 5 deferred (deferred are not passes) |
| Static checks | `bash tools/t001-static-checks.sh`, `t002`, `t003-visual`, `t004`, `t005`, `t006` | all six ALL PASS (t001 33 PASS lines, t002 60, t003-visual 188, t004 72, t005 84, t006 95) |
| t003 static | `bash tools/t003-static-checks.sh` | 115 PASS, 1 FAIL (CHECK 12, caused only by the uncommitted docs edit; see the last section) |

What the T006 tests contain:
- 62 hand-computed table rows (tests/t006_sizing_fixtures.py, derivations in its docstring, computed separately from the code formula). The geometry for each row is produced by the REAL T005 reference first (BUY and mirrored SELL), then passed to the sizer. Covered: steps 0.01, 0.1, 0.05, 1.0, 0.001, 0.5; raw volume exactly on the step (0.3 lots with step 0.1, 0.07, 0.29, 1.6); float-sensitive tolerance case (10 ticks, step 0.001, budget 0.29 = 29 steps although floor(0.29/0.01) style division gives 28.99..); a budget 5e-7 step below an integer fit (the 1e-6 tolerance proposes 3 steps, the never-exceed guard gives 2); tick values 0.8, 2 and 5 with tick 0.05; below min, rounds to zero, exactly min, above max, exactly max, above cap, exactly cap, cap off the grid above and below, float-sensitive cap 0.3 with step 0.1, cap greater/smaller than max, both exceeded, cap below min, min == max; geometry not OK (ZERO_RISK, SL_WRONG_SIDE, invalid direction, geometry failure wins over a bad budget); every INVALID_INPUT tag (budget, tick value, min, step, max, cap, max below min, min/max off grid, step tiny, cap too many steps, raw overflow, non-finite raw).
- Interface tests: stop ticks come from the reported geometry ticks (T005 BUY_ROUND_FAR gives 101 ticks, not from raw prices); other geometry fields ignored; 500 random real T005 BUY/SELL pairs with equal stop ticks give identical sizing; seven real T005 failure statuses (ZERO_RISK, SL_WRONG_SIDE, INVALID_DIRECTION, INVALID_INPUT, BELOW_STOPS_LEVEL, TARGET_WRONG_SIDE, PENDING_TOO_CLOSE) all give GEOMETRY_NOT_OK with nothing reported; OK status with equal ticks, not computed, out-of-range, non-integer or boolean ticks, and junk objects.
- Validation: each of the six parameters rejects 0, negative, NaN, +/-inf, None, string, bool with its tag and nothing reported; first-failure order; steps 0.01 / 0.1 / 0.05 / 1 / 0.001 / 0.5 / 0.25 / 0.02 (step 0.01 never assumed); grid tolerance boundaries (9e-7 step accepted, 2e-6 rejected); 1e9 step boundary; overflow tags.
- Properties: seeded sweep of 20000 random cases (15842 OK, 4158 skip/overflow): risk_realized <= budget in the defined double expression, risk_realized == n*risk_per_step, volume_out == n*step, volume_out never above volume_raw beyond 1e-6 step, at most one step lost, result maximal (n+1 steps would exceed), and an exact-rational check with Fraction: the real-arithmetic excess over the budget is at most 1e-14 relative (float rounding only). A second sweep of 20000 decimal-exact fits: the result is n0 or n0-1, never more.
- Mutation checks (15 defective copies of the reference source, each caught by the hand table or the property sweep): round up instead of down; no never-exceed guard loop (caught by BUY_TOLERANCE_OVERSHOOT and by the sweep); no float tolerance; clamp to max/cap instead of skip; raise to minimum instead of skip; ignore tick_value; assume step 0.01; min/max/cap boundary made exclusive; missing max < min, min grid, max grid and step-range guards; cap floored without tolerance.
- Also: determinism, no mutation of inputs, immutable results, labels, header statements, no hidden 0.01 or 10 literal in the reference, MQL5 fixture block textually equal to the generated Python table.

Static checks (tools/t006-static-checks.sh, 95 PASS lines): no trading API, no quote/tick/symbol/account/series/clock access, no hidden 0.01 or 10 literal, header statements and labels in code, status enum, reason tags and their first-failure order, and four numeric constants equal in MQL5 and Python, identical round-down and never-exceed expressions in both languages, no ceil/round/NormalizeDouble, limit order min -> max -> cap, no reduced_to_limit field, balanced syntax, format strings, ASCII, includes resolve, 55 T001-T005 paths identical to 25dbb10, 21 negative controls detected.

## NOT run (UNVERIFIED)
- MetaEditor compilation of src/include/PositionSizing.mqh and src/tests/T006_SizingTest.mq5 (not available here). The MQL5 was written by hand and mirrored from the Python reference; compile errors or warnings are possible (for example struct passing by const reference, `ulong` LCG arithmetic, `%I64d` formats).
- Execution of T006_SizingTest.mq5 in MT5. The Python tests prove the contract of the Python reference; the MQL5 fixture block is only checked for textual equality with the generated Python table. The MQL5 test also repeats the table, NaN/inf inputs, a hand-built geometry struct, the ulp-tie case and a 5000-case deterministic sweep, all UNRUN.
- Behaviour with real broker symbol parameters (tick value in account currency, volume min/step/max) of the target account.

## Relayed from owner or Codex
Nothing relayed for T006 yet.

## Conventions needing review (proposals, not client answers)
1. Strict never-exceed in the double expression can cost one step on a one-ulp tie of a decimal-exact fit (documented test: 47 ticks, step 0.1, budget 249.1 gives 52 steps, 53 fit in decimal); about 19% of contrived exact-fit cases lose a step. A relative tolerance would avoid it but would allow exceeding the budget.
2. Tolerances and bounds: 1e-6 step (grid and float noise), 1e9 steps (max and cap), 1e15 raw steps, 1e13 ticks.
3. A cap off the step grid is compared after flooring (cap_steps) and never used as a volume; a cap below the minimum is valid input and always skips; the broker maximum is reported before the cap when both are exceeded; geometry failure is reported before parameter validation.
4. SKIP results keep diagnostics (steps_rounded, volume_raw, ...) but zero volume and risk.
5. The caller must normalize volume_out to the broker volume digits (n*step carries binary noise, e.g. 3*0.1); the integer steps_rounded is authoritative.

## Still open (not decided by this module)
Base of the 1%; costs and slippage in risk and in R; account-currency conversion and the real tick value of the target broker; combined 2% and pending reservation; 2-position limit; 80/20 partial volume rounding; 2 versus 3 trades; the 50 stop-distance limit; order placement and wiring.

## t003 static check note
`bash tools/t003-static-checks.sh` ran (115 PASS lines) with exactly ONE FAIL, CHECK 12 ("a tracked file other than the T003-owned ones differs from HEAD"), triggered only by the intentional UNCOMMITTED edit of docs/PROJECT_CHECKLIST.md (the new T006 files are untracked and listed as INFO). The same check's code-path comparison against the base commit dd571f6 PASSES, and every other t003 check passes. It should pass again once the parent commits the documents; rerun it after the commit.
