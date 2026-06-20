/**
 * Container <-> host path normalization test suite (EPIC E-047-2_7, Step 3).
 *
 * Covers spec §9.6 / risk #18: roots are injected, never hardcoded; leading
 * root segment is replaced while the remainder is preserved; translation is
 * idempotent, identity-safe, and prefix-collision-safe.
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, it, expect } from 'vitest';
import { createPathMap, DEFAULT_HOST_ROOT } from './pathmap.js';

const CONTAINER = { projectsRoot: '/projects', hostRoot: '/opt/eco/projects' };

// ---------------------------------------------------------------------------
// AC1 — hostToContainer rewrites the leading root, preserves the remainder
// ---------------------------------------------------------------------------

describe('AC1 — hostToContainer rewrites leading root', () => {
  it('maps a host evidence path into the container projectsRoot', () => {
    const map = createPathMap(CONTAINER);
    expect(map.hostToContainer('/opt/eco/projects/acta/.aid-o/work/timeline.jsonl')).toBe(
      '/projects/acta/.aid-o/work/timeline.jsonl',
    );
  });

  it('maps the bare host root to the bare container root', () => {
    const map = createPathMap(CONTAINER);
    expect(map.hostToContainer('/opt/eco/projects')).toBe('/projects');
  });
});

// ---------------------------------------------------------------------------
// AC2 — containerToHost is the exact inverse for paths under the root
// ---------------------------------------------------------------------------

describe('AC2 — containerToHost is the exact inverse', () => {
  it('round-trips host -> container -> host', () => {
    const map = createPathMap(CONTAINER);
    const host = '/opt/eco/projects/acta/.aid-o/work/evidence/E-1/R-1/timeline.jsonl';
    expect(map.containerToHost(map.hostToContainer(host))).toBe(host);
  });

  it('containerToHost rewrites a container path back to host', () => {
    const map = createPathMap(CONTAINER);
    expect(map.containerToHost('/projects/krok/.aid-o/work/run.md')).toBe(
      '/opt/eco/projects/krok/.aid-o/work/run.md',
    );
  });
});

// ---------------------------------------------------------------------------
// AC3 — a path outside both roots is returned unchanged (no throw)
// ---------------------------------------------------------------------------

describe('AC3 — paths outside both roots pass through untouched', () => {
  it('returns an unrelated absolute path unchanged for both directions', () => {
    const map = createPathMap(CONTAINER);
    const outside = '/var/lib/docker/volumes/foo/bar';
    expect(map.hostToContainer(outside)).toBe(outside);
    expect(map.containerToHost(outside)).toBe(outside);
  });

  it('does not throw and does not partially mangle a near-miss path', () => {
    const map = createPathMap(CONTAINER);
    // contains the root string mid-path but is not rooted there
    const tricky = '/home/user/opt/eco/projects/acta/file.txt';
    expect(() => map.hostToContainer(tricky)).not.toThrow();
    expect(map.hostToContainer(tricky)).toBe(tricky);
  });
});

// ---------------------------------------------------------------------------
// AC4 — spec-required: an embedded absolute evidence_dir resolves correctly
// ---------------------------------------------------------------------------

describe('AC4 — embedded host evidence_dir resolves to container path', () => {
  it('resolves a §9.6 fixture evidence_dir through hostToContainer', () => {
    const map = createPathMap(CONTAINER);
    const evidenceDir =
      '/opt/eco/projects/krok/.aid-o/work/evidence/E-1/R-1/timeline.jsonl';
    expect(map.hostToContainer(evidenceDir)).toBe(
      '/projects/krok/.aid-o/work/evidence/E-1/R-1/timeline.jsonl',
    );
  });
});

// ---------------------------------------------------------------------------
// AC5 — ZERO `/opt/eco/projects` literal in the translation logic
// ---------------------------------------------------------------------------

describe('AC5 — no hardcoded host root in the translation logic', () => {
  it('only references /opt/eco/projects in the labelled DEFAULT_HOST_ROOT constant', () => {
    const src = readFileSync(
      fileURLToPath(new URL('./pathmap.ts', import.meta.url)),
      'utf-8',
    );
    // Strip comments so the doc references in the header are not counted.
    const code = src
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/\/\/.*$/gm, '');
    const occurrences = code.match(/\/opt\/eco\/projects/g) ?? [];
    // Exactly one occurrence allowed: the DEFAULT_HOST_ROOT default constant.
    expect(occurrences).toHaveLength(1);
    expect(code).toContain("DEFAULT_HOST_ROOT = '/opt/eco/projects'");
  });

  it('exposes the default as a clearly-named constant, not embedded logic', () => {
    expect(DEFAULT_HOST_ROOT).toBe('/opt/eco/projects');
  });
});

// ---------------------------------------------------------------------------
// AC6 — host-native dev (hostRoot === projectsRoot) is an identity no-op
// ---------------------------------------------------------------------------

describe('AC6 — identity no-op when hostRoot === projectsRoot', () => {
  it('returns every path unchanged in both directions', () => {
    const map = createPathMap({
      projectsRoot: DEFAULT_HOST_ROOT,
      hostRoot: DEFAULT_HOST_ROOT,
    });
    const p = '/opt/eco/projects/acta/.aid-o/work/run.md';
    expect(map.hostToContainer(p)).toBe(p);
    expect(map.containerToHost(p)).toBe(p);
  });
});

// ---------------------------------------------------------------------------
// AC7 — prefix-collision safety
// ---------------------------------------------------------------------------

describe('AC7 — prefix-collision safety on segment boundary', () => {
  it('does not rewrite /projects-backup when projectsRoot is /projects', () => {
    const map = createPathMap(CONTAINER);
    expect(map.containerToHost('/projects-backup/x')).toBe('/projects-backup/x');
  });

  it('does not rewrite /opt/eco/projects-old when hostRoot is /opt/eco/projects', () => {
    const map = createPathMap(CONTAINER);
    expect(map.hostToContainer('/opt/eco/projects-old/x')).toBe('/opt/eco/projects-old/x');
  });
});

// ---------------------------------------------------------------------------
// Extra — idempotency and trailing-slash robustness
// ---------------------------------------------------------------------------

describe('idempotency and trailing-slash robustness', () => {
  it('hostToContainer applied twice equals applied once (idempotent)', () => {
    const map = createPathMap(CONTAINER);
    const once = map.hostToContainer('/opt/eco/projects/acta/file.txt');
    expect(map.hostToContainer(once)).toBe(once);
    expect(once).toBe('/projects/acta/file.txt');
  });

  it('tolerates a trailing slash on the configured roots', () => {
    const map = createPathMap({ projectsRoot: '/projects/', hostRoot: '/opt/eco/projects/' });
    expect(map.hostToContainer('/opt/eco/projects/acta/file.txt')).toBe(
      '/projects/acta/file.txt',
    );
  });
});
