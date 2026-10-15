"""T011 persistence tests: codec round trip, damage / truncation, version and identity, confirmation preservation, restart with a pending request,
the file protocol with injected faults, integration with the real activation / reconciliation references, and mutants."""
import copy
import os
import random
import re
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t011_activation_reference as act  # noqa: E402
import t011_persist_fixtures as fx  # noqa: E402
import t011_persist_reference as p  # noqa: E402
import t011_reconcile_reference as rec  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ID = fx.IDENT
STEP, VINIT, LEVEL = 0.01, 0.5, 4310.5


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def run_rows(mod):
    bad = []
    for r in fx.ROWS:
        txt = None if r['kind'] == 'missing' else r['text']
        o = mod.restore(txt, r['ident'], tmp_present=(r['kind'] == 'tmp'))
        got = (o.verdict, o.state.status, int(o.new_request_allowed), int(o.reconcile_required), o.state.confirmations if r['conf'] else 0,
               o.state.executed_steps if r['executed'] else 0, len(o.orders), o.generation)
        exp = (r['verdict'], r['status'], r['new_req'], r['recon'], r['conf'], r['executed'], r['nord'], r['gen'])
        if r['verdict'] == p.RECOVERY_REQUIRED and r['status'] == 'BLOCKED':
            got, exp = got[:6] + (0, 0), exp[:6] + (0, 0)
        reason_ok = r['reason'] in o.reason or r['reason'] in o.state.reason
        if got != exp or not reason_ok:
            bad.append((r['name'], got, exp, o.reason))
        if r['canon']:
            ok, rc = mod.decode(r['text'])
            ok2, again = mod.encode(rc)
            if not (ok and ok2 and again == r['text']):
                bad.append((r['name'], 'not canonical'))
    return bad


def pending_state():
    s = act.State()
    q = act.on_quote(s, 987654, 1, LEVEL, 4310.6, 4310.9, VINIT, VINIT, 0.01, STEP, 100.0)
    assert q.action == act.REQUEST_ACTION, q
    return s


def record_of(state, phase=p.SEND_MAPPED, orders=(111222,), complete=False, gen=2):
    return p.Record(gen, ID, state, phase, complete, list(orders))


class Codec(unittest.TestCase):
    def test_every_row(self):
        self.assertEqual(run_rows(p), [])

    def test_crc_equals_zlib(self):
        rnd = random.Random(3)
        for _ in range(200):
            t = ''.join(chr(rnd.randrange(32, 127)) for _ in range(rnd.randrange(0, 80)))
            self.assertEqual(p.crc32(t), zlib.crc32(t.encode('ascii')))

    def test_escape_round_trip_including_unicode_and_separators(self):
        for s in ('MetaQuotes-Demo', 'A B=C\nD', 'XAUUSD.r', 'k\u00fcrt\u20ac', '%0041', ''):
            self.assertEqual(p.unesc(p.esc(s)), s)
        self.assertIsNone(p.unesc('a b'))
        self.assertIsNone(p.unesc('%00'))
        self.assertIsNone(p.unesc('%00zz'))
        self.assertIsNone(p.unesc('%004'))

    def test_round_trip_of_states_produced_by_the_real_activation(self):
        s = pending_state()
        for st in (act.State(), s):
            ok, t = p.encode(record_of(st, p.SEND_MAPPED if st.status != act.IDLE else p.SEND_NONE, (5,) if st.status != act.IDLE else ()))
            self.assertTrue(ok, t)
            ok, back = p.decode(t)
            self.assertTrue(ok, back)
            self.assertEqual(back.state, st)
            self.assertEqual(p.encode(back)[1], t)

    def test_every_truncation_is_rejected(self):
        ok, t = p.encode(record_of(pending_state()))
        for n in range(len(t)):
            self.assertFalse(p.decode(t[:n])[0], n)
        self.assertTrue(p.decode(t)[0])

    def test_every_single_byte_change_is_rejected(self):
        ok, t = p.encode(record_of(pending_state()))
        for i in range(len(t)):
            for repl in ('0', 'x', '\n', '='):
                if t[i] == repl:
                    continue
                self.assertFalse(p.decode(t[:i] + repl + t[i + 1:])[0], (i, repl))

    def test_every_field_edit_with_a_fresh_crc_is_rejected_or_validated(self):
        ok, t = p.encode(record_of(pending_state()))
        lines = t.split('\n')[:-2]            # without 'CRC=' line and the empty tail
        bad_values = {'VERSION': '9', 'GEN': '0', 'LOGIN': '0', 'POSITION': '0', 'STATUS': '7', 'BOUND': '2', 'DIRECTION': '5', 'LEVEL': '-1.000000000000',
                      'VOLUME_STEP': '0.000000000000', 'REQUEST_STEPS': '41', 'INITIAL_STEPS': '51', 'EXECUTED_STEPS': '1', 'CONFIRMATIONS': '1', 'SEND_PHASE': '0'}
        for i, line in enumerate(lines):
            key = line.split('=')[0]
            if key in bad_values:
                mutated = lines[:i] + [key + '=' + bad_values[key]] + lines[i + 1:]
                body = '\n'.join(mutated) + '\n'
                text = body + 'CRC=%08X\n' % p.crc32(body)
                self.assertFalse(p.decode(text)[0], key)

    def test_unrepresentable_double_is_refused_not_rounded(self):
        s = pending_state()
        s.level = 0.1 + 0.2          # 0.30000000000000004: not exactly representable with 12 decimals
        ok, why = p.encode(record_of(s))
        self.assertFalse(ok)
        self.assertEqual(p.fnum(0.1 + 0.2), None)

    def test_invalid_records_are_never_written(self):
        s = pending_state()
        for mut in (lambda r: setattr(r, 'generation', 0), lambda r: setattr(r.state, 'confirmations', 2), lambda r: setattr(r, 'orders', [1, 1]),
                    lambda r: setattr(r, 'send_phase', 0), lambda r: setattr(r.state, 'request_id', 'X2R80-1')):
            r = record_of(copy.deepcopy(s))
            try:
                mut(r)
            except Exception:
                continue
            self.assertFalse(p.encode(r)[0])

    def test_nine_orders_are_refused(self):
        r = record_of(pending_state(), orders=list(range(1, 10)))
        self.assertFalse(p.encode(r)[0])


class Restore(unittest.TestCase):
    def test_missing_corrupt_and_foreign_files_never_allow_a_request_and_block_the_activation(self):
        for r in fx.ROWS:
            if r['verdict'] != p.RECOVERY_REQUIRED or r['status'] != 'BLOCKED':
                continue
            o = p.restore(None if r['kind'] == 'missing' else r['text'], r['ident'], r['kind'] == 'tmp')
            self.assertFalse(o.new_request_allowed, r['name'])
            self.assertEqual(o.state.status, act.BLOCKED, r['name'])
            res = act.on_quote(o.state, 987654, 1, LEVEL, 4310.6, 4310.9, VINIT, VINIT, 0.01, STEP, 100.0)
            self.assertEqual((res.event, res.action), ('BLOCKED', act.NONE_ACTION), r['name'])

    def test_restart_with_a_pending_request_never_produces_a_second_request(self):
        s = pending_state()
        t = p.encode(record_of(s))[1]
        o = p.restore(t, ID)
        self.assertEqual((o.verdict, o.state.status, o.new_request_allowed, o.reconcile_required), (p.USABLE_REQUEST, act.REQUEST_PENDING, False, True))
        for _ in range(3):            # many quotes after the restart at and beyond the level
            res = act.on_quote(o.state, 987654, 1, LEVEL, 4320.0, 4320.3, VINIT, VINIT, 0.01, STEP, 100.0)
            self.assertEqual(res.action, act.NONE_ACTION)
            self.assertEqual(res.event, 'IGNORED')

    def test_restart_without_the_order_map_is_recovery_and_stops_every_action(self):
        s = pending_state()
        t = p.encode(record_of(s, p.SEND_INTENT, ()))[1]
        o = p.restore(t, ID)
        self.assertEqual((o.verdict, o.state.status, o.new_request_allowed, o.reconcile_required), (p.RECOVERY_REQUIRED, act.NEEDS_RECONCILIATION, False, True))
        self.assertEqual(o.orders, [])
        res = act.on_quote(o.state, 987654, 1, LEVEL, 4320.0, 4320.3, VINIT, VINIT, 0.01, STEP, 100.0)
        self.assertEqual((res.event, res.action), ('RECONCILE_REQUIRED', act.NONE_ACTION))
        # no map is invented: a later retry-like report does not create a request either
        self.assertEqual(act.on_report(o.state, act.request_id_for(987654), act.TIMEOUT, 0.0, STEP).action, act.NONE_ACTION)

    def test_stored_idle_allows_a_request_exactly_once_under_the_protocol(self):
        s = act.State()
        t = p.encode(p.Record(1, ID, s))[1]
        o = p.restore(t, ID)
        self.assertTrue(o.new_request_allowed)
        res = act.on_quote(o.state, 987654, 1, LEVEL, 4320.0, 4320.3, VINIT, VINIT, 0.01, STEP, 100.0)
        self.assertEqual(res.action, act.REQUEST_ACTION)
        # protocol: the PENDING + INTENT record is persisted BEFORE sending; a crash after it restores to recovery, not to another request
        t2 = p.encode(p.Record(2, ID, o.state, p.SEND_INTENT))[1]
        o2 = p.restore(t2, ID)
        self.assertFalse(o2.new_request_allowed)
        self.assertEqual(act.on_quote(o2.state, 987654, 1, LEVEL, 4320.0, 4320.3, VINIT, VINIT, 0.01, STEP, 100.0).action, act.NONE_ACTION)

    def test_a_stale_idle_file_is_the_documented_gap(self):
        """If the protocol is NOT followed (the request is sent while the file still says IDLE), a restart restores IDLE and allows a second request.
        This test documents the gap that only the persist-before-send protocol closes; nothing in the codec can detect it."""
        stale = p.encode(p.Record(1, ID, act.State()))[1]
        o = p.restore(stale, ID)
        self.assertTrue(o.new_request_allowed)

    def test_the_confirmation_is_preserved_and_not_added_by_a_restore_and_a_recheck(self):
        s = pending_state()
        act.on_report(s, s.request_id, act.FULL, 0.4, STEP)
        self.assertEqual((s.status, s.confirmations), (act.DONE, 1))
        t = p.encode(record_of(s))[1]
        for _ in range(3):             # restart, restore, persist again, restart ...
            o = p.restore(t, ID)
            self.assertEqual((o.state.status, o.state.confirmations, o.state.executed_steps), (act.DONE, 1, 40))
            t = p.encode(p.Record(o.generation + 1, ID, o.state, p.SEND_MAPPED, False, o.orders))[1]
        # reconciliation after the restore regains DONE with confirmations still 1
        snap = rec.Snapshot(True, 987654, s.request_id, STEP, 0.1, [rec.Exec('d1', s.request_id, 0.4)], True)
        o = p.restore(t, ID)
        out = rec.reconcile(o.state, snap)
        self.assertEqual((out.decision, o.state.confirmations, o.state.status), ('CONFIRMED', 1, act.DONE))
        # a duplicate report after the restore is a duplicate, not a second confirmation
        res = act.on_report(o.state, s.request_id, act.FULL, 0.4, STEP)
        self.assertEqual((res.event, o.state.confirmations), ('DUPLICATE_IGNORED', 1))

    def test_a_restored_reconciliation_state_reconciles_with_a_snapshot_not_with_the_file(self):
        s = pending_state()
        act.on_report(s, s.request_id, act.TIMEOUT, 0.0, STEP)
        self.assertEqual(s.status, act.NEEDS_RECONCILIATION)
        o = p.restore(p.encode(record_of(s))[1], ID)
        self.assertTrue(o.reconcile_required)
        snap = rec.Snapshot(True, 987654, s.request_id, STEP, 0.1, [rec.Exec('d1', s.request_id, 0.4)], True)
        out = rec.reconcile(o.state, snap)
        self.assertEqual((out.decision, o.state.status), ('CONFIRMED', act.DONE))

    def test_blocked_stays_blocked_after_a_restore(self):
        s = pending_state()
        act.on_report(s, 'X2R80-1', act.FULL, 0.4, STEP)
        self.assertEqual(s.status, act.BLOCKED)
        o = p.restore(p.encode(record_of(s))[1], ID)
        self.assertEqual((o.verdict, o.state.status), (p.USABLE_BLOCKED, act.BLOCKED))
        self.assertEqual(act.on_quote(o.state, 987654, 1, LEVEL, 4320.0, 4320.3, VINIT, VINIT, 0.01, STEP, 100.0).action, act.NONE_ACTION)


class Files(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fs = p.FileStore(self.tmp.name)
        self.name = 'VELO_T011_TEST.state'

    def tearDown(self):
        self.tmp.cleanup()

    def pend(self, gen):
        return p.Record(gen, ID, pending_state(), p.SEND_MAPPED, False, [7])

    def test_fresh_save_load_and_next_generation(self):
        self.assertEqual(self.fs.load(self.name, ID).verdict, p.RECOVERY_REQUIRED)     # missing
        self.assertTrue(self.fs.init_fresh(self.name, ID)[0])
        self.assertEqual(self.fs.load(self.name, ID).verdict, p.USABLE_IDLE)
        self.assertFalse(self.fs.init_fresh(self.name, ID)[0])                         # never overwrites
        self.assertTrue(self.fs.save(self.name, self.pend(2))[0])
        o = self.fs.load(self.name, ID)
        self.assertEqual((o.verdict, o.generation, o.state.status), (p.USABLE_REQUEST, 2, act.REQUEST_PENDING))
        self.assertFalse(self.fs.exists(self.name + '.tmp'))

    def test_generation_identity_and_existing_damage_are_refused(self):
        self.fs.init_fresh(self.name, ID)
        self.assertFalse(self.fs.save(self.name, self.pend(1))[0])
        self.assertFalse(self.fs.save(self.name, self.pend(3))[0])
        other = p.Record(2, p.Identity('Other', 1, 'XAUUSD', 5), act.State())
        self.assertFalse(self.fs.save(self.name, other)[0])
        with open(self.fs.path(self.name), 'ab') as f:
            f.write(b'junk')
        self.assertFalse(self.fs.save(self.name, self.pend(2))[0])
        self.assertEqual(self.fs.load(self.name, ID).verdict, p.RECOVERY_REQUIRED)

    def test_first_save_must_be_generation_one(self):
        self.assertFalse(self.fs.save(self.name, self.pend(2))[0])

    def test_a_crash_with_a_half_written_temporary_file_leaves_the_target_and_blocks_the_restart(self):
        self.fs.init_fresh(self.name, ID)
        with self.assertRaises(p.Crash):
            self.fs.save(self.name, self.pend(2), fault='write_partial')
        o = self.fs.load(self.name, ID)
        self.assertEqual(o.verdict, p.RECOVERY_REQUIRED)           # leftover temporary file
        self.assertIn('LEFTOVER_TMP', o.reason)
        self.assertFalse(o.new_request_allowed)
        self.assertEqual(self.fs.read(self.name).count('STATUS=0'), 1)    # the target still holds the previous generation, unreadable by the restore policy
        self.assertFalse(self.fs.save(self.name, self.pend(2))[0])        # no save over a leftover until recovery

    def test_a_crash_before_the_move_and_after_the_move(self):
        self.fs.init_fresh(self.name, ID)
        with self.assertRaises(p.Crash):
            self.fs.save(self.name, self.pend(2), fault='crash_before_move')
        self.assertIn('LEFTOVER_TMP', self.fs.load(self.name, ID).reason)
        os.remove(self.fs.path(self.name + '.tmp'))               # operator recovery
        with self.assertRaises(p.Crash):
            self.fs.save(self.name, self.pend(2), fault='crash_after_move')
        o = self.fs.load(self.name, ID)
        self.assertEqual((o.verdict, o.generation), (p.USABLE_REQUEST, 2))

    def test_move_failure_and_readback_failure_report_false(self):
        self.fs.init_fresh(self.name, ID)
        ok, why = self.fs.save(self.name, self.pend(2), fault='move_fails')
        self.assertFalse(ok)
        self.assertEqual(self.fs.load(self.name, ID).verdict, p.USABLE_IDLE)     # the target is unchanged
        ok, why = self.fs.save(self.name, self.pend(2), fault='target_differs')
        self.assertFalse(ok)
        self.assertEqual(self.fs.load(self.name, ID).verdict, p.RECOVERY_REQUIRED)

    def test_truncated_and_edited_files_on_disk(self):
        self.fs.init_fresh(self.name, ID)
        self.fs.save(self.name, self.pend(2))
        full = self.fs.read(self.name)
        for cut in (0, 1, len(full) // 2, len(full) - 1):
            with open(self.fs.path(self.name), 'wb') as f:
                f.write(full[:cut].encode('latin-1'))
            o = self.fs.load(self.name, ID)
            self.assertEqual((o.verdict, o.new_request_allowed, o.state.status), (p.RECOVERY_REQUIRED, False, act.BLOCKED), cut)
        with open(self.fs.path(self.name), 'wb') as f:
            f.write(full.replace('STATUS=1', 'STATUS=0').encode('latin-1'))
        self.assertEqual(self.fs.load(self.name, ID).verdict, p.RECOVERY_REQUIRED)

    def test_wrong_identity_file(self):
        self.fs.init_fresh(self.name, ID)
        o = self.fs.load(self.name, p.Identity('MetaQuotes-Demo', 5001234, 'XAUUSD.r', 1))
        self.assertEqual(o.verdict, p.RECOVERY_REQUIRED)
        self.assertIn('IDENTITY_MISMATCH', o.reason)


class Mutants(unittest.TestCase):
    def test_mutants_are_caught(self):
        src = _read('tests', 't011_persist_reference.py')
        cases = [
            ('crc not checked', "    if int(trailer[4:12], 16) != crc32(body):", "    if False:"),
            ('identity not compared', "    if rec.identity != expected:", "    if False:"),
            ('pending restored as new request allowed', "    out.new_request_allowed = False\n    out.reconcile_required = True", "    out.new_request_allowed = True\n    out.reconcile_required = True"),
            ('reconcile flag dropped', "    out.new_request_allowed = False\n    out.reconcile_required = True", "    out.new_request_allowed = False\n    out.reconcile_required = False"),
            ('uncertain send accepted', "    if rec.send_phase == SEND_INTENT and st.status in (act.REQUEST_PENDING, act.NEEDS_RECONCILIATION):", "    if False:"),
            ('missing file allows a request', "        return Restore(RECOVERY_REQUIRED, 'MISSING: no state file; a missing file never allows a new request', _blocked('MISSING'))",
             "        return Restore(USABLE_IDLE, 'x', act.State(), True)"),
            ('leftover temp ignored', "    if tmp_present:", "    if False:"),
            ('confirmation reset on restore', "    st = rec.state\n    out = Restore(", "    st = rec.state\n    st.confirmations = 0\n    out = Restore("),
            ('version not checked', "    if _geti(vals['VERSION']) != VERSION:", "    if False:"),
            ('semantic validation skipped', "    bad = validate(rec)\n    if bad:\n        return False, bad\n    return True, rec", "    return True, rec"),
            ('DONE needs no confirmation', "(st.executed_steps != st.request_steps or st.confirmations != 1)", "False"),
            ('blocked turned idle', "    if st.status == act.BLOCKED:\n        out.verdict, out.reason = USABLE_BLOCKED, 'BLOCKED restored as stored'\n        return out",
             "    if st.status == act.BLOCKED:\n        st.status = act.IDLE\n        out.verdict = USABLE_IDLE\n        return out"),
            ('generation not checked on save', "            if rec.generation != cur.generation + 1:", "            if False:"),
            ('existing damaged file overwritten', "            if cur is None:\n                return False, 'EXISTING_FILE_UNUSABLE: recover first'", "            if False:\n                pass"),
            ('read back skipped', "        if self.read(tmp) != text:", "        if False:"),
            ('init overwrites', "        if self.exists(name) or self.exists(name + '.tmp'):", "        if False:"),
            ('rounding accepted', "    return t if float(t) == x else None", "    return t"),
        ]
        for name, old, new in cases:
            with self.subTest(name):
                self.assertIn(old, src, 'vacuous mutant')
                ns = {'__name__': 'persist_mutant'}
                exec(compile(src.replace(old, new, 1), 'persist_mutant', 'exec'), ns)

                class M:
                    pass
                m = M()
                for k, v in ns.items():
                    setattr(m, k, v)
                caught = False
                try:
                    caught = bool(run_rows(m))
                    if not caught:
                        caught = self.extra(m, name)
                except Exception:
                    caught = True
                self.assertTrue(caught, 'mutant not caught: ' + name)

    def extra(self, m, name):
        """mutants that live in the file protocol / validation and are not reachable from the table rows"""
        with tempfile.TemporaryDirectory() as d:
            fs = m.FileStore(d)
            n = 'x.state'
            fs.init_fresh(n, ID)
            if not fs.init_fresh(n, ID)[0] is False:
                return True
            if fs.save(n, p.Record(5, ID, act.State()))[0]:
                return True
            with open(fs.path(n), 'ab') as f:
                f.write(b'junk')
            if fs.save(n, p.Record(2, ID, act.State()))[0]:
                return True
            fs2 = m.FileStore(d)
            os.remove(fs2.path(n))
            fs2.init_fresh(n, ID)
            try:
                ok, why = fs2.save(n, p.Record(2, ID, act.State(), p.SEND_NONE), fault='target_differs')
            except Exception:
                return True
            return ok
        return False


class Mql(unittest.TestCase):
    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T011_PersistTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())

    def test_empty_reason_expectation_means_no_condition_in_the_mql_test(self):
        t = _read('src', 'tests', 'T011_PersistTest.mq5')
        self.assertIn('if(expected=="") return(true);', t)
        self.assertIn('Check(ReasonOk(X_REASON[i],o.reason,st.reason)', t)
        self.assertNotIn('Check(StringFind(o.reason,X_REASON[i])', t)           # the raw search that failed on an empty expectation
        self.assertIn('TestReasonOk();', t)
        # the Python table has the same meaning: '' in text is True, and rows with a non-empty expectation really search
        empties = [r['name'] for r in fx.ROWS if r['reason'] == '']
        self.assertTrue(empties and all(r['reason'] for r in fx.ROWS if r['verdict'] == p.RECOVERY_REQUIRED))
        self.assertTrue(any(r['reason'] for r in fx.ROWS))

    def test_int_generation_and_file_size_are_bounded_before_conversion(self):
        c = _read('src', 'include', 'ExitStateCodec.mqh')
        f = _read('src', 'include', 'ExitStateFile.mqh')
        self.assertNotIn('r.generation>ESC_MAX_GEN', c)                         # an int is never compared with INT_MAX (always false)
        self.assertLess(c.index('if(gen<1 || gen>ESC_MAX_GEN)'), c.index('rec.generation=(int)gen;'))
        self.assertIn('ulong size=FileSize(h);', f)
        self.assertLess(f.index('size>(ulong)(ESC_MAX_TEXT+16)'), f.index('(int)size'))
        self.assertIsNone(re.search(r'(?<![a-z])long size=FileSize', f))
        self.assertIn('cur.generation>=ESC_MAX_GEN', f)                         # no int overflow of generation+1

    def test_codec_constants_agree_with_the_python_reference(self):
        h = _read('src', 'include', 'ExitStateCodec.mqh')
        self.assertIn('#define ESC_MAX_ORDERS %d' % p.MAX_ORDERS, h)
        self.assertIn('#define ESC_MAX_TEXT %d' % p.MAX_TEXT, h)
        self.assertIn('#define ESC_MAX_ID %d' % p.MAX_ID, h)
        adapter = _read('src', 'include', 'ExitSnapshotAdapter.mqh')
        self.assertIn('#define XA_MAX_ORDERS %d' % p.MAX_ORDERS, adapter)
        self.assertIn(p.HEADER, h)


if __name__ == '__main__':
    unittest.main()
