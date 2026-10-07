#!/usr/bin/env python3
"""Check that braces, parentheses and brackets balance in the T001 sources.

Comments and string/character literals are stripped first, so a brace inside
a comment or a string does not count. Exits 1 if any file is unbalanced, so
the caller can fold the result into its own exit status.
"""
import re
import sys

PAIRS = (('{', '}', 'braces'), ('(', ')', 'parens'), ('[', ']', 'brackets'))


def strip(src):
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    src = re.sub(r'"(\\.|[^"\\])*"', '""', src)
    src = re.sub(r"'(\\.|[^'\\])*'", "''", src)
    return src


def main(paths):
    if not paths:
        print("  FAIL: no files given to check")
        return 1
    bad = 0
    for path in paths:
        try:
            src = strip(open(path).read())
        except OSError as exc:
            print(f"  FAIL {path}: cannot read ({exc.strerror})")
            bad += 1
            continue
        ok = True
        for opener, closer, name in PAIRS:
            delta = src.count(opener) - src.count(closer)
            if delta:
                print(f"  FAIL {path}: {name} unbalanced by {delta:+d}")
                ok = False
        if ok:
            print(f"  PASS {path}: braces/parens/brackets balanced")
        else:
            bad += 1
    if bad:
        print(f"  FAIL: {bad} file(s) unbalanced")
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
