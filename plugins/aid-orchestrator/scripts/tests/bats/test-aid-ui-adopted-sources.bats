#!/usr/bin/env bats
# aid-tier: t0
# P103 Step 1 — every adopted third-party file has a register row, every licence has its text.
# P108 Step 1 — the marketingskills snapshot (adopted/marketingskills/MANIFEST: git blob id per
# file) is byte-identical to upstream dda3841, nothing is added or missing, no symlink, and every
# adopted marketingskills file names the plugin file that reads it (column "Čte ho").

setup() {
  REF="$BATS_TEST_DIRNAME/../../../skills/ui-design/references"
  PLUGIN="$BATS_TEST_DIRNAME/../../.."
}

# check <refdir> [<plugin root>] — prints each problem, exits 1 on any.
check() {
  local ref="$1" plugin="${2:-$PLUGIN}" bad=0 f row lic
  # columns by header name, so a new column never shifts the others
  local hdr col_file col_lic col_reader
  hdr=$(grep -m1 '^| Soubor / pravidlo' "$ref/adopted-sources.md")
  col() { awk -F'|' -v n="$1" '{for(i=2;i<NF;i++){c=$i; gsub(/^ +| +$/,"",c); if(c==n){print i; exit}}}' <<<"$hdr"; }
  col_file=$(col "Soubor / pravidlo"); col_lic=$(col "Licence"); col_reader=$(col "Čte ho")
  if [[ -n "$(find "$ref/adopted" -type l)" ]]; then echo "symlink in adopted/: $(find "$ref/adopted" -type l | head -1)"; bad=1; fi
  while IFS= read -r f; do
    f="${f#"$ref"/}"
    row=$(grep -F "| \`$f\` |" "$ref/adopted-sources.md") || { echo "no register row: $f"; bad=1; continue; }
    [[ $(wc -l <<<"$row") -eq 1 ]] || { echo "duplicate register rows: $f"; bad=1; continue; }
    # file | source | commit | changes | licence | notice must not be empty
    awk -F'|' '{for(i=3;i<=7;i++) if ($i ~ /^ *$/) exit 1}' <<<"$row" || { echo "empty column: $f"; bad=1; }
    if [[ "$f" == adopted/marketingskills/* ]]; then
      local reader
      reader=$(awk -F'|' -v c="$col_reader" '{print $c}' <<<"$row")
      [[ "$reader" == *"(krok P108-"* ]] && continue   # reader added by a later P108 step
      reader=$(grep -o '`[^`]*`' <<<"$reader" | head -1 | tr -d '`')
      if [[ -z "$reader" || ! -f "$plugin/$reader" ]]; then echo "no reader file for $f: '$reader'"; bad=1
      elif ! grep -qF "$f" "$plugin/$reader"; then echo "reader $reader does not name $f"; bad=1; fi
    fi
  done < <(find "$ref/adopted" -type f | sort)
  for lic in $(grep '^| ' "$ref/adopted-sources.md" | awk -F'|' -v c="$col_lic" 'NR>1{print $c}' | tr ',' '\n' | tr -d ' ' | sort -u); do
    ls "$ref/LICENSES/$lic"* >/dev/null 2>&1 || { echo "no licence text: $lic"; bad=1; }
  done
  [[ -n "$col_file" ]] || { echo "no header"; bad=1; }
  return $bad
}

# manifest <refdir> — adopted/marketingskills/MANIFEST lists exactly the files under it, each with
# the git blob id of its bytes (git hash-object), so a changed byte, a missing or an extra file fails.
manifest() {
  local m="$1/adopted/marketingskills" bad=0 id p listed
  [[ -f "$m/MANIFEST" ]] || { echo "no MANIFEST"; return 1; }
  while read -r id p; do
    [[ -f "$m/$p" ]] || { echo "missing: $p"; bad=1; continue; }
    [[ "$(git hash-object "$m/$p")" == "$id" ]] || { echo "changed: $p"; bad=1; }
  done < "$m/MANIFEST"
  listed=$(awk '{print $2}' "$m/MANIFEST" | sort)
  while IFS= read -r p; do
    grep -qxF "$p" <<<"$listed" || { echo "extra: $p"; bad=1; }
  done < <(cd "$m" && find . -type f ! -name MANIFEST | sed 's#^\./##' | sort)
  return $bad
}

@test "every adopted file has a full register row and every licence its text" {
  run check "$REF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "P108: a duplicated register row fails" {
  cp -r "$REF" "$BATS_TEST_TMPDIR/ref"
  grep -F '| `adopted/marketingskills/cro/SKILL.md` |' "$REF/adopted-sources.md" >> "$BATS_TEST_TMPDIR/ref/adopted-sources.md"
  run check "$BATS_TEST_TMPDIR/ref"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate register rows: adopted/marketingskills/cro/SKILL.md"* ]]
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

@test "P108: the marketingskills snapshot matches its MANIFEST (14 files, git blob ids)" {
  run manifest "$REF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(wc -l < "$REF/adopted/marketingskills/MANIFEST")" -eq 14 ]
  grep -q "Corey Haines" "$REF/LICENSES/MIT-marketingskills.txt"
}

@test "P108: a changed byte, a missing file and an extra file fail the manifest" {
  cp -r "$REF" "$BATS_TEST_TMPDIR/ref"; M="$BATS_TEST_TMPDIR/ref/adopted/marketingskills"
  printf ' ' >> "$M/copywriting/SKILL.md"
  run manifest "$BATS_TEST_TMPDIR/ref"; [ "$status" -eq 1 ]; [[ "$output" == *"changed: copywriting/SKILL.md"* ]]
  cp "$REF/adopted/marketingskills/copywriting/SKILL.md" "$M/copywriting/SKILL.md"
  rm "$M/cro/references/form.md"
  run manifest "$BATS_TEST_TMPDIR/ref"; [ "$status" -eq 1 ]; [[ "$output" == *"missing: cro/references/form.md"* ]]
  cp "$REF/adopted/marketingskills/cro/references/form.md" "$M/cro/references/form.md"
  echo x > "$M/cro/extra.md"
  run manifest "$BATS_TEST_TMPDIR/ref"; [ "$status" -eq 1 ]; [[ "$output" == *"extra: cro/extra.md"* ]]
}

@test "P108: a symlink in adopted/ and a reader that does not name its file fail" {
  cp -r "$REF" "$BATS_TEST_TMPDIR/ref"; R="$BATS_TEST_TMPDIR/ref"
  ln -s ../adopted-sources.md "$R/adopted/link.md"
  run check "$R"; [ "$status" -eq 1 ]; [[ "$output" == *"symlink in adopted/"* ]]
  rm "$R/adopted/link.md"
  # the MANIFEST row names this test file as its reader; a plugin root where the reader lacks the path fails
  mkdir -p "$BATS_TEST_TMPDIR/plugin/scripts/tests/bats"
  echo "nothing here" > "$BATS_TEST_TMPDIR/plugin/scripts/tests/bats/test-aid-ui-adopted-sources.bats"
  run check "$R" "$BATS_TEST_TMPDIR/plugin"; [ "$status" -eq 1 ]
  [[ "$output" == *"does not name adopted/marketingskills/MANIFEST"* ]]
}
