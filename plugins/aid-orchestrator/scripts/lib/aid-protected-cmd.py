#!/usr/bin/env python3
"""aid-protected-cmd.py — may a stand-in approve this substitute measuring command (stdin)? (3.16.0, K7)

An ALLOWLIST, not a list of what is forbidden (a denylist over shell text was bypassed five ways in review):
the command is one or more simple commands joined by && || | (and a leading !), each one of
  grep (no -r/-R/--recursive, no -f/--file), test / [, jq (no --rawfile/--slurpfile), wc,
  git log | show | diff | ls-files | rev-parse | cat-file -e
with nothing the shell would expand outside single quotes ($, `, unquoted * ? [ { ~ and backslashes are allowed
only inside quotes), and no word that, normalised, names a protected path (GLOBS env: space-separated globs,
matched at any depth). Anything else is printed as "<class>: <why>" and goes to the PM; nothing printed = technical.
"""
import fnmatch
import os
import shlex
import sys

cmd = sys.stdin.read().strip()
globs = [g.lower() for g in os.environ.get("GLOBS", "").split()]


def out(msg):
    print(msg)
    sys.exit(0)


if any(ord(c) < 32 for c in cmd):
    out("security: the new command has a newline or a control character — one line, printable characters only")

# 1. what the shell would expand, outside single quotes (inside double quotes $ and ` still expand)
q = None
i = 0
while i < len(cmd):
    c = cmd[i]
    if q == "'":
        q = None if c == "'" else q
    elif c == "\\":
        if q is None:
            out("security: the new command has a backslash outside quotes — write the character inside quotes")
        i += 1
    elif q == '"':
        if c in "$`":
            out("security: the new command expands %s inside double quotes — use single quotes" % c)
        if c == '"':
            q = None
    else:
        if c in "'\"":
            q = c
        elif c == "[" and (i == 0 or cmd[i - 1] in " \t&|!") and cmd[i + 1:i + 2] in (" ", "\t"):
            pass   # the test command [ … ], a word of its own
        elif c in "$`*?[{~":
            out("security: the new command has %s outside quotes (the shell expands it) — quote the pattern" % c)
        elif c in ";<>()":
            out("security: the new command uses %s — only && || | ! join commands in a substitute" % c)
        elif c == "&" and cmd[i:i + 2] != "&&" and cmd[i - 1:i + 1] != "&&":
            out("security: the new command runs something in the background (&)")
    i += 1
if q is not None:
    out("unevaluable: the new command leaves a quote open")

# 2. the words, split into simple commands at && || |
try:
    lex = shlex.shlex(cmd, posix=True, punctuation_chars="&|!")
    lex.whitespace_split = True
    words = list(lex)
except ValueError as e:
    out("unevaluable: the new command does not parse as shell words (%s)" % e)
segments, cur = [], []
for w in words:
    if w in ("&&", "||", "|"):
        segments.append(cur)
        cur = []
    elif w == "!":
        if cur:
            cur.append(w)   # test ! -e x: an argument of test, not an operator
    elif set(w) <= set("&|!"):
        out("security: the new command uses %s — only && || | ! join commands" % w)
    else:
        cur.append(w)
segments.append(cur)
if any(not s for s in segments):
    out("unevaluable: an empty command between the operators")

GIT_SUB = {"log", "show", "diff", "ls-files", "rev-parse", "cat-file"}


def protected(word):
    for part in [word] + word.replace("=", ":").split(":"):
        if not part:
            continue
        p = os.path.normpath(part).lower()
        if p.startswith("-"):
            continue
        for cand in (p, os.path.basename(p)):
            for g in globs:
                if fnmatch.fnmatch(cand, g) or fnmatch.fnmatch(cand, "*/" + g) or fnmatch.fnmatch(p, "*/" + g):
                    return part, g
    return None


GREP_LETTERS = set("qEFinclwxvsHh")
GIT_BAD = ("--output", "--no-index", "--ext-diff", "--textconv", "--git-dir", "--work-tree", "--exec-path", "-O", "-c", "-C")
JQ_BAD_WORDS = ("env", "$ENV", "input_filename", "import", "include", "$__loc__", "$__prog_args", "debug", "stderr")


def plain_path(a, what):
    if any(c in a for c in "*?[") or a.startswith(":("):
        out("security: %s %s has a glob or pathspec magic — name the file" % (what, a))
    if os.path.isabs(a) or ".." in os.path.normpath(a).split(os.sep):
        out("security: %s %s is outside the plan's tree" % (what, a))


for seg in segments:
    if "/" in seg[0]:
        out("security: %s is a path to a program — name the program (grep, test, [, jq, wc, git)" % seg[0])
    prog, args = seg[0], seg[1:]
    if prog == "grep":
        pattern_given, positional, k = False, [], 0
        while k < len(args):
            a = args[k]
            if a == "-e":
                pattern_given = True; k += 2; continue
            if a == "--":
                positional += args[k + 1:]; break
            if a.startswith("-"):
                if a.startswith("--") or not set(a[1:]) <= GREP_LETTERS:
                    out("security: grep %s is not a flag a substitute may use (-%s, -e)" % (a, "".join(sorted(GREP_LETTERS))))
            else:
                positional.append(a)
            k += 1
        files = positional if pattern_given else positional[1:]
        for a in files:
            plain_path(a, "grep file")
    elif prog in ("test", "[", "wc"):
        for a in args:
            if not a.startswith("-") and a not in ("!", "]", "=", "!="):
                if any(c in a for c in "*?["):
                    out("security: %s %s has a glob — name the file" % (prog, a))
    elif prog == "jq":
        if any(a.startswith(("-L", "--library-path", "--rawfile", "--slurpfile", "--from-file", "-f", "--args", "--jsonargs")) for a in args):
            out("security: jq with a file, library or argument option reads beyond what it names")
        prog_txt = next((a for a in args if not a.startswith("-")), "")
        if any(w in prog_txt for w in JQ_BAD_WORDS):
            out("security: the jq program reads the environment, a library or a file name")
        for a in [a for a in args if not a.startswith("-")][1:]:
            plain_path(a, "jq file")
    elif prog == "git":
        if not args or args[0] not in GIT_SUB:
            out("security: git %s is not a read-only git a substitute may run (%s)" % (args[0] if args else "", ", ".join(sorted(GIT_SUB))))
        if args[0] == "cat-file" and "-e" not in args:
            out("security: git cat-file only as -e (existence) in a substitute")
        for a in args[1:]:
            if a.startswith(GIT_BAD):
                out("security: git %s writes, runs a program or leaves the repository" % a)
            if not a.startswith("-"):
                plain_path(a.split(":", 1)[-1] if ":" in a else a, "git argument")
    else:
        out("security: %s is not one of the commands a substitute may run (grep, test, [, jq, wc, read-only git)" % prog)
    for a in args:
        hit = protected(a)
        if hit:
            out("security: the new command names %s, which matches the protected path %s" % hit)
