# T010 - USD high-impact news filter and spread filter (preview integration)

Owner-approved. Base 8c562fe. Scope: two filters for the EXISTING read-only preview EA only. No orders, no cancellations, no position handling, no persistence, no monitoring (one snapshot at initialization). T001-T009 rules, modules and tests untouched; the only existing file edited is src/XauUsdTradePreview.mq5 (v1.03).

## Contract
NEWS (pure: src/include/NewsSpreadFilters.mqh, NF_NewsEvaluate)
- Relevant = currency USD and importance HIGH. Window [event-1800 s, event+1800 s], both boundaries included; one second outside does not block.
- Time basis: SERVER time. `now` = TimeTradeServer(); calendar value time compared in the same sense. Not UTC, not Tirane (T009 keeps its own UTC basis).
- BLOCKED: any relevant event in the window (nearest event time and name reported).
- UNKNOWN (never CLEAR): query error/exception, calendar not ready (terminal not connected), Strategy Tester (automatic source unsupported), an event record or country that cannot be fetched (currency/importance unknowable), a USD HIGH event with undefined time (time 0, or time mode not DATETIME: all-day, no-time, tentative), invalid now.
- CLEAR only for a successful query with no blocking and no unknown event. Empty result without error is CLEAR.
- Priority: BLOCKED over UNKNOWN as the reported status (more informative); both end as a block in the T007 permit. Other currencies or non-HIGH importance never block (even with undefined time).
- Thin reader ReadUsdCalendar in the EA: CalendarValueHistory(now-1800, now+1800, NULL, "USD"), then CalendarEventById and CalendarCountryById per value; query failure -> NF_Q_ERROR.

SPREAD (pure: NF_SpreadEvaluate)
- spread_points = (Ask-Bid)/point from the SAME quote the preview already reads.
- Maximum = input InpMaxSpreadPoints, no default value chosen. Sentinel -1.0 = UNSET (0 is a legal threshold: only zero spread passes, so 0 cannot mean unset; same convention as T007 limits). Statuses: POLICY_UNSET, INVALID_THRESHOLD (NaN, inf, any other negative), INVALID_QUOTE (non-finite, bid<=0, ask<=0, ask<bid, point<=0, overflow), BLOCKED (spread > threshold), CLEAR (<= threshold; ask==bid is valid).
- Threshold is checked before the quote. Noise tolerance 16*DBL_EPSILON*(max(ask,bid)/point + max(1,threshold)): about 7e-10 points at 2000/0.01; a real 0.001-point excess blocks. Realistic quotes such as 2000.00/2000.20 compute to 20.000000000004547 and are allowed at 20.
- Map to the permit (unchanged T007): CLEAR/BLOCKED as is; POLICY_UNSET, INVALID_THRESHOLD, INVALID_QUOTE -> UNKNOWN (permit reason SPREAD_UNKNOWN). The permit has no spread POLICY_UNSET reason, so the filter status carries the detail in the log and panel. Convention for review.

Integration: InpNewsSource (NEWS_SRC_MANUAL default | NEWS_SRC_CALENDAR_AUTO), InpSpreadSource (SPREAD_SRC_MANUAL default | SPREAD_SRC_QUOTE_AUTO). MANUAL keeps the old inputs and behaviour exactly. Results only fill snap.news_state / snap.spread_state; log lines "T010 NEWS ..." and "T010 SPREAD ...", panel lines NEWS/SPREAD with source and status.

## Documentation verification
NOT verified online: www.mql5.com was unreachable from the build sandbox (proxy 403). Signatures and semantics below are from memory and MUST be checked by Codex/owner against the official docs: CalendarValueHistory(MqlCalendarValue &values[], datetime from, datetime to=0, const string country_code=NULL, const string currency=NULL) returns bool; CalendarEventById(ulong, MqlCalendarEvent&) bool; CalendarCountryById(ulong, MqlCalendarCountry&) bool; MqlCalendarEvent fields importance, time_mode, country_id, name; time modes DATETIME/NOTIME/ALLDAY/TENTATIVE; calendar times in trade-server time. Compile will confirm names/types, not the time semantics.

## NOT decided here
- Action after a spread block (wait, cancel pending, skip setup).
- What to do with open positions at news and at the normal session end.
- Spread threshold value (needs measurement on the target XAUUSD.r feed).
- Whether an empty history returns true or false with an error code on the real terminal (a false return is treated as UNKNOWN, fail-safe).
- Calendar history / Strategy Tester source (tester is UNKNOWN/BLOCK).
- Pending-cancel before news (T007 cancel decision exists; not wired).
