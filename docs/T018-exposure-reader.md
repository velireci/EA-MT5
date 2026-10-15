# T018 Read-only account exposure for the entry gate

Status: written in the sandbox on base c6e9557. Compile and MT5 run UNVERIFIED (Codex compiles, owner runs). FAKE execution only; no real transport, no trade, no merge.

## Why
After T016/T017 the gate still got `open_positions` and `existing_risk` from hand-typed EA inputs. This block replaces them, opt-in, with a READ-ONLY reading of the account. Nothing strategic is decided.

## What
- `src/include/ExposureReader.mqh` - pure core `EX_Compute(magic, symbol, pending_policy, port, result)` over an abstract port `CExPort`; Python mirror `tests/exposure_reference.py`; tests `tests/test_exposure.py` (incl. 9 source-replace mutants), MQL5 `src/tests/ExposureReaderTest.mq5` (8 scenarios pinned equal by a Python test).
- `src/include/ExposureReaderReal.mqh` - the real port: `PositionsTotal/PositionGet*`, `OrdersTotal/OrderGet*`, `ACCOUNT_MARGIN_MODE`, `OrderCalcProfit`. No order function (compile-only).
- `src/XauUsdEntryOrchestrator.mq5` v1.02: inputs `InpExposureSource` (EXPLICIT default | ACCOUNT_READ), `InpPendingPolicy` (UNSET default | COUNT_AS_POSITIONS | IGNORE) and `InpPendingRiskPolicy` (UNSET default | INCLUDE | EXCLUDE). An unknown enum value (e.g. 99) is refused in `Configure` (INIT_PARAMETERS_INCORRECT); it never falls through to the manual inputs. Before every `Step` the ACCOUNT_READ path overwrites `open_positions` and `existing_risk`; the explicit inputs are then ignored, with no fallback. `trades_today` stays an explicit input (its definition is the open daily classification decision).
- `tools/exposure-static-checks.sh` (nine negative controls). `tools/entry-orchestrator-static-checks.sh` updated: the EA include list gains `ExposureReaderReal.mqh`; the `EntryTransportReal.mqh` hash pin vs e8968bd is dropped (T017 moved the file store out; `entry-persistence-static-checks.py` protects it).

## Rules
- Ownership = magic only, on a HEDGING account only. Netting/exchange: `OWNERSHIP_NOT_SEPARABLE`, unknown (a manual trade cannot be separated). Items of another magic are counted as foreign information, never owned, never evaluated.
- Unknown is `-1` (the gate blocks), never zero: unreadable account, incomplete or over-capacity list (64), unknown type, UNSET pending policy. Zero is reported only for a read that really found nothing.
- Two SEPARATE owner decisions, neither defaulted: (1) does an owned pending order RESERVE a position (`InpPendingPolicy`); (2) is its RISK part of the existing risk (`InpPendingRiskPolicy`). IGNORE the reservation never drops the risk (regression: a pending order with risk 10 still gives 10 with IGNORE + INCLUDE). With the risk policy UNSET the risk is UNKNOWN as soon as an owned pending order exists (the count stays known); with no owned pending order nothing is left to decide. Orders are always read.
- Read integrity: the real port uses only the getter overloads that return a success flag (a failed getter is never 0 - a magic of 0 would look like a manual position), a negative magic or empty symbol is a failed read, and a count that changes while a list is read makes it incomplete. The core takes TWO complete snapshots in the order positions -> orders -> positions -> orders and compares every field of each list afterwards; a difference is `POSITIONS_CHANGED` / `ORDERS_CHANGED` = unknown. This order matters: a pending order filled between the reads leaves the orders and appears among the positions, so reading positions twice and then orders twice could miss it in both lists and confirm a zero.
- Risk = loss at the stop from the BROKER calculation (`OrderCalcProfit`); a stop past break-even carries 0; a missing SL/price/volume or an unobtained calculation makes the risk unknown while the count stays known.

## Not decided / not done
- Whether pending orders reserve a position, whether their risk counts, the 2-vs-3 trade limit, the combined risk cap and the daily classification stay owner decisions (inputs, UNSET blocks).
- `trades_today` is not derived. FAKE tickets are not on the account; this reads real broker state only.
- T011 registration after a fill remains unconnected (needs owner authorisation to change the stored-SL rule).

## Evidence
Sandbox: `python3 -m unittest tests.test_exposure` and `tools/exposure-static-checks.sh` (static only). MetaEditor compile of `ExposureReaderTest.mq5` and `XauUsdEntryOrchestrator.mq5`, and the MT5 run of the test, are UNVERIFIED.

## Next action
Codex compiles both files; the owner runs `ExposureReaderTest`. Then, with ACCOUNT_READ and a policy chosen by the owner, one demo-chart observation that the log line `T018 EXPOSURE` matches the account.

## Correction after the Codex review of ebbcb38 (compile 0/0 both files, 11 Python OK)
Three findings fixed together, regressions first: (1) unchecked getters / unverified list stability -> flagged getters, change detection in the port and a double read in the core; (2) `IGNORE` merged the reservation with the risk -> two policies; (3) unknown `InpExposureSource` fell to the manual inputs -> refused in `Configure`. Python 11 -> 13 tests (2 new MQL scenarios `list_changes_during_read`, `pending_risk_separate`), static script 14 controls. The signature of `EX_Compute` gained `risk_policy`. Compile and MT5 of the new version UNVERIFIED.

## Second correction (Codex review of 36493e8)
Read order positions -> orders -> positions -> orders (was positions, positions, orders, orders, which lost a pending -> position transition and could confirm zero). Regression for BUY and SELL: the fill happens before read 2, 3 or 4 -> UNKNOWN (-1), never a confirmed zero; before read 1 or after read 4 the snapshot is consistent. Python 14 tests (mutant that restores the old order is caught), MQL5 scenario `fill_between_reads`, static control for the order. One MT5 round for the whole package follows the compile.
