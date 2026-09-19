_generated_by: aid-orchestrator:verifier@s02-acta-E-024-1_4-step1
_generated_at: 2026-09-19T00:00:00Z
classification: FULL_REVIEW
verdict: pass
findings: []

## Verification notes

Repository: /opt/eco/projects/acta @ 2ba535a1efde61e043bd38fff602f30a2e9dee5b (read via `git show`, no checkout/modification).

### AC1 — 2000 unseeded counterparties, `limit=1600` → at most 800 new
`select_candidates` (backend/acta/registry/scheduler.py) now computes
`window_limit = max(adis_limit, 0)`, `seed_limit = int(window_limit * settings.REGISTRY_SEED_WINDOW_SHARE)`,
`rotation_limit = window_limit - seed_limit`, and dispatches seeding and rotation
against their own limits before combining (`dedup_candidates(seeds + rotation)`).
With `adis_limit=1600` and default `REGISTRY_SEED_WINDOW_SHARE=0.5`: `seed_limit=800`,
`rotation_limit=800`. Confirmed against
`test_seed_backfill_cannot_push_rotation_out_of_the_window` (backend/tests/registry/test_scheduler.py:525-559),
which asserts `len(seeds) == 800`, `len(rotation) == 800`, `len(candidates) == 1600`. Matches AC1.

### AC2 — `REGISTRY_SEED_WINDOW_SHARE=0` → only rotation candidates
`seed_limit = int(window_limit * 0) == 0`, so `_unseeded_or_empty(session, limit=0)` returns no seeds
regardless of how many unseeded counterparties exist; rotation gets the full window.
Confirmed by `test_seed_share_zero_turns_seeding_off` (test_scheduler.py:562-577), which
monkeypatches the share to `0.0` and asserts the result contains only the pre-existing
rotation candidate, none of the unseeded supplier.

### AC3 — `count_pending` with 212 counterparties (1 already snapshotted) → 212, not 1 or 213
`count_pending` (scheduler.py:597-641, unchanged logic from Step 1, docstring extended this step)
sums `known` (rows in `vat_registry_status` for CZ with ico/vat set) plus `len(unseeded)`
from `_unseeded_or_empty(session, limit=None)`, where unseeded is identity-deduplicated against
the known population. Confirmed by `test_count_pending_counts_the_union_not_either_side`
(test_scheduler.py:580-603): 212 suppliers, one of which shares an identity with an existing
`VatRegistryStatus` row → `known=1`, `unseeded=211`, `pending=212`. Matches AC3 (rules out both
the pre-Step-1 regression of `1` and the double-count regression of `213`).

### AC4 — `REGISTRY_SEED_WINDOW_SHARE=1.5` fails app startup with a named error
`backend/acta/config.py` adds a `field_validator` on `REGISTRY_SEED_WINDOW_SHARE` that raises
`ValueError(f"REGISTRY_SEED_WINDOW_SHARE musí být mezi 0 a 1, dostal jsem {value}")` for any
value outside `[0, 1]`. Pydantic wraps this into `pydantic.ValidationError` at `Settings(...)`
construction time (app startup), which is a named, non-silent failure. Confirmed by
`test_invalid_seed_window_share_stops_the_app_at_startup` (test_scheduler.py:647-671), which
also checks the boundary values `0` and `1` remain valid.

### Scope / forbidden paths
Diff touches only `backend/acta/config.py`, `backend/acta/registry/scheduler.py`, and
`backend/tests/registry/test_scheduler.py` — all listed in step_outputs. No trace of
Prometheus `Counter(`, UI-level "registry didn't answer" vs "subject not found" distinction,
`REGISTRY_STALE_AFTER_DAYS` change, ISIR_WS event detail, blocking-behavior changes, or VAT-regime
classification changes (P016 Step 14) anywhere in the diff. Forbidden paths respected.

### Secondary observations (not findings — consistent with stated design, no AC violated)
- `select_unseeded_candidates` was also reworked in this diff to resolve country before full
  identity normalization (avoids misclassifying unsupported-country rows as `malformed`), to dedup
  per identity axis instead of per `(country, ico, vat)` triple, and to sort candidates
  deterministically before quota slicing. These are documented as carry-forward CP2 findings
  (F1/F3/F4) in the same file/step and are covered by their own new tests
  (`test_seed_dedups_per_axis_not_per_identity_triple`,
  `test_unsupported_country_is_not_reported_as_malformed_identity`). They do not touch any
  forbidden path or contradict the DoD.
- `process_candidates`'s `limit` parameter is now documented as a "last resort" cap rather than
  the primary split mechanism; the actual per-source split happens in `select_candidates`. This
  matches the step_outputs description and does not change `process_candidates`'s external
  behavior for callers that already respect the limit.

No discrepancies against the DoD or scope were found.
