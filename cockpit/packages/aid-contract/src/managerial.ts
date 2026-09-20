import type { StatusKey } from './status.js';
import type { Explanation } from './explain.js';
import type { BacklogItem, EpicSummary, MembershipSource, ReportRef } from './view.js';

export interface PlanSummary {
  projectId: string; planId: string;            // e.g. "P046" — from plan filename / plan_path / id-derivation (§13.6)
  title: string; planRef: string;               // path of the plan .md
  epicIds: string[];                             // member EPIC ids (tiers 1-3; orphans excluded — §13.6)
  epicMembers: { epicId: string; membershipSource: MembershipSource }[]; // per-EPIC resolution tier (MF1); 'derived' rows carry a warning so the weaker grouping is visible
  membershipMixed: boolean;                      // true when members span >1 source tier (e.g. P046: plan_ref + derived) — drives the "přiřazeno podle čísla EPICu" note
  epicsTotal: number; epicsDone: number;
  progressPct: number;                           // done_epics/total_epics*100 (§5.5)
  acPct: number | null;                          // Σpresent/Σac_count (§5.5); null = not measured
  lessonsPreview: { date: string|null; lesson: string; epicId: string|null }[]; // thin list-row lessons-per-plan (§4.7); PlanDetail carries the full LessonsView under `lessons`
  auditTrend: AuditTrend;                        // score-over-time across this plan's EPICs (§13.5); one point per audited latest-run per EPIC
  lastActivityAt: string | null;
}

// ── CROSS-PROJECT PLAN OUTCOMES (Rev 4.1, §13.12) ────────────────────────────
// Pure scanner-cache projection. Missing proof/retry evidence remains unknown;
// it MUST NOT be converted to zero, pass, or a successful plan outcome.
export type PlanOutcome = 'passed' | 'partial' | 'failed' | 'in_progress' | 'unverifiable';
export interface PlanOutcomeSummary {
  projectId: string;
  /** Plan STEM — PRIMARY identity (e.g. "P046-foo"). Colliding numbers stay distinct rows. */
  planId: string;
  /** True when planId's plan NUMBER is shared by ≥2 stems (number alias unusable for lookup). */
  ambiguousNumber: boolean;
  title: string;
  outcome: PlanOutcome;
  epicsTotal: number; epicsDone: number; runsTotal: number; failedRuns: number;
  gateFailures: number; gateRetries: number;
  checkpointRetries: { knownTotal: number; unknownCheckpoints: number };
  fsmFailures: { precondition: number; increment: number; doneAdvance: number; other: number };
  escalations: number; forceOverrides: number;
  compliance: { passed: number; failed: number; unknown: number };
  topFailureReasons: { reason: string; count: number }[];
  firstStartedAt: string | null; lastCompletedAt: string | null; lastActivityAt: string | null;
  dataPartial: boolean;
  warnings: string[];
}
export interface PlanOutcomeAnalytics {
  generatedAt: string;
  plans: PlanOutcomeSummary[];
  totals: {
    plans: number; passed: number; partial: number; failed: number;
    inProgress: number; unverifiable: number; failedRuns: number;
    gateFailures: number; gateRetries: number; escalations: number; forceOverrides: number;
  };
  partialProjects: string[];
}

// Deterministic RISK (§13.2). Level from countable real signals only; never a fake probability.
export type RiskLevel = 'nizke' | 'stredni' | 'vysoke' | 'neurceno';
export interface RiskReason {
  text: string;                                  // human Czech line (lidská řeč)
  status: StatusKey;                             // §6.2 token — drives colour
  signal: string;                                // machine id of the firing signal, e.g. "open_blocking_violations"
  value?: number | string;                       // the countable value that fired it (audit trail)
}
export interface Risk {
  level: RiskLevel;                              // 'neurceno' when data coverage insufficient (§13.2 coverage rule)
  reasons: RiskReason[];                         // empty + level 'nizke' = clean; empty + 'neurceno' = no data
  confidence: 'high' | 'low';                   // 'low' when key signals are missing/thin
}

// ── UNIFIED MANAGERIAL ITEM (E-047-6 REOPEN — productization) ─────────────────
// ONE managerial model. BriefItem is the single human-facing managerial type;
// technical screens consume ActivityEvent / ComplianceFailure / view contracts —
// there is no parallel "ManagedProblem". Every field is human-first; raw signals
// live only in `signal` / `rootCauseKey` for the expandable technical detail.

/**
 * Evidence-based lifecycle (§A3).
 *  - `active`     — newest authoritative evidence still requires action.
 *  - `stale`      — still active, unchanged >7d → STAYS current, raised attention.
 *  - `resolved`   — newer authoritative evidence closed THIS root cause (F2, per-signal closure rule).
 *  - `historical` — EPIC archived WITH EVIDENCE (tasks/archive, task status, authoritative artifact) + no open action.
 *  - `unknown`    — archive status unprovable AND not demonstrably active: NEVER silently filed as historical,
 *                   NEVER posed as a confident current blocker — surfaced flagged for triage.
 */
export type ItemLifecycle = 'active' | 'resolved' | 'historical' | 'stale' | 'unknown';

/** Who/what is expected to act next. */
export type NextActor = 'pm' | 'aid' | 'agent' | 'none';

/** A clickable piece of evidence behind an item (replaces a single href). */
export interface EvidenceRef {
  label: string;                                 // human Czech label, e.g. "Audit report", "EPIC detail"
  href: string;                                  // deep-link (Screen B/C/Plan) or run-scoped /file path
  kind: 'epic' | 'plan' | 'file' | 'run';
}

// One BriefItem = one thing the manager should see, grouped by ROOT CAUSE and
// already explained in plain language. The same problem NEVER appears twice:
// it has one home (decision > blocker precedence), cross-links via `relatedIds`.
export interface BriefItem {
  id: string;                                    // stable key = rootCauseKey
  projectId: string; epicId?: string; planId?: string; runId?: string;
  humanTitle: string;                            // human Czech name — NEVER snake_case (e.g. "Čeká na rozhodnutí o mergi")
  explanation: Explanation;                      // {headline, detail, status, color} resolved via explain() (§6.4)
  whatHappened: string;                          // plain-language what occurred
  whyItMatters: string;                          // impact — why the user should care
  whatBlocks: string | null;                     // what it blocks; null = blocks nothing
  recommendedAction: string | null;             // what the user should do; null = nothing actionable yet
  nextActor: NextActor;                          // expected next actor
  severity: 'blocking' | 'warn' | 'info';        // routing/sort key (blocking first)
  signal: string;                                // machine id, e.g. "open_blocking_violation" (technical detail)
  rootCauseKey: string;                          // "projectId:signal:concreteKey" — concreteKey is the specific check/gate/reason
  lifecycle: ItemLifecycle;                      // §A3 evidence-based lifecycle
  occurrenceCount: number;                       // count of distinct RUNS currently exhibiting this root cause
  affectedEpics: string[];                       // the EPIC ids those runs belong to (EPIC count derivable)
  firstSeen: string | null;                      // first occurrence of this root cause
  lastSeen: string | null;                       // most recent occurrence (sort / lastSeen key) — was `at`
  requiresDecision: boolean;                     // routing flag → decisionsNeeded view
  isBlocker: boolean;                            // routing flag → blockers view
  relatedIds: string[];                          // explicit links to related items (no silent duplication)
  evidenceRefs: EvidenceRef[];                   // clickable evidence (replaces single href)
  inconsistencyFlags: string[];                  // e.g. "archived_unclosed_evidence"
}

// MF5 — successProbability envelope. Forward-compatible for MVP2 WITHOUT contract
// churn, while the binding MVP1 invariant keeps "flag, never fake": in MVP1
// `value` MUST be null AND `source` MUST be null (no model exists to produce a
// number — D2). MVP2's LLM agent fills `value` with `source:'agent'`. The UI
// renders "přesnější odhad přijde s agentem (MVP2)" while value===null.
export interface SuccessProbability {
  value: number | null;                          // 0-100 probability. MVP1 INVARIANT: MUST be null.
  source: 'agent' | null;                        // MVP1 INVARIANT: MUST be null. MVP2: 'agent'.
  confidence?: 'high' | 'low';                   // optional; only meaningful once value is non-null (MVP2)
}

// THE managerial read-model. ONE shape, THREE scopes (D1). Screen G = infra; Screen B tab 1 = project;
// Plan screen tab 1 = plan. Answers the seven PM questions (§13.1).
export interface Brief {
  scope: 'infra' | 'project' | 'plan';
  projectId: string | null;                      // null for infra scope
  planId: string | null;                         // set only for plan scope
  generatedAt: string;                           // server scan time (ISO-8601 UTC)
  ecosystemLine: string;                         // ONE-LINE Czech state summary (E-047-6 REOPEN — landing lead)
  sinceLastSeen: {                               // "co se změnilo od poslední návštěvy" — vs client lastSeen (§13.3)
    since: string | null;                        // the lastSeen timestamp the client sent (null = first visit)
    items: BriefItem[];                          // new/changed runs, new gate fails, new violations, new backlog, transitions since `since`
    counts: { newRuns: number; newGateFails: number; newViolations: number;
              newBacklog: number; stateTransitions: number };
  };
  blockers: BriefItem[];                         // "co blokuje postup" — open blocking failures, ESCALATION, repeated precond fails, stuck/stale, missing PM decision
  watchOuts: BriefItem[];                        // "na co si dát pozor" — advisory violations, force-overrides, retry hot-spots, branch mismatch, stale, non-blocking audit findings
  nextUp: BriefItem[];                           // "co bude následovat" — queue next EPICs, runs in READY/EXECUTE, plan progress
  decisionsNeeded: BriefItem[];                  // "jaká rozhodnutí jsou potřeba" — runs awaiting PM decision/merge, ESCALATION needing a human, blocking audit findings
  needsTriage: BriefItem[];                      // §A3 `unknown` lifecycle — archive unprovable, not demonstrably active; flagged, never a confident current blocker
  risk: Risk;                                    // "odhad rizika" — deterministic level + reasons (§13.2)
  successProbability: SuccessProbability;        // MF5 — envelope; binding MVP1 invariant value===null && source===null
}

// ── Structured AUDIT SUMMARY + trend (Rev 3, §13.5) ───────────────────────────
export type AuditSeverity = 'Critical' | 'High' | 'Medium' | 'Low';
export type AuditEffort = 'S' | 'M' | 'L' | null;          // normalized from S|M|L | small|medium|large
export interface AuditCategoryScore {
  category: string;                              // "Code Quality" | "Security" | "Documentation" | "Process" | …
  score: number;                                 // normalized to /100 (a /25 cell ×4; see §13.5 normalization)
  rawScore: string;                              // verbatim cell, e.g. "22/25" | "92" | "100" (provenance, never lost)
  max: 25 | 100;                                 // detected denominator of rawScore
  status: string | null;                         // "PASS" | "WARN" | … when a Status column exists, else null
}
export interface AuditFinding {
  severity: AuditSeverity;
  area: string | null;                           // file:line when present
  auditType: string | null;                      // "process" | "security" | "code" | …
  finding: string;                               // the finding text (1-3 sentences)
  recommendation: string | null;
  effort: AuditEffort;
  autoFixable: boolean | null;                   // null = field absent (distinct from explicit false)
}
export interface AuditNextStep {
  finding: string;                               // short label of what to do
  severity: AuditSeverity;
  effort: AuditEffort;
  autoFixable: boolean | null;
  rank: number;                                  // sort key: severity-weight × effort-cheapness (§13.5)
}
export interface AuditSummary {
  present: boolean;                              // false = no audit-report.md for this run (render "auditor zatím neběžel")
  overallScore: number | null;                   // best-effort /100; null when no parseable score (§4.3 three shapes)
  scoreSource: 'frontmatter' | 'heading' | 'table' | null;  // which of the 3 shapes matched (provenance)
  blockingFindings: boolean | null;              // the ONLY reliably-present auditor field; null only when even it is unparseable
  blockingFindingsSource: 'frontmatter' | 'heading' | 'bold' | 'backtick' | 'inline' | 'numeric' | null; // §13.5 6-form parse
  categories: AuditCategoryScore[];             // [] when no score table present
  topReasons: string[];                          // why the score is what it is — derived from largest deductions / highest-severity findings (§13.5)
  topRisks: AuditFinding[];                      // Critical + High findings, severity-desc
  countsBySeverity: { Critical: number; High: number; Medium: number; Low: number };
  autoFixableCount: number;                      // findings with autoFixable === true
  nextSteps: AuditNextStep[];                    // recommended actions, sorted severity × effort (§13.5)
  headlineCs: string;                            // DETERMINISTIC Czech "proč audit dopadl takhle" (§13.5) — NOT an LLM narrative
  previousScoreHint: { score: number | null; ref: string | null } | null; // auditor's own "Previous audit … Score: N/100" line, when present (§13.5)
  rawRelPath: string;                            // path for the raw-markdown drawer (served via /file, §7.4.1)
  warnings: string[];                            // parse degradations (e.g. "score unparseable", "blocking_findings inferred from prose")
}
export interface AuditTrendPoint {
  runId: string; epicId: string;
  startedAt: string | null;                      // run started_at — the time ORDERING key (§13.5)
  score: number | null;                          // null = real gap (run had no parseable score); NEVER interpolated
  blockingFindings: boolean | null;
}
export interface AuditTrend {
  scope: 'epic' | 'plan' | 'project';           // 'project' = MF7 project-scope trend (one point per audited EPIC)
  points: AuditTrendPoint[];                     // chronological by startedAt; gaps kept as score:null, not dropped
  scoredPointCount: number;                      // how many points actually have a number (drives "málo dat" UI)
  delta: number | null;                          // last scored − first scored; null when <2 scored points
}

// ── PLAN as a first-class entity (Rev 3, §13.6) ───────────────────────────────
export interface PlanDetail extends PlanSummary {
  description: string | null;                    // first prose block of the plan .md (gray-matter body), null when unparseable
  epics: EpicSummary[];                          // member EPICs, status-weighted sort (same order as Screen B)
  orphanEpicCount: number;                       // tier-4 orphan EPICs only (§13.6)
  durationS: number | null;                      // plan_duration_sec (§5.1)
  boundaryAudit: AuditSummary;                   // the SINGLE plan-boundary auditor run (§13.5.7)
  aggregateAudit: AuditSummary & { scoredEpicCount: number; medianEpicId: string | null };
  deliveryReport: ReporterDelivery;              // MF6: plan-boundary Reporter delivery report (§4.3)
  simplifierSummary: SimplifierSummary;          // MF6: plan-boundary Simplifier proposals (§4.3)
  backlog: { items: BacklogItem[]; openCount: number; closedCount: number; warnings: string[] };
  lessons: LessonsView;                          // lessons-per-plan (§13.8); distinct from PlanSummary.lessonsPreview[]
  warnings: string[];                            // aggregation degradations
}

// ── REPORTER DELIVERY + SIMPLIFIER (Rev 4, MF6) ────────────────────────────────
export type DeliveryOutcome = 'pass' | 'fail' | 'partial' | null;
export interface ReporterTestEvidence {
  name: string;                                  // artifact file name (MUST exist on disk, §4.3)
  relPath: string;                               // path served via /file (§7.4.1)
  exists: boolean;                               // verified on disk — false flags missing/fabricated evidence
}
export interface ReporterDelivery {
  present: boolean;                              // false = no reports/{plan_id}-delivery.md
  outcome: DeliveryOutcome;
  summaryCs: string | null;                      // short Czech "co se dodalo" line, null when unparseable
  generatedBy: string | null;                    // frontmatter _generated_by, null when absent
  generatedAt: string | null;                    // frontmatter _generated_at ISO, null when absent
  testEvidence: ReporterTestEvidence[];          // _test_evidence[] artifacts (existence-checked)
  rawRelPath: string | null;                     // path to full delivery .md for the drawer; null when present:false
  warnings: string[];
}
export type SimplifierDisposition = 'approve' | 'reject' | 'defer' | null;
export interface SimplifierProposal {
  id: string | null;                             // IMP-{NNN} / PROP-*; null when none
  area: string | null;                           // file/component the proposal targets
  proposal: string;                              // the simplification text (1-3 sentences)
  disposition: SimplifierDisposition;
  effort: AuditEffort;                           // reuses the audit effort scale
}
export interface SimplifierSummary {
  present: boolean;
  proposalCount: number;
  proposals: SimplifierProposal[];
  headlineCs: string | null;
  rawRelPath: string | null;
  warnings: string[];
}

// ── BACKLOG DELTA (Rev 3, §13.7) — CLIENT-SIDE in MVP1 ────────────────────────
export interface BacklogSnapshotRow {
  id: string | null;
  status: string | null;
  priority: string | null;
}
export interface BacklogSnapshot {
  version: 1;
  scopeKey: string;
  lastSeen: string;
  rows: BacklogSnapshotRow[];
}
export interface BacklogDeltaItem {
  id: string | null;
  title: string;
  type: string | null;
  area: string | null;
  status: string | null;
  priority: string | null;
  changeSince: 'added' | 'closed' | 'priorityChanged' | 'statusChanged' | 'unchanged';
  prevStatus?: string | null;
  prevPriority?: string | null;
}
export interface BacklogDelta {
  scope: 'project' | 'plan';
  projectId: string; planId: string | null;
  openCount: number;
  closedCount: number;
  firstVisit: boolean;
  lastSeen: string | null;
  added: BacklogDeltaItem[];
  closed: BacklogDeltaItem[];
  priorityChanged: BacklogDeltaItem[];
  statusChanged: BacklogDeltaItem[];
  warnings: string[];
}

// ── LESSONS-PER-PLAN (Rev 3, §13.8) ───────────────────────────────────────────
export interface LessonEntry {
  date: string | null;
  lesson: string;
  epicId: string | null;
  kind: 'lesson' | 'gotcha';
}
export interface LessonsView {
  scope: 'plan' | 'project' | 'infra';
  projectId: string | null; planId: string | null;
  entries: LessonEntry[];
  total: number;
  warnings: string[];
}

// ── LAST-SEEN (Rev 3, §13.3) — localStorage shape, NOT a server resource (MVP1) ─
export interface LastSeen {
  version: 1;
  scopes: Record<string, string>;               // scopeKey → ISO-8601 UTC of last visit
}
