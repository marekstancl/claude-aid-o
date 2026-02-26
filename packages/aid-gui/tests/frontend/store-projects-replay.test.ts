/**
 * Unit tests for the two newest Zustand store slices:
 *   ProjectsSlice — projects list, activeProject, projectsLoading
 *   ReplaySlice   — replayState, replayEvents, replayIndex, playbackSpeed, resetReplay
 *
 * Test approach:
 *   - Direct store access via `useStore.getState()` / `useStore.setState()`
 *   - Store is reset to initial state before every test via `useStore.getInitialState()`
 *   - Each test verifies one logical concept (behaviour, not implementation detail)
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { useStore } from '../../src/store.ts';
import type { StageLogEntryResponse } from '../../src/types/api.ts';
import type { ReplayState } from '../../src/types/store.ts';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function resetStore(): void {
  useStore.setState(useStore.getInitialState());
}

/** Minimal ApiProject factory — matches the server Project shape. */
function makeProject(overrides: { id?: string; name?: string; path?: string; active?: boolean; aidoPath?: string; registeredAt?: string; accessible?: boolean } = {}) {
  return {
    id: 'proj-001',
    name: 'My Project',
    path: '/workspace/my-project',
    aidoPath: '/workspace/my-project/.aid-o',
    registeredAt: '2026-01-01T00:00:00Z',
    accessible: true,
    active: false,
    ...overrides,
  };
}

/** Minimal StageLogEntryResponse factory for replay events. */
function makeLogEntry(overrides: Partial<StageLogEntryResponse> = {}): StageLogEntryResponse {
  return {
    timestamp: '2026-02-26T10:00:00.000Z',
    state: 'EXECUTING',
    step: 'step_1',
    action: 'dispatch_agent',
    details: 'Dispatching architect agent',
    result: 'pass',
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Test setup
// ---------------------------------------------------------------------------

beforeEach(() => {
  resetStore();
});

// ===========================================================================
// ProjectsSlice — initial state
// ===========================================================================

describe('ProjectsSlice — initial state', () => {
  it('starts with an empty projects array', () => {
    expect(useStore.getState().projects).toEqual([]);
  });

  it('starts with null activeProject', () => {
    expect(useStore.getState().activeProject).toBeNull();
  });

  it('starts with projectsLoading false', () => {
    expect(useStore.getState().projectsLoading).toBe(false);
  });
});

// ===========================================================================
// ProjectsSlice — setProjects
// ===========================================================================

describe('ProjectsSlice — setProjects', () => {
  it('replaces the projects list with a new set', () => {
    const projects = [
      makeProject({ id: 'proj-001', name: 'Alpha' }),
      makeProject({ id: 'proj-002', name: 'Beta' }),
    ];
    useStore.getState().setProjects(projects);

    const { projects: stored } = useStore.getState();
    expect(stored).toHaveLength(2);
    expect(stored[0].id).toBe('proj-001');
    expect(stored[1].name).toBe('Beta');
  });

  it('accepts an empty array to clear all projects', () => {
    useStore.getState().setProjects([makeProject()]);
    useStore.getState().setProjects([]);

    expect(useStore.getState().projects).toEqual([]);
  });

  it('replaces the previous list entirely on successive calls', () => {
    useStore.getState().setProjects([makeProject({ id: 'proj-001' }), makeProject({ id: 'proj-002' })]);
    useStore.getState().setProjects([makeProject({ id: 'proj-003' })]);

    const { projects } = useStore.getState();
    expect(projects).toHaveLength(1);
    expect(projects[0].id).toBe('proj-003');
  });

  it('preserves all project fields after set', () => {
    const project = makeProject({ id: 'proj-001', name: 'Full Project', path: '/src', active: true });
    useStore.getState().setProjects([project]);

    const stored = useStore.getState().projects[0];
    expect(stored.id).toBe('proj-001');
    expect(stored.name).toBe('Full Project');
    expect(stored.path).toBe('/src');
    expect(stored.active).toBe(true);
  });
});

// ===========================================================================
// ProjectsSlice — setActiveProject
// ===========================================================================

describe('ProjectsSlice — setActiveProject', () => {
  it('sets a project as active', () => {
    const project = makeProject({ id: 'proj-001', name: 'Active Project' });
    useStore.getState().setActiveProject(project);

    const { activeProject } = useStore.getState();
    expect(activeProject).not.toBeNull();
    expect(activeProject?.id).toBe('proj-001');
    expect(activeProject?.name).toBe('Active Project');
  });

  it('accepts null to clear the active project', () => {
    useStore.getState().setActiveProject(makeProject({ id: 'proj-001' }));
    useStore.getState().setActiveProject(null);

    expect(useStore.getState().activeProject).toBeNull();
  });

  it('replaces the previous active project when called with a different project', () => {
    useStore.getState().setActiveProject(makeProject({ id: 'proj-001', name: 'Old' }));
    useStore.getState().setActiveProject(makeProject({ id: 'proj-002', name: 'New' }));

    const { activeProject } = useStore.getState();
    expect(activeProject?.id).toBe('proj-002');
    expect(activeProject?.name).toBe('New');
  });

  it('does not affect the projects list when setting active project', () => {
    const projects = [makeProject({ id: 'proj-001' }), makeProject({ id: 'proj-002' })];
    useStore.getState().setProjects(projects);

    useStore.getState().setActiveProject(makeProject({ id: 'proj-001' }));

    // The projects list itself is unaffected
    expect(useStore.getState().projects).toHaveLength(2);
  });
});

// ===========================================================================
// ProjectsSlice — setProjectsLoading
// ===========================================================================

describe('ProjectsSlice — setProjectsLoading', () => {
  it('sets projectsLoading to true', () => {
    useStore.getState().setProjectsLoading(true);
    expect(useStore.getState().projectsLoading).toBe(true);
  });

  it('sets projectsLoading back to false', () => {
    useStore.getState().setProjectsLoading(true);
    useStore.getState().setProjectsLoading(false);
    expect(useStore.getState().projectsLoading).toBe(false);
  });

  it('is idempotent — calling true twice stays true', () => {
    useStore.getState().setProjectsLoading(true);
    useStore.getState().setProjectsLoading(true);
    expect(useStore.getState().projectsLoading).toBe(true);
  });
});

// ===========================================================================
// ProjectsSlice — project switching data refresh pattern
// ===========================================================================

describe('ProjectsSlice — project switching pattern', () => {
  it('loading flag transitions correctly during a project switch (false→true→false)', () => {
    // Simulate: user triggers project switch
    expect(useStore.getState().projectsLoading).toBe(false);

    useStore.getState().setProjectsLoading(true);
    expect(useStore.getState().projectsLoading).toBe(true);

    // Simulate: API returns new project list
    const projects = [makeProject({ id: 'proj-002', name: 'New Context' })];
    useStore.getState().setProjects(projects);
    useStore.getState().setActiveProject(projects[0]);
    useStore.getState().setProjectsLoading(false);

    expect(useStore.getState().projectsLoading).toBe(false);
    expect(useStore.getState().activeProject?.id).toBe('proj-002');
    expect(useStore.getState().projects).toHaveLength(1);
  });

  it('switching active project clears previous active and sets the new one', () => {
    const proj1 = makeProject({ id: 'proj-001', name: 'Alpha' });
    const proj2 = makeProject({ id: 'proj-002', name: 'Beta' });

    useStore.getState().setProjects([proj1, proj2]);
    useStore.getState().setActiveProject(proj1);

    // Switch to proj2
    useStore.getState().setActiveProject(proj2);

    expect(useStore.getState().activeProject?.id).toBe('proj-002');
    // Both projects still in the list
    expect(useStore.getState().projects).toHaveLength(2);
  });

  it('projects list and activeProject are independent store fields', () => {
    const proj = makeProject({ id: 'proj-001' });
    useStore.getState().setProjects([proj]);
    useStore.getState().setActiveProject(null);

    expect(useStore.getState().projects).toHaveLength(1);
    expect(useStore.getState().activeProject).toBeNull();
  });
});

// ===========================================================================
// ReplaySlice — initial state
// ===========================================================================

describe('ReplaySlice — initial state', () => {
  it('starts with replayState of idle', () => {
    expect(useStore.getState().replayState).toBe('idle');
  });

  it('starts with an empty replayEvents array', () => {
    expect(useStore.getState().replayEvents).toEqual([]);
  });

  it('starts with replayIndex of 0', () => {
    expect(useStore.getState().replayIndex).toBe(0);
  });

  it('starts with playbackSpeed of 1', () => {
    expect(useStore.getState().playbackSpeed).toBe(1);
  });
});

// ===========================================================================
// ReplaySlice — setReplayState
// ===========================================================================

describe('ReplaySlice — setReplayState', () => {
  const validStates: ReplayState[] = ['idle', 'playing', 'paused', 'scrubbing'];

  it('transitions to playing state', () => {
    useStore.getState().setReplayState('playing');
    expect(useStore.getState().replayState).toBe('playing');
  });

  it('transitions to paused state', () => {
    useStore.getState().setReplayState('playing');
    useStore.getState().setReplayState('paused');
    expect(useStore.getState().replayState).toBe('paused');
  });

  it('transitions to scrubbing state', () => {
    useStore.getState().setReplayState('scrubbing');
    expect(useStore.getState().replayState).toBe('scrubbing');
  });

  it('transitions back to idle state', () => {
    useStore.getState().setReplayState('playing');
    useStore.getState().setReplayState('idle');
    expect(useStore.getState().replayState).toBe('idle');
  });

  it('accepts all valid replay states without error', () => {
    for (const state of validStates) {
      useStore.getState().setReplayState(state);
      expect(useStore.getState().replayState).toBe(state);
    }
  });
});

// ===========================================================================
// ReplaySlice — setReplayEvents
// ===========================================================================

describe('ReplaySlice — setReplayEvents', () => {
  it('loads a list of events for replay', () => {
    const events = [
      makeLogEntry({ action: 'event_1', step: 'step_1' }),
      makeLogEntry({ action: 'event_2', step: 'step_2' }),
      makeLogEntry({ action: 'event_3', step: 'step_3' }),
    ];
    useStore.getState().setReplayEvents(events);

    const { replayEvents } = useStore.getState();
    expect(replayEvents).toHaveLength(3);
    expect(replayEvents[0].action).toBe('event_1');
    expect(replayEvents[2].action).toBe('event_3');
  });

  it('replaces the previous events list on successive calls', () => {
    useStore.getState().setReplayEvents([makeLogEntry({ action: 'old' })]);
    useStore.getState().setReplayEvents([makeLogEntry({ action: 'new_a' }), makeLogEntry({ action: 'new_b' })]);

    const { replayEvents } = useStore.getState();
    expect(replayEvents).toHaveLength(2);
    expect(replayEvents[0].action).toBe('new_a');
  });

  it('accepts an empty array to clear replay events', () => {
    useStore.getState().setReplayEvents([makeLogEntry()]);
    useStore.getState().setReplayEvents([]);
    expect(useStore.getState().replayEvents).toEqual([]);
  });

  it('preserves full event data for each entry', () => {
    const event = makeLogEntry({
      timestamp: '2026-02-26T12:00:00.000Z',
      state: 'GATES',
      step: 'step_5',
      action: 'evaluate_gate',
      details: 'Running quality gate',
      result: 'pass',
    });
    useStore.getState().setReplayEvents([event]);

    const stored = useStore.getState().replayEvents[0];
    expect(stored.timestamp).toBe('2026-02-26T12:00:00.000Z');
    expect(stored.state).toBe('GATES');
    expect(stored.step).toBe('step_5');
    expect(stored.action).toBe('evaluate_gate');
    expect(stored.result).toBe('pass');
  });
});

// ===========================================================================
// ReplaySlice — setReplayIndex
// ===========================================================================

describe('ReplaySlice — setReplayIndex', () => {
  it('advances the replay cursor to the given index', () => {
    const events = Array.from({ length: 10 }, (_, i) => makeLogEntry({ action: `event_${i}` }));
    useStore.getState().setReplayEvents(events);

    useStore.getState().setReplayIndex(5);
    expect(useStore.getState().replayIndex).toBe(5);
  });

  it('can be set to index 0 (start position)', () => {
    useStore.getState().setReplayIndex(7);
    useStore.getState().setReplayIndex(0);
    expect(useStore.getState().replayIndex).toBe(0);
  });

  it('can be set to the last event index (end position)', () => {
    const events = Array.from({ length: 5 }, (_, i) => makeLogEntry({ action: `ev_${i}` }));
    useStore.getState().setReplayEvents(events);

    useStore.getState().setReplayIndex(4);
    expect(useStore.getState().replayIndex).toBe(4);
  });

  it('correctly tracks sequential advancement through events', () => {
    useStore.getState().setReplayEvents(Array.from({ length: 20 }, (_, i) => makeLogEntry({ action: `ev_${i}` })));

    for (let i = 0; i < 20; i++) {
      useStore.getState().setReplayIndex(i);
      expect(useStore.getState().replayIndex).toBe(i);
    }
  });
});

// ===========================================================================
// ReplaySlice — setPlaybackSpeed
// ===========================================================================

describe('ReplaySlice — setPlaybackSpeed', () => {
  it('sets playback speed to 1x (normal)', () => {
    useStore.getState().setPlaybackSpeed(2);
    useStore.getState().setPlaybackSpeed(1);
    expect(useStore.getState().playbackSpeed).toBe(1);
  });

  it('sets playback speed to 2x', () => {
    useStore.getState().setPlaybackSpeed(2);
    expect(useStore.getState().playbackSpeed).toBe(2);
  });

  it('sets playback speed to 4x', () => {
    useStore.getState().setPlaybackSpeed(4);
    expect(useStore.getState().playbackSpeed).toBe(4);
  });

  it('accepts all valid SPEED_OPTIONS values (1, 2, 4)', () => {
    const speedOptions = [1, 2, 4] as const;
    for (const speed of speedOptions) {
      useStore.getState().setPlaybackSpeed(speed);
      expect(useStore.getState().playbackSpeed).toBe(speed);
    }
  });
});

// ===========================================================================
// ReplaySlice — resetReplay
// ===========================================================================

describe('ReplaySlice — resetReplay', () => {
  it('resets replayState to idle', () => {
    useStore.getState().setReplayState('playing');
    useStore.getState().resetReplay();
    expect(useStore.getState().replayState).toBe('idle');
  });

  it('clears all replay events', () => {
    useStore.getState().setReplayEvents([makeLogEntry(), makeLogEntry(), makeLogEntry()]);
    useStore.getState().resetReplay();
    expect(useStore.getState().replayEvents).toEqual([]);
  });

  it('resets replayIndex to 0', () => {
    useStore.getState().setReplayIndex(15);
    useStore.getState().resetReplay();
    expect(useStore.getState().replayIndex).toBe(0);
  });

  it('resets playbackSpeed to 1', () => {
    useStore.getState().setPlaybackSpeed(4);
    useStore.getState().resetReplay();
    expect(useStore.getState().playbackSpeed).toBe(1);
  });

  it('resets all replay fields atomically in a single call', () => {
    useStore.getState().setReplayState('paused');
    useStore.getState().setReplayEvents([makeLogEntry(), makeLogEntry()]);
    useStore.getState().setReplayIndex(8);
    useStore.getState().setPlaybackSpeed(2);

    useStore.getState().resetReplay();

    const state = useStore.getState();
    expect(state.replayState).toBe('idle');
    expect(state.replayEvents).toEqual([]);
    expect(state.replayIndex).toBe(0);
    expect(state.playbackSpeed).toBe(1);
  });

  it('is safe to call when already in initial state (idempotent)', () => {
    useStore.getState().resetReplay();

    const state = useStore.getState();
    expect(state.replayState).toBe('idle');
    expect(state.replayEvents).toEqual([]);
    expect(state.replayIndex).toBe(0);
    expect(state.playbackSpeed).toBe(1);
  });
});

// ===========================================================================
// ReplaySlice — replay accuracy (index vs events consistency)
// ===========================================================================

describe('ReplaySlice — replay accuracy and event ordering', () => {
  it('events are stored in insertion order and accessible by index', () => {
    const events = [
      makeLogEntry({ action: 'start_pipeline', state: 'PLAN_REVIEW' }),
      makeLogEntry({ action: 'approve_plan', state: 'PLAN_REVIEW' }),
      makeLogEntry({ action: 'dispatch_architect', state: 'EXECUTING' }),
      makeLogEntry({ action: 'dispatch_backend', state: 'EXECUTING' }),
      makeLogEntry({ action: 'evaluate_gate', state: 'GATES' }),
    ];
    useStore.getState().setReplayEvents(events);

    const stored = useStore.getState().replayEvents;
    expect(stored[0].action).toBe('start_pipeline');
    expect(stored[1].action).toBe('approve_plan');
    expect(stored[2].action).toBe('dispatch_architect');
    expect(stored[3].action).toBe('dispatch_backend');
    expect(stored[4].action).toBe('evaluate_gate');
  });

  it('replayIndex correctly identifies the current event during playback', () => {
    const events = [
      makeLogEntry({ action: 'event_0' }),
      makeLogEntry({ action: 'event_1' }),
      makeLogEntry({ action: 'event_2' }),
    ];
    useStore.getState().setReplayEvents(events);

    // Simulate advancing through replay
    useStore.getState().setReplayState('playing');
    useStore.getState().setReplayIndex(1);

    const { replayEvents, replayIndex } = useStore.getState();
    // The current event at replayIndex should be event_1
    expect(replayEvents[replayIndex].action).toBe('event_1');
  });

  it('scrubbing state allows setting arbitrary index positions', () => {
    const events = Array.from({ length: 50 }, (_, i) =>
      makeLogEntry({ action: `ev_${i}`, step: `step_${Math.floor(i / 5)}` })
    );
    useStore.getState().setReplayEvents(events);
    useStore.getState().setReplayState('scrubbing');
    useStore.getState().setReplayIndex(35);

    const { replayState, replayIndex, replayEvents } = useStore.getState();
    expect(replayState).toBe('scrubbing');
    expect(replayIndex).toBe(35);
    expect(replayEvents[35].action).toBe('ev_35');
  });

  it('loading new events for replay resets the index correctly via resetReplay', () => {
    // First replay session
    useStore.getState().setReplayEvents([makeLogEntry(), makeLogEntry()]);
    useStore.getState().setReplayState('playing');
    useStore.getState().setReplayIndex(1);

    // New replay session: reset then load new events
    useStore.getState().resetReplay();
    const newEvents = [makeLogEntry({ action: 'session2_event_0' })];
    useStore.getState().setReplayEvents(newEvents);

    expect(useStore.getState().replayIndex).toBe(0);
    expect(useStore.getState().replayState).toBe('idle');
    expect(useStore.getState().replayEvents[0].action).toBe('session2_event_0');
  });
});

// ===========================================================================
// Cross-slice isolation — ProjectsSlice and ReplaySlice
// ===========================================================================

describe('Cross-slice isolation — ProjectsSlice and ReplaySlice coexist', () => {
  it('setting replay events does not affect the projects list', () => {
    const projects = [makeProject({ id: 'proj-001' }), makeProject({ id: 'proj-002' })];
    useStore.getState().setProjects(projects);

    useStore.getState().setReplayEvents([makeLogEntry(), makeLogEntry(), makeLogEntry()]);
    useStore.getState().setReplayState('playing');
    useStore.getState().setReplayIndex(2);

    expect(useStore.getState().projects).toHaveLength(2);
    expect(useStore.getState().projects[0].id).toBe('proj-001');
  });

  it('switching active project does not corrupt replay state', () => {
    useStore.getState().setReplayEvents([makeLogEntry({ action: 'preserved' })]);
    useStore.getState().setReplayState('paused');
    useStore.getState().setReplayIndex(0);

    useStore.getState().setActiveProject(makeProject({ id: 'proj-001' }));
    useStore.getState().setProjectsLoading(true);
    useStore.getState().setProjectsLoading(false);

    expect(useStore.getState().replayState).toBe('paused');
    expect(useStore.getState().replayEvents).toHaveLength(1);
    expect(useStore.getState().replayEvents[0].action).toBe('preserved');
    expect(useStore.getState().replayIndex).toBe(0);
  });

  it('resetReplay does not affect projects or activeProject', () => {
    const project = makeProject({ id: 'proj-001', name: 'Stable' });
    useStore.getState().setProjects([project]);
    useStore.getState().setActiveProject(project);

    useStore.getState().setReplayEvents([makeLogEntry()]);
    useStore.getState().setReplayState('playing');
    useStore.getState().resetReplay();

    expect(useStore.getState().projects).toHaveLength(1);
    expect(useStore.getState().activeProject?.id).toBe('proj-001');
  });

  it('ProjectsSlice and ReplaySlice changes do not affect ConnectionSlice', () => {
    useStore.getState().setWsStatus('connected');
    useStore.getState().handleHeartbeat('2026-02-26T10:00:00.000Z', 3);

    useStore.getState().setProjects([makeProject()]);
    useStore.getState().setActiveProject(makeProject());
    useStore.getState().setReplayEvents([makeLogEntry()]);
    useStore.getState().setReplayState('playing');

    expect(useStore.getState().wsStatus).toBe('connected');
    expect(useStore.getState().serverClientCount).toBe(3);
  });

  it('replay operations do not affect stage log entries', () => {
    useStore.getState().addStageLogEntry(makeLogEntry({ action: 'live_event' }));

    useStore.getState().setReplayEvents([makeLogEntry({ action: 'replay_event_1' }), makeLogEntry({ action: 'replay_event_2' })]);
    useStore.getState().setReplayState('playing');
    useStore.getState().setReplayIndex(1);

    // Stage log (live) should be untouched
    expect(useStore.getState().stageLogEntries).toHaveLength(1);
    expect(useStore.getState().stageLogEntries[0].action).toBe('live_event');

    // Replay events are separate
    expect(useStore.getState().replayEvents).toHaveLength(2);
  });
});

// ===========================================================================
// Store reset validation for new slices
// ===========================================================================

describe('Store reset — ProjectsSlice and ReplaySlice are reset between tests', () => {
  it('state set in this test does not leak (first test)', () => {
    useStore.getState().setProjects([makeProject({ id: 'proj-001' }), makeProject({ id: 'proj-002' })]);
    useStore.getState().setActiveProject(makeProject({ id: 'proj-001' }));
    useStore.getState().setReplayEvents([makeLogEntry(), makeLogEntry()]);
    useStore.getState().setReplayState('playing');
    useStore.getState().setReplayIndex(1);
    useStore.getState().setPlaybackSpeed(4);

    expect(useStore.getState().projects).toHaveLength(2);
    expect(useStore.getState().replayState).toBe('playing');
  });

  it('state from previous test is fully reset (second test)', () => {
    // After beforeEach reset, all state must be back to initial defaults
    expect(useStore.getState().projects).toEqual([]);
    expect(useStore.getState().activeProject).toBeNull();
    expect(useStore.getState().projectsLoading).toBe(false);
    expect(useStore.getState().replayState).toBe('idle');
    expect(useStore.getState().replayEvents).toEqual([]);
    expect(useStore.getState().replayIndex).toBe(0);
    expect(useStore.getState().playbackSpeed).toBe(1);
  });
});
