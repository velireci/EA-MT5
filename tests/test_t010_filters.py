"""Unit tests for the T010 pure news/spread filter reference. Run: python3 -m unittest test_t010_filters (from tests/).
Expected values come from tests/t010_filters_fixtures.py (hand-derived). They prove the CONTRACT of the pure decision only; the
live MT5 calendar reader, the tester behaviour and the broker quote are NOT exercised and stay UNVERIFIED."""
import os
import re
import sys
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t007_planning_reference as p7  # noqa: E402
import t010_filters_reference as ref  # noqa: E402
from t007_planning_fixtures import PLAN_CASES  # noqa: E402
from t010_filters_fixtures import (CLASSIFY_CASES, COVERAGE_CASES, D, NEWS_CASES, NOW, RANGE_CASES, SPREAD_CASES,  # noqa: E402
                                   emit_mql, real)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF_PATH = os.path.join(ROOT, 'tests', 't010_filters_reference.py')


def events_of(m, case):
    out = []
    for delta, time_ok, cur, imp, fetch_ok, name in case['events']:
        out.append(m.Event(time=0 if delta is None else case['now'] + delta, time_ok=time_ok, currency=cur,
                           importance=imp, fetch_ok=fetch_ok, name=name))
    return out


def news_failures(m):
    bad = []
    for c in NEWS_CASES:
        r = m.news_evaluate(c['now'], events_of(m, c), c['q'])
        want_near = 0 if c['nearest'] is None else c['now'] + c['nearest']
        got = (r.state, r.status, r.blocking, r.unknown, r.nearest_time, r.nearest_name)
        if got != (c['state'], c['status'], c['blocking'], c['unknown'], want_near, c['nname']):
            bad.append(c['name'])
    return bad


def spread_failures(m):
    bad = []
    for c in SPREAD_CASES:
        r = m.spread_evaluate(real(c['bid']), real(c['ask']), real(c['point']), real(c['mx']))
        if (r.state, r.status) != (c['state'], c['status']):
            bad.append(c['name'])
    return bad


def classify_failures(m):
    return [c['name'] for c in CLASSIFY_CASES if m.classify_calendar_read(c['ret'], c['err'], c['size']) != c['want']]


def range_failures(m):
    return ['R_' + c['name'] for c in RANGE_CASES if m.query_range(c['now']) != c['want']]


def coverage_failures(m):
    """Fake calendar keyed by absolute anchor: only events inside the query range are 'returned', then the pure rule decides."""
    bad = []
    for c in COVERAGE_CASES:
        rg = m.query_range(NOW)
        evs = [m.Event(time=D + a, time_ok=ok, currency=cur, importance=imp, name=nm) for a, ok, cur, imp, nm in c['evs']]
        got = [e for e in evs if rg is not None and rg[0] <= e.time <= rg[1]]
        r = m.news_evaluate(NOW, got, m.Q_OK)
        if (r.state, r.status) != (c['state'], c['status']):
            bad.append(c['name'])
    return bad


def load_mutant(old, new):
    with open(REF_PATH, encoding='ascii') as fh:
        src = fh.read()
    assert src.count(old) == 1, (old, src.count(old))
    ns = {'__name__': 't010_mutant'}
    exec(compile(src.replace(old, new), 't010_mutant', 'exec'), ns)
    return types.SimpleNamespace(**ns)


class NewsTests(unittest.TestCase):
    def test_every_fixture_row(self):
        self.assertEqual(news_failures(ref), [])

    def test_boundaries_in_seconds(self):
        # event at NOW+d : now is d seconds before the event (d>0) or -d seconds after it
        for d, blocks in ((1800, True), (1799, True), (1801, False), (-1800, True), (-1799, True), (-1801, False), (0, True)):
            r = ref.news_evaluate(NOW, [ref.Event(time=NOW + d)])
            self.assertEqual(r.state, ref.BLOCKED if blocks else ref.CLEAR, d)

    def test_filters_by_currency_and_importance(self):
        for cur, imp, blocks in (('USD', 3, True), ('EUR', 3, False), ('GBP', 3, False), ('USD', 2, False), ('USD', 1, False),
                                 ('USD', 0, False)):
            r = ref.news_evaluate(NOW, [ref.Event(time=NOW, currency=cur, importance=imp)])
            self.assertEqual(r.state, ref.BLOCKED if blocks else ref.CLEAR, (cur, imp))

    def test_unknown_is_never_clear(self):
        for q in (ref.Q_ERROR, ref.Q_NOT_READY, ref.Q_TESTER, 7):
            self.assertEqual(ref.news_evaluate(NOW, [], q).state, ref.UNKNOWN)
        self.assertEqual(ref.news_evaluate(NOW, [ref.Event(time=NOW + 9000, fetch_ok=False)]).state, ref.UNKNOWN)
        self.assertEqual(ref.news_evaluate(NOW, [ref.Event(time=0)]).state, ref.UNKNOWN)
        self.assertEqual(ref.news_evaluate(NOW, []).state, ref.CLEAR)

    def test_input_order_does_not_change_state(self):
        evs = [ref.Event(time=NOW + 7200), ref.Event(time=NOW, fetch_ok=False), ref.Event(time=NOW + 600, name='A')]
        a = ref.news_evaluate(NOW, evs)
        b = ref.news_evaluate(NOW, list(reversed(evs)))
        self.assertEqual((a.state, a.blocking, a.unknown), (b.state, b.blocking, b.unknown))


class CalendarReadTests(unittest.TestCase):
    def test_classifier_rows(self):
        self.assertEqual(classify_failures(ref), [])

    def test_range_rows(self):
        self.assertEqual(range_failures(ref), [])

    def test_hand_computed_ranges(self):
        self.assertEqual(D % 86400, 0)
        self.assertEqual(NOW - D, 28800)
        self.assertEqual(ref.query_range(NOW), (1799884800, 1800143999))
        self.assertEqual(ref.query_range(D), (1799798400, 1800143999))

    def test_window_is_inside_the_range_for_every_second_of_a_day(self):
        for now in range(D - 90000, D + 90000, 37):
            lo, hi = ref.query_range(now)
            self.assertLess(lo, now - 1800 + 1)
            self.assertGreater(hi, now + 1800 - 1)
            self.assertEqual(lo % 86400, 0)
            self.assertEqual((hi + 1) % 86400, 0)

    def test_coverage_rows(self):
        self.assertEqual(coverage_failures(ref), [])

    def test_undefined_time_outside_window_is_unknown_not_clear(self):
        r = ref.news_evaluate(NOW, [ref.Event(time=D, time_ok=False)])
        self.assertEqual(r.state, ref.UNKNOWN)
        # the same event with a defined time outside the window does not block
        self.assertEqual(ref.news_evaluate(NOW, [ref.Event(time=D)]).state, ref.CLEAR)

    def test_only_a_count_equal_to_the_array_size_is_accepted(self):
        # int per the official documentation: ret=1 with N>1 values is a partial/inconsistent read, not a bool true
        for n in (2, 3, 5):
            self.assertEqual(ref.classify_calendar_read(1, 0, n), ref.Q_ERROR)
            self.assertEqual(ref.classify_calendar_read(n, 0, n), ref.Q_OK)


class SpreadTests(unittest.TestCase):
    def test_every_fixture_row(self):
        self.assertEqual(spread_failures(ref), [])

    def test_noise_versus_real_excess(self):
        r = ref.spread_evaluate(1.0, 21.000000000000004, 1.0, 20.0)
        self.assertEqual(r.spread_points, 20.000000000000004)
        self.assertGreater(r.spread_points, 20.0)
        self.assertEqual(r.state, ref.CLEAR)
        self.assertGreater(ref.spread_evaluate(2000.0, 2000.20001, .01, 20.0).spread_points, 20.0009)
        self.assertEqual(ref.spread_evaluate(2000.0, 2000.20001, .01, 20.0).state, ref.BLOCKED)
        self.assertGreater(ref.spread_evaluate(2000.0, 2000.2, .01, 20.0).spread_points, 20.0)   # binary noise only
        # the tolerance is far below a real 0.001 point at realistic prices
        self.assertLess(ref.spread_evaluate(2000.0, 2000.2, .01, 20.0).tolerance, 1e-6)

    def test_threshold_is_exactly_the_documented_sentinel(self):
        self.assertEqual(ref.SPREAD_UNSET, -1.0)
        self.assertEqual(ref.spread_evaluate(2000.0, 2000.1, .01, -1.0).status, 'POLICY_UNSET')
        self.assertEqual(ref.spread_evaluate(2000.0, 2000.1, .01, -1.0000001).status, 'INVALID_THRESHOLD')
        self.assertEqual(ref.spread_evaluate(2000.0, 2000.0, .01, 0.0).state, ref.CLEAR)

    def test_exactly_representable_equal_and_above(self):
        self.assertEqual(ref.spread_evaluate(1000.0, 1020.0, 1.0, 20.0).state, ref.CLEAR)
        self.assertEqual(ref.spread_evaluate(1000.0, 1020.5, 1.0, 20.0).state, ref.BLOCKED)
        self.assertEqual(ref.spread_evaluate(1000.0, 1019.5, 1.0, 20.0).state, ref.CLEAR)


class PermitIntegrationTests(unittest.TestCase):
    """Filter result -> T007 snapshot -> T007 permit (unchanged). BUY_BASIC with arbitrary test limits."""

    @staticmethod
    def plan():
        sid, setup, d, e, s, t, budget, tv, sym, quote, vol = next(c for c in PLAN_CASES if c['name'] == 'BUY_BASIC')['args']
        bid, ask = quote if quote else (None, None)
        return p7.build_plan(sid, setup, d, e, s, t, budget, tv, sym[0], sym[1], sym[2], sym[3], bid, ask, *vol)

    def permit(self, news_state, spread_state):
        snap = p7.Snapshot(news_state=news_state, spread_state=spread_state)
        lim = p7.Limits(max_positions=3, max_trades_per_day=5, combined_risk_cap=5000.0)
        return p7.check_permit(self.plan(), snap, lim, p7.Registry.new(4))

    def test_clear_clear_allows(self):
        n = ref.news_evaluate(NOW, [])
        s = ref.spread_evaluate(2000.0, 2000.1, .01, 20.0)
        p = self.permit(n.state, s.state)
        self.assertEqual((p.decision, p.reasons), ('ALLOW', ()))

    def test_news_states_map_to_permit_reasons(self):
        blocked = ref.news_evaluate(NOW, [ref.Event(time=NOW)])
        unknown = ref.news_evaluate(NOW, [], ref.Q_TESTER)
        self.assertEqual(self.permit(blocked.state, 'CLEAR').reasons, ('NEWS_BLOCK',))
        self.assertEqual(self.permit(unknown.state, 'CLEAR').reasons, ('NEWS_UNKNOWN',))

    def test_spread_states_map_to_permit_reasons(self):
        cases = ((2000.0, 2000.5, .01, 20.0, 'SPREAD_BLOCK'), (2000.0, 2000.1, .01, -1.0, 'SPREAD_UNKNOWN'),
                 (2000.0, 2000.1, .01, -3.0, 'SPREAD_UNKNOWN'), (0.0, 2000.1, .01, 20.0, 'SPREAD_UNKNOWN'))
        for bid, ask, pt, mx, want in cases:
            s = ref.spread_evaluate(bid, ask, pt, mx)
            self.assertEqual(self.permit('CLEAR', s.state).reasons, (want,), (bid, ask, mx))

    def test_both_filters_block_together_in_permit_order(self):
        p = self.permit('BLOCKED', 'UNKNOWN')
        self.assertEqual((p.decision, p.reasons), ('BLOCK', ('NEWS_BLOCK', 'SPREAD_UNKNOWN')))


def all_failures(m):
    return (news_failures(m) + spread_failures(m) + classify_failures(m) + range_failures(m) + coverage_failures(m))


# Not mutated (equivalent mutants): the explicit array_size<0 and now<=0 guards are defense in depth; ret/size and the from<0
# check already reject the same inputs, so removing the guard changes no result.
MUTANTS = {
    'boundary made exclusive': ("    return -WINDOW_SECONDS <= d <= WINDOW_SECONDS", "    return -WINDOW_SECONDS < d < WINDOW_SECONDS",
                                'BEFORE_1800_INCLUDED'),
    'upper boundary made exclusive': ("    return -WINDOW_SECONDS <= d <= WINDOW_SECONDS", "    return -WINDOW_SECONDS <= d < WINDOW_SECONDS",
                                      'AFTER_1800_INCLUDED'),
    'window widened by one second': ("    return -WINDOW_SECONDS <= d <= WINDOW_SECONDS", "    return -WINDOW_SECONDS - 1 <= d <= WINDOW_SECONDS + 1",
                                     'BEFORE_1801_OUTSIDE'),
    'currency ignored': ("        if e.currency != 'USD' or e.importance != IMP_HIGH:", "        if e.importance != IMP_HIGH:",
                         'EUR_HIGH_IGNORED'),
    'importance ignored': ("        if e.currency != 'USD' or e.importance != IMP_HIGH:", "        if e.currency != 'USD':",
                           'USD_MEDIUM_IGNORED'),
    'failed fetch treated as clear': ("        if not e.fetch_ok:\n            unknown += 1\n            continue",
                                      "        if not e.fetch_ok:\n            continue", 'FETCH_FAILED_ALONE'),
    'undefined time treated as clear': ("        if not e.time_ok or e.time <= 0:\n            unknown += 1\n            continue",
                                        "        if not e.time_ok or e.time <= 0:\n            continue", 'TIME_ZERO'),
    'unknown never reported': ("    if unknown > 0:\n        return News(UNKNOWN", "    if False:\n        return News(UNKNOWN",
                               'FAR_AND_UNKNOWN'),
    'tester guard removed': ("    if query_status == Q_TESTER:\n        return News(UNKNOWN, 'UNKNOWN_TESTER_UNSUPPORTED')\n", "",
                             'TESTER_UNSUPPORTED'),
    'query error ignored': ("    if query_status != Q_OK:\n", "    if False:\n", 'QUERY_ERROR'),
    'unknown beats block': ("    if blocking > 0:\n        return News(BLOCKED", "    if blocking > 0 and unknown == 0:\n        return News(BLOCKED",
                            'UNKNOWN_AND_BLOCK_BLOCK_WINS'),
    'minus one accepted by the classifier': ("    if array_size < 0 or last_error != 0 or ret < 0:\n        return Q_ERROR\n",
                                             "    if array_size < 0 or last_error != 0:\n        return Q_ERROR\n    if ret < 0:\n        return Q_OK\n",
                                             'NEGATIVE_RET'),
    'read error ignored by the classifier': ("    if array_size < 0 or last_error != 0 or ret < 0:", "    if array_size < 0 or ret < 0:",
                                             'ZERO_RET_WITH_ERROR'),
    'ret above size accepted': ("    if ret > array_size:\n        return Q_ERROR\n    if ret == array_size:",
                                "    if ret >= array_size:", 'RET_ABOVE_SIZE_PARTIAL'),
    'ret below size accepted': ("    if ret == array_size:", "    if ret >= 0:", 'RET_BELOW_SIZE_PARTIAL'),
    'bool-compat exception re-added (ret 1 with many values)': ("    if ret == array_size:", "    if ret == array_size or ret == 1:",
                                                                'RET_ONE_BUT_THREE_VALUES'),
    'classifier accepts everything': ("    if ret > array_size:\n        return Q_ERROR\n    if ret == array_size:\n        return Q_OK\n    return Q_ERROR",
                                      "    return Q_OK", 'RET_ABOVE_SIZE_PARTIAL'),
    'zero ret with values accepted': ("return Q_OK if array_size == 0 else Q_ERROR", "return Q_OK", 'ZERO_RET_BUT_VALUES'),
    'range narrowed back to now +-1800': ("    lo = floor_day(now - WINDOW_SECONDS) - DAY_SECONDS\n    hi = floor_day(now + WINDOW_SECONDS) + 2 * DAY_SECONDS - 1",
                                          "    lo = now - WINDOW_SECONDS\n    hi = now + WINDOW_SECONDS", 'COV_USD_HIGH_UNDEFINED_SAME_DAY_OUTSIDE_WINDOW'),
    'range without the extra day before': ("floor_day(now - WINDOW_SECONDS) - DAY_SECONDS", "floor_day(now - WINDOW_SECONDS)",
                                           'COV_USD_HIGH_UNDEFINED_PREVIOUS_DAY'),
    'range without the extra day after': ("+ 2 * DAY_SECONDS - 1", "+ DAY_SECONDS - 1", 'COV_USD_HIGH_UNDEFINED_NEXT_DAY'),
    'spread >= threshold blocks (equal not allowed)': ("    return spread <= threshold + tolerance", "    return spread < threshold",
                                                       'ZERO_SPREAD_THRESHOLD_0'),
    'exact equality without noise tolerance': ("    return spread <= threshold + tolerance", "    return spread <= threshold",
                                               'AT_THRESHOLD_BINARY_NOISE_ABOVE'),
    'noise tolerance far too wide': ("NOISE_ULPS = 16.0", "NOISE_ULPS = 1e13", 'REAL_EXCESS_0_001_POINT'),
    'unset sentinel not special': ("    if _finite(max_points) and max_points == SPREAD_UNSET:\n        return Spread(UNKNOWN, 'POLICY_UNSET')\n",
                                   "", 'THRESHOLD_UNSET'),
    'negative threshold accepted': ("    if not _finite(max_points) or max_points < 0:", "    if not _finite(max_points):",
                                    'THRESHOLD_NEGATIVE_HALF'),
    'ask below bid accepted': ("or ask < bid or point <= 0", "or point <= 0", 'QUOTE_ASK_BELOW_BID'),
}


class MutationTests(unittest.TestCase):
    def test_the_unmutated_reference_has_no_failures(self):
        self.assertEqual(all_failures(ref), [])

    def test_each_defective_copy_is_caught_by_the_named_row(self):
        for name, (old, new, expect) in MUTANTS.items():
            with self.subTest(name):
                m = load_mutant(old, new)
                bad = all_failures(m)
                self.assertIn(expect, bad, '%s not caught by %s (failures: %s)' % (name, expect, bad))


class SyncAndScopeTests(unittest.TestCase):
    def test_mql_fixture_block_equals_generated_text(self):
        with open(os.path.join(ROOT, 'src', 'tests', 'T010_FiltersTest.mq5'), encoding='ascii') as fh:
            text = fh.read()
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', text, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), emit_mql())

    def test_constants_match_the_mql5_header(self):
        with open(os.path.join(ROOT, 'src', 'include', 'NewsSpreadFilters.mqh'), encoding='ascii') as fh:
            h = fh.read()
        for name, value in (('NF_WINDOW_SECONDS', ref.WINDOW_SECONDS), ('NF_NOISE_ULPS', ref.NOISE_ULPS),
                            ('NF_IMP_HIGH', ref.IMP_HIGH), ('NF_Q_OK', ref.Q_OK), ('NF_Q_ERROR', ref.Q_ERROR),
                            ('NF_Q_NOT_READY', ref.Q_NOT_READY), ('NF_Q_TESTER', ref.Q_TESTER),
                            ('NF_DAY_SECONDS', ref.DAY_SECONDS), ('NF_MAX_DATETIME', ref.MAX_DATETIME)):
            m = re.search(r'#define %s (\S+)' % name, h)
            self.assertIsNotNone(m, name)
            self.assertEqual(float(m.group(1)), float(value), name)
        self.assertIn('#define NF_SPREAD_UNSET (-1.0)', h)

    def test_names_are_unique(self):
        for rows in (NEWS_CASES, SPREAD_CASES, CLASSIFY_CASES, RANGE_CASES, COVERAGE_CASES):
            names = [c['name'] for c in rows]
            self.assertEqual(len(names), len(set(names)))

    def test_reference_has_no_clock_file_or_trading_use(self):
        with open(REF_PATH, encoding='ascii') as fh:
            code = re.sub(r'(?s)""".*?"""|#[^\n]*', '', fh.read())
        for word in ('time', 'datetime', 'random', 'os', 'json', 'socket', 'sqlite3'):
            self.assertIsNone(re.search(r'^\s*(import|from)\s+%s\b' % word, code, re.M), word)
        for word in ('open(', 'OrderSend', 'print('):
            self.assertNotIn(word, code)


if __name__ == '__main__':
    unittest.main()
