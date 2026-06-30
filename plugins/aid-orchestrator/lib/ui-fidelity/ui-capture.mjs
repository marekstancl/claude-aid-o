/**
 * ui-capture.mjs — Playwright-based screenshot capture + computed styles extractor
 *
 * CLI usage:
 *   node ui-capture.mjs --url <url> --selector <css-selector> --target-id <id> --output-dir <path> [--api-mocks-file <json-file>]
 *
 * Outputs to --output-dir:
 *   <target-id>.png           — clipped screenshot of matched element
 *   baseline-computed.json    — computed styles, bbox, text, aria attributes
 *
 * Part of E-056 E7A foundation. Standalone — no pipeline/FSM wiring.
 */

import { chromium } from '@playwright/test';
import { readFileSync, mkdirSync, writeFileSync } from 'fs';
import { resolve, join } from 'path';

// ---------------------------------------------------------------------------
// CLI argument parsing
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

function printHelp() {
  console.log(`
ui-capture.mjs — UI fidelity screenshot + computed styles capture

Usage:
  node ui-capture.mjs --url <url> --selector <css-selector> --target-id <id> --output-dir <path> [--api-mocks-file <json-file>]

Options:
  --url <url>               Page URL to navigate to
  --selector <css>          CSS selector of the element to capture
  --target-id <id>          Identifier used for output filenames
  --output-dir <path>       Directory to write outputs into (created if missing)
  --api-mocks-file <file>   JSON file with API mock definitions (optional)
  --help                    Show this help

Output files (written to --output-dir):
  <target-id>.png           Clipped screenshot of the matched element
  baseline-computed.json    Computed styles, bbox, text content, aria attributes

API mocks file format (array):
  [
    { "url": "<pattern>", "method": "GET", "status": 200, "body": { ... } }
  ]
`.trim());
}

// ---------------------------------------------------------------------------
// Core capture logic
// ---------------------------------------------------------------------------

/**
 * Load and register API mocks from a JSON file onto the page.
 * Each mock entry: { url, method?, status?, body?, contentType? }
 */
async function registerApiMocks(page, mocksFile) {
  const raw = readFileSync(resolve(mocksFile), 'utf8');
  const mocks = JSON.parse(raw);

  if (!Array.isArray(mocks)) {
    throw new Error(`api-mocks-file must contain a JSON array, got: ${typeof mocks}`);
  }

  for (const mock of mocks) {
    const { url: urlPattern, method = '*', status = 200, body = {}, contentType = 'application/json' } = mock;
    await page.route(urlPattern, (route) => {
      const req = route.request();
      if (method !== '*' && req.method().toUpperCase() !== method.toUpperCase()) {
        return route.continue();
      }
      const bodyStr = typeof body === 'string' ? body : JSON.stringify(body);
      route.fulfill({
        status,
        contentType,
        body: bodyStr,
      });
    });
  }
}

/**
 * Capture computed styles, bounding box, text content, and aria attributes
 * for the first element matching selector.
 */
async function extractElementData(page, selector, targetId, url) {
  const data = await page.evaluate(({ sel, tid, pageUrl }) => {
    const el = document.querySelector(sel);
    if (!el) return null;

    const cs = window.getComputedStyle(el);
    const rect = el.getBoundingClientRect();

    // Aria attributes
    const attrNames = Array.from(el.attributes).map(a => a.name);
    const attributes = {};
    for (const name of attrNames) {
      attributes[name] = el.getAttribute(name);
    }

    return {
      target_id: tid,
      captured_at: new Date().toISOString(),
      url: pageUrl,
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
  }, { sel: selector, tid: targetId, pageUrl: url });

  return data;
}

/**
 * Main capture function — navigates to URL, mocks APIs, captures element.
 */
async function capture({ url, selector, targetId, outputDir, apiMocksFile }) {
  const absOutputDir = resolve(outputDir);
  mkdirSync(absOutputDir, { recursive: true });

  const browser = await chromium.launch({
    headless: true,
    args: ['--disable-gpu', '--no-sandbox', '--disable-dev-shm-usage'],
  });

  try {
    const context = await browser.newContext({
      viewport: { width: 1280, height: 720 },
      locale: 'en-US',
      timezoneId: 'UTC',
      colorScheme: 'light',
    });

    const page = await context.newPage();

    // Register API mocks before navigation
    if (apiMocksFile) {
      await registerApiMocks(page, apiMocksFile);
    }

    await page.goto(url, { waitUntil: 'networkidle' });

    // Wait for selector to be visible
    await page.waitForSelector(selector, { state: 'visible', timeout: 10000 });

    // Extract computed data
    const elementData = await extractElementData(page, selector, targetId, url);
    if (!elementData) {
      throw new Error(`No element found for selector: ${selector}`);
    }

    // Take clipped screenshot of the element
    const locator = page.locator(selector).first();
    const pngPath = join(absOutputDir, `${targetId}.png`);
    await locator.screenshot({ path: pngPath });

    // Write computed JSON
    const jsonPath = join(absOutputDir, 'baseline-computed.json');
    writeFileSync(jsonPath, JSON.stringify(elementData, null, 2), 'utf8');

    console.log(`Captured: ${pngPath}`);
    console.log(`Metadata: ${jsonPath}`);

    return { pngPath, jsonPath, elementData };
  } finally {
    await browser.close();
  }
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  printHelp();
  process.exit(0);
}

const required = ['url', 'selector', 'targetId', 'outputDir'];
const missing = required.filter(k => !args[k]);
if (missing.length > 0) {
  console.error(`Missing required arguments: ${missing.map(k => '--' + k.replace(/([A-Z])/g, '-$1').toLowerCase()).join(', ')}`);
  console.error('Run with --help for usage.');
  process.exit(1);
}

try {
  await capture({
    url: args.url,
    selector: args.selector,
    targetId: args.targetId,
    outputDir: args.outputDir,
    apiMocksFile: args.apiMocksFile ?? null,
  });
  process.exit(0);
} catch (err) {
  console.error(`Capture failed: ${err.message}`);
  process.exit(1);
}
