"""T019 entry LIFECYCLE (Python mirror of src/include/EntryLifecycle.mqh): the part between the placement and the end of a pending order that the orchestrator lacked.
 - a small persistent INDEX of the signal ids that still need attention (open pending orders and unresolved records) + a persistent HALT flag, in one CRC-protected file written through the entry store;
 - STARTUP: reconcile every indexed signal with the EXISTING executor reconcile (never a send); a record that cannot be proven (recovery / blocked / cancel-uncertain / missing / unusable) halts the layer, and the
   halt survives a restart until the owner acknowledges it explicitly (an acknowledgement only drops the unresolved ids from the index; the records stay, so the signals stay consumed);
 - TICK: reconcile again; a fill is recorded and reported as FILLED_UNMANAGED (the T011 registration is NOT connected: a changed stored-SL / ownership contract needs the owner's agreement); cancel events that are due
   (session closed / news blocked / daily limit) cancel an open pending order ONLY when the owner enabled that event; the cancel is the existing TP_CancelDecision + EN_Cancel, one per fresh runtime; any cancel that is not
   confirmed halts. FAKE tickets are never mapped to broker facts: after a restart under the FAKE transport the book is empty, so a placed record cannot be proven and halts - that is the honest answer."""
from dataclasses import dataclass, field

import entry_reference as en
import t011_driver_reference as dr
import t011_executor_reference as ex
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
    unmanaged: list = field(default_factory=list)   # fills whose T011 registration was refused in THIS process (not persisted): the sink is not asked again, the halt stays
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


SINK_CONFIRMED, SINK_PENDING, SINK_REFUSED = 'CONFIRMED', 'PENDING', 'REFUSED'


def exit_file_name(login, position_id):
    return 'VELO_T011_EXIT_%d_%d.state' % (login, position_id)


PROV_UNSET, PROV_SYNTHETIC, PROV_BROKER = 0, 1, 2     # where the filled order came from: UNSET blocks; SYNTHETIC = the FAKE entry transport (its position ids are not broker facts); BROKER = a real entry transport


class Registrar:
    """the fill sink: AUTOMATIC registration of a filled entry with T011 through the EXISTING ex.register (via the T011 driver's per-position lock), with the contracts of the explicit script unchanged:
    ownership (magic, symbol, direction, volume, hedging account), the initial SL asserted from the executor record and accepted only while the LIVE SL equals it, the stored plan, a state file that is
    never overwritten, the authorisation phrase and the demo account (the transport reports IsReal() = true), the TP / 2R rule of T011 (TP_EQUALS_2R stays a refusal). Idempotent: an existing T011
    record is accepted only when it matches the plan (nothing is rewritten); any other existing record is a conflict. Transient refusals are retried a bounded number of times."""
    MAX_TRIES = 5
    TRANSIENT = ('ACCOUNT_UNREADABLE', 'SYMBOL_UNREADABLE', 'POSITION_NOT_FOUND', 'INSTANCE_LOCK_HELD', 'ENTRY_UNAVAILABLE')

    def __init__(self, entry_store, exit_tr, exit_store, locks, magic, phrase, rpol, provenance=PROV_UNSET):
        self.entry_store, self.exit_tr, self.exit_store, self.locks = entry_store, exit_tr, exit_store, locks
        self.magic, self.phrase, self.rpol, self.provenance = magic, phrase, rpol, provenance
        self.tries = {}

    def inputs(self, rec):
        return ('InpRPolicy=R_GEOM InpEaMagic=%d InpPositionId=%d InpSymbol=%s InpDirection=%s InpInitialSl=%.8f InpTpPrice=%.8f InpVolumeInitial=%.8f '
                '(start XauUsdT011ExitManager with these; its filling, deviation and filter policy stay the owner inputs)'
                % (rec.magic, rec.position_id, rec.symbol, 'BUY' if rec.direction == 1 else 'SELL', rec.s, rec.tp, rec.volume))

    def on_filled(self, login, sid):
        status, detail = self._attempt(login, sid)
        if status == SINK_PENDING:
            n = self.tries.get(sid, 0) + 1
            self.tries[sid] = n
            if n >= self.MAX_TRIES:
                return SINK_REFUSED, 'RETRIES_EXHAUSTED after %d attempts: %s' % (n, detail)
        return status, detail

    def _attempt(self, login, sid):
        if self.provenance != PROV_BROKER:
            return SINK_REFUSED, 'PROVENANCE_NOT_BROKER: the fill comes from a %s entry transport; its position id is not a broker fact and is never matched to a real position' % ('synthetic (FAKE)' if self.provenance == PROV_SYNTHETIC else 'not declared')
        ok, text = self.entry_store.read(en.file_name(login, sid))
        ok, rec = en.decode(text) if ok else (False, None)
        if not ok:
            return SINK_REFUSED, 'ENTRY_RECORD_UNREADABLE'
        if rec.state != en.ST_FILLED or rec.linked != 1 or rec.position_id <= 0:
            return SINK_REFUSED, 'FILL_NOT_PROVEN'
        acct = self.exit_tr.read_account()
        if not acct.read_ok:
            return SINK_PENDING, 'ACCOUNT_UNREADABLE'
        if acct.login != rec.login or acct.server != rec.server:
            return SINK_REFUSED, 'ACCOUNT_IDENTITY_MISMATCH'
        ident = p.Identity(acct.server, acct.login, rec.symbol, rec.position_id)
        name = exit_file_name(acct.login, rec.position_id)
        if self.exit_store.exists(name) or self.exit_store.exists(name + '.tmp'):
            return self._compare(name, ident, rec, acct)
        cfg = ex.Config(enabled=True, real_authorised=(self.phrase == ex.AUTH_PHRASE), authorisation=self.phrase, ea_magic=self.magic, tp_set=True, tp_price=rec.tp, r_policy=self.rpol,
                        sl_initial_set=True, sl_initial=rec.s)
        q = ex.Quote(rec.direction, 0.0, 0.0, 0.0, rec.volume)
        res = dr.register(cfg, self.exit_tr, ex.Runtime(), self.exit_store, name, ident, q, self.locks)
        if res.final == ex.REGISTERED:
            return SINK_CONFIRMED, 'REGISTERED_WITH_T011 ' + self.inputs(rec)
        if res.final == ex.RECOVERY_REQUIRED:
            return SINK_PENDING, 'REGISTRATION_UNCERTAIN: ' + res.reason
        return (SINK_PENDING if res.reason.startswith(self.TRANSIENT) else SINK_REFUSED), res.reason

    def _compare(self, name, ident, rec, acct):
        """an EXISTING T011 record is accepted only when the whole base of the plan matches what registration would store NOW and the registration gates still hold; nothing is written.
        What management legitimately changes (the live SL, the live volume, the request / order state) is not compared; what it cannot change (the open price, the initial SL, TP, direction,
        the initial volume, the symbol's volume rules, the derived 2R level) is."""
        if self.exit_store.exists(name + '.tmp'):
            return SINK_REFUSED, 'T011_RECORD_CONFLICT: a leftover temporary file exists; recover by hand'
        if not (self.phrase == ex.AUTH_PHRASE):
            return SINK_REFUSED, 'REAL_NOT_AUTHORISED'
        if not acct.demo:
            return SINK_REFUSED, 'REAL_REQUIRES_DEMO_ACCOUNT'
        if acct.margin_mode != 2:
            return SINK_REFUSED, 'UNSUPPORTED_ACCOUNT_MODE: only HEDGING'
        if not (self.magic > 0 and rec.magic == self.magic):
            return SINK_REFUSED, 'OWNERSHIP_NOT_PROVEN: the magic of the configuration differs from the magic of the entry record'
        sym = self.exit_tr.read_symbol(ident.symbol)
        if not sym.read_ok or sym.tick_size <= 0:
            return SINK_PENDING, 'SYMBOL_UNREADABLE'
        pos = self.exit_tr.find_position(ident.position_id)
        if not pos.found or pos.ticket <= 0 or pos.identifier != ident.position_id:
            return SINK_PENDING, 'POSITION_NOT_FOUND: the open price of the position cannot be proven, so the stored base cannot be compared'
        if pos.symbol != ident.symbol or pos.magic != self.magic or pos.type != (0 if rec.direction == 1 else 1):
            return SINK_REFUSED, 'OWNERSHIP_NOT_PROVEN: symbol, magic or direction of the live position differ from the record / configuration'
        o = self.exit_store.load(name, ident)
        if o.verdict not in (p.USABLE_IDLE, p.USABLE_REQUEST, p.USABLE_BLOCKED) or not o.plan_set:
            return SINK_REFUSED, 'T011_RECORD_CONFLICT: the existing T011 record is unusable and is never overwritten (%s)' % o.reason
        if not (ex._finite(pos.price_open) and pos.price_open > 0 and ex._on_grid(pos.price_open, sym.tick_size) and ex._on_grid(rec.s, sym.tick_size)):
            return SINK_REFUSED, 'T011_RECORD_CONFLICT: the live open price or the initial SL is not usable as a base'
        geo = ex._geometry(sym, rec.direction, pos.price_open, rec.s, rec.tp)
        if geo.status != tg.OK:
            return SINK_REFUSED, 'T011_RECORD_CONFLICT: the base does not give a geometry (%s)' % geo.status
        same = (o.state.direction == rec.direction and o.state.volume_initial == rec.volume and o.plan_tp == rec.tp and o.plan_rpol == self.rpol and o.plan_e_src == pos.price_open
                and o.plan_s_src == rec.s and o.plan_e_out == geo.e_out and o.plan_s_out == geo.s_out and o.state.level == geo.level_2r
                and o.plan_vol_min == sym.vol_min and o.plan_vol_step == sym.vol_step and o.plan_vol_max == sym.vol_max)
        if not same:
            return SINK_REFUSED, 'T011_RECORD_CONFLICT: the existing T011 record differs from the plan (open price, initial SL, TP, direction, volume, 2R level or symbol volume rules) and is never overwritten'
        return SINK_CONFIRMED, 'ALREADY_REGISTERED (the whole base of the T011 record matches; nothing is rewritten) ' + self.inputs(rec)


def _sweep(cfg, tr, store, st, notes, sink=None):
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
        elif v == FILLED and sink is not None:
            if sid in st.unmanaged:
                continue                                  # refused in this process: the halt stays, the sink is not asked again
            status, detail = sink.on_filled(st.login, sid)
            if status == SINK_CONFIRMED:
                notes.append('%s: %s' % (sid, detail))
                st.ids.remove(sid)
            elif status == SINK_PENDING:
                notes.append('FILL_REGISTRATION_PENDING %s: %s' % (sid, detail))
            else:
                notes.append('UNMANAGED_FILL %s: %s' % (sid, detail))
                st.unmanaged.append(sid)
                if not st.halted:
                    st.halted = 'MANAGEMENT_REGISTRATION_REFUSED: %s' % _clean(detail)
        elif v == FILLED and sid not in st.noted:
            notes.append('FILLED_UNMANAGED %s: no T011 registration is connected | %s' % (sid, proposal(cfg, tr, store, st.login, sid)))
            st.noted.append(sid)                  # reported first; forgotten on the next sweep, so a restart in between reports it again
        else:
            st.ids.remove(sid)
            if sid in st.noted:
                st.noted.remove(sid)
    return open_ids


def startup(cfg, tr, store, lockstore, acknowledge=False, sink=None):
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
    _sweep(cfg, tr, store, st, notes, sink)
    if acknowledge and st.halted:
        notes.append('HALT_ACKNOWLEDGED by the owner: %s' % (was_halted or st.halted))
        # only the ids that are still unresolved are dropped from the index; their records stay on disk (the signals stay consumed)
        for sid in list(st.ids):
            if sid in st.unmanaged or verdict(en.reconcile(cfg, tr, store, sid)) == HALT:
                st.ids.remove(sid)
        st.unmanaged = []
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


def tick(cfg, tr, store, st, due, enabled, sink=None):
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
    open_ids = _sweep(cfg, tr, store, st, notes, sink)
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

