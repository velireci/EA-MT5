"""T011 tests: exact 80/20 split on the volume grid (pure; no order, no account)."""
import math
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t006_sizing_reference as t006  # noqa: E402
import t011_split_reference as ref  # noqa: E402
from t011_split_fixtures import CASES, emit_mql  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


class Fixtures(unittest.TestCase):
    def test_table(self):
        for c in CASES:
            with self.subTest(c['name']):
                s = ref.split(*c['p'])
                self.assertEqual(s.status, c['status'], s.reason)
                if c['why']:
                    self.assertTrue(s.reason.startswith(c['why']), s.reason)
                if c['status'] == ref.OK:
                    n, close, rem = c['steps']
                    self.assertEqual((s.initial_steps, s.close_steps, s.remaining_steps), (n, close, rem))
                    self.assertEqual(s.close_steps + s.remaining_steps, s.initial_steps)
                    self.assertEqual(s.close_steps * 5, s.initial_steps * 4)
                    self.assertEqual(s.close_percent, 0.8)
                    self.assertEqual(s.close_volume, close * c['p'][2])
                    self.assertEqual(s.remaining_volume, rem * c['p'][2])
                    self.assertLessEqual(abs(s.close_volume + s.remaining_volume - c['p'][0]),
                                         8 * t006.DBL_EPSILON * max(1.0, c['p'][0]))
                elif c['status'] == ref.SPLIT_POLICY_UNSET:
                    self.assertEqual(s.initial_steps, c['steps'][0])
                    self.assertEqual((s.close_steps, s.remaining_steps, s.close_volume, s.remaining_volume, s.close_percent),
                                     (0, 0, 0.0, 0.0, 0.0))
                else:
                    self.assertEqual((s.initial_steps, s.min_steps, s.max_steps, s.close_steps, s.remaining_steps,
                                      s.close_volume, s.remaining_volume, s.close_percent), (0, 0, 0, 0, 0, 0.0, 0.0, 0.0))

    def test_every_status_and_tag_covered(self):
        self.assertEqual({c['status'] for c in CASES}, {ref.OK, ref.INVALID_INPUT, ref.SPLIT_POLICY_UNSET})
        tags = {c['why'] for c in CASES if c['why']}
        for t in ('NOT_EXACT_80_20', 'REMAINDER_BELOW_MIN', 'INVALID_INITIAL', 'INVALID_VOLUME_MIN', 'INVALID_VOLUME_STEP',
                  'INVALID_VOLUME_MAX', 'VOLUME_MAX_BELOW_MIN', 'STEP_RANGE', 'VOLUME_NOT_ON_GRID', 'INITIAL_BELOW_MIN',
                  'INITIAL_ABOVE_MAX'):
            self.assertIn(t, tags)


class Properties(unittest.TestCase):
    def test_sweep_exact_iff_divisible_by_five(self):
        for step in (0.01, 0.1, 0.001, 0.05):
            for n in range(1, 801):
                s = ref.split(n * step, step, step, 1000.0)
                if n % 5 == 0:
                    self.assertEqual(s.status, ref.OK, (step, n, s.reason))
                    self.assertEqual((s.close_steps, s.remaining_steps), (4 * n // 5, n // 5))
                    self.assertEqual(s.close_steps + s.remaining_steps, n)
                else:
                    self.assertEqual(s.status, ref.SPLIT_POLICY_UNSET, (step, n))
                    self.assertTrue(s.reason.startswith('NOT_EXACT_80_20'))

    def test_no_invented_policy(self):
        # not splittable: nothing is rounded, closed fully or skipped; the result carries no volume at all
        s = ref.split(0.07, 0.01, 0.01, 100.0)
        self.assertEqual((s.status, s.close_volume, s.remaining_volume), (ref.SPLIT_POLICY_UNSET, 0.0, 0.0))
        s = ref.split(0.05, 0.02, 0.01, 100.0)
        self.assertEqual((s.status, s.close_volume, s.remaining_volume), (ref.SPLIT_POLICY_UNSET, 0.0, 0.0))

    def test_non_finite_and_wrong_types(self):
        inf, nan = float('inf'), float('nan')
        for args, tag in (((nan, 0.01, 0.01, 100.0), 'INVALID_INITIAL'), ((inf, 0.01, 0.01, 100.0), 'INVALID_INITIAL'),
                          ((0.1, nan, 0.01, 100.0), 'INVALID_VOLUME_MIN'), ((0.1, 0.01, nan, 100.0), 'INVALID_VOLUME_STEP'),
                          ((0.1, 0.01, 0.01, inf), 'INVALID_VOLUME_MAX'), (('0.1', 0.01, 0.01, 100.0), 'INVALID_INITIAL'),
                          ((True, 0.01, 0.01, 100.0), 'INVALID_INITIAL'), ((None, 0.01, 0.01, 100.0), 'INVALID_INITIAL')):
            with self.subTest(args):
                s = ref.split(*args)
                self.assertEqual(s.status, ref.INVALID_INPUT)
                self.assertTrue(s.reason.startswith(tag), s.reason)

    def test_uses_t006_grid_not_a_copy(self):
        src = _read('tests', 't011_split_reference.py')
        self.assertIn('t006._grid_steps', src)
        self.assertNotIn('GRID_ULPS', src)
        self.assertNotIn('def _grid_steps', src)
        hdr = _read('src', 'include', 'ExitSplit.mqh')
        self.assertIn('PS_GridSteps(', hdr)
        self.assertIn('PositionSizing.mqh', hdr)
        self.assertNotIn('PS_GRID_ULPS', hdr)

    def test_inputs_not_mutated_and_deterministic(self):
        a = ref.split(0.1, 0.01, 0.01, 100.0)
        b = ref.split(0.1, 0.01, 0.01, 100.0)
        self.assertEqual(a, b)


class Mutants(unittest.TestCase):
    """Each mutant of the reference must be caught by the fixture table."""

    def _caught(self, fn):
        for c in CASES:
            s = fn(*c['p'])
            if s.status != c['status'] or (c['why'] and not s.reason.startswith(c['why'])):
                return True
            if c['status'] == ref.OK and (s.initial_steps, s.close_steps, s.remaining_steps) != c['steps']:
                return True
        return False

    def test_mutants(self):
        orig = ref.split

        def round_nearest(init, vmin, step, vmax):
            s = orig(init, vmin, step, vmax)
            if s.status == ref.SPLIT_POLICY_UNSET and s.reason.startswith('NOT_EXACT'):
                n = s.initial_steps
                close = round(n * 0.8)
                return ref.Split(ref.OK, initial_steps=n, close_steps=close, remaining_steps=n - close,
                                 close_volume=close * step, remaining_volume=(n - close) * step, close_percent=close / n)
            return s

        def full_close(init, vmin, step, vmax):
            s = orig(init, vmin, step, vmax)
            if s.status == ref.SPLIT_POLICY_UNSET:
                n = s.initial_steps
                return ref.Split(ref.OK, initial_steps=n, close_steps=n, remaining_steps=0, close_volume=n * step, close_percent=1.0)
            return s

        def skip_partial(init, vmin, step, vmax):
            s = orig(init, vmin, step, vmax)
            if s.status == ref.SPLIT_POLICY_UNSET:
                return ref.Split(ref.OK, initial_steps=s.initial_steps)
            return s

        def lost_volume(init, vmin, step, vmax):
            s = orig(init, vmin, step, vmax)
            if s.status == ref.OK:
                s.remaining_steps -= 1
            return s

        for name, m in (('round to nearest', round_nearest), ('full close', full_close), ('skip partial', skip_partial),
                        ('lost volume', lost_volume)):
            with self.subTest(name):
                self.assertTrue(self._caught(m), name)


class MqlBlock(unittest.TestCase):
    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T011_SplitTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), emit_mql())


if __name__ == '__main__':
    unittest.main()
