#!/usr/bin/env bats
# aid-tier: t0
# The brief file (P109 Step 1): `aid-plan-lint.sh --zadani` refuses a brief out
# of shape, one case per branch of the reader (lib/aid-zadani.sh) and of the
# block validator shared with the plan check's A6 (lib/aid-verification-pattern.sh).
# Defects caught, by case: a brief without a done-when section the plan lint
# would silently accept; a brief without stakes the critic cannot read; a point
# id the plan cannot reference; a point aid-plan-diff.sh cannot run; a brief
# version the sha binding cannot name; an A6 or runner regression from the move.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  LINT="$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh"
  GOOD="$AID_PLUGIN_PATH/scripts/tests/fixtures/zadani/p109-zadani.md"
  T="$(mktemp -d)"; B="$T/P1-zadani.md"
  cp "$GOOD" "$B"
}

teardown() { rm -rf "$T"; }

@test "zadani: the P109 brief passes with eleven points" {
  run "$LINT" --zadani "$GOOD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"zadani OK (11 points)"* ]]
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-zadani.sh'; aid_zadani_points '$GOOD' | wc -l"
  [ "$output" -eq 11 ]
}

@test "zadani: the template itself is in shape" {
  run "$LINT" --zadani "$AID_PLUGIN_PATH/defaults/templates/zadani.md"
  [ "$status" -eq 0 ]
}

@test "zadani: a missing section is refused by name" {
  sed -i 's/^## 2\. Změřený výchozí stav/## 2. Stav/' "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"## 2. Změřený výchozí stav" is missing'* ]]
}

@test "zadani: a brief without the stakes paragraph is refused" {
  sed -i 's/^\*\*Co je v sázce:\*\*/Co je v sázce:/' "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Co je v sázce"* ]]
}

@test "zadani: a gap in the numbering is refused" {
  # AC2 relabelled AC3: AC1, AC3, AC3 — a gap and a duplicate
  sed -i 's/^- \[ \] AC2:/- [ ] AC3:/' "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC3 follows AC1"* ]]
  [[ "$output" == *"AC3 appears twice"* ]]
}

@test "zadani: a point without a block within 5 lines is refused" {
  awk '/^- \[ \] AC4:/ { print; for (i = 0; i < 5; i++) print "  filler"; next } 1' "$B" > "$T/x" && mv "$T/x" "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC4 has no verification_pattern block within 5 lines"* ]]
}

@test "zadani: a cmd block without cmd: is refused by the shared validator" {
  awk '/^- \[ \] AC5:/ { a = 1 } a && /^    cmd:/ { a = 0; next } 1' "$B" > "$T/x" && mv "$T/x" "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC5: verification_pattern type cmd without cmd:"* ]]
}

@test "zadani: frontmatter verze 0 is refused" {
  sed -i 's/^verze: .*/verze: 0/' "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verze '0' is not a positive integer"* ]]
}

@test "zadani: a doubled section, an out-of-order section and a section holding only a comment are refused" {
  printf '\n## 1. Co PM chce\n\nagain\n' >> "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]; [[ "$output" == *'"1. Co PM chce" appears twice'* ]]
  cp "$GOOD" "$B"
  awk '/^## 4\. Kde co je/ { hold = 1 } hold && /^## 5\./ { hold = 0 } hold { buf = buf $0 "\n"; next } { print } END { printf "%s", buf }' "$GOOD" > "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]; [[ "$output" == *'out of order'* ]]
  awk '/^## 5\. Pravidla práce/ { print; print ""; print "<!-- a template comment"; print "     over two lines -->"; skip = 1; next } skip && /^## / { skip = 0 } !skip' "$GOOD" > "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]; [[ "$output" == *'"5. Pravidla práce" is empty'* ]]
}

@test "zadani: a stakes label with no paragraph is refused" {
  awk '/^\*\*Co je v sázce:\*\*/ { print "**Co je v sázce:**"; print ""; skip = 1; next } skip && /^[[:space:]]*$/ { skip = 0; next } !skip' "$GOOD" > "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]; [[ "$output" == *'paragraph is empty'* ]]
}

@test "zadani: a checkbox without AC<n>, a point without text, a block not opening with verification_pattern and a cmd without expected_exit are refused" {
  awk '/^- \[ \] AC11:/ { print "- [ ] Release documentation" } 1' "$GOOD" > "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]; [[ "$output" == *'must be "- [ ] AC<n>: <text>"'* ]]
  sed 's/^- \[ \] AC3: .*/- [ ] AC3:/' "$GOOD" > "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]; [[ "$output" == *'AC3 has no text'* ]]
  awk '/^- \[ \] AC6:/ { a = 1 } a && /verification_pattern:/ { a = 0; next } 1' "$GOOD" > "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]; [[ "$output" == *"AC6: the block's first key must be verification_pattern:"* ]]
  awk '/^- \[ \] AC7:/ { a = 1 } a && /expected_exit:/ { a = 0; next } 1' "$GOOD" > "$B"
  run "$LINT" --zadani "$B"
  [ "$status" -eq 1 ]; [[ "$output" == *'AC7: a cmd block names its expected_exit'* ]]
}

@test "A6: the plan check still refuses a bad block after the validator moved" {
  cat > "$T/p.md" <<'EOF'
---
id: P1
---
# Plan

## Acceptance Criteria

- [ ] AC1: something
  ```yaml
  verification_pattern:
    type: must_contain
    file: "a.txt"
  ```
EOF
  run "$AID_PLUGIN_PATH/scripts/aid-plan-check.sh" "$T/p.md"
  [[ "$output" == *"BLOCK A6"*"must_contain needs file: and regex:"* ]]
}

@test "A6: the runner reads the same criteria after the parser moved" {
  mkdir -p "$T/ev"
  cat > "$T/p.md" <<'EOF'
# Plan

## Acceptance Criteria

- [ ] AC1: the ghost file is gone
  ```yaml
  verification_pattern:
    type: must_not_exist
    file: "ghost.txt"
  ```
- [ ] AC2: prose only
EOF
  cd "$T"
  run "$AID_PLUGIN_PATH/scripts/aid-plan-diff.sh" --plan "$T/p.md" --evidence-dir "$T/ev" --base-commit HEAD
  [ "$(jq -r '.ac_count' "$T/ev/plan-diff.json")" -eq 2 ]
  [ "$(jq -r '.results[0].verdict' "$T/ev/plan-diff.json")" = present ]
}

@test "zadani: the brief beside a plan is never taken for the plan" {
  mkdir -p "$T/.aid-o/plans"
  cp "$GOOD" "$T/.aid-o/plans/P7-zadani.md"
  echo "# plan" > "$T/.aid-o/plans/P7-zzz-plan.md"
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-roots.sh'; aid_plan_files '$T/.aid-o/plans' P7"
  [ "$output" = "$T/.aid-o/plans/P7-zzz-plan.md" ]
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh'; aid_lifecycle_plan_file P7 '$T'"
  [ "$output" = "$T/.aid-o/plans/P7-zzz-plan.md" ]
  rm "$T/.aid-o/plans/P7-zzz-plan.md"
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh'; aid_lifecycle_plan_file P7 '$T'"
  [ -z "$output" ]
}
