# Case C — Recovery Path

**Fail reason:** `delta_unauthorized_change` on `font-size` (changed from 16px to 18px without declaring it in delta.typed)

**Fix:** Remove the unauthorized font-size change. Only apply the declared color change.

**Verification:** Run ui-compare.mjs with `--after-computed fixed-computed.json` -> expected-fixed-verdict.json (verdict: pass)
