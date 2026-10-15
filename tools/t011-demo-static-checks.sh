#!/bin/bash
# Static checks for the T011 demo package (harness, lock, open-position step, presets). NOT a compiler, NOT an MT5 run; the real transport is never executed.
# Usage: bash tools/t011-demo-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=0356f39
LOCK=src/include/ExitInstanceLock.mqh
CORE=src/include/DemoHarness.mqh
HAR=src/XauUsdT011DemoHarness.mq5
OPEN=src/XauUsdT011DemoOpenPosition.mq5
GUARD=src/include/DemoOpenGuard.mqh
GTST=src/tests/T011_DemoOpenGuardTest.mq5
TST=src/tests/T011_DemoHarnessTest.mq5
CHK="python3 -I tools/t010-static-check.py"
NEWFILES="$LOCK $CORE $HAR $OPEN $TST $GUARD $GTST $GUARD $GTST tests/t011_demo_open_reference.py tests/t011_demo_reference.py tests/test_t011_demo.py tools/t011-demo-static-checks.sh docs/T011-demo-package.md src/presets/XauUsdT011Demo_01_status.set src/presets/XauUsdT011Demo_02_register.set src/presets/XauUsdT011Demo_03_activate.set src/presets/XauUsdT011Demo_04_reconcile.set src/presets/XauUsdT011DemoOpenPosition.set"

echo "=== S1: files exist ==="
for f in $NEWFILES; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: trading calls only where intended; no deletion; no signal code; the harness core and the lock never touch a transport or a file ==="
python3 -I - $LOCK $CORE $HAR $OPEN $TST $GUARD $GTST $GUARD $GTST <<'PYEOF' && echo "  PASS OrderSend: real transport + open-position script only; no CTrade / async / close; no FileDelete or GlobalVariableDel outside the test; no price-series or timer code" || { echo "  FAIL"; FAIL=1; }
import re, sys
strip = lambda t: re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))
lock, core, har, opn, tst, grd, gts = [strip(open(f, encoding='ascii').read()) for f in sys.argv[1:8]]
for name, code in (('lock', lock), ('core', core), ('harness', har), ('open', opn), ('test', tst), ('guard', grd), ('guard test', gts)):
    for w in ('OrderSendAsync', 'CTrade', 'PositionClose', 'PositionOpen', 'OrderDelete', 'OrderModify'):
        assert not re.search(r'\b%s\b' % w, code), (name, w)
    for w in ('iHigh', 'iLow', 'iClose', 'iOpen', 'CopyRates', 'CopyHigh', 'CopyLow', 'CopyClose', 'OnTick', 'OnTimer', 'EventSetTimer', 'Sleep'):
        assert not re.search(r'\b%s\b' % w, code), (name, w)
for name, code in (('lock', lock), ('core', core), ('harness', har), ('open', opn), ('guard', grd)):
    assert not re.search(r'FileDelete|GlobalVariableDel|GlobalVariablesDeleteAll|FileMove', code), (name, 'deletes something')
assert not re.search(r'\bOrderSend\s*\(|OrderCheck', core + lock + har + tst + grd + gts), 'trading call outside the real transport / open-position script'
assert len(re.findall(r'\bOrderSend\s*\(', opn)) == 1
assert not re.search(r'\bFile\w+\s*\(', core + lock + har + opn + grd), 'direct file access (records go through ExitStateFile only)'
assert not re.search(r'ESF_(Save|InitFresh|Load)|FileMove', grd), 'the open guard uses only ESF_Exists / ESF_WriteAll / ESF_ReadAll'
assert 'ExitTransportReal' not in grd and 'ExitTransportReal' not in gts
assert 'ExitTransportReal' not in core and 'ExitTransportReal' not in tst and 'ExitTransportReal' not in opn
assert '#include "include/ExitTransportReal.mqh"' in har
PYEOF
out=$($CHK trading $CORE $LOCK $TST $GUARD $GTST) && echo "  PASS no order structure in the core, the lock or the test" || { echo "$out"; FAIL=1; }

echo "=== S3: disabled by default, mandatory parameters UNSET, acting steps behind the lock, the separate open-position step fully gated ==="
python3 -I - $CORE $HAR $OPEN $GUARD <<'PYEOF' && echo "  PASS defaults, gate order, one DM_Run call, open-position gates in order" || { echo "  FAIL"; FAIL=1; }
import re, sys
strip = lambda t: re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))
core, har, opn, grd = [strip(open(f, encoding='ascii').read()) for f in sys.argv[1:5]]
init = core[core.index('void DM_ParamsInit('):core.index('void DM_Set(')]
for need in ('p.step=DM_STEP_NONE;', 'p.authorisation="";', 'p.confirm_send_once=false;', 'p.magic=0;', 'p.position_id=0;', 'p.symbol="";', 'DM_DIR_UNSET', 'p.level_2r=-1.0;', 'p.tp_price=-1.0;',
             'p.volume_initial=0.0;', 'EX_FILL_UNSET', 'p.deviation=-1;', 'EX_POL_UNSET', 'EX_FS_UNKNOWN'):
    assert need in init, need
run = core[core.index('bool DM_Run('):]
order = ['DM_STEP_NONE', 'INPUT_UNSET: position_id or symbol', 'tr.ReadAccount(', 'DM_STEP_STATUS', 'cfg.real_authorised=(p.authorisation==EX_AUTH_PHRASE)', 'EL_Acquire(', 'EX_Register(', 'p.confirm_send_once',
         'EX_Process(', 'EX_Reconcile(', 'EL_Release(']
at, pos = 0, []
for s in order:
    at = run.index(s, at)
    pos.append(at)
assert pos == sorted(pos), list(zip(order, pos))
assert run.count('EX_Process(') == 1 and run.count('EX_Register(') == 1 and run.count('EL_Acquire(') == 1
assert 'tr.Send(' not in core
for need in ('input ENUM_DM_STEP InpStep=DM_STEP_NONE;', 'input string InpAuthorisation="";', 'input bool InpConfirmSendOnce=false;'):
    assert need in har, need
assert har.count('DM_Run(') == 1
for need in ('input bool InpEnabled=false;', 'input string InpAuthorisation="";', 'input long InpEaMagic=0;', 'input ENUM_OP_DIRECTION InpDirection=OP_DIR_UNSET;', 'input double InpVolume=0;',
             'input double InpStopLossDistance=0;', 'input double InpTakeProfitDistance=0;', 'input ENUM_EX_FILLING InpFilling=EX_FILL_UNSET;', 'input long InpDeviation=-1;'):
    assert need in opn, need
flat = re.sub(r'\s+', '', opn)
gates = ['if(!InpEnabled)', 'InpAuthorisation!=OP_AUTH_PHRASE', 'ACCOUNT_TRADE_MODE_DEMO', 'ACCOUNT_MARGIN_MODE_RETAIL_HEDGING', 'TERMINAL_TRADE_ALLOWED', 'InpEaMagic<=0', 'InpSymbol!=_Symbol',
         '(int)InpDirection!=(int)OP_DIR_BUY&&(int)InpDirection!=(int)OP_DIR_SELL', 'InpDeviation<0', 'EX_OnGrid(InpVolume,vstep)', 'ES_Split(', 'OPG_Run(']
at, pos = 0, []
for s in gates:
    at = flat.index(s, at)
    pos.append(at)
assert pos == sorted(pos), list(zip(gates, pos))
assert 'InpDirection==OP_DIR_UNSET' not in flat
onstart = opn[opn.index('void OnStart()'):]
assert onstart.index('OPG_Run(') < onstart.index('PositionsTotal'), 'a look at positions before the guard'
for w in ('EL_Acquire(', 'OrderCheck(', 'OrderSend('):
    assert w not in onstart, w
run = grd[grd.index('bool OPG_Run('):]
inlock = ['EL_Acquire(', 'ESF_Exists(intent_name)', 'CountPositions()', 'CountOrders()', 'PreCheck()', 'ESF_WriteAll(intent_name', 'ESF_ReadAll(intent_name,back)', 'port.Send(', 'EL_Release(']
at, pos = 0, []
for s in inlock:
    at = run.index(s, at)
    pos.append(at)
assert pos == sorted(pos), list(zip(inlock, pos))
assert grd.count('port.Send(') == 1 and run.count('EL_Release(') == run.count('return(false);') + run.count('return(true);') - 1
PYEOF

echo "=== S4: terminal API argument counts in the new files (as remembered; official pages unreadable: UNVERIFIED) ==="
python3 -I - $LOCK $HAR $OPEN $GUARD <<'PYEOF' && echo "  PASS every listed call has the expected number of arguments" || { echo "  FAIL"; FAIL=1; }
import re, sys
want = {'OrderSend': 2, 'OrderCheck': 2, 'GlobalVariableCheck': 1, 'GlobalVariableTemp': 1, 'GlobalVariableSetOnCondition': 3, 'GlobalVariableSet': 2, 'PositionsTotal': 0, 'PositionGetTicket': 1,
        'PositionGetString': 1, 'PositionGetInteger': 1, 'PositionGetDouble': 1, 'SymbolInfoTick': 2, 'SymbolInfoDouble': 2, 'SymbolInfoInteger': 2, 'AccountInfoInteger': 1, 'TerminalInfoInteger': 1,
         'MQLInfoInteger': 1, 'ZeroMemory': 1, 'OrdersTotal': 0, 'OrderGetTicket': 1, 'OrderGetString': 1, 'OrderGetInteger': 1, 'FileIsExist': 1, 'NormalizeDouble': 2, 'GetLastError': 0, 'ResetLastError': 0}
def nargs(code, i):
    depth, n, cur, k = 0, 0, False, i
    while k < len(code):
        ch = code[k]
        if ch in '([': depth += 1
        elif ch in ')]':
            depth -= 1
            if depth == 0: return n + (1 if cur else 0)
        elif ch == ',' and depth == 1: n += 1; cur = False
        elif ch == '"':
            k += 1
            while code[k] != '"':
                k += 2 if code[k] == '\\' else 1
            cur = True
        elif not ch.isspace(): cur = True
        k += 1
    return -1
bad = 0
for f in sys.argv[1:]:
    code = re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', open(f, encoding='ascii').read()))
    for m in re.finditer(r'\b(%s)\s*\(' % '|'.join(want), code):
        if nargs(code, m.end() - 1) != want[m.group(1)]:
            print(f, m.group(1), 'has', nargs(code, m.end() - 1), 'arguments'); bad = 1
sys.exit(bad)
PYEOF

echo "=== S5: verified modules unchanged since $BASE ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in src/include/ExitSplit.mqh src/include/ExitActivation.mqh src/include/ExitReconciliation.mqh src/include/ExitSnapshotAdapter.mqh src/include/ExitStateCodec.mqh src/include/ExitStateFile.mqh src/include/ExitRestartFlow.mqh src/include/ExitExecutor.mqh src/include/ExitTransport.mqh src/include/ExitTransportFake.mqh src/include/ExitTransportReal.mqh src/XauUsdTradePreview.mq5; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S6: balance, format strings, includes, ASCII, reserved words ==="
python3 tools/t001-check-balance.py $LOCK $CORE $HAR $OPEN $TST $GUARD $GTST || FAIL=1
python3 - $LOCK $CORE $HAR $OPEN $TST $GUARD $GTST <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
for f in $LOCK $CORE $HAR $OPEN $TST $GUARD $GTST; do
  d=$(dirname "$f"); bad=0
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "  FAIL $f: missing include $d/$inc"; bad=1; FAIL=1; }
  done
  [ $bad -eq 0 ] && echo "  PASS $f: every include resolves"
done
for f in $NEWFILES; do n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true); [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }; done
echo "  INFO ASCII-only checked"
RESERVED='final|override|sealed|explicit|delete|new|virtual|template|typename|operator|this|static|class|struct|union|enum|public|private|protected|extern|input|sinput|void|auto|namespace|using|typedef|interface|implements'
for f in $LOCK $CORE $HAR $OPEN $TST $GUARD $GTST; do
  if grep -nE "\b(bool|int|long|double|string|ulong|uint|datetime|color|char|short|uchar|ushort|float)\s+($RESERVED)\b\s*(=|;|,|\))" "$f" >/dev/null; then echo "  FAIL $f reserved word as a variable"; FAIL=1; else echo "  PASS $f: no variable is named with a reserved MQL5 word"; fi
done
# the unused-variable warning of the executor test (Codex): no declared-but-unused local in the executor test
python3 -I - src/tests/T011_ExecutorTest.mq5 <<'PYEOF' && echo "  PASS T011_ExecutorTest.mq5: the unused variable 'w' is gone and no local string/int/bool is declared without being used" || { echo "  FAIL"; FAIL=1; }
import re, sys
code = re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', open(sys.argv[1], encoding='ascii').read()))
for fn in re.finditer(r'\n(?:void|bool|string|int)\s+\w+\([^)]*\)\n  \{(.*?)\n  \}', code, re.S):
    body = fn.group(1)
    for decl in re.finditer(r'^\s*(?:string|int|bool|double|ulong|long)\s+([\w, ]+?)(?:\[\d*\])?\s*(?:=[^;]*)?;', body, re.M):
        for v in [x.strip() for x in decl.group(1).split(',')]:
            v = re.sub(r'=.*', '', v).strip()
            if v and len(re.findall(r'\b%s\b' % re.escape(v), body)) < 2:
                print('unused local:', v); sys.exit(1)
PYEOF

echo "=== S7: negative controls ==="
cp $CORE "$NEG/A.mqh"; sed -i 's/^void DM_ParamsInit(/int zz=OrderSend(0,0);\nvoid DM_ParamsInit(/' "$NEG/A.mqh"
grep -qE '\bOrderSend\s*\(' "$NEG/A.mqh" && echo "  PASS an OrderSend in the harness core is detected" || { echo "  FAIL order control"; FAIL=1; }
cp $HAR "$NEG/B.mq5"; sed -i 's/input ENUM_DM_STEP InpStep=DM_STEP_NONE;/input ENUM_DM_STEP InpStep=DM_STEP_ACTIVATE;/' "$NEG/B.mq5"
grep -qF 'input ENUM_DM_STEP InpStep=DM_STEP_NONE;' "$NEG/B.mq5" && { echo "  FAIL default control"; FAIL=1; } || echo "  PASS a harness that is enabled by default loses the pin"
cp $OPEN "$NEG/C.mq5"; sed -i 's/input bool InpEnabled=false;/input bool InpEnabled=true;/' "$NEG/C.mq5"
grep -qF 'input bool InpEnabled=false;' "$NEG/C.mq5" && { echo "  FAIL open default control"; FAIL=1; } || echo "  PASS an open-position step that is enabled by default loses the pin"
cp $OPEN "$NEG/D.mq5"; sed -i 's/   MqlTradeCheckResult c;/   MqlTradeCheckResult c; bool zzz=OrderSend(r,s);/' "$NEG/D.mq5"
python3 -I - "$NEG/D.mq5" <<'PYEOF' && { echo "  FAIL a second OrderSend not detected"; FAIL=1; } || echo "  PASS a second OrderSend in the open-position script is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
sys.exit(1 if len(re.findall(r'\bOrderSend\s*\(', code)) != 1 else 0)
PYEOF
cp $CORE "$NEG/E.mqh"; sed -i 's/^void DM_ParamsInit(/void zz(){FileDelete("x");}\nvoid DM_ParamsInit(/' "$NEG/E.mqh"
python3 -I - "$NEG/E.mqh" <<'PYEOF' && { echo "  FAIL a deletion in the core not detected"; FAIL=1; } || echo "  PASS a deletion in the harness core is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
sys.exit(1 if re.search(r'FileDelete|GlobalVariableDel', code) else 0)
PYEOF
cp $CORE "$NEG/F.mqh"; sed -i 's/   if(p.use_lock \&\& !EL_Acquire(key,held,why)) {DM_Set(res,"BLOCKED",why); return(false);}//' "$NEG/F.mqh"
grep -q 'EL_Acquire(' "$NEG/F.mqh" && { echo "  FAIL lock control"; FAIL=1; } || echo "  PASS a harness without the instance lock loses the pin"
cp $LOCK "$NEG/G.mqh"; sed -i 's/GlobalVariableSetOnCondition(key,1.0,0.0)/GlobalVariableSetOnCondition(key,1.0)/' "$NEG/G.mqh"
python3 -I - "$NEG/G.mqh" <<'PYEOF' && { echo "  FAIL a wrong SetOnCondition arity not detected"; FAIL=1; } || echo "  PASS a wrong GlobalVariableSetOnCondition argument count is detected"
import re, sys
code = open(sys.argv[1], encoding='ascii').read()
m = re.search(r'GlobalVariableSetOnCondition\s*\(([^)]*)\)', code)
sys.exit(0 if m and m.group(1).count(',') == 2 else 1)
PYEOF
cp $CORE "$NEG/H.mqh"; echo "void x(){" >> "$NEG/H.mqh"
python3 tools/t001-check-balance.py "$NEG/H.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace"; FAIL=1; } || echo "  PASS unbalanced brace detected"

cp $GUARD "$NEG/I.mqh"; python3 - "$NEG/I.mqh" <<'PYEOF'
import sys
t = open(sys.argv[1]).read()
t = t.replace("   int np=port.CountPositions();", "   int np=0;").replace("   int no=port.CountOrders();", "   int no=0;")
open(sys.argv[1], 'w').write(t)
PYEOF
grep -q 'CountPositions()' "$NEG/I.mqh" && { echo "  FAIL guard scan control"; FAIL=1; } || echo "  PASS a guard without the scan inside the lock loses the pin"
cp $GUARD "$NEG/J.mqh"; sed -i 's/ESF_WriteAll(intent_name,intent_text) || //' "$NEG/J.mqh"
grep -q 'ESF_WriteAll(intent_name' "$NEG/J.mqh" && { echo "  FAIL intent control"; FAIL=1; } || echo "  PASS a guard that does not write the intent loses the pin"
cp $GUARD "$NEG/K.mqh"; sed -i 's/^   string detail="";/   FileDelete(intent_name);\n   string detail="";/' "$NEG/K.mqh"
python3 -I - "$NEG/K.mqh" <<'PYEOF' && { echo "  FAIL intent deletion not detected"; FAIL=1; } || echo "  PASS a guard that removes the intent is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
sys.exit(1 if re.search(r'FileDelete|FileMove|GlobalVariableDel', code) else 0)
PYEOF
cp $OPEN "$NEG/L.mq5"; sed -i 's/(int)InpDirection!=(int)OP_DIR_BUY \&\& (int)InpDirection!=(int)OP_DIR_SELL/InpDirection==OP_DIR_UNSET/' "$NEG/L.mq5"
python3 -I - "$NEG/L.mq5" <<'PYEOF' && { echo "  FAIL weak direction check not detected"; FAIL=1; } || echo "  PASS a direction check that is only != UNSET is detected"
import re, sys
flat = re.sub(r'\s+', '', open(sys.argv[1], encoding='ascii').read())
sys.exit(0 if '(int)InpDirection!=(int)OP_DIR_BUY&&(int)InpDirection!=(int)OP_DIR_SELL' in flat else 1)
PYEOF

echo
[ $FAIL -eq 0 ] && echo "T011 DEMO STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED; the real transport is never executed)" || echo "T011 DEMO STATIC CHECKS: FAILURES"
exit $FAIL
