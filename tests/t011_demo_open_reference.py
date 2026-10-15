"""T011 demo open-position guard (Python mirror of src/include/DemoOpenGuard.mqh). FAKE port only.
The locked sequence: acquire -> intent file must not exist -> no position -> no pending order -> precheck -> intent written and read back -> ONE send -> release.
The intent file is never removed by any code; whatever the outcome, the next run is blocked while it exists."""
from dataclasses import dataclass, field

BUY, SELL, UNSET = 1, -1, 0


def direction_ok(d):
    """a known BUY or SELL only (an enum input can carry any integer)"""
    return d in (BUY, SELL) and not isinstance(d, bool)


def intent_name(login, magic):
    return 'VELO_T011_DEMO_OPEN_INTENT_%d_%d.txt' % (login, magic)


def lock_key(login, magic):
    return 'VELO_T011_LOCK_OPEN_%d_%d' % (login, magic)


class Files:
    """sandbox files; fail_write makes the write fail AFTER creating the file (FileOpen creates it), corrupt_readback makes the read-back differ"""

    def __init__(self, fail_write=False, corrupt_readback=False):
        self.data = {}
        self.fail_write = fail_write
        self.corrupt_readback = corrupt_readback
        self.deletes = 0

    def exists(self, n):
        return n in self.data

    def write(self, n, t):
        self.data[n] = '' if self.fail_write else t
        return not self.fail_write

    def read(self, n):
        t = self.data.get(n)
        if t is None:
            return False, ''
        return True, (t + 'x' if self.corrupt_readback else t)


class Locks:
    def __init__(self):
        self.held = set()

    def acquire(self, k):
        if k in self.held:
            return False
        self.held.add(k)
        return True

    def release(self, k):
        self.held.discard(k)


@dataclass
class Port:
    positions: int = 0
    orders: int = 0
    precheck: bool = True
    sends: int = 0
    log: list = field(default_factory=list)
    on_scan: object = None      # callback run at the moment of the position scan (lets a test model a second instance)
    shows_position_after_send: bool = False

    def count_positions(self):
        self.log.append('positions')
        if self.on_scan:
            self.on_scan()
        return self.positions

    def count_orders(self):
        self.log.append('orders')
        return self.orders

    def pre_check(self):
        self.log.append('precheck')
        return self.precheck

    def send(self):
        self.log.append('send')
        self.sends += 1
        if self.shows_position_after_send:
            self.positions += 1


@dataclass
class Outcome:
    sent: bool = False
    sends: int = 0
    status: str = 'BLOCKED'
    reason: str = ''


def run(port, files, locks, key, name, text):
    o = Outcome()
    if not locks.acquire(key):
        o.reason = 'INSTANCE_LOCK_HELD'
        return o
    try:
        if files.exists(name):
            o.reason = 'OPEN_INTENT_EXISTS'
            return o
        n = port.count_positions()
        if n < 0:
            o.reason = 'POSITIONS_UNREADABLE'
            return o
        if n > 0:
            o.reason = 'A_POSITION_WITH_THIS_MAGIC_ALREADY_EXISTS'
            return o
        m = port.count_orders()
        if m < 0:
            o.reason = 'ORDERS_UNREADABLE'
            return o
        if m > 0:
            o.reason = 'AN_ORDER_WITH_THIS_MAGIC_ALREADY_EXISTS'
            return o
        if not port.pre_check():
            o.reason = 'PRECHECK_FAILED'
            return o
        ok = files.write(name, text)
        rok, back = files.read(name)
        if not (ok and rok and back == text):
            o.reason = 'OPEN_INTENT_NOT_VERIFIED'
            return o
        o.sends = 1
        port.send()
        o.sent, o.status, o.reason = True, 'SENT', 'ONE request sent'
        return o
    finally:
        locks.release(key)
