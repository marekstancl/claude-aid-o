/**
 * READ-ONLY INVARIANT enforcement test (EPIC E-047-4_7, Step 9 — FINAL).
 *
 * THIS IS THE BINDING ENFORCEMENT for the cockpit's core invariant: the
 * aid-server reads disk and NEVER writes it. Per AID-v3-principles §1
 * ("Detector without Enforcement is Decoration"), the invariant is not a
 * comment or a code-review convention — it is THIS test, which fails the build
 * if any production source file performs a filesystem write or shells out.
 *
 * Mechanism (deliberately robust against false positives AND false negatives):
 *   1. Walk every `.ts` under `src/`, EXCLUDING `*.test.ts` (tests legitimately
 *      write temp fixtures) and `__fixtures__/` (fixture builders write the
 *      on-disk trees the integration tests read) and any `node_modules`.
 *   2. STRIP comments before grepping — a JSDoc that *names* `writeFile` while
 *      explaining the guarantee must NOT trip the check (we assert on code, not
 *      documentation). Both block (`/* … *​/`) and line (`// …`) comments are
 *      removed; line-comment stripping is string/regex-aware so a `//` inside a
 *      string or regex literal is preserved.
 *   3. Grep for write-capable CALL EXPRESSIONS (`fn(` / `obj.fn(`), not bare
 *      substrings — so the chokidar `'unlink'` EVENT-NAME string literal is not
 *      a false positive while a real `fs.unlink(…)` call still is. Plus any
 *      `child_process` import / `exec`/`spawn` usage.
 *   4. ASSERT ZERO matches. On a match, fail LOUDLY with `file:line` so the
 *      offending write is pinpointed (the WAN P026 lesson: a detector that
 *      flags but does not block is decoration).
 *
 * Today the production tree is clean (the Phase-3 cleanup removed the
 * write-capable orphans). This test keeps it that way.
 *
 * Module: src/integration/read-only-invariant.test.ts
 */

import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
// src/integration/ → src/
const SRC_ROOT = join(here, '..');

// ---------------------------------------------------------------------------
// Source enumeration (production .ts only)
// ---------------------------------------------------------------------------

/** True for files this invariant does NOT police (tests + fixtures). */
function isExcluded(absPath: string): boolean {
  const p = absPath.replace(/\\/g, '/');
  if (p.includes('/node_modules/')) return true;
  if (p.includes('/__fixtures__/')) return true;
  if (p.endsWith('.test.ts')) return true;
  // d.ts type declarations carry no runtime behaviour.
  if (p.endsWith('.d.ts')) return true;
  return false;
}

/** Recursively collect production `.ts` files under `src/`. */
function collectProductionSources(root: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(root)) {
    const abs = join(root, entry);
    const st = statSync(abs);
    if (st.isDirectory()) {
      if (entry === 'node_modules' || entry === '__fixtures__') continue;
      out.push(...collectProductionSources(abs));
    } else if (entry.endsWith('.ts') && !isExcluded(abs)) {
      out.push(abs);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Comment stripping (string/regex-aware) — so prose naming a write op is safe.
// ---------------------------------------------------------------------------

/**
 * Remove block + line comments AND blank the CONTENTS of string / template /
 * regex literals from TS source. Blanking literal contents is deliberate: a real
 * `fs.writeFile(…)` call never lives inside a string or regex, so the scan only
 * needs the literal's delimiters — not its body. This kills two false-positive
 * classes at once:
 *   - a write-op NAME used as a string literal (chokidar's `'unlink'` event), and
 *   - a `name(` token that happens to appear INSIDE a regex literal
 *     (e.g. `/open(?:_count)?/` would otherwise look like an `open(` call).
 * String/regex delimiters are kept so the surrounding code still tokenises, and
 * newlines inside literals/comments are preserved so reported line numbers stay
 * accurate. A `//` or `/*` inside a string or regex is NOT treated as a comment.
 */
function stripComments(src: string): string {
  let out = '';
  let i = 0;
  const n = src.length;
  type Mode = 'code' | 'line' | 'block' | 'sq' | 'dq' | 'tpl' | 'regex';
  let mode: Mode = 'code';

  // For regex detection: a `/` starts a regex only when the previous
  // significant token suggests an expression position (not a divide).
  let prevSignificant = '';

  while (i < n) {
    const c = src[i];
    const next = i + 1 < n ? src[i + 1] : '';

    if (mode === 'code') {
      if (c === '/' && next === '/') {
        mode = 'line';
        i += 2;
        continue;
      }
      if (c === '/' && next === '*') {
        mode = 'block';
        i += 2;
        continue;
      }
      if (c === "'") {
        mode = 'sq';
        out += c;
        i++;
        prevSignificant = c;
        continue;
      }
      if (c === '"') {
        mode = 'dq';
        out += c;
        i++;
        prevSignificant = c;
        continue;
      }
      if (c === '`') {
        mode = 'tpl';
        out += c;
        i++;
        prevSignificant = c;
        continue;
      }
      if (c === '/') {
        // Decide regex vs divide based on the previous significant char.
        const regexAllowedAfter = /[=(,:;!&|?{}[\n+\-*%<>~^]/;
        const isRegex =
          prevSignificant === '' || regexAllowedAfter.test(prevSignificant);
        if (isRegex) {
          mode = 'regex';
          out += c;
          i++;
          continue;
        }
      }
      out += c;
      if (!/\s/.test(c)) prevSignificant = c;
      i++;
      continue;
    }

    if (mode === 'line') {
      if (c === '\n') {
        mode = 'code';
        out += c; // keep the newline so line numbers are preserved
      }
      i++;
      continue;
    }

    if (mode === 'block') {
      if (c === '*' && next === '/') {
        mode = 'code';
        i += 2;
      } else {
        if (c === '\n') out += c; // preserve newlines inside block comments
        i++;
      }
      continue;
    }

    // Inside string / template / regex literals: BLANK the body (keep delimiters
    // + newlines), so a write-op token inside a literal is never scanned.
    if (mode === 'sq' || mode === 'dq' || mode === 'tpl' || mode === 'regex') {
      if (c === '\\') {
        // Drop the escape pair from the body (a delimiter cannot follow it).
        if (next === '\n') out += '\n';
        i += 2;
        continue;
      }
      const isCloser =
        (mode === 'sq' && c === "'") ||
        (mode === 'dq' && c === '"') ||
        (mode === 'tpl' && c === '`') ||
        (mode === 'regex' && c === '/');
      if (isCloser) {
        out += c; // keep the closing delimiter
        mode = 'code';
        prevSignificant = c;
      } else if (c === '\n') {
        out += c; // preserve newlines (template literals / multiline)
      }
      // else: blank the body character.
      i++;
      continue;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Write-op detectors — CALL EXPRESSIONS + child_process surface.
// ---------------------------------------------------------------------------

/**
 * The forbidden filesystem-write operations, matched as CALL EXPRESSIONS:
 * `name(` optionally with a member prefix (`fs.name(`, `fsp.name(`). A bare
 * occurrence of the word (e.g. the chokidar `'unlink'` event-name string) is
 * NOT matched, because a `(` is required after the identifier.
 */
const WRITE_FNS = [
  'writeFile',
  'writeFileSync',
  'appendFile',
  'appendFileSync',
  'mkdir',
  'mkdirSync',
  'rm',
  'rmSync',
  'rmdir',
  'rmdirSync',
  'unlink',
  'unlinkSync',
  'rename',
  'renameSync',
  'createWriteStream',
  'truncate',
  'truncateSync',
  'chmod',
  'chmodSync',
  'chown',
  'chownSync',
  'mkdtemp',
  'mkdtempSync',
  'cp',
  'cpSync',
  'copyFile',
  'copyFileSync',
] as const;

/**
 * Per-line write-op pattern: an identifier from WRITE_FNS, optionally preceded
 * by a member-access dot (`.writeFile(`), then an opening paren (allowing
 * whitespace). The leading `(?<![\w.])` / `(?:\.)?` form lets `fs.writeFile(`
 * AND a bare destructured `writeFile(` both match, while `someWriteFileLabel`
 * (no paren) does NOT.
 */
const WRITE_CALL_RE = new RegExp(
  `(?<![A-Za-z0-9_$])(?:[A-Za-z0-9_$]+\\s*\\.\\s*)?(${WRITE_FNS.join('|')})\\s*\\(`,
);

/**
 * child_process import, OR a bare exec/spawn/fork call expression. The negative
 * lookbehind `(?<![A-Za-z0-9_$.])` excludes a MEMBER call like `RegExp.exec(` /
 * `re.exec(` (the JS `RegExp.prototype.exec` method, heavily used by the parsers)
 * — a real `child_process.exec(...)` is caught by the `child_process` token, and
 * a destructured `execSync(...)` is a bare call (no leading dot), so it still
 * matches.
 */
const CHILD_PROCESS_RE =
  /\bchild_process\b|(?<![A-Za-z0-9_$.])(?:exec|execSync|execFile|execFileSync|spawn|spawnSync|fork)\s*\(/;

/**
 * child_process IMPORT on the RAW (un-stripped) source — the binding catch.
 * No production file may import child_process at all, so any `from
 * 'node:child_process'` / `require('node:child_process')` IS a violation,
 * regardless of how the shell-out is later called (`cp.execSync(...)` member
 * form via a default/namespace import is otherwise missed: the token lives only
 * in the import-specifier string that stripComments blanks, and the member call
 * is excluded by the RegExp.exec negative-lookbehind). Matched on raw text so
 * the specifier string is intact.
 */
const CHILD_PROCESS_IMPORT_RE =
  /(?:from\s*['"](?:node:)?child_process['"]|require\(\s*['"](?:node:)?child_process['"]\s*\))/;

interface Hit {
  file: string;
  line: number;
  text: string;
  why: string;
}

/**
 * Scan one source for write-op call expressions. `stripped` is comment/string-
 * blanked (avoids JSDoc / string-literal false-positives for the call matchers);
 * `raw` is the original text, scanned ONLY for the child_process import (whose
 * token lives inside the import-specifier string that stripping would blank).
 */
function scanSource(relPath: string, stripped: string, raw: string = stripped): Hit[] {
  const hits: Hit[] = [];
  const lines = stripped.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (WRITE_CALL_RE.test(line)) {
      hits.push({ file: relPath, line: i + 1, text: line.trim(), why: 'fs-write' });
    }
    if (CHILD_PROCESS_RE.test(line)) {
      hits.push({ file: relPath, line: i + 1, text: line.trim(), why: 'child_process' });
    }
  }
  // child_process import detected on RAW text (catches default/namespace imports
  // whose member call form `cp.execSync(` the stripped-line matchers miss).
  const rawLines = raw.split('\n');
  for (let i = 0; i < rawLines.length; i++) {
    if (CHILD_PROCESS_IMPORT_RE.test(rawLines[i])) {
      hits.push({
        file: relPath,
        line: i + 1,
        text: rawLines[i].trim(),
        why: 'child_process-import',
      });
    }
  }
  return hits;
}

// ===========================================================================
// Tests
// ===========================================================================

describe('READ-ONLY INVARIANT (AC #8) — production source performs NO disk write', () => {
  const sources = collectProductionSources(SRC_ROOT);

  it('enumerates the production source set (excludes tests + fixtures)', () => {
    expect(sources.length).toBeGreaterThan(0);
    for (const f of sources) {
      expect(f.endsWith('.test.ts'), `test file leaked into scan: ${f}`).toBe(false);
      expect(f.includes('__fixtures__'), `fixture leaked into scan: ${f}`).toBe(false);
    }
  });

  it('finds ZERO filesystem-write / child_process call in production source', () => {
    const allHits: Hit[] = [];
    for (const abs of sources) {
      const rel = relative(SRC_ROOT, abs);
      const raw = readFileSync(abs, 'utf-8');
      const stripped = stripComments(raw);
      allHits.push(...scanSource(rel, stripped, raw));
    }

    if (allHits.length > 0) {
      const report = allHits
        .map((h) => `  ${h.file}:${h.line}  [${h.why}]  ${h.text}`)
        .join('\n');
      // Fail LOUDLY with file:line — the binding enforcement (§1).
      throw new Error(
        `READ-ONLY INVARIANT VIOLATED — ${allHits.length} write/exec op(s) in production source:\n${report}`,
      );
    }
    expect(allHits).toEqual([]);
  });

  // --- Meta-tests: prove the grep itself is sound (no false pos / false neg). ---

  it('does NOT match a write-op named only in a comment (false-positive guard)', () => {
    const sample = [
      '// this function never calls writeFile() or mkdir()',
      '/* appendFile is mentioned here in a block comment, unlinkSync too */',
      'const x = 1;',
    ].join('\n');
    const stripped = stripComments(sample);
    expect(scanSource('sample.ts', stripped)).toEqual([]);
  });

  it('does NOT match a write-op name used as a STRING literal (chokidar event)', () => {
    const sample = [
      "watcher.on('unlink', (p) => this.handle(p));",
      "const ev = 'rename';",
      'const list = ["mkdir", "writeFile"];',
    ].join('\n');
    const stripped = stripComments(sample);
    expect(scanSource('sample.ts', stripped)).toEqual([]);
  });

  it('DOES match a real fs write call expression (false-negative guard)', () => {
    const sample = [
      "import { writeFile } from 'node:fs/promises';",
      'await writeFile(path, data);',
      'fs.mkdirSync(dir, { recursive: true });',
      "execSync('rm -rf /');",
    ].join('\n');
    const stripped = stripComments(sample);
    const hits = scanSource('sample.ts', stripped);
    // writeFile call + mkdirSync call + execSync call (the import line has no `(`).
    const lines = hits.map((h) => h.line);
    expect(lines).toContain(2); // writeFile(
    expect(lines).toContain(3); // mkdirSync(
    expect(lines).toContain(4); // execSync(
    expect(hits.length).toBeGreaterThanOrEqual(3);
  });

  it('DOES match child_process via a default/namespace import + member call (CP2 gap regression)', () => {
    // The form a prior reviewer found MISSED: `import cp from 'node:child_process'`
    // then `cp.execSync(...)`. The member call is excluded by the RegExp.exec
    // negative-lookbehind, and the token lives only in the blanked specifier
    // string — so it is caught by the RAW-source import detector instead.
    const sample = [
      "import cp from 'node:child_process';", // 1 — the violation
      'const out = cp.execSync("git status");', // 2 — member call (lookbehind-excluded)
    ].join('\n');
    const stripped = stripComments(sample);
    const hits = scanSource('sample.ts', stripped, sample);
    expect(hits.some((h) => h.why === 'child_process-import' && h.line === 1)).toBe(true);
  });

  it('also catches `require("child_process")` and the bare `node:child_process`', () => {
    const a = scanSource('a.ts', stripComments("const cp = require('child_process');"), "const cp = require('child_process');");
    const b = scanSource('b.ts', stripComments("import { spawn } from 'node:child_process';"), "import { spawn } from 'node:child_process';");
    expect(a.some((h) => h.why === 'child_process-import')).toBe(true);
    expect(b.some((h) => h.why === 'child_process-import')).toBe(true);
  });

  it('preserves line numbers across multi-line block comments (accuracy guard)', () => {
    const sample = [
      '/* line1', // 1
      ' line2', // 2
      ' line3 */', // 3
      'await writeFile(p, d);', // 4 — the real hit
    ].join('\n');
    const stripped = stripComments(sample);
    const hits = scanSource('sample.ts', stripped);
    expect(hits).toHaveLength(1);
    expect(hits[0].line).toBe(4);
  });
});
