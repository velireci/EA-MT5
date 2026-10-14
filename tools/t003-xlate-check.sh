#!/bin/bash
# T003 evidence: transliterate the MQL5 logic and test script to C++ and RUN them (g++, ASan/UBSan).
# This is NOT MetaEditor and NOT MT5 (see tools/t003_xlate/mql2cpp.py). It shows only that the
# transliterated H4Bias.mqh / H4Structure.mqh agree with the Python model on the controlled cases and
# that the hand-written MQL5 test checks pass in that setting. Compilation in MetaEditor stays UNVERIFIED.
# It runs two test scripts: T003_LogicTest.mq5 (H4Bias.mqh) and T003_LayersTest.mq5 (the pure helpers of the visual
# layers, src/include/H4BiasLayers.mqh: disagreement definition, bias timeline, T002 sources, historical liquidity, T002 baseline,
# panel wrap / line budget, label slot, export key / hash, since-baseline reset).
# Usage: bash tools/t003-xlate-check.sh   (exit 0 = both transliterated test scripts passed, failures 0)
set -u
cd "$(dirname "$0")/.."
command -v g++ >/dev/null || { echo "g++ not available: transliteration check not run"; exit 2; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
X=tools/t003_xlate
cp $X/mql_shim.hpp "$D/"
python3 $X/mql2cpp.py src/include/H4Structure.mqh "$D/H4Structure.hpp" || exit 1
python3 $X/mql2cpp.py src/include/H4Bias.mqh "$D/H4Bias.hpp" || exit 1
python3 $X/mql2cpp.py src/tests/T003_LogicTest.mq5 "$D/test.cpp" --test || exit 1
build_run() { # build_run NAME -> compiles $D/test.cpp, runs it, prints the summary line, returns the exit code
  g++ -std=c++17 -O1 -ftrivial-auto-var-init=zero -g -fsanitize=address,undefined -Wno-all -I"$D" "$D/test.cpp" -o "$D/$1" 2> "$D/$1.cerr" || { echo "  C++ build failed:"; head -5 "$D/$1.cerr"; return 3; }
  "$D/$1" > "$D/$1.out" 2> "$D/$1.err"; local rc=$?
  grep -E '^T003 LOGIC TEST finished' "$D/$1.out"
  [ -s "$D/$1.err" ] && { echo "  sanitizer / stderr output:"; head -5 "$D/$1.err"; rc=4; }
  return $rc
}
echo "=== transliterated T003_LogicTest.mq5 (C++, NOT MetaEditor) ==="
build_run run; rc=$?
echo "exit $rc"
# negative control: break the ratchet in the transliterated header, the same run must FAIL
sed -i 's/if(!(lvl.ext_time > st.lv_ext \&\& s \* lvl.price < s \* st.lv_price))/if(!(lvl.ext_time > st.lv_ext))/' "$D/H4Bias.hpp"
cmp -s "$D/H4Bias.hpp" <(python3 $X/mql2cpp.py src/include/H4Bias.mqh /dev/stdout) && { echo "NEG: the mutation did not change the header (vacuous)"; exit 5; }
echo "=== negative control: ratchet condition (iii) removed in the transliterated header ==="
build_run mut; rcm=$?
[ $rcm -eq 1 ] && echo "NEG PASS: the mutated logic fails the transliterated test script (exit $rcm = test failures, not a build error)" || { echo "NEG FAIL: mutation not detected or the build failed (exit $rcm)"; exit 6; }

# ---- the pure helpers of the visual layers (model/helper check; NOT MetaEditor, NOT MT5)
# The ratchet mutation above was applied to $D/H4Bias.hpp: translate the UNMUTATED header again, otherwise the layers test
# would run against the mutated logic (found in round 4: the earlier layers run used the mutated header).
python3 $X/mql2cpp.py src/include/H4Bias.mqh "$D/H4Bias.hpp" || exit 1
cmp -s "$D/H4Bias.hpp" <(python3 $X/mql2cpp.py src/include/H4Bias.mqh /dev/stdout) && echo "layers run uses the unmutated H4Bias header (re-translated)" || { echo "the header for the layers run differs from a fresh translation"; exit 5; }
python3 $X/mql2cpp.py src/include/H4BiasLayers.mqh "$D/H4BiasLayers.hpp" || exit 1
python3 $X/mql2cpp.py src/tests/T003_LayersTest.mq5 "$D/layers_test.cpp" --test || exit 1
build_layers() { # build_layers NAME -> compiles layers_test.cpp against the (possibly mutated) $D/H4BiasLayers.hpp
  g++ -std=c++17 -O1 -ftrivial-auto-var-init=zero -g -fsanitize=address,undefined -Wno-all -I"$D" "$D/layers_test.cpp" -o "$D/$1" 2> "$D/$1.cerr" || { echo "  C++ build failed:"; head -8 "$D/$1.cerr"; return 3; }
  "$D/$1" > "$D/$1.out" 2> "$D/$1.err"; local rc=$?
  grep -E '^T003 LAYERS TEST finished|^  INFO' "$D/$1.out"; grep -E '^  FAIL' "$D/$1.out" | head -5
  [ -s "$D/$1.err" ] && { echo "  sanitizer / stderr output:"; head -5 "$D/$1.err"; rc=4; }
  return $rc
}
echo "=== transliterated T003_LayersTest.mq5 (C++, NOT MetaEditor) ==="
build_layers lrun; rcl=$?
echo "exit $rcl"
# negative controls on the helpers: each mutation must make the same test fail
cp "$D/H4BiasLayers.hpp" "$D/H4BiasLayers.orig"
negl() { # negl LABEL OLD NEW
  cp "$D/H4BiasLayers.orig" "$D/H4BiasLayers.hpp"
  python3 - "$D/H4BiasLayers.hpp" "$2" "$3" <<'PYEOF' || { echo "NEG $1: the mutation target is absent (vacuous)"; return 1; }
import sys
p, old, new = sys.argv[1:4]
t = open(p).read()
if old not in t:
    sys.exit(3)
open(p, 'w').write(t.replace(old, new, 1))
PYEOF
  build_layers mutl > /dev/null; local r=$?
  [ $r -eq 1 ] && echo "NEG PASS $1 (exit $r = test failures)" || { echo "NEG FAIL $1: mutation not detected or build error (exit $r)"; return 1; }
}
negs=0
negl "MIXED counted as a disagreement" 'if(t2dir == H4_DIR_BULLISH && bias == H3_BEAR)' 'if(t2dir != H4_DIR_BEARISH && bias == H3_BEAR)' || negs=1
negl "liquidity: equal high counts as exceeded" 'if(win[j].high > sw[i].price)' 'if(win[j].high >= sw[i].price)' || negs=1
negl "liquidity: farthest first" 'if(best < 0 || dd < bd ||' 'if(best < 0 || dd > bd ||' || negs=1
negl "liquidity: unconfirmed swings included" 'int nk = H3KnownCount(sw, ns, right, nw - 1);' 'int nk = ns;' || negs=1
negl "short name is not deterministic-length" 'for(int k = 7; k >= 0; k--)' 'for(int k = 6; k >= 0; k--)' || negs=1
negl "bias timeline reads events after the bar" 'if(events[i].bar_time > bar_open)
         break;' 'if(events[i].bar_time > bar_open + 4 * 14400)
         break;' || negs=1
negl "run ignores the trusted region" 'int stop = (warm < last ? warm : last);' 'int stop = 0;' || negs=1
negl "baseline window is not the last N bars" 'int start = n_end - nbars;' 'int start = 0;' || negs=1
negl "baseline run uses the whole prefix instead of the lookback" 'int d2 = H3LBaselineDir(win, t + 1, lookback, left, right, period, nb);' 'int d2 = H3LBaselineDir(win, t + 1, t + 1, left, right, period, nb);' || negs=1
negl "panel budget drops the MOST important line first" 'if(best < 0 || prio[j] < prio[best])' 'if(best < 0 || prio[j] > prio[best])' || negs=1
negl "label slot ignores the rank in the bar" 'return((s % 3) * ln + lane);' 'return(lane);' || negs=1
negl "export key without the bar count" 'IntegerToString(n) + S("|") + IntegerToString((long)rates[0].time)' 'IntegerToString((long)rates[0].time)' || negs=1
negl "export hash ignores the close" '      h = H3LHashStep(h, H3LScaled(rates[i].close, scale));
' '' || negs=1
negl "clear keeps the since-baseline values" '   s.new_total = 0;
   s.changes   = 0;
   s.baselines++;' '   s.baselines++;' || negs=1
negl "wrap drops the continuation indent" 'out[n] = (first ? S("") : S("  ")) + StringSubstr(rest, 0, cut);' 'out[n] = StringSubstr(rest, 0, cut);' || negs=1
[ $negs -eq 0 ] || exit 6
[ $rc -ne 0 ] && exit $rc
exit $rcl
