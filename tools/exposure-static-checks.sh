#!/bin/bash
# Static checks for T018 (read-only exposure reader): the core is pure (no terminal, no order function), ownership is the magic on a hedging account, unknown is never zero, the real port only reads,
# the EA wiring is opt-in (EXPLICIT / UNSET defaults) with no fallback to the manual exposure inputs, protected modules untouched. NOT a compiler, NOT an MT5 run.
# Usage: bash tools/exposure-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=c6e9557
CORE=src/include/ExposureReader.mqh
REAL=src/include/ExposureReaderReal.mqh
EA=src/XauUsdEntryOrchestrator.mq5
TS=src/tests/ExposureReaderTest.mq5
FILES="$CORE $REAL $EA $TS tests/exposure_reference.py tests/test_exposure.py tools/exposure-static-checks.sh"

echo "=== X1: files exist, ASCII only ==="
for f in $FILES; do
  [ -s "$f" ] || { echo "  FAIL $f missing or empty"; FAIL=1; continue; }
  if LC_ALL=C grep -nP '[^\x00-\x7F]' "$f" >/dev/null; then echo "  FAIL $f has non-ASCII characters"; FAIL=1; else echo "  PASS $f exists, ASCII"; fi
done

echo "=== X2: the core is pure and keeps the ownership / unknown rules ==="
cat > "$NEG/x2.py" <<'PYEOF'
import re, sys
t = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
for w in ('OrderSend', 'OrderCheck', 'OrderCalcProfit', 'PositionClose', 'PositionGet', 'OrderGet', 'PositionsTotal', 'OrdersTotal', 'AccountInfo', 'SymbolInfo', 'FileOpen', 'FileWrite', 'GlobalVariable',
          'TimeCurrent', 'TimeGMT', 'TimeLocal', 'Sleep', 'EntryTransportReal'):
    assert w not in t, w
assert re.findall(r'#include "([^"]+)"', t) == [], 'the core includes nothing'
c = t[t.index('void EX_Compute('):]
order = ['INPUT_UNSET', 'port.Account(', 'ACCOUNT_UNREADABLE', 'mode!=EX_HEDGING', 'port.Positions(', 'POSITIONS_INCOMPLETE', 'pos[i].magic!=magic', 'POSITION_TYPE_UNKNOWN',
         'if(pend_policy==EX_PEND_COUNT)', 'port.Orders(', 'ORDERS_INCOMPLETE', 'ord[i].magic!=magic', 'ORDER_TYPE_UNKNOWN', 'r.ok=true;', 'EX_Usable(own[i])', 'port.Calc(', 'MathMax(0.0,-profit)',
         'r.existing_risk=(r.risk_known ? total : -1.0)']
for o in order:
    assert o in c, 'missing step: ' + o
pos = [c.index(o) for o in order]
assert pos == sorted(pos), pos
assert c.count('port.Orders(') == 1 and c.count('port.Calc(') == 1 and c.count('port.Positions(') == 1, 'call sites'
assert 'long EX_GatePositions(const SExResult &r) {return(r.ok ? r.open_positions : -1);}' in t, 'gate positions mapping'
assert 'double EX_GateRisk(const SExResult &r) {return((r.ok && r.risk_known) ? r.existing_risk : -1.0);}' in t, 'gate risk mapping'
assert 'pend_policy!=EX_PEND_COUNT && pend_policy!=EX_PEND_IGNORE' in c, 'pending policy default'
PYEOF
python3 -I "$NEG/x2.py" $CORE && echo "  PASS pure core, order of the checks, magic-only ownership, hedging only, unknown is -1, one read of each list, one calculation call site" || { echo "  FAIL"; FAIL=1; }

echo "=== X3: the real port only reads; the EA wiring is opt-in and has no fallback ==="
cat > "$NEG/x3.py" <<'PYEOF'
import re, sys
real = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
ea = re.sub(r'//[^\n]*', '', open(sys.argv[2], encoding='ascii').read())
for w in ('OrderSend', 'OrderCheck', 'OrderDelete', 'PositionClose', 'CTrade', 'TRADE_ACTION', 'FileOpen', 'FileWrite', 'GlobalVariableSet', 'ObjectCreate', 'SymbolInfoDouble', 'DBS_', 'EntryTransportReal'):
    assert w not in real, 'real port: ' + w
assert 'OrderCalcProfit(' in real and 'PositionsTotal()' in real and 'OrdersTotal()' in real, 'real reads'
assert 'class CExRealPort : public CExPort' in real
assert 'InpExposureSource=EOI_EXPOSURE_EXPLICIT' in ea, 'exposure source default'
assert 'InpPendingPolicy=EOI_PENDING_UNSET' in ea, 'pending policy default'
w = ea[ea.index('if(InpExposureSource==EOI_EXPOSURE_ACCOUNT_READ)'):ea.index('SEoOutcome out;')]
assert 'EX_Compute(InpEaMagic,_Symbol,(int)InpPendingPolicy' in w and 'g_cfg.open_positions=EX_GatePositions(ex)' in w and 'g_cfg.existing_risk=EX_GateRisk(ex)' in w, 'wiring'
assert 'InpOpenPositions' not in w and 'InpExistingRisk' not in w, 'a fallback to the manual exposure inputs'
assert ea.count('EX_Compute(') == 1 and ea.count('CExRealPort') == 1, 'one read per build'
assert 'OrderSend' not in ea and 'CEnRealTransport' not in ea
PYEOF
python3 -I "$NEG/x3.py" $REAL $EA && echo "  PASS read-only port, opt-in defaults, wiring without a manual fallback" || { echo "  FAIL"; FAIL=1; }

echo "=== X4: the test uses a scripted port only ==="
grep -nE 'EntryTransportReal|ExposureReaderReal|OrderSend|PositionsTotal|OrdersTotal|AccountInfo|OrderCalcProfit' $TS >/dev/null && { echo "  FAIL the test touches the terminal"; FAIL=1; } || echo "  PASS the test uses the scripted fake port only"

echo "=== X5: protected modules are untouched since $BASE ==="
for p in src/include/EntryTransport.mqh src/include/EntryTransportFake.mqh src/include/EntryTransportReal.mqh src/include/EntryStateFile.mqh src/include/EntryExecutor.mqh src/include/EntryGate.mqh \
         src/include/EntryOrchestrator.mqh src/include/EntryOrchestratorFeed.mqh src/include/SetupPlanBridge.mqh src/include/TradePlanning.mqh src/include/BrokerLossCheck.mqh src/include/DailyBridge.mqh \
         src/include/DailyBalanceStore.mqh src/include/ExitExecutor.mqh src/include/ExitTickDriver.mqh src/XauUsdTradePreview.mq5 src/XauUsdT011ExitManager.mq5; do
  if git cat-file -e $BASE:$p 2>/dev/null; then
    if git diff --quiet $BASE -- $p; then echo "  PASS $p identical to $BASE"; else echo "  FAIL $p differs from $BASE"; FAIL=1; fi
  else echo "  SKIP $p (base not available)"; fi
done

echo "=== X6: negative controls ==="
expect_assert() {   # $1 script, $2 file(s), $3 message, $4 text the assertion message must contain
  if err=$(python3 -I "$1" $2 2>&1 >/dev/null); then echo "  FAIL $3 NOT detected"; FAIL=1;
  elif echo "$err" | grep -q "AssertionError.*$4"; then echo "  PASS $3 is detected";
  else echo "  FAIL $3: the control broke for another reason: $(echo "$err" | tail -1)"; FAIL=1; fi
}
mut() {   # $1 name, $2 source, $3 sed expression
  cp "$2" "$NEG/$1"; sed -i "$3" "$NEG/$1"; cmp -s "$2" "$NEG/$1" && { echo "  FAIL control $1 changed nothing"; FAIL=1; }
}
mut A.mqh $CORE 's/   if(mode!=EX_HEDGING) {r.reason="OWNERSHIP_NOT_SEPARABLE"; return;}/   if(false) {}/'
expect_assert "$NEG/x2.py" "$NEG/A.mqh" "ownership assumed on a netting account" "missing step: mode!=EX_HEDGING"
mut B.mqh $CORE 's/      if(pos\[i\].magic!=magic) {r.foreign_positions++; continue;}/      if(false) {continue;}/'
expect_assert "$NEG/x2.py" "$NEG/B.mqh" "foreign positions counted as owned" "missing step: pos\[i\].magic"
mut C.mqh $CORE 's/   r.existing_risk=(r.risk_known ? total : -1.0);/   r.existing_risk=total;/'
expect_assert "$NEG/x2.py" "$NEG/C.mqh" "an unknown risk reported as a number" "missing step: r.existing_risk"
mut D.mqh $CORE 's/double EX_GateRisk(const SExResult \&r) {return((r.ok \&\& r.risk_known) ? r.existing_risk : -1.0);}/double EX_GateRisk(const SExResult \&r) {return(r.existing_risk);}/'
expect_assert "$NEG/x2.py" "$NEG/D.mqh" "a gate risk without the known flag" "gate risk mapping"
mut E.mqh $CORE 's/(pend_policy!=EX_PEND_COUNT \&\& pend_policy!=EX_PEND_IGNORE)/(false)/'
expect_assert "$NEG/x2.py" "$NEG/E.mqh" "a defaulted pending policy" "pending policy default"
mut F.mqh $CORE 's/   int nown_pos=nown;/   int nown_pos=nown; OrderSend();/'
expect_assert "$NEG/x2.py" "$NEG/F.mqh" "an order call in the core" "OrderSend"
mut G.mqh $REAL 's/      return(OrderCalcProfit(/      return(OrderSend() \&\& OrderCalcProfit(/'
expect_assert "$NEG/x3.py" "$NEG/G.mqh $EA" "an order call in the real port" "OrderSend"
mut H.mqh $EA 's/^input ENUM_EO_PENDING InpPendingPolicy=EOI_PENDING_UNSET;/input ENUM_EO_PENDING InpPendingPolicy=EOI_PENDING_COUNT_AS_POSITIONS;/'
expect_assert "$NEG/x3.py" "$REAL $NEG/H.mqh" "a defaulted pending policy in the EA" "pending policy default"
mut I.mqh $EA 's/      g_cfg.existing_risk=EX_GateRisk(ex);/      g_cfg.existing_risk=(ex.risk_known ? ex.existing_risk : InpExistingRisk);/'
expect_assert "$NEG/x3.py" "$REAL $NEG/I.mqh" "a fallback to the manual exposure input" "fallback to the manual\|wiring"

[ $FAIL -eq 0 ] && echo "EXPOSURE STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "EXPOSURE STATIC CHECKS: FAILURES"
exit $FAIL
