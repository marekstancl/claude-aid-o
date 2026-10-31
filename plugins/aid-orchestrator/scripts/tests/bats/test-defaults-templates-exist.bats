#!/usr/bin/env bats
# aid-tier: t0
# aid-subject: plugins/aid-orchestrator/defaults/templates
# Every template a script, command, skill or agent card reads from defaults/templates/ exists. Defect it catches:
# aid-stand-in.sh ask read defaults/templates/stand-in-decision.md, which was never written — every stand-in
# decision since 3.8.0 went out without its instructions and printed `cat: … No such file` (WAN P115 25. 10.,
# P116 28. 10. 2026, three times). Tests and their fixtures, and comment lines, are not code that reads a file.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
}

@test "every defaults/templates/<file> the plugin's code names exists" {
  cd "$AID_PLUGIN_PATH"
  local missing="" f
  while IFS= read -r f; do
    [[ -e "$f" ]] || missing+=" $f"
  done < <(grep -rhE 'defaults/templates/' scripts commands skills agents --exclude-dir=tests 2>/dev/null \
             | grep -vE '^[[:space:]]*#' | grep -oE 'defaults/templates/[A-Za-z0-9._-]+\.[a-z]+' | sort -u)
  [[ -z "$missing" ]] || { echo "missing:$missing"; false; }
}

@test "every artifact template an aid_artifact_render call names exists (artifact-<id>.html)" {
  cd "$AID_PLUGIN_PATH"
  local ids missing="" id
  ids="$(grep -rhE 'aid_artifact_render [a-z]' scripts --include='*.sh' --exclude-dir=tests | grep -vE '^[[:space:]]*#' \
           | grep -oE 'aid_artifact_render [a-z][a-z0-9-]*' | awk '{print $2}' | sort -u)"
  [[ -n "$ids" ]]                                                            # the scan found the calls at all
  for id in $ids; do [[ -f "defaults/templates/artifact-${id}.html" ]] || missing+=" $id"; done
  [[ -z "$missing" ]] || { echo "missing artifact templates:$missing"; false; }
}

@test "the stand-in's prompt opens with its instructions, not a cat error" {
  grep -q '^# Independent decision on one run decision' "$AID_PLUGIN_PATH/defaults/templates/stand-in-decision.md"
  grep -q 'technical' "$AID_PLUGIN_PATH/defaults/templates/stand-in-decision.md"
}
