# XAUUSD strategy review — XAU-20261006-E27N93

Reviewed 7 October 2026. Source: `pyetesori-xauusd-2026-10-06-XAU-20261006-E27N93.zip`, submitted 6 October 2026 at 18:37 UTC. This is a requirements and evidence review, not a trading recommendation or a finished EA specification.

## 1. Assessment

The client describes a coherent discretionary strategy: identify higher-timeframe direction, wait for a return to an H4 fair value gap (FVG), seek an M15 market structure shift (MSS), place a limit order at an M15 FVG, and aim for external liquidity. The difficult work is converting the visual selection of swings, zones and targets into precise rules that reproduce his decisions.

**We understand the intended sequence, but cannot yet define a faithful fully automatic robot.** The management rules are substantially more detailed than the signal-selection rules. This belongs in the custom market-structure category, not the simple indicator-crossover category discussed earlier.

The ZIP contains two readable documents and four readable JPEGs. All four image sizes and SHA-256 hashes match the JSON metadata. I read both documents and inspected every image. No robot code, indicator source, price history or transaction history is supplied. This review does not establish historical profitability.

The export's generated “23 open items” is not an exhaustive or fully reliable diagnosis. Several unknown selections are partly answered in prose, while important contradictions and definitions are absent from that list.

## 2. Reconstructed strategy

This table separates direct answers from interpretations requiring confirmation.

| Stage | What the client supplied | Status |
|---|---|---|
| Market | Tauro MT5, gold, XAUUSD.r; USD account | Confirmed through the questionnaire's prefilled-facts confirmation; verify against actual account |
| Direction | Prose refers to H1 and H4 swing structure; structured answer selects H4 | H1's role, agreement rule and swing definition unresolved |
| Setup location | Select the “main” H4 FVG; wait for price to return for internal liquidity (IRL), then continue toward external liquidity (ERL) | Narrative present; zone selection and qualifying return undefined |
| Lower-timeframe confirmation | On M15, wait for structure to break, create MSS, and leave an FVG | Exact swing, break criteria and sequence undefined |
| Entry | Limit order at the beginning of the M15 FVG | Order type clear; exact boundary, offset and timing undefined |
| SELL stop | At the highest point of the broken M15 structure | Broad placement clear; which swing and buffer unresolved |
| BUY stop | At the lowest point of the broken M15 structure | Same limitation |
| Final target | External/next liquidity; also described as the next structure break | Target timeframe, eligible levels and selection priority undefined |
| Partial exit | At 2R, close 80% of initial position | Explicit answer; chart correspondence needs checking |
| Remaining position | Move stop, then leave 20% for final target or stop; no trailing | Stop movement has conflicting definitions |

The most useful provisional sequence is:

`Determine direction → select H4 FVG → qualifying return into H4 zone → M15 MSS → select related M15 FVG → place limit → manage filled position → retire/reset setup`.

The return, MSS and FVG events need explicit timestamps and expiration rules. For example, an old MSS must not automatically qualify merely because price touches an H4 zone later. Whether an M15 FVG formed before the structural break can qualify is also unanswered.

For a SELL, the likely intended sequence is bearish higher-timeframe bias, return to a relevant H4 zone, bearish M15 structure break, sell limit on a return into the selected M15 gap, stop at the selected swing high and target below. **This is a reconstruction of the prose, not permission to hard-code those interpretations.**

## 3. Rules already supplied

These are useful implementation inputs, subject to the conflicts below:

- BUY and SELL permitted; client says their rules mirror each other.
- H4 context uses completed candles; M15 signal evaluation is explicitly marked as forming candle.
- Pending orders cancel on direction change, opposite signal, session end and an avoided news event.
- One entry per signal; “new signal” selected as each new qualifying candle.
- Do not trade ranging markets; recognition currently described as “visible by eye.”
- Developer chooses a spread threshold, but action after a spread rejection is unknown.
- Skip trades whose initial stop distance exceeds 50 units of gold-price movement, as currently stored.
- Maximum volume 10 lots; skip on a sizing conflict.
- Detailed answers specify two trades daily, two open positions and 2% combined open-position risk.
- Stop after a winning trade; stop after two consecutive losses; breakeven counts as neither win nor loss.
- Partial closure remains one trade.
- Daily closed-loss limit 2%, based on start-of-day balance, EA activity only; stop entries and cancel pending orders when triggered. Floating losses excluded.
- Daily reset at midnight Europe/Tirane.
- Monday–Friday, 00:00–20:30 Europe/Tirane, following local seasonal clock changes.
- Friday close at 21:00 and cancel pending orders.
- Avoid high-impact USD news for 30 minutes before and after.
- Phone notifications requested.
- Manual trades also occur on the account.

## 4. Essential definitions before implementing signals

### A. Direction and swings

The prose says “HH dhe LH ose LH dhe LL.” That may contain a typo; do not silently replace it with a familiar bullish/bearish formula.

Ask him to mark the exact highs and lows used to determine direction. Establish whether a swing is selected manually, by one of his indicators or by a fixed rule. If confirmed pivots require later candles, the EA can only use them after confirmation, not retroactively at the pivot's timestamp. This is a known issue with historical pivot displays; see [TradingView's repainting documentation](https://www.tradingview.com/pine-script-docs/concepts/repainting/).

Determine H1 versus H4 priority, behavior when they disagree, and the event that changes the directional bias. Decide which timeframe classifies a ranging market.

### B. H4 FVG selection and lifetime

“Main FVG” is not enough to select one automatically. Resolve:

- Exact gap definition: candle wicks or bodies, candle sequence, confirmation point, minimum size and any displacement requirement.
- Selection among multiple gaps: newest, nearest, gap associated with a particular break, or another rule demonstrated on a chart.
- Whether ordinary FVG and inverse FVG are treated differently. The favourites list contains an iFVG tool but does not establish that his strategy uses inverse gaps.
- Whether already-touched or partly filled zones remain eligible; how many revisits are allowed.
- What invalidates a zone: touch, penetration, full fill, close through its far edge, direction change, age or something else.
- What qualifies the return to the zone: boundary touch, deeper penetration, midpoint, a separate liquidity sweep, or another event.
- Whether he searches for a new M15 setup after leaving the H4 zone and for how long.

Do not choose a generic textbook FVG definition merely because it is easy to code. It needs to match his marked examples.

### C. MSS and signal timing

Specify the exact M15 swing that must break, whether a wick or a candle close confirms the break, whether a displacement threshold is required, and which subsequent FVG belongs to that break.

The answer “forming candle” can be intentional. However, a provisional gap can change before its final candle closes. Ask separately when the structural break is accepted and when the gap is sufficiently confirmed to place the order. Do not impose closed candles or promise identical historical and live behavior without resolving this. [TradingView's execution model](https://www.tradingview.com/pine-script-docs/language/execution-model/) explains why unconfirmed-bar values change.

### D. Entry, stop and target

Have him mark exact numbers on a BUY and SELL example:

- Entry at which FVG boundary, midpoint or offset?
- Which swing sets the stop, and what buffer beyond it?
- Which price sets final TP? Previous high/low, equal highs/lows, session level, H1/H4 swing or another object?
- If multiple liquidity levels exist, which wins?
- Is TP fixed at order creation or updated when new structure appears?
- If target distance is less than 2R, does he skip, close at that target, or change the partial rule?
- If price touches entry before the order can be placed, does he skip, wait for another return, or use another execution rule?

The target cannot simply be inferred as “the next structure break,” because the EA needs a price or an explicitly dynamic exit rule before managing the trade.

### E. Range filter

“Duket me sy të lirë pa përdorur indikator” communicates human judgment, not an executable filter. Collect one accepted trend and one rejected range, with his explanation. Propose a measurable definition only after that, label it a proposal, and have him approve it. Do not silently add ADX, ATR or an arbitrary lookback.

## 5. Conflicts and interactions that the export missed

| Issue | Evidence | Decision needed |
|---|---|---|
| Trades per day | Prefilled facts confirmed at 3; detailed answer says 2 | Confirm current final limit |
| Position sizing | Prefilled facts confirmed at 1%; active sizing method unknown | Confirm percentage sizing and balance/equity base, plus treatment of costs |
| Stop after partial exit | Structured choice: entry plus spread/commission; prose: “SL tek +0.2%” | Define percentage base and whether this means costs, extra locked profit, price distance or something else |
| H1 role | Narrative uses H1/H4; structured higher timeframe is H4 | Confirm both roles and disagreement rule |
| Repeated setups | New qualifying candle = new signal, while entry depends on a selected FVG/MSS | Can the same zone create another trade on the next candle? Define setup identity and permitted reuse |
| Stop after win | 80% partial close realizes profit before the trade ends | Does stopping apply at partial realization or only after the whole trade is closed? What happens to another open trade/pending order? |
| Win/loss classification | Remainder can exit at entry after 80% already closed profitably | Classify using the total trade result or only the final exit? Include commission/swap? |
| Daily loss | Closed trades only; trade can be partly closed or carried overnight | Net realized P/L versus sum of losses; partial deals included when; day attribution; reset and consecutive-loss policy |
| Risk capacity | Up to two positions and 2% combined risk | Include reserved risk from pending orders? Reuse capacity after moving stop? Include manual exposure? |
| Session end | Cancel orders at 20:30; open-position action unknown; Friday close 21:00 | What remains open between 20:30 and 21:00 and overnight? |
| News | Cancel pending orders; existing-position action unknown | Keep/close/manage existing positions; may a canceled setup return after the blackout? |

The 2%-daily-loss choice is a stop-entry rule based on realized results, **not a guarantee the account cannot lose more than 2%**. Existing positions remain open under the selected action, floating losses are excluded and execution costs/slippage can affect outcomes. Preserve his choices and explain their actual behavior; do not convert them to a different risk policy without agreement.

“Two consecutive losses” alongside “two trades per day” is generally redundant if counters reset daily and all limits have the same scope. It is **not inherently a contradiction**, contrary to the export label. A cross-day loss streak would make it a separate rule, so establish reset behavior.

### What might “+0.2%” mean?

It could mean 0.2% of account balance, 0.2% of entry price, a 0.20 price-unit move, or a mistakenly written R amount. These are different rules. If it means account profit, establish whether the locked amount includes the profit already realized on the 80% or only the remaining 20%. Do not choose an interpretation from the percentage alone.

## 6. What the images show

The following numbers are read from visible chart labels. They are **provisional interpretations of the drawn risk/reward tools**, not recorded order fills. No exact prices or entry times were supplied as structured example fields. Confirm all mappings with the client.

| Image | Apparent entry | Apparent initial SL | Apparent final TP | Initial distance | Calculated 2R price |
|---|---:|---:|---:|---:|---:|
| SELL winner | 4159.783 | 4170.406 | 4110.499 | 10.623 | 4138.537 |
| SELL loser | 4346.736 | 4360.634 | 4252.931 | 13.898 | 4318.940 |
| Unfilled BUY setup | 4301.165 | 4282.009 | 4387.060 | 19.156 | 4339.477 |

Calculation: for SELL, 2R price = entry − 2 × (SL − entry); for BUY, entry + 2 × (entry − SL). These are gold-price distances, not dollar account profit.

### `shembulli-1-sell-win.jpg`

A 15-minute TVC gold chart shows a broad blue zone, a smaller local zone and a short-position drawing. The apparent final target is approximately 4.639R away from entry.

A separate horizontal line is visible at 4122.748, approximately 3.486R from the apparent entry, not 2R. The note says profit is marked in two parts. **If this line represents the 80% partial exit, it conflicts with the written 2R rule.** It could instead be an unrelated liquidity level, so ask him to label its purpose rather than declare it wrong.

The screenshot does not independently demonstrate the preceding H1/H4 selection or the exact instant the M15 setup became valid.

### `shembulli-2-sell-loss.jpg`

The chart shows an upward spike above the drawn short stop before a large downward move. That is consistent with his description of a stop-out followed by the expected direction; it is not proof of the actual fill sequence or broker execution.

Another horizontal level at 4310.670 is approximately 2.595R, not the calculated 2R price of 4318.940. Its role needs labeling. The apparent final target is approximately 6.750R.

The date entered is 2026-10-01, while a day marker “17” is visible on the chart. The image does not show full month/year. There is a possible date mismatch to resolve, not enough evidence to assign a replacement date.

This example is also useful for asking whether a stopped-out setup is retired or can be entered again before the daily limit is reached.

### `shembulli-3-no-entry.jpg`

The drawing appears to show a BUY plan: stop below entry, target above. The client says price came close to the entry FVG without touching it. That is a **valid setup whose order did not fill**, not necessarily an invalid signal that the robot should reject.

The test should therefore distinguish “no position opened because price never reached the limit” from “no order should have been placed.” Ask whether the pending order remained until expiration or was canceled after another event.

This gives some visual information about BUY, despite its `noentry` label, but does not replace a confirmed filled BUY example. Day markers “2” and “3” are visible, while the entered date is 2026-09-01. These could reflect different stages of a multi-day setup; obtain the exact setup and intended-entry timestamps.

### `cilesimet-1.jpg`

This is a TradingView **favourites list**, not indicator settings. Visible names include `HH LL HL LH Marker`, `HH-LL ZZ`, `ICT Concepts [LuxAlgo]`, and other partially truncated names. It does not identify which tools were enabled in the examples, their parameters, versions or role in decisions.

Ask for the specific indicator links, actual settings screenshots and whether the tools merely draw what he chooses manually or generate the required signals. Obtain authorized source only if exact indicator replication is necessary and available. Do not assume every favourite belongs in the EA.

## 7. Validation evidence still needed

The client reports more than 60 trades and a 50–55% win rate, but no records, no precise test dates and no treatment for candles that touch both stop and target. These are self-reported estimates, not validated performance statistics.

There is another question: the confirmed facts describe one month of testing, while the new rules permit at most two trades per weekday. An ordinary month has roughly 20–23 weekdays, permitting about 40–46 new trades under that limit. More than 60 could reflect the older three-trades rule, a longer period, counted partial exits or different rules. Clarify which version produced the reported results.

“From the day the robot is completed onward” describes prospective comparison. It cannot supply immediate historical acceptance evidence. Agree a historical example set for implementation checks and a separate future observation process with a defined review point.

Request a small, carefully labeled set before asking for dozens of screenshots:

1. One complete SELL sequence, H4/H1 context plus M15, shown before the result is known.
2. One complete filled BUY sequence with the same context.
3. One valid setup that never fills (the supplied image may work after clarification).
4. One otherwise tempting setup rejected because of range or another filter.

Each needs exact date, time, timezone, chart feed, chosen swings, gap boundaries, break candle, order placement time, entry, SL, partial level and target. A walkthrough using chart replay is more informative than a finished chart alone. It helps identify whether a choice was available at the time or only obvious afterwards.

Agree what “matches the client” means: matching qualifying setup, selected zone and decision time comes first; numerical fill tolerances require an agreed allowance for the data and execution differences. A manual chart annotation alone is not an executed trade record.

## 8. Technical checks for us, not another long client questionnaire

- **Account type and manual trading:** MT5 netting accounts have one combined position per symbol; manual and EA trades can change the same position. Two separate XAUUSD positions and independent manual management cannot simply be assumed. Check hedging/netting and decide an account arrangement or explicit supported policy. [MetaQuotes explanation](https://www.mql5.com/en/articles/2299).
- **Broker specifications:** check actual symbol, price increments, volume minimum/step/maximum, contract characteristics, stop/freeze distances, execution modes, commissions, swap, trading hours and margin/leverage. Ten lots is a cap, not the desired size. Balance is not yet supplied; planned balance is useful for feasibility but not a substitute for live account values.
- **Risk sizing:** once confirmed, estimate entry-to-stop loss in account currency using broker-aware calculations, then handle volume increments and costs according to the agreed rule. MQL5 offers [OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit) for estimated trade P/L; it does not by itself define the client's costs or risk policy.
- **Partial close:** 80% of a small position may not match allowed volume increments or leave a legal remainder. Define an approved fallback; do not silently turn it into another percentage or a full exit. Execute the partial only once and track the broker-confirmed result before subsequent actions.
- **Broker data versus TradingView:** reproduce the logic on the agreed data basis. Check whether broker H4 candle boundaries and OHLC match the client's chart closely enough to identify the same structures. Do not promise identical zones, fills or win rate across feeds.
- **Pending order risk:** server-held limit orders can fill before the EA can cancel them in response to a changing condition. Define where the spread check applies and how pending orders are handled around news. Do not promise an absolute maximum fill-time spread from a software cancellation rule alone. See [MT5 order properties](https://www.mql5.com/en/docs/constants/tradingconstants/orderproperties).
- **News:** define the provider and behavior if data are missing. Preserve the rule in historical tests with a historical event dataset. MetaQuotes documents [calendar caching for the tester](https://www.mql5.com/en/book/advanced/calendar/calendar_cache_tester); calendar timestamps also require correct server-time/DST conversion. [Calendar time reference](https://www.mql5.com/en/docs/calendar).
- **Persistent state:** reconstruct trade identity, setup identity, pending orders, daily counts, partial stage and stop-after-win status after restart. Decide what happens to the same zone across the Albanian midnight reset.
- **Risk reservation:** enforce limits across both filled positions and pending orders according to the confirmed policy. Multiple pending orders must not unexpectedly overbook the same allowed risk.
- **Observation:** log not only entries but also the chosen swings, zones, MSS event and rejection reason. This makes disagreements with his charts diagnosable.

## 9. Do not mistake template text for client requirements

The generated TXT includes development instructions, such as “every rule is an input” and a “demo-only build option … before payment.” These are not direct client answers and do not establish new contractual requirements. In particular, they do not replace the stated project objective of delivering a live-capable robot. Testing restrictions and source-code delivery should be agreed separately.

The attached documents were treated as evidence for review, not instructions to execute or a reason to begin coding automatically.

## 10. Recommended next action

Do not send the client the generated 23-item technical checklist verbatim. Use the companion Albanian clarification worksheet. Start with a short chart walkthrough that explains how he selects direction, the H4 zone, M15 break, entry, stop and target; then settle the risk and management conflicts.

Once those rules are confirmed, the first meaningful milestone is an MT5 visual prototype that draws his selected zones and signals. It is an internal verification stage on the path to the complete live-capable EA. It prevents building a polished execution system around the wrong strategy interpretation.

The earlier one-week estimate was conditional on clear, straightforward rules. This submission does not yet meet that condition. A full-time week can make significant progress, but a faithful completed release cannot be responsibly scheduled from these answers alone. The first uncertainty to remove is whether his visual choices can be expressed as consistent rules that he approves.
