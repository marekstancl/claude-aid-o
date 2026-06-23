/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor, within, fireEvent } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type {
  AuditSummary,
  AuditTrend,
  Brief,
  EpicSummary,
  PlanDetail,
  ReporterDelivery,
  SimplifierSummary,
} from '@aid/contract';
import { ScreenPlan } from './ScreenPlan';
import * as api from '../lib/api';
import * as lastSeen from '../lib/lastSeen';
import * as backlogDelta from '../lib/backlog-delta';
import * as projectsCtx from '../components/shell/ProjectsContext';

vi.mock('../lib/api', () => ({
  ApiError: class ApiError extends Error {
    code: string;
    constructor(code: string, message: string) {
      super(message);
      this.name = 'ApiError';
      this.code = code;
    }
  },
  getPlanDetail: vi.fn(),
  getBrief: vi.fn(),
  // ReporterDeliveryPanel imports getRunFile/ApiError from api — provide a stub.
  getRunFile: vi.fn(),
}));
vi.mock('../lib/lastSeen', () => ({ getLastSeen: vi.fn() }));
vi.mock('../lib/backlog-delta', async (importOriginal) => {
  // Keep the REAL buildBacklogDelta (client-side delta is under test); only the
  // localStorage snapshot read is stubbed so we can drive firstVisit.
  const actual = await importOriginal<typeof backlogDelta>();
  return { ...actual, getBacklogSnapshot: vi.fn() };
});
vi.mock('../components/shell/ProjectsContext', () => ({ useProjects: vi.fn() }));

const getPlanDetail = vi.mocked(api.getPlanDetail);
const getBrief = vi.mocked(api.getBrief);
const getLastSeen = vi.mocked(lastSeen.getLastSeen);
const getBacklogSnapshot = vi.mocked(backlogDelta.getBacklogSnapshot);
const useProjects = vi.mocked(projectsCtx.useProjects);

const PROJECT = 'wan';
const PLAN = 'P046-cockpit';

function makeBrief(): Brief {
  return {
    scope: 'plan',
    projectId: PROJECT,
    planId: PLAN,
    generatedAt: '2026-06-20T10:00:00.000Z',
    sinceLastSeen: {
      since: null,
      items: [],
      counts: { newRuns: 0, newGateFails: 0, newViolations: 0, newBacklog: 0, stateTransitions: 0 },
    },
    ecosystemLine: 'plán v pořádku',
    blockers: [],
    watchOuts: [],
    nextUp: [],
    decisionsNeeded: [],
    needsTriage: [],
    risk: { level: 'nizke', reasons: [], confidence: 'high' },
    successProbability: { value: null, source: null },
  };
}

function makeEpic(id: string, over: Partial<EpicSummary> = {}): EpicSummary {
  return {
    projectId: PROJECT,
    id,
    title: `Epic ${id}`,
    status: 'done',
    planRef: null,
    runsTotal: 2,
    runsCompleted: 2,
    latestRun: { runId: `R-${id}-1`, state: 'DONE', format: 'v3', startedAt: '2026-06-20T09:00:00.000Z' },
    lastActivityAt: '2026-06-20T09:30:00.000Z',
    ...over,
  };
}

function makeAudit(over: Partial<AuditSummary> = {}): AuditSummary {
  return {
    present: true,
    overallScore: 84,
    scoreSource: 'table',
    blockingFindings: false,
    blockingFindingsSource: 'frontmatter',
    categories: [],
    topReasons: [],
    topRisks: [],
    countsBySeverity: { Critical: 0, High: 0, Medium: 1, Low: 2 },
    autoFixableCount: 0,
    nextSteps: [],
    headlineCs: 'Audit na hranici plánu dopadl dobře.',
    previousScoreHint: null,
    rawRelPath: 'audit-report.md',
    warnings: [],
    ...over,
  };
}

function makeAggregate(
  over: Partial<AuditSummary & { scoredEpicCount: number; medianEpicId: string | null }> = {},
): AuditSummary & { scoredEpicCount: number; medianEpicId: string | null } {
  return {
    ...makeAudit({ overallScore: 89, headlineCs: 'Souhrnný audit plánu.' }),
    scoredEpicCount: 3,
    medianEpicId: 'E-046-2_3',
    ...over,
  };
}

function makeTrend(): AuditTrend {
  return {
    scope: 'plan',
    points: [
      { runId: 'R-1', epicId: 'E-046-1_3', startedAt: '2026-06-18T10:00:00.000Z', score: 84, blockingFindings: false },
      { runId: 'R-2', epicId: 'E-046-2_3', startedAt: '2026-06-19T10:00:00.000Z', score: null, blockingFindings: null },
      { runId: 'R-3', epicId: 'E-046-3_3', startedAt: '2026-06-20T10:00:00.000Z', score: 89, blockingFindings: false },
    ],
    scoredPointCount: 2,
    delta: 5,
  };
}

function makeDelivery(over: Partial<ReporterDelivery> = {}): ReporterDelivery {
  return {
    present: true,
    outcome: 'pass',
    summaryCs: 'Dodávka proběhla.',
    generatedBy: 'reporter',
    generatedAt: '2026-06-20T11:00:00.000Z',
    testEvidence: [
      { name: 'reporter/ok.txt', relPath: 'reporter/ok.txt', exists: true },
      { name: 'reporter/missing.txt', relPath: 'reporter/missing.txt', exists: false },
    ],
    rawRelPath: 'reports/P046-delivery.md',
    warnings: [],
    ...over,
  };
}

function makeSimplifier(over: Partial<SimplifierSummary> = {}): SimplifierSummary {
  return {
    present: true,
    proposalCount: 1,
    proposals: [
      { id: 'IMP-001', area: 'src/foo.ts', proposal: 'Sloučit duplicitní helpery.', disposition: 'approve', effort: 'S' },
    ],
    headlineCs: 'Jeden návrh.',
    rawRelPath: 'reports/simplifier-report.md',
    warnings: [],
    ...over,
  };
}

/**
 * P046 fixture: three members spanning two membership tiers (one plan_ref, two
 * derived) → membershipMixed=true, one excluded orphan.
 */
function makePlanDetail(over: Partial<PlanDetail> = {}): PlanDetail {
  const epics = [
    makeEpic('E-046-1_3', { membershipSource: 'derived' }),
    makeEpic('E-046-2_3', { membershipSource: 'derived' }),
    makeEpic('E-046-3_3', { membershipSource: 'plan_ref' }),
  ];
  return {
    projectId: PROJECT,
    planId: PLAN,
    title: 'Cockpit Phase 6',
    planRef: 'docs/plans/P046-cockpit.md',
    epicIds: epics.map((e) => e.id),
    epicMembers: [
      { epicId: 'E-046-1_3', membershipSource: 'derived' },
      { epicId: 'E-046-2_3', membershipSource: 'derived' },
      { epicId: 'E-046-3_3', membershipSource: 'plan_ref' },
    ],
    membershipMixed: true,
    epicsTotal: 3,
    epicsDone: 3,
    progressPct: 100,
    acPct: 92,
    lessonsPreview: [],
    auditTrend: makeTrend(),
    lastActivityAt: '2026-06-20T09:30:00.000Z',
    description: 'Plán šesté fáze cockpitu.',
    epics,
    orphanEpicCount: 1,
    durationS: 3600,
    boundaryAudit: makeAudit({ overallScore: 84 }),
    aggregateAudit: makeAggregate({ overallScore: 89 }),
    deliveryReport: makeDelivery(),
    simplifierSummary: makeSimplifier(),
    backlog: { items: [], openCount: 0, closedCount: 0, warnings: [] },
    lessons: { scope: 'plan', projectId: PROJECT, planId: PLAN, entries: [], total: 0, warnings: [] },
    warnings: [],
    ...over,
  };
}

function renderScreen(plan: string = PLAN) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[`/p/${PROJECT}/plans/${plan}`]}>
        <Routes>
          <Route path="/p/:project/plans/:planId" element={<ScreenPlan />} />
          <Route path="/p/:project" element={<div>Projekt {PROJECT}</div>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  useProjects.mockReturnValue({
    projects: [{ id: PROJECT } as never],
    loading: false,
    loaded: true,
    error: false,
  });
  getLastSeen.mockReturnValue(null);
  getBacklogSnapshot.mockReturnValue(null); // first visit by default
  getBrief.mockResolvedValue(makeBrief());
  getPlanDetail.mockResolvedValue(makePlanDetail());
});
afterEach(() => vi.restoreAllMocks());

describe('ScreenPlan — plan detail tabs', () => {
  it('passes the STEM verbatim to getPlanDetail and renders the header band', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-header-band]')).toBeInTheDocument());
    expect(getPlanDetail).toHaveBeenCalledWith(PROJECT, PLAN);
    expect(container.querySelector('[data-header-band]')).toHaveTextContent(PLAN);
  });

  it('Brief (plan scope) is the default tab', async () => {
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-brief-panel][data-scope="plan"]')).toBeInTheDocument(),
    );
    expect(getBrief).toHaveBeenCalledWith({ project: PROJECT, plan: PLAN }, undefined);
  });

  it('P046 → exactly 3 members with correct chips (one plan_ref, two derived) + "přiřazeno podle čísla EPICu" note + orphan count', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-header-band]')).toBeInTheDocument());

    fireEvent.click(screen.getByRole('tab', { name: 'EPICy' }));
    await waitFor(() =>
      expect(container.querySelector('[data-plan-epics-list]')).toBeInTheDocument(),
    );

    const rows = container.querySelectorAll('[data-plan-epic-row]');
    expect(rows).toHaveLength(3);

    // Two derived chips + one plan_ref (rendered as the plain "z plánu" chip).
    const derived = container.querySelectorAll('[data-membership-source="derived"]');
    const planRef = container.querySelectorAll('[data-membership-source="plan_ref"]');
    expect(derived).toHaveLength(2);
    expect(planRef).toHaveLength(1);

    // The derived rows carry the "přiřazeno podle čísla" pozor chip.
    derived.forEach((row) => {
      expect(within(row as HTMLElement).getByText(/přiřazeno podle čísla/)).toBeInTheDocument();
    });

    // The mixed-tier note is shown.
    expect(container.querySelector('[data-membership-mixed-note]')).toHaveTextContent(
      'přiřazeny podle čísla EPICu',
    );

    // The excluded orphan is reflected.
    expect(container.querySelector('[data-orphan-count]')).toHaveTextContent('1');
  });

  it('Audit tab renders boundaryAudit (84) and aggregateAudit (89) as two distinct labelled numbers + a broken trend', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-header-band]')).toBeInTheDocument());

    fireEvent.click(screen.getByRole('tab', { name: 'Audit' }));
    await waitFor(() =>
      expect(container.querySelector('[data-boundary-audit]')).toBeInTheDocument(),
    );

    const boundary = container.querySelector('[data-boundary-audit]') as HTMLElement;
    const aggregate = container.querySelector('[data-aggregate-audit]') as HTMLElement;
    // Two DISTINCT numbers in two DISTINCT regions.
    expect(within(boundary).getByText('84/100')).toBeInTheDocument();
    expect(within(aggregate).getByText('89/100')).toBeInTheDocument();
    expect(within(boundary).queryByText('89/100')).not.toBeInTheDocument();

    // Trend keeps the gap (connectNulls={false}, scoredPointCount=2 → real chart).
    const trend = container.querySelector('[data-audit-trend]') as HTMLElement;
    expect(trend).toBeInTheDocument();
    expect(trend).not.toHaveAttribute('data-empty');
  });

  it('boundaryAudit absent but aggregate scored → "auditor zatím neběžel" + still shows aggregate', async () => {
    getPlanDetail.mockResolvedValue(
      makePlanDetail({ boundaryAudit: makeAudit({ present: false, overallScore: null }) }),
    );
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-header-band]')).toBeInTheDocument());

    fireEvent.click(screen.getByRole('tab', { name: 'Audit' }));
    await waitFor(() =>
      expect(container.querySelector('[data-boundary-audit-late]')).toBeInTheDocument(),
    );
    // The boundary card degrades honestly…
    expect(container.querySelector('[data-audit-absent]')).toHaveTextContent('auditor zatím neběžel');
    // …while the aggregate (89) still renders (two independent presence flags).
    const aggregate = container.querySelector('[data-aggregate-audit]') as HTMLElement;
    expect(within(aggregate).getByText('89/100')).toBeInTheDocument();
  });

  it('Dodávka tab renders Reporter + Simplifier; a missing test-evidence file flags exists:false', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-header-band]')).toBeInTheDocument());

    fireEvent.click(screen.getByRole('tab', { name: /Dodávka/ }));
    await waitFor(() =>
      expect(container.querySelector('[data-reporter-evidence]')).toBeInTheDocument(),
    );

    // Both panels present.
    expect(container.querySelector('[data-simplifier-proposals]')).toBeInTheDocument();

    // The missing artifact is flagged exists:false and NOT dropped.
    const missing = container.querySelector('[data-evidence-exists="false"]');
    expect(missing).toBeInTheDocument();
    expect(missing).toHaveTextContent('chybí na disku');
    // The present one is exists:true.
    expect(container.querySelector('[data-evidence-exists="true"]')).toBeInTheDocument();
  });

  it('present:false on both delivery + simplifier → "zatím neběžel", no fabricated outcome', async () => {
    getPlanDetail.mockResolvedValue(
      makePlanDetail({
        deliveryReport: makeDelivery({ present: false, outcome: null, testEvidence: [], rawRelPath: null }),
        simplifierSummary: makeSimplifier({ present: false, proposalCount: 0, proposals: [], rawRelPath: null }),
      }),
    );
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-header-band]')).toBeInTheDocument());

    fireEvent.click(screen.getByRole('tab', { name: /Dodávka/ }));
    await waitFor(() =>
      expect(container.querySelector('[data-reporter-absent]')).toBeInTheDocument(),
    );
    expect(container.querySelector('[data-reporter-absent]')).toHaveTextContent('Reporter zatím neběžel');
    expect(container.querySelector('[data-simplifier-absent]')).toHaveTextContent('Simplifier zatím neběžel');
  });

  it('AC headline acPct:null → "neměřeno / fast mode", never 0 %', async () => {
    getPlanDetail.mockResolvedValue(makePlanDetail({ acPct: null }));
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-header-band]')).toBeInTheDocument());

    fireEvent.click(screen.getByRole('tab', { name: 'AC' }));
    await waitFor(() =>
      expect(container.querySelector('[data-ac-headline="null"]')).toBeInTheDocument(),
    );
    const headline = container.querySelector('[data-plan-ac-tab]') as HTMLElement;
    expect(headline).toHaveTextContent('neměřeno / fast mode');
    expect(headline.textContent).not.toContain('AC 0 %');
  });

  it('Backlog tab computes the delta client-side; first visit → "bez porovnání - vše jako nové"', async () => {
    getBacklogSnapshot.mockReturnValue(null); // no snapshot → firstVisit
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-header-band]')).toBeInTheDocument());

    fireEvent.click(screen.getByRole('tab', { name: 'Backlog' }));
    await waitFor(() =>
      expect(container.querySelector('[data-backlog-firstvisit]')).toBeInTheDocument(),
    );
    expect(container.querySelector('[data-backlog-firstvisit]')).toHaveTextContent(
      'bez porovnání - vše jako nové',
    );
    expect(getBacklogSnapshot).toHaveBeenCalledWith(`plan:${PROJECT}:${PLAN}`);
  });

  it('Lekce empty → plan-scoped honest line', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-header-band]')).toBeInTheDocument());

    fireEvent.click(screen.getByRole('tab', { name: 'Lekce' }));
    await waitFor(() =>
      expect(container.querySelector('[data-plan-lessons-empty]')).toBeInTheDocument(),
    );
    expect(container.querySelector('[data-plan-lessons-empty]')).toHaveTextContent(
      'Z tohohle plánu se zatím nezaznamenala žádná lekce.',
    );
  });

  it('getPlanDetail 404 → "Plán … se nenašel" + back link to the project', async () => {
    getPlanDetail.mockRejectedValue(new api.ApiError('NOT_FOUND', 'missing'));
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-plan-not-found]')).toBeInTheDocument(),
    );
    expect(container.querySelector('[data-plan-not-found]')).toHaveTextContent(`Plán ${PLAN} se nenašel`);
    const back = within(container.querySelector('[data-plan-not-found]') as HTMLElement).getByRole('link');
    expect(back).toHaveAttribute('href', `/p/${PROJECT}`);
  });

  it('keeps the Phase-5 ProjectNotFound guard for an unknown :project', () => {
    useProjects.mockReturnValue({ projects: [], loading: false, loaded: true, error: false });
    const { container } = renderScreen();
    expect(container.textContent).toContain('Projekt nenalezen');
  });
});
