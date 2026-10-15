"""T019 entry LIFECYCLE (Python mirror of src/include/EntryLifecycle.mqh): the part between the placement and the end of a pending order that the orchestrator lacked.
 - a small persistent INDEX of the signal ids that still need attention (open pending orders and unresolved records) + a persistent HALT flag, in one CRC-protected file written through the entry store;
 - STARTUP: reconcile every indexed signal with the EXISTING executor reconcile (never a send); a record that cannot be proven (recovery / blocked / cancel-uncertain / missing / unusable) halts the layer, and the
   halt survives a restart until the owner acknowledges it explicitly (an acknowledgement only drops the unresolved ids from the index; the records stay, so the signals stay consumed);
 - TICK: reconcile again; a fill is recorded and reported as FILLED_UNMANAGED (the T011 registration is NOT connected: a changed stored-SL / ownership contract needs the owner's agreement); cancel events that are due
   (session closed / news blocked / daily limit) cancel an open pending order ONLY when the owner enabled that event; the cancel is the existing TP_CancelDecision + EN_Cancel, one per fresh runtime; any cancel that is not
   confirmed halts. FAKE tickets are never mapped to broker facts: after a restart under the FAKE transport the book is empty, so a placed record cannot be proven and halts - that is the honest answer."""
from dataclasses import dataclass, field

import entry_reference as en
import t005_geometry_reference as tg
import t007_planning_reference as tp
import t011_persist_reference as p

HEADER, VERSION = 'VELO_EO_LIFECYCLE', 1
LC_MAX = 32


def file_name(login):
    return 'VELO_T013_ENTRY_INDEX_%d.state' % login


def lock_key(login):
    return 'VELO_T013_LOCK_INDEX_%d' % login


@dataclass
class State:
    login: int = 0
    halted: str = ''
    ids: list = field(default_factory=list)
    noted: list = field(default_factory=list)       # fills already reported in THIS process (not persisted): a fill is forgotten only on the tick after its report
    lock_owned: bool = False            # exclusive ownership of the index (the existing lock mechanism); every index access needs it
    lock_key: str = ''


def acquire(lockstore, login, st):
    key = lock_key(login)
    if not lockstore.lock(key):
        return False
    st.lock_owned = True
    st.lock_key = key
    return True


def release(lockstore, st):
    """only the owner releases, and only its own key; a refused instance, a forged key or a second release do nothing"""
    if st.lock_owned and st.lock_key:
        lockstore.unlock(st.lock_key)
        st.lock_owned = False


def _owned(st):
    if not st.lock_owned:
        st.halted = st.halted or 'LIFECYCLE_LOCK_NOT_OWNED'
        return False
    return True


def _clean(s):
    return s.replace('\n', ' ').replace('\r', ' ')


def encode(st):
    body = '%s\n%d\nlogin=%d\nhalt=%s\nn=%d\n' % (HEADER, VERSION, st.login, _clean(st.halted), len(st.ids)) + ''.join(i + '\n' for i in st.ids)
    return body + 'CRC=%08X\n' % p.crc32(body)


def decode(text, login):
    """-> (ok, State | reason)"""
    k = text.rfind('CRC=')
    if k < 0 or not text.endswith('\n'):
        return False, 'NO_CRC'
    body, crc = text[:k], text[k + 4:-1]
    if crc != '%08X' % p.crc32(body):
        return False, 'CRC_MISMATCH'
    lines = body.split('\n')[:-1]
    if len(lines) < 5 or lines[0] != HEADER or lines[1] != str(VERSION):
        return False, 'BAD_HEADER'
    if lines[2] != 'login=%d' % login:
        return False, 'LOGIN_MISMATCH'
    if not lines[3].startswith('halt=') or not lines[4].startswith('n='):
        return False, 'BAD_FIELDS'
    try:
        n = int(lines[4][2:])
    except ValueError:
        return False, 'BAD_COUNT'
    if lines[4][2:] != str(n):
        return False, 'BAD_COUNT'
    ids = lines[5:]
    if n != len(ids) or n < 0 or n > LC_MAX or any(not i.strip() for i in ids):
        return False, 'BAD_COUNT'
    return True, State(login, lines[3][5:], ids)


def load(store, login):
    """-> ('NONE' | 'OK' | 'DAMAGED', State)"""
    name = file_name(login)
    if not store.exists(name):
        return 'NONE', State(login)
    ok, text = store.read(name)
    if not ok:
        return 'DAMAGED', State(login, 'LIFECYCLE_STATE_UNREADABLE')
    ok, r = decode(text, login)
    if not ok:
        return 'DAMAGED', State(login, 'LIFECYCLE_STATE_DAMAGED: ' + r)
    return 'OK', r


def save(store, st):
    text = encode(st)
    if not store.write(file_name(st.login), text):
        return False
    ok, back = store.read(file_name(st.login))
    return ok and back == text


def disk_check(store, st):
    """the EXISTING index is validated (readable, CRC, login) before every update and every lifecycle action; no file = the initial creation is allowed. -> (ok, reason)"""
    name = file_name(st.login)
    if not store.exists(name):
        return True, ''
    ok, text = store.read(name)
    if not ok:
        return False, 'LIFECYCLE_STATE_UNREADABLE'
    ok, r = decode(text, st.login)
    if not ok:
        return False, 'LIFECYCLE_STATE_DAMAGED: ' + r
    return True, ''


def _persist(store, st, notes):
    if not _owned(st):
        return False
    ok, why = disk_check(store, st)
    if not ok:
        st.halted = st.halted or why
        notes.append(why)
        return False
    if not save(store, st):
        st.halted = st.halted or 'LIFECYCLE_STATE_NOT_SAVED'
        notes.append('LIFECYCLE_STATE_NOT_SAVED')
        return False
    return True


def register(store, st, signal_id, notes):
    """the id must be indexed (saved and read back) BEFORE the executor can send; any failure halts"""
    if not _owned(st):
        return False
    if not signal_id.strip() or '\n' in signal_id or '\r' in signal_id:
        st.halted = st.halted or 'LIFECYCLE_BAD_SIGNAL_ID'
        return False
    if signal_id not in st.ids:
        if len(st.ids) >= LC_MAX:
            st.halted = st.halted or 'LIFECYCLE_INDEX_FULL'
            return False
        st.ids.append(signal_id)
    return _persist(store, st, notes)


def halt(store, st, reason, notes):
    if not st.halted:
        st.halted = _clean(reason)
    _persist(store, st, notes)


# verdicts of one reconcile
OPEN, CLOSED, FILLED, HALT = 'OPEN', 'CLOSED', 'FILLED', 'HALT'


def verdict(res):
    f = res.final
    if f == en.R_NOCHANGE:
        if res.reason == 'ACTIVE':
            return OPEN
        if res.state == en.ST_FILLED:
            return FILLED
        if res.state in (en.ST_PRECHECK_REFUSED, en.ST_REJECTED, en.ST_CANCELLED, en.ST_EXPIRED):
            return CLOSED
        return HALT
    if f == en.R_PLACED:
        return OPEN
    if f == en.R_FILLED:
        return FILLED
    if f in (en.R_CANCELLED, en.R_EXPIRED):
        return CLOSED
    return HALT


def proposal(cfg, tr, store, login, sid):
    """the fill is NOT registered with T011 (the registration stays the explicit, owner-asserted script): this is the exact input set of that script, read from the executor record,
    with planned geometry diagnostics only; actual registration needs live proof. It writes nothing and calls nothing of T011."""
    ok, text = store.read(en.file_name(login, sid))
    ok, rec = en.decode(text) if ok else (False, None)
    if not ok:
        return 'T011_REGISTRATION: NOT_REGISTRABLE (the executor record is unreadable)'
    sym = tr.read_symbol(rec.symbol)
    why = []
    if rec.state != en.ST_FILLED or rec.linked != 1 or rec.position_id <= 0:
        why.append('FILL_NOT_PROVEN')
    buy = rec.direction == 1
    geo = tg.compute(tg.BUY if buy else tg.SELL, rec.e, rec.s, sym.tick_size, sym.digits, sym.point, sym.stops_level)
    if geo.status != tg.OK:
        why.append('GEOMETRY_REFUSED: ' + geo.status)
    elif abs(rec.tp - geo.level_2r) < sym.tick_size / 2.0:
        why.append('TP_EQUALS_2R: planned entry only; actual fill can change the 2R level')
    elif (buy and rec.tp < geo.level_2r) or (not buy and rec.tp > geo.level_2r):
        why.append('TP_BEFORE_2R: planned entry only; actual fill must be checked')
    out = ('T011_REGISTRATION_INPUTS (the explicit script; the owner asserts the initial SL): InpEnabled=true InpRPolicy=R_GEOM InpEaMagic=%d InpPositionId=%d InpSymbol=%s InpDirection=%s '
           'InpInitialSl=%.8f InpTpPrice=%.8f InpVolumeInitial=%.8f (planned entry %.8f; R_GEOM is derived from the real open price)'
           % (rec.magic, rec.position_id, rec.symbol, 'BUY' if buy else 'SELL', rec.s, rec.tp, rec.volume, rec.e))
    return out + ' | LIVE_CHECK_REQUIRED: actual open price, ownership, initial SL and volume are not proven by this report' + (' | PLANNED_GEOMETRY: ' + '; '.join(why) if why else '')


def _sweep(cfg, tr, store, st, notes):
    """reconcile every indexed id (never a send); returns the ids that are open pending orders"""
    open_ids = []
    for sid in list(st.ids):
        res = en.reconcile(cfg, tr, store, sid)
        v = verdict(res)
        if v == OPEN:
            open_ids.append(sid)
        elif v == HALT:
            notes.append('UNRESOLVED %s: %s %s' % (sid, res.final, res.reason))
            if not st.halted:
                st.halted = 'UNRESOLVED_ENTRY_RECORD: %s' % _clean(res.reason)
        elif v == FILLED and sid not in st.noted:
            notes.append('FILLED_UNMANAGED %s: no T011 registration is connected | %s' % (sid, proposal(cfg, tr, store, st.login, sid)))
            st.noted.append(sid)                  # reported first; forgotten on the next sweep, so a restart in between reports it again
        else:
            st.ids.remove(sid)
            if sid in st.noted:
                st.noted.remove(sid)
    return open_ids


def startup(cfg, tr, store, lockstore, acknowledge=False):
    """-> (State, notes). The instance lock comes first: without it the index is neither read nor written and nothing is sent or cancelled.
    A damaged state file is never overwritten: it halts until the owner removes it. The lock is kept for every run that continues (halted or not) and released by release()."""
    notes = []
    acct = tr.read_account()
    if not acct.read_ok or acct.login <= 0:
        return State(0, 'ACCOUNT_UNREADABLE'), ['ACCOUNT_UNREADABLE']
    st = State(acct.login)
    if not acquire(lockstore, acct.login, st):
        st.halted = 'LIFECYCLE_INSTANCE_LOCK_NOT_ACQUIRED'
        return st, [st.halted]
    kind, loaded = load(store, acct.login)
    loaded.lock_owned, loaded.lock_key = st.lock_owned, st.lock_key
    st = loaded
    if kind == 'DAMAGED':
        notes.append(st.halted)
        return st, notes
    was_halted = st.halted
    _sweep(cfg, tr, store, st, notes)
    if acknowledge and st.halted:
        notes.append('HALT_ACKNOWLEDGED by the owner: %s' % (was_halted or st.halted))
        # only the ids that are still unresolved are dropped from the index; their records stay on disk (the signals stay consumed)
        for sid in list(st.ids):
            if verdict(en.reconcile(cfg, tr, store, sid)) == HALT:
                st.ids.remove(sid)
        st.halted = ''
    if kind == 'OK' or st.ids or st.halted:
        _persist(store, st, notes)
    return st, notes


def due_events(session, news, daily_present, daily_cancel_due):
    """events from facts the existing filters already produce; UNKNOWN never asserts an event"""
    ev = 0
    if session == tp.SESSION_CLOSED:
        ev |= tp.EV_SESSION_END
    if news == tp.NEWS_BLOCKED:
        ev |= tp.EV_NEWS_BLOCK
    if daily_present and daily_cancel_due:
        ev |= tp.EV_DAILY_LIMIT
    return ev


def tick(cfg, tr, store, st, due, enabled):
    """-> notes. Reconcile, then cancel the open pending orders for the events that are due AND enabled."""
    notes = []
    if not st.login:
        return notes
    if not st.lock_owned:
        return notes
    ok, why = disk_check(store, st)
    if not ok:
        st.halted = st.halted or why
        notes.append(why)
        return notes
    before = (list(st.ids), st.halted)
    open_ids = _sweep(cfg, tr, store, st, notes)
    events = due & enabled
    if due and not events:
        notes.append('CANCEL_DUE_NOT_ENABLED events=%d' % due)
    if events:
        for sid in open_ids:
            dec = tp.cancel_decision(True, sid, False, events)
            if dec.status != tp.CANCEL_REQUEST:
                continue
            res = en.cancel(cfg, tr, store, en.Runtime(), sid, dec)
            if res.final == en.R_CANCELLED:
                st.ids.remove(sid)
                notes.append('CANCELLED %s: %s' % (sid, dec.reason))
            else:
                notes.append('CANCEL_NOT_CONFIRMED %s: %s %s' % (sid, res.final, res.reason))
                if not st.halted:
                    st.halted = 'CANCEL_NOT_CONFIRMED: %s' % _clean(res.reason)
    if (list(st.ids), st.halted) != before:
        _persist(store, st, notes)
    return notes


class Guard:
    """the gate's pre-send hook: the index entry is saved and read back BEFORE the executor can create an intent or send"""

    def __init__(self, store, st):
        self.store, self.st = store, st
        self.new = False
        self.calls = 0
        self.notes = []

    def reserve(self, signal_id):
        st = self.st
        self.calls += 1
        if not st.lock_owned:
            st.halted = st.halted or 'LIFECYCLE_LOCK_NOT_OWNED'
            return False, 'LIFECYCLE_LOCK_NOT_OWNED'
        if st.halted:
            return False, 'LIFECYCLE_HALTED: ' + st.halted
        had = signal_id in st.ids
        if not register(self.store, st, signal_id, self.notes):
            return False, 'INDEX_NOT_SAVED: ' + (st.halted or 'unknown')
        self.new = not had
        return True, ''

    def settled(self, signal_id, res):
        """a reservation the executor did not turn into a record (refused before the intent) is released again; a signal with a record stays indexed"""
        st = self.st
        record = self.store.exists(en.file_name(st.login, signal_id))
        if not record and self.new and signal_id in st.ids:
            st.ids.remove(signal_id)
            _persist(self.store, st, self.notes)
        self.new = False

