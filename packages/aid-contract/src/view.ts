import type { StatusKey } from './status.js';
import type { TimeSource } from './seams.js';
import type { DictionaryEntry } from './explain.js';
import type { AuditSummary, AuditTrend } from './managerial.js';

export type FsmState = 'READY' | 'EXECUTE' | 'GATES' | 'ESCALATION' | 'DONE' | 'ERROR';
export type RunFormat = 'v3' | 'legacy' | 'stub';
export type CheckpointId = 'CP1'|'CP2'|'CP3'|'CP4'|'CP5'|'CP6';
export type Verdict = 'pass' | 'fail' | 'skipped' | 'unverifiable' | null;

// Headline-score envelope (§5.7) — never a bare number; carries honesty metadata.
export interface Score {
  value: number | null;
  partial: boolean;
  confidence: 'high' | 'low';
  components: Record<string, number | null>;
  warnings: string[];
}

export interface Project {
  id: string; name: string; path: string; aidoPath: string;
  discovered: boolean; partial: boolean;
  epicsTotal: number; epicsActive: number; runsTotal: number;
  activeRun: { epicId: string; runId: string; state: FsmState } | null;
  health: {
    value: number | null; partial: boolean; confidence: 'high' | 'low';
    compliancePassRate: number | null; openViolations: number;
    lastGateOverall: 'pass'|'fail'|null; warnings: string[];
  };
  lastActivityAt: string | null;
}
export interface ProjectDetail extends Project {
  epics: EpicSummary[]; queue: QueueEntry[]; recentActivity: ActivityEvent[];
  aggregateAudit: AuditSummary & { scoredEpicCount: number; medianEpicId: string | null };
  auditTrend: AuditTrend;
}
export interface EpicSummary {
  projectId: string; id: string; title: string; status: string;
  planRef: string | null; runsTotal: number; runsCompleted: number;
  membershipSource?: MembershipSource;
  latestRun: { runId: string; state: FsmState; format: RunFormat; startedAt: string|null } | null;
  lastActivityAt: string | null;
}
export interface EpicDetail extends EpicSummary {
  spec: EpicSpec; runs: RunSummary[]; latest: RunDetail | null;
  metrics: MetricSet; explanations: DictionaryEntry['id'][];
  auditTrend: AuditTrend;
}
export interface RunSummary {
  runId: string; format: RunFormat; state: FsmState;
  startedAt: string|null; finishedAt: string|null; durationS: number|null;
  overallGate: 'pass'|'fail'|null; complianceOverall: 'pass'|'fail'|null;
}
export interface RunDetail {
  projectId: string; epicId: string; runId: string; format: RunFormat;
  state: FsmState; mode: string; branch: string; baseCommit: string;
  currentStep: number; totalSteps: number; gateRetries: number; escalationCount: number;
  startedAt: string|null; createdAt: string|null; donePhase: string|null; pmDecision: string|null;
  steps: RunStep[]; checkpoints: Checkpoint[]; gates: GateResult[];
  compliance: ComplianceRun | null; reports: ReportRef[];
  audit: AuditSummary;
  timeline: ActivityEvent[]; files: string[];
}
export interface RunStep {
  id: string | number; name: string;
  status: 'pending'|'executing'|'done'|'failed'|'completed';
  role: string|null; startedAt: string|null; completedAt: string|null; durationS: number|null;
}
export interface Checkpoint {
  id: CheckpointId; label: string;
  dispatched: boolean; verdict: Verdict;
  provenance: string | string[] | null;
  provenanceSource: 'compliance' | 'timeline' | null;
  repeatCount: number | null;
  repeatSource: 'files' | 'timeline' | null;
  outputs: { name: string; relPath: string }[];
}
export interface GateResult {
  gate: string; result: 'pass'|'fail'|'skipped';
  exitCode: number; durationMs: number; attempts: number; outputPreview: string;
}
export interface ComplianceFailure {
  check: string;
  evidence: string;
  severity: 'blocking' | 'advisory';
  promotedAt?: string | null;
}
export interface ComplianceRun {
  epicId: string; runId: string; aidVersion: string; deployEra: string; evaluatedAt: string;
  coverageMode: string | null; overall: 'pass'|'fail';
  checks: Record<string, unknown>; failures: ComplianceFailure[];
  forceOverrideCount: number; forceOverrideReasons: string[]; notes: string[];
}
export interface ComplianceView {
  scope: 'all' | string; fsmAdherenceScore: Score; passRate: number;
  totals: { runs: number; passed: number; failed: number; forceOverrides: number };
  violations: { projectId: string; epicId: string; runId: string;
    overall: 'fail'; failures: ComplianceFailure[]; forceOverrideCount: number; evaluatedAt: string; }[];
}
export interface ActivityEvent {
  projectId: string; epicId?: string; runId?: string;
  ts: string; event: string; from?: FsmState; to?: FsmState;
  step?: number|string; gate?: string; role?: string;
  result?: 'pass'|'fail'; durationS?: number; raw: Record<string, unknown>;
}
export interface MetricSet {
  epicWallTimeS: number | null; runCount: number;
  stepDurationsS: (number | null)[];
  avgStepDurationS: number | null;
  longestStep: { id: string|number; durationS: number } | null;
  stepTimingSource: 'mtime' | 'dispatch' | null;
  gateRuns: number; gateRetries: number;
  checkpointRepeats: Record<CheckpointId, number | null>;
  escalations: number;
  timeBy: TimeSource[];
  partial: boolean; warnings: string[];
}
export interface QueueEntry { epicId: string; path: string; priority: string; status: string; addedAt: string; }
export interface BacklogItem { projectId: string; id: string|null; title: string; status: string|null; raw: string; }
export interface ReportRef { kind: 'audit'|'curator'|'reporter'|'epic-summary'|'final'|'other'; name: string; relPath: string; }
export interface AcceptanceCriterion {
  role: string;
  text: string;
  checked: boolean;
}
export interface EpicStep {
  number: number;
  role: string;
  objective: string;
  dependsOn: string[];
  parallelGroup?: string;
}
export interface EpicSpec {
  epicId: string;
  status: string;
  planRef: string;
  planEpicsTotal: number;
  runsTotal: number;
  runsCompleted: number;
  title: string;
  context: string;
  goal: string;
  scope: { allowedPaths: string[]; forbiddenPaths: string[]; rawMarkdown: string };
  artifacts?: string;
  constraints: string;
  dodGates: string[];
  acceptanceCriteria: AcceptanceCriterion[];
  dependencies?: string;
  steps: EpicStep[];
  hints?: Record<string, string | number>;
}

export type MembershipSource = 'plan_path' | 'plan_ref' | 'derived' | 'orphan';
