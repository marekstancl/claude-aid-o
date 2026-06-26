/**
 * Deterministic RISK model — spec §13.2 (D2 "flag, never fake").
 *
 * `computeRisk(signals): Risk` is a PURE, TOTAL function: same input → same
 * output, no LLM, no network, no Date.now/random in the decision path, never
 * throws. The level comes from countable real signals only (S1-S8, §13.2.1);
 * a missing signal is NEVER counted as clean (§13.2.4 coverage floor — the
 * "never fake low" guarantee).
 *
 * Signal extraction from disk lives elsewhere (the brief builder, §13.4) — this
 * module decides the level/reasons/confidence from already-extracted signals.
 */

import type { Risk, RiskReason, RiskLevel } from '@aid/contract';

/**
 * Named thresholds — the single source for the rule table (§13.2.2, VERBATIM).
 * Tunable constants; the rule table below references these by name only.
 */
export const RISK = {
  STALE_DAYS: 3, // active run with no file activity ≥ 3 days → S7 fires
  STUCK_DWELL_SEC: 86400, // ≥ 24h in one FSM state on an active run → S6 (dwell)
  REPEAT_FAIL_MIN: 2, // same (from,to,reason) precondition fail ≥ 2× → S5
  INCREMENT_FAIL_MIN: 2, // same (step,reason) increment fail ≥ 2× → S6 (loop)
  GATE_FIRST_PASS_WARN: 0.6, // first-pass gate rate < 60% → střední contributor
  GATE_FIRST_PASS_BAD: 0.4, // first-pass gate rate < 40% → vysoké contributor
  FORCE_OVERRIDE_WARN: 1, // any force override → at least pozor watch-out + střední
  COVERAGE_MIN_SIGNALS: 2, // < 2 of the level-relevant signals available → level = 'neurceno'
} as const;

/**
 * S1-S8 signal inventory (§13.2.1) + per-signal availability flags. The value
 * fields hold the already-extracted countable signal; the `*Available` flags say
 * whether the source artifact existed at all (drives the coverage rule §13.2.4 —
 * a missing source is never silently "clean").
 *
 * Availability flags map to the §13.2.1 "availability source" column:
 *   complianceAvailable → a compliance.json exists (covers S1, S3)
 *   gatesAvailable      → ≥1 run has a gates_report.json (covers S4)
 *   timelineAvailable   → a non-empty per-run timeline exists (covers S5, S6)
 *   auditAvailable      → an audit-report.md exists (covers S8)
 *   fsmStateAvailable   → a parseable fsm-state.yaml exists (S2 presence — EXCLUDED from count)
 *   runDirAvailable     → the run dir + file mtimes exist (S7 — ALWAYS true for a v3 run, EXCLUDED from count)
 */
export interface RiskSignals {
  // S1 — open blocking compliance violations (unresolved, §5.7 resolution rule applied upstream)
  openBlockingViolations: number;
  // S2 — escalation: count + any run currently in ESCALATION
  escalationCount: number;
  escalationActive: boolean;
  // S3 — force overrides + systematic flag (§4.5)
  forceOverrideCount: number;
  forceOverrideSystematic: boolean;
  // S4 — gate first-pass rate over runs with a gates_report.json (null = no rate computable)
  gateFirstPassRate: number | null;
  gateRunCount: number; // runs backing the rate (≥3 needed for 'high' confidence on S4)
  // S5 — repeated precondition fails (same (from,to,reason) ≥ REPEAT_FAIL_MIN)
  repeatedPreconditionFails: boolean;
  // S6 — stuck/looping FSM (dwell ≥ STUCK_DWELL_SEC or same (step,reason) ≥ INCREMENT_FAIL_MIN)
  stuckOrLoopingFsm: boolean;
  // S7 — stale active run idle ≥ STALE_DAYS (staleDays = the actual idle days, for the reason text)
  staleRun: boolean;
  staleDays?: number;
  // S8 — auditor blocking findings on the latest run
  auditBlockingFindings: boolean;

  // Availability flags (§13.2.1 "availability source" column)
  complianceAvailable: boolean;
  gatesAvailable: boolean;
  timelineAvailable: boolean;
  auditAvailable: boolean;
  fsmStateAvailable: boolean; // S2 presence — NOT counted toward coverage
  runDirAvailable: boolean; // S7 — NOT counted toward coverage
}

// StatusKey tokens (§6.2) used by the reasons below — typed via RiskReason.status.
const FAIL = 'selhalo' as const; // T1 — vysoké rows
const WARN = 'pozor' as const; // T2 — střední rows + neurceno
const PASS = 'proslo' as const; // T3 — nízké clean row

/**
 * The §13.2.4 coverage set: the level-relevant signals whose availability counts
 * toward COVERAGE_MIN_SIGNALS. Each entry maps a signal id to the availability
 * flag that backs it. S7 (staleRun) and S2's fsm-state presence are DELIBERATELY
 * EXCLUDED — they are always available for any v3 run, so counting them would let
 * a thin run trivially reach ≥2 and falsely earn 'nizke'.
 */
function coverageCount(s: RiskSignals): number {
  let n = 0;
  if (s.complianceAvailable) n += 1; // S1, S3 source
  if (s.gatesAvailable) n += 1; // S4 source
  if (s.timelineAvailable) n += 1; // S5, S6 source
  if (s.auditAvailable) n += 1; // S8 source
  return n;
}

/**
 * The floor (§13.2.4) — the PRIMARY "never fake low" guarantee. `nizke` requires
 * that at least the compliance source (S1/S3) OR the gates source (S4) was
 * actually present AND clean. A run we know nothing about cannot earn a green
 * badge even if the count were somehow satisfied. Floor wins on conflict.
 */
function cleanFloorMet(s: RiskSignals): boolean {
  const complianceClean = s.complianceAvailable && s.openBlockingViolations === 0;
  const gatesClean =
    s.gatesAvailable && s.gateFirstPassRate !== null && s.gateFirstPassRate >= RISK.GATE_FIRST_PASS_WARN;
  return complianceClean || gatesClean;
}

/**
 * Compute the deterministic Risk for a scope's signal set (§13.2.3 rule table).
 *
 * Order of operations:
 *   1. Accumulate ALL firing reasons (union — reasons accumulate across tiers).
 *   2. The first matching tier (top→bottom precedence) sets the LEVEL and the
 *      level-setting signal decides CONFIDENCE (per-signal class, SF3).
 *   3. If no tier fired AND coverage is satisfied AND the clean floor is met →
 *      'nizke'. Otherwise → 'neurceno' (coverage floor, never a fake green).
 *
 * Confidence is annotation-only: a 'low' confidence NEVER moves the level
 * (§13.2.4). The level-setting signal's class determines confidence.
 */
export function computeRisk(s: RiskSignals): Risk {
  const reasons: RiskReason[] = [];

  // Track the level-setting signal's confidence class. 'high' = authoritative
  // single-file / pattern-≥2 / present-state; 'low' = rate signal with <3 runs.
  let level: RiskLevel | null = null;
  let confidence: 'high' | 'low' | null = null;

  // Helper: the first firing tier sets the level + its confidence; later firing
  // signals still append their reason but do not change the level/confidence.
  const setLevel = (l: RiskLevel, c: 'high' | 'low'): void => {
    if (level === null) {
      level = l;
      confidence = c;
    }
  };

  // ── T1 — vysoké ───────────────────────────────────────────────────────────
  // S1 openBlockingViolations > 0 — authoritative single-file → high from one run.
  if (s.openBlockingViolations > 0) {
    setLevel('vysoke', 'high');
    reasons.push({
      text: 'Blokující porušení pravidel není vyřešené - release je zastavený, dokud se to nenapraví nebo PM vědomě nepřepíše.',
      status: FAIL,
      signal: 'open_blocking_violations',
      value: s.openBlockingViolations,
    });
  }
  // S8 auditBlockingFindings — authoritative single-file (audit-report.md) → high.
  if (s.auditBlockingFindings) {
    setLevel('vysoke', 'high');
    reasons.push({
      text: 'Auditor našel kritický nález - merge je zablokovaný, dokud to PM neposoudí.',
      status: FAIL,
      signal: 'audit_blocking_findings',
    });
  }
  // S3 systematic — authoritative single-file when compliance.json present → high.
  if (s.forceOverrideSystematic) {
    setLevel('vysoke', 'high');
    reasons.push({
      text: 'Kontroly se obcházejí systematicky (ne jednorázově) - proces se přestává dodržovat.',
      status: FAIL,
      signal: 'force_override_systematic',
      value: s.forceOverrideCount,
    });
  }
  // S4 gateFirstPassRate < BAD (and ≥3 runs with gates) — rate signal: high only with ≥3 runs.
  if (
    s.gatesAvailable &&
    s.gateFirstPassRate !== null &&
    s.gateRunCount >= 3 &&
    s.gateFirstPassRate < RISK.GATE_FIRST_PASS_BAD
  ) {
    // Rate signal: the ≥3-runs guard above is what makes this 'high' (SF3).
    setLevel('vysoke', 'high');
    reasons.push({
      text: 'Brány kvality padají na první pokus ve většině běhů - kód jde do kontrol nehotový.',
      status: FAIL,
      signal: 'gate_first_pass_bad',
      value: s.gateFirstPassRate,
    });
  }

  // ── T2 — střední ────────────────────────────────────────────────────────────
  // S2 escalation active — present-state fact → high when fsm-state parseable.
  if (s.escalationActive) {
    setLevel('stredni', 'high');
    reasons.push({
      text: 'Něco se zaseklo a eskalovalo - běh čeká na rozhodnutí nebo opravu člověkem.',
      status: WARN,
      signal: 'escalation_active',
      value: s.escalationCount,
    });
  }
  // S5 repeated precondition fail — pattern is ≥2 by construction → high.
  if (s.repeatedPreconditionFails) {
    setLevel('stredni', 'high');
    reasons.push({
      text: 'Stejný přechod stavového automatu opakovaně neprošel - to není náhoda, drhne tam podmínka.',
      status: WARN,
      signal: 'repeated_precondition_fail',
    });
  }
  // S6 stuck/looping FSM — pattern is ≥2 / dwell over threshold → high.
  if (s.stuckOrLoopingFsm) {
    setLevel('stredni', 'high');
    reasons.push({
      text: 'Běh se točí na jednom místě (dlouho v jednom stavu nebo opakuje stejný krok) - postup vázne.',
      status: WARN,
      signal: 'stuck_or_looping',
    });
  }
  // S3 forceOverrideCount ≥ WARN (any bypass, not yet systematic) — authoritative single-file → high.
  if (!s.forceOverrideSystematic && s.forceOverrideCount >= RISK.FORCE_OVERRIDE_WARN) {
    setLevel('stredni', 'high');
    reasons.push({
      text: 'PM ručně obešel kontrolu - jednorázově, ale stojí to za pozornost.',
      status: WARN,
      signal: 'force_override',
      value: s.forceOverrideCount,
    });
  }
  // S4 gateFirstPassRate < WARN (and ≥3 runs) — rate signal: high only with ≥3 runs.
  if (
    s.gatesAvailable &&
    s.gateFirstPassRate !== null &&
    s.gateRunCount >= 3 &&
    s.gateFirstPassRate < RISK.GATE_FIRST_PASS_WARN &&
    s.gateFirstPassRate >= RISK.GATE_FIRST_PASS_BAD
  ) {
    setLevel('stredni', 'high');
    reasons.push({
      text: 'Brány kvality často padají na první pokus - víc oprav než obvykle.',
      status: WARN,
      signal: 'gate_first_pass_warn',
      value: s.gateFirstPassRate,
    });
  }
  // S7 staleRun — present-state fact → high when the run dir exists (always for v3).
  if (s.staleRun) {
    const days = s.staleDays ?? RISK.STALE_DAYS;
    setLevel('stredni', 'high');
    reasons.push({
      text: `Rozdělaný běh se ${days} dní nehnul - buď visí, nebo se na něj zapomnělo.`,
      status: WARN,
      signal: 'stale_run',
      value: days,
    });
  }

  // ── Level resolved by a firing tier? Return it. ─────────────────────────────
  if (level !== null && confidence !== null) {
    return { level, reasons, confidence };
  }

  // ── No tier fired: T3 nízké, but ONLY if the coverage floor is satisfied. ───
  // §13.2.4 — the floor is the primary "never fake low" guarantee. Both the
  // count rule AND the clean floor must hold; the floor wins on conflict.
  const enoughCoverage = coverageCount(s) >= RISK.COVERAGE_MIN_SIGNALS;
  const floorMet = cleanFloorMet(s);

  if (enoughCoverage && floorMet) {
    // Clean run, rests on the authoritative single-file clean-compliance floor →
    // high. If the ONLY clean evidence is the gate rate (S4) with <3 runs, the
    // green is honest-but-thin → low confidence.
    const complianceClean = s.complianceAvailable && s.openBlockingViolations === 0;
    const cleanConfidence: 'high' | 'low' = complianceClean ? 'high' : s.gateRunCount >= 3 ? 'high' : 'low';
    return {
      level: 'nizke',
      reasons: [
        {
          text: 'Žádné blokující ani varovné signály - proces běží, jak má.',
          status: PASS,
          signal: 'no_adverse_signal',
        },
      ],
      confidence: cleanConfidence,
    };
  }

  // Insufficient coverage OR floor not met → neurceno. NEVER nizke by absence.
  return {
    level: 'neurceno',
    reasons: [
      {
        text: 'Zatím je málo dat na odhad rizika - chybí výsledky bran, compliance nebo timeline.',
        status: WARN,
        signal: 'insufficient_coverage',
      },
    ],
    confidence: 'low',
  };
}
