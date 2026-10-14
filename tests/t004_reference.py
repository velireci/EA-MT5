"""T004 pure observer. Technical proposals, not client-validated entry rules."""
from dataclasses import dataclass
import math

PERIOD = 900
UNSET = 0
A_AT_OR_AFTER_BREAK = 1

@dataclass(frozen=True)
class Context:
    setup: str = ''
    direction: int = 0
    source: str = ''
    fvg: str = ''
    lower: float = 0.0
    upper: float = 0.0
    confirmed: int = 0
    valid_from: int = 0
    ready: bool = False
    reliable: bool = False
    selected: bool = False

@dataclass(frozen=True)
class Level:
    id: str
    price: float
    known: int

@dataclass(frozen=True)
class Bar:
    time: int
    high: float
    low: float
    close: float

@dataclass(frozen=True)
class Event:
    type: str
    time: int
    known: int
    ref: str

@dataclass
class Candidate:
    id: str
    lower: float
    upper: float
    confirmed: int
    returned: bool = False
    invalid: bool = False

class Observer:
    def __init__(self, policy=UNSET):
        self.policy = policy
        self.phase = 'WAIT_CONTEXT'
        self.events = []
        self.candidates = []
        self.context = None
        self.active_from = 0
        self.observed = 0
        self.last = None
        self.last_asof = 0
        self.recent = []
        self.bos_time = 0
        self.bos_known = 0
        self.bos_level = ''
    def _event(self,kind,when,known,ref):
        self.events.append(Event(kind,when,known,ref))
    def _clear_progress(self):
        self.candidates=[]
        self.recent=[]
        self.bos_time=0
        self.bos_known=0
        self.bos_level=''
    def _replay_required(self,known):
        self.last_asof=max(self.last_asof,known)
        self._clear_progress()
        if self.phase!='REPLAY_REQUIRED':
            self._event('REPLAY_REQUIRED',known,known,self.context.setup if self.context else '')
        self.phase='REPLAY_REQUIRED'
        return self.phase
    def set_context(self, context, observed_at):
        if observed_at<self.last_asof:
            return self._replay_required(self.last_asof)
        self.last_asof=observed_at
        c=context
        good=(c.ready and c.reliable and c.selected and c.direction in (-1,1)
              and bool(c.setup) and bool(c.source) and bool(c.fvg)
              and math.isfinite(c.lower) and math.isfinite(c.upper)
              and 0<c.lower<c.upper and 0<c.confirmed<=c.valid_from<=observed_at)
        if good and c==self.context:
            return False
        if self.context is not None:
            self._event('CONTEXT_CLOSED',observed_at,observed_at,self.context.setup)
        self._clear_progress()
        self.last=None
        self.context=c if good else None
        self.observed=observed_at
        self.active_from=max(c.valid_from,observed_at) if good else 0
        self.phase=('WAIT_BREAK' if self.policy==A_AT_OR_AFTER_BREAK else 'WAIT_POLICY') if good else 'WAIT_CONTEXT'
        if good:
            self._event('CONTEXT_OPEN',observed_at,observed_at,c.setup)
        return True
    def step(self, bar, asof, level=None):
        b=bar
        if self.phase=='REPLAY_REQUIRED':return self.phase
        if self.context is None:return 'WAIT_CONTEXT'
        if b.time<=0 or b.time%PERIOD:return 'INVALID_BAR'
        if b.time<self.active_from:return 'BEFORE_CONTEXT'
        if b.time+PERIOD>asof:return 'NOT_CLOSED'
        if asof<self.last_asof:return self._replay_required(self.last_asof)
        if self.last and b.time<=self.last.time:
            if b.time==self.last.time and b==self.last:
                self.last_asof=asof
                return 'DUPLICATE'
            return self._replay_required(asof)
        if (not all(math.isfinite(x) for x in (b.high,b.low,b.close)) or b.low<=0
                or b.high<b.low or not b.low<=b.close<=b.high):return 'INVALID_BAR'
        self.last_asof=asof
        if self.last:
            if b.time!=self.last.time+PERIOD:
                self._clear_progress()
                self.phase='WAIT_BREAK' if self.policy==A_AT_OR_AFTER_BREAK else 'WAIT_POLICY'
                self.last=b;self.recent=[b]
                self._event('DATA_GAP',b.time,b.time+PERIOD,self.context.setup)
                return 'DATA_GAP'
        self.last=b
        self.recent=(self.recent+[b])[-3:]
        if self.policy!=A_AT_OR_AFTER_BREAK:return 'WAIT_POLICY'
        d=self.context.direction
        if not self.bos_time:
            valid_level=(level is not None and bool(level.id) and math.isfinite(level.price)
                         and level.price>0 and 0<level.known<=b.time)
            if valid_level and d*(b.close-level.price)>0:
                self.bos_time=b.time;self.bos_known=b.time+PERIOD;self.bos_level=level.id
                self.phase='WAIT_FVG'
                self._event('BOS_CANDIDATE',b.time,self.bos_known,level.id)
        # Existing gaps are judged before the newly confirmed one is appended.
        for f in self.candidates:
            if f.invalid or b.time<f.confirmed:continue
            if (d>0 and b.close<f.lower) or (d<0 and b.close>f.upper):
                f.invalid=True
                self._event('FVG_INVALIDATED',b.time,b.time+PERIOD,f.id)
            elif not f.returned and b.low<=f.upper and b.high>=f.lower:
                f.returned=True
                self._event('RETURN_OBSERVED',b.time,b.time+PERIOD,f.id)
        if self.bos_time and len(self.recent)==3:
            a,_,c=self.recent
            gap=(d>0 and c.low>a.high) or (d<0 and c.high<a.low)
            if a.time>=self.bos_time and gap:
                lower,upper=(a.high,c.low) if d>0 else (c.high,a.low)
                fid='M15F%d%s'%(a.time,'U' if d>0 else 'D')
                self.candidates.append(Candidate(fid,lower,upper,c.time+PERIOD))
                self._event('FVG_CANDIDATE',c.time,c.time+PERIOD,fid)
        if self.bos_time:
            valid=[f for f in self.candidates if not f.invalid]
            self.phase=('RETURN_OBSERVED' if any(f.returned for f in valid) else
                        'WAIT_RETURN' if valid else 'WAIT_FVG')
        return 'PROCESSED'
