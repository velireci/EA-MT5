# T018 Read-only account exposure for the entry gate

Status: written in the sandbox on base c6e9557. Compile and MT5 run UNVERIFIED (Codex compiles, owner runs). FAKE execution only; no real transport, no trade, no merge.

## Why
After T016/T017 the gate still got `open_positions` and `existing_risk` from hand-typed EA inputs. This block replaces them, opt-in, with a READ-ONLY reading of the account. Nothing strategic is decided.

## What
- `src/include/ExposureReader.mqh` - pure core `EX_Compute(magic, symbol, pending_policy, port, result)` over an abstract port `CExPort`; Python mirror `tests/exposure_reference.py`; tests `tests/test_exposure.py` (incl. 9 source-replace mutants), MQL5 `src/tests/ExposureReaderTest.mq5` (8 scenarios pinned equal by a Python test).
- `src/include/ExposureReaderReal.mqh` - the real port: `PositionsTotal/PositionGet*`, `OrdersTotal/OrderGet*`, `ACCOUNT_MARGIN_MODE`, `OrderCalcProfit`. No order function (compile-only).
- `src/XauUsdEntryOrchestrator.mq5` v1.02: inputs `InpExposureSource` (EXPLICIT default | ACCOUNT_READ) and `InpPendingPolicy` (UNSET default | COUNT_AS_POSITIONS | IGNORE). Before every `Step` the ACCOUNT_READ path overwrites `open_positions` and `existing_risk`; the explicit inputs are then ignored, with no fallback. `trades_today` stays an explicit input (its definition is the open daily classification decision).
- `tools/exposure-static-checks.sh` (nine negative controls). `tools/entry-orchestrator-static-checks.sh` updated: the EA include list gains `ExposureReaderReal.mqh`; the `EntryTransportReal.mqh` hash pin vs e8968bd is dropped (T017 moved the file store out; `entry-persistence-static-checks.py` protects it).

## Rules
- Ownership = magic only, on a HEDGING account only. Netting/exchange: `OWNERSHIP_NOT_SEPARABLE`, unknown (a manual trade cannot be separated). Items of another magic are counted as foreign information, never owned, never evaluated.
- Unknown is `-1` (the gate blocks), never zero: unreadable account, incomplete or over-capacity list (64), unknown type, UNSET pending policy. Zero is reported only for a read that really found nothing.
- Pending policy is the owner's decision and has no default. COUNT: an owned pending order reserves a position and adds its risk at its own price; IGNORE: orders are not read.
- Risk = loss at the stop from the BROKER calculation (`OrderCalcProfit`); a stop past break-even carries 0; a missing SL/price/volume or an unobtained calculation makes the risk unknown while the count stays known.

## Not decided / not done
- Whether pending orders reserve a position, the 2-vs-3 trade limit, the combined risk cap and the daily classification stay owner decisions (inputs, UNSET blocks).
- `trades_today` is not derived. FAKE tickets are not on the account; this reads real broker state only.
- T011 registration after a fill remains unconnected (needs owner authorisation to change the stored-SL rule).

## Evidence
Sandbox: `python3 -m unittest tests.test_exposure` and `tools/exposure-static-checks.sh` (static only). MetaEditor compile of `ExposureReaderTest.mq5` and `XauUsdEntryOrchestrator.mq5`, and the MT5 run of the test, are UNVERIFIED.

## Next action
Codex compiles both files; the owner runs `ExposureReaderTest`. Then, with ACCOUNT_READ and a policy chosen by the owner, one demo-chart observation that the log line `T018 EXPOSURE` matches the account.
