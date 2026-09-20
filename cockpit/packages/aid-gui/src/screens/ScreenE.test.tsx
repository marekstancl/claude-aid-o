/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, waitFor, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ComplianceView, Project, Score } from '@aid/contract';
import { ScreenE } from './ScreenE';
import * as api from '../lib/api';
import * as projectsCtx from '../components/shell/ProjectsContext';

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
  getComplianceAll: vi.fn(),
  getProjects: vi.fn(),
}));
vi.mock('../components/shell/ProjectsContext', () => ({ useProjects: vi.fn() }));

const getComplianceAll = vi.mocked(api.getComplianceAll);
const getProjects = vi.mocked(api.getProjects);
const useProjects = vi.mocked(projectsCtx.useProjects);

// ── fixtures ────────────────────────────────────────────────────────────────

function makeProject(id: string): Project {
  return {
    id,
    name: id,
    path: `/${id}`,
    aidoPath: `/${id}/.aid-o`,
    discovered: true,
    partial: false,
    epicsTotal: 1,
    epicsActive: 0,
    runsTotal: 1,
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
  };
}

function makeScore(over: Partial<Score> = {}): Score {
  return {
    value: 91,
    partial: false,
    confidence: 'high',
    components: {},
    warnings: [],
    ...over,
  };
}

/**
 * A cross-project compliance view with:
 *  - vulcan: a SYSTEMATIC override (forceOverrideCount 5) on a blocking + advisory fail
 *  - wan: a one-off override (forceOverrideCount 1)
 *  - "necinne" (a 3rd project from the list, `acta`) has NO violation → N/A column.
 */
function makeView(over: Partial<ComplianceView> = {}): ComplianceView {
  return {
    scope: 'all',
    fsmAdherenceScore: makeScore(),
    passRate: 0.82,
    totals: { runs: 13, passed: 11, failed: 2, forceOverrides: 6 },
    violations: [
      {
        projectId: 'vulcan',
        epicId: 'E-047',
        runId: 'R-3',
        overall: 'fail',
        forceOverrideCount: 5,
        evaluatedAt: '2026-06-20T10:00:00.000Z',
        failures: [
          { check: 'fsm_adherence', evidence: 'precondition skipped', severity: 'blocking' },
          { check: 'branch_match', evidence: 'wrong branch', severity: 'advisory' },
        ],
      },
      {
        projectId: 'wan',
        epicId: 'E-202',
        runId: 'R-9',
        overall: 'fail',
        forceOverrideCount: 1,
        evaluatedAt: '2026-06-20T09:00:00.000Z',
        failures: [{ check: 'gates_report', evidence: 'no gates artifact', severity: 'blocking' }],
      },
    ],
    ...over,
  };
}

// ── matchMedia control (desktop by default; flip for the mobile-cards test) ───
const realMatchMedia = window.matchMedia;
function setMatchMedia(matches: boolean) {
  window.matchMedia = vi.fn().mockImplementation((query: string) => ({
    matches,
    media: query,
    onchange: null,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    addListener: vi.fn(),
    removeListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })) as unknown as typeof window.matchMedia;
}

function renderScreen() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={['/compliance']}>
        <ScreenE />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  setMatchMedia(false); // desktop → ComplianceMatrix
  useProjects.mockReturnValue({
    projects: [makeProject('vulcan'), makeProject('wan'), makeProject('acta')],
    loading: false,
    loaded: true,
    error: false,
  });
  getComplianceAll.mockResolvedValue(makeView());
  getProjects.mockResolvedValue([makeProject('vulcan'), makeProject('wan'), makeProject('acta')]);
});
afterEach(() => {
  window.matchMedia = realMatchMedia;
  vi.restoreAllMocks();
});

describe('ScreenE — cross-project compliance', () => {
  it('renders the ecosystem-score header (skóre %, blocking, notes)', async () => {
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-ecosystem-header]')).toBeInTheDocument(),
    );
    const header = container.querySelector('[data-ecosystem-header]') as HTMLElement;
    expect(header).toHaveTextContent('Skóre ekosystému');
    expect(header).toHaveTextContent('91 %');
    // 2 blocking failures (fsm_adherence + gates_report), 1 advisory (branch_match).
    expect(container.querySelector('[data-blocking-count]')).toHaveTextContent('2 blokující');
    expect(container.querySelector('[data-advisory-count]')).toHaveTextContent('1 poznámka');
  });

  it('renders force-override counts + flags SYSTEMATIC per §4.5 (5/13), one-off → "pozor"', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-violations]')).toBeInTheDocument());

    const vulcan = container.querySelector('[data-violation][data-project="vulcan"]') as HTMLElement;
    // force-override count rendered.
    expect(vulcan.querySelector('[data-force-override]')).toHaveTextContent('force-override 5');
    // SYSTEMATIC (>=3) badge present, NOT the one-off "pozor".
    expect(vulcan).toHaveAttribute('data-systematic', 'true');
    expect(vulcan.querySelector('[data-systematic-badge]')).toBeInTheDocument();
    expect(vulcan.querySelector('[data-oneoff-badge]')).not.toBeInTheDocument();

    const wan = container.querySelector('[data-violation][data-project="wan"]') as HTMLElement;
    expect(wan.querySelector('[data-force-override]')).toHaveTextContent('force-override 1');
    // one-off (count 1) → "pozor", NOT systematic.
    expect(wan).toHaveAttribute('data-systematic', 'false');
    expect(wan.querySelector('[data-systematic-badge]')).not.toBeInTheDocument();
    expect(wan.querySelector('[data-oneoff-badge]')).toBeInTheDocument();

    // ecosystem-level SYSTEMATIC (6 overrides / 13 runs >= 30%, max single 5 > 3).
    expect(container.querySelector('[data-ecosystem-systematic]')).toBeInTheDocument();
  });

  it('a project with no compliance result renders "N/A" cells, never 0%/fail', async () => {
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-compliance-matrix]')).toBeInTheDocument(),
    );
    // `acta` has no violation → its row is all-N/A (null cells), never a fail/0%.
    const actaRow = container.querySelector('[data-compliance-matrix] [data-project="acta"]') as HTMLElement;
    expect(actaRow).toBeInTheDocument();
    const cells = actaRow.querySelectorAll('td[data-check]');
    expect(cells.length).toBeGreaterThan(0);
    for (const c of cells) {
      expect(c).toHaveAttribute('data-state', 'null');
      expect(c).toHaveTextContent('N/A');
      expect(c.textContent).not.toContain('0 %');
      expect(c.textContent).not.toContain('0%');
      expect(c.textContent).not.toContain('selhalo');
    }
  });

  it('a null headline score renders "N/A", never 0%', async () => {
    getComplianceAll.mockResolvedValue(
      makeView({ fsmAdherenceScore: makeScore({ value: null, partial: true, confidence: 'low' }) }),
    );
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-ecosystem-header]')).toBeInTheDocument(),
    );
    const header = container.querySelector('[data-ecosystem-header]') as HTMLElement;
    expect(header).toHaveTextContent('N/A');
    expect(header.textContent).not.toContain('0 %');
    expect(container.querySelector('[data-score-partial]')).toBeInTheDocument();
  });

  it('"podle checku" toggle transposes the matrix (rows become checks)', async () => {
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-compliance-matrix]')).toBeInTheDocument(),
    );
    // Default by-project: a vulcan row exists.
    expect(container.querySelector('[data-compliance-matrix] [data-project="vulcan"]')).toBeInTheDocument();

    fireEvent.click(container.querySelector('[data-view="check"]') as HTMLElement);
    await waitFor(() =>
      // Transposed: a row keyed by a check id (fsm_adherence) appears.
      expect(
        container.querySelector('[data-compliance-matrix] [data-project="fsm_adherence"]'),
      ).toBeInTheDocument(),
    );
  });

  it('mobile viewport renders ComplianceCards instead of the matrix', async () => {
    setMatchMedia(true); // mobile
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-compliance-cards]')).toBeInTheDocument(),
    );
    expect(container.querySelector('[data-compliance-matrix]')).not.toBeInTheDocument();
  });

  it('getComplianceAll failure → "Compliance se nepodařilo načíst" + retry, not a crash', async () => {
    getComplianceAll.mockRejectedValue(new api.ApiError('HTTP_500', 'boom'));
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-compliance-error]')).toBeInTheDocument(),
    );
    expect(container.querySelector('[data-compliance-error]')).toHaveTextContent(
      'Compliance se nepodařilo načíst',
    );
  });

  it('a malformed failure (empty check) is skipped, never a thrown matrix', async () => {
    getComplianceAll.mockResolvedValue(
      makeView({
        violations: [
          {
            projectId: 'vulcan',
            epicId: 'E-047',
            runId: 'R-3',
            overall: 'fail',
            forceOverrideCount: 0,
            evaluatedAt: '2026-06-20T10:00:00.000Z',
            // malformed: empty check string → skipped, not crashing the fold.
            failures: [{ check: '', evidence: 'partial', severity: 'blocking' }],
          },
        ],
      }),
    );
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-compliance-matrix]')).toBeInTheDocument(),
    );
    // The matrix renders (empty-state line is acceptable) — no throw.
    expect(container.querySelector('[data-compliance-matrix]')).toBeInTheDocument();
  });
});
