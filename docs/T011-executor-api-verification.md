# T011 executor: trading API verification status and limits

RELAYED 2026-10-15 (owner/Codex, details not seen by me): Codex has read the official OrderSend and MqlTradeRequest pages. Status below: from my side the pages stay unread and the item list is the checklist Codex compared; I do not know which items were confirmed beyond that statement.

Historical text (state at 129a267, written when no page could be read):

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

## Correction after the Codex review of 59ec88e (relayed: Python 0 failures; ExecutorTest and RealCompile MetaEditor 0 errors / 0 warnings; real transport not executed)
Reproduced with the fake transport: filling = 99 and filter_policy = 99 sent once and returned SENT_MAPPED; `_on_grid(4000.004, 0.01)` was True because the tolerance 1e-6 * max(1, |price/tick|) allowed 0.4 tick at that price.
Fixed: every enum that steers the send (filling, exit-filter policy, exit-filter state, the test save fault, the position direction) must be a known value, otherwise BLOCKED before any read, persist or send ("INVALID_INPUT"); UNSET stays "INPUT_UNSET".
The real transport no longer maps an unknown filling to RETURN: an unmappable request makes `Fill` return false, the pre-check fails and `Send` returns without calling OrderSend. The grid test is floating-point noise only (8 machine epsilons relative to the number of ticks)
and requires finite, positive price and tick: a real difference such as 0.004 with a tick of 0.01 is refused. A plan value on the grid but not exactly representable in the record (for example 399991 * 0.01 = 3999.9100000000003) is
refused as PLAN_NOT_REPRESENTABLE_IN_RECORD before anything is persisted, never rounded (the activation compares level and volume with ==). A blocked call sends nothing and writes no new INTENT.
