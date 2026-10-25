#!/usr/bin/env python3
"""Every `shift 2` in the plugin's scripts is preceded by a check that two arguments are left.

Without it, an option given last without its value makes `shift 2` shift nothing: a script without
`set -e` loops forever (aid-plan-check.sh --json, WAN P115, 25. 10. 2026), one with `set -u` dies on
`$2: unbound variable`. The check must stand before the value is first read.

Check mode (default) lists every unguarded site and every inserted guard whose action is not the one
below, and exits 1. `--fix` inserts the guard with ONE action for every context:
`return 2 2>/dev/null || exit 2` — inside a function it returns (a script such as aid-fsm.sh is also
sourced, and an `exit` there would end the caller), at top level `return` fails and it exits (a
`return` alone there loops on, aid-review-round.sh, Codex review 25. 10. 2026). No guessing where a
function ends. Deliberate exceptions live
in opt-value-guard-allow.txt, one `<path>: <line as written>  # <reason>` per line.
Used by test-opt-value-guard.bats.

Usage: opt-value-guard.py <plugin-root> [--fix]
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
apply = '--fix' in sys.argv[2:]
ALLOW_FILE = pathlib.Path(__file__).with_name('opt-value-guard-allow.txt')

CNT = re.compile(r'\$# -ge 2|\$# -lt 2|\(\( *\$# *>= *2 *\)\)|\$# -gt 1|\$# -le 1|_require_optval'
                 r'|\[\[ -n "\$\{2:-\}" \]\] \|\||\[\[ "\$\{2:-\}" (==|=~) .*\]\] \|\|')
READ2 = re.compile(r'\$2\b|\$\{2[:}?-]')
ARM = re.compile(r'^(\s*(?:[-\w|*"\'.=]+)\)\s+)(.*)$')
PATONLY = re.compile(r'^\s*[-\w|*"\'.=]+\)\s*$')
FUNC = re.compile(r'^\s*(function\s+)?[\w:.-]+\s*\(\)\s*\{')
OURS = re.compile(r'echo "\$\{(?:0##\*/|FUNCNAME\[0\]:-\$\{0##\*/\})\}: (?:\$\{1:-\} needs a value|needs 2 arguments, got \$#)" >&2; ([^}]*)\}')  # only guards this tool inserts
ACT = 'return 2 2>/dev/null || exit 2'

allow = set()
if ALLOW_FILE.exists():
    for a in ALLOW_FILE.read_text().splitlines():
        a = a.split('  #', 1)[0].strip()
        if a and not a.startswith('#'):
            allow.add(a)
used = set()


def guard(lib, positional):
    name = '${FUNCNAME[0]:-${0##*/}}' if lib else '${0##*/}'
    what = 'needs 2 arguments, got $#' if positional else '${1:-} needs a value'
    return '[[ $# -ge 2 ]] || { echo "%s: %s" >&2; %s; }' % (name, what, ACT)


problems = []
for f in sorted(root.glob('scripts/**/*.sh')):
    rel = f.relative_to(root).as_posix()
    if rel.startswith('scripts/tests/'):
        continue
    lib = rel.startswith('scripts/lib/')
    L = f.read_text().split('\n')
    ins = []
    for i, l in enumerate(L):
        if l.lstrip().startswith('#'):
            continue
        mo = OURS.search(l)
        if mo and mo.group(1).strip().rstrip(';').strip() != ACT:
            problems.append(f'WRONG-ACTION {rel}:{i+1}: {l.strip()}')
        if not re.search(r'\bshift 2\b', l):
            continue
        if f'{rel}: {l.strip()}' in allow:
            used.add(f'{rel}: {l.strip()}')
            continue
        pos = l.index('shift 2')
        m2 = READ2.search(l)
        first_read = m2.start() if m2 else pos
        mc = CNT.search(l[:pos])
        if mc and mc.start() < first_read:
            continue
        ok = False
        j = i - 1
        anchor = None
        while j >= 0 and i - j <= 8:
            lj = L[j]
            if ';;' in lj or re.match(r'\s*case ', lj):   # the previous arm's check is not this arm's
                break
            if CNT.search(lj):
                ok = True
                break
            if FUNC.match(lj):
                anchor = ('func', j)
                break
            if PATONLY.match(lj):
                anchor = ('pat', j)
                break
            j -= 1
        if ok:
            continue
        problems.append(f'UNGUARDED {rel}:{i+1}: {l.strip()}')
        m = ARM.match(l)
        if m and m2:
            ins.append((i, 'arm'))
        elif anchor:
            ins.append((anchor[1], anchor[0]))
    if apply and ins:
        for i, mode in sorted(set(ins), reverse=True):
            if mode == 'arm':
                m = ARM.match(L[i])
                L[i] = m.group(1) + guard(lib, False) + '; ' + m.group(2)
            else:
                ind = re.match(r'\s*', L[i + 1]).group(0)
                L.insert(i + 1, ind + guard(lib, mode == 'func'))
        f.write_text('\n'.join(L))

for a in sorted(allow - used):
    if (root / a.split(':', 1)[0]).exists():   # an entry about another tree (a test's fixture root) is not stale here
        problems.append(f'STALE-ALLOW {a}')
if apply:
    problems = [p for p in problems if not p.startswith('UNGUARDED')]
for p in problems:
    print(p)
sys.exit(1 if problems else 0)
