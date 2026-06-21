/**
 * Explanations (dictionary) route tests (EPIC E-047-4_7, Step 1).
 *
 * Drives the Express app via supertest (no real port). Covers:
 *   - AC2: GET /api/explanations?lang=cs → 200 with a non-empty
 *          Record<string, DictionaryEntry>, including the §13.10 concept keys,
 *          each with all DictionaryEntry fields populated.
 *   - AC3: an unknown `lang` returns the `cs` map with a `meta.warnings` note
 *          (graceful fallback, NOT 404).
 */

import { describe, it, expect } from 'vitest';
import request from 'supertest';
import type { DictionaryEntry } from '@aid/contract';
import { createApp } from '../index.js';
import { loadConfig, type ServerConfig } from '../config.js';

function testConfig(): ServerConfig {
  const root = '/tmp/does-not-matter';
  return { ...loadConfig(), projectsRoot: root, hostRoot: root };
}

/** The §13.10 managerial concept keys that power the read-model tooltips. */
const REQUIRED_CONCEPT_KEYS = [
  'concept:risk:vysoke',
  'concept:stale_run',
  'concept:decision_needed',
  'concept:success_probability_mvp2',
] as const;

/** All seven DictionaryEntry fields (the contract's full content shape). */
const ENTRY_FIELDS: (keyof DictionaryEntry)[] = [
  'id',
  'kind',
  'status',
  'headlineTemplate',
  'detailTemplate',
  'term',
  'keywords',
];

describe('explanations route (E-047-4_7 Step 1)', () => {
  it('AC2 — GET /api/explanations?lang=cs returns a non-empty dictionary, no meta', async () => {
    const app = createApp(testConfig(), undefined as never);
    const res = await request(app).get('/api/explanations?lang=cs');

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.meta).toBeUndefined();

    const dict = res.body.data as Record<string, DictionaryEntry>;
    expect(typeof dict).toBe('object');
    expect(Object.keys(dict).length).toBeGreaterThan(0);
  });

  it('AC2 — includes the §13.10 concept keys with all DictionaryEntry fields populated', async () => {
    const app = createApp(testConfig(), undefined as never);
    const res = await request(app).get('/api/explanations?lang=cs');
    const dict = res.body.data as Record<string, DictionaryEntry>;

    for (const key of REQUIRED_CONCEPT_KEYS) {
      const entry = dict[key];
      expect(entry, `missing concept key "${key}"`).toBeDefined();

      // Every field present and non-empty.
      for (const field of ENTRY_FIELDS) {
        expect(entry[field], `${key}.${field} missing`).toBeDefined();
      }
      expect(entry.kind).toBe('concept');
      expect(typeof entry.id).toBe('string');
      expect(entry.id.length).toBeGreaterThan(0);
      expect(typeof entry.status).toBe('string');
      expect(entry.status.length).toBeGreaterThan(0);
      expect(typeof entry.headlineTemplate).toBe('string');
      expect(entry.headlineTemplate.length).toBeGreaterThan(0);
      expect(typeof entry.detailTemplate).toBe('string');
      expect(entry.detailTemplate.length).toBeGreaterThan(0);
      expect(typeof entry.term).toBe('string');
      expect(entry.term.length).toBeGreaterThan(0);
      expect(Array.isArray(entry.keywords)).toBe(true);
      expect(entry.keywords.length).toBeGreaterThan(0);
    }
  });

  it('AC2 — default (no lang param) also returns the cs dictionary, no meta', async () => {
    const app = createApp(testConfig(), undefined as never);
    const res = await request(app).get('/api/explanations');

    expect(res.status).toBe(200);
    expect(res.body.meta).toBeUndefined();
    const dict = res.body.data as Record<string, DictionaryEntry>;
    expect(dict['concept:risk:vysoke']).toBeDefined();
  });

  it('AC3 — unknown lang returns the cs map with a meta.warnings note (NOT 404)', async () => {
    const app = createApp(testConfig(), undefined as never);
    const res = await request(app).get('/api/explanations?lang=de');

    // Graceful fallback — NOT a 404.
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    // Same cs content.
    const dict = res.body.data as Record<string, DictionaryEntry>;
    expect(dict['concept:risk:vysoke']).toBeDefined();

    // meta.warnings present and mentions the requested + served language.
    expect(res.body.meta).toBeDefined();
    expect(Array.isArray(res.body.meta.warnings)).toBe(true);
    expect(res.body.meta.warnings.length).toBeGreaterThan(0);
    expect(res.body.meta.warnings[0]).toContain('de');
    expect(res.body.meta.warnings[0]).toContain('cs');
  });

  it('AC3 — fallback dictionary is identical to the cs dictionary', async () => {
    const app = createApp(testConfig(), undefined as never);
    const [cs, unknown] = await Promise.all([
      request(app).get('/api/explanations?lang=cs'),
      request(app).get('/api/explanations?lang=xx'),
    ]);

    expect(unknown.body.data).toEqual(cs.body.data);
  });
});
