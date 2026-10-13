#!/usr/bin/env python3
"""MQL5 -> C++ transliteration for EVIDENCE only (T003, revision 10).

NOT MetaEditor, NOT the MQL5 compiler, NOT an MT5 run. It converts the subset of MQL5 that
src/include/H4Structure.mqh, src/include/H4Bias.mqh and src/tests/T003_LogicTest.mq5 use into C++
(see mql_shim.hpp for the MQL5 built-ins it emulates), so that the SAME logic and the SAME test
script can be compiled with g++ (+ AddressSanitizer / UBSan) and executed. A pass shows that the
transliterated logic agrees with the Python model on the controlled cases; it does not prove that
MetaEditor accepts the source or that MT5 behaves the same (string/array semantics are emulated).

Usage: mql2cpp.py IN.mqh|IN.mq5 OUT.hpp|OUT.cpp [--test]
"""
import calendar
import re
import sys


def strip_line_comments(src):
    out = []
    for line in src.split('\n'):
        res = []
        i = 0
        instr = False
        while i < len(line):
            c = line[i]
            if instr:
                res.append(c)
                if c == '\\':
                    res.append(line[i + 1])
                    i += 2
                    continue
                if c == '"':
                    instr = False
            else:
                if c == '"':
                    instr = True
                    res.append(c)
                elif c == '/' and line[i:i + 2] == '//':
                    break
                else:
                    res.append(c)
            i += 1
        out.append(''.join(res).rstrip())
    return '\n'.join(out)


def convert(src, is_test):
    t = strip_line_comments(src)
    t = re.sub(r'/\*.*?\*/', '', t, flags=re.S)
    if is_test:
        def dl(m):
            y, mo, d, h, mi = map(int, re.match(r"(\d+)\.(\d+)\.(\d+) (\d+):(\d+)", m.group(1)).groups())
            return '%dLL' % calendar.timegm((y, mo, d, h, mi, 0))
        t = re.sub(r"D'([^']+)'", dl, t)
        t = re.sub(r'(?m)^(\s*)([A-Za-z_]\w*)\s+([A-Za-z_]\w*)\[\]\s*=\s*\{(.*?)\};',
                   lambda m: '%sMArr<%s> %s = {{%s}};' % (m.group(1), m.group(2), m.group(3), m.group(4)), t, flags=re.S)
    t = re.sub(r'"(?:[^"\\\n]|\\.)*"', lambda m: 'S(' + m.group(0) + ')', t)
    t = re.sub(r'#include\s+S\("([^"]+)"\)', lambda m: '#include "' + m.group(1).split('/')[-1].replace('.mqh', '.hpp') + '"', t)
    t = t.replace('#property', '//#property')
    t = re.sub(r'\b(const\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*&\s*([A-Za-z_][A-Za-z0-9_]*)\s*\[\]',
               lambda m: '%sMArr<%s> &%s' % (m.group(1) or '', m.group(2), m.group(3)), t)
    t = re.sub(r'(?m)^(\s*)([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\[\]\s*;',
               lambda m: '%sMArr<%s> %s;' % (m.group(1), m.group(2), m.group(3)), t)
    if is_test:
        t = re.sub(r'(?m)^(\s*)([A-Za-z_]\w*)\s+([A-Za-z_]\w*)\[([A-Za-z0-9_]+)\]\s*;',
                   lambda m: '%sMArr<%s> %s(%s);' % (m.group(1), m.group(2), m.group(3), m.group(4)), t)
        t += '\nint main(){ OnStart(); return g_fail == 0 ? 0 : 1; }\n'
    else:
        if 'H4Structure' not in t[:200]:
            pass
    return t


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    is_test = '--test' in sys.argv
    src = open(args[0]).read()
    out = convert(src, is_test)
    if args[0].endswith('H4Structure.mqh'):
        out = '#include "mql_shim.hpp"\n' + out
    open(args[1], 'w').write(out)


if __name__ == '__main__':
    main()
