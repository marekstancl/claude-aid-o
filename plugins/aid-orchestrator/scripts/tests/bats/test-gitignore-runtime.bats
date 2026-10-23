#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: defaults/.gitignore
# What /aid-init writes into a project's .gitignore: AID's runtime files are ignored, the plans' own records are
# not, and every file the scripts write under .aid-o/work is decided one way or the other. Defect it catches: a
# runtime file left out (Trading 9. 10. 2026: active.md, audit-log.jsonl and locks showed up as uncommitted
# changes and stopped the FSM four times).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  R="$BATS_TEST_TMPDIR/r"; mkdir -p "$R"; git -C "$R" init -q
  cp "$AID_PLUGIN_PATH/defaults/.gitignore" "$R/.gitignore"
}

# the two lists: a name the scripts write under .aid-o/work is one or the other
RUNTIME="evidence plan-final quick timeline.jsonl interim- audit-log.jsonl lifecycle-migration.log active.md active-runs.json active-run-pointer.json auto-mode-state.yaml codex-probe.json test-durations.jsonl release-force- companion superseded-runs runs test-audits"
VERSIONED="backlog.md aid-plugin-issues.md plan-state brainstorm backlog"

@test "gitignore: AID's runtime files are ignored, the plans' records are not" {
  local p
  for p in audit-log.jsonl lifecycle-migration.log active.md active-runs.json active-run-pointer.json auto-mode-state.yaml \
           codex-probe.json test-durations.jsonl release-force-P900.json companion/P900/x.png superseded-runs/a/b \
           runs/R-1/x.md test-audits/x plan-final/P900/x .cache/x x.lock evidence/P900/x timeline.jsonl interim-P900.md; do
    git -C "$R" check-ignore -q ".aid-o/work/$p" || { echo "not ignored: .aid-o/work/$p"; return 1; }
  done
  git -C "$R" check-ignore -q .aid-o/config/x.lock; git -C "$R" check-ignore -q .aid-o/.lock; git -C "$R" check-ignore -q .aid-o/work/a/b.tmp
  for p in backlog.md aid-plugin-issues.md plan-state/P900/plan-state.yaml brainstorm/P900/vision.md; do
    ! git -C "$R" check-ignore -q ".aid-o/work/$p" || { echo "ignored but a record: .aid-o/work/$p"; return 1; }
  done
}

@test "gitignore: every name the scripts write under .aid-o/work is decided — runtime (ignored) or versioned" {
  local n missing=""
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    [[ " $RUNTIME $VERSIONED " == *" $n "* ]] || missing+=" $n"
  done < <(grep -rhE '\.aid-o/work/[A-Za-z]' "$AID_PLUGIN_PATH/scripts" "$AID_PLUGIN_PATH/lib" "$AID_PLUGIN_PATH/defaults/hooks" \
             --include=*.sh --include=*.py --include=*.js --include=*.mjs --exclude-dir=tests 2>/dev/null \
           | grep -vE '^[[:space:]]*(#|//)' | grep -oE '\.aid-o/work/[A-Za-z][A-Za-z0-9_.-]*' \
           | sed -E 's#^\.aid-o/work/##; s#[.]$##; s#^(interim|release-force)-.*#\1-#' | sort -u)
  [[ -z "$missing" ]] || { echo "undecided:$missing — add each to RUNTIME (and defaults/.gitignore) or VERSIONED"; return 1; }
}

@test "gitignore: the block /aid-init documents is the file it copies" {
  local doc; doc="$(awk '/^### .gitignore \(copied from defaults\/.gitignore\)/{f=1} f && /^```gitignore/{g=1; next} g && /^```/{exit} g' "$AID_PLUGIN_PATH/commands/aid-init.md")"
  local l; while IFS= read -r l; do
    [[ -z "$l" || "$l" == \#* ]] && continue
    grep -qxF -- "$l" "$AID_PLUGIN_PATH/defaults/.gitignore" || { echo "documented but not in defaults/.gitignore: $l"; return 1; }
  done <<< "$doc"
}
