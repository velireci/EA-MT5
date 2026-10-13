# T003 verification record - first limited implementation round (pure logic and tests)

Branch `claude/t003-h4-bias`, created from the T002 head `dd571f6` (PR velireci/EA-MT5#2, draft, not merged). Specification: `tasks/T003-h4-bias-change.md` revision 5. Every rule is a PROPOSAL awaiting the client's visual validation, not confirmed strategy. T003 is not complete.

## 1. Evidence, by kind
| Evidence | Status | Source |
|---|---|---|
| MQL5 compilation of `H4Bias.mqh` and `T003_LogicTest.mq5` | **UNVERIFIED, not compiled** | No MetaEditor in my environment. The Codex 0/0 results for T002 say nothing about this code |
| `T003_LogicTest.mq5` run in MT5 | **NOT RUN** | - |
| Python reference model tests (`tests/t003_reference_test.py`) | 188 passed, 0 failed, 5 deferred (deferred are not passes) | Run by the implementing agent and again by me. They verify the algorithm MODEL, not the MQL5 source |
| Static checks `tools/t003-static-checks.sh` | PASS, exit 0, 51 PASS lines; negative controls 13a-13r fail for the intended reason | Run by the agent and by me. Not a compilation |
| T002 and T001 static checks, `tests/t002_reference_test.py` | PASS / PASS / 197 passed, 0 failed | Rerun by me: nothing existing changed. `git status` shows only the four new files; `git diff HEAD` is empty for tracked files |
| C++ translation run (supplementary) | the agent reports: the three MQL5 files regex-translated to C++ with a shim, compiled with g++ -Wall; the translated script printed 166 passed, 0 failed, 5 deferred, covering the 98 transcript equalities with the Python model; four mutations of the translated logic were detected | Agent-reported. The harness is outside the repository and was not delivered; I did not run it. It is NOT MQL5 compilation and does not show MetaEditor will accept the code |
| Mutation checks on the Python model | The agent reports the delicate rules are caught (equality as a break or wick, retroactive `detected_at`, FVG qualified by `detected_at`, seed overwriting a conflict, A/B state/event/anchor/depth checks removed, invalid not winning over touch, interior break flipping, consumer ignoring the cursor, candidates built from a state including bar t, window index in IDs, and others). Two mutants are not caught and are equivalent by construction (a redundant touch guard and a redundant level guard) | Agent-reported; some mutants were caught only after the agent added cases (`p16e_event_only_diff`) or factored helpers (`fvg_eligible`, `consumer_prev_ok`) |

What the Python tests prove: the algorithm model behaves as specified on controlled data. What they do not prove: that the MQL5 compiles, that MT5 results equal the model, or any client rule.

## 2. Files (new only; no existing file changed)
- `src/include/H4Bias.mqh` - pure logic, includes `H4Structure.mqh` unchanged (no chart objects, series access, clock, trading API, Sleep).
- `src/tests/T003_LogicTest.mq5` - script (OnStart; install under `MQL5/Scripts/velo_src/tests/` with `include/` as a sibling, as for T002); generated block of 98 cases between BEGIN/END markers; prints DEFERRED lines that are not counted as passes. About 200 KB / 2073 lines.
- `tests/t003_reference_test.py` - Python model, scenarios, `--emit-mql`.
- `tools/t003-static-checks.sh` - static checks with negative controls.

## 3. Implemented proposals
P1 body versus wick (strict). P2 candidate/level from the state known before the evaluated bar, both contexts, consumed candidate kept as the frozen protecting level, retroactive scan at first derivation. P3 one flip trigger (body close beyond the current protecting level), CONTINUATION and INTERNAL_BREAK events, no flip without a level. P4 wick record with `source_wick_time`, `source_wick_known_time`, `detected_at`, `retroactive`; HOLD from `detected_at`. P5 eligible new FVG (candle A open time at or after `source_wick_time`). P6 reconfirmation (touch counted only on bars opening at or after `detected_at`, at the close of the touching candle; INVALID wins). P7 interrupting transitions. P10 start from NONE only (break before seed, CONFLICT not overwritten by the seed on that bar, NO_EVIDENCE). P14 INTERNAL_SWEEP / SWEEP_WAIT / RECONFIRMED (reason INTERNAL), structural logic superseding; the two entry-block flags are only REPORTED (`H3HoldBlock` for S3, `H3SweepBlock` is the technical proposal); nothing acts on them. P11 stateless fixed-depth rebuild: R (default 1000, never below 3 x lookback), warm-up = lookback, check depth = warm-up, hard cap 5000, replays A and B, flags CONVERGED / SEEDED / LIMITED_BY_HISTORY with a reason and the depths used (R requested, R_eff, B depth, warm-up, check depth); wording "converged at depth X vs Y", never "unchanged by more history"; LIMITED reports UNKNOWN and emits no market event; depth-only differences are RE-DERIVATION. BUY and SELL share one symmetric implementation (direction sign).

Owner's two technical requirements: (a) IDs of levels, FVGs and events, and the A/B comparison, use absolute times only (static check 9 and a window-shift test guard this); (b) the replay's event history is separate from the new events for the consumer: `H3BaselineCursor` sets the cursor to the last closed bar so init/restart re-emits no historical event, `H3ConsumeNew` returns only the latest bar's events and only when the state is RELIABLE (status OK / NOTHING_NEW / NOT_RELIABLE / REDERIVED / GAP).

## 4. Test groups (task section 9)
Implemented in the Python model and mirrored in the MQL5 script: 1-8, 10-17, 19, 21 and acceptance cases A, B, B2, C, D, E, plus consumer-event separation and ID stability under window shifts.
DEFERRED, not PASS (printed as DEFERRED in both Python and MQL5): 9 (EA lifecycle and reload), 18 (intrabar overlay P12), 20 (target P13), drawing/panel tests, M5/M15.
Not implemented in this round, by instruction: the visual EA, the intrabar overlay P12, the target P13, M5/M15, orders, position handling.

## 5. Ambiguities that affected the code (each marked `AMBIGUITY n` in `H4Bias.mqh`)
Format: what the code does; the alternative. These are decisions for Codex and the owner, not silent solutions.
1. RECONFIRMED(INTERNAL) is not frozen and keeps deriving the level, while P3 says "frozen during HOLD and RECONFIRMED". Alternative: freeze it when reconfirmed.
2. Touches are evaluated only while HOLD or SWEEP_WAIT; a touch of another eligible FVG during RECONFIRMED is not remembered; after the recorded FVG is lost the fall-back and a new touch can happen on the same bar.
3. When several eligible FVGs are touched on one bar, the one nearest the bar's close is recorded (T002 ordering). The spec names no reference price.
4. A wick bar produces no CONTINUATION or INTERNAL event; those events and sweeps occur only in ACTIVE and SWEEP_WAIT.
5. The dependency anchor is the minimum absolute time of the origin reference, level pivots and sweep; for HOLD and frozen RECONFIRMED only the wick and frozen-level pivots (literal text); moved back by Left x period as the reading of "minus the bars that confirm them".
6. NONE counts as CONVERGED, and any HOLD or frozen RECONFIRMED is CONVERGED even with a seed origin; SEEDED is only for ACTIVE-like states with a seed origin. The spec lists both flags for a seeded HOLD.
7. The consumer emits only the latest bar's events; a cursor older than the previous bar gives GAP and the caller must re-baseline. Alternative: catch up on missed bars.
8. INTERNAL_SWEEP and INTERNAL_BREAK need a defined protecting level (the interior level exists only with it, P14). P3 says internal events continue for a bias without a level.
9. The A/B event comparison covers events from B's first non-warm-up bar onward, by full text; earlier events are ignored.
10. A seed's level is "defined" unless a bar up to t-1 closed beyond it; bar t closing beyond it still seeds and the retroactive scan then removes the level.
11. Equal-price ties pick the earliest pivot.
12. "The low before it" is the immediately preceding extreme in the list, so a minor swing of the extreme kind inside a leg can bound the interval and define the level.
13. "Latest HH/LL" is the latest swing strictly beyond its predecessor; candidates crossed by a close since their pivot are ignored.
14. The sweep wait counts touches from the close of the sweep bar, with candle A at or after the sweep bar's open.
15. After a flip the new bias has no level and origin BREAK; the level is derived at the end of the flip bar, and that retroactive scan includes the flip bar.
16. The retroactive scan covers the bars after the level pivot up to and including the discovery bar; `detected_at = max(level known, wick known, bias start)`; the event is dated by the discovery bar.
17. CONFLICT is unreachable (see section 6); not a decision.
18. NONE_WICK is recorded for P2 levels only.
19. A wick during RECONFIRMED(INTERNAL) or SWEEP_WAIT starts HOLD with the then-current level frozen.

## 6. Contradictions and observations in the specification
- CONFLICT cannot occur: with consumed candidates excluded, the up-level lies strictly above the down-level (confirmation bars lie between them), so one close cannot break both. The agent's search of 120 random series found none; this is evidence, not proof. The branch is kept and unit-tested through the pure resolver `H3P10Resolve`. The spec's CONFLICT rule is therefore dead in practice unless the candidate definitions change.
- P2 against "minor swings never become the level": taken literally, "the low before it" lets a minor swing inside a leg bound the interval (ambiguity 12).
- P3 against P14 on freezing (ambiguity 1).
- Case D ("a break and a seed in opposite directions") is reachable only under the literal "up to t-1" reading with a plateau structure; the test `d_break_vs_seed` with control `d_seed_control` shows it.
- Case B2 ("an FVG formed between the wick and discovery"): in the immediate-discovery variant the wick and discovery are at most two bars apart, so no FVG (A at or after the wick, C = A+2) can complete in between; it is testable only in the late-seed (NONE) variant, which the tests use.

## 7. Risks and what to watch in compilation
Equivalence risks between Python and MQL5: `DoubleToString` versus `'%.2f'` (the emitter refuses prices on an exact rounding tie); `datetime` arithmetic (long casts used); `ArrayCopy`/`ArrayResize` with const sources; struct copies containing strings (copied field-wise).
Size risk: the test script is about 200 KB with one `switch` of 98 cases, 2073 lines, a longest line of 2467 characters, expected strings chunked at 700 characters; MetaEditor limits for this are unknown. If it does not compile, splitting the generated block is the first remedy.
MQL5 constructs not used by the T002 code compiled so far: structure members that are structures (`SH3State` inside `SH3Rep` and `SH3Eval`); `StringGetCharacter` (test script); `ArrayCopy` of `MqlRates` from a const array into a dynamic array; initialiser lists for dynamic arrays and a 2-D `int shifts[6][4] = {{...}}`; several struct declarators in one statement; concatenation chains with string-literal ternaries; dynamic `string` and `datetime` arrays resized inside the logic; passing array elements to non-const struct references; `#define H3_BEAR (-1)` used in arithmetic; chunked `expected += "..."` and the generated block with a `first` offset argument (`T3FillBars(d, count, first, bars)`).

## 8. Next steps
Codex compiles `H4Bias.mqh` and `T003_LogicTest.mq5` in MetaEditor, runs the script in MT5 (expect 0 failed and the five DEFERRED lines; the MQL5 pass count need not equal the Python count, because the Python run has Python-only checks), reviews the nineteen `AMBIGUITY` markers and the contradictions above. No visual EA, overlay, target, M5/M15, order or position code exists; those come after the logic review.
