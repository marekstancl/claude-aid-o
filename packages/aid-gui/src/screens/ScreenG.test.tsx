/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { Brief, Project } from '@aid/contract';
import { ScreenG } from './ScreenG';
import * as api from '../lib/api';
import * as lastSeen from '../lib/lastSeen';

vi.mock('../lib/api', () => ({
  getBrief: vi.fn(),
  getProjects: vi.fn(),
}));
vi.mock('../lib/lastSeen', () => ({
  getLastSeen: vi.fn(),
  setLastSeen: vi.fn(),
}));

const getBrief = vi.mocked(api.getBrief);
const getProjects = vi.mocked(api.getProjects);
const getLastSeen = vi.mocked(lastSeen.getLastSeen);

/** Build an infra-scope Brief; callers override the slices they assert on. */
function makeBrief(over: Partial<Brief> = {}): Brief {
  return {
    scope: 'infra',
    projectId: null,
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
    risk: { level: 'stredni', reasons: [], confidence: 'high' },
    successProbability: { value: null, source: null },
    ...over,
  };
}

function makeProject(id: string): Project {
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
  };
}

function renderScreen() {
  // retry:false so an error query settles immediately for the error-surface test.
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={['/']}>
        <ScreenG />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  getProjects.mockResolvedValue([makeProject('wan'), makeProject('krok')]);
});
afterEach(() => vi.restoreAllMocks());

describe('ScreenG — infra managerial brief landing', () => {
  it('renders the decisions/blockers as the FIRST content region — no tile grid precedes them', async () => {
    getLastSeen.mockReturnValue(null);
    getBrief.mockResolvedValue(makeBrief());

    const { container } = renderScreen();

    // Wait for the brief to render (the "Rozhodnutí" decisions list).
    await waitFor(() => expect(container.querySelector('[data-decisions-empty]')).toBeInTheDocument());

    const decisions = container.querySelector('[data-decisions-empty]') as HTMLElement;
    const grid = container.querySelector('[data-project-grid]') as HTMLElement;
    expect(decisions).toBeInTheDocument();
    expect(grid).toBeInTheDocument();

    // Document order: the decisions region must come BEFORE the tile grid.
    const position = decisions.compareDocumentPosition(grid);
    // DOCUMENT_POSITION_FOLLOWING (4) = grid follows decisions.
    expect(position & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('renders the embedded "Přehled projektů" tiles BELOW the brief blocks', async () => {
    getLastSeen.mockReturnValue(null);
    getBrief.mockResolvedValue(makeBrief());

    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-project-grid]')).toBeInTheDocument());

    const riziko = container.querySelector('[data-risk-block]') as HTMLElement;
    const grid = container.querySelector('[data-project-grid]') as HTMLElement;
    // The tile grid follows the Riziko block (i.e. it is the LAST §8.2 section).
    expect(riziko.compareDocumentPosition(grid) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    // The grid actually rendered the projects, not the empty state.
    expect(grid).not.toHaveAttribute('data-empty');
  });

  it('renders the RiskBadge with the infra risk.level', async () => {
    getLastSeen.mockReturnValue(null);
    getBrief.mockResolvedValue(makeBrief({ risk: { level: 'vysoke', reasons: [], confidence: 'high' } }));

    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-risk-badge]')).toBeInTheDocument());

    const badge = container.querySelector('[data-risk-badge]') as HTMLElement;
    expect(badge).toHaveAttribute('data-level', 'vysoke');
    expect(badge).toHaveTextContent('vysoké');
  });

  it('renders the literal MVP2 placeholder for the success-probability slot (never a number)', async () => {
    getLastSeen.mockReturnValue(null);
    getBrief.mockResolvedValue(makeBrief());

    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-success-probability]')).toBeInTheDocument());

    const slot = container.querySelector('[data-success-probability]') as HTMLElement;
    expect(slot).toHaveTextContent(/MVP2/);
    expect(slot.textContent ?? '').not.toMatch(/\d+\s*%/);
  });

  it('first visit (since===null) → "první návštěva" line, no comparison', async () => {
    getLastSeen.mockReturnValue(null);
    getBrief.mockResolvedValue(makeBrief({ sinceLastSeen: { since: null, items: [], counts: { newRuns: 0, newGateFails: 0, newViolations: 0, newBacklog: 0, stateTransitions: 0 } } }));

    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-since-firstvisit]')).toBeInTheDocument());

    expect(screen.getByText(/První návštěva/)).toBeInTheDocument();
    // getBrief was called with no `since` (first visit passes undefined).
    expect(getBrief).toHaveBeenCalledWith({}, undefined);
  });

  it('with a stored lastSeen → the brief is fetched with that since and shows the changed-since counts', async () => {
    const since = '2026-06-19T08:00:00.000Z';
    getLastSeen.mockReturnValue(since);
    getBrief.mockResolvedValue(
      makeBrief({
        sinceLastSeen: {
          since,
          items: [],
          counts: { newRuns: 3, newGateFails: 1, newViolations: 0, newBacklog: 2, stateTransitions: 0 },
        },
      }),
    );

    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-since-list], [data-since-empty]')).toBeTruthy());

    // The brief request carried the stored lastSeen as `since`.
    expect(getBrief).toHaveBeenCalledWith({}, since);
    // No first-visit line when since is set.
    expect(container.querySelector('[data-since-firstvisit]')).not.toBeInTheDocument();
    // The counts pill reflects sinceLastSeen.counts.
    expect(screen.getByText(/3 běhů/)).toBeInTheDocument();
  });

  it('on a brief failure renders the error surface but still shows the project tiles', async () => {
    getLastSeen.mockReturnValue(null);
    getBrief.mockRejectedValue(new Error('boom'));

    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-brief-error]')).toBeInTheDocument());

    expect(screen.getByText(/Brief se nepodařilo načíst/)).toBeInTheDocument();
    // Tiles survive a failed brief (independent /api/projects query).
    await waitFor(() => expect(container.querySelector('[data-project-grid]')).toBeInTheDocument());
    expect(container.querySelector('[data-project-grid]')).not.toHaveAttribute('data-empty');
  });
});
