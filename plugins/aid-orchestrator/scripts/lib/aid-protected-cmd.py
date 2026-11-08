#!/usr/bin/env python3
"""aid-protected-cmd.py — does a substitute measuring command (stdin) touch a protected path? (3.16.0, K7)

Prints "<class>: <why>" and nothing else when it does; prints nothing when the command is technical.
GLOBS (env): the protected globs, space separated. Used by lib/aid-protected.sh for kind ac_command.
"""
import fnmatch, os, re, shlex, sys
cmd = sys.stdin.read()
bare = re.sub(r"'[^']*'", "''", cmd)   # inside single quotes nothing expands: a literal backtick stays a backtick
if re.search(r"\$[({A-Za-z_0-9]|`|\b(eval|source|exec)\b|\b(ba|z|da|k)?sh\s+-c\b|<\(|>\(", bare):
    print("security: the new command expands variables, substitutes a command or starts a nested shell"); sys.exit()
try:
    words = shlex.split(cmd, comments=False, posix=True)
except ValueError as e:
    print("unevaluable: the new command does not parse as shell words (%s)" % e); sys.exit()
globs = [g.lower() for g in os.environ["GLOBS"].split()]
names = [".env", ".env.local", "secrets.yml", "credentials.json", "deploy/x", ".aid-o/config/execution.yaml"]
def hit(path):
    p = path.lower()
    while p.startswith("./"): p = p[2:]
    for cand in {p, os.path.basename(p)}:
        for g in globs:
            if fnmatch.fnmatch(cand, g) or ("/" not in g and fnmatch.fnmatch(os.path.basename(cand), g)):
                return g
    return None
for w in words:
    for part in re.split(r"[=:,]", w):
        if not part: continue
        g = hit(part)
        if g: print("security: the new command names %s, which matches the protected path %s" % (part, g)); sys.exit()
        if any(c in part for c in "*?["):
            for n in names:
                pl = part.lower()
                while pl.startswith("./"): pl = pl[2:]
                if fnmatch.fnmatch(n, pl) or fnmatch.fnmatch(os.path.basename(n), os.path.basename(pl)):
                    print("security: the new command has the glob %s, which reaches the protected %s" % (part, n)); sys.exit()
