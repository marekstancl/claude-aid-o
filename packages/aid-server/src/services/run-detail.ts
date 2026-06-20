/**
 * RunDetail builder (EPIC E-047-2_7, Step 8 — FINAL backend step).
 *
 * NET-NEW assembler that produces the contract {@link RunDetail} from a run's
 * on-disk evidence files. This is the highest-correctness-risk step in Phase 2:
 * a naive implementation FABRICATES data (e.g. trusts `fsm-state.steps[]`,
 * re-derives provenance from the timeline, reports `repeatCount:0` where there
 * is no signal). The spec §4.0 reliability rules below are non-negotiable and
 * each is annotated at its enforcement site.
 *
 * Wiring (closes the Step 7↔8 loop): {@link buildRunDetail} is injected into the
 * Step 7 {@link ScannerCache} as its {@link RunDetailLoader} via the
 * {@link createRunDetailLoader} / {@link createScannerCache} factories. The
 * cache memoizes the RESULT; it has no compile-time dependency on this module —
 * the dependency is introduced ONLY at the factory seam.
 *
 * Reliability posture (§4.0): NEVER throws on a partial / broken run. Every disk
 * read routes through the never-throw {@link FsReader}; every parse degrades to
 * nulls + warnings. A completely empty run dir yields a type-valid stub.
 *
 * §4.0 rule map (where each is honored):
 *  #1  fsm-state TOP-LEVEL fields only; pmDecision → null when absent (merge-only).
 *  #2  steps[] derived from timeline + verify-file mtimes, NOT fsm-state.steps[].
 *  #3  provenance READ from compliance.json (NOT re-derived from timeline).
 *  #4  repeatCount: CP1 from files; CP2/CP3/CP4 from timeline dispatch groups
 *      minus 1; null (never 0) when no dispatch events.
 *  #5  audit score in THREE shapes (frontmatter / heading / table), in order.
 *  #6  gates from gates_report.json (root OR gates/); plan_diff exit 2 = skip.
 *  #7  timeline from PER-RUN timeline.jsonl only.
 *  #8  compliance parsed all-optional; failures[] mapped to ComplianceFailure[];
 *      null (not {}) when no compliance.json.
 *  #9  files via root-relative recursive walk (NEVER FsReader.listDirRecursive,
 *      which is BUGGED — IMP-128 — it flattens nested paths to basenames).
 *  #10 format: v3 / legacy / stub (reuses the Step 6 classification rule).
 */

import { basename, join, relative, posix, sep } from 'node:path';
import { readdir, stat } from 'node:fs/promises';
import type {
  ActivityEvent,
  AuditSummary,
  Checkpoint,
  CheckpointId,
  ComplianceFailure,
  ComplianceRun,
  FsmState,
  GateResult,
  ReportRef,
  RunDetail,
  RunFormat,
  RunStep,
  Verdict,
} from '@aid/contract';
import { FsReader } from './fs-reader.js';
import { createPathMap, type PathMap } from './pathmap.js';

// ===========================================================================
// Dependency injection
// ===========================================================================

/**
 * Dependencies for {@link buildRunDetail}. All injectable for tests; sensible
 * defaults wire the real {@link FsReader} (Step 4) and an identity
 * {@link PathMap} (Step 3 — host === container in host-native dev).
 */
export interface RunDetailDeps {
  /** Never-throw reader + tolerant parsers (Step 4). */
  fs: FsReader;
  /**
   * Host↔container path translator (Step 3). Resolves embedded absolute host
   * paths in evidence (e.g. `evidence_dir`, dispatch `output_file`) to the
   * file list / display form. Defaults to an identity map.
   */
  pathMap: PathMap;
}

/** The six valid v3 FSM states (mirrors project-scanner.ts §4.0 #9). */
const VALID_FSM_STATES: ReadonlySet<string> = new Set<FsmState>([
  'READY',
  'EXECUTE',
  'GATES',
  'ESCALATION',
  'DONE',
  'ERROR',
]);

// ===========================================================================
// Security helpers — path traversal defense (CWE-22)
// ===========================================================================

/**
 * Validate that a path segment (projectId/epicId/runId) is safe — does not
 * contain traversal patterns (`..`), separators (`/`, `\`), or be empty/`.`.
 * Returns false for any dangerous input; never throws.
 */
function isValidPathSegment(segment: string): boolean {
  if (!segment || segment === '.' || segment === '..') return false;
  if (segment.includes('/') || segment.includes('\\')) return false;
  if (segment.includes('..')) return false;
  return true;
}

/**
 * Segment-boundary-aware "is `p` under `root`" check (mirrored from pathmap.ts).
 * True when `p` equals `root` exactly, or `p` continues with a path separator
 * immediately after `root` (so `/projects/x` matches but `/projects-backup/x`
 * does not). Never throws.
 */
function isUnderRoot(p: string, root: string): boolean {
  if (p === root) return true;
  if (!p.startsWith(root)) return false;
  const boundary = p[root.length];
  return boundary === posix.sep || boundary === sep;
}

// ===========================================================================
// buildRunDetail — the assembler
// ===========================================================================

/**
 * Assemble the full {@link RunDetail} for a `(projectId, epicId, runId)` triple.
 *
 * @param projectId   project id (basename of the project dir).
 * @param epicId      EPIC id.
 * @param runId       run id.
 * @param runDir      ABSOLUTE path to the run's evidence dir
 *                    (`<aido>/work/evidence/<epicId>/<runId>`). The caller (the
 *                    Step 7 cache loader) resolves it from the Tier-1 index.
 * @param deps        injected {@link RunDetailDeps} (fs + pathMap).
 *
 * Never throws. A broken / partial / empty run degrades to nulls + warnings and
 * a type-valid stub RunDetail. Security (CWE-22): inputs are validated for
 * traversal attempts.
 */
export async function buildRunDetail(
  projectId: string,
  epicId: string,
  runId: string,
  runDir: string,
  deps: RunDetailDeps,
): Promise<RunDetail> {
  const { fs, pathMap } = deps;

  // Security defense layer 1: reject traversal in input segments
  if (!isValidPathSegment(projectId) || !isValidPathSegment(epicId) || !isValidPathSegment(runId)) {
    // Return a safe empty stub when input is invalid (never throw)
    return createEmptyRunDetail(projectId, epicId, runId);
  }

  // --- (#9) file list via root-relative recursive walk (NOT listDirRecursive) ---
  const files = await walkRunFiles(runDir, pathMap);

  // --- (#1, #10) fsm-state top-level fields + format classification ---
  const fsm = await readFsmState(fs, runDir);

  // --- (#7) per-run timeline → ActivityEvent[] ---
  const timeline = await readTimeline(fs, runDir, projectId, epicId, runId);

  // --- (#10) format classification (v3 / legacy / stub) ---
  const format = classifyFormat(fsm.present, fsm.state, timeline.length, files);

  // --- (#8) compliance.json (all-optional; failures → ComplianceFailure[]) ---
  const compliance = await readCompliance(fs, runDir, epicId, runId);

  // --- (#6) gates from gates_report.json (root OR gates/) ---
  const gates = await readGates(fs, runDir);

  // --- (#5) audit summary (three score shapes) ---
  const audit = await readAudit(fs, runDir, files);

  // --- (#2) steps[] derived from timeline + verify-file mtimes ---
  const steps = await deriveSteps(fs, runDir, files, fsm, timeline);

  // --- (#3, #4) checkpoints: provenance from compliance, repeats from files/timeline ---
  const checkpoints = buildCheckpoints(compliance, timeline, files, gates, format);

  // --- reports (audit / curator / reporter / epic-summary / final / other) ---
  const reports = buildReports(files);

  return {
    projectId,
    epicId,
    runId,
    format,
    state: fsm.state ?? 'READY',
    mode: fsm.mode ?? '',
    branch: fsm.branch ?? '',
    baseCommit: fsm.baseCommit ?? '',
    currentStep: fsm.currentStep ?? 0,
    totalSteps: fsm.totalSteps ?? 0,
    gateRetries: fsm.gateRetries ?? 0,
    escalationCount: fsm.escalationCount ?? 0,
    startedAt: fsm.startedAt ?? null,
    createdAt: fsm.createdAt ?? null,
    donePhase: fsm.donePhase ?? null,
    pmDecision: fsm.pmDecision ?? null, // §4.0 #2: null when the field is absent (pre-merge)
    steps,
    checkpoints,
    gates,
    compliance,
    reports,
    audit,
    timeline,
    files,
  };
}

// ===========================================================================
// Empty stub for security failures
// ===========================================================================

/**
 * Create a type-valid empty RunDetail stub when security checks fail
 * (traversal attempt detected). Never throws.
 */
function createEmptyRunDetail(projectId: string, epicId: string, runId: string): RunDetail {
  return {
    projectId,
    epicId,
    runId,
    format: 'stub',
    state: 'READY',
    mode: '',
    branch: '',
    baseCommit: '',
    currentStep: 0,
    totalSteps: 0,
    gateRetries: 0,
    escalationCount: 0,
    startedAt: null,
    createdAt: null,
    donePhase: null,
    pmDecision: null,
    steps: [],
    checkpoints: [],
    gates: [],
    compliance: null,
    reports: [],
    audit: {
      present: false,
      overallScore: null,
      scoreSource: null,
      blockingFindings: null,
      blockingFindingsSource: null,
      categories: [],
      topReasons: [],
      topRisks: [],
      countsBySeverity: { Critical: 0, High: 0, Medium: 0, Low: 0 },
      autoFixableCount: 0,
      nextSteps: [],
      headlineCs: '',
      previousScoreHint: null,
      rawRelPath: 'audit-report.md',
      warnings: ['Security check failed: invalid path segments in projectId/epicId/runId'],
    },
    timeline: [],
    files: [],
  };
}

// ===========================================================================
// #9 — root-relative recursive file walk (IMP-128 — NEVER listDirRecursive)
// ===========================================================================

/**
 * List every file under `runDir` as a ROOT-RELATIVE path (e.g.
 * `gates/gates_report.json`, `steps/...`), recursively. This deliberately does
 * NOT use {@link FsReader.listDirRecursive}, which is BUGGED (IMP-128): it
 * flattens nested paths to basenames (`gates/gates_report.json` →
 * `gates_report.json`), losing the directory and colliding sibling names.
 *
 * DOES NOT FOLLOW SYMLINKS — defense against symlink DoS / enumeration of
 * out-of-tree paths (CWE-22). Symlinks are treated as leaf files and listed,
 * but their targets are not recursed. This mirrors the `maxFileMtime` pattern
 * in scanner-cache.ts which uses `Dirent.isDirectory()` (false for symlinks).
 *
 * Embedded absolute HOST paths are not part of this list (they live inside file
 * CONTENTS, resolved by {@link PathMap} when read); the file list is purely the
 * relative on-disk layout. Never throws — unreadable entries are skipped. The
 * result is sorted for deterministic output.
 *
 * @param pathMap reserved for callers that surface absolute paths; the relative
 *   listing itself is path-map-independent (kept in the signature so the seam is
 *   explicit and future absolute-path emission has the translator available).
 */
async function walkRunFiles(runDir: string, _pathMap: PathMap): Promise<string[]> {
  const out: string[] = [];
  const MAX_DEPTH = 32; // Defensive depth cap against unbounded walks

  const walk = async (dir: string, depth: number): Promise<void> => {
    // Defense: stop recursion at MAX_DEPTH to prevent pathological walks
    if (depth > MAX_DEPTH) {
      return;
    }

    let entries: import('node:fs').Dirent[];
    try {
      entries = await readdir(dir, { withFileTypes: true });
    } catch {
      return; // unreadable dir → skip (never throw)
    }
    for (const ent of entries) {
      const full = join(dir, ent.name);
      // DO NOT FOLLOW SYMLINKS — treat them as leaf files.
      // Dirent.isDirectory() returns false for symlinks, which is what we want.
      if (ent.isSymbolicLink()) {
        // Symlink is a leaf file; list it but do not recurse into it
        out.push(relative(runDir, full).split('\\').join('/'));
        continue;
      }
      if (ent.isDirectory()) {
        await walk(full, depth + 1);
      } else {
        // ROOT-relative path with POSIX separators for stable display.
        out.push(relative(runDir, full).split('\\').join('/'));
      }
    }
  };

  await walk(runDir, 0);
  out.sort((a, b) => a.localeCompare(b));
  return out;
}

// ===========================================================================
// #1, #10 — fsm-state top-level fields
// ===========================================================================

/** The TOP-LEVEL fsm-state fields we trust (§4.0 #1). `steps[]` is IGNORED. */
interface FsmTop {
  present: boolean;
  state: FsmState | null;
  mode: string | null;
  branch: string | null;
  baseCommit: string | null;
  currentStep: number | null;
  totalSteps: number | null;
  gateRetries: number | null;
  escalationCount: number | null;
  startedAt: string | null;
  createdAt: string | null;
  donePhase: string | null;
  streamlinedMode: boolean | null;
  planPath: string | null;
  /** §4.0 #2: present ONLY post-merge → null when the field is absent. */
  pmDecision: string | null;
}

/**
 * Read `fsm-state.yaml` and extract ONLY the reliable top-level fields (§4.0
 * #1). The keys are camelCased by the tolerant YAML parser
 * (`started_at`→`startedAt`, `current_step`→`currentStep`, …). `steps[]` is
 * deliberately NOT read here — on DONE runs it is always `status: pending` with
 * empty names and null timestamps (§4.0 #1/#2). `pmDecision` is parsed
 * all-optional → null when absent (it is written only at merge).
 */
async function readFsmState(fs: FsReader, runDir: string): Promise<FsmTop> {
  const path = join(runDir, 'fsm-state.yaml');
  const parsed = await fs.readYamlParsed<Record<string, unknown>>(path);
  const d = parsed.data;
  if (d === null || typeof d !== 'object') {
    return emptyFsmTop();
  }

  const stateRaw = typeof d.state === 'string' ? d.state : null;
  const state =
    stateRaw !== null && VALID_FSM_STATES.has(stateRaw) ? (stateRaw as FsmState) : null;

  return {
    present: true,
    state,
    mode: asString(d.mode),
    branch: asString(d.branch),
    baseCommit: asString(d.baseCommit),
    currentStep: asNumber(d.currentStep),
    totalSteps: asNumber(d.totalSteps),
    gateRetries: asNumber(d.gateRetries) ?? 0,
    escalationCount: asNumber(d.escalationCount) ?? 0,
    startedAt: asIso(d.startedAt),
    createdAt: asIso(d.createdAt),
    donePhase: asString(d.donePhase),
    streamlinedMode: typeof d.streamlinedMode === 'boolean' ? d.streamlinedMode : null,
    planPath: d.planPath === null ? null : asString(d.planPath),
    pmDecision: asString(d.pmDecision), // §4.0 #2 — null when key absent
  };
}

function emptyFsmTop(): FsmTop {
  return {
    present: false,
    state: null,
    mode: null,
    branch: null,
    baseCommit: null,
    currentStep: null,
    totalSteps: null,
    gateRetries: null,
    escalationCount: null,
    startedAt: null,
    createdAt: null,
    donePhase: null,
    streamlinedMode: null,
    planPath: null,
    pmDecision: null,
  };
}

// ===========================================================================
// #10 — format classification
// ===========================================================================

/**
 * Classify the run format (§4.0 #10, mirrors the Step 6 scanner rule):
 * - **v3**: a parseable fsm-state with a valid `state` AND a non-empty timeline.
 * - **legacy**: an fsm-state present (or legacy markers) but not v3-shaped.
 * - **stub**: nothing usable (no fsm-state, minimal files).
 */
function classifyFormat(
  fsmPresent: boolean,
  state: FsmState | null,
  timelineLen: number,
  files: string[],
): RunFormat {
  if (fsmPresent && state !== null && timelineLen > 0) return 'v3';
  if (fsmPresent && state !== null) return 'v3'; // fsm-state alone still v3-shaped
  if (
    fsmPresent ||
    files.includes('state.yaml') ||
    files.includes('plan_progress.json')
  ) {
    return 'legacy';
  }
  return 'stub';
}

// ===========================================================================
// #7 — per-run timeline → ActivityEvent[]
// ===========================================================================

/**
 * Read the PER-RUN `timeline.jsonl` and map each entry to an {@link
 * ActivityEvent} (§4.0 #7). NEVER reads the root `work/timeline.jsonl`. Keys are
 * camelCased by the parser (`step_id`→`stepId`, `duration_s`→`durationS`,
 * `step_n`→`stepN`). The raw entry is preserved in `raw` for downstream
 * (provenance corroboration, repeat grouping).
 */
async function readTimeline(
  fs: FsReader,
  runDir: string,
  projectId: string,
  epicId: string,
  runId: string,
): Promise<ActivityEvent[]> {
  const path = join(runDir, 'timeline.jsonl');
  const parsed = await fs.readJsonlParsed<Record<string, unknown>>(path);
  const rows = parsed.data ?? [];

  const events: ActivityEvent[] = [];
  for (const r of rows) {
    if (typeof r !== 'object' || r === null) continue;
    const ts = asString(r.ts) ?? '';
    const event = asString(r.event) ?? '';
    if (event === '') continue; // not a usable timeline event

    const ev: ActivityEvent = {
      projectId,
      epicId,
      runId,
      ts,
      event,
      raw: r,
    };
    const from = asString(r.from);
    if (from !== null && VALID_FSM_STATES.has(from)) ev.from = from as FsmState;
    const to = asString(r.to);
    if (to !== null && VALID_FSM_STATES.has(to)) ev.to = to as FsmState;
    const step = r.step ?? r.stepN ?? r.stepId;
    if (typeof step === 'number' || typeof step === 'string') ev.step = step;
    const gate = asString(r.gate);
    if (gate !== null) ev.gate = gate;
    const role = asString(r.role);
    if (role !== null) ev.role = role;
    const result = asString(r.result);
    if (result === 'pass' || result === 'fail') ev.result = result;
    const durationS = asNumber(r.durationS);
    if (durationS !== null) ev.durationS = durationS;

    events.push(ev);
  }
  return events;
}

// ===========================================================================
// #8 — compliance.json (all-optional; failures → ComplianceFailure[])
// ===========================================================================

/**
 * Read `compliance.json` and map it to a {@link ComplianceRun} (§4.0 #8).
 * Returns `null` (NOT `{}`) when there is no compliance.json — distinguishing
 * "not evaluated" from "evaluated empty". `failures[]` is mapped to STRUCTURED
 * {@link ComplianceFailure}[] (check / evidence / severity), never raw strings.
 * Keys are camelCased by the parser (`aid_version`→`aidVersion`,
 * `force_override_count`→`forceOverrideCount`, etc.).
 */
async function readCompliance(
  fs: FsReader,
  runDir: string,
  epicId: string,
  runId: string,
): Promise<ComplianceRun | null> {
  const path = join(runDir, 'compliance.json');
  if (!(await fs.exists(path))) return null; // §4.0 #8 — null, not {}

  const parsed = await fs.readJsonParsed<Record<string, unknown>>(path);
  const d = parsed.data;
  if (d === null || typeof d !== 'object') return null;

  const overall = d.overall === 'fail' ? 'fail' : 'pass';
  const checks =
    typeof d.checks === 'object' && d.checks !== null
      ? (d.checks as Record<string, unknown>)
      : {};

  const failures: ComplianceFailure[] = [];
  if (Array.isArray(d.failures)) {
    for (const f of d.failures) {
      if (typeof f !== 'object' || f === null) continue;
      const ff = f as Record<string, unknown>;
      const severity = ff.severity === 'blocking' ? 'blocking' : 'advisory';
      failures.push({
        check: asString(ff.check) ?? '',
        evidence: asString(ff.evidence) ?? '',
        severity,
        promotedAt: ff.promotedAt === undefined ? undefined : asString(ff.promotedAt),
      });
    }
  }

  return {
    epicId: asString(d.epicId) ?? epicId,
    runId: asString(d.runId) ?? runId,
    aidVersion: asString(d.aidVersion) ?? '',
    deployEra: asString(d.deployEra) ?? '',
    evaluatedAt: asString(d.evaluatedAt) ?? '',
    coverageMode: asString(d.coverageMode),
    overall,
    checks,
    failures,
    forceOverrideCount: asNumber(d.forceOverrideCount) ?? 0,
    forceOverrideReasons: asStringArray(d.forceOverrideReasons),
    notes: asStringArray(d.notes),
  };
}

// ===========================================================================
// #6 — gates from gates_report.json (root OR gates/)
// ===========================================================================

/**
 * Read `gates_report.json` (§4.0 #6). The path may be `gates/gates_report.json`
 * OR the run-dir root — try both. Maps each gate to a {@link GateResult}. The
 * `plan_diff` gate with `exit_code:2` is a SKIP-AS-PASS sentinel (no plan diff
 * to check, fast mode) → reported as `result:'skipped'`, never a failure. Keys
 * are camelCased (`exit_code`→`exitCode`, `duration_ms`→`durationMs`).
 */
async function readGates(fs: FsReader, runDir: string): Promise<GateResult[]> {
  const nested = join(runDir, 'gates', 'gates_report.json');
  const root = join(runDir, 'gates_report.json');
  const path = (await fs.exists(nested)) ? nested : root;

  const parsed = await fs.readJsonParsed<Record<string, unknown>>(path);
  const d = parsed.data;
  if (d === null || typeof d !== 'object') return [];

  const gatesObj =
    typeof d.gates === 'object' && d.gates !== null
      ? (d.gates as Record<string, unknown>)
      : {};

  const out: GateResult[] = [];
  for (const [key, raw] of Object.entries(gatesObj)) {
    if (typeof raw !== 'object' || raw === null) continue;
    const g = raw as Record<string, unknown>;
    // The map KEY is camelCased by the parser (`plan_diff`→`planDiff`); the
    // inner `gate` field preserves the canonical snake_case name. Prefer it,
    // so the plan_diff sentinel below matches against the real gate name.
    const gateName = asString(g.gate) ?? key;
    const exitCode = asNumber(g.exitCode) ?? 0;
    const attempts = asNumber(g.attempts) ?? 0;
    const durationMs = asNumber(g.durationMs) ?? 0;
    const outputPreview = previewOutput(asString(g.output) ?? '');

    // §4.0 #6: plan_diff exit 2 = nothing-to-diff → skip-as-pass, never fail.
    // Disk also writes the literal `result: "skip"` (e.g. fast mode) — normalize
    // the `skip`/`skipped` synonyms to the contract's `skipped`.
    let result: GateResult['result'];
    const rawResult = asString(g.result);
    if (gateName === 'plan_diff' && exitCode === 2) {
      result = 'skipped';
    } else if (rawResult === 'pass' || rawResult === 'fail') {
      result = rawResult;
    } else if (rawResult === 'skipped' || rawResult === 'skip') {
      result = 'skipped';
    } else {
      result = exitCode === 0 ? 'pass' : 'fail';
    }

    out.push({
      gate: gateName,
      result,
      exitCode,
      durationMs,
      attempts,
      outputPreview,
    });
  }
  // Deterministic order by gate name.
  out.sort((a, b) => a.gate.localeCompare(b.gate));
  return out;
}

/** Truncate a gate's stdout to a bounded preview (first 500 chars). */
function previewOutput(output: string): string {
  const MAX = 500;
  return output.length <= MAX ? output : output.slice(0, MAX);
}

// ===========================================================================
// #5 — audit summary (THREE score shapes)
// ===========================================================================

/** Match `## Score: N/100` heading (with optional `s`, e.g. `## Scores:`). */
const SCORE_HEADING_RE = /^##\s+scores?\s*:\s*(\d{1,3})\s*(?:\/\s*100)?\s*$/im;
/** Match a `**Total**` table row carrying `N/100`. */
const SCORE_TOTAL_ROW_RE = /\|\s*\*{0,2}total\*{0,2}\s*\|\s*\*{0,2}\s*(\d{1,3})\s*\/\s*100/i;
/** Match a leading bare/frontmatter `overall_score: N` line. */
const OVERALL_SCORE_RE = /^\s*overall_score\s*:\s*(\d{1,3})\s*$/im;
/** Match a leading bare/frontmatter `blocking_findings: true|false`. */
const BLOCKING_FM_RE = /^\s*blocking_findings\s*:\s*(true|false)\s*$/im;

/**
 * Build the managerial {@link AuditSummary} from `audit-report.md` (§4.0 #5 /
 * §13.5). The score is parsed in THREE shapes, tried IN ORDER, null if none:
 *   1. frontmatter / leading bare `overall_score: N` → scoreSource 'frontmatter'
 *   2. `## Score: N/100` heading                     → scoreSource 'heading'
 *   3. `**Total** N/100` row in a `## Score(s)` table → scoreSource 'table'
 *
 * `blocking_findings` is the only reliably-present auditor field; parsed from a
 * leading `blocking_findings: true|false` line (the FIELD, not body prose).
 * `_generated_by` / `classification` are CONDITIONAL — their absence is NOT
 * treated as fabrication (unlike verifier outputs). The brief-only projection
 * fields (topReasons / nextSteps / headlineCs / previousScoreHint) are
 * conservative best-effort here (empty / "" / null) — the full §13.5 managerial
 * brief is a later phase; they are kept type-valid.
 */
async function readAudit(
  fs: FsReader,
  runDir: string,
  files: string[],
): Promise<AuditSummary> {
  const relPath = 'audit-report.md';
  const present = files.includes(relPath);

  if (!present) {
    return emptyAudit(relPath, false, ['no audit-report.md for this run']);
  }

  const text = await fs.readText(join(runDir, relPath));
  if (text === null || text.trim().length === 0) {
    return emptyAudit(relPath, true, ['audit-report.md unreadable or empty']);
  }

  const warnings: string[] = [];

  // --- score: three shapes, in order ---
  let overallScore: number | null = null;
  let scoreSource: AuditSummary['scoreSource'] = null;

  const fm = OVERALL_SCORE_RE.exec(text);
  if (fm) {
    overallScore = clampScore(parseInt(fm[1], 10));
    scoreSource = 'frontmatter';
  }
  if (overallScore === null) {
    const heading = SCORE_HEADING_RE.exec(text);
    if (heading) {
      overallScore = clampScore(parseInt(heading[1], 10));
      scoreSource = 'heading';
    }
  }
  if (overallScore === null) {
    const totalRow = SCORE_TOTAL_ROW_RE.exec(text);
    if (totalRow) {
      overallScore = clampScore(parseInt(totalRow[1], 10));
      scoreSource = 'table';
    }
  }
  if (overallScore === null) {
    warnings.push('score unparseable — none of the three shapes matched');
  }

  // --- blocking_findings (the one reliable field) ---
  let blockingFindings: boolean | null = null;
  let blockingFindingsSource: AuditSummary['blockingFindingsSource'] = null;
  const bf = BLOCKING_FM_RE.exec(text);
  if (bf) {
    blockingFindings = bf[1].toLowerCase() === 'true';
    blockingFindingsSource = 'frontmatter';
  } else {
    warnings.push('blocking_findings field not found');
  }

  // --- categories from a `## Score(s)` table (best-effort) ---
  const categories = parseScoreCategories(text);

  // --- findings → topRisks + counts + autoFixableCount (best-effort) ---
  const { topRisks, countsBySeverity, autoFixableCount } = parseFindings(text);

  return {
    present: true,
    overallScore,
    scoreSource,
    blockingFindings,
    blockingFindingsSource,
    categories,
    topReasons: [], // brief-only projection — later phase (§13.5)
    topRisks,
    countsBySeverity,
    autoFixableCount,
    nextSteps: [], // brief-only projection — later phase (§13.5)
    headlineCs: '', // brief-only projection — later phase (§13.5)
    previousScoreHint: null, // brief-only projection — later phase (§13.5)
    rawRelPath: relPath,
    warnings,
  };
}

/** A conservative, type-valid empty AuditSummary. */
function emptyAudit(
  rawRelPath: string,
  present: boolean,
  warnings: string[],
): AuditSummary {
  return {
    present,
    overallScore: null,
    scoreSource: null,
    blockingFindings: null,
    blockingFindingsSource: null,
    categories: [],
    topReasons: [],
    topRisks: [],
    countsBySeverity: { Critical: 0, High: 0, Medium: 0, Low: 0 },
    autoFixableCount: 0,
    nextSteps: [],
    headlineCs: '',
    previousScoreHint: null,
    rawRelPath,
    warnings,
  };
}

function clampScore(n: number): number | null {
  if (Number.isNaN(n)) return null;
  return Math.max(0, Math.min(100, n));
}

/**
 * Parse a `## Score(s)` table into {@link AuditSummary.categories}. Rows look
 * like `| Code | 22/25 |` or `| Security | 92 |`; the `**Total**` row is the
 * headline (excluded from per-category rows). Best-effort — an unrecognized
 * table yields `[]`.
 */
function parseScoreCategories(text: string): AuditSummary['categories'] {
  const out: AuditSummary['categories'] = [];
  // Isolate the body under a `## Score` / `## Scores` heading: everything from
  // the heading line up to the next `## ` heading, a `---` rule, or end of text.
  // NOTE: no `/m` here — a multiline `$` would let the lazy group match zero
  // chars (it satisfies at the first line end), yielding an empty block.
  const headingMatch = /^##[ \t]+scores?\b.*$/im.exec(text);
  if (!headingMatch) return out;
  const after = text.slice(headingMatch.index + headingMatch[0].length);
  const stop = after.search(/\n##[ \t]|\n-{3,}/);
  const block = stop === -1 ? after : after.slice(0, stop);
  for (const line of block.split('\n')) {
    const row = line.match(/^\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|/);
    if (!row) continue;
    const label = row[1].replace(/\*/g, '').trim();
    const cell = row[2].replace(/\*/g, '').trim();
    const lower = label.toLowerCase();
    if (lower === 'dimension' || lower === '' || /^-+$/.test(label)) continue;
    if (lower === 'total') continue; // headline, not a category
    const scoreMatch = cell.match(/^(\d{1,3})(?:\s*\/\s*(\d{1,3}))?/);
    if (!scoreMatch) continue;
    const rawNum = parseInt(scoreMatch[1], 10);
    const denom = scoreMatch[2] ? parseInt(scoreMatch[2], 10) : 100;
    const max: 25 | 100 = denom === 25 ? 25 : 100;
    const normalized = max === 25 ? rawNum * 4 : rawNum;
    out.push({
      category: label,
      score: clampScore(normalized) ?? 0,
      rawScore: cell,
      max,
      status: null,
    });
  }
  return out;
}

/**
 * Parse `### Critical|High|Medium|Low` finding sub-sections into severity counts,
 * top risks (Critical + High), and the auto-fixable count. Best-effort and
 * defensive — an audit report without finding sections yields zero counts.
 */
function parseFindings(text: string): {
  topRisks: AuditSummary['topRisks'];
  countsBySeverity: AuditSummary['countsBySeverity'];
  autoFixableCount: number;
} {
  const counts = { Critical: 0, High: 0, Medium: 0, Low: 0 };
  const topRisks: AuditSummary['topRisks'] = [];
  let autoFixableCount = 0;

  // Split on `###` headings; each block belongs to the nearest severity heading.
  const sevHeadingRe = /^###\s+(Critical|High|Medium|Low)\b/gim;
  const headings: { sev: keyof typeof counts; index: number }[] = [];
  let hm: RegExpExecArray | null;
  while ((hm = sevHeadingRe.exec(text)) !== null) {
    const sev = (hm[1][0].toUpperCase() + hm[1].slice(1).toLowerCase()) as keyof typeof counts;
    headings.push({ sev, index: hm.index });
  }

  for (let i = 0; i < headings.length; i++) {
    const start = headings[i].index;
    const end = i + 1 < headings.length ? headings[i + 1].index : text.length;
    const block = text.slice(start, end);
    const sev = headings[i].sev;

    // Each finding is a `**[ID] title**` bold marker within the block.
    const findingMarkers = block.match(/^\s*\*\*\[[^\]]+\][^\n]*\*\*/gim) ?? [];
    const n = findingMarkers.length;
    counts[sev] += n;

    // auto_fixable: true markers within the block.
    autoFixableCount += (block.match(/^\s*auto_fixable\s*:\s*true\s*$/gim) ?? []).length;

    if ((sev === 'Critical' || sev === 'High') && n > 0) {
      for (const marker of findingMarkers) {
        const finding = marker.replace(/\*/g, '').trim();
        topRisks.push({
          severity: sev,
          area: null,
          auditType: null,
          finding,
          recommendation: null,
          effort: null,
          autoFixable: null,
        });
      }
    }
  }

  // Critical first, then High.
  topRisks.sort((a, b) => (a.severity === b.severity ? 0 : a.severity === 'Critical' ? -1 : 1));
  return { topRisks, countsBySeverity: counts, autoFixableCount };
}

// ===========================================================================
// #2 — steps[] derived from timeline + verify-file mtimes (NOT fsm-state.steps[])
// ===========================================================================

/**
 * Derive `steps[]` from the timeline + verify-file presence/mtimes (§4.0 #2),
 * NEVER from `fsm-state.steps[]` (which is always `pending` / empty / null on
 * DONE runs). A step is considered DONE when its `step-N-verify.md` (or
 * `verifier-output-step-N.md`) file exists; `durationS` is a file-mtime boundary
 * approximation, `null` when the bounding mtimes are missing.
 *
 * Step roles are taken from `plan.json.steps[]` when available (id → role);
 * names from the verify-file H1 title when present. The step count is the max of
 * fsm `totalSteps`, the highest verify-file index, and any plan.json steps.
 */
async function deriveSteps(
  fs: FsReader,
  runDir: string,
  files: string[],
  fsm: FsmTop,
  timeline: ActivityEvent[],
): Promise<RunStep[]> {
  // --- which step indices have a verify / verifier-output file? ---
  // Files use 0-based indices: step-0-verify.md, verifier-output-step-0.md.
  const verifyIdx = new Set<number>();
  const verifyFileFor = new Map<number, string>();
  for (const f of files) {
    let m = f.match(/^step-(\d+)-verify\.md$/);
    if (m) {
      const idx = parseInt(m[1], 10);
      verifyIdx.add(idx);
      if (!verifyFileFor.has(idx)) verifyFileFor.set(idx, f);
      continue;
    }
    m = f.match(/^verifier-output-step-(\d+)\.md$/);
    if (m) {
      const idx = parseInt(m[1], 10);
      verifyIdx.add(idx);
      if (!verifyFileFor.has(idx)) verifyFileFor.set(idx, f);
    }
  }

  // --- plan.json: id → role + objective (for names/roles) ---
  const planSteps = await readPlanSteps(fs, runDir);

  // --- total step count: prefer fsm totalSteps; reconcile with evidence ---
  const maxVerifyIdx = verifyIdx.size > 0 ? Math.max(...verifyIdx) : -1;
  const totalFromFsm = fsm.totalSteps ?? 0;
  const total = Math.max(totalFromFsm, maxVerifyIdx + 1, planSteps.length);
  if (total === 0) return [];

  // mtime boundaries (file-mtime approximation for durationS).
  const mtimeCache = new Map<number, number | null>();
  const mtimeForIdx = async (idx: number): Promise<number | null> => {
    if (mtimeCache.has(idx)) return mtimeCache.get(idx) ?? null;
    const file = verifyFileFor.get(idx);
    const m = file ? await fs.statMtime(join(runDir, file)) : null;
    mtimeCache.set(idx, m);
    return m;
  };

  const steps: RunStep[] = [];
  // currentStep marks the boundary between done/executing for in-flight runs.
  const current = fsm.currentStep ?? 0;
  const terminal = fsm.state === 'DONE';

  for (let i = 0; i < total; i++) {
    // Display id is 1-based; the file/index space is 0-based.
    const displayId = i + 1;
    const plan = planSteps[i] ?? null;

    // name: verify-file title > plan objective (first line) > "".
    let name = '';
    const vf = verifyFileFor.get(i);
    if (vf) {
      const title = await readVerifyTitle(fs, join(runDir, vf));
      if (title) name = title;
    }
    if (name === '' && plan) name = firstLine(plan.objective);

    const hasVerify = verifyIdx.has(i);
    let status: RunStep['status'];
    if (hasVerify) {
      status = 'done';
    } else if (!terminal && i === current) {
      status = 'executing';
    } else if (terminal) {
      // DONE run without a verify file for this index → still count as done
      // when within currentStep, else pending (defensive; do not fabricate).
      status = i < current ? 'done' : 'pending';
    } else {
      status = 'pending';
    }

    // durationS: boundary approximation between this step's verify-file mtime
    // and the previous step's (null when either is missing).
    let durationS: number | null = null;
    const thisMtime = await mtimeForIdx(i);
    const prevMtime = i > 0 ? await mtimeForIdx(i - 1) : (fsm.startedAt ? Date.parse(fsm.startedAt) : null);
    if (thisMtime !== null && prevMtime !== null && thisMtime >= prevMtime) {
      durationS = Math.round((thisMtime - prevMtime) / 1000);
    }

    // completedAt: the verify-file mtime as ISO (approx) when present.
    const completedAt =
      hasVerify && thisMtime !== null ? new Date(thisMtime).toISOString() : null;

    steps.push({
      id: displayId,
      name,
      status,
      role: plan?.role ?? null,
      startedAt: null, // not reliably recorded per-step (§4.0 #2)
      completedAt,
      durationS,
    });
  }

  // Corroborate roles from timeline dispatch focus when plan.json lacked them.
  void timeline; // timeline corroboration reserved; presence already drives status
  return steps;
}

interface PlanStep {
  role: string | null;
  objective: string;
}

/** Read `plan.json.steps[]` → ordered { role, objective }. Never throws. */
async function readPlanSteps(fs: FsReader, runDir: string): Promise<PlanStep[]> {
  const parsed = await fs.readJsonParsed<Record<string, unknown>>(
    join(runDir, 'plan.json'),
  );
  const d = parsed.data;
  if (d === null || typeof d !== 'object' || !Array.isArray(d.steps)) return [];
  const out: PlanStep[] = [];
  for (const s of d.steps as unknown[]) {
    if (typeof s !== 'object' || s === null) {
      out.push({ role: null, objective: '' });
      continue;
    }
    const ss = s as Record<string, unknown>;
    out.push({
      role: asString(ss.role),
      objective: asString(ss.objective) ?? '',
    });
  }
  return out;
}

/** Read the first H1 title from a verify markdown file (best-effort). */
async function readVerifyTitle(fs: FsReader, path: string): Promise<string | null> {
  const text = await fs.readText(path);
  if (text === null) return null;
  const m = text.match(/^#\s+(.+)$/m);
  return m ? m[1].trim() : null;
}

function firstLine(s: string): string {
  const line = s.split('\n')[0]?.trim() ?? '';
  return line.length > 120 ? line.slice(0, 120) : line;
}

// ===========================================================================
// #3, #4 — checkpoints (provenance from compliance; repeats from files/timeline)
// ===========================================================================

/** Static labels for the six checkpoints. */
const CHECKPOINT_LABELS: Record<CheckpointId, string> = {
  CP1: 'Plan grounding',
  CP2: 'Per-step verification',
  CP3: 'Integration review',
  CP4: 'Curator validation',
  CP5: 'Compliance / done-advance',
  CP6: 'Plan-boundary review',
};

/**
 * Build the checkpoint list (§4.0 #3 + #4).
 *
 * **Provenance (#3):** READ from `compliance.json.checks.verifierOutputs.*`
 * (already camelCased). `provenanceSource:'compliance'`. The timeline dispatch
 * pairs are only corroboration. When compliance.json is absent, provenance is
 * `null` ("not recorded"), NOT 'unverifiable' — 23/26 real timelines have ZERO
 * dispatch events while verifier-output md files exist, so re-deriving would
 * falsely mark everything unverifiable.
 *
 * **repeatCount (#4):**
 *  - CP1 from the file inventory (`repeatSource:'files'`).
 *  - CP2/CP3/CP4 from timeline `verifier_dispatch_start` grouped by focus minus
 *    1 (`repeatSource:'timeline'`); `null` + `repeatSource:null` when there are
 *    no dispatch events (the common case) — NEVER 0.
 *  - CP6 omitted/greyed for /aid-run runs.
 */
function buildCheckpoints(
  compliance: ComplianceRun | null,
  timeline: ActivityEvent[],
  files: string[],
  gates: GateResult[],
  format: RunFormat,
): Checkpoint[] {
  void gates; // gates inform CP5 verdict only via compliance; reserved
  void format;
  const vo = readVerifierOutputs(compliance);

  // Group timeline dispatch starts by focus for repeat counts (#4).
  const dispatchByFocus = new Map<string, number>();
  for (const e of timeline) {
    if (e.event !== 'verifier_dispatch_start') continue;
    const focus = asString(e.raw.focus);
    if (focus === null) continue;
    dispatchByFocus.set(focus, (dispatchByFocus.get(focus) ?? 0) + 1);
  }
  const anyDispatch = dispatchByFocus.size > 0;

  // CP2 repeat: max repeats across the cp2-step-* focuses (minus 1), else null.
  const cp2Repeat = focusGroupRepeat(dispatchByFocus, /^cp2-step-\d+$/, anyDispatch);
  const cp3Repeat = focusGroupRepeat(dispatchByFocus, /^cp3-/, anyDispatch);
  const cp4Repeat = focusGroupRepeat(dispatchByFocus, /^cp4-/, anyDispatch);

  const checkpoints: Checkpoint[] = [];

  // --- CP1: plan grounding — repeat from file inventory (#4) ---
  const cp1Files = files.filter(
    (f) => /cp1/i.test(f) || /grounding/i.test(f) || /^plan-diff\.json$/.test(f),
  );
  checkpoints.push({
    id: 'CP1',
    label: CHECKPOINT_LABELS.CP1,
    dispatched: cp1Files.length > 0 || files.includes('plan.json'),
    verdict: null,
    provenance: null,
    provenanceSource: null,
    repeatCount: cp1Files.length > 0 ? cp1Files.length : null,
    repeatSource: cp1Files.length > 0 ? 'files' : null,
    outputs: cp1Files.map((f) => ({ name: basename(f), relPath: f })),
  });

  // --- CP2: per-step verification ---
  checkpoints.push({
    id: 'CP2',
    label: CHECKPOINT_LABELS.CP2,
    dispatched: vo.cp2Dispatched ?? files.some((f) => /^verifier-output-step-\d+\.md$/.test(f)),
    verdict: vo.cp2Verdict,
    provenance: vo.cp2Provenance,
    provenanceSource: vo.cp2Provenance !== null ? 'compliance' : null,
    repeatCount: cp2Repeat,
    repeatSource: cp2Repeat !== null ? 'timeline' : null,
    outputs: files
      .filter((f) => /^verifier-output-step-\d+\.md$/.test(f))
      .map((f) => ({ name: basename(f), relPath: f })),
  });

  // --- CP3: integration review (code-review + security) ---
  const cp3Files = files.filter((f) => /^verifier-output-cp3-/.test(f));
  checkpoints.push({
    id: 'CP3',
    label: CHECKPOINT_LABELS.CP3,
    dispatched: vo.cp3Dispatched ?? cp3Files.length > 0,
    verdict: vo.cp3Verdict,
    provenance: vo.cp3Provenance,
    provenanceSource: vo.cp3Provenance !== null ? 'compliance' : null,
    repeatCount: cp3Repeat,
    repeatSource: cp3Repeat !== null ? 'timeline' : null,
    outputs: cp3Files.map((f) => ({ name: basename(f), relPath: f })),
  });

  // --- CP4: curator validation ---
  const cp4Files = files.filter((f) => /^verifier-output-cp4-/.test(f));
  checkpoints.push({
    id: 'CP4',
    label: CHECKPOINT_LABELS.CP4,
    dispatched: cp4Files.length > 0,
    verdict: null,
    provenance: null,
    provenanceSource: null,
    repeatCount: cp4Repeat,
    repeatSource: cp4Repeat !== null ? 'timeline' : null,
    outputs: cp4Files.map((f) => ({ name: basename(f), relPath: f })),
  });

  // --- CP5: compliance / done-advance (verdict from compliance overall) ---
  checkpoints.push({
    id: 'CP5',
    label: CHECKPOINT_LABELS.CP5,
    dispatched: compliance !== null,
    verdict: compliance === null ? null : compliance.overall === 'pass' ? 'pass' : 'fail',
    provenance: compliance !== null ? vo.aggregate : null,
    provenanceSource: compliance !== null && vo.aggregate !== null ? 'compliance' : null,
    repeatCount: null,
    repeatSource: null,
    outputs: compliance !== null ? [{ name: 'compliance.json', relPath: 'compliance.json' }] : [],
  });

  // CP6 is intentionally omitted for /aid-run runs (greyed in the UI).
  return checkpoints;
}

interface VerifierOutputs {
  cp2Dispatched: boolean | null;
  cp2Verdict: Verdict;
  cp2Provenance: string | string[] | null;
  cp3Dispatched: boolean | null;
  cp3Verdict: Verdict;
  cp3Provenance: string | string[] | null;
  aggregate: string | null;
}

/**
 * Read the structured `verifier_outputs` block from compliance (§4.0 #3). Keys
 * are camelCased: `cp2_per_step_verdict`→`cp2PerStepVerdict`,
 * `cp3_code_review_provenance`→`cp3CodeReviewProvenance`,
 * `provenance_aggregate`→`provenanceAggregate`. Returns all-null when there is
 * no compliance — provenance "not recorded", NOT 'unverifiable'.
 */
function readVerifierOutputs(compliance: ComplianceRun | null): VerifierOutputs {
  const blank: VerifierOutputs = {
    cp2Dispatched: null,
    cp2Verdict: null,
    cp2Provenance: null,
    cp3Dispatched: null,
    cp3Verdict: null,
    cp3Provenance: null,
    aggregate: null,
  };
  if (compliance === null) return blank;
  const vo = compliance.checks?.verifierOutputs;
  if (typeof vo !== 'object' || vo === null) return blank;
  const v = vo as Record<string, unknown>;

  const cp3CodeProv = v.cp3CodeReviewProvenance;
  const cp3SecProv = v.cp3SecurityProvenance;
  const cp3Provenance: string | string[] | null = (() => {
    const arr: string[] = [];
    if (typeof cp3CodeProv === 'string') arr.push(cp3CodeProv);
    if (typeof cp3SecProv === 'string') arr.push(cp3SecProv);
    return arr.length === 0 ? null : arr.length === 1 ? arr[0] : arr;
  })();

  return {
    cp2Dispatched: typeof v.cp2PerStepDispatched === 'boolean' ? v.cp2PerStepDispatched : null,
    cp2Verdict: asVerdict(v.cp2PerStepVerdict),
    cp2Provenance: Array.isArray(v.cp2PerStepProvenance)
      ? (v.cp2PerStepProvenance.filter((x) => typeof x === 'string') as string[])
      : typeof v.cp2PerStepProvenance === 'string'
        ? v.cp2PerStepProvenance
        : null,
    cp3Dispatched:
      typeof v.cp3CodeReviewDispatched === 'boolean'
        ? v.cp3CodeReviewDispatched
        : typeof v.cp3SecurityDispatched === 'boolean'
          ? v.cp3SecurityDispatched
          : null,
    cp3Verdict: asVerdict(v.cp3CodeReviewVerdict) ?? asVerdict(v.cp3SecurityVerdict),
    cp3Provenance,
    aggregate: typeof v.provenanceAggregate === 'string' ? v.provenanceAggregate : null,
  };
}

/**
 * For a focus-group regex, return `maxCountInGroup - 1` (number of REPEATS
 * beyond the first dispatch), or `null` when there are no matching dispatch
 * events (§4.0 #4 — null, never 0). `anyDispatch` short-circuits the common
 * zero-dispatch case so a focus that never fired stays null.
 */
function focusGroupRepeat(
  dispatchByFocus: Map<string, number>,
  groupRe: RegExp,
  anyDispatch: boolean,
): number | null {
  if (!anyDispatch) return null; // §4.0 #4 — no dispatch events → null
  let max = 0;
  let matched = false;
  for (const [focus, count] of dispatchByFocus) {
    if (groupRe.test(focus)) {
      matched = true;
      if (count > max) max = count;
    }
  }
  if (!matched) return null;
  return Math.max(0, max - 1);
}

function asVerdict(v: unknown): Verdict {
  if (v === 'pass' || v === 'fail' || v === 'skipped' || v === 'unverifiable') return v;
  return null;
}

// ===========================================================================
// Reports
// ===========================================================================

/**
 * Classify report-like files in the run dir into {@link ReportRef}[]. Reuses the
 * known report names; everything else under a report directory is `'other'`.
 */
function buildReports(files: string[]): ReportRef[] {
  const out: ReportRef[] = [];
  for (const f of files) {
    const name = basename(f);
    let kind: ReportRef['kind'] | null = null;
    if (name === 'audit-report.md') kind = 'audit';
    else if (name === 'curator-report.md') kind = 'curator';
    else if (name === 'simplifier-report.md') kind = 'reporter';
    else if (name === 'epic-summary.md') kind = 'epic-summary';
    else if (name === 'final_report.md') kind = 'final';
    else if (/^reporter\//.test(f)) kind = 'reporter';
    if (kind !== null) out.push({ kind, name, relPath: f });
  }
  return out;
}

// ===========================================================================
// Step 7↔8 wiring: factory that injects buildRunDetail as the cache loader
// ===========================================================================

/**
 * Create a {@link RunDetailLoader} bound to a projects root + path-map roots.
 * This is the SEAM that closes the Step 7↔8 loop: the loader resolves the run
 * dir by the discovery convention (or via a supplied resolver) and delegates to
 * {@link buildRunDetail}. The loader is what the {@link ScannerCache} memoizes.
 *
 * The cache prefers its Tier-1 index when resolving run dirs; this loader's own
 * convention path is only used when the cache calls it with a triple whose dir
 * it could not resolve from the index (the cache passes nothing but the triple,
 * so the loader reconstructs the dir under `<projectsRoot>/<projectId>/.aid-o/
 * work/evidence/<epicId>/<runId>`, mirroring `ScannerCache.resolveRunDir`).
 */
export function createRunDetailLoader(opts: {
  projectsRoot: string;
  hostRoot: string;
  fs?: FsReader;
  /** Optional override that resolves a run dir from the cache's Tier-1 index. */
  resolveRunDir?: (projectId: string, epicId: string, runId: string) => string;
}): (projectId: string, epicId: string, runId: string) => Promise<RunDetail> {
  const fs = opts.fs ?? new FsReader();
  const pathMap = createPathMap({
    projectsRoot: opts.projectsRoot,
    hostRoot: opts.hostRoot,
  });
  return (projectId: string, epicId: string, runId: string): Promise<RunDetail> => {
    const runDir =
      opts.resolveRunDir?.(projectId, epicId, runId) ??
      join(opts.projectsRoot, projectId, '.aid-o', 'work', 'evidence', epicId, runId);
    return buildRunDetail(projectId, epicId, runId, runDir, { fs, pathMap });
  };
}

// ===========================================================================
// Local primitive coercion helpers (never throw)
// ===========================================================================

function asString(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null;
}

function asNumber(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

function asIso(v: unknown): string | null {
  if (typeof v === 'string' && v.length > 0) return v;
  if (v instanceof Date) return v.toISOString();
  return null;
}

function asStringArray(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return v.filter((x): x is string => typeof x === 'string');
}
