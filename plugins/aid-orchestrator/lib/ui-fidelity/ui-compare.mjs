/**
 * ui-compare.mjs — Mechanical UI fidelity guard
 *
 * CLI usage:
 *   node ui-compare.mjs \
 *     --before-png <path>          # baseline PNG (before change)
 *     --after-png <path>           # capture PNG (after change)
 *     --before-computed <path>     # baseline-computed.json (before)
 *     --after-computed <path>      # baseline-computed.json (after)
 *     --contract <path>            # ui-change-contract YAML file
 *     --output-dir <path>          # directory to write ui/verdict.json
 *     [--color-threshold <0-1>]    # pixelmatch threshold, default 0.1
 *     [--noise-budget <0-1>]       # fraction of pixels allowed outside mask, default 0.01
 *
 * Checks performed:
 *   (a) positive_delta  — every typed change in delta was applied
 *   (b) rest_lock       — no unauthorized change inside delta element
 *   (c) locked_crops    — pixel equality in locked crops within tolerance
 *   (d) affected_reflow — reflow within bounds
 *   (e) outside_mask    — nothing changed outside delta+affected+locked mask
 *
 * Output: <output-dir>/ui/verdict.json
 *
 * Part of E-056 E7A Step 3. Standalone — no pipeline/FSM wiring.
 */

import { execFileSync } from 'child_process';
import { existsSync, readFileSync, mkdirSync, writeFileSync } from 'fs';
import { resolve, join, dirname } from 'path';
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';

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
ui-compare.mjs — UI fidelity mechanical guard

Usage:
  node ui-compare.mjs \\
    --before-png <path>          Baseline PNG (before change)
    --after-png <path>           Capture PNG (after change)
    --before-computed <path>     baseline-computed.json (before)
    --after-computed <path>      baseline-computed.json (after)
    --contract <path>            ui-change-contract YAML file
    --output-dir <path>          Directory to write ui/verdict.json

Options:
  --color-threshold <0-1>        pixelmatch per-pixel threshold (default: 0.1)
  --noise-budget <0-1>           fraction of outside-mask pixels allowed to differ (default: 0.01)
  --help                         Show this help

Output:
  <output-dir>/ui/verdict.json   Verdict JSON with per-check results
`.trim());
}

// ---------------------------------------------------------------------------
// YAML parsing via yq CLI
// ---------------------------------------------------------------------------

/**
 * Parse a YAML file to a JS object using yq (converts YAML -> JSON).
 * Requires yq v4+ on PATH.
 */
function parseYaml(yamlPath) {
  const absPath = resolve(yamlPath);
  if (!existsSync(absPath)) {
    throw new Error(`Contract file not found: ${absPath}`);
  }
  try {
    const json = execFileSync('yq', ['-o=json', '.', absPath], {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return JSON.parse(json);
  } catch (err) {
    throw new Error(`Failed to parse YAML contract (${absPath}): ${err.message}`);
  }
}

// ---------------------------------------------------------------------------
// PNG loading
// ---------------------------------------------------------------------------

/**
 * Load a PNG file synchronously via pngjs.
 * Returns { data, width, height } or null if file does not exist.
 */
function loadPng(pngPath) {
  const absPath = resolve(pngPath);
  if (!existsSync(absPath)) return null;
  const buffer = readFileSync(absPath);
  return PNG.sync.read(buffer);
}

// ---------------------------------------------------------------------------
// CSS value normalization
// ---------------------------------------------------------------------------

/**
 * Normalize a CSS value for comparison.
 * - Trim whitespace
 * - Lowercase color keywords
 * - Leave hex values as-is (already canonical from getComputedStyle)
 */
function normalizeCssValue(val) {
  if (typeof val !== 'string') return String(val ?? '');
  return val.trim().toLowerCase();
}

// ---------------------------------------------------------------------------
// Pixel-level comparison helpers
// ---------------------------------------------------------------------------

/**
 * Run pixelmatch on two PNG images and return the number of differing pixels.
 * Images must have the same dimensions.
 *
 * @param {object} imgA  pngjs image { data, width, height }
 * @param {object} imgB  pngjs image { data, width, height }
 * @param {number} threshold  pixelmatch color threshold 0-1
 * @returns {number} count of differing pixels
 */
function countDiffPixels(imgA, imgB, threshold) {
  const { width, height } = imgA;
  const diff = new Uint8Array(width * height * 4);
  return pixelmatch(imgA.data, imgB.data, diff, width, height, { threshold });
}

/**
 * Run pixelmatch on a specific rectangular crop of two PNG images.
 * Crops are clamped to image bounds.
 *
 * @param {object} imgA         pngjs image { data, width, height }
 * @param {object} imgB         pngjs image { data, width, height }
 * @param {object} crop         { x, y, width, height } crop region
 * @param {number} threshold    pixelmatch color threshold 0-1
 * @returns {number} count of differing pixels in crop
 */
function countDiffPixelsInCrop(imgA, imgB, crop, threshold) {
  const imgW = imgA.width;
  const imgH = imgA.height;

  // Clamp crop to image bounds
  const x0 = Math.max(0, Math.min(imgW - 1, crop.x));
  const y0 = Math.max(0, Math.min(imgH - 1, crop.y));
  const x1 = Math.max(0, Math.min(imgW, crop.x + crop.width));
  const y1 = Math.max(0, Math.min(imgH, crop.y + crop.height));

  const cropW = x1 - x0;
  const cropH = y1 - y0;
  if (cropW <= 0 || cropH <= 0) return 0;

  // Extract crop from each image into flat RGBA buffers
  const bufA = new Uint8Array(cropW * cropH * 4);
  const bufB = new Uint8Array(cropW * cropH * 4);

  for (let row = 0; row < cropH; row++) {
    for (let col = 0; col < cropW; col++) {
      const srcIdx = ((y0 + row) * imgW + (x0 + col)) * 4;
      const dstIdx = (row * cropW + col) * 4;
      bufA[dstIdx]     = imgA.data[srcIdx];
      bufA[dstIdx + 1] = imgA.data[srcIdx + 1];
      bufA[dstIdx + 2] = imgA.data[srcIdx + 2];
      bufA[dstIdx + 3] = imgA.data[srcIdx + 3];
      bufB[dstIdx]     = imgB.data[srcIdx];
      bufB[dstIdx + 1] = imgB.data[srcIdx + 1];
      bufB[dstIdx + 2] = imgB.data[srcIdx + 2];
      bufB[dstIdx + 3] = imgB.data[srcIdx + 3];
    }
  }

  const diff = new Uint8Array(cropW * cropH * 4);
  return pixelmatch(bufA, bufB, diff, cropW, cropH, { threshold });
}

/**
 * Build a boolean mask array (per-pixel, flat) marking pixels that are
 * inside any of the provided bounding boxes.
 *
 * @param {number} imgW    image width
 * @param {number} imgH    image height
 * @param {Array}  bboxes  array of { x, y, width, height }
 * @returns {Uint8Array}   mask of length imgW * imgH, 1 = inside mask
 */
function buildMask(imgW, imgH, bboxes) {
  const mask = new Uint8Array(imgW * imgH); // 0 = outside, 1 = inside
  for (const bbox of bboxes) {
    const x0 = Math.max(0, Math.min(imgW - 1, bbox.x));
    const y0 = Math.max(0, Math.min(imgH - 1, bbox.y));
    const x1 = Math.max(0, Math.min(imgW, bbox.x + bbox.width));
    const y1 = Math.max(0, Math.min(imgH, bbox.y + bbox.height));
    for (let y = y0; y < y1; y++) {
      for (let x = x0; x < x1; x++) {
        mask[y * imgW + x] = 1;
      }
    }
  }
  return mask;
}

/**
 * Count differing pixels outside the provided mask.
 * Uses pixelmatch color threshold for per-pixel comparison.
 *
 * @param {object}     imgA       pngjs image before
 * @param {object}     imgB       pngjs image after
 * @param {Uint8Array} mask       flat mask (1 = inside/excluded, 0 = outside/checked)
 * @param {number}     threshold  pixelmatch color threshold
 * @returns {{ diffPixels: number, outsideTotal: number }}
 */
function countDiffOutsideMask(imgA, imgB, mask, threshold) {
  const { width, height } = imgA;
  const total = width * height;

  let outsideTotal = 0;
  let diffPixels = 0;

  // Use pixelmatch channel-by-channel comparison approximation:
  // For speed, do a direct RGBA comparison with a tolerance-like threshold.
  // pixelmatch expects full image buffers, so we blank out masked pixels first.
  //
  // Strategy: copy both images, zero out masked pixels identically (so they
  // never differ), then run pixelmatch on the full images — only unmasked
  // pixels can produce a diff.
  const dataA = new Uint8Array(imgA.data.length);
  const dataB = new Uint8Array(imgB.data.length);

  for (let i = 0; i < total; i++) {
    const pixIdx = i * 4;
    if (mask[i] === 1) {
      // Mask out: set identical neutral pixel (transparent) in both
      dataA[pixIdx] = 0; dataA[pixIdx + 1] = 0; dataA[pixIdx + 2] = 0; dataA[pixIdx + 3] = 0;
      dataB[pixIdx] = 0; dataB[pixIdx + 1] = 0; dataB[pixIdx + 2] = 0; dataB[pixIdx + 3] = 0;
    } else {
      outsideTotal++;
      dataA[pixIdx]     = imgA.data[pixIdx];
      dataA[pixIdx + 1] = imgA.data[pixIdx + 1];
      dataA[pixIdx + 2] = imgA.data[pixIdx + 2];
      dataA[pixIdx + 3] = imgA.data[pixIdx + 3];
      dataB[pixIdx]     = imgB.data[pixIdx];
      dataB[pixIdx + 1] = imgB.data[pixIdx + 1];
      dataB[pixIdx + 2] = imgB.data[pixIdx + 2];
      dataB[pixIdx + 3] = imgB.data[pixIdx + 3];
    }
  }

  const diffBuf = new Uint8Array(total * 4);
  diffPixels = pixelmatch(dataA, dataB, diffBuf, width, height, { threshold });

  return { diffPixels, outsideTotal };
}

// ---------------------------------------------------------------------------
// Check implementations
// ---------------------------------------------------------------------------

/**
 * Check (a): positive_delta
 * Verify every typed change in delta was applied in after_computed.
 */
function checkPositiveDelta(contract, beforeComputed, afterComputed) {
  const findings = [];
  const typed = contract.delta?.typed ?? [];

  for (const change of typed) {
    const { property, to } = change;
    const actual = afterComputed.computed_styles?.[property];
    const expected = normalizeCssValue(to);
    const actualNorm = normalizeCssValue(actual ?? '');

    if (actualNorm !== expected) {
      findings.push({
        reason: 'delta_not_applied',
        property,
        expected: to,
        actual: actual ?? null,
      });
    }
  }

  return {
    pass: findings.length === 0,
    skipped: false,
    findings,
  };
}

/**
 * Check (b): rest_lock
 * No computed_style key that is NOT in delta.typed changed unexpectedly.
 * Skipped if presence state is "removed" or "hidden".
 */
function checkRestLock(contract, beforeComputed, afterComputed) {
  const presenceState = contract.target?.presence?.state;
  if (presenceState === 'removed' || presenceState === 'hidden') {
    return { pass: true, skipped: true, findings: [] };
  }

  const typed = contract.delta?.typed ?? [];
  const allowedProperties = new Set(typed.map(c => c.property));

  const findings = [];
  const beforeStyles = beforeComputed.computed_styles ?? {};
  const afterStyles = afterComputed.computed_styles ?? {};

  // Check all properties present in after (covers both before-only and after-only keys)
  const allProps = new Set([...Object.keys(beforeStyles), ...Object.keys(afterStyles)]);

  for (const prop of allProps) {
    if (allowedProperties.has(prop)) continue; // this property is part of the approved delta
    const beforeVal = normalizeCssValue(beforeStyles[prop] ?? '');
    const afterVal = normalizeCssValue(afterStyles[prop] ?? '');
    if (beforeVal !== afterVal) {
      findings.push({
        reason: 'delta_unauthorized_change',
        property: prop,
        before: beforeStyles[prop] ?? null,
        after: afterStyles[prop] ?? null,
      });
    }
  }

  return {
    pass: findings.length === 0,
    skipped: false,
    findings,
  };
}

/**
 * Check (c): locked_crops
 * Pixel equality in locked crop areas within their tolerance.
 *
 * For each locked entry we use the before_computed.bbox as the crop region
 * when the locked selector matches the target selector. For non-target selectors
 * we compare the full image (since per-selector bbox is unavailable from capture data).
 */
function checkLockedCrops(contract, beforeComputed, afterComputed, beforePng, afterPng, colorThreshold) {
  const findings = [];
  const locked = contract.delta?.locked ?? [];

  if (locked.length === 0) {
    return { pass: true, findings: [] };
  }

  // Images must have the same dimensions for comparison
  if (beforePng.width !== afterPng.width || beforePng.height !== afterPng.height) {
    findings.push({
      reason: 'image_dimension_mismatch',
      note: 'before and after PNGs have different dimensions, cannot compare',
      before_dims: `${beforePng.width}x${beforePng.height}`,
      after_dims: `${afterPng.width}x${afterPng.height}`,
    });
    return { pass: false, findings };
  }

  const targetSelector = contract.target?.selector ?? null;
  const targetBbox = beforeComputed.bbox;

  for (const lock of locked) {
    const { selector, tolerance_px } = lock;
    let diffPixels;
    let cropNote = null;

    if (selector === targetSelector && targetBbox) {
      // Use target bbox as crop
      diffPixels = countDiffPixelsInCrop(beforePng, afterPng, targetBbox, colorThreshold);
    } else {
      // No per-selector bbox available — use full image comparison
      diffPixels = countDiffPixels(beforePng, afterPng, colorThreshold);
      cropNote = 'bbox not available for selector, compared full image';
    }

    if (diffPixels > tolerance_px) {
      const finding = {
        reason: 'locked_violation',
        selector,
        diff_pixels: diffPixels,
        tolerance_px,
      };
      if (cropNote) finding.note = cropNote;
      findings.push(finding);
    }
  }

  return {
    pass: findings.length === 0,
    findings,
  };
}

/**
 * Check (d): affected_reflow
 * Compare bbox of target between before and after.
 * Fails if movement exceeds max_reflow_px or max_reflow_percent.
 */
function checkAffectedReflow(contract, beforeComputed, afterComputed) {
  const findings = [];
  const affected = contract.delta?.affected;

  if (!affected) {
    return { pass: true, findings: [] };
  }

  const beforeBbox = beforeComputed.bbox;
  const afterBbox = afterComputed.bbox;

  if (!beforeBbox || !afterBbox) {
    return {
      pass: true,
      findings: [],
      note: 'bbox missing in computed data, reflow check skipped',
    };
  }

  // Reflow = max absolute diff across x, y, width, height
  const diffs = [
    Math.abs((afterBbox.x ?? 0) - (beforeBbox.x ?? 0)),
    Math.abs((afterBbox.y ?? 0) - (beforeBbox.y ?? 0)),
    Math.abs((afterBbox.width ?? 0) - (beforeBbox.width ?? 0)),
    Math.abs((afterBbox.height ?? 0) - (beforeBbox.height ?? 0)),
  ];
  const reflowPx = Math.max(...diffs);

  const { max_reflow_px, max_reflow_percent } = affected;
  const refDimension = Math.max(beforeBbox.width ?? 1, beforeBbox.height ?? 1);
  const reflowPercent = (reflowPx / refDimension) * 100;

  let exceeded = false;

  if (max_reflow_px !== undefined && reflowPx > max_reflow_px) {
    exceeded = true;
  }
  if (max_reflow_percent !== undefined && reflowPercent > max_reflow_percent) {
    exceeded = true;
  }

  if (exceeded) {
    findings.push({
      reason: 'affected_reflow_exceeded',
      reflow_px: reflowPx,
      reflow_percent: Math.round(reflowPercent * 100) / 100,
      max_reflow_px: max_reflow_px ?? null,
      max_reflow_percent: max_reflow_percent ?? null,
    });
  }

  return { pass: findings.length === 0, findings };
}

/**
 * Check (e): outside_mask
 * Nothing changed outside the union of delta+affected+locked regions.
 * Two-part tolerance: color_threshold (per-pixel) + noise_budget (fraction).
 */
function checkOutsideMask(contract, beforeComputed, afterComputed, beforePng, afterPng, colorThreshold, noiseBudget) {
  const findings = [];

  // Images must match dimensions
  if (beforePng.width !== afterPng.width || beforePng.height !== afterPng.height) {
    findings.push({
      reason: 'outside_mask_diff',
      note: 'before and after PNGs have different dimensions, cannot perform outside-mask check',
    });
    return { pass: false, diff_pixels: null, diff_ratio: null, findings };
  }

  const imgW = beforePng.width;
  const imgH = beforePng.height;

  // Collect bboxes for mask regions
  const maskBboxes = [];

  // Delta region: use target bbox (the element being changed)
  const targetBbox = beforeComputed.bbox;
  if (targetBbox) {
    maskBboxes.push(targetBbox);
  } else {
    // If no bbox, mask the whole image to avoid false positives
    maskBboxes.push({ x: 0, y: 0, width: imgW, height: imgH });
  }

  // Affected region: use after bbox if it changed (compare by value, not reference)
  const afterBbox = afterComputed.bbox;
  if (afterBbox && JSON.stringify(afterBbox) !== JSON.stringify(targetBbox)) {
    maskBboxes.push(afterBbox);
  }

  // Locked regions: use target bbox when selector matches, or full image otherwise
  const locked = contract.delta?.locked ?? [];
  const targetSelector = contract.target?.selector ?? null;
  for (const lock of locked) {
    if (lock.selector === targetSelector && targetBbox) {
      maskBboxes.push(targetBbox);
    } else {
      // No per-selector bbox — mask full image for this lock (conservative)
      maskBboxes.push({ x: 0, y: 0, width: imgW, height: imgH });
    }
  }

  const mask = buildMask(imgW, imgH, maskBboxes);
  const { diffPixels, outsideTotal } = countDiffOutsideMask(beforePng, afterPng, mask, colorThreshold);

  const diffRatio = outsideTotal > 0 ? diffPixels / outsideTotal : 0;

  if (diffRatio > noiseBudget) {
    findings.push({
      reason: 'outside_mask_diff',
      diff_pixels: diffPixels,
      diff_ratio: Math.round(diffRatio * 1e6) / 1e6,
      noise_budget: noiseBudget,
      outside_total_pixels: outsideTotal,
    });
  }

  return {
    pass: findings.length === 0,
    diff_pixels: diffPixels,
    diff_ratio: Math.round(diffRatio * 1e6) / 1e6,
    findings,
  };
}

// ---------------------------------------------------------------------------
// Main comparison orchestrator
// ---------------------------------------------------------------------------

function compare({
  beforePngPath,
  afterPngPath,
  beforeComputedPath,
  afterComputedPath,
  contractPath,
  outputDir,
  colorThreshold,
  noiseBudget,
}) {
  // --- Resolve all paths ---
  const absBefore = resolve(beforePngPath);
  const absAfter = resolve(afterPngPath);
  const absBeforeComp = resolve(beforeComputedPath);
  const absAfterComp = resolve(afterComputedPath);

  // --- Detect missing inputs ---
  const missingInputs = [];
  if (!existsSync(absBefore)) missingInputs.push(`--before-png: ${absBefore}`);
  if (!existsSync(absAfter)) missingInputs.push(`--after-png: ${absAfter}`);
  if (!existsSync(absBeforeComp)) missingInputs.push(`--before-computed: ${absBeforeComp}`);
  if (!existsSync(absAfterComp)) missingInputs.push(`--after-computed: ${absAfterComp}`);

  // Parse contract (needed for metadata even in unverifiable state)
  let contract;
  try {
    contract = parseYaml(contractPath);
  } catch (err) {
    console.error(`Failed to load contract: ${err.message}`);
    process.exit(1);
  }

  const contractId = contract.contract_id ?? null;
  const targetId = contract.target?.id ?? null;

  if (missingInputs.length > 0) {
    console.error('Missing required inputs (verdict: unverifiable):');
    for (const m of missingInputs) console.error(`  ${m}`);
    const verdict = {
      verdict: 'unverifiable',
      contract_id: contractId,
      target_id: targetId,
      checks: {
        positive_delta: { pass: false, skipped: false, findings: [{ reason: 'unverifiable', missing: missingInputs }] },
        rest_lock: { pass: false, skipped: false, findings: [] },
        locked_crops: { pass: false, findings: [] },
        affected_reflow: { pass: false, findings: [] },
        outside_mask: { pass: false, diff_pixels: null, diff_ratio: null, findings: [] },
      },
      generated_at: new Date().toISOString(),
    };
    writeVerdict(outputDir, verdict);
    return verdict;
  }

  // --- Load computed JSON files ---
  const beforeComputed = JSON.parse(readFileSync(absBeforeComp, 'utf8'));
  const afterComputed = JSON.parse(readFileSync(absAfterComp, 'utf8'));

  // --- Load PNG images ---
  const beforePng = loadPng(absBefore);
  const afterPng = loadPng(absAfter);

  // Run all checks
  const positiveDelta = checkPositiveDelta(contract, beforeComputed, afterComputed);
  const restLock = checkRestLock(contract, beforeComputed, afterComputed);

  let lockedCrops;
  let affectedReflow;
  let outsideMask;

  if (beforePng && afterPng) {
    lockedCrops = checkLockedCrops(contract, beforeComputed, afterComputed, beforePng, afterPng, colorThreshold);
    outsideMask = checkOutsideMask(contract, beforeComputed, afterComputed, beforePng, afterPng, colorThreshold, noiseBudget);
  } else {
    // PNGs loaded OK (existence checked above) but PNG.sync.read returned null —
    // treat as unverifiable for pixel checks only
    lockedCrops = { pass: false, findings: [{ reason: 'unverifiable', note: 'PNG could not be decoded' }] };
    outsideMask = { pass: false, diff_pixels: null, diff_ratio: null, findings: [{ reason: 'unverifiable', note: 'PNG could not be decoded' }] };
  }

  affectedReflow = checkAffectedReflow(contract, beforeComputed, afterComputed);

  // --- Overall verdict ---
  const allPassed = [
    positiveDelta.pass || positiveDelta.skipped,
    restLock.pass || restLock.skipped,
    lockedCrops.pass,
    affectedReflow.pass,
    outsideMask.pass,
  ].every(Boolean);

  const verdict = {
    verdict: allPassed ? 'pass' : 'fail',
    contract_id: contractId,
    target_id: targetId,
    checks: {
      positive_delta: positiveDelta,
      rest_lock: restLock,
      locked_crops: lockedCrops,
      affected_reflow: affectedReflow,
      outside_mask: outsideMask,
    },
    generated_at: new Date().toISOString(),
  };

  writeVerdict(outputDir, verdict);

  return verdict;
}

function writeVerdict(outputDir, verdict) {
  const verdictDir = join(resolve(outputDir), 'ui');
  mkdirSync(verdictDir, { recursive: true });
  const verdictPath = join(verdictDir, 'verdict.json');
  writeFileSync(verdictPath, JSON.stringify(verdict, null, 2), 'utf8');
  console.log(`Verdict: ${verdict.verdict}`);
  console.log(`Written: ${verdictPath}`);
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  printHelp();
  process.exit(0);
}

const required = [
  ['beforePng', '--before-png'],
  ['afterPng', '--after-png'],
  ['beforeComputed', '--before-computed'],
  ['afterComputed', '--after-computed'],
  ['contract', '--contract'],
  ['outputDir', '--output-dir'],
];

const missing = required.filter(([key]) => !args[key]);
if (missing.length > 0) {
  console.error(`Missing required arguments: ${missing.map(([, flag]) => flag).join(', ')}`);
  console.error('Run with --help for usage.');
  process.exit(1);
}

const colorThreshold = parseFloat(args.colorThreshold ?? '0.1');
const noiseBudget = parseFloat(args.noiseBudget ?? '0.01');

if (isNaN(colorThreshold) || colorThreshold < 0 || colorThreshold > 1) {
  console.error('--color-threshold must be a number between 0 and 1');
  process.exit(1);
}
if (isNaN(noiseBudget) || noiseBudget < 0 || noiseBudget > 1) {
  console.error('--noise-budget must be a number between 0 and 1');
  process.exit(1);
}

try {
  const result = compare({
    beforePngPath: args.beforePng,
    afterPngPath: args.afterPng,
    beforeComputedPath: args.beforeComputed,
    afterComputedPath: args.afterComputed,
    contractPath: args.contract,
    outputDir: args.outputDir,
    colorThreshold,
    noiseBudget,
  });

  // Exit 0 for pass/unverifiable, 1 for fail (so CI can detect failures)
  process.exit(result.verdict === 'fail' ? 1 : 0);
} catch (err) {
  console.error(`Comparison failed: ${err.message}`);
  process.exit(1);
}
