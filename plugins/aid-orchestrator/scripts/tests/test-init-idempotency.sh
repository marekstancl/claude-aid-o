#!/usr/bin/env bash
# aid-tier: t1
#
# TIER DECISION, made deliberately against the assigner's own proposal.
# Measured: 1.9 s whole suite, 235 ms mean per case, slowest case 556 ms — that is
# t0-cheap. `aid-test-tier-assign.sh` nonetheless proposes t2, via
# `resolve_subject` (:85-97) returning `unresolvable -> cross-component`: it looks
# for a subject file named after the suite (`scripts/init-idempotency.sh`,
# `commands/init-idempotency.md`, ...) and this suite's subject has no such name —
# it is `commands/aid-init.md`'s contract plus two libs. The cross-component
# verdict is therefore a NAMING artifact, not a statement about cost or reach.
#
# t2 is nightly-only, so accepting it would leave init's idempotency contract off
# the merge path for a suite that costs two seconds. t1 is what the measurement
# supports, `aid-test-tier-lint.sh` accepts it (the lint only rejects a tier
# CHEAPER than measurement supports), and the guard runs where it can stop a
# regression instead of reporting one the next morning.
# =============================================================================
# test-init-idempotency.sh — mechanical anchor for the `/aid-init` idempotency
# contract (`commands/aid-init.md` § Idempotency), P080 EPIC 2 Step 8.
#
# ── WHAT THIS HARNESS PROVES ────────────────────────────────────────────────
# It pins the SCRIPTED SUBSTRATE of init — the operations init delegates to
# shipped libraries, plus the declared file manifest:
#
#   1. `lib/aid-init-execution-yaml.sh`  — compose (fresh) / skip (existing)
#   2. `lib/aid-gitignore-backfill.sh`   — per-line append, never reorder
#   3. the base manifest declared in `commands/aid-init.md`
#   4. the declined `gate_profiles` upgrade path (`execution_yaml_has_gate_profiles`
#      + the deliberate NON-call of `append_gate_profiles_block`)
#
# ── WHAT THIS HARNESS DOES *NOT* PROVE — read this before trusting it ───────
# `/aid-init` is LLM-executed prose. Any operation it performs INLINE rather
# than through a shipped library is invisible to any harness in this
# repository, and this one does not pretend otherwise:
#
#   * **Hook installation has NO library at this HEAD.** `defaults/hooks/pre-commit`
#     and `defaults/hooks/pre-push` are payload files that aid-init.md's PROSE
#     installs (§ "Git Hook Installation"). The marker-replace helper below is
#     the HARNESS's own implementation of those written semantics — it is used
#     with the shipped hooks as fixture INPUT, and it asserts that the semantics
#     are idempotent. It CANNOT detect drift in aid-init.md's prose
#     instructions: if the prose changes to a broken install order tomorrow,
#     every case here still passes. Extracting hook installation into a shared
#     library would close that gap; it is OUT of P080's scope and recorded as a
#     named follow-up rather than papered over here.
#   * **The five prose-authored workspace files** (`config/project.yaml`,
#     `config/permissions.yaml`, `config/plugin.yaml`, `work/active.md`,
#     `work/backlog.md`) have no generator to replay. The harness writes
#     placeholder content for them, so it covers their PRESENCE in the manifest
#     and their never-overwritten behaviour — never their CONTENT.
#   * Stack auto-detection breadth, the PM-facing prompts, the memory deep
#     scan, and the v1→v2 upgrade flow are all out of scope here.
#
# A test that overstates its reach is worse than none, so the boundary above is
# part of the suite, not a footnote to it.
#
# ── CASES ───────────────────────────────────────────────────────────────────
#   C1  Fresh replay produces exactly the manifest declared in aid-init.md, and
#       the hardcoded expectation is cross-checked against the doc's single
#       count sentence (doc/test drift fails the test).
#   C2  Second replay changes ZERO bytes of the tree — nothing to normalise,
#       because init's contract skips the one generator that has a clock.
#   C3  The one declared source of non-determinism is EXACTLY the generated
#       header line: two composes under different clocks differ on that line
#       and on nothing else.
#   C4  A customized existing `execution.yaml` is byte-identical after a replay
#       (init's contract: never overwrite existing).
#   C5  `.gitignore` backfill appends only missing lines, preserves pre-existing
#       non-AID content, and appends nothing on the second run.
#   C6  Marker-replace over a hook carrying an OLDER AID marker block is
#       idempotent, and bytes OUTSIDE the markers are untouched.
#   C7  A corrupted marker block (START without END) is refused, naming the file.
#   C8  Declined `gate_profiles` upgrade leaves the tree byte-identical
#       (`diff -r` empty).
#
# ── ROOTS CONTRACT ──────────────────────────────────────────────────────────
# Every replay runs under `cd <fixture>` with `AID_PROJECT_ROOT` and `HOME`
# both pointed INSIDE the fixture. Redirecting HOME disarms
# `_resolve_plugin_dir`'s `$HOME/.claude/plugins/...` fallback (so the plugin
# under test is the one in this checkout, never an installed copy) and makes any
# stray write to `$HOME` land where the tree diff can see it.
#
# Exit codes: 0=all passed, 1=one or more tests failed
# **Last Updated:** 2026-08-12
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$PLUGIN_DIR/scripts/lib"
DEFAULTS_DIR="$PLUGIN_DIR/defaults"
INIT_DOC="$PLUGIN_DIR/commands/aid-init.md"

EXEC_YAML_LIB="$LIB_DIR/aid-init-execution-yaml.sh"
GITIGNORE_LIB="$LIB_DIR/aid-gitignore-backfill.sh"

PASS=0
FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
for f in "$EXEC_YAML_LIB" "$GITIGNORE_LIB" "$INIT_DOC" \
         "$DEFAULTS_DIR/.gitignore" "$DEFAULTS_DIR/check-severity.yaml" \
         "$DEFAULTS_DIR/config/test-audit.yaml" \
         "$DEFAULTS_DIR/hooks/pre-commit" "$DEFAULTS_DIR/hooks/pre-push"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: required file not found: $f" >&2
    exit 1
  fi
done
for tool in git sha256sum yq diff; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool not found on PATH: $tool" >&2
    exit 1
  fi
done

# shellcheck source=/dev/null
source "$EXEC_YAML_LIB"
# shellcheck source=/dev/null
source "$GITIGNORE_LIB"

# A FAILED mktemp must stop the harness, not be ignored. With `set -uo pipefail`
# and no return-code check, a failure left TMPDIR_ROOT empty and every fixture
# path collapsed to `/c1`, `/c2`, … at the filesystem root — verified live by CP3.
# As an ordinary user that fails loudly and the tests report FAIL, so nothing
# passes falsely; as root in a container it would create directories in `/`.
# A test harness that can escape its own sandbox is not one to leave to luck.
TMPDIR_ROOT="$(mktemp -d)" || {
  echo "FATAL: mktemp -d failed — refusing to run with an unset fixture root" >&2
  exit 1
}
if [[ -z "${TMPDIR_ROOT:-}" || ! -d "$TMPDIR_ROOT" ]]; then
  echo "FATAL: fixture root is empty or not a directory ('${TMPDIR_ROOT:-}')" >&2
  exit 1
fi
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

echo "=== test-init-idempotency.sh ==="
echo "Plugin dir: $PLUGIN_DIR"
echo ""

# ---------------------------------------------------------------------------
# The base manifest, hardcoded — and cross-checked against aid-init.md's single
# count sentence in C1. The doc is the authority on the NUMBER; this list is
# the authority on WHICH items. Drift between them fails C1.
# ---------------------------------------------------------------------------
MANIFEST_FILES=(
  ".aid-o/config/project.yaml"
  ".aid-o/config/permissions.yaml"
  ".aid-o/config/execution.yaml"
  ".aid-o/config/plugin.yaml"
  ".aid-o/config/check-severity.yaml"
  ".aid-o/config/test-audit.yaml"
  ".aid-o/work/active.md"
  ".aid-o/work/backlog.md"
  ".aid-o/work/timeline.jsonl"
)
MANIFEST_EMPTY_DIRS=(
  ".aid-o/plans"
  ".aid-o/tasks"
  ".aid-o/work/quick"
  ".aid-o/work/evidence"
)

# The generated-header line in execution.yaml — the ONE non-deterministic line
# in the scripted substrate (aid-init-execution-yaml.sh writes `date -u` into
# it). Normalised out of every snapshot; proven to be the ONLY one by C3.
GENERATED_HEADER_RE='^# AUTO-GENERATED by aid-init at '

# ---------------------------------------------------------------------------
# Fixture construction
# ---------------------------------------------------------------------------
# new_fixture <name> — a throwaway git repo with a package.json so stack
# auto-detection has something real to find.
new_fixture() {
  local name="$1"
  local dir="$TMPDIR_ROOT/$name"
  mkdir -p "$dir"
  git -C "$dir" init -q
  printf '{\n  "name": "fixture-%s",\n  "version": "1.0.0"\n}\n' "$name" > "$dir/package.json"
  mkdir -p "$dir/.fakehome"
  printf '%s\n' "$dir"
}

# ---------------------------------------------------------------------------
# The replay: init's SCRIPTED operations, in init's documented order.
# ---------------------------------------------------------------------------
# install_hook <template> <target> <start_marker> <end_marker>
#   The HARNESS's implementation of aid-init.md § "Git Hook Installation"
#   (no shipped library exists to call — see the header's scope statement).
#     * target missing            → copy template
#     * target has START marker   → replace START..END block with the template's
#     * target has START, no END  → REFUSE, naming the file (corrupt block)
#     * target without any marker → replace whole file with template
#   Then ensure line 1 is a shebang, on every path.
install_hook() {
  local template="$1" target="$2" start="$3" end="$4"

  if [[ ! -f "$target" ]]; then
    mkdir -p "$(dirname "$target")"
    cp "$template" "$target"
    chmod +x "$target"
    return 0
  fi

  if grep -qF -- "$start" "$target"; then
    if ! grep -qF -- "$end" "$target"; then
      echo "ERROR: corrupt AID hook marker block in '$target' — '$start' present without '$end'" >&2
      return 1
    fi
    local tmp; tmp="$(mktemp)"
    # Everything before START, then the template's whole marker block, then
    # everything after END. Bytes outside the markers are copied verbatim.
    awk -v s="$start" -v e="$end" 'index($0,s){exit} {print}' "$target" > "$tmp"
    awk -v s="$start" -v e="$end" '
      index($0,s){inb=1} inb{print} index($0,e){inb=0}' "$template" >> "$tmp"
    awk -v e="$end" 'f{print} index($0,e){f=1}' "$target" >> "$tmp"
    cat "$tmp" > "$target"
    rm -f "$tmp"
  else
    cp "$template" "$target"
  fi

  if [[ "$(head -n 1 "$target")" != '#!'* ]]; then
    local tmp2; tmp2="$(mktemp)"
    { echo '#!/usr/bin/env bash'; cat "$target"; } > "$tmp2"
    cat "$tmp2" > "$target"
    rm -f "$tmp2"
  fi
  chmod +x "$target"
  return 0
}

# replay_init <fixture_dir>
#   Runs init's scripted substrate against the fixture. Every write is
#   never-overwrite, matching init's documented contract.
replay_init() {
  local root="$1"
  (
    cd "$root" || return 1
    export AID_PROJECT_ROOT="$root"
    export AID_PLUGIN_PATH="$PLUGIN_DIR"
    export HOME="$root/.fakehome"

    # 1. execution.yaml — composed ONLY when absent (contract: never overwrite).
    if [[ ! -f ".aid-o/config/execution.yaml" ]]; then
      local stacks=()
      mapfile -t stacks < <(detect_stacks "$root")
      compose_execution_yaml "$root" "$root/.aid-o/config/execution.yaml" "${stacks[@]}" || return 1
    fi

    # 2. Config defaults — copied only when absent.
    mkdir -p "$root/.aid-o/config" "$root/.aid-o/work"
    [[ -f ".aid-o/config/check-severity.yaml" ]] || cp "$DEFAULTS_DIR/check-severity.yaml" ".aid-o/config/check-severity.yaml"
    [[ -f ".aid-o/config/test-audit.yaml" ]]    || cp "$DEFAULTS_DIR/config/test-audit.yaml" ".aid-o/config/test-audit.yaml"

    # 3. Prose-authored templates — PLACEHOLDER content (see header: content is
    #    explicitly not covered; presence and never-overwrite are).
    [[ -f ".aid-o/config/project.yaml" ]]     || printf 'name: fixture\ntype: node\n'   > ".aid-o/config/project.yaml"
    [[ -f ".aid-o/config/permissions.yaml" ]] || printf 'autonomous_mode: false\n'      > ".aid-o/config/permissions.yaml"
    [[ -f ".aid-o/config/plugin.yaml" ]]      || printf 'plugin_path: %s\n' "$PLUGIN_DIR" > ".aid-o/config/plugin.yaml"
    [[ -f ".aid-o/work/active.md" ]]          || printf '# Active\n'                    > ".aid-o/work/active.md"
    [[ -f ".aid-o/work/backlog.md" ]]         || printf '# Backlog\n'                   > ".aid-o/work/backlog.md"
    [[ -f ".aid-o/work/timeline.jsonl" ]]     || : > ".aid-o/work/timeline.jsonl"

    # 4. Empty directories.
    local d
    for d in "${MANIFEST_EMPTY_DIRS[@]}"; do mkdir -p "$root/$d"; done

    # 5. .gitignore per-line backfill (shipped library, append-only).
    local line
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      gitignore_exclude_append "$root/.gitignore" "$line"
    done < "$DEFAULTS_DIR/.gitignore"

    # 6. Git hooks (harness-implemented semantics — see header).
    install_hook "$DEFAULTS_DIR/hooks/pre-commit" "$root/.git/hooks/pre-commit" \
      "AID-ORCHESTRATOR-HOOK-START" "AID-ORCHESTRATOR-HOOK-END" || return 1
    install_hook "$DEFAULTS_DIR/hooks/pre-push" "$root/.git/hooks/pre-push" \
      "AID-ORCHESTRATOR-PREPUSH-START" "AID-ORCHESTRATOR-PREPUSH-END" || return 1
  )
}

# ---------------------------------------------------------------------------
# Snapshotting — sha256 per path, NOT mtime.
# ---------------------------------------------------------------------------
# snapshot_tree <fixture_dir> <out_file>
#   One `<relpath> <sha256>` line per file. `.git/` internals are skipped
#   (git's own index/objects are not init's product) EXCEPT `.git/hooks/`,
#   which init genuinely writes. Directories are listed too, so a vanished
#   empty directory is visible in the diff. execution.yaml is hashed with the
#   generated-header line normalised — the one declared exception.
snapshot_tree() {
  local root="$1" out="$2"
  : > "$out"
  local p rel h
  while IFS= read -r -d '' p; do
    rel="${p#"$root"/}"
    [[ "$rel" == ".git/"* && "$rel" != ".git/hooks/"* ]] && continue
    [[ "$rel" == ".git" ]] && continue
    if [[ -d "$p" ]]; then
      printf '%s\tDIR\n' "$rel" >> "$out"
    else
      if [[ "$rel" == ".aid-o/config/execution.yaml" ]]; then
        h="$(sed "s|${GENERATED_HEADER_RE}.*|# AUTO-GENERATED by aid-init at <NORMALISED>|" "$p" | sha256sum | cut -d' ' -f1)"
      else
        h="$(sha256sum "$p" | cut -d' ' -f1)"
      fi
      printf '%s\t%s\n' "$rel" "$h" >> "$out"
    fi
  done < <(find "$root" -mindepth 1 -print0 | sort -z)
}

# ===========================================================================
# C1 — fresh replay produces exactly the declared manifest, cross-checked
#      against aid-init.md's single count sentence
# ===========================================================================
test_c1_manifest() {
  local count_lines n_files n_dirs n_total
  count_lines="$(grep -cE '^\*\*Total: [0-9]+ files under' "$INIT_DOC")"
  if [[ "$count_lines" -ne 1 ]]; then
    _fail "C1 — aid-init.md must carry exactly ONE count sentence; found $count_lines"
    return
  fi
  local sentence
  sentence="$(grep -E '^\*\*Total: [0-9]+ files under' "$INIT_DOC")"
  n_files="$(sed -E 's/^\*\*Total: ([0-9]+) files under.*/\1/' <<< "$sentence")"
  n_dirs="$(sed -E 's/.*\+ ([0-9]+) empty directories.*/\1/' <<< "$sentence")"
  n_total="$(sed -E 's/.*= ([0-9]+) items.*/\1/' <<< "$sentence")"

  if [[ "$n_files" != "${#MANIFEST_FILES[@]}" || "$n_dirs" != "${#MANIFEST_EMPTY_DIRS[@]}" ]]; then
    _fail "C1 — doc/test drift: aid-init.md says $n_files files + $n_dirs dirs; this test expects ${#MANIFEST_FILES[@]} + ${#MANIFEST_EMPTY_DIRS[@]}"
    return
  fi
  if (( n_total != n_files + n_dirs )); then
    _fail "C1 — aid-init.md's own count sentence does not add up: $n_files + $n_dirs != $n_total"
    return
  fi

  local fx; fx="$(new_fixture c1)"
  if ! replay_init "$fx"; then
    _fail "C1 — replay_init failed on a fresh fixture"
    return
  fi

  local missing=() extra=() f d
  for f in "${MANIFEST_FILES[@]}"; do
    [[ -f "$fx/$f" ]] || missing+=("$f")
  done
  for d in "${MANIFEST_EMPTY_DIRS[@]}"; do
    if [[ ! -d "$fx/$d" ]]; then
      missing+=("$d/")
    elif [[ -n "$(ls -A "$fx/$d")" ]]; then
      extra+=("$d/ is not empty")
    fi
  done
  # Nothing under .aid-o/ beyond the declared manifest.
  local rel
  while IFS= read -r -d '' rel; do
    rel="${rel#"$fx"/}"
    [[ -d "$fx/$rel" ]] && continue
    local known=0
    for f in "${MANIFEST_FILES[@]}"; do [[ "$rel" == "$f" ]] && known=1 && break; done
    (( known == 0 )) && extra+=("$rel")
  done < <(find "$fx/.aid-o" -mindepth 1 -print0)

  if (( ${#missing[@]} == 0 && ${#extra[@]} == 0 )); then
    _pass "C1 — fresh replay yields exactly $n_total declared items (${n_files} files + ${n_dirs} empty dirs), matching aid-init.md"
  else
    _fail "C1 — manifest mismatch; missing: ${missing[*]:-none}; unexpected: ${extra[*]:-none}"
  fi
}

# ===========================================================================
# C2 — second replay changes zero bytes of the tree
# ===========================================================================
test_c2_second_replay_noop() {
  local fx; fx="$(new_fixture c2)"
  if ! replay_init "$fx"; then _fail "C2 — first replay failed"; return; fi
  local before="$TMPDIR_ROOT/c2.before" after="$TMPDIR_ROOT/c2.after"
  snapshot_tree "$fx" "$before"
  if ! replay_init "$fx"; then _fail "C2 — second replay failed"; return; fi
  snapshot_tree "$fx" "$after"

  local d
  d="$(diff "$before" "$after" || true)"
  if [[ -z "$d" ]]; then
    _pass "C2 — second replay changed zero bytes across $(grep -c '' "$before") tracked paths"
  else
    _fail "C2 — second replay changed the tree:
$d"
  fi
}

# ===========================================================================
# C3 — the generated header line is the ONLY source of non-determinism
# ===========================================================================
test_c3_only_exception_is_header() {
  local fx; fx="$(new_fixture c3)"
  local a="$TMPDIR_ROOT/c3.a.yaml" b="$TMPDIR_ROOT/c3.b.yaml"
  local stacks=(); mapfile -t stacks < <(detect_stacks "$fx")

  ( export AID_PLUGIN_PATH="$PLUGIN_DIR"
    compose_execution_yaml "$fx" "$a" "${stacks[@]}" ) || { _fail "C3 — first compose failed"; return; }

  # Second compose under a DIFFERENT clock: shadow `date` so the generated
  # header provably differs even inside the same wall-clock second.
  ( export AID_PLUGIN_PATH="$PLUGIN_DIR"
    date() { echo "2020-01-01T00:00:00Z"; }
    compose_execution_yaml "$fx" "$b" "${stacks[@]}" ) || { _fail "C3 — second compose failed"; return; }

  local changed
  changed="$(diff "$a" "$b" | grep -E '^[<>]' || true)"
  local n_changed; n_changed="$(printf '%s' "$changed" | grep -c '' || true)"
  local n_header;  n_header="$(printf '%s\n' "$changed" | grep -cE "^[<>] # AUTO-GENERATED by aid-init at " || true)"

  if [[ "$n_changed" -eq 2 && "$n_header" -eq 2 ]]; then
    _pass "C3 — two composes under different clocks differ on the generated-header line and nothing else"
  else
    _fail "C3 — expected exactly the header line to differ; got $n_changed differing line(s), $n_header of them the header:
$changed"
  fi
}

# ===========================================================================
# C4 — a customized existing execution.yaml is never overwritten
# ===========================================================================
test_c4_existing_execution_yaml_untouched() {
  local fx; fx="$(new_fixture c4)"
  mkdir -p "$fx/.aid-o/config"
  cat > "$fx/.aid-o/config/execution.yaml" <<'EOF'
# hand-written by the PM, deliberately NOT the generated shape
version: "1.0"
gates:
  my_custom_gate:
    command: "make check"
    required: true
EOF
  local sum_before; sum_before="$(sha256sum "$fx/.aid-o/config/execution.yaml" | cut -d' ' -f1)"
  if ! replay_init "$fx"; then _fail "C4 — replay failed"; return; fi
  local sum_after; sum_after="$(sha256sum "$fx/.aid-o/config/execution.yaml" | cut -d' ' -f1)"

  if [[ "$sum_before" == "$sum_after" ]]; then
    _pass "C4 — customized execution.yaml byte-identical after replay (compose did not run)"
  else
    _fail "C4 — replay overwrote a customized execution.yaml ($sum_before -> $sum_after)"
  fi
}

# ===========================================================================
# C5 — .gitignore backfill: append only what is missing, keep foreign content
# ===========================================================================
test_c5_gitignore_backfill() {
  local fx; fx="$(new_fixture c5)"
  cat > "$fx/.gitignore" <<'EOF'
# project's own rules, predating AID
node_modules/
dist/
.aid-o/work/quick/
EOF
  local foreign_before; foreign_before="$(head -n 4 "$fx/.gitignore")"

  if ! replay_init "$fx"; then _fail "C5 — first replay failed"; return; fi
  local after_first; after_first="$(sha256sum "$fx/.gitignore" | cut -d' ' -f1)"

  local problems=()
  # Pre-existing content preserved verbatim, still at the top, never reordered.
  [[ "$(head -n 4 "$fx/.gitignore")" == "$foreign_before" ]] || problems+=("pre-existing lines were altered or reordered")
  # The already-present AID line was NOT duplicated.
  local dupes; dupes="$(grep -cxF '.aid-o/work/quick/' "$fx/.gitignore" || true)"
  [[ "$dupes" -eq 1 ]] || problems+=("'.aid-o/work/quick/' present $dupes times, expected 1")
  # Every shipped pattern is present exactly once.
  local line n
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    n="$(grep -cxF -- "$line" "$fx/.gitignore" || true)"
    [[ "$n" -eq 1 ]] || problems+=("pattern '$line' present $n times, expected 1")
  done < "$DEFAULTS_DIR/.gitignore"

  if ! replay_init "$fx"; then _fail "C5 — second replay failed"; return; fi
  local after_second; after_second="$(sha256sum "$fx/.gitignore" | cut -d' ' -f1)"
  [[ "$after_first" == "$after_second" ]] || problems+=("second replay changed .gitignore")

  if (( ${#problems[@]} == 0 )); then
    _pass "C5 — backfill appended only missing patterns, preserved foreign content, and was a no-op on re-run"
  else
    _fail "C5 — ${problems[*]}"
  fi
}

# ===========================================================================
# C6 — marker-replace over an OLDER AID hook is idempotent and preserves
#      bytes outside the markers
# ===========================================================================
test_c6_hook_marker_idempotency() {
  local fx; fx="$(new_fixture c6)"
  local target="$fx/.git/hooks/pre-commit"
  mkdir -p "$fx/.git/hooks"
  # A hook from an OLDER AID: same markers, different (stale) block content,
  # wrapped in project-owned lines that AID must never touch.
  cat > "$target" <<'EOF'
#!/usr/bin/env bash
# project-owned preamble — AID must not touch this line
echo "project pre-hook"
# AID-ORCHESTRATOR-HOOK-START (do not edit this block manually)
echo "STALE v1 block that must be replaced"
# AID-ORCHESTRATOR-HOOK-END
# project-owned epilogue — AID must not touch this line either
exit 0
EOF
  chmod +x "$target"

  if ! install_hook "$DEFAULTS_DIR/hooks/pre-commit" "$target" \
        "AID-ORCHESTRATOR-HOOK-START" "AID-ORCHESTRATOR-HOOK-END"; then
    _fail "C6 — first marker-replace failed"; return
  fi
  local sum1; sum1="$(sha256sum "$target" | cut -d' ' -f1)"

  if ! install_hook "$DEFAULTS_DIR/hooks/pre-commit" "$target" \
        "AID-ORCHESTRATOR-HOOK-START" "AID-ORCHESTRATOR-HOOK-END"; then
    _fail "C6 — second marker-replace failed"; return
  fi
  local sum2; sum2="$(sha256sum "$target" | cut -d' ' -f1)"

  local problems=()
  [[ "$sum1" == "$sum2" ]] || problems+=("second marker-replace changed the file ($sum1 -> $sum2)")
  grep -qF 'project-owned preamble' "$target" || problems+=("preamble outside the markers was lost")
  grep -qF 'project-owned epilogue' "$target" || problems+=("epilogue outside the markers was lost")
  grep -qF 'STALE v1 block' "$target" && problems+=("stale block inside the markers was NOT replaced")
  # The shipped block really landed.
  grep -qF 'AID-ORCHESTRATOR-HOOK-END' "$target" || problems+=("END marker missing after replace")

  if (( ${#problems[@]} == 0 )); then
    _pass "C6 — marker-replace is idempotent; bytes outside the markers survived, stale block inside was replaced"
  else
    _fail "C6 — ${problems[*]}"
  fi
}

# ===========================================================================
# C7 — a corrupted marker block is refused, naming the file
# ===========================================================================
test_c7_corrupt_marker_refused() {
  local fx; fx="$(new_fixture c7)"
  local target="$fx/.git/hooks/pre-push"
  mkdir -p "$fx/.git/hooks"
  # START present, END deleted — a half-written block. Blind replacement here
  # would eat the rest of the file.
  cat > "$target" <<'EOF'
#!/usr/bin/env bash
# AID-ORCHESTRATOR-PREPUSH-START (do not edit this block manually)
echo "half a block"
echo "project logic that a blind replace would swallow"
exit 0
EOF
  local sum_before; sum_before="$(sha256sum "$target" | cut -d' ' -f1)"

  local err rc=0
  err="$(install_hook "$DEFAULTS_DIR/hooks/pre-push" "$target" \
          "AID-ORCHESTRATOR-PREPUSH-START" "AID-ORCHESTRATOR-PREPUSH-END" 2>&1)" || rc=$?
  local sum_after; sum_after="$(sha256sum "$target" | cut -d' ' -f1)"

  if [[ "$rc" -ne 0 ]] && [[ "$err" == *"$target"* ]] && [[ "$sum_before" == "$sum_after" ]]; then
    _pass "C7 — corrupt marker block refused, error names the file, file left untouched"
  else
    _fail "C7 — expected refusal naming '$target'; got rc=$rc, changed=$([[ "$sum_before" == "$sum_after" ]] && echo no || echo yes), stderr: ${err:-<empty>}"
  fi
}

# ===========================================================================
# C8 — declined gate_profiles upgrade leaves the tree byte-identical
# ===========================================================================
test_c8_declined_upgrade() {
  local fx; fx="$(new_fixture c8)"
  mkdir -p "$fx/.aid-o/config"
  # An existing execution.yaml WITHOUT gate_profiles — the upgrade candidate.
  cat > "$fx/.aid-o/config/execution.yaml" <<'EOF'
# AUTO-GENERATED by aid-init at 2025-01-01T00:00:00Z
version: "1.0"

gates:
  ts_test:
    command: "npm test -- --hand-edited"
    required: true
EOF
  if ! replay_init "$fx"; then _fail "C8 — replay failed"; return; fi

  local target="$fx/.aid-o/config/execution.yaml"
  if execution_yaml_has_gate_profiles "$target"; then
    _fail "C8 — fixture precondition broken: the file already has gate_profiles, so there is no upgrade to decline"
    return
  fi

  # Snapshot the whole tree as a directory copy, then walk the upgrade path and
  # take the DECLINE branch — the append is simply not called.
  local before_dir="$TMPDIR_ROOT/c8-before"
  cp -a "$fx" "$before_dir"

  local stacks=(); mapfile -t stacks < <(detect_stacks "$fx")
  # P083 Step 7: render_gate_profiles_block discovers its filter target at
  # the CWD-relative .aid-o/config/execution.yaml (matching real
  # commands/aid-init.md usage, which always runs with CWD == project root)
  # unless a caller overrides it. `cd "$fx"` here so this call matches that
  # real convention instead of picking up whatever unrelated
  # execution.yaml happens to sit at the test runner's own CWD.
  local block; block="$( cd "$fx" && export AID_PLUGIN_PATH="$PLUGIN_DIR"; render_gate_profiles_block "${stacks[@]}" )"
  if [[ -z "$block" ]]; then
    _fail "C8 — render_gate_profiles_block produced nothing; the offer path is not reachable"
    return
  fi
  # BOTH BRANCHES ARE WALKED, and this is the point of the case.
  #
  # An earlier version ran only the DECLINE branch with a hardcoded `pm_answer=N`,
  # so `append_gate_profiles_block` was never called on any executed path. CP2
  # replaced that function with one that corrupts its target — and the case still
  # passed. It was proving that an uncalled function changes nothing, which is true
  # of every function ever written. A test that cannot distinguish "declining is
  # safe" from "nothing happened" asserts the second while claiming the first.
  #
  # So ACCEPT runs on a COPY and must change exactly execution.yaml, and DECLINE
  # runs on the fixture and must change nothing. The pair is what makes the claim
  # real: the same call site, one answer apart, with opposite and both-observed
  # outcomes.
  local accept_dir="$TMPDIR_ROOT/c8-accept"
  cp -a "$fx" "$accept_dir"
  append_gate_profiles_block "$accept_dir/.aid-o/config/execution.yaml" "$block"
  local accept_diff; accept_diff="$(diff -rq "$before_dir" "$accept_dir" || true)"
  if [[ "$(printf '%s\n' "$accept_diff" | grep -c .)" -ne 1 ]] \
     || [[ "$accept_diff" != *"execution.yaml"* ]]; then
    _fail "C8 — ACCEPT branch: expected exactly execution.yaml to change, got:
$accept_diff"
    return
  fi
  if ! execution_yaml_has_gate_profiles "$accept_dir/.aid-o/config/execution.yaml"; then
    _fail "C8 — ACCEPT branch ran but the file still has no gate_profiles; the append is a no-op"
    return
  fi

  # DECLINE: same call site, the other answer.
  local pm_answer="N"
  if [[ "$pm_answer" == "Y" ]]; then
    append_gate_profiles_block "$target" "$block"
  fi

  local d
  d="$(diff -r "$before_dir" "$fx" || true)"
  if [[ -z "$d" ]]; then
    _pass "C8 — accept changes exactly execution.yaml and really appends; decline changes nothing"
  else
    _fail "C8 — declined upgrade modified the tree:
$d"
  fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
test_c1_manifest
test_c2_second_replay_noop
test_c3_only_exception_is_header
test_c4_existing_execution_yaml_untouched
test_c5_gitignore_backfill
test_c6_hook_marker_idempotency
test_c7_corrupt_marker_refused
test_c8_declined_upgrade

total=$((PASS + FAIL))
echo ""
echo "Results: $total/$total run, $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
