#!/usr/bin/env python3
# aid-redact-filter.py <name> — one stream in, its last 8 KiB redacted out (P117): the measurement's points
# (aid-plan-diff.sh) and the plan's nightly tests at the close (lib/aid-plan-tests.sh) never write raw output.
# The values to redact come in AID_PD_SECRETS (one per line); token shapes and URL credentials always.
import os, re, signal, sys
SEC = sorted({s for s in os.environ.get("AID_PD_SECRETS", "").split("\n") if s}, key=len, reverse=True)
name, lim = sys.argv[1], 8192
# the raw tail is kept in memory only, with a margin longer than any secret; it is redacted as one piece at the
# end, so a value split across two reads is still caught, and the margin (where a cut-off fragment of a secret
# or token could sit) is dropped before anything is written (Codex, P117 A+C round 2)
margin = max([len(x.encode()) for x in SEC] + [0]) + 128
raw, total, binary = b"", 0, False
def red(t):
    for s in SEC: t = t.replace(s, "[redigováno]")
    t = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+", r"\1[redigováno]", t)
    t = re.sub(r"\b(sk-[A-Za-z0-9_-]{8,}|ghp_[A-Za-z0-9]{20,}|xox[abp]-[A-Za-z0-9-]{10,})", "[redigováno]", t)
    return re.sub(r"(://)[^/\s:@]+:[^/\s@]+@", r"\1[redigováno]@", t)   # scheme://user:password@
def done(*_):
    head = "--- std%s (%d bytes%s) ---\n" % (name, total, ", last 8192 shown" if total > lim else "")
    if binary: body = "[binary output, %d bytes]" % total
    else:
        t = raw.decode("utf-8", "replace")
        if total > len(raw):                     # the window was cut: its start may hold a fragment of a
            t = re.sub(r"^\S*", "", t[margin:], count=1)   # secret, or of a token of any length
        body = red(t).encode()[-lim:].decode("utf-8", "ignore")
    sys.stdout.write(head + body + "\n"); sys.stdout.flush(); os._exit(0)
signal.signal(signal.SIGTERM, done)
while True:
    chunk = sys.stdin.buffer.read1(1 << 16)
    if not chunk: break
    total += len(chunk)
    if b"\0" in chunk: binary = True
    if not binary: raw = (raw + chunk)[-(lim + 2 * margin):]
done()