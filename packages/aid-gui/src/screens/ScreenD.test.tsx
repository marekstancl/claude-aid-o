/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor, within, fireEvent, act } from '@testing-library/react';
import { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ActivityEvent, DictionaryEntry, Project } from '@aid/contract';
import { ScreenD } from './ScreenD';
import * as api from '../lib/api';
import * as projectsCtx from '../components/shell/ProjectsContext';

// No real WebSocket in jsdom.
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
  getActivity: vi.fn(),
  getProjects: vi.fn(),
  getExplanations: vi.fn(),
}));
vi.mock('../components/shell/ProjectsContext', () => ({ useProjects: vi.fn() }));

const getActivity = vi.mocked(api.getActivity);
const getProjects = vi.mocked(api.getProjects);
const getExplanations = vi.mocked(api.getExplanations);
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

function ev(over: Partial<ActivityEvent> & Pick<ActivityEvent, 'projectId' | 'ts' | 'event'>): ActivityEvent {
  return { raw: {}, ...over };
}

/** A mixed cross-project feed (newest-first by ts when returned). */
function makeFeed(): ActivityEvent[] {
  return [
    ev({
      projectId: 'vulcan',
      epicId: 'E-047',
      ts: '2026-06-20T10:05:00.000Z',
      event: 'gate_complete',
      gate: 'build',
      result: 'fail',
    }),
    ev({
      projectId: 'wan',
      epicId: 'E-202',
      ts: '2026-06-20T10:03:00.000Z',
      event: 'fsm_transition',
      from: 'READY',
      to: 'EXECUTE',
    }),
    ev({
      projectId: 'vulcan',
      epicId: 'E-047',
      ts: '2026-06-20T10:01:00.000Z',
      event: 'checkpoint',
      raw: { cp: 'CP1' },
    }),
  ];
}

const DICTIONARY: Record<string, DictionaryEntry> = {
  'event:gate_complete:fail': {
    id: 'event:gate_complete:fail',
    headlineTemplate: 'Brána selhala.',
    detailTemplate: 'Brána {gate} selhala.',
    status: 'selhalo',
  } as DictionaryEntry,
  'event:fsm_transition:READY_to_EXECUTE': {
    id: 'event:fsm_transition:READY_to_EXECUTE',
    headlineTemplate: 'Běh se rozběhl.',
    detailTemplate: 'READY → EXECUTE.',
    status: 'bezi',
  } as DictionaryEntry,
  'event:checkpoint': {
    id: 'event:checkpoint',
    headlineTemplate: 'Kontrolní bod proběhl.',
    detailTemplate: 'CP.',
    status: 'proslo',
  } as DictionaryEntry,
};

// Surface the current location so we can assert the row link target.
let lastLocation = '';
function LocationProbe() {
  const loc = useLocation();
  lastLocation = loc.pathname + loc.search;
  return null;
}

function renderScreen() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={['/activity']}>
        <Routes>
          <Route path="/activity" element={<ScreenD />} />
          <Route path="/p/:project/e/:epic" element={<LocationProbe />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  lastLocation = '';
  useProjects.mockReturnValue({
    projects: [makeProject('vulcan'), makeProject('wan')],
    loading: false,
    loaded: true,
    error: false,
  });
  getActivity.mockResolvedValue(makeFeed());
  getProjects.mockResolvedValue([makeProject('vulcan'), makeProject('wan')]);
  getExplanations.mockResolvedValue(DICTIONARY);
});
afterEach(() => vi.restoreAllMocks());

describe('ScreenD — merged live activity stream', () => {
  it('renders each row with a Czech translation (no raw JSON leaks)', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-event-feed]')).toBeInTheDocument());
    const feed = container.querySelector('[data-event-feed]') as HTMLElement;
    // Each event maps to its dictionary Czech sentence.
    expect(feed).toHaveTextContent('Brána selhala.');
    expect(feed).toHaveTextContent('Běh se rozběhl.');
    expect(feed).toHaveTextContent('Kontrolní bod proběhl.');
    // Three events → three rows, each carrying a non-empty translation.
    const rows = container.querySelectorAll('[data-activity-row]');
    expect(rows).toHaveLength(3);
    for (const r of rows) expect((r.textContent ?? '').trim().length).toBeGreaterThan(0);
  });

  it('newest-first ordering: the latest ts (gate fail) is the first row', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-event-feed]')).toBeInTheDocument());
    const rows = container.querySelectorAll('[data-activity-row]');
    expect(rows[0]).toHaveTextContent('Brána selhala.');
  });

  it('project filter narrows the feed to one project', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-event-feed]')).toBeInTheDocument());
    expect(container.querySelectorAll('[data-activity-row]')).toHaveLength(3);

    fireEvent.click(container.querySelector('[data-project-filter="wan"]') as HTMLElement);
    await waitFor(() => expect(container.querySelectorAll('[data-activity-row]')).toHaveLength(1));
    expect(container.querySelector('[data-event-feed]')).toHaveTextContent('Běh se rozběhl.');
    expect(container.querySelector('[data-event-feed]')).not.toHaveTextContent('Brána selhala.');
  });

  it('event-kind filter (FSM·CP·gate·audit) narrows by kind', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-event-feed]')).toBeInTheDocument());

    // gate-only → just the gate_complete row.
    fireEvent.click(container.querySelector('[data-kind-filter="gate"]') as HTMLElement);
    await waitFor(() => expect(container.querySelectorAll('[data-activity-row]')).toHaveLength(1));
    expect(container.querySelector('[data-event-feed]')).toHaveTextContent('Brána selhala.');

    // fsm-only → just the transition row.
    fireEvent.click(container.querySelector('[data-kind-filter="gate"]') as HTMLElement); // un-toggle
    fireEvent.click(container.querySelector('[data-kind-filter="fsm"]') as HTMLElement);
    await waitFor(() =>
      expect(container.querySelector('[data-event-feed]')).toHaveTextContent('Běh se rozběhl.'),
    );
    expect(container.querySelector('[data-event-feed]')).not.toHaveTextContent('Brána selhala.');
  });

  it('"jen důležité" severity filter keeps only the failing event', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-event-feed]')).toBeInTheDocument());
    fireEvent.click(container.querySelector('[data-important-filter]') as HTMLElement);
    await waitFor(() => expect(container.querySelectorAll('[data-activity-row]')).toHaveLength(1));
    expect(container.querySelector('[data-event-feed]')).toHaveTextContent('Brána selhala.');
  });

  it('pause freezes auto-scroll (overflow-hidden) while events keep buffering', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-event-feed]')).toBeInTheDocument());

    const toggle = container.querySelector('[data-pause-toggle]') as HTMLElement;
    expect(toggle).toHaveAttribute('aria-pressed', 'false');

    fireEvent.click(toggle);
    await waitFor(() =>
      expect(container.querySelector('[data-event-feed]')).toHaveAttribute('data-paused', 'true'),
    );
    // Auto-scroll frozen: the feed container becomes a capped, overflow-hidden box.
    const feed = container.querySelector('[data-event-feed]') as HTMLElement;
    expect(feed.className).toContain('overflow-hidden');
    expect(container.querySelector('[data-paused-note]')).toBeInTheDocument();

    // Events keep buffering: a new poll result still lands in the query cache and
    // is rendered (pause stops scrolling, NOT data flow).
    getActivity.mockResolvedValue([
      ...makeFeed(),
      ev({
        projectId: 'wan',
        epicId: 'E-202',
        ts: '2026-06-20T10:10:00.000Z',
        event: 'fsm_transition',
        from: 'EXECUTE',
        to: 'GATES',
      }),
    ]);
    // The 2s refetchInterval re-runs; rows grow even while paused.
    await waitFor(
      () => expect(container.querySelectorAll('[data-activity-row]').length).toBeGreaterThanOrEqual(4),
      { timeout: 4000 },
    );
  });

  it('a row click navigates to /p/:project/e/:epic anchored at ?ts=', async () => {
    const { container } = renderScreen();
    await waitFor(() => expect(container.querySelector('[data-event-feed]')).toBeInTheDocument());
    const firstRow = container.querySelector('[data-activity-row]') as HTMLAnchorElement;
    // The link target is the EPIC deep view anchored to the event ts.
    expect(firstRow.getAttribute('href')).toBe(
      '/p/vulcan/e/E-047?ts=2026-06-20T10%3A05%3A00.000Z',
    );
    fireEvent.click(firstRow);
    await waitFor(() => expect(lastLocation).toContain('/p/vulcan/e/E-047'));
    expect(lastLocation).toContain('ts=');
  });

  it('getActivity failure → last-good buffer + error line, never silent', async () => {
    getActivity.mockRejectedValue(new api.ApiError('NETWORK_ERROR', 'down'));
    const { container } = renderScreen();
    await waitFor(() =>
      expect(container.querySelector('[data-activity-error]')).toBeInTheDocument(),
    );
    expect(container.querySelector('[data-activity-error]')).toHaveTextContent('zkouším znovu');
  });
});
