#!/bin/bash
# T003 evidence: transliterate the MQL5 logic and test script to C++ and RUN them (g++, ASan/UBSan).
# This is NOT MetaEditor and NOT MT5 (see tools/t003_xlate/mql2cpp.py). It shows only that the
# transliterated H4Bias.mqh / H4Structure.mqh agree with the Python model on the controlled cases and
# that the hand-written MQL5 test checks pass in that setting. Compilation in MetaEditor stays UNVERIFIED.
# Usage: bash tools/t003-xlate-check.sh   (exit 0 = transliterated test script passed, failures 0)
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
[ $rcm -ne 0 ] && echo "NEG PASS: the mutated logic fails the transliterated test script (exit $rcm)" || { echo "NEG FAIL: mutation not detected"; exit 6; }
exit $rc
