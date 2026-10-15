"""T012 day-balance store tests (FAKE port only): LOAD is read-only, CAPTURE is explicit, locked, never overwrites, reads back and validates; WINDOW_EMPTY is a conditional proof;
OWNER_ASSERTED is separate; nothing is reconstructed; a new day carries nothing. No order, no policy, no T011 file."""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t011_persist_reference as p  # noqa: E402
import t012_balance_fixtures as fx  # noqa: E402
import t012_balance_reference as b  # noqa: E402
import t012_history_reference as dh  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def strip(t):
    return re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))


def disk_class(port, row):
    name = port.name
    if row['disk'] == 'NEWDAY':
        n2 = b.file_name(5001234, fx.DAY + 1)
        ok, rec = b.decode(port.files.get(n2, ''))
        return 'NEWDAY' if (ok and port.files.get(name) == port.start_text and rec.day == fx.DAY + 1) else 'BAD'
    if name not in port.files:
        return 'MISSING'
    t = port.files[name]
    if t == port.start_text:
        return 'SAME'
    return 'NEW' if b.decode(t)[0] else 'PARTIAL'


def run_op(mod, row, port):
    if row['op'] == fx.LOAD:
        return mod.load(port)
    s = port.s
    asserts = mod.Asserts(bool(s['asrt.complete']), int(s['asrt.offset']))
    if row['op'] == fx.CAP_WE:
        return mod.capture(port, mod.SRC_WE, asserts)
    return mod.capture(port, mod.SRC_OA, asserts, s['own.amount'], fx.DAY + int(s['own.day_shift']))


def run_rows(mod):
    bad = []
    for r in fx.ROWS:
        port = fx.FakePort(r['start'], r['sets'])
        res = run_op(mod, r, port)
        got = (res.status, port.writes, port.bal_calls, disk_class(port, r))
        exp = (r['status'], r['writes'], r['reads'], r['disk'])
        if got != exp or r['reason'] not in res.reason or res.source != r['source'] or res.amount != r['amount']:
            bad.append((r['name'], got, exp, res.reason, res.source, res.amount))
            continue
        if res.status == b.USABLE and res.known is not True:
            bad.append((r['name'], 'usable without known'))
        if res.status != b.USABLE and (res.known or res.amount != 0.0):
            bad.append((r['name'], 'an unusable result carries an amount'))
        if port.held or port.locked_ok != port.unlocks:
            bad.append((r['name'], 'lock not released', port.locked_ok, port.unlocks))
        if r['op'] == fx.LOAD and (port.writes or port.locks or set(port.files) != ({port.name} if port.start_text is not None else set())):
            bad.append((r['name'], 'LOAD must be read-only and lock-free'))
        if r['disk'] == 'NEW' and res.status == b.USABLE:
            ok, rec = b.decode(port.files[port.name])
            if not (ok and rec.amount == res.amount and rec.source == res.source):
                bad.append((r['name'], 'the stored record differs from the result'))
    return bad


class Rows(unittest.TestCase):
    def test_every_row(self):
        self.assertEqual(run_rows(b), [])

    def test_coverage(self):
        names = {r['name'] for r in fx.ROWS}
        for need in ('LOAD_MISSING_FILE_IS_NONE_AND_NOTHING_IS_CREATED', 'LOAD_RESTART_INSIDE_THE_DAY_KEEPS_THE_STORED_AMOUNT', 'LOAD_NEXT_DAY_DOES_NOT_CARRY_THE_OLD_BALANCE',
                     'CAPTURE_WE_EMPTY_WINDOW_AT_00_00_05', 'CAPTURE_WE_ANY_DEAL_OF_ANY_MAGIC_OR_TYPE_COUNTS', 'CAPTURE_WE_MIDNIGHT_CROSSED_WITHIN_THE_SPAN',
                     'CAPTURE_WE_EXISTING_DAMAGED_IS_NEVER_OVERWRITTEN', 'CAPTURE_WE_LOCK_HELD_NOTHING_IS_READ_OR_WRITTEN', 'CAPTURE_OA_EXPLICIT_AMOUNT'):
            self.assertIn(need, names)
        self.assertEqual({r['status'] for r in fx.ROWS}, {b.USABLE, b.NONE, b.UNKNOWN, b.BLOCK})

    def test_the_midnight_closure_case_stays_unknown_even_with_the_balance_known(self):
        # the terminal starts at 09:00 and the night already holds a deal: the current balance is NOT the start-of-day balance, and nothing is subtracted
        port = fx.FakePort(fx.K_MISSING, {'asrt.complete': 1, 'asrt.offset': fx.OFF, 't_a': 9 * 3600, 't_b': 9 * 3600 + 2, 'hist.deals': 2, 'bal1': 1100.0, 'bal2': 1100.0})
        res = b.capture(port, b.SRC_WE, b.Asserts(True, fx.OFF))
        self.assertEqual((res.status, res.known, res.amount, port.writes, len(port.files)), (b.UNKNOWN, False, 0.0, 0, 0))
        self.assertIn('MID_DAY_NOT_PROVEN', res.reason)

    def test_day_change_does_not_carry_anything(self):
        port = fx.FakePort(fx.K_VALID_WE, {'clock.day_shift': 1})
        res = b.load(port)
        self.assertEqual((res.status, res.known, res.amount), (b.NONE, False, 0.0))

    def test_a_second_capture_is_idempotent(self):
        port = fx.FakePort(fx.K_MISSING, dict(asrt_ok := {'asrt.complete': 1, 'asrt.offset': fx.OFF}))
        a1 = b.capture(port, b.SRC_WE, b.Asserts(True, fx.OFF))
        port.now_calls = 0
        port.bal_calls = 0
        port.s['bal1'] = port.s['bal2'] = 4242.0                       # the balance moved meanwhile
        a2 = b.capture(port, b.SRC_WE, b.Asserts(True, fx.OFF))
        self.assertEqual((a1.status, a1.amount, a2.status, a2.amount, port.writes, port.bal_calls), (b.USABLE, 1000.0, b.USABLE, 1000.0, 1, 0))
        self.assertIn('ALREADY_CAPTURED', a2.reason)


class Codec(unittest.TestCase):
    def rec(self, **kw):
        d = dict(login=5001234, server='MetaQuotes-Demo', currency='EUR', day=fx.DAY, amount=1000.0, source=b.SRC_WE, complete_asserted=1, offset=7200, t_first=fx.START + 5, t_last=fx.START + 7)
        d.update(kw)
        return b.Record(**d)

    def test_round_trip_and_canonical_text(self):
        for r in (self.rec(), self.rec(source=b.SRC_OA, complete_asserted=0, offset=0, t_last=fx.START + 5, amount=1234.5), self.rec(server='A B=C%\u00fc', currency='E/R')):
            ok, t = b.encode(r)
            self.assertTrue(ok, t)
            ok2, back = b.decode(t)
            self.assertTrue(ok2, back)
            self.assertEqual(back, r)
            self.assertEqual(b.encode(back)[1], t)

    def test_invalid_records_are_never_written(self):
        for kw in (dict(login=0), dict(server=''), dict(currency=''), dict(day=1), dict(amount=0.0), dict(amount=-1.0), dict(amount=float('nan')), dict(amount=float('inf')), dict(amount=1.0000000000001234),
                   dict(source='X'), dict(complete_asserted=0), dict(complete_asserted=2), dict(offset=7201), dict(offset=50401 - 1 + 900), dict(t_first=0), dict(t_last=fx.START + 4),
                   dict(t_last=fx.START + 5 + 121), dict(t_first=fx.START - 5), dict(t_last=fx.END + 1), dict(source=b.SRC_OA, complete_asserted=1, offset=0, t_last=fx.START + 5),
                   dict(source=b.SRC_OA, complete_asserted=0, offset=900, t_last=fx.START + 5), dict(source=b.SRC_OA, complete_asserted=0, offset=0, t_last=fx.START + 9)):
            self.assertFalse(b.encode(self.rec(**kw))[0], kw)

    def test_damage_is_detected_but_the_crc_is_not_protection_against_an_edit(self):
        ok, t = b.encode(self.rec())
        self.assertFalse(b.decode(t.replace('AMOUNT=1000', 'AMOUNT=1001'))[0])
        body = t[:t.index('CRC=')].replace('AMOUNT=1000.000000000000', 'AMOUNT=2000.000000000000')
        resealed = body + 'CRC=%08X\n' % p.crc32(body)
        self.assertTrue(b.decode(resealed)[0])          # a deliberate edit with a recomputed CRC is accepted: documented limit
        for cut in range(0, len(t) - 1, 7):
            self.assertFalse(b.decode(t[:cut])[0], cut)


class Sources(unittest.TestCase):
    def test_header_calls_no_trading_no_deletion_no_policy_no_profit_fields_and_only_the_needed_primitives(self):
        h = strip(_read('src', 'include', 'DailyBalanceStore.mqh'))
        for word in ('OrderSend', 'OrderCheck', 'OrderDelete', 'PositionClose', 'CTrade', 'FileDelete', 'FileMove', 'GlobalVariableDel', 'ESF_Save', 'ESF_Load', 'ESF_InitFresh', 'ESC_Encode', 'ESC_Decode',
                     'ESC_Restore', 'ACCOUNT_EQUITY', 'ACCOUNT_CREDIT', 'ACCOUNT_MARGIN', 'candidate_profit', 'nontrade_profit', 'nontrade_commission', 'nontrade_swap',
                     'nontrade_fee', 'result_formula', 'DB_Check', 'DL_Check', 'max_trades', 'ACCOUNT_PROFIT', 'TimeCurrent', 'Sleep'):
            self.assertNotIn(word, h, word)
        self.assertIsNone(re.search(r'\b(EX|ETD|ER|XA)_\w+', h))
        used = set(re.findall(r'\b(ESC_\w+|ESF_\w+)\s*\(', h))
        self.assertLessEqual(used, {'ESC_Crc32', 'ESC_Escape', 'ESC_Unescape', 'ESC_Fnum', 'ESC_ParseInt', 'ESC_ParseDouble', 'ESC_Lines', 'ESC_Field', 'ESF_ReadAll', 'ESF_WriteAll', 'ESF_Exists'})
        self.assertIn('ACCOUNT_BALANCE', h)

    def test_load_has_no_write_and_no_lock_and_capture_orders_its_steps(self):
        h = strip(_read('src', 'include', 'DailyBalanceStore.mqh'))
        load = h[h.index('void DBS_Load('):h.index('void DBS_Capture(')]
        for word in ('WriteFile', 'Lock(', 'Unlock(', 'ReadBalance', 'ReadHistory'):
            self.assertNotIn(word, load)
        cap = h[h.index('void DBS_Capture('):]
        ident = h[h.index('bool DBS_Identity('):h.index('void DBS_Load(')]
        self.assertLess(ident.index('ReadAccount('), ident.index('NowUtc('))
        self.assertLess(ident.index('NowUtc('), ident.index('DH_DayWindow('))
        marks = ['HISTORY_COMPLETE_NOT_ASSERTED', 'DBS_Identity(', 'port.Lock(', 'port.Exists(', 'port.ReadBalance(', 'port.ReadHistory(', 'port.ReadBalance(', 'port.NowUtc(', 'DH_DayWindow(',
                 'DAY_CHANGED_DURING_ACQUISITION', 'MID_DAY_NOT_PROVEN', 'DBS_Encode(', 'port.WriteFile(', 'port.ReadFile(', 'DBS_Decode(', 'port.Unlock(']
        at, pos = 0, []
        for m in marks:
            at = cap.index(m, at)
            pos.append(at)
        self.assertEqual(pos, sorted(pos))
        self.assertGreaterEqual(cap.count('port.Unlock('), 1)

    def test_reference_pins(self):
        src = _read('tests', 't012_balance_reference.py')
        self.assertNotIn('candidate', src.split('"""', 2)[2])
        self.assertNotIn('nontrade', src.split('"""', 2)[2])
        self.assertIn('finally:\n        port.unlock(key)', src)


class Mutants(unittest.TestCase):
    def _build(self, pairs):
        src = _read('tests', 't012_balance_reference.py')
        for old, new in pairs:
            self.assertIn(old, src, 'vacuous: ' + old[:50])
            src = src.replace(old, new, 1)
        ns = {'__name__': 't012_balance_mutant'}
        exec(compile(src, 't012_balance_mutant', 'exec'), ns)

        class M:
            pass
        m = M()
        for k, v in ns.items():
            setattr(m, k, v)
        return m

    def test_mutants_are_caught(self):
        cases = [
            ('deals in the window ignored', [("            if h.deals_in_window != 0:", "            if False:")]),
            ('balance changes ignored', [("            if b2 != b1:", "            if False:")]),
            ('history not required to be complete', [("            if not h.complete:", "            if False:")]),
            ('history verdict ignored', [("            if h.verdict != dh.READY:", "            if False:")]),
            ('day change during the acquisition accepted', [("            if wb is None or wb[0] != day:", "            if False:")]),
            ('history of another day accepted', [("            if h.day_key != day:", "            if False:")]),
            ('window coverage ignored', [("            if not (h.window_start <= t_a and t_b < h.window_end):", "            if False:")]),
            ('acquisition span unlimited', [("            if t_b - t_a > MAX_SPAN:", "            if False:")]),
            ('clock regression accepted', [("            if t_b < t_a:", "            if False:")]),
            ('existing file overwritten', [("        if port.exists(name):                                          # INSIDE the lock; never overwritten, whatever it holds", "        if False:")]),
            ('existence checked outside the lock', [("    key = lock_key(acct.login, day)\n    if not port.lock(key):\n        return Result(UNKNOWN, 'LOCK_FAILED", "    key = lock_key(acct.login, day)\n    port.lock(key)\n    if False:\n        return Result(UNKNOWN, 'LOCK_FAILED")]),
            ('lock not released', [("    finally:\n        port.unlock(key)", "    finally:\n        pass")]),
            ('no read back', [("        if not ok or back != text:", "        if False:")]),
            ('write failure ignored', [("        if not port.write_file(name, text):", "        if False:")]),
            ('other account accepted', [("    if (rec.login, rec.server, rec.currency) != (acct.login, acct.server, acct.currency):", "    if False:")]),
            ('currency not part of the identity', [("(rec.login, rec.server, rec.currency) != (acct.login, acct.server, acct.currency)", "(rec.login, rec.server) != (acct.login, acct.server)")]),
            ('day inside the record not compared', [("    if rec.day != day:", "    if False:")]),
            ('damaged file used', [("    ok, rec = decode(text)\n    if not ok:\n        return Result(BLOCK, 'DAMAGED: ' + rec)", "    ok, rec = decode(text)\n    if not ok:\n        return Result(USABLE, '', True, day, 1.0, SRC_WE)")]),
            ('crc not checked', [("    if int(trailer[4:12], 16) != p.crc32(body):", "    if False:")]),
            ('missing file created by LOAD', [("        return Result(NONE, 'NO_RECORD:", "        port.write_file(file_name(acct.login, day), 'x')\n        return Result(NONE, 'NO_RECORD:")]),
            ('complete assertion not required', [("        if asserts.complete is not True:", "        if False:")]),
            ('offset not required', [("        if asserts.offset == OFFSET_UNSET:", "        if False:")]),
            ('owner day not compared', [("    if src == SRC_OA and owner_day != day:", "    if False:")]),
            ('owner value promoted to window empty', [("            rec = Record(acct.login, acct.server, acct.currency, day, owner_amount, SRC_OA, 0, 0, t_a, t_a)", "            rec = Record(acct.login, acct.server, acct.currency, day, owner_amount, SRC_WE, 1, 7200, t_a, t_a)")]),
            ('balance zero accepted', [("            if not ok1 or not math.isfinite(b1) or not b1 > 0:", "            if not ok1:")]),
            ('stored amount replaced by the current balance', [("    return Result(USABLE, '', True, day, rec.amount, rec.source, False, True)", "    return Result(USABLE, '', True, day, port.read_balance()[1], rec.source, False, True)")]),
        ]
        for name, pairs in cases:
            with self.subTest(name):
                m = self._build(pairs)
                try:
                    bad = run_rows(m)
                except Exception:
                    bad = ['exception']
                self.assertTrue(bad, 'mutant not caught: ' + name)


class MqlBlock(unittest.TestCase):
    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T012_BalanceStoreTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())


if __name__ == '__main__':
    unittest.main()
