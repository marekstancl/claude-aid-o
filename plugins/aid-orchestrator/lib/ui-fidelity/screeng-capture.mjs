/**
 * screeng-capture.mjs — Real ScreenG capture for D-desktop / D-mobile calibration
 *
 * Captures 3 states in ONE Playwright session (to avoid pixel jitter between
 * separate launches):
 *   1. baseline.png + baseline-computed.json  — ScreenG with GOOD API mocks
 *   2. regressed.png + regressed-computed.json — ScreenG with BAD brief mock (500)
 *   3. rerun.png + rerun-computed.json         — ScreenG with GOOD API mocks again
 *
 * CLI usage:
 *   node screeng-capture.mjs \
 *     --port N \
 *     [--base-url http://host:port] \
 *     --viewport-width W \
 *     --viewport-height H \
 *     --selector SEL \
 *     --output-dir DIR
 *
 * If --base-url is provided it takes precedence over --port for constructing the URL.
 *
 * Exit codes: 0 success, 1 error
 */

import { chromium } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'fs';
import { resolve, join } from 'path';

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg.startsWith('--')) {
      const key = arg.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      args[key] = argv[i + 1] ?? true;
      i++;
    }
  }
  return args;
}

const args = parseArgs(process.argv.slice(2));

const required = ['viewportWidth', 'viewportHeight', 'selector', 'outputDir'];
// Either --port or --base-url must be provided
if (!args.port && !args.baseUrl) {
  required.push('port');
}
const missing = required.filter(k => !args[k]);
if (missing.length > 0) {
  const flags = missing.map(k => '--' + k.replace(/([A-Z])/g, '-$1').toLowerCase());
  process.stderr.write(`Missing required arguments: ${flags.join(', ')}\n`);
  process.exit(1);
}

const PORT = args.port ? parseInt(args.port, 10) : null;
const BASE_URL = args.baseUrl ? args.baseUrl.replace(/\/$/, '') : `http://localhost:${PORT}`;
const VIEWPORT_WIDTH = parseInt(args.viewportWidth, 10);
const VIEWPORT_HEIGHT = parseInt(args.viewportHeight, 10);
const SELECTOR = args.selector;
const OUTPUT_DIR = resolve(args.outputDir);

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

// Mock matching the real /api/brief response shape (scope + sinceLastSeen + blockers, etc.)
const GOOD_BRIEF = {
  ok: true,
  data: {
    scope: 'infra',
    projectId: null,
    planId: null,
    generatedAt: '2026-06-30T12:00:00Z',
    ecosystemLine: '1 projekt · 0 blokací',
    sinceLastSeen: {
      since: null,
      items: [],
      counts: { newRuns: 0, newGateFails: 0, newViolations: 0, newBacklog: 0, stateTransitions: 0 }
    },
    blockers: [],
    watchOuts: [],
    nextUp: [],
    decisionsNeeded: [],
    needsTriage: [],
    risk: { level: 'nizke', reasons: [], confidence: 'high' },
    successProbability: { value: null, source: null }
  }
};

// Mock matching the real /api/projects response shape
const GOOD_PROJECTS = {
  ok: true,
  data: [
    {
      id: 'aid-orchestrator',
      name: 'aid-orchestrator',
      path: '/opt/eco/projects/aid-orchestrator',
      aidoPath: '/opt/eco/projects/aid-orchestrator/.aid-o',
      discovered: true,
      partial: false,
      epicsTotal: 1,
      epicsActive: 1,
      runsTotal: 1,
      activeRun: null,
      health: { value: null, partial: false, confidence: 'high' },
      lastActivityAt: '2026-06-30T10:00:00Z'
    }
  ]
};

// Bad brief: triggers ScreenG error state
const BAD_BRIEF = {
  ok: false,
  error: {
    code: 'INTERNAL_ERROR',
    message: 'Calibration test: simulated brief failure'
  }
};

// ---------------------------------------------------------------------------
// Helper: extract computed styles from element
// ---------------------------------------------------------------------------

async function extractComputedStyles(page, selector) {
  return await page.evaluate((sel) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    const style = window.getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return {
      target_id: 'screeng-root',
      captured_at: new Date().toISOString(),
      url: window.location.href,
      selector: sel,
      viewport: { width: window.innerWidth, height: window.innerHeight },
      bbox: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
      computed_styles: {
        color: style.color,
        'background-color': style.backgroundColor,
        'font-size': style.fontSize,
        display: style.display,
        visibility: style.visibility,
        opacity: style.opacity
      },
      text_content: (el.textContent || '').trim().slice(0, 200)
    };
  }, selector);
}

// ---------------------------------------------------------------------------
// Main capture logic
//
// Capture sequence (3 states in ONE session — no pixel jitter):
//
//  1. REGRESSED — navigate fresh with BAD brief mock.
//     ScreenG has no cached data → briefQuery.isError && !brief → error banner
//     shown. Captures regressed.png + regressed-computed.json.
//
//  2. BASELINE — switch to GOOD mock, wait for React Query to recover.
//     brief data now available, BriefPanel renders normally.
//     Captures baseline.png + baseline-computed.json.
//
//  3. RERUN — keep GOOD mock, wait for another refetch cycle.
//     Should match baseline (confirms deterministic render).
//     Captures rerun.png + rerun-computed.json.
//
// Calibration compare:
//   first_run  → baseline vs regressed → expect FAIL (error banner differs)
//   rerun      → baseline vs rerun     → expect PASS (identical renders)
// ---------------------------------------------------------------------------

async function main() {
  mkdirSync(OUTPUT_DIR, { recursive: true });

  const browser = await chromium.launch({
    headless: true,
    args: ['--disable-gpu', '--no-sandbox', '--disable-dev-shm-usage']
  });

  try {
    const context = await browser.newContext({
      locale: 'en-US',
      timezoneId: 'UTC',
      colorScheme: 'light'
    });

    const page = await context.newPage();
    await page.setViewportSize({ width: VIEWPORT_WIDTH, height: VIEWPORT_HEIGHT });

    const pageUrl = `${BASE_URL}/`;

    // -------------------------------------------------------------------
    // State 1: REGRESSED — start fresh with BAD brief mock so error banner
    // appears immediately (no stale cache to keep good data visible).
    // -------------------------------------------------------------------

    // Projects always good so the tile section renders
    await page.route('**/api/projects', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(GOOD_PROJECTS)
      });
    });
    // Brief returns 500 → briefQuery.isError && !brief → error banner
    await page.route('**/api/brief', (route) => {
      route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify(BAD_BRIEF)
      });
    });

    await page.goto(pageUrl, { waitUntil: 'networkidle' });

    // Wait for section to be visible (it always is — even with no brief)
    await page.waitForSelector(SELECTOR, { state: 'visible', timeout: 15000 });

    // Wait for error banner to appear — max 6s (one refetch cycle)
    try {
      await page.waitForSelector('[data-brief-error]', { state: 'visible', timeout: 6000 });
      process.stdout.write('error banner detected\n');
    } catch {
      // Error banner may not appear if brief never succeeded — still capture
      process.stdout.write('error banner not detected (capturing anyway)\n');
    }

    await page.waitForTimeout(300);

    const regressedData = await extractComputedStyles(page, SELECTOR);
    if (!regressedData) {
      throw new Error(`Regressed: no element found for selector: ${SELECTOR}`);
    }
    await page.locator(SELECTOR).first().screenshot({ path: join(OUTPUT_DIR, 'regressed.png') });
    writeFileSync(join(OUTPUT_DIR, 'regressed-computed.json'), JSON.stringify(regressedData, null, 2), 'utf8');
    process.stdout.write('regressed captured\n');

    // -------------------------------------------------------------------
    // State 2: BASELINE — switch to GOOD mock, wait for UI to recover.
    // React Query will refetch on interval (4s) and brief will load.
    // -------------------------------------------------------------------
    await page.unroute('**/api/brief');
    await page.route('**/api/brief', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(GOOD_BRIEF)
      });
    });

    // Wait for error banner to disappear and BriefPanel content to appear
    try {
      await page.waitForFunction(
        () => {
          const errEl = document.querySelector('[data-brief-error]');
          if (errEl) return false;
          // BriefPanel renders content; check for any known element
          const body = document.body.innerText || '';
          return body.includes('Riziko') || body.includes('Rozhodnutí') || body.includes('Co se změnilo');
        },
        { timeout: 15000 }
      );
    } catch {
      process.stdout.write('BriefPanel recovery wait timed out, capturing anyway\n');
      await page.waitForTimeout(5000);
    }

    await page.waitForTimeout(300);

    const baselineData = await extractComputedStyles(page, SELECTOR);
    if (!baselineData) {
      throw new Error(`Baseline: no element found for selector: ${SELECTOR}`);
    }
    await page.locator(SELECTOR).first().screenshot({ path: join(OUTPUT_DIR, 'baseline.png') });
    writeFileSync(join(OUTPUT_DIR, 'baseline-computed.json'), JSON.stringify(baselineData, null, 2), 'utf8');
    process.stdout.write('baseline captured\n');

    // -------------------------------------------------------------------
    // State 3: RERUN — keep GOOD mock, wait for next refetch (another 4s).
    // Should render identically to baseline.
    // -------------------------------------------------------------------

    // Wait for one more refetch cycle
    await page.waitForTimeout(5000);
    await page.waitForTimeout(300);

    const rerunData = await extractComputedStyles(page, SELECTOR);
    if (!rerunData) {
      throw new Error(`Rerun: no element found for selector: ${SELECTOR}`);
    }
    await page.locator(SELECTOR).first().screenshot({ path: join(OUTPUT_DIR, 'rerun.png') });
    writeFileSync(join(OUTPUT_DIR, 'rerun-computed.json'), JSON.stringify(rerunData, null, 2), 'utf8');
    process.stdout.write('rerun captured\n');

    process.stdout.write(`All 3 states captured in: ${OUTPUT_DIR}\n`);
  } finally {
    await browser.close();
  }
}

main().then(() => process.exit(0)).catch((err) => {
  process.stderr.write(`screeng-capture failed: ${err.message}\n${err.stack || ''}\n`);
  process.exit(1);
});
