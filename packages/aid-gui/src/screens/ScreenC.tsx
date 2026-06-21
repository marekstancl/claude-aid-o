import { useMemo, useState } from 'react';
import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { Link, useParams } from 'react-router-dom';
import { Tabs } from '@base-ui/react/tabs';
import { Dialog } from '@base-ui/react/dialog';
import { X } from 'lucide-react';
import type {
  ActivityEvent,
  Checkpoint,
  CheckpointId,
  ComplianceFailure,
  EpicDetail,
  FsmState,
  GateResult,
  MetricSet,
  RunDetail,
  StatusKey,
  Verdict,
} from '@aid/contract';
import { getEpic, getExplanations, ApiError } from '../lib/api';
import { explainEvent, type Dictionary } from '../lib/explain';
import { FSM_STATUS, FSM_WORD } from '../lib/fsmStatus';
import { cn } from '../lib/utils';
import { useAidSocket } from '../hooks/useAidSocket';
import { MobileBackHeader } from '../components/shell/MobileBackHeader';
import { ProjectNotFound } from '../components/shell/ProjectNotFound';
import { useProjects } from '../components/shell/ProjectsContext';
import { FsmTimeline, type TimelineNode } from '../components/FsmTimeline';
import { CheckpointStrip } from '../components/CheckpointStrip';
import { AgentRolePanel, type AgentRole } from '../components/AgentRolePanel';
import { AuditSummaryCard } from '../components/managerial/AuditSummaryCard';
import { AuditTrendChart } from '../components/charts/AuditTrendChart';
import { RawMarkdownDialog } from '../components/managerial/RawMarkdownDialog';
import { Card } from '../components/managerial/Card';
import { StatusDot } from '../components/common/StatusDot';
import { StatusBadge } from '../components/common/StatusBadge';
import { MetricBadge } from '../components/common/MetricBadge';
import { DurationBar } from '../components/common/DurationBar';
import { EventRow } from '../components/common/EventRow';

/**
 * Screen C — the rich EPIC deep view (§9) at `/p/:project/e/:epic`.
 *
 * Replaces the Phase-5 STUB while KEEPING its {@link ProjectNotFound} guard. A
 * single `['epic-detail', project, epic]` query feeds {@link getEpic}; the live
 * socket (subscribed below + the app-shell global socket) plus a 4s refetch keep
 * the run fresh. Everything renders from the SHARED §6/§8 primitives — no new
 * vocabulary — and every artifact carries a Czech explanation line.
 *
 * The honesty contract from §5.7/§13 is enforced throughout:
 *  - legacy/stub run OR `latest === null` → header + ONE "starší formát / bez
 *    detailu" panel; the FSM / CP / role / timing / gate / compliance panels are
 *    SUPPRESSED (never rendered with fabricated data).
 *  - a CP whose `repeatCount` is unknown → "?" (never 0), and a `>=3` hot-spot is
 *    flagged ONLY when `repeatSource !== null` (a known, sourced repeat).
 *  - `compliance === null` → "N/A" + warning, NEVER 0%/fail.
 *  - per-step durations of `null` → "neměřeno" (hatched bar), never "0 m".
 *  - the raw-`.md` drawer fetches via the RUN-SCOPED /file endpoint and degrades
 *    to "Soubor nelze zobrazit" inside the drawer (never a crash).
 */
export function ScreenC() {
  const { project = '', epic = '' } = useParams();
  const { projects, loaded, error } = useProjects();
  const known = projects.some((p) => p.id === project);

  // KEEP the Phase-5 guard (distinguish a list-fetch outage from a genuine miss).
  if (loaded && error) return <ProjectNotFound projectId={project} loadError />;
  if (loaded && !known) return <ProjectNotFound projectId={project} />;

  return <EpicDeepView project={project} epic={epic} />;
}

function EpicDeepView({ project, epic }: { project: string; epic: string }) {
  // Live freshness for this run. The app shell already subscribes to ALL topics
  // across ALL projects; this scoped subscription is belt-and-suspenders and the
  // 4s refetchInterval below is the deterministic floor (the hook invalidates on
  // gates/compliance/checkpoints/pipeline events).
  useAidSocket({ topics: [], projects: [project] });

  const detailQuery = useQuery({
    queryKey: ['epic-detail', project, epic],
    queryFn: () => getEpic(project, epic),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });

  // The §6.4 dictionary — small + stable; shared across screens via this key.
  const explanationsQuery = useQuery({
    queryKey: ['explanations'],
    queryFn: () => getExplanations('cs'),
    staleTime: 5 * 60_000,
  });
  const dictionary: Dictionary = explanationsQuery.data ?? {};

  const detail = detailQuery.data;

  // getEpic failure (not a 404) → calm retry; a 404 → back link.
  if (!detail) {
    if (detailQuery.isError) {
      const err = detailQuery.error;
      const notFound = err instanceof ApiError && err.code === 'NOT_FOUND';
      return (
        <section className="space-y-4 p-4 sm:p-6" aria-label={`EPIC ${epic}`}>
          <MobileBackHeader title={`EPIC ${epic}`} />
          {notFound ? (
            <div data-epic-not-found className="rounded-lg border border-slate-200 bg-white p-4">
              <p className="text-sm text-slate-600">EPIC „{epic}" v projektu nenalezen.</p>
              <Link
                to={`/p/${project}`}
                className="mt-2 inline-block rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-50"
              >
                Zpět na projekt
              </Link>
            </div>
          ) : (
            <div
              data-epic-error
              className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700"
            >
              EPIC {epic} se nepodařilo načíst — zkouším znovu.
            </div>
          )}
        </section>
      );
    }
    return (
      <section className="space-y-4 p-4 sm:p-6" aria-label={`EPIC ${epic}`}>
        <MobileBackHeader title={`EPIC ${epic}`} />
        <p data-epic-loading className="text-sm text-slate-400">
          Načítám EPIC…
        </p>
      </section>
    );
  }

  const latest = detail.latest;
  // A run is "rich" only when it is a fully-parsed v3 run with a detail payload.
  // legacy / stub / latest===null degrade to the single fallback panel.
  const degraded = latest === null || latest.format !== 'v3';

  return (
    <section className="space-y-4 p-4 sm:p-6" aria-label={`EPIC ${epic}`}>
      <MobileBackHeader title={detail.title || `EPIC ${epic}`} />
      <HeaderBand detail={detail} />

      {degraded ? (
        <LegacyFallbackPanel detail={detail} />
      ) : (
        <RichRunView
          project={project}
          epic={epic}
          detail={detail}
          latest={latest as RunDetail}
          dictionary={dictionary}
        />
      )}
    </section>
  );
}

// ---------------------------------------------------------------------------
// Header band — id · run · FSM state · progress · mode · branch · human line
// ---------------------------------------------------------------------------

function HeaderBand({ detail }: { detail: EpicDetail }) {
  const latest = detail.latest;
  const state: FsmState | null = latest?.state ?? null;
  const status = state ? FSM_STATUS[state] : 'necinne';
  const word = state ? FSM_WORD[state] : 'klid';
  const pct =
    latest && latest.totalSteps > 0
      ? Math.round((latest.currentStep / latest.totalSteps) * 100)
      : null;

  return (
    <div data-header-band className="space-y-1">
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-slate-600">
        <StatusDot status={status} title={word} />
        <span className="font-semibold tabular-nums text-slate-900">{detail.id}</span>
        <span aria-hidden>·</span>
        <span data-header-run className="tabular-nums">
          běh {latest?.runId ?? '—'}
        </span>
        <span aria-hidden>·</span>
        <span data-header-state>{word}</span>
        <span aria-hidden>·</span>
        <span>
          krok{' '}
          <MetricBadge value={latest ? latest.currentStep : null} nullLabel="?" />/
          <MetricBadge value={latest ? latest.totalSteps : null} nullLabel="?" />
          {' · '}
          <MetricBadge value={pct} unit=" %" nullLabel="?" /> hotovo
        </span>
        <span aria-hidden>·</span>
        <span data-header-mode>režim {latest?.mode ?? '—'}</span>
        <span aria-hidden>·</span>
        <span data-header-branch className="truncate">
          větev {latest?.branch ?? '—'}
        </span>
      </div>
      <p data-header-human className="text-sm text-slate-500">
        {humanLine(detail)}
      </p>
    </div>
  );
}

/** A short Czech "lidská řeč" sentence describing where the EPIC stands. */
function humanLine(detail: EpicDetail): string {
  const latest = detail.latest;
  if (!latest) return 'Tento EPIC zatím nemá žádný zaznamenaný běh.';
  if (latest.format === 'stub') return 'Běh je teprve založený — detaily ještě nevznikly.';
  if (latest.format === 'legacy') return 'Běh je ve starším formátu — bohatý detail není k dispozici.';
  switch (latest.state) {
    case 'EXECUTE':
      return 'Agenti právě pracují na krocích EPICu.';
    case 'GATES':
      return 'Běh prošel kroky a teď se ověřují kontroly kvality.';
    case 'ESCALATION':
      return 'Běh narazil na problém a čeká na zásah člověka.';
    case 'DONE':
      return latest.pmDecision
        ? `Běh je hotový, rozhodnutí PM: ${latest.pmDecision}.`
        : 'Běh je hotový a čeká na rozhodnutí PM.';
    case 'ERROR':
      return 'Běh skončil chybou.';
    default:
      return 'Běh je připravený ke spuštění.';
  }
}

// ---------------------------------------------------------------------------
// Legacy / stub fallback — header stays, everything else is suppressed
// ---------------------------------------------------------------------------

function LegacyFallbackPanel({ detail }: { detail: EpicDetail }) {
  const fmt = detail.latest?.format ?? null;
  const reason =
    fmt === 'stub'
      ? 'Běh je teprve založený, detailní artefakty ještě nevznikly.'
      : fmt === 'legacy'
        ? 'Běh pochází ze staršího formátu bez strukturovaných artefaktů.'
        : 'Pro tento EPIC zatím není žádný běh s detailem.';
  return (
    <div
      data-legacy-fallback
      className="rounded-lg border border-slate-200 bg-white p-4"
    >
      <p className="text-sm font-medium text-slate-700">starší formát / bez detailu</p>
      <p className="mt-1 text-sm text-slate-500">{reason}</p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Rich v3 run view — section tabs (FSM · CP · Role · Audit · Časy · Dění)
// ---------------------------------------------------------------------------

function RichRunView({
  project,
  epic,
  detail,
  latest,
  dictionary,
}: {
  project: string;
  epic: string;
  detail: EpicDetail;
  latest: RunDetail;
  dictionary: Dictionary;
}) {
  return (
    <Tabs.Root defaultValue="fsm">
      <Tabs.List
        data-screen-c-tabs
        className="flex gap-1 overflow-x-auto whitespace-nowrap border-b border-slate-200"
      >
        <TabButton value="fsm">FSM</TabButton>
        <TabButton value="cp">CP</TabButton>
        <TabButton value="role">Role</TabButton>
        <TabButton value="audit">Audit</TabButton>
        <TabButton value="time">Časy</TabButton>
        <TabButton value="events">Dění</TabButton>
      </Tabs.List>

      <Tabs.Panel value="fsm" className="pt-4">
        <FsmSection latest={latest} dictionary={dictionary} />
      </Tabs.Panel>
      <Tabs.Panel value="cp" className="pt-4">
        <CheckpointSection
          project={project}
          epic={epic}
          latest={latest}
          dictionary={dictionary}
        />
      </Tabs.Panel>
      <Tabs.Panel value="role" className="pt-4">
        <RolesSection latest={latest} dictionary={dictionary} />
      </Tabs.Panel>
      <Tabs.Panel value="audit" className="pt-4">
        <AuditSection project={project} epic={epic} detail={detail} latest={latest} />
      </Tabs.Panel>
      <Tabs.Panel value="time" className="pt-4">
        <TimingSection metrics={detail.metrics} latest={latest} />
      </Tabs.Panel>
      <Tabs.Panel value="events" className="pt-4">
        <EventsSection
          project={project}
          epic={epic}
          latest={latest}
          dictionary={dictionary}
        />
      </Tabs.Panel>
    </Tabs.Root>
  );
}

function TabButton({ value, children }: { value: string; children: React.ReactNode }) {
  return (
    <Tabs.Tab
      value={value}
      className="min-h-[40px] shrink-0 border-b-2 border-transparent px-3 text-sm font-medium text-slate-500 data-[active]:border-slate-900 data-[active]:text-slate-900"
    >
      {children}
    </Tabs.Tab>
  );
}

// ---------------------------------------------------------------------------
// FSM section — current state + the fsm_transition walk + explanation lines
// ---------------------------------------------------------------------------

function FsmSection({ latest, dictionary }: { latest: RunDetail; dictionary: Dictionary }) {
  const nodes = useMemo(() => fsmNodes(latest, dictionary), [latest, dictionary]);
  const state = latest.state;
  return (
    <Card title="Stav a přechody (FSM)">
      <div className="space-y-3">
        <p data-fsm-current className="flex items-center gap-2 text-sm text-slate-600">
          <StatusBadge status={FSM_STATUS[state]} label={FSM_WORD[state]} />
          <span>
            krok <MetricBadge value={latest.currentStep} />/<MetricBadge value={latest.totalSteps} />
          </span>
        </p>
        <FsmTimeline nodes={nodes} emptyLabel="zatím žádné přechody" />
      </div>
    </Card>
  );
}

/**
 * Build the FSM state-walk from the run's `fsm_transition` timeline events.
 * Each node carries the §6.4 explanation resolved via {@link explainEvent}, so
 * every node has a Czech line. The CURRENT state node is emphasised.
 */
function fsmNodes(latest: RunDetail, dictionary: Dictionary): TimelineNode[] {
  const transitions = latest.timeline.filter((e) => e.event === 'fsm_transition');
  const nodes: TimelineNode[] = [];
  const seen = new Set<string>();

  for (const ev of transitions) {
    const to = ev.to;
    if (!to) continue;
    const key = `${to}:${ev.ts}`;
    if (seen.has(key)) continue;
    seen.add(key);
    nodes.push({
      key,
      label: to,
      status: FSM_STATUS[to] ?? 'necinne',
      explanation: explainEvent(ev, dictionary),
      at: ev.ts || null,
      current: to === latest.state,
    });
  }

  // No transition events recorded but the run has a state → at least show it.
  if (nodes.length === 0) {
    const synthetic: ActivityEvent = {
      projectId: latest.projectId,
      epicId: latest.epicId,
      runId: latest.runId,
      ts: latest.startedAt ?? '',
      event: 'fsm_transition',
      to: latest.state,
      raw: {},
    };
    nodes.push({
      key: `current:${latest.state}`,
      label: latest.state,
      status: FSM_STATUS[latest.state] ?? 'necinne',
      explanation: explainEvent(synthetic, dictionary),
      at: latest.startedAt,
      current: true,
    });
  }

  return nodes;
}

// ---------------------------------------------------------------------------
// Checkpoint section — CP1-CP5 strip + per-CP drawer (CP6 = Fast-Mode-only)
// ---------------------------------------------------------------------------

const NORMAL_CPS: CheckpointId[] = ['CP1', 'CP2', 'CP3', 'CP4', 'CP5'];

function CheckpointSection({
  project,
  epic,
  latest,
  dictionary,
}: {
  project: string;
  epic: string;
  latest: RunDetail;
  dictionary: Dictionary;
}) {
  // CP1-CP5 are the normal-run checkpoints; CP6 is Fast-Mode-only ("/aid-do").
  const normal = latest.checkpoints.filter((cp) => NORMAL_CPS.includes(cp.id));
  const cp6 = latest.checkpoints.find((cp) => cp.id === 'CP6') ?? null;

  return (
    <Card title="Kontrolní body (CP1-CP5)">
      <div className="space-y-3">
        <CheckpointStrip checkpoints={normal} />
        <p className="text-sm text-slate-500">
          Kontrolní body ověřují kvalitu v klíčových fázích běhu. Klikni na bod pro verdikt a stopu.
        </p>

        <ul className="space-y-2" data-cp-list>
          {normal.map((cp) => (
            <li key={cp.id}>
              <CheckpointRow
                project={project}
                epic={epic}
                runId={latest.runId}
                cp={cp}
                dictionary={dictionary}
              />
            </li>
          ))}
        </ul>

        {/* CP6 is only meaningful on a Fast-Mode (/aid-do) run; greyed otherwise. */}
        <p data-cp6-note className="text-xs text-slate-400">
          {cp6
            ? `CP6: ${cp6.label || 'Fast Mode'}`
            : 'CP6: jen Fast Mode (/aid-do)'}
        </p>
      </div>
    </Card>
  );
}

/** Czech §6.2 token for a checkpoint verdict (mirrors CheckpointStrip). */
function verdictStatus(verdict: Verdict): StatusKey {
  switch (verdict) {
    case 'pass':
      return 'proslo';
    case 'fail':
      return 'selhalo';
    case 'unverifiable':
      return 'pozor';
    case 'skipped':
      return 'ceka';
    default:
      return 'necinne';
  }
}

function verdictWord(verdict: Verdict): string {
  if (verdict == null) return 'nezaznamenáno';
  return { pass: 'prošlo', fail: 'selhalo', unverifiable: 'nelze ověřit', skipped: 'přeskočeno' }[verdict];
}

function CheckpointRow({
  project,
  epic,
  runId,
  cp,
  dictionary,
}: {
  project: string;
  epic: string;
  runId: string;
  cp: Checkpoint;
  dictionary: Dictionary;
}) {
  const [open, setOpen] = useState(false);
  const status = verdictStatus(cp.verdict);

  // Repeat badge: a KNOWN >=3 repeat is a hot-spot, but ONLY when sourced
  // (repeatSource !== null). An unknown repeatCount is "?" — NEVER 0, never a
  // fabricated hot-spot.
  const repeatKnown = cp.repeatCount != null && cp.repeatSource != null;
  const hotSpot = repeatKnown && (cp.repeatCount as number) >= 3;
  const repeatLabel = cp.repeatCount == null ? '?' : `×${cp.repeatCount}`;

  // Czech one-liner via the dictionary (role:verdict-style key falls back gracefully).
  const explanation = explainEvent(
    {
      projectId: project,
      epicId: epic,
      runId,
      ts: '',
      event: 'checkpoint',
      result: cp.verdict === 'pass' ? 'pass' : cp.verdict === 'fail' ? 'fail' : undefined,
      raw: { verdict: cp.verdict ?? 'null', cp: cp.id },
    },
    dictionary,
  );

  return (
    <>
      <button
        type="button"
        data-cp-row={cp.id}
        data-verdict={cp.verdict ?? 'null'}
        onClick={() => setOpen(true)}
        className="flex w-full flex-wrap items-center gap-x-3 gap-y-1 rounded-lg border border-slate-200 bg-white px-3 py-2 text-left text-sm hover:bg-slate-50"
      >
        <StatusDot status={status} title={cp.label || cp.id} />
        <span className="font-medium tabular-nums text-slate-800">{cp.id}</span>
        <span className="text-slate-500">{verdictWord(cp.verdict)}</span>
        <span
          data-cp-repeat={cp.repeatCount ?? 'null'}
          className={cn(
            'ml-auto rounded-full border px-2 py-0.5 text-xs tabular-nums',
            hotSpot
              ? 'border-orange-300 bg-orange-50 text-orange-700'
              : 'border-slate-200 text-slate-500',
          )}
          title={hotSpot ? 'hot-spot: opakováno ≥3×' : 'počet opakování'}
        >
          {repeatLabel}
          {hotSpot ? ' hot-spot' : ''}
        </span>
      </button>

      <Dialog.Root open={open} onOpenChange={setOpen}>
        <Dialog.Portal>
          <Dialog.Backdrop className="fixed inset-0 z-50 bg-slate-900/40" />
          <Dialog.Popup className="fixed inset-x-0 bottom-0 z-50 max-h-[85vh] overflow-y-auto rounded-t-2xl border-t border-slate-200 bg-white pb-[env(safe-area-inset-bottom)] shadow-xl sm:inset-x-auto sm:right-0 sm:top-0 sm:bottom-0 sm:max-h-none sm:w-[36rem] sm:max-w-[90vw] sm:rounded-none sm:rounded-l-2xl sm:border-l sm:border-t-0">
            <div className="flex items-start justify-between gap-3 border-b border-slate-200 px-4 py-3">
              <Dialog.Title className="text-base font-semibold text-slate-900">
                {cp.id} — {cp.label || 'kontrolní bod'}
              </Dialog.Title>
              <Dialog.Close
                className="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg text-slate-500 hover:bg-slate-100"
                aria-label="Zavřít"
              >
                <X className="h-5 w-5" />
              </Dialog.Close>
            </div>
            <div className="space-y-3 px-4 py-4">
              <div className="flex items-center gap-2">
                <StatusBadge status={status} label={verdictWord(cp.verdict)} />
                <span
                  data-cp-provenance
                  className="text-xs text-slate-400"
                  title={cp.provenanceSource ?? undefined}
                >
                  stopa:{' '}
                  {cp.provenance == null
                    ? 'nezaznamenáno'
                    : Array.isArray(cp.provenance)
                      ? cp.provenance.filter(Boolean).join(', ') || 'nezaznamenáno'
                      : cp.provenance}
                </span>
              </div>
              <p data-cp-explanation className="text-sm text-slate-600">
                {explanation.headline}
              </p>

              {/* Findings: each output .md opens via the RUN-SCOPED /file endpoint. */}
              {cp.outputs.length > 0 ? (
                <ul className="space-y-1.5" data-cp-outputs>
                  {cp.outputs.map((o) => (
                    <li key={o.relPath} className="flex items-center justify-between gap-2">
                      <span className="truncate text-sm text-slate-600">{o.name}</span>
                      <RawMarkdownDialog
                        projectId={project}
                        epicId={epic}
                        runId={runId}
                        name={o.relPath}
                        title={`${cp.id} — ${o.name}`}
                        triggerLabel="Zobrazit"
                      />
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-sm text-slate-400">Pro tento kontrolní bod nejsou žádné výstupy.</p>
              )}
            </div>
          </Dialog.Popup>
        </Dialog.Portal>
      </Dialog.Root>
    </>
  );
}

// ---------------------------------------------------------------------------
// Roles section — four AgentRolePanels with permanent Czech micro-explanations
// ---------------------------------------------------------------------------

const ROLES: AgentRole[] = ['auditor', 'curator', 'reporter', 'simplifier'];

function RolesSection({ latest, dictionary }: { latest: RunDetail; dictionary: Dictionary }) {
  // Derive each role's verdict from the available signals:
  //  - auditor: from latest.audit (the only structured per-run role result here);
  //  - all roles: a matching role event in the timeline (newest wins);
  //  - null when none → AgentRolePanel falls back to the generic role:<role> key.
  const verdicts = useMemo(() => roleVerdicts(latest), [latest]);

  return (
    <div className="grid gap-3 sm:grid-cols-2" data-roles-grid>
      {ROLES.map((role) => (
        <AgentRolePanel
          key={role}
          role={role}
          verdict={verdicts[role]}
          dictionary={dictionary}
        />
      ))}
    </div>
  );
}

/** Best-effort per-role verdict from audit + timeline role events. */
function roleVerdicts(latest: RunDetail): Record<AgentRole, string | null> {
  const out: Record<AgentRole, string | null> = {
    auditor: null,
    curator: null,
    reporter: null,
    simplifier: null,
  };

  // Auditor: the structured audit summary is the source of record for this run.
  if (latest.audit.present) {
    out.auditor =
      latest.audit.blockingFindings === true
        ? 'blocking'
        : latest.audit.blockingFindings === false
          ? 'clean'
          : null;
  }

  // Any role event in the timeline (newest first) provides a verdict/disposition.
  for (const ev of latest.timeline) {
    const role = ev.role as AgentRole | undefined;
    if (!role || !(role in out)) continue;
    if (out[role] != null) continue;
    const verdict =
      ev.result ??
      (typeof ev.raw?.verdict === 'string' ? ev.raw.verdict : undefined) ??
      (typeof ev.raw?.disposition === 'string' ? ev.raw.disposition : undefined);
    out[role] = verdict ?? null;
  }

  return out;
}

// ---------------------------------------------------------------------------
// Audit section — per-run AuditSummaryCard + EPIC-scope AuditTrendChart
// ---------------------------------------------------------------------------

function AuditSection({
  project,
  epic,
  detail,
  latest,
}: {
  project: string;
  epic: string;
  detail: EpicDetail;
  latest: RunDetail;
}) {
  return (
    <div className="space-y-4" data-audit-section>
      {/* present:false → the card itself renders "auditor zatím neběžel". */}
      <AuditSummaryCard
        variant="run"
        summary={latest.audit}
        projectId={project}
        epicId={epic}
        runId={latest.runId}
      />

      <Card title="Vývoj skóre auditu (EPIC)">
        {/* EPIC-scope trend; connectNulls={false} is enforced inside the chart. */}
        <AuditTrendChart trend={detail.auditTrend} />
        <p className="mt-2 text-sm text-slate-500">
          Skóre auditu napříč běhy tohoto EPICu. Mezery jsou běhy bez měřitelného skóre.
        </p>
      </Card>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Timing section — per-step DurationBars + retry, gates, compliance
// ---------------------------------------------------------------------------

function TimingSection({ metrics, latest }: { metrics: MetricSet; latest: RunDetail }) {
  return (
    <div className="space-y-4" data-timing-section>
      <StepTimings metrics={metrics} latest={latest} />
      <GatesCard gates={latest.gates} />
      <ComplianceCard compliance={latest.compliance} />
    </div>
  );
}

function StepTimings({ metrics, latest }: { metrics: MetricSet; latest: RunDetail }) {
  const durations = metrics.stepDurationsS;
  // Full-scale reference = the longest measured step (so bars are comparable);
  // never derived from null entries (a null step contributes nothing to maxS).
  const maxS = Math.max(1, ...durations.filter((d): d is number => d != null));
  const repeats = metrics.checkpointRepeats;

  return (
    <Card title="Časy kroků a opakování">
      <div className="space-y-3">
        {durations.length === 0 ? (
          <p data-steps-empty className="text-sm text-slate-400">
            Pro tento běh nejsou žádná data o krocích.
          </p>
        ) : (
          <ul className="space-y-2" data-step-bars>
            {durations.map((d, i) => {
              const step = latest.steps[i];
              const label = step ? `${step.id}` : `krok ${i + 1}`;
              return (
                <li key={i} className="flex items-center gap-3 text-xs">
                  <span className="w-24 shrink-0 truncate tabular-nums text-slate-700">{label}</span>
                  <span className="flex-1">
                    {/* null → "neměřeno" hatched bar (never a 0-length / 0m bar). */}
                    <DurationBar durationS={d} maxS={maxS} />
                  </span>
                  <span className="w-16 shrink-0 text-right tabular-nums text-slate-500">
                    {d == null ? 'neměřeno' : `${Math.round(d / 60)} m`}
                  </span>
                </li>
              );
            })}
          </ul>
        )}

        <p data-step-source className="text-xs text-slate-400">
          Zdroj měření:{' '}
          {metrics.stepTimingSource === 'mtime'
            ? 'čas úprav souborů'
            : metrics.stepTimingSource === 'dispatch'
              ? 'záznam dispečinku'
              : 'neměřeno'}
        </p>

        {/* Per-CP retry counts (the metrics roll-up). null → "?" never 0; a
            hot-spot is flagged only on a KNOWN >=3 repeat. */}
        <div className="border-t border-slate-100 pt-2">
          <p className="mb-1.5 text-xs font-medium text-slate-600">Opakování kontrol</p>
          <ul className="flex flex-wrap gap-2" data-cp-repeats>
            {NORMAL_CPS.map((id) => {
              const n = repeats[id] ?? null;
              const hotSpot = n != null && n >= 3;
              return (
                <li
                  key={id}
                  data-cp={id}
                  data-repeat={n ?? 'null'}
                  className={cn(
                    'inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs tabular-nums',
                    hotSpot
                      ? 'border-orange-300 bg-orange-50 text-orange-700'
                      : 'border-slate-200 text-slate-500',
                  )}
                >
                  <span className="font-medium">{id}</span>
                  <span>{n == null ? '?' : `×${n}`}</span>
                  {hotSpot && <span>hot-spot</span>}
                </li>
              );
            })}
          </ul>
        </div>
      </div>
    </Card>
  );
}

/** Czech §6.2 token for a gate result. */
function gateStatus(result: GateResult['result']): StatusKey {
  if (result === 'pass') return 'proslo';
  if (result === 'fail') return 'selhalo';
  return 'ceka';
}

function GatesCard({ gates }: { gates: GateResult[] }) {
  return (
    <Card title="Brány kvality (gates)">
      {gates.length === 0 ? (
        <p data-gates-empty className="text-sm text-slate-400">
          Pro tento běh nejsou žádné brány.
        </p>
      ) : (
        <ul className="space-y-1.5" data-gates-list>
          {gates.map((g) => (
            <li
              key={g.gate}
              data-gate={g.gate}
              className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm"
            >
              <StatusBadge status={gateStatus(g.result)} />
              <span className="font-medium text-slate-700">{g.gate}</span>
              <span className="ml-auto text-xs tabular-nums text-slate-500">
                {/* duration_ms → seconds chip, honest about absence. */}
                <MetricBadge
                  value={g.durationMs > 0 ? Math.round(g.durationMs / 1000) : null}
                  unit=" s"
                  nullLabel="neměřeno"
                />
                {' · '}
                pokusů <MetricBadge value={g.attempts} />
                {' · '}
                kód <MetricBadge value={g.exitCode} />
              </span>
            </li>
          ))}
        </ul>
      )}
      <p className="mt-2 text-sm text-slate-500">
        Brány jsou automatické kontroly (build, testy, lint). Selhání blokuje postup běhu.
      </p>
    </Card>
  );
}

/** Czech §6.2 token for a compliance failure severity. */
function severityStatus(severity: ComplianceFailure['severity']): StatusKey {
  return severity === 'blocking' ? 'zablokovano' : 'pozor';
}

function ComplianceCard({ compliance }: { compliance: RunDetail['compliance'] }) {
  // null compliance → "N/A" + warning, NEVER 0%/fail.
  if (compliance == null) {
    return (
      <Card title="Shoda (compliance)">
        <p data-compliance-na className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700">
          Shoda pro tento běh: N/A — nezaznamenáno (žádné skóre ani selhání).
        </p>
      </Card>
    );
  }

  const overallKey: StatusKey = compliance.overall === 'pass' ? 'proslo' : 'selhalo';

  return (
    <Card title="Shoda (compliance)">
      <div className="space-y-3">
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <StatusBadge status={overallKey} />
          <span className="text-xs tabular-nums text-slate-500">
            přepisů <MetricBadge value={compliance.forceOverrideCount} />
          </span>
        </div>

        {compliance.failures.length === 0 ? (
          <p data-compliance-clean className="text-sm text-slate-400">
            Žádná porušení shody.
          </p>
        ) : (
          <ul className="space-y-1.5" data-compliance-failures>
            {compliance.failures.map((f, i) => (
              <li
                key={`${f.check}:${i}`}
                data-check={f.check}
                data-severity={f.severity}
                className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm"
              >
                <StatusBadge
                  status={severityStatus(f.severity)}
                  label={f.severity === 'blocking' ? 'blokující' : 'doporučení'}
                />
                <span className="font-medium text-slate-700">{f.check}</span>
                <span className="text-xs text-slate-500">{f.evidence}</span>
              </li>
            ))}
          </ul>
        )}

        <p className="text-sm text-slate-500">
          Shoda ověřuje dodržení pravidel pipeline. „Blokující" porušení zastaví postup, „doporučení" je
          varování.
        </p>
      </div>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Events section — narrator "CO SE DĚJE" (newest-first) + raw-md file tree
// ---------------------------------------------------------------------------

function EventsSection({
  project,
  epic,
  latest,
  dictionary,
}: {
  project: string;
  epic: string;
  latest: RunDetail;
  dictionary: Dictionary;
}) {
  // Newest-first narrated timeline.
  const events = useMemo(
    () => [...latest.timeline].sort((a, b) => (a.ts < b.ts ? 1 : a.ts > b.ts ? -1 : 0)),
    [latest.timeline],
  );

  // Raw-md file tree: run files + report artifacts, de-duplicated by path.
  const files = useMemo(() => {
    const map = new Map<string, string>(); // relPath → display name
    for (const r of latest.reports) map.set(r.relPath, r.name);
    for (const f of latest.files) if (!map.has(f)) map.set(f, f);
    return [...map.entries()].map(([relPath, name]) => ({ relPath, name }));
  }, [latest.reports, latest.files]);

  return (
    <div className="space-y-4" data-events-section>
      <Card title="Co se děje" collapsibleOnMobile>
        {events.length === 0 ? (
          <p data-events-empty className="text-sm text-slate-400">
            Zatím se nic nestalo.
          </p>
        ) : (
          <div data-event-feed className="divide-y divide-slate-100">
            {events.map((event, i) => (
              <EventRow
                key={`${event.ts}:${event.event}:${i}`}
                event={event}
                explanation={explainEvent(event, dictionary)}
                at={event.ts}
              />
            ))}
          </div>
        )}
      </Card>

      <Card title="Zdrojové soubory běhu">
        {files.length === 0 ? (
          <p data-files-empty className="text-sm text-slate-400">
            Pro tento běh nejsou žádné soubory.
          </p>
        ) : (
          <ul className="space-y-1.5" data-file-tree>
            {files.map((f) => (
              <li key={f.relPath} className="flex items-center justify-between gap-2">
                <span className="truncate text-sm text-slate-600" title={f.relPath}>
                  {f.name}
                </span>
                {/* Each file opens via the RUN-SCOPED /file endpoint (name=, not path=). */}
                <RawMarkdownDialog
                  projectId={project}
                  epicId={epic}
                  runId={latest.runId}
                  name={f.relPath}
                  title={f.name}
                  triggerLabel="Zobrazit"
                />
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
