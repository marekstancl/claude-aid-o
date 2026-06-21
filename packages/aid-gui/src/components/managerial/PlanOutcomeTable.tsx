import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Download, AlertTriangle } from 'lucide-react';
import type {
  PlanOutcomeAnalytics,
  PlanOutcomeSummary,
  PlanOutcome,
  StatusKey,
} from '@aid/contract';
import { cn } from '../../lib/utils';
import { Card } from './Card';
import { StatusBadge } from '../common/StatusBadge';
import { useIsMobile } from '../shell/useIsMobile';

/**
 * §13.12 PlanOutcome → §6.2 token + Czech word. All five outcomes get BOTH a
 * word and an icon (via StatusBadge), so colour is never the only signal:
 *   failed → selhalo, partial → pozor, in_progress → běží,
 *   unverifiable → čeká, passed → prošlo.
 */
const OUTCOME_STATUS: Record<PlanOutcome, { status: StatusKey; label: string }> = {
  failed: { status: 'selhalo', label: 'selhalo' },
  partial: { status: 'pozor', label: 'pozor' },
  in_progress: { status: 'bezi', label: 'běží' },
  unverifiable: { status: 'ceka', label: 'čeká' },
  passed: { status: 'proslo', label: 'prošlo' },
};

/** Attention-first ordering weight: worse/needs-a-look outcomes sort to the top. */
const OUTCOME_WEIGHT: Record<PlanOutcome, number> = {
  failed: 0,
  partial: 1,
  in_progress: 2,
  unverifiable: 3,
  passed: 4,
};

const ALL_OUTCOMES: PlanOutcome[] = ['failed', 'partial', 'in_progress', 'unverifiable', 'passed'];

interface PlanOutcomeTableProps {
  analytics: PlanOutcomeAnalytics;
  /**
   * Deep-link builder for a plan row. MUST receive the plan STEM (never the bare
   * number — the API answers a bare number with HTTP 409 AMBIGUOUS_PLAN_NUMBER).
   * Defaults to `/p/:project/plan/:stem`.
   */
  planHref?: (projectId: string, planStem: string) => string;
  className?: string;
}

/**
 * §13.12 cross-project plan-outcome table. Responsive (table on desktop, cards
 * on mobile). Attention-first ordering, project + outcome filters, and a
 * client-side JSON export of the CURRENTLY-FILTERED analytics via a browser Blob
 * (no server write).
 *
 * Contract-drift invariants (Phases 1-4 REOPEN):
 *  - every row is KEYED and DISPLAYED by its plan STEM (`planId`), so two plans
 *    that share a number but have distinct stems render as DISTINCT rows.
 *  - a row whose `ambiguousNumber` is true gets a visible marker.
 *  - the row's plan link href uses the STEM, never the bare number.
 *  - member-less plans (`outcome:'unverifiable'`) still render.
 *
 * Honesty: `checkpointRetries.unknownCheckpoints > 0` shows a visible `?` plus
 * "část CP opakování není dohledatelná" — the unknown is never substituted with 0.
 */
export function PlanOutcomeTable({
  analytics,
  planHref = (projectId, planStem) => `/p/${projectId}/plan/${encodeURIComponent(planStem)}`,
  className,
}: PlanOutcomeTableProps) {
  const isMobile = useIsMobile();
  const [projectFilter, setProjectFilter] = useState<string>('all');
  const [outcomeFilter, setOutcomeFilter] = useState<PlanOutcome | 'all'>('all');

  const projects = useMemo(() => {
    const set = new Set(analytics.plans.map((p) => p.projectId));
    return [...set].sort();
  }, [analytics.plans]);

  const filtered = useMemo(() => {
    const rows = analytics.plans.filter(
      (p) =>
        (projectFilter === 'all' || p.projectId === projectFilter) &&
        (outcomeFilter === 'all' || p.outcome === outcomeFilter),
    );
    // Attention-first: worst outcome first, then most-recent activity.
    return [...rows].sort((a, b) => {
      const w = OUTCOME_WEIGHT[a.outcome] - OUTCOME_WEIGHT[b.outcome];
      if (w !== 0) return w;
      return (b.lastActivityAt ?? '').localeCompare(a.lastActivityAt ?? '');
    });
  }, [analytics.plans, projectFilter, outcomeFilter]);

  /** Build the filtered analytics payload and download it as JSON (no server). */
  const exportJson = () => {
    const payload: PlanOutcomeAnalytics = buildFilteredAnalytics(analytics, filtered);
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `plan-outcomes-${analytics.generatedAt.slice(0, 10)}.json`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  };

  return (
    <Card
      title="Výsledky plánů napříč projekty"
      action={
        <button
          type="button"
          data-export-json
          onClick={exportJson}
          className="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 px-2.5 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
        >
          <Download aria-hidden className="h-3.5 w-3.5" />
          Export JSON
        </button>
      }
      className={className}
    >
      <div className="space-y-3">
        {/* Filters. */}
        <div className="flex flex-wrap items-center gap-3">
          <label className="flex items-center gap-1.5 text-xs text-slate-500">
            Projekt
            <select
              data-filter-project
              value={projectFilter}
              onChange={(e) => setProjectFilter(e.target.value)}
              className="rounded-md border border-slate-200 px-2 py-1 text-xs text-slate-700"
            >
              <option value="all">vše</option>
              {projects.map((p) => (
                <option key={p} value={p}>
                  {p}
                </option>
              ))}
            </select>
          </label>
          <label className="flex items-center gap-1.5 text-xs text-slate-500">
            Výsledek
            <select
              data-filter-outcome
              value={outcomeFilter}
              onChange={(e) => setOutcomeFilter(e.target.value as PlanOutcome | 'all')}
              className="rounded-md border border-slate-200 px-2 py-1 text-xs text-slate-700"
            >
              <option value="all">vše</option>
              {ALL_OUTCOMES.map((o) => (
                <option key={o} value={o}>
                  {OUTCOME_STATUS[o].label}
                </option>
              ))}
            </select>
          </label>
          <span className="ml-auto text-xs tabular-nums text-slate-400">{filtered.length} plánů</span>
        </div>

        {filtered.length === 0 ? (
          <p data-plan-outcome-empty className="text-sm text-slate-500">
            žádné plány pro tento filtr
          </p>
        ) : isMobile ? (
          <ul className="space-y-2" data-plan-outcome-cards>
            {filtered.map((row) => (
              <PlanOutcomeCard key={row.planId} row={row} planHref={planHref} />
            ))}
          </ul>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm" data-plan-outcome-table>
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs uppercase tracking-wide text-slate-400">
                  <th className="py-1.5 pr-3 font-medium">Projekt</th>
                  <th className="py-1.5 pr-3 font-medium">Plán</th>
                  <th className="py-1.5 pr-3 font-medium">Výsledek</th>
                  <th className="py-1.5 pr-3 font-medium">EPICy</th>
                  <th className="py-1.5 pr-3 font-medium">Selhání</th>
                  <th className="py-1.5 pr-3 font-medium">Retry</th>
                  <th className="py-1.5 pr-3 font-medium">Eskalace</th>
                  <th className="py-1.5 pr-3 font-medium">Override</th>
                  <th className="py-1.5 font-medium">Poslední změna</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((row) => (
                  <PlanOutcomeRow key={row.planId} row={row} planHref={planHref} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </Card>
  );
}

/** Total checkpoint retries rendered honestly: known count, plus `?` when some are unknown. */
function RetryCell({ row }: { row: PlanOutcomeSummary }) {
  const { knownTotal, unknownCheckpoints } = row.checkpointRetries;
  if (unknownCheckpoints > 0) {
    return (
      <span
        data-retry="unknown"
        title="část CP opakování není dohledatelná"
        className="inline-flex items-center gap-1 tabular-nums text-amber-700"
      >
        {knownTotal}
        <span className="font-semibold">?</span>
      </span>
    );
  }
  return <span className="tabular-nums text-slate-700">{knownTotal}</span>;
}

/** Plan-stem cell: stem as the display + link target, with an ambiguousNumber marker. */
function PlanStemCell({
  row,
  planHref,
}: {
  row: PlanOutcomeSummary;
  planHref: (projectId: string, planStem: string) => string;
}) {
  return (
    <span className="flex items-center gap-1.5">
      <Link
        data-plan-link
        data-stem={row.planId}
        to={planHref(row.projectId, row.planId)}
        className="font-mono text-xs text-sky-700 hover:underline"
        title={row.title}
      >
        {row.planId}
      </Link>
      {row.ambiguousNumber && (
        <span
          data-ambiguous-number
          title="číslo plánu sdílí víc plánů - používej celý název (stem)"
          className="inline-flex items-center gap-0.5 rounded-full border border-amber-300 bg-amber-50 px-1.5 py-0.5 text-[10px] font-medium text-amber-700"
        >
          <AlertTriangle aria-hidden className="h-3 w-3" />
          dvojí číslo
        </span>
      )}
    </span>
  );
}

function PlanOutcomeRow({
  row,
  planHref,
}: {
  row: PlanOutcomeSummary;
  planHref: (projectId: string, planStem: string) => string;
}) {
  const outcome = OUTCOME_STATUS[row.outcome];
  return (
    <tr data-plan-row={row.planId} className="border-b border-slate-100 align-top">
      <td className="py-1.5 pr-3 text-slate-600">{row.projectId}</td>
      <td className="py-1.5 pr-3">
        <PlanStemCell row={row} planHref={planHref} />
      </td>
      <td className="py-1.5 pr-3">
        <StatusBadge status={outcome.status} label={outcome.label} />
      </td>
      <td className="py-1.5 pr-3 tabular-nums text-slate-700">
        {row.epicsDone}/{row.epicsTotal}
      </td>
      <td className="py-1.5 pr-3 tabular-nums text-slate-700">{row.failedRuns}</td>
      <td className="py-1.5 pr-3">
        <RetryCell row={row} />
      </td>
      <td className="py-1.5 pr-3 tabular-nums text-slate-700">{row.escalations}</td>
      <td className="py-1.5 pr-3 tabular-nums text-slate-700">{row.forceOverrides}</td>
      <td className="py-1.5 tabular-nums text-slate-400">{row.lastActivityAt ?? '—'}</td>
    </tr>
  );
}

function PlanOutcomeCard({
  row,
  planHref,
}: {
  row: PlanOutcomeSummary;
  planHref: (projectId: string, planStem: string) => string;
}) {
  const outcome = OUTCOME_STATUS[row.outcome];
  return (
    <li data-plan-card={row.planId} className="rounded-lg border border-slate-100 p-2">
      <div className="mb-1 flex items-center justify-between gap-2">
        <PlanStemCell row={row} planHref={planHref} />
        <StatusBadge status={outcome.status} label={outcome.label} />
      </div>
      <div className="text-xs text-slate-500">{row.projectId}</div>
      <div className="mt-1 grid grid-cols-2 gap-x-3 gap-y-0.5 text-xs text-slate-600">
        <span className="tabular-nums">
          EPICy: {row.epicsDone}/{row.epicsTotal}
        </span>
        <span className="tabular-nums">Selhání: {row.failedRuns}</span>
        <span className="flex items-center gap-1">
          Retry: <RetryCell row={row} />
        </span>
        <span className="tabular-nums">Eskalace: {row.escalations}</span>
        <span className="tabular-nums">Override: {row.forceOverrides}</span>
        <span className="tabular-nums">{row.lastActivityAt ?? '—'}</span>
      </div>
    </li>
  );
}

/**
 * Rebuild a {@link PlanOutcomeAnalytics} payload over the filtered rows, with
 * `totals` recomputed from those rows so the exported JSON is self-consistent.
 * Exported for the JSON-export test.
 */
export function buildFilteredAnalytics(
  source: PlanOutcomeAnalytics,
  plans: PlanOutcomeSummary[],
): PlanOutcomeAnalytics {
  const totals = {
    plans: plans.length,
    passed: plans.filter((p) => p.outcome === 'passed').length,
    partial: plans.filter((p) => p.outcome === 'partial').length,
    failed: plans.filter((p) => p.outcome === 'failed').length,
    inProgress: plans.filter((p) => p.outcome === 'in_progress').length,
    unverifiable: plans.filter((p) => p.outcome === 'unverifiable').length,
    failedRuns: sum(plans, (p) => p.failedRuns),
    gateFailures: sum(plans, (p) => p.gateFailures),
    gateRetries: sum(plans, (p) => p.gateRetries),
    escalations: sum(plans, (p) => p.escalations),
    forceOverrides: sum(plans, (p) => p.forceOverrides),
  };
  const partialProjects = [...new Set(plans.filter((p) => p.dataPartial).map((p) => p.projectId))].sort();
  return { generatedAt: source.generatedAt, plans, totals, partialProjects };
}

function sum<T>(rows: T[], pick: (row: T) => number): number {
  return rows.reduce((acc, row) => acc + pick(row), 0);
}

export { OUTCOME_STATUS, OUTCOME_WEIGHT };
