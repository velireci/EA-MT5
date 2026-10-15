"""T011 R_GEOM executor tests (Part 14, FAKE transport only): registration and the tick path derive the 2R level from TG_Compute over the stored E and S, never from a live SL."""
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t011_executor_reference as ex  # noqa: E402
import t011_geom_fixtures as fx  # noqa: E402
import t011_persist_reference as p  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = 'VELO_T011_GEOMTEST.state'


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def disk_of(store):
    if not store.exists(NAME):
        return 'MISSING', 0, 0.0
    ok, rec = p.decode(store.read(NAME))
    return (rec.state.status, rec.generation, rec.state.level) if ok else ('CORRUPT', 0, 0.0)


def run_rows(mod):
    bad = []
    for r in fx.ROWS:
        with tempfile.TemporaryDirectory() as d:
            store = p.FileStore(d)
            txt = fx.start_text(r['start'], r['side'])
            if txt is not None:
                with open(store.path(NAME), 'wb') as f:
                    f.write(txt.encode('latin-1'))
            cfg, tr, q, rt = fx.world(r['side'], r['sets'])
            fn = mod.register if r['op'] == fx.REG else mod.process
            res = fn(cfg, tr, rt, store, NAME, fx.IDENT, q)
            disk, gen, lvl = disk_of(store)
            got = (res.final, len(tr.sends), disk, gen, lvl)
            exp = (r['final'], r['sends'], r['disk'], r['gen'], r['level'])
            if r['disk'] == 'MISSING' and r['final'] == ex.REGISTERED:
                exp = (r['final'], 0, 'IDLE', 1, r['level'])
            if r['disk'] == 'CORRUPT':
                exp = (r['final'], r['sends'], 'CORRUPT', 0, 0.0)
            if got != exp or r['reason'] not in res.reason or store.exists(NAME + '.tmp'):
                bad.append((r['name'], got, exp, res.reason))
    return bad


def probe_normalization(mod):
    """a TG whose normalized entry differs from the declared one: registration must refuse and save nothing"""
    from dataclasses import replace

    class Shifted:
        def __init__(self, real):
            self.real = real

        def __getattr__(self, n):
            return getattr(self.real, n)

        def compute(self, *a, **k):
            r = self.real.compute(*a, **k)
            return replace(r, e_out=r.e_out + 0.01)
    real = mod.tg
    mod.tg = Shifted(real)
    try:
        with tempfile.TemporaryDirectory() as d:
            store = p.FileStore(d)
            cfg, tr, q, rt = fx.world(1, {})
            res = mod.register(cfg, tr, rt, store, NAME, fx.IDENT, q)
            if not (res.final == ex.BLOCKED and not store.exists(NAME) and 'BASE_CHANGED_BY_NORMALIZATION' in res.reason):
                return [('normalization change accepted', res.final, res.reason)]
    finally:
        mod.tg = real
    return []


class Rows(unittest.TestCase):
    def test_every_row(self):
        self.assertEqual(run_rows(ex), [])

    def test_the_old_version_2_file_is_not_modified(self):
        with tempfile.TemporaryDirectory() as d:
            store = p.FileStore(d)
            txt = fx.start_text(fx.S_OLD_V2, 1)
            with open(store.path(NAME), 'wb') as f:
                f.write(txt.encode('latin-1'))
            cfg, tr, q, rt = fx.world(1, {})
            for fn in (ex.process, ex.register):
                fn(cfg, tr, rt, store, NAME, fx.IDENT, q)
            self.assertEqual(store.read(NAME), txt)                  # not changed, migrated or deleted
            self.assertEqual(len(tr.sends), 0)

    def test_coverage(self):
        names = {r['name'] for r in fx.ROWS}
        for need in ('BUY_REGISTERS_FROM_THE_OPEN_PRICE_AND_THE_ASSERTED_SL', 'SELL_REGISTERS_FROM_THE_OPEN_PRICE_AND_THE_ASSERTED_SL', 'BUY_SENDS_ONCE_AT_THE_LEVEL',
                     'SELL_SENDS_ONCE_AT_THE_LEVEL', 'BUY_LIVE_SL_AT_BREAK_EVEN_DOES_NOT_CHANGE_THE_LEVEL', 'BUY_ONLY_THE_ASK_AT_THE_LEVEL_IS_NOT_ENOUGH_FOR_A_BUY',
                     'SELL_ONLY_THE_BID_AT_THE_LEVEL_IS_NOT_ENOUGH_FOR_A_SELL', 'BUY_POLICY_UNSET_BLOCKS'):
            self.assertIn(need, names)

    def test_the_registered_record_stores_the_declared_basis_and_no_r(self):
        for side, sl, lvl in ((1, 1995.0, 2010.0), (-1, 2005.0, 1990.0)):
            with tempfile.TemporaryDirectory() as d:
                store = p.FileStore(d)
                cfg, tr, q, rt = fx.world(side, {})
                res = ex.register(cfg, tr, rt, store, NAME, fx.IDENT, q)
                self.assertEqual(res.final, ex.REGISTERED, res.reason)
                ok, rec = p.decode(store.read(NAME))
                self.assertTrue(ok, rec)
                self.assertEqual((rec.plan_rpol, rec.plan_e_src, rec.plan_s_src, rec.plan_e_out, rec.plan_s_out, rec.state.level), (p.RPOL_R_GEOM, 2000.0, sl, 2000.0, sl, lvl))
                self.assertNotIn('R_GEOM=', store.read(NAME))
                self.assertNotRegex(store.read(NAME), r'(?m)^(R|R_GEOM|RISK)=')

    def test_a_normalization_that_changes_the_declared_basis_is_refused_before_anything_is_saved(self):
        self.assertEqual(probe_normalization(ex), [])

    def test_no_level_arithmetic_in_the_reference(self):
        src = _read('tests', 't011_executor_reference.py')
        self.assertNotRegex(src, r'2\s*\*\s*(r_geom|r\b|risk)')
        self.assertNotRegex(src, r'(e_out|entry)\s*[+-]\s*2')


class Mutants(unittest.TestCase):
    def _build(self, pairs):
        src = _read('tests', 't011_executor_reference.py')
        for old, new in pairs:
            self.assertIn(old, src, 'mutation target absent (vacuous): ' + old[:50])
            src = src.replace(old, new, 1)
        ns = {'__name__': 't011_geom_mutant'}
        exec(compile(src, 't011_geom_mutant', 'exec'), ns)

        class M:
            pass
        m = M()
        for k, v in ns.items():
            setattr(m, k, v)
        return m

    def test_mutants_are_caught(self):
        cases = [
            ('level derived from the live SL', [("geo = _geometry(sym, q.direction, o.plan_e_src, o.plan_s_src, cfg.tp_price)", "geo = _geometry(sym, q.direction, o.plan_e_src, pos.sl, cfg.tp_price)")]),
            ('level input of the quote used', [("        level = geo.level_2r                         # compared", "        level = q.level_2r if q.level_2r else geo.level_2r                         # compared")]),
            ('configured initial SL not compared', [("    if cfg.sl_initial != o.plan_s_src:", "    if False:")]),
            ('policy not compared with the record', [("    if o.plan_rpol != cfg.r_policy:", "    if False:")]),
            ('live SL not compared at registration', [("    if not (pos.sl > 0 and abs(pos.sl - cfg.sl_initial) < sym.tick_size / 2):", "    if False:")]),
            ('base off the grid accepted', [("    if not (_on_grid(pos.price_open, sym.tick_size) and _on_grid(cfg.sl_initial, sym.tick_size)):", "    if False:")]),
            ('geometry status ignored', [("    if geo.status != tg.OK:", "    if False:")]),
            ('asserted SL not required', [("    if not cfg.sl_initial_set:", "    if False:")]),
            ('policy UNSET accepted at registration', [("    if cfg.r_policy == RPOL_UNSET:\n        return block('INPUT_UNSET: r_policy')\n    if not cfg.tp_set:", "    if False:\n        return block('INPUT_UNSET: r_policy')\n    if not cfg.tp_set:")]),
            ('normalization change accepted', [("        if abs(geo.e_out - pos.price_open) > p.BASIS_TOL", "        if False and abs(geo.e_out - pos.price_open) > p.BASIS_TOL")]),
        ]
        for name, pairs in cases:
            with self.subTest(name):
                try:
                    m = self._build(pairs)
                    bad = run_rows(m) or probe_normalization(m)
                except AssertionError:
                    raise
                except Exception:
                    bad = ['exception']
                self.assertTrue(bad, 'mutant not caught: ' + name)


class Presets(unittest.TestCase):
    @staticmethod
    def inputs(path):
        code = re.sub(r'//[^\n]*', '', _read(*path))
        return dict((n, v.strip()) for n, v in re.findall(r'^input\s+[\w ]+?\s+(Inp\w+)\s*=\s*([^;]+);', code, re.M))

    @staticmethod
    def values(path):
        d = {}
        for line in _read(*path).splitlines():
            line = line.strip()
            if line and not line.startswith(';'):
                k, v = line.split('=', 1)
                assert k not in d, k
                d[k] = v
        return d

    def test_presets_list_every_input_once_and_are_disabled_with_unset_blocking(self):
        for src, preset in (('XauUsdT011ExitManager.mq5', 'XauUsdT011ExitManager.set'), ('XauUsdT011ExitRegister.mq5', 'XauUsdT011ExitRegister.set')):
            names = sorted(self.inputs(('src', src)))
            v = self.values(('src', 'presets', preset))
            self.assertEqual(sorted(v), names, preset)
            self.assertEqual((v['InpEnabled'], v['InpAuthorisation'], v['InpRPolicy'], v['InpDirection']), ('false', '', '0', '0'), preset)
            self.assertEqual((v['InpPositionId'], v['InpInitialSl'], v['InpTpPrice'], v['InpVolumeInitial']), ('0', '0', '0', '0'), preset)
        self.assertEqual(self.values(('src', 'presets', 'XauUsdT011ExitManager.set'))['InpConfirmAutoSend'], 'false')

    def test_the_entry_points_default_to_inert(self):
        ea = re.sub(r'//[^\n]*', '', _read('src', 'XauUsdT011ExitManager.mq5'))
        reg = re.sub(r'//[^\n]*', '', _read('src', 'XauUsdT011ExitRegister.mq5'))
        for code in (ea, reg):
            self.assertIn('input bool InpEnabled=false;', code)
            self.assertIn('input ENUM_ETD_RPOLICY InpRPolicy=ETD_RPOL_UNSET;', code)
            self.assertIn('input ENUM_ETD_DIRECTION InpDirection=ETD_DIR_UNSET;', code)
            self.assertIn('(int)InpDirection!=(int)ETD_DIR_BUY && (int)InpDirection!=(int)ETD_DIR_SELL', code)
        self.assertIn('input bool InpConfirmAutoSend=false;', ea)
        self.assertNotIn('EX_Register', ea)
        self.assertNotIn('ETD_Register', ea)
        oninit = ea[ea.index('int OnInit()'):ea.index('void OnDeinit(')]
        self.assertLess(oninit.index('ETD_Init('), oninit.index('EventSetTimer('))


class DemoSellPackage(unittest.TestCase):
    """the presets of the ONE demo SELL test: complete, disabled, separate magic, 0.05 -> 4 / 1, TP beyond the geometric 2R"""
    P = Presets.values

    def test_presets_are_complete_and_disabled(self):
        for step, src in (('01_open', 'XauUsdT011DemoOpenPosition.mq5'), ('02_register', 'XauUsdT011ExitRegister.mq5'), ('03_manager', 'XauUsdT011ExitManager.mq5')):
            names = sorted(Presets.inputs(('src', src)))
            v = Presets.values(('src', 'presets', 'XauUsdT011ExitDemoSell_%s.set' % step))
            self.assertEqual(sorted(v), names, step)
            self.assertEqual((v['InpEnabled'], v['InpAuthorisation']), ('false', ''), step)
            self.assertEqual((v['InpEaMagic'], v['InpSymbol'], v['InpDirection']), ('778', 'XAUUSD', '-1'), step)       # a magic separate from 777; SELL
        m = Presets.values(('src', 'presets', 'XauUsdT011ExitDemoSell_03_manager.set'))
        self.assertEqual(m['InpConfirmAutoSend'], 'false')
        for step in ('02_register', '03_manager'):
            v = Presets.values(('src', 'presets', 'XauUsdT011ExitDemoSell_%s.set' % step))
            self.assertEqual((v['InpPositionId'], v['InpInitialSl'], v['InpTpPrice']), ('0', '0', '0'), step)             # filled in ONLY from the opener's log
            self.assertEqual((v['InpRPolicy'], v['InpVolumeInitial']), ('2', '0.05'), step)

    def test_the_volume_splits_four_and_one_and_the_tp_is_beyond_the_geometric_2r(self):
        import t011_split_reference as es
        sp = es.split(0.05, 0.01, 0.01, 100.0)
        self.assertEqual(sp.status, 'OK')
        self.assertEqual((round(sp.close_volume, 8), round(sp.remaining_volume, 8)), (0.04, 0.01))
        o = Presets.values(('src', 'presets', 'XauUsdT011ExitDemoSell_01_open.set'))
        self.assertEqual(o['InpVolume'], '0.05')
        sl, tp = float(o['InpStopLossDistance']), float(o['InpTakeProfitDistance'])
        self.assertGreater(tp, 2 * sl)                                      # TP is neither equal to nor before the 2R level
        self.assertEqual(o['InpFilling'], '2')

    def test_nothing_of_the_first_test_is_referenced(self):
        for step in ('01_open', '02_register', '03_manager'):
            txt = _read('src', 'presets', 'XauUsdT011ExitDemoSell_%s.set' % step)
            self.assertNotIn('58913478802', txt)
            self.assertNotIn('InpEaMagic=777', txt)
        doc = _read('docs', 'T011-exit-manager-demo-sell.md')
        for need in ('PENDING proof', 'magic **778**', 'Zero requests before the level', 'At most one request', 'Restart without a second send', 'SL is NOT moved'):
            self.assertIn(need, doc)


class MqlBlock(unittest.TestCase):
    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T011_GeomTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())


if __name__ == '__main__':
    unittest.main()
