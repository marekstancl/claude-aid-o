_generated_by: aid-orchestrator:verifier@s13-acta-E-024-4_4-step0
_generated_at: 2026-09-19T09:31:00Z
classification: FULL_REVIEW
verdict: pass
findings: []

## Verification detail

Repository: /opt/eco/projects/acta @ 94a5a9b604c2c226dcee480b98967616fba063e3 (read-only; verified via `git archive` into a scratch dir, no checkout/mutation of the repo).

### Acceptance criteria checked

1. **`npm test -- content-coverage` prochází.**
   Ran against the archived commit content: `Test Files 1 passed (1)`, `Tests 13 passed (13)`. PASS.
   Also ran `npm test -- helpSections` for the sibling test touched in the diff: `Test Files 1 passed (1)`, `Tests 11 passed (11)`. PASS.

2. **`helpSections.ts` obsahuje kotvy `kdy-se-kontroluje` a `kontrola-uctu`, `ProtistranyPage.tsx` má pro obě `id=`.**
   `frontend/src/config/helpSections.ts:142-143` adds both anchor entries under the `protistrany` page's `sections` array.
   `frontend/src/pages/help/ProtistranyPage.tsx:189` (`id="kontrola-uctu"`) and `:247` (`id="kdy-se-kontroluje"`) define matching `<HelpSection id=...>` blocks. PASS.
   (Bonus: `frontend/e2e/help-structure.spec.ts` was not modified but is registry-driven — it iterates `HELP_SECTIONS` generically, so the new anchors are covered by the existing spec without edits, satisfying the "Test" line in step_outputs.)

3. **Stránka protistran má `lastReviewedPlan: 'P024'`.**
   `frontend/src/config/helpSections.ts:117` sets `lastReviewedPlan: 'P024'` (with `lastReviewedAt: '2026-09-02'`) on the `protistrany` entry, overriding the shared `...REVIEW` spread. The companion `helpSections.test.ts` was updated to allow per-page divergence while still enforcing internal consistency (same plan → same date). PASS.

4. **Text vysvětluje periodu obnovy, ruční vynucení i význam varování o účtu.**
   - Renewal period: `ProtistranyPage.tsx` "Kdy se registry kontrolují" section explains nightly refresh times (~03:00 for DPH/insolvency/VIES, ~04:00 for ARES), rate-limited catch-up over several nights, and near-real-time onboarding for new counterparties (lines ~247-266).
   - Manual force: same section's "Když nechcete čekat do rána" HelpCard describes the per-row "Ověřit registrní stav teď" button, including its disabled/hidden conditions (lines ~268-279). The permission matrix (`kdo-vidi-co`) also gets a new row for who can trigger it.
   - Account-warning meaning: "Účet na faktuře a §109" section explains matched vs. not-published states, ties severity (red vs. grey badge) to the statutory liability threshold without hardcoding the number, and explains the silent (no badge) case. PASS.

5. **Fráze „Insolvence nezjištěna" v textu zůstává.**
   Confirmed present verbatim at `ProtistranyPage.tsx:203` (`git grep` at the target commit). PASS.

### Scope / forbidden-paths check

Diff touches only: `frontend/src/config/__tests__/helpSections.test.ts`, `frontend/src/config/helpSections.ts`, `frontend/src/pages/help/ProtistranyPage.tsx`, `frontend/src/pages/help/__tests__/content-coverage.test.ts` — matches step_outputs scope exactly (the e2e spec file needed no change, as noted above).

No forbidden-path violations found:
- No Prometheus/`Counter(` instrumentation touched.
- No "registr neodpověděl" vs. "subjekt tam není" UI distinction introduced (text stays deliberately vague, matching the forbidden-scope note).
- `REGISTRY_STALE_AFTER_DAYS` / snapshot semantics untouched.
- No full `ISIR_WS` eventový detail added — only the existing badge is referenced/demoed with hand-built fixture objects.
- No blocking behavior added — badges and warnings stay advisory (explicitly worded as "poradní" analog: informational/advisory framing throughout).
- DPH-regime classification (P016 Step 14) untouched.
- New `content-coverage.test.ts` assertions explicitly guard against the §109 threshold amount leaking into help text (`540 000` / `270 000` patterns), consistent with "no config-value changes" constraint.

### Type safety

`npx tsc --noEmit` on the archived commit produced no errors referencing `ProtistranyPage.tsx` or `helpSections.ts` (the new `RegistryBadgeData` fixture objects and `published_account_match` fields type-check against the existing component contract).

### Conclusion

All acceptance criteria are met, tests pass, and no forbidden paths were touched. Verdict: **pass**, 0 findings.
