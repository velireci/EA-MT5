#!/bin/bash
# Static checks for the T016 entry orchestrator: the decision core only calls the existing modules in the pinned order (two plan passes, one probe, one EG_Submit), halts and keeps the baseline; the EA and the feed
# never send an order, never CAPTURE, never include a real transport, expose no transport selector and label every virtual request; protected modules are untouched. NOT a compiler, NOT an MT5 run.
# Usage: bash tools/entry-orchestrator-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=e8968bd
CORE=src/include/EntryOrchestrator.mqh
FEED=src/include/EntryOrchestratorFeed.mqh
EA=src/XauUsdEntryOrchestrator.mq5
TS=src/tests/EntryOrchestratorTest.mq5
FILES="$CORE $FEED $EA $TS tests/eo_reference.py tests/test_eo.py tools/entry-orchestrator-static-checks.sh"

echo "=== O1: files exist, ASCII only ==="
for f in $FILES; do
  [ -s "$f" ] || { echo "  FAIL $f missing or empty"; FAIL=1; continue; }
  if LC_ALL=C grep -nP '[^\x00-\x7F]' "$f" >/dev/null; then echo "  FAIL $f has non-ASCII characters"; FAIL=1; else echo "  PASS $f exists, ASCII"; fi
done

echo "=== O2: the core reuses the modules, in the pinned order, and touches no terminal ==="
cat > "$NEG/o2.py" <<'PYEOF'
import re, sys
t = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
assert t.count('SPB_Build(') == 2 and t.count('EG_Submit(') == 1 and t.count('PB_ProbeTickValue(') == 1, 'call sites'
for w in ('OrderSend', 'OrderCheck', 'OrderCalcProfit', 'TP_Authorize', 'DG_FinalPreview', 'FileOpen', 'FileWrite', 'GlobalVariable', 'TimeCurrent', 'TimeGMT', 'TimeLocal', 'Sleep', 'AccountInfo', 'SymbolInfo',
          'DBS_Capture', 'DBS_Load', 'CAPTURE', 'TP_BuildPlan', 'TG_Compute', 'PS_Compute', 'M4Step(', 'M4Replay', 'H3Evaluate', 'EntryTransportReal', 'ExitTransportReal', 'EN_Place(', 'store.Write', 'store.Lock', 'MathMax(baseline,0'):
    assert w not in t, w
step = t[t.index('void Step('):]
order = ['if(!feed_ok)', 'Defect();', 'k!=key) rebase=true', 'baseline=MathMax(baseline,(long)cut)', 'if(halted!="")', 'EO_UnsetConfig(c)', 'mk.Symbol(sym)', 'mk.Quote(q)', 'sel.live_after=baseline',
         'SPB_Build(sel,m,st,f,broken,cut,r1)', 'Handled(r1.signal_id)', 'mk.CalcProfit(buy,sym.vol_min', 'PB_ProbeTickValue(', 'm.tick_value=tick', 'SPB_Build(sel,m,st,f,broken,cut,r2)',
         'mk.CalcProfit(buy,r2.plan.volume_out', 'mk.Filters(', 'chk.daily_present=mk.Daily(', 'EG_Submit(', 'Remember(r2.signal_id)', 'halted="HALTED after']
for o in order:
    assert o in step, 'missing step: ' + o
pos = [step.index(o) for o in order]
assert pos == sorted(pos), pos
assert 'baseline=MathMax(baseline' in step and 'baseline=cut' not in step and 'baseline=0' not in step, 'baseline can move backwards'
assert 'if(!(tick>0.0))' in step and 'tick=sym.reported_tick_value' not in step and 'm.tick_value=sym.reported_tick_value;' in step[:step.index('SPB_Build(sel,m,st,f,broken,cut,r1)')], 'tick value'
assert 'chk.snap_digest=digest' in step and 'chk.loss_digest=digest' in step and 'chk.daily_digest=digest' in step, 'plan digest binding'
assert 'chk.snap_time=now' in step and 'chk.loss_time=now' in step and 'chk.daily_time=now' in step, 'shared instant'
assert 'EN_RuntimeInit(rt)' in step and step.index('EN_RuntimeInit(rt)') < step.index('EG_Submit('), 'fresh runtime per signal'
assert 'EN_R_CANCEL_UNCERTAIN' in step and 'EN_R_RECOVERY' in step and 'EN_R_BLOCKED' in step, 'halt results'
assert 'EO_FAKE_LABEL' in step and 'out.request=true' in step, 'label'
assert re.search(r'out\.request=true;\s*out\.label=EO_FAKE_LABEL', step), 'request without label'
inc = re.findall(r'#include "([^"]+)"', t)
assert inc == ['EntryGate.mqh'], inc
PYEOF
python3 -I "$NEG/o2.py" $CORE && echo "  PASS call sites, no terminal / file / clock / real transport, order, baseline, probe, shared instant and digest, fresh runtime, halt, label" || { echo "  FAIL"; FAIL=1; }

echo "=== O3: the EA and the feed: fake transport fixed, read-only, LOAD only, labelled ==="
cat > "$NEG/o3.py" <<'PYEOF'
import re, sys
ea = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
fd = re.sub(r'//[^\n]*', '', open(sys.argv[2], encoding='ascii').read())
for name, t in (('EA', ea), ('feed', fd)):
    for w in ('OrderSend', 'OrderSendAsync', 'OrderCheck', 'OrderDelete', 'PositionClose', 'CTrade', 'DBS_Capture', 'DBS_Write', 'CAPTURE', 'TP_Authorize', 'DG_FinalPreview', 'FileOpen', 'FileWrite', 'FileDelete',
              'GlobalVariableSet', 'EntryTransportReal', 'ExitTransportReal', 'ExitStateFile', 'ExitExecutor', 'CEnRealTransport', 'CEnRealStore', 'ObjectCreate', 'real=true', 'real = true'):
        assert w not in t, name + ': ' + w
assert 'DBS_Load(' in fd and fd.count('DBS_Load(') == 1, 'the store is read with LOAD only'
assert 'class CEoTerminalFake : public CEnFakeTransport' in ea, 'fake transport class'
assert ea.count('CEoTerminalFake g_tr;') == 1 and 'GetPointer(g_tr)' in ea, 'transport fixed'
assert 'EO_FAKE_LABEL' in ea and 'CEnFakeTransport::Send(req,res)' in ea, 'virtual request label'
assert 'MQL_TESTER' in ea and 'INIT_FAILED' in ea, 'tester refused'
assert 'CEnFakeStore g_store;' in ea, 'in-memory store'
assert 'g_cfg.exec.symbol=_Symbol;' in ea and 'XAUUSD' not in ea.replace('XauUsdEntryOrchestrator', ''), 'chart symbol only'
inputs = re.findall(r'^input\s+\S+\s+(\w+)', ea, re.M)
assert inputs, 'inputs'
for n in inputs:
    assert not re.search(r'(?i)transport|real|live|send|order', n), 'a transport selector input: ' + n
# every selection / policy input is UNSET by default
for n in ('InpContextSource=EOI_SRC_UNSELECTED', 'InpM15Level=EOI_SWING_UNSELECTED', 'InpFvgTiming=EOI_TIMING_UNSELECTED', 'InpCandidate=EOI_CAND_UNSELECTED', 'InpEntryEdge=EOI_EDGE_UNSELECTED',
          'InpSlRule=EOI_SL_UNSELECTED', 'InpSlBuffer=-1', 'InpTargetRule=EOI_TGT_UNSELECTED', 'InpRiskBudget=-1', 'InpLotCap=-1', 'InpModelTolerance=-1', 'InpMaxQuoteAgeSeconds=-1', 'InpGateMaxAgeSeconds=-1',
          'InpPermitMaxAgeSeconds=-1', 'InpOpenPositions=-1', 'InpTradesToday=-1', 'InpExistingRisk=-1', 'InpMaxPositions=-1', 'InpMaxTrades=-1', 'InpCombinedRiskCap=-1', 'InpSessionClock=false',
          'InpNewsCalendar=false', 'InpMaxSpreadPoints=-1', 'InpDailyHistoryBridge=false', 'InpDailyServerOffsetSeconds=99999', 'InpDailyHistoryComplete=false', 'InpFilling=EOI_FILL_UNSET', 'InpExpiryMode=EOI_EXP_UNSET'):
    assert n in ea, 'default not UNSET: ' + n
assert sorted(re.findall(r'#include "([^"]+)"', ea)) == ['include/EntryOrchestratorFeed.mqh', 'include/EntryTransportFake.mqh'], 'EA includes'
assert 'daily_on=InpDailyHistoryBridge' in ea
PYEOF
python3 -I "$NEG/o3.py" $EA $FEED && echo "  PASS no order / CAPTURE / file write / real transport, fixed fake transport, no transport selector, UNSET defaults, tester refused, chart symbol, LOAD only" || { echo "  FAIL"; FAIL=1; }

echo "=== O4: the test never includes a real transport or reads the terminal ==="
grep -nE 'EntryTransportReal|ExitTransportReal|OrderSend|SymbolInfo|OrderCalcProfit|TimeCurrent|FileOpen|CopyRates|AccountInfo|DBS_' $TS >/dev/null && { echo "  FAIL the test touches the real side"; FAIL=1; } || echo "  PASS the test uses the fake transport, the fake store and a scripted market only"

echo "=== O5: protected modules are untouched since $BASE ==="
for p in src/include/EntryTransport.mqh src/include/EntryTransportFake.mqh src/include/EntryTransportReal.mqh src/include/EntryExecutor.mqh src/include/EntryGate.mqh src/include/SetupPlanBridge.mqh \
         src/include/TradePlanning.mqh src/include/BrokerLossCheck.mqh src/include/DailyBridge.mqh src/include/DailyLimits.mqh src/include/DailyPreviewGate.mqh src/include/DailyBalanceStore.mqh \
         src/include/M15Confirmation.mqh src/include/M15Timeline.mqh src/include/H4M15Bridge.mqh src/include/H4TouchContext.mqh src/include/TimeframeWatcher.mqh src/include/NewsSpreadFilters.mqh \
         src/include/SessionPolicy.mqh src/include/SymbolSnapshot.mqh src/include/ExitExecutor.mqh src/include/ExitTickDriver.mqh src/include/ExitStateFile.mqh src/XauUsdTradePreview.mq5 \
         src/XauUsdM15Observer.mq5 src/XauUsdT011DemoOpenPosition.mq5 src/XauUsdT011ExitManager.mq5; do
  if git cat-file -e $BASE:$p 2>/dev/null; then
    if git diff --quiet $BASE -- $p; then echo "  PASS $p identical to $BASE"; else echo "  FAIL $p differs from $BASE"; FAIL=1; fi
  else echo "  SKIP $p (base not available)"; fi
done

echo "=== O6: negative controls ==="
expect_assert() {   # $1 script, $2 file(s), $3 message, $4 text the assertion message must contain
  if err=$(python3 -I "$1" $2 2>&1 >/dev/null); then echo "  FAIL $3 NOT detected"; FAIL=1;
  elif echo "$err" | grep -q "AssertionError.*$4"; then echo "  PASS $3 is detected";
  else echo "  FAIL $3: the control broke for another reason: $(echo "$err" | tail -1)"; FAIL=1; fi
}
mut() {   # $1 name, $2 source, $3 sed expression
  cp "$2" "$NEG/$1"; sed -i "$3" "$NEG/$1"; cmp -s "$2" "$NEG/$1" && { echo "  FAIL control $1 changed nothing"; FAIL=1; }
}
mut A.mqh $CORE 's/      baseline=MathMax(baseline,(long)cut);/      baseline=(long)cut;/'
expect_assert "$NEG/o2.py" "$NEG/A.mqh" "a baseline that can move backwards" "missing step: baseline=MathMax"
mut B.mqh $CORE 's/   if(halted!="") {EO_Set(out,"HALTED",halted); return;}/   if(false) {}/'
expect_assert "$NEG/o2.py" "$NEG/B.mqh" "no halt after an uncertain outcome" "missing step: if(halted"
mut C.mqh $CORE 's/   if(!(tick>0.0)) {EO_Set(out,"PROBE_FAILED"/   if(false) {EO_Set(out,"PROBE_FAILED"/'
expect_assert "$NEG/o2.py" "$NEG/C.mqh" "a missing probe that does not block" "tick value"
mut D.mqh $CORE 's/      chk.snap_digest=digest;/      chk.snap_digest="";/'
expect_assert "$NEG/o2.py" "$NEG/D.mqh" "evidence not bound to the plan digest" "plan digest binding"
mut E.mqh $CORE 's/      chk.loss_time=now;/      chk.loss_time=0;/'
expect_assert "$NEG/o2.py" "$NEG/E.mqh" "evidence without the shared instant" "shared instant"
mut F.mqh $CORE 's/      EN_RuntimeInit(rt);/      \/\/ none/'
expect_assert "$NEG/o2.py" "$NEG/F.mqh" "a runtime reused across signals" "missing step: \|fresh runtime"
mut G.mqh $CORE 's/      SPB_Build(sel,m,st,f,broken,cut,r2);   /      OrderSend(); SPB_Build(sel,m,st,f,broken,cut,r2);   /'
expect_assert "$NEG/o2.py" "$NEG/G.mqh" "an order call in the core" "OrderSend"
mut H.mqh $CORE 's/         out.label=EO_FAKE_LABEL;/         out.label="";/'
expect_assert "$NEG/o2.py" "$NEG/H.mqh" "a virtual request without the label" "label\|request without label"
mut I.mqh $EA 's/#include "include\/EntryTransportFake.mqh"/#include "include\/EntryTransportFake.mqh"\n#include "include\/EntryTransportReal.mqh"/'
expect_assert "$NEG/o3.py" "$NEG/I.mqh $FEED" "the real transport included in the EA" "EntryTransportReal\|EA includes"
mut J.mqh $EA 's/^input long InpEaMagic=0; /input bool InpRealTransport=false; \/\/ x\ninput long InpEaMagic=0; /'
expect_assert "$NEG/o3.py" "$NEG/J.mqh $FEED" "a transport selector input" "transport selector input"
mut K.mqh $EA 's/^input double InpRiskBudget=-1; /input double InpRiskBudget=100; /'
expect_assert "$NEG/o3.py" "$NEG/K.mqh $FEED" "a policy input with a default value" "default not UNSET"
mut L.mqh $FEED 's/      DBS_Load(port,stored);/      DBS_Load(port,stored); DBS_Capture(port,stored);/'
expect_assert "$NEG/o3.py" "$EA $NEG/L.mqh" "a CAPTURE in the feed" "DBS_Capture\|LOAD only"
mut M.mqh $EA 's/   virtual void Send(const SEnRequest \&req,SEnSendResult \&res)/   virtual void Send(const SEnRequest \&req,SEnSendResult \&res) {OrderSend(); }\n   virtual void SendUnused(const SEnRequest \&req,SEnSendResult \&res)/'
expect_assert "$NEG/o3.py" "$NEG/M.mqh $FEED" "an OrderSend in the EA" "OrderSend"

[ $FAIL -eq 0 ] && echo "ENTRY ORCHESTRATOR STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "ENTRY ORCHESTRATOR STATIC CHECKS: FAILURES"
exit $FAIL
