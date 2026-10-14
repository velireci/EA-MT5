# T008 — read-only broker preview

Owner authorised continuing while Claude is rate-limited. Codex is sole writer. Base 40fede0; T005–T007 production code unchanged.

Goal: connect tested geometry/sizing/planning to actual broker symbol data and OrderCalcProfit without sending any order. This is a manually supplied candidate preview, not automatic H4/M15 signal selection.

Architecture: XauUsdTradePreview EA performs one explicit evaluation at initialization; only chart display refreshes on timeframe change. Prices, monetary risk budget and policy snapshot are user inputs, unset/unknown by default. Existing SymbolSnapshotLoad supplies instrument/account properties; SYMBOL_TRADE_TICK_VALUE_LOSS supplies the loss-side tick value. TradePlanning supplies plan and permit. CheckPermit is used, never Authorize, because preview consumes no signal. BrokerLossCheck pure helper rejects failed/nonfinite/nonnegative profit, budget excess and excessive model discrepancy. OrderCalcProfit is read-only and returns account currency; no cost guarantee.

Constraints: no OrderSend/CTrade/OrderCheck, no account/history exposure inference, automatic risk base, news/calendar or session inference, persistence, actual cancellation, partial exits or 50-unit stop policy. Unknown policies remain BLOCK. Real broker properties are not client choices. Trade mode disabled/close-only or wrong side blocks. Quotes must be connected, positive/ordered and no older than a supplied maximum age (default30 seconds, technical diagnostic convention).

Implementation steps:
- Write failing pure-helper tests for BUY/SELL losses, failed broker calc, NaN/inf, nonloss, budget overrun, discrepancy boundary and invalid tolerance.
- Implement identical pure comparison in Python and MQL5. Tolerance fraction is explicitly supplied (default1% in preview for diagnostics only, not trading risk). Budget comparison uses existing TP_RiskExceeded; do not copy risk arithmetic.
- Add EA adapter reading current symbol, quote and account currency, build plan with supplied E/SL/target/budget, compare OrderCalcProfit for actual proposed volume, run permit on external snapshot with unknown defaults.
- Run focused Python tests and compile helper test/EA. Independent review; owner runs actual terminal smoke tests. Update STATE/checklist and publish without merge.

Acceptance: pure test pass, MetaEditor0/0, owner script and real broker preview separately recorded. PREVIEW_ONLY is never execution permission. A synthetic test cannot validate actual broker settings.

References: https://www.mql5.com/en/docs/trading/ordercalcprofit ; https://www.mql5.com/en/docs/marketinformation/symbolinfotick ; https://www.mql5.com/en/docs/constants/environment_state/marketinfoconstants
