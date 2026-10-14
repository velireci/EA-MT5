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
from t010_filters_fixtures import NEWS_CASES, NOW, SPREAD_CASES, emit_mql, real  # noqa: E402

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
        self.assertEqual(news_failures(ref) + spread_failures(ref), [])

    def test_each_defective_copy_is_caught_by_the_named_row(self):
        for name, (old, new, expect) in MUTANTS.items():
            with self.subTest(name):
                m = load_mutant(old, new)
                bad = news_failures(m) + spread_failures(m)
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
                            ('NF_Q_NOT_READY', ref.Q_NOT_READY), ('NF_Q_TESTER', ref.Q_TESTER)):
            m = re.search(r'#define %s (\S+)' % name, h)
            self.assertIsNotNone(m, name)
            self.assertEqual(float(m.group(1)), float(value), name)
        self.assertIn('#define NF_SPREAD_UNSET (-1.0)', h)

    def test_names_are_unique(self):
        for rows in (NEWS_CASES, SPREAD_CASES):
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
