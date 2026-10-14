"""Disabled-by-default latest-unbroken-fractal candidate PROPOSAL, not MSS approval."""
from dataclasses import dataclass
import math
from t004_reference import Level

@dataclass
class Selection:
    status: str='DISABLED'
    level: object=None
    pivot: int=0
    window_start: int=0
    used: int=0
    ambiguous: int=0

def select_level(bars,n,direction,left=2,right=2,lookback=300,enabled=False):
    out=Selection()
    if not enabled:return out
    out.status='INVALID_INPUT'
    if (direction not in (-1,1) or not 0<=n<=len(bars) or not 1<=left<=10
            or not 1<=right<=10 or not left+right+1<=lookback<=1000):return out
    if not n:
        out.status='SHORT_HISTORY';return out
    start=max(0,n-lookback)
    if any(bars[i].time<=bars[i-1].time for i in range(start+1,n)):return out
    for i in range(n-1,start,-1):
        if bars[i].time-bars[i-1].time!=900:
            start=i;break
    window=bars[start:n]
    for b in window:
        if (b.time<=0 or b.time%900 or not all(math.isfinite(x) for x in (b.high,b.low,b.close))
                or b.low<=0 or b.high<b.low or not b.low<=b.close<=b.high):return out
    out.window_start=window[0].time;out.used=len(window)
    if len(window)<left+right+1:
        out.status='SHORT_HISTORY';return out
    swings=[]
    for i in range(left,len(window)-right):
        x=window[i]
        neighbors=window[i-left:i]+window[i+1:i+right+1]
        hi=all(x.high>b.high for b in neighbors)
        lo=all(x.low<b.low for b in neighbors)
        if hi and lo:
            out.ambiguous+=1;continue
        if (direction==1 and hi) or (direction==-1 and lo):swings.append(i)
    for i in reversed(swings):
        x=window[i];price=x.high if direction==1 else x.low
        if any(direction*(b.close-price)>0 for b in window[i+1:]):continue
        out.pivot=x.time
        out.level=Level('M15S%s%d'%('H' if direction==1 else 'L',x.time),price,window[i+right].time+900)
        out.status='SELECTED';return out
    out.status='NO_LEVEL';return out
