"""T011 hand-computed fixtures: (name, initial, min, step, max, status, why, steps) with steps = (N, close, remaining) or None.

Every number is derived by hand from the volume grid (N = initial/step, close = 4N/5, remaining = N/5).
emit_mql() produces the data block kept in src/tests/T011_SplitTest.mq5 (equality is tested)."""
CASES = []


def case(name, init, vmin, step, vmax, status, why='', steps=None):
    CASES.append(dict(name=name, p=(init, vmin, step, vmax), status=status, why=why, steps=steps))


OKS, UNS, INV = 'OK', 'SPLIT_POLICY_UNSET', 'INVALID_INPUT'
# exact splits
case('EXACT_0_10', 0.10, 0.01, 0.01, 100.0, OKS, steps=(10, 8, 2))
case('SMALLEST_EXACT_0_05', 0.05, 0.01, 0.01, 100.0, OKS, steps=(5, 4, 1))
case('STEP_0_1', 1.0, 0.1, 0.1, 100.0, OKS, steps=(10, 8, 2))
case('LARGE_10_LOTS', 10.0, 0.01, 0.01, 100.0, OKS, steps=(1000, 800, 200))
case('STEP_0_05', 0.5, 0.05, 0.05, 100.0, OKS, steps=(10, 8, 2))
case('STEP_0_001', 0.015, 0.001, 0.001, 100.0, OKS, steps=(15, 12, 3))
case('INITIAL_EQUALS_MAX', 100.0, 0.01, 0.01, 100.0, OKS, steps=(10000, 8000, 2000))
case('REMAINDER_EQUALS_MIN', 0.10, 0.02, 0.01, 100.0, OKS, steps=(10, 8, 2))
case('NOISY_DIVISION_0_35', 0.35, 0.01, 0.01, 100.0, OKS, steps=(35, 28, 7))
case('NOISY_DIVISION_0_15', 0.15, 0.01, 0.01, 100.0, OKS, steps=(15, 12, 3))
case('NOISY_DIVISION_0_3_STEP_0_1', 3.0, 0.1, 0.1, 100.0, OKS, steps=(30, 24, 6))
case('MIN_LOT_ONE_STEP_GRID_0_1', 0.5, 0.1, 0.1, 100.0, OKS, steps=(5, 4, 1))
# not exactly splittable / part below minimum -> SPLIT_POLICY_UNSET (nothing invented)
case('ONE_STEP', 0.01, 0.01, 0.01, 100.0, UNS, 'NOT_EXACT_80_20', (1, 0, 0))
case('SEVEN_STEPS', 0.07, 0.01, 0.01, 100.0, UNS, 'NOT_EXACT_80_20', (7, 0, 0))
case('ELEVEN_STEPS', 0.11, 0.01, 0.01, 100.0, UNS, 'NOT_EXACT_80_20', (11, 0, 0))
case('NINETY_NINE_STEPS', 0.99, 0.01, 0.01, 100.0, UNS, 'NOT_EXACT_80_20', (99, 0, 0))
case('EXACTNESS_BEFORE_MIN', 0.07, 0.05, 0.01, 100.0, UNS, 'NOT_EXACT_80_20', (7, 0, 0))
case('REMAINDER_BELOW_MIN_1_OF_2', 0.05, 0.02, 0.01, 100.0, UNS, 'REMAINDER_BELOW_MIN', (5, 0, 0))
case('REMAINDER_BELOW_MIN_2_OF_3', 0.10, 0.03, 0.01, 100.0, UNS, 'REMAINDER_BELOW_MIN', (10, 0, 0))
case('INITIAL_EQUALS_MIN', 0.05, 0.05, 0.01, 100.0, UNS, 'REMAINDER_BELOW_MIN', (5, 0, 0))
case('MIN_LOT_ONLY_STEP_0_1', 0.1, 0.1, 0.1, 100.0, UNS, 'NOT_EXACT_80_20', (1, 0, 0))
# invalid input, first failure wins
case('INITIAL_ZERO', 0.0, 0.01, 0.01, 100.0, INV, 'INVALID_INITIAL')
case('INITIAL_NEGATIVE', -0.1, 0.01, 0.01, 100.0, INV, 'INVALID_INITIAL')
case('VMIN_ZERO', 0.1, 0.0, 0.01, 100.0, INV, 'INVALID_VOLUME_MIN')
case('STEP_ZERO', 0.1, 0.01, 0.0, 100.0, INV, 'INVALID_VOLUME_STEP')
case('STEP_NEGATIVE', 0.1, 0.01, -0.01, 100.0, INV, 'INVALID_VOLUME_STEP')
case('VMAX_ZERO', 0.1, 0.01, 0.01, 0.0, INV, 'INVALID_VOLUME_MAX')
case('FIRST_FAILURE_STEP_BEFORE_INITIAL', 0.0, 0.01, 0.0, 100.0, INV, 'INVALID_VOLUME_STEP')
case('MAX_BELOW_MIN', 0.1, 1.0, 0.01, 0.5, INV, 'VOLUME_MAX_BELOW_MIN')
case('STEP_RANGE_MAX', 0.1, 0.01, 0.01, 1e8, INV, 'STEP_RANGE')
case('MIN_OFF_GRID', 0.1, 0.015, 0.01, 100.0, INV, 'VOLUME_NOT_ON_GRID')
case('MAX_OFF_GRID', 0.1, 0.01, 0.01, 5.005, INV, 'VOLUME_NOT_ON_GRID')
case('INITIAL_OFF_GRID', 0.105, 0.01, 0.01, 100.0, INV, 'VOLUME_NOT_ON_GRID')
case('INITIAL_BELOW_ONE_STEP', 0.004, 0.01, 0.01, 100.0, INV, 'VOLUME_NOT_ON_GRID')
case('INITIAL_BELOW_MIN', 0.05, 0.10, 0.01, 100.0, INV, 'INITIAL_BELOW_MIN')
case('INITIAL_ABOVE_MAX', 200.0, 0.01, 0.01, 100.0, INV, 'INITIAL_ABOVE_MAX')


def _num(v):
    return repr(float(v))


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t011_split_fixtures.py emit_mql)']
    out.append('#define NCASES %d' % len(CASES))

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    arr('string', 'C_NAME', ['"%s"' % c['name'] for c in CASES])
    for i, nm in enumerate(('C_INIT', 'C_VMIN', 'C_STEP', 'C_VMAX')):
        arr('double', nm, [_num(c['p'][i]) for c in CASES])
    arr('string', 'X_STATUS', ['"%s"' % c['status'] for c in CASES])
    arr('string', 'X_WHY', ['"%s"' % c['why'] for c in CASES])
    ex = [c['steps'] if c['steps'] is not None else (0, 0, 0) for c in CASES]
    arr('long', 'X_N', [str(x[0]) for x in ex])
    arr('long', 'X_CLOSE', [str(x[1]) for x in ex])
    arr('long', 'X_REM', [str(x[2]) for x in ex])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
