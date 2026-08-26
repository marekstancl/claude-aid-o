#!/usr/bin/env bats
# aid-tier: t0
# test-release-paths-drift.bats — the declared release paths versus what the
# image actually packages (P089 Step 10).
#
# WIRING, SO NOBODY MISREADS A GREEN RUN: these cases prove the gate DECIDES
# correctly. They say nothing about whether it BLOCKS: in this repository it is
# wired as `check_release_paths` with `required: false`, so a disagreement is
# reported and the run continues, and in a consumer project it is wired to
# nothing until that project asks for it.

load test-helpers.bash

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  GATE="$AID_PLUGIN_PATH/scripts/gates/release-paths-drift.sh"
  export GATE
  TMP="$(mktemp -d)"
  R="$TMP/repo"
  export TMP R
  mkdir -p "$R/.aid-o/config"
}

teardown() {
  cd /
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
  return 0
}

_config() {
  cat > "$R/.aid-o/config/project.yaml" <<'YAML'
versioning:
  release_exempt_paths:
    - tests
    - docs
  app_paths:
    - src
    - package.json
YAML
}

_dockerfile() { printf '%s\n' "$@" > "$R/Dockerfile"; }

@test "AC28: a source that lies entirely in the exempt paths fails the gate" {
  _config
  _dockerfile 'FROM node:20' 'COPY src /app/src' 'COPY tests /app/tests'
  run bash "$GATE" --root "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"packages 'tests'"* ]]
  [[ "$output" == *"would ship without a release"* ]]
}

@test "AC29: a source outside app_paths fails the gate" {
  _config
  _dockerfile 'FROM node:20' 'COPY src /app/src' 'COPY vendor /app/vendor'
  run bash "$GATE" --root "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"packages 'vendor'"* ]]
  [[ "$output" == *"app_paths does not cover"* ]]
}

@test "sources that agree with both lists pass" {
  _config
  _dockerfile 'FROM node:20' 'COPY package.json /app/' 'COPY src /app/src'
  run bash "$GATE" --root "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"agree with the declared release paths"* ]]
}

@test "a multi-stage build's --from= sources are not repository paths and are ignored" {
  _config
  _dockerfile 'FROM node:20 AS build' 'COPY src /app/src' \
              'FROM node:20' 'COPY --from=build /app/dist /app/dist'
  run bash "$GATE" --root "$R"
  [ "$status" -eq 0 ]
}

@test "a wrapped COPY is read whole, not half" {
  _config
  _dockerfile 'FROM node:20' 'COPY src \' '     tests \' '     /app/'
  run bash "$GATE" --root "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"packages 'tests'"* ]]
}

@test "COPY . . is reported as the widest drift there is, not waved through" {
  _config
  _dockerfile 'FROM node:20' 'COPY . .'
  run bash "$GATE" --root "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"whole build context"* ]]
}

@test "AC30: a project with no Dockerfile does not run the gate" {
  _config
  run bash "$GATE" --root "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no Dockerfile"* ]]
}

@test "a project with no declared lists has no claim to compare against" {
  _dockerfile 'FROM node:20' 'COPY tests /app/tests'
  run bash "$GATE" --root "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"neither versioning.release_exempt_paths nor"* ]]
}

@test "a Dockerfile that exists and cannot be read is an error, never a pass" {
  _config
  _dockerfile 'FROM node:20' 'COPY src /app/src'
  chmod 000 "$R/Dockerfile"
  run bash "$GATE" --root "$R"
  chmod 644 "$R/Dockerfile"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot be read"* ]]
}

@test "a comment line is not an instruction" {
  _config
  _dockerfile 'FROM node:20' '# COPY tests /app/tests' 'COPY src /app/src'
  run bash "$GATE" --root "$R"
  [ "$status" -eq 0 ]
}

# ─── two shapes a shell split gets wrong (Codex, P089) ──────────────────────

@test "a glob source is not expanded against the caller's working directory" {
  _config
  _dockerfile 'FROM node:20' 'COPY package*.json /app/'
  # A file the glob WOULD match if it were expanded here, in a directory that
  # is not the build context.
  local here; here="$(mktemp -d)"
  : > "$here/package-lock.json"
  run bash -c "cd '$here' && bash '$GATE' --root '$R'"
  rm -rf "$here"
  # The source judged is the literal 'package*.json', which app_paths does not
  # cover — never 'package-lock.json' picked up from wherever the gate ran.
  [ "$status" -eq 1 ]
  [[ "$output" == *"package*.json"* ]]
  [[ "$output" != *"package-lock.json"* ]]
}

@test "the JSON-array COPY form is parsed as sources, not as shell words" {
  _config
  _dockerfile 'FROM node:20' 'COPY ["src", "/app/"]'
  run bash "$GATE" --root "$R"
  [ "$status" -eq 0 ]
}

@test "the JSON-array form still catches a genuinely exempt source" {
  _config
  _dockerfile 'FROM node:20' 'COPY ["tests", "/app/tests"]'
  run bash "$GATE" --root "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"packages 'tests'"* ]]
}
