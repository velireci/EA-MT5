#!/usr/bin/env python3
"""Pattern checks for tools/t007-static-checks.sh (comments and string literals are stripped first where stated).
Reuses strip / trading / nofeed from tools/t005-static-check.py (read-only import); adds the planning-specific checks.

Usage: t007-static-check.py trading|nofeed|nopersist|contract|parity|guards FILE...
  trading   : no order / position / trade-class API (module and test)
  nofeed    : no quote, tick, symbol/account read, indicator, series or clock access (every value is an argument)
  nopersist : no file / global-variable / network / resource access in MQL5, no file, clock, random or process import in Python
  contract  : header statements present; labels are returned by code (FILE... = .mqh then reference .py)
  parity    : (FILE... = .mqh then reference .py) statuses, stages, cancel statuses, plan/permit/cancel reason tags in the SAME
              first-occurrence order, event order, numeric constants, state constants (also versus the fixtures), labels
  guards    : (FILE... = .mqh then reference .py) boundary comparisons, registration only after an ALLOW and a final bounds guard,
              POLICY_UNSET guards, plan stage/id/value validation, the overflow-free risk comparison (no naive sum), registry
              capacity checks, geometry before sizing, positions_untouched, no rounding/normalization of its own
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

PLAN_TAGS = ['INVALID_SIGNAL_ID', 'INVALID_SETUP_ID', 'GEOMETRY_REFUSED', 'SIZING_REFUSED']
PERMIT_TAGS = ['PLAN_NOT_OK', 'PLAN_INVALID_ID', 'PLAN_INVALID_VALUES', 'DATA_UNRELIABLE', 'DATA_NOT_READY', 'DATA_UNKNOWN', 'INVALID_SNAPSHOT:data_state',
               'SESSION_CLOSED', 'SESSION_UNKNOWN', 'INVALID_SNAPSHOT:session_state', 'NEWS_BLOCK', 'NEWS_UNKNOWN',
               'INVALID_SNAPSHOT:news_state', 'SPREAD_BLOCK', 'SPREAD_UNKNOWN', 'INVALID_SNAPSHOT:spread_state',
               'REGISTRY_INVALID', 'DUPLICATE_SIGNAL', 'REGISTRY_FULL',
               'POLICY_UNSET:max_positions', 'INVALID_SNAPSHOT:max_positions', 'INVALID_SNAPSHOT:open_positions', 'MAX_POSITIONS_REACHED',
               'POLICY_UNSET:max_trades_per_day', 'INVALID_SNAPSHOT:max_trades_per_day', 'INVALID_SNAPSHOT:trades_today', 'MAX_TRADES_REACHED',
               'POLICY_UNSET:combined_risk_cap', 'INVALID_SNAPSHOT:combined_risk_cap', 'INVALID_SNAPSHOT:existing_risk', 'COMBINED_RISK_EXCEEDED']
CANCEL_TAGS = ['INVALID_EVENTS', 'NO_PENDING', 'INVALID_PENDING_SIGNAL_ID', 'NO_EVENT', 'CANCEL_REQUEST']
EVENTS = ['DIRECTION_CHANGE', 'OPPOSITE_SIGNAL', 'SESSION_END', 'NEWS_BLOCK', 'DAILY_LIMIT']
STATUSES = {'OK', 'INVALID_INPUT', 'GEOMETRY_REFUSED', 'SIZING_REFUSED'}
STAGES = {'INPUT', 'GEOMETRY', 'SIZING', 'COMPLETE'}
CANCEL_STATUSES = {'CANCEL_REQUEST', 'NO_PENDING', 'NO_EVENT', 'INVALID_INPUT'}
CONSTS = (('TP_RISK_ULPS', 'RISK_ULPS'), ('TP_MAX_REASONS', 'MAX_REASONS'), ('TP_EV_DIRECTION_CHANGE', 'EV_DIRECTION_CHANGE'),
          ('TP_EV_OPPOSITE_SIGNAL', 'EV_OPPOSITE_SIGNAL'), ('TP_EV_SESSION_END', 'EV_SESSION_END'),
          ('TP_EV_NEWS_BLOCK', 'EV_NEWS_BLOCK'), ('TP_EV_DAILY_LIMIT', 'EV_DAILY_LIMIT'), ('TP_EV_ALL', 'EV_ALL'))
STATES = (('DATA', ('READY', 'NOT_READY', 'UNKNOWN'), 'DATA_INT'), ('SESSION', ('OPEN', 'CLOSED', 'UNKNOWN'), 'SESS_INT'),
          ('NEWS', ('CLEAR', 'BLOCKED', 'UNKNOWN'), 'NEWS_INT'), ('SPREAD', ('CLEAR', 'BLOCKED', 'UNKNOWN'), 'NEWS_INT'))
LABELS = ['PLAN_ONLY / NOT_AN_ORDER', 'PERMIT_ONLY / NOT_AN_ORDER', 'CANCEL_REQUEST_ONLY / NOT_SENT',
          'PARTIAL_AT_2R (client answer: 80% of initial volume; no volume split here)', 'LINEAR_MODEL, COSTS_NOT_MODELLED']
REQUIRED = ['NOT a trading rule', 'NOT an order', 'NOT wired', 'PLAN_ONLY / NOT_AN_ORDER', 'POLICY_UNSET', 'fail closed',
            'NOT atomic, NOT persistent', 'never consumes', 'REGISTRY_FULL', 'never dropped silently', 'PROPOSALS',
            'exactly at the cap is ALLOWED', 'positions_untouched is ALWAYS', 'PERMIT RESULT ONLY', 'NOT decided here',
            'the base of the 1%', 'No expiry by time or candles', 'never invents', 'copies no formula']
MQL_PERSIST = re.compile(r'\b(File\w+|GlobalVariable\w+|Resource\w+|WebRequest|SendMail|SendNotification|SendFTP|Database\w+|'
                         r'FolderCreate|FolderDelete|TerminalInfo\w*|ChartSave\w*|ChartScreenShot|EventSetTimer|EventChart\w+)\b|#import')
PY_PERSIST = re.compile(r'^\s*(import|from)\s+(os|sys|json|pickle|sqlite3|socket|time|datetime|random|shutil|pathlib|subprocess)\b|\bopen\(', re.M)
OWN_ROUNDING_MQL = re.compile(r'\b(MathFloor|MathCeil|MathRound|NormalizeDouble|DoubleToString)\b')
OWN_ROUNDING_PY = re.compile(r'math\.(floor|ceil|trunc)|\bround\(|\bint\(round')


def read(f):
    return open(f, encoding='ascii').read()


def pycode(text):
    return re.sub(r'(?s)""".*?"""|#[^\n]*', '', text)


def check_trading(files):
    return t5.check_trading(files)


def check_nofeed(files):
    return t5.check_nofeed(files)


def check_nopersist(files):
    bad = 0
    for f in files:
        if f.endswith('.py'):
            m = PY_PERSIST.search(pycode(read(f)))
        else:
            m = MQL_PERSIST.search(t5.strip(read(f)))
        if m:
            print('%s: persistence / file / clock / network access %s' % (f, m.group(0).strip()))
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
        code = t5.strip(raw, keep_strings=True) if f.endswith('.mqh') else pycode(raw)
        for lab in LABELS:
            if lab not in code:
                print('%s: label %r is not returned by code (only in comments)' % (f, lab))
                bad = 1
    return bad


def section(text, start, end=None):
    i = text.find(start)
    if i < 0:
        return ''
    j = text.find(end, i + len(start)) if end else -1
    return text[i:j] if j >= 0 else text[i:]


def tag_order(code, tags, prefix_only=False):
    pat = r'[\'"](%s)%s' % ('|'.join(re.escape(t) for t in tags), r'\b' if prefix_only else r'[\'"]')
    seq = []
    for m in re.finditer(pat, code):
        if m.group(1) not in seq:
            seq.append(m.group(1))
    return seq


def check_parity(files):
    mqh_raw, ref_raw = read(files[0]), read(files[1])
    mqh = t5.strip(mqh_raw, keep_strings=True)
    ref = pycode(ref_raw)
    bad = 0
    for enum, prefix, want in (('ENUM_TP_STATUS', 'TP_', STATUSES), ('ENUM_TP_STAGE', 'TP_STAGE_', STAGES),
                               ('ENUM_TP_CANCEL', 'TP_CANCEL_', {'REQUEST', 'NO_PENDING', 'NO_EVENT', 'INVALID_INPUT'})):
        m = re.search(r'enum\s+%s\s*\{(.*?)\}' % enum, mqh, re.S)
        got = {x.strip().split('=')[0].replace(prefix, '', 1) for x in m.group(1).split(',')} if m else set()
        if got != want:
            print('MQL5 %s differs: only-mql=%s only-ref=%s' % (enum, sorted(got - want), sorted(want - got)))
            bad = 1
    for name in STATUSES | STAGES | CANCEL_STATUSES:
        if '"%s"' % name not in mqh:
            print('MQL5 name function does not return "%s"' % name)
            bad = 1
        if "'%s'" % name not in ref:
            print('reference lacks the value %r' % name)
            bad = 1
    for label, tags, ma, ra, prefix in (
            ('plan tags', PLAN_TAGS, section(mqh, 'bool TP_BuildPlan', 'bool TP_CountOk'), section(ref, 'def build_plan', 'class Snapshot'), True),
            ('permit tags', PERMIT_TAGS, section(mqh, 'bool TP_CheckPermit', 'bool TP_Authorize'), section(ref, 'def check_permit', 'def authorize'), False),
            ('cancel tags', CANCEL_TAGS, section(mqh, 'bool TP_CancelDecision', 'string TP_CancelReasonsText'),
             section(ref, 'def cancel_decision'), True)):
        a, b = tag_order(ma, tags, prefix), tag_order(ra, tags, prefix)
        if a != b or set(a) != set(tags):
            print('%s / first-failure order differ: mqh=%s py=%s' % (label, a, b))
            bad = 1
    ev_m = re.findall(r'"(%s)"' % '|'.join(EVENTS), section(mqh, 'bool TP_CancelDecision', 'string TP_CancelReasonsText'))
    ev_p = re.findall(r"'(%s)'" % '|'.join(EVENTS), section(ref, 'EVENT_ORDER =', '\n\n'))
    if ev_m != EVENTS or ev_p != EVENTS:
        print('event order differs: mqh=%s py=%s expected %s' % (ev_m, ev_p, EVENTS))
        bad = 1
    for cm, cp in CONSTS:
        x = re.search(r'#define\s+%s\s+(\S+)' % cm, mqh)
        y = re.search(r'^%s\s*=\s*(\S+)' % cp, ref, re.M)
        if not x or not y or float(x.group(1)) != float(y.group(1)):
            print('%s / %s differs or is missing: mqh=%s py=%s' % (cm, cp, x and x.group(1), y and y.group(1)))
            bad = 1
    spec = importlib.util.spec_from_file_location('t007fx', os.path.join(_here, '..', 'tests', 't007_planning_fixtures.py'))
    fx = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fx)
    for grp, names, table in STATES:
        for n in names:
            x = re.search(r'#define\s+TP_%s_%s\s+(\d+)' % (grp, n), mqh)
            if not x or getattr(fx, table).get(n) != int(x.group(1)) or not re.search(r'\b%s_%s\b' % (grp, n), ref):
                print('state constant %s_%s differs between MQL5, Python and the fixture table %s' % (grp, n, table))
                bad = 1
    for lab in LABELS:
        if lab not in mqh_raw or lab not in ref_raw:
            print('label differs or is missing: %s' % lab)
            bad = 1
    return bad


def check_guards(files):
    mqh = t5.strip(read(files[0]), keep_strings=True)
    ref = pycode(read(files[1]))
    bad = 0
    fields = ('e_out', 's_out', 'tp', 'level_2r', 'partial_price', 'r_geom', 'volume_out', 'risk_model')
    must_mqh = [r'snap\.open_positions>=lim\.max_positions', r'snap\.trades_today>=lim\.max_trades',
                r'plan_ok && TP_RiskExceeded\(snap\.existing_risk,plan\.risk_model,lim\.risk_cap\)',
                r'double tol=TP_RISK_ULPS\*DBL_EPSILON\*MathMax\(1\.0,cap\);\s*double remaining=cap-existing;',
                r'if\(remaining>=0\.0\) return\(\(risk-remaining\)>tol\);\s*double over=-remaining;\s*return\(!\(over<=tol && risk<=tol-over\)\);',
                r'bool plan_complete=\(plan\.status==TP_OK && plan\.stage==TP_STAGE_COMPLETE\);',
                r'bool ids_ok=\(!TP_IsBlank\(plan\.signal_id\) && !TP_IsBlank\(plan\.setup_id\)\);',
                r'bool values_ok=TP_PlanValuesOk\(plan\);', r'bool plan_ok=\(plan_complete && ids_ok && values_ok\);',
                r'if\(!plan_complete\) TP_AddReason\(out,"PLAN_NOT_OK"\);\s*else\s*\{\s*if\(!ids_ok\) TP_AddReason\(out,"PLAN_INVALID_ID"\);\s*if\(!values_ok\) TP_AddReason\(out,"PLAN_INVALID_VALUES"\);',
                r'bool TP_PosFinite\(const double v\) \{return\(TG_Finite\(v\) && v>0\.0\);\}'] + \
               [r'TP_PosFinite\(p\.%s\)' % f for f in fields] + [
                r'if\(!TP_CheckPermit\(plan,snap,lim,reg_ids,reg_count,out\)\)\s*return\(false\);\s*int capacity=ArraySize\(reg_ids\);\s*if\(reg_count<0 \|\| reg_count>=capacity\)[^{]*\{[^}]*return\(false\);\s*\}\s*reg_ids\[reg_count\]=plan\.signal_id;\s*reg_count\+\+;',
                r'if\(!lim\.max_positions_set\) TP_AddReason\(out,"POLICY_UNSET:max_positions"\)',
                r'if\(!lim\.max_trades_set\) TP_AddReason\(out,"POLICY_UNSET:max_trades_per_day"\)',
                r'if\(!lim\.risk_cap_set\) TP_AddReason\(out,"POLICY_UNSET:combined_risk_cap"\)',
                r'out\.positions_untouched=true;', r'events<0 \|\| \(events & ~TP_EV_ALL\)!=0',
                r'if\(capacity<0 \|\| reg_count<0 \|\| reg_count>capacity\) TP_AddReason\(out,"REGISTRY_INVALID"\);\s*else if\(dup\) TP_AddReason\(out,"DUPLICATE_SIGNAL"\);\s*else if\(reg_count>=capacity\) TP_AddReason\(out,"REGISTRY_FULL"\);',
                r'TG_Compute\([^;]*\);\s*if\(geo\.status!=TG_OK\)', r'PS_Compute\(geo,risk_budget,tick_value,volume_min,volume_step,volume_max,cap_lots,siz\);\s*if\(siz\.status!=PS_OK\)',
                r'out\.risk_model=siz\.risk_realized;']
    must_py = [r'snap\.open_positions >= limits\.max_positions', r'snap\.trades_today >= limits\.max_trades_per_day',
               r'plan_ok and _risk_exceeded\(snap\.existing_risk, plan\.risk_model, cap\)',
               r'tol = RISK_ULPS \* DBL_EPSILON \* max\(1\.0, cap\)\n\s+remaining = cap - existing',
               r'if remaining >= 0\.0:\n\s+return \(risk - remaining\) > tol\n\s+over = -remaining\n\s+return not \(over <= tol and risk <= tol - over\)',
               r"plan_complete = getattr\(plan, 'status', None\) == OK and getattr\(plan, 'stage', None\) == STAGE_COMPLETE",
               r"ids_ok = not \(_blank\(getattr\(plan, 'signal_id', None\)\) or _blank\(getattr\(plan, 'setup_id', None\)\)\)",
               r"values_ok = all\(_pos_finite\(getattr\(plan, f, None\)\) for f in PLAN_REQUIRED\)", r'plan_ok = plan_complete and ids_ok and values_ok',
               r"if not plan_complete:\n\s+reasons\.append\('PLAN_NOT_OK'\)\n\s+else:\n\s+if not ids_ok:\n\s+reasons\.append\('PLAN_INVALID_ID'\)\n\s+if not values_ok:\n\s+reasons\.append\('PLAN_INVALID_VALUES'\)",
               r'math\.isfinite\(v\) and v > 0',
               r"PLAN_REQUIRED = \(%s\)" % ', '.join("'%s'" % f for f in fields),
               r'if permit\.decision != ALLOW:\n\s+return permit\n\s+if not _count_ok\(registry\.count\) or registry\.count >= len\(registry\.ids\):[^\n]*\n\s+return Permit\(decision=BLOCK, primary_reason=.REGISTRY_FULL.[^\n]*\n\s+registry\.ids\[registry\.count\] = plan\.signal_id\n\s+registry\.count \+= 1',
               r"if limits\.max_positions is None:\n\s+reasons\.append\('POLICY_UNSET:max_positions'\)",
               r"if limits\.max_trades_per_day is None:\n\s+reasons\.append\('POLICY_UNSET:max_trades_per_day'\)",
               r"if cap is None:\n\s+reasons\.append\('POLICY_UNSET:combined_risk_cap'\)",
               r'positions_untouched: bool = True', r'\(events & ~EV_ALL\) != 0',
               r"if capacity < 0 or not _count_ok\(registry\.count\) or registry\.count > capacity:\n\s+reasons\.append\('REGISTRY_INVALID'\)\n\s+elif not _blank\(sid\) and sid in registry\.ids\[:registry\.count\]:\n\s+reasons\.append\('DUPLICATE_SIGNAL'\)\n\s+elif registry\.count >= capacity:\n\s+reasons\.append\('REGISTRY_FULL'\)",
               r'geo = g5\.compute\([^\n]*\n\s+if geo\.status != g5\.OK:', r'siz = p6\.size\(geo, risk_budget, tick_value, volume_min, volume_step, volume_max, cap_lots\)\n\s+if siz\.status != p6\.OK:',
               r'risk_model=siz\.risk_realized']
    for pat in must_mqh:
        if not re.search(pat, mqh):
            print('%s: guard expression missing in MQL5: %s' % (files[0], pat))
            bad = 1
    for pat in must_py:
        if not re.search(pat, ref):
            print('%s: guard expression missing in Python: %s' % (files[1], pat))
            bad = 1
    for lang, text in (('MQL5', mqh), ('Python', ref)):
        if re.search(r'existing_risk\s*\+\s*plan\.risk_model', text):
            print('%s code forms the naive overflowing sum existing_risk + plan.risk_model (use the overflow-free comparison)' % lang)
            bad = 1
    for lang, text, forb in (('MQL5', mqh, OWN_ROUNDING_MQL), ('Python', ref, OWN_ROUNDING_PY)):
        m = forb.search(text)
        if m:
            print('%s code does its own rounding / normalization (the plan must use the T005/T006 results): %s' % (lang, m.group(0)))
            bad = 1
    for lang, text, forb in (('MQL5', mqh, r'positions_untouched\s*=\s*false'), ('Python', ref, r'positions_untouched\s*=\s*False|positions_untouched:\s*bool\s*=\s*False')):
        if re.search(forb, text):
            print('%s code can set positions_untouched to false' % lang)
            bad = 1
    for lang, text in (('MQL5', mqh), ('Python', ref)):
        m = re.search(r'\b(close_positions?|cancel_positions?|PositionClose\w*|expir\w*|cooldown|reentry|re_entry)\b', text, re.I)
        if m:
            print('%s code names a forbidden concept (%s): no position closing, expiry, cooldown or re-entry in T007' % (lang, m.group(0)))
            bad = 1
    return bad


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    kind, files = argv[1], argv[2:]
    fn = {'trading': check_trading, 'nofeed': check_nofeed, 'nopersist': check_nopersist, 'contract': check_contract,
          'parity': check_parity, 'guards': check_guards}.get(kind)
    if fn is None:
        print('unknown check', kind)
        return 2
    return fn(files)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
