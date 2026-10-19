#!/usr/bin/env bats
# aid-tier: t0
# test-static.bats — the pulse: every file of the plugin parses. Nothing of AID
# runs here (ecosystem test standard, T0 = lint, syntax, types; PM 15. 10. 2026).
# Defect caught: a script, page, config or default that no longer parses — the
# one that would break every command before any behaviour test gets to it.
# Fails closed: no file of a kind, or a missing parser, is a failure, not a pass.

setup_file() {
  PLUGIN="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export PLUGIN
}

# _files <root> <name patterns…> — fixtures are deliberately broken, node_modules is not ours
_files() {
  local root="$1" args=() p; shift
  for p in "$@"; do args+=(-o -name "$p"); done
  find "$root" \( -name node_modules -o -name fixtures \) -prune -o -type f \( "${args[@]:1}" \) -print
}

# _shebang_scripts <root> — files without an extension that start as a shell script (git hooks)
_shebang_scripts() {
  local f
  while IFS= read -r f; do head -1 "$f" | grep -qE '^#!.*\b(ba)?sh\b' && printf '%s\n' "$f"; done \
    < <(find "$1" \( -name node_modules -o -name fixtures \) -prune -o -type f ! -name '*.*' -print)
}

# _unparsable <root> <kind> — prints every file of <kind> under <root> that does not parse;
# returns 1 when there is none of that kind to check or its parser is missing
_unparsable() {
  local root="$1" kind="$2" f files tool
  case "$kind" in
    sh)   files="$(_files "$root" '*.sh' '*.bash'; _shebang_scripts "$root")"; tool=bash ;;
    js)   files="$(_files "$root" '*.js' '*.mjs')"; tool=node ;;
    py)   files="$(_files "$root" '*.py')"; tool=python3 ;;
    json) files="$(_files "$root" '*.json')"; tool=jq ;;
    yaml) files="$(_files "$root" '*.yaml' '*.yml')"; tool=yq ;;
  esac
  command -v "$tool" >/dev/null || { echo "no $tool to parse $kind"; return 1; }
  [[ -n "$files" ]] || { echo "no $kind file found under $root"; return 1; }
  if [[ "$kind" == py ]]; then   # one interpreter for all of them: a start per file costs seconds
    local list; mapfile -t list <<<"$files"   # a name with a space stays one name
    python3 -c 'import sys
for f in sys.argv[1:]:
    try: compile(open(f, encoding="utf-8").read(), f, "exec")
    except (SyntaxError, ValueError): print("does not parse: " + f)' "${list[@]}"
    return 0
  fi
  while IFS= read -r f; do
    case "$kind" in
      sh)   head -1 "$f" | grep -q bats && continue   # a bats suite is not bash; bats parses it when it runs
            bash -n "$f" 2>/dev/null ;;
      js)   node --check "$f" 2>/dev/null ;;
      json) jq empty "$f" 2>/dev/null ;;
      yaml) yq '.' "$f" >/dev/null 2>&1 ;;
    esac || echo "does not parse: $f"
  done <<<"$files"
}

# _parses <kind> — the plugin's files of <kind> all parse (one case per kind keeps each under 2 s)
_parses() { run _unparsable "$PLUGIN" "$1"; [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$output"; return 1; }; }

@test "every shell script of the plugin parses" { _parses sh; }
@test "every JavaScript file of the plugin parses" { _parses js; }
@test "every Python file of the plugin parses" { _parses py; }
@test "every JSON file of the plugin parses" { _parses json; }
@test "every YAML file of the plugin parses" { _parses yaml; }

@test "a broken file of each kind is caught, and a kind with no file fails" {
  local d="$BATS_TEST_TMPDIR/p" kind; mkdir -p "$d"
  printf 'if then\n' > "$d/a.sh"; printf 'function (\n' > "$d/a.js"; printf 'def (\n' > "$d/a.py"
  printf '{"a":\n' > "$d/a.json"; printf 'a: [\n' > "$d/a.yaml"; printf '#!/bin/sh\nif then\n' > "$d/hook"
  for kind in sh js py json yaml; do
    run _unparsable "$d" "$kind"; [[ "$output" == *"does not parse: $d/a."* ]] || { echo "$kind: $output"; return 1; }
  done
  run _unparsable "$d" sh; [[ "$output" == *"does not parse: $d/hook"* ]]   # a hook has no extension
  printf 'return 1\n' > "$d/a.py"; run _unparsable "$d" py; [[ "$output" == *"does not parse: $d/a.py"* ]]   # parses, does not compile
  rm "$d/a.py"; run _unparsable "$d" py
  [ "$status" -eq 1 ]; [[ "$output" == *"no py file found"* ]]
  PATH="$BATS_TEST_TMPDIR/nothing" run _unparsable "$d" js
  [ "$status" -eq 1 ]; [[ "$output" == *"no node to parse js"* ]]
}

@test "no test fixture is ignored by git: a fixture under a docs/ directory is tracked, not left on one machine (AID 14. 10. 2026)" {
  local root; root="$(cd "$BATS_TEST_DIRNAME/../../.." && git rev-parse --show-toplevel)"
  run git -C "$root" check-ignore -q "plugins/aid-orchestrator/scripts/tests/fixtures/any/project/docs/content/x.yaml"
  [ "$status" -eq 1 ]
  run git -C "$root" ls-files -oi --exclude-standard -- plugins/aid-orchestrator/scripts/tests/fixtures
  [ -z "$(grep -v '/node_modules/' <<< "$output")" ] || { echo "ignored fixtures: $output"; false; }
}
