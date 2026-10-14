import unittest
from dataclasses import replace
from t004_reference import Bar,Observer,A_AT_OR_AFTER_BREAK
from t004_selector_reference import select_level
from test_t004 import context,START

def fixture(direction=1):
    rows=[(96,90,93),(98,91,94),(100,92,95),(97,90,93),(96,89,92),
          (101,95,100.5),(107,100,105),(110,103,108),(109,102,104)]
    if direction==-1:rows=[(200-l,200-h,200-c) for h,l,c in rows]
    return [Bar(START+i*900,h,l,c) for i,(h,l,c) in enumerate(rows)]

class SelectorTests(unittest.TestCase):
    def select(self,bars,n=None,d=1,**kw):
        return select_level(bars,len(bars) if n is None else n,d,enabled=True,**kw)
    def test_disabled_default_cannot_supply_a_level(self):
        s=select_level(fixture(),5,1)
        self.assertEqual(s.status,'DISABLED');self.assertIsNone(s.level)
    def test_buy_candidate_known_at_crossing_bar_open(self):
        s=self.select(fixture(),5)
        self.assertEqual(s.status,'SELECTED')
        self.assertEqual((s.level.price,s.level.known,s.pivot),(100,START+4500,START+1800))
    def test_sell_mirror(self):
        s=self.select(fixture(-1),5,d=-1)
        self.assertEqual(s.status,'SELECTED')
        self.assertEqual((s.level.price,s.level.known),(100,START+4500))
    def test_current_crossing_bar_is_excluded_by_prefix(self):
        bars=fixture()
        self.assertEqual(self.select(bars,5).status,'SELECTED')
        self.assertEqual(self.select(bars,6).status,'NO_LEVEL')
    def test_unconfirmed_swing_is_not_usable(self):
        self.assertEqual(self.select(fixture(),4).status,'SHORT_HISTORY')
    def test_wick_does_not_consume(self):
        b=fixture();b[5]=replace(b[5],close=99)
        self.assertEqual(self.select(b,6).level.price,100)
    def test_equal_close_does_not_consume(self):
        b=fixture();b[5]=replace(b[5],close=100)
        self.assertEqual(self.select(b,6).level.price,100)
    def test_body_close_consumes_before_context_activation(self):
        self.assertEqual(self.select(fixture(),6).status,'NO_LEVEL')
    def test_ties_do_not_form_strict_swing(self):
        b=fixture();b[1]=replace(b[1],high=100)
        self.assertEqual(self.select(b,5).status,'NO_LEVEL')
    def test_ambiguous_high_low_is_excluded(self):
        b=fixture();b[2]=replace(b[2],low=80)
        s=self.select(b,5)
        self.assertEqual((s.status,s.ambiguous),('NO_LEVEL',1))
    def test_gap_does_not_form_swing_across_missing_bars(self):
        b=fixture();b=[replace(x,time=x.time+900 if i>=3 else x.time) for i,x in enumerate(b)]
        self.assertEqual(self.select(b,5).status,'SHORT_HISTORY')
    def test_nonmonotonic_history_rejected(self):
        b=fixture();b[3]=replace(b[3],time=b[2].time)
        self.assertEqual(self.select(b,5).status,'INVALID_INPUT')
    def test_malformed_hlc_rejected(self):
        b=fixture();b[3]=replace(b[3],close=200)
        self.assertEqual(self.select(b,5).status,'INVALID_INPUT')
    def test_bad_parameters_rejected(self):
        for kw in ({'left':0},{'right':11},{'lookback':4},{'lookback':1001}):
            self.assertEqual(self.select(fixture(),5,**kw).status,'INVALID_INPUT')
        self.assertEqual(self.select(fixture(),5,d=0).status,'INVALID_INPUT')
        self.assertEqual(self.select(fixture(),10).status,'INVALID_INPUT')
    def test_prefix_does_not_read_future_nan(self):
        b=fixture();b[5]=replace(b[5],high=float('nan'))
        self.assertEqual(self.select(b,5).level.price,100)
    def test_selector_does_not_mutate_input(self):
        b=fixture();before=list(b);self.select(b,5)
        self.assertEqual(b,before)
    def test_full_flow_both_directions_uses_precontext_level(self):
        for d in (1,-1):
            b=fixture(d)
            o=Observer(A_AT_OR_AFTER_BREAK)
            o.set_context(context(direction=d,valid_from=START+4500),START+4500)
            for i in range(5,len(b)):
                s=self.select(b,i,d=d)
                o.step(b[i],b[i].time+900,s.level)
            self.assertEqual(o.phase,'RETURN_OBSERVED')
            self.assertEqual([e.type for e in o.events],['CONTEXT_OPEN','BOS_CANDIDATE','FVG_CANDIDATE','RETURN_OBSERVED'])
    def test_continuation_with_no_prior_level_cannot_infer_bos(self):
        b=fixture();o=Observer(A_AT_OR_AFTER_BREAK)
        o.set_context(context(direction=1,valid_from=START+5400),START+5400)
        s=self.select(b,6)
        o.step(b[6],b[6].time+900,s.level)
        self.assertEqual(o.phase,'WAIT_BREAK')
    def test_latest_pivot_not_highest_price_then_older_unbroken_fallback(self):
        rows=[(104,95,100),(106,96,101),(110,97,102),(105,94,99),(104,93,98),
              (95,90,93),(96,91,94),(100,92,95),(97,90,93),(96,89,92),(104,97,103)]
        b=[Bar(START+i*900,h,l,c) for i,(h,l,c) in enumerate(rows)]
        self.assertEqual(self.select(b,10).level.price,100)
        self.assertEqual(self.select(b,11).level.price,110)
    def test_id_and_known_time_do_not_depend_on_window_index(self):
        b=fixture()
        prior=[Bar(START-1800,94,88,90),Bar(START-900,95,89,91)]
        a=self.select(b,5);p=self.select(prior+b,7)
        self.assertEqual(a.level,p.level)
    def test_shorter_lookback_reports_only_covered_swings(self):
        b=fixture();b[5]=replace(b[5],close=99)
        self.assertEqual(self.select(b,6).status,'SELECTED')
        s=self.select(b,6,lookback=5)
        self.assertEqual((s.status,s.window_start,s.used),('NO_LEVEL',START+900,5))
    def test_recovery_after_gap_uses_only_new_contiguous_segment(self):
        b=fixture()[:5]
        b+= [replace(x,time=x.time+9000) for x in fixture()[:5]]
        self.assertEqual(self.select(b,9).status,'SHORT_HISTORY')
        s=self.select(b,10)
        self.assertEqual((s.status,s.window_start,s.used,s.pivot),('SELECTED',START+9000,5,START+10800))
    def test_asymmetric_left_right_uses_actual_confirmation_close(self):
        b=fixture();b[5]=Bar(b[5].time,95,88,90)
        self.assertEqual(self.select(b,5,left=1,right=3).status,'NO_LEVEL')
        s=self.select(b,6,left=1,right=3)
        self.assertEqual((s.level.price,s.level.known,s.pivot),(100,START+5400,START+1800))

if __name__=='__main__':unittest.main(verbosity=2)
