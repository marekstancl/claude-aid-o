#!/usr/bin/env bats
# aid-tier: t0
# P103 Step 1 — every adopted third-party file has a register row, every licence has its text.

setup() {
  REF="$BATS_TEST_DIRNAME/../../../skills/ui-design/references"
}

# check <refdir> — prints each problem, exits 1 on any.
check() {
  local ref="$1" bad=0 f row lic
  for f in "$ref"/adopted/*; do
    f="adopted/$(basename "$f")"
    row=$(grep -F "| \`$f\` |" "$ref/adopted-sources.md") || { echo "no register row: $f"; bad=1; continue; }
    # columns: file | source | commit | changes | licence | notice
    awk -F'|' '{for(i=3;i<=7;i++) if ($i ~ /^ *$/) exit 1}' <<<"$row" || { echo "empty column: $f"; bad=1; }
  done
  for lic in $(grep '^| ' "$ref/adopted-sources.md" | awk -F'|' 'NR>1{print $6}' | tr ',' '\n' | tr -d ' ' | sort -u); do
    ls "$ref/LICENSES/$lic"* >/dev/null 2>&1 || { echo "no licence text: $lic"; bad=1; }
  done
  return $bad
}

@test "every adopted file has a full register row and every licence its text" {
  run check "$REF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "an adopted file without a register row fails" {
  cp -r "$REF" "$BATS_TEST_TMPDIR/ref"
  echo x > "$BATS_TEST_TMPDIR/ref/adopted/unregistered.md"
  run check "$BATS_TEST_TMPDIR/ref"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no register row: adopted/unregistered.md"* ]]
}

@test "a licence without its text fails" {
  cp -r "$REF" "$BATS_TEST_TMPDIR/ref"
  rm "$BATS_TEST_TMPDIR/ref/LICENSES/MIT"*
  run check "$BATS_TEST_TMPDIR/ref"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no licence text: MIT"* ]]
}
