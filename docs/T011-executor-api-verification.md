# T011 executor: trading API verification status (UNVERIFIED) and limits

## What could and could not be verified
The two official pages requested were NOT readable from the build environment: `https://www.mql5.com/en/docs/trading/ordersend` and
`https://www.mql5.com/en/docs/constants/structures/mqltraderequest` (direct requests are refused by the egress proxy with 403; the fetch tool could not resolve the host). Only web-search result snippets were
seen. They support, and nothing more than, these points; every other line of `src/include/ExitTransportReal.mqh` is from memory:
* `OrderSend` returning true does not mean the order was executed; the outcome is in the result structure (`retcode`, `order`, `deal`), with 10008 "placed" and 10009 "done" seen in the snippets (10010 "done partially" is from memory).
* The request structure has the fields action, magic, order, symbol, volume, price, stoplimit, sl, tp, deviation, type, type_filling, type_time, expiration, comment, position, position_by; `position` identifies an existing position
  being modified or closed; `position_by` is for close-by on hedging accounts; a market order needs, at least, action, symbol, volume, type, type_filling.
Not verified: that `position` must be the current position TICKET (as opposed to the identifier) on a hedging account; the exact meaning of `MqlTradeResult.order` for a market deal; the full return-code table; `OrderCheck` success semantics
(`retcode == 0` assumed, `TRADE_RETCODE_DONE` also accepted); the `ACCOUNT_TRADE_MODE_DEMO`, `SYMBOL_TRADE_MODE_*`, `ORDER_FILLING_*` constants; `PositionGetTicket` selecting the position for the following `PositionGetInteger` calls.
**Codex or the owner must read both pages before any demo run and correct the real transport if needed. Nothing was executed against a terminal.**

## What is protected and what is not
* Protected by tests with the FAKE transport (45 rows plus sequences): zero sends when any check or save fails; exactly one send; an uncertain answer without retry; an unsaved map; a partial-fill answer; a restart after INTENT; a duplicate call; DONE only from the reconciliation.
* Real activation is refused unless ALL hold: the executor is enabled (default off), the authorisation phrase `I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE` is supplied with `real_authorised`, the account is DEMO, the account login / server equal the record's, trading is allowed, the account is HEDGING, the position is found by identifier
  with the configured magic (> 0), symbol and direction, filling / deviation / exit-filter policy are set, TP is known and beyond 2R, and the plan is exactly on the tick grid (a value off the grid is refused, never rounded).
* NOT protected: parallel writers (two terminals or instances using the same folder) - there is no lock and none is claimed; a backup restored over the file; a crash between the single send and the map save (reported as an uncertain send at the next load); the plan is not persisted before the request (a volume-step change between
  registration and the 2R quote is not detected); a state that `ExitActivation` can reach but the codec cannot store (`VOLUME_MISMATCH_BEFORE_REQUEST` is NEEDS_RECONCILIATION without a plan) is only BLOCKED in memory, not saved - a gap between two verified modules, reported and not refactored.
* The real transport is compiled by `T011_ExecutorRealCompile.mq5`, which calls none of its methods.
