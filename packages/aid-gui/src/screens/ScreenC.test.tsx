/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor, within, fireEvent } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type {
  AuditSummary,
  AuditTrend,
  Checkpoint,
  ComplianceRun,
  DictionaryEntry,
  EpicDetail,
  GateResult,
  MetricSet,
  Project,
  RunDetail,
} from '@aid/contract';
import { ScreenC } from './ScreenC';
import * as api from '../lib/api';
import * as projectsCtx from '../components/shell/ProjectsContext';

// Mock the live socket so no real WebSocket is constructed in jsdom.
vi.mock('../hooks/useAidSocket', () => ({
  useAidSocket: () => ({ status: 'open' }),
}));

vi.mock('../lib/api', () => ({
  ApiError: class ApiError extends Error {
    code: string;
    constructor(code: string, message: string) {
      super(message);
      this.name = 'ApiError';
      this.code = code;
    }
  },
  getEpic: vi.fn(),
  getExplanations: vi.fn(),
  getRunFile: vi.fn(),
}));
vi.mock('../components/shell/ProjectsContext', () => ({ useProjects: vi.fn() }));

const getEpic = vi.mocked(api.getEpic);
const getExplanations = vi.mocked(api.getExplanations);
const getRunFile = vi.mocked(api.getRunFile);
const useProjects = vi.mocked(projectsCtx.useProjects);

const PROJECT = 'vulcan';
const EPIC = 'E-047';

// ── factories ────────────────────────────────────────────────────────────────

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
    activeRun: { epicId: EPIC, runId: 'R-1', state: 'EXECUTE' },
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

function makeAudit(over: Partial<AuditSummary> = {}): AuditSummary {
  return {
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
    ...over,
  };
}

function makeTrend(): AuditTrend {
  return {
    scope: 'epic',
    points: [
      { runId: 'R-1', epicId: EPIC, startedAt: '2026-06-18T10:00:00.000Z', score: 80, blockingFindings: false },
      { runId: 'R-2', epicId: EPIC, startedAt: '2026-06-19T10:00:00.000Z', score: null, blockingFindings: null },
      { runId: 'R-3', epicId: EPIC, startedAt: '2026-06-20T10:00:00.000Z', score: 87, blockingFindings: false },
    ],
    scoredPointCount: 2,
    delta: 7,
  };
}

function makeMetrics(over: Partial<MetricSet> = {}): MetricSet {
  return {
    epicWallTimeS: 3600,
    runCount: 3,
    stepDurationsS: [120, null, 300],
    avgStepDurationS: 210,
    longestStep: { id: 'step-3', durationS: 300 },
    stepTimingSource: 'mtime',
    gateRuns: 2,
    gateRetries: 1,
    checkpointRepeats: { CP1: 1, CP2: null, CP3: 4, CP4: 1, CP5: 1, CP6: null },
    escalations: 0,
    timeBy: [],
    partial: false,
    warnings: [],
    ...over,
  };
}

function makeCheckpoints(): Checkpoint[] {
  return [
    {
      id: 'CP1',
      label: 'plán',
      dispatched: true,
      verdict: 'pass',
      provenance: 'compliance.json',
      provenanceSource: 'compliance',
      repeatCount: 1,
      repeatSource: 'files',
      outputs: [{ name: 'verifier-output-1.md', relPath: 'verifier-output-1.md' }],
    },
    {
      id: 'CP2',
      label: 'kód',
      dispatched: true,
      verdict: 'fail',
      provenance: ['timeline'],
      provenanceSource: 'timeline',
      // KNOWN >=3 repeat WITH a source → genuine hot-spot.
      repeatCount: 3,
      repeatSource: 'timeline',
      outputs: [],
    },
    {
      id: 'CP3',
      label: 'testy',
      dispatched: true,
      // unknown repeat (count null) → "?" never 0, no hot-spot.
      verdict: null,
      provenance: null,
      provenanceSource: null,
      repeatCount: null,
      repeatSource: null,
      outputs: [],
    },
    {
      id: 'CP4',
      label: 'dokumentace',
      dispatched: true,
      verdict: 'skipped',
      provenance: 'compliance.json',
      provenanceSource: 'compliance',
      repeatCount: 1,
      repeatSource: 'files',
      outputs: [],
    },
    {
      id: 'CP5',
      label: 'shoda',
      dispatched: true,
      verdict: 'pass',
      provenance: 'compliance.json',
      provenanceSource: 'compliance',
      repeatCount: 1,
      repeatSource: 'files',
      outputs: [],
    },
  ];
}

function makeGates(): GateResult[] {
  return [
    { gate: 'build', result: 'pass', exitCode: 0, durationMs: 12000, attempts: 1, outputPreview: 'ok' },
    { gate: 'test', result: 'fail', exitCode: 1, durationMs: 45000, attempts: 2, outputPreview: 'boom' },
  ];
}

function makeCompliance(): ComplianceRun {
  return {
    epicId: EPIC,
    runId: 'R-3',
    aidVersion: '2.6.0',
    deployEra: 'mirror',
    evaluatedAt: '2026-06-20T10:00:00.000Z',
    coverageMode: 'full',
    overall: 'fail',
    checks: {},
    failures: [
      { check: 'fsm_adherence', evidence: 'precondition skipped', severity: 'blocking' },
      { check: 'branch_match', evidence: 'wrong branch', severity: 'advisory' },
    ],
    forceOverrideCount: 0,
    forceOverrideReasons: [],
    notes: [],
  };
}

function makeRun(over: Partial<RunDetail> = {}): RunDetail {
  return {
    projectId: PROJECT,
    epicId: EPIC,
    runId: 'R-3',
    format: 'v3',
    state: 'GATES',
    mode: 'autonomous',
    branch: 'feat/E-047',
    baseCommit: 'abc123',
    currentStep: 5,
    totalSteps: 7,
    gateRetries: 1,
    escalationCount: 0,
    startedAt: '2026-06-20T09:00:00.000Z',
    createdAt: '2026-06-20T08:55:00.000Z',
    donePhase: null,
    pmDecision: null,
    planPath: null,
    steps: [
      { id: 'step-1', name: 'seams', status: 'done', role: 'implementer', startedAt: null, completedAt: null, durationS: 120 },
      { id: 'step-2', name: 'contract', status: 'done', role: 'implementer', startedAt: null, completedAt: null, durationS: null },
      { id: 'step-3', name: 'screen', status: 'executing', role: 'implementer', startedAt: null, completedAt: null, durationS: 300 },
    ],
    checkpoints: makeCheckpoints(),
    gates: makeGates(),
    compliance: makeCompliance(),
    reports: [{ kind: 'audit', name: 'audit-report.md', relPath: 'audit-report.md' }],
    audit: makeAudit(),
    timeline: [
      {
        projectId: PROJECT,
        epicId: EPIC,
        runId: 'R-3',
        ts: '2026-06-20T09:00:00.000Z',
        event: 'fsm_transition',
        from: 'READY',
        to: 'EXECUTE',
        raw: {},
      },
      {
        projectId: PROJECT,
        epicId: EPIC,
        runId: 'R-3',
        ts: '2026-06-20T09:30:00.000Z',
        event: 'fsm_transition',
        from: 'EXECUTE',
        to: 'GATES',
        raw: {},
      },
      {
        projectId: PROJECT,
        epicId: EPIC,
        runId: 'R-3',
        ts: '2026-06-20T09:35:00.000Z',
        event: 'role',
        role: 'curator',
        result: 'pass',
        raw: { verdict: 'clean' },
      },
    ],
    files: ['audit-report.md', 'reporter/summary.md'],
    ...over,
  };
}

function makeEpicDetail(over: Partial<EpicDetail> = {}): EpicDetail {
  return {
    projectId: PROJECT,
    id: EPIC,
    title: 'AID Cockpit',
    status: 'running',
    planRef: 'docs/plans/P047.md',
    runsTotal: 3,
    runsCompleted: 2,
    latestRun: { runId: 'R-3', state: 'GATES', format: 'v3', startedAt: '2026-06-20T09:00:00.000Z' },
    lastActivityAt: '2026-06-20T09:35:00.000Z',
    spec: {
      epicId: EPIC,
      status: 'running',
      planRef: 'docs/plans/P047.md',
      planEpicsTotal: 7,
      runsTotal: 3,
      runsCompleted: 2,
      title: 'AID Cockpit',
      context: '',
      goal: '',
      scope: { allowedPaths: [], forbiddenPaths: [], rawMarkdown: '' },
      constraints: '',
      dodGates: [],
      acceptanceCriteria: [],
      steps: [],
    },
    runs: [],
    latest: makeRun(),
    metrics: makeMetrics(),
    explanations: [] as DictionaryEntry['id'][],
    auditTrend: makeTrend(),
    ...over,
  };
}

const DICTIONARY: Record<string, DictionaryEntry> = {
  'event:fsm_transition:READY_to_EXECUTE': {
    id: 'event:fsm_transition:READY_to_EXECUTE',
    headlineTemplate: 'Běh se rozběhl.',
    detailTemplate: 'Přechod READY → EXECUTE.',
    status: 'bezi',
  } as DictionaryEntry,
  'event:fsm_transition:EXECUTE_to_GATES': {
    id: 'event:fsm_transition:EXECUTE_to_GATES',
    headlineTemplate: 'Spustily se kontroly.',
    detailTemplate: 'Přechod EXECUTE → GATES.',
    status: 'bezi',
  } as DictionaryEntry,
  'role:curator:pass': {
    id: 'role:curator:pass',
    headlineTemplate: 'Kurátor schválil.',
    detailTemplate: 'Kurátor neměl námitky.',
    status: 'proslo',
  } as DictionaryEntry,
};

function renderScreen() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[`/p/${PROJECT}/e/${EPIC}`]}>
        <Routes>
          <Route path="/p/:project/e/:epic" element={<ScreenC />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  useProjects.mockReturnValue({ projects: [makeProject(PROJECT)], loading: false, loaded: true, error: false });
  getEpic.mockResolvedValue(makeEpicDetail());
  getExplanations.mockResolvedValue(DICTIONARY);
  getRunFile.mockResolvedValue({ format: 'markdown', content: '# Audit\nall good' });
});
afterEach(() => vi.restoreAllMocks());

describe('ScreenC — EPIC deep view (v3 run)', () => {
  it('renders the header band with FSM state + progress + mode + branch + human line', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-header-band]')).toBeInTheDocument());
    const band = container.querySelector('[data-header-band]') as HTMLElement;
    expect(within(band).getByText(EPIC)).toBeInTheDocument();
    expect(band).toHaveTextContent('běh R-3');
    expect(container.querySelector('[data-header-state]')).toHaveTextContent('kontroly');
    expect(band).toHaveTextContent('režim autonomous');
    expect(band).toHaveTextContent('feat/E-047');
    // 5/7 ≈ 71 %
    expect(band).toHaveTextContent('71 %');
    expect(container.querySelector('[data-header-human]')).toHaveTextContent(/kontroly/i);
  });

  it('FSM tab renders the transition walk with a Czech line per node', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-screen-c-tabs]')).toBeInTheDocument());
    fireEvent.click(screen.getByRole('tab', { name: 'FSM' }));
    await waitFor(() => expect(container.querySelector('[data-fsm-timeline]')).toBeInTheDocument());
    const tl = container.querySelector('[data-fsm-timeline]') as HTMLElement;
    // Both transitions present, each with its dictionary Czech line.
    expect(tl.querySelector('[data-node*="EXECUTE"]')).toBeInTheDocument();
    expect(tl.querySelector('[data-node*="GATES"]')).toBeInTheDocument();
    expect(tl).toHaveTextContent('Běh se rozběhl.');
    expect(tl).toHaveTextContent('Spustily se kontroly.');
    // Current state (GATES) is emphasised.
    expect(container.querySelector('[data-fsm-current]')).toHaveTextContent('kontroly');
  });

  it('CP tab renders CP1-CP5 verdicts + provenance; null repeat → "?" no hot-spot; known >=3 → hot-spot; CP6 = Fast-Mode note', async () => {
    const { container, baseElement } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-screen-c-tabs]')).toBeInTheDocument());
    fireEvent.click(screen.getByRole('tab', { name: 'CP' }));
    await waitFor(() => expect(container.querySelector('[data-cp-list]')).toBeInTheDocument());

    // Five CP rows.
    expect(container.querySelectorAll('[data-cp-row]')).toHaveLength(5);

    // CP3: unknown repeat → "?" badge, never 0, no hot-spot.
    const cp3 = container.querySelector('[data-cp-row="CP3"]') as HTMLElement;
    const cp3badge = cp3.querySelector('[data-cp-repeat]') as HTMLElement;
    expect(cp3badge).toHaveTextContent('?');
    expect(cp3badge.textContent).not.toContain('0');
    expect(cp3badge.textContent).not.toContain('hot-spot');

    // CP2: KNOWN repeatCount=3 WITH a source → hot-spot.
    const cp2 = container.querySelector('[data-cp-row="CP2"]') as HTMLElement;
    expect((cp2.querySelector('[data-cp-repeat]') as HTMLElement).textContent).toContain('hot-spot');

    // CP6 fast-mode-only note (CP6 absent from this normal run).
    expect(container.querySelector('[data-cp6-note]')).toHaveTextContent('jen Fast Mode (/aid-do)');

    // Click CP1 → drawer (portaled) shows verdict + provenance + a Czech one-liner + outputs.
    fireEvent.click(container.querySelector('[data-cp-row="CP1"]') as HTMLElement);
    await waitFor(() => expect(baseElement.querySelector('[data-cp-provenance]')).toBeInTheDocument());
    expect(baseElement.querySelector('[data-cp-provenance]')).toHaveTextContent('compliance.json');
    expect(baseElement.querySelector('[data-cp-explanation]')).toBeInTheDocument();
    expect(baseElement.querySelector('[data-cp-outputs]')).toBeInTheDocument();
  });

  it('Role tab renders all four AgentRolePanels', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-screen-c-tabs]')).toBeInTheDocument());
    fireEvent.click(screen.getByRole('tab', { name: 'Role' }));
    await waitFor(() => expect(container.querySelector('[data-roles-grid]')).toBeInTheDocument());
    expect(container.querySelector('[data-role-panel="auditor"]')).toBeInTheDocument();
    expect(container.querySelector('[data-role-panel="curator"]')).toBeInTheDocument();
    expect(container.querySelector('[data-role-panel="reporter"]')).toBeInTheDocument();
    expect(container.querySelector('[data-role-panel="simplifier"]')).toBeInTheDocument();
    // Curator verdict came from the timeline role:pass event → its Czech line.
    expect(container.querySelector('[data-role-panel="curator"]')).toHaveTextContent('Kurátor schválil.');
  });

  it('Audit tab renders the per-run AuditSummaryCard + EPIC-scope trend', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-screen-c-tabs]')).toBeInTheDocument());
    fireEvent.click(screen.getByRole('tab', { name: 'Audit' }));
    await waitFor(() => expect(container.querySelector('[data-audit-section]')).toBeInTheDocument());
    const section = container.querySelector('[data-audit-section]') as HTMLElement;
    expect(within(section).getByText('87/100')).toBeInTheDocument();
    const trend = section.querySelector('[data-audit-trend]') as HTMLElement;
    expect(trend).toBeInTheDocument();
    expect(trend).not.toHaveAttribute('data-empty');
  });

  it('Časy tab renders per-step DurationBars (null → neměřeno), gates with duration_ms, compliance with severity', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-screen-c-tabs]')).toBeInTheDocument());
    fireEvent.click(screen.getByRole('tab', { name: 'Časy' }));
    await waitFor(() => expect(container.querySelector('[data-timing-section]')).toBeInTheDocument());

    // Per-step bars: 3 entries, the null one labelled "neměřeno", never "0 m".
    const bars = container.querySelector('[data-step-bars]') as HTMLElement;
    expect(bars.querySelectorAll('li')).toHaveLength(3);
    expect(bars).toHaveTextContent('neměřeno');
    expect(bars.textContent).not.toContain('0 m');

    // checkpointRepeats: CP3 known×4 → hot-spot; CP2 unknown → "?" no hot-spot.
    const repeats = container.querySelector('[data-cp-repeats]') as HTMLElement;
    expect((repeats.querySelector('[data-cp="CP3"]') as HTMLElement).textContent).toContain('hot-spot');
    const cp2repeat = repeats.querySelector('[data-cp="CP2"]') as HTMLElement;
    expect(cp2repeat).toHaveTextContent('?');
    expect(cp2repeat.textContent).not.toContain('hot-spot');

    // Gates with duration_ms (45000ms → "45 s") + severity-mapped compliance.
    const gates = container.querySelector('[data-gates-list]') as HTMLElement;
    expect(gates).toHaveTextContent('build');
    expect(gates).toHaveTextContent('45 s');
    const comp = container.querySelector('[data-compliance-failures]') as HTMLElement;
    expect(comp.querySelector('[data-severity="blocking"]')).toBeInTheDocument();
    expect(comp.querySelector('[data-severity="advisory"]')).toBeInTheDocument();
    expect(comp.querySelector('[data-severity="blocking"]')).toHaveTextContent('blokující');
  });

  it('Dění tab narrates the timeline newest-first and lists run files behind a run-scoped /file drawer', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-screen-c-tabs]')).toBeInTheDocument());
    fireEvent.click(screen.getByRole('tab', { name: 'Dění' }));
    await waitFor(() => expect(container.querySelector('[data-event-feed]')).toBeInTheDocument());
    // newest-first: the curator role event (latest ts) explanation appears.
    expect(container.querySelector('[data-event-feed]')).toHaveTextContent('Kurátor schválil.');

    // File tree → opening one fetches via getRunFile (run-scoped /file, name=).
    const tree = container.querySelector('[data-file-tree]') as HTMLElement;
    expect(tree).toBeInTheDocument();
    const trigger = tree.querySelector('[data-raw-md-trigger]') as HTMLElement;
    fireEvent.click(trigger);
    await waitFor(() => expect(getRunFile).toHaveBeenCalled());
    // run-scoped call: (project, epic, runId, name) — NOT a /file?path= shape.
    expect(getRunFile).toHaveBeenCalledWith(PROJECT, EPIC, 'R-3', expect.any(String));
  });

  it('?ts= deep-link opens directly on the Dění tab and highlights the matching event (REOPEN H2)', async () => {
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const { container } = render(
      <QueryClientProvider client={qc}>
        <MemoryRouter initialEntries={[`/p/${PROJECT}/e/${EPIC}?ts=2026-06-20T09:30:00.000Z`]}>
          <Routes>
            <Route path="/p/:project/e/:epic" element={<ScreenC />} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>,
    );
    // Without any tab click, the Dění feed is already rendered (controlled tab).
    await waitFor(() => expect(container.querySelector('[data-event-feed]')).toBeInTheDocument());
    // The anchored row is marked + highlighted.
    const anchored = container.querySelector('[data-event-ts="2026-06-20T09:30:00.000Z"]') as HTMLElement;
    expect(anchored).toBeInTheDocument();
    await waitFor(() => expect(anchored).toHaveAttribute('data-anchored', 'true'));
    expect(anchored.className).toContain('bg-amber-50');
  });

  it('file tree hides artifacts off the /file allow-list — no 404 links (REOPEN M3)', async () => {
    getEpic.mockResolvedValue(
      makeEpicDetail({
        latest: makeRun({
          // epic_input.md + plan.md are on disk but NOT allow-listed by /file.
          files: ['audit-report.md', 'epic_input.md', 'plan.md', 'reporter/summary.md'],
        }),
      }),
    );
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-screen-c-tabs]')).toBeInTheDocument());
    fireEvent.click(screen.getByRole('tab', { name: 'Dění' }));
    const tree = await waitFor(() => container.querySelector('[data-file-tree]') as HTMLElement);
    // Allow-listed ones show…
    expect(tree).toHaveTextContent('audit-report.md');
    expect(tree).toHaveTextContent('reporter/summary.md');
    // …off-list ones are filtered out (would have 404'd).
    expect(tree).not.toHaveTextContent('epic_input.md');
    expect(tree).not.toHaveTextContent('plan.md');
  });

  it('compliance:null → "N/A" + warning, never 0%/fail', async () => {
    getEpic.mockResolvedValue(makeEpicDetail({ latest: makeRun({ compliance: null }) }));
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-screen-c-tabs]')).toBeInTheDocument());
    fireEvent.click(screen.getByRole('tab', { name: 'Časy' }));
    await waitFor(() => expect(container.querySelector('[data-compliance-na]')).toBeInTheDocument());
    const na = container.querySelector('[data-compliance-na]') as HTMLElement;
    expect(na).toHaveTextContent('N/A');
    expect(na.textContent).not.toContain('0 %');
    expect(na.textContent).not.toContain('0%');
  });
});

describe('ScreenC — degraded runs', () => {
  it('legacy run → header + single "starší formát / bez detailu" panel, all detail panels SUPPRESSED', async () => {
    getEpic.mockResolvedValue(
      makeEpicDetail({
        latest: makeRun({ format: 'legacy' }),
        latestRun: { runId: 'R-3', state: 'DONE', format: 'legacy', startedAt: null },
      }),
    );
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-legacy-fallback]')).toBeInTheDocument());
    expect(container.querySelector('[data-legacy-fallback]')).toHaveTextContent('starší formát / bez detailu');
    // Header band still renders; the rich section tabs do NOT.
    expect(container.querySelector('[data-header-band]')).toBeInTheDocument();
    expect(container.querySelector('[data-screen-c-tabs]')).not.toBeInTheDocument();
    expect(container.querySelector('[data-cp-list]')).not.toBeInTheDocument();
    expect(container.querySelector('[data-roles-grid]')).not.toBeInTheDocument();
  });

  it('stub run → fallback panel, panels suppressed', async () => {
    getEpic.mockResolvedValue(
      makeEpicDetail({
        latest: makeRun({ format: 'stub' }),
        latestRun: { runId: 'R-3', state: 'READY', format: 'stub', startedAt: null },
      }),
    );
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-legacy-fallback]')).toBeInTheDocument());
    expect(container.querySelector('[data-screen-c-tabs]')).not.toBeInTheDocument();
  });

  it('latest === null → fallback panel, no thrown error', async () => {
    getEpic.mockResolvedValue(makeEpicDetail({ latest: null, latestRun: null }));
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-legacy-fallback]')).toBeInTheDocument());
    expect(container.querySelector('[data-screen-c-tabs]')).not.toBeInTheDocument();
    expect(container.querySelector('[data-header-band]')).toBeInTheDocument();
  });
});

describe('ScreenC — errors & guards', () => {
  it('getEpic failure → "se nepodařilo načíst" + retry, not a crash', async () => {
    getEpic.mockRejectedValue(new api.ApiError('HTTP_500', 'boom'));
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-epic-error]')).toBeInTheDocument());
    expect(container.querySelector('[data-epic-error]')).toHaveTextContent('se nepodařilo načíst');
  });

  it('getEpic 404 (NOT_FOUND) → back link to the project', async () => {
    getEpic.mockRejectedValue(new api.ApiError('NOT_FOUND', 'no such epic'));
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-epic-not-found]')).toBeInTheDocument());
    expect(screen.getByRole('link', { name: /Zpět na projekt/ })).toHaveAttribute('href', `/p/${PROJECT}`);
  });

  it('keeps the ProjectNotFound guard for an unknown :project', () => {
    useProjects.mockReturnValue({ projects: [], loading: false, loaded: true, error: false });
    const { container } = renderScreen();
    expect(container.textContent).toContain('Projekt nenalezen');
  });
});
