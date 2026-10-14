"""ISOLATED PROTOTYPE (scratchpad, not product): internal-liquidity per-level selection, patched into a COPY of
the model as it was BEFORE revision 14 (baseline_t003_reference_d7a201f.py = tests/t003_reference_test.py at
commit d7a201f, the single-candidate selector). Revision 14 put this rule into tests/t003_reference_test.py itself,
so the prototype can no longer patch that file; the frozen baseline keeps the prototype and the comparison with the
old behaviour reproducible. The frozen baseline is also registered unpatched as sys.modules['t003_baseline'].
Nothing here is imported by the product."""
import sys, types
import os
HERE=os.path.dirname(os.path.abspath(__file__))
TESTS=os.path.normpath(os.path.join(HERE,'..','..','tests'))
SRC=os.path.join(HERE,'baseline_t003_reference_d7a201f.py')
text=open(SRC,encoding='utf-8').read()
sys.path.insert(0, TESTS)   # the baseline imports t002_reference_test from tests/
base=types.ModuleType('t003_baseline'); base.__file__=os.path.join(TESTS,'t003_baseline_virtual.py'); base.__name__='t003_baseline'
sys.modules['t003_baseline']=base
exec(compile(text,'t003_baseline','exec'),base.__dict__)

# (a) replace the single-candidate interior block of bias_step
a=text.index("    if st.has_level and st.has_lint and (not st.li_consumed):")
b=text.index("    return False\n\n\ndef dist_to_zone")
text=text[:a]+"    proto_internal(t, bars, sw, fv, p, st, tracks, events, open_t, close_t, d, s, ph)\n"+text[b:]
# (b) state key: LI element becomes the proto key
old="        ('%s@%s/%d' % (st.li_id, pf(st.li_price), 1 if st.li_consumed else 0)) if st.has_lint else '-',"
assert old in text
text=text.replace(old,"        (getattr(st, 'liq_key', '-') or '-'),")

PROTO='''
# ---------------- PROTOTYPE internal liquidity (per-level, historical consumption) ----------------
def liq_id(s, x):
    return ('IH' if s > 0 else 'IL') + ts(x.pivot_time)

def liq_scope(st, sw, p, s, at_time):
    """confirmed swings usable at the bar opening at at_time, with pivot later than the CURRENT protecting
    level's pivot and strictly inside (beyond the level = not interior). Consumption is NOT part of the scope."""
    out = []
    for x in sw:
        if x.is_high == (s > 0) and x.confirm_time <= at_time and x.pivot_time > st.lv_pivot \\
                and s * (x.price - st.lv_price) < 0:
            out.append(x)
    return out

def liq_first_cross(st, bars, p, x, upto):
    """first bar index j (x.index+right+1 <= j <= upto) whose adverse extreme is STRICTLY beyond x; None if none.
    The scan starts at the first bar usable after the confirmation of x, whatever the scope at the time:
    a change of the protecting level cannot resurrect a consumed swing. Cached per replay (st.liq_cache)."""
    s = 1 if x.is_high else -1
    cache = st.__dict__.setdefault('liq_cache', {})
    scanned, first = cache.get(x.pivot_time, (x.index + p.right, None))
    if first is None and scanned < upto:
        for j in range(scanned + 1, upto + 1):
            if s * (adverse_ext(bars[j], s) - x.price) > 0:
                first = j
                break
        scanned = upto
        cache[x.pivot_time] = (scanned, first)
    return first

def proto_internal(t, bars, sw, fv, p, st, tracks, events, open_t, close_t, d, s, ph):
    if not st.has_level:
        return
    bar = bars[t]
    swept = []
    broke = []
    for x in liq_scope(st, sw, p, s, open_t):
        if liq_first_cross(st, bars, p, x, t - 1) is not None:
            continue                                    # consumed earlier (history from its confirmation)
        if s * (adverse_ext(bar, s) - x.price) > 0:      # strictly beyond; a touch (==) is NOT a crossing
            st.liq_cache[x.pivot_time] = (t, t)
            if s * (bar.close - x.price) > 0:
                broke.append(x)                         # body beyond this level
            else:
                swept.append(x)                         # wick beyond, close not beyond
    broke.sort(key=lambda x: x.pivot_time)
    swept.sort(key=lambda x: (s * x.price, x.pivot_time))
    for x in broke:
        events.append(Event(EV_INT_BREAK, open_t, liq_id(s, x), 'dir=%s;lint=%s' % (dir_name(d), liq_id(s, x))))
    if swept:
        top = swept[-1]                                   # the most adverse level swept
        if ph == 'ACTIVE' or ph == 'SWEEP_WAIT':
            restart = (ph == 'SWEEP_WAIT')
            new_id = 'SWEEP@%s#%s' % (ts(open_t), st.lv_id)
            setup_ended(st, open_t, END_REPLACED, events, new_id)
            st.phase = 'SWEEP_WAIT'
            st.setup_id = new_id
            st.setup_type = 'SWEEP'
            st.snap_id = st.lv_id
            st.snap_price = st.lv_price
            st.snap_known = st.lv_known
            st.has_wick = False
            st.wk_retro = False
            st.sweep_time = open_t
            st.src_time = open_t
            st.wait_start = close_t
            st.rec_id = ''
            st.rec_from = 0
            st.recon_reason = ''
            build_tracks(st, tracks, fv, bars, t, d == BULL)
            made = 1
        else:
            made = 0
        for x in swept:
            events.append(Event(EV_INT_SWEEP, open_t, liq_id(s, x),
                                'dir=%s;lint=%s;sweep=%s;setup=%d;top=%d' % (dir_name(d), liq_id(s, x), ts(open_t),
                                                                              made if x is top else 0, 1 if x is top else 0)))

_orig_process_bar = process_bar
def process_bar(t, bars, sw, fv, p, st, tracks, events):
    _orig_process_bar(t, bars, sw, fv, p, st, tracks, events)
    key = '-'
    if st.dir != 0 and st.has_level:
        s = -st.dir
        close_t = bars[t].time + p.period
        ids = []
        for x in liq_scope(st, sw, p, s, close_t):
            if liq_first_cross(st, bars, p, x, t) is None:
                ids.append(liq_id(s, x))
        key = ','.join(sorted(ids)) if ids else '-'
    st.liq_key = key
'''
# insert PROTO after the definition of process_bar (before pre_wick_ids)
k=text.index("def pre_wick_ids(")
text=text[:k]+PROTO+"\n\n"+text[k:]
mod=types.ModuleType('t003_proto')
mod.__file__=os.path.join(TESTS,'t003_proto_virtual.py')
mod.__name__='t003_proto'
sys.modules['t003_proto']=mod
exec(compile(text,'t003_proto','exec'),mod.__dict__)
