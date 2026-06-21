import { useMemo } from 'react';
import { useQuery, keepPreviousData } from '@tanstack/react-query';
import type { Project, ActivityEvent, PlanOutcomeAnalytics } from '@aid/contract';
import { getProjects, getActivity, getPlanOutcomes, getExplanations } from '../lib/api';
import { explainEvent, type Dictionary } from '../lib/explain';
import { ProjectTileGrid } from '../components/ProjectTileGrid';
import { PlanOutcomeTable } from '../components/managerial/PlanOutcomeTable';
import { Card } from '../components/managerial/Card';
import { EventRow } from '../components/common/EventRow';
import { InstallPwaButton } from '../components/common/InstallPwaButton';

/** FSM states that mean "PM must decide" — counted in the header summary as "čeká na PM". */
const PM_APPROVAL_STATES = new Set(['DONE']);

/** Genuinely-active FSM states → counted as "běží" (aligns with FSM_STATUS bezi). */
const RUNNING_STATES = new Set(['EXECUTE', 'GATES']);

/**
 * Screen A — the operational cross-project overview at `/prehled` (§ Step 42).
 *
 * The READ-ONLY operational front door (distinct from Screen G's managerial
 * brief at `/`). It answers "what is the fleet doing right now?":
 *
 *   - a header summary line aggregated over every project (count, lifetime runs,
 *     running now, waiting on PM, open violations);
 *   - the cross-project {@link ProjectTileGrid} (the SAME component Screen G
 *     embeds — imported, never re-owned);
 *   - a 5-row "DĚJE SE TEĎ" mini live feed of the newest activity;
 *   - a first-class "Výsledky plánů" section via {@link PlanOutcomeTable}.
 *
 * Four independent queries back the screen so any one failure degrades only its
 * own surface; the others stay usable (live-dashboard resilience):
 *   - `['projects']`               — tiles + header summary (4s refetch)
 *   - `['activity','feed',5]`      — the mini live feed (4s refetch)
 *   - `['explanations']`           — the §6.4 dictionary for narrated events
 *   - `['plan-outcomes']`          — the cross-project plan analytics (15s refetch)
 *
 * Contract note: the plan sketched `useQuery(['plan-outcomes', filters])` with
 * project/outcome/since filter state lifted into the screen. The real built
 * `PlanOutcomeTable` already OWNS its project + outcome filters and JSON export
 * (client-side over the full payload). To avoid double-filtering and respect the
 * existing component contract, the screen fetches the FULL analytics once and
 * lets the table filter — matching the real `getPlanOutcomes()` signature.
 */
export function ScreenA() {
  const projectsQuery = useQuery({
    queryKey: ['projects'],
    queryFn: getProjects,
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });

  const activityQuery = useQuery({
    queryKey: ['activity', 'feed', 5],
    queryFn: () => getActivity({ limit: 5 }),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });

  // The §6.4 dictionary is small + stable; cache it long and reuse across screens.
  const explanationsQuery = useQuery({
    queryKey: ['explanations'],
    queryFn: () => getExplanations('cs'),
    staleTime: 5 * 60_000,
  });

  const outcomesQuery = useQuery({
    queryKey: ['plan-outcomes'],
    queryFn: () => getPlanOutcomes(),
    refetchInterval: 15_000,
    placeholderData: keepPreviousData,
  });

  const projects = projectsQuery.data ?? [];
  const events = activityQuery.data ?? [];
  const dictionary: Dictionary = explanationsQuery.data ?? {};
  const analytics = outcomesQuery.data;

  const summary = useMemo(() => summarise(projects), [projects]);

  return (
    <section className="space-y-4 p-4 sm:p-6" aria-label="Přehled">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-2xl font-semibold text-slate-900">Přehled</h1>
        <InstallPwaButton />
      </header>

      {/* Aggregated summary line over all projects (null-safe). */}
      <p data-summary className="text-sm text-slate-600">
        {projectsQuery.isError && projects.length === 0 ? (
          <span className="text-slate-400">Souhrn nedostupný</span>
        ) : (
          <SummaryLine summary={summary} />
        )}
      </p>

      {/* Project tiles — the shared grid. Errors degrade to a calm retry line. */}
      {projectsQuery.isError && projects.length === 0 ? (
        <p
          data-projects-error
          className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700"
        >
          Seznam projektů se nepodařilo načíst — zkouším znovu.
        </p>
      ) : (
        <ProjectTileGrid projects={projects} />
      )}

      {/* Mini live feed — newest 5 events, narrated. */}
      <Card title="Děje se teď" collapsibleOnMobile>
        {activityQuery.isError && events.length === 0 ? (
          <p data-activity-error className="text-sm text-amber-700">
            Aktivitu se nepodařilo načíst — zkouším znovu.
          </p>
        ) : events.length === 0 ? (
          <p data-activity-empty className="text-sm text-slate-400">
            Zatím se nic neděje.
          </p>
        ) : (
          <div data-activity-feed className="divide-y divide-slate-100">
            {events.slice(0, 5).map((event, i) => (
              <EventRow
                key={eventKey(event, i)}
                event={event}
                explanation={explainEvent(event, dictionary)}
                at={event.ts}
              />
            ))}
          </div>
        )}
      </Card>

      {/* "Výsledky plánů" — first-class cross-project analytics section. */}
      <section aria-label="Výsledky plánů" className="space-y-3">
        {outcomesQuery.isError && !analytics ? (
          <p
            data-outcomes-error
            className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700"
          >
            Výsledky plánů se nepodařilo načíst — zkouším znovu.
          </p>
        ) : analytics ? (
          <>
            {/* Compact totals above the table — five honest outcome buckets. */}
            <PlanTotals analytics={analytics} />

            {/* Partial-coverage warning band naming the affected projects. */}
            {analytics.partialProjects.length > 0 && (
              <p
                data-outcomes-partial
                className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-700"
              >
                Neúplná data pro: {analytics.partialProjects.join(', ')} — některé výsledky mohou být
                neúplné.
              </p>
            )}

            <PlanOutcomeTable analytics={analytics} />
          </>
        ) : (
          <p data-outcomes-loading className="text-sm text-slate-400">
            Načítám výsledky plánů…
          </p>
        )}
      </section>
    </section>
  );
}

/** Aggregated cross-project counters for the header summary line. */
interface FleetSummary {
  projectCount: number;
  totalRuns: number;
  running: number;
  pmApproval: number;
  openViolations: number;
}

/**
 * Aggregate the header summary over all projects. Every read is null-safe:
 * `health.value` may be null (→ ignored, never coerced to 0); `runsTotal` and
 * `openViolations` are summed as honest counts.
 */
function summarise(projects: Project[]): FleetSummary {
  return projects.reduce<FleetSummary>(
    (acc, p) => {
      acc.projectCount += 1;
      acc.totalRuns += p.runsTotal ?? 0;
      if (p.activeRun) {
        // "běží" = genuinely active FSM states only (EXECUTE/GATES → bezi). A DONE
        // run is finished + awaiting PM — it is counted under "čeká na PM", NOT
        // "běží" (counting both would double-label + contradict FSM_STATUS).
        if (RUNNING_STATES.has(p.activeRun.state)) acc.running += 1;
        if (PM_APPROVAL_STATES.has(p.activeRun.state)) acc.pmApproval += 1;
      }
      acc.openViolations += p.health?.openViolations ?? 0;
      return acc;
    },
    { projectCount: 0, totalRuns: 0, running: 0, pmApproval: 0, openViolations: 0 },
  );
}

/** Render the aggregated summary as a Czech "·"-separated line. */
function SummaryLine({ summary }: { summary: FleetSummary }) {
  return (
    <span className="tabular-nums">
      <span data-summary-projects>
        {summary.projectCount} {czechPlural(summary.projectCount, 'projekt', 'projekty', 'projektů')}
      </span>{' '}
      ·{' '}
      <span data-summary-runs>
        {summary.totalRuns} {czechPlural(summary.totalRuns, 'běh', 'běhy', 'běhů')}
      </span>{' '}
      · <span data-summary-running>{summary.running} běží</span> ·{' '}
      <span data-summary-pm>{summary.pmApproval} čeká na PM</span> ·{' '}
      <span data-summary-violations>
        {summary.openViolations}{' '}
        {czechPlural(summary.openViolations, 'porušení', 'porušení', 'porušení')}
      </span>
    </span>
  );
}

/**
 * Compact totals strip above the plan-outcome table — the five honest outcome
 * buckets straight from `analytics.totals` (never derived/zero-substituted).
 */
function PlanTotals({ analytics }: { analytics: PlanOutcomeAnalytics }) {
  const t = analytics.totals;
  const buckets: { key: string; label: string; value: number }[] = [
    { key: 'passed', label: 'prošlo', value: t.passed },
    { key: 'partial', label: 'částečně', value: t.partial },
    { key: 'failed', label: 'selhalo', value: t.failed },
    { key: 'in_progress', label: 'běží', value: t.inProgress },
    { key: 'unverifiable', label: 'nelze ověřit', value: t.unverifiable },
  ];
  return (
    <div data-plan-totals className="flex flex-wrap gap-2 text-xs">
      {buckets.map((b) => (
        <span
          key={b.key}
          data-total={b.key}
          className="inline-flex items-center gap-1 rounded-full border border-slate-200 bg-slate-50 px-2.5 py-1 text-slate-600"
        >
          <span className="font-medium tabular-nums text-slate-800">{b.value}</span>
          {b.label}
        </span>
      ))}
    </div>
  );
}

/** Stable key for a feed event (events carry no id; fall back to ts+event+index). */
function eventKey(event: ActivityEvent, index: number): string {
  return `${event.ts}:${event.event}:${index}`;
}

/** Czech 1 / 2-4 / 5+ plural picker. */
function czechPlural(n: number, one: string, few: string, many: string): string {
  if (n === 1) return one;
  if (n >= 2 && n <= 4) return few;
  return many;
}
