#!/usr/bin/env bash
# aid-tier: t2
# test-gates-hygiene.sh — the gate files say why they exist, and no live text
# teaches a removed layer (P097 Step 7).
#
# WHY THIS FILE EXISTS: P097 removed the per-gate applicability key, the
# service lifecycle, the profile-defaults table and the runtime baseline. A
# sentence that still teaches one of them is how the next agent re-implements
# it. Two checks, both t0 so they sit on the merge path:
#   (a) every gate file opens, within its first 20 lines, with a
#       `WHY THIS FILE EXISTS` paragraph of at most 15 comment lines;
#   (b) a sweep over the plugin's commands, skills, agents, defaults and
#       scripts finds no removed-layer name outside an EXPLICIT allow-list of
#       lines that document the refusal, the upgrade, a leftover file, or the
#       removal itself (the registry's removed rows). The allow-list is a list
#       of (file, line-substring) pairs, never a wide regex.
# Excluded from the sweep, and why: scripts/tests/ (a test that proves the
# runner refuses a key has to name the key), scripts/tests/fixtures/ and
# reference/review-successors.md (history), CHANGELOG* (history).
# The sweep proves it is not vacuous: a copy of an allow-listed file with one
# planted `required_when:` line must turn it red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

pass=0; fail=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass+1)); }

# ─── (a) WHY THIS FILE EXISTS ────────────────────────────────────────────────
GATE_FILES=(
  scripts/aid-run-gates.sh
  scripts/lib/aid-gate-row.sh
  scripts/lib/aid-run-gates-report.sh
  scripts/lib/aid-gate-outcome-summary.sh
  scripts/lib/aid-gate-profile-select.sh
  scripts/lib/aid-gate-runtime-baseline.sh
  scripts/aid-job.sh
)

# why_paragraph_lines <file> — the number of comment lines from the WHY line
# to the first blank comment (`#` alone) or non-comment line; 0 when the WHY
# line is not within the first 20 lines.
why_paragraph_lines() {
  awk 'NR <= 20 && !start && /WHY THIS FILE EXISTS/ { start = NR }
       start && ($0 ~ /^#[[:space:]]*$/ || $0 !~ /^#/) { print NR - start; done = 1; exit }
       END { if (!start) print 0; else if (!done) print NR - start + 1 }' "$1"
}

echo "TEST: every gate file opens with a WHY THIS FILE EXISTS paragraph (<= 15 lines, within the first 20)"
for rel in "${GATE_FILES[@]}"; do
  f="${PLUGIN_DIR}/${rel}"
  if [[ ! -f "$f" ]]; then fail_msg "$rel does not exist"; continue; fi
  n="$(why_paragraph_lines "$f")"
  if (( n == 0 )); then
    fail_msg "$rel has no 'WHY THIS FILE EXISTS' line within its first 20 lines"
  elif (( n > 15 )); then
    fail_msg "$rel: WHY paragraph is ${n} lines (max 15)"
  else
    pass_msg "$rel: WHY paragraph, ${n} lines"
  fi
done

# ─── (b) the sweep ───────────────────────────────────────────────────────────
# Word-bounded on purpose: `review_required_when` (a live decision-policy key)
# and `gate_runtime_baseline_advisory` (a registry id) are not the removed
# names. `^services:` is the top-level key form only. `restart_service_[o]nce`
# matches the plain name; the bracket only keeps this line out of P097 Step 9's
# repository-wide `git grep` for that name, which must come back empty.
REMOVED_RE='\brequired_when\b|\bneeds_services\b|^services:|\bgate_profile_defaults\b|gate-runtime-baselines|\bruntime_baseline\b|aid-gate-applicability|\brestart_service_[o]nce\b|\b_fsm_service_sweep\b'

# "<file>|<substring>" — a hit is allowed iff its file matches AND its line
# contains the substring. Each entry says what the line documents.
ALLOW=(
  # the runner's refusal: the block that names the keys it refuses
  'scripts/aid-run-gates.sh|no longer reads'
  'scripts/aid-run-gates.sh|left this runner'
  'scripts/aid-run-gates.sh|rotted unread'
  'scripts/aid-run-gates.sh|_refuse_dead_keys'
  'scripts/aid-run-gates.sh|select(. as $k | $r | has($k))'
  'scripts/aid-run-gates.sh|select(. == "required_when" or . == "needs_services")'
  'scripts/aid-run-gates.sh|is refused with the upgrade command'
  'scripts/aid-run-gates.sh|no longer exists'
  'scripts/aid-run-gates.sh|`services:` and `gate_profile_defaults`'
  'scripts/aid-run-gates.sh|Same entry point: a `services:` block'
  # the upgrade: the dead-key list and the notes it writes
  'scripts/lib/aid-init-execution-yaml.sh|'
  # the upgrade paragraph a user reads
  'commands/aid-init.md|`required_when`, `needs_services`'
  'commands/aid-init.md|`runtime_baseline`, `quarantine`'
  'commands/aid-init.md|The missing-table upgrade'
  'commands/aid-init.md|the old `gate_profile_defaults.epic`'
  # a leftover file a pre-P097 project may still track (nothing writes it)
  'scripts/lib/aid-ancillary.sh|.aid-o/metrics/gate-runtime-baselines.yaml'
  'defaults/policies/plan-final-policy.yaml|.aid-o/metrics/gate-runtime-baselines.yaml'
  'scripts/aid-fsm.sh|nothing writes them since P097 Step 5'
  'scripts/aid-fsm.sh|.aid-o/metrics/gate-runtime-baselines.yaml (+ its .lock sidecar)'
  # the registry's removed rows
  'defaults/enforcement-registry.yaml|removed'
  'defaults/enforcement-registry.yaml|RETIRED'
  'defaults/enforcement-registry.yaml|P097 Step'
)

allowed() {
  local file="$1" line="$2" entry efile esub
  for entry in "${ALLOW[@]}"; do
    efile="${entry%%|*}"; esub="${entry#*|}"
    [[ "$file" == "$efile" ]] || continue
    [[ -z "$esub" || "$line" == *"$esub"* ]] && return 0
  done
  return 1
}

# excluded <file> — the paths the header lists; decided here in bash so the
# sweep does not depend on which grep's --exclude flags are in effect.
excluded() {
  case "$1" in
    scripts/tests/*|*/CHANGELOG*|CHANGELOG*|reference/review-successors.md) return 0 ;;
  esac
  return 1
}

# sweep <root> — prints every disallowed hit as "<file>:<line>:<text>".
# `command grep` is GNU grep even where the shell aliases grep to another tool.
sweep() {
  local root="$1" hit file line text
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    file="${hit%%:*}"; hit="${hit#*:}"; line="${hit%%:*}"; text="${hit#*:}"
    file="${file#"$root"/}"
    excluded "$file" && continue
    allowed "$file" "$text" || printf '%s:%s:%s\n' "$file" "$line" "$text"
  done < <(command grep -rnE -- "$REMOVED_RE" \
      "$root/commands" "$root/skills" "$root/agents" "$root/defaults" "$root/scripts" 2>/dev/null)
}

echo "TEST: no live instruction or script names a removed layer outside the allow-list"
offenders="$(sweep "$PLUGIN_DIR")"
if [[ -z "$offenders" ]]; then
  pass_msg "sweep clean"
else
  fail_msg "these lines still name a removed layer (fix the text, or add the line to ALLOW with what it documents):"
  sed 's/^/      /' <<<"$offenders" | cut -c1-200
fi

echo "TEST: the sweep is not vacuous (a planted required_when: line turns it red)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/commands" "$WORK/skills" "$WORK/agents" "$WORK/defaults" "$WORK/scripts/lib"
# An allow-listed file, copied, with one planted key: every real line stays
# allowed, the planted one must not be.
cp "${PLUGIN_DIR}/commands/aid-init.md" "$WORK/commands/aid-init.md"
printf '\n    required_when: "src/**/*.py exists"\n' >> "$WORK/commands/aid-init.md"
planted="$(sweep "$WORK")"
if [[ "$planted" == *'commands/aid-init.md:'*'required_when: "src/**/*.py exists"'* ]]; then
  pass_msg "planted line reported: ${planted%%$'\n'*}"
else
  fail_msg "planted required_when: line was not reported (got: '${planted}')"
fi
# And the copy WITHOUT the plant is clean, so the case above proves the plant.
cp "${PLUGIN_DIR}/commands/aid-init.md" "$WORK/commands/aid-init.md"
clean="$(sweep "$WORK")"
[[ -z "$clean" ]] && pass_msg "the unplanted copy is clean" \
  || fail_msg "the unplanted copy reports hits, so the planted case proves nothing: $clean"

echo "TEST: the WHY check is not vacuous (a file without the paragraph is reported)"
printf '#!/usr/bin/env bash\n# a header with no purpose line\necho hi\n' > "$WORK/no-why.sh"
n="$(why_paragraph_lines "$WORK/no-why.sh")"
(( n == 0 )) && pass_msg "file without WHY reports 0" || fail_msg "file without WHY reported ${n}"

echo "Results: ${pass}/$((pass+fail)) passed, ${fail} failed"
(( fail == 0 ))
