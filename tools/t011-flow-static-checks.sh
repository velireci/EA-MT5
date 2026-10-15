#!/bin/bash
# Static checks for the T011 restart flow (ExitRestartFlow). NOT a compiler, NOT an MT5 run: compile and run are UNVERIFIED.
# Usage: bash tools/t011-flow-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=01b8d9f
HDR=src/include/ExitRestartFlow.mqh
TST=src/tests/T011_FlowTest.mq5
DIA=src/XauUsdT011FlowDiag.mq5
REF=tests/t011_flow_reference.py
CHK="python3 -I tools/t010-static-check.py"
NEWFILES="$HDR $TST $DIA $REF tests/t011_flow_fixtures.py tests/test_t011_flow.py tools/t011-flow-static-checks.sh docs/T011-restart-flow.md"

echo "=== S1: files exist ==="
for f in $NEWFILES; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: no trading API; the flow does no file access of its own and cannot produce a request; no clock / sleep / retry ==="
out=$($CHK trading $HDR $TST $DIA) && echo "  PASS no order/position API" || { echo "$out"; FAIL=1; }
out=$($CHK persist $HDR) && echo "  PASS the flow header has no direct file access (only ExitStateFile)" || { echo "$out"; FAIL=1; }
python3 -I - $HDR $TST $DIA <<'PYEOF' && echo "  PASS header: no EA_OnQuote / request action / report; no clock, sleep, retry; no position or symbol read; tests and diagnostic delete only their own files" || { echo "  FAIL"; FAIL=1; }
import re, sys
strip = lambda t: re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))
hdr, tst, dia = [strip(open(f, encoding='ascii').read()) for f in sys.argv[1:4]]
bad = re.compile(r'EA_OnQuote|EA_ACT_REQUEST|EA_OnReport|EA_RequestId|PositionSelect|PositionGet|PositionsTotal|OrdersTotal|HistorySelect|SymbolInfo|TimeCurrent|TimeLocal|TimeGMT|TimeTradeServer|GetTickCount|EventSetTimer|Sleep\s*\(|FILE_COMMON|FileOpen|FileMove|FileWrite|FileRead|FileDelete|\b[rR]etry\w*\s*(=|\(|\+\+)')
m = bad.search(hdr)
assert not m, 'header: ' + m.group(0)
assert 'request_produced=true' not in hdr.replace(' ', '')
for name, code in (('test', tst), ('diagnostic', dia)):
    m = re.search(r'PositionSelect|PositionGet|PositionsTotal|OrdersTotal|HistorySelect|SymbolInfo|TimeCurrent|TimeLocal|TimeGMT|TimeTradeServer|Sleep\s*\(|FILE_COMMON', code)
    assert not m, name + ': ' + m.group(0)
assert sorted(set(re.findall(r'FileDelete\(([^)]*)\)', tst))) == ['FN', 'FN+ESF_TMP_SUFFIX'], 'test deletes'
assert sorted(set(re.findall(r'FileDelete\(([^)]*)\)', dia))) == ['FD_FILE', 'FD_FILE+ESF_TMP_SUFFIX'], 'diag deletes'
assert sorted(set(re.findall(r'Account\w+\(([A-Z_]+)\)', dia + tst))) == ['ACCOUNT_LOGIN', 'ACCOUNT_SERVER'], 'account reads'
PYEOF
for f in $TST $DIA; do
  if grep -q 'VELO_T011_EXIT_\|VELO_T011_PERSIST_SELFTEST\|VELO_T011_RESTART_PROBE' "$f"; then echo "  FAIL $f uses another script's or the production file name"; FAIL=1; else echo "  PASS $f: only its own file name"; fi
done

echo "=== S3: ERF_Run composes the existing pieces once each, in order, behind the gates ==="
python3 -I - $HDR <<'PYEOF' && echo "  PASS load -> map -> snapshot (READY only) -> ER_Reconcile -> save; one call site each; the map comes from the record" || { echo "  FAIL"; FAIL=1; }
import re, sys
h = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
run = h[h.index('bool ERF_Run('):]
order = ['ESF_Load(', 'if(o.generation==0)', 'ESC_USABLE_BLOCKED', 'ESC_USABLE_IDLE', 'if(o.n_orders==0)', 'XA_MapAdd(mp,o.orders[i])', 'XA_Build(', 'if(xr.verdict==XA_UNKNOWN)',
         'if(xr.verdict==XA_BLOCK)', 'ER_Reconcile(', 'ESF_Save(']
pos = [run.index(s) for s in order]
assert pos == sorted(pos), list(zip(order, pos))
for s in ('ESF_Load(', 'XA_ReadAndBuild(', 'XA_Build(', 'ER_Reconcile(', 'ESF_Save(', 'XA_MapAdd('):
    assert h.count(s) == 1, s
assert 'ESF_InitFresh' not in h and 'ESC_Restore(' not in h and 'ESC_Decode(' not in h, 'the flow must not re-implement load / validation'
assert 'o.generation+1' in run and 'ESC_MAX_GEN' in run
PYEOF

echo "=== S4: dependencies are declared; verified modules unchanged since $BASE ==="
grep -q '#include "ExitStateFile.mqh"' $HDR && grep -q '#include "ExitSnapshotAdapter.mqh"' $HDR && grep -q '#include "../include/ExitRestartFlow.mqh"' $TST && grep -q '#include "include/ExitRestartFlow.mqh"' $DIA && echo "  PASS direct includes" || { echo "  FAIL includes"; FAIL=1; }
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in src/include/ExitStateFile.mqh src/include/ExitSplit.mqh src/include/ExitActivation.mqh src/include/ExitReconciliation.mqh src/include/ExitSnapshotAdapter.mqh src/XauUsdTradePreview.mq5 tests/t011_adapter_reference.py tests/t011_reconcile_reference.py; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S5: balance, format strings, includes, ASCII, reserved words, literal-only generated arrays ==="
python3 tools/t001-check-balance.py $HDR $TST $DIA || FAIL=1
python3 - $HDR $TST $DIA <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
for f in $HDR $TST $DIA; do
  d=$(dirname "$f"); bad=0
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "  FAIL $f: missing include $d/$inc"; bad=1; FAIL=1; }
  done
  [ $bad -eq 0 ] && echo "  PASS $f: every include resolves"
done
for f in $NEWFILES; do n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true); [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }; done
echo "  INFO ASCII-only checked"
RESERVED='final|override|sealed|explicit|delete|new|virtual|template|typename|operator|this|static|class|struct|union|enum|public|private|protected|extern|input|sinput|void|auto|namespace|using|typedef|interface|implements'
for f in $HDR $TST $DIA; do
  if grep -nE "\b(bool|int|long|double|string|ulong|uint|datetime|color|char|short|uchar|ushort|float)\s+($RESERVED)\b\s*(=|;|,|\))" "$f" >/dev/null; then echo "  FAIL $f reserved word as a variable"; FAIL=1; else echo "  PASS $f: no variable is named with a reserved MQL5 word"; fi
done
python3 -I - $TST <<'PYEOF' && echo "  PASS generated arrays hold literals only" || { echo "  FAIL"; FAIL=1; }
import re, sys
t = open(sys.argv[1], encoding='ascii').read()
blk = t[t.index('// BEGIN GENERATED'):t.index('// END GENERATED')]
for m in re.finditer(r'^(?:string|int|long|double) \w+\[\]=\{(.*)\};$', blk, re.M):
    body = re.sub(r'"(?:[^"\\]|\\.)*"', '', m.group(1))
    if re.search(r'[A-Za-z_(]', body.replace('e-', '').replace('e+', '')):
        print('non-literal initializer:', m.group(0)[:80]); sys.exit(1)
PYEOF

echo "=== S6: negative controls ==="
cp $HDR "$NEG/A.mqh"; sed -i 's/^void ERF_InputInit(/bool zz=EA_OnQuote(0,0,0,0,0,0,0,0,0,0,0,0);\nvoid ERF_InputInit(/' "$NEG/A.mqh"
grep -qE 'EA_OnQuote' "$NEG/A.mqh" && echo "  PASS a request-producing call in the flow is detected" || { echo "  FAIL request control"; FAIL=1; }
cp $HDR "$NEG/B.mqh"; sed -i 's/if(xr.verdict==XA_UNKNOWN)/if(false)/' "$NEG/B.mqh"
python3 -I - "$NEG/B.mqh" <<'PYEOF' && { echo "  FAIL a bypassed UNKNOWN gate was not detected"; FAIL=1; } || echo "  PASS a flow that bypasses the UNKNOWN verdict loses the pin"
import re, sys
h = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
run = h[h.index('bool ERF_Run('):]
sys.exit(0 if 'if(xr.verdict==XA_UNKNOWN)' in run[:run.index('ER_Reconcile(')] else 1)
PYEOF
cp $HDR "$NEG/C.mqh"; sed -i 's/^void ERF_InputInit(/int zh=FileOpen("x",FILE_READ);\nvoid ERF_InputInit(/' "$NEG/C.mqh"
$CHK persist "$NEG/C.mqh" >/dev/null 2>&1 && { echo "  FAIL file access in the flow not detected"; FAIL=1; } || echo "  PASS direct file access in the flow is detected"
cp $HDR "$NEG/D.mqh"; sed -i 's/XA_MapAdd(mp,o.orders\[i\]);/XA_MapAdd(mp,501);/' "$NEG/D.mqh"
grep -q 'XA_MapAdd(mp,o.orders\[i\]);' "$NEG/D.mqh" && { echo "  FAIL invented-map control"; FAIL=1; } || echo "  PASS an invented order map loses the pin"
cp $HDR "$NEG/E.mqh"; sed -i '/#include "ExitSnapshotAdapter.mqh"/d' "$NEG/E.mqh"
grep -q '#include "ExitSnapshotAdapter.mqh"' "$NEG/E.mqh" && { echo "  FAIL include control"; FAIL=1; } || echo "  PASS a flow without its direct adapter include is detected"
cp $DIA "$NEG/F.mq5"; sed -i 's/^void OnStart()/bool zz=PositionSelect("X");\nvoid OnStart()/' "$NEG/F.mq5"
grep -qE 'PositionSelect' "$NEG/F.mq5" && echo "  PASS a position read in the diagnostic is detected" || { echo "  FAIL position control"; FAIL=1; }
cp $HDR "$NEG/H.mqh"; echo "void x(){" >> "$NEG/H.mqh"
python3 tools/t001-check-balance.py "$NEG/H.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace"; FAIL=1; } || echo "  PASS unbalanced brace detected"

echo
[ $FAIL -eq 0 ] && echo "T011 FLOW STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T011 FLOW STATIC CHECKS: FAILURES"
exit $FAIL
