"""T017 file-store/namespace mirror. Existing entry codec and executor are reused.
Locks model one terminal in this Python process; files are real temporary files.
This is not a broker or a cross-process lock implementation.
"""
from pathlib import Path
import os
import re

_HELD = set()


def physical(name, lock=False, selftest=False):
    prefix = 'VELO_T013_LOCK_' if lock else 'VELO_T013_ENTRY_'
    if not isinstance(name, str) or not name.startswith(prefix):
        return ''
    stem = name if lock else name[:-6] if name.endswith('.state') else ''
    if len(stem) <= len(prefix) or not re.fullmatch(r'[A-Za-z0-9_]+', stem):
        return ''
    result = ('VELO_T017_SELFTEST_' if selftest else 'VELO_T016_FAKE_') + name
    return result if len(result) <= (63 if lock else 240) else ''


class FileStore:
    def __init__(self, root, selftest=False):
        self.root = Path(root).resolve()
        self.selftest = selftest
        self.held = None

    def path(self, name):
        mapped = physical(name, selftest=self.selftest)
        return self.root / mapped if mapped else None

    def lock(self, key):
        mapped = physical(key, True, self.selftest)
        token = (str(self.root), mapped)
        if not mapped or self.held is not None or token in _HELD:
            return False
        _HELD.add(token)
        self.held = (key, token)
        return True

    def unlock(self, key):
        if self.held is not None and self.held[0] == key:
            _HELD.discard(self.held[1])
            self.held = None

    def exists(self, name):
        path = self.path(name)
        return True if path is None else path.exists()

    def read(self, name):
        path = self.path(name)
        if path is None:
            return False, ''
        try:
            return True, path.read_text(encoding='ascii')
        except (OSError, UnicodeError):
            return False, ''

    def write(self, name, text):
        path = self.path(name)
        if path is None:
            return False
        tmp = path.with_name(path.name + '.tmp')
        if tmp.exists():
            return False
        try:
            tmp.write_text(text, encoding='ascii', newline='')
            if tmp.read_text(encoding='ascii') != text:
                tmp.unlink(missing_ok=True)
                return False
            os.replace(tmp, path)
            return path.read_text(encoding='ascii') == text
        except (OSError, UnicodeError):
            tmp.unlink(missing_ok=True)
            return False
