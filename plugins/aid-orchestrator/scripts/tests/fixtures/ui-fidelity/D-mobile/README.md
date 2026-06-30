# Fixture D-mobile — ScreenG mobile calibration

Real `ScreenG` component captured at viewport 375x812 via Playwright with `page.route` API mocks.

**Calibration strategy:**
- `baseline` — ScreenG with good API mocks (`/api/brief` returns mock brief, `/api/projects` returns mock project list)
- `regressed` — ScreenG with broken brief mock (`/api/brief` returns 500 error -> error banner appears)
- `rerun` — ScreenG with good API mocks again (matches baseline)

**Expected FAIL reason:** `pixel_match` detects visual difference (error banner vs BriefPanel content)
**Expected PASS:** `pixel_match` confirms matching renders after recovery

**Note:** `before.png`/`after.png` are placeholder references. Calibration captures fresh screenshots via `screeng-capture.mjs` at run time.
