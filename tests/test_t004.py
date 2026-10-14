import unittest
from dataclasses import replace
from t004_reference import Observer, Context, Level, Bar, UNSET, A_AT_OR_AFTER_BREAK

START=14400
def context(**changes):
    return replace(Context('S1',-1,'EXPLICIT_PROPOSAL','H4F1',80,120,START,START,True,True,True),**changes)
def bar(i, high, low, close):
    return Bar(START+i*900,high,low,close)

class TemporalTests(unittest.TestCase):
    def make(self, direction=-1, policy=A_AT_OR_AFTER_BREAK):
        o=Observer(policy)
        o.set_context(context(direction=direction),START)
        return o
    def push(self,o,i,high,low,close,level=None):
        b=bar(i,high,low,close)
        return o.step(b,b.time+900,level)
    def sell(self):
        o=self.make()
        self.push(o,0,101,95,96,Level('L',98,START))
        self.push(o,1,96,89,90)
        self.push(o,2,93,87,88)
        return o
    def test_context_activates_at_h4_close(self):
        o=self.make()
        self.assertEqual(o.phase,'WAIT_BREAK')
        self.assertEqual(o.step(bar(-1,101,95,96),START,Level('L',98,START-900)),'BEFORE_CONTEXT')
        self.assertEqual(len(o.events),1)
    def test_default_policy_cannot_produce_break(self):
        o=self.make(policy=UNSET)
        self.push(o,0,101,95,96,Level('L',98,START))
        self.assertEqual(o.phase,'WAIT_POLICY')
        self.assertNotIn('BOS_CANDIDATE',[e.type for e in o.events])
    def test_unselected_source_blocks(self):
        o=Observer(A_AT_OR_AFTER_BREAK)
        o.set_context(context(selected=False),START)
        self.assertEqual(o.phase,'WAIT_CONTEXT')
    def test_unreliable_context_revokes_progress(self):
        o=self.sell()
        o.set_context(context(reliable=False),START+2700)
        self.assertEqual(o.phase,'WAIT_CONTEXT')
        self.assertEqual(o.candidates,[])
    def test_no_bos_without_level(self):
        o=self.make()
        self.push(o,0,101,95,96)
        self.assertEqual(o.phase,'WAIT_BREAK')
    def test_level_must_be_known_before_bar(self):
        o=self.make()
        self.push(o,0,101,95,96,Level('future',98,START+900))
        self.assertEqual(o.phase,'WAIT_BREAK')
    def test_wick_and_equal_close_are_not_body_break(self):
        o=self.make()
        self.push(o,0,101,95,99,Level('L',98,START))
        self.push(o,1,100,95,98,Level('L',98,START))
        self.assertEqual(o.phase,'WAIT_BREAK')
        self.push(o,2,99,95,97,Level('L',98,START))
        self.assertEqual(o.phase,'WAIT_FVG')
    def test_forming_bar_does_not_advance(self):
        o=self.make()
        self.assertEqual(o.step(bar(0,101,95,96),START+899,Level('L',98,START)),'NOT_CLOSED')
        self.assertEqual(o.phase,'WAIT_BREAK')
        self.push(o,0,101,95,96,Level('L',98,START))
        self.assertEqual(o.phase,'WAIT_FVG')
    def test_fvg_confirmation_is_not_own_return(self):
        o=self.sell()
        self.assertEqual(o.phase,'WAIT_RETURN')
        self.assertEqual((o.candidates[0].lower,o.candidates[0].upper),(93,95))
        self.assertEqual([(e.type,e.known) for e in o.events], [('CONTEXT_OPEN',START),('BOS_CANDIDATE',START+900),('FVG_CANDIDATE',START+2700)])
    def test_return_observed_only_after_confirmation(self):
        o=self.sell()
        self.push(o,3,94,86,90)
        self.assertEqual(o.phase,'RETURN_OBSERVED')
        self.push(o,4,94,86,90)
        self.assertEqual(sum(e.type=='RETURN_OBSERVED' for e in o.events),1)
    def test_invalidation_wins_over_touch(self):
        o=self.sell()
        self.push(o,3,97,90,96)
        self.assertEqual(o.phase,'WAIT_FVG')
        self.assertNotIn('RETURN_OBSERVED',[e.type for e in o.events])
        self.assertEqual(o.events[-1].type,'FVG_INVALIDATED')
    def test_bull_mirror(self):
        o=self.make(direction=1)
        self.push(o,0,105,99,104,Level('H',102,START))
        self.push(o,1,111,104,110)
        self.push(o,2,113,107,112)
        self.assertEqual((o.candidates[0].lower,o.candidates[0].upper),(105,107))
        self.push(o,3,114,106,110)
        self.assertEqual(o.phase,'RETURN_OBSERVED')
    def test_changed_context_clears_candidates(self):
        o=self.sell()
        o.set_context(context(fvg='H4F2',valid_from=START+2700),START+2700)
        self.assertEqual(o.phase,'WAIT_BREAK')
        self.assertEqual(o.candidates,[])
    def test_identical_context_does_not_reset(self):
        o=self.sell()
        o.set_context(context(),START+2700)
        self.assertEqual(o.phase,'WAIT_RETURN')
    def test_late_context_excludes_elapsed_m15(self):
        o=Observer(A_AT_OR_AFTER_BREAK)
        o.set_context(context(),START+1800)
        self.assertEqual(o.step(bar(1,101,95,96),START+2700,Level('L',98,START)),'BEFORE_CONTEXT')
    def test_duplicate_is_idempotent(self):
        o=self.sell(); n=len(o.events)
        self.assertEqual(o.step(bar(2,93,87,88),START+2700),'DUPLICATE')
        self.assertEqual(len(o.events),n)
    def test_changed_duplicate_requires_replay(self):
        o=self.sell()
        self.assertEqual(o.step(bar(2,94,87,88),START+2700),'REPLAY_REQUIRED')
        self.assertEqual(o.phase,'REPLAY_REQUIRED')
        self.assertEqual(o.candidates,[])
    def test_out_of_order_requires_replay(self):
        o=self.sell()
        self.assertEqual(o.step(bar(1,96,89,90),START+3600),'REPLAY_REQUIRED')
    def test_gap_discards_bos_and_fvg_progress(self):
        o=self.sell()
        self.assertEqual(self.push(o,4,94,86,90,Level('L',98,START)),'DATA_GAP')
        self.assertEqual(o.phase,'WAIT_BREAK')
        self.assertEqual(o.candidates,[])
    def test_invalid_ohlc_does_not_advance(self):
        o=self.make()
        self.assertEqual(self.push(o,0,90,95,96),'INVALID_BAR')
        self.assertEqual(o.phase,'WAIT_BREAK')
    def test_invalid_context_cannot_activate(self):
        for c in [context(direction=0),context(confirmed=START+900),context(upper=79),context(source='')]:
            o=Observer(A_AT_OR_AFTER_BREAK);o.set_context(c,START)
            self.assertEqual(o.phase,'WAIT_CONTEXT')
    def test_fvg_before_bos_cannot_qualify(self):
        o=self.make()
        self.push(o,0,101,95,96)
        self.push(o,1,96,89,90)
        self.push(o,2,93,87,88,Level('L',89,START))
        self.assertEqual(o.phase,'WAIT_FVG')
        self.assertEqual(o.candidates,[])
    def test_prefix_causality(self):
        data=[bar(0,101,95,96),bar(1,96,89,90),bar(2,93,87,88),bar(3,94,86,90)]
        o=self.make(); snapshots=[]
        for b in data:
            o.step(b,b.time+900,Level('L',98,START));snapshots.append(list(o.events))
        for n in range(1,len(data)+1):
            p=self.make()
            for b in data[:n]:p.step(b,b.time+900,Level('L',98,START))
            self.assertEqual(p.events,snapshots[n-1])
    def test_unconfigured_context_cannot_activate(self):
        o=Observer(A_AT_OR_AFTER_BREAK)
        o.set_context(Context(),START)
        self.assertEqual(o.phase,'WAIT_CONTEXT')
    def test_multiple_fvgs_are_not_silently_selected(self):
        o=self.sell()
        self.push(o,3,88,84,85)
        self.assertEqual([(f.lower,f.upper) for f in o.candidates],[(93,95),(88,89)])
        self.push(o,4,94,86,88)
        self.assertEqual(sum(e.type=='RETURN_OBSERVED' for e in o.events),2)
        self.assertTrue(all(f.returned for f in o.candidates))
    def test_close_equal_far_edge_is_not_invalid(self):
        o=self.sell()
        self.push(o,3,96,90,95)
        self.assertEqual(o.phase,'RETURN_OBSERVED')
        self.assertFalse(o.candidates[0].invalid)
    def test_bull_invalidation_precedes_touch(self):
        o=self.make(direction=1)
        self.push(o,0,105,99,104,Level('H',102,START))
        self.push(o,1,111,104,110)
        self.push(o,2,113,107,112)
        self.push(o,3,110,103,104)
        self.assertEqual(o.phase,'WAIT_FVG')
        self.assertEqual(sum(e.type=='RETURN_OBSERVED' for e in o.events),0)
    def test_context_clock_cannot_go_backwards(self):
        o=self.sell()
        o.set_context(context(),START)
        self.assertEqual(o.phase,'REPLAY_REQUIRED')
    def test_bar_clock_cannot_go_backwards(self):
        o=self.sell()
        self.assertEqual(o.step(bar(3,94,86,90),START+2600),'NOT_CLOSED')
        self.assertEqual(o.phase,'WAIT_RETURN')
    def test_replay_latch_is_not_healed_by_same_context(self):
        o=self.sell()
        o.step(bar(2,94,87,88),START+2700)
        o.set_context(context(),START+2700)
        self.assertEqual(o.phase,'REPLAY_REQUIRED')
    def test_direction_source_change_starts_new_epoch(self):
        o=self.sell()
        o.set_context(context(source='OTHER_PROPOSAL'),START+2700)
        self.assertEqual(o.phase,'WAIT_BREAK')
        self.assertEqual(o.candidates,[])
    def test_invalid_revision_clears_progress_and_latches(self):
        for i in (1,2):
            o=self.sell()
            self.assertEqual(o.step(bar(i,86,87,88),START+2700),'REPLAY_REQUIRED')
            self.assertEqual(o.candidates,[])
            self.assertEqual(self.push(o,3,94,86,90),'REPLAY_REQUIRED')
            self.assertNotIn('RETURN_OBSERVED',[e.type for e in o.events])
    def test_revision_advances_clock_before_context_replacement(self):
        o=self.sell()
        self.assertEqual(o.step(bar(2,86,87,88),START+3600),'REPLAY_REQUIRED')
        o.set_context(context(setup='S2'),START+2700)
        self.assertEqual(o.phase,'REPLAY_REQUIRED')
        self.assertEqual(o.last_asof,START+3600)

if __name__=='__main__':unittest.main(verbosity=2)
