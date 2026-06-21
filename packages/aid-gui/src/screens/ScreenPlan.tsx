import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { Link, useParams } from 'react-router-dom';
import { Tabs } from '@base-ui/react/tabs';
import { useMemo } from 'react';
import type { EpicSummary, PlanDetail } from '@aid/contract';
import { getPlanDetail, getBrief, ApiError } from '../lib/api';
import { getLastSeen } from '../lib/lastSeen';
import { getBacklogSnapshot, buildBacklogDelta } from '../lib/backlog-delta';
import { relativeCzech, czechPlural } from '../lib/utils';
import { MobileBackHeader } from '../components/shell/MobileBackHeader';
import { ProjectNotFound } from '../components/shell/ProjectNotFound';
import { useProjects } from '../components/shell/ProjectsContext';
import { TabButton } from '../components/common/TabButton';
import { BriefPanel } from '../components/managerial/BriefPanel';
import { PlanPhaseTimeline } from '../components/managerial/PlanPhaseTimeline';
import { AuditSummaryCard } from '../components/managerial/AuditSummaryCard';
import { AuditTrendChart } from '../components/charts/AuditTrendChart';
import { ReporterDeliveryPanel } from '../components/managerial/ReporterDeliveryPanel';
import { SimplifierPanel } from '../components/managerial/SimplifierPanel';
import { BacklogDeltaList } from '../components/managerial/BacklogDeltaList';
import { LessonsTable } from '../components/managerial/LessonsTable';
import { Card } from '../components/managerial/Card';
import { MetricBadge } from '../components/common/MetricBadge';

/**
 * Screen Plan — first-class Plan detail (§13.6) at `/p/:project/plans/:planId`.
 *
 * The route `:planId` IS the plan STEM (the §13.6 PRIMARY identity); it is passed
 * verbatim to {@link getPlanDetail}, so a bare ambiguous plan NUMBER is rejected
 * server-side with HTTP 409 AMBIGUOUS_PLAN_NUMBER rather than silently resolving
 * to the wrong plan.
 *
 * Eight Rev-4 tabs (default "brief"): Brief · Fáze · EPICy · Audit ·
 * Dodávka & zjednodušení · AC · Backlog · Lekce. The five primary tabs are
 * left-anchored; AC · Backlog · Lekce live past the fold and horizontal-scroll
 * on mobile. Every tab is backed by the SINGLE plan-detail query (one fetch),
 * except Brief which has its own since-scoped query — so a Brief outage degrades
 * locally and never takes the detail tabs down.
 *
 * A non-existent `:project` is caught by the Phase-5 {@link ProjectNotFound}
 * guard (an API outage is NOT "not found"). A missing plan / 409 is handled
 * inside the body as a plan-level miss with a back-link to the project's Plány tab.
 */
export function ScreenPlan() {
  const { project = '', planId = '' } = useParams();
  const { projects, loaded, error } = useProjects();
  const known = projects.some((p) => p.id === project);

  // KEEP the Phase-5 guard: a list-fetch outage is not a genuine project miss.
  if (loaded && error) return <ProjectNotFound projectId={project} loadError />;
  if (loaded && !known) return <ProjectNotFound projectId={project} />;

  return (
    <section className="space-y-4 p-4 sm:p-6" aria-label={`Plán ${planId}`}>
      <PlanBody project={project} planId={planId} />
    </section>
  );
}

/**
 * The plan-detail body. Owns the single `plan-detail` query so the header band,
 * Fáze/EPICy/Audit/Dodávka/AC/Backlog/Lekce tabs all read ONE PlanDetail. A
 * failure / 404 / 409 renders the plan-level "nenašel se" state with a back-link.
 */
function PlanBody({ project, planId }: { project: string; planId: string }) {
  const detailQuery = useQuery({
    // The :planId route param IS the STEM — pass it verbatim (§13.6).
    queryKey: ['plan-detail', project, planId],
    queryFn: () => getPlanDetail(project, planId),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
    retry: false,
  });

  const detail = detailQuery.data;

  if (!detail) {
    if (detailQuery.isError) {
      const err = detailQuery.error;
      const ambiguous = err instanceof ApiError && err.code === 'AMBIGUOUS_PLAN_NUMBER';
      return (
        <>
          <MobileBackHeader title={`Plán ${planId}`} />
          <div
            data-plan-not-found
            className="space-y-2 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800"
          >
            <p>
              {ambiguous
                ? `Číslo plánu ${planId} je nejednoznačné — použij plný identifikátor (stem).`
                : `Plán ${planId} se nenašel`}
            </p>
            <Link to={`/p/${project}`} className="font-medium text-sky-700 hover:underline">
              ← zpět na Plány projektu
            </Link>
          </div>
        </>
      );
    }
    return (
      <>
        <MobileBackHeader title={`Plán ${planId}`} />
        <p data-plan-loading className="text-sm text-slate-400">
          Načítám detail plánu…
        </p>
      </>
    );
  }

  return (
    <>
      <MobileBackHeader title={detail.title || `Plán ${planId}`} />
      <PlanHeaderBand detail={detail} />

      {/* Aggregation degradations are a muted note, NOT an error (Edge Cases). */}
      {detail.warnings.length > 0 && (
        <ul data-plan-warnings className="space-y-0.5 text-xs text-amber-700">
          {detail.warnings.map((w, i) => (
            <li key={i}>{w}</li>
          ))}
        </ul>
      )}

      <Tabs.Root defaultValue="brief">
        <Tabs.List
          data-screen-plan-tabs
          className="flex gap-1 overflow-x-auto whitespace-nowrap border-b border-slate-200"
        >
          <TabButton value="brief">Brief</TabButton>
          <TabButton value="phases">Fáze</TabButton>
          <TabButton value="epics">EPICy</TabButton>
          <TabButton value="audit">Audit</TabButton>
          <TabButton value="delivery">Dodávka &amp; zjednodušení</TabButton>
          <TabButton value="ac">AC</TabButton>
          <TabButton value="backlog">Backlog</TabButton>
          <TabButton value="lessons">Lekce</TabButton>
        </Tabs.List>

        <Tabs.Panel value="brief" className="pt-4">
          <BriefTab project={project} planId={planId} />
        </Tabs.Panel>
        <Tabs.Panel value="phases" className="pt-4">
          <PhasesTab project={project} detail={detail} />
        </Tabs.Panel>
        <Tabs.Panel value="epics" className="pt-4">
          <EpicsTab project={project} detail={detail} />
        </Tabs.Panel>
        <Tabs.Panel value="audit" className="pt-4">
          <AuditTab project={project} detail={detail} />
        </Tabs.Panel>
        <Tabs.Panel value="delivery" className="pt-4">
          <DeliveryTab project={project} detail={detail} />
        </Tabs.Panel>
        <Tabs.Panel value="ac" className="pt-4">
          <AcTab detail={detail} />
        </Tabs.Panel>
        <Tabs.Panel value="backlog" className="pt-4">
          <BacklogTab project={project} planId={planId} detail={detail} />
        </Tabs.Panel>
        <Tabs.Panel value="lessons" className="pt-4">
          <LessonsTab project={project} detail={detail} />
        </Tabs.Panel>
      </Tabs.Root>
    </>
  );
}

// ---------------------------------------------------------------------------
// Header band — "P003 · {title} běží · 5 EPICů · 3 hotové · 60%"
// ---------------------------------------------------------------------------

/**
 * One-line plan header band from PlanDetail counts. Honest nulls: an unmeasured
 * `acPct` renders "AC neměřeno", never "0 %".
 */
function PlanHeaderBand({ detail }: { detail: PlanDetail }) {
  const word = detail.lastActivityAt ? 'běží' : 'klid';
  const age = detail.lastActivityAt ? relativeCzech(detail.lastActivityAt) : null;

  return (
    <p
      data-header-band
      className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-slate-600"
    >
      <span className="font-semibold tabular-nums text-slate-900">{detail.planId}</span>
      <span aria-hidden>·</span>
      <span className="truncate text-slate-700">{detail.title}</span>
      <span aria-hidden>·</span>
      <span>{word}</span>
      <span aria-hidden>·</span>
      <span>
        <MetricBadge value={detail.epicsTotal} /> EPICů
      </span>
      <span aria-hidden>·</span>
      <span>
        <MetricBadge value={detail.epicsDone} /> hotových
      </span>
      <span aria-hidden>·</span>
      <span>
        <MetricBadge value={Math.round(detail.progressPct)} unit=" %" />
      </span>
      <span aria-hidden>·</span>
      <span>
        AC{' '}
        <MetricBadge
          value={detail.acPct == null ? null : Math.round(detail.acPct)}
          unit=" %"
          nullLabel="neměřeno"
        />
      </span>
      {age && (
        <>
          <span aria-hidden>·</span>
          <span className="text-xs text-slate-400">{age}</span>
        </>
      )}
    </p>
  );
}

// ---------------------------------------------------------------------------
// Run-coordinate threading — plan-boundary EPIC for /file evidence fetches
// ---------------------------------------------------------------------------

/**
 * Run-scope coords for the plan-boundary EPIC. The boundary EPIC is the LAST
 * member EPIC (status-weighted sort = plan order, §13.6) and its `latestRun`
 * supplies the runId for the run-scoped `/file?name=` evidence/raw fetches.
 *
 * When the boundary EPIC has no latest run, `runId` is undefined and the panels
 * already hide their raw/evidence triggers (they accept missing coords).
 */
function boundaryRunCoords(
  project: string,
  epics: EpicSummary[],
): { projectId: string; epicId?: string; runId?: string } {
  const boundary = epics.length > 0 ? epics[epics.length - 1] : null;
  return {
    projectId: project,
    epicId: boundary?.id,
    runId: boundary?.latestRun?.runId,
  };
}

// ---------------------------------------------------------------------------
// Tab 1 — Brief (plan scope) — DEFAULT
// ---------------------------------------------------------------------------

function BriefTab({ project, planId }: { project: string; planId: string }) {
  // Plan-scope lastSeen key (spec §13.3: `plan:<project>:<planId>`).
  const since = getLastSeen(`plan:${project}:${planId}`);
  const briefQuery = useQuery({
    queryKey: ['brief', 'plan', project, planId, since],
    queryFn: () => getBrief({ project, plan: planId }, since ?? undefined),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });

  const brief = briefQuery.data;

  if (!brief) {
    if (briefQuery.isError) {
      return (
        <p data-brief-error className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700">
          Brief plánu se nepodařilo načíst — zkouším znovu.
        </p>
      );
    }
    return (
      <p data-brief-loading className="text-sm text-slate-400">
        Načítám přehled plánu…
      </p>
    );
  }

  return <BriefPanel scope="plan" brief={brief} />;
}

// ---------------------------------------------------------------------------
// Tab 2 — Fáze (member EPICs as a phase timeline)
// ---------------------------------------------------------------------------

function PhasesTab({ project, detail }: { project: string; detail: PlanDetail }) {
  return (
    <Card title="Fáze plánu">
      {/* The timeline visualizes member-EPIC state; FsmTimeline carries no links,
          so the per-EPIC deep-links live in the chip row beneath it. */}
      <PlanPhaseTimeline epics={detail.epics} />
      <ul className="mt-3 flex flex-wrap gap-2" data-phase-links>
        {detail.epics.map((epic) => (
          <li key={epic.id}>
            <Link
              to={`/p/${project}/e/${epic.id}`}
              className="inline-flex items-center rounded-full border border-slate-200 bg-slate-50 px-2 py-0.5 font-mono text-xs text-slate-600 hover:bg-slate-100"
            >
              {epic.id}
            </Link>
          </li>
        ))}
      </ul>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Tab 3 — EPICy (member rows + membershipSource chips)
// ---------------------------------------------------------------------------

const MEMBERSHIP_LABEL: Record<string, { label: string; cls: string } | null> = {
  plan_path: { label: 'z plánu', cls: 'border-slate-200 bg-slate-50 text-slate-600' },
  plan_ref: { label: 'z plánu', cls: 'border-slate-200 bg-slate-50 text-slate-600' },
  derived: {
    label: 'pozor: přiřazeno podle čísla',
    cls: 'border-amber-300 bg-amber-50 text-amber-700',
  },
  orphan: { label: 'osiřelý', cls: 'border-rose-300 bg-rose-50 text-rose-700' },
};

function EpicsTab({ project, detail }: { project: string; detail: PlanDetail }) {
  // Resolve each EPIC's membership tier from epicMembers (per-EPIC resolution).
  const sourceById = useMemo(() => {
    const m = new Map<string, string>();
    for (const em of detail.epicMembers) m.set(em.epicId, em.membershipSource);
    return m;
  }, [detail.epicMembers]);

  return (
    <div className="space-y-3" data-plan-epics-tab>
      {/* Mixed-tier note — the "přiřazeno podle čísla EPICu" warning (§13.6). */}
      {detail.membershipMixed && (
        <p
          data-membership-mixed-note
          className="rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-700"
        >
          Některé EPICy jsou k plánu přiřazeny podle čísla EPICu — slabší vazba než přímý odkaz z
          plánu.
        </p>
      )}

      {detail.orphanEpicCount > 0 && (
        <p data-orphan-count className="text-xs text-slate-400">
          Mimo plán zůstává {detail.orphanEpicCount}{' '}
          {czechPlural(detail.orphanEpicCount, 'osiřelý EPIC', 'osiřelé EPICy', 'osiřelých EPICů')}.
        </p>
      )}

      {detail.epics.length === 0 ? (
        <p data-plan-epics-empty className="text-sm text-slate-400">
          Plán nemá žádné členské EPICy.
        </p>
      ) : (
        <ul className="space-y-1.5" data-plan-epics-list>
          {detail.epics.map((epic) => (
            <li key={epic.id}>
              <PlanEpicRow
                project={project}
                epic={epic}
                source={epic.membershipSource ?? sourceById.get(epic.id) ?? null}
              />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function PlanEpicRow({
  project,
  epic,
  source,
}: {
  project: string;
  epic: EpicSummary;
  source: string | null;
}) {
  const chip = source ? MEMBERSHIP_LABEL[source] : null;
  const pct =
    epic.runsTotal > 0 ? Math.round((epic.runsCompleted / epic.runsTotal) * 100) : null;

  return (
    <Link
      to={`/p/${project}/e/${epic.id}`}
      data-plan-epic-row
      data-epic-id={epic.id}
      data-membership-source={source ?? undefined}
      className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm hover:bg-slate-50"
    >
      <span className="font-medium tabular-nums text-slate-800">{epic.id}</span>
      <span className="truncate text-slate-600">{epic.title}</span>
      {chip && (
        <span
          data-membership-chip
          className={`rounded-full border px-2 py-0.5 text-xs font-medium ${chip.cls}`}
        >
          {chip.label}
        </span>
      )}
      <span className="ml-auto text-xs text-slate-500">
        <MetricBadge value={pct} unit=" %" nullLabel="bez běhu" /> hotovo
      </span>
    </Link>
  );
}

// ---------------------------------------------------------------------------
// Tab 4 — Audit (boundary + aggregate, two distinct numbers, + trend)
// ---------------------------------------------------------------------------

function AuditTab({ project, detail }: { project: string; detail: PlanDetail }) {
  const coords = boundaryRunCoords(project, detail.epics);
  // boundaryAudit (#1) and aggregateAudit (#2) are TWO independent presence flags.
  const boundaryAbsent = !detail.boundaryAudit.present;
  const aggregateHasScore =
    detail.aggregateAudit.present && detail.aggregateAudit.scoredEpicCount > 0;

  return (
    <div className="space-y-4" data-plan-audit-tab>
      {/* Plan-level aggregation warnings as a muted note atop the tab. */}
      {detail.warnings.length > 0 && (
        <ul className="space-y-0.5 text-xs text-amber-700" data-plan-audit-warnings>
          {detail.warnings.map((w, i) => (
            <li key={i}>{w}</li>
          ))}
        </ul>
      )}

      {/* #1 — the SINGLE plan-boundary auditor run. */}
      <div data-boundary-audit>
        {boundaryAbsent && aggregateHasScore && (
          <p data-boundary-audit-late className="mb-1 text-xs text-amber-700">
            Audit na konci plánu: auditor zatím neběžel.
          </p>
        )}
        {/* Pass the boundary EPIC's run coords for the raw audit-report.md drawer
            (the card hides the trigger when coords are unavailable). */}
        <AuditSummaryCard
          variant="boundary"
          summary={detail.boundaryAudit}
          projectId={coords.projectId}
          epicId={coords.epicId}
          runId={coords.runId}
        />
      </div>

      {/* #2 — the project/plan aggregate (DISTINCT labelled number). */}
      <div data-aggregate-audit>
        <AuditSummaryCard variant="aggregate" summary={detail.aggregateAudit} />
      </div>

      {/* Trend — connectNulls={false} is enforced inside AuditTrendChart. */}
      <Card title="Vývoj skóre auditu">
        <AuditTrendChart trend={detail.auditTrend} />
      </Card>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab 5 — Dodávka & zjednodušení (Reporter delivery + Simplifier, stacked)
// ---------------------------------------------------------------------------

function DeliveryTab({ project, detail }: { project: string; detail: PlanDetail }) {
  const coords = boundaryRunCoords(project, detail.epics);

  return (
    <div className="space-y-4" data-plan-delivery-tab>
      {/* Reporter delivery — testEvidence exists:false flagged, never dropped.
          Run coords drive the run-scoped /file?name= evidence fetch. */}
      <ReporterDeliveryPanel
        delivery={detail.deliveryReport}
        projectId={coords.projectId}
        epicId={coords.epicId}
        runId={coords.runId}
      />
      {/* Simplifier proposals — present:false → "zatím neběžel", no fabrication. */}
      <SimplifierPanel
        summary={detail.simplifierSummary}
        projectId={coords.projectId}
        epicId={coords.epicId}
        runId={coords.runId}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab 6 — AC (plan acPct headline + per-EPIC AC bars)
// ---------------------------------------------------------------------------

function AcTab({ detail }: { detail: PlanDetail }) {
  return (
    <Card title="Akceptační kritéria">
      <div className="space-y-3" data-plan-ac-tab>
        {/* Headline — acPct:null → "neměřeno / fast mode", NEVER 0 %. */}
        <p className="text-sm">
          {detail.acPct == null ? (
            <span data-ac-headline="null" className="text-slate-500">
              AC: neměřeno / fast mode
            </span>
          ) : (
            <span data-ac-headline className="font-semibold tabular-nums text-slate-800">
              AC {Math.round(detail.acPct)} %
            </span>
          )}
        </p>

        {detail.epics.length === 0 ? (
          <p className="text-sm text-slate-400">Plán nemá žádné členské EPICy.</p>
        ) : (
          <ul className="space-y-2" data-plan-ac-bars>
            {detail.epics.map((epic) => {
              const pct =
                epic.runsTotal > 0
                  ? Math.round((epic.runsCompleted / epic.runsTotal) * 100)
                  : null;
              return (
                <li key={epic.id} className="flex items-center gap-3 text-xs">
                  <span className="w-28 shrink-0 truncate tabular-nums text-slate-700">
                    {epic.id}
                  </span>
                  {pct != null ? (
                    <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-slate-100">
                      <span
                        className="block h-full rounded-full bg-slate-400"
                        style={{ width: `${pct}%` }}
                      />
                    </span>
                  ) : (
                    <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-slate-200 text-slate-400">
                      neměřeno
                    </span>
                  )}
                  <span className="w-16 shrink-0 text-right tabular-nums text-slate-500">
                    <MetricBadge value={pct} unit=" %" nullLabel="—" />
                  </span>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Tab 7 — Backlog (CLIENT-SIDE delta vs localStorage snapshot)
// ---------------------------------------------------------------------------

function BacklogTab({
  project,
  planId,
  detail,
}: {
  project: string;
  planId: string;
  detail: PlanDetail;
}) {
  // Compute the delta CLIENT-SIDE (§13.7): current rows vs the persisted snapshot
  // under `aid.backlog.plan:<project>:<planId>`. firstVisit (no snapshot) →
  // BacklogDeltaList renders "bez porovnání - vše jako nové". Read-only — we never
  // mutate the backlog or persist a snapshot here.
  const delta = useMemo(() => {
    const snapshot = getBacklogSnapshot(`plan:${project}:${planId}`);
    return buildBacklogDelta(detail.backlog.items, snapshot, {
      scope: 'plan',
      projectId: project,
      planId,
      closedCount: detail.backlog.closedCount,
    });
  }, [detail.backlog.items, detail.backlog.closedCount, project, planId]);

  return (
    <div data-plan-backlog-tab>
      <BacklogDeltaList delta={delta} />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab 8 — Lekce (lessons-per-plan)
// ---------------------------------------------------------------------------

function LessonsTab({ project, detail }: { project: string; detail: PlanDetail }) {
  // Empty → an explicit plan-scoped honest line (overrides the component default).
  if (detail.lessons.entries.length === 0) {
    return (
      <Card title="Ponaučení">
        <p data-plan-lessons-empty className="text-sm text-slate-500">
          Z tohohle plánu se zatím nezaznamenala žádná lekce.
        </p>
      </Card>
    );
  }

  return (
    <div data-plan-lessons-tab>
      <LessonsTable
        lessons={detail.lessons}
        epicHref={(_pid, epicId) => `/p/${project}/e/${epicId}`}
      />
    </div>
  );
}
