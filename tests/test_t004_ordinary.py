import re
import unittest
from dataclasses import replace
from pathlib import Path
import t002_reference_test as t2
from t004_reference import Context, A_AT_OR_AFTER_BREAK
from t004_timeline_reference import Snapshot, replay_timeline
from t004_ordinary_reference import (scan, direction_agreement, SOURCE_ID, T003_SOURCE_ID,
                                     RETOUCH_UNSET, RETOUCH_AFTER_LOSS, RETOUCH_FIRST_ONLY)
from t004_ordinary_fixtures import sell, buy, BASE, ROWS, emit_mql, H4
from test_t004_selector import fixture

T0 = BASE[0].time
W = 50


def close_of(index):
    """close time of H4 bar `index` of the fixture grid"""
    return T0 + (index + 1) * H4


def run(bars, retouch=RETOUCH_AFTER_LOSS, scan_from=50):
    return scan(bars, scan_from, window=W, retouch=retouch)


def summary(s):
    return [(u.kind, u.reason, u.known, u.context.fvg) for u in s.updates]


def m15(direction, base):
    return [replace(b, time=b.time - 14400 + base) for b in fixture(direction)]


def timeline(bars_m15, updates, start, asof, selector=True, policy=A_AT_OR_AFTER_BREAK):
    return replay_timeline(bars_m15, [Snapshot(u.known, u.context) for u in updates], start, asof,
                           selector, policy)


class TouchRecordTests(unittest.TestCase):
    def test_sell_and_buy_record_only_at_touching_candle_close(self):
        for fn, d, fvg, lo, hi in ((sell, -1, 'F202601111600D', 2053.0, 2059.0),
                                   (buy, 1, 'F202601111600U', 2141.0, 2147.0)):
            before = run(fn('touch')[:50])              # last closed bar is 49: nothing touched yet
            self.assertEqual(before.updates, [])
            s = run(fn('touch'))
            self.assertEqual(len(s.updates), 1)
            u = s.updates[0]
            c = u.context
            self.assertEqual((u.kind, u.known), ('OPEN', close_of(50)))
            self.assertEqual((c.direction, c.fvg, c.lower, c.upper), (d, fvg, lo, hi))
            self.assertEqual((c.valid_from, c.source), (close_of(50), SOURCE_ID))
            self.assertEqual(c.confirmed, T0 + 43 * H4)                  # candle C (bar 42) closed
            self.assertTrue(c.confirmed <= fn('touch')[50].time)       # FVG known before the touch opens
            self.assertTrue(c.ready and c.reliable and c.selected)

    def test_touch_candidate_is_nearest_first_from_last_closed_close(self):
        s = run(sell('touch'))
        self.assertEqual(s.updates[0].context.fvg, 'F202601111600D')      # lower 2053, price 2036
        # one candle reaching both zones: the nearer Z2 wins; Z1 is only the fallback
        bars = sell('touch')
        bars[50] = bars[50]._replace(high=2060.0, close=2056.0)
        self.assertEqual(run(bars).updates[0].context.fvg, 'F202601111600D')

    def test_wick_without_reaching_the_zone_is_no_touch(self):
        self.assertEqual(run(sell('no_touch')).updates, [])

    def test_close_beyond_far_edge_on_touching_candle_is_not_a_touch(self):
        self.assertEqual(run(sell('beyond_all')).updates, [])          # both zones closed through
        self.assertEqual(run(buy('beyond_all')).updates, [])
        s = run(sell('beyond_nearest'))                               # Z2 invalid, Z1 still valid
        self.assertEqual(summary(s), [('OPEN', '', close_of(50), 'F202601111200D')])

    def test_close_equal_to_far_edge_is_not_invalid(self):
        self.assertEqual(run(sell('equal_edge')).updates[0].context.fvg, 'F202601111600D')

    def test_no_setup_when_erl_was_already_taken_before_the_touch(self):
        self.assertEqual(run(sell('erl_first')).updates, [])
        self.assertEqual(run(buy('erl_first')).updates, [])

    def test_fvg_confirmed_by_the_touching_candle_itself_is_unusable(self):
        for fn in (sell, buy):
            bars = fn('confirm')
            c_bar = 52                                         # candle C of the new zone
            early = run(bars[:c_bar + 1])                      # last closed bar = C
            self.assertEqual(early.updates, [])
            s = run(bars)                                      # bar 53 opens exactly at the confirmation
            self.assertEqual(len(s.updates), 1)
            c = s.updates[0].context
            self.assertEqual(c.confirmed, bars[53].time)
            self.assertEqual(s.updates[0].known, bars[53].time + H4)

    def test_open_record_is_not_changed_by_later_touches(self):
        s = run(sell('replace')[:52])                          # bar 51 touches Z1 while Z2 is open
        self.assertEqual(len(s.updates), 1)
        self.assertEqual(s.updates[0].context.fvg, 'F202601111600D')


class RevocationTests(unittest.TestCase):
    def test_invalidated_fvg_is_replaced_by_the_next_zone_at_the_same_close(self):
        for fn, a, b in ((sell, 'F202601111600D', 'F202601111200D'), (buy, 'F202601111600U', 'F202601111200U')):
            s = run(fn('replace'))
            self.assertEqual(summary(s), [('OPEN', '', close_of(50), a),
                                          ('REPLACE', 'after FVG_INVALID', close_of(52), b)])
            self.assertEqual(s.updates[1].context.valid_from, close_of(52))
            self.assertEqual((s.opened, s.closed, s.replaced), (2, 0, 1))

    def test_erl_taken_revokes(self):
        for fn in (sell, buy):
            s = run(fn('erl'))
            self.assertEqual([(u.kind, u.reason, u.known) for u in s.updates],
                             [('OPEN', '', close_of(50)), ('CLOSE', 'ERL_TAKEN', close_of(51))])
            self.assertFalse(s.updates[1].context.ready)

    def test_trend_change_revokes_when_the_swing_is_confirmed(self):
        for fn in (sell, buy):
            s = run(fn('trend'))
            self.assertEqual([(u.kind, u.reason, u.known) for u in s.updates],
                             [('OPEN', '', close_of(50)), ('CLOSE', 'TREND_CHANGE', close_of(53))])
            # not earlier: the spike bar 51 alone does not change the trend
            self.assertEqual(len(run(fn('trend')[:53]).updates), 1)

    def test_retouch_after_loss_versus_first_only(self):
        for fn, fvg in ((sell, 'F202601111600D'), (buy, 'F202601111600U')):
            again = run(fn('retouch'), RETOUCH_AFTER_LOSS)
            self.assertEqual([(u.kind, u.reason, u.known) for u in again.updates],
                             [('OPEN', '', close_of(50)), ('CLOSE', 'TREND_CHANGE', close_of(53)),
                              ('OPEN', '', close_of(58))])
            self.assertEqual(again.updates[2].context.fvg, fvg)
            self.assertNotEqual(again.updates[2].context.setup, again.updates[0].context.setup)
            first = run(fn('retouch'), RETOUCH_FIRST_ONLY)
            self.assertEqual([(u.kind, u.reason) for u in first.updates],
                             [('OPEN', ''), ('CLOSE', 'TREND_CHANGE')])

    def test_no_reopen_while_the_trend_is_not_active(self):
        s = run(sell('retouch')[:58])                          # up to bar 57: trend only restored at its close
        self.assertEqual([u.kind for u in s.updates], ['OPEN', 'CLOSE'])

    def test_partial_history_never_records(self):
        s = scan(sell('touch'), 10, window=W, retouch=RETOUCH_AFTER_LOSS)
        self.assertEqual(summary(s), summary(run(sell('touch'))))       # earlier partial windows add nothing
        short = scan(sell('touch'), 50, window=60, retouch=RETOUCH_AFTER_LOSS)     # 51 bars < 60
        self.assertEqual(short.updates, [])

    def test_invalid_input(self):
        self.assertEqual(scan(sell('touch'), 50, window=49, retouch=1).status, 'INVALID_INPUT')
        self.assertEqual(scan(sell('touch'), 50, window=W, retouch=3).status, 'INVALID_INPUT')
        bad = sell('touch')
        bad[10] = bad[10]._replace(time=bad[9].time)
        self.assertEqual(scan(bad, 50, window=W, retouch=1).status, 'INVALID_H4')


class NoLookaheadTests(unittest.TestCase):
    def test_prefix_determinism_for_every_cut_and_policy(self):
        for fn in (sell, buy):
            for r in (RETOUCH_AFTER_LOSS, RETOUCH_FIRST_ONLY):
                for name in ('replace', 'retouch', 'trend', 'confirm'):
                    bars = fn(name)
                    full = run(bars, r)
                    for k in range(50, len(bars) + 1):
                        part = run(bars[:k], r)
                        horizon = bars[k - 1].time + H4
                        self.assertEqual(part.updates, [u for u in full.updates if u.known <= horizon],
                                         (name, k, r))

    def test_future_bars_do_not_change_an_earlier_record(self):
        s1 = run(sell('touch'))
        later = sell('touch') + [t2.Bar(sell('touch')[-1].time + H4, 2300.0, 1900.0, 2000.0)]
        s2 = run(later)
        self.assertEqual(s2.updates[0], s1.updates[0])


class GateTests(unittest.TestCase):
    def test_default_retouch_policy_leaves_contexts_unselected(self):
        s = run(sell('touch'), RETOUCH_UNSET)
        self.assertEqual(len(s.updates), 1)
        self.assertFalse(s.updates[0].context.selected)
        T = s.updates[0].known
        t = timeline(m15(-1, T), s.updates, T, T + 8100)
        self.assertEqual(t.observer.phase, 'WAIT_CONTEXT')
        self.assertNotIn('CONTEXT_OPEN', [e.type for e in t.observer.events])


class M15ChainTests(unittest.TestCase):
    def test_both_directions_full_path_after_the_touching_candle(self):
        for fn, d in ((sell, -1), (buy, 1)):
            s = run(fn('touch'))
            T = s.updates[0].known
            t = timeline(m15(d, T), s.updates, T, T + 8100)
            self.assertEqual((t.status, t.processed, t.observer.phase, t.bos_price), ('OK', 9, 'RETURN_OBSERVED', 100))
            self.assertEqual(t.observer.context.source, SOURCE_ID)
            self.assertTrue(t.observer.context.setup.startswith('T002TOUCH-'))

    def test_m15_bar_ending_exactly_at_the_touching_close_is_excluded(self):
        s = run(sell('touch'))
        T = s.updates[0].known
        t = timeline(m15(-1, T - 5400), s.updates, T - 5400, T + 2700)    # BOS bar 5 spans T-900..T
        self.assertEqual(t.observer.phase, 'WAIT_BREAK')
        self.assertNotIn('BOS_CANDIDATE', [e.type for e in t.observer.events])
        # control: had the context been valid from the touching candle's OPEN, the same data breaks
        early = replace(s.updates[0].context, valid_from=T - H4)
        c = timeline(m15(-1, T - 5400), [type(s.updates[0])(T - H4, early, 'OPEN', '')], T - 5400, T + 2700)
        self.assertIn('BOS_CANDIDATE', [e.type for e in c.observer.events])

    def test_m15_bar_opening_at_the_close_is_usable_after_its_own_close(self):
        s = run(sell('touch'))
        T = s.updates[0].known
        t = timeline(m15(-1, T - 4500), s.updates, T - 4500, T + 3600)    # BOS bar 5 opens at T
        bos = [e for e in t.observer.events if e.type == 'BOS_CANDIDATE']
        self.assertEqual([(e.time, e.known) for e in bos], [(T, T + 900)])

    def test_h4_revocation_wins_at_the_same_close_as_the_m15_return(self):
        s = run(sell('erl'))
        T, Tr = s.updates[0].known, s.updates[1].known
        base = Tr - 8100                       # the return bar closes exactly when the H4 candle revokes
        t = timeline(m15(-1, base), s.updates, base, Tr)
        self.assertEqual(t.observer.phase, 'WAIT_CONTEXT')
        self.assertNotIn('RETURN_OBSERVED', [e.type for e in t.observer.events])
        c = timeline(m15(-1, base), s.updates[:1], base, Tr)               # control: no revocation
        self.assertEqual(c.observer.phase, 'RETURN_OBSERVED')

    def test_replacement_at_the_close_clears_progress_and_excludes_that_candle(self):
        s = run(sell('replace'))
        Tr = s.updates[1].known
        base = Tr - 8100
        t = timeline(m15(-1, base), s.updates, base, Tr)
        self.assertEqual(t.observer.phase, 'WAIT_BREAK')
        self.assertEqual(t.observer.context.fvg, 'F202601111200D')
        self.assertEqual(t.observer.candidates, [])
        self.assertEqual([e.type for e in t.observer.events if e.type.startswith('CONTEXT')],
                         ['CONTEXT_OPEN', 'CONTEXT_CLOSED', 'CONTEXT_OPEN'])
        self.assertNotIn('RETURN_OBSERVED', [e.type for e in t.observer.events])

    def test_later_h4_updates_are_not_used_for_earlier_m15_bars(self):
        s = run(sell('retouch'), RETOUCH_AFTER_LOSS)       # three updates: OPEN, CLOSE (bar 53), OPEN (bar 58)
        first = s.updates[0].known
        asof = first + 8100                                  # well before the CLOSE at bar 53's close
        self.assertTrue(s.updates[1].known > asof)
        t = timeline(m15(-1, first), s.updates, first, asof)
        self.assertEqual(t.observer.phase, 'RETURN_OBSERVED')
        self.assertEqual(t.observer.context.setup, s.updates[0].context.setup)


class SourceDistinctionTests(unittest.TestCase):
    def test_sources_have_distinct_ids_and_are_not_merged(self):
        self.assertNotEqual(SOURCE_ID, T003_SOURCE_ID)
        s = run(sell('touch'))
        T = s.updates[0].known
        t3 = Context('SWEEP@1', -1, T003_SOURCE_ID, 'T3F', 80, 120, T, T, True, True, True)
        a = timeline(m15(-1, T), s.updates, T, T + 8100)
        b = timeline(m15(-1, T), [type(s.updates[0])(T, t3, 'OPEN', '')], T, T + 8100)
        self.assertEqual((a.observer.context.source, b.observer.context.source), (SOURCE_ID, T003_SOURCE_ID))
        self.assertEqual((a.observer.phase, b.observer.phase), ('RETURN_OBSERVED', 'RETURN_OBSERVED'))
        self.assertNotEqual(a.observer.context.setup, b.observer.context.setup)

    def test_disagreement_is_flagged_not_resolved(self):
        self.assertEqual(direction_agreement(-1, 'BULL'), 'DISAGREE')
        self.assertEqual(direction_agreement(1, 'BEAR'), 'DISAGREE')
        self.assertEqual(direction_agreement(-1, 'BEAR'), 'AGREE')
        self.assertEqual(direction_agreement(1, 'BULLISH'), 'AGREE')
        self.assertEqual(direction_agreement(1, 'UNKNOWN'), 'NO_DIRECTION')
        self.assertEqual(direction_agreement(0, 'BULL'), 'NO_DIRECTION')
        # T002 BEARISH ordinary context and a T003 BULL bias keep their own contexts: the SELL context
        # is produced and replayed untouched by the disagreement flag
        s = run(sell('touch'))
        self.assertEqual(s.updates[0].context.direction, -1)
        self.assertEqual(direction_agreement(s.updates[0].context.direction, 'BULL'), 'DISAGREE')


class MqlSyncTests(unittest.TestCase):
    def test_mql_test_embeds_the_generated_fixtures(self):
        text = (Path(__file__).resolve().parent.parent / 'src' / 'tests' / 'T004_OrdinaryTest.mq5').read_text()
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', text, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), emit_mql())


if __name__ == '__main__':
    unittest.main(verbosity=2)
