# T009 — Albania session policy and day identity

Owner authorised continuing while Claude rate limited; Codex sole writer. Base4b6a5b5. Scope: confirmed Mon–Fri 00:00–20:30 Europe/Tirane with DST; Friday21:00 close request; daily key/reset boundary at local midnight. Pure UTC input, no server-offset guessing. Configurable minute boundaries and weekday mask (defaults62), validated non-overnight window. Year support1996–2099 follows current EU recurrence; later law changes require update, unsupported years block.

Session [start,end) and Friday cutoff inclusive are explicit technical boundary conventions. Friday close is a flag/request, never API action. Normal session end cancels pending eligibility, not open positions. The Friday flag is due only Friday at/after21:00; weekend catchup/persistence are not silently added. DayChanged only accepts monotonic UTC and compares local day keys.

Pure MQL/Python module with independent zoneinfo comparison and hand boundary tests, MQL test script. Optional opt-in preview session source uses TimeGMT outside tester, derived from PC clock; logs UTC/local/day for owner validation. Manual source remains default. Historical/replay must supply true UTC to pure helper; never use tester TimeGMT as UTC. No news, daily accounting, orders or positions touched. Other preview gates stay unknown/external.

Plan: failing boundary/DST tests → pure module and fixtures → optional preview adapter → focused tests/compile/review → publish/checklist → owner MT5. Source https://data.iana.org/time-zones/tzdb/europe (Europe/Tirane and EU rules); https://www.mql5.com/en/docs/dateandtime/timegmt .
