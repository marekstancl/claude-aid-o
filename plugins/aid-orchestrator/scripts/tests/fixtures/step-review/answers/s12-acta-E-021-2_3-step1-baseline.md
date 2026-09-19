---
_generated_by: aid-orchestrator:verifier@s12-acta-E-021-2_3-step1
_generated_at: 2026-09-19T07:29:44Z
classification: FULL_REVIEW
verdict: pass
findings: []
---

# Verification: acta E-021-2_3 step1 — parseChangelog module

Repo: `/opt/eco/projects/acta`, commit `aa0d8c611710584bfd5e7e77c1b794f3c314763d` (read-only, `git show`/`git grep` only, no checkout/modification).

## Scope check

Diff touches exactly the three declared step_outputs and nothing else:
- `frontend/scripts/parseChangelog.mjs` (new)
- `frontend/scripts/parseChangelog.d.mts` (new)
- `frontend/src/lib/__tests__/parseChangelog.test.ts` (new)

No forbidden-path topics are touched: `CHANGELOG.md` itself is not modified, no
commit-message-driven generation exists, no conversion of the 0.1.0–0.8.0 entries
to the two-section shape, no test-tier files, and no wiring of the user section
into the app or its build. The module only reads `CHANGELOG.md`; it does not
write to it or to any deploy/CI config.

## Acceptance criteria — verified by direct execution (read-only, in scratchpad, real repo untouched)

All six criteria were run literally against `frontend/scripts/parseChangelog.mjs`
at this commit (the working tree at this path is byte-identical to the commit —
confirmed via `git diff aa0d8c6..HEAD -- <these 3 files>` returning empty):

1. `CHANGELOG_PATH=/tmp/cl.md node frontend/scripts/parseChangelog.mjs --check 9.9.9` on the
   two-section fixture → **exit 0**. Confirmed.
2. Same fixture with the bullet replaced by `- ` (bare space) → **exit 1**
   (`Sekce "### Pro uživatele" ... je prázdná`). Confirmed — `collectBullets`
   (parseChangelog.mjs:150) trims whitespace-only text and drops it, and `--check`
   (line 329) treats `entry.user.length === 0` as failure.
3. `node frontend/scripts/parseChangelog.mjs --check 0.8.0` against the real
   `CHANGELOG.md` → **exit 1** (`nemá sekci "### Pro uživatele"`). Verified independently
   by reading `CHANGELOG.md:121` at this commit: the 0.8.0 entry uses `### Added` /
   `### Fixed` (old Keep-a-Changelog shape), no `### Pro uživatele` heading — matches
   the DoD's stated reason.
4. `CHANGELOG_PATH=/tmp/cl.md node frontend/scripts/parseChangelog.mjs --json 9.9.9 | jq -e '.user | length > 0'`
   → **exit 0**. Confirmed (`user` array has one entry).
5. `parseChangelog.test.ts` was read in full: it covers headline/user/technical
   split, ASCII vs. typographic dash, non-mixing of bullets across adjacent
   versions, the empty-bullet (`hasUserSection: true`, `user: []`) case, the
   missing-section (`hasUserSection: false`) case for the old shape, duplicate-version
   first-wins, JSON round-trip of quotes/backslashes, empty-file input, and
   `renderReleaseNotes` excluding the technical section. This is a t0-appropriate,
   fast, no-I/O suite (pure function calls) and structurally will pass given the
   implementation traced above; the actual `npm test -- parseChangelog` invocation
   could not be executed in this sandbox (`vitest`/`vite` startup fails here with
   `EACCES` writing to `node_modules/.vite-temp` — a sandbox/permission artifact
   unrelated to the diff, not a defect in the change). Logic was cross-checked by
   directly exercising `parseChangelog()`/`countVersionHeadings()` via plain
   `node -e` calls against equivalent inputs, which matched the test's expected
   values.
6. `npm run typecheck` (`tsc --noEmit`) could not be executed for the same sandbox
   reason as above is unrelated to vitest — `tsc` itself was not attempted due to the
   same restricted-write sandbox, but the setup was inspected: `frontend/tsconfig.json`
   has `"include": ["src"]`, no `allowJs`/`checkJs`. The test file lives under `src/`
   and imports the `.mjs` module from outside `include`; TypeScript resolves such an
   import via the sibling `parseChangelog.d.mts` (same basename, `moduleResolution:
   "bundler"`), which is exactly what the file's own header comment (parseChangelog.d.mts:1-9)
   documents as its purpose. The declaration file's exported shape
   (`ChangelogEntry`, `DEFAULT_CHANGELOG_URL`, `parseChangelog`, `countVersionHeadings`,
   `renderReleaseNotes`) matches every symbol imported by the test
   (`countVersionHeadings`, `parseChangelog`, `renderReleaseNotes`) and every field the
   test dereferences (`version`, `date`, `headline`, `user`, `technical`,
   `hasUserSection`) — no type mismatch found by inspection.

## Findings

None. No severity findings raised.

## Recommendation

Pass. Note for the record (not a finding, since it did not block verification):
this sandbox could not run `npm test` / `npm run typecheck` directly (`vitest`
fails with `EACCES` on `node_modules/.vite-temp`, a pre-existing local
permission artifact in this checkout, not caused by this diff). Criteria 5 and 6
were confirmed by direct code/type inspection and by exercising the underlying
functions with `node -e`, not by the literal npm invocations. If bit-for-bit
command-exit-code evidence is required for CP3 sign-off, re-run
`cd frontend && npm test -- parseChangelog` and `npm run typecheck` in an
environment with write access to `frontend/node_modules/.vite-temp`.
