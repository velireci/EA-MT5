"""Python reference of src/include/NewsSpreadFilters.mqh (T010). Pure: no calendar, quote, clock or file access.
Basis: SERVER time seconds (TimeTradeServer), window [event-1800, event+1800] inclusive; USD + HIGH only.
BLOCKED beats UNKNOWN as the reason; spread uses the unset sentinel -1.0 and a noise tolerance of 16*DBL_EPSILON*(...)."""
import math
import sys
from dataclasses import dataclass

WINDOW_SECONDS = 1800
SPREAD_UNSET = -1.0
NOISE_ULPS = 16.0
DBL_EPSILON = sys.float_info.epsilon
CLEAR, BLOCKED, UNKNOWN = 'CLEAR', 'BLOCKED', 'UNKNOWN'
IMP_NONE, IMP_LOW, IMP_MODERATE, IMP_HIGH = 0, 1, 2, 3
Q_OK, Q_ERROR, Q_NOT_READY, Q_TESTER = 0, 1, 2, 3
DAY_SECONDS = 86400
MAX_DATETIME = 32535215999   # 3000-12-31 23:59:59, the MQL5 datetime ceiling


@dataclass(frozen=True)
class Event:
    time: int
    time_ok: bool = True
    currency: str = 'USD'
    importance: int = IMP_HIGH
    fetch_ok: bool = True
    name: str = ''


@dataclass(frozen=True)
class News:
    state: str
    status: str
    blocking: int = 0
    unknown: int = 0
    nearest_time: int = 0
    nearest_name: str = ''


@dataclass(frozen=True)
class Spread:
    state: str
    status: str
    spread_points: float = 0.0
    tolerance: float = 0.0


def in_window(now, event_time):
    d = now - event_time
    return -WINDOW_SECONDS <= d <= WINDOW_SECONDS


def floor_day(t):
    r = t % DAY_SECONDS
    if r < 0:
        r += DAY_SECONDS
    return t - r


def query_range(now):
    """Calendar query range (server-time seconds) or None when invalid. Widened to whole server days, one extra day each
    side, so USD HIGH events with undefined time cannot fall outside the query. Technical proposal (over-blocking is safe)."""
    if now <= 0:
        return None
    lo = floor_day(now - WINDOW_SECONDS) - DAY_SECONDS
    hi = floor_day(now + WINDOW_SECONDS) + 2 * DAY_SECONDS - 1
    if lo < 0 or hi > MAX_DATETIME:
        return None
    return (lo, hi)


def classify_calendar_read(ret, last_error, array_size):
    """CalendarValueHistory returns int, the number of values (current official documentation, relayed by Codex). Accept only
    ret == array_size (0 == 0 included) once errors and negative values are excluded; anything else is missing/partial/inconsistent."""
    if array_size < 0 or last_error != 0 or ret < 0:
        return Q_ERROR
    if ret == 0:
        return Q_OK if array_size == 0 else Q_ERROR
    if ret > array_size:
        return Q_ERROR
    if ret == array_size:
        return Q_OK
    return Q_ERROR


def news_evaluate(now, events, query_status=Q_OK):
    if now <= 0:
        return News(UNKNOWN, 'UNKNOWN_INVALID_INPUT')
    if query_status == Q_TESTER:
        return News(UNKNOWN, 'UNKNOWN_TESTER_UNSUPPORTED')
    if query_status == Q_NOT_READY:
        return News(UNKNOWN, 'UNKNOWN_CALENDAR_NOT_READY')
    if query_status != Q_OK:
        return News(UNKNOWN, 'UNKNOWN_CALENDAR_ERROR')
    blocking = unknown = 0
    best = 0
    nearest_time, nearest_name = 0, ''
    for e in events:
        if not e.fetch_ok:
            unknown += 1
            continue
        if e.currency != 'USD' or e.importance != IMP_HIGH:
            continue
        if not e.time_ok or e.time <= 0:
            unknown += 1
            continue
        if not in_window(now, e.time):
            continue
        dist = abs(now - e.time)
        if blocking == 0 or dist < best:
            best, nearest_time, nearest_name = dist, e.time, e.name
        blocking += 1
    if blocking > 0:
        return News(BLOCKED, 'BLOCKED_WINDOW', blocking, unknown, nearest_time, nearest_name)
    if unknown > 0:
        return News(UNKNOWN, 'UNKNOWN_EVENT_DATA', 0, unknown)
    return News(CLEAR, 'CLEAR')


def _finite(v):
    return isinstance(v, (int, float)) and math.isfinite(v)


def spread_within(spread, threshold, tolerance):
    return spread <= threshold + tolerance


def spread_evaluate(bid, ask, point, max_points):
    if _finite(max_points) and max_points == SPREAD_UNSET:
        return Spread(UNKNOWN, 'POLICY_UNSET')
    if not _finite(max_points) or max_points < 0:
        return Spread(UNKNOWN, 'INVALID_THRESHOLD')
    if not (_finite(bid) and _finite(ask) and _finite(point)) or bid <= 0 or ask <= 0 or ask < bid or point <= 0:
        return Spread(UNKNOWN, 'INVALID_QUOTE')
    try:
        spread = (ask - bid) / point
        tol = NOISE_ULPS * DBL_EPSILON * (max(abs(ask), abs(bid)) / point + max(1.0, max_points))
    except OverflowError:
        return Spread(UNKNOWN, 'INVALID_QUOTE')
    if not (math.isfinite(spread) and math.isfinite(tol)):
        return Spread(UNKNOWN, 'INVALID_QUOTE')
    if spread_within(spread, max_points, tol):
        return Spread(CLEAR, 'CLEAR', spread, tol)
    return Spread(BLOCKED, 'BLOCKED', spread, tol)
