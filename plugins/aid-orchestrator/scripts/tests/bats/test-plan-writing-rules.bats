#!/usr/bin/env bats
# aid-tier: t2
# test-plan-writing-rules.bats — plan-writing.md rule #21 pre-screen activation tests
#
# Verifies that the mechanical handler-pattern heuristic (rule #21) correctly
# identifies plans containing request handler patterns and marks them for
# branch-coverage review.
#
# The pre-screen logic is intentionally lightweight — it is a grep/regex check
# that runs BEFORE LLM judgment. These tests validate pattern detection only,
# not the LLM verdict.

setup() {
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "$TMPDIR_TEST"
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# ---------------------------------------------------------------------------
# Fixture: handler_fixture.md
# A minimal plan containing a FastAPI handler — must trigger #21 pre-screen.
# ---------------------------------------------------------------------------

create_handler_fixture() {
  mkdir -p "${TMPDIR_TEST}/fixtures"
  cat > "${TMPDIR_TEST}/fixtures/handler_fixture.md" <<'EOF'
## Plan: Add user login endpoint

### Implementation Detail

Add a new FastAPI route to handle user authentication:

```python
@app.post("/login")
async def login(request: Request):
    data = await request.json()
    user = authenticate(data["username"], data["password"])
    return {"token": user.token}
```

### Artifacts

- `api/auth.py` — login handler
EOF
}

create_no_handler_fixture() {
  mkdir -p "${TMPDIR_TEST}/fixtures"
  cat > "${TMPDIR_TEST}/fixtures/no_handler_fixture.md" <<'EOF'
## Plan: Update configuration values

### Implementation Detail

Change the `MAX_CONNECTIONS` constant in `config.py` from 10 to 50.
Update the corresponding unit test in `tests/test_config.py`.

### Artifacts

- `config.py` — constant update
- `tests/test_config.py` — test update
EOF
}

# Inline regex check matching the pre-screen heuristic from plan-writing.md #21
check_handler_patterns() {
  local file="$1"
  grep -qE '@app\.[a-z]+\(|@router\.[a-z]+\(|add_route\(|def [a-zA-Z_]+\(.*request|async def [a-zA-Z_]+\(.*request' "$file"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "#21 pre-screen: handler_fixture.md with @app.post triggers activation" {
  create_handler_fixture
  run check_handler_patterns "${TMPDIR_TEST}/fixtures/handler_fixture.md"
  [ "$status" -eq 0 ]
}

@test "#21 pre-screen: handler_fixture.md with async def login(request:...) triggers activation" {
  create_handler_fixture
  # Verify the async def pattern specifically
  run grep -q 'async def login(request' "${TMPDIR_TEST}/fixtures/handler_fixture.md"
  [ "$status" -eq 0 ]
}

@test "#21 pre-screen: no_handler_fixture.md does NOT trigger activation" {
  create_no_handler_fixture
  run check_handler_patterns "${TMPDIR_TEST}/fixtures/no_handler_fixture.md"
  [ "$status" -ne 0 ]
}

@test "#21 pre-screen: @router.<method>( pattern triggers activation" {
  cat > "${TMPDIR_TEST}/router_plan.md" <<'EOF'
## Implementation Detail
@router.get("/items")
async def list_items(request: Request):
    return []
EOF
  run check_handler_patterns "${TMPDIR_TEST}/router_plan.md"
  [ "$status" -eq 0 ]
}

@test "#21 pre-screen: add_route( pattern triggers activation" {
  cat > "${TMPDIR_TEST}/add_route_plan.md" <<'EOF'
## Implementation Detail
app.add_route("/health", health_check, methods=["GET"])
EOF
  run check_handler_patterns "${TMPDIR_TEST}/add_route_plan.md"
  [ "$status" -eq 0 ]
}

@test "#21 pre-screen: plain def with request param triggers activation" {
  cat > "${TMPDIR_TEST}/def_request_plan.md" <<'EOF'
## Implementation Detail
def handle_webhook(request, db_session):
    payload = request.body
    process(payload)
EOF
  run check_handler_patterns "${TMPDIR_TEST}/def_request_plan.md"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Band-scoped obligations (P084 Step 3)
#
# The band split is written in plan-writing.md and ENFORCED by aid-plan-lint.sh,
# which reads the band from the shared classifier lib/aid-plan-band.sh (NOT by
# calling the gate — the gate is consulted once per plan and the lint runs
# inside generation's pre-flight). These cases assert the two halves
# agree: what the document promises a light plan is not asked for, the lint does
# not ask for either.
# ---------------------------------------------------------------------------

# write_step_plan <path> <declared file> — a strict-cohort plan with exactly one
# step that carries the UNIVERSAL fields and none of the band-scoped ones.
write_step_plan() {
  cat > "$1" <<EOF
---
id: P998
type: plan
lifecycle_strict: true
---

## Testing Strategy

No new verification — these fixtures exercise the band-scoped step obligations.

## Implementation Steps

### Step 1: the step

**Objective:** do the thing.

**Files:**
- Modify: \`$2\` — the thing

**Implementation Detail:** one sentence is enough here.

**Dependencies:**
- Depends on: none

**Acceptance Criteria:**
- [ ] AC1 — the thing is done

**Effort:** S
**AID Role:** docs
EOF
}

@test "AC10: a light plan passes the lint with no Architecture Context and no Edge Cases" {
  write_step_plan "${TMPDIR_TEST}/light.md" "plugins/aid-orchestrator/commands/aid-help.md"
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "${TMPDIR_TEST}/light.md"
  [ "$status" -eq 0 ]
}

@test "AC11: the same step in a full plan does not pass — the band-scoped fields are owed" {
  write_step_plan "${TMPDIR_TEST}/full.md" "plugins/aid-orchestrator/scripts/aid-fsm.sh"
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "${TMPDIR_TEST}/full.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"band=full step is missing Architecture Context,Error Handling,Edge Cases"* ]]
}

@test "a legacy plan gets the same finding as an advisory, never a block" {
  write_step_plan "${TMPDIR_TEST}/legacy.md" "plugins/aid-orchestrator/scripts/aid-fsm.sh"
  sed -i '/^lifecycle_strict:/d' "${TMPDIR_TEST}/legacy.md"
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "${TMPDIR_TEST}/legacy.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN legacy] band=full step is missing"* ]]
}

@test "AC9: every one of the 28 completeness checks carries a band verdict" {
  skill="$PLUGIN_ROOT/skills/plan-writing.md"
  # The verdict table is the answer to "does this check apply to my band" — a
  # check absent from it would silently read as universal, which is exactly the
  # ambiguity the table exists to remove.
  table="$(sed -n '/^### Which checks apply to which band/,/^### Gate Failure Recovery/p' "$skill")"
  [ -n "$table" ]
  for check in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 17a 17b 17c 17d 17e 18 19 20a 20b 20c 21; do
    echo "$table" | grep -qE "^\| [^|]*\b${check}\b" || {
      echo "check ${check} has no verdict row" >&2
      return 1
    }
  done
  # And the verdict column uses exactly the two sanctioned words — a third one
  # ("mostly", "n/a", "see below") would be a verdict nobody can act on.
  verdicts="$(printf '%s\n' "$table" | grep -oE '\| (universal|band-scoped) \|' | sort -u | wc -l)"
  [ "$verdicts" -eq 2 ]
}

@test "an EMPTY band-scoped field label does not satisfy the obligation" {
  # Three bare labels used to pass all three checks while saying nothing
  # (codex review of EPIC 1, finding 6).
  write_step_plan "${TMPDIR_TEST}/empty.md" "plugins/aid-orchestrator/scripts/aid-fsm.sh"
  printf '\n**Architecture Context:**\n\n**Error Handling:**\n\n**Edge Cases:**\n' \
    >> "${TMPDIR_TEST}/empty.md"
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "${TMPDIR_TEST}/empty.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing Architecture Context,Error Handling,Edge Cases"* ]]
}

@test "a Testing Strategy section that is only a sub-heading is not a strategy" {
  write_step_plan "${TMPDIR_TEST}/heading.md" "plugins/aid-orchestrator/commands/aid-help.md"
  # Replace the fixture's real strategy with one that is only a sub-heading.
  sed -i '/^No new verification/d' "${TMPDIR_TEST}/heading.md"
  sed -i 's/^## Testing Strategy$/## Testing Strategy\n\n### Tests/' "${TMPDIR_TEST}/heading.md"
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "${TMPDIR_TEST}/heading.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Testing Strategy"* ]]
}

@test "a risk: high plan is checked as full even when it declares only texts" {
  # The escalation lives in the classifier, so the lint cannot forget it
  # (codex review of EPIC 1, finding 4).
  write_step_plan "${TMPDIR_TEST}/high.md" "plugins/aid-orchestrator/commands/aid-help.md"
  sed -i 's/^type: plan$/type: plan\nrisk: high/' "${TMPDIR_TEST}/high.md"
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "${TMPDIR_TEST}/high.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"band=full step is missing"* ]]
}


@test "a step quoted inside a fenced block is not linted as a step" {
  write_step_plan "${TMPDIR_TEST}/fenced.md" "plugins/aid-orchestrator/scripts/aid-fsm.sh"
  # Give the real step what its band owes, then quote an example step that has
  # none of it. Only the quoted one is missing fields, and it must not be seen.
  printf '\n**Architecture Context:**\nIt sits in the gate.\n\n**Error Handling:** fail closed.\n\n**Edge Cases:**\n- one\n' \
    >> "${TMPDIR_TEST}/fenced.md"
  printf '\n## Appendix\n\n```markdown\n### Step 99: quoted example\n\n**Objective:** nothing real.\n```\n' \
    >> "${TMPDIR_TEST}/fenced.md"
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "${TMPDIR_TEST}/fenced.md"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Step 99"* ]]
}

# ---------------------------------------------------------------------------
# The documentation / help obligation (P085 Step 6)
#
# A plan that changes behaviour a user meets must name the help file and the
# docs page it changes — a path in a Files bullet, like any other work. What
# the project HAS is read from project.yaml, recorded once by /aid-init or
# /aid-setup, so the obligation activates only where there is somewhere to
# write.
# ---------------------------------------------------------------------------
_doc_setup() {   # <project.yaml documentation block, or "">
  DOCDIR="$(mktemp -d)"
  mkdir -p "$DOCDIR/.aid-o/plans" "$DOCDIR/.aid-o/config"
  { printf 'project_name: "fixture"\n'; [[ -n "${1:-}" ]] && printf '%s\n' "$1"; } \
    > "$DOCDIR/.aid-o/config/project.yaml"
  DOCPLAN="$DOCDIR/.aid-o/plans/P903-fixture.md"
}

_doc_plan() {   # <type> <files-bullets…>
  local ptype="$1"; shift
  { printf -- '---\nid: P903\ntype: %s\nrisk: high\nlifecycle_strict: true\n---\n' "$ptype"
    printf '# Plan: P903\n\n## Testing Strategy\n\nNo new verification — this fixture is about the documentation obligation.\n\n**EPIC 1: Steps 1-1**\n\n### Step 1: work\n\n**Objective:** implement the thing properly for this step.\n\n**Files:**\n'
    printf -- '- %s\n' "$@"
    printf '\n**Architecture Context:**\nn/a\n\n**Error Handling:**\nn/a\n\n**Edge Cases:**\n- none\n'
  } > "$DOCPLAN"
}

@test "P085: a behaviour-changing plan with no path into help or docs is refused" {
  _doc_setup 'documentation:
  in_app_help: src/help
  docusaurus: docs/docs'
  _doc_plan regular 'Modify: `src/feature.ts` — new behaviour'
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "$DOCPLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"changes behaviour a user meets"* ]]
  rm -rf "$DOCDIR"
}

@test "P085: naming EVERY surface satisfies it" {
  _doc_setup 'documentation:
  in_app_help: src/help
  docusaurus: docs/docs'
  _doc_plan regular 'Modify: `src/feature.ts` — new behaviour' \
    'Modify: `src/help/features.md` — the section describing it' \
    'Modify: `docs/docs/features.md` — the page describing it'
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "$DOCPLAN"
  [ "$status" -eq 0 ]
  rm -rf "$DOCDIR"
}

@test "P085: naming only ONE of two surfaces is not enough" {
  # Half the users are left on the old behaviour, and the finding names which
  # half (codex review of EPIC 2, finding 1).
  _doc_setup 'documentation:
  in_app_help: src/help
  docusaurus: docs/docs'
  _doc_plan regular 'Modify: `src/feature.ts` — new behaviour' \
    'Modify: `src/help/features.md` — the section describing it'
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "$DOCPLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"docs/docs"* ]]
  [[ "$output" != *"'src/help'"* ]]
  rm -rf "$DOCDIR"
}

@test "P085: a project with only one surface owes only that half" {
  _doc_setup 'documentation:
  docusaurus: docs/docs'
  _doc_plan regular 'Modify: `src/feature.ts` — new behaviour' \
    'Modify: `docs/docs/features.md` — the page'
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "$DOCPLAN"
  [ "$status" -eq 0 ]
  rm -rf "$DOCDIR"
}

@test "P085: a refactor is exempt by definition" {
  _doc_setup 'documentation:
  in_app_help: src/help'
  _doc_plan refactor 'Modify: `src/feature.ts` — same behaviour, different shape'
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "$DOCPLAN"
  [ "$status" -eq 0 ]
  rm -rf "$DOCDIR"
}

@test "P085: a project with no help and no docs owes nothing, and the lint records it" {
  _doc_setup ''
  _doc_plan regular 'Modify: `src/feature.ts` — new behaviour'
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "$DOCPLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"records no in-app help and no documentation site"* ]]
  rm -rf "$DOCDIR"
}

@test "P085: a light-band plan is not asked" {
  _doc_setup 'documentation:
  in_app_help: src/help'
  { printf -- '---\nid: P903\ntype: regular\nrisk: low\nlifecycle_strict: true\n---\n'
    printf '# Plan: P903\n\n## Testing Strategy\n\nnone\n\n**EPIC 1: Steps 1-1**\n\n### Step 1: work\n\n**Objective:** implement the thing properly.\n\n**Files:**\n- Modify: `src/feature.ts` — new behaviour\n'
  } > "$DOCPLAN"
  run bash "$PLUGIN_ROOT/scripts/aid-plan-lint.sh" "$DOCPLAN"
  [ "$status" -eq 0 ]
  [[ "$output" != *"changes behaviour a user meets"* ]]
  rm -rf "$DOCDIR"
}
