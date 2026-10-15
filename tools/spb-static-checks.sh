#!/bin/bash
# Static checks for the T014 setup -> plan bridge: pure (no execution module, no terminal call, no clock), one TP_BuildPlan call and no geometry / sizing / permit logic, no detection code, explicit
# selections, protected modules untouched. NOT a compiler, NOT an MT5 run. Usage: bash tools/spb-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=1b0016a
HD=src/include/SetupPlanBridge.mqh
TS=src/tests/SetupPlanBridgeTest.mq5
FILES="$HD $TS tests/spb_reference.py tests/test_spb.py tools/spb-static-checks.sh"

echo "=== B1: files exist, ASCII only ==="
for f in $FILES; do
  [ -s "$f" ] || { echo "  FAIL $f missing or empty"; FAIL=1; continue; }
  if LC_ALL=C grep -nP '[^\x00-\x7F]' "$f" >/dev/null; then echo "  FAIL $f has non-ASCII characters"; FAIL=1; else echo "  PASS $f exists, ASCII"; fi
done

echo "=== B2: the bridge is pure and only reuses the existing builder ==="
cat > "$NEG/b2.py" <<'PYEOF'
import re, sys
t = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
assert t.count('TP_BuildPlan(') == 1, 'exactly one plan builder call'
assert t.count('TG_Compute(') == 1, 'TG_Compute geometry call count'
geometry = t[t.index('bool SPB_Geometry('):t.index('void SPB_Build(')]
assert 'TG_Compute(' in geometry and 'TP_BuildPlan(' not in geometry, 'geometry before sizing'
for w in ('PS_Compute', 'TP_CheckPermit', 'TP_Authorize', 'TP_CancelDecision', 'OrderSend', 'OrderCheck', 'CTrade', 'FileOpen', 'FileWrite', 'FileDelete', 'GlobalVariable',
          'TimeCurrent', 'TimeGMT', 'TimeLocal', 'TimeTradeServer', 'Sleep', 'AccountInfo', 'SymbolInfo', 'CopyRates', 'HistorySelect', 'PositionGet', 'M4Step(', 'M4SetContext(', 'M4Init(',
          'M4SelectSwingProposal', 'H3'):
    assert w not in t, w
assert re.search(r'\b(EN|EX|ETD|ER|XA|ESC|ESF|EL)_', t) is None, 'an execution module is referenced'
inc = re.findall(r'#include "([^"]+)"', t)
assert sorted(inc) == ['M15Confirmation.mqh', 'TradePlanning.mqh'], inc
# the bridge only READS the observer: it never assigns a member of st / f / broken
assert re.search(r'\b(st|f\[[^\]]*\]|broken)\.\w+\s*=[^=]', t) is None, 'the observer state is written'
# the near edge / stop / target come from explicit selections only; the order of the checks
b = t[t.index('bool SPB_Prepare('):]
order = ['SPB_Unset(sel,asof)', 'CONTEXT_LOST_OR_NOT_READY', 'CONTEXT_SOURCE_MISMATCH', 'TIMING_MISMATCH', 'REPLAY_REQUIRED', 'RETURN_ALREADY_OBSERVED', 'PHASE_NOT_WAIT_RETURN', 'FUTURE_DATA',
         'BROKEN_LEVEL_MISMATCH', 'CANDIDATE_IDS_NOT_UNIQUE', 'AMBIGUOUS_CANDIDATES', 'CANDIDATE_DIRECTION_INCONSISTENT', 'HISTORICAL_OR_REPLAYED_CANDIDATE', 'TP_BuildPlan(']
pos = [b.index(o) for o in order]
assert pos == sorted(pos), pos
assert 'plan_ready=true' in b and b.rindex('plan_ready=true') > b.index('TP_BuildPlan(')
# a plan is never marked ready before the builder accepted it, and no permit is produced
assert 'permit' not in t.lower().replace('tp_checkpermit', '')
# no default selection: SPB_SelectionInit leaves everything unset
init = t[t.index('void SPB_SelectionInit('):t.index('struct SSpbMarket')]
for need in ('SPB_SWING_UNSET', 'SPB_CAND_UNSET', 'SPB_EDGE_UNSET', 'SPB_SL_UNSET', 'SPB_TGT_UNSET', 'M4_POLICY_UNSET', 'sl_buffer_set=false', 'live_after=0'):
    assert need in init, need
# no clock / counter / random value in the ids
ids = t[t.index('string SPB_SetupId('):t.index('bool SPB_Prepare(')]
assert 'Time' not in ids and 'asof' not in ids and 'live_after' not in ids
sig = [l for l in b.split('\n') if l.strip().startswith('string signal=')]
assert sig == ['   string signal=setup+"|"+f[pick].id;'], sig
PYEOF
python3 -I "$NEG/b2.py" $HD && echo "  PASS pure, one TP_BuildPlan, no execution module, observer read-only, check order, nothing selected by default, ids without clock" || { echo "  FAIL"; FAIL=1; }

echo "=== B3: the test never includes an execution transport or the real transport ==="
grep -nE 'EntryTransportReal|ExitTransportReal|EntryExecutor|ExitExecutor|OrderSend' $TS >/dev/null && { echo "  FAIL the test touches the execution side"; FAIL=1; } || echo "  PASS the test uses only the bridge and the T004 observer"

echo "=== B4: protected modules are untouched since $BASE ==="
for p in src/include/TradePlanning.mqh src/include/TradeGeometry.mqh src/include/PositionSizing.mqh src/include/M15Confirmation.mqh src/include/M15SwingProposal.mqh src/include/M15Timeline.mqh \
         src/include/H4M15Bridge.mqh src/include/H4Bias.mqh src/include/H4Structure.mqh src/include/H4TouchContext.mqh src/include/EntryTransport.mqh \
         src/include/EntryTransportFake.mqh src/include/EntryTransportReal.mqh src/include/ExitExecutor.mqh src/include/ExitTickDriver.mqh src/include/DailyBalanceStore.mqh src/XauUsdTradePreview.mq5 \
         src/XauUsdM15Observer.mq5 src/XauUsdT011DemoOpenPosition.mq5; do
  if git cat-file -e $BASE:$p 2>/dev/null; then
    if git diff --quiet $BASE -- $p; then echo "  PASS $p identical to $BASE"; else echo "  FAIL $p differs from $BASE"; FAIL=1; fi
  else echo "  SKIP $p (base not available)"; fi
done

echo "=== B5: negative controls ==="
expect_assert() {   # $1 script, $2 file, $3 message, $4 text the assertion message must contain
  if err=$(python3 -I "$1" "$2" 2>&1 >/dev/null); then echo "  FAIL $3 NOT detected"; FAIL=1;
  elif echo "$err" | grep -q "AssertionError.*$4"; then echo "  PASS $3 is detected";
  else echo "  FAIL $3: the control broke for another reason: $(echo "$err" | tail -1)"; FAIL=1; fi
}
cp $HD "$NEG/A.mqh"; sed -i 's/   out.plan_ready=true;/   out.plan_ready=true;\n   TG_Compute(d,e,s,has_target,t,mkt.tick_size,mkt.digits,mkt.point,mkt.stops_level,mkt.has_quote,mkt.bid,mkt.ask,*(STgResult*)0);/' "$NEG/A.mqh"
expect_assert "$NEG/b2.py" "$NEG/A.mqh" "geometry logic copied into the bridge" "TG_Compute"
cp $HD "$NEG/B.mqh"; sed -i 's/   SPB_ResultInit(out);\n   string bad=SPB_Unset/XX/; s/   int d=st.context.direction;/   int d=st.context.direction;\n   st.phase="WAIT_RETURN";/' "$NEG/B.mqh"
expect_assert "$NEG/b2.py" "$NEG/B.mqh" "a write into the observer state" "observer state is written"
cp $HD "$NEG/C.mqh"; sed -i 's/   s.entry_edge=SPB_EDGE_UNSET;/   s.entry_edge=SPB_EDGE_NEAR_SIDE;/' "$NEG/C.mqh"
expect_assert "$NEG/b2.py" "$NEG/C.mqh" "a default entry edge" "SPB_EDGE_UNSET"
cp $HD "$NEG/D.mqh"; sed -i 's/   string signal=setup+"|"+f\[pick\].id;/   string signal=setup+"|"+f[pick].id+"|"+IntegerToString((long)asof);/' "$NEG/D.mqh"
expect_assert "$NEG/b2.py" "$NEG/D.mqh" "a clock value in the signal id" "signal"
cp $HD "$NEG/E.mqh"; sed -i 's/#include "TradePlanning.mqh"/#include "TradePlanning.mqh"\n#include "EntryExecutor.mqh"/' "$NEG/E.mqh"
expect_assert "$NEG/b2.py" "$NEG/E.mqh" "an include of the execution side" "TradePlanning"
cp $HD "$NEG/F.mqh"; python3 - "$NEG/F.mqh" <<'PYEOF'
import sys
t = open(sys.argv[1]).read()
a = '   if(st.phase=="RETURN_OBSERVED") {SPB_Block(out,"RETURN_ALREADY_OBSERVED: the price already came back; no delayed entry"); return(false);}\n'
assert a in t
open(sys.argv[1], 'w').write(t.replace(a, ''))
PYEOF
expect_assert "$NEG/b2.py" "$NEG/F.mqh" "a missing RETURN_OBSERVED block" "[0-9]"

[ $FAIL -eq 0 ] && echo "SETUP PLAN BRIDGE STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "SETUP PLAN BRIDGE STATIC CHECKS: FAILURES"
exit $FAIL
