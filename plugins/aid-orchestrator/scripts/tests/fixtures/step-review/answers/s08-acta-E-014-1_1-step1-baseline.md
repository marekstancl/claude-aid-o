_generated_by: aid-orchestrator:verifier@s08-acta-E-014-1_1-step1
_generated_at: 2026-09-19T00:00:00Z
classification: FULL_REVIEW
verdict: pass
findings: []

## Scope check

- Diff touches only `backend/acta/convert/adapter.py` and
  `backend/tests/convert/test_adapter.py` — both listed in `step_outputs`.
- No forbidden paths touched: no changes to `build_isdoc`/`_emit_party`/ISDOC
  shape, no DB persistence added, no other FlexiBee agendas touched, no
  weakening of the existing dobropis (negative-amount) skip rule, and the
  bank-account-of-supplier feature is not implemented — `bank_account` for
  přijaté invoices is simply hardcoded to `None`, not parsed/derived.

## DoD / acceptance-criteria walkthrough (read against commit
`6c9314190588758be4f59ca7dd1c3aea284becfc`)

- **Role flip for přijaté**: `to_isdoc_document` (adapter.py L127-166) sets
  `fields["supplier_name"] = inv.nazev_firmy`, `supplier_ico/dic = inv.ic/dic`
  and `customer_* = supplier.*` when `inv.typ == "prijata"`. Verified against
  `test_prijata_role_flip` (test_adapter.py L367-385).
- **`f_invoice_number` for přijaté**: `inv.cis_dosle or inv.kod` (adapter.py
  L223). Verified by `test_prijata_invoice_number_prefers_cis_dosle` and
  `test_prijata_invoice_number_falls_back_to_kod` (L388-397).
- **RC přijatá (celkem==základ, dph>0) not skipped, line keeps rate**:
  `is_reverse_charge` (L42-58) requires `typ=="prijata"` and
  `dph_celkem>0` and `celkem≈zakl_celkem+osv`; `should_skip`'s consistency
  check is skipped when `is_reverse_charge(inv)` is true (L157-161); line
  emission keeps `vat_rate=szb`, sets `amount_vat=0`, `amount_total=zakl`
  (L204-217, "reverse_charge" branch). Verified by
  `test_reverse_charge_not_skipped` and `test_reverse_charge_line_mapping`
  (L406-419).
- **VYDANÁ with same signature (celkem==základ, dph>0) still skipped**:
  `is_reverse_charge` returns `False` for `typ!="prijata"` (L48-49), so the
  consistency check in `should_skip` still fires. Verified by
  `test_reverse_charge_detected_only_for_prijata` and
  `test_vydana_same_signature_still_skipped` (L400-403, L439-442).
- **RC přijatá with osv≠0: osv line kept, total sums to celkem**: the osv
  bucket is emitted identically in both RC and non-RC paths (L303-317,
  comment explicitly calls this out); confirmed with the concrete numeric
  example in `test_reverse_charge_with_osv_keeps_osv_line` (celkem=1300 =
  1000 base + 300 osv), which asserts `len(lines)==2` and
  `sum(amount_total) == inv.celkem` (L422-436).
- **Non-RC inconsistent přijatá still skipped**: `test_non_rc_inconsistent_prijata_still_skipped`
  (L445-449) uses a přijatá invoice with `celkem=5000` (not matching the RC
  signature), confirms `is_reverse_charge` is False and `should_skip` still
  returns the consistency-mismatch reason.
- **`typ_dokl=="ZÁLOHA"` → skip, reason contains "zálohová"**: `should_skip`
  L137-138 returns `"zálohová faktura — není daňový doklad"`, checked before
  currency/kod checks, for both directions. Verified by
  `test_skip_zaloha_vydana`/`test_skip_zaloha_prijata` (L452-461).
- **uuid5 přijatá ≠ vydaná for same `(client_id, kod)`; vydaná seed
  unchanged**: přijatá uses prefix `flexibee-prijata:{client_id}:{kod|cis_dosle}`
  (L206-209) vs. vydaná's unchanged `flexibee:{client_id}:{kod}` (L226).
  Verified by `test_uuid5_prijata_differs_from_vydana` and the regression
  test `test_uuid5_vydana_seed_unchanged` which pins the exact literal seed
  string (L475-489). Also `test_uuid5_prijata_without_kod_distinct_by_cis_dosle`
  covers the C0-R3-F1 collision concern for two přijaté without `kod`.
- **Missing invoice number for přijaté**: `should_skip` requires
  `cis_dosle or kod` for přijaté (L142-144), vs. `kod` only for vydaná
  (L145-146). Verified by `test_prijata_missing_both_numbers_skipped` and
  `test_prijata_cis_dosle_only_not_skipped` (L464-472).

All acceptance criteria in the DoD are backed by a corresponding test that
actually exercises the described behavior (not just a smoke assertion), and
the implementation code matches the described logic on manual trace-through.
No regressions found in the surrounding skip-rule ordering (storno → záloha →
currency → invoice number → date → negative → zero-base → DPH consistency →
amount consistency, in that order, matches the updated docstring).

## Notes (not findings, informational)

- Static review only; the sandbox denied running `pytest` from this session
  (Bash permission for a `git clone`/test-run was refused), so test execution
  itself was not observed — verdict is based on manual code/test trace-through
  against the stated DoD and cross-checking test bodies against the
  implementation line-by-line.
