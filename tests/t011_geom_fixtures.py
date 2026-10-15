"""T011 R_GEOM executor scenarios (FAKE transport only; Part 14). A start record + a world (BUY or SELL position, configuration, quote) + a list of SET assignments that tweak the world
-> hand-written finals, sends, the state ON DISK, the generation and the level stored. Operation: REG = EX_Register, PROC = EX_Process. The data is generic (field id + value) so that the
MQL5 test applies exactly the same assignments; emit_mql() produces the flat data block of src/tests/T011_GeomTest.mq5 (equality is tested).
BUY world: position price_open 2000.0, live SL 1995.0 (= the asserted initial SL), R = 5.0, level 2R = 2010.0, TP 2015.0. SELL world: price_open 2000.0, SL 2005.0, level 1990.0, TP 1985.0.
The quote's level_2r is passed as 0.0 / garbage on purpose: in R_GEOM the level comes ONLY from the stored basis."""
import t011_activation_reference as act
import t011_executor_reference as ex
import t011_persist_reference as p

IDENT = p.Identity('MetaQuotes-Demo', 5001234, 'XAUUSD', 7)
ROWS = []
FIELDS = ['cfg.r_policy', 'cfg.sl_initial_set', 'cfg.sl_initial', 'cfg.tp_price', 'cfg.enabled', 'pos.price_open', 'pos.sl', 'pos.magic', 'pos.volume', 'pos.found', 'sym.digits',
          'q.level', 'q.bid', 'q.ask', 'q.volume', 'cfg.tp_set', 'rt.latched']
FI = {n: i for i, n in enumerate(FIELDS)}
MAXSET = 4
REG, PROC = 0, 1
S_MISSING, S_GEOM, S_TYPED, S_NOPLAN, S_OLD_V2, S_TAMPER_LEVEL, S_PEND_MAP = range(7)
SIDE_NAME = {1: 'BUY', -1: 'SELL'}
BASE = {1: dict(sl=1995.0, level=2010.0, tp=2015.0, bid=2010.0, ask=2010.3, ptype=0), -1: dict(sl=2005.0, level=1990.0, tp=1985.0, bid=1989.7, ask=1990.0, ptype=1)}


def world(side, sets):
    b = BASE[side]
    cfg = ex.Config(enabled=True, r_policy=ex.RPOL_R_GEOM, sl_initial_set=True, sl_initial=b['sl'], ea_magic=777, filling=ex.FILL_IOC, deviation=20, filter_policy=ex.POL_IGNORE,
                    filter_state=ex.FS_CLEAR, tp_set=True, tp_price=b['tp'])
    tr = ex.FakeTransport()
    tr.response = ex.SendResult(True, True, 10009, 501, 1001, 0.4, 2000.0)
    tr.position.type, tr.position.price_open, tr.position.sl, tr.position.volume = b['ptype'], 2000.0, b['sl'], 0.5
    q = ex.Quote(side, 0.0, b['bid'], b['ask'], 0.5)
    rt = ex.Runtime()
    for k, v in sets.items():
        if k == 'cfg.r_policy': cfg.r_policy = int(v)
        elif k == 'cfg.sl_initial_set': cfg.sl_initial_set = bool(v)
        elif k == 'cfg.sl_initial': cfg.sl_initial = v
        elif k == 'cfg.tp_price': cfg.tp_price = v
        elif k == 'cfg.enabled': cfg.enabled = bool(v)
        elif k == 'cfg.tp_set': cfg.tp_set = bool(v)
        elif k == 'pos.price_open': tr.position.price_open = v
        elif k == 'pos.sl': tr.position.sl = v
        elif k == 'pos.magic': tr.position.magic = int(v)
        elif k == 'pos.volume': tr.position.volume = v
        elif k == 'pos.found': tr.position.found = bool(v)
        elif k == 'sym.digits': tr.symbol.digits = int(v)
        elif k == 'q.level': q.level_2r = v
        elif k == 'q.bid': q.bid = v
        elif k == 'q.ask': q.ask = v
        elif k == 'q.volume': q.volume_initial = v
        elif k == 'rt.latched': rt.latched = bool(v)
        else:
            raise KeyError(k)
    return cfg, tr, q, rt


def geom_record(side, tamper_level=False, phase=p.SEND_NONE, gen=1):
    b = BASE[side]
    s = act.State()
    s.bound, s.position_id, s.direction, s.level, s.volume_initial = True, 7, side, (b['level'] + 1.0 if tamper_level else b['level']), 0.5
    e, sl = 2000.0, b['sl']
    if phase == p.SEND_MAPPED:
        act.on_quote(s, 7, side, b['level'], b['bid'], b['ask'], 0.5, 0.5, 0.01, 0.01, 100.0)
        return p.Record(3, IDENT, s, p.SEND_MAPPED, True, [501], True, b['tp'], 0.01, 0.01, 100.0, p.RPOL_R_GEOM, e, sl, e, sl)
    return p.Record(gen, IDENT, s, phase, False, [], True, b['tp'], 0.01, 0.01, 100.0, p.RPOL_R_GEOM, e, sl, e, sl)


def start_text(start, side):
    if start == S_MISSING:
        return None
    if start == S_GEOM:
        rec = geom_record(side)
    elif start == S_TAMPER_LEVEL:
        rec = geom_record(side, tamper_level=True)
    elif start == S_PEND_MAP:
        rec = geom_record(side, phase=p.SEND_MAPPED)
    elif start == S_TYPED:
        b = BASE[side]
        s = act.State()
        s.bound, s.position_id, s.direction, s.level, s.volume_initial = True, 7, side, b['level'], 0.5
        rec = p.Record(1, IDENT, s, p.SEND_NONE, False, [], True, b['tp'], 0.01, 0.01, 100.0, p.RPOL_TYPED)
    elif start == S_NOPLAN:
        rec = p.Record(1, IDENT, act.State())
    else:                                                                     # S_OLD_V2: the genuine previous layout, version 2, valid CRC
        ok, t = p.encode(geom_record(side))
        body = t[:t.index('CRC=')]
        body = '\n'.join(l for l in body.split('\n') if not l.startswith(('PLAN_RPOL', 'PLAN_E_', 'PLAN_S_'))).replace('VERSION=3', 'VERSION=2', 1)
        return body + 'CRC=%08X\n' % p.crc32(body)
    ok, t = p.encode(rec)
    assert ok, t
    return t


def row(name, op, start, side=1, sets=None, final='', sends=0, disk='MISSING', gen=0, reason='', level=0.0):
    sets = dict(sets or {})
    assert len(sets) <= MAXSET, name
    ROWS.append(dict(name='%s_%s' % (SIDE_NAME[side], name), op=op, start=start, side=side, sets=sets, final=final, sends=sends, disk=disk, gen=gen, reason=reason, level=level))


B, RR, SM, RG, NI, NR = ex.BLOCKED, ex.RECOVERY_REQUIRED, ex.SENT_MAPPED, ex.REGISTERED, ex.NOT_IDLE, ex.NO_REQUEST
# ---------------------------------------------------------------- registration: the level comes from TG_Compute(E = open price, S = asserted initial SL)
for side, lvl in ((1, 2010.0), (-1, 1990.0)):
    row('REGISTERS_FROM_THE_OPEN_PRICE_AND_THE_ASSERTED_SL', REG, S_MISSING, side, final=RG, disk='IDLE', gen=1, level=lvl)
row('POLICY_UNSET_BLOCKS', REG, S_MISSING, sets={'cfg.r_policy': 0}, final=B, reason='INPUT_UNSET: r_policy')
row('POLICY_UNKNOWN_BLOCKS', REG, S_MISSING, sets={'cfg.r_policy': 9}, final=B, reason='INVALID_INPUT: r_policy')
row('ASSERTED_SL_MISSING_BLOCKS', REG, S_MISSING, sets={'cfg.sl_initial_set': 0}, final=B, reason='INPUT_UNSET: initial_sl')
row('LIVE_SL_MOVED_TO_BREAK_EVEN_IS_NOT_THE_INITIAL_SL', REG, S_MISSING, sets={'pos.sl': 2000.0}, final=B, reason='INITIAL_SL_NOT_PROVEN')
row('LIVE_SL_MOVED_CLOSER_IS_NOT_THE_INITIAL_SL', REG, S_MISSING, sets={'pos.sl': 1999.0}, final=B, reason='INITIAL_SL_NOT_PROVEN')
row('LIVE_SL_ABSENT_IS_NOT_THE_INITIAL_SL', REG, S_MISSING, sets={'pos.sl': 0.0}, final=B, reason='INITIAL_SL_NOT_PROVEN')
row('SELL_LIVE_SL_MOVED', REG, S_MISSING, -1, sets={'pos.sl': 2000.0}, final=B, reason='INITIAL_SL_NOT_PROVEN')
row('OPEN_PRICE_UNAVAILABLE', REG, S_MISSING, sets={'pos.price_open': 0.0}, final=B, reason='ENTRY_UNAVAILABLE')
row('OPEN_PRICE_OFF_THE_TICK_GRID', REG, S_MISSING, sets={'pos.price_open': 2000.004}, final=B, reason='BASE_NOT_ON_SYMBOL_GRID')
row('ASSERTED_SL_OFF_THE_TICK_GRID', REG, S_MISSING, sets={'cfg.sl_initial': 1995.004, 'pos.sl': 1995.004}, final=B, reason='BASE_NOT_ON_SYMBOL_GRID')
row('BUY_STOP_ABOVE_ENTRY_GEOMETRY_REFUSED', REG, S_MISSING, sets={'cfg.sl_initial': 2005.0, 'pos.sl': 2005.0}, final=B, reason='GEOMETRY_REFUSED')
row('SELL_STOP_BELOW_ENTRY_GEOMETRY_REFUSED', REG, S_MISSING, -1, sets={'cfg.sl_initial': 1995.0, 'pos.sl': 1995.0}, final=B, reason='GEOMETRY_REFUSED')
row('ZERO_RISK_GEOMETRY_REFUSED', REG, S_MISSING, sets={'cfg.sl_initial': 2000.0, 'pos.sl': 2000.0}, final=B, reason='GEOMETRY_REFUSED')
row('TICK_DIGITS_INCOMPATIBLE_GEOMETRY_REFUSED', REG, S_MISSING, sets={'sym.digits': 1}, final=B, reason='GEOMETRY_REFUSED')
row('TP_EQUALS_2R_BLOCKS', REG, S_MISSING, sets={'cfg.tp_price': 2010.0}, final=B, reason='TP_EQUALS_2R')
row('TP_BEFORE_2R_BLOCKS', REG, S_MISSING, sets={'cfg.tp_price': 2005.0}, final=B, reason='TP_BEFORE_2R')
row('SELL_TP_BEFORE_2R_BLOCKS', REG, S_MISSING, -1, sets={'cfg.tp_price': 1995.0}, final=B, reason='TP_BEFORE_2R')
row('FOREIGN_MAGIC_IS_NEVER_ADOPTED', REG, S_MISSING, sets={'pos.magic': 0}, final=B, reason='OWNERSHIP_NOT_PROVEN')
row('POSITION_NOT_FOUND', REG, S_MISSING, sets={'pos.found': 0}, final=B, reason='POSITION_NOT_FOUND')
row('POSITION_VOLUME_DIFFERS_FROM_THE_PLAN', REG, S_MISSING, sets={'pos.volume': 0.4}, final=B, reason='POSITION_VOLUME_DIFFERS')
row('SPLIT_NOT_REALISABLE', REG, S_MISSING, sets={'pos.volume': 0.52, 'q.volume': 0.52}, final=B, reason='REGISTRATION_REFUSED')
row('DISABLED_BLOCKS', REG, S_MISSING, sets={'cfg.enabled': 0}, final=B, reason='DISABLED')
row('EXISTING_RECORD_IS_NEVER_OVERWRITTEN', REG, S_GEOM, final=B, disk='IDLE', gen=1, reason='ALREADY_EXISTS', level=2010.0)
row('EXISTING_OLD_V2_FILE_IS_NEVER_TOUCHED', REG, S_OLD_V2, final=B, disk='CORRUPT', gen=0, reason='ALREADY_EXISTS')
# ---------------------------------------------------------------- tick path: level from the STORED basis, BUY Bid >= level / SELL Ask <= level
row('SENDS_ONCE_AT_THE_LEVEL', PROC, S_GEOM, 1, final=SM, sends=1, disk='REQUEST_PENDING', gen=3, level=2010.0)
row('SENDS_ONCE_AT_THE_LEVEL', PROC, S_GEOM, -1, final=SM, sends=1, disk='REQUEST_PENDING', gen=3, level=1990.0)
row('BID_JUST_BELOW_THE_LEVEL_NO_REQUEST', PROC, S_GEOM, sets={'q.bid': 2009.99, 'q.ask': 2010.3}, final=NR, disk='IDLE', gen=1, level=2010.0)
row('ONLY_THE_ASK_AT_THE_LEVEL_IS_NOT_ENOUGH_FOR_A_BUY', PROC, S_GEOM, sets={'q.bid': 2009.9, 'q.ask': 2010.1}, final=NR, disk='IDLE', gen=1, level=2010.0)
row('ONLY_THE_BID_AT_THE_LEVEL_IS_NOT_ENOUGH_FOR_A_SELL', PROC, S_GEOM, -1, sets={'q.bid': 1989.9, 'q.ask': 1990.1}, final=NR, disk='IDLE', gen=1, level=1990.0)
row('ASK_JUST_ABOVE_THE_LEVEL_SELL_NO_REQUEST', PROC, S_GEOM, -1, sets={'q.bid': 1990.0, 'q.ask': 1990.01}, final=NR, disk='IDLE', gen=1, level=1990.0)
row('LIVE_SL_AT_BREAK_EVEN_DOES_NOT_CHANGE_THE_LEVEL', PROC, S_GEOM, sets={'pos.sl': 2000.0}, final=SM, sends=1, disk='REQUEST_PENDING', gen=3, level=2010.0)
row('LIVE_SL_MOVED_CLOSER_DOES_NOT_CHANGE_THE_LEVEL', PROC, S_GEOM, sets={'pos.sl': 1999.0, 'q.bid': 2005.0, 'q.ask': 2005.3}, final=NR, disk='IDLE', gen=1, level=2010.0)
row('SELL_LIVE_SL_AT_BREAK_EVEN_DOES_NOT_CHANGE_THE_LEVEL', PROC, S_GEOM, -1, sets={'pos.sl': 2000.0}, final=SM, sends=1, disk='REQUEST_PENDING', gen=3, level=1990.0)
row('LIVE_SL_ABSENT_DOES_NOT_CHANGE_THE_LEVEL', PROC, S_GEOM, sets={'pos.sl': 0.0}, final=SM, sends=1, disk='REQUEST_PENDING', gen=3, level=2010.0)
row('THE_QUOTE_LEVEL_INPUT_IS_IGNORED', PROC, S_GEOM, sets={'q.level': 2005.0}, final=SM, sends=1, disk='REQUEST_PENDING', gen=3, level=2010.0)
row('THE_QUOTE_LEVEL_INPUT_CANNOT_ARM_EARLIER', PROC, S_GEOM, sets={'q.level': 2005.0, 'q.bid': 2006.0, 'q.ask': 2006.3}, final=NR, disk='IDLE', gen=1, level=2010.0)
row('CONFIGURED_INITIAL_SL_DIFFERS_FROM_THE_STORED_ONE', PROC, S_GEOM, sets={'cfg.sl_initial': 1996.0}, final=B, disk='IDLE', gen=1, reason='PLAN_CHANGED: initial_sl', level=2010.0)
row('CONFIGURED_INITIAL_SL_MISSING', PROC, S_GEOM, sets={'cfg.sl_initial_set': 0}, final=B, disk='IDLE', gen=1, reason='INPUT_UNSET: initial_sl', level=2010.0)
row('POLICY_UNSET_BLOCKS', PROC, S_GEOM, sets={'cfg.r_policy': 0}, final=B, disk='IDLE', gen=1, reason='INPUT_UNSET: r_policy', level=2010.0)
row('TYPED_POLICY_AGAINST_A_GEOMETRY_RECORD', PROC, S_GEOM, sets={'cfg.r_policy': 1, 'q.level': 2010.0}, final=B, disk='IDLE', gen=1, reason='PLAN_CHANGED: r_policy', level=2010.0)
row('GEOMETRY_POLICY_AGAINST_A_TYPED_RECORD', PROC, S_TYPED, sets={}, final=B, disk='IDLE', gen=1, reason='PLAN_CHANGED: r_policy', level=2010.0)
row('STORED_LEVEL_DIFFERS_FROM_THE_ONE_DERIVED_FROM_THE_BASIS', PROC, S_TAMPER_LEVEL, final=B, disk='IDLE', gen=1, reason='PLAN_CHANGED: level_2R', level=2011.0)
row('SELL_STORED_LEVEL_DIFFERS_FROM_THE_ONE_DERIVED_FROM_THE_BASIS', PROC, S_TAMPER_LEVEL, -1, final=B, disk='IDLE', gen=1, reason='PLAN_CHANGED: level_2R', level=1991.0)
row('CONFIGURED_TP_CHANGED', PROC, S_GEOM, sets={'cfg.tp_price': 2016.0}, final=B, disk='IDLE', gen=1, reason='PLAN_CHANGED: tp', level=2010.0)
row('GEOMETRY_REFUSED_WHEN_THE_SYMBOL_DIGITS_CHANGED', PROC, S_GEOM, sets={'sym.digits': 1}, final=B, disk='IDLE', gen=1, reason='GEOMETRY_REFUSED', level=2010.0)
row('RECORD_WITHOUT_A_PLAN_IS_NEVER_FILLED_IN', PROC, S_NOPLAN, final=RR, disk='IDLE', gen=1, reason='PLAN_MISSING')
row('MISSING_FILE_NEVER_STARTS_FROM_SCRATCH', PROC, S_MISSING, final=RR, disk='MISSING', reason='LOAD_UNUSABLE')
row('OLD_VERSION_2_FILE_IS_REFUSED_AND_LEFT_UNCHANGED', PROC, S_OLD_V2, final=RR, disk='CORRUPT', reason='UNSUPPORTED_VERSION')
row('RECORD_THAT_NEEDS_RECONCILIATION_IS_NOT_PROCESSED', PROC, S_PEND_MAP, final=NI, disk='REQUEST_PENDING', gen=3, level=2010.0)
row('FOREIGN_MAGIC_BLOCKS_BEFORE_ANY_SEND', PROC, S_GEOM, sets={'pos.magic': 0}, final=B, disk='IDLE', gen=1, reason='OWNERSHIP_NOT_PROVEN', level=2010.0)
row('POSITION_VOLUME_CHANGED_BLOCKS', PROC, S_GEOM, sets={'pos.volume': 0.4}, final=B, disk='IDLE', gen=1, level=2010.0)
row('LATCHED_RUNTIME_BLOCKS', PROC, S_GEOM, sets={'rt.latched': 1}, final=B, disk='IDLE', gen=1, reason='LATCHED', level=2010.0)
row('DISABLED_BLOCKS', PROC, S_GEOM, sets={'cfg.enabled': 0}, final=B, disk='IDLE', gen=1, reason='DISABLED', level=2010.0)


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t011_geom_fixtures.py emit_mql)']
    out.append('#define NROWS %d' % len(ROWS))
    out.append('#define MAXSET %d' % MAXSET)
    q = lambda v: '"%s"' % v

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    def num(v):
        return repr(float(v))

    arr('string', 'R_NAME', [q(r['name']) for r in ROWS])
    arr('int', 'R_OP', [str(r['op']) for r in ROWS])
    arr('int', 'R_START', [str(r['start']) for r in ROWS])
    arr('int', 'R_SIDE', [str(r['side']) for r in ROWS])
    arr('int', 'S_N', [str(len(r['sets'])) for r in ROWS])
    keys, vals = [], []
    for r in ROWS:
        items = list(r['sets'].items())
        for k in range(MAXSET):
            keys.append(str(FI[items[k][0]]) if k < len(items) else '-1')
            vals.append(num(items[k][1]) if k < len(items) else '0.0')
    arr('int', 'S_KEY', keys)
    arr('double', 'S_VAL', vals)
    arr('string', 'X_FINAL', [q(r['final']) for r in ROWS])
    arr('int', 'X_SENDS', [str(r['sends']) for r in ROWS])
    arr('string', 'X_DISK', [q(r['disk']) for r in ROWS])
    arr('int', 'X_GEN', [str(r['gen']) for r in ROWS])
    arr('string', 'X_REASON', [q(r['reason']) for r in ROWS])
    arr('double', 'X_LEVEL', [num(r['level']) for r in ROWS])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
