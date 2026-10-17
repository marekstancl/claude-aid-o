#!/usr/bin/env bats
# aid-tier: t1
# P103 Step 1 — every adopted third-party file has a register row, every licence has its text.
# P108 Step 1 — the marketingskills snapshot (adopted/marketingskills/MANIFEST: git blob id per
# file) is byte-identical to upstream dda3841, nothing is added or missing, no symlink, and every
# adopted marketingskills file names the plugin file that reads it (column "Čte ho").
# P108 (7. 10.): the same for the logo-design snapshot (adopted/logo-design, upstream 0ecf52e, 25 files).

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
    if [[ "$f" == adopted/marketingskills/* || "$f" == adopted/logo-design/* ]]; then
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

# manifest <refdir> <snapshot|folder/> — adopted/<snapshot>/MANIFEST (or <refdir>/<folder>/MANIFEST when the second
# argument ends in /, P113: the standards' copies) lists exactly the files under it, each with the git blob id of its
# bytes (git hash-object), so a changed byte, a missing or an extra file fails. A SOURCES file is no copy.
manifest() {
  local m="$1/adopted/${2:-marketingskills}" bad=0 id p listed
  [[ "${2:-}" != */ ]] || m="$1/${2%/}"
  [[ -f "$m/MANIFEST" ]] || { echo "no MANIFEST"; return 1; }
  while read -r id p; do
    [[ -f "$m/$p" ]] || { echo "missing: $p"; bad=1; continue; }
    [[ "$(git hash-object "$m/$p")" == "$id" ]] || { echo "changed: $p"; bad=1; }
  done < "$m/MANIFEST"
  listed=$(awk '{print $2}' "$m/MANIFEST" | sort)
  while IFS= read -r p; do
    grep -qxF "$p" <<<"$listed" || { echo "extra: $p"; bad=1; }
  done < <(cd "$m" && find . -type f ! -name MANIFEST ! -name SOURCES | sed 's#^\./##' | sort)
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
  run manifest "$REF" marketingskills
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(wc -l < "$REF/adopted/marketingskills/MANIFEST")" -eq 14 ]
  grep -q "Corey Haines" "$REF/LICENSES/MIT-marketingskills.txt"
}

@test "P108: a changed byte, a missing file and an extra file fail the manifest" {
  cp -r "$REF" "$BATS_TEST_TMPDIR/ref"; M="$BATS_TEST_TMPDIR/ref/adopted/marketingskills"
  printf ' ' >> "$M/copywriting/SKILL.md"
  run manifest "$BATS_TEST_TMPDIR/ref" marketingskills; [ "$status" -eq 1 ]; [[ "$output" == *"changed: copywriting/SKILL.md"* ]]
  cp "$REF/adopted/marketingskills/copywriting/SKILL.md" "$M/copywriting/SKILL.md"
  rm "$M/cro/references/form.md"
  run manifest "$BATS_TEST_TMPDIR/ref" marketingskills; [ "$status" -eq 1 ]; [[ "$output" == *"missing: cro/references/form.md"* ]]
  cp "$REF/adopted/marketingskills/cro/references/form.md" "$M/cro/references/form.md"
  echo x > "$M/cro/extra.md"
  run manifest "$BATS_TEST_TMPDIR/ref" marketingskills; [ "$status" -eq 1 ]; [[ "$output" == *"extra: cro/extra.md"* ]]
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

@test "P108: the logo-design snapshot matches its MANIFEST (25 files, git blob ids of upstream 0ecf52e); the library is not in it" {
  run manifest "$REF" logo-design
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(wc -l < "$REF/adopted/logo-design/MANIFEST")" -eq 25 ]
  grep -q "kaankiziltug" "$REF/LICENSES/MIT-logo-design.txt"
  [ ! -e "$REF/adopted/logo-design/assets" ]; [ ! -e "$REF/adopted/logo-design/scripts/search_library.py" ]
  grep -q 'nepřevzato: logo-design `assets/library/`' "$REF/adopted-sources.md"
  # the scripts run here without the library: an audit of a plain mark passes
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><circle cx="128" cy="128" r="100"/></svg>' > "$BATS_TEST_TMPDIR/m.svg"
  run python3 "$REF/adopted/logo-design/scripts/svg_audit.py" "$BATS_TEST_TMPDIR/m.svg"; [ "$status" -eq 0 ]
  cp -r "$REF" "$BATS_TEST_TMPDIR/ref2"; printf ' ' >> "$BATS_TEST_TMPDIR/ref2/adopted/logo-design/SKILL.md"
  run manifest "$BATS_TEST_TMPDIR/ref2" logo-design; [ "$status" -eq 1 ]; [[ "$output" == *"changed: SKILL.md"* ]]
}

@test "P113a: the emil-skills snapshot is byte for byte what its MANIFEST lists" {
  run manifest "$REF" emil-skills
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "P113a (PM 13. 10. 2026: no dead skill): every adopted guidance file is required reading of a step method, or named here with why not" {
  python3 - "$REF/../sections.json" "$REF/adopted" <<'PY'
import json, glob, os, sys
d = json.load(open(sys.argv[1]))
read = {os.path.normpath(f) for m in d["methods"].values() if m for f in m["files"]}
NOT_GUIDANCE = {   # why each is not a method file
    "logo-design/TRADEMARKS.md": "a trademark notice, not a procedure",
    "logo-design/references/library-guide.md": "guides the logo library, which the snapshot does not ship",
}
dead = []
for f in sorted(glob.glob(sys.argv[2] + "/**/*.md", recursive=True)):
    rel = os.path.relpath(f, sys.argv[2])
    if rel in NOT_GUIDANCE:
        continue
    if os.path.normpath(os.path.join("skills/ui-design/references/adopted", rel)) not in read:
        dead.append(rel)
assert not dead, "adopted but read by no step method (sections.json methods): " + ", ".join(dead)
PY
}

# ---------------------------------------------------------------- P113 step 5: the standards inside the plugin
@test "standards: the copies match their MANIFEST byte for byte, SOURCES names each one, and they are the coverage sources" {
  run manifest "$REF" standards/; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(grep -c . "$REF/standards/MANIFEST")" -ge 12 ]
  for p in $(awk '{print $2}' "$REF/standards/MANIFEST"); do grep -q "^$p ecosystem/" "$REF/standards/SOURCES" || { echo "no source for $p"; return 1; }; done
  for s in $(yq -r '.sources[]' "$REF/../coverage/sources.yaml"); do grep -q " $s$" "$REF/standards/SOURCES" || { echo "no copy of coverage source $s"; return 1; }; done
  # a changed byte fails
  cp -r "$REF" "$BATS_TEST_TMPDIR/ref"; echo x >> "$BATS_TEST_TMPDIR/ref/standards/seo/index.md"
  run manifest "$BATS_TEST_TMPDIR/ref" standards/; [ "$status" -eq 1 ]; [[ "$output" == *"changed: seo/index.md"* ]]
}

@test "standards: no step, SKILL.md, command file, method map or studio server needs /opt/eco/docs" {
  run grep -rn '/opt/eco/docs' "$PLUGIN/skills/ui-design/steps" "$PLUGIN/skills/ui-design/SKILL.md" "$PLUGIN/commands/aid-ui.md" \
    "$PLUGIN/skills/ui-design/sections.json" "$PLUGIN/lib/aid-ui-studio/server.py" "$PLUGIN/scripts/aid-ui-coverage.sh"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  for f in $(jq -r '[.methods[] | select(type == "object") | .files[]] | unique[]' "$PLUGIN/skills/ui-design/sections.json"); do
    [[ "$f" != /* ]] || { echo "a method file outside the plugin: $f"; return 1; }
  done
}

@test "standards: a project without a declared standards map is checked against the plugin's copies with a warning and exit 0; a declared one is read" {
  P="$BATS_TEST_TMPDIR/p"; mkdir -p "$P"
  run bash "$PLUGIN/scripts/aid-ui-coverage.sh" check "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"projekt nemá mapu standardů"* ]]; [[ "$output" == *"coverage ok"* ]]
  # a declared docs tree is the project's own data: read there (here a copy of the standards with one changed item)
  D="$BATS_TEST_TMPDIR/docs/ecosystem/specs"; mkdir -p "$D/seo" "$BATS_TEST_TMPDIR/docs/ecosystem/templates" "$P/.aid-o/config"
  while read -r rel src; do [[ "$rel" == \#* || -z "$rel" ]] && continue; mkdir -p "$BATS_TEST_TMPDIR/docs/$(dirname "$src")"; cp "$REF/standards/$rel" "$BATS_TEST_TMPDIR/docs/$src"; done < "$REF/standards/SOURCES"
  touch "$D/standards-map.md"; printf 'standards:\n  map_path: %s\n' "$D/standards-map.md" > "$P/.aid-o/config/project.yaml"
  run bash "$PLUGIN/scripts/aid-ui-coverage.sh" check "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }; [[ "$output" != *"nemá mapu"* ]]
  sed -i '0,/^- /s/^- \(.*\)$/- \1 ZMĚNA/' "$D/design-system-standard.md"
  run bash "$PLUGIN/scripts/aid-ui-coverage.sh" check "$P"; [ "$status" -ne 0 ]   # the declared tree, not the copies
}
