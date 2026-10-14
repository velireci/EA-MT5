"""UTC -> Tirane session snapshot using current EU recurrence, years1996..2099.
No clock reads, server offset inference, account state or orders.
"""
from datetime import datetime, timezone, timedelta


def _offset(dt):
    def edge(month):
        last=datetime(dt.year,month,31,1,tzinfo=timezone.utc)
        return last-timedelta(days=(last.weekday()+1)%7)
    return 7200 if edge(3)<=dt<edge(10) else 3600


def evaluate(utc,start=0,end=1230,mask=62,friday=1260,friday_enabled=True):
    fail={'status':'INVALID_INPUT'}
    if not isinstance(utc,int) or utc<=0 or not all(isinstance(x,int) for x in (start,end,mask,friday)):
        return fail
    if not (0<=start<end<=1440 and 0<=mask<=127 and 0<=friday<1440):
        return fail
    try: dt=datetime.fromtimestamp(utc,timezone.utc)
    except (ValueError,OverflowError,OSError): return fail
    if not 1996<=dt.year<=2099: return {'status':'UNSUPPORTED_YEAR'}
    offset=_offset(dt);local=dt+timedelta(seconds=offset)
    if not 1996<=local.year<=2099: return {'status':'UNSUPPORTED_YEAR'}
    dow=(local.weekday()+1)%7;minute=local.hour*60+local.minute
    close=friday_enabled and dow==5 and minute>=friday
    opened=bool(mask&(1<<dow)) and start<=minute<end and not close
    midnight=local.replace(hour=0,minute=0,second=0,microsecond=0)
    guess=midnight-timedelta(hours=1)
    midnight_utc=int(midnight.timestamp())-_offset(guess)
    return dict(status='OK',offset=offset,local=int(local.timestamp()),day=local.year*10000+local.month*100+local.day,
                midnight_utc=midnight_utc,open=opened,cancel_pending=not opened,friday_close=close)


def day_changed(previous,current):
    a=evaluate(previous);b=evaluate(current)
    if current<previous or a['status']!='OK' or b['status']!='OK': return None
    return a['day']!=b['day']
