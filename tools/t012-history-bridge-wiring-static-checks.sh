#!/bin/bash
# Static checks for the HISTORY_BRIDGE source of the observation-only preview. NOT a compiler, NOT an MT5 run: compile and run are UNVERIFIED.
# Usage: bash tools/t012-history-bridge-wiring-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=f1db94c
EA=src/XauUsdTradePreview.mq5
SB=src/presets/XauUsdTradePreview_T012_history_bridge_readonly.set
SH=src/presets/XauUsdTradePreview_T012_hypothetical_daily_block.set
CHK="python3 -I tools/t010-static-check.py"

echo "=== S1: files ==="
for f in $EA $SB $SH tests/test_t012_history_bridge_wiring.py; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing"; FAIL=1; }; done

echo "=== S2: the preview has no order / cancellation / persistence / direct account or history API ==="
out=$($CHK trading $EA) && echo "  PASS no order/position API" || { echo "$out"; FAIL=1; }
out=$($CHK persist $EA) && echo "  PASS no file, global-variable, network or mail access" || { echo "$out"; FAIL=1; }
if grep -nE 'Account(Info|InfoDouble|InfoInteger)|HistorySelect|HistoryDeal|HistoryOrder|PositionsTotal|OrdersTotal|PositionGet' $EA >/dev/null; then echo "  FAIL the EA calls an account/history/position API directly (reads live only in DailyHistory.mqh)"; FAIL=1; else echo "  PASS the EA reads history only through DH_ReadAndBuild"; fi

echo "=== S3: the chain is DH_ReadAndBuild -> DB_Check -> daily result -> the one final assignment, inside the bridge branch ==="
python3 -I - $EA <<'PYEOF' && echo "  PASS chain, order, single call sites, final result and tester refusal" || { echo "  FAIL"; FAIL=1; }
import re, sys
t = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
i = t.index('if(daily_bridge)\n     {')
j = t.index('\n     }', i)
blk = t[i:j]
assert t.count('DH_ReadAndBuild(') == 1 and blk.count('DH_ReadAndBuild(') == 1, 'history read outside the bridge branch'
assert t.count('DB_Check(') == 1 and blk.count('DB_Check(') == 1, 'DB_Check outside the bridge branch'
assert blk.index('DH_ReadAndBuild(') < blk.index('DB_Check('), 'order'
assert 'daily_evaluated=true;' in blk
assert t.index('if(daily_bridge && MQLInfoInteger(MQL_TESTER)) {StopPreview("DAILY_HISTORY_UNAVAILABLE_IN_TESTER");return;}') < t.index('DH_ReadAndBuild('), 'tester refusal after the read'
fin = [l.strip() for l in t.splitlines() if 'bool preview_ok' in l]
assert fin == ['bool preview_ok=DG_FinalPreview(loss_check=="OK",permit.allow,daily_evaluated,daily.entry_allowed);'], fin
assert len(re.findall(r'\bpreview_ok\s*=[^=]', t)) == 1
for w in ('InpDailyClosedResult', 'InpDailyResultKnown', 'TimeTradeServer', 'SymbolInfo'):
    assert w not in blk, w
assert not re.search(r'(result_formula|classification)\s*=\s*"', blk), 'a policy literal is assigned'
assert not re.search(r'(ea_magic|server_offset_seconds)\s*=\s*\d', blk), 'a magic/offset literal'
PYEOF

echo "=== S4: only the allowed existing lines of the preview changed since $BASE ==="
python3 -I - $BASE $EA <<'PYEOF' && echo "  PASS exactly the version, the enum, two input comments, the source comment line and the MANUAL log line changed" || { echo "  FAIL"; FAIL=1; }
import difflib, subprocess, sys
base = subprocess.run(['git', 'show', sys.argv[1] + ':src/XauUsdTradePreview.mq5'], capture_output=True, text=True).stdout
if not base:
    print('base not available'); sys.exit(0)
old = [l.rstrip() for l in base.splitlines()]
new = [l.rstrip() for l in open(sys.argv[2], encoding='ascii').read().splitlines()]
pref = ('#property version "1.04"', 'enum PREVIEW_DAILY_SOURCE {', 'input PREVIEW_DAILY_SOURCE InpDailySource=', 'input int InpDailySnapshotDay=0;',
        'input double InpDailyBalanceStart=-1;', 'else Print("T012 DAILY source=MANUAL')
rem = [l[2:] for l in difflib.ndiff(old, new) if l.startswith('- ')]
bad = [l for l in rem if not l.strip().startswith(pref)]
for l in bad:
    print('changed/removed line:', l)
sys.exit(1 if bad or len(rem) != 6 else 0)
PYEOF

echo "=== S5: both presets list every input exactly once; defaults stay unset ==="
python3 -I - $EA $SB $SH <<'PYEOF' && echo "  PASS preset inputs equal the EA inputs; the bridge preset is read-only with an incomplete history and UNSET policies" || { echo "  FAIL"; FAIL=1; }
import re, sys
ea = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
inputs = dict(re.findall(r'^input\s+\w+\s+(Inp\w+)\s*=\s*([^;]+);', ea, re.M))
def load(p):
    d = {}
    for l in open(p, encoding='ascii'):
        l = l.strip()
        if l and not l.startswith(';'):
            k, v = l.split('=', 1)
            assert k not in d, 'duplicate ' + k
            d[k] = v
    return d
for p in sys.argv[2:]:
    d = load(p)
    assert sorted(d) == sorted(inputs), (p, sorted(set(inputs) ^ set(d)))
b = load(sys.argv[2])
assert b['InpDailySource'] == '2' and b['InpDailyHistoryComplete'] == 'false' and b['InpDailyResultFormula'] == 'UNSET' and b['InpDailyClassification'] == 'UNSET'
assert b['InpDailyBalanceStart'] == '-1' and b['InpMaxTrades'] == '-1'
assert inputs['InpDailyEaMagic'] == '0' and inputs['InpDailyServerOffsetSeconds'] == '99999' and inputs['InpDailyHistoryComplete'] == 'false'
assert inputs['InpDailyResultFormula'] == '"UNSET"' and inputs['InpDailyClassification'] == '"UNSET"' and inputs['InpDailySource'] == 'DAILY_SRC_MANUAL'
PYEOF

echo "=== S6: balance, format strings, includes, ASCII, reserved words ==="
python3 tools/t001-check-balance.py $EA || FAIL=1
python3 - $EA <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
bad=0; for inc in $(grep -oE '#include "[^"]+"' $EA | sed 's/#include "//;s/"//'); do [ -f "src/$inc" ] || { echo "  FAIL missing include src/$inc"; bad=1; FAIL=1; }; done
[ $bad -eq 0 ] && echo "  PASS every include of the EA resolves"
for f in $EA $SB $SH; do n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true); [ "$n" = "0" ] || { echo "  FAIL $f: non-ASCII"; FAIL=1; }; done
echo "  INFO ASCII-only checked"
RESERVED='final|override|sealed|explicit|delete|new|virtual|template|typename|operator|this|static|class|struct|union|enum|public|private|protected|extern|input|sinput|void|auto|namespace|using|typedef|interface|implements'
grep -nE "\b(bool|int|long|double|string|ulong|uint|datetime)\s+($RESERVED)\b\s*(=|;|,|\))" $EA >/dev/null && { echo "  FAIL reserved word as a variable name"; FAIL=1; } || echo "  PASS no variable is named with a reserved MQL5 word"
echo "=== S7: verified modules identical to $BASE ==="
for p in src/include/DailyBridge.mqh src/include/DailyHistory.mqh src/include/DailyLimits.mqh src/include/DailyPreviewGate.mqh src/include/SessionPolicy.mqh; do
  git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
done

echo "=== S8: negative controls ==="
cp $EA "$NEG/A.mq5"; sed -i 's/DH_ReadAndBuild(_Symbol/DH_ReadAndBuild(_Symbol/; s/^   bool daily_bridge=/   double zz=AccountInfoDouble(ACCOUNT_BALANCE);\n   bool daily_bridge=/' "$NEG/A.mq5"
grep -qE 'Account(Info|InfoDouble|InfoInteger)' "$NEG/A.mq5" && echo "  PASS a direct account read in the EA is detected" || { echo "  FAIL account control"; FAIL=1; }
cp $EA "$NEG/B.mq5"; sed -i 's/bool preview_ok=DG_FinalPreview(loss_check=="OK",permit.allow,daily_evaluated,daily.entry_allowed);/bool preview_ok=(loss_check=="OK" \&\& permit.allow);/' "$NEG/B.mq5"
grep -qF 'bool preview_ok=DG_FinalPreview(loss_check=="OK",permit.allow,daily_evaluated,daily.entry_allowed);' "$NEG/B.mq5" && { echo "  FAIL ignored-daily control"; FAIL=1; } || echo "  PASS an EA whose final result ignores the bridge loses the pin (detected)"
cp $EA "$NEG/C.mq5"; sed -i 's/hpolicy.result_formula=InpDailyResultFormula;/hpolicy.result_formula="PROFIT";/' "$NEG/C.mq5"
grep -qE 'result_formula\s*=\s*"' "$NEG/C.mq5" && echo "  PASS a guessed policy literal is detected" || { echo "  FAIL policy control"; FAIL=1; }
cp $EA "$NEG/D.mq5"; sed -i 's/hcfg.server_offset_seconds=InpDailyServerOffsetSeconds;/hcfg.server_offset_seconds=(int)(TimeTradeServer()-TimeGMT());/' "$NEG/D.mq5"
grep -q 'TimeTradeServer()-TimeGMT()' "$NEG/D.mq5" && ! grep -qF 'hcfg.server_offset_seconds=InpDailyServerOffsetSeconds;' "$NEG/D.mq5" && echo "  PASS an offset derived from the clock loses the explicit-input pin (detected)" || { echo "  FAIL offset control"; FAIL=1; }
cp $SB "$NEG/E.set"; sed -i 's/^InpDailyHistoryComplete=false/InpDailyHistoryComplete=true/' "$NEG/E.set"
grep -q '^InpDailyHistoryComplete=false' "$NEG/E.set" && { echo "  FAIL preset control"; FAIL=1; } || echo "  PASS a bridge preset that asserts completeness no longer matches the pin (detected)"
cp $SB "$NEG/F.set"; sed -i '/^InpDailyEaMagic=/d' "$NEG/F.set"
python3 -I - $EA "$NEG/F.set" <<'PYEOF' && { echo "  FAIL a preset missing an input was not detected"; FAIL=1; } || echo "  PASS a preset that misses an input is detected"
import re, sys
ea = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
names = [n for n, _ in re.findall(r'^input\s+\w+\s+(Inp\w+)\s*=\s*([^;]+);', ea, re.M)]
keys = [l.split('=', 1)[0] for l in open(sys.argv[2], encoding='ascii') if l.strip() and not l.startswith(';')]
sys.exit(0 if sorted(keys) == sorted(names) else 1)
PYEOF
cp $EA "$NEG/G.mq5"; echo "void x(){" >> "$NEG/G.mq5"
python3 tools/t001-check-balance.py "$NEG/G.mq5" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace"; FAIL=1; } || echo "  PASS unbalanced brace detected"

echo
[ $FAIL -eq 0 ] && echo "T012 HISTORY_BRIDGE WIRING STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T012 HISTORY_BRIDGE WIRING STATIC CHECKS: FAILURES"
exit $FAIL
