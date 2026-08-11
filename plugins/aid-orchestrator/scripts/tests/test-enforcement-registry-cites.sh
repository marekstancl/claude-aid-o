#!/usr/bin/env bash
# aid-tier: t0
# test-enforcement-registry-cites.sh — P080 Step 4.
#
# Registry hygiene: every `source:` / `instruction:` cite in
# defaults/enforcement-registry.yaml must name a file (or directory) that
# actually exists, and every row id must be unique.
#
# Why this exists: a registry row is the plugin's promise that a detector has a
# real enforcing surface. A cite that points at a file which was deleted,
# renamed, or moved into an untracked tree is the P026 failure mode one level
# up — the row still LOOKS wired, and nothing notices that it isn't. Step 4 of
# P080 found 8 such rows; this harness is what keeps the ninth from happening
# silently.
#
# What is deliberately NOT asserted: line numbers. `file:123` drifts on every
# edit above line 123 and asserting it would make the registry unmaintainable.
# File existence is the invariant; the line is a navigation hint.
#
# The id-uniqueness check closes the append-duplication class: this file is
# edited by appending rows, and an appended duplicate id silently shadows
# whichever row a consumer's `select(.id == …) | head -1` happens to hit first.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_DIR="$(cd "${PLUGIN_DIR}/../.." && pwd)"
REGISTRY="${PLUGIN_DIR}/defaults/enforcement-registry.yaml"

pass=0; fail=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }

for dep in jq yq; do
  command -v "$dep" >/dev/null 2>&1 || {
    echo "  FAIL: $dep not installed"
    echo "Results: 0/1 passed, 1 failed"
    exit 1
  }
done

# ─── Tokeniser ──────────────────────────────────────────────────────────────
#
# All four annotation grammars below are present verbatim in the shipped
# registry, so a parser that handles only `;` / `:N` / `§` reports hundreds of
# false dangles:
#
#   scripts/aid-plan-fsm.sh:cmd_plan_finalize --stage gates   (:identifier)
#   scripts/lib/review-profile-check.sh:~84                   (:~digits)
#   scripts/aid-fsm.sh's existing ESCALATION precondition     (possessive)
#   scripts/aid-plan-to-epic.sh (search: '…') + lib/aid-scoping.sh:_fn  (+ join)
#
# A value is split on `;` and ` + `; the LEADING whitespace-delimited token of
# each part is the path candidate. A candidate containing no `/` is a prose
# label and is dropped — and this drop is applied PER TOKEN, after tokenising,
# never per whole value. Applied per value it leaves ~40 false positives,
# because a value like `scripts/x.sh (search: 'foo') + Step 3` contains a slash
# overall while several of its split tokens are pure prose.
#
# Result is returned in the global CITE_TOKEN rather than via `$(…)`: this runs
# once per cite token over a ~430-row registry, and a command substitution forks
# a subshell every time — enough to push the harness from t0 into t1 for nothing.
CITE_TOKEN=""
_cite_normalise_token() {
  local t="$1" dir base
  # Leading punctuation: a cite is routinely written parenthesised or quoted, e.g.
  # `… (lib/review-profile-check.sh:~84)`. Stripping the closing bracket but not the
  # opening one left `(lib/…` as the token — which resolves nowhere and reads as a
  # dangling cite for a file that is right there.
  t="${t#\`}"; t="${t#\'}"; t="${t#\"}"; t="${t#(}"; t="${t#[}"
  while [[ "$t" =~ [\`\'\"\,\)\.\;\:]$ ]]; do t="${t%?}"; done
  t="${t%\'s}"
  if [[ "$t" == */* ]]; then dir="${t%/*}"; base="${t##*/}"; else dir=""; base="$t"; fi
  # Everything from the first `:` in the basename onwards is an annotation
  # (`:128`, `:~84`, `:cmd_plan_finalize`, `:gates.d5`) — never part of the path.
  base="${base%%:*}"
  base="${base%\'s}"
  while [[ "$base" =~ [\`\'\"\,\)\.]$ ]]; do base="${base%?}"; done
  if [[ -n "$dir" ]]; then CITE_TOKEN="${dir}/${base}"; else CITE_TOKEN="$base"; fi
}

# The registry's cite base is MIXED — measured over the shipped file: the vast
# majority of tokens resolve only under the plugin root, a handful only under
# the repo root, and a third convention writes bare `lib/…` meaning
# plugin + `scripts/`. A token resolving under NONE of the three is a violation.
# `-e`, not `-f`: rows legitimately cite directories (e.g. `skills/visual-companion/`).
_cite_resolves() {
  local t="$1" plugin_dir="$2" repo_dir="$3"
  [[ -e "${plugin_dir}/${t}" ]] && return 0
  [[ -e "${repo_dir}/${t}" ]] && return 0
  [[ -e "${plugin_dir}/scripts/${t}" ]] && return 0
  return 1
}

# _cite_violations <registry> <plugin_dir> <repo_dir>
# Emits one `CITE|<row-id>|<field>|<path>` line per unresolvable cite.
_cite_violations() {
  local registry="$1" plugin_dir="$2" repo_dir="$3"
  local id status source instruction field val part word tok parts rows rc

  # THE FAIL-OPEN THIS GUARD EXISTS FOR: a single row whose `source:` is a LIST
  # rather than a scalar makes `@tsv` abort. In a pipeline that error is invisible
  # — every row after it is simply never read, the violation list comes back
  # empty, and the harness reports "all cites resolve" with exit 0. Measured on
  # the real registry: 0 of 428 rows checked, two deliberately broken cites
  # missed, exit 0. A cite checker that under-reports is worse than none, because
  # it certifies a lying registry.
  #
  # So the rows are materialised FIRST, jq's exit code is checked, and the row
  # count is compared against the registry's own length. Anything short is a hard
  # failure, never a quiet pass.
  # FIELDS ARE JOINED ON \x1f (unit separator), NOT on a tab, and IFS is set to it
  # below. A tab is an IFS *whitespace* character, so bash collapses runs of them:
  # a row with an empty `status` produced `id<TAB><TAB>source`, read collapsed the
  # pair, and `source` landed in `status` while `source` came out empty — the row's
  # cites were then silently never checked. `status` is not a required key
  # anywhere, so that was a field a row could omit to opt out of validation.
  # \x1f is non-whitespace, so consecutive separators keep their empty fields.
  rows="$(yq -o=json '.' "$registry" \
    | jq -r '.enforcements[] | [(.id // ""), (.status // ""), (.source // ""), (.instruction // "")] | join("")')"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    printf 'CITE|<harness>|extract|row extraction failed (jq rc=%s) — a non-scalar cite field is the known cause; rows were NOT checked\n' "$rc"
    return 0
  fi
  local declared actual
  declared="$(yq '.enforcements | length' "$registry" 2>/dev/null || echo 0)"
  actual="$(printf '%s\n' "$rows" | grep -c . || true)"
  if [[ "$declared" != "$actual" ]]; then
    printf 'CITE|<harness>|extract|extracted %s of %s rows — extraction stopped early (or yq/jq returned nothing); the rest were NOT checked\n' "$actual" "$declared"
    return 0
  fi

  printf '%s\n' "$rows" \
    | while IFS=$'\x1f' read -r id status source instruction; do
        # Rows with status dead / removed_scoped keep citing removed files BY
        # DESIGN — that is what the status means. Skip their path validation.
        # Anything else, INCLUDING an empty status, is validated: `status` is not
        # a required key anywhere, and treating "no status" as a reason to skip
        # would let a row opt out of the check by omitting a field.
        case "$status" in dead|removed_scoped) continue ;; esac
        for field in source instruction; do
          val="$source"; [[ "$field" == "instruction" ]] && val="$instruction"
          case "$val" in ""|"n/a"|"planned"|"null") continue ;; esac
          parts="${val// + /$'\n'}"; parts="${parts//;/$'\n'}"
          while IFS= read -r part; do
            part="${part#"${part%%[![:space:]]*}"}"
            [[ -z "$part" ]] && continue
            # EVERY word of the part is considered, not just the leading one:
            # taking only the first word meant `see scripts/does-not-exist.sh` was
            # dropped whole, because `see` has no slash and read as a prose label —
            # a zero-effort way to exempt a row from validation, in a file that
            # already contains prose-styled cites so the shape looks unremarkable.
            #
            # But "contains a slash" alone is far too loose for a non-leading word:
            # measured over the shipped registry it produces 12 false positives from
            # ordinary prose — `pre/post`, `plan/<id>`, `run/status/collect/cancel`,
            # `--plan-id/--plan-mode`, `files/paths`, `backslash/pipe`. A harness
            # that cries wolf twelve times is a harness people learn to ignore, so a
            # non-leading word must LOOK like a repo path: it starts with a known
            # top-level segment, or it ends in a source-file extension.
            # The LEADING word of a part is the cite. Every later word is prose
            # unless it unmistakably names a repo path — the two are held to
            # different standards on purpose, and both standards were measured
            # against the shipped registry rather than guessed:
            #
            #   leading    validated even without a slash, so `CLAUDE.md` — a real
            #              instruction surface, and the shape this harness uses in
            #              its OWN registry row — is checkable. Without this, the
            #              tool for finding rows that merely look wired could not
            #              check itself.
            #   non-leading  must start with a known top-level segment. Accepting
            #              "contains a slash" produced 12 false positives from
            #              ordinary prose (`pre/post`, `plan/<id>`,
            #              `run/status/collect/cancel`, `--plan-id/--plan-mode`);
            #              also accepting a bare extension produced 8 more from
            #              filenames mentioned mid-sentence (`plan-writing.md`,
            #              `active.md`) that live in a subdirectory, not at root.
            #              A harness that cries wolf is one people learn to ignore.
            #
            # What this still misses: a second FULL path inside one part that does
            # not start with a known segment. Recorded rather than papered over.
            local first=1
            for word in $part; do
              _cite_normalise_token "$word"; tok="$CITE_TOKEN"
              if [[ $first -eq 1 ]]; then
                first=0
                case "$tok" in
                  */*) ;;
                  *.md|*.sh|*.yaml|*.yml|*.json|*.bats) ;;
                  *) continue ;;
                esac
              else
                case "$tok" in
                  scripts/*|skills/*|commands/*|agents/*|defaults/*|docs/*|lib/*|.github/*) ;;
                  *) continue ;;
                esac
              fi
              _cite_resolves "$tok" "$plugin_dir" "$repo_dir" \
                || printf 'CITE|%s|%s|%s\n' "${id:-<no-id>}" "$field" "$tok"
            done
          done <<< "$parts"
        done
      done
}

# ─── 1. The registry parses ─────────────────────────────────────────────────
echo "TEST: the registry parses as YAML"
if yq -o=json '.' "$REGISTRY" >/dev/null 2>&1; then
  pass_msg "$REGISTRY parses"
else
  fail_msg "$REGISTRY did not parse as YAML"
  echo "Results: ${pass}/$((pass + fail)) passed, ${fail} failed"
  exit 1
fi

# ─── 2. Every row has an id ─────────────────────────────────────────────────
# A hand-edited row that lost its `id` is caught HERE, with its index, rather
# than as a mystery empty selector in a downstream consumer.
echo "TEST: every enforcement row carries an id"
missing_idx="$(yq -o=json '.' "$REGISTRY" \
  | jq -r 'to_entries | .[] | select(.key == "enforcements") | .value
           | to_entries | map(select((.value.id // "") == "") | .key) | join(", ")')"
if [[ -z "$missing_idx" ]]; then
  pass_msg "no row is missing its id"
else
  fail_msg "enforcement row(s) at index [$missing_idx] have no 'id' field"
fi

# ─── 3. Row ids are unique ──────────────────────────────────────────────────
echo "TEST: every row id is unique"
dupes="$(yq '.enforcements[].id' "$REGISTRY" 2>/dev/null | sort | uniq -d)"
if [[ -z "$dupes" ]]; then
  pass_msg "no duplicate row ids"
else
  fail_msg "duplicate row id(s): $(tr '\n' ' ' <<<"$dupes")"
fi

# ─── 4. Every cite resolves ─────────────────────────────────────────────────
echo "TEST: every source/instruction cite resolves to a real file or directory"
violations="$(_cite_violations "$REGISTRY" "$PLUGIN_DIR" "$REPO_DIR")"
if [[ -z "$violations" ]]; then
  pass_msg "all source/instruction cites resolve"
else
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "  $line"
  done <<< "$violations"
  fail_msg "$(grep -c . <<<"$violations") unresolvable cite(s) — see CITE| lines above"
fi

# ─── 5. Negative control: the check FIRES ───────────────────────────────────
# Without this, a green run proves only that nothing happens to be broken —
# not that a broken cite would be caught. The fixture is built in a temp dir so
# no deliberately-corrupt registry ships in the tree.
echo "TEST: the cite check FIRES on a deliberately corrupted fixture"
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
cat > "${fixture_dir}/registry.yaml" <<'FIXTURE'
enforcements:
  - {id: control_good, type: 1, source: "scripts/aid-fsm.sh:1", instruction: "n/a", severity: advisory, surface: internal-guard, status: active, verdict: ALIGNED, description: "resolves"}
  - {id: control_bad, type: 1, source: "scripts/this-file-does-not-exist.sh:12", instruction: "n/a", severity: advisory, surface: internal-guard, status: active, verdict: ALIGNED, description: "must be flagged"}
  - {id: control_dead, type: 1, source: "scripts/also-gone.sh", instruction: "n/a", severity: advisory, surface: internal-guard, status: dead, verdict: ORPHAN, description: "dead rows keep citing removed files by design"}
FIXTURE
control="$(_cite_violations "${fixture_dir}/registry.yaml" "$PLUGIN_DIR" "$REPO_DIR")"
if grep -q '^CITE|control_bad|source|scripts/this-file-does-not-exist\.sh$' <<<"$control"; then
  pass_msg "the corrupted cite is flagged"
else
  fail_msg "the corrupted cite was NOT flagged — the guard cannot fire (got: ${control:-<nothing>})"
fi
if grep -q '^CITE|control_good|' <<<"$control"; then
  fail_msg "a resolvable cite was flagged — false positive in the control fixture"
else
  pass_msg "the resolvable cite is not flagged"
fi
if grep -q '^CITE|control_dead|' <<<"$control"; then
  fail_msg "a status: dead row was path-validated — dead rows cite removed files by design"
else
  pass_msg "status: dead rows are exempt from path validation"
fi

echo "----------------------------------------------------------------------"
total=$((pass + fail))
echo "Results: ${pass}/${total} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
