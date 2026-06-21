import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { Link, useParams } from 'react-router-dom';
import { Tabs } from '@base-ui/react/tabs';
import { ToggleGroup } from '@base-ui/react/toggle-group';
import { Toggle } from '@base-ui/react/toggle';
import { useState } from 'react';
import type { EpicSummary, FsmState, PlanSummary, Project } from '@aid/contract';
import {
  getBrief,
  getEpics,
  getPlans,
  getAuditSummary,
  getAuditTrend,
  getProjectDetail,
  getCompliance,
} from '../lib/api';
import { getLastSeen } from '../lib/lastSeen';
import { relativeCzech } from '../lib/utils';
import { FSM_STATUS, FSM_WORD } from '../lib/fsmStatus';
import { MobileBackHeader } from '../components/shell/MobileBackHeader';
import { ProjectNotFound } from '../components/shell/ProjectNotFound';
import { useProjects } from '../components/shell/ProjectsContext';
import { BriefPanel } from '../components/managerial/BriefPanel';
import { AuditSummaryCard } from '../components/managerial/AuditSummaryCard';
import { AuditTrendChart } from '../components/charts/AuditTrendChart';
import { Card } from '../components/managerial/Card';
import { StatusDot } from '../components/common/StatusDot';
import { MetricBadge } from '../components/common/MetricBadge';
import { DurationBar } from '../components/common/DurationBar';

/**
 * Screen B — project detail (§8) at `/p/:project`.
 *
 * A five-tab strip with the managerial **Brief (project scope) as the default
 * tab 1**: `[ Brief ][ EPICy ][ Plány ][ Audit ][ Zdraví ]`. The Brief leads so
 * the non-technical front door of a project is the explained read-model, not a
 * raw list. The tab strip horizontal-scrolls on mobile.
 *
 * Each tab is backed by its OWN react-query, so a failure in one tab degrades
 * locally (e.g. the audit-summary 500 → "Audit projektu se nepodařilo načíst"
 * inside the Audit tab) and never takes down the screen — Brief/EPICy stay live.
 * A non-existent `:project` is caught by the existing {@link ProjectNotFound}
 * guard (an API outage is NOT "not found": see {@link useProjects} `error`).
 */
export function ScreenB() {
  const { project = '' } = useParams();
  const { projects, loaded, error } = useProjects();
  const known = projects.some((p) => p.id === project);

  // KEEP the Phase-5 guard: distinguish a list-fetch outage from a genuine miss.
  if (loaded && error) return <ProjectNotFound projectId={project} loadError />;
  if (loaded && !known) return <ProjectNotFound projectId={project} />;

  const summary = projects.find((p) => p.id === project) ?? null;

  return (
    <section className="space-y-4 p-4 sm:p-6" aria-label={`Projekt ${project}`}>
      <MobileBackHeader title={summary?.name ?? project} />
      <ProjectHeaderBand project={project} summary={summary} />

      <Tabs.Root defaultValue="brief">
        <Tabs.List
          data-screen-b-tabs
          className="flex gap-1 overflow-x-auto whitespace-nowrap border-b border-slate-200"
        >
          <TabButton value="brief">Brief</TabButton>
          <TabButton value="epics">EPICy</TabButton>
          <TabButton value="plans">Plány</TabButton>
          <TabButton value="audit">Audit</TabButton>
          <TabButton value="health">Zdraví</TabButton>
        </Tabs.List>

        <Tabs.Panel value="brief" className="pt-4">
          <BriefTab project={project} />
        </Tabs.Panel>
        <Tabs.Panel value="epics" className="pt-4">
          <EpicsTab project={project} />
        </Tabs.Panel>
        <Tabs.Panel value="plans" className="pt-4">
          <PlansTab project={project} />
        </Tabs.Panel>
        <Tabs.Panel value="audit" className="pt-4">
          <AuditTab project={project} />
        </Tabs.Panel>
        <Tabs.Panel value="health" className="pt-4">
          <HealthTab project={project} />
        </Tabs.Panel>
      </Tabs.Root>
    </section>
  );
}

/** A single tab trigger styled as an underline tab (active = slate underline). */
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
// Header band — "vulcan běží · 9 EPICů · 1 aktivní · compliance 94 % · 2 plány"
// ---------------------------------------------------------------------------

/**
 * One-line project header band built from the cross-project {@link Project}
 * shape (already in context) plus a thin plan-count query. Counts are honest:
 * a `null` compliance pass-rate renders "compliance N/A", never "0 %".
 */
function ProjectHeaderBand({ project, summary }: { project: string; summary: Project | null }) {
  const plansQuery = useQuery({
    queryKey: ['plans', project],
    queryFn: () => getPlans(project),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });

  const word = summary?.activeRun ? FSM_WORD[summary.activeRun.state] : 'klid';
  const passRate = summary?.health.compliancePassRate ?? null;
  const plansCount = plansQuery.data?.length ?? null;

  return (
    <p data-header-band className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-slate-600">
      <span className="font-semibold text-slate-900">{summary?.name ?? project}</span>
      <span aria-hidden>·</span>
      <span>{word}</span>
      <span aria-hidden>·</span>
      <span>
        <MetricBadge value={summary?.epicsTotal ?? null} /> EPICů
      </span>
      <span aria-hidden>·</span>
      <span>
        <MetricBadge value={summary?.epicsActive ?? null} /> aktivní
      </span>
      <span aria-hidden>·</span>
      <span>
        compliance{' '}
        <MetricBadge
          value={passRate == null ? null : Math.round(passRate * 100)}
          unit=" %"
          nullLabel="N/A"
        />
      </span>
      <span aria-hidden>·</span>
      <span>
        <MetricBadge value={plansCount} nullLabel="?" /> plánů
      </span>
    </p>
  );
}

// ---------------------------------------------------------------------------
// Tab 1 — Brief (project scope) — DEFAULT
// ---------------------------------------------------------------------------

function BriefTab({ project }: { project: string }) {
  const since = getLastSeen(`p:${project}`);
  const briefQuery = useQuery({
    queryKey: ['brief', 'project', project, since],
    queryFn: () => getBrief({ project }, since ?? undefined),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });

  const brief = briefQuery.data;

  if (!brief) {
    if (briefQuery.isError) {
      return (
        <p data-brief-error className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700">
          Brief projektu se nepodařilo načíst — zkouším znovu.
        </p>
      );
    }
    return (
      <p data-brief-loading className="text-sm text-slate-400">
        Načítám přehled projektu…
      </p>
    );
  }

  return <BriefPanel scope="project" brief={brief} />;
}

// ---------------------------------------------------------------------------
// Tab 2 — EPICy (list with status filter chips)
// ---------------------------------------------------------------------------

type EpicFilter = 'all' | 'running' | 'waiting' | 'done' | 'failed';

const EPIC_FILTERS: { value: EpicFilter; label: string }[] = [
  { value: 'all', label: 'vše' },
  { value: 'running', label: 'běží' },
  { value: 'waiting', label: 'čeká' },
  { value: 'done', label: 'hotovo' },
  { value: 'failed', label: 'selhalo' },
];

/** Map an EPIC's latestRun.state onto a coarse filter bucket. */
function epicBucket(epic: EpicSummary): EpicFilter {
  const state: FsmState | null = epic.latestRun?.state ?? null;
  if (state === 'EXECUTE' || state === 'GATES') return 'running';
  if (state === 'READY') return 'waiting';
  if (state === 'DONE') return 'done';
  if (state === 'ERROR' || state === 'ESCALATION') return 'failed';
  // No run / legacy idle EPIC → still listed under "vše" only.
  return 'all';
}

function EpicsTab({ project }: { project: string }) {
  const [filter, setFilter] = useState<EpicFilter>('all');
  const epicsQuery = useQuery({
    queryKey: ['epics', project],
    queryFn: () => getEpics(project),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });

  const epics = epicsQuery.data;

  if (!epics) {
    if (epicsQuery.isError) {
      return (
        <p data-epics-error className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700">
          EPICy se nepodařilo načíst.
        </p>
      );
    }
    return (
      <p data-epics-loading className="text-sm text-slate-400">
        Načítám EPICy…
      </p>
    );
  }

  const shown =
    filter === 'all' ? epics : epics.filter((e) => epicBucket(e) === filter);

  return (
    <div className="space-y-3" data-epics-tab>
      <ToggleGroup
        data-epic-filter
        value={[filter]}
        onValueChange={(next) => {
          // Single-select semantics: keep a chip always active (default "all").
          const picked = next.find((v) => v !== filter) ?? 'all';
          setFilter(picked as EpicFilter);
        }}
        className="flex flex-wrap gap-1.5"
      >
        {EPIC_FILTERS.map((f) => (
          <Toggle
            key={f.value}
            value={f.value}
            className="min-h-[32px] rounded-full border border-slate-200 px-3 text-xs font-medium text-slate-500 data-[pressed]:border-slate-900 data-[pressed]:bg-slate-900 data-[pressed]:text-white"
          >
            {f.label}
          </Toggle>
        ))}
      </ToggleGroup>

      {shown.length === 0 ? (
        <p data-epics-empty className="text-sm text-slate-400">
          V tomhle filtru není žádný EPIC.
        </p>
      ) : (
        <ul className="space-y-1.5" data-epics-list>
          {shown.map((epic) => (
            <li key={epic.id}>
              <EpicRow project={project} epic={epic} />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function EpicRow({ project, epic }: { project: string; epic: EpicSummary }) {
  const state = epic.latestRun?.state ?? null;
  const status = state ? FSM_STATUS[state] : 'necinne';
  const word = state ? FSM_WORD[state] : 'klid';
  const pct =
    epic.runsTotal > 0 ? Math.round((epic.runsCompleted / epic.runsTotal) * 100) : null;
  const age = epic.lastActivityAt ? relativeCzech(epic.lastActivityAt) : null;

  return (
    <Link
      to={`/p/${project}/e/${epic.id}`}
      data-epic-row
      data-epic-id={epic.id}
      className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm hover:bg-slate-50"
    >
      <StatusDot status={status} title={word} />
      <span className="font-medium tabular-nums text-slate-800">{epic.id}</span>
      <span className="text-slate-400">{word}</span>
      <span className="ml-auto text-xs text-slate-500">
        <MetricBadge value={pct} unit=" %" nullLabel="bez běhu" /> hotovo
      </span>
      {age && <span className="text-xs text-slate-400">{age}</span>}
    </Link>
  );
}

// ---------------------------------------------------------------------------
// Tab 3 — Plány (plan summaries, STEM-primary deep-links)
// ---------------------------------------------------------------------------

function PlansTab({ project }: { project: string }) {
  const plansQuery = useQuery({
    queryKey: ['plans', project],
    queryFn: () => getPlans(project),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });

  const plans = plansQuery.data;

  if (!plans) {
    if (plansQuery.isError) {
      return (
        <p data-plans-error className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700">
          Plány se nepodařilo načíst.
        </p>
      );
    }
    return (
      <p data-plans-loading className="text-sm text-slate-400">
        Načítám plány…
      </p>
    );
  }

  if (plans.length === 0) {
    return (
      <p data-plans-empty className="text-sm text-slate-400">
        V projektu zatím není žádný plán.
      </p>
    );
  }

  return (
    <ul className="space-y-1.5" data-plans-list>
      {plans.map((plan) => (
        <li key={plan.planId}>
          <PlanRow project={project} plan={plan} />
        </li>
      ))}
    </ul>
  );
}

function PlanRow({ project, plan }: { project: string; plan: PlanSummary }) {
  return (
    <Link
      // STEM-primary deep-link (the plan STEM is the contract identity, §13.6).
      to={`/p/${project}/plans/${plan.planId}`}
      data-plan-row
      data-plan-id={plan.planId}
      className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm hover:bg-slate-50"
    >
      <span className="font-medium tabular-nums text-slate-800">{plan.planId}</span>
      <span className="truncate text-slate-600">{plan.title}</span>
      <span className="ml-auto text-xs text-slate-500">
        <MetricBadge value={Math.round(plan.progressPct)} unit=" %" /> hotovo
      </span>
      <span className="text-xs text-slate-500">
        AC <MetricBadge value={plan.acPct == null ? null : Math.round(plan.acPct)} unit=" %" nullLabel="neměřeno" />
      </span>
    </Link>
  );
}

// ---------------------------------------------------------------------------
// Tab 4 — Audit (aggregate summary + project-scope trend)
// ---------------------------------------------------------------------------

function AuditTab({ project }: { project: string }) {
  const summaryQuery = useQuery({
    queryKey: ['audit-summary', project],
    queryFn: () => getAuditSummary(project),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });
  const trendQuery = useQuery({
    queryKey: ['audit-trend', project],
    queryFn: () => getAuditTrend(project),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });

  return (
    <div className="space-y-4" data-audit-tab>
      {/* The summary query fails INDEPENDENTLY — its error stays in this tab. */}
      {summaryQuery.data ? (
        <AuditSummaryCard variant="aggregate" summary={summaryQuery.data} />
      ) : summaryQuery.isError ? (
        <p data-audit-summary-error className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700">
          Audit projektu se nepodařilo načíst
        </p>
      ) : (
        <p data-audit-summary-loading className="text-sm text-slate-400">
          Načítám audit…
        </p>
      )}

      {/* The trend query also fails independently. */}
      <Card title="Vývoj skóre auditu">
        {trendQuery.data ? (
          // connectNulls={false} is enforced inside AuditTrendChart — gaps break.
          <AuditTrendChart trend={trendQuery.data} />
        ) : trendQuery.isError ? (
          <p data-audit-trend-error className="text-sm text-amber-700">
            Trend auditu se nepodařilo načíst.
          </p>
        ) : (
          <p className="text-sm text-slate-400">Načítám trend…</p>
        )}
      </Card>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab 5 — Zdraví (compliance / progress / queue health rail)
// ---------------------------------------------------------------------------

function HealthTab({ project }: { project: string }) {
  const detailQuery = useQuery({
    queryKey: ['project-detail', project],
    queryFn: () => getProjectDetail(project),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });
  const complianceQuery = useQuery({
    queryKey: ['compliance', project],
    queryFn: () => getCompliance(project),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });

  const detail = detailQuery.data;
  const compliance = complianceQuery.data;

  return (
    <div className="space-y-4" data-health-tab>
      {/* Compliance health (pass-rate + open violations as retry/hot-spots). */}
      <Card title="Shoda a porušení">
        {compliance ? (
          <div className="space-y-2 text-sm">
            <p>
              Pass-rate{' '}
              <MetricBadge value={Math.round(compliance.passRate * 100)} unit=" %" className="font-semibold" />
              {' · '}
              běhů <MetricBadge value={compliance.totals.runs} />
              {' · '}
              vynucených přepisů <MetricBadge value={compliance.totals.forceOverrides} />
            </p>
            {compliance.violations.length === 0 ? (
              <p data-health-no-violations className="text-slate-400">
                Žádná otevřená porušení.
              </p>
            ) : (
              <ul className="space-y-1" data-health-violations>
                {compliance.violations.slice(0, 8).map((v) => (
                  <li key={`${v.epicId}/${v.runId}`} className="flex items-center gap-2 text-xs">
                    <StatusDot status="selhalo" title="porušení" />
                    <span className="tabular-nums text-slate-700">{v.epicId}</span>
                    <span className="text-slate-400">
                      {v.failures.length} {v.failures.length === 1 ? 'nález' : 'nálezů'}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        ) : complianceQuery.isError ? (
          <p data-health-compliance-error className="text-sm text-amber-700">
            Data o shodě se nepodařilo načíst.
          </p>
        ) : (
          <p className="text-sm text-slate-400">Načítám shodu…</p>
        )}
      </Card>

      {/* Per-EPIC progress bars (run-completion ratio) — honest "bez běhu" track. */}
      <Card title="Postup EPICů">
        {detail ? (
          detail.epics.length === 0 ? (
            <p data-health-epics-empty className="text-sm text-slate-400">
              V projektu zatím není žádný EPIC.
            </p>
          ) : (
            <ul className="space-y-2" data-health-epic-bars>
              {detail.epics.map((epic) => (
                <li key={epic.id} className="flex items-center gap-3 text-xs">
                  <span className="w-28 shrink-0 truncate tabular-nums text-slate-700">{epic.id}</span>
                  <span className="flex-1">
                    <DurationBar
                      durationS={epic.runsTotal > 0 ? epic.runsCompleted : null}
                      maxS={Math.max(1, epic.runsTotal)}
                    />
                  </span>
                  <span className="w-20 shrink-0 text-right tabular-nums text-slate-500">
                    {epic.runsCompleted}/{epic.runsTotal}
                  </span>
                </li>
              ))}
            </ul>
          )
        ) : detailQuery.isError ? (
          <p data-health-detail-error className="text-sm text-amber-700">
            Detail projektu se nepodařilo načíst.
          </p>
        ) : (
          <p className="text-sm text-slate-400">Načítám EPICy…</p>
        )}
      </Card>

      {/* Queue snippet. */}
      <Card title="Fronta">
        {detail ? (
          detail.queue.length === 0 ? (
            <p data-health-queue-empty className="text-sm text-slate-400">
              Ve frontě nic nečeká.
            </p>
          ) : (
            <ul className="space-y-1" data-health-queue>
              {detail.queue.slice(0, 8).map((q) => (
                <li key={q.epicId} className="flex items-center gap-2 text-xs">
                  <StatusDot status="ceka" title="čeká" />
                  <span className="tabular-nums text-slate-700">{q.epicId}</span>
                  <span className="text-slate-400">{q.priority}</span>
                </li>
              ))}
            </ul>
          )
        ) : detailQuery.isError ? (
          <p className="text-sm text-amber-700">Frontu se nepodařilo načíst.</p>
        ) : (
          <p className="text-sm text-slate-400">Načítám frontu…</p>
        )}
      </Card>
    </div>
  );
}
