#!/usr/bin/env python3
"""T003 exploration on SYNTHETIC random-walk H4 series (NOT market data, NOT gold).

Question: which class of situation gives AB_STATE_DIFF + AB_EVENT_DIFF + ANCHOR_IN_WARMUP on a long
series? This script runs the Python model on seeded random walks (several regimes of drift) at the
default parameters (L=300, R=1000) and tabulates what the diagnostics report.

What the numbers mean: they describe the behaviour of the PROPOSED rules on artificial data. They
are evidence for hypotheses, not for what a real gold series does. A hypothesis is confirmed or
rejected only by replaying a real CSV (tests/t003_replay_csv.py).

Usage:  python3 tests/t003_explore_synthetic.py [seeds] [bars] [rebuild]     (default 40 1400 1000)
"""
import collections
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t003_reference_test as m  # noqa: E402


def gen(seed, n, vol=6.0, regime=150, drift=1.5):
    """seeded random walk: `regime` bars of constant random drift, gaussian noise, ranges around it"""
    r = random.Random(seed)
    c = 4000.0
    out = []
    dr = 0.0
    for i in range(n):
        if i % regime == 0:
            dr = r.uniform(-drift, drift)
        o = c
        c = o + dr + r.gauss(0, vol)
        h = max(o, c) + abs(r.gauss(0, vol * 0.5))
        l = min(o, c) - abs(r.gauss(0, vol * 0.5))
        out.append(m.Bar(m.T0 + i * m.PERIOD, round(h, 2), round(l, 2), round(c, 2)))
    return out


def main():
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 40
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 1400
    rebuild = int(sys.argv[3]) if len(sys.argv) > 3 else 1000
    reasons = collections.Counter()
    final = collections.Counter()
    first_field = collections.Counter()
    first_event = collections.Counter()
    old_cause = collections.Counter()
    nolv_share = []
    for seed in range(seeds):
        bars = gen(seed, n)
        p = m.Params(rebuild=rebuild)
        ev = m.evaluate(bars, n, p)
        st = ev.state
        kind = 'NONE' if st.dir == 0 else ('frozen' if st.frozen else 'unfrozen')
        final[(kind, 'LIMITED' if not ev.reliable else 'OK')] += 1
        reasons[ev.reason if not ev.reliable else 'RELIABLE (%s)' % ev.flag] += 1
        if ev.reliable:
            continue
        d = m.diagnose(bars, n, p, ev)
        first_field[d.field_diff[0] if d.field_diff else 'none (events/anchor only)'] += 1
        if d.event_diff:
            first_event['%s vs %s' % (d.event_diff[1].type, d.event_diff[2].type)] += 1
        elif d.event_count_diff:
            first_event['count differs (first extra: %s)' % d.event_extra[0].type] += 1
        old_cause['A reference older than B start' if (d.a.anchor_ref and d.a.anchor_ref < d.b.start) else 'A reference inside B window'] += 1
        for side in (d.a, d.b):
            nolv_share.append(side.nolv_total / float(side.bars))
    print('SYNTHETIC random walks: %d series of %d bars, L=300, R=%d (not market data)' % (seeds, n, rebuild))
    print('reasons:')
    for k, v in reasons.most_common():
        print('  %3d  %s' % (v, k))
    print('final state of replay A (bias state kind, outcome):')
    for k, v in sorted(final.items(), key=str):
        print('  %3d  %s' % (v, k))
    print('first differing field in the explicit order (LIMITED cases):')
    for k, v in first_field.most_common():
        print('  %3d  %s' % (v, k))
    print('first differing event in the comparison zone (LIMITED cases):')
    for k, v in first_event.most_common():
        print('  %3d  %s' % (v, k))
    print('where the cause of replay A lies (anchor reference versus B start):')
    for k, v in old_cause.most_common():
        print('  %3d  %s' % (v, k))
    if nolv_share:
        print('share of bars with a bias and NO protecting level (A and B of LIMITED cases): mean %.0f%%, max %.0f%%' % (
            100.0 * sum(nolv_share) / len(nolv_share), 100.0 * max(nolv_share)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
