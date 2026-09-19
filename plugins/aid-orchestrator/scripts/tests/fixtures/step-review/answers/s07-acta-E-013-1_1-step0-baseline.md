_generated_by: aid-orchestrator:verifier@s07-acta-E-013-1_1-step0
_generated_at: 2026-09-19T00:00:00Z
classification: FULL_REVIEW
verdict: pass
findings:
  - severity: low
    file: backend/acta/convert/flexibee.py:86-97
    finding: >
      `_strip_code` is defined and unit-tested directly
      (`test_strip_code_helper_on_ref_value` in
      backend/tests/convert/test_flexibee_parser.py:505-511) but is never
      called from `parse_flexibee`/`_parse_invoice`. The fixture even
      includes `<typDokl>code:FAKTURA</typDokl>` (test file line 371,
      comment on line 366) to exercise the `code:` prefix case, but
      `typDokl` is not read by `_parse_invoice` and no field of
      `FlexibeeInvoice` stores a `code:`-prefixed ref value. The stated
      Objective ("s ošetřeným code: prefixem") is therefore only
      demonstrated at the helper-unit level, not wired into the actual
      parser output — dead code from the parser's point of view in this
      step.
    recommendation: >
      Either wire `_strip_code` into a field that will actually carry a
      `code:`-prefixed value in this step (e.g. capture `typDokl` on
      `FlexibeeInvoice` and strip it), or, if that field is intentionally
      deferred to Step 2/3 (as the models.py docstring implies for
      `_ConvDoc`/`_ConvLine`), say so explicitly in flexibee.py's
      docstring so it reads as "prepared for a later step" rather than
      an unmet objective. Does not block this step since all four listed
      Acceptance Criteria pass; flag for Step 2 follow-up.
notes: >
  All four Acceptance Criteria verified directly against the diff:
  (1) count — `root.findall("faktura-vydana")` (flexibee.py:220) returns
  direct children only (comment explicitly forbids `.//`, avoiding
  over-matching nested ref `<kod>` elements), test asserts len==2
  (test_flexibee_parser.py:422-427).
  (2) mena from showAs — `_mena()` (flexibee.py:141-161) reads
  `mena_el.get("showAs")` before falling back to `.text`/nested
  `mena/mena/kod`; test_currency_read_from_showas_not_text and
  test_currency_fallback_to_inner_kod_when_no_showas both pass against
  the fixture.
  (3) root guard — `parse_flexibee` (flexibee.py:212-216) raises
  `FlexibeeFormatError` when `root.tag != "winstrom"` or
  `root.get("source") != "FlexiBee"`; also wraps `ET.ParseError` on
  malformed XML into the same exception type (flexibee.py:208-210);
  covered by test_wrong_root_raises and test_invalid_xml_raises.
  (4) empty `<dic>` → None / "790.08" → Decimal / "2026-01-09" → date —
  `_text()` returns `value or None` after strip (flexibee.py:100-106,
  correctly handles the empty-text case since `child.text` is `None`
  for `<dic></dic>`); `_dec()`/`_date()` parse via `Decimal()` /
  `date.fromisoformat()` with try/except fallback; covered by
  test_empty_dic_is_none and test_decimal_and_date_parsing.
  No forbidden path was touched: diff only adds the five in-scope files
  (backend/acta/convert/__init__.py, models.py, flexibee.py,
  backend/tests/convert/__init__.py, test_flexibee_parser.py). No
  `faktura-prijata`/dobropis/zálohová faktura root handling, no DB
  persistence, no other-ERP adapters, no line-item extraction, and no
  change to `build_isdoc`/`_emit_party`/ISDOC shape appear anywhere in
  the diff. `models.py` additionally defines `SupplierIdentity`,
  `_ConvDoc`, `_ConvLine`, `SkippedInvoice`, `ConvertResult` ahead of
  need — explicitly flagged in its own docstring as prep for Step 2/3,
  consistent with step_outputs allowing models.py to hold the module's
  full data model; not a forbidden-path violation since nothing outside
  the listed in-scope files was created or edited.
