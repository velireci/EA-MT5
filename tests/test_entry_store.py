"""T017: real temporary disk, existing executor, fake transport; no terminal/trading."""
import json
import pathlib
import sys
import shutil
import uuid
import subprocess
import itertools
from contextlib import contextmanager
import unittest
from dataclasses import replace

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import entry_reference as en
from test_entry_executor import cfg, plan, permit_for
from entry_store_reference import FileStore, physical


@contextmanager
def testdir():
    parent = pathlib.Path(__file__).resolve().parent
    root = parent / ('.t017-' + uuid.uuid4().hex)
    root.mkdir()
    try:
        yield root
    finally:
        assert root.resolve().parent == parent and root.name.startswith('.t017-')
        shutil.rmtree(root)


def disk(root, selftest=False):
    return FileStore(root, selftest)


class Persistence(unittest.TestCase):
    def test_recreated_store_transport_runtime_cannot_send_the_same_signal(self):
        for direction in (1, -1):
            with self.subTest(direction=direction), testdir() as root:
                tr = en.FakeTransport()
                p = plan(direction)
                first = en.place(cfg(), tr, disk(root), en.Runtime(), p, permit_for(p, tr))
                self.assertEqual((first.final, tr.sends), (en.R_PLACED, 1))
                fresh = en.FakeTransport()
                again = en.place(cfg(), fresh, disk(root), en.Runtime(), p, permit_for(p, fresh))
                self.assertEqual((again.final, fresh.sends), (en.R_DUPLICATE, 0))

    def test_existing_record_in_every_state_consumes_the_signal(self):
        states = [en.ST_INTENT, en.ST_PRECHECK_REFUSED, en.ST_REJECTED, en.ST_PLACED,
                  en.ST_FILLED, en.ST_CANCEL_UNCERTAIN, en.ST_CANCELLED, en.ST_EXPIRED,
                  en.ST_RECOVERY, en.ST_BLOCKED]
        for state, direction in itertools.product(states, (1, -1)):
            with self.subTest(state=state, direction=direction), testdir() as root:
                tr = en.FakeTransport()
                p = plan(direction)
                store = disk(root)
                en.place(cfg(), tr, store, en.Runtime(), p, permit_for(p, tr))
                name = en.file_name(tr.account.login, p.signal_id)
                ok, text = store.read(name)
                self.assertTrue(ok)
                ok, rec = en.decode(text)
                self.assertTrue(ok, rec)
                values = dict(state=state, position_id=7 if state == en.ST_FILLED else 0,
                              attempts=0 if state in (en.ST_INTENT, en.ST_PRECHECK_REFUSED) else 1,
                              cancel_attempts=1 if state == en.ST_CANCEL_UNCERTAIN else 0)
                if state in (en.ST_INTENT, en.ST_PRECHECK_REFUSED, en.ST_REJECTED):
                    values.update(order_ticket=0, linked=0)
                ok, text = en.encode(replace(rec, **values))
                self.assertTrue(ok, text)
                self.assertTrue(store.write(name, text))
                fresh = en.FakeTransport()
                result = en.place(cfg(), fresh, disk(root), en.Runtime(), p, permit_for(p, fresh))
                self.assertEqual((result.final, fresh.sends), (en.R_DUPLICATE, 0))

    def test_corrupt_record_never_allows_a_send(self):
        with testdir() as root:
            tr = en.FakeTransport()
            p = plan()
            store = disk(root)
            self.assertTrue(store.write(en.file_name(tr.account.login, p.signal_id), 'damaged'))
            result = en.place(cfg(), tr, disk(root), en.Runtime(), p, permit_for(p, tr))
            self.assertEqual((result.final, tr.sends), (en.R_BLOCKED, 0))

    def test_a_separate_python_process_sees_the_record_without_fake_order_recreation(self):
        with testdir() as root:
            tr = en.FakeTransport()
            p = plan()
            self.assertEqual(en.place(cfg(), tr, disk(root), en.Runtime(), p, permit_for(p, tr)).final, en.R_PLACED)
            script = """import sys,json
sys.path.insert(0,sys.argv[2])
import entry_reference as en
from entry_store_reference import FileStore
from test_entry_executor import cfg,plan,permit_for
tr=en.FakeTransport(); p=plan()
r=en.place(cfg(),tr,FileStore(sys.argv[1]),en.Runtime(),p,permit_for(p,tr))
print(json.dumps([r.final,tr.sends,len(tr.orders)]))
"""
            proc = subprocess.run([sys.executable, '-c', script, str(root), str(pathlib.Path(__file__).resolve().parent)], capture_output=True, text=True, check=True)
            self.assertEqual(json.loads(proc.stdout), ['DUPLICATE', 0, 0])


class Boundaries(unittest.TestCase):
    def test_file_and_lock_namespaces_are_separate_from_ordinary_records(self):
        with testdir() as root:
            name = 'VELO_T013_ENTRY_1_ABCD1234.state'
            ordinary = root / name
            ordinary.write_text('ordinary untouched')
            a, b = disk(root), disk(root, True)
            self.assertTrue(a.write(name, 'fake'))
            self.assertTrue(b.write(name, 'test'))
            self.assertEqual(ordinary.read_text(), 'ordinary untouched')
            self.assertEqual(a.read(name), (True, 'fake'))
            self.assertEqual(b.read(name), (True, 'test'))
            key = 'VELO_T013_LOCK_1_ABCD1234'
            self.assertTrue(a.lock(key))
            self.assertTrue(b.lock(key))
            a.unlock(key)
            b.unlock(key)

    def test_invalid_names_never_create_or_read_any_path(self):
        bad = ['', '../VELO_T013_ENTRY_1_A.state', 'C:/a.state', 'VELO_T011_A.state',
               'VELO_T013_ENTRY_../x.state', 'VELO_T013_ENTRY_1_A.state.tmp',
               'VELO_T013_ENTRY_.state', 'VELO_T013_ENTRY_1_é.state', 'VELO_T013_ENTRY_1_A:stream.state',
               'VELO_T013_ENTRY_' + 'A'*250 + '.state']
        with testdir() as root:
            a = disk(root)
            for name in bad:
                with self.subTest(name=name):
                    self.assertTrue(a.exists(name))  # EN_Load must fail closed, not report missing.
                    self.assertEqual(a.read(name), (False, ''))
                    self.assertFalse(a.write(name, 'not written'))
                    self.assertFalse(a.lock(name))
            self.assertEqual(list(root.iterdir()), [])

    def test_contention_nested_acquire_and_wrong_unlock_cannot_release_another_lock(self):
        with testdir() as root:
            a, b = disk(root), disk(root)
            key, other = 'VELO_T013_LOCK_1_ABCD1234', 'VELO_T013_LOCK_1_EF123456'
            self.assertTrue(a.lock(key))
            self.assertFalse(a.lock(other))
            self.assertFalse(b.lock(key))
            a.unlock(other)
            self.assertFalse(b.lock(key))
            a.unlock(key)
            self.assertTrue(b.lock(key))
            b.unlock(key)

    def test_leftover_temp_and_unreadable_existing_file_block_sends(self):
        for kind in ('temporary', 'unreadable', 'locked'):
            with self.subTest(kind=kind), testdir() as root:
                tr = en.FakeTransport()
                p = plan()
                store = disk(root)
                name = en.file_name(tr.account.login, p.signal_id)
                held = disk(root)
                if kind == 'temporary':
                    (root / (physical(name) + '.tmp')).write_text('partial intent')
                elif kind == 'unreadable':
                    (root / physical(name)).mkdir()
                else:
                    self.assertTrue(held.lock(en.lock_key(tr.account.login, p.signal_id)))
                r = en.place(cfg(), tr, store, en.Runtime(), p, permit_for(p, tr))
                self.assertEqual(tr.sends, 0)
                self.assertIn(r.final, (en.R_BLOCKED, en.R_LOCK_FAILED))
                held.unlock(en.lock_key(tr.account.login, p.signal_id))

    def test_false_write_and_failed_readback_do_not_send_or_assume_rollback(self):
        class Fault:
            def __init__(self, delegate, mode):
                self.delegate, self.mode = delegate, mode
            def __getattr__(self, name):
                return getattr(self.delegate, name)
            def write(self, name, text):
                if self.mode == 'false_partial':
                    self.delegate.write(name, 'partial')
                    return False
                return self.delegate.write(name, text)
            def read(self, name):
                return (False, '') if self.mode == 'readback' else self.delegate.read(name)
        for mode in ('false_partial', 'readback'):
            with self.subTest(mode=mode), testdir() as root:
                tr = en.FakeTransport()
                p = plan()
                r = en.place(cfg(), tr, Fault(disk(root), mode), en.Runtime(), p, permit_for(p, tr))
                self.assertEqual((r.final, tr.sends), (en.R_BLOCKED, 0))
                fresh = en.FakeTransport()
                r2 = en.place(cfg(), fresh, disk(root), en.Runtime(), p, permit_for(p, fresh))
                self.assertEqual(fresh.sends, 0)
                self.assertIn(r2.final, (en.R_BLOCKED, en.R_DUPLICATE))


if __name__ == '__main__':
    unittest.main()
