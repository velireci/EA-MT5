# T006 - pure position sizing (checklist area 2, first bounded step)

Status: 2026-10-14. Implemented as a PURE helper, not wired to any EA or order. Python tests executed; MetaEditor compile and MT5 run: UNVERIFIED (see reports/T006-verification.md). Authorised by the owner as a bounded step; nothing else of area 2 is decided here.

Files: src/include/PositionSizing.mqh (MQL5), tests/t006_sizing_reference.py (Python mirror), tests/t006_sizing_fixtures.py (hand-computed table shared with the MQL5 test), tests/test_t006_sizing.py, src/tests/T006_SizingTest.mq5, tools/t006-static-checks.sh + tools/t006-static-check.py. T001-T005 code, tests and tools are untouched (read-only reuse of TradeGeometry's `TG_Finite`, `STgResult`, `TG_OK`, and of the Python `Result`).

## Contract
Interface (the same in both languages): `PS_Compute(geo, risk_budget, tick_value, volume_min, volume_step, volume_max, cap_lots, out)` / `size(geo, risk_budget, tick_value, volume_min, volume_step, volume_max, cap_lots)`; no default argument anywhere.
- `geo` is the T005 result (`STgResult` / `Result`). Only `status`, `computed`, `e_ticks`, `s_ticks` are read; no price is normalized, validated or recomputed. `stop_ticks = |e_ticks - s_ticks|`.
- `risk_budget` (account currency) is SUPPLIED. The base of the 1% is not chosen and the 1% is not applied.
- `tick_value` = value of ONE tick for ONE LOT in ACCOUNT currency, as the caller passes it. No conversion here.
- `volume_min/step/max` are the broker's; `volume_step = 0.01` is never assumed. `cap_lots` is an input (the client number 10 is passed by the caller).
- LINEAR MODEL: `loss_per_lot = stop_ticks * tick_value`; `volume_raw = risk_budget / loss_per_lot`. A model with the supplied parameters, not a guarantee of the broker's real loss. COSTS_NOT_MODELLED (costs, slippage, contract changes, profit-currency conversion are outside).
- ROUND DOWN only: `n = floor(budget / (step*loss) + 1e-6)`, then `while n > 0 and n*(step*loss) > budget: n -= 1`; `volume_out = n*step`, `risk_realized = n*(step*loss)`. Realized risk never exceeds the budget for that double expression (same in both languages; tested by a 20000-case seeded sweep plus an exact-rational check: float rounding only, relative <= 1e-14). Never raised to the minimum, never clamped to max or cap: a conflict is a SKIP and `volume_out = 0`. There is no `reduced_to_limit` field (documented, static-checked).
- LIMITS after rounding, in integer steps: `n < min_steps` SKIP_BELOW_MIN_VOLUME (includes 0); `n > max_steps` SKIP_ABOVE_MAX_VOLUME; `n > cap_steps` SKIP_ABOVE_CAP with `cap_steps = floor(cap/step + 1e-6)` (the cap may be off the grid; it is a comparison bound, never a volume). Max and cap are checked separately, the broker maximum first. A cap below the minimum is valid input (always a skip).
- Statuses, first failure wins: GEOMETRY_NOT_OK; INVALID_INPUT with tags in this order INVALID_STOP_TICKS, INVALID_RISK_BUDGET, INVALID_TICK_VALUE, INVALID_VOLUME_MIN, INVALID_VOLUME_STEP, INVALID_VOLUME_MAX, INVALID_CAP, VOLUME_MAX_BELOW_MIN, STEP_RANGE (max/step or cap/step > 1e9 or non-finite), VOLUME_NOT_ON_GRID (min, then max; multiple >= 1 of the step within 1e-6 step), NUMERIC_OVERFLOW (non-finite/non-positive loss or risk per step, raw steps > 1e15); then SKIP_BELOW_MIN_VOLUME, SKIP_ABOVE_MAX_VOLUME, SKIP_ABOVE_CAP; else OK. Nothing is coerced.
- Output on failure: GEOMETRY_NOT_OK and INVALID_INPUT report all numeric fields as 0 (computed false). A SKIP keeps diagnostics (stop_ticks, loss_per_lot, volume_raw, steps_rounded, min/max/cap steps) but volume_out, risk_realized and rounding fields are 0.
- Result also reports `step_rounded`, `volume_rounding_loss` (normal rounding down) and `risk_unused`.

## What this task does NOT decide (open items)
- The base of the 1% (balance, equity, start-of-day, ...) and whether the cap/min conflicts use other rules: C6.
- Costs in R and in risk (spread, commission, slippage), and how tick_value is obtained in the account currency from the target broker (Tauro XAUUSD.r/USD properties are unverified).
- Combined 2% open risk, reservation by pending orders, 2-position limit, manual-trade separation.
- 80/20 partial volume rounding (the 20% remainder at the broker's step and minimum) and the remainder when TP equals 2R.
- 2 versus 3 trades per day; the 50 stop-distance limit.
- Order placement, margin/free-margin checks, wiring into the EA, restart recovery.

## Conventions needing review (proposals, not client answers)
1. The strict never-exceed rule can cost one step on a one-ulp binary tie of a decimal-exact fit (e.g. 47 ticks, step 0.1, budget 249.1 gives 52 steps although 53 fit in decimal). About 19% of contrived exact-fit cases lose a step; real budgets are rarely exact. The alternative (a relative tolerance such as 1e-12 on the comparison) was NOT chosen because the owner required "never exceeds".
2. 1e-6 step tolerance for "on the grid" and for float noise on an exact fit; 1e9 step bound for max and cap; 1e15 raw step bound; 1e13 tick bound.
3. Cap below the minimum accepted as valid (always skips); broker maximum reported before the cap when both are exceeded.
4. Geometry failure is reported before parameter validation.
