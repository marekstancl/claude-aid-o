_generated_by: aid-orchestrator:verifier@s16-aid-orchestrator-E-065-2_7-step0
_generated_at: 2026-09-19T00:00:00Z
classification: FULL_REVIEW
verdict: pass
findings:
  - severity: low
    file: plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh:85
    finding: >
      `CODEX_MODEL` defaults to `gpt-5.6-terra`, but the grounding source cited
      by this step's own comments (scripts/tests/e2e/evidence/codex-stream-sample/fields.md
      §"Model floor", 2026-07-14) only confirms `gpt-5.5` as working on the
      current build/account and does not mention `gpt-5.6-terra` at all (it
      does document `gpt-5.6-sol` as REJECTED). The code comment at line 68-69
      ("Default is the session-confirmed working model") is not substantiated
      by any evidence file inside this diff or its cited grounding doc.
    recommendation: >
      Either cite the evidence that confirmed `gpt-5.6-terra` works against a
      real Codex CLI invocation, or fall back to the value fields.md actually
      grounds (`gpt-5.5`) until such evidence exists. Not blocking here because
      the value is only exercised through mocked `codex` in this step's tests,
      but a live `dispatch` run before that confirmation could fail every
      invocation with "Model metadata not found". (Note: repo history shows
      later P065 steps, e.g. commit 866f83ce "committed real-AC dogfood proof",
      continue to use `gpt-5.6-terra`, consistent with it having been validated
      in a later step not visible in this diff — this is why the finding is
      low, not blocking.)

--- Notes supporting the pass verdict ---

AC1 (high profile → `detect --required cross_provider`, never `cross_model`):
  Satisfied. `cmd_dispatch` (aid-c3-dispatch.sh:597-602) calls
  `"$INDEPENDENCE_BIN" detect --required cross_provider` unconditionally,
  ignoring `required_level` read from the manifest. Test
  `step5/AC1` (test-aid-c3-dispatch.bats:539-560) seeds a `high` profile whose
  manifest `required_independence_level` is `cross_model`, then asserts via a
  spy log that only `cross_provider` was probed and `cross_model` never
  appears, and that the recorded `probed_independence_level` is
  `cross_provider` while `required_independence_level` is carried through
  verbatim as `cross_model`.

AC2 (fixture `valid` → `codex --cd <repo> --sandbox read-only`):
  Satisfied. `_run_codex_isolated` (aid-c3-dispatch.sh:471-485) invokes
  `codex exec --json --cd "$project_root" --sandbox read-only -m "$CODEX_MODEL"
  -c model_reasoning_effort=high --output-last-message "$last_out" "$prompt"`
  under `timeout`, stdin redirected from `/dev/null`. Test `step5/AC2`
  (test-aid-c3-dispatch.bats:564-601) asserts, via a logging `codex` spy
  prepended to PATH, the exact `ARG:exec`, `ARG:--cd`, `ARG:<repo root>`,
  `ARG:--sandbox`, `ARG:read-only` sequence, the deliberate absence of
  `--output-schema` (documented rationale: the response schema's `if/then`
  gets rejected with HTTP 400 by Codex's structured-output backend, per the
  Step-1 grounding doc §"--output-schema empirical behavior"), and validates
  the resulting `c3-dispatch.json` (`codex_session_id` UUID shape,
  `events_valid:true`, `outcome:dispatched`, `achieved_independence_level:
  cross_provider`, `raw_response_sha256`/`stdout_sha256` matching the actual
  captured files' sha256).

AC3 (non-sticky — two consecutive `rate_limited` runs both invoke codex):
  Satisfied. `cmd_dispatch` performs no read of any cross-run cache/state
  before probing or invoking; `_write_dispatch_json` writes only under
  `<evidence_dir>/c3/`, never anything resembling an availability cache. Test
  `step5/AC3` (test-aid-c3-dispatch.bats:620-644) runs `dispatch` twice with
  `FAKE_CODEX_MODE=rate_limited`, asserts both exits are 2 with
  `outcome:rate_limited` and `invoked:true`, that the codex spy log shows
  `ARG:exec` exactly twice and the independence spy log shows the
  `cross_provider` probe exactly twice, and that no file matching
  `*availab*`/`*cache*` exists anywhere under the evidence dir afterward.

Scope discipline:
  `git diff c17b7e9f..317657b5 --stat` touches only
  `plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh` and
  `plugins/aid-orchestrator/scripts/tests/bats/test-aid-c3-dispatch.bats`,
  matching step_outputs exactly. No changes to
  `plugins/aid-orchestrator/scripts/lib/aid-audit-independence.sh` (confirmed
  via `git diff` on that path — empty) — its D7 absolute-bans section
  (line 40 at this commit) is untouched. No advisory-fallback invocation was
  added to any bash bridge (the bridge only ever signals unavailability via
  exit 2, per the code's own Step-8 comment); no filesystem read-jail/OS
  sandbox was introduced (independence remains provider + fresh process +
  `--sandbox read-only`, as documented in the code comment above
  `_run_codex_isolated`); `legacy_health` A–J audit and multi-provider fan-out
  are not referenced or touched anywhere in the diff.

Dependency/consistency check (read-only, at commit 317657b5):
  - `plugins/aid-orchestrator/scripts/lib/aid-render-prompt.sh` exists.
  - `plugins/aid-orchestrator/defaults/prompts/c3-audit-prompt-v1.md` exists.
  - `plugins/aid-orchestrator/defaults/schemas/c3-codex-response.schema.json` exists.
  - `aid-audit-independence.sh detect --required <level>` subcommand exists
    and matches the call signature used by `cmd_dispatch`.
  - `scripts/tests/fixtures/fake-codex/codex` (pre-existing fixture, not part
    of this diff) implements all `FAKE_CODEX_MODE` values exercised by the new
    tests (`valid`, `rate_limited`, `timeout`, `no_stream`, `invalid_json`),
    consistent with the grounding doc's documented stream/error shapes.
  - The updated skeleton test (`test-aid-c3-dispatch.bats:454-465`) correctly
    reflects that `dispatch` with no `<evidence_dir>` is now a usage/
    precondition error (exit 1, "PRECONDITION FAIL"), not the old "not yet
    implemented" stub (exit 2) — matching `cmd_dispatch`'s own arg-count guard
    at aid-c3-dispatch.sh:585-589.

No other correctness issues found in `_events_valid_of`, `_session_id_of`,
`_looks_rate_limited`, `_write_dispatch_json`'s null-handling helpers, or the
outcome/achieved-level state machine (dispatched/timeout/rate_limited/failed →
cross_provider/unavailable) against the DoD and the cited grounding
(fields.md §events_valid, §Error path, §Session id).
