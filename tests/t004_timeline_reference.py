"""Pure chronological replay of supplied H4 context snapshots and M15 bars."""
from dataclasses import dataclass
import math
from t004_reference import Observer
from t004_selector_reference import select_level

@dataclass
class Snapshot:
    known: int
    context: object

@dataclass
class Timeline:
    observer: object
    status: str='EMPTY'
    processed: int=0
    bos_price: float=0.0

@dataclass
class ReplayCache:
    built: bool=False
    cut: int=0

def reset_replay(timeline,cache):
    timeline.observer=Observer()
    timeline.status='RESET';timeline.processed=0;timeline.bos_price=0
    cache.built=False;cache.cut=0

def needs_build(historical,built,cut,previous,h4_changed=False,m15_changed=False):
    return not built or cut!=previous or (not historical and (h4_changed or m15_changed))

def replay_timeline(bars,updates,start,asof,selector=False,policy=0,left=2,right=2,lookback=300):
    out=Timeline(Observer(policy));o=out.observer
    closed=[b for b in bars if b.time+900<=asof]
    usable=[u for u in updates if u.known<=asof]
    if any(u.known<=0 or (i and u.known<=usable[i-1].known) for i,u in enumerate(usable)):
        out.status='INVALID_UPDATES';return out
    if any(b.time<=0 or b.time%900 or not all(math.isfinite(x) for x in (b.high,b.low,b.close))
           or b.low<=0 or not b.low<=b.close<=b.high or (i and b.time<=closed[i-1].time)
           for i,b in enumerate(closed)):
        out.status='INVALID_M15';return out
    first=next((i for i,b in enumerate(closed) if b.time>=start),len(closed))
    observed=closed[first].time if first<len(closed) else asof
    j=0
    while j<len(usable) and usable[j].known<=observed:j+=1
    if j:o.set_context(usable[j-1].context,observed)
    for i in range(first,len(closed)):
        b=closed[i];close=b.time+900
        while j<len(usable) and usable[j].known<=close:
            o.set_context(usable[j].context,usable[j].known);j+=1
        s=select_level(closed,i,o.context.direction if o.context else 0,left,right,lookback,
                       selector and o.context is not None)
        previous=o.bos_time
        o.step(b,close,s.level)
        if not o.bos_time:out.bos_price=0
        elif not previous:out.bos_price=s.level.price
        out.processed+=1
    while j<len(usable):
        o.set_context(usable[j].context,usable[j].known);j+=1
        if not o.bos_time:out.bos_price=0
    out.status='OK' if out.processed else 'EMPTY'
    return out
