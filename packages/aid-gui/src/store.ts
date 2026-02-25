import { create } from 'zustand';

export type FSMState = 
  | 'IDLE' 
  | 'PLAN_REVIEW' 
  | 'PLAN_READY' 
  | 'EXECUTING' 
  | 'PHASE_CHECK' 
  | 'PHASE_RETRY' 
  | 'GATES' 
  | 'GATES_RETRY' 
  | 'PM_APPROVAL' 
  | 'CURATOR_RESOLVE' 
  | 'DONE' 
  | 'ERROR';

export interface Project {
  id: string;
  name: string;
  health: number;
}

interface DashboardState {
  currentProject: Project | null;
  fsmState: FSMState;
  progress: number;
  activeStep: string | null;
  epic: string | null;
  duration: string | null;
  
  setProject: (project: Project) => void;
  setFSMState: (state: FSMState) => void;
  updatePipeline: (data: Partial<DashboardState>) => void;
}

export const useStore = create<DashboardState>((set) => ({
  currentProject: null,
  fsmState: 'IDLE',
  progress: 0,
  activeStep: null,
  epic: null,
  duration: null,

  setProject: (project) => set({ currentProject: project }),
  setFSMState: (state) => set({ fsmState: state }),
  updatePipeline: (data) => set((state) => ({ ...state, ...data })),
}));

export const stateColors: Record<FSMState, string> = {
  IDLE: 'var(--color-state-idle)',
  PLAN_REVIEW: 'var(--color-state-plan-review)',
  PLAN_READY: 'var(--color-state-plan-ready)',
  EXECUTING: 'var(--color-state-executing)',
  PHASE_CHECK: 'var(--color-state-phase-check)',
  PHASE_RETRY: 'var(--color-state-phase-retry)',
  GATES: 'var(--color-state-gates)',
  GATES_RETRY: 'var(--color-state-gates-retry)',
  PM_APPROVAL: 'var(--color-state-pm-approval)',
  CURATOR_RESOLVE: 'var(--color-state-curator-resolve)',
  DONE: 'var(--color-state-done)',
  ERROR: 'var(--color-state-error)',
};
