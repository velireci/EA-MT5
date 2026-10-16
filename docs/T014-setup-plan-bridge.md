# T014 - setup -> plan bridge (one existing T004 candidate -> TradePlanning plan)

Status 2026-10-15: IMPLEMENTED in the sandbox on top of 1b0016a (one integration block). Compile and MT5 run UNVERIFIED (Codex compiles `SetupPlanBridgeTest.mq5`, the owner runs it in MT5). Not wired to any EA, permit, executor or demo. T011/T012/T013/TradePlanning untouched.

## What it does
`SPB_Build(selection, market, SM4State, SM4Candidate[], broken SM4Level, asof) -> SSpbResult`: either `plan_ready` with an `STpPlan` produced by the existing `TP_BuildPlan` (geometry and sizing are NOT re-implemented), or ONE concrete blocking reason. It gives no permit, sends nothing, writes no execution record and never changes the observer state. A plan is not a trading permission: `TP_CheckPermit` and the entry executor are separate steps.

## What it does NOT do
It does not detect H4 or M15 structure (the T004 observer state is the input), does not pick a source, swing, timing, candidate, entry edge, stop, buffer or target silently (every one is an explicit selection; the default selection is all UNSET and blocks with the names of what is unset), does not use the demo opener and does not read the terminal or a clock (`asof` and `live_after` are arguments).

## Explicit selections (`SSpbSelection`), all UNSET by default
`context_source` (must equal the observer context source: T003_PROTOTYPE or T002_H4_TOUCH_PROPOSAL, never combined), `swing_selector` (recorded; the swing is chosen by whoever drives the observer), `timing_policy` (must equal the observer policy and be A_AT_OR_AFTER_BREAK), `candidate_selector` (EXPLICIT_ID with an id, or SOLE_ELIGIBLE = exactly one eligible candidate, else BLOCK; the first candidate is never taken), `entry_edge` (NEAR_SIDE = BUY upper / SELL lower, the edge met first on the return, an interpretation of "the beginning of the FVG"; FAR_SIDE), `sl_rule` (BROKEN_LEVEL_PRICE with an EXPLICIT buffer, 0.0 allowed only if stated; or SUPPLIED price; the exact extreme of the broken structure remains an open definition), `target_rule` (NONE_2R_MINIMUM = only the client 2R minimum; or SUPPLIED price with a stated source), `live_after` (baseline instant of the live run).

## Rules of the bridge (in this order, first failure wins)
selections stated -> context ready / reliable / selected -> source and timing equal the selection -> not REPLAY_REQUIRED -> not RETURN_OBSERVED while no valid untouched candidate is left (PROPOSAL under review 2026-10-16, not applied to the active EA: the phase is global; a touched candidate stays refused, no delayed entry) -> phase WAIT_RETURN or RETURN_OBSERVED -> no future observer data -> the supplied broken level is the one the observer recorded -> candidate ids unique -> candidate chosen (invalidated and returned ones are never eligible) -> bounds and direction consistent -> candidate not newer than `asof` -> candidate newer than `live_after` (older = historical / replayed, not a signal) -> E, S, T from the explicit rules -> `TP_BuildPlan` (a refusal is `PLAN_REFUSED: <builder reason>`).

## Identities
`setup_id = S|source|context.setup|context.fvg|broken level id`, `signal_id = setup_id|candidate id` (the candidate id `M15F<time of candle A><U|D>` already carries time and direction). No clock, counter or random value enters an id, so a restart or a replay of the same bars gives the same ids; the entry executor's one-record-per-signal rule therefore keeps blocking (verified in a Python test that builds a plan, places it through the fake entry executor, rebuilds it from a fresh observer and gets DUPLICATE).

## Tests
Python `tests/test_spb.py` (27 tests, 18 mutants; the real T004 reference observer is driven with closed bars for BUY and SELL), MQL5 `src/tests/SetupPlanBridgeTest.mq5` (12 scenarios, names pinned equal by a Python test), `tools/spb-static-checks.sh` (pure, one `TP_BuildPlan`, no geometry/permit/execution reference, observer read-only, check order, nothing selected by default, ids without clock, protected modules identical to 1b0016a, 6 negative controls).

## Open / UNVERIFIED
Compile and MT5 of the new files; the choice of source, swing selector, FVG timing, candidate rule, entry edge, SL definition, buffer and target are open client/owner decisions and stay inputs; `live_after` must be supplied by the live orchestrator (which does not exist yet); the market block (risk budget, tick value, symbol limits, quote) is supplied by the caller exactly as `TP_BuildPlan` expects.

## T016 correction: geometry before sizing
SPB_Build keeps its original signature and one TP_BuildPlan call. Shared SPB_Prepare performs the existing candidate validation and identity work; SPB_Geometry calls TG_Compute without sizing. This prevents unreliable reported tick values from refusing a provisional plan before the broker probe. Codex: SetupPlanBridgeTest compiles 0 errors / 0 warnings; bridge tests pass within 128 targeted entry-chain Python tests. Owner MT5 rerun pending.

