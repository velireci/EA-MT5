#!/bin/bash
# Static checks for the T012 day-balance store: no trading, no deletion, only the needed T011 primitives, no profit-based reconstruction, read-only LOAD, locked explicit CAPTURE,
# untouched protected modules. NOT a compiler, NOT an MT5 run.  Usage: bash tools/t012-balance-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=4671407
HDR=src/include/DailyBalanceStore.mqh
SCR=src/XauUsdT012BalanceStore.mq5
TST=src/tests/T012_BalanceStoreTest.mq5
FILES="$HDR $SCR $TST"
NEWFILES="$FILES src/presets/XauUsdT012BalanceStore_load.set src/presets/XauUsdT012BalanceStore_capture_window_empty.set src/presets/XauUsdT012BalanceStore_capture_owner_asserted.set tests/t012_balance_reference.py tests/t012_balance_fixtures.py tests/test_t012_balance.py tools/t012-balance-static-checks.sh"

echo "=== S1: files exist ==="
for f in $NEWFILES; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: no trading call, no deletion, only the needed primitives, no T011 file, no profit-based reconstruction ==="
python3 -I - $HDR $SCR $TST <<'PYEOF' && echo "  PASS no order / cancellation / deletion; only the listed ESC / ESF primitives; no T011 record function or file; no equity / credit / profit fields" || { echo "  FAIL"; FAIL=1; }
import re, sys
strip = lambda t: re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))
hdr, scr, tst = [strip(open(f, encoding='ascii').read()) for f in sys.argv[1:4]]
for name, code in (('header', hdr), ('script', scr), ('test', tst)):
    assert not re.search(r'\bOrder\w*\s*\(|CTrade|PositionClose|PositionOpen|PositionModify|MqlTradeRequest', code), (name, 'trading call')
    assert not re.search(r'FileDelete|FileMove|GlobalVariableDel|GlobalVariablesDeleteAll', code), (name, 'deletes or moves something')
    assert not re.search(r'VELO_T011|\b(EX|ETD|ER|XA)_\w+', code), (name, 'T011 file or module used')
for name, code in (('header', hdr), ('script', scr)):
    assert not re.search(r'ACCOUNT_EQUITY|ACCOUNT_CREDIT|ACCOUNT_PROFIT|ACCOUNT_MARGIN|candidate_|nontrade_|result_formula|DB_Check|DL_Check|max_trades|TimeCurrent|Sleep|OnTick|OnTimer', code), (name, 'forbidden')
assert 'ACCOUNT_BALANCE' in hdr
used = set(re.findall(r'\b(ESC_\w+|ESF_\w+|EL_\w+)\s*\(', hdr))
allowed = {'ESC_Crc32', 'ESC_Escape', 'ESC_Unescape', 'ESC_Fnum', 'ESC_ParseInt', 'ESC_ParseDouble', 'ESC_Lines', 'ESC_Field', 'ESF_ReadAll', 'ESF_WriteAll', 'ESF_Exists', 'EL_Acquire', 'EL_Release'}
assert used <= allowed, used - allowed
assert not re.search(r'\b(Print|PrintFormat)\b.*(ESF_Load)', hdr)
assert hdr.count('ESF_WriteAll(') == 1 and hdr.count('WriteFile(') >= 2
PYEOF

echo "=== S3: LOAD is read-only, CAPTURE is explicit / locked / ordered, defaults are inert ==="
python3 -I - $HDR $SCR <<'PYEOF' && echo "  PASS read-only LOAD, locked CAPTURE order, inert defaults" || { echo "  FAIL"; FAIL=1; }
import re, sys
strip = lambda t: re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))
hdr, scr = [strip(open(f, encoding='ascii').read()) for f in sys.argv[1:3]]
load = hdr[hdr.index('void DBS_Load('):hdr.index('void DBS_Capture(')]
for w in ('WriteFile', 'Lock(', 'Unlock(', 'ReadBalance', 'ReadHistory', 'Put('):
    assert w not in load, w
cap = hdr[hdr.index('void DBS_Capture('):hdr.index('class CDbsRealPort')]
marks = ['HISTORY_COMPLETE_NOT_ASSERTED', 'DBS_Identity(', 'port.Lock(', 'port.Exists(', 'port.ReadBalance(', 'port.ReadHistory(', 'port.ReadBalance(', 'port.NowUtc(', 'DH_DayWindow(', 'DAY_CHANGED_DURING_ACQUISITION',
         'MID_DAY_NOT_PROVEN', 'DBS_Encode(', 'port.WriteFile(', 'port.ReadFile(', 'DBS_Decode(', 'port.Unlock(']
at, pos = 0, []
for m in marks:
    at = cap.index(m, at)
    pos.append(at)
assert pos == sorted(pos), list(zip(marks, pos))
assert cap.count('port.WriteFile(') == 1 and cap.count('port.Lock(') == 1
# every return after the lock is preceded by an unlock
after = cap[cap.index('port.Lock('):]
assert after.count('port.Unlock(') >= after.count('return;') - 0, 'every exit after the lock must unlock'
for need in ('input ENUM_DBS_ACTION InpAction=DBS_ACT_LOAD;', 'input bool InpConfirmCapture=false;', 'input long InpEaMagic=0;', 'input int InpServerOffsetSeconds=2147483647;', 'input bool InpHistoryComplete=false;',
             'input double InpOwnerAmount=0;', 'input int InpOwnerDay=0;'):
    assert need in scr, need
assert scr.index('!InpConfirmCapture') < scr.index('DBS_Capture(')
assert 'DBS_Load(' in scr and scr.count('DBS_Capture(') == 1
PYEOF

echo "=== S4: protected modules unchanged since $BASE ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in src/include/DailyBridge.mqh src/include/DailyLimits.mqh src/include/DailyHistory.mqh src/include/DailyPreviewGate.mqh src/include/SessionPolicy.mqh src/XauUsdTradePreview.mq5 src/XauUsdDailyHistoryDiag.mq5 \
           src/include/ExitStateCodec.mqh src/include/ExitStateFile.mqh src/include/ExitInstanceLock.mqh src/include/ExitExecutor.mqh src/include/ExitTickDriver.mqh src/include/ExitRestartFlow.mqh src/include/ExitTransportReal.mqh \
           src/XauUsdT011ExitManager.mq5 src/XauUsdT011ExitRegister.mq5 src/XauUsdT011DemoOpenPosition.mq5 src/XauUsdT011DemoHarness.mq5 src/presets/XauUsdT011ExitDemoSell_01_open.set \
           src/presets/XauUsdT011ExitDemoSell_02_register.set src/presets/XauUsdT011ExitDemoSell_03_manager.set; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S5: balance, format strings, includes, ASCII, reserved words ==="
python3 tools/t001-check-balance.py $FILES || FAIL=1
python3 - $FILES <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
for f in $FILES; do
  d=$(dirname "$f"); bad=0
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "  FAIL $f: missing include $d/$inc"; bad=1; FAIL=1; }
  done
  [ $bad -eq 0 ] && echo "  PASS $f: every include resolves"
done
for f in $NEWFILES; do n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true); [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }; done
echo "  INFO ASCII-only checked"
RESERVED='final|override|sealed|explicit|delete|new|virtual|template|typename|operator|this|static|class|struct|union|enum|public|private|protected|extern|input|sinput|void|auto|namespace|using|typedef|interface|implements'
for f in $FILES; do
  if grep -nE "\b(bool|int|long|double|string|ulong|uint|datetime|color|char|short|uchar|ushort|float)\s+($RESERVED)\b\s*(=|;|,|\))" "$f" >/dev/null; then echo "  FAIL $f reserved word as a variable"; FAIL=1; else echo "  PASS $f: no variable is named with a reserved MQL5 word"; fi
done

echo "=== S6: negative controls ==="
cp $HDR "$NEG/A.mqh"; sed -i 's/^string DBS_StatusName(/void zz(){FileDelete("x");}\nstring DBS_StatusName(/' "$NEG/A.mqh"
python3 -I - "$NEG/A.mqh" <<'PYEOF' && { echo "  FAIL deletion not detected"; FAIL=1; } || echo "  PASS a FileDelete in the header is detected"
import re, sys
sys.exit(1 if re.search(r'FileDelete|FileMove', re.sub(r'//[^\n]*', '', open(sys.argv[1]).read())) else 0)
PYEOF
cp $HDR "$NEG/B.mqh"; sed -i 's/   if(!port.Exists(DBS_FileName(a.login,day)))/   port.WriteFile("x","y");\n   if(!port.Exists(DBS_FileName(a.login,day)))/' "$NEG/B.mqh"
python3 -I - "$NEG/B.mqh" <<'PYEOF' && { echo "  FAIL writing LOAD not detected"; FAIL=1; } || echo "  PASS a LOAD that writes is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1]).read())
load = code[code.index('void DBS_Load('):code.index('void DBS_Capture(')]
sys.exit(1 if 'WriteFile' in load else 0)
PYEOF
cp $HDR "$NEG/C.mqh"; python3 - "$NEG/C.mqh" <<'PYEOF'
import sys
t = open(sys.argv[1]).read()
a = '   if(!port.Lock(key)) {DBS_ResultInit(res,DBS_UNKNOWN,"LOCK_FAILED'
assert a in t, 'control could not be built'
i = t.index('   string key=DBS_LockKey(a.login,day);')
j = t.index('   string name=DBS_FileName(a.login,day);\n   if(port.Exists(name))')
t = t[:i] + '   string key=DBS_LockKey(a.login,day);\n   string name=DBS_FileName(a.login,day);\n   bool pre=port.Exists(name);\n' + t[i:j].split('string key=DBS_LockKey(a.login,day);')[1] + t[j+len('   string name=DBS_FileName(a.login,day);\n'):]
open(sys.argv[1], 'w').write(t)
PYEOF
python3 -I - "$NEG/C.mqh" <<'PYEOF' && { echo "  FAIL existence check before the lock not detected"; FAIL=1; } || echo "  PASS an existence check before the lock is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1]).read())
cap = code[code.index('void DBS_Capture('):]
i, j = cap.find('port.Lock('), cap.find('port.Exists(')
sys.exit(0 if (i >= 0 and j >= 0 and i < j) else 1)
PYEOF
cp $HDR "$NEG/D.mqh"; sed -i 's/ACCOUNT_BALANCE/ACCOUNT_EQUITY/' "$NEG/D.mqh"
python3 -I - "$NEG/D.mqh" <<'PYEOF' && { echo "  FAIL equity not detected"; FAIL=1; } || echo "  PASS a base other than ACCOUNT_BALANCE is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1]).read())
sys.exit(1 if re.search(r'ACCOUNT_EQUITY|ACCOUNT_CREDIT', code) or 'ACCOUNT_BALANCE' not in code else 0)
PYEOF
cp $HDR "$NEG/E.mqh"; sed -i 's/^string DBS_StatusName(/double zz(const SDhFacts \&f){return(f.nontrade_profit);}\nstring DBS_StatusName(/' "$NEG/E.mqh"
python3 -I - "$NEG/E.mqh" <<'PYEOF' && { echo "  FAIL profit field not detected"; FAIL=1; } || echo "  PASS a read of a profit field (reconstruction) is detected"
import re, sys
sys.exit(1 if re.search(r'candidate_|nontrade_', re.sub(r'//[^\n]*', '', open(sys.argv[1]).read())) else 0)
PYEOF
cp $SCR "$NEG/F.mq5"; sed -i 's/input ENUM_DBS_ACTION InpAction=DBS_ACT_LOAD;/input ENUM_DBS_ACTION InpAction=DBS_ACT_CAPTURE_WINDOW_EMPTY;/' "$NEG/F.mq5"
grep -qF 'InpAction=DBS_ACT_LOAD;' "$NEG/F.mq5" && { echo "  FAIL default control"; FAIL=1; } || echo "  PASS a script whose default action captures loses the pin"
cp $HDR "$NEG/G.mqh"; sed -i 's/ESF_WriteAll(name,text)/ESF_Save(name,text)/' "$NEG/G.mqh"
python3 -I - "$NEG/G.mqh" <<'PYEOF' && { echo "  FAIL T011 record function not detected"; FAIL=1; } || echo "  PASS a T011 record function in the header is detected"
import re, sys
used = set(re.findall(r'\b(ESC_\w+|ESF_\w+)\s*\(', re.sub(r'//[^\n]*', '', open(sys.argv[1]).read())))
allowed = {'ESC_Crc32', 'ESC_Escape', 'ESC_Unescape', 'ESC_Fnum', 'ESC_ParseInt', 'ESC_ParseDouble', 'ESC_Lines', 'ESC_Field', 'ESF_ReadAll', 'ESF_WriteAll', 'ESF_Exists'}
sys.exit(1 if used - allowed else 0)
PYEOF
cp $HDR "$NEG/H.mqh"; echo "void x(){" >> "$NEG/H.mqh"
python3 tools/t001-check-balance.py "$NEG/H.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace"; FAIL=1; } || echo "  PASS unbalanced brace detected"

echo
[ $FAIL -eq 0 ] && echo "T012 BALANCE STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T012 BALANCE STATIC CHECKS: FAILURES"
exit $FAIL
