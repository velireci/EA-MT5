#!/usr/bin/env python3
"""T017 static boundary checks and destructive negative controls in memory only."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]


def strip(text):
    return re.sub(r'//[^\n]*', '', re.sub(r'/\*.*?\*/', '', text, flags=re.S))


def verify(files):
    ea = strip(files['src/XauUsdEntryOrchestrator.mq5'])
    hd = strip(files['src/include/EntryStateFile.mqh'])
    real = strip(files['src/include/EntryTransportReal.mqh'])
    assert 'CEnFakeFileStore g_store;' in ea, 'persistent store wiring'
    assert 'CEoTerminalFake g_tr;' in ea, 'fixed FAKE transport'
    assert 'class CEnRealStore' not in real and '#include "EntryStateFile.mqh"' in real, 'compatible extraction'
    assert sum(t.count('class CEnRealStore :') for t in files.values()) == 1, 'single store definition'
    def digest(text):
        return hashlib.sha256(re.sub(r'\s+', '', strip(text)).encode()).hexdigest()
    old_store = hd[hd.index('class CEnRealStore :'):hd.index('string EFS_Name(')]
    assert digest(old_store) == 'b4b207e6936fa47e9c35a3a756f0cb2d8fe0006c6f4b34042508e74faa5d845b', 'original file protocol changed'
    assert digest(real[real.index('class CEnRealTransport :'):]) == '2b2b9ff3c87f246a1e2da293dc84c8e36082b96462b5f1ce3b8ac2abd26b801f', 'real transport body changed'
    assert '"VELO_T017_SELFTEST_" : "VELO_T016_FAKE_"' in hd, 'distinct namespaces'
    assert 'if(StringFind(logical,prefix)!=0) return("");' in hd, 'logical prefix guard'
    assert 'ch==95)) return("");' in hd and 'StringSubstr(logical,n-6)!=".state"' in hd, 'path and suffix guard'
    assert 'if(name=="" || m_key!="") return(false);' in hd, 'nested lock guard'
    assert 'if(m_key=="" || m_key!=key) return;' in hd, 'release ownership'
    assert 'mapped=="" ? true' in hd, 'invalid exists fails closed'
    visited = set()
    def walk(path):
        if path in visited:
            return
        visited.add(path)
        assert 'TransportReal' not in path, 'real transport reachable'
        text = strip(files[path])
        assert not re.search(r'\b(OrderSend|OrderSendAsync|OrderCheck|CTrade|CEnRealTransport)\b', text), 'trading API reachable'
        for inc in re.findall(r'#include "([^"]+)"', text):
            child = (Path(path).parent / inc).as_posix()
            # Source tree uses simple relative includes; resolve .. without filesystem lookup.
            child = (ROOT / child).resolve().relative_to(ROOT).as_posix()
            assert child in files, 'missing include: ' + child
            walk(child)
    walk('src/XauUsdEntryOrchestrator.mq5')
    walk('src/tests/EntryPersistenceTest.mq5')
    test = strip(files['src/tests/EntryPersistenceTest.mq5'])
    assert 'EFS_Name(logical,false,true)' in test and 'if(StringFind(name,"VELO_T017_SELFTEST_")!=0) return(false);' in test, 'self-test cleanup boundary'
    return len(visited)


def main():
    files = {p.relative_to(ROOT).as_posix(): p.read_text(encoding='utf-8-sig') for p in (ROOT / 'src').rglob('*') if p.suffix in ('.mqh', '.mq5')}
    count = verify(files)
    print('PASS persistent FAKE wiring, isolated names/locks, compatible extraction, %d reachable files without trading API' % count)
    mutations = [
        ('real include', 'src/XauUsdEntryOrchestrator.mq5', '#include "include/EntryStateFile.mqh"', '#include "include/EntryStateFile.mqh"\n#include "include/EntryTransportReal.mqh"'),
        ('memory store', 'src/XauUsdEntryOrchestrator.mq5', 'CEnFakeFileStore g_store;', 'CEnFakeStore g_store;'),
        ('namespace alias', 'src/include/EntryStateFile.mqh', '"VELO_T017_SELFTEST_" : "VELO_T016_FAKE_"', '"VELO_T016_FAKE_" : "VELO_T016_FAKE_"'),
        ('missing path guard', 'src/include/EntryStateFile.mqh', 'ch==95)) return("");', 'ch==95)) {}'),
        ('nested lock', 'src/include/EntryStateFile.mqh', 'if(name=="" || m_key!="") return(false);', 'if(name=="") return(false);'),
        ('wrong release', 'src/include/EntryStateFile.mqh', 'if(m_key=="" || m_key!=key) return;', 'if(m_key=="") return;'),
        ('invalid missing', 'src/include/EntryStateFile.mqh', 'mapped=="" ? true', 'mapped=="" ? false'),
        ('file protocol changed', 'src/include/EntryStateFile.mqh', 'FileMove(tmp,0,name,FILE_REWRITE)', 'FileMove(tmp,0,name,0)'),
        ('test cleanup boundary', 'src/tests/EntryPersistenceTest.mq5', 'if(StringFind(name,"VELO_T017_SELFTEST_")!=0) return(false);', ''),
    ]
    for name, path, old, new in mutations:
        assert files[path].count(old) == 1, 'vacuous mutation: ' + name
        changed = dict(files)
        changed[path] = files[path].replace(old, new)
        try:
            verify(changed)
        except AssertionError:
            print('PASS negative control:', name)
        else:
            raise AssertionError('negative control survived: ' + name)
    print('ENTRY PERSISTENCE STATIC CHECKS: ALL PASS (static only; owner MT5 run pending)')


if __name__ == '__main__':
    main()
