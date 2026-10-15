#!/bin/bash
# Static checks for the T011 restart probe scripts. NOT a compiler, NOT an MT5 run: compile and run are UNVERIFIED.
# Usage: bash tools/t011-restart-probe-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=d6ceb8e
HDR=src/include/T011RestartProbe.mqh
PRE=src/XauUsdT011RestartPrepare.mq5
RES=src/XauUsdT011RestartRestore.mq5
CHK="python3 -I tools/t010-static-check.py"
NEWFILES="$HDR $PRE $RES tests/test_t011_restart_probe.py tools/t011-restart-probe-static-checks.sh docs/T011-restart-probe.md"

echo "=== S1: files exist ==="
for f in $NEWFILES; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: no trading API; no direct file API (files only through ExitStateFile); no position / symbol / history / clock read; account reads = server and login only ==="
out=$($CHK trading $HDR $PRE $RES) && echo "  PASS no order/position API" || { echo "$out"; FAIL=1; }
python3 -I - $HDR $PRE $RES <<'PYEOF' && echo "  PASS no forbidden read; the only FileDelete calls are on the probe's own names; PREPARE never deletes; RESTORE never writes" || { echo "  FAIL"; FAIL=1; }
import re, sys
bad = re.compile(r'PositionSelect|PositionGet|PositionsTotal|OrdersTotal|HistorySelect|HistoryDeal|HistoryOrder|SymbolInfo|SymbolSelect|TimeCurrent|TimeLocal|TimeGMT|TimeTradeServer|GetTickCount|EventSetTimer|Sleep\s*\(|FILE_COMMON|FileOpen|FileMove|FileWrite|FileRead|GlobalVariable|WebRequest|[rR]etry\w*\s*(=|\(|\+\+)')
txt = {}
for f in sys.argv[1:]:
    code = re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', open(f, encoding='ascii').read()))
    txt[f] = code
    m = bad.search(code)
    if m:
        print(f, m.group(0)); sys.exit(1)
allc = ''.join(txt.values())
acc = sorted(set(re.findall(r'Account\w+\(([A-Z_]+)\)', allc)))
assert acc == ['ACCOUNT_LOGIN', 'ACCOUNT_SERVER'], acc
dels = sorted(set(re.findall(r'FileDelete\(([^)]*)\)', allc)))
assert dels == ['RP_FILE', 'RP_FILE+ESF_TMP_SUFFIX'], dels
pre = txt[sys.argv[2]]; res = txt[sys.argv[3]]
assert 'FileDelete' not in pre and 'ESF_Save' in pre and 'ESF_InitFresh' in pre
assert 'ESF_Save' not in res and 'ESF_InitFresh' not in res and 'EA_OnReport' not in res and 'ER_Reconcile' not in res
assert 'ESC_SEND_MAPPED' not in pre + res and 'n_orders' not in pre
PYEOF
for f in $HDR $PRE $RES; do
  if grep -q 'VELO_T011_EXIT_\|VELO_T011_PERSIST_SELFTEST' "$f"; then echo "  FAIL $f uses a production or test file name"; FAIL=1; else echo "  PASS $f: only the probe's own file name"; fi
done

echo "=== S3: dependencies are declared; verified modules unchanged since $BASE ==="
grep -q '#include "ExitStateFile.mqh"' $HDR && grep -q '#include "include/T011RestartProbe.mqh"' $PRE && grep -q '#include "include/T011RestartProbe.mqh"' $RES && echo "  PASS direct includes" || { echo "  FAIL includes"; FAIL=1; }
grep -q 'ACCOUNT_SERVER' $HDR && grep -q 'ACCOUNT_LOGIN' $HDR && echo "  PASS identity from ACCOUNT_SERVER and ACCOUNT_LOGIN (one-argument forms)" || { echo "  FAIL identity"; FAIL=1; }
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in src/include/ExitStateCodec.mqh src/include/ExitStateFile.mqh src/include/ExitSplit.mqh src/include/ExitActivation.mqh src/include/ExitReconciliation.mqh src/include/ExitSnapshotAdapter.mqh src/XauUsdTradePreview.mq5 src/tests/T011_PersistTest.mq5 src/tests/T011_PersistFileTest.mq5; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S4: balance, format strings, includes, ASCII, reserved words ==="
python3 tools/t001-check-balance.py $HDR $PRE $RES || FAIL=1
python3 - $HDR $PRE $RES <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
for f in $NEWFILES; do n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true); [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }; done
echo "  INFO ASCII-only checked"
RESERVED='final|override|sealed|explicit|delete|new|virtual|template|typename|operator|this|static|class|struct|union|enum|public|private|protected|extern|input|sinput|void|auto|namespace|using|typedef|interface|implements'
for f in $HDR $PRE $RES; do
  if grep -nE "\b(bool|int|long|double|string|ulong|uint|datetime)\s+($RESERVED)\b\s*(=|;|,|\))" "$f" >/dev/null; then echo "  FAIL $f reserved word as a variable"; FAIL=1; else echo "  PASS $f: no variable is named with a reserved MQL5 word"; fi
done
for f in $PRE $RES; do
  out=$(grep -c 'void OnStart' $f); [ "$out" = "1" ] && echo "  PASS $f has one OnStart (a script)" || { echo "  FAIL $f OnStart"; FAIL=1; }
done

echo "=== S5: negative controls ==="
cp $PRE "$NEG/A.mq5"; sed -i 's/^void OnStart()/int zz=OrderSend(0,0);\nvoid OnStart()/' "$NEG/A.mq5"
$CHK trading "$NEG/A.mq5" >/dev/null 2>&1 && { echo "  FAIL order API not detected"; FAIL=1; } || echo "  PASS an order API in PREPARE is detected"
cp $RES "$NEG/B.mq5"; sed -i 's/^void OnStart()/bool zz=PositionSelect("X");\nvoid OnStart()/' "$NEG/B.mq5"
grep -qE 'PositionSelect' "$NEG/B.mq5" && echo "  PASS a position read in RESTORE is detected" || { echo "  FAIL position control"; FAIL=1; }
cp $RES "$NEG/C.mq5"; sed -i 's/FileDelete(RP_FILE+ESF_TMP_SUFFIX)/FileDelete("ANY_OTHER_FILE")/' "$NEG/C.mq5"
python3 -I - "$NEG/C.mq5" <<'PYEOF' && { echo "  FAIL deletion of another file not detected"; FAIL=1; } || echo "  PASS a deletion of a file other than the probe's own is detected"
import re, sys
code = open(sys.argv[1], encoding='ascii').read()
sys.exit(0 if sorted(set(re.findall(r'FileDelete\(([^)]*)\)', code))) == ['RP_FILE', 'RP_FILE+ESF_TMP_SUFFIX'] else 1)
PYEOF
cp $RES "$NEG/D.mq5"; sed -i 's/^void OnStart()/void zzw(){SEaState s; SEsRecord r; string w; ESF_Save(RP_FILE,r,w);}\nvoid OnStart()/' "$NEG/D.mq5"
grep -q 'ESF_Save' "$NEG/D.mq5" && echo "  PASS a write of the record in RESTORE is detected (ESF_Save is forbidden there)" || { echo "  FAIL write control"; FAIL=1; }
cp $PRE "$NEG/E.mq5"; sed -i 's/ESF_Exists(RP_FILE)/false/' "$NEG/E.mq5"
grep -q 'ESF_Exists(RP_FILE)' "$NEG/E.mq5" && { echo "  FAIL overwrite-guard control"; FAIL=1; } || echo "  PASS a PREPARE without the existing-file guard loses the pin"
cp $HDR "$NEG/F.mqh"; sed -i 's/AccountInfoString(ACCOUNT_SERVER)/AccountInfoString(ACCOUNT_NAME)/' "$NEG/F.mqh"
python3 -I - "$NEG/F.mqh" <<'PYEOF' && { echo "  FAIL another account property not detected"; FAIL=1; } || echo "  PASS an account read beyond server and login is detected"
import re, sys
code = open(sys.argv[1], encoding='ascii').read()
sys.exit(0 if sorted(set(re.findall(r'Account\w+\(([A-Z_]+)\)', code))) == ['ACCOUNT_LOGIN', 'ACCOUNT_SERVER'] else 1)
PYEOF
cp $PRE "$NEG/G.mq5"; echo "void x(){" >> "$NEG/G.mq5"
python3 tools/t001-check-balance.py "$NEG/G.mq5" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace"; FAIL=1; } || echo "  PASS unbalanced brace detected"

echo
[ $FAIL -eq 0 ] && echo "T011 RESTART PROBE STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T011 RESTART PROBE STATIC CHECKS: FAILURES"
exit $FAIL
