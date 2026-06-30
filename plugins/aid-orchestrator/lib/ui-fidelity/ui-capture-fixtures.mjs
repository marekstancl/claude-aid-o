/**
 * ui-capture-fixtures.mjs — Determinism harness + hermetic test page
 *
 * Exports:
 *   applyDeterminismFixtures(page, context) — apply before any capture
 *   HERMETIC_TEST_PAGE_HTML                 — self-contained HTML for determinism tests
 *
 * CLI usage (determinism self-test):
 *   node ui-capture-fixtures.mjs --output-dir <path>
 *
 * The self-test captures the hermetic page twice, then compares:
 *   - JSON equality of baseline-computed.json (both runs)
 *   - Pixel diff < 1% of total pixels (color_threshold=0.1, noise_budget=0.01)
 *
 * Part of E-056 E7A foundation. Standalone — no pipeline/FSM wiring.
 */

import { chromium } from '@playwright/test';
import { mkdirSync, writeFileSync, readFileSync } from 'fs';
import { join, resolve } from 'path';
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';

// ---------------------------------------------------------------------------
// Hermetic test page — no external resources, fully self-contained
// ---------------------------------------------------------------------------

export const HERMETIC_TEST_PAGE_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=1280">
  <style>
    body { margin: 0; font-family: monospace; background: #fff; }
    .box { width: 200px; height: 100px; background: #0066cc; color: #fff; display: flex; align-items: center; justify-content: center; font-size: 16px; }
  </style>
</head>
<body>
  <div class="box" data-testid="hermetic-box">DETERMINISTIC</div>
</body>
</html>`;

// ---------------------------------------------------------------------------
// Determinism fixtures
// ---------------------------------------------------------------------------

/**
 * Apply determinism fixtures to a Playwright page + context.
 * Must be called BEFORE page.goto() or page.setContent().
 *
 * Fixtures applied:
 *   - Disable CSS animations/transitions via init script
 *   - Pin Date.now() to a fixed timestamp via init script
 *   - Set document.documentElement.lang = 'en' via init script
 *   - Fixed viewport 1280x720
 *   - Locale en-US, timezone UTC, color scheme light (set in context options)
 *   - GPU rasterization disabled (set in launch args)
 *
 * @param {import('@playwright/test').Page} page
 * @param {import('@playwright/test').BrowserContext} _context  (reserved for future per-context hooks)
 */
export async function applyDeterminismFixtures(page, _context) {
  await page.addInitScript(() => {
    // Disable CSS animations
    const style = document.createElement('style');
    style.textContent = `
      *, *::before, *::after {
        animation-duration: 0s !important;
        animation-delay: 0s !important;
        transition-duration: 0s !important;
        transition-delay: 0s !important;
      }
    `;
    // We can't append to head yet (DOM not ready), so listen for DOMContentLoaded
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', () => {
        document.head?.appendChild(style);
      });
    } else {
      document.head?.appendChild(style);
    }

    // Also override via CSS custom property route
    document.documentElement.style.setProperty('--duration', '0s');

    // Stub Animation prototype so JS-driven animations are also no-ops
    if (typeof Animation !== 'undefined') {
      const origPlay = Animation.prototype.play;
      Animation.prototype.play = function () {
        this.currentTime = this.effect?.getTiming?.()?.duration ?? 0;
        return origPlay.apply(this, arguments);
      };
    }

    // Pin Date.now() to a fixed timestamp for deterministic timestamps
    const FIXED = 1700000000000;
    const OrigDate = Date;
    class DeterministicDate extends OrigDate {
      constructor(...args) {
        if (args.length === 0) {
          super(FIXED);
        } else {
          super(...args);
        }
      }
      static now() { return FIXED; }
    }
    // Copy static methods
    Object.setPrototypeOf(DeterministicDate, OrigDate);
    globalThis.Date = DeterministicDate;

    // Set document language deterministically
    document.documentElement.lang = 'en';
  });
}

// ---------------------------------------------------------------------------
// Determinism self-test helpers
// ---------------------------------------------------------------------------

/**
 * Load a PNG file and return its raw pixel data.
 * @param {string} filePath
 * @returns {{ data: Buffer, width: number, height: number }}
 */
function loadPng(filePath) {
  const data = readFileSync(filePath);
  const png = PNG.sync.read(data);
  return { data: png.data, width: png.width, height: png.height };
}

/**
 * Compare two PNG files using pixelmatch.
 * Returns { diffPixels, totalPixels, diffRatio }
 */
function comparePngs(pathA, pathB) {
  const imgA = loadPng(pathA);
  const imgB = loadPng(pathB);

  if (imgA.width !== imgB.width || imgA.height !== imgB.height) {
    throw new Error(
      `Image size mismatch: ${imgA.width}x${imgA.height} vs ${imgB.width}x${imgB.height}`
    );
  }

  const { width, height } = imgA;
  const diff = Buffer.alloc(width * height * 4);

  const diffPixels = pixelmatch(imgA.data, imgB.data, diff, width, height, {
    threshold: 0.1,   // color_threshold per D7 constraint
    includeAA: false, // ignore anti-aliasing differences
  });

  const totalPixels = width * height;
  return { diffPixels, totalPixels, diffRatio: diffPixels / totalPixels };
}

/**
 * Run a single capture of the hermetic test page, writing outputs to a subdirectory.
 * Returns { jsonPath, pngPath }
 */
async function captureHermeticPage(browser, runDir) {
  mkdirSync(runDir, { recursive: true });

  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 },
    locale: 'en-US',
    timezoneId: 'UTC',
    colorScheme: 'light',
  });

  const page = await context.newPage();
  await applyDeterminismFixtures(page, context);
  await page.setContent(HERMETIC_TEST_PAGE_HTML, { waitUntil: 'load' });

  const selector = '[data-testid="hermetic-box"]';
  await page.waitForSelector(selector, { state: 'visible', timeout: 5000 });

  // Extract element data
  const elementData = await page.evaluate(({ sel }) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    const cs = window.getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    const attributes = {};
    for (const attr of el.attributes) {
      attributes[attr.name] = attr.value;
    }
    return {
      target_id: 'hermetic-box',
      captured_at: new Date().toISOString(),
      url: 'hermetic://test',
      selector: sel,
      bbox: {
        x: Math.round(rect.x),
        y: Math.round(rect.y),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
      },
      computed_styles: {
        color: cs.color,
        'background-color': cs.backgroundColor,
        'font-size': cs.fontSize,
        display: cs.display,
        visibility: cs.visibility,
        opacity: cs.opacity,
      },
      text_content: el.textContent?.trim() ?? '',
      attributes,
    };
  }, { sel: selector });

  if (!elementData) {
    throw new Error('Hermetic page element not found');
  }

  const jsonPath = join(runDir, 'baseline-computed.json');
  writeFileSync(jsonPath, JSON.stringify(elementData, null, 2), 'utf8');

  const pngPath = join(runDir, 'hermetic-box.png');
  await page.locator(selector).first().screenshot({ path: pngPath });

  await context.close();
  return { jsonPath, pngPath };
}

// ---------------------------------------------------------------------------
// CLI entry point — determinism self-test
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      args.help = true;
    } else if (arg.startsWith('--')) {
      const key = arg.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      args[key] = argv[i + 1] ?? true;
      i++;
    }
  }
  return args;
}

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  console.log(`
ui-capture-fixtures.mjs — Determinism harness + hermetic test page

Exports (for use as a module):
  applyDeterminismFixtures(page, context)   Apply before any capture
  HERMETIC_TEST_PAGE_HTML                   Self-contained test HTML

CLI (determinism self-test):
  node ui-capture-fixtures.mjs --output-dir <path>

Runs 2x capture of the hermetic page and compares outputs:
  - JSON equality of baseline-computed.json
  - Pixel diff < 1% of total pixels (color_threshold=0.1)

Exit 0: PASS — both captures are identical within tolerance
Exit 1: FAIL — outputs differ beyond tolerance
  `.trim());
  process.exit(0);
}

if (!args.outputDir) {
  console.error('Missing required argument: --output-dir');
  console.error('Run with --help for usage.');
  process.exit(1);
}

const absOutputDir = resolve(args.outputDir);
const run1Dir = join(absOutputDir, 'run1');
const run2Dir = join(absOutputDir, 'run2');

console.log('Starting determinism self-test...');
console.log(`Output dir: ${absOutputDir}`);

const browser = await chromium.launch({
  headless: true,
  args: ['--disable-gpu', '--no-sandbox', '--disable-dev-shm-usage'],
});

let exitCode = 0;

try {
  console.log('\nRun 1...');
  const run1 = await captureHermeticPage(browser, run1Dir);
  console.log(`  JSON: ${run1.jsonPath}`);
  console.log(`  PNG:  ${run1.pngPath}`);

  console.log('\nRun 2...');
  const run2 = await captureHermeticPage(browser, run2Dir);
  console.log(`  JSON: ${run2.jsonPath}`);
  console.log(`  PNG:  ${run2.pngPath}`);

  // Compare JSON
  const json1 = JSON.parse(readFileSync(run1.jsonPath, 'utf8'));
  const json2 = JSON.parse(readFileSync(run2.jsonPath, 'utf8'));

  // Remove captured_at from comparison (it uses pinned Date but just to be safe)
  const normalize = (obj) => {
    const { captured_at: _, ...rest } = obj;
    return rest;
  };

  const json1Str = JSON.stringify(normalize(json1), null, 2);
  const json2Str = JSON.stringify(normalize(json2), null, 2);
  const jsonEqual = json1Str === json2Str;

  if (!jsonEqual) {
    console.error('\nFAIL: baseline-computed.json differs between runs');
    console.error('Run 1:', json1Str);
    console.error('Run 2:', json2Str);
    exitCode = 1;
  } else {
    console.log('\nJSON equality: PASS');
  }

  // Compare PNGs
  try {
    const { diffPixels, totalPixels, diffRatio } = comparePngs(run1.pngPath, run2.pngPath);
    const NOISE_BUDGET = 0.01; // 1% max pixel diff

    if (diffRatio > NOISE_BUDGET) {
      console.error(`\nFAIL: PNG diff ${(diffRatio * 100).toFixed(3)}% exceeds noise budget ${(NOISE_BUDGET * 100).toFixed(1)}%`);
      console.error(`  Diff pixels: ${diffPixels} / ${totalPixels}`);
      exitCode = 1;
    } else {
      console.log(`\nPNG pixel diff: PASS (${diffPixels} diff pixels, ${(diffRatio * 100).toFixed(3)}% of ${totalPixels})`);
    }
  } catch (err) {
    console.error(`\nFAIL: PNG comparison error: ${err.message}`);
    exitCode = 1;
  }

  if (exitCode === 0) {
    console.log('\nResult: PASS — both captures are identical within tolerance');
  } else {
    console.log('\nResult: FAIL — captures differ beyond tolerance');
  }
} catch (err) {
  console.error(`\nFAIL: ${err.message}`);
  exitCode = 1;
} finally {
  await browser.close();
}

process.exit(exitCode);
