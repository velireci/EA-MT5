#!/usr/bin/env python3
"""Compare every StringFormat/PrintFormat format string in the T001 sources
against its argument count. A mismatch compiles but prints garbage at runtime."""
import re, sys, glob

FILES = ['src/XauUsdFoundation.mq5'] + sorted(glob.glob('src/include/*.mqh'))
SPEC = re.compile(r'%(?:[-+ #0]*)(?:\d+|\*)?(?:\.\d+)?(?:I64|ll|h)?([diuxXeEfgGsc%])')


def split_args(body):
    args, depth, cur, j = [], 0, '', 0
    while j < len(body):
        c = body[j]
        if c == '"':
            cur += c
            j += 1
            while j < len(body) and body[j] != '"':
                if body[j] == '\\':
                    cur += body[j]
                    j += 1
                cur += body[j]
                j += 1
            cur += body[j] if j < len(body) else ''
        elif c in '([':
            depth += 1
            cur += c
        elif c in ')]':
            depth -= 1
            cur += c
        elif c == ',' and depth == 0:
            args.append(cur)
            cur = ''
        else:
            cur += c
        j += 1
    args.append(cur)
    return args


def main():
    bad = 0
    for path in FILES:
        src = open(path).read()
        for m in re.finditer(r'\b(StringFormat|PrintFormat)\s*\(', src):
            i, depth, start = m.end(), 1, m.end()
            while i < len(src) and depth > 0:
                c = src[i]
                if c == '"':
                    i += 1
                    while i < len(src) and src[i] != '"':
                        i += 2 if src[i] == '\\' else 1
                elif c == '(':
                    depth += 1
                elif c == ')':
                    depth -= 1
                i += 1
            args = split_args(src[start:i - 1])
            specs = [s for s in SPEC.findall(args[0]) if s != '%']
            nargs = len(args) - 1
            if len(specs) != nargs:
                line = src[:m.start()].count('\n') + 1
                print(f"  FAIL {path}:{line} {m.group(1)}: "
                      f"{len(specs)} specifier(s), {nargs} argument(s)")
                bad += 1
    if bad:
        print(f"  FAIL: {bad} mismatch(es)")
        return 1
    print("  PASS: every format string matches its argument count")
    return 0


if __name__ == '__main__':
    sys.exit(main())
