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
unreferenced = []
for f in bats:
    r = rel(f)
    stem = r[:-5] if r.endswith(".bats") else r
    if referenced and not any(stem in x or x in stem for x in referenced):
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
for f in bats:
    try: ref_blob += open(f, errors="ignore").read()
    except Exception: pass
churn_raw = git("log","--since=90 days ago","--name-only","--pretty=format:")
churn = collections.Counter(l for l in churn_raw.splitlines() if l.strip())
for src in tracked:
    base = os.path.basename(src)
    if base and base not in ref_blob and src not in ref_blob:
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
    },
}
os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
with open(OUT, "w") as f:
    json.dump(doc, f, indent=1)
print(OUT)
PY
