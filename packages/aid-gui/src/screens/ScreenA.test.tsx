/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type {
  Project,
  ActivityEvent,
  PlanOutcomeAnalytics,
  PlanOutcomeSummary,
  PlanOutcome,
  DictionaryEntry,
} from '@aid/contract';
import { ScreenA } from './ScreenA';
import * as api from '../lib/api';

vi.mock('../lib/api', () => ({
  getProjects: vi.fn(),
  getActivity: vi.fn(),
  getPlanOutcomes: vi.fn(),
  getExplanations: vi.fn(),
}));

const getProjects = vi.mocked(api.getProjects);
const getActivity = vi.mocked(api.getActivity);
const getPlanOutcomes = vi.mocked(api.getPlanOutcomes);
const getExplanations = vi.mocked(api.getExplanations);

// ── fixtures ──────────────────────────────────────────────────────────────────

/** The six real projects from the §Step-42 edge-case fixture. */
const SIX_PROJECTS = ['krok', 'sousto-na-miru', 'wan', 'acta', 'aid-orchestrator', 'vulcan'];

function makeProject(id: string, over: Partial<Project> = {}): Project {
  return {
    id,
    name: id,
    path: `/${id}`,
    aidoPath: `/${id}/.aid-o`,
    discovered: true,
    partial: false,
    epicsTotal: 0,
    epicsActive: 0,
    runsTotal: 0,
    activeRun: null,
    health: {
      value: null,
      partial: false,
      confidence: 'low',
      compliancePassRate: null,
      openViolations: 0,
      lastGateOverall: null,
      warnings: [],
    },
    lastActivityAt: null,
    ...over,
  };
}

/** The 6-project fixture: a mix of active / idle / violations / partial. */
function sixProjectFixture(): Project[] {
  return [
    makeProject('krok', {
      runsTotal: 12,
      activeRun: { epicId: 'E-101', runId: 'r1', state: 'EXECUTE' },
    }),
    makeProject('sousto-na-miru', { runsTotal: 30, health: idleHealth(3) }),
    makeProject('wan', {
      runsTotal: 8,
      activeRun: { epicId: 'E-202', runId: 'r2', state: 'DONE' }, // waiting on PM
    }),
    makeProject('acta', { runsTotal: 0, partial: true }),
    makeProject('aid-orchestrator', { runsTotal: 5, lastActivityAt: '2026-06-20T08:00:00.000Z' }),
    makeProject('vulcan', { runsTotal: 4 }),
  ];
}

function idleHealth(openViolations: number): Project['health'] {
  return {
    value: null,
    partial: false,
    confidence: 'low',
    compliancePassRate: null,
    openViolations,
    lastGateOverall: null,
    warnings: [],
  };
}

function makeEvent(over: Partial<ActivityEvent> = {}): ActivityEvent {
  return {
    projectId: 'krok',
    ts: '2026-06-20T10:00:00.000Z',
    event: 'fsm_transition',
    raw: {},
    ...over,
  };
}

function makePlan(over: Partial<PlanOutcomeSummary> = {}): PlanOutcomeSummary {
  return {
    projectId: 'krok',
    planId: 'P046-foo',
    ambiguousNumber: false,
    title: 'Foo plan',
    outcome: 'passed',
    epicsTotal: 3,
    epicsDone: 3,
    runsTotal: 3,
    failedRuns: 0,
    gateFailures: 0,
    gateRetries: 0,
    checkpointRetries: { knownTotal: 0, unknownCheckpoints: 0 },
    fsmFailures: { precondition: 0, increment: 0, doneAdvance: 0, other: 0 },
    escalations: 0,
    forceOverrides: 0,
    compliance: { passed: 3, failed: 0, unknown: 0 },
    topFailureReasons: [],
    firstStartedAt: null,
    lastCompletedAt: null,
    lastActivityAt: '2026-06-20T09:00:00.000Z',
    dataPartial: false,
    warnings: [],
    ...over,
  };
}

/** One plan per outcome → exercises all five outcome labels. */
function fiveOutcomePlans(): PlanOutcomeSummary[] {
  const outcomes: PlanOutcome[] = ['passed', 'partial', 'failed', 'in_progress', 'unverifiable'];
  return outcomes.map((outcome, i) =>
    makePlan({ planId: `P${100 + i}-${outcome}`, projectId: SIX_PROJECTS[i], outcome }),
  );
}

function makeAnalytics(over: Partial<PlanOutcomeAnalytics> = {}): PlanOutcomeAnalytics {
  const plans = over.plans ?? fiveOutcomePlans();
  return {
    generatedAt: '2026-06-20T10:00:00.000Z',
    plans,
    totals: {
      plans: plans.length,
      passed: plans.filter((p) => p.outcome === 'passed').length,
      partial: plans.filter((p) => p.outcome === 'partial').length,
      failed: plans.filter((p) => p.outcome === 'failed').length,
      inProgress: plans.filter((p) => p.outcome === 'in_progress').length,
      unverifiable: plans.filter((p) => p.outcome === 'unverifiable').length,
      failedRuns: 0,
      gateFailures: 0,
      gateRetries: 0,
      escalations: 0,
      forceOverrides: 0,
    },
    partialProjects: [],
    ...over,
  };
}

function makeDict(): Record<string, DictionaryEntry> {
  return {
    'event:fsm_transition': {
      id: 'event:fsm_transition',
      kind: 'event',
      status: 'bezi',
      headlineTemplate: 'Změna stavu',
      detailTemplate: 'Stav se změnil.',
      term: 'Přechod stavu',
      keywords: [],
    },
  };
}

// ── harness ─────────────────────────────────────────────────────────────────

function renderScreen() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={['/prehled']}>
        <ScreenA />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  getProjects.mockResolvedValue(sixProjectFixture());
  getActivity.mockResolvedValue([]);
  getPlanOutcomes.mockResolvedValue(makeAnalytics());
  getExplanations.mockResolvedValue(makeDict());
});
afterEach(() => vi.restoreAllMocks());

// ── AC 1: exactly 6 tiles ───────────────────────────────────────────────────

describe('ScreenA — project tiles', () => {
  it('renders exactly 6 tiles for the 6-project fixture', async () => {
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelectorAll('[data-project-tile]')).toHaveLength(6),
    );
    for (const id of SIX_PROJECTS) {
      expect(container.querySelector(`[data-project-tile="${id}"]`)).toBeInTheDocument();
    }
  });

  // AC 2: each tile shows its StatusBadge token + active-EPIC / progress, links to /p/:id.
  it('each tile renders status + active-EPIC and links to /p/:id', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-project-tile="krok"]')).toBeInTheDocument());

    // Active project (krok) → active variant, its EPIC id, a progress strip, link.
    const krok = container.querySelector('[data-project-tile="krok"]') as HTMLAnchorElement;
    expect(krok).toHaveAttribute('data-variant', 'active');
    expect(krok).toHaveAttribute('href', '/p/krok');
    expect(krok).toHaveTextContent('E-101');

    // Idle project (vulcan) → idle variant, "nečinné", lifetime run count, link.
    const vulcan = container.querySelector('[data-project-tile="vulcan"]') as HTMLAnchorElement;
    expect(vulcan).toHaveAttribute('data-variant', 'idle');
    expect(vulcan).toHaveAttribute('href', '/p/vulcan');
    expect(vulcan).toHaveTextContent('nečinné');
    expect(vulcan).toHaveTextContent('4');
  });

  it('a partial project still renders a tile (never thrown)', async () => {
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-project-tile="acta"]')).toBeInTheDocument(),
    );
  });
});

// ── header summary line ─────────────────────────────────────────────────────

describe('ScreenA — header summary', () => {
  it('aggregates count / runs / running / PM-waiting / violations null-safely', async () => {
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-summary]')).toHaveTextContent(/6 projektů/),
    );

    const summary = container.querySelector('[data-summary]') as HTMLElement;
    // 6 projects.
    expect(summary).toHaveTextContent(/6 projektů/);
    // runsTotal = 12+30+8+0+5+4 = 59.
    expect(summary).toHaveTextContent(/59 běhů/);
    // running = krok (EXECUTE) only = 1. A DONE run is NOT "běží" — it is finished
    // and awaiting PM, so it must NOT inflate the running count (FSM_STATUS: only
    // EXECUTE/GATES → bezi).
    expect(summary).toHaveTextContent(/1 běží/);
    expect(summary).not.toHaveTextContent(/2 běží/);
    // PM-waiting = wan (DONE) = 1.
    expect(summary).toHaveTextContent(/1 čeká na PM/);
    // open violations = sousto's 3.
    expect(summary).toHaveTextContent(/3 porušení/);
  });

  it('renders the InstallPwaButton slot in the header (null when not eligible)', async () => {
    renderScreen();
    // No beforeinstallprompt fired → button is null; header still renders.
    await waitFor(() => expect(screen.getByRole('heading', { name: 'Přehled' })).toBeInTheDocument());
  });
});

// ── AC 4: plan-outcome section ──────────────────────────────────────────────

describe('ScreenA — Výsledky plánů', () => {
  it('renders all five fixture plans with all five outcome labels, totals, filters and export', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-plan-outcome-table]')).toBeInTheDocument());

    // One row per plan (5).
    expect(container.querySelectorAll('[data-plan-row]')).toHaveLength(5);

    // All five outcome labels present (StatusBadge words).
    for (const label of ['prošlo', 'pozor', 'selhalo', 'běží', 'čeká']) {
      expect(screen.getAllByText(label).length).toBeGreaterThan(0);
    }

    // Compact totals strip above the table — five honest buckets.
    const totals = container.querySelector('[data-plan-totals]') as HTMLElement;
    expect(totals).toBeInTheDocument();
    expect(totals.querySelector('[data-total="passed"]')).toHaveTextContent('1');
    expect(totals.querySelector('[data-total="unverifiable"]')).toHaveTextContent('1');

    // Filters + export affordances come from the reused PlanOutcomeTable.
    expect(container.querySelector('[data-filter-project]')).toBeInTheDocument();
    expect(container.querySelector('[data-filter-outcome]')).toBeInTheDocument();
    expect(container.querySelector('[data-export-json]')).toBeInTheDocument();

    // Plan links are STEM-primary and point at /p/:project/plans/:stem.
    const link = container.querySelector('[data-plan-link]') as HTMLAnchorElement;
    expect(link.getAttribute('href')).toMatch(/^\/p\/[^/]+\/plans\//);
  });

  it('keeps an "unverifiable" plan in the totals (never coerced to 0 / pass)', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-plan-totals]')).toBeInTheDocument());
    const totals = container.querySelector('[data-plan-totals]') as HTMLElement;
    // It stays its own honest bucket, distinct from passed.
    expect(totals.querySelector('[data-total="unverifiable"]')).toHaveTextContent('1');
    expect(within(container.querySelector('[data-plan-outcome-table]') as HTMLElement).getByText('čeká')).toBeInTheDocument();
  });

  it('shows a partial-coverage warning band naming affected projects', async () => {
    getPlanOutcomes.mockResolvedValue(makeAnalytics({ partialProjects: ['wan', 'acta'] }));
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-outcomes-partial]')).toBeInTheDocument());
    expect(container.querySelector('[data-outcomes-partial]')).toHaveTextContent('wan');
    expect(container.querySelector('[data-outcomes-partial]')).toHaveTextContent('acta');
  });
});

// ── mini live feed ──────────────────────────────────────────────────────────

describe('ScreenA — Děje se teď mini feed', () => {
  it('renders up to 5 narrated EventRows from getActivity({limit:5})', async () => {
    const events = Array.from({ length: 5 }, (_, i) =>
      makeEvent({ ts: `2026-06-20T10:0${i}:00.000Z`, projectId: SIX_PROJECTS[i] }),
    );
    getActivity.mockResolvedValue(events);

    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-activity-feed]')).toBeInTheDocument());

    expect(getActivity).toHaveBeenCalledWith({ limit: 5 });
    const feed = container.querySelector('[data-activity-feed]') as HTMLElement;
    expect(feed.querySelectorAll('[data-event]')).toHaveLength(5);
  });

  it('renders an honest empty state when the feed is empty', async () => {
    getActivity.mockResolvedValue([]);
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-activity-empty]')).toBeInTheDocument());
  });
});

// ── error handling ──────────────────────────────────────────────────────────

describe('ScreenA — error handling', () => {
  it('projects failure → error surface, but plan outcomes stay usable', async () => {
    getProjects.mockRejectedValue(new Error('boom'));
    const { container } = renderScreen();

    await waitFor(() => expect(container.querySelector('[data-projects-error]')).toBeInTheDocument());
    expect(screen.getByText(/Seznam projektů se nepodařilo načíst/)).toBeInTheDocument();

    // The analytics query is independent — the table still renders.
    await waitFor(() => expect(container.querySelector('[data-plan-outcome-table]')).toBeInTheDocument());
  });

  it('analytics failure → its own error surface, tiles stay usable', async () => {
    getPlanOutcomes.mockRejectedValue(new Error('boom'));
    const { container } = renderScreen();

    await waitFor(() => expect(container.querySelector('[data-outcomes-error]')).toBeInTheDocument());
    expect(screen.getByText(/Výsledky plánů se nepodařilo načíst/)).toBeInTheDocument();

    // Tiles survive an analytics failure (independent /api/projects query).
    expect(container.querySelectorAll('[data-project-tile]')).toHaveLength(6);
  });
});

// ── AC 3: mobile single-column ──────────────────────────────────────────────

describe('ScreenA — mobile responsive (below 768px)', () => {
  const realMatchMedia = window.matchMedia;
  beforeEach(() => {
    // Force the mobile branch (useIsMobile → matchMedia matches) for the table cards.
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
    window.matchMedia = realMatchMedia;
    vi.restoreAllMocks();
  });

  it('the tile grid is single-column (grid-cols-1) and the plan outcomes render as cards', async () => {
    const { container } = renderScreen();
    // Wait for the tiles to load so the grid is the populated (not empty-state) node.
    await waitFor(() =>
      expect(container.querySelectorAll('[data-project-tile]')).toHaveLength(6),
    );

    // Tile grid base class is single-column (responsive cols added at md/lg only).
    const grid = container.querySelector('[data-project-grid]') as HTMLElement;
    expect(grid.className).toContain('grid-cols-1');

    // Plan outcomes collapse to cards (not a table) below 768px.
    await waitFor(() => expect(container.querySelector('[data-plan-outcome-cards]')).toBeInTheDocument());
    expect(container.querySelector('[data-plan-outcome-table]')).toBeNull();
  });
});
