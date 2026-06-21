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
  PlanSummary,
  Project,
} from '@aid/contract';
import { ScreenB } from './ScreenB';
import * as api from '../lib/api';
import * as lastSeen from '../lib/lastSeen';
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
  getBrief: vi.fn(),
  getEpics: vi.fn(),
  getPlans: vi.fn(),
  getAuditSummary: vi.fn(),
  getAuditTrend: vi.fn(),
  getProjectDetail: vi.fn(),
  getCompliance: vi.fn(),
}));
vi.mock('../lib/lastSeen', () => ({ getLastSeen: vi.fn() }));
vi.mock('../components/shell/ProjectsContext', () => ({ useProjects: vi.fn() }));

const getBrief = vi.mocked(api.getBrief);
const getEpics = vi.mocked(api.getEpics);
const getPlans = vi.mocked(api.getPlans);
const getAuditSummary = vi.mocked(api.getAuditSummary);
const getAuditTrend = vi.mocked(api.getAuditTrend);
const getProjectDetail = vi.mocked(api.getProjectDetail);
const getCompliance = vi.mocked(api.getCompliance);
const getLastSeen = vi.mocked(lastSeen.getLastSeen);
const useProjects = vi.mocked(projectsCtx.useProjects);

const PROJECT = 'vulcan';

function makeProject(id: string): Project {
  return {
    id,
    name: id,
    path: `/${id}`,
    aidoPath: `/${id}/.aid-o`,
    discovered: true,
    partial: false,
    epicsTotal: 9,
    epicsActive: 1,
    runsTotal: 12,
    activeRun: { epicId: 'E-001', runId: 'R-1', state: 'EXECUTE' },
    health: {
      value: 90,
      partial: false,
      confidence: 'high',
      compliancePassRate: 0.94,
      openViolations: 0,
      lastGateOverall: 'pass',
      warnings: [],
    },
    lastActivityAt: '2026-06-20T10:00:00.000Z',
  };
}

function makeBrief(): Brief {
  return {
    scope: 'project',
    projectId: PROJECT,
    planId: null,
    generatedAt: '2026-06-20T10:00:00.000Z',
    sinceLastSeen: {
      since: null,
      items: [],
      counts: { newRuns: 0, newGateFails: 0, newViolations: 0, newBacklog: 0, stateTransitions: 0 },
    },
    blockers: [],
    watchOuts: [],
    nextUp: [],
    decisionsNeeded: [],
    risk: { level: 'nizke', reasons: [], confidence: 'high' },
    successProbability: { value: null, source: null },
  };
}

function makeEpic(id: string): EpicSummary {
  return {
    projectId: PROJECT,
    id,
    title: id,
    status: 'done',
    planRef: null,
    runsTotal: 2,
    runsCompleted: 2,
    latestRun: { runId: 'R-1', state: 'DONE', format: 'v3', startedAt: '2026-06-20T09:00:00.000Z' },
    lastActivityAt: '2026-06-20T09:30:00.000Z',
  };
}

function makePlan(planId: string): PlanSummary {
  return {
    projectId: PROJECT,
    planId,
    title: `Plán ${planId}`,
    planRef: `docs/plans/${planId}.md`,
    epicIds: ['E-001'],
    epicMembers: [{ epicId: 'E-001', membershipSource: 'plan_ref' }],
    membershipMixed: false,
    epicsTotal: 2,
    epicsDone: 1,
    progressPct: 50,
    acPct: 80,
    lessonsPreview: [],
    auditTrend: { scope: 'plan', points: [], scoredPointCount: 0, delta: null },
    lastActivityAt: '2026-06-20T09:00:00.000Z',
  };
}

/** Aggregate AuditSummary with a real median score and provenance. */
function makeAuditSummary(over: Partial<AuditSummary & { scoredEpicCount: number; medianEpicId: string | null }> = {}) {
  const base: AuditSummary & { scoredEpicCount: number; medianEpicId: string | null } = {
    present: true,
    overallScore: 87,
    scoreSource: 'table',
    blockingFindings: false,
    blockingFindingsSource: 'frontmatter',
    categories: [],
    topReasons: [],
    topRisks: [],
    countsBySeverity: { Critical: 0, High: 0, Medium: 1, Low: 2 },
    autoFixableCount: 0,
    nextSteps: [],
    headlineCs: 'Audit dopadl dobře.',
    previousScoreHint: null,
    rawRelPath: 'audit-report.md',
    warnings: [],
    scoredEpicCount: 4,
    medianEpicId: 'E-042',
  };
  return { ...base, ...over };
}

function makeAuditTrend(): AuditTrend {
  // Two scored points with a real null gap between → connectNulls={false} breaks the line.
  return {
    scope: 'project',
    points: [
      { runId: 'R-1', epicId: 'E-001', startedAt: '2026-06-18T10:00:00.000Z', score: 80, blockingFindings: false },
      { runId: 'R-2', epicId: 'E-002', startedAt: '2026-06-19T10:00:00.000Z', score: null, blockingFindings: null },
      { runId: 'R-3', epicId: 'E-042', startedAt: '2026-06-20T10:00:00.000Z', score: 87, blockingFindings: false },
    ],
    scoredPointCount: 2,
    delta: 7,
  };
}

function renderScreen() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[`/p/${PROJECT}`]}>
        <Routes>
          <Route path="/p/:project" element={<ScreenB />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  useProjects.mockReturnValue({ projects: [makeProject(PROJECT)], loading: false, loaded: true, error: false });
  getLastSeen.mockReturnValue(null);
  getBrief.mockResolvedValue(makeBrief());
  getEpics.mockResolvedValue([makeEpic('E-001')]);
  getPlans.mockResolvedValue([makePlan('P046')]);
  getAuditSummary.mockResolvedValue(makeAuditSummary());
  getAuditTrend.mockResolvedValue(makeAuditTrend());
  getProjectDetail.mockResolvedValue({
    ...makeProject(PROJECT),
    epics: [makeEpic('E-001')],
    queue: [],
    recentActivity: [],
    aggregateAudit: makeAuditSummary(),
    auditTrend: makeAuditTrend(),
  });
  getCompliance.mockResolvedValue({
    scope: PROJECT,
    fsmAdherenceScore: { value: 94, partial: false, confidence: 'high', components: {}, warnings: [] },
    passRate: 0.94,
    totals: { runs: 12, passed: 11, failed: 1, forceOverrides: 0 },
    violations: [],
  });
});
afterEach(() => vi.restoreAllMocks());

describe('ScreenB — project detail tab strip', () => {
  it('renders Brief (project scope) as the default tab', async () => {
    const { container } = renderScreen();
    // BriefPanel renders with data-scope="project" only at project scope.
    await waitFor(() =>
      expect(container.querySelector('[data-brief-panel][data-scope="project"]')).toBeInTheDocument(),
    );
    expect(getBrief).toHaveBeenCalledWith({ project: PROJECT }, undefined);
    // The Brief tab is the active tab (data-active per base-ui Tabs).
    const briefTab = screen.getByRole('tab', { name: 'Brief' });
    expect(briefTab).toHaveAttribute('data-active');
  });

  it('Audit tab renders the aggregate median score + "ze N auditovaných" provenance chip + a connectNulls={false} broken trend', async () => {
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-brief-panel]')).toBeInTheDocument(),
    );

    fireEvent.click(screen.getByRole('tab', { name: 'Audit' }));

    // Aggregate median score badge.
    await waitFor(() =>
      expect(container.querySelector('[data-audit-provenance]')).toBeInTheDocument(),
    );
    const card = container.querySelector('[data-audit-tab]') as HTMLElement;
    expect(within(card).getByText('87/100')).toBeInTheDocument();

    // Provenance chip: "z EPICu E-042 · ze 4 auditovaných".
    const chip = container.querySelector('[data-audit-provenance]') as HTMLElement;
    expect(chip).toHaveTextContent('z EPICu E-042');
    expect(chip).toHaveTextContent('ze 4 auditovaných');

    // Trend renders the real (non-empty) chart — scoredPointCount>0, so NOT the
    // "žádné audity" empty state. connectNulls={false} keeps the null point a gap.
    const trend = container.querySelector('[data-audit-trend]') as HTMLElement;
    expect(trend).toBeInTheDocument();
    expect(trend).not.toHaveAttribute('data-empty');
  });

  it('scoredEpicCount===0 → honest empty line, never a fabricated 0%/median', async () => {
    getAuditSummary.mockResolvedValue(
      makeAuditSummary({ scoredEpicCount: 0, medianEpicId: null, overallScore: null }),
    );
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-brief-panel]')).toBeInTheDocument(),
    );

    fireEvent.click(screen.getByRole('tab', { name: 'Audit' }));

    await waitFor(() =>
      expect(container.querySelector('[data-audit-empty]')).toBeInTheDocument(),
    );
    const empty = container.querySelector('[data-audit-empty]') as HTMLElement;
    expect(empty).toHaveTextContent('žádné audity v projektu');
    // No fabricated score/provenance chip when there is nothing to aggregate.
    expect(container.querySelector('[data-audit-provenance]')).not.toBeInTheDocument();
    expect(container.textContent).not.toContain('0/100');
  });

  it('shows the EPIC list on the EPICy tab and the health rail on Zdraví (nothing lost)', async () => {
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-brief-panel]')).toBeInTheDocument(),
    );

    fireEvent.click(screen.getByRole('tab', { name: 'EPICy' }));
    await waitFor(() => expect(container.querySelector('[data-epics-list]')).toBeInTheDocument());
    expect(container.querySelector('[data-epic-id="E-001"]')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('tab', { name: 'Zdraví' }));
    await waitFor(() =>
      expect(container.querySelector('[data-health-epic-bars]')).toBeInTheDocument(),
    );
  });

  it('audit-summary 500 fails INDEPENDENTLY — Brief stays live, error stays inside the Audit tab', async () => {
    getAuditSummary.mockRejectedValue(new api.ApiError('HTTP_500', 'boom'));
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-brief-panel][data-scope="project"]')).toBeInTheDocument(),
    );

    fireEvent.click(screen.getByRole('tab', { name: 'Audit' }));
    await waitFor(() =>
      expect(container.querySelector('[data-audit-summary-error]')).toBeInTheDocument(),
    );
    expect(container.querySelector('[data-audit-summary-error]')).toHaveTextContent(
      'Audit projektu se nepodařilo načíst',
    );
    // No whole-screen crash: the tab strip + the trend Card still render, and the
    // Brief tab is still navigable (its query was never affected by the audit 500).
    expect(container.querySelector('[data-screen-b-tabs]')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('tab', { name: 'Brief' }));
    await waitFor(() =>
      expect(container.querySelector('[data-brief-panel][data-scope="project"]')).toBeInTheDocument(),
    );
  });

  it('keeps the existing ProjectNotFound guard for an unknown :project', () => {
    useProjects.mockReturnValue({ projects: [], loading: false, loaded: true, error: false });
    const { container } = renderScreen();
    expect(container.textContent).toContain('Projekt nenalezen');
  });
});
