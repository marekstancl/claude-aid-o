#!/usr/bin/env bash
# aid-test-content-scan.sh — deterministic content checks, every audit, no LLM.
#
# WHY THIS EXISTS
#   The report page has sections for duplicates, weak oracles and double-run
#   gates — and the audit collected data for none of them. Those findings had
#   been produced exactly once, by hand, after the owner asked where they were.
#   Everything here is mechanical: string comparison, regex, config reading.
#   Leaving mechanical work to an LLM analyst's diligence is how a whole week
#   of audits reported "keep" over unread files — this script is the same
#   lesson applied to content: what can be computed, is computed, every run.
#
# WHAT IT CHECKS (deterministic, evidence with file:line or file pairs):
#   1. duplicate_test_cases   — identical @test names in two different files
#   2. weak_oracle            — suites whose asserts are ≥80 % bare exit-code
#                               checks (schema-validator suites are exempt by
#                               name heuristic and MARKED, not silently skipped)
#   3. gate_overlap           — a test file reachable from two or more gate
#                               commands in execution.yaml (the double-run cost)
#   4. unreferenced_tests     — test files on disk that no inventory unit and
#                               no gate command references
#
# Output: <output>/content-scan.json  { schema_version, checks: {...} }
# Exit 0 even when findings exist — findings are the product, not a failure.

set -euo pipefail
_die() { echo "aid-test-content-scan.sh: $2" >&2; exit "$1"; }

project_root="" output="" inventory="" execution_yaml="" catalog=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)   [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --inventory)      [[ $# -ge 2 ]] || _die 2 "--inventory requires a value"; inventory="$2"; shift 2 ;;
    --execution-yaml) [[ $# -ge 2 ]] || _die 2 "--execution-yaml requires a value"; execution_yaml="$2"; shift 2 ;;
    --catalog)        [[ $# -ge 2 ]] || _die 2 "--catalog requires a value"; catalog="$2"; shift 2 ;;
    --output)         [[ $# -ge 2 ]] || _die 2 "--output requires a value"; output="$2"; shift 2 ;;
    *) _die 2 "unknown argument '$1'" ;;
  esac
done
[[ -n "$project_root" && -d "$project_root" ]] || _die 2 "--project-root is required and must exist"
[[ -n "$output" ]] || _die 2 "--output is required"
[[ -n "$execution_yaml" ]] || execution_yaml="${project_root%/}/.aid-o/config/execution.yaml"
command -v python3 >/dev/null 2>&1 || _die 2 "python3 is required"

[[ -n "$catalog" ]] || catalog="${project_root%/}/.aid-o/config/test-catalog.yaml"
PROJECT_ROOT="$project_root" OUTPUT="$output" INVENTORY="${inventory:-}" \
EXEC_YAML="$execution_yaml" CATALOG="${catalog:-}" python3 - <<'PY'
import json, os, re, glob, collections

ROOT = os.environ["PROJECT_ROOT"].rstrip("/")
OUT = os.environ["OUTPUT"]
INV = os.environ.get("INVENTORY") or ""
EXY = os.environ.get("EXEC_YAML") or ""

def rel(p): return os.path.relpath(p, ROOT)

# every test-looking file we can reason about mechanically
bats = sorted(glob.glob(f"{ROOT}/**/*.bats", recursive=True))
bats = [f for f in bats if "/.git/" not in f and "/node_modules/" not in f]

# test files of EVERY runner — the first cut scanned only bats, was pointed at
# a pytest project, and produced garbage in both directions: 813 "untested"
# sources that 42 tests import, and "0 unreferenced" over 153 test files no
# gate runs. An independent review caught both. Never again bats-only.
def _clean(paths):
    return [f for f in paths if "/.git/" not in f and "/node_modules/" not in f
            and "/.venv/" not in f and "/venv/" not in f]
py_tests = _clean(sorted(set(
    glob.glob(f"{ROOT}/**/test_*.py", recursive=True)
    + glob.glob(f"{ROOT}/**/*_test.py", recursive=True))))
ts_tests = _clean(sorted(set(
    glob.glob(f"{ROOT}/**/*.test.ts", recursive=True)
    + glob.glob(f"{ROOT}/**/*.test.tsx", recursive=True)
    + glob.glob(f"{ROOT}/**/*.spec.ts", recursive=True))))
all_tests = bats + py_tests + ts_tests

# ── 1. duplicate test cases ────────────────────────────────────────────────
cases = collections.defaultdict(list)
for f in bats:
    try: txt = open(f, errors="ignore").read()
    except Exception: continue
    for m in re.finditer(r'@test\s+"([^"]+)"', txt):
        cases[m.group(1)].append(rel(f))
pairs = collections.Counter()
for name, fs in cases.items():
    u = sorted(set(fs))
    if len(u) > 1:
        for i in range(len(u)):
            for j in range(i + 1, len(u)):
                pairs[(u[i], u[j])] += 1
duplicates = [{"file_a": a, "file_b": b, "shared_cases": n}
              for (a, b), n in pairs.most_common()]

# ── 2. weak oracles ────────────────────────────────────────────────────────
weak = []
for f in bats:
    try: txt = open(f, errors="ignore").read()
    except Exception: continue
    tests = len(re.findall(r"@test ", txt))
    asserts = re.findall(r"^\s*\[+ .*\]+\s*$", txt, flags=re.M)
    if tests < 5 or not asserts: continue
    status_only = sum(1 for a in asserts
                      if re.match(r'^\s*\[+ "\$status" -eq \d+ \]+\s*$', a))
    if status_only / len(asserts) >= 0.8:
        # A validator suite's whole point IS the exit code — marked, not hidden.
        validator_like = bool(re.search(r"schema|validate|lint", os.path.basename(f)))
        weak.append({"file": rel(f), "tests": tests,
                     "status_only_asserts": status_only,
                     "total_asserts": len(asserts),
                     "likely_legitimate": validator_like})

# ── 3. gate overlap (double runs) ──────────────────────────────────────────
# Static reachability: a .bats file is reachable from a gate whose command
# names it directly, or whose command runs an aggregate/pool runner. This is
# deliberately coarse — it flags CANDIDATE overlaps for the profiles that
# include both gates; the execution ledger remains the runtime proof.
overlap = []
gate_files = {}
try:
    import yaml
    ey = yaml.safe_load(open(EXY)) or {}
    gates = ey.get("gates") or {}
    POOLISH = re.compile(r"parallel-lane\.sh|run-all-tests\.sh")
    for g, spec in gates.items():
        cmd = (spec or {}).get("command") or ""
        direct = set(re.findall(r"[\w./-]+\.bats", cmd))
        gate_files[g] = {"direct": direct, "poolish": bool(POOLISH.search(cmd))}
    pool_gates = [g for g, v in gate_files.items() if v["poolish"]]
    for g, v in gate_files.items():
        for f in v["direct"]:
            for pg in pool_gates:
                if pg != g:
                    overlap.append({"file": f, "gate_direct": g, "gate_pool": pg,
                                    "note": "candidate double run when a profile includes both gates"})
    if len(pool_gates) > 1:
        overlap.append({"file": "(whole pool)", "gate_direct": pool_gates[0],
                        "gate_pool": pool_gates[1],
                        "note": "two aggregate runners — profiles including both run shared files twice"})
except Exception as e:
    overlap = [{"file": "(unreadable)", "gate_direct": "", "gate_pool": "",
                "note": f"execution.yaml could not be read: {e}"}]

# ── 4. unreferenced test files ─────────────────────────────────────────────
referenced = set()
if INV and os.path.exists(INV):
    try:
        for e in json.load(open(INV)).get("entries", []):
            uid = e.get("run_unit_id", "")
            _, _, path = uid.partition(":")
            if path: referenced.add(path.rstrip("/") )
    except Exception: pass
# reachability: a test file counts as RUN when the inventory names it, or a
# gate command's path token covers it, or — for marker-gated pytest commands —
# the file actually carries that marker. An independent review found 153 test
# files no gate runs while this check said "0", because it only looked at bats.
gate_cmds = []
try:
    import yaml as _y3
    _ey = _y3.safe_load(open(EXY)) or {}
    gate_cmds = [ (str((v or {}).get("command") or "")) for v in (_ey.get("gates") or {}).values() ]
except Exception:
    pass
# wrapper resolution, one level deep: a gate whose command is a shell script is
# opaque to path-token matching, so every file behind it counted as "unrun".
# A verification agent measured the real number at less than half of what this
# check reported — the overshoot was entirely wrapper opacity. Reading the
# wrapper's own text closes most of it.
_runner_line = re.compile(r"\b(pytest|vitest|jest|bats|playwright\s+test)\b|npm\s+(run\s+)?test\b|npx\s+vitest")
gate_texts = []
for cmd in gate_cmds:
    text = cmd
    for sh in re.findall(r"[\w./-]+\.sh\b", cmd):
        for cand in (os.path.join(ROOT, sh.lstrip("./")), sh):
            try:
                body = open(cand, errors="ignore").read()
            except Exception:
                continue
            # only lines that actually INVOKE a runner count — a wrapper that
            # merely mentions test paths (a registry checker looping over
            # tests/integration/*.py) must not mark those paths as run
            text += "\n" + "\n".join(l for l in body.splitlines() if _runner_line.search(l))
            break
    gate_texts.append(text)
_all_text = "\n".join(gate_texts)
# a bare js/ts runner invocation collects every matching file by convention —
# assume reachable; whether the runner's config actually collects them is the
# separate npm-collects-1-of-24 class of finding, not this one
_ts_runner = bool(re.search(r"\b(vitest|jest)\b|npm (run )?test\b|npx vitest", _all_text))
_pw_runner = bool(re.search(r"\bplaywright\s+test\b", _all_text))
def _reachable(rl, content):
    stem = re.sub(r"\.(bats|py|ts|tsx)$", "", rl)
    if referenced and any(stem in x or x in stem for x in referenced):
        return True
    if rl.endswith((".ts", ".tsx")):
        if ".spec." in rl and "/e2e/" in rl:
            return _pw_runner
        if _ts_runner:
            return True
    for cmd in gate_texts:
        toks = re.findall(r"[\w./-]+", cmd)
        path_toks = [t for t in toks if "/" in t and not t.endswith(".sh")]
        markers = re.findall(r"-m\s+([\w]+)", cmd)
        if markers:
            # a marker-filtered gate runs ONLY opted-in files — a path match
            # proves nothing (the exact overshoot-then-undershoot a verifying
            # agent measured: the truth was files without the marker)
            if any(f"pytest.mark.{mk}" in content or
                   ("pytestmark" in content and mk in content) for mk in markers if mk):
                return True
            continue
        if any(rl.startswith(t.rstrip("/") + "/") or rl == t for t in path_toks):
            return True
        if rl + "" in cmd:
            return True
    return False
unreferenced = []
for f in all_tests:
    r = rel(f)
    try: content = open(f, errors="ignore").read()
    except Exception: content = ""
    if (referenced or gate_cmds) and not _reachable(r, content):
        unreferenced.append({"file": r})

# ── 5. untested production surfaces (risk coverage) ───────────────────────
# Which tracked source files does NO test unit reference? Weighted by churn,
# because an untested file nobody touches is a smaller risk than an untested
# file changed weekly. Mechanical and honest: "referenced by a test" is a
# necessary condition of coverage, not proof of it — the report says so.
import subprocess
def git(*a):
    try:
        return subprocess.run(["git","-C",ROOT,*a],capture_output=True,text=True,timeout=60).stdout
    except Exception:
        return ""
untested = []
referenced_src = set()
try:
    import yaml as _y
    _cat = _y.safe_load(open(os.environ.get("CATALOG",""))) or {}
    for u in _cat.get("run_units", []):
        for k in ("source_paths","production_surfaces"):
            for pth in (u.get(k) or []):
                referenced_src.add(pth)
except Exception:
    pass
if INV and os.path.exists(INV):
    try:
        for e in json.load(open(INV)).get("entries", []):
            uid = e.get("run_unit_id","")
            _,_,pth = uid.partition(":")
            if pth: referenced_src.add(pth)
    except Exception: pass
tracked = [l for l in git("ls-files").splitlines()
           if re.search(r"\.(sh|ts|tsx|py|js)$", l)
           and "/tests/" not in l and not re.search(r"(^|/)test[-_.]", os.path.basename(l))
           and "/node_modules/" not in l]
# test file contents also reference scripts directly — count those too
ref_blob = " ".join(referenced_src)
for f in all_tests:
    try: ref_blob += open(f, errors="ignore").read()
    except Exception: pass
churn_raw = git("log","--since=90 days ago","--name-only","--pretty=format:")
churn = collections.Counter(l for l in churn_raw.splitlines() if l.strip())
for src in tracked:
    base = os.path.basename(src)
    # a Python test references wan/api/scan.py as `wan.api.scan` — the dotted
    # module form, which the basename check can never see
    module = re.sub(r"\.(py|ts|tsx|js|sh)$", "", src).replace("/", ".")
    mod_tail = ".".join(module.split(".")[-3:])
    if base and base not in ref_blob and src not in ref_blob \
       and module not in ref_blob and mod_tail not in ref_blob:
        untested.append({"file": src, "changes_90d": churn.get(src, 0)})
untested.sort(key=lambda x: -x["changes_90d"])

# ── 6. freshness + owner per test file ─────────────────────────────────────
fresh = []
for f in bats[:400]:
    r = rel(f)
    out = git("log","-1","--format=%as|%an","--",r)
    if out.strip():
        d,_,a = out.strip().partition("|")
        fresh.append({"file": r, "last_change": d, "author": a})
stale_cut = ""
try:
    import datetime as _dt
    stale_cut = (_dt.date.today()-_dt.timedelta(days=180)).isoformat()
except Exception: pass
stale = [x for x in fresh if stale_cut and x["last_change"] < stale_cut]

# ── 7. gate stability from runtime baselines ───────────────────────────────
gate_stability = []
try:
    import yaml as _y2
    bl = _y2.safe_load(open(f"{ROOT}/.aid-o/metrics/gate-runtime-baselines.yaml")) or {}
    for g, v in (bl.get("gates") or bl or {}).items():
        if not isinstance(v, dict): continue
        samples = v.get("recent_samples") or []
        if not samples: continue
        ok = sum(1 for x in samples if x.get("exit_code") == 0)
        gate_stability.append({"gate": g, "samples": len(samples),
                               "pass_rate": round(ok/len(samples), 2),
                               "censored": sum(1 for x in samples if x.get("censored"))})
except Exception:
    pass

# ── 8. case counts — how many TESTS, not just suites ──────────────────────
# The owner's first question was "kolik testů máme" and every answer so far
# counted SUITES. Cases are countable mechanically for bats; where they are
# not countable (a gate wrapping an opaque command), the report says
# "uncounted" instead of pretending the suite count is the test count.
case_counts = []
total_cases = 0
cases_by_runner = {"bats": 0, "py": 0, "ts": 0}
def _count_cases(f):
    if f in bats:
        return "bats", len(re.findall(r"@test ", open(f, errors="ignore").read()))
    if f in py_tests:
        # pytest collects test functions AND test methods; parametrize multiplies
        # at runtime, so this is a static lower bound — the report says so.
        return "py", len(re.findall(r"^\s*(?:async\s+)?def\s+test_",
                                    open(f, errors="ignore").read(), re.M))
    return "ts", len(re.findall(r"\b(?:it|test)(?:\.each\([^)]*\))?\s*\(",
                                open(f, errors="ignore").read()))
for f in all_tests:
    try: runner, n = _count_cases(f)
    except Exception: continue
    total_cases += n
    cases_by_runner[runner] += n
    case_counts.append({"file": rel(f), "runner": runner, "cases": n})
case_counts.sort(key=lambda x: -x["cases"])

# ── 9. naming conventions ─────────────────────────────────────────────────
# "aktuálně totál bordel bez konvence" — measurable: what prefixes dominate,
# and which files follow no recognisable pattern. The proposal writes itself:
# the dominant pattern IS the convention candidate, outliers are the renames.
def name_tokens(f):
    b = os.path.basename(f)
    b = re.sub(r"\.bats$", "", b)
    b = re.sub(r"^test[-_]?", "", b)
    return b.split("-")[0] if "-" in b else (b.split("_")[0] if "_" in b else b)
prefix_freq = collections.Counter(name_tokens(f) for f in bats)
dominant = [p for p, n in prefix_freq.most_common(8) if n >= 3]
outliers = [rel(f) for f in bats if name_tokens(f) not in dominant]
naming = {"dominant_prefixes": [{"prefix": p, "files": prefix_freq[p]} for p in dominant],
          "outliers": outliers[:30], "outlier_count": len(outliers)}

# ── 10. measured-claims cross-check ───────────────────────────────────────
# An analyst wrote cost.kind="measured" with numbers invented BEFORE the
# measurements ran — twice, in two different projects, and an independent
# review showed the audit undercounted its own finding (5 of 5 wrong, reported
# as 4 of 10). The adversarial wave caught it by diligence; this makes it
# arithmetic: every "measured" claim is compared against the actual receipt.
fabricated = []
if INV and os.path.exists(INV):
    adir = os.path.dirname(INV)
    real = {}
    try:
        with open(os.path.join(adir, "measurements.jsonl")) as f:
            for l in f:
                m = json.loads(l)
                if m.get("duration_ms"): real[m.get("run_unit_id")] = m["duration_ms"]
    except Exception:
        pass
    for af in glob.glob(os.path.join(adir, "agents", "*.json")):
        for d in (jload_ := (lambda p: (json.load(open(p)) if os.path.exists(p) else {})))(af).get("dispositions") or []:
            c = d.get("cost") or {}
            if c.get("kind") == "measured" and c.get("duration_ms") is not None:
                uid = d.get("run_unit_id")
                actual = real.get(uid)
                claimed = c["duration_ms"]
                if actual is None:
                    fabricated.append({"run_unit_id": uid, "claimed_ms": claimed,
                                       "actual_ms": None, "problem": "claimed measured, no measurement exists"})
                elif abs(actual - claimed) > max(2000, actual * 0.1):
                    fabricated.append({"run_unit_id": uid, "claimed_ms": claimed,
                                       "actual_ms": actual, "problem": "claimed measured, receipt disagrees"})

# ── 10b. gate overview — what each suite is FOR ───────────────────────────
# The owner's standing question nobody answered: "k čemu ty sady vlastně jsou
# a proč je máme?" Mechanically derivable: which files a gate runs, what topics
# those files cover, which profiles include it, and — where the name is an EPIC
# codename (p070, p077...) — a purpose-based name proposal. Codenames tell a
# reader nothing a week after the EPIC merges.
_case_by_file = {c["file"]: c["cases"] for c in case_counts}
_profiles = {}
try:
    for pn, pv in ((_ey.get("gate_profiles") or {}).items()):
        for gname in ((pv or {}).get("include") or []):
            _profiles.setdefault(str(gname), []).append(pn)
except Exception:
    pass
_generic = {"test", "tests", "integration", "unit", "e2e", "py", "ts", "check", "gate"}
gate_overview = []
try:
    for gname, gv in ((_ey.get("gates") or {}).items()):
        cmd = str((gv or {}).get("command") or "")
        text = cmd
        for sh in re.findall(r"[\w./-]+\.sh\b", cmd):
            try: text += "\n" + "\n".join(
                l for l in open(os.path.join(ROOT, sh.lstrip("./")), errors="ignore").read().splitlines()
                if _runner_line.search(l))
            except Exception: pass
        gfiles = sorted({t for t in re.findall(r"[\w./-]+\.(?:py|bats|ts|tsx)\b", text)
                         if t in _case_by_file})
        # a path-only WHOLE argument (pytest tests/unit/) runs a directory;
        # substrings of explicit file paths must never expand to their parent
        for arg in re.findall(r"\S+", text):
            arg = arg.rstrip("/")
            if "/" not in arg or re.search(r"\.(py|bats|ts|tsx|sh)$", arg): continue
            if os.path.isdir(os.path.join(ROOT, arg)):
                gfiles += [f for f in _case_by_file if f.startswith(arg + "/") and f not in gfiles]
        # a bare js/ts runner collects every matching file; a marker-filtered
        # pytest gate runs exactly the files carrying the marker
        if not gfiles and re.search(r"\b(vitest|jest)\b|npm\s+(run\s+)?test\b|npx\s+vitest", text):
            gfiles = [rel(f) for f in ts_tests if "/e2e/" not in rel(f)]
        for mk in re.findall(r"-m\s+([\w]+)", text):
            for f in py_tests:
                r2 = rel(f)
                if r2 in gfiles: continue
                try: c2 = open(f, errors="ignore").read()
                except Exception: continue
                if f"pytest.mark.{mk}" in c2 or ("pytestmark" in c2 and mk in c2):
                    gfiles.append(r2)
        cases = sum(_case_by_file.get(f, 0) for f in gfiles)
        toks = collections.Counter()
        for f in gfiles:
            b = re.sub(r"\.(py|bats|ts|tsx)$", "", os.path.basename(f))
            b = re.sub(r"^test[-_]?|[-_]?test$", "", b)
            for t in re.split(r"[-_.]", b):
                if len(t) > 2 and t not in _generic: toks[t] += 1
        topics = [t for t, _ in toks.most_common(4)]
        codename = bool(re.match(r"^p\d+", gname))
        suggested = ""
        if codename and topics:
            suggested = "_".join(topics[:2])
        gate_overview.append({
            "gate": gname, "files": len(gfiles), "cases": cases,
            "topics": topics, "profiles": sorted(_profiles.get(gname, [])),
            "required": bool((gv or {}).get("required")),
            "codename": codename, "suggested_name": suggested,
            "noop": cmd.strip().startswith("true")})
except Exception:
    pass

# ── 10b. vacuous green: tests that cannot fail (P079 Step 11, IMP-481) ─────
# Two MECHANICAL shapes of "a green test that checks nothing". The judgment
# shapes (an assertion that reads back the same surface that wrote the claim, a
# test whose subject could vanish and it would still pass) are NOT here — they
# need a reader, and scripts/README.md's authoring rule covers them as
# instruction.
#
# (a) set_e_grep_count — `x=$(grep -c ...)` in a `set -e` shell suite with no
#     `|| true` guard. `grep -c` exits 1 when it counts zero, so the assignment
#     kills the script BEFORE it prints anything, and a suite that dies early
#     reports the cases it did run as green. Line CONTINUATIONS are joined
#     first: the one live candidate in this repo carries its `|| true` on the
#     next line, and flagging it would be a false positive.
#
# (b) existence_keyed_skip — a `skip` guarded by whether the file under test
#     exists. If the subject disappears, the test reports SKIPPED instead of
#     failing, and a skip that is counted and rendered as skipped is legal —
#     but keyed on the SUBJECT's existence it is the test's own oracle. Add
#     `# content-scan: allow existence-skip — <reason>` on the preceding line
#     to record a deliberate one; it is reported with suppressed: true.
#
# Both checks read test files as TEXT, so a suite that carries an example of
# either shape inside a heredoc (this scanner's own bats suite does) is
# reported for the line it really contains. That is a true statement about the
# file, not a false positive to suppress.
#
# Plain `.sh` suites are enumerated HERE and nowhere else: the scanner's other
# checks are calibrated against the bats/py/ts universe, and widening that
# universe globally would silently change their counts. Named work, not free.
sh_tests = _clean(sorted(glob.glob(f"{ROOT}/**/tests/test-*.sh", recursive=True)))

def _join_continuations(lines):
    """[(lineno, joined_text)] — a backslash-continued command as one line."""
    out, buf, start = [], "", None
    for i, ln in enumerate(lines, 1):
        if start is None:
            start = i
        if ln.rstrip().endswith("\\"):
            buf += ln.rstrip()[:-1] + " "
            continue
        out.append((start, buf + ln))
        buf, start = "", None
    # A file ending mid-continuation has an UNFINISHED command; reporting it
    # would be reporting a syntax error as a vacuous-green pattern.
    return out

# `grep -c`, `grep -cE`, `grep -E -c`, `grep --count` — the option may carry
# other letters and may be a separate word, so match ANY grep invocation that
# takes a count flag before its pattern.
_grep_count_re = re.compile(
    r"=\s*[\$`]\(?\s*grep\b(?:\s+-[a-zA-Z]*\b|\s+--[a-z-]+)*"
    r"(?:\s+-[a-zA-Z]*c[a-zA-Z]*\b|\s+--count\b)")
set_e_grep_count = []
for f in sh_tests:
    try: lines = open(f, errors="ignore").read().splitlines()
    except Exception: continue
    if not any(re.search(r"^\s*set\s+(-[a-zA-Z]*e|-o\s+errexit)", ln) for ln in lines[:25]):
        continue
    for lineno, text in _join_continuations(lines):
        if text.lstrip().startswith("#"): continue
        if not _grep_count_re.search(text): continue
        if "||" in text: continue          # guarded
        if re.search(r"\brun\s+grep\b", text): continue   # bats `run` wrapper
        set_e_grep_count.append({"file": rel(f), "line": lineno,
                                 "text": text.strip()[:160]})

# Three shapes of the same thing: `[ -f X ] || skip`, `[[ ! -f X ]] && skip`,
# and `if [[ ! -f X ]]; then skip`. A skip keyed on an ABSOLUTE path (`/proc`,
# quoted or not) is a PLATFORM capability check rather than a claim about the
# subject under test, and is not flagged.
_skip_res = [
    re.compile(r"\[\[?\s+-[fdesx]\s+(?P<t>[^]]*?)\s*\]\]?\s*\|\|\s*skip\b"),
    re.compile(r"\[\[?\s+!\s*-[fdesx]\s+(?P<t>[^]]*?)\s*\]\]?\s*(?:&&\s*|;\s*then\s*)skip\b"),
]
def _skip_target(ln):
    for rx in _skip_res:
        m = rx.search(ln)
        if m:
            return m.group("t").strip()
    return None
def _is_platform_path(tok):
    return tok.strip("\"'").startswith("/")
_allow_re = re.compile(r"#\s*content-scan:\s*allow existence-skip")
existence_keyed_skip = []
for f in all_tests + sh_tests:
    try: lines = open(f, errors="ignore").read().splitlines()
    except Exception: continue
    for i, ln in enumerate(lines, 1):
        target = _skip_target(ln)
        if target is None or _is_platform_path(target): continue
        prev = lines[i - 2] if i >= 2 else ""
        existence_keyed_skip.append({"file": rel(f), "line": i,
                                     "text": ln.strip()[:160],
                                     "suppressed": bool(_allow_re.search(prev))})

# ── 11. does CI run any tests at all? ─────────────────────────────────────
# A verification agent found the project's single most serious hole in a place
# this audit never looked: the CI workflow's test step was commented out, so a
# merge to main verified NOTHING. Commented lines do not count as coverage.
_runner_re = re.compile(r"\b(pytest|vitest|jest|bats|playwright\s+test|go\s+test|cargo\s+test)\b|npm\s+(run\s+)?test\b|npx\s+vitest")
ci_files = sorted(glob.glob(f"{ROOT}/.github/workflows/*.yml")
                  + glob.glob(f"{ROOT}/.github/workflows/*.yaml")
                  + glob.glob(f"{ROOT}/.gitlab-ci.yml"))
ci_evidence, ci_commented = [], []
for cf in ci_files:
    try: lines = open(cf, errors="ignore").read().splitlines()
    except Exception: continue
    for i, ln in enumerate(lines, 1):
        if not _runner_re.search(ln): continue
        rec = f"{rel(cf)}:{i}: {ln.strip()[:120]}"
        (ci_commented if ln.lstrip().startswith("#") else ci_evidence).append(rec)
ci = {"workflows": len(ci_files),
      "runs_tests": bool(ci_evidence),
      "evidence": ci_evidence[:10],
      "commented_out": ci_commented[:10]}

doc = {
    "schema_version": "aid-test-content-scan-v1",
    "checks": {
        "duplicate_test_cases": duplicates,
        "weak_oracle": weak,
        "gate_overlap": overlap,
        "unreferenced_tests": unreferenced,
        "untested_surfaces": untested[:50],
        "test_freshness": {"stale_180d": len(stale), "files": stale[:20]},
        "gate_stability": gate_stability,
        "case_counts": {"total_countable": total_cases,
                        "files_counted": len(case_counts),
                        "by_runner": cases_by_runner,
                        "top": case_counts[:15],
                        "files": case_counts},
        "naming": naming,
        "fabricated_measured": fabricated,
        "set_e_grep_count": set_e_grep_count,
        "existence_keyed_skip": existence_keyed_skip,
        "ci": ci,
        "gate_overview": gate_overview,
        "scope": {"bats_files": len(bats), "py_test_files": len(py_tests),
                  "ts_test_files": len(ts_tests)},
    },
    "counts": {
        "bats_files_scanned": len(bats),
        "duplicate_pairs": len(duplicates),
        "weak_oracle_files": len(weak),
        "gate_overlap_candidates": len(overlap),
        "unreferenced": len(unreferenced),
        "untested_surfaces": len(untested),
        "stale_tests_180d": len(stale),
        "gates_with_history": len(gate_stability),
        "total_cases_countable": total_cases,
        "naming_outliers": len(outliers),
        "fabricated_measured": len(fabricated),
        "set_e_grep_count": len(set_e_grep_count),
        "existence_keyed_skip": len([e for e in existence_keyed_skip if not e["suppressed"]]),
        "sh_test_files_scanned": len(sh_tests),
        "test_files_all_runners": len(all_tests),
    },
}
os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
with open(OUT, "w") as f:
    json.dump(doc, f, indent=1)
print(OUT)
PY
