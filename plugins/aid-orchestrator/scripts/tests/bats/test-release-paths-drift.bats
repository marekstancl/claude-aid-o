#!/usr/bin/env bats
# aid-tier: t0
# test-release-paths-drift.bats — the declared release paths versus what the
# image actually packages (P089 Step 10).
#
# WIRING, SO NOBODY MISREADS A GREEN RUN: in THIS repository the gate is
# attached to no runner. These cases prove it DECIDES correctly; they do not
# claim anything runs it. That distinction is also written into its enforcement
# registry row.

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
