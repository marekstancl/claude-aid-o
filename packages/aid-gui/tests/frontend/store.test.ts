/**
 * Unit tests for the Zustand dashboard store slices (`src/store.ts`).
 *
 * Each slice is tested independently.  Between tests the store is reset to
 * its initial state using `useStore.setState(useStore.getInitialState())`.
 * This ensures no state leaks across tests even though all tests share the
 * same singleton store instance.
 *
 * Slice coverage:
 *   ConnectionSlice   — wsStatus, heartbeat, reconnect counter, topics
 *   PipelineSlice     — pipeline state, steps, step statuses
 *   StageLogSlice     — add single entry, bulk add, clear, 500-entry cap
 *   SatelliteSlice    — queue, health score, decisions, cc usage
 *   LegacySlice       — project, FSM state, updatePipeline partial update
 *   Combined store    — slices coexist; one slice's actions don't corrupt others
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { useStore } from '../../src/store.ts';
import type { StageLogEntryResponse } from '../../src/types/api.ts';
import type { StepStatus } from '../../src/types/store.ts';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Reset the singleton store to its initial state before every test. */
function resetStore(): void {
  useStore.setState(useStore.getInitialState());
}

/** Build a minimal stage log entry. */
function makeLogEntry(overrides: Partial<StageLogEntryResponse> = {}): StageLogEntryResponse {
  return {
    timestamp: '2026-02-25T10:00:00.000Z',
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

// ---------------------------------------------------------------------------
// ConnectionSlice
// ---------------------------------------------------------------------------

describe('ConnectionSlice — initial state', () => {
  it('starts with disconnected status', () => {
    const { wsStatus } = useStore.getState();
    expect(wsStatus).toBe('disconnected');
  });

  it('starts with null lastHeartbeat', () => {
    const { lastHeartbeat } = useStore.getState();
    expect(lastHeartbeat).toBeNull();
  });

  it('starts with reconnectAttempt of 0', () => {
    const { reconnectAttempt } = useStore.getState();
    expect(reconnectAttempt).toBe(0);
  });

  it('starts with empty subscribedTopics array', () => {
    const { subscribedTopics } = useStore.getState();
    expect(subscribedTopics).toEqual([]);
  });
});

describe('ConnectionSlice — setWsStatus', () => {
  it('updates wsStatus to connecting', () => {
    useStore.getState().setWsStatus('connecting');
    expect(useStore.getState().wsStatus).toBe('connecting');
  });

  it('updates wsStatus to connected', () => {
    useStore.getState().setWsStatus('connected');
    expect(useStore.getState().wsStatus).toBe('connected');
  });

  it('updates wsStatus to reconnecting', () => {
    useStore.getState().setWsStatus('reconnecting');
    expect(useStore.getState().wsStatus).toBe('reconnecting');
  });

  it('updates wsStatus to disconnected', () => {
    useStore.getState().setWsStatus('connected');
    useStore.getState().setWsStatus('disconnected');
    expect(useStore.getState().wsStatus).toBe('disconnected');
  });
});

describe('ConnectionSlice — handleHeartbeat', () => {
  it('stores the heartbeat timestamp', () => {
    const ts = '2026-02-25T10:30:00.000Z';
    useStore.getState().handleHeartbeat(ts, 3);
    expect(useStore.getState().lastHeartbeat).toBe(ts);
  });

  it('stores the server client count', () => {
    useStore.getState().handleHeartbeat('2026-02-25T10:30:00.000Z', 7);
    expect(useStore.getState().serverClientCount).toBe(7);
  });

  it('updates on subsequent heartbeats', () => {
    useStore.getState().handleHeartbeat('2026-02-25T10:00:00.000Z', 1);
    useStore.getState().handleHeartbeat('2026-02-25T10:30:00.000Z', 2);
    expect(useStore.getState().lastHeartbeat).toBe('2026-02-25T10:30:00.000Z');
    expect(useStore.getState().serverClientCount).toBe(2);
  });
});

describe('ConnectionSlice — reconnect attempt counter', () => {
  it('incrementReconnectAttempt increases counter by 1 each call', () => {
    useStore.getState().incrementReconnectAttempt();
    expect(useStore.getState().reconnectAttempt).toBe(1);
    useStore.getState().incrementReconnectAttempt();
    expect(useStore.getState().reconnectAttempt).toBe(2);
    useStore.getState().incrementReconnectAttempt();
    expect(useStore.getState().reconnectAttempt).toBe(3);
  });

  it('resetReconnectAttempt returns counter to 0', () => {
    useStore.getState().incrementReconnectAttempt();
    useStore.getState().incrementReconnectAttempt();
    useStore.getState().resetReconnectAttempt();
    expect(useStore.getState().reconnectAttempt).toBe(0);
  });

  it('resetReconnectAttempt is idempotent when already at 0', () => {
    useStore.getState().resetReconnectAttempt();
    expect(useStore.getState().reconnectAttempt).toBe(0);
  });
});

describe('ConnectionSlice — setSubscribedTopics', () => {
  it('stores the provided topics array', () => {
    const topics = ['pipeline', 'queue'] as const;
    useStore.getState().setSubscribedTopics([...topics]);
    expect(useStore.getState().subscribedTopics).toEqual(['pipeline', 'queue']);
  });

  it('replaces the previous topics array entirely', () => {
    useStore.getState().setSubscribedTopics(['pipeline', 'queue', 'audit']);
    useStore.getState().setSubscribedTopics(['decisions']);
    expect(useStore.getState().subscribedTopics).toEqual(['decisions']);
  });

  it('accepts an empty array to clear subscriptions', () => {
    useStore.getState().setSubscribedTopics(['pipeline']);
    useStore.getState().setSubscribedTopics([]);
    expect(useStore.getState().subscribedTopics).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// PipelineSlice
// ---------------------------------------------------------------------------

describe('PipelineSlice — initial state', () => {
  it('starts with IDLE state', () => {
    expect(useStore.getState().currentState).toBe('IDLE');
  });

  it('starts with null currentEpicId and currentStepId', () => {
    const { currentEpicId, currentStepId } = useStore.getState();
    expect(currentEpicId).toBeNull();
    expect(currentStepId).toBeNull();
  });

  it('starts with zeroed pipeline progress', () => {
    const { pipelineProgress } = useStore.getState();
    expect(pipelineProgress.epicsCompleted).toBe(0);
    expect(pipelineProgress.epicsTotal).toBe(0);
    expect(pipelineProgress.stepsCompleted).toBe(0);
    expect(pipelineProgress.stepsTotal).toBe(0);
  });

  it('starts with empty steps array', () => {
    expect(useStore.getState().steps).toEqual([]);
  });

  it('starts with empty stepStatuses object', () => {
    expect(useStore.getState().stepStatuses).toEqual({});
  });
});

describe('PipelineSlice — setPipelineState', () => {
  it('updates all pipeline state fields atomically', () => {
    useStore.getState().setPipelineState({
      currentState: 'EXECUTING',
      currentEpicId: 'E-001',
      currentStepId: 'step_3',
      progress: { epicsCompleted: 1, epicsTotal: 2, stepsCompleted: 3, stepsTotal: 10 },
    });

    const state = useStore.getState();
    expect(state.currentState).toBe('EXECUTING');
    expect(state.currentEpicId).toBe('E-001');
    expect(state.currentStepId).toBe('step_3');
    expect(state.pipelineProgress.stepsCompleted).toBe(3);
    expect(state.pipelineProgress.stepsTotal).toBe(10);
  });

  it('allows null for epicId and stepId (idle state)', () => {
    useStore.getState().setPipelineState({
      currentState: 'IDLE',
      currentEpicId: null,
      currentStepId: null,
      progress: { epicsCompleted: 0, epicsTotal: 0, stepsCompleted: 0, stepsTotal: 0 },
    });

    const state = useStore.getState();
    expect(state.currentEpicId).toBeNull();
    expect(state.currentStepId).toBeNull();
  });

  it('can be called multiple times, always reflecting the latest call', () => {
    useStore.getState().setPipelineState({
      currentState: 'GATES',
      currentEpicId: 'E-001',
      currentStepId: null,
      progress: { epicsCompleted: 0, epicsTotal: 1, stepsCompleted: 5, stepsTotal: 5 },
    });
    useStore.getState().setPipelineState({
      currentState: 'DONE',
      currentEpicId: 'E-001',
      currentStepId: null,
      progress: { epicsCompleted: 1, epicsTotal: 1, stepsCompleted: 5, stepsTotal: 5 },
    });

    expect(useStore.getState().currentState).toBe('DONE');
    expect(useStore.getState().pipelineProgress.epicsCompleted).toBe(1);
  });
});

describe('PipelineSlice — setSteps', () => {
  it('replaces the steps array', () => {
    useStore.getState().setSteps([
      { id: 'step_1', role: 'architect', objective: 'Design' },
      { id: 'step_2', role: 'backend', objective: 'Implement' },
    ]);

    const { steps } = useStore.getState();
    expect(steps).toHaveLength(2);
    expect(steps[0].id).toBe('step_1');
    expect(steps[1].role).toBe('backend');
  });

  it('accepts an empty array to clear steps', () => {
    useStore.getState().setSteps([{ id: 'step_1', role: 'qa', objective: 'Test' }]);
    useStore.getState().setSteps([]);
    expect(useStore.getState().steps).toEqual([]);
  });
});

describe('PipelineSlice — updateStepStatus', () => {
  it('adds a new step status entry by stepId', () => {
    const status: StepStatus = { status: 'executing', startedAt: '2026-02-25T10:00:00.000Z' };
    useStore.getState().updateStepStatus('step_1', status);

    const { stepStatuses } = useStore.getState();
    expect(stepStatuses['step_1']).toBeDefined();
    expect(stepStatuses['step_1'].status).toBe('executing');
  });

  it('overwrites an existing step status', () => {
    useStore.getState().updateStepStatus('step_1', { status: 'executing' });
    useStore.getState().updateStepStatus('step_1', {
      status: 'done',
      completedAt: '2026-02-25T10:05:00.000Z',
    });

    expect(useStore.getState().stepStatuses['step_1'].status).toBe('done');
    expect(useStore.getState().stepStatuses['step_1'].completedAt).toBe('2026-02-25T10:05:00.000Z');
  });

  it('preserves other step statuses when updating one step', () => {
    useStore.getState().updateStepStatus('step_1', { status: 'done' });
    useStore.getState().updateStepStatus('step_2', { status: 'executing' });
    useStore.getState().updateStepStatus('step_1', { status: 'failed' });

    expect(useStore.getState().stepStatuses['step_1'].status).toBe('failed');
    expect(useStore.getState().stepStatuses['step_2'].status).toBe('executing');
  });
});

// ---------------------------------------------------------------------------
// StageLogSlice
// ---------------------------------------------------------------------------

describe('StageLogSlice — initial state', () => {
  it('starts with empty stageLogEntries array', () => {
    expect(useStore.getState().stageLogEntries).toEqual([]);
  });

  it('starts with max entries limit of 500', () => {
    expect(useStore.getState().stageLogMaxEntries).toBe(500);
  });
});

describe('StageLogSlice — addStageLogEntry (single)', () => {
  it('appends a single entry to an empty log', () => {
    const entry = makeLogEntry({ action: 'first_action' });
    useStore.getState().addStageLogEntry(entry);

    const { stageLogEntries } = useStore.getState();
    expect(stageLogEntries).toHaveLength(1);
    expect(stageLogEntries[0].action).toBe('first_action');
  });

  it('appends successive entries in arrival order', () => {
    useStore.getState().addStageLogEntry(makeLogEntry({ action: 'action_a' }));
    useStore.getState().addStageLogEntry(makeLogEntry({ action: 'action_b' }));
    useStore.getState().addStageLogEntry(makeLogEntry({ action: 'action_c' }));

    const { stageLogEntries } = useStore.getState();
    expect(stageLogEntries).toHaveLength(3);
    expect(stageLogEntries[0].action).toBe('action_a');
    expect(stageLogEntries[1].action).toBe('action_b');
    expect(stageLogEntries[2].action).toBe('action_c');
  });
});

describe('StageLogSlice — addStageLogEntries (bulk)', () => {
  it('appends multiple entries in a single call', () => {
    const entries = [
      makeLogEntry({ action: 'replay_1' }),
      makeLogEntry({ action: 'replay_2' }),
      makeLogEntry({ action: 'replay_3' }),
    ];
    useStore.getState().addStageLogEntries(entries);

    const { stageLogEntries } = useStore.getState();
    expect(stageLogEntries).toHaveLength(3);
    expect(stageLogEntries[0].action).toBe('replay_1');
    expect(stageLogEntries[2].action).toBe('replay_3');
  });

  it('appends bulk entries after existing single entries', () => {
    useStore.getState().addStageLogEntry(makeLogEntry({ action: 'existing' }));
    useStore.getState().addStageLogEntries([
      makeLogEntry({ action: 'bulk_1' }),
      makeLogEntry({ action: 'bulk_2' }),
    ]);

    const { stageLogEntries } = useStore.getState();
    expect(stageLogEntries).toHaveLength(3);
    expect(stageLogEntries[0].action).toBe('existing');
    expect(stageLogEntries[1].action).toBe('bulk_1');
  });

  it('accepts an empty array without changing state', () => {
    useStore.getState().addStageLogEntry(makeLogEntry({ action: 'before' }));
    useStore.getState().addStageLogEntries([]);

    expect(useStore.getState().stageLogEntries).toHaveLength(1);
  });
});

describe('StageLogSlice — clearStageLog', () => {
  it('empties the log after entries have been added', () => {
    useStore.getState().addStageLogEntry(makeLogEntry());
    useStore.getState().addStageLogEntry(makeLogEntry());
    useStore.getState().clearStageLog();

    expect(useStore.getState().stageLogEntries).toEqual([]);
  });

  it('is safe to call on an already-empty log', () => {
    useStore.getState().clearStageLog();
    expect(useStore.getState().stageLogEntries).toEqual([]);
  });
});

describe('StageLogSlice — 500-entry buffer cap', () => {
  it('does not discard entries when exactly at the limit', () => {
    const entries = Array.from({ length: 500 }, (_, i) =>
      makeLogEntry({ action: `action_${i}`, timestamp: `2026-02-25T10:${String(i).padStart(2, '0')}:00.000Z` }),
    );
    useStore.getState().addStageLogEntries(entries);

    expect(useStore.getState().stageLogEntries).toHaveLength(500);
    expect(useStore.getState().stageLogEntries[0].action).toBe('action_0');
    expect(useStore.getState().stageLogEntries[499].action).toBe('action_499');
  });

  it('discards oldest entries when the buffer exceeds 500', () => {
    // Fill to exactly 500
    const initial = Array.from({ length: 500 }, (_, i) =>
      makeLogEntry({ action: `old_${i}` }),
    );
    useStore.getState().addStageLogEntries(initial);

    // Add one more — should push out the oldest
    useStore.getState().addStageLogEntry(makeLogEntry({ action: 'new_entry' }));

    const { stageLogEntries } = useStore.getState();
    expect(stageLogEntries).toHaveLength(500);
    expect(stageLogEntries[0].action).toBe('old_1');
    expect(stageLogEntries[499].action).toBe('new_entry');
  });

  it('drops all oldest entries when a large bulk add exceeds the cap', () => {
    // Add 100 entries first
    useStore.getState().addStageLogEntries(
      Array.from({ length: 100 }, (_, i) => makeLogEntry({ action: `early_${i}` })),
    );

    // Bulk add 450 more — total = 550, should keep only the last 500
    useStore.getState().addStageLogEntries(
      Array.from({ length: 450 }, (_, i) => makeLogEntry({ action: `late_${i}` })),
    );

    const { stageLogEntries } = useStore.getState();
    expect(stageLogEntries).toHaveLength(500);
    // The first 50 early entries should be discarded (100 + 450 - 500 = 50 dropped)
    expect(stageLogEntries[0].action).toBe('early_50');
    expect(stageLogEntries[499].action).toBe('late_449');
  });
});

// ---------------------------------------------------------------------------
// SatelliteSlice
// ---------------------------------------------------------------------------

describe('SatelliteSlice — initial state', () => {
  it('starts with queueCount of 0 and queuePaused false', () => {
    const { queueCount, queuePaused } = useStore.getState();
    expect(queueCount).toBe(0);
    expect(queuePaused).toBe(false);
  });

  it('starts with null healthScore', () => {
    expect(useStore.getState().healthScore).toBeNull();
  });

  it('starts with pendingDecisions of 0', () => {
    expect(useStore.getState().pendingDecisions).toBe(0);
  });

  it('starts with zeroed ccUsage', () => {
    const { ccUsage } = useStore.getState();
    expect(ccUsage.totalEvents).toBe(0);
    expect(ccUsage.agentDispatches).toBe(0);
    expect(ccUsage.gateEvaluations).toBe(0);
    expect(ccUsage.escalations).toBe(0);
  });
});

describe('SatelliteSlice — setQueueInfo', () => {
  it('updates queueCount and queuePaused together', () => {
    useStore.getState().setQueueInfo(5, true);

    expect(useStore.getState().queueCount).toBe(5);
    expect(useStore.getState().queuePaused).toBe(true);
  });

  it('can set queueCount to 0 with paused false', () => {
    useStore.getState().setQueueInfo(3, true);
    useStore.getState().setQueueInfo(0, false);

    expect(useStore.getState().queueCount).toBe(0);
    expect(useStore.getState().queuePaused).toBe(false);
  });
});

describe('SatelliteSlice — setHealthScore', () => {
  it('sets a numeric health score', () => {
    useStore.getState().setHealthScore(92);
    expect(useStore.getState().healthScore).toBe(92);
  });

  it('allows setting health score to null (no audit data)', () => {
    useStore.getState().setHealthScore(80);
    useStore.getState().setHealthScore(null);
    expect(useStore.getState().healthScore).toBeNull();
  });

  it('accepts boundary values 0 and 100', () => {
    useStore.getState().setHealthScore(0);
    expect(useStore.getState().healthScore).toBe(0);

    useStore.getState().setHealthScore(100);
    expect(useStore.getState().healthScore).toBe(100);
  });
});

describe('SatelliteSlice — setPendingDecisions', () => {
  it('updates pending decision count', () => {
    useStore.getState().setPendingDecisions(3);
    expect(useStore.getState().pendingDecisions).toBe(3);
  });

  it('can reset pending decisions to 0', () => {
    useStore.getState().setPendingDecisions(5);
    useStore.getState().setPendingDecisions(0);
    expect(useStore.getState().pendingDecisions).toBe(0);
  });
});

describe('SatelliteSlice — setCcUsage', () => {
  it('replaces all ccUsage fields', () => {
    useStore.getState().setCcUsage({
      totalEvents: 200,
      agentDispatches: 60,
      gateEvaluations: 15,
      escalations: 4,
    });

    const { ccUsage } = useStore.getState();
    expect(ccUsage.totalEvents).toBe(200);
    expect(ccUsage.agentDispatches).toBe(60);
    expect(ccUsage.gateEvaluations).toBe(15);
    expect(ccUsage.escalations).toBe(4);
  });

  it('replaces previous ccUsage on subsequent calls', () => {
    useStore.getState().setCcUsage({ totalEvents: 50, agentDispatches: 10, gateEvaluations: 2, escalations: 0 });
    useStore.getState().setCcUsage({ totalEvents: 100, agentDispatches: 20, gateEvaluations: 5, escalations: 1 });

    expect(useStore.getState().ccUsage.totalEvents).toBe(100);
  });
});

// ---------------------------------------------------------------------------
// LegacySlice
// ---------------------------------------------------------------------------

describe('LegacySlice — initial state', () => {
  it('starts with null currentProject', () => {
    expect(useStore.getState().currentProject).toBeNull();
  });

  it('starts with IDLE fsmState', () => {
    expect(useStore.getState().fsmState).toBe('IDLE');
  });

  it('starts with progress 0 and null activeStep, epic, duration', () => {
    const { progress, activeStep, epic, duration } = useStore.getState();
    expect(progress).toBe(0);
    expect(activeStep).toBeNull();
    expect(epic).toBeNull();
    expect(duration).toBeNull();
  });
});

describe('LegacySlice — setProject', () => {
  it('stores the project object', () => {
    const project = { id: 'proj-1', name: 'My Project', health: 85 };
    useStore.getState().setProject(project);

    expect(useStore.getState().currentProject).toEqual(project);
  });

  it('replaces the previous project on successive calls', () => {
    useStore.getState().setProject({ id: 'proj-1', name: 'Old', health: 50 });
    useStore.getState().setProject({ id: 'proj-2', name: 'New', health: 90 });

    expect(useStore.getState().currentProject?.id).toBe('proj-2');
    expect(useStore.getState().currentProject?.name).toBe('New');
  });
});

describe('LegacySlice — setFSMState', () => {
  it('updates fsmState to any valid legacy FSM state', () => {
    const states = [
      'PLAN_REVIEW', 'PLAN_READY', 'EXECUTING', 'PHASE_CHECK',
      'PHASE_RETRY', 'GATES', 'GATES_RETRY', 'PM_APPROVAL',
      'CURATOR_RESOLVE', 'DONE', 'ERROR',
    ] as const;

    for (const state of states) {
      useStore.getState().setFSMState(state);
      expect(useStore.getState().fsmState).toBe(state);
    }
  });
});

describe('LegacySlice — updatePipeline', () => {
  it('performs a partial update of pipeline fields', () => {
    useStore.getState().updatePipeline({
      fsmState: 'EXECUTING',
      epic: 'E-003',
    });

    const state = useStore.getState();
    expect(state.fsmState).toBe('EXECUTING');
    expect(state.epic).toBe('E-003');
    // Untouched fields remain at defaults
    expect(state.progress).toBe(0);
    expect(state.activeStep).toBeNull();
  });

  it('updates progress percentage', () => {
    useStore.getState().updatePipeline({ progress: 60 });
    expect(useStore.getState().progress).toBe(60);
  });

  it('updates activeStep and duration', () => {
    useStore.getState().updatePipeline({
      activeStep: 'step_5',
      duration: '3m 15s',
    });

    expect(useStore.getState().activeStep).toBe('step_5');
    expect(useStore.getState().duration).toBe('3m 15s');
  });

  it('does not apply undefined fields to state', () => {
    useStore.getState().updatePipeline({ epic: 'E-001' });
    useStore.getState().updatePipeline({ activeStep: 'step_2' });

    // epic should still be E-001 (not overwritten by undefined)
    expect(useStore.getState().epic).toBe('E-001');
    expect(useStore.getState().activeStep).toBe('step_2');
  });

  it('accepts null values to reset nullable fields', () => {
    useStore.getState().updatePipeline({ epic: 'E-001', activeStep: 'step_1' });
    useStore.getState().updatePipeline({ epic: null, activeStep: null });

    expect(useStore.getState().epic).toBeNull();
    expect(useStore.getState().activeStep).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Combined store — slice isolation
// ---------------------------------------------------------------------------

describe('Combined store — slices coexist without interference', () => {
  it('connection actions do not affect pipeline state', () => {
    useStore.getState().setPipelineState({
      currentState: 'GATES',
      currentEpicId: 'E-001',
      currentStepId: null,
      progress: { epicsCompleted: 0, epicsTotal: 1, stepsCompleted: 5, stepsTotal: 5 },
    });

    useStore.getState().setWsStatus('reconnecting');
    useStore.getState().incrementReconnectAttempt();
    useStore.getState().incrementReconnectAttempt();

    // Pipeline state unchanged
    expect(useStore.getState().currentState).toBe('GATES');
    expect(useStore.getState().currentEpicId).toBe('E-001');
    // Connection state updated
    expect(useStore.getState().wsStatus).toBe('reconnecting');
    expect(useStore.getState().reconnectAttempt).toBe(2);
  });

  it('satellite actions do not affect stage log entries', () => {
    useStore.getState().addStageLogEntry(makeLogEntry({ action: 'preserved' }));

    useStore.getState().setQueueInfo(10, true);
    useStore.getState().setHealthScore(75);
    useStore.getState().setPendingDecisions(2);

    // Stage log unchanged
    expect(useStore.getState().stageLogEntries).toHaveLength(1);
    expect(useStore.getState().stageLogEntries[0].action).toBe('preserved');
    // Satellite state updated
    expect(useStore.getState().queueCount).toBe(10);
    expect(useStore.getState().healthScore).toBe(75);
  });

  it('legacy slice actions do not corrupt typed pipeline slice', () => {
    useStore.getState().setPipelineState({
      currentState: 'EXECUTING',
      currentEpicId: 'E-002',
      currentStepId: 'step_4',
      progress: { epicsCompleted: 1, epicsTotal: 3, stepsCompleted: 4, stepsTotal: 10 },
    });
    useStore.getState().setSteps([
      { id: 'step_4', role: 'qa', objective: 'Write tests' },
    ]);

    // Update legacy fields
    useStore.getState().setFSMState('EXECUTING');
    useStore.getState().updatePipeline({ progress: 40, activeStep: 'step_4' });

    // Typed pipeline slice still intact
    expect(useStore.getState().currentState).toBe('EXECUTING');
    expect(useStore.getState().currentEpicId).toBe('E-002');
    expect(useStore.getState().steps).toHaveLength(1);
    // Legacy fields updated
    expect(useStore.getState().fsmState).toBe('EXECUTING');
    expect(useStore.getState().progress).toBe(40);
  });

  it('resetting stage log does not affect other slices', () => {
    useStore.getState().setWsStatus('connected');
    useStore.getState().setQueueInfo(3, false);
    useStore.getState().addStageLogEntry(makeLogEntry());

    useStore.getState().clearStageLog();

    expect(useStore.getState().stageLogEntries).toEqual([]);
    // Other slices unaffected
    expect(useStore.getState().wsStatus).toBe('connected');
    expect(useStore.getState().queueCount).toBe(3);
  });
});

// ---------------------------------------------------------------------------
// Store reset utility (validates the testing helper itself)
// ---------------------------------------------------------------------------

describe('Store reset between tests', () => {
  it('state modified in one test does not leak to the next (first test)', () => {
    useStore.getState().setWsStatus('connected');
    useStore.getState().addStageLogEntry(makeLogEntry());
    useStore.getState().setQueueInfo(5, true);

    // No assertion needed — this just sets state; the next test verifies isolation
    expect(useStore.getState().wsStatus).toBe('connected');
  });

  it('state from previous test is fully reset (second test)', () => {
    // After beforeEach reset, state must be back to initial defaults
    expect(useStore.getState().wsStatus).toBe('disconnected');
    expect(useStore.getState().stageLogEntries).toEqual([]);
    expect(useStore.getState().queueCount).toBe(0);
  });
});
