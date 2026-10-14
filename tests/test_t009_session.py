import unittest
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
from t009_session_reference import evaluate, day_changed


def utc(s):
    return int(datetime.fromisoformat(s).replace(tzinfo=timezone.utc).timestamp())


class SessionTests(unittest.TestCase):
    def test_weekday_boundaries(self):
        self.assertTrue(evaluate(utc('2026-10-14T18:29:59'))['open'])
        r=evaluate(utc('2026-10-14T18:30:00'))
        self.assertFalse(r['open'])
        self.assertTrue(r['cancel_pending'])
        self.assertFalse(r['friday_close'])
        self.assertTrue(evaluate(utc('2026-10-13T22:00:00'))['open'])

    def test_friday_and_weekend(self):
        self.assertFalse(evaluate(utc('2026-10-16T18:59:59'))['friday_close'])
        self.assertTrue(evaluate(utc('2026-10-16T19:00:00'))['friday_close'])
        self.assertFalse(evaluate(utc('2026-10-17T10:00:00'))['open'])
        self.assertFalse(evaluate(utc('2026-10-17T10:00:00'))['friday_close'])

    def test_dst_transitions(self):
        for text,offset in [('2026-03-29T00:59:59',3600),('2026-03-29T01:00:00',7200),
                            ('2026-10-25T00:59:59',7200),('2026-10-25T01:00:00',3600)]:
            self.assertEqual(evaluate(utc(text))['offset'],offset)

    def test_day_and_midnight(self):
        t=utc('2026-10-13T22:00:00');r=evaluate(t)
        self.assertEqual(r['day'],20261014)
        self.assertEqual(r['midnight_utc'],t)
        self.assertTrue(day_changed(t-1,t))
        self.assertFalse(day_changed(t,t+1))
        self.assertIsNone(day_changed(t,t-1))

    def test_invalid_config_and_range(self):
        for kwargs in [dict(start=1300,end=1200),dict(end=1441),dict(mask=128),dict(friday=1440)]:
            self.assertEqual(evaluate(utc('2026-10-14T12:00:00'),**kwargs)['status'],'INVALID_INPUT')
        self.assertEqual(evaluate(utc('1995-01-01T00:00:00'))['status'],'UNSUPPORTED_YEAR')

    def test_iana_zoneinfo_independent_oracle(self):
        zone=ZoneInfo('Europe/Tirane')
        start=datetime(2025,1,1,tzinfo=timezone.utc)
        for hour in range(24*365*3):
            dt=start+timedelta(hours=hour);local=dt.astimezone(zone);r=evaluate(int(dt.timestamp()))
            self.assertEqual(r['offset'],int(local.utcoffset().total_seconds()))
            self.assertEqual(r['day'],local.year*10000+local.month*100+local.day)
            midnight=local.replace(hour=0,minute=0,second=0,microsecond=0)
            self.assertEqual(r['midnight_utc'],int(midnight.timestamp()))
            self.assertEqual(r['open'],local.weekday()<5 and local.hour*60+local.minute<1230)

if __name__=='__main__': unittest.main()
