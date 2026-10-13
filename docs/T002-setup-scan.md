# T002 setup scan - diagnostic script (instructions)

File: `src/tests/T002_SetupScan.mq5`. Purpose: finish the T002 visual check by finding, in the H4 history of the chart symbol, moments at which the proposed T002 model would show an ACTIVE setup, so the owner can open exactly those moments with the EA's historical mode.
Status when written: NOT compiled and NOT run by its author (no MetaEditor available). Any compile or run result must be attributed to whoever produced it. The script uses the existing T002 functions unchanged; the T002 algorithm and the existing `src/` and `tools/` files were not modified. It contains no trading API and reads no live price.
All rules shown are PROPOSED (T002, client validation pending). A hit is not a trading signal and not a client-confirmed setup.

## What counts as a hit
At a moment, all of these hold, using only closed H4 bars up to that moment:
- direction BULLISH or BEARISH;
- structural interval VALID;
- ERL not TAKEN (UNTOUCHED; TAKEN is judged on closed bars only);
- at least one selectable IRL candidate (`H4SelectIrl` > 0);
- `H4SetupActive` is true.

## How a moment is built (matches the EA's historical mode)
- Moment k is the close of closed H4 bar k: as-of time = open(k) + 4 h, in broker/server time.
- The window is the newest `InpLookbackBars` closed bars up to bar k. No bar after k is copied into the window.
- The price for the IRL selection is the close of bar k, never a live price.
- Left/Right/Lookback use the same clamps as the EA (1..10, 1..10, 50..1000).
- Only full windows are used: the first `InpLookbackBars - 1` bars serve only as history, so a moment is evaluated only when a complete window exists.
- Consecutive hits are grouped into a run. The first moment of each run is listed in full, with the run length and its last as-of time; up to `InpMaxReport` runs are listed, newest first. Many consecutive H4 bars usually show the same setup, which is why runs are used.

## Install and run
1. Copy the whole repository `src/` folder to `<terminal data folder>/MQL5/Scripts/velo_src/` so that `MQL5/Scripts/velo_src/tests/T002_SetupScan.mq5` and `MQL5/Scripts/velo_src/include/H4Structure.mqh` sit side by side (the include is relative to the script). This layout is not tested in MT5.
2. Compile `T002_SetupScan.mq5` in MetaEditor and note every warning. It is a script (it has `OnStart`), so it goes under Scripts, not Experts.
3. Open an H4 chart of the symbol (XAUUSD on the test account; the Tauro symbol is not confirmed), let the history load, and drag the script onto the chart. Inputs: `InpLeftBars=2`, `InpRightBars=2`, `InpLookbackBars=300` (set them equal to the EA's inputs), `InpScanBars` (newest closed bars used as moments, default 2000; cost grows with it), `InpMaxReport` (default 5).
4. Read the Experts log lines starting with `T002 SETUP SCAN` / `T002 SCAN RESULT`.

## What the log shows
- The history actually copied (count, first and last bar open time) and a note if it is shorter than requested.
- `Searched N moments (as-of A to B)` and a cumulative funnel: trending direction, + valid interval, + ERL not TAKEN, + selectable IRL, + `H4SetupActive`.
- If nothing qualifies, a clear line `ZERO moments found` with the number of moments searched; if the history is too short or the copy fails, `NO RESULT` / `ZERO moments evaluated` with the reason.
- For each listed run: the as-of time (server time), the open time of the last closed bar, the price used, direction, interval H and L with the time it became known, ERL price and state, the number of selectable candidates, the nearest candidate (ID, bounds, FRESH/TOUCHED, inside or ahead of the price), the direction evidence (the swings that decide it), the run length, and the exact EA inputs to reproduce it.

## Reproduce a moment in the EA
Attach `XauUsdH4Map` to the same symbol with `InpAsOfTime` = the printed as-of time (broker/server time, as shown on the MT5 time axis; not UTC, not TradingView time), and the same `InpLeftBars`, `InpRightBars`, `InpLookbackBars`. The EA's panel must then show HISTORICAL REVIEW, the same direction, interval, ERL and nearest IRL, and "price used" equal to the close printed by the script. The EA's chart needs history at least as deep as the window; a shorter history gives the EA's PARTIAL/INSUFFICIENT states instead. A difference between the two is a finding to report with both logs, not something to explain away.

## Limits
- It scans the chart symbol only, the H4 series only, one moment per H4 close. It says nothing about M15, entries, targets or the 2R policy.
- A hit means "the proposed model shows an active setup here"; whether the client would choose the same zone, level or direction is the visual validation that is still open.
- TAKEN and all states are judged on closed bars, so they can lag the live price by up to one H4 bar.
- The broker's server time and candle boundaries may differ from the client's TradingView chart; no match is assumed.
- Nothing in this file shows that the script compiles or runs; that evidence is still to come.
