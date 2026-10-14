"""Hand-derived H4 fixtures for the T004 ordinary touch source (shared by Python tests and the MQL5 script).

Base: the T002 bearish scenario t002_reference_test.bear_base() (50 H4 bars, trend LH+LL, interval
2023..2081, ERL 2023 untouched, two FRESH IRL bearish FVGs):
  Z1 = F202601111200D [2057, 2063] (candle C closes 1768176000)
  Z2 = F202601111600D [2053, 2059] (candle C closes 1768190400)
Price before the first appended bar: close 2036, so Z2 (lower 2053) is nearer than Z1 (2057).
Appended rows are (high, low, close) for H4 bars 50, 51, ... The BUY fixtures are the exact price
mirror (t002 mirror(): 4200 - x), which turns bearish FVGs into bullish ones.

Derivations (window = 50, so the analysed window slides by one bar per step):
  touch      bar50 wick 2045..2054 reaches Z2 (2054>=2053), not Z1 (2054<2057); close 2050 is not beyond
             2059 -> Z2 recorded at the close of bar 50.
  replace    bar51 (2049..2058) touches Z1 but Z2 is open: no change. bar52 closes 2062 > 2059: Z2 INVALID;
             the same wick (2056..2063) touches Z1, whose close 2062 <= 2063: Z1 replaces Z2.
  erl        bar51 low 2022 <= 2023: ERL TAKEN, record revoked.
  trend      bar51 high 2095 is a swing high once bars 52, 53 are lower (confirmed at the close of bar 53):
             highs 2081 -> 2095 with lows still falling = MIXED, record revoked at the close of bar 53.
  retouch    like trend but the spike high is EQUAL to 2081 (not strictly lower: MIXED, revoked at the
             close of bar 53); later the swing high 2072 (bar 55, confirmed at the close of bar 57) makes
             2081 -> 2072 lower again = BEARISH. Lows rise monotonically (no pivot low). bar58 touches Z2
             again (2053..2056, not Z1 2057).
  confirm    A=bar50 (2052/2048), B=bar51, C=bar52 (high 2044 < 2048): bearish FVG [2044, 2048] confirmed
             at the close of bar 52; C itself cannot touch it. bar53 (2041..2046) is the first candle that
             can: it opens exactly at the confirmation time.
"""
import t002_reference_test as t2
from t002_reference_test import Bar

BASE = t2.bear_base()
M = t2.MIRROR
H4 = 14400

ROWS = {
    'touch': [(2054, 2045, 2050)],
    'replace': [(2054, 2045, 2050), (2058, 2049, 2052), (2063, 2056, 2062)],
    'erl': [(2054, 2045, 2050), (2040, 2022, 2030)],
    'trend': [(2054, 2045, 2050), (2095, 2050, 2055), (2056, 2048, 2052), (2054, 2046, 2050)],
    'retouch': [(2054, 2045, 2050), (2081, 2046, 2055), (2060, 2047, 2052), (2058, 2048, 2050),
                (2066, 2049, 2057), (2072, 2050, 2058), (2066, 2051, 2056), (2062, 2052, 2054),
                (2056, 2053, 2055)],
    'confirm': [(2052, 2048, 2050), (2049, 2038, 2040), (2044, 2036, 2040), (2046, 2041, 2043)],
    'beyond_all': [(2065, 2045, 2064)],
    'beyond_nearest': [(2062, 2045, 2060)],
    'equal_edge': [(2062, 2045, 2059)],
    'no_touch': [(2052, 2045, 2050)],
    'erl_first': [(2040, 2022, 2030), (2056, 2045, 2050)],
}


def sell(name):
    bars = list(BASE)
    for k, (h, l, c) in enumerate(ROWS[name]):
        bars.append(Bar(BASE[0].time + (len(BASE) + k) * H4, float(h), float(l), float(c)))
    return bars


def buy(name):
    return t2.mirror(sell(name))


def emit_mql():
    """Text of the MQL5 data block (kept in src/tests/T004_OrdinaryTest.mq5 between the markers)."""
    out = ['// BEGIN GENERATED FIXTURES (tests/t004_ordinary_fixtures.py emit_mql)']
    out.append('datetime T0=%d;' % BASE[0].time)
    out.append('double BASE_H[]={%s};' % ','.join('%.1f' % b.high for b in BASE))
    out.append('double BASE_L[]={%s};' % ','.join('%.1f' % b.low for b in BASE))
    out.append('double BASE_C[]={%s};' % ','.join('%.1f' % b.close for b in BASE))
    for name, rows in ROWS.items():
        out.append('double R_%s[]={%s};' % (name.upper(), ','.join('%.1f,%.1f,%.1f' % r for r in rows)))
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
