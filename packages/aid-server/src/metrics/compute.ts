/**
 * Metrics computation (EPIC E-047-4_7, Step 2).
 *
 * The SINGLE source of truth for the contract {@link MetricSet} plus the two
 * §5.7 headline derived scores ({@link computeFsmAdherenceScore} for
 * ComplianceView, {@link computeHealth} for Project.health / the infra tile).
 *
 * Reconciliation (the Phase-3 lesson — divergent selectors caused real bugs):
 * `services/view-assembly.ts buildMetrics` now DELEGATES to {@link computeMetrics}
 * here; there is exactly one MetricSet builder. The richer §5.7 run-set helpers
 * live only in this module — they operate on a `RunDetail[]` scope (per project
 * or cross-project), which the per-EPIC MetricSet does not need.
 *
 * §5.7 honesty posture (the audit's exact concern): a missing signal is NEVER
 * counted as "clean". Each penalty/blend term's denominator is the count of runs
 * for which that signal is actually AVAILABLE, not the total run count. A term
 * with zero available runs is DROPPED from the weighting (re-normalize) and sets
 * `partial:true`. Below a data threshold ⇒ `value:null`, `partial:true`,
 * `confidence:'low'` — never a single fabricated number, never a silent 0.
 *
 * Determinism: every function is a pure projection over already-parsed contract
 * objects. No disk reads, no clock, no network. The same inputs always produce
 * the same output.
 *
 * Module: src/metrics/compute.ts
 */

import type {
  ActivityEvent,
  CheckpointId,
  MetricSet,
  Project,
  RunDetail,
  RunStep,
  RunSummary,
  Score,
  TimeSource,
} from '@aid/contract';

// ===========================================================================
// Per-run signal-availability probes (§5.7 — the available-runs denominators)
// ===========================================================================
//
// Each §5.7 penalty/blend term is divided by the count of runs for which THAT
// term's source signal actually exists on disk. These predicates name, per run,
// whether the signal is present — so a run missing the signal is DROPPED from
// that term's denominator (never folded into the numerator as a clean 0).

/** A run HAS a `gates_report.json` (parsed gates, or the file on disk). */
export function hasGatesReport(run: RunDetail): boolean {
  if (run.gates.length > 0) return true;
  return run.files.some(
    (f) => f === 'gates_report.json' || f.endsWith('/gates_report.json'),
  );
}

/** A run HAS a `compliance.json` (parsed → non-null ComplianceRun). */
export function hasCompliance(run: RunDetail): boolean {
  return run.compliance !== null;
}

/** A run HAS a non-empty per-run timeline (the only source of precondition fails). */
export function hasNonEmptyTimeline(run: RunDetail): boolean {
  return run.timeline.length > 0;
}

/**
 * A run HAS a parseable `fsm-state.yaml`. `format === 'v3'` means fsm-state.yaml
 * was present AND parseable (run-detail.ts `classifyFormat`); the escalationCount
 * scalar is read from it.
 */
export function hasFsmState(run: RunDetail): boolean {
  return run.format === 'v3';
}

// ===========================================================================
// computeRunDuration (§5.1) — READY→EXECUTE run-start anchor (NOT fsm_init)
// ===========================================================================

/** Provenance tags for the run-duration window (surfaced so the UI can warn). */
export interface RunDurationResult {
  durationS: number | null;
  startSource: 'ready_execute' | 'init_idle_included' | null;
  endSource: 'done_advance' | 'compliance_written' | 'last_transition_done' | 'max_mtime' | null;
  incomplete: boolean;
  warnings: string[];
}

/**
 * Wall-clock of active work in ONE run (§5.1 `run_duration_sec`).
 *
 * Start anchor = the FIRST `READY→EXECUTE` `fsm_transition` (the Phase-3 MED-1
 * lesson: NOT `fsm_init`, which can precede real work by hours of PM-idle time).
 * Falls back to `fsm_init` only when no such transition exists, tagging
 * `start_source:'init_idle_included'` + a warning.
 *
 * End fallback chain: `fsm_done_advance` → `compliance_written` → last
 * `fsm_transition` to DONE (the LAST fallback is the common case on real disk).
 * Open run with no end event → `max(file mtime)`, `incomplete:true`. No usable
 * timeline anchor at all → `null` (NOT 0), `NOT_COMPUTABLE` warning.
 *
 * `files` carry no mtimes in the contract shape, so the `max(file mtime)` open-run
 * fallback uses the latest parseable timeline `ts` as the run's last-known-active
 * marker — the same boundary RunDetail already exposes (no new measurement).
 */
export function computeRunDuration(
  timeline: ActivityEvent[],
  _files: string[],
): RunDurationResult {
  const warnings: string[] = [];

  // --- start anchor: first READY→EXECUTE fsm_transition ---
  let startMs: number | null = null;
  let startSource: RunDurationResult['startSource'] = null;
  for (const e of timeline) {
    if (e.event === 'fsm_transition' && e.from === 'READY' && e.to === 'EXECUTE') {
      const t = parseTs(e.ts);
      if (t !== null) {
        startMs = t;
        startSource = 'ready_execute';
        break; // first transition only
      }
    }
  }
  if (startMs === null) {
    // Fallback: fsm_init (idle gap INCLUDED — tag + warn so the UI labels it).
    for (const e of timeline) {
      if (e.event === 'fsm_init') {
        const t = parseTs(e.ts);
        if (t !== null) {
          startMs = t;
          startSource = 'init_idle_included';
          warnings.push(
            'run-start anchored at fsm_init (no READY→EXECUTE transition) — includes PM-idle time',
          );
          break;
        }
      }
    }
  }

  if (startMs === null) {
    warnings.push('run_duration_sec NOT_COMPUTABLE — no parseable start anchor in timeline');
    return { durationS: null, startSource: null, endSource: null, incomplete: false, warnings };
  }

  // --- end anchor: fsm_done_advance → compliance_written → last DONE transition ---
  let endMs: number | null = null;
  let endSource: RunDurationResult['endSource'] = null;

  endMs = lastTs(timeline, (e) => e.event === 'fsm_done_advance');
  if (endMs !== null) endSource = 'done_advance';

  if (endMs === null) {
    endMs = lastTs(timeline, (e) => e.event === 'compliance_written');
    if (endMs !== null) endSource = 'compliance_written';
  }
  if (endMs === null) {
    endMs = lastTs(
      timeline,
      (e) => e.event === 'fsm_transition' && e.to === 'DONE',
    );
    if (endMs !== null) endSource = 'last_transition_done';
  }

  let incomplete = false;
  if (endMs === null) {
    // Open run — boundary = the latest parseable timeline ts (last-known-active).
    endMs = lastTs(timeline, () => true);
    if (endMs !== null) {
      endSource = 'max_mtime';
      incomplete = true;
      warnings.push('open run — end anchored at last timeline event (incomplete)');
    }
  }

  if (endMs === null || endMs < startMs) {
    warnings.push('run_duration_sec NOT_COMPUTABLE — no usable end anchor after start');
    return { durationS: null, startSource, endSource: null, incomplete: false, warnings };
  }

  return {
    durationS: Math.round((endMs - startMs) / 1000),
    startSource,
    endSource,
    incomplete,
    warnings,
  };
}

// ===========================================================================
// computeCheckpointRepeats (§5.2) — pass through the RunDetail repeat sourcing
// ===========================================================================

const CHECKPOINT_IDS: CheckpointId[] = ['CP1', 'CP2', 'CP3', 'CP4', 'CP5', 'CP6'];

/**
 * Per-checkpoint repeat counts (§5.2). The per-checkpoint sourcing rule
 * (CP1 = file inventory; CP2/CP3/CP4 = timeline dispatch groups; null — NEVER 0
 * — when no dispatch signal) is applied by RunDetail's `buildCheckpoints`; this
 * is a faithful projection of that `repeatCount` into the `Record<CheckpointId>`
 * shape `MetricSet.checkpointRepeats` needs. `null` is preserved as `null`.
 */
export function computeCheckpointRepeats(
  run: RunDetail | null,
): Record<CheckpointId, number | null> {
  const out = {} as Record<CheckpointId, number | null>;
  for (const id of CHECKPOINT_IDS) {
    out[id] = run?.checkpoints.find((c) => c.id === id)?.repeatCount ?? null;
  }
  return out;
}

// ===========================================================================
// buildTimeBy (§13.9 / §5.1) — the TimeSource seam (MVP1 = mostly neměřeno)
// ===========================================================================

/**
 * MetricSet.timeBy: measured time PER ACTOR (§13.9 seam). MVP1 honest behaviour:
 *  - `user` / `dev` → `{ durationS:null, source:null }` ("neměřeno"); MVP1
 *    measures no human/dev time. WakaTime fills these in MVP2 with zero churn.
 *  - `ai` / `controller` → a BEST-EFFORT `durationS` re-projected from the
 *    existing §5.1 timeline numbers (`source:'timeline'`); this adds NO new
 *    measurement, it re-slices the run's own active-work window. `null` +
 *    `source:null` when the timeline yields no anchor (never a fabricated number).
 *
 * The single timeline window is attributed to `ai` (the agents do the work); the
 * `controller` slot carries the same provenance with a `null` duration in MVP1
 * (the controller's wall time is not separable from the timeline — §5.6), so it
 * shows as a present-but-unmeasured actor rather than being dropped.
 */
export function buildTimeBy(timeline: ActivityEvent[]): TimeSource[] {
  const dur = computeRunDuration(timeline, []);
  const aiDuration = dur.durationS;
  return [
    { kind: 'ai', durationS: aiDuration, source: aiDuration !== null ? 'timeline' : null },
    { kind: 'controller', durationS: null, source: aiDuration !== null ? 'timeline' : null },
    { kind: 'user', durationS: null, source: null },
    { kind: 'dev', durationS: null, source: null },
  ];
}

// ===========================================================================
// computeMetrics (§5.1–§5.3) — the SINGLE MetricSet builder
// ===========================================================================

/**
 * Derive the per-EPIC {@link MetricSet} from the latest full {@link RunDetail}
 * plus the run summaries (run count). The SINGLE MetricSet builder —
 * `view-assembly.buildMetrics` delegates here.
 *
 * Step timings are file-mtime boundary approximations carried on `RunDetail.steps`
 * (run-detail.ts §4.0 #2). Per-step `durationS` stays `null` (NEVER 0) when the
 * verify-file mtimes are absent; when every step is null we emit a
 * `no_step_timing` flag and `stepTimingSource:null` (§5.6). Gate counts
 * (`gateRuns`/`gateRetries`) and `runCount` are NON-null integers — they are real
 * counts, not nullable durations (MF1).
 */
export function computeMetrics(latest: RunDetail | null, runs: RunSummary[]): MetricSet {
  const warnings: string[] = [];

  const steps: RunStep[] = latest ? latest.steps : [];
  const stepDurationsS: (number | null)[] = steps.map((s) => s.durationS);
  const measured = stepDurationsS.filter((d): d is number => d !== null);

  const avgStepDurationS =
    measured.length > 0
      ? Math.round(measured.reduce((a, b) => a + b, 0) / measured.length)
      : null;

  let longestStep: MetricSet['longestStep'] = null;
  for (const s of steps) {
    if (s.durationS === null) continue;
    if (longestStep === null || s.durationS > longestStep.durationS) {
      longestStep = { id: s.id, durationS: s.durationS };
    }
  }

  // §5.1 epicWallTimeS: prefer the run-duration window from the timeline; fall
  // back to summed step boundaries only when the timeline yields no anchor.
  let epicWallTimeS: number | null = null;
  if (latest) {
    const rd = computeRunDuration(latest.timeline, latest.files);
    if (rd.durationS !== null) {
      epicWallTimeS = rd.durationS;
    } else if (measured.length > 0) {
      epicWallTimeS = measured.reduce((a, b) => a + b, 0);
    }
  }

  // §5.6 step-timing honesty: null (never 0) per step; flag when none measurable.
  const stepTimingSource: MetricSet['stepTimingSource'] =
    latest && measured.length > 0 ? 'mtime' : null;
  if (latest !== null && steps.length > 0 && measured.length === 0) {
    warnings.push('no_step_timing — verify-file mtimes absent; per-step durations null');
  }
  if (latest === null) warnings.push('no latest run — metrics unavailable');

  // partial:true when latest is null OR there is NO usable data: no wall time,
  // no step timing, every step duration null, AND every checkpoint repeat null.
  // (computeCheckpointRepeats returns a Record, never === null — the bug was
  // comparing the object to null; check its VALUES. Real case: vulcan/E-045-7_8
  // has a run but all times + CP repeats null → must be partial:true.)
  const cpRepeats = computeCheckpointRepeats(latest);
  const allCpNull =
    cpRepeats === null || Object.values(cpRepeats).every((v) => v === null);
  const allStepsNull = stepDurationsS.every((d) => d === null);
  const noUsableData =
    latest !== null &&
    epicWallTimeS === null &&
    stepTimingSource === null &&
    allStepsNull &&
    allCpNull;
  const partial = latest === null || noUsableData;

  return {
    epicWallTimeS,
    runCount: runs.length,
    stepDurationsS,
    avgStepDurationS,
    longestStep,
    stepTimingSource,
    // Gate counts are real counts (non-null), NEVER nullable durations (MF1).
    gateRuns: latest ? latest.gates.length : 0,
    gateRetries: latest ? latest.gateRetries : 0,
    checkpointRepeats: computeCheckpointRepeats(latest),
    escalations: latest ? latest.escalationCount : 0,
    timeBy: latest ? buildTimeBy(latest.timeline) : buildTimeBy([]),
    partial,
    warnings,
  };
}

// ===========================================================================
// computeFsmAdherenceScore (§5.7) — penalty model over a run SET
// ===========================================================================

/**
 * `fsmAdherenceScore` (§5.7) — "Drží se AID svého procesu?" A penalty model over
 * a run set (per project, or all projects). Each penalty term's denominator is
 * the count of runs where THAT signal is available (§5.7 per-term denominators):
 *  - force_override  → runs with compliance.json OR a non-empty timeline
 *  - precondition    → runs with a non-empty timeline
 *  - gate_first_pass → runs that HAVE a gates_report.json
 *  - escalation      → runs with a parseable fsm-state.yaml
 *
 * A term with ZERO available runs is dropped (its weight is re-normalized away)
 * and sets `partial:true`. Data threshold: `value` is non-null ONLY with ≥3 runs
 * carrying a parseable fsm-state.yaml; below that ⇒ `value:null`, `partial:true`,
 * `confidence:'low'`, and the four-term breakdown renders instead of a number.
 * `confidence:'high'` only when ALL four terms have ≥3 available runs.
 */
export function computeFsmAdherenceScore(runSet: RunDetail[]): Score {
  const warnings: string[] = [];

  // --- per-term available-runs partitions (the §5.7 denominators) ---
  const forceRuns = runSet.filter((r) => hasCompliance(r) || hasNonEmptyTimeline(r));
  const timelineRuns = runSet.filter((r) => hasNonEmptyTimeline(r));
  const gatesRuns = runSet.filter((r) => hasGatesReport(r));
  const fsmRuns = runSet.filter((r) => hasFsmState(r));

  // --- per-term numerators (each over its OWN available-runs denominator) ---
  // force_override term: total force-overrides / available runs.
  const forceOverrideCount = forceRuns.reduce((sum, r) => sum + forceOverridesFor(r), 0);

  // precondition term: runs that had ≥1 precondition fail / runs with timeline.
  const runsWithPreconditionFail = timelineRuns.filter((r) =>
    r.timeline.some((e) => e.event === 'fsm_precondition_fail'),
  ).length;

  // gate first-pass rate: over runs with a gates_report.
  const gateFirstPassRate = gatesRuns.length > 0
    ? gatesRuns.filter((r) => gatesFirstPass(r)).length / gatesRuns.length
    : null;

  // escalation term: Σ escalationCount / runs with fsm-state.
  const escalationCount = fsmRuns.reduce((sum, r) => sum + r.escalationCount, 0);

  // --- weighted penalty terms, each dropped when its denominator is empty ---
  interface Term {
    name: string;
    weight: number;
    /** the penalty fraction in [0,1+]; null when the term's denominator is 0 */
    fraction: number | null;
  }
  const terms: Term[] = [
    {
      name: 'force_override',
      weight: 20,
      fraction: forceRuns.length > 0 ? forceOverrideCount / forceRuns.length : null,
    },
    {
      name: 'precondition',
      weight: 15,
      fraction: timelineRuns.length > 0 ? runsWithPreconditionFail / timelineRuns.length : null,
    },
    {
      name: 'gate_first_pass',
      weight: 10,
      fraction: gateFirstPassRate !== null ? 1 - gateFirstPassRate : null,
    },
    {
      name: 'escalation',
      weight: 5,
      fraction: fsmRuns.length > 0 ? escalationCount / fsmRuns.length : null,
    },
  ];

  const available = terms.filter((t) => t.fraction !== null);
  const dropped = terms.filter((t) => t.fraction === null);
  for (const t of dropped) {
    warnings.push(`term "${t.name}" dropped — zero available runs for its signal`);
  }
  const partial = dropped.length > 0;

  // --- re-normalize the surviving weights so a dropped term is not silently 0 ---
  const totalWeight = available.reduce((s, t) => s + t.weight, 0);
  let penalty = 0;
  if (totalWeight > 0) {
    const fullWeight = terms.reduce((s, t) => s + t.weight, 0); // 50
    for (const t of available) {
      const renorm = (t.weight / totalWeight) * fullWeight;
      penalty += renorm * (t.fraction as number);
    }
  }

  // --- the §5.7 component breakdown (always exposed) ---
  const components: Record<string, number | null> = {
    force_override_count: forceOverrideCount,
    runs_with_precondition_fail: runsWithPreconditionFail,
    gate_first_pass_rate: gateFirstPassRate !== null ? round2(gateFirstPassRate) : null,
    escalation_count: escalationCount,
  };

  // --- data threshold: ≥3 runs with a parseable fsm-state.yaml ---
  if (fsmRuns.length < 3) {
    warnings.push(`málo dat (n=${fsmRuns.length}) — fsmAdherenceScore below ≥3-runs threshold`);
    return { value: null, partial: true, confidence: 'low', components, warnings };
  }

  // confidence:'high' ONLY when ALL four terms have ≥3 available runs.
  const allTermsWellPopulated =
    forceRuns.length >= 3 &&
    timelineRuns.length >= 3 &&
    gatesRuns.length >= 3 &&
    fsmRuns.length >= 3;
  const confidence: Score['confidence'] = allTermsWellPopulated && !partial ? 'high' : 'low';

  const value = clamp(Math.round(100 - penalty), 0, 100);
  return { value, partial, confidence, components, warnings };
}

// ===========================================================================
// computeHealth (§5.7) — quality blend over a run SET (Project.health)
// ===========================================================================

/**
 * Aggregate `health` (§5.7) — a quality blend distinct from adherence (adherence
 * = did it follow the process; health = is the output sound). Blend:
 *   0.50 * compliance_checks_pass_rate (over NON-NULL checks; denominator ≥1)
 * + 0.30 * gate_final_pass_rate (over runs with a gates_report)
 * + 0.20 * (100 if openViolations == 0 else 0)  ← any open blocking fail = hard 0
 *
 * Data threshold: computed only with ≥1 run carrying a compliance.json; else
 * `value:null` and the tile shows "bez dat" (NEVER 0). `confidence:'low'` when
 * fewer than 3 runs contribute. The 0.50 term is dropped (partial) when there are
 * zero non-null checks. `openViolations` = the LATEST run's unresolved blocking
 * ComplianceFailure[] (§5.7 resolution rule: cleared when a LATER run of the same
 * EPIC has no failure with that `.check`).
 */
export function computeHealth(runSet: RunDetail[]): Project['health'] {
  const warnings: string[] = [];

  const complianceRuns = runSet.filter(hasCompliance);
  const gatesRuns = runSet.filter(hasGatesReport);

  // --- 0.50 term: compliance_checks_pass_rate over NON-NULL checks ---
  let nonNullChecks = 0;
  let passedChecks = 0;
  for (const r of complianceRuns) {
    const checks = r.compliance?.checks ?? {};
    for (const v of Object.values(checks)) {
      if (v === null) continue; // §5.3 — exclude null checks from the denominator
      nonNullChecks += 1;
      if (isPassCheck(v)) passedChecks += 1;
    }
  }
  const compliancePassRate = nonNullChecks > 0 ? round0((passedChecks / nonNullChecks) * 100) : null;

  // --- 0.30 term: gate_final_pass_rate over runs with a gates_report ---
  const gateFinalPassRate =
    gatesRuns.length > 0
      ? (gatesRuns.filter((r) => gatesFinalPass(r)).length / gatesRuns.length) * 100
      : null;

  // --- 0.20 term: openViolations on the LATEST run (hard 0 when any open) ---
  const openViolations = computeOpenViolations(runSet);

  // --- data threshold: ≥1 run with compliance.json ---
  if (complianceRuns.length === 0) {
    warnings.push('bez dat — no run has a compliance.json');
    return {
      value: null,
      partial: true,
      confidence: 'low',
      compliancePassRate: null,
      openViolations,
      lastGateOverall: lastGateOverall(runSet),
      warnings,
    };
  }

  // --- weighted blend, dropping a term whose denominator is empty (re-normalize) ---
  interface BlendTerm {
    name: string;
    weight: number;
    value: number | null; // 0–100; null when this term's denominator is empty
  }
  const blendTerms: BlendTerm[] = [
    { name: 'compliance', weight: 0.5, value: compliancePassRate },
    { name: 'gate_final_pass', weight: 0.3, value: gateFinalPassRate },
    { name: 'open_violations', weight: 0.2, value: openViolations === 0 ? 100 : 0 },
  ];
  let partial = false;
  if (compliancePassRate === null) {
    warnings.push('compliance term dropped — zero non-null checks');
    partial = true;
  }
  if (gateFinalPassRate === null) {
    warnings.push('gate_final_pass term dropped — no run has a gates_report');
    partial = true;
  }

  const survivors = blendTerms.filter((t) => t.value !== null);
  const survivingWeight = survivors.reduce((s, t) => s + t.weight, 0);
  let value: number | null = null;
  if (survivingWeight > 0) {
    const blended = survivors.reduce((s, t) => s + (t.weight / survivingWeight) * (t.value as number), 0);
    value = Math.round(blended);
  }

  const confidence: Project['health']['confidence'] = complianceRuns.length >= 3 ? 'high' : 'low';
  if (complianceRuns.length < 3) {
    warnings.push(`málo dat (n=${complianceRuns.length}) — fewer than 3 runs contribute`);
  }

  return {
    value,
    partial,
    confidence,
    compliancePassRate,
    openViolations,
    lastGateOverall: lastGateOverall(runSet),
    warnings,
  };
}

// ===========================================================================
// Internal helpers (pure)
// ===========================================================================

/** force_override_count for one run: prefer compliance scalar, else timeline events. */
function forceOverridesFor(run: RunDetail): number {
  if (run.compliance !== null) return run.compliance.forceOverrideCount;
  return run.timeline.filter((e) => e.event === 'fsm_force_override').length;
}

/**
 * Gates passed on the FIRST attempt (§5.7 gate_first_pass): every non-skipped
 * gate has `attempts <= 1` AND `result === 'pass'`. A run with only skipped gates
 * (e.g. plan_diff exit 2) counts as a first-pass (nothing failed).
 */
function gatesFirstPass(run: RunDetail): boolean {
  const realGates = run.gates.filter((g) => g.result !== 'skipped');
  if (realGates.length === 0) return true;
  return realGates.every((g) => g.result === 'pass' && g.attempts <= 1);
}

/** Gates GREEN in the end (§5.7 gate_final_pass): no non-skipped gate fails. */
function gatesFinalPass(run: RunDetail): boolean {
  const realGates = run.gates.filter((g) => g.result !== 'skipped');
  if (realGates.length === 0) return true;
  return realGates.every((g) => g.result === 'pass');
}

/** The latest run's overall gate verdict for the Project.health tile. */
function lastGateOverall(runSet: RunDetail[]): 'pass' | 'fail' | null {
  const latest = latestRun(runSet);
  if (latest === null) return null;
  const realGates = latest.gates.filter((g) => g.result !== 'skipped');
  if (realGates.length === 0) return null;
  return realGates.every((g) => g.result === 'pass') ? 'pass' : 'fail';
}

/**
 * §5.7 openViolations: count the LATEST run's `ComplianceFailure[]` with
 * `severity === 'blocking'` still UNRESOLVED. A blocking failure (matched by its
 * `.check`) is cleared when a LATER run of the SAME EPIC has no ComplianceFailure
 * with that same `.check` value (resolution = a newer run's structured failures[],
 * never an in-place edit). Returns a non-null `number` (0 when none).
 */
function computeOpenViolations(runSet: RunDetail[]): number {
  // Group by epicId; within each EPIC order runs chronologically (oldest→newest).
  const byEpic = new Map<string, RunDetail[]>();
  for (const r of runSet) {
    const list = byEpic.get(r.epicId) ?? [];
    list.push(r);
    byEpic.set(r.epicId, list);
  }

  let open = 0;
  for (const runs of byEpic.values()) {
    const ordered = [...runs].sort(byChrono);
    const latest = ordered[ordered.length - 1];
    if (!latest.compliance) continue;
    const blocking = latest.compliance.failures.filter((f) => f.severity === 'blocking');
    if (blocking.length === 0) continue;
    // There IS no later run than `latest` in this EPIC, so each blocking failure
    // on the latest run is by definition unresolved (the resolution source would
    // have to be a NEWER run of the same EPIC, which does not exist).
    open += blocking.length;
  }
  return open;
}

/** A compliance check value counts as "pass" for the §5.3 pass-rate. */
function isPassCheck(v: unknown): boolean {
  if (v === true) return true;
  if (typeof v === 'string') {
    const s = v.toLowerCase();
    return s === 'pass' || s === 'passed' || s === 'ok' || s === 'true';
  }
  if (typeof v === 'object' && v !== null) {
    const o = v as Record<string, unknown>;
    if (typeof o.result === 'string') return isPassCheck(o.result);
    if (typeof o.status === 'string') return isPassCheck(o.status);
    if (typeof o.pass === 'boolean') return o.pass;
  }
  return false;
}

/** Latest run across a set (chronological by startedAt, then runId). */
function latestRun(runSet: RunDetail[]): RunDetail | null {
  if (runSet.length === 0) return null;
  return [...runSet].sort(byChrono)[runSet.length - 1];
}

/** Chronological comparator: startedAt asc (nulls first), then runId. */
function byChrono(a: RunDetail, b: RunDetail): number {
  const sa = a.startedAt ?? '';
  const sb = b.startedAt ?? '';
  if (sa !== sb) return sa.localeCompare(sb);
  return a.runId.localeCompare(b.runId);
}

/** Latest parseable timeline `ts` (ms) matching `pred`; null when none. */
function lastTs(timeline: ActivityEvent[], pred: (e: ActivityEvent) => boolean): number | null {
  let max: number | null = null;
  for (const e of timeline) {
    if (!pred(e)) continue;
    const t = parseTs(e.ts);
    if (t === null) continue;
    if (max === null || t > max) max = t;
  }
  return max;
}

/** Parse an ISO-8601 ts to epoch-ms; null when unparseable. */
function parseTs(ts: string): number | null {
  if (!ts) return null;
  const n = Date.parse(ts);
  return Number.isNaN(n) ? null : n;
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}

function round0(n: number): number {
  return Math.round(n);
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
