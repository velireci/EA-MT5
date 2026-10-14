#!/usr/bin/env python3
"""Pattern checks for tools/t006-static-checks.sh (comments and string literals are stripped first where stated).
Reuses strip / trading / nofeed from tools/t005-static-check.py (read-only import); adds the sizing-specific checks.

Usage: t006-static-check.py trading|nofeed|nodefaults|contract|parity|guards FILE...
  trading   : no order / position / trade-class API (module and test)
  nofeed    : no quote, tick, symbol/account read, indicator, series or clock access (every number is an argument)
  nodefaults: no hidden 0.01 step or hidden 10 lot cap literal in the module code (FILE... = .mqh and reference .py)
  contract  : header and strings keep the required statements; labels are returned by code
  parity    : (FILE... = .mqh then reference .py) status enum, statuses, reason tags in the SAME first-occurrence order
              inside PS_Compute / size, and the four numeric constants
  guards    : (FILE... = .mqh then reference .py) round-down arithmetic and the never-exceed loop use the same expression
              in both languages; no ceil / round / NormalizeDouble; limits are checked min -> max -> cap
Exit 0 = pass, 1 = findings printed.
"""
import importlib.util
import os
import re
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('t005check', os.path.join(_here, 't005-static-check.py'))
t5 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(t5)

TAGS = ['GEOMETRY_NOT_OK', 'INVALID_STOP_TICKS', 'INVALID_RISK_BUDGET', 'INVALID_TICK_VALUE', 'INVALID_VOLUME_MIN',
        'INVALID_VOLUME_STEP', 'INVALID_VOLUME_MAX', 'INVALID_CAP', 'VOLUME_MAX_BELOW_MIN', 'STEP_RANGE',
        'VOLUME_NOT_ON_GRID', 'NUMERIC_OVERFLOW', 'SKIP_BELOW_MIN_VOLUME', 'SKIP_ABOVE_MAX_VOLUME', 'SKIP_ABOVE_CAP']
STATUSES = {'OK', 'INVALID_INPUT', 'GEOMETRY_NOT_OK', 'SKIP_BELOW_MIN_VOLUME', 'SKIP_ABOVE_MAX_VOLUME', 'SKIP_ABOVE_CAP'}
CONSTS = (('PS_EPS_STEPS', 'EPS_STEPS'), ('PS_CAP_ULPS', 'CAP_ULPS'), ('PS_MAX_STEPS', 'MAX_STEPS'), ('PS_MAX_RAW_STEPS', 'MAX_RAW_STEPS'),
          ('PS_MAX_STOP_TICKS', 'MAX_STOP_TICKS'))
REQUIRED = ['LINEAR MODEL', 'NOT a guarantee', 'COSTS_NOT_MODELLED', 'does NOT choose the base of the 1%', 'tick_value',
            'ONE tick for ONE LOT in ACCOUNT currency', 'NEVER raised to volume_min', 'reduced_to_limit',
            'first failure wins', 'NOT handled here', 'combined 2%', '80/20 partial volume rounding', 'NOT wired',
            'volume_step = 0.01 is NEVER assumed', 'rounded DOWN']


def read(f):
    return open(f, encoding='ascii').read()


def check_trading(files):
    return t5.check_trading(files)


def check_nofeed(files):
    return t5.check_nofeed(files)


def check_nodefaults(files):
    bad = 0
    lit = re.compile(r'(?<![\w.])(0\.01|10\.0|10)(?![\w.])')
    for f in files:
        text = t5.strip(read(f)) if f.endswith('.mqh') else re.sub(r'(?s)""".*?"""|#[^\n]*', '', read(f))
        if f.endswith('.py'):
            text = re.sub(r"'[^'\n]*'", "''", text)
        for m in lit.finditer(text):
            print('%s: hidden default literal %s' % (f, m.group(0)))
            bad = 1
    return bad


def check_contract(files):
    bad = 0
    for f in files:
        raw = read(f)
        for req in REQUIRED:
            if req not in raw:
                print('%s: required contract text missing: %s' % (f, req))
                bad = 1
        code = t5.strip(raw, keep_strings=True) if f.endswith('.mqh') else re.sub(r'(?s)""".*?"""|#[^\n]*', '', raw)
        for lab in ('COSTS_NOT_MODELLED', 'LINEAR_MODEL', 'NO_REDUCTION_TO_LIMIT'):
            if lab not in code:
                print('%s: label %s is not returned by code (only in comments)' % (f, lab))
                bad = 1
    return bad


def body(text, start):
    i = text.find(start)
    return text[i:] if i >= 0 else ''


def tag_order(code):
    seq = []
    for m in re.finditer(r'[\'"](%s)\b' % '|'.join(TAGS), code):
        if m.group(1) not in seq:
            seq.append(m.group(1))
    return seq


def check_parity(files):
    mqh_raw, ref_raw = read(files[0]), read(files[1])
    mqh = t5.strip(mqh_raw, keep_strings=True)
    ref = re.sub(r'(?s)""".*?"""|#[^\n]*', '', ref_raw)
    bad = 0
    enum = re.search(r'enum\s+ENUM_PS_STATUS\s*\{(.*?)\}', mqh, re.S)
    got = {x.strip().split('=')[0].replace('PS_', '', 1) for x in enum.group(1).split(',')} if enum else set()
    if got != STATUSES:
        print('MQL5 status enum differs: only-mql=%s only-ref=%s' % (sorted(got - STATUSES), sorted(STATUSES - got)))
        bad = 1
    ref_status = set(re.findall(r"^([A-Z_]+) = '\1'$", ref, re.M))
    if not STATUSES <= ref_status:
        print('reference lacks statuses: %s' % sorted(STATUSES - ref_status))
        bad = 1
    for name in STATUSES:
        if '"%s"' % name not in mqh:
            print('PS_StatusName does not return "%s"' % name)
            bad = 1
    a, b = tag_order(body(mqh, 'bool PS_Compute')), tag_order(body(ref, 'def size('))
    if a != b or set(a) != set(TAGS):
        print('reason tags / first-failure order differ: mqh=%s py=%s' % (a, b))
        bad = 1
    for cm, cp in CONSTS:
        x = re.search(r'#define\s+%s\s+(\S+)' % cm, mqh)
        y = re.search(r'^%s\s*=\s*(\S+)' % cp, ref, re.M)
        if not x or not y or float(x.group(1)) != float(y.group(1)):
            print('%s / %s differs or is missing: mqh=%s py=%s' % (cm, cp, x and x.group(1), y and y.group(1)))
            bad = 1
    for lab in ('COSTS_NOT_MODELLED', 'LINEAR_MODEL (loss per lot at SL = stop ticks * tick value; not the broker real loss)',
                'NO_REDUCTION_TO_LIMIT (a limit conflict is a SKIP; volume is never raised to min or clamped to max/cap)'):
        if lab not in mqh_raw or lab not in ref_raw:
            print('label differs or is missing: %s' % lab)
            bad = 1
    return bad


def check_guards(files):
    mqh = t5.strip(read(files[0]), keep_strings=True)
    ref = re.sub(r'(?s)""".*?"""|#[^\n]*', '', read(files[1]))
    bad = 0
    must_mqh = [r'MathFloor\(raw_steps\+PS_EPS_STEPS\)', r'while\(n>0 && \(double\)n\*risk_per_step>risk_budget\)', r'\n\s+n--;',
                r'risk_realized=\(double\)n\*risk_per_step', r'volume_out=\(double\)n\*volume_step',
                r'raw_steps=risk_budget/risk_per_step', r'risk_per_step=volume_step\*loss_per_lot',
                r'loss_per_lot=\(double\)stop_ticks\*tick_value', r'cap_steps=\(long\)MathFloor\(cap_x\+PS_CAP_ULPS\*DBL_EPSILON\*MathMax\(1\.0,cap_x\)\)',
                r'volume_max<volume_min', r'PS_GridSteps\(volume_min,volume_step\)', r'PS_GridSteps\(volume_max,volume_step\)',
                r'MathAbs\(x-k\)>PS_EPS_STEPS']
    must_py = [r'math\.floor\(raw_steps \+ EPS_STEPS\)', r'while n > 0 and n \* risk_per_step > risk_budget:', r'\n\s+n -= 1',
               r'risk_realized = n \* risk_per_step', r'volume_out = n \* volume_step',
               r'raw_steps = risk_budget / risk_per_step', r'risk_per_step = volume_step \* loss_per_lot',
               r'loss_per_lot = float\(stop_ticks\) \* tick_value', r'cap_steps = int\(math\.floor\(cap_x \+ CAP_ULPS \* DBL_EPSILON \* max\(1\.0, cap_x\)\)\)', r'\nDBL_EPSILON = 2\.220446049250313e-16',
               r'volume_max < volume_min', r'_grid_steps\(volume_min, volume_step\)', r'_grid_steps\(volume_max, volume_step\)',
               r'abs\(x - k\) > EPS_STEPS']
    for pat in must_mqh:
        if not re.search(pat, mqh):
            print('%s: sizing expression missing in MQL5: %s' % (files[0], pat))
            bad = 1
    for pat in must_py:
        if not re.search(pat, ref):
            print('%s: sizing expression missing in Python: %s' % (files[1], pat))
            bad = 1
    for lang, text, forb in (('MQL5', mqh, r'MathCeil|MathRound|NormalizeDouble|\bceil\b'), ('Python', ref, r'math\.ceil|\bround\(|\bint\(round')):
        m = re.search(forb, text)
        if m:
            print('%s code uses a rounding that can round UP or change the grid: %s' % (lang, m.group(0)))
            bad = 1
    for lang, text, pats in (('MQL5', mqh, (r'n<min_steps', r'n>max_steps', r'n>cap_steps')),
                             ('Python', ref, (r'n < min_steps', r'n > max_steps', r'n > cap_steps'))):
        pos = [re.search(pt, text) for pt in pats]
        if not all(pos) or not (pos[0].start() < pos[1].start() < pos[2].start()):
            print('%s: limits must be checked min -> max -> cap' % lang)
            bad = 1
    for lang, text in (('MQL5', mqh), ('Python', ref)):
        if re.search(r'reduced_to_limit', text):
            print('%s code defines reduced_to_limit (the module never reduces to a limit)' % lang)
            bad = 1
    return bad


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    kind, files = argv[1], argv[2:]
    fn = {'trading': check_trading, 'nofeed': check_nofeed, 'nodefaults': check_nodefaults, 'contract': check_contract,
          'parity': check_parity, 'guards': check_guards}.get(kind)
    if fn is None:
        print('unknown check', kind)
        return 2
    return fn(files)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
