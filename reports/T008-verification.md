# T008 verification

Code base 40fede0; implementation by Codex, 14 October 2026. No prior production module modified.

Executed: initial new Python tests failed because the helper did not exist, then 8 focused T008 tests pass. Existing T006/T007 regression suites run with T008 (98 total tests pass). New MQL test has 19 assertions; this count is not an MT5 result.

MetaEditor: XauUsdTradePreview.mq5 0 errors, 0 warnings, 1709ms; T008_BrokerLossTest.mq5 0 errors, 0 warnings, 891ms. Includes compiled tested T005/T006/T007 and existing SymbolSnapshot.

Independent review found combined cap previously checked lower model loss while broker loss could be higher within discrepancy tolerance. Corrected to use max(model,broker estimate) in a separate guarded plan for permit only; original model preserved. Regression: existing90/cap100/model10/broker10.05/budget11/tolerance1% blocks combined cap. Exact boundary100 still allowed. Unknown signal usage explicitly blocks; preview never calls Authorize or consumes a signal.

Actual MT5 helper test and EA default/input/live broker observations: PENDING. No broker prices/account identifiers saved here. No automatic signal selection, calendar, session inference, risk-base choice, orders, actual cancellation, persistence or partial management. No claim of strategy/client validation, broker execution acceptance, margin adequacy or profitability.

T007 relayed owner evidence: 2026.10.14 19:36:11.672 T007_PlanningTest-40fede0 (XAUUSD,M15), 1092 passed, 0 failed. Earlier1090/2 at d992258 was test-fixture initialization and remains a failed historical observation; corrected run is separate.
