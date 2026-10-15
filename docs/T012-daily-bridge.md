# T012 bridge: history FACTS -> daily-limit check

Status: pure module, Python-tested; MetaEditor compile and MT5 run UNVERIFIED. T012 is NOT closed. No terminal read, order, persistence, real reset
or EA integration. Files: `src/include/DailyBridge.mqh`, `src/tests/T012_BridgeTest.mq5`, `tests/t012_bridge_{reference,fixtures}.py`,
`tests/test_t012_bridge.py`, `tools/t012-bridge-static-checks.sh`.

## What it does
`DB_Check(verdict, facts, utc, balance, policy, classified, max_trades_set, max_trades, result)` maps READY + complete `SDhFacts` and explicit inputs to
the arguments of `DL_Check` (reused, nothing copied) and returns its result unchanged. It selects no policy and reconstructs nothing.

## Contract the caller must fulfil (every missing item blocks, reasons listed in this order)
| # | Requirement | Reason when missing |
|---|---|---|
| 1 | verdict `READY` (UNKNOWN / BLOCK carry no facts) | `HISTORY_NOT_READY:UNKNOWN` / `:BLOCK` / `:?` |
| 2 | `facts.complete == true` (owner assertion + detectable checks) | `HISTORY_INCOMPLETE` |
| 3 | balance at the START of the day, supplied (`known`, `amount`) | `BALANCE_START_UNSET` |
| 4 | the balance is for the same Tirane day as the facts | `BALANCE_DAY_MISMATCH` |
| 5 | result formula: `PROFIT` / `PROFIT_COMMISSION_SWAP` / `PROFIT_COMMISSION_SWAP_FEE` (which candidate sum is the closed result) | `POLICY_UNSET:result_formula` (UNSET) / `POLICY_UNSUPPORTED:result_formula` |
| 6 | trade classification `CALLER_CLASSIFIED`: the caller supplies `trades`, `wins`, `consecutive_losses` after applying ITS OWN definition of trade / win / loss / breakeven | `POLICY_UNSET:trade_classification` / `POLICY_UNSUPPORTED:trade_classification` |
| 7 | classification not contradicted by the facts (trades > 0 with no robot position) | `CLASSIFICATION_CONTRADICTS_FACTS:trades_without_positions` |
| - | trade limit 2 or 3 stays an input | `POLICY_UNSET:max_trades_per_day` (from `DL_Check`, which still proves the other limits) |

When any of 1-7 is missing `DL_Check` is NOT called: not allowed, `cancel_pending_due=false`, `daily_limit_reached=false` (missing data proves no
limit). Facts-dependent checks (2 is skipped when not READY; 4 and 7 only on READY) never read the facts of an UNKNOWN / BLOCK verdict.
When everything is defined: the facts day is passed as `snapshot_day`, so the history of another Tirane day ends as `STALE_SNAPSHOT_DAY`; unknown
(negative) counts become `INVALID_SNAPSHOT:*` and are never zero; the deal count is never a trade count; all other results/reasons/flags come from `DL_Check`.

## Decisions that remain for the client / owner (nothing here chooses them)
1. Which closed-result formula counts for the -2% rule (profit only, + commission + swap, + fee); fees on the demo may differ from Tauro.
2. The definition of trade, win, loss and breakeven, incl. partial exits (the 80/20 split makes one position two exits), costs and breakeven; and what "consecutive" means across partials.
3. 2 versus 3 trades per day (input).
4. How the balance at the start of the day is obtained: owner-supplied input today; a verified read/reconstruction (deposits, withdrawals, credits) is a later step.
5. Whether a manual close of a robot position, other-EA trades with the same magic, and positions opened on an earlier day and closed today count.
6. Who asserts `complete=true` and on what evidence (today: the owner's assertion).
7. Server-offset (broker DST) handling inside a day, and netting/exchange accounts (unsupported: BLOCK).
Plus the pre-existing open items: reset at the Tirane midnight and persistence/restart recovery (not built), wiring of the permit (not done).

## Preview source HISTORY_BRIDGE (preview v1.05)
`InpDailySource=DAILY_SRC_HISTORY_BRIDGE` runs `DH_ReadAndBuild` -> `DB_Check` and feeds the daily result into the existing final preview result; MANUAL (default) and DAILY_SNAPSHOT are unchanged. Explicit inputs only: `InpDailyEaMagic` (>0), `InpDailyServerOffsetSeconds`, `InpDailyHistoryComplete`, `InpDailyBalanceStart` + `InpDailySnapshotDay` (the balance's day), `InpDailyResultFormula`, `InpDailyClassification`, `InpTradesToday`, `InpDailyWins`, `InpDailyConsecutiveLosses`, `InpMaxTrades`. Defaults: UNSET / unknown / complete=false. `InpDailyClosedResult` and `InpDailyResultKnown` are ignored in this source. Read-only proof preset: `src/presets/XauUsdTradePreview_T012_history_bridge_readonly.set`.
