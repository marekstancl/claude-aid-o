#!/usr/bin/env python3
"""aid-ui-sources.py - the sources /aid-ui reads before asking anything about the product (step 1p).

  python3 aid-ui-sources.py <project> --list [--old-site <dir>] [--sessions-dir <dir>]... [--sessions-from <path>]... [--out <file>]
  python3 aid-ui-sources.py <project> [--session <file.jsonl>]... [--sessions-from <path>]... [--old-site <dir>] [--out <file>]

--list writes the candidates: the project's own files (PRODUCT.md, README*, *.md in the root,
docs/** md/txt/html, not docs/brand, docs/design, .aid-ui) and the Claude Code session logs of the
project (~/.claude/projects/<project path with / and . as ->/*.jsonl, or --sessions-dir), each with
its date range, the number of the human's own records and up to five excerpts of at most 300
characters for the studio card (redacted first, then cut). A session's text does not enter the
sources in this mode. Only records whose working directory (cwd) is the project or under it count;
--sessions-from adds another root (the original project of a pilot copy). A file with no such
record is not a candidate, so another project's sessions never reach the studio.

The manifest mode (no --list) also reads the sessions passed with --session, but only a session the
PM approved: brand-state.json must hold an answer of kind "sources", decision "approve", whose target
is "<file>@<sha256 of the file>". A record counts as the human's own text only when type is "user",
isMeta is not true, origin.kind is absent or "human", the content is text (no tool_result) and it is
not a system reminder, a command wrapper or pasted content. Everything kept - excerpts included - is
redacted by the shared detector table (_aid_artifact_redact of scripts/lib/aid-artifact-render.sh,
called through bash so the grep -E patterns are used as written) and the hits are counted.

Output: <project>/.aid-ui/sources/manifest.json (or --out) and, in manifest mode, the redacted text
of each used session in .aid-ui/sources/session-<id>.txt for the agent to read. Never a whole
session in the manifest. Exit 0 written, 1 refused (unapproved session, unreadable project),
2 usage.
"""
import argparse, datetime, glob, hashlib, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RENDER_LIB = os.path.join(HERE, "lib", "aid-artifact-render.sh")
TEXT_EXT = (".md", ".txt", ".html")
SKIP_DIRS = {"node_modules", ".git", ".aid-ui", "dist", "build", "out", "site"}
NOT_HUMAN = re.compile(r"<(system-reminder|command-name|command-message|command-args|local-command-stdout|pasted_content|task-notification)\b", re.I)


def die(msg, code=1):
    print(f"ERROR: aid-ui-sources.py: {msg}", file=sys.stderr)
    sys.exit(code)


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def redact(text):
    """(redacted text, hits) through the plugin's own detector table."""
    script = 'source "$1"; t="$(cat)"; c=0; _aid_artifact_redact t c; printf "%s\\n%s" "$c" "$t"'
    r = subprocess.run(["bash", "-c", script, "_", RENDER_LIB], input=text, capture_output=True, text=True)
    if r.returncode != 0:
        die(f"redaction failed: {r.stderr.strip()[:200]}")
    count, _, out = r.stdout.partition("\n")
    return out, int(count or 0)


def human_records(path, roots):
    """(timestamp, text) of the human's own messages whose cwd is under one of roots; torn lines."""
    torn = 0
    out = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                j = json.loads(line)
            except ValueError:
                torn += 1
                continue
            if j.get("type") != "user" or j.get("isMeta") is True:
                continue
            cwd = os.path.realpath(j["cwd"]) if isinstance(j.get("cwd"), str) else None
            if not cwd or not any(cwd == r or cwd.startswith(r + os.sep) for r in roots):
                continue
            origin = j.get("origin")
            kind = origin.get("kind") if isinstance(origin, dict) else origin
            if kind not in (None, "human"):
                continue
            content = (j.get("message") or {}).get("content")
            if isinstance(content, list):
                if any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
                    continue
                content = "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
            if not isinstance(content, str) or not content.strip() or NOT_HUMAN.search(content):
                continue
            out.append((j.get("timestamp", ""), content))
    return out, torn


def project_files(proj):
    files = []
    for name in sorted(os.listdir(proj)):
        p = os.path.join(proj, name)
        if os.path.isfile(p) and (name.endswith(".md") or name.startswith("README")):
            files.append(p)
    docs = os.path.join(proj, "docs")
    for root, dirs, names in os.walk(docs):
        rel = os.path.relpath(root, proj)
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and os.path.join(rel, d) not in ("docs/brand", "docs/design", "docs/zakaznik")]   # our own outputs are not sources
        files += [os.path.join(root, n) for n in sorted(names) if n.endswith(TEXT_EXT)]
    return files


def session_dir(proj):
    enc = re.sub(r"[/.]", "-", os.path.realpath(proj))
    return os.path.join(os.path.expanduser("~/.claude/projects"), enc)


def approved_sessions(proj):
    st = os.path.join(proj, "docs/design/brand-state.json")
    try:
        answers = json.load(open(st, encoding="utf-8")).get("answers") or {}
    except (OSError, ValueError):
        return set()
    return {str(a.get("target")) for a in answers.values()
            if isinstance(a, dict) and a.get("kind") == "sources" and a.get("decision") == "approve"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--session", action="append", default=[])
    ap.add_argument("--sessions-dir", action="append", default=[])
    ap.add_argument("--sessions-from", action="append", default=[])
    ap.add_argument("--old-site")
    ap.add_argument("--out")
    a = ap.parse_args()
    proj = os.path.abspath(a.project)
    if not os.path.isdir(proj):
        die(f"no project directory {proj}", 2)
    out = a.out or os.path.join(proj, ".aid-ui/sources/manifest.json")
    roots = [os.path.realpath(proj)] + [os.path.realpath(x) for x in a.sessions_from]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sources, secrets_total = [], 0
    for p in project_files(proj) + ([os.path.join(r, n) for r, _, ns in os.walk(a.old_site) for n in ns if n.endswith(TEXT_EXT)] if a.old_site else []):
        kind = "old_site" if a.old_site and os.path.abspath(p).startswith(os.path.abspath(a.old_site)) else "project"
        try:
            sources.append({"path": os.path.relpath(p, proj), "kind": kind, "size": os.path.getsize(p), "sha256": sha(p),
                            "used": True, "reason": "", "secret_lines_removed": 0})
        except OSError as e:
            sources.append({"path": os.path.relpath(p, proj), "kind": kind, "size": None, "sha256": None,
                            "used": False, "reason": e.strerror, "secret_lines_removed": 0})
    man = {"generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "sources": sources}
    if a.list:
        cands = []
        files = sorted({f for sd in (a.sessions_dir or [session_dir(proj)]) for f in glob.glob(os.path.join(os.path.abspath(sd), "*.jsonl"))})
        for f in files:
            recs, torn = human_records(f, roots)
            if not recs:
                continue   # no record of this project: never shown
            excerpts = []
            for _, t in recs[:5]:
                red, hits = redact(t)   # the whole record first, then cut: a secret never straddles the cut
                secrets_total += hits
                excerpts.append(" ".join(red.split())[:300])
            cands.append({"file": f, "sha256": sha(f), "records_human": len(recs), "torn_lines": torn,
                          "first_at": recs[0][0] if recs else "", "last_at": recs[-1][0] if recs else "", "excerpts": excerpts})
        man["candidates"] = cands
    else:
        ok = approved_sessions(proj)
        for f in a.session:
            f = os.path.abspath(f)
            if not os.path.isfile(f):
                die(f"no session file {f}")
            if f"{f}@{sha(f)}" not in ok:
                die(f"session {f} is not approved: answer a 'sources' question whose target is <file>@<sha256> first")
            recs, torn = human_records(f, roots)
            text, hits = redact("\n\n".join(t for _, t in recs))
            sid = f"{os.path.splitext(os.path.basename(f))[0]}-{sha(f)[:12]}"   # same basename elsewhere never collides
            txt = os.path.join(os.path.dirname(out), f"session-{sid}.txt")
            with open(txt, "w", encoding="utf-8") as fh:
                fh.write(text)
            sources.append({"path": f, "kind": "session", "size": os.path.getsize(f), "sha256": sha(f), "used": True,
                            "reason": "", "records_human": len(recs), "torn_lines": torn, "secret_lines_removed": hits,
                            "text": os.path.relpath(txt, proj)})
            secrets_total += hits
    man["secrets_removed"] = secrets_total
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(man, fh, ensure_ascii=False, indent=1)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
