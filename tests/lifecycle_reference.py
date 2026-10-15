"""T019 entry LIFECYCLE (Python mirror of src/include/EntryLifecycle.mqh): the part between the placement and the end of a pending order that the orchestrator lacked.
 - a small persistent INDEX of the signal ids that still need attention (open pending orders and unresolved records) + a persistent HALT flag, in one CRC-protected file written through the entry store;
 - STARTUP: reconcile every indexed signal with the EXISTING executor reconcile (never a send); a record that cannot be proven (recovery / blocked / cancel-uncertain / missing / unusable) halts the layer, and the
   halt survives a restart until the owner acknowledges it explicitly (an acknowledgement only drops the unresolved ids from the index; the records stay, so the signals stay consumed);
 - TICK: reconcile again; a fill is recorded and reported as FILLED_UNMANAGED (the T011 registration is NOT connected: a changed stored-SL / ownership contract needs the owner's agreement); cancel events that are due
   (session closed / news blocked / daily limit) cancel an open pending order ONLY when the owner enabled that event; the cancel is the existing TP_CancelDecision + EN_Cancel, one per fresh runtime; any cancel that is not
   confirmed halts. FAKE tickets are never mapped to broker facts: after a restart under the FAKE transport the book is empty, so a placed record cannot be proven and halts - that is the honest answer."""
from dataclasses import dataclass, field

import entry_reference as en
import t007_planning_reference as tp
import t011_persist_reference as p

HEADER, VERSION = 'VELO_EO_LIFECYCLE', 1
LC_MAX = 32


def file_name(login):
    return 'VELO_T013_ENTRY_INDEX_%d.state' % login


@dataclass
class State:
    login: int = 0
    halted: str = ''
    ids: list = field(default_factory=list)


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


def _persist(store, st, notes):
    if not save(store, st):
        st.halted = st.halted or 'LIFECYCLE_STATE_NOT_SAVED'
        notes.append('LIFECYCLE_STATE_NOT_SAVED')
        return False
    return True


def register(store, st, signal_id, notes):
    """called after the executor reached the intent for a signal: the id must be indexed or the layer halts"""
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
        else:
            st.ids.remove(sid)
            if v == FILLED:
                notes.append('FILLED_UNMANAGED %s: no T011 registration is connected' % sid)
    return open_ids


def startup(cfg, tr, store, acknowledge=False):
    """-> (State, notes). A damaged state file is never overwritten: it halts until the owner removes it."""
    notes = []
    acct = tr.read_account()
    if not acct.read_ok or acct.login <= 0:
        return State(0, 'ACCOUNT_UNREADABLE'), ['ACCOUNT_UNREADABLE']
    kind, st = load(store, acct.login)
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
