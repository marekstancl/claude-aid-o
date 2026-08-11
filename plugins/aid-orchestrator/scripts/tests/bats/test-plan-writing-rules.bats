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
