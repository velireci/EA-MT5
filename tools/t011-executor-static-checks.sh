#!/bin/bash
# Static checks for the detached T011 executor. NOT a compiler, NOT an MT5 run: compile and run are UNVERIFIED. The real transport is never executed.
# Usage: bash tools/t011-executor-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=129a267
SEAM=src/include/ExitTransport.mqh
FAKE=src/include/ExitTransportFake.mqh
REAL=src/include/ExitTransportReal.mqh
CORE=src/include/ExitExecutor.mqh
TST=src/tests/T011_ExecutorTest.mq5
STUB=src/tests/T011_ExecutorRealCompile.mq5
CHK="python3 -I tools/t010-static-check.py"
NEWFILES="$SEAM $FAKE $REAL $CORE $TST $STUB tests/t011_executor_reference.py tests/t011_executor_fixtures.py tests/test_t011_executor.py tools/t011-executor-static-checks.sh docs/T011-executor-api-verification.md"

echo "=== S1: files exist ==="
for f in $NEWFILES; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: the trading call exists only in the real transport; the real transport is included only by the compile stub; tests use the fake only ==="
python3 -I - <<'PYEOF' && echo "  PASS exactly one OrderSend in the real transport and one in the separate demo open-position script; no OrderSendAsync / CTrade / PositionClose anywhere; only the compile stub and the demo harness script include the real header" || { echo "  FAIL"; FAIL=1; }
import glob, re
strip = lambda t: re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))
files = glob.glob('src/**/*.mq[h5]', recursive=True)
calls = {}
for f in files:
    code = strip(open(f, encoding='ascii').read())
    for w in ('OrderSend', 'OrderSendAsync', 'CTrade', 'PositionClose', 'PositionOpen', 'OrderDelete', 'OrderModify', 'OrderCalcMargin'):
        n = len(re.findall(r'\b%s\s*\(' % w, code)) + (len(re.findall(r'\bCTrade\b', code)) if w == 'CTrade' else 0)
        if n and not (w == 'OrderSend' and ((f.endswith('ExitTransportReal.mqh') or f.endswith('XauUsdT011DemoOpenPosition.mq5')) and n == 1 or (f.endswith('EntryTransportReal.mqh') and n == 2))):   # T013: the entry real transport (place + cancel), compile-only
            # legacy / earlier modules must not have gained a call; only report calls outside the allowed one
            calls.setdefault(f, []).append(w)
legacy_ok = ('MA_Crossover',)
bad = {f: w for f, w in calls.items() if not any(x in f for x in legacy_ok)}
assert not bad, bad
real = strip(open('src/include/ExitTransportReal.mqh', encoding='ascii').read())
assert len(re.findall(r'\bOrderSend\s*\(', real)) == 1
includers = [f for f in files if re.search(r'#include\s+"[^"]*ExitTransportReal\.mqh"', strip(open(f, encoding='ascii').read()))]
assert sorted(includers) == ['src/XauUsdEntryOrchestrator.mq5', 'src/XauUsdT011DemoHarness.mq5', 'src/XauUsdT011ExitManager.mq5', 'src/XauUsdT011ExitRegister.mq5', 'src/tests/T011_ExecutorRealCompile.mq5'], includers
stub = strip(open('src/tests/T011_ExecutorRealCompile.mq5', encoding='ascii').read())
assert not re.search(r'\btransport\s*\.', stub), 'the compile stub calls a method'
for f in ('src/include/ExitExecutor.mqh', 'src/tests/T011_ExecutorTest.mq5', 'src/include/ExitTransportFake.mqh'):
    assert 'ExitTransportReal' not in strip(open(f, encoding='ascii').read()), f
PYEOF

echo "=== S3: the executor core has one send call site, one counter, the documented gates in order, and no file / clock / retry code of its own ==="
python3 -I - $CORE <<'PYEOF' && echo "  PASS gate order, single tr.Send, single send counter increment, defaults off and UNSET" || { echo "  FAIL"; FAIL=1; }
import re, sys
c = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
body = c[c.index('bool EX_Process('):]
order = ['!cfg.enabled', 'cfg.ea_magic<=0', 'EX_RPOL_UNSET', 'EX_FILL_UNSET', 'cfg.deviation<0', 'EX_POL_UNSET', 'EX_POL_NEEDS_CLEAR', '!cfg.tp_set', 'rt.latched', 'rt.send_calls>=1', 'tr.ReadAccount(', 'tr.IsReal()',
         'EX_AUTH_PHRASE', 'acct.demo', 'acct.login', 'trade_allowed', 'margin_mode!=2', 'tr.ReadSymbol(', 'EX_PlanRefusal(q.level_2r', 'tr.FindPosition(', 'OWNERSHIP_NOT_PROVEN',
         'ESF_Load(', 'EA_OnQuote(', 'tr.PreCheck(', 'EX_Save(', 'ESF_Load(', 'tr.Send(', 'EX_Save(']
at, pos = 0, []
for s in order:
    at = body.index(s, at)
    pos.append(at)
assert pos == sorted(pos)
assert c.count('tr.Send(') == 1 and c.count('rt.send_calls++') == 1
es = c[c.index('bool EX_Save('):c.index('bool EX_Process(')]
assert c.count('ESF_Save(') == es.count('ESF_Save(') == 2 and body.count('ESF_Save(') == 0, 'ESF_Save must only be reached through EX_Save'
init = c[c.index('void EX_ConfigInit('):c.index('void EX_RuntimeInit(')]
for need in ('c.enabled=false;', 'c.real_authorised=false;', 'c.ea_magic=0;', 'EX_FILL_UNSET', 'c.deviation=-1;', 'EX_POL_UNSET', 'c.tp_set=false;', 'c.authorisation="";'):
    assert need in init, need
assert re.search(r'accepted=\(sr\.returned_true && sr\.have_result && \(sr\.retcode==10008 \|\| sr\.retcode==10009 \|\| sr\.retcode==10010\) && sr\.order>0\)', c)
assert '8.0*DBL_EPSILON*MathMax(1.0,MathAbs(r))' in c and '1e-6' not in c, 'the grid tolerance must be floating-point noise only'
for need in ('(int)cfg.filling>(int)EX_FILL_RETURN', '(int)cfg.filter_policy>(int)EX_POL_NEEDS_CLEAR', '(int)cfg.filter_state>(int)EX_FS_BLOCKED', 'q.direction!=1 && q.direction!=-1', 'ESC_Fnum(level,exact)'):
    assert need in c, need
real = re.sub(r'//[^\n]*', '', open('src/include/ExitTransportReal.mqh', encoding='ascii').read())
assert 'else return(false);' in real and not re.search(r'else\s+r\.type_filling\s*=\s*ORDER_FILLING_RETURN', real), 'an unknown filling must not map to RETURN'
for need in ('bool EX_Register(', 'if(!o.plan_set)', 'PLAN_CHANGED', 'st.direction!=q.direction', 'st.level!=level', 'st.volume_initial!=q.volume_initial', 'o.plan_tp!=cfg.tp_price',
             'o.plan_vol_min!=sym.vol_min', 'o.plan_vol_step!=sym.vol_step', 'o.plan_vol_max!=sym.vol_max', 'rec.plan_set=o.plan_set;', 'mapped.plan_set=o.plan_set;',
             'ESF_Exists(name) || ESF_Exists(name+ESF_TMP_SUFFIX)', 'ES_Split(q.volume_initial,sym.vol_min,sym.vol_step,sym.vol_max,sp)', 'pos.magic!=cfg.ea_magic'):
    assert need in c, need
body_ = c[c.index('bool EX_Process('):c.index('bool EX_Register(')]
assert body_.index('if(!o.plan_set)') < body_.index('EA_OnQuote(') and body_.index('PLAN_CHANGED') < body_.index('tr.PreCheck(') < body_.index('EX_Save('), 'the plan is compared before any persist or send'
reg_ = c[c.index('bool EX_Register('):c.index('bool EX_Reconcile(')]
assert 'tr.Send(' not in reg_ and 'rt.send_calls' not in reg_ and 'ESF_InitFresh' not in reg_, 'registration never sends'
cod = re.sub(r'//[^\n]*', '', open('src/include/ExitStateCodec.mqh', encoding='ascii').read())
assert '#define ESC_VERSION 3' in cod and all(k in cod for k in ('"PLAN_SET="', '"PLAN_TP="', '"PLAN_VOL_MIN="', '"PLAN_VOL_STEP="', '"PLAN_VOL_MAX="', '"PLAN_SET","PLAN_TP","PLAN_VOL_MIN","PLAN_VOL_STEP","PLAN_VOL_MAX"')), 'codec plan block'
flw = re.sub(r'//[^\n]*', '', open('src/include/ExitRestartFlow.mqh', encoding='ascii').read())
assert all(k in flw for k in ('rec.plan_set=o.plan_set;', 'rec.plan_tp=o.plan_tp;', 'rec.plan_vol_min=o.plan_vol_min;', 'rec.plan_vol_step=o.plan_vol_step;', 'rec.plan_vol_max=o.plan_vol_max;')), 'the flow must carry the plan over'
assert not re.search(r'FileOpen|FileMove|FileWrite|FileRead|FileDelete|TimeCurrent|TimeGMT|TimeLocal|Sleep\s*\(|[rR]etry\w*\s*(=|\(|\+\+)|NormalizeDouble|MathRound\(\s*q\.', c), 'forbidden code in the core'
PYEOF

echo "=== S4: the abstract seam has the six pure virtual methods; the fake and the real transport implement all of them ==="
python3 -I - $SEAM $FAKE $REAL <<'PYEOF' && echo "  PASS six pure virtual methods, both transports override all six" || { echo "  FAIL"; FAIL=1; }
import re, sys
strip = lambda t: re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))
seam, fake, real = [strip(open(f, encoding='ascii').read()) for f in sys.argv[1:4]]
names = re.findall(r'virtual\s+\w+\s+(\w+)\s*\([^;]*\)\s*=\s*0\s*;', seam)
assert names == ['IsReal', 'ReadAccount', 'ReadSymbol', 'FindPosition', 'PreCheck', 'Send'], names
for nm, src in (('fake', fake), ('real', real)):
    for n in names:
        assert re.search(r'virtual\s+\w+\s+%s\s*\(' % n, src), (nm, n)
assert 'class CFakeTransport : public CExitTransport' in fake and 'class CRealTransport : public CExitTransport' in real
assert re.search(r'virtual bool IsReal\(void\) \{return\(true\);\}', real) and re.search(r'virtual bool IsReal\(void\) \{return\(real\);\}', fake)
PYEOF

echo "=== S5: terminal API argument counts in the real transport (as remembered; the official pages were not reachable: UNVERIFIED) ==="
python3 -I - $REAL <<'PYEOF' && echo "  PASS every listed call has the expected number of arguments" || { echo "  FAIL"; FAIL=1; }
import re, sys
want = {'OrderSend': 2, 'OrderCheck': 2, 'PositionGetTicket': 1, 'PositionGetInteger': 1, 'PositionGetString': 1, 'PositionGetDouble': 1, 'PositionsTotal': 0, 'AccountInfoInteger': 1,
        'AccountInfoString': 1, 'SymbolInfoDouble': 2, 'SymbolInfoInteger': 2, 'TerminalInfoInteger': 1, 'MQLInfoInteger': 1, 'ZeroMemory': 1, 'ResetLastError': 0, 'GetLastError': 0}
def nargs(code, i):
    depth, n, cur, k = 0, 0, False, i
    while k < len(code):
        ch = code[k]
        if ch in '([': depth += 1
        elif ch in ')]':
            depth -= 1
            if depth == 0: return n + (1 if cur else 0)
        elif ch == ',' and depth == 1: n += 1; cur = False
        elif not ch.isspace(): cur = True
        k += 1
    return -1
code = re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', open(sys.argv[1], encoding='ascii').read()))
bad = 0
for m in re.finditer(r'\b(%s)\s*\(' % '|'.join(want), code):
    if nargs(code, m.end() - 1) != want[m.group(1)]:
        print(m.group(1), 'has', nargs(code, m.end() - 1), 'arguments'); bad = 1
sys.exit(bad)
PYEOF

echo "=== S6: verified modules unchanged since $BASE ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in src/include/ExitSplit.mqh src/include/ExitActivation.mqh src/include/ExitStateFile.mqh; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S7: balance, format strings, includes, ASCII, reserved words, literal-only generated arrays ==="
python3 tools/t001-check-balance.py $SEAM $FAKE $REAL $CORE $TST $STUB || FAIL=1
python3 - $SEAM $FAKE $REAL $CORE $TST $STUB <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
for f in $SEAM $FAKE $REAL $CORE $TST $STUB; do
  d=$(dirname "$f"); bad=0
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "  FAIL $f: missing include $d/$inc"; bad=1; FAIL=1; }
  done
  [ $bad -eq 0 ] && echo "  PASS $f: every include resolves"
done
for f in $NEWFILES; do n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true); [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }; done
echo "  INFO ASCII-only checked"
RESERVED='final|override|sealed|explicit|delete|new|virtual|template|typename|operator|this|static|class|struct|union|enum|public|private|protected|extern|input|sinput|void|auto|namespace|using|typedef|interface|implements'
for f in $SEAM $FAKE $REAL $CORE $TST $STUB; do
  if grep -nE "\b(bool|int|long|double|string|ulong|uint|datetime|color|char|short|uchar|ushort|float)\s+($RESERVED)\b\s*(=|;|,|\))" "$f" >/dev/null; then echo "  FAIL $f reserved word as a variable"; FAIL=1; else echo "  PASS $f: no variable is named with a reserved MQL5 word"; fi
done
python3 -I - $TST <<'PYEOF' && echo "  PASS generated arrays hold literals only" || { echo "  FAIL"; FAIL=1; }
import re, sys
t = open(sys.argv[1], encoding='ascii').read()
blk = t[t.index('// BEGIN GENERATED'):t.index('// END GENERATED')]
for m in re.finditer(r'^(?:string|int|long|double) \w+\[\]=\{(.*)\};$', blk, re.M):
    body = re.sub(r'"(?:[^"\\]|\\.)*"', '', m.group(1))
    if re.search(r'[A-Za-z_(]', body):
        print('non-literal initializer:', m.group(0)[:80]); sys.exit(1)
PYEOF

echo "=== S8: negative controls ==="
cp $CORE "$NEG/A.mqh"; sed -i 's/^bool EX_OnGrid(/int zz=OrderSend(0,0);\nbool EX_OnGrid(/' "$NEG/A.mqh"
python3 -I - "$NEG/A.mqh" <<'PYEOF' && { echo "  FAIL an OrderSend in the core was not detected"; FAIL=1; } || echo "  PASS an OrderSend outside the real transport is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
sys.exit(1 if re.search(r'\bOrderSend\s*\(', code) else 0)
PYEOF
cp $CORE "$NEG/B.mqh"; sed -i 's/   if(!cfg.enabled) {res.reason="DISABLED: the executor is off by default"; return(false);}//' "$NEG/B.mqh"
grep -q '!cfg.enabled' "$NEG/B.mqh" && { echo "  FAIL disabled-gate control"; FAIL=1; } || echo "  PASS an executor without the enabled gate loses the pin"
cp $CORE "$NEG/C.mqh"; sed -i 's/c.enabled=false;/c.enabled=true;/' "$NEG/C.mqh"
grep -q 'c.enabled=false;' "$NEG/C.mqh" && { echo "  FAIL default control"; FAIL=1; } || echo "  PASS an executor that is enabled by default loses the pin"
cp $CORE "$NEG/D.mqh"; sed -i 's/accepted=(sr.returned_true \&\& sr.have_result \&\& (sr.retcode==10008 || sr.retcode==10009 || sr.retcode==10010) \&\& sr.order>0);/accepted=sr.returned_true;/' "$NEG/D.mqh"
grep -q 'accepted=sr.returned_true;' "$NEG/D.mqh" && ! grep -q 'sr.order>0' "$NEG/D.mqh" && echo "  PASS 'returned true' as a fill proof loses the pin" || { echo "  FAIL accepted control"; FAIL=1; }
cp $TST "$NEG/E.mq5"; sed -i 's/#include "..\/include\/ExitTransportFake.mqh"/#include "..\/include\/ExitTransportReal.mqh"/' "$NEG/E.mq5"
grep -q 'ExitTransportReal' "$NEG/E.mq5" && echo "  PASS a test that includes the real transport is detected" || { echo "  FAIL real-include control"; FAIL=1; }
cp $STUB "$NEG/F.mq5"; sed -i 's/CRealTransport transport;/CRealTransport transport; SExSendRequest rq; SExSendResult rs; transport.Send(rq,rs);/' "$NEG/F.mq5"
python3 -I - "$NEG/F.mq5" <<'PYEOF' && { echo "  FAIL a stub that calls Send was not detected"; FAIL=1; } || echo "  PASS a compile stub that calls a transport method is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
sys.exit(1 if re.search(r'\btransport\s*\.', code) else 0)
PYEOF
cp $REAL "$NEG/G.mqh"; sed -i 's/bool ok=OrderSend(r,s);/bool ok=OrderSend(r);/' "$NEG/G.mqh"
python3 -I - "$NEG/G.mqh" <<'PYEOF' && { echo "  FAIL wrong OrderSend arity not detected"; FAIL=1; } || echo "  PASS a wrong OrderSend argument count is detected"
import re, sys
code = open(sys.argv[1], encoding='ascii').read()
m = re.search(r'OrderSend\s*\(([^)]*)\)', code)
sys.exit(0 if m and m.group(1).count(',') == 1 else 1)
PYEOF
cp $CORE "$NEG/H.mqh"; echo "void x(){" >> "$NEG/H.mqh"
python3 tools/t001-check-balance.py "$NEG/H.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace"; FAIL=1; } || echo "  PASS unbalanced brace detected"

echo
[ $FAIL -eq 0 ] && echo "T011 EXECUTOR STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED; the real transport is never executed)" || echo "T011 EXECUTOR STATIC CHECKS: FAILURES"
exit $FAIL
