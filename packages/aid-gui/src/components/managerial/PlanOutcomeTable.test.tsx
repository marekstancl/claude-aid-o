/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import type { PlanOutcomeAnalytics, PlanOutcomeSummary, PlanOutcome } from '@aid/contract';
import { PlanOutcomeTable, buildFilteredAnalytics, OUTCOME_WEIGHT } from './PlanOutcomeTable';

// ── builders ─────────────────────────────────────────────────────────────────

function plan(over: Partial<PlanOutcomeSummary> & { planId: string; outcome: PlanOutcome }): PlanOutcomeSummary {
  return {
    projectId: over.projectId ?? 'wan',
    planId: over.planId,
    ambiguousNumber: over.ambiguousNumber ?? false,
    title: over.title ?? over.planId,
    outcome: over.outcome,
    epicsTotal: over.epicsTotal ?? 3,
    epicsDone: over.epicsDone ?? 1,
    runsTotal: over.runsTotal ?? 5,
    failedRuns: over.failedRuns ?? 0,
    gateFailures: over.gateFailures ?? 0,
    gateRetries: over.gateRetries ?? 0,
    checkpointRetries: over.checkpointRetries ?? { knownTotal: 0, unknownCheckpoints: 0 },
    fsmFailures: over.fsmFailures ?? { precondition: 0, increment: 0, doneAdvance: 0, other: 0 },
    escalations: over.escalations ?? 0,
    forceOverrides: over.forceOverrides ?? 0,
    compliance: over.compliance ?? { passed: 0, failed: 0, unknown: 0 },
    topFailureReasons: over.topFailureReasons ?? [],
    firstStartedAt: over.firstStartedAt ?? null,
    lastCompletedAt: over.lastCompletedAt ?? null,
    lastActivityAt: over.lastActivityAt ?? null,
    dataPartial: over.dataPartial ?? false,
    warnings: over.warnings ?? [],
  };
}

function analytics(plans: PlanOutcomeSummary[]): PlanOutcomeAnalytics {
  return {
    generatedAt: '2026-06-20T12:00:00Z',
    plans,
    totals: {
      plans: plans.length,
      passed: 0,
      partial: 0,
      failed: 0,
      inProgress: 0,
      unverifiable: 0,
      failedRuns: 0,
      gateFailures: 0,
      gateRetries: 0,
      escalations: 0,
      forceOverrides: 0,
    },
    partialProjects: [],
  };
}

function renderTable(a: PlanOutcomeAnalytics) {
  return render(
    <MemoryRouter>
      <PlanOutcomeTable analytics={a} />
    </MemoryRouter>,
  );
}

// ── outcome → status text + icon mapping ──────────────────────────────────────

describe('PlanOutcomeTable — §13.12 outcome mapping', () => {
  const cases: { outcome: PlanOutcome; word: string }[] = [
    { outcome: 'failed', word: 'selhalo' },
    { outcome: 'partial', word: 'pozor' },
    { outcome: 'in_progress', word: 'běží' },
    { outcome: 'unverifiable', word: 'čeká' },
    { outcome: 'passed', word: 'prošlo' },
  ];

  it.each(cases)('renders outcome "$outcome" with word "$word" + an icon', ({ outcome, word }) => {
    const { container } = renderTable(analytics([plan({ planId: `P1-${outcome}`, outcome })]));
    const row = container.querySelector(`[data-plan-row="P1-${outcome}"]`) as HTMLElement;
    expect(row).toBeInTheDocument();
    expect(row).toHaveTextContent(word);
    // text+icon: the StatusBadge carries an svg glyph (never colour alone).
    expect(row.querySelector('[data-status] svg')).toBeInTheDocument();
  });

  it('member-less plans (outcome:unverifiable) still render a row', () => {
    const { container } = renderTable(
      analytics([plan({ planId: 'P9-empty', outcome: 'unverifiable', epicsTotal: 0, epicsDone: 0 })]),
    );
    expect(container.querySelector('[data-plan-row="P9-empty"]')).toBeInTheDocument();
  });
});

// ── attention-first ordering ──────────────────────────────────────────────────

describe('PlanOutcomeTable — attention-first ordering', () => {
  it('sorts failed → partial → in_progress → unverifiable → passed', () => {
    const { container } = renderTable(
      analytics([
        plan({ planId: 'P-pass', outcome: 'passed' }),
        plan({ planId: 'P-fail', outcome: 'failed' }),
        plan({ planId: 'P-partial', outcome: 'partial' }),
      ]),
    );
    const order = [...container.querySelectorAll('[data-plan-row]')].map((r) =>
      r.getAttribute('data-plan-row'),
    );
    expect(order).toEqual(['P-fail', 'P-partial', 'P-pass']);
    // Weight invariant.
    expect(OUTCOME_WEIGHT.failed).toBeLessThan(OUTCOME_WEIGHT.passed);
  });
});

// ── filters ───────────────────────────────────────────────────────────────────

describe('PlanOutcomeTable — filters', () => {
  it('filters by project', () => {
    const { container } = render(
      <MemoryRouter>
        <PlanOutcomeTable
          analytics={analytics([
            plan({ planId: 'P-wan', projectId: 'wan', outcome: 'passed' }),
            plan({ planId: 'P-krok', projectId: 'krok', outcome: 'passed' }),
          ])}
        />
      </MemoryRouter>,
    );
    const select = container.querySelector('[data-filter-project]') as HTMLSelectElement;
    // Both visible by default.
    expect(container.querySelector('[data-plan-row="P-wan"]')).toBeInTheDocument();
    expect(container.querySelector('[data-plan-row="P-krok"]')).toBeInTheDocument();
    // Filter to krok.
    fireEvent.change(select, { target: { value: 'krok' } });
    expect(container.querySelector('[data-plan-row="P-krok"]')).toBeInTheDocument();
    expect(container.querySelector('[data-plan-row="P-wan"]')).toBeNull();
  });

  it('filters by outcome', () => {
    const { container } = renderTable(
      analytics([
        plan({ planId: 'P-fail', outcome: 'failed' }),
        plan({ planId: 'P-pass', outcome: 'passed' }),
      ]),
    );
    const select = container.querySelector('[data-filter-outcome]') as HTMLSelectElement;
    fireEvent.change(select, { target: { value: 'failed' } });
    expect(container.querySelector('[data-plan-row="P-fail"]')).toBeInTheDocument();
    expect(container.querySelector('[data-plan-row="P-pass"]')).toBeNull();
  });
});

// ── JSON export ───────────────────────────────────────────────────────────────

describe('PlanOutcomeTable — JSON export (client-side, no server write)', () => {
  it('buildFilteredAnalytics recomputes totals over the filtered rows', () => {
    const rows = [
      plan({ planId: 'P-fail', outcome: 'failed', failedRuns: 2, escalations: 1 }),
      plan({ planId: 'P-pass', outcome: 'passed', failedRuns: 0 }),
    ];
    const payload = buildFilteredAnalytics(analytics(rows), [rows[0]]);
    expect(payload.plans).toHaveLength(1);
    expect(payload.plans[0].planId).toBe('P-fail');
    expect(payload.totals.plans).toBe(1);
    expect(payload.totals.failed).toBe(1);
    expect(payload.totals.passed).toBe(0);
    expect(payload.totals.failedRuns).toBe(2);
    expect(payload.totals.escalations).toBe(1);
  });

  it('clicking Export builds a Blob URL and never writes to a server', () => {
    const created: Blob[] = [];
    const createObjectURL = vi.fn((b: Blob) => {
      created.push(b);
      return 'blob:mock';
    });
    const revokeObjectURL = vi.fn();
    // jsdom lacks URL.createObjectURL — install mocks.
    (URL as unknown as { createObjectURL: typeof createObjectURL }).createObjectURL = createObjectURL;
    (URL as unknown as { revokeObjectURL: typeof revokeObjectURL }).revokeObjectURL = revokeObjectURL;
    const fetchSpy = vi.fn();
    vi.stubGlobal('fetch', fetchSpy);
    const clickSpy = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});

    const { container } = renderTable(analytics([plan({ planId: 'P-1', outcome: 'failed' })]));
    const btn = container.querySelector('[data-export-json]') as HTMLButtonElement;
    btn.click();

    expect(createObjectURL).toHaveBeenCalledTimes(1);
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:mock');
    expect(clickSpy).toHaveBeenCalled();
    // No network write of any kind.
    expect(fetchSpy).not.toHaveBeenCalled();

    clickSpy.mockRestore();
    vi.unstubAllGlobals();
  });
});

// ── unknown retry / proof honesty ─────────────────────────────────────────────

describe('PlanOutcomeTable — unknown retry rendering', () => {
  it('renders unknownCheckpoints > 0 as a visible "?" warning, never substituting 0/pass', () => {
    const { container } = renderTable(
      analytics([
        plan({
          planId: 'P-unknown',
          outcome: 'partial',
          checkpointRetries: { knownTotal: 1, unknownCheckpoints: 2 },
        }),
      ]),
    );
    const cell = container.querySelector('[data-retry="unknown"]') as HTMLElement;
    expect(cell).toBeInTheDocument();
    expect(cell).toHaveTextContent('?');
    expect(cell.getAttribute('title')).toContain('část CP opakování není dohledatelná');
  });

  it('renders a fully-known retry total as a plain number (no "?")', () => {
    const { container } = renderTable(
      analytics([
        plan({
          planId: 'P-known',
          outcome: 'passed',
          checkpointRetries: { knownTotal: 4, unknownCheckpoints: 0 },
        }),
      ]),
    );
    expect(container.querySelector('[data-retry="unknown"]')).toBeNull();
    const row = container.querySelector('[data-plan-row="P-known"]') as HTMLElement;
    expect(row).toHaveTextContent('4');
  });
});

// ── mobile cards ──────────────────────────────────────────────────────────────

describe('PlanOutcomeTable — mobile cards', () => {
  const realMatchMedia = window.matchMedia;
  beforeEach(() => {
    // Force the mobile branch (useIsMobile → matchMedia matches).
    window.matchMedia = vi.fn().mockImplementation((query: string) => ({
      matches: true,
      media: query,
      onchange: null,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      addListener: vi.fn(),
      removeListener: vi.fn(),
      dispatchEvent: vi.fn(),
    }));
  });
  afterEach(() => {
    // Restore the desktop default so later describes are unaffected.
    window.matchMedia = realMatchMedia;
    vi.restoreAllMocks();
  });

  it('renders cards (not a table) on mobile', () => {
    const { container } = renderTable(analytics([plan({ planId: 'P-m', outcome: 'failed' })]));
    expect(container.querySelector('[data-plan-outcome-cards]')).toBeInTheDocument();
    expect(container.querySelector('[data-plan-outcome-table]')).toBeNull();
    expect(container.querySelector('[data-plan-card="P-m"]')).toBeInTheDocument();
  });
});

// ── STEM-primary identity (contract drift, Phases 1-4 REOPEN) ─────────────────

describe('PlanOutcomeTable — STEM-primary identity', () => {
  it('two plans sharing a number but distinct stems render as DISTINCT rows keyed by stem', () => {
    const { container } = renderTable(
      analytics([
        plan({ planId: 'P046-foo', projectId: 'wan', outcome: 'failed', ambiguousNumber: true }),
        plan({ planId: 'P046-bar', projectId: 'krok', outcome: 'passed', ambiguousNumber: true }),
      ]),
    );
    const fooRow = container.querySelector('[data-plan-row="P046-foo"]');
    const barRow = container.querySelector('[data-plan-row="P046-bar"]');
    expect(fooRow).toBeInTheDocument();
    expect(barRow).toBeInTheDocument();
    expect(fooRow).not.toBe(barRow);
    // Two distinct rows — the colliding number did NOT collapse them.
    expect(container.querySelectorAll('[data-plan-row]')).toHaveLength(2);
  });

  it('an ambiguousNumber:true row shows a visible marker', () => {
    const { container } = renderTable(
      analytics([plan({ planId: 'P046-foo', outcome: 'failed', ambiguousNumber: true })]),
    );
    const marker = container.querySelector('[data-plan-row="P046-foo"] [data-ambiguous-number]');
    expect(marker).toBeInTheDocument();
    expect(marker).toHaveTextContent('dvojí číslo');
  });

  it('an unambiguous row shows NO ambiguity marker', () => {
    const { container } = renderTable(
      analytics([plan({ planId: 'P050-solo', outcome: 'passed', ambiguousNumber: false })]),
    );
    expect(
      container.querySelector('[data-plan-row="P050-solo"] [data-ambiguous-number]'),
    ).toBeNull();
  });

  it("the row's plan link href uses the STEM, never the bare number", () => {
    const { container } = renderTable(
      analytics([plan({ planId: 'P046-foo', projectId: 'wan', outcome: 'failed', ambiguousNumber: true })]),
    );
    const link = container.querySelector('[data-plan-link]') as HTMLAnchorElement;
    expect(link).toHaveAttribute('data-stem', 'P046-foo');
    // The href carries the full stem (URL-encoded), not the bare "P046".
    expect(link.getAttribute('href')).toContain('P046-foo');
    expect(link.getAttribute('href')).not.toMatch(/\/plan\/P046$/);
    // It MUST target the real router route `/p/:project/plans/:planId` (plural).
    // The earlier singular `/p/:project/plan/:stem` 404'd — this pins the prefix.
    expect(link.getAttribute('href')).toMatch(/^\/p\/wan\/plans\//);
  });
});
