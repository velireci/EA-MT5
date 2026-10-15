"""T011 executor scenarios (FAKE transport only). A stored record + a tweak of the configuration / world / quote + a scripted send response + an optional injected save fault ->
hand-written finals, the number of sends, the state ON DISK afterwards, the generation and the order map. emit_mql() produces the flat data block of src/tests/T011_ExecutorTest.mq5."""
import t011_activation_reference as act
import t011_executor_reference as ex
import t011_persist_reference as p

IDENT = p.Identity('MetaQuotes-Demo', 5001234, 'XAUUSD', 7)
ROWS = []
K_IDLE, K_MISSING, K_PEND_INTENT, K_PEND_MAP, K_DONE_MAP = range(5)

TWEAKS = ['NONE', 'DISABLED', 'MAGIC_ZERO', 'FILLING_UNSET', 'DEVIATION_UNSET', 'FILTER_POLICY_UNSET', 'FILTERS_NEEDED_BUT_BLOCKED', 'TP_UNSET', 'TP_EQUALS_2R', 'TP_BEFORE_2R',
          'REAL_NOT_AUTHORISED', 'REAL_AUTHORISED_BUT_NOT_DEMO', 'REAL_WRONG_PHRASE', 'REAL_FULLY_AUTHORISED_DEMO', 'ACCOUNT_UNREADABLE', 'LOGIN_MISMATCH', 'TRADING_NOT_ALLOWED',
          'NETTING', 'SYMBOL_UNREADABLE', 'SYMBOL_NOT_TRADABLE', 'POSITION_NOT_FOUND', 'POSITION_MAGIC_OTHER', 'POSITION_SYMBOL_OTHER', 'POSITION_DIRECTION_OTHER',
          'POSITION_VOLUME_CHANGED', 'PRECHECK_FAILS', 'LEVEL_OFF_TICK_GRID', 'SPLIT_UNSET', 'BELOW_LEVEL', 'TP_OFF_TICK_GRID']
T = {n: i for i, n in enumerate(TWEAKS)}
RESPONSES = ['FILLED_10009', 'PARTIAL_10010', 'PLACED_10008', 'TIMEOUT_NO_ORDER', 'FALSE_NO_RESULT', 'TRUE_BUT_NO_ORDER', 'REJECT_10006', 'RETCODE_UNKNOWN_WITH_ORDER']
RS = {n: i for i, n in enumerate(RESPONSES)}


def response(i):
    return [ex.SendResult(True, True, 10009, 501, 1001, 0.4, 2000.0), ex.SendResult(True, True, 10010, 501, 1001, 0.1, 2000.0), ex.SendResult(True, True, 10008, 501, 0, 0.0, 0.0),
            ex.SendResult(False, True, 10012, 0, 0, 0.0, 0.0), ex.SendResult(False, False, 0, 0, 0, 0.0, 0.0), ex.SendResult(True, True, 10009, 0, 1001, 0.4, 2000.0),
            ex.SendResult(True, True, 10006, 0, 0, 0.0, 0.0), ex.SendResult(True, True, 10099, 501, 0, 0.0, 0.0)][i]


def setup(tweak, resp):
    cfg = ex.Config(enabled=True, ea_magic=777, filling=ex.FILL_IOC, deviation=20, filter_policy=ex.POL_IGNORE, filter_state=ex.FS_CLEAR, tp_set=True, tp_price=2010.0)
    tr = ex.FakeTransport()
    tr.response = response(resp)
    q = ex.Quote(1, 2000.0, 2000.0, 2000.3, 0.5)
    t = TWEAKS[tweak]
    if t == 'DISABLED': cfg.enabled = False
    elif t == 'MAGIC_ZERO': cfg.ea_magic = 0
    elif t == 'FILLING_UNSET': cfg.filling = ex.FILL_UNSET
    elif t == 'DEVIATION_UNSET': cfg.deviation = -1
    elif t == 'FILTER_POLICY_UNSET': cfg.filter_policy = ex.POL_UNSET
    elif t == 'FILTERS_NEEDED_BUT_BLOCKED': cfg.filter_policy, cfg.filter_state = ex.POL_NEEDS_CLEAR, ex.FS_BLOCKED
    elif t == 'TP_UNSET': cfg.tp_set = False
    elif t == 'TP_EQUALS_2R': cfg.tp_price = 2000.0
    elif t == 'TP_BEFORE_2R': cfg.tp_price = 1990.0
    elif t == 'TP_OFF_TICK_GRID': cfg.tp_price = 2010.005
    elif t == 'REAL_NOT_AUTHORISED': tr.real = True
    elif t == 'REAL_AUTHORISED_BUT_NOT_DEMO': tr.real, cfg.real_authorised, cfg.authorisation, tr.account.demo = True, True, ex.AUTH_PHRASE, False
    elif t == 'REAL_WRONG_PHRASE': tr.real, cfg.real_authorised, cfg.authorisation = True, True, 'yes'
    elif t == 'REAL_FULLY_AUTHORISED_DEMO': tr.real, cfg.real_authorised, cfg.authorisation = True, True, ex.AUTH_PHRASE
    elif t == 'ACCOUNT_UNREADABLE': tr.account.read_ok = False
    elif t == 'LOGIN_MISMATCH': tr.account.login = 1
    elif t == 'TRADING_NOT_ALLOWED': tr.account.trade_allowed = False
    elif t == 'NETTING': tr.account.margin_mode = 0
    elif t == 'SYMBOL_UNREADABLE': tr.symbol.read_ok = False
    elif t == 'SYMBOL_NOT_TRADABLE': tr.symbol.close_allowed = False
    elif t == 'POSITION_NOT_FOUND': tr.position.found = False
    elif t == 'POSITION_MAGIC_OTHER': tr.position.magic = 0
    elif t == 'POSITION_SYMBOL_OTHER': tr.position.symbol = 'EURUSD'
    elif t == 'POSITION_DIRECTION_OTHER': tr.position.type = 1
    elif t == 'POSITION_VOLUME_CHANGED': tr.position.volume = 0.4
    elif t == 'PRECHECK_FAILS': tr.precheck_ok = False
    elif t == 'LEVEL_OFF_TICK_GRID': q.level_2r = 2000.005
    elif t == 'SPLIT_UNSET': q.volume_initial, tr.position.volume = 0.52, 0.52
    elif t == 'BELOW_LEVEL': q.bid, q.ask = 1999.0, 1999.3
    return cfg, tr, q


def start_record(kind):
    s = act.State()
    if kind == K_IDLE:
        return p.Record(1, IDENT, s)
    act.on_quote(s, 7, act.BUY, 2000.0, 2000.0, 2000.3, 0.5, 0.5, 0.01, 0.01, 100.0)
    if kind == K_PEND_INTENT:
        return p.Record(2, IDENT, s, p.SEND_INTENT)
    if kind == K_PEND_MAP:
        return p.Record(3, IDENT, s, p.SEND_MAPPED, True, [501])
    act.on_report(s, 'X2R80-7', act.FULL, 0.4, 0.01)
    return p.Record(4, IDENT, s, p.SEND_MAPPED, True, [501])


def row(name, start=K_IDLE, tweak='NONE', resp='FILLED_10009', fault=0, fault_no=0, final='', sends=0, disk='IDLE', gen=1, orders=0, reason=''):
    ROWS.append(dict(name=name, start=start, tweak=T[tweak], resp=RS[resp], fault=fault, fault_no=fault_no, final=final, sends=sends, disk=disk, gen=gen, orders=orders, reason=reason))


B = ex.BLOCKED
# ---- the single send and its map
row('ACCEPTED_FILLED_IS_SENT_ONCE_AND_MAPPED', final=ex.SENT_MAPPED, sends=1, disk='REQUEST_PENDING', gen=3, orders=1)
row('ACCEPTED_PARTIAL_FILL_RESPONSE_IS_ONLY_MAPPED_NOT_DONE', resp='PARTIAL_10010', final=ex.SENT_MAPPED, sends=1, disk='REQUEST_PENDING', gen=3, orders=1)
row('ACCEPTED_PLACED_RESPONSE_IS_ONLY_MAPPED', resp='PLACED_10008', final=ex.SENT_MAPPED, sends=1, disk='REQUEST_PENDING', gen=3, orders=1)
row('REAL_TRANSPORT_FULLY_AUTHORISED_ON_DEMO_PASSES_THE_GATE', tweak='REAL_FULLY_AUTHORISED_DEMO', final=ex.SENT_MAPPED, sends=1, disk='REQUEST_PENDING', gen=3, orders=1)
row('QUOTE_BELOW_THE_LEVEL_IS_NO_REQUEST', tweak='BELOW_LEVEL', final=ex.NO_REQUEST, disk='IDLE', gen=1)
# ---- uncertain responses: one send, no retry, the intent stays, recovery
for r_ in ('TIMEOUT_NO_ORDER', 'FALSE_NO_RESULT', 'TRUE_BUT_NO_ORDER', 'REJECT_10006', 'RETCODE_UNKNOWN_WITH_ORDER'):
    row('UNCERTAIN_' + r_ + '_IS_RECOVERY_WITHOUT_RETRY', resp=r_, final=ex.RECOVERY_REQUIRED, sends=1, disk='REQUEST_PENDING', gen=2, orders=0, reason='SEND_UNCERTAIN')
# ---- save failures
row('INTENT_SAVE_FAILS_BEFORE_ANY_WRITE_ZERO_SENDS', fault=1, fault_no=1, final=ex.RECOVERY_REQUIRED, sends=0, disk='IDLE', gen=1, reason='INTENT_SAVE_FAILED')
row('INTENT_SAVE_FALSE_BUT_THE_MOVE_HAPPENED_ZERO_SENDS_AND_THE_DISK_IS_NOT_ASSUMED', fault=2, fault_no=1, final=ex.RECOVERY_REQUIRED, sends=0, disk='REQUEST_PENDING', gen=2,
    reason='INTENT_SAVE_FAILED')
row('MAP_SAVE_FAILS_BEFORE_WRITE_ONE_SEND_INTENT_STAYS', fault=1, fault_no=2, final=ex.RECOVERY_REQUIRED, sends=1, disk='REQUEST_PENDING', gen=2, orders=0, reason='MAP_NOT_SAVED')
row('MAP_SAVE_FALSE_BUT_THE_MOVE_HAPPENED_STILL_RECOVERY', fault=2, fault_no=2, final=ex.RECOVERY_REQUIRED, sends=1, disk='REQUEST_PENDING', gen=3, orders=1, reason='MAP_NOT_SAVED')
# ---- stored state gates
row('RESTART_AFTER_INTENT_IS_NOT_IDLE_NO_SEND', start=K_PEND_INTENT, final=ex.NOT_IDLE, disk='REQUEST_PENDING', gen=2)
row('STORED_PENDING_WITH_MAP_IS_NOT_IDLE_NO_SEND', start=K_PEND_MAP, final=ex.NOT_IDLE, disk='REQUEST_PENDING', gen=3, orders=1)
row('STORED_DONE_IS_NOT_IDLE_NO_SEND', start=K_DONE_MAP, final=ex.NOT_IDLE, disk='DONE', gen=4, orders=1)
row('MISSING_FILE_IS_RECOVERY_NO_SEND', start=K_MISSING, final=ex.RECOVERY_REQUIRED, disk='', gen=0, reason='LOAD_UNUSABLE')
# ---- every check that fails means zero sends and nothing persisted
for tw, why in (('DISABLED', 'DISABLED'), ('MAGIC_ZERO', 'INPUT_UNSET: ea_magic'), ('FILLING_UNSET', 'INPUT_UNSET: filling'), ('DEVIATION_UNSET', 'INPUT_UNSET: deviation'),
                ('FILTER_POLICY_UNSET', 'INPUT_UNSET: exit_filter_policy'), ('FILTERS_NEEDED_BUT_BLOCKED', 'EXIT_FILTERS_NOT_CLEAR'), ('TP_UNSET', 'TP_UNKNOWN'),
                ('TP_EQUALS_2R', 'TP_EQUALS_2R'), ('TP_BEFORE_2R', 'TP_BEFORE_2R'), ('TP_OFF_TICK_GRID', 'PLAN_NOT_ON_SYMBOL_GRID: TP'), ('REAL_NOT_AUTHORISED', 'REAL_NOT_AUTHORISED'),
                ('REAL_AUTHORISED_BUT_NOT_DEMO', 'REAL_REQUIRES_DEMO_ACCOUNT'), ('REAL_WRONG_PHRASE', 'REAL_NOT_AUTHORISED'), ('ACCOUNT_UNREADABLE', 'ACCOUNT_UNREADABLE'),
                ('LOGIN_MISMATCH', 'ACCOUNT_IDENTITY_MISMATCH'), ('TRADING_NOT_ALLOWED', 'TRADING_NOT_ALLOWED'), ('NETTING', 'UNSUPPORTED_ACCOUNT_MODE'),
                ('SYMBOL_UNREADABLE', 'SYMBOL_UNREADABLE_OR_NOT_TRADABLE'), ('SYMBOL_NOT_TRADABLE', 'SYMBOL_UNREADABLE_OR_NOT_TRADABLE'), ('POSITION_NOT_FOUND', 'POSITION_NOT_FOUND'),
                ('POSITION_MAGIC_OTHER', 'OWNERSHIP_NOT_PROVEN'), ('POSITION_SYMBOL_OTHER', 'OWNERSHIP_NOT_PROVEN'), ('POSITION_DIRECTION_OTHER', 'OWNERSHIP_NOT_PROVEN'),
                ('POSITION_VOLUME_CHANGED', 'RECONCILE_REQUIRED'), ('PRECHECK_FAILS', 'PRECHECK_FAILED'), ('LEVEL_OFF_TICK_GRID', 'PLAN_NOT_ON_SYMBOL_GRID: level_2R'),
                ('SPLIT_UNSET', 'SPLIT_POLICY_UNSET')):
    row('BLOCK_' + tw + '_ZERO_SENDS', tweak=tw, final=B, sends=0, disk='IDLE', gen=1, reason=why)


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t011_executor_fixtures.py emit_mql)', '#define NROWS %d' % len(ROWS)]

    def q(v):
        return '"' + v + '"'

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    arr('string', 'R_NAME', [q(r['name']) for r in ROWS])
    for key, nm in (('start', 'R_START'), ('tweak', 'R_TWEAK'), ('resp', 'R_RESP'), ('fault', 'R_FAULT'), ('fault_no', 'R_FAULTNO'), ('sends', 'X_SENDS'), ('gen', 'X_GEN'),
                    ('orders', 'X_ORDERS')):
        arr('int', nm, [str(r[key]) for r in ROWS])
    arr('string', 'X_FINAL', [q(r['final']) for r in ROWS])
    arr('string', 'X_DISK', [q(r['disk']) for r in ROWS])
    arr('string', 'X_REASON', [q(r['reason']) for r in ROWS])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)
