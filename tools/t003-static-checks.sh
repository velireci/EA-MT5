#!/bin/bash
# Static checks for T003 (tasks/T003-h4-bias-change.md, revision 10 PROPOSAL / PROTOTYPE, awaiting the client).
#
# These are NOT a compiler and NOT a runtime test. They prove only what can be
# read from the source: no trading API / Sleep / clock in the T003 logic and
# test script, balanced syntax, resolvable includes, no MQL4 API, matching
# format strings, ASCII-only source, no global mutable state and no window
# index inside identity builders in H4Bias.mqh, that the case data in
# src/tests/T003_LogicTest.mq5 is exactly what the Python reference model
# emits, that the Python model tests pass, that no existing T001/T002 file was
# modified, and that deferred test groups are never counted as passes.
# Compilation (MetaEditor) and the MT5 test run are still UNVERIFIED.
#
# Reuses tools/t001-check-balance.py (takes file arguments) and
# tools/t001-check-format-strings.py (hardcoded T001 file list: it is loaded
# as a module and its FILES variable is overridden here; the T001 file is not
# modified).
#
# Usage: bash tools/t003-static-checks.sh   (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
HDR=src/include/H4Bias.mqh
TEST=src/tests/T003_LogicTest.mq5
PYT=tests/t003_reference_test.py
FILES="$HDR $TEST"

# trading API (same list as T002)
PAT='OrderSend|OrderSendAsync|OrderClose|OrderModify|OrderDelete|PositionClose|PositionModify|PositionOpen|CTrade|CPositionInfo|COrderInfo|MqlTradeRequest|MqlTradeResult|OrderCalcMargin|OrderCalcProfit|OnTradeTransaction|OnTrade\(|PositionSelect|PositionGet|OrderSelect|OrderGet|HistoryOrder|HistoryDeal|PositionsTotal|OrdersTotal|#include[[:space:]]*<Trade'
# blocking waits, clock and terminal/series access: none of it belongs in pure logic
PATIMPURE='\bSleep\(|\bTimeCurrent\(|\bTimeLocal\(|\bTimeTradeServer\(|\bTimeGMT\(|\bGetTickCount|\bGetMicrosecondCount|\bObject[A-Z][A-Za-z]*\(|\bChart[A-Z][A-Za-z]*\(|\bCopyRates\(|\bCopyTime\(|\bCopyHigh\(|\bCopyLow\(|\bCopyClose\(|\biTime\(|\biHigh\(|\biLow\(|\biClose\(|\biBars\(|\bSymbolInfo[A-Za-z]*\(|\bAccountInfo[A-Za-z]*\(|\bTerminalInfo[A-Za-z]*\(|\bMQLInfo[A-Za-z]*\(|\bFile[A-Z][A-Za-z]*\(|\bGlobalVariable[A-Za-z]*\(|\bEventSet[A-Za-z]*\(|\bWebRequest\(|\bSend[A-Z][A-Za-z]*\('

# strip // comments and /* */ blocks, print what is left
strip_comments() {
  sed -e 's://.*::' "$1" | awk 'BEGIN{b=0} {l=$0; while(match(l,/\/\*/)){b=1; l=substr(l,1,RSTART-1)} if(b&&match($0,/\*\//)){b=0; l=substr($0,RSTART+2)} if(!b)print l}'
}
# scan_trading FILE -> prints offending lines, returns 0 when clean
scan_trading() {
  local out
  out=$(strip_comments "$1" | grep -nE "$PAT")
  if [ -n "$out" ]; then echo "$out"; return 1; fi
  return 0
}
# scan_impure FILE -> prints offending lines, returns 0 when clean
scan_impure() {
  local out
  out=$(strip_comments "$1" | grep -nE "$PATIMPURE")
  if [ -n "$out" ]; then echo "$out"; return 1; fi
  return 0
}

echo "=== CHECK 1: no order/trading API in executable code (comments stripped) ==="
bad1=0
for f in $FILES; do
  out=$(scan_trading "$f") || { echo "  FAIL $f: $out"; FAIL=1; bad1=1; }
done
[ $bad1 -eq 0 ] && echo "  PASS: no order/trading API in H4Bias.mqh or T003_LogicTest.mq5"

echo "=== CHECK 2: brace / parenthesis balance per file ==="
python3 tools/t001-check-balance.py $FILES || FAIL=1

echo "=== CHECK 3: include guard closed, includes resolve ==="
# unresolved_includes FILE -> prints every #include "x" of FILE that does not exist relative to FILE's directory
unresolved_includes() {
  local f="$1" d inc bad=0
  d=$(dirname "$f")
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "    missing include: $d/$inc"; bad=1; }
  done
  return $bad
}
g=$(grep -c '^#ifndef' "$HDR"); e=$(grep -c '^#endif' "$HDR")
[ "$g" = "$e" ] && echo "  PASS $HDR: include guard balanced ($g/$e)" || { echo "  FAIL $HDR: guard $g vs endif $e"; FAIL=1; }
for f in $FILES; do
  out=$(unresolved_includes "$f") && echo "  PASS $f: every include resolves" || { echo "$out"; echo "  FAIL $f: unresolved include"; FAIL=1; }
  [ "$(grep -c '#include "' "$f")" -ge 1 ] || { echo "  FAIL $f: no include found (vacuous check)"; FAIL=1; }
done

echo "=== CHECK 4: MQL4-only APIs must be absent ==="
PAT4='\bOrdersTotal\(\)|\biBars\(|\bAccountBalance\(|\bMarketInfo\(|\bOrderType\(\)|\bSymbol\(\)|\bBid\b|\bAsk\b|\bPoint\b[^(]|\bDigits\b[^(]|\bstart\(\)|\binit\(\)|\bdeinit\(\)'
bad4=0
for f in $FILES; do
  out=$(strip_comments "$f" | grep -nE "$PAT4")
  if [ -n "$out" ]; then echo "  FAIL $f: $out"; bad4=1; FAIL=1; fi
done
[ $bad4 -eq 0 ] && echo "  PASS: no MQL4-style API used"
grep -qE "^void OnStart\(" $TEST && echo "  PASS $TEST OnStart defined (script)" || { echo "  FAIL OnStart missing in test"; FAIL=1; }

echo "=== CHECK 5: StringFormat/PrintFormat specifiers match argument count ==="
python3 - $FILES <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF

echo "=== CHECK 6: source must stay pure ASCII ==="
for f in $FILES $PYT tools/t003-static-checks.sh; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  if [ "$n" != "0" ]; then
    echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1
  else
    echo "  PASS $f: ASCII only"
  fi
done

echo "=== CHECK 7: pure logic (no Sleep, clock, chart/object/series/terminal access) ==="
bad7=0
for f in $FILES; do
  out=$(scan_impure "$f") || { echo "  FAIL $f is not pure: $out"; FAIL=1; bad7=1; }
done
[ $bad7 -eq 0 ] && echo "  PASS: H4Bias.mqh and T003_LogicTest.mq5 use no Sleep, clock, object, chart or series access"

echo "=== CHECK 8: no global mutable state in H4Bias.mqh (stateless rebuild) ==="
# a global variable declaration starts in column 0 with a type and ends in = or ;
# (functions have a parenthesis after the name; #define and struct are not variables)
glob_vars() { strip_comments "$1" | grep -nE '^(static[[:space:]]+)?(const[[:space:]]+)?(int|uint|long|ulong|double|float|string|bool|datetime|color|char|uchar|short|ushort)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?[[:space:]]*(=|;)'; }
out=$(glob_vars $HDR)
if [ -n "$out" ]; then echo "  FAIL global variable(s) in $HDR: $out"; FAIL=1; else echo "  PASS: $HDR declares no global variable (every function works on its arguments)"; fi
out=$(strip_comments $HDR | grep -nE '\bstatic\b')
if [ -n "$out" ]; then echo "  FAIL static storage in $HDR: $out"; FAIL=1; else echo "  PASS: no 'static' storage in $HDR"; fi

echo "=== CHECK 9: identity builders use absolute times only, never a window index ==="
# fn_body FILE PREFIX -> stripped source of the function whose DEFINITION line starts with the literal
# text PREFIX. The prefix is matched with index() and handed over through the environment (no regex
# crosses awk -v). Definitions end with a line of exactly two spaces and a closing brace.
fn_body() { strip_comments "$1" | FN_PREFIX="$2" awk 'index($0, ENVIRON["FN_PREFIX"]) == 1 && $0 !~ /;[ \t]*$/ {p=1} p{print} p&&/^  }$/{exit}'; }
# check_ids FILE -> prints violations, returns 0 when intact
check_ids() {
  local f="$1" bad=0 fn b sig
  for fn in 'string H3LevelId(' 'string H3ExtId(' 'string H3InteriorId(' 'string H3EventId(' 'string H3EventText('; do
    b=$(fn_body "$f" "$fn")
    [ -n "$b" ] || { echo "    function body not found: $fn"; bad=1; continue; }
    sig=$(echo "$b" | sed -n '1p')
    echo "$sig" | grep -qiE '\b(idx|index|pos|bar_index|window)\b' && { echo "    window index parameter in: $sig"; bad=1; }
    echo "$b" | sed '1d' | grep -qE '\bidx\b|\bindex\b|\.idx\b|\.index\b|\.f\b|\[' && { echo "    window index or array subscript inside: $fn"; bad=1; }
  done
  # the time based builders must use the T002 absolute time stamp helper
  for fn in 'string H3LevelId(' 'string H3ExtId(' 'string H3InteriorId(' 'string H3EventId('; do
    fn_body "$f" "$fn" | grep -q 'H4TimeStamp(' || { echo "    $fn does not build from H4TimeStamp"; bad=1; }
  done
  return $bad
}
out=$(check_ids $HDR) && echo "  PASS: level, extreme, interior and event IDs are built from H4TimeStamp of pivot/bar times; no index in signature or body" || { echo "$out"; echo "  FAIL identity builders"; FAIL=1; }
# the generated expected transcripts must not carry bar counts either: IDs in the data block are 12-digit stamps
n_bad=$(awk '/^\/\/ BEGIN GENERATED CASE DATA/{p=1} p' $TEST | grep -oE '(SH|SL|HH|LL|IH|IL)[0-9]+_' | grep -vE '^(SH|SL|HH|LL|IH|IL)[0-9]{12}_$' | wc -l)
[ "$n_bad" = "0" ] && echo "  PASS: every level/extreme/interior id in the expected transcripts starts with a 12-digit time stamp" || { echo "  FAIL: $n_bad id(s) in the data block are not 12-digit time stamps"; FAIL=1; }

echo "=== CHECK 10: generated case data in the MQL5 test matches the Python model ==="
python3 $PYT --emit-mql > "$TMPD/emit" 2>/dev/null
awk '/^\/\/ BEGIN GENERATED CASE DATA/{p=1} p{print} /^\/\/ END GENERATED CASE DATA/{p=0}' $TEST > "$TMPD/have"
# Windows Python emits CRLF, the source block is LF: normalise both sides.
tr -d '\r' < "$TMPD/emit" > "$TMPD/emit.n"; tr -d '\r' < "$TMPD/have" > "$TMPD/have.n"
if [ -s "$TMPD/emit.n" ] && cmp -s "$TMPD/emit.n" "$TMPD/have.n"; then
  echo "  PASS: generated block in $TEST equals --emit-mql output"
else
  echo "  FAIL: generated block in $TEST differs from $PYT --emit-mql"; FAIL=1
fi
cc=$(grep -c '^      case [0-9]*:' "$TMPD/have.n"); decl=$(grep -oE '#define T3_CASE_COUNT [0-9]+' "$TMPD/have.n" | awk '{print $3}')
[ "$cc" = "$decl" ] && [ "$cc" -gt 0 ] && echo "  PASS: T3_CASE_COUNT ($decl) equals the number of generated cases" || { echo "  FAIL: T3_CASE_COUNT $decl vs $cc cases"; FAIL=1; }

echo "=== CHECK 11: Python reference model tests (verify the MODEL only) ==="
python3 $PYT > "$TMPD/py" 2>&1; rc=$?
if [ $rc -eq 0 ]; then echo "  PASS: $(grep -E '^[0-9]+ passed' "$TMPD/py")"; else tail -5 "$TMPD/py"; echo "  FAIL: reference tests"; FAIL=1; fi
nd=$(grep -c 'DEFERRED (not implemented in this round)' "$TMPD/py")
[ "$nd" -ge 5 ] && echo "  PASS: the Python run prints $nd explicit DEFERRED lines (never counted as PASS)" || { echo "  FAIL: expected at least 5 DEFERRED lines in the Python run, found $nd"; FAIL=1; }
grep -q 'DEFERRED.*PASS' "$TMPD/py" && { echo "  FAIL: a DEFERRED line contains PASS"; FAIL=1; }
# the MQL5 Deferred() helper must not touch the pass counter
db=$(fn_body $TEST 'void Deferred(')
if [ -n "$db" ] && ! echo "$db" | grep -q 'g_pass' && echo "$db" | grep -q 'DEFERRED (not implemented in this round)'; then
  echo "  PASS: MQL5 Deferred() prints DEFERRED and never increments g_pass"
else
  echo "  FAIL: MQL5 Deferred() missing, or it touches g_pass"; FAIL=1
fi
nm=$(strip_comments $TEST | grep -c 'Deferred("')
[ "$nm" -ge 5 ] && echo "  PASS: the MQL5 test lists $nm deferred groups" || { echo "  FAIL: fewer than 5 deferred groups in the MQL5 test"; FAIL=1; }

echo "=== CHECK 12: no existing T001/T002 (or other pre-existing) file was modified ==="
# check_unmodified REPO FILES... -> returns 0 when none of the files differ from HEAD
check_unmodified() {
  local repo="$1"; shift
  git -C "$repo" diff --quiet HEAD -- "$@" 2>/dev/null
}
# The T003-owned files are legitimately edited in the working tree before they are committed
# (the T003 code files, the visual EA and its tools, the replay tools, the T003 task/report/doc, the hand-updated STATE). Every OTHER tracked file
# must be identical to HEAD; the base-commit comparison below covers all code paths of T001/T002.
T003_OWNED='^(src/include/H4Bias\.mqh|src/tests/T003_LogicTest\.mq5|tests/t003_reference_test\.py|tests/t003_replay_csv\.py|tests/t003_explore_synthetic\.py|tools/t003-static-checks\.sh|tools/t003-xlate-check\.sh|tools/t003_xlate/[A-Za-z0-9_.]+|tools/t003-visual-static-checks\.sh|tools/t003-visual-check\.py|src/XauUsdH4Bias\.mq5|src/include/H4BiasDrawer\.mqh|src/include/H4BiasLayers\.mqh|src/tests/T003_LayersTest\.mq5|docs/T003-visual-ea\.md|tasks/T003-h4-bias-change\.md|reports/T003-verification\.md|docs/STATE\.md|reports/t003-liq-prototype/[A-Za-z0-9_.]+)$'
EXISTING=$(git ls-files | grep -vE "$T003_OWNED")
tracked_new=0
if check_unmodified . $EXISTING; then
  echo "  PASS: every tracked file except the T003-owned ones (code, task, report, STATE) is identical to HEAD (git diff --quiet HEAD)"
else
  echo "  FAIL: a tracked file other than the T003-owned ones differs from HEAD:"; git diff --stat HEAD -- $EXISTING | tail -5; FAIL=1
fi
if git cat-file -e dd571f6 2>/dev/null; then
  if git diff --quiet dd571f6 -- $(git ls-tree -r --name-only dd571f6 -- src tools tests) 2>/dev/null; then
    echo "  PASS: every code file (src, tools, tests) that exists at base commit dd571f6 is identical to it (working tree); docs, reports and tasks are excluded because they are updated by hand"
  else
    echo "  FAIL: a code file (src, tools, tests) of base commit dd571f6 differs in the working tree"; git diff --stat dd571f6 | tail -5; FAIL=1
  fi
else
  echo "  INFO: base commit dd571f6 not available here; the parent must verify against it"
fi
echo "  INFO: new (untracked) files: $(git ls-files --others --exclude-standard | tr '\n' ' ')"
echo "  INFO: the parent still verifies the final change set against the base commit"

echo "=== CHECK 12b: FINDING 1 and FINDING 2 are present in the MQL5 logic (static reading, not a test) ==="
# anchor: located by existing bars (index search + Left bars before it), never by time arithmetic
anchor_ok() {
  local f="$1" b
  b=$(fn_body "$f" 'datetime H3AnchorTime(')
  [ -n "$b" ] || { echo "    H3AnchorTime body not found"; return 1; }
  echo "$b" | grep -q 'H3BarIndexByTime(' || { echo "    H3AnchorTime does not locate the reference in the series"; return 1; }
  echo "$b" | grep -q 'bars\[ix - p.left\]\.time' || { echo "    H3AnchorTime does not take the Left existing bars before the reference"; return 1; }
  echo "$b" | grep -qE 'period' && { echo "    H3AnchorTime uses period arithmetic"; return 1; }
  strip_comments "$f" | grep -q 'H3AnchorTime(repA.st, p, bars_all, n_avail, ev.anchor_missing)' || { echo "    H3Evaluate does not pass the bar series to H3AnchorTime"; return 1; }
  strip_comments "$f" | grep -q 'ANCHOR_HISTORY_MISSING' || { echo "    no ANCHOR_HISTORY_MISSING reason"; return 1; }
  return 0
}
out=$(anchor_ok $HDR) && echo "  PASS: H3AnchorTime searches the reference by absolute time in the series, uses the Left existing bars before it, has no period arithmetic; H3Evaluate passes the series; missing history has its own reason" || { echo "$out"; echo "  FAIL: FINDING 1 pattern"; FAIL=1; }
# revision 10 (PROPOSAL / PROTOTYPE): nothing is frozen or thawed; the structure updates in every phase through the
# ratchet; RECONF_LOST keeps the setup; SETUP_ENDED has only the reasons INVALIDATED_BY_FLIP and REPLACED
structure_ok() {
  local f="$1" b pb ab bb db
  b=$(fn_body "$f" 'void H3FvgStep(')
  [ -n "$b" ] || { echo "    H3FvgStep body not found"; return 1; }
  echo "$b" | grep -qE 'st\.frozen +=' && { echo "    H3FvgStep still writes st.frozen (the freeze/thaw of revisions 6-7 was removed in revision 10)"; return 1; }
  echo "$b" | grep -qE 'skip_derive' && { echo "    a derive step is skipped"; return 1; }
  echo "$b" | grep -qE 'H3ClearSetup\(|st\.setup_id +=|H3SetupEnded\(|H3_EV_SETUP_ENDED' && { echo "    H3FvgStep ends or clears the setup (RECONF_LOST must keep it)"; return 1; }
  echo "$b" | grep -qE 'st\.rec_id += +S?""|st\.rec_id += +""' || { echo "    RECONF_LOST does not clear rec_id"; return 1; }
  echo "$b" | grep -qE 'if\(st\.phase == H3_PH_SWEEP_WAIT && !st\.has_level\)' || { echo "    the defensive no-level guard of a touch is missing"; return 1; }
  pb=$(fn_body "$f" 'void H3ProcessBar(')
  echo "$pb" | grep -q 'H3FvgStep(' || { echo "    H3ProcessBar does not call H3FvgStep"; return 1; }
  echo "$pb" | grep -q 'return;' && { echo "    H3ProcessBar returns before the derive step"; return 1; }
  db=$(fn_body "$f" 'void H3DeriveStep(')
  [ -n "$db" ] || { echo "    H3DeriveStep body not found"; return 1; }
  echo "$db" | grep -q 'st\.frozen' && { echo "    H3DeriveStep reads st.frozen (the structure must run in every phase)"; return 1; }
  echo "$db" | grep -q 'H3AcceptCandidate(' || { echo "    H3DeriveStep does not use the ratchet acceptance"; return 1; }
  ab=$(fn_body "$f" 'bool H3AcceptCandidate(')
  [ -n "$ab" ] || { echo "    H3AcceptCandidate body not found"; return 1; }
  echo "$ab" | grep -q 'lvl.ext_time > st.lv_ext' || { echo "    ratchet (ii) missing: the extreme pivot must be later than the current level's"; return 1; }
  echo "$ab" | grep -q 's \* lvl.price < s \* st.lv_price' || { echo "    ratchet (iii) missing: the candidate must be strictly more advanced"; return 1; }
  echo "$ab" | grep -q 'body' || { echo "    ratchet (iv) missing: a candidate crossed by a close must be rejected"; return 1; }
  bb=$(fn_body "$f" 'bool H3BiasStep(')
  [ -n "$bb" ] || { echo "    H3BiasStep body not found"; return 1; }
  echo "$bb" | grep -qE 'ph != H3_PH_ACTIVE && ph != H3_PH_SWEEP_WAIT' && { echo "    H3BiasStep returns early outside ACTIVE/SWEEP_WAIT (observation events must run in every phase)"; return 1; }
  [ "$(echo "$bb" | grep -vE 'st\.snap_price +=' | grep -o 'snap_price' | wc -l)" = "2" ] || { echo "    the snapshot price is read outside the SNAPSHOT_CROSSED diagnostic (it is a reference only)"; return 1; }
  echo "$bb" | grep -q 'H3_EV_SNAP_CROSSED' || { echo "    SNAPSHOT_CROSSED diagnostic missing"; return 1; }
  echo "$bb" | tr '\n' ' ' | grep -qE 'H3AddEvent\(events, ne, H3_EV_SNAP_CROSSED.*st\.lv_id, ""\);' || { echo "    SNAPSHOT_CROSSED must have an empty comparison signature (not compared by A/B)"; return 1; }
  fn_body "$f" 'void H3DoFlip(' | grep -q 'INVALIDATED_BY_FLIP' || { echo "    a flip does not end the setup with INVALIDATED_BY_FLIP"; return 1; }
  fn_body "$f" 'void H3StartHold(' | grep -q 'H3SetupEnded(st, bars\[t\].time, S\?"REPLACED"\|H3SetupEnded(st, bars\[t\].time, "REPLACED"' || { echo "    a new setup does not end the previous one with REPLACED"; return 1; }
  strip_comments "$f" | grep -nE 'SUPERSEDED_BY_STRUCTURE|M15_OUTCOME' && { echo "    SUPERSEDED_BY_STRUCTURE / M15_OUTCOME must not be implemented in this round"; return 1; }
  strip_comments "$f" | grep -niE 'expir|max_age|bar_count_limit|age_bars' && { echo "    an expiry / age limit exists (no arbitrary expiry is allowed)"; return 1; }
  [ "$(strip_comments "$f" | grep -oE '"(INVALIDATED_BY_FLIP|REPLACED)"|reason=[A-Z_]+' | sort -u | tr '\n' ' ')" = '"REPLACED" reason=INVALIDATED_BY_FLIP ' ] || { echo "    SETUP_ENDED reasons other than INVALIDATED_BY_FLIP / REPLACED: $(strip_comments "$f" | grep -oE '"(INVALIDATED_BY_FLIP|REPLACED)"|reason=[A-Z_]+' | sort -u | tr '\n' ' ')"; return 1; }
  return 0
}
out=$(structure_ok $HDR) && echo "  PASS: revision 10 structure present: no freeze/thaw, ratchet (ii)-(iv) in H3AcceptCandidate, H3DeriveStep runs in every phase, observation events in every phase, snapshot used only by the diagnostic SNAPSHOT_CROSSED (empty signature), RECONF_LOST keeps the setup, flip ends it (INVALIDATED_BY_FLIP), new setup REPLACES the old, no SUPERSEDED/M15_OUTCOME, no expiry" || { echo "$out"; echo "  FAIL: revision 10 structure pattern"; FAIL=1; }
echo "=== CHECK 12c: revision 14 internal-liquidity layer pattern (PROPOSAL / PROTOTYPE; static reading, not a test) ==="
# the per-level layer: strict crossing, historical consumption from the first usable bar, scope bounded by the CURRENT level's pivot,
# observation only (never writes the bias / level), raised only for a bar that is not structural, the LI key element is the set
liq_ok() {
  local f="$1" b
  strip_comments "$f" | grep -qE 'has_li\b|SH3Cand +[a-z, ]*lint|, *lint\)' && { echo "    the single-candidate interior output (has_li / lint) is still present"; return 1; }
  b=$(fn_body "$f" 'int H3LiqFirstCross(')
  [ -n "$b" ] || { echo "    H3LiqFirstCross body not found"; return 1; }
  echo "$b" | grep -qE 'H3AdverseExt\(bars\[j\], s\) - sw\[i\]\.price\) > 0\)' || { echo "    H3LiqFirstCross: the crossing test is not the STRICT 'adverse extreme beyond the swing > 0'"; return 1; }
  echo "$b" | grep -qE '>= *0\)' && { echo "    H3LiqFirstCross: a non-strict comparison (a touch would consume)"; return 1; }
  echo "$b" | grep -q 'lc.scanned\[i\] + 1' || { echo "    H3LiqFirstCross does not continue from the first unscanned bar"; return 1; }
  b=$(fn_body "$f" 'void H3LiqCacheInit(')
  [ -n "$b" ] || { echo "    H3LiqCacheInit body not found"; return 1; }
  echo "$b" | grep -q 'lc.scanned\[i\] = sw\[i\].index + right;' || { echo "    the first usable bar of a swing is not pivot + right + 1"; return 1; }
  b=$(fn_body "$f" 'int H3LiqScope(')
  [ -n "$b" ] || { echo "    H3LiqScope body not found"; return 1; }
  echo "$b" | grep -q 'sw\[i\].pivot_time <= st.lv_pivot' || { echo "    H3LiqScope: the scope is not bounded by the pivot of the CURRENT protecting level"; return 1; }
  echo "$b" | grep -q 's \* (sw\[i\].price - st.lv_price) < 0' || { echo "    H3LiqScope: the price must be strictly inside the protecting level"; return 1; }
  echo "$b" | grep -q 'H3LiqFirstCross(' || { echo "    H3LiqScope does not apply the consumption history"; return 1; }
  b=$(fn_body "$f" 'void H3LiqInternalEvents(')
  [ -n "$b" ] || { echo "    H3LiqInternalEvents body not found"; return 1; }
  echo "$b" | grep -q 'H3KnownCount(sw, ns, p.right, t - 1)' || { echo "    H3LiqInternalEvents: the scope of bar t must use the swings confirmed by the close of t-1"; return 1; }
  echo "$b" | grep -q 'H3LiqScope(bars, sw, nk, st, s, t - 1, lc, scope)' || { echo "    H3LiqInternalEvents: consumption must be judged up to t-1 (bar t is the crossing candidate)"; return 1; }
  echo "$b" | grep -qE 'if\(ph == H3_PH_ACTIVE \|\| ph == H3_PH_SWEEP_WAIT\)' || { echo "    H3LiqInternalEvents: a setup is created only from ACTIVE or SWEEP_WAIT"; return 1; }
  echo "$b" | grep -qE 'bars\[t\]\.close - sw\[i\]\.price\) > 0' || { echo "    H3LiqInternalEvents: a break needs a close STRICTLY beyond the level"; return 1; }
  echo "$b" | grep -qE 'st\.(dir|has_level|lv_[a-z]+|bias_start|origin) *=[^=]' && { echo "    H3LiqInternalEvents writes the bias or the protecting level (the layer is observation only)"; return 1; }
  echo "$b" | grep -qE 'H3DoFlip\(|H3StartHold\(' && { echo "    H3LiqInternalEvents flips or starts a structural setup"; return 1; }
  b=$(fn_body "$f" 'bool H3BiasStep(')
  echo "$b" | grep -q 'H3LiqInternalEvents(' || { echo "    H3BiasStep does not raise the internal events"; return 1; }
  [ "$(echo "$b" | grep -n 'H3LiqInternalEvents(' | head -1 | cut -d: -f1)" -gt "$(echo "$b" | grep -n 'H3StartHold(' | head -1 | cut -d: -f1)" ] || { echo "    the internal events are raised before the structural wick/flip handling (the structural priority is lost)"; return 1; }
  b=$(fn_body "$f" 'string H3StructKey(')
  echo "$b" | grep -q 'st.li_key' || { echo "    the structure key does not carry the set of unconsumed internal levels (li_key)"; return 1; }
  b=$(fn_body "$f" 'void H3LiqUpdate(')
  [ -n "$b" ] || { echo "    H3LiqUpdate body not found"; return 1; }
  echo "$b" | grep -q 'H3KnownCount(sw, ns, p.right, t)' || { echo "    H3LiqUpdate: the next-bar set uses the swings confirmed by the close of t"; return 1; }
  return 0
}
out=$(liq_ok $HDR) && echo "  PASS: revision 14 layer present: strict crossing, historical consumption from pivot+right+1, scope bounded by the CURRENT level's pivot and price, setups only from ACTIVE/SWEEP_WAIT, observation only, after the structural handling, LI key = li_key" || { echo "$out"; echo "  FAIL: revision 14 layer pattern"; FAIL=1; }
neg_liq() { # neg_liq LABEL SED_EXPR SUBSTRING : the layer checker must detect each of its own patterns being broken
  local label="$1" expr="$2" sub="$3" o
  sed "$expr" "$NEG/h.mqh" > "$NEG/lq.mqh"
  if cmp -s "$NEG/lq.mqh" "$NEG/h.mqh"; then echo "  FAIL 13s ($label): the mutation did not change the header (vacuous)"; FAIL=1; return; fi
  o=$(liq_ok "$NEG/lq.mqh") && { echo "  FAIL 13s ($label): NOT detected"; FAIL=1; return; }
  echo "$o" | grep -qF -- "$sub" && echo "  PASS 13s ($label): detected (intended reason: $sub)" || { echo "  FAIL 13s ($label): other reason: $o"; FAIL=1; }
}
LIQNEG=1

# Revision 14 (internal liquidity layer, PROPOSAL / PROTOTYPE): the T003 LOGIC files (H4Bias.mqh, the Python model, T003_LogicTest.mq5)
# are CHANGED on purpose in this round, so they are no longer compared with the prototype 2837527. What must stay identical: the T002
# structure header reused by the logic, and (CHECK 12) every T001/T002 file. The revision 14 change is guarded by CHECK 15 (pattern),
# CHECK 10/11 (transcripts, Python model) and the transliteration run.
LOGIC_BASE=2837527
NEW_BASE=d7a201f
for b0 in $LOGIC_BASE $NEW_BASE; do
  if git cat-file -e "$b0^{commit}" 2>/dev/null; then
    git diff --quiet "$b0" -- src/include/H4Structure.mqh tests/t002_reference_test.py 2>/dev/null && echo "  PASS: src/include/H4Structure.mqh and tests/t002_reference_test.py are byte-identical to $b0 (the T002 structure code is reused unchanged)" || { echo "  FAIL: H4Structure.mqh / t002_reference_test.py differ from $b0"; FAIL=1; }
  else
    echo "  INFO: base $b0 not available here; the parent must verify that the T002 structure files are unchanged"
  fi
done
echo "  INFO: src/include/H4Bias.mqh, tests/t003_reference_test.py and src/tests/T003_LogicTest.mq5 are the revision 14 logic (changed on purpose; no longer compared with $LOGIC_BASE)"

echo "=== CHECK 14: diagnostics, candle export text and the TrackChanges decision are read-only / behaviour neutral (static reading) ==="
# (a) H3Diagnose takes the evaluation as const and never calls the evaluation itself
diag_ro_ok() {
  local f="$1" b
  b=$(fn_body "$f" 'void H3Diagnose(')
  [ -n "$b" ] || { echo "    H3Diagnose body not found"; return 1; }
  strip_comments "$f" | grep -q 'void H3Diagnose(const MqlRates &bars_all\[\], const int n_avail, const SH3Params &p, const SH3Eval &ev, SH3Diag &d)' || { echo "    H3Diagnose does not take the evaluation as const SH3Eval &ev"; return 1; }
  echo "$b" | grep -qE '\bH3Evaluate(Latest)?\(' && { echo "    H3Diagnose calls the evaluation (it must only explain it)"; return 1; }
  echo "$b" | grep -qE '\bev\.[A-Za-z_]+ *=[^=]' && { echo "    H3Diagnose writes to the evaluation"; return 1; }
  return 0
}
out=$(diag_ro_ok $HDR) && echo "  PASS: H3Diagnose takes 'const SH3Eval &ev', does not call H3Evaluate and writes nothing into ev" || { echo "$out"; echo "  FAIL diagnostics read-only pattern"; FAIL=1; }
# (b) the diagnostic counters of a replay are not part of the state key / state text
key_ok() {
  local f="$1" fn b
  for fn in 'string H3StateKey(' 'string H3StructKey(' 'string H3SetupKey(' 'string H3ProvKey(' 'string H3StateText(' 'string H3EventsText(' 'string H3EventsSigText(' 'string H3EvalText('; do
    b=$(fn_body "$f" "$fn")
    [ -n "$b" ] || { echo "    body not found: $fn"; return 1; }
    echo "$b" | grep -qE 'nolv_|n_flips|last_flip|flips_after_run' && { echo "    $fn uses a diagnostic counter"; return 1; }
  done
  return 0
}
out=$(key_ok $HDR) && echo "  PASS: the state key, state text, events text and evaluation text do not use the diagnostic counters (the A/B comparison cannot change)" || { echo "$out"; echo "  FAIL key purity"; FAIL=1; }
# (c) REPLACED in revision 10: the old check required H4Bias.mqh to have only GROWN against the revision-7 logic
# (62a0747). Revision 10 changes the logic ON PURPOSE (no freeze, ratchet, setup layer, A/B by function); that
# change is guarded by structure_ok (CHECK 12b), the transcripts (CHECK 10) and the Python/C++ runs instead.
removed_ok() { # kept only as the checker used by the negative control 14d: the diagnostics helpers must not change the replay
  local f="$1"
  fn_body "$f" 'void H3ProcessBar(' | grep -q 'H3DeriveStep(' || { echo "    H3ProcessBar does not run the derive step (changed or removed line)"; return 1; }
  fn_body "$f" 'void H3ProcessBar(' | grep -q 'H3LiqUpdate(' || { echo "    H3ProcessBar does not run the internal-liquidity update (revision 14)"; return 1; }
  return 0
}
out=$(removed_ok $HDR) && echo "  PASS: H3ProcessBar still runs bias, FVG and derive steps in the documented order (the revision-7 'only grew' rule was replaced, see the comment)" || { echo "$out"; echo "  FAIL process order"; FAIL=1; }
# (d) the TrackChanges decision reports only for a consumer status OK
tc_ok() {
  local f="$1" b
  b=$(fn_body "$f" 'int H3TrackChangesMode(')
  [ -n "$b" ] || { echo "    H3TrackChangesMode body not found"; return 1; }
  echo "$b" | grep -q 'consume_status == H3_C_OK' || { echo "    the decision does not test the consumer status OK"; return 1; }
  [ "$(echo "$b" | grep -c 'return(H3_TC_REPORT)')" = "1" ] || { echo "    H3_TC_REPORT is returned more than once"; return 1; }
  echo "$b" | grep -B1 'return(H3_TC_REPORT)' | grep -qxE '   if\(consume_status == H3_C_OK\)' || { echo "    H3_TC_REPORT is not guarded by exactly the OK status"; return 1; }
  return 0
}
out=$(tc_ok $HDR) && echo "  PASS: H3TrackChangesMode returns H3_TC_REPORT only for the consumer status OK" || { echo "$out"; echo "  FAIL TrackChanges decision"; FAIL=1; }
# (e) export text helpers exist and are pure text (CHECK 7 already bans File*/Terminal*/SymbolInfo* in the whole header)
for fn in 'string H3CsvName(' 'string H3CsvHeader(' 'string H3CsvRow(' 'string H3CsvSafeSymbol('; do
  fn_body $HDR "$fn" | grep -q . && echo "  PASS: $fn found (pure text building)" || { echo "  FAIL: $fn missing"; FAIL=1; }
done
# negative controls for CHECK 14 (each mutation must change the header, and the matching checker must fail for the intended reason)
N14=$(mktemp -d)
# mut14 OLD NEW DST : DST = $HDR with the first exact OLD replaced; returns 1 (vacuous) if OLD is absent
mut14() {
  python3 -I - "$HDR" "$3" "$1" "$2" <<'PYEOF'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding='ascii').read()
if old not in t:
    sys.exit(3)
open(dst, 'w', encoding='ascii').write(t.replace(old, new, 1))
PYEOF
}
neg14() { # neg14 LABEL OLD NEW CHECKFN SUBSTRING
  local label="$1" old="$2" new="$3" fn="$4" sub="$5" o
  if ! mut14 "$old" "$new" "$N14/m.mqh"; then echo "  FAIL $label: the mutation target text is absent (vacuous control)"; FAIL=1; return; fi
  o=$($fn "$N14/m.mqh") && { echo "  FAIL $label: NOT detected"; FAIL=1; return; }
  echo "$o" | grep -qF -- "$sub" && echo "  PASS $label (detected: $sub)" || { echo "  FAIL $label: failed for another reason: $o"; FAIL=1; }
}
neg14 "14a H3Diagnose calls H3Evaluate" '   H3Replay(winA, ev.r_eff, p, repA, trA, evA, keysA, true);' '   H3Replay(winA, ev.r_eff, p, repA, trA, evA, keysA, true); SH3Eval zz; H3Evaluate(bars_all, n_avail, p, zz, trA, evA);' diag_ro_ok 'calls the evaluation'
neg14 "14b H3Diagnose takes a non-const evaluation" 'const SH3Params &p, const SH3Eval &ev, SH3Diag &d)' 'const SH3Params &p, SH3Eval &ev, SH3Diag &d)' diag_ro_ok 'const SH3Eval &ev'
neg14 "14c a diagnostic counter inside the structure key" '   return("BIAS=" + H3DirName(st.dir) + ";LV=" + lv' '   string nolv_dummy = ""; return("BIAS=" + H3DirName(st.dir) + ";LV=" + lv' key_ok 'uses a diagnostic counter'
neg14 "14d the derive step removed from the bar order" '   H3DeriveStep(t, bars, sw, ns, p, fv, nf, st, tracks, nt, events, ne);
   H3LiqUpdate(' '   H3LiqUpdate(' removed_ok 'derive step'
neg14 "14g the internal-liquidity update removed from the bar order" '   H3LiqUpdate(t, bars, sw, ns, p, st, lc);' '   ' removed_ok 'internal-liquidity update'
neg14 "14e a widened report condition" '   if(consume_status == H3_C_OK)
      return(H3_TC_REPORT);' '   if(consume_status == H3_C_OK || consume_status == H3_C_GAP)
      return(H3_TC_REPORT);' tc_ok 'not guarded'
neg14 "14f an unconditional report" '   if(consume_status == H3_C_OK)
      return(H3_TC_REPORT);
   return(H3_TC_REDERIVE);' '   return(H3_TC_REPORT);' tc_ok 'does not test the consumer status'
rm -rf "$N14"

echo "=== CHECK 13: negative controls (every checker must actually detect its problem, for the intended reason) ==="
NEG=$(mktemp -d)
cp $HDR "$NEG/h.mqh"
# 13a: injected trading API
printf 'void F(){ MqlTradeRequest r; OrderSend(r, res); }\n' > "$NEG/a.mqh"
out=$(scan_trading "$NEG/a.mqh") && { echo "  FAIL 13a: injected OrderSend was NOT detected"; FAIL=1; } || { echo "$out" | grep -q 'OrderSend' && echo "  PASS 13a: injected OrderSend / MqlTradeRequest detected (reason: trading API)" || { echo "  FAIL 13a: failed for another reason: $out"; FAIL=1; }; }
# 13b: the same words inside comments must NOT be flagged
printf '// OrderSend and Sleep( are forbidden\n/* CTrade\n   PositionClose TimeCurrent() */\nvoid F(){}\n' > "$NEG/b.mqh"
scan_trading "$NEG/b.mqh" >/dev/null && scan_impure "$NEG/b.mqh" >/dev/null && echo "  PASS 13b: trading/clock words in comments are ignored" || { echo "  FAIL 13b: comment-only mention flagged"; FAIL=1; }
# 13c: Sleep, clock and series access in executable code
for snippet in 'void F(){ Sleep(10); }' 'datetime F(){ return(TimeCurrent()); }' 'void F(){ MqlRates r[]; CopyRates(_Symbol, PERIOD_H4, 0, 5, r); }' 'void F(){ ObjectCreate(0, "x", OBJ_LABEL, 0, 0, 0); }' 'double F(){ return(iClose(_Symbol, PERIOD_H4, 1)); }'; do
  printf '%s\n' "$snippet" > "$NEG/c.mqh"
  out=$(scan_impure "$NEG/c.mqh") && { echo "  FAIL 13c: impure construct not detected: $snippet"; FAIL=1; } || echo "  PASS 13c: detected as impure: $snippet"
done
# 13d: balance checker must fail on an unbalanced file
printf 'void F(){ if(a { }\n' > "$NEG/d.mqh"
python3 tools/t001-check-balance.py "$NEG/d.mqh" >/dev/null && { echo "  FAIL 13d: unbalanced file passed"; FAIL=1; } || echo "  PASS 13d: unbalanced parentheses detected"
# 13e: format checker must fail on a specifier/argument mismatch
printf 'void F(){ string s = StringFormat("%%d %%s", 1); }\n' > "$NEG/e.mqh"
python3 - "$NEG/e.mqh" <<'PYEOF' >/dev/null
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
[ $? -ne 0 ] && echo "  PASS 13e: format-string mismatch detected" || { echo "  FAIL 13e: mismatch not detected"; FAIL=1; }
# 13f: the case-data comparison must fail when the generated block is altered
sed 's/FLAG=CONVERGED/FLAG=SEEDED/' $TEST | awk '/^\/\/ BEGIN GENERATED CASE DATA/{p=1} p{print} /^\/\/ END GENERATED CASE DATA/{p=0}' > "$NEG/have.txt"
python3 $PYT --emit-mql | tr -d '\r' > "$NEG/emit.txt"
tr -d '\r' < "$NEG/have.txt" > "$NEG/have.n"
cmp -s "$NEG/have.n" "$NEG/emit.txt" && { echo "  FAIL 13f: altered data block not detected"; FAIL=1; } || echo "  PASS 13f: altered generated data detected"
# 13g: a CRLF-converted copy of the (unaltered) block must compare equal after normalisation
awk '/^\/\/ BEGIN GENERATED CASE DATA/{p=1} p{print} /^\/\/ END GENERATED CASE DATA/{p=0}' $TEST | sed 's/$/\r/' > "$NEG/crlf.txt"
cmp -s "$NEG/crlf.txt" "$NEG/emit.txt" && { echo "  FAIL 13g: raw CRLF copy unexpectedly equal (test is vacuous)"; FAIL=1; }
tr -d '\r' < "$NEG/crlf.txt" > "$NEG/crlf.n"
cmp -s "$NEG/crlf.n" "$NEG/emit.txt" && echo "  PASS 13g: CRLF copy of the block equals --emit-mql after line-ending normalisation" || { echo "  FAIL 13g: CRLF copy differs after normalisation"; FAIL=1; }
# 13h: global mutable state must be detected
cp "$NEG/h.mqh" "$NEG/h2.mqh"; printf 'int g_cache = 0;\nstring g_last;\n' >> "$NEG/h2.mqh"
out=$(glob_vars "$NEG/h2.mqh"); echo "$out" | grep -q 'g_cache' && echo "$out" | grep -q 'g_last' && echo "  PASS 13h: injected global variables detected (reason: global state)" || { echo "  FAIL 13h: global variables not detected: $out"; FAIL=1; }
# 13i: a window index in an identity builder must be detected, for the intended reason
sed 's/string H3InteriorId(const string kind, const datetime t_int)/string H3InteriorId(const string kind, const datetime t_int, const int idx)/' "$NEG/h.mqh" > "$NEG/i1.mqh"
o=$(check_ids "$NEG/i1.mqh"); r=$?; { [ $r -ne 0 ] && echo "$o" | grep -q 'window index parameter' && ! echo "$o" | grep -q 'function body not found'; } && echo "  PASS 13i: window index in an ID builder signature detected (intended reason)" || { echo "  FAIL 13i: index parameter not detected, or other reason: $o"; FAIL=1; }
sed 's/   return(kind + H4TimeStamp(t_int));/   return(kind + H4TimeStamp(t_int) + "_" + IntegerToString(sw[0].index));/' "$NEG/h.mqh" > "$NEG/i2.mqh"
o=$(check_ids "$NEG/i2.mqh"); r=$?; { [ $r -ne 0 ] && echo "$o" | grep -q 'window index or array subscript inside' && ! echo "$o" | grep -q 'function body not found'; } && echo "  PASS 13i: window index / array subscript in an ID builder body detected (intended reason)" || { echo "  FAIL 13i: index in body not detected, or other reason: $o"; FAIL=1; }
sed 's/   return(H3EventName(type) + "@" + H4TimeStamp(bar_time) + "#" + ref);/   return(H3EventName(type) + "@" + IntegerToString(type) + "#" + ref);/' "$NEG/h.mqh" > "$NEG/i3.mqh"
o=$(check_ids "$NEG/i3.mqh"); r=$?; { [ $r -ne 0 ] && echo "$o" | grep -q 'does not build from H4TimeStamp' && ! echo "$o" | grep -q 'function body not found'; } && echo "  PASS 13i: an event ID not built from the absolute bar time detected (intended reason)" || { echo "  FAIL 13i: event id without time stamp not detected, or other reason: $o"; FAIL=1; }
# 13j: MQL4 pattern and non-ASCII detection
printf 'void F(){ int n = iBars(Symbol(), 0); }\n' > "$NEG/j.mqh"
strip_comments "$NEG/j.mqh" | grep -qE "$PAT4" && echo "  PASS 13j: MQL4 pattern iBars/Symbol() detected" || { echo "  FAIL 13j: MQL4 pattern not detected"; FAIL=1; }
printf 'void F(){ } // caf\xc3\xa9\n' > "$NEG/k.mqh"
[ "$(LC_ALL=C grep -c '[^ -~	]' "$NEG/k.mqh")" != "0" ] && echo "  PASS 13k: non-ASCII byte detected" || { echo "  FAIL 13k: non-ASCII byte not detected"; FAIL=1; }
# 13l: a modified tracked file must be detected (temporary repository)
mkdir "$NEG/repo" && git -C "$NEG/repo" init -q && echo 'one' > "$NEG/repo/f.txt" && git -C "$NEG/repo" add f.txt && git -C "$NEG/repo" -c user.email=x@x -c user.name=x commit -q -m base
check_unmodified "$NEG/repo" f.txt && echo "  PASS 13l: an unmodified file passes" || { echo "  FAIL 13l: unmodified file flagged"; FAIL=1; }
echo 'two' > "$NEG/repo/f.txt"
check_unmodified "$NEG/repo" f.txt && { echo "  FAIL 13l: a modified tracked file was NOT detected"; FAIL=1; } || echo "  PASS 13l: a modified tracked file is detected"
# 13m: the Deferred() check must notice a pass-counting deferred helper
sed 's/g_deferred++;/g_deferred++; g_pass++;/' $TEST > "$NEG/t.mq5"
db=$(fn_body "$NEG/t.mq5" 'void Deferred(')
echo "$db" | grep -q 'g_pass' && echo "  PASS 13m: a Deferred() that counts a pass is detected" || { echo "  FAIL 13m: pass-counting Deferred() not detected"; FAIL=1; }
# 13n: a deferred line that says PASS must be caught by the pattern used in CHECK 11
printf '  DEFERRED PASS (not implemented in this round): x\n' > "$NEG/dp.txt"
grep -q 'DEFERRED.*PASS' "$NEG/dp.txt" && echo "  PASS 13n: a pass-labelled deferred line is detected" || { echo "  FAIL 13n: pass-labelled deferred line not detected"; FAIL=1; }
# 13o: an unresolved include must be detected
printf '#include "does_not_exist.mqh"\nvoid F(){}\n' > "$NEG/o.mqh"
out=$(unresolved_includes "$NEG/o.mqh") && { echo "  FAIL 13o: missing include not detected"; FAIL=1; } || { echo "$out" | grep -q 'does_not_exist' && echo "  PASS 13o: a missing include is detected (intended reason)" || { echo "  FAIL 13o: other reason: $out"; FAIL=1; }; }
# 13p: a mutated reference model must make the Python run fail, for the intended reason
mkdir "$NEG/py" && cp tests/t002_reference_test.py tests/t003_replay_csv.py "$NEG/py/" && sed 's/if s \* (bar.close - P) > 0:/if s * (bar.close - P) >= 0:/' $PYT > "$NEG/py/t003_reference_test.py"
cmp -s "$NEG/py/t003_reference_test.py" $PYT && { echo "  FAIL 13p: the mutation did not change the model (vacuous)"; FAIL=1; }
( cd "$NEG/py" && python3 t003_reference_test.py > out.txt 2>&1 ); rcm=$?
{ [ $rcm -ne 0 ] && grep -q 'FAILED: SELL: close exactly on the level is not a break' "$NEG/py/out.txt"; } && echo "  PASS 13p: a model that treats equality as a break fails the Python run (intended check failed)" || { echo "  FAIL 13p: mutated model not detected for the intended reason (rc=$rcm)"; FAIL=1; }
# 13q: a case-count mismatch must be detected
sed 's/#define T3_CASE_COUNT [0-9]*/#define T3_CASE_COUNT 1/' "$TMPD/have.n" > "$NEG/cnt.n"
cc2=$(grep -c '^      case [0-9]*:' "$NEG/cnt.n"); decl2=$(grep -oE '#define T3_CASE_COUNT [0-9]+' "$NEG/cnt.n" | awk '{print $3}')
[ "$cc2" != "$decl2" ] && echo "  PASS 13q: a wrong T3_CASE_COUNT is detected" || { echo "  FAIL 13q: count mismatch not detected"; FAIL=1; }
# 13r: fewer than 5 DEFERRED lines must be detected
printf '  DEFERRED (not implemented in this round): a\n' > "$NEG/d5.txt"
[ "$(grep -c 'DEFERRED (not implemented in this round)' "$NEG/d5.txt")" -lt 5 ] && echo "  PASS 13r: too few DEFERRED lines would be detected" || { echo "  FAIL 13r"; FAIL=1; }
# 13s: the FINDING 1 / FINDING 2 pattern checks must detect their own removal
sed 's/ix = H3BarIndexByTime(bars, n, refs\[i\])/ix = 0/' "$NEG/h.mqh" > "$NEG/s1.mqh"
o=$(anchor_ok "$NEG/s1.mqh") && { echo "  FAIL 13s: an anchor that does not locate the reference by time was NOT detected"; FAIL=1; } || { echo "$o" | grep -q 'does not locate the reference' && echo "  PASS 13s: anchor without the series search detected (intended reason)" || { echo "  FAIL 13s: other reason: $o"; FAIL=1; }; }
sed 's/datetime c = bars\[ix - p.left\].time;/datetime c = refs[i] - (datetime)(p.left * p.period);/' "$NEG/h.mqh" > "$NEG/s2.mqh"
o=$(anchor_ok "$NEG/s2.mqh") && { echo "  FAIL 13s: period arithmetic in the anchor was NOT detected"; FAIL=1; } || { echo "$o" | grep -qE 'Left existing bars|period arithmetic' && echo "  PASS 13s: time arithmetic instead of existing bars detected (intended reason)" || { echo "  FAIL 13s: other reason: $o"; FAIL=1; }; }
# revision 10: the structure checker must detect each of its own patterns being broken
neg_struct() { # neg_struct LABEL SED_EXPR SUBSTRING
  local label="$1" expr="$2" sub="$3" o
  sed "$expr" "$NEG/h.mqh" > "$NEG/st.mqh"
  if cmp -s "$NEG/st.mqh" "$NEG/h.mqh"; then echo "  FAIL 13s ($label): the mutation did not change the header (vacuous)"; FAIL=1; return; fi
  o=$(structure_ok "$NEG/st.mqh") && { echo "  FAIL 13s ($label): NOT detected"; FAIL=1; return; }
  echo "$o" | grep -qF -- "$sub" && echo "  PASS 13s ($label): detected (intended reason: $sub)" || { echo "  FAIL 13s ($label): other reason: $o"; FAIL=1; }
}
neg_struct "a freeze comes back in H3FvgStep" 's/         st.rec_from     = open_t + p.period;/         st.rec_from     = open_t + p.period; st.frozen = true;/' 'still writes st.frozen'
neg_struct "the derive step reads frozen" 's/   if(st.dir == H3_NONE)\r\?$/   if(st.dir == H3_NONE || st.frozen)/' 'reads st.frozen'
neg_struct "ratchet (iii) removed" 's/ \&\& s \* lvl.price < s \* st.lv_price//' 'ratchet (iii) missing'
neg_struct "ratchet (ii) removed" 's/lvl.ext_time > st.lv_ext \&\& //' 'ratchet (ii) missing'
neg_struct "RECONF_LOST ends the setup" 's/            st.rec_from     = 0;\r\?$/            st.rec_from     = 0; H3ClearSetup(st, tracks, nt);/' 'ends or clears the setup'
neg_struct "a SUPERSEDED reason appears" 's/H3SetupEnded(st, open_t, "REPLACED", new_id, events, ne);/H3SetupEnded(st, open_t, "SUPERSEDED_BY_STRUCTURE", new_id, events, ne);/' 'SUPERSEDED_BY_STRUCTURE'
neg_struct "an expiry appears" 's/   if(st.dir == H3_NONE)\r\?$/   int max_age = 100; if(st.dir == H3_NONE)/' 'expiry'
neg_struct "the snapshot becomes an invalidation" 's/      if(ph != H3_PH_ACTIVE \&\& st.snap_id != "" \&\& s \* (bars\[t\].close - st.snap_price) > 0)/      if(ph != H3_PH_ACTIVE \&\& st.snap_id != "" \&\& s * (bars[t].close - st.snap_price) > 0 \&\& s * (bars[t].low - st.snap_price) > 0)/' 'snapshot price is read outside'
neg_struct "observation events limited to ACTIVE/SWEEP_WAIT again" 's/   \/\/--- observation events: the structure runs in EVERY phase (a setup does not freeze it)/   if(ph != H3_PH_ACTIVE \&\& ph != H3_PH_SWEEP_WAIT) return(false);/' 'returns early outside ACTIVE/SWEEP_WAIT'
neg_liq "a touch consumes (>= 0 in the first-crossing scan)" 's/H3AdverseExt(bars\[j\], s) - sw\[i\].price) > 0)/H3AdverseExt(bars[j], s) - sw[i].price) >= 0)/' 'STRICT'
neg_liq "the scope is not bounded by the level pivot" 's/sw\[i\].pivot_time <= st.lv_pivot/false/' 'bounded by the pivot'
neg_liq "a swing at the level price is inside" 's/s \* (sw\[i\].price - st.lv_price) < 0/s * (sw[i].price - st.lv_price) <= 0/' 'strictly inside'
neg_liq "consumption ignored in the scope" 's/      if(H3LiqFirstCross(bars, sw, i, upto, lc) >= 0)/      if(false)/' 'consumption history'
neg_liq "the first usable bar is skipped" 's/lc.scanned\[i\] = sw\[i\].index + right;/lc.scanned[i] = sw[i].index + right + 2;/' 'first usable bar'
neg_liq "a sweep setup from any phase" 's/   if(ph == H3_PH_ACTIVE || ph == H3_PH_SWEEP_WAIT)           \/\/ never from HOLD/   if(true)           \/\/ never from HOLD/' 'only from ACTIVE or SWEEP_WAIT'
neg_liq "the layer writes the bias" 's/      st.setup_type   = "SWEEP";/      st.setup_type   = "SWEEP"; st.dir = -st.dir;/' 'observation only'
neg_liq "the LI key element removed" 's/   string li = (st.li_key == "" ? "-" : st.li_key);/   string li = "-";/' 'li_key'
neg_liq "the consumption is judged up to t instead of t-1" 's/H3LiqScope(bars, sw, nk, st, s, t - 1, lc, scope)/H3LiqScope(bars, sw, nk, st, s, t, lc, scope)/' 'up to t-1'
# the visual EA identity check must detect a change (temporary repository)
mkdir "$NEG/vrepo" && git -C "$NEG/vrepo" init -q && mkdir -p "$NEG/vrepo/src/include" && echo a > "$NEG/vrepo/src/XauUsdH4Bias.mq5" && echo b > "$NEG/vrepo/src/include/H4BiasDrawer.mqh" && git -C "$NEG/vrepo" add -A && git -C "$NEG/vrepo" -c user.email=x@x -c user.name=x commit -q -m base
vb=$(git -C "$NEG/vrepo" rev-parse HEAD)
git -C "$NEG/vrepo" diff --quiet "$vb" -- src/XauUsdH4Bias.mq5 src/include/H4BiasDrawer.mqh && echo "  PASS 13s: an unchanged visual EA pair passes the identity test" || { echo "  FAIL 13s: unchanged pair flagged"; FAIL=1; }
echo c >> "$NEG/vrepo/src/include/H4BiasDrawer.mqh"
git -C "$NEG/vrepo" diff --quiet "$vb" -- src/XauUsdH4Bias.mq5 src/include/H4BiasDrawer.mqh && { echo "  FAIL 13s: a modified drawer was NOT detected"; FAIL=1; } || echo "  PASS 13s: a modified visual EA file is detected by the identity test"
# 13t: mutated MODELS must make the Python run fail, for the intended reason
mutate_py() { # mutate_py SED_EXPR EXPECTED_FAILED_LABEL_REGEX LABEL
  mkdir -p "$NEG/pm" && cp tests/t002_reference_test.py tests/t003_replay_csv.py "$NEG/pm/" && sed "$1" $PYT > "$NEG/pm/t003_reference_test.py"
  if cmp -s "$NEG/pm/t003_reference_test.py" $PYT; then echo "  FAIL 13t ($3): the mutation did not change the model (vacuous)"; FAIL=1; return; fi
  ( cd "$NEG/pm" && python3 t003_reference_test.py > out.txt 2>&1 ); local rcx=$?
  if [ $rcx -ne 0 ] && grep -qE "(^  FAIL |FAILED: ).*($2)" "$NEG/pm/out.txt"; then echo "  PASS 13t: $3 -> the Python run fails (intended check: $2)"; else echo "  FAIL 13t ($3): not detected for the intended reason (rc=$rcx)"; FAIL=1; fi
}
mutate_py2() { # mutate_py2 OLD NEW EXPECTED_FAILED_LABEL_REGEX LABEL : exact text replacement in the model, the Python run must fail
  mkdir -p "$NEG/pm" && cp tests/t002_reference_test.py tests/t003_replay_csv.py "$NEG/pm/"
  python3 -I - "$PYT" "$NEG/pm/t003_reference_test.py" "$1" "$2" <<'PYEOF2'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding='ascii').read()
if old not in t:
    sys.exit(3)
open(dst, 'w', encoding='ascii').write(t.replace(old, new, 1))
PYEOF2
  if [ $? -ne 0 ]; then echo "  FAIL 13t ($4): the mutation target text is absent (vacuous)"; FAIL=1; return; fi
  ( cd "$NEG/pm" && python3 t003_reference_test.py > out.txt 2>&1 ); local rcy=$?
  if [ $rcy -ne 0 ] && grep -qE "(^  FAIL |FAILED: ).*($3)" "$NEG/pm/out.txt"; then echo "  PASS 13t: $4 -> the Python run fails (intended check: $3)"; else echo "  FAIL 13t ($4): not detected for the intended reason (rc=$rcy)"; FAIL=1; fi
}
mutate_py2 "        if not (lvl.ext_time > st.lv_ext and s * lvl.price < s * st.lv_price):" "        if False:" 'R2|R13|R14' 'the ratchet is removed (a wick top can raise the level)'
mutate_py2 "                st.phase = to
                st.recon_reason = ''
                st.rec_id = ''
                st.rec_from = 0" "                st.phase = to
                st.recon_reason = ''
                st.rec_id = ''
                st.rec_from = 0
                setup_ended(st, open_t, 'RECONF_LOST', events)
                clear_setup(st, tracks)" 'RECONF_LOST' 'RECONF_LOST ends the setup'
mutate_py2 "    if struct_a != struct_b:
        why.append('AB_STRUCTURE_DIFF')" "    if False:
        why.append('AB_STRUCTURE_DIFF')" 'SC-1|R17|R18' 'the A/B check ignores the STRUCTURE key'
mutate_py2 "    if setup_a != setup_b:
        why.append('AB_SETUP_DIFF')" "    if False:
        why.append('AB_SETUP_DIFF')" 'R17|R18' 'the A/B check ignores the SETUP key'
mutate_py2 "        tx(st.src_time), tx(st.wait_start)," "        tx(st.src_time), '0'," 'wait_start' 'wait_start removed from the compared key'
mutate_py2 "        out.append('%s[%s-%s]@%s:%s' % (tr.id, pf(tr.lower), pf(tr.upper), tx(tr.conf)," "        out.append('%s[%s-%s]@%s:%s' % (tr.id, '0', '0', tx(tr.conf)," 'FVG bound' 'FVG bounds removed from the compared key'
mutate_py2 "        ('%s@%s/%d' % (st.ex_id, pf(st.ex_price), 1 if st.ex_consumed else 0)) if st.has_ext else '-'," "        ('%s@%s/%d' % (st.ex_id, pf(st.ex_price), 0)) if st.has_ext else '-'," 'R21' 'the consumed flag of the continuation candidate removed from the key'
mutate_py2 "        st.li_key if st.li_key else '-'," "        '-'," 'R21|29m|29r' 'the LI element (set of unconsumed in-scope internal levels) removed from the structure key'
mutate_py2 "            if s * (adverse_ext(bars[j], s) - x.price) > 0:
                first = j" "            if s * (adverse_ext(bars[j], s) - x.price) >= 0:
                first = j" '29d|29m|29e' 'revision 14: a TOUCH (==) counts as a consumption'
mutate_py2 "        if s * (adverse_ext(bar, s) - x.price) > 0:          # strictly beyond; a touch (==) is NOT a crossing" "        if s * (adverse_ext(bar, s) - x.price) >= 0:          # strictly beyond; a touch (==) is NOT a crossing" '29d|29e|29m' 'revision 14: a TOUCH (==) is raised as a crossing'
mutate_py2 "            if s * (bar.close - x.price) > 0:
                broke.append(x)" "            if s * (bar.close - x.price) >= 0:
                broke.append(x)" '29c2' 'revision 14: a close EQUAL to the level is a break'
mutate_py2 "        if liq_first_cross(st, bars, p, sw, i, upto) >= 0:
            continue" "        if False:
            continue" '29m|29a|29f|29i' 'revision 14: consumption ignored (a crossed level stays in the set)'
# NOTE: removing the pivot bound of the scope is an EQUIVALENT mutant (a swing high before the protecting level's pivot and below it is
# always crossed by the level's own bar, hence consumed); the bound is kept as the written rule and as a cost bound, and only the
# pattern check (CHECK 12c) guards its presence. The revival mutation below is the behavioural control of the consumption history.
mutate_py2 "        if liq_first_cross(st, bars, p, sw, i, upto) >= 0:
            continue" "        fc_ = liq_first_cross(st, bars, p, sw, i, upto)
        if fc_ >= 0 and bars[fc_].time + p.period > st.lv_known:
            continue" '29i|29j' 'revision 14: only crossings after the CURRENT level became known consume (a change of the level or a flip REVIVES a consumed level)'
mutate_py2 "    scanned, first = st.liq_cache.get(i, (x.index + p.right, -1))" "    scanned, first = st.liq_cache.get(i, (x.index + p.right + 2, -1))" '29k|29m|29i' 'revision 14: the first usable bar is skipped (consumption starts too late)'
mutate_py2 "    for x in broke:
        lid = interior_id(kind, x.pivot_time)" "    for x in []:
        lid = interior_id(kind, x.pivot_time)" 'INTERNAL_BREAK|29c' 'revision 14: the INTERNAL_BREAK events of a bar are not raised'
mutate_py2 "            events.append(wick_event(open_t, st, restart))
            return False" "            events.append(wick_event(open_t, st, restart))
            liq_internal_events(t, bars, sw, fv, p, st, tracks, events, open_t, close_t, d, s, ph)
            return False" '29f' 'revision 14: the structural priority is lost (a wick bar raises INTERNAL_* too)'
mutate_py2 "    if ph == 'ACTIVE' or ph == 'SWEEP_WAIT':                   # never from HOLD / RECONFIRMED (11.5 open point)" "    if True:                   # never from HOLD / RECONFIRMED (11.5 open point)" '29g|29h' 'revision 14: a sweep seen in HOLD / RECONFIRMED replaces the setup'
mutate_py2 "    top = swept[-1]                                            # ONE setup per bar, from the most adverse level" "    top = swept[0]                                            # ONE setup per bar, from the most adverse level" '29b|29a' 'revision 14: the setup is taken from the nearest swept level instead of the most adverse'
mutate_py2 "    setup_ended(st, open_t, END_REPLACED, events, new_id)
    st.phase = 'HOLD'" "    st.phase = 'HOLD'" 'REPLACED|R16|second wick' 'a new wick no longer ends the previous setup'
mutate_py2 "    if old_setup != '':
        # the structure flipped: the setup is over for good (INVALIDATED_BY_FLIP)" "    if False:
        # the structure flipped: the setup is over for good (INVALIDATED_BY_FLIP)" 'body break during' 'a flip no longer ends the setup'
mutate_py 's/        c = bars\[i - p\.left\]\.time/        c = r - p.left * p.period/' '(weekend gap|history gap)' 'anchor by time arithmetic instead of existing bars'
mutate_py "s/        if i < p\.left:/        if False:/" 'window start' 'no missing-history report when fewer than Left bars exist'
mutate_py2 "                if sx.confirm_time != bars[sx.index + right].time + PERIOD:" "                if sx.confirm_time != sx.pivot_time + (right + 1) * PERIOD:" 'confirm_time' 'confirm_time checked by pivot + (Right+1) periods (the revision 9 wording) fails across a weekend'
rm -rf "$NEG"

echo "=== RESULT ==="
[ $FAIL -eq 0 ] && echo "ALL STATIC CHECKS PASSED (not a compilation, not a runtime test)" || echo "STATIC CHECKS FAILED"
exit $FAIL
