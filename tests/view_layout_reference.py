"""Python MIRROR of the pure layout helpers of src/include/EntryOrchestratorView.mqh (EV_Wrap, EV_Select): word wrap of a panel line to the characters that fit the chart, and the choice of the
lines to keep when the chart is too small. Lines carry a priority (0 = never dropped, larger = dropped first, later lines before earlier ones of the same priority); a dropped line is announced by ONE
marker row. Pure: no chart, no object."""

MARKER = '(+%d te fshehura)'
MIN_WIDTH = 8


def wrap(text, width):
    width = max(width, MIN_WIDTH)
    if len(text) <= width:
        return [text]
    rows = []
    cur = ''
    for w in text.split(' '):
        if w == '':
            continue
        indent = '' if not rows else '  '
        room = width - len(indent)
        cand = w if cur == '' else cur + ' ' + w
        if len(cand) <= room:
            cur = cand
            continue
        if cur != '':
            rows.append(indent + cur)
            cur = ''
            indent = '  '
            room = width - 2
        while len(w) > room:
            rows.append(('' if not rows else '  ') + w[:room])
            w = w[room:]
            room = width - 2
        cur = w
    if cur != '':
        rows.append(('' if not rows else '  ') + cur)
    return rows


def select(texts, prios, width, max_rows):
    """-> (keep flags, dropped count, total rows including the marker row)"""
    n = len(texts)
    rows = [len(wrap(t, width)) for t in texts]
    keep = [True] * n
    total = sum(rows)
    dropped = 0
    while total + (1 if dropped else 0) > max_rows:
        pick = -1
        for i in range(n):
            if keep[i] and prios[i] > 0 and (pick < 0 or prios[i] >= prios[pick]):
                pick = i
        if pick < 0:
            break
        keep[pick] = False
        total -= rows[pick]
        dropped += 1
    return keep, dropped, total + (1 if dropped else 0)
