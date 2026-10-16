"""The layout helpers of the chart view (mirror of EV_Wrap / EV_Select): a long line wraps to the width, a narrow chart drops the lowest priorities first and says so, the lines that matter most
(priority 0: the mode and the decision) are never dropped, a wide chart keeps everything."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import view_layout_reference as lay  # noqa: E402


class Wrap(unittest.TestCase):
    def test_a_short_line_is_one_row(self):
        self.assertEqual(lay.wrap('SIMULIM - PA URDHRA REALE', 40), ['SIMULIM - PA URDHRA REALE'])

    def test_a_long_line_wraps_at_words_and_continuation_rows_are_indented(self):
        rows = lay.wrap('M15 mungon: thyerja e nivelit M15; FVG M15 pas thyerjes; kthimi i cmimit ne FVG', 30)
        self.assertEqual(rows, ['M15 mungon: thyerja e nivelit', '  M15; FVG M15 pas thyerjes;', '  kthimi i cmimit ne FVG'])
        self.assertTrue(all(len(r) <= 30 for r in rows))
        self.assertEqual(' '.join(r.strip() for r in rows), 'M15 mungon: thyerja e nivelit M15; FVG M15 pas thyerjes; kthimi i cmimit ne FVG')

    def test_a_word_longer_than_the_width_is_cut_and_nothing_is_lost(self):
        rows = lay.wrap('x ' + 'a' * 25, 10)
        self.assertTrue(all(len(r) <= 10 for r in rows))
        self.assertEqual(''.join(r.strip() for r in rows), 'x' + 'a' * 25)

    def test_a_tiny_width_is_raised_to_the_minimum(self):
        self.assertTrue(all(len(r) <= lay.MIN_WIDTH for r in lay.wrap('abc defgh ijklmnop', 2)))


class Select(unittest.TestCase):
    TEXTS = ['SIMULIM - PA URDHRA REALE', 'H4: ZBRITES (SELL) | sweep i brendshem u pa; pret qe cmimi te preke nje FVG H4 te ri', 'M15 konfirmuar: asgje ende', 'M15 mungon: setup H4 i rikonfirmuar',
             'VENDIMI: PRET - pret rikonfirmimin H4', 'Konfirmuar nga klienti: hyrja LIMIT ne skaj te FVG, seanca, lajmet, kufijte ditore.', 'E perkohshme (prototip): burimi H4, niveli M15 i thyer, SL, TP/2R']
    PRIOS = [0, 1, 1, 1, 0, 3, 3]

    def test_a_wide_chart_keeps_every_line_and_adds_no_marker(self):
        keep, dropped, rows = lay.select(self.TEXTS, self.PRIOS, 120, 12)
        self.assertEqual((keep, dropped, rows), ([True] * 7, 0, 7))

    def test_a_small_chart_drops_the_lowest_priorities_first_and_announces_it_once(self):
        keep, dropped, rows = lay.select(self.TEXTS, self.PRIOS, 120, 6)
        self.assertEqual(keep, [True, True, True, True, True, False, False])
        self.assertEqual((dropped, rows), (2, 6))
        self.assertEqual(lay.MARKER % 2, '(+2 te fshehura)')

    def test_the_later_line_of_the_same_priority_leaves_first(self):
        keep, dropped, rows = lay.select(['a', 'b', 'c', 'd'], [0, 2, 2, 2], 40, 3)
        self.assertEqual((keep, dropped, rows), ([True, True, False, False], 2, 3))

    def test_priority_zero_is_never_dropped_even_when_nothing_fits(self):
        keep, dropped, rows = lay.select(self.TEXTS, self.PRIOS, 20, 2)
        self.assertTrue(keep[0] and keep[4])
        self.assertEqual([k for i, k in enumerate(keep) if self.PRIOS[i] > 0], [False] * 5)

    def test_wrapping_counts_in_the_rows_that_are_needed(self):
        keep, dropped, rows = lay.select(self.TEXTS, self.PRIOS, 40, 9)
        total_wrapped = sum(len(lay.wrap(t, 40)) for t, k in zip(self.TEXTS, keep) if k)
        self.assertLessEqual(total_wrapped + (1 if dropped else 0), 9)
        self.assertGreater(dropped, 0)


if __name__ == '__main__':
    unittest.main()
