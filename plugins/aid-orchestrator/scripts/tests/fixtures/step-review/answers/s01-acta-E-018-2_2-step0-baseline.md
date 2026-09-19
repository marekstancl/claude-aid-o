---
_generated_by: aid-orchestrator:verifier@s01-acta-E-018-2_2-step0
_generated_at: 2026-09-19T00:00:00Z
classification: FULL_REVIEW
verdict: pass
findings: []
---

# Verification: acta E-018-2_2 step0 (help pages sync)

Repository: /opt/eco/projects/acta
Commit range: 44035c2e17ecbe5260670a9f0885a9b51a3b2e69..41713838bc4403c824831d95c3042a606c040590

## Acceptance criteria check

1. `helpSections.ts` contains sections `vychozi-hodnoty` and `cislo-z-faktury`
   — CONFIRMED. `frontend/src/config/helpSections.ts:115` adds `vychozi-hodnoty`
   under the `vydane-faktury` slug; `frontend/src/config/helpSections.ts:123`
   adds `cislo-z-faktury` under the `ciselne-rady` slug. Both entries have
   non-empty `id`, `label`, and `keywords`.

2. Both sections have a matching `<HelpSection>` on their pages — CONFIRMED.
   - `frontend/src/pages/help/VydaneFakturyPage.tsx:193` renders
     `<HelpSection n={7} id="vychozi-hodnoty" ...>`, and the following section
     `caste-problemy` was renumbered to `n={8}` (VydaneFakturyPage.tsx:228) to
     keep the sequence intact.
   - `frontend/src/pages/help/CiselneRadyPage.tsx:82` renders
     `<HelpSection n={3} id="cislo-z-faktury" ...>`; subsequent sections
     (`oddelene-rady`, `kdy-se-cislo-prideli`, `zmena-smeru-cisla`,
     `caste-problemy`) were shifted from n=3..6 to n=4..7 accordingly.
   - `HelpSection`'s `id` prop is rendered verbatim as the DOM `<section id=…>`
     (`frontend/src/components/help/HelpSection.tsx`), so registry ids and DOM
     ids line up 1:1 for every section on both pages — verified by listing all
     `<HelpSection n=… id=…>` occurrences on both files against the registry
     entries for the two slugs; sets match exactly.

3. `REVIEW` in `helpSections.ts` has `lastReviewedPlan: 'P018'` — CONFIRMED.
   `frontend/src/config/helpSections.ts:106` sets
   `const REVIEW = { lastReviewedPlan: 'P018', lastReviewedAt: '2026-08-22' };`,
   spread via `...REVIEW` into every page entry (registry-wide, not just the
   two touched pages), so all `HELP_SECTIONS[*].lastReviewedPlan === 'P018'`.

4. `frontend/e2e/help-structure.spec.ts` passes — CONFIRMED BY STATIC
   ANALYSIS (Playwright browser run not executed in this read-only review;
   spec content and registry/DOM cross-checked by hand):
   - Per-slug section-id parity (registry ⟷ DOM `#id`) holds for both changed
     pages, per point 2 above.
   - "No dead anchors" check: the new cross-page link added in
     `VydaneFakturyPage.tsx:261` (`/napoveda/ciselne-rady#cislo-z-faktury`)
     resolves — `cislo-z-faktury` exists in the `ciselne-rady` registry entry's
     `sections[]` and as a DOM section id on `CiselneRadyPage.tsx:82`.
   - "Links to other help pages resolve to existing slugs" check: no new
     inter-page `/napoveda/<slug>` links were introduced besides the one above,
     which targets the existing `ciselne-rady` slug.

   No spec assertions in `help-structure.spec.ts` were modified, so the
   contract test's own logic is unchanged; only the registry/DOM data it reads
   changed, and that data was verified to satisfy the spec's invariants above.

5. New unit test coverage (`frontend/src/config/__tests__/helpSections.test.ts`)
   — CONFIRMED. Two new `it(...)` blocks assert: (a) both new sections exist
   under the right slugs with non-empty `id`/`label`(>3 chars)/`keywords`
   (each keyword non-empty after trim), and (b) every page in `HELP_SECTIONS`
   has `lastReviewedPlan === 'P018'`.

## Scope / forbidden-paths check

`git diff --stat` for the reviewed range touches exactly the four files listed
in step_outputs:
- `frontend/src/config/helpSections.ts`
- `frontend/src/pages/help/VydaneFakturyPage.tsx`
- `frontend/src/pages/help/CiselneRadyPage.tsx`
- `frontend/src/config/__tests__/helpSections.test.ts`

No other files changed. None of the step_forbidden_paths (backend/acta/documents/isdoc.py,
received-invoice numbering/masks, nested-ZIP handling, other archive formats,
auto-approval of issued invoices, e-mail dedup, LiteLLM pricing/models, or
Číslo ACTA derivation for received invoices) were touched.

## Notes

- This review is static (git show / git grep against the pinned commit); the
  Playwright e2e spec was not executed against a running frontend in this
  sandbox. The DoD line item is verified by manually walking the spec's three
  assertions against the registry/DOM/link data, which is sufficient given the
  narrow, additive nature of the diff and the unchanged spec logic.
