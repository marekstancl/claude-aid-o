/**
 * Managerial model (E-047-6_7 REOPEN — Cockpit productization).
 *
 * The "brain" that turns raw per-run signal FACTS into grouped, lifecycle-classified,
 * deduplicated managerial {@link BriefItem}s. Pure + deterministic + never throws —
 * same facts → same items. `build-brief.ts` detects the raw facts from RunDetail and
 * hands them here; this module owns:
 *
 *   1. SIGNAL_PLAYBOOK  — per-signal human copy (title / what happened / why it
 *      matters / what it blocks / recommended action / next actor / routing).
 *   2. groupByRootCause — collapse facts sharing a rootCauseKey into ONE item with
 *      occurrenceCount (distinct RUNS), affectedEpics[], first/last, evidenceRefs[].
 *   3. classifyLifecycle — §A3 evidence-based active / resolved / historical / stale
 *      (a newer EPIC in the same plan is NOT proof; supersession needs real evidence).
 *   4. dedupe + project — decision > blocker precedence; one problem has ONE home;
 *      blockers / decisionsNeeded / watchOuts / nextUp are projections of the one set.
 *   5. ecosystemLine — one-line Czech state summary for the landing lead.
 *
 * Binding decisions: docs/design/E-047-6-productization-addendum.md.
 */
import type { BriefItem, EvidenceRef, Explanation, FsmState, ItemLifecycle, NextActor } from '@aid/contract';
import { explain, type ExplainInput } from '../explain/index.js';

// ===========================================================================
// Raw fact — one detected signal occurrence on one run (build-brief emits these)
// ===========================================================================

export interface RawSignalFact {
  projectId: string;
  epicId?: string;
  planId?: string;
  runId?: string;
  /** Machine signal id, e.g. 'open_blocking_violation', 'merge_pending'. */
  signal: string;
  /** The SPECIFIC check / gate / reason — makes rootCauseKey concrete (NOT just the generic signal). */
  concreteKey: string;
  /** Occurrence time (ISO) for first/last + sort. */
  at: string | null;
  /** Deep-link for the primary evidence ref. */
  href: string;
  /** Extra evidence refs beyond the primary epic/plan link. */
  extraEvidence?: EvidenceRef[];
  /** Context for the explanation template + copy interpolation. */
  context?: Record<string, unknown>;

  // ── lifecycle inputs (§A3) ────────────────────────────────────────────────
  /**
   * Archive status — EVIDENCE-BASED tri-state (Marek's correction): NOT "absent
   * from the active set". `archived` requires explicit proof (tasks/archive, task
   * status, or another authoritative artifact); `active` = demonstrably active;
   * `unknown` = unprovable either way → never filed as historical.
   */
  archiveStatus: 'archived' | 'active' | 'unknown';
  /** The EPIC's latest-run FSM state (null = unknown/legacy). */
  latestRunState: FsmState | null;
  /** Active problem unchanged > 7 days (touchedAt older than the stale window). */
  stale: boolean;
  /**
   * F2 ONLY: newer authoritative evidence closed this exact root cause, per the
   * per-signal CLOSURE_RULES table (NOT a universal "a newer run passed"). F1
   * MUST leave this false — nothing is resolved without evidence.
   */
  resolvedEvidence?: boolean;
}

/**
 * F2 closure contract (binding, before DONE — Marek's correction). "A newer run
 * passed" is NEVER a universal resolver; a root cause is `resolved` only when a
 * NEWER run of the SAME EPIC (matched by the SAME rootCauseKey) satisfies the
 * signal-specific rule below. Run-history MUST come from the ONE shared source
 * (Plan Outcome Analytics / scanner) — no second parallel resolver. F1 ships
 * these as documentation; the resolver lands in F2 before DONE.
 */
export const CLOSURE_RULES: Record<string, string> = {
  open_blocking_violation: 'newer COMPLETE result of the same check with no violation',
  advisory_violation: 'newer complete result of the same check with no violation',
  audit_blocking_findings: 'newer audit without the same blocking finding',
  merge_pending: 'a recorded PM decision / merge for this EPIC',
  escalation_active: 'a subsequent successful transition out of ESCALATION',
  repeated_precondition_fail: 'a subsequent successful transition for the same precondition',
  retry_hotspot: 'a newer run whose same gate passed first-try',
  stale_run: 'any newer activity on the run (touched again)',
};

// ===========================================================================
// Per-signal playbook — the human copy + routing for every signal we surface
// ===========================================================================

interface PlaybookEntry {
  /** Human Czech name — NEVER snake_case. May reference {ctx} fields. */
  humanTitle: (ctx: Record<string, unknown>) => string;
  whatHappened: (ctx: Record<string, unknown>) => string;
  whyItMatters: string;
  /** What it blocks; null = blocks nothing. */
  whatBlocks: string | null;
  recommendedAction: string | null;
  nextActor: NextActor;
  severity: BriefItem['severity'];
  requiresDecision: boolean;
  isBlocker: boolean;
  /** Dictionary lookup for the §6.4 Explanation (shared Czech with Screen C/D). */
  explainInput: (ctx: Record<string, unknown>) => ExplainInput;
}

const cstr = (v: unknown, fallback = ''): string =>
  v === null || v === undefined ? fallback : String(v);

/**
 * Human Czech labels for compliance check ids — so a raw snake_case check name
 * (e.g. `verifier_provenance`) never surfaces as a managerial title (Marek's
 * "no raw snake_case outside the technical detail"). Unknown checks fall back to
 * a de-snaked Title Case form, still never the raw token.
 */
const CHECK_LABELS: Record<string, string> = {
  verifier_provenance: 'původ kontroly verifikátora',
  branch_correct: 'správná větev',
  plan_ac_match: 'shoda s akceptačními kritérii',
  gates_generated_by: 'původ bran',
  gates_no_generated_by: 'chybějící původ bran',
  execution_yaml_present: 'přítomnost execution.yaml',
  dod_present: 'definice hotového (DoD)',
  delivery_report_present: 'dodací report',
  simplifier_report_present: 'report zjednodušení',
  memory_substantive: 'využití paměti',
  missing_verifier_output: 'chybějící výstup verifikátora',
};
function checkLabel(check: string): string {
  if (CHECK_LABELS[check]) return CHECK_LABELS[check];
  if (!check) return 'kontrola';
  return check.replace(/_/g, ' ');
}

export const SIGNAL_PLAYBOOK: Record<string, PlaybookEntry> = {
  merge_pending: {
    humanTitle: () => 'Čeká na rozhodnutí o mergi',
    whatHappened: () =>
      'EPICa prošla všemi kontrolami a stojí ve fázi DONE bez tvého rozhodnutí o začlenění.',
    whyItMatters: 'Hotová práce se nezačlení a další EPICy v plánu na ni čekají.',
    whatBlocks: 'Začlenění výsledku a navazující EPICy plánu.',
    recommendedAction: 'Otevři EPIC, zkontroluj výsledek a rozhodni merge / fix / abort.',
    nextActor: 'pm',
    severity: 'blocking',
    requiresDecision: true,
    isBlocker: true,
    explainInput: () => ({ kind: 'concept', id: 'decision_needed' }),
  },
  escalation_active: {
    humanTitle: () => 'Eskalace čeká na zásah',
    whatHappened: () => 'Běh se zastavil v eskalaci — automat dál nepokračuje bez člověka.',
    whyItMatters: 'Vývoj té EPICy stojí, dokud eskalaci nevyřešíš.',
    whatBlocks: 'Pokračování běhu EPICy.',
    recommendedAction: 'Otevři EPIC a rozhodni: oprav, přeskoč, nebo zastav.',
    nextActor: 'pm',
    severity: 'blocking',
    requiresDecision: true,
    isBlocker: true,
    explainInput: () => ({ kind: 'state', id: 'ESCALATION' }),
  },
  audit_blocking_findings: {
    humanTitle: () => 'Auditor našel kritický nález',
    whatHappened: () => 'Auditor označil blokující nález (CP5), který brání mergi.',
    whyItMatters: 'Bez vyřešení nálezu se EPICa nesmí začlenit.',
    whatBlocks: 'Merge EPICy (CP5 gate).',
    recommendedAction: 'Projdi audit report, oprav nález nebo rozhodni o výjimce.',
    nextActor: 'pm',
    severity: 'blocking',
    requiresDecision: true,
    isBlocker: true,
    explainInput: () => ({ kind: 'role', id: 'auditor', context: { outcome: 'blocking' } }),
  },
  open_blocking_violation: {
    humanTitle: (c) => `Blokující porušení pravidla: ${checkLabel(cstr(c.concreteKey))}`,
    whatHappened: (c) =>
      `Kontrola „${checkLabel(cstr(c.concreteKey))}" skončila jako blokující porušení.`,
    whyItMatters: 'Blokující porušení brání čistému dokončení a mergi EPICy.',
    whatBlocks: 'Dokončení a merge EPICy.',
    recommendedAction: 'Oprav příčinu porušení, nebo rozhodni o auditované výjimce.',
    nextActor: 'aid',
    severity: 'blocking',
    requiresDecision: false,
    isBlocker: true,
    explainInput: () => ({ kind: 'severity', id: 'blocking' }),
  },
  repeated_precondition_fail: {
    humanTitle: () => 'Běh se zacyklil na stejné podmínce',
    whatHappened: (c) =>
      `Stejný přechod stavového automatu se opakovaně odmítá${c.reason ? ` (${checkLabel(cstr(c.reason))})` : ''}.`,
    whyItMatters: 'Běh se nehne dál — sám se z té smyčky nedostane.',
    whatBlocks: 'Postup běhu EPICy.',
    recommendedAction: 'Otevři EPIC, najdi nesplněnou podmínku a odblokuj ji.',
    nextActor: 'aid',
    severity: 'blocking',
    requiresDecision: false,
    isBlocker: true,
    explainInput: () => ({ kind: 'concept', id: 'stuck_or_looping' }),
  },
  stale_run: {
    humanTitle: (c) => `Rozdělaný běh se ${cstr(c.staleDays, 'několik')} dní nehnul`,
    whatHappened: (c) => `Aktivní běh je beze změny už ${cstr(c.staleDays, 'několik')} dní.`,
    whyItMatters: 'Nečinný rozdělaný běh nejspíš někde uvázl a potřebuje pozornost.',
    whatBlocks: null,
    recommendedAction: 'Zkontroluj, jestli běh nečeká na zásah, a posuň ho dál.',
    nextActor: 'pm',
    severity: 'warn',
    requiresDecision: false,
    isBlocker: false,
    explainInput: (c) => ({ kind: 'concept', id: 'stale_run', context: { staleDays: c.staleDays } }),
  },
  advisory_violation: {
    humanTitle: (c) => `Doporučující nález: ${checkLabel(cstr(c.concreteKey))}`,
    whatHappened: (c) =>
      `Kontrola „${checkLabel(cstr(c.concreteKey))}" hlásí doporučující (neblokující) nález.`,
    whyItMatters: 'Neblokuje merge, ale je to dluh, který je dobré uklidit.',
    whatBlocks: null,
    recommendedAction: 'Zvaž nápravu při nejbližší příležitosti.',
    nextActor: 'aid',
    severity: 'warn',
    requiresDecision: false,
    isBlocker: false,
    explainInput: () => ({ kind: 'severity', id: 'advisory' }),
  },
  force_override: {
    humanTitle: () => 'Kontrola byla ručně obejita',
    whatHappened: (c) =>
      `PM ručně obešel kontrolu${c.blocked_checks ? ` (${cstr(c.blocked_checks)})` : ''}${c.reason ? `, důvod: ${cstr(c.reason)}` : ''}.`,
    whyItMatters: 'Obejití kontroly je vědomé riziko, které má být vidět.',
    whatBlocks: null,
    recommendedAction: 'Ověř, že obejití bylo oprávněné a zdokumentované.',
    nextActor: 'pm',
    severity: 'warn',
    requiresDecision: false,
    isBlocker: false,
    explainInput: (c) => ({
      kind: 'event',
      id: 'fsm_force_override',
      context: { blocked_checks: c.blocked_checks ?? null, reason: c.reason ?? null },
    }),
  },
  retry_hotspot: {
    humanTitle: (c) => `Brána se opakovaně přehrává (${cstr(c.retries, '3+')}×)`,
    whatHappened: (c) => `Brána kvality se musela přehrávat ${cstr(c.retries, '3+')}×, než prošla.`,
    whyItMatters: 'Opakované přehrávání bran značí křehké místo, které se může zlomit.',
    whatBlocks: null,
    recommendedAction: 'Podívej se, proč brána padá, a stabilizuj ji.',
    nextActor: 'aid',
    severity: 'warn',
    requiresDecision: false,
    isBlocker: false,
    explainInput: () => ({ kind: 'concept', id: 'stuck_or_looping' }),
  },
  audit_recommended: {
    humanTitle: () => 'Auditor má doporučení',
    whatHappened: (c) =>
      `Auditor proběhl bez blokujícího nálezu, ale má ${cstr(c.count, 'několik')} doporučení.`,
    whyItMatters: 'Doporučení nezdrží merge, ale zlepší kvalitu, když je vezmeš.',
    whatBlocks: null,
    recommendedAction: 'Projdi doporučení auditora a aplikuj smysluplná.',
    nextActor: 'pm',
    severity: 'warn',
    requiresDecision: false,
    isBlocker: false,
    explainInput: (c) => ({ kind: 'role', id: 'auditor', context: { outcome: 'recommended', count: c.count } }),
  },
  queued_next: {
    humanTitle: (c) => `Ve frontě: ${cstr(c.epicId, 'další EPICa')}`,
    whatHappened: (c) => `EPICa ${cstr(c.epicId)} čeká ve frontě na spuštění.`,
    whyItMatters: 'Tohle přijde na řadu jako další.',
    whatBlocks: null,
    recommendedAction: null,
    nextActor: 'aid',
    severity: 'info',
    requiresDecision: false,
    isBlocker: false,
    explainInput: () => ({ kind: 'state', id: 'READY' }),
  },
  run_in_flight: {
    humanTitle: (c) => (c.state === 'EXECUTE' ? 'Právě se pracuje' : 'Připraveno ke spuštění'),
    whatHappened: (c) =>
      c.state === 'EXECUTE' ? 'Běh právě probíhá — kóduje se.' : 'Běh je připraven a brzy se rozjede.',
    whyItMatters: 'Tohle se teď děje nebo se hned rozjede.',
    whatBlocks: null,
    recommendedAction: null,
    nextActor: 'aid',
    severity: 'info',
    requiresDecision: false,
    isBlocker: false,
    explainInput: (c) => ({ kind: 'state', id: (c.state as string) ?? 'READY' }),
  },
  plan_progress: {
    humanTitle: () => 'Postup plánu',
    whatHappened: (c) => `Plán je hotový z ${cstr(c.progressPct, '?')} %.`,
    whyItMatters: 'Přehled, jak daleko plán je.',
    whatBlocks: null,
    recommendedAction: null,
    nextActor: 'aid',
    severity: 'info',
    requiresDecision: false,
    isBlocker: false,
    explainInput: () => ({ kind: 'state', id: 'EXECUTE' }),
  },
};

/** Fallback for an unmapped signal — never leaks a placeholder; flagged for growth. */
function fallbackEntry(signal: string): PlaybookEntry {
  return {
    humanTitle: () => 'Neznámý signál',
    whatHappened: () => `Zaznamenán signál „${signal}", pro který zatím není lidský popis.`,
    whyItMatters: 'Zatím bez interpretace — detail je v technickém zobrazení.',
    whatBlocks: null,
    recommendedAction: null,
    nextActor: 'none',
    severity: 'info',
    requiresDecision: false,
    isBlocker: false,
    explainInput: () => ({ kind: 'concept', id: signal }),
  };
}

// ===========================================================================
// Grouping by root cause → one BriefItem per (project, signal, concreteKey)
// ===========================================================================

const STALE_DAYS = 7;
export const STALE_WINDOW_MS = STALE_DAYS * 86_400_000;

function rootCauseKeyOf(f: RawSignalFact): string {
  return `${f.projectId}:${f.signal}:${f.concreteKey}`;
}

function isoMax(a: string | null, b: string | null): string | null {
  if (!a) return b;
  if (!b) return a;
  return a >= b ? a : b;
}
function isoMin(a: string | null, b: string | null): string | null {
  if (!a) return b;
  if (!b) return a;
  return a <= b ? a : b;
}

/**
 * §A3 lifecycle for a group of facts sharing one root cause:
 *  - resolved   — newer authoritative evidence closed it (resolvedEvidence on the newest fact).
 *  - active     — newest authoritative evidence still needs action (a live EPIC, or a decision pending).
 *  - stale      — active but unchanged > 7d (stays current, raised attention).
 *  - historical — every occurrence is on an archived/closed EPIC with no open action.
 * `inconsistencyFlags` carries `archived_unclosed_evidence` when an archived EPIC's
 * last run still shows a failure-class signal (it must NOT pose as a current blocker).
 */
function classifyGroupLifecycle(
  facts: RawSignalFact[],
  isBlocker: boolean,
  requiresDecision: boolean,
): { lifecycle: ItemLifecycle; inconsistencyFlags: string[] } {
  const flags: string[] = [];
  // Newest fact by `at` is the authoritative evidence.
  const newest = facts.reduce((acc, f) => (isoMax(acc.at, f.at) === f.at ? f : acc), facts[0]);
  const failureClass = isBlocker || requiresDecision;

  // resolved — F2 only, per-signal CLOSURE_RULES; F1 never sets resolvedEvidence.
  if (newest.resolvedEvidence) return { lifecycle: 'resolved', inconsistencyFlags: flags };

  // active — at least one occurrence is on a demonstrably-active EPIC.
  if (facts.some((f) => f.archiveStatus === 'active')) {
    const allStale = facts.every((f) => f.stale);
    return { lifecycle: allStale ? 'stale' : 'active', inconsistencyFlags: flags };
  }

  // historical — EVERY occurrence is on an EPIC archived WITH EVIDENCE.
  if (facts.every((f) => f.archiveStatus === 'archived')) {
    if (failureClass) flags.push('archived_unclosed_evidence');
    return { lifecycle: 'historical', inconsistencyFlags: flags };
  }

  // unknown — archive unprovable AND not demonstrably active. NEVER silently
  // historical, NEVER a confident current blocker. Surfaced flagged for triage.
  flags.push('archive_status_unknown');
  return { lifecycle: 'unknown', inconsistencyFlags: flags };
}

function evidenceRefsFor(facts: RawSignalFact[]): EvidenceRef[] {
  const refs: EvidenceRef[] = [];
  const seen = new Set<string>();
  for (const f of facts) {
    const key = f.href;
    if (seen.has(key)) continue;
    seen.add(key);
    refs.push({
      label: f.epicId ? `EPIC ${f.epicId}` : f.planId ? `Plán ${f.planId}` : f.projectId,
      href: f.href,
      kind: f.epicId ? 'epic' : f.planId ? 'plan' : 'run',
    });
    for (const e of f.extraEvidence ?? []) {
      if (!seen.has(e.href)) {
        seen.add(e.href);
        refs.push(e);
      }
    }
  }
  return refs.slice(0, 8);
}

/** Group raw facts into enriched, lifecycle-classified BriefItems (one per root cause). */
export function buildManagerialItems(facts: RawSignalFact[]): BriefItem[] {
  const groups = new Map<string, RawSignalFact[]>();
  for (const f of facts) {
    const k = rootCauseKeyOf(f);
    const arr = groups.get(k);
    if (arr) arr.push(f);
    else groups.set(k, [f]);
  }

  const items: BriefItem[] = [];
  for (const [rootCauseKey, group] of groups) {
    const pb = SIGNAL_PLAYBOOK[group[0].signal] ?? fallbackEntry(group[0].signal);
    // Merge context from the newest fact (best label/value provenance).
    const newest = group.reduce((acc, f) => (isoMax(acc.at, f.at) === f.at ? f : acc), group[0]);
    const ctx: Record<string, unknown> = {
      ...(newest.context ?? {}),
      concreteKey: group[0].concreteKey,
      epicId: newest.epicId,
    };

    const affectedEpics = [...new Set(group.map((f) => f.epicId).filter((e): e is string => !!e))];
    const occurrenceCount = new Set(group.map((f) => f.runId ?? `${f.epicId}/${f.at}`)).size;
    const firstSeen = group.reduce<string | null>((acc, f) => isoMin(acc, f.at), group[0].at);
    const lastSeen = group.reduce<string | null>((acc, f) => isoMax(acc, f.at), group[0].at);

    const { lifecycle, inconsistencyFlags } = classifyGroupLifecycle(
      group,
      pb.isBlocker,
      pb.requiresDecision,
    );

    const explanation: Explanation = explain(pb.explainInput(ctx));

    items.push({
      id: rootCauseKey,
      projectId: group[0].projectId,
      epicId: affectedEpics.length === 1 ? affectedEpics[0] : newest.epicId,
      planId: newest.planId,
      runId: newest.runId,
      humanTitle: pb.humanTitle(ctx),
      explanation,
      whatHappened: pb.whatHappened(ctx),
      whyItMatters: pb.whyItMatters,
      whatBlocks: pb.whatBlocks,
      recommendedAction: pb.recommendedAction,
      nextActor: pb.nextActor,
      severity: pb.severity,
      signal: group[0].signal,
      rootCauseKey,
      lifecycle,
      occurrenceCount,
      affectedEpics,
      firstSeen,
      lastSeen,
      requiresDecision: pb.requiresDecision,
      isBlocker: pb.isBlocker,
      relatedIds: [],
      evidenceRefs: evidenceRefsFor(group),
      inconsistencyFlags,
    });
  }

  // Link related items across the SAME EPIC (explicit relation, no silent dup).
  linkRelated(items);
  return items;
}

/** Cross-link items that touch the same EPIC so views can reference, never duplicate. */
function linkRelated(items: BriefItem[]): void {
  const byEpic = new Map<string, BriefItem[]>();
  for (const it of items) {
    for (const e of it.affectedEpics) {
      const arr = byEpic.get(e);
      if (arr) arr.push(it);
      else byEpic.set(e, [it]);
    }
  }
  for (const group of byEpic.values()) {
    if (group.length < 2) continue;
    for (const it of group) {
      it.relatedIds = [...new Set([...it.relatedIds, ...group.filter((o) => o.id !== it.id).map((o) => o.id)])];
    }
  }
}

// ===========================================================================
// Projection — one home per problem (decision > blocker precedence)
// ===========================================================================

const SEVERITY_WEIGHT: Record<BriefItem['severity'], number> = { blocking: 0, warn: 1, info: 2 };
const LIFECYCLE_WEIGHT: Record<ItemLifecycle, number> = {
  active: 0,
  stale: 1,
  unknown: 2,
  resolved: 3,
  historical: 4,
};

function sortItems(items: BriefItem[]): BriefItem[] {
  return [...items].sort((a, b) => {
    const lc = LIFECYCLE_WEIGHT[a.lifecycle] - LIFECYCLE_WEIGHT[b.lifecycle];
    if (lc !== 0) return lc;
    const sw = SEVERITY_WEIGHT[a.severity] - SEVERITY_WEIGHT[b.severity];
    if (sw !== 0) return sw;
    return (b.lastSeen ?? '') < (a.lastSeen ?? '') ? -1 : 1;
  });
}

export interface ManagerialProjection {
  blockers: BriefItem[];
  decisionsNeeded: BriefItem[];
  watchOuts: BriefItem[];
  nextUp: BriefItem[];
  /** §A3 `unknown` lifecycle — archive unprovable, not demonstrably active. Surfaced for triage, never as a confident current blocker. */
  needsTriage: BriefItem[];
}

/**
 * Project the one deduplicated item set into the managerial views, with the §C
 * invariant: a problem appears in EXACTLY ONE of blockers/decisionsNeeded
 * (decision > blocker precedence). `historical`/`resolved` are EXCLUDED from
 * every current view (they live in history/technical surfaces). `stale` stays
 * (active, raised attention). `unknown` goes to its own `needsTriage` bucket —
 * never silently dropped, never posed as a confident current blocker.
 */
export function projectViews(items: BriefItem[]): ManagerialProjection {
  const current = items.filter((i) => i.lifecycle === 'active' || i.lifecycle === 'stale');

  const decisionsNeeded = sortItems(current.filter((i) => i.requiresDecision));
  // decision > blocker precedence: a decision item is NOT also listed as a blocker.
  const blockers = sortItems(current.filter((i) => i.isBlocker && !i.requiresDecision));
  const watchOuts = sortItems(
    current.filter((i) => !i.isBlocker && !i.requiresDecision && i.severity === 'warn'),
  );
  const nextUp = sortItems(current.filter((i) => i.severity === 'info'));
  const needsTriage = sortItems(items.filter((i) => i.lifecycle === 'unknown'));

  return { blockers, decisionsNeeded, watchOuts, nextUp, needsTriage };
}

// ===========================================================================
// Ecosystem one-liner (landing lead)
// ===========================================================================

function plural(n: number, one: string, few: string, many: string): string {
  if (n === 1) return one;
  if (n >= 2 && n <= 4) return few;
  return many;
}

/**
 * One-line Czech state summary for the landing lead. Counts only CURRENT
 * (active+stale) items; never invents a green when there is simply no data.
 */
export function buildEcosystemLine(
  proj: ManagerialProjection,
  projectCount: number,
  riskLevel: string,
): string {
  const d = proj.decisionsNeeded.length;
  const b = proj.blockers.length;
  const parts: string[] = [];
  parts.push(`${projectCount} ${plural(projectCount, 'projekt', 'projekty', 'projektů')}`);
  if (d > 0) parts.push(`${d} ${plural(d, 'rozhodnutí čeká', 'rozhodnutí čekají', 'rozhodnutí čeká')}`);
  if (b > 0) parts.push(`${b} ${plural(b, 'blokace', 'blokace', 'blokací')}`);
  if (d === 0 && b === 0) parts.push('nic nečeká na tvé rozhodnutí');
  const riskWord =
    riskLevel === 'vysoke'
      ? 'riziko vysoké'
      : riskLevel === 'stredni'
        ? 'riziko střední'
        : riskLevel === 'nizke'
          ? 'riziko nízké'
          : 'riziko zatím neurčené';
  parts.push(riskWord);
  return parts.join(' · ');
}
