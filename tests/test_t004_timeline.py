import unittest
from dataclasses import replace
from t004_reference import Context,A_AT_OR_AFTER_BREAK
from t004_timeline_reference import Snapshot,replay_timeline,needs_build,ReplayCache,reset_replay
from test_t004 import START,context
from test_t004_selector import fixture

class TimelineTests(unittest.TestCase):
    def test_chart_reinitialization_cannot_keep_old_success_cache(self):
        t=self.replay(fixture(),[Snapshot(START,context(direction=1))])
        cache=ReplayCache(True,START+8100)
        reset_replay(t,cache)
        self.assertTrue(needs_build(True,cache.built,START+8100,cache.cut))
        self.assertEqual((t.observer.phase,t.bos_price,t.processed,t.status),('WAIT_CONTEXT',0,0,'RESET'))
        self.assertEqual((t.observer.events,t.observer.candidates),([],[]))
    def test_live_h4_change_rebuilds_even_at_same_m15_cut(self):
        self.assertTrue(needs_build(False,True,START,START,True,False))
        self.assertFalse(needs_build(False,True,START,START,False,False))
        self.assertFalse(needs_build(True,True,START,START,True,True))
        self.assertTrue(needs_build(True,False,START,START,False,False))
    def replay(self,b,updates,start=START+4500,asof=START+8100,selector=True,policy=A_AT_OR_AFTER_BREAK):
        return replay_timeline(b,updates,start,asof,selector,policy)
    def test_both_full_paths_from_h4_snapshots(self):
        for d in (1,-1):
            t=self.replay(fixture(d),[Snapshot(START,context(direction=d))])
            self.assertEqual((t.status,t.processed,t.observer.phase,t.bos_price),('OK',4,'RETURN_OBSERVED',100))
    def test_h4_reconfirmation_at_close_excludes_inside_m15_bos(self):
        c=context(direction=1,valid_from=START+5400)
        t=self.replay(fixture(),[Snapshot(START+5400,c)])
        self.assertEqual(t.observer.phase,'WAIT_BREAK')
        self.assertNotIn('BOS_CANDIDATE',[e.type for e in t.observer.events])
    def test_h4_revocation_wins_at_same_return_close(self):
        c=context(direction=1)
        t=self.replay(fixture(),[Snapshot(START,c),Snapshot(START+8100,replace(c,ready=False))])
        self.assertEqual(t.observer.phase,'WAIT_CONTEXT')
        self.assertNotIn('RETURN_OBSERVED',[e.type for e in t.observer.events])
    def test_h4_update_after_last_m15_is_applied(self):
        c=context(direction=1)
        t=self.replay(fixture()[:8],[Snapshot(START,c),Snapshot(START+8100,replace(c,ready=False))])
        self.assertEqual(t.observer.phase,'WAIT_CONTEXT')
    def test_final_h4_snapshot_is_not_used_in_the_past(self):
        c=context(direction=1,valid_from=START+7200)
        t=self.replay(fixture(),[Snapshot(START+7200,c)])
        self.assertEqual(t.observer.phase,'WAIT_BREAK')
        self.assertNotIn('BOS_CANDIDATE',[e.type for e in t.observer.events])
    def test_disabled_choices_do_not_emit_candidates(self):
        for selected,selector,policy in [(False,True,A_AT_OR_AFTER_BREAK),(True,False,A_AT_OR_AFTER_BREAK),(True,True,0)]:
            t=self.replay(fixture(),[Snapshot(START,context(direction=1,selected=selected))],selector=selector,policy=policy)
            self.assertNotIn('BOS_CANDIDATE',[e.type for e in t.observer.events])
    def test_future_snapshot_and_unclosed_bar_are_not_used(self):
        c=context(direction=1)
        t=self.replay(fixture(),[Snapshot(START,c),Snapshot(START+9000,Context())],asof=START+7199)
        self.assertEqual(t.observer.phase,'WAIT_FVG')
        self.assertEqual(t.processed,2)
    def test_h4_snapshot_time_order_is_validated(self):
        t=self.replay(fixture(),[Snapshot(START+900,context()),Snapshot(START,context())])
        self.assertEqual(t.status,'INVALID_UPDATES')
        self.assertEqual(t.observer.events,[])
    def test_replay_does_not_present_earlier_context_activation(self):
        t=self.replay(fixture(),[Snapshot(START,context(direction=1))])
        self.assertEqual(t.observer.events[0].known,START+4500)

if __name__=='__main__':unittest.main(verbosity=2)
