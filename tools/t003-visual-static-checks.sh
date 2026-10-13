#!/bin/bash
# Static checks for the T003 VISUAL EA (src/XauUsdH4Bias.mq5, src/include/H4BiasDrawer.mqh).
#
# These are NOT a compiler and NOT a runtime test and NOT a chart observation. They prove only
# what can be read from the source text: no trading API, chart-object isolation (T003 prefix only),
# the live/historical flow (closed bars only, no live price, baseline cursor, clear/recover),
# no other-timeframe or out-of-scope construct, balanced syntax, format strings, ASCII, and that the
# T001/T002 files (and the T003 logic) are byte-identical to the base commits. Every checker is
# shown to fail on a mutated copy (negative controls), for the intended reason.
# MetaEditor compilation, the MT5 script run and the chart observation are still UNVERIFIED.
#
# The python helper tools/t003-visual-check.py holds the pattern checks; t001-check-balance.py and
# t001-check-format-strings.py are reused unchanged.
#
# Usage: bash tools/t003-visual-static-checks.sh   (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
EA=src/XauUsdH4Bias.mq5
DRW=src/include/H4BiasDrawer.mqh
VIS="$EA $DRW"
CHK="python3 -I tools/t003-visual-check.py"
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT

# collect_includes FILE -> FILE plus every file it includes (transitively, relative includes only)
collect_includes() {
  local todo="$1" seen="" f d inc p
  while [ -n "$todo" ]; do
    set -- $todo; f="$1"; shift; todo="$*"
    case " $seen " in *" $f "*) continue;; esac
    seen="$seen $f"
    d=$(dirname "$f")
    for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
      p="$d/$inc"
      [ -f "$p" ] && todo="$todo $p"
    done
  done
  echo $seen
}
# mut SRC DST OLD NEW -> DST = SRC with the first exact OLD replaced; exits 3 (vacuous) if OLD is absent
mut() {
  python3 -I - "$1" "$2" "$3" "$4" <<'PYEOF'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding='ascii').read()
if old not in t:
    sys.exit(3)
open(dst, 'w', encoding='ascii').write(t.replace(old, new, 1))
PYEOF
}
# expect_fail LABEL CHECK FILE... -- SUBSTRING : the check must fail and its output must contain SUBSTRING
expect_fail() {
  local label="$1" chk="$2"; shift 2
  local files=() sub
  while [ "$1" != "--" ]; do files+=("$1"); shift; done
  shift; sub="$1"
  local out; out=$($CHK "$chk" "${files[@]}" 2>&1); local rc=$?
  if [ $rc -ne 0 ] && echo "$out" | grep -qF -- "$sub"; then
    echo "  PASS $label (detected: $sub)"
  else
    echo "  FAIL $label: rc=$rc, expected output containing '$sub', got: $out"; FAIL=1
  fi
}
# neg LABEL CHECK FILE_KIND(EA|DRW) OLD NEW SUBSTRING : mutate the EA or drawer copy, then expect failure
neg() {
  local label="$1" chk="$2" kind="$3" old="$4" new="$5" sub="$6" f
  rm -rf "$NEG/m"; mkdir -p "$NEG/m/include"
  cp $EA "$NEG/m/XauUsdH4Bias.mq5"; cp $DRW "$NEG/m/include/H4BiasDrawer.mqh"
  if [ "$kind" = EA ]; then f="$NEG/m/XauUsdH4Bias.mq5"; else f="$NEG/m/include/H4BiasDrawer.mqh"; fi
  local src; if [ "$kind" = EA ]; then src=$EA; else src=$DRW; fi
  if ! mut "$src" "$f" "$old" "$new"; then echo "  FAIL $label: the mutation target text is absent (vacuous control)"; FAIL=1; return; fi
  expect_fail "$label" "$chk" "$NEG/m/XauUsdH4Bias.mq5" "$NEG/m/include/H4BiasDrawer.mqh" -- "$sub"
}

echo "=== V1: the visual files exist and are not empty ==="
for f in $VIS tools/t003-visual-check.py; do
  [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }
done

echo "=== V2: no order/trading API in the EA, the drawer or any file they include (comments stripped) ==="
ALLINC=$(collect_includes $EA)
echo "  INFO: files scanned: $ALLINC"
case "$ALLINC" in *H4Bias.mqh*H4Structure.mqh*|*H4Structure.mqh*H4Bias.mqh*) echo "  PASS include closure contains H4Bias.mqh and H4Structure.mqh (check is not vacuous)";; *) echo "  FAIL include closure incomplete: $ALLINC"; FAIL=1;; esac
[ $(echo $ALLINC | wc -w) -ge 6 ] || { echo "  FAIL fewer than 6 files in the include closure"; FAIL=1; }
out=$($CHK trading $ALLINC) && echo "  PASS no trading API in $(echo $ALLINC | wc -w) files" || { echo "$out"; echo "  FAIL trading API present"; FAIL=1; }
grep -q 'input .*Magic\|CTrade' $EA && { echo "  FAIL the EA declares a magic or trade object"; FAIL=1; } || echo "  PASS the EA declares no magic number / trade object"

echo "=== V3: balance, includes, format strings, ASCII, MQL4 ==="
python3 tools/t001-check-balance.py $VIS || FAIL=1
for f in $VIS; do
  d=$(dirname "$f"); bad=0
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "  FAIL $f: missing include $d/$inc"; bad=1; FAIL=1; }
  done
  [ $bad -eq 0 ] && echo "  PASS $f: every include resolves"
done
g=$(grep -c '^#ifndef' $DRW); e=$(grep -c '^#endif' $DRW)
[ "$g" = "$e" ] && echo "  PASS $DRW: include guard balanced ($g/$e)" || { echo "  FAIL $DRW: guard $g vs endif $e"; FAIL=1; }
python3 - $VIS <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
for f in $VIS tools/t003-visual-check.py tools/t003-visual-static-checks.sh docs/T003-visual-ea.md; do
  [ -f "$f" ] || { echo "  FAIL $f missing"; FAIL=1; continue; }
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  [ "$n" = "0" ] && echo "  PASS $f: ASCII only" || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }
done
PAT4='\bOrdersTotal\(\)|\biBars\(|\bAccountBalance\(|\bMarketInfo\(|\bOrderType\(\)|\bSymbol\(\)|\bBid\b|\bAsk\b|\bPoint\b[^(]|\bDigits\b[^(]|\bstart\(\)|\binit\(\)|\bdeinit\(\)'
for f in $VIS; do
  out=$(python3 -I -c "import sys; sys.path.insert(0,'tools'); import importlib.util as u; s=u.spec_from_file_location('v','tools/t003-visual-check.py'); m=u.module_from_spec(s); s.loader.exec_module(m); print(m.strip(open('$f').read(), keep_strings=False))" | grep -nE "$PAT4")
  [ -z "$out" ] && echo "  PASS $f: no MQL4-style API" || { echo "  FAIL $f: $out"; FAIL=1; }
done
grep -qE '^int OnInit\(' $EA && grep -qE '^void OnDeinit\(' $EA && grep -qE '^void OnTimer\(' $EA && echo "  PASS $EA defines OnInit / OnDeinit / OnTimer (an Expert Advisor, not a script)" || { echo "  FAIL EA entry points missing"; FAIL=1; }

echo "=== V4: chart-object isolation (T003 prefix only) and prefix collision ==="
out=$($CHK isolation $VIS) && echo "  PASS every ObjectsDeleteAll uses m_prefix / m_panel_prefix, ClearMap tests the prefix before each ObjectDelete, every created object name starts with the T003 prefix, names are stable" || { echo "$out"; echo "  FAIL isolation"; FAIL=1; }
out=$($CHK collision $VIS) && echo "  PASS velo_t003_ cannot collide with velo_t001_ / velo_t002_ (neither is a prefix of the other); no foreign prefix literal" || { echo "$out"; echo "  FAIL prefix collision"; FAIL=1; }

echo "=== V5: live / historical flow ==="
out=$($CHK flow $VIS) && echo "  PASS closed bars only (CopyRates from position 1 live, from the as-of time historical), historical mode never rebuilds on new bars and never consumes events, baseline cursor before H3ConsumeNew, clear/recover resets the baseline, unreliable evaluation draws nothing" || { echo "$out"; echo "  FAIL flow"; FAIL=1; }
out=$($CHK nopricefeed $VIS) && echo "  PASS no quote/tick/indicator access, no other timeframe than H4, no overlay/target/SL-TP construct in the EA or the drawer" || { echo "$out"; echo "  FAIL price feed or out-of-scope construct"; FAIL=1; }

echo "=== V6: T001/T002 files are unchanged; the T003 logic only GREW (diagnostics) ==="
# The T003 logic files below were extended on purpose by the diagnostics round (H4Bias.mqh gained lines only: see
# tools/t003-static-checks.sh CHECK 14; the test script, the model and the static checks follow); every other file
# that exists at the base commits must still be identical.
T003_LOGIC='^(src/include/H4Bias\.mqh|src/tests/T003_LogicTest\.mq5|tests/t003_reference_test\.py|tools/t003-static-checks\.sh)$'
for base in dd571f6 62a0747; do
  if git cat-file -e "$base^{commit}" 2>/dev/null; then
    files=$(git ls-tree -r --name-only "$base" -- src tools tests | grep -vE "$T003_LOGIC")
    n=$(echo "$files" | wc -l)
    if git diff --quiet "$base" -- $files 2>/dev/null; then
      echo "  PASS all $n files under src/ tools/ tests/ that exist at $base (except the four T003 logic files) are identical in the working tree"
    else
      echo "  FAIL a file that exists at $base differs from it:"; git diff --stat "$base" -- $files | tail -5; FAIL=1
    fi
  else
    echo "  INFO: base commit $base not available here; the parent must verify against it"
  fi
done
for f in src/include/H4Structure.mqh src/XauUsdH4Map.mq5 src/include/H4MapDrawer.mqh src/XauUsdFoundation.mq5; do
  git diff --quiet HEAD -- "$f" 2>/dev/null && echo "  PASS $f identical to HEAD" || { echo "  FAIL $f differs from HEAD"; FAIL=1; }
done
echo "  INFO: untracked files: $(git ls-files --others --exclude-standard | tr '\n' ' ')"

echo "=== V8: diagnostics, candle export and TrackChanges (source reading) ==="
out=$($CHK diag $VIS) && echo "  PASS export off by default and gated by InpExportCandles; file access only inside ExportCandles (closed-bar set g_bars, no series/tick/quote read, full path reported); called once from EvaluateAndDraw; diagnostics only for an unreliable evaluation and read-only; TrackChanges reports only under H3_TC_REPORT" || { echo "$out"; echo "  FAIL diagnostics / export / TrackChanges pattern"; FAIL=1; }

echo "=== V7: negative controls (every checker must detect its problem, for the intended reason) ==="
# trading API
cp $EA "$NEG/ea1.mq5"; printf 'void F(){ MqlTradeRequest r; OrderSend(r, res); }\n' >> "$NEG/ea1.mq5"
expect_fail "N1 injected OrderSend / MqlTradeRequest in the EA" trading "$NEG/ea1.mq5" -- "trading API"
cp $DRW "$NEG/d1.mqh"; printf '#include <Trade\\Trade.mqh>\nCTrade g_t;\n' >> "$NEG/d1.mqh"
expect_fail "N2 CTrade include in the drawer" trading "$NEG/d1.mqh" -- "trading API"
cp src/include/SymbolSnapshot.mqh "$NEG/ss.mqh"; printf 'void F(){ PositionOpen(1); }\n' >> "$NEG/ss.mqh"
expect_fail "N3 trading API inside an included file" trading "$NEG/ss.mqh" -- "trading API"
printf '// OrderSend and CTrade are forbidden\n/* PositionClose */ void F(){ string s = "OrderSend"; }\n' > "$NEG/c1.mqh"
$CHK trading "$NEG/c1.mqh" >/dev/null && echo "  PASS N4 trading words in comments and string literals are not flagged" || { echo "  FAIL N4 comment/string mention flagged"; FAIL=1; }
# isolation
neg "N5 ObjectsDeleteAll with an empty prefix" isolation DRW 'ObjectsDeleteAll(m_chart, m_prefix);
     }

   //--- Delete the map objects' 'ObjectsDeleteAll(m_chart, "");
     }

   //--- Delete the map objects' "(only m_prefix / m_panel_prefix allowed)"
neg "N6 ObjectsDeleteAll with the T002 prefix" isolation DRW 'ObjectsDeleteAll(m_chart, m_prefix);
     }

   //--- Delete the map objects' 'ObjectsDeleteAll(m_chart, "velo_t002_");
     }

   //--- Delete the map objects' "(only m_prefix / m_panel_prefix allowed)"
neg "N7 ObjectsDeleteAll with only the chart (deletes everything)" isolation DRW 'ObjectsDeleteAll(m_chart, m_prefix);
     }

   //--- Delete the map objects' 'ObjectsDeleteAll(m_chart);
     }

   //--- Delete the map objects' "without a prefix argument"
neg "N8 ClearMap without the prefix test" isolation DRW 'StringFind(name, m_prefix) != 0)' 'StringFind(name, m_prefix) != 99)' "does not skip objects whose name does not start with m_prefix"
neg "N9 ClearMap deleting the panel too" isolation DRW 'StringFind(name, m_panel_prefix) == 0)' 'StringFind(name, m_panel_prefix) == 99)' "leave the panel sub-prefix alone"
neg "N10 a chart label without the prefix" isolation DRW 'Note(m_prefix + "wick_" + H4TimeStamp(st.wk_src), st.wk_src, wp,' 'Note("wick_" + H4TimeStamp(st.wk_src), st.wk_src, wp,' "does not start with m_prefix"
neg "N11 an object name depending on the clock" isolation DRW 'Note(m_prefix + "det_" + H4TimeStamp(st.wk_det),' 'Note(m_prefix + "det_" + IntegerToString(GetTickCount()),' "depends on a clock"
neg "N12 ObjectDelete outside ClearMap/End" isolation DRW '   void              Reset(void)
     {
      ClearMap();' '   void              Reset(void)
     {
      ObjectDelete(m_chart, "x");
      ClearMap();' "ObjectDelete outside ClearMap/End"
neg "N13 a T002 prefix literal in the EA" collision EA 'Print("================ T003 H4 bias (visual) ================");' 'Print("================ T003 H4 bias (visual) ================"); string zz = "velo_t002_foo";' "another task prefix"
neg "N14 the T003 prefix shortened so that it covers T001/T002" collision DRW '#define H3V_PREFIX        "velo_t003_"' '#define H3V_PREFIX        "velo_t00"' "expected velo_t003_"
# flow
neg "N15 live CopyRates from position 0 (forming bar)" flow EA 'CopyRates(g_symbol, PERIOD_H4, 1, g_depth, out)' 'CopyRates(g_symbol, PERIOD_H4, 0, g_depth, out)' "forming bar"
neg "N16 historical mode rebuilds on new bars" flow EA 'H4NewBarForLife(g_hist, new_bar)' 'new_bar' "H4NewBarForLife"
neg "N17 events consumed in historical mode too" flow EA 'if(!g_hist)
      ConsumeEvents();' 'ConsumeEvents();' "ConsumeEvents is not restricted to live mode"
neg "N18 no baseline before H3ConsumeNew" flow EA 'g_cursor = H3BaselineCursor(g_ev);' 'g_cursor = 0;' "H3BaselineCursor"
neg "N19 recovery keeps the old baseline" flow EA '   g_cursor = 0;
   g_n_new = 0;
   g_prev_valid = false;' '   g_n_new = 0;
   g_prev_valid = false;' "ClearBiasState lacks g_cursor = 0"
neg "N20 a clear that does not remove the objects" flow EA '   H3VViewInit(g_view);
   g_drawer.Reset();' '   H3VViewInit(g_view);' "g_drawer.Reset()"
neg "N21 an unreliable evaluation still draws" flow DRW 'if(!ev.reliable || !ev.has_state' 'if(!ev.has_state' "does not stop on an unreliable"
neg "N22 the historical branch evaluates like live" flow EA 'if(g_hist)
      H3Evaluate(g_bars, g_n, g_params, g_ev, g_tracks, g_events);
   else
      H3EvaluateLatest' 'if(false)
      H3Evaluate(g_bars, g_n, g_params, g_ev, g_tracks, g_events);
   else
      H3EvaluateLatest' "does not use H3Evaluate for historical"
neg "N23 a live bid read" nopricefeed EA 'void OnTick(void)  { Poll(); }' 'void OnTick(void)  { double b = SymbolInfoDouble(g_symbol, SYMBOL_BID); Poll(); }' "quote/tick"
neg "N24 an M15 series" nopricefeed EA 'void OnTick(void)  { Poll(); }' 'void OnTick(void)  { int p = PERIOD_M15; Poll(); }' "other-timeframe"
neg "N25 an intrabar overlay construct" nopricefeed DRW '      ChartRedraw(m_chart);
     }
  };' '      ChartRedraw(m_chart); bool overlay = true;
     }
  };' "out-of-scope"
# diagnostics / export / TrackChanges
neg "N30 candle export on by default" diag EA 'input bool             InpExportCandles = false;' 'input bool             InpExportCandles = true;' "default false"
neg "N31 file access outside the export" diag EA 'void OnTick(void)  { Poll(); }' 'void OnTick(void)  { int hh = FileOpen("x.csv", FILE_WRITE); Poll(); }' "outside ExportCandles"
neg "N32 the export reads a series" diag EA '   g_export_text = "";
   if(!InpExportCandles || g_n <= 0)
      return;' '   g_export_text = "";
   MqlRates zz[];
   int cz = CopyRates(g_symbol, PERIOD_H4, 0, 5, zz);
   if(!InpExportCandles || g_n <= 0)
      return;' "a series/tick copy"
neg "N33 the export is not gated by the input" diag EA 'if(!InpExportCandles || g_n <= 0)' 'if(g_n <= 0)' "not gated by InpExportCandles"
neg "N34 the export reads a quote" diag EA '   string name = H3CsvName(g_symbol, x.last);' '   double qq = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   string name = H3CsvName(g_symbol, x.last);' "a quote"
neg "N35 the export is not reported with its full path" diag EA 'TerminalInfoString(TERMINAL_DATA_PATH)' 'g_symbol' "full path"
neg "N36 the diagnostics rewrite the evaluation" diag EA '   H3Diagnose(g_bars, g_n, g_params, g_ev, g_diag);' '   H3Diagnose(g_bars, g_n, g_params, g_ev, g_diag); g_ev.reliable = true;' "changes or recomputes the evaluation"
neg "N37 TrackChanges ignores the consumer decision" diag EA 'int mode = H3TrackChangesMode(g_cons_status, g_prev_valid);' 'int mode = H3_TC_REPORT;' "H3TrackChangesMode"
neg "N38 TrackChanges reports outside the REPORT branch" diag EA '   else
      if(mode == H3_TC_REDERIVE && (bias != g_prev_bias' '   else
      if(mode == H3_TC_REDERIVE && (PushChange("x"), bias != g_prev_bias' "outside the H3_TC_REPORT branch"
neg "N39 the consumer status is not recorded" diag EA '   g_cons_status = cs;' '   int cs_unused = cs;' "consumer status"
# balance / format / ASCII
printf 'void F(){ if(a { }\n' > "$NEG/b1.mqh"
python3 tools/t001-check-balance.py "$NEG/b1.mqh" >/dev/null && { echo "  FAIL N26 unbalanced file passed"; FAIL=1; } || echo "  PASS N26 unbalanced parentheses detected"
printf 'void F(){ string s = StringFormat("%%d %%s", 1); }\n' > "$NEG/f1.mqh"
python3 - "$NEG/f1.mqh" <<'PYEOF' >/dev/null
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
[ $? -ne 0 ] && echo "  PASS N27 format-string mismatch detected" || { echo "  FAIL N27 mismatch not detected"; FAIL=1; }
printf 'void F(){ } // caf\xc3\xa9\n' > "$NEG/a1.mqh"
[ "$(LC_ALL=C grep -c '[^ -~	]' "$NEG/a1.mqh")" != "0" ] && echo "  PASS N28 non-ASCII byte detected" || { echo "  FAIL N28 non-ASCII not detected"; FAIL=1; }
# unchanged-file check: a modified tracked file must be caught
mkdir "$NEG/repo" && git -C "$NEG/repo" init -q && echo one > "$NEG/repo/f.txt" && git -C "$NEG/repo" add f.txt && git -C "$NEG/repo" -c user.email=x@x -c user.name=x commit -q -m base
b=$(git -C "$NEG/repo" rev-parse HEAD)
git -C "$NEG/repo" diff --quiet "$b" -- f.txt && echo "  PASS N29a an unmodified file passes the base comparison" || { echo "  FAIL N29a"; FAIL=1; }
echo two > "$NEG/repo/f.txt"
git -C "$NEG/repo" diff --quiet "$b" -- f.txt && { echo "  FAIL N29 a modified file was NOT detected"; FAIL=1; } || echo "  PASS N29 a file modified against the base commit is detected"

echo "=== RESULT ==="
[ $FAIL -eq 0 ] && echo "ALL VISUAL STATIC CHECKS PASSED (not a compilation, not a runtime test, not a chart observation)" || echo "VISUAL STATIC CHECKS FAILED"
exit $FAIL
