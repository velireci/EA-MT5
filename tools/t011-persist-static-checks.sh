#!/bin/bash
# Static checks for the T011 state persistence (codec + thin file layer). NOT a compiler, NOT an MT5 run: compile and run are UNVERIFIED.
# Usage: bash tools/t011-persist-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=87380ac
COD=src/include/ExitStateCodec.mqh
FIL=src/include/ExitStateFile.mqh
TC=src/tests/T011_PersistTest.mq5
TF=src/tests/T011_PersistFileTest.mq5
REF=tests/t011_persist_reference.py
CHK="python3 -I tools/t010-static-check.py"
NEWFILES="$COD $FIL $TC $TF $REF tests/t011_persist_fixtures.py tests/test_t011_persist.py tools/t011-persist-static-checks.sh tasks/T011-exit-persistence.md"

echo "=== S1: files exist ==="
for f in $NEWFILES; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: no trading API anywhere; file access ONLY in the file layer and its test; no clock / account / terminal read; no retry ==="
out=$($CHK trading $COD $FIL $TC $TF) && echo "  PASS no order/position API" || { echo "$out"; FAIL=1; }
out=$($CHK persist $COD $TC) && echo "  PASS the codec and its test use no file, global-variable, network or mail access" || { echo "$out"; FAIL=1; }
for f in src/include/ExitSplit.mqh src/include/ExitActivation.mqh src/include/ExitReconciliation.mqh src/include/ExitSnapshotAdapter.mqh; do
  out=$($CHK persist $f) && echo "  PASS $f has no file access (unchanged)" || { echo "$out"; FAIL=1; }
done
python3 -I - $COD $FIL $TC $TF <<'PYEOF' && echo "  PASS no clock / account / symbol / history read, no Sleep, no retry loop, no FILE_COMMON" || { echo "  FAIL"; FAIL=1; }
import re, sys
bad = re.compile(r'Account(Info|InfoDouble|InfoInteger)|SymbolInfo|HistorySelect|HistoryDeal|HistoryOrder|PositionSelect|PositionGet|PositionsTotal|OrdersTotal|TimeCurrent|TimeLocal|TimeGMT|TimeTradeServer|GetTickCount|EventSetTimer|Sleep\s*\(|FILE_COMMON|MathRand|\b[rR]etry\w*\s*(=|\(|\+\+)|\battempts?\w*\s*(=|<|\+\+)')
for f in sys.argv[1:]:
    code = re.sub(r'(?s)/\*.*?\*/', '', open(f, encoding='ascii').read())
    code = re.sub(r'//[^\n]*', '', code)
    m = bad.search(code)
    if m:
        print(f, m.group(0)); sys.exit(1)
PYEOF

echo "=== S3: verified modules are unchanged since $BASE ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in src/include/ExitSplit.mqh src/include/ExitActivation.mqh src/include/ExitReconciliation.mqh src/include/ExitSnapshotAdapter.mqh src/include/DailyBridge.mqh src/XauUsdTradePreview.mq5 tests/t011_activation_reference.py tests/t011_reconcile_reference.py; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S4: dependencies are declared by the headers; every SEaState field is stored and restored; constants agree ==="
python3 -I - $COD $FIL $TC $TF <<'PYEOF' && echo "  PASS direct includes, all SEaState fields serialised both ways, ESC_MAX_ORDERS == XA_MAX_ORDERS" || { echo "  FAIL"; FAIL=1; }
import re, sys
cod, fil, tc, tf = [open(f, encoding='ascii').read() for f in sys.argv[1:5]]
strip = lambda t: re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))
def incs(t): return re.findall(r'#include "([^"]+)"', strip(t))
assert 'ExitActivation.mqh' in incs(cod), 'codec must include ExitActivation.mqh itself'
assert 'ExitStateCodec.mqh' in incs(fil), 'file layer must include the codec itself'
assert '../include/ExitStateCodec.mqh' in incs(tc) and '../include/ExitReconciliation.mqh' in incs(tc)
assert '../include/ExitStateFile.mqh' in incs(tf)
act = open('src/include/ExitActivation.mqh', encoding='ascii').read()
body = re.search(r'struct SEaState\s*\{(.*?)\};', act, re.S).group(1)
fields = re.findall(r'^\s*[A-Za-z_][\w]*\s+(\w+)\s*;', re.sub(r'//[^\n]*', '', body), re.M)
assert len(fields) == 15, fields
c = strip(cod)
enc = c[c.index('bool ESC_Encode('):c.index('int ESC_Lines(')]
dec = c[c.index('bool ESC_Decode('):c.index('void ESC_RestoreInit(')]
for f in fields:
    assert re.search(r'\bst\.%s\b' % f, enc), 'ESC_Encode does not write SEaState.%s' % f
    assert re.search(r'rec\.state\.%s\s*=' % f, dec), 'ESC_Decode does not restore SEaState.%s' % f
xa = re.search(r'#define XA_MAX_ORDERS (\d+)', open('src/include/ExitSnapshotAdapter.mqh', encoding='ascii').read()).group(1)
assert re.search(r'#define ESC_MAX_ORDERS %s\b' % xa, cod), 'ESC_MAX_ORDERS differs from XA_MAX_ORDERS'
PYEOF

echo "=== S5: terminal file API argument counts (FileMove / FileOpen / ... as the official signatures; UNVERIFIED against the live docs) ==="
python3 -I - $FIL $TF <<'PYEOF' && echo "  PASS every call of the file API has an accepted argument count" || { echo "  FAIL"; FAIL=1; }
import re, sys
want = {'FileOpen': (2, 3), 'FileClose': (1,), 'FileMove': (4,), 'FileDelete': (1,), 'FileIsExist': (1, 2), 'FileSize': (1,), 'FileFlush': (1,),
        'FileReadArray': (4,), 'FileWriteArray': (4,), 'StringToCharArray': (4,), 'CharArrayToString': (3,)}
def args(code, i):
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
seen = set()
for f in sys.argv[1:]:
    code = re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', open(f, encoding='ascii').read()))
    for m in re.finditer(r'\b(File\w+|StringToCharArray|CharArrayToString)\s*\(', code):
        name = m.group(1)
        if name not in want:
            if name.startswith('File') and name not in ('FILE_READ',):
                print('%s: unlisted file API %s' % (f, name)); bad = 1
            continue
        n = args(code, m.end() - 1)
        seen.add(name)
        if n not in want[name]:
            print('%s: %s called with %d arguments' % (f, name, n)); bad = 1
need = {'FileOpen', 'FileMove', 'FileDelete', 'FileReadArray', 'FileWriteArray', 'FileFlush', 'FileClose', 'FileIsExist', 'FileSize'}
if need - seen:
    print('not exercised:', sorted(need - seen)); bad = 1
sys.exit(bad)
PYEOF

echo "=== S6: balance, format strings, includes, ASCII, reserved words, literal-only generated arrays ==="
python3 tools/t001-check-balance.py $COD $FIL $TC $TF || FAIL=1
python3 - $COD $FIL $TC $TF <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
for f in $COD $FIL $TC $TF; do
  d=$(dirname "$f"); bad=0
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "  FAIL $f: missing include $d/$inc"; bad=1; FAIL=1; }
  done
  [ $bad -eq 0 ] && echo "  PASS $f: every include resolves"
done
for f in $NEWFILES; do n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true); [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }; done
echo "  INFO ASCII-only checked for every persistence file"
RESERVED='final|override|sealed|explicit|delete|new|virtual|template|typename|operator|this|static|class|struct|union|enum|public|private|protected|extern|input|sinput|void|auto|namespace|using|typedef|interface|implements'
for f in $COD $FIL $TC $TF; do
  if grep -nE "\b(bool|int|long|double|string|ulong|uint|datetime|color|char|short|uchar|ushort|float)\s+($RESERVED)\b\s*(=|;|,|\))" "$f" >/dev/null; then echo "  FAIL $f declares a variable with a reserved MQL5 word"; FAIL=1; else echo "  PASS $f: no variable is named with a reserved MQL5 word"; fi
done
python3 -I - $TC <<'PYEOF' && echo "  PASS generated arrays hold literals only" || { echo "  FAIL"; FAIL=1; }
import re, sys
t = open(sys.argv[1], encoding='ascii').read()
blk = t[t.index('// BEGIN GENERATED'):t.index('// END GENERATED')]
for m in re.finditer(r'^(?:string|int|long) \w+\[\]=\{(.*)\};$', blk, re.M):
    body = re.sub(r'"(?:[^"\\]|\\.)*"', '', m.group(1))
    if re.search(r'[A-Za-z_(]', body):
        print('non-literal initializer:', m.group(0)[:80]); sys.exit(1)
PYEOF

echo "=== S7: negative controls ==="
cp $COD "$NEG/A.mqh"; sed -i 's/^string ESC_VerdictName(/int zz=FileOpen("x",FILE_READ);\nstring ESC_VerdictName(/' "$NEG/A.mqh"
$CHK persist "$NEG/A.mqh" >/dev/null 2>&1 && { echo "  FAIL file access in the codec was not detected"; FAIL=1; } || echo "  PASS file access in the codec is detected"
cp $FIL "$NEG/B.mqh"; sed -i 's/^string ESF_FileName(/MqlTradeRequest rq;\nstring ESF_FileName(/' "$NEG/B.mqh"
$CHK trading "$NEG/B.mqh" >/dev/null 2>&1 && { echo "  FAIL order structure in the file layer was not detected"; FAIL=1; } || echo "  PASS an order structure in the file layer is detected"
cp $FIL "$NEG/C.mqh"; sed -i 's/FileMove(tmp,0,name,FILE_REWRITE)/FileMove(tmp,name,FILE_REWRITE)/' "$NEG/C.mqh"
python3 -I - "$NEG/C.mqh" <<'PYEOF' && { echo "  FAIL a FileMove with 3 arguments was not detected"; FAIL=1; } || echo "  PASS a FileMove with the wrong argument count is detected"
import re, sys
code = open(sys.argv[1], encoding='ascii').read()
m = re.search(r'FileMove\s*\((.*?)\)\s*\)', code)
sys.exit(0 if m and m.group(1).count(',') == 3 else 1)
PYEOF
cp $COD "$NEG/D.mqh"; sed -i 's/   b+="DUPLICATES="+IntegerToString(st.duplicates_ignored)+"\\n";//' "$NEG/D.mqh"
python3 -I - "$NEG/D.mqh" <<'PYEOF' && { echo "  FAIL a field missing from the encoder was not detected"; FAIL=1; } || echo "  PASS a SEaState field missing from the encoder is detected"
import re, sys
c = open(sys.argv[1], encoding='ascii').read()
enc = c[c.index('bool ESC_Encode('):c.index('int ESC_Lines(')]
sys.exit(0 if re.search(r'\bst\.duplicates_ignored\b', enc) else 1)
PYEOF
cp $FIL "$NEG/E.mqh"; sed -i '/#include "ExitStateCodec.mqh"/d' "$NEG/E.mqh"
grep -q '#include "ExitStateCodec.mqh"' "$NEG/E.mqh" && { echo "  FAIL include control"; FAIL=1; } || echo "  PASS a file layer without its direct include is detected"
cp $COD "$NEG/F.mqh"; sed -i 's/TimeCurrent/zz/; s/^string ESC_VerdictName(/datetime zt=TimeCurrent();\nstring ESC_VerdictName(/' "$NEG/F.mqh"
grep -qE 'TimeCurrent' "$NEG/F.mqh" && echo "  PASS a clock read in the codec is detected" || { echo "  FAIL clock control"; FAIL=1; }
cp $TC "$NEG/G.mq5"; sed -i 's/bool ok=ESC_Decode/bool final=ESC_Decode/' "$NEG/G.mq5"
grep -nE "\b(bool|int|long|double|string)\s+($RESERVED)\b\s*(=|;|,|\))" "$NEG/G.mq5" >/dev/null && echo "  PASS a variable named final is detected" || { echo "  FAIL reserved-word control"; FAIL=1; }
cp $COD "$NEG/H.mqh"; echo "void x(){" >> "$NEG/H.mqh"
python3 tools/t001-check-balance.py "$NEG/H.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace"; FAIL=1; } || echo "  PASS unbalanced brace detected"

echo
[ $FAIL -eq 0 ] && echo "T011 PERSIST STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T011 PERSIST STATIC CHECKS: FAILURES"
exit $FAIL
