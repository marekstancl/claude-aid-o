import { useMemo, useState } from 'react';
import { useQuery, keepPreviousData } from '@tanstack/react-query';
import type { ComplianceView } from '@aid/contract';
import { getComplianceAll, getProjects } from '../lib/api';
import { cn } from '../lib/utils';
import { useAidSocket } from '../hooks/useAidSocket';
import { useIsMobile } from '../components/shell/useIsMobile';
import { useProjects } from '../components/shell/ProjectsContext';
import { Card } from '../components/managerial/Card';
import { MetricBadge } from '../components/common/MetricBadge';
import { StatusBadge } from '../components/common/StatusBadge';
import { ComplianceMatrix } from '../components/ComplianceMatrix';
import { ComplianceCards } from '../components/ComplianceCards';
import {
  type ComplianceMatrixData,
  type ComplianceMatrixRow,
  type ComplianceCellState,
} from '../components/compliance';

/**
 * Screen E — cross-project compliance (§13) at `/compliance`.
 *
 * Replaces the Phase-5 STUB. It renders the ecosystem-wide {@link ComplianceView}
 * (`getComplianceAll()`, `scope:'all'`) three ways:
 *   - an ecosystem-score header ("Skóre ekosystému 91 % · 3 blokující · …");
 *   - a projects × checks {@link ComplianceMatrix} on desktop / per-project
 *     {@link ComplianceCards} on mobile, with a "podle projektu / podle checku"
 *     orientation toggle;
 *   - an "AKTIVNÍ PORUŠENÍ" list with force-override counts + SYSTEMATIC badges.
 *
 * Honesty contract (§4.5/§5.7): a project with no recorded result for a check is
 * a `null` cell → "N/A" (grey), NEVER 0% and NEVER a fabricated fail. A SYSTEMATIC
 * badge fires only on a genuine repeated bypass per §4.5 (avg>1 / max>3 / ≥30%
 * forced, derived from totals + per-violation counts). A malformed/partial
 * compliance on one project degrades to "—"/N/A cells, never a thrown matrix.
 */
export function ScreenE() {
  // Cross-project compliance changes ride the `compliance` topic; the app-shell
  // socket invalidates the read-model keys. Belt-and-suspenders + the 4s poll.
  useAidSocket({ topics: [], projects: [] });

  const { projects: shellProjects } = useProjects();
  const isMobile = useIsMobile();

  const complianceQuery = useQuery({
    queryKey: ['compliance', 'all'],
    queryFn: () => getComplianceAll(),
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });

  // Project list backs the matrix rows (so a clean project with no violation
  // still appears, as an all-"N/A" row — never silently dropped).
  const projectsQuery = useQuery({
    queryKey: ['projects'],
    queryFn: getProjects,
    staleTime: 30_000,
    enabled: shellProjects.length === 0,
  });

  const view = complianceQuery.data;
  const projectIds = useMemo(() => {
    const source = shellProjects.length > 0 ? shellProjects : (projectsQuery.data ?? []);
    return source.map((p) => ({ id: p.id, name: p.name }));
  }, [shellProjects, projectsQuery.data]);

  // ── orientation toggle: rows = projects (default) | rows = checks ──────────
  const [byCheck, setByCheck] = useState(false);
  const [violationsOnly, setViolationsOnly] = useState(false);

  // getComplianceAll failure → calm retry (last-good buffer stays via keepPreviousData).
  if (!view) {
    if (complianceQuery.isError) {
      return (
        <section className="space-y-4 p-4 sm:p-6" aria-label="Compliance">
          <h1 className="text-2xl font-semibold text-slate-900">Compliance</h1>
          <div
            data-compliance-error
            className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700"
          >
            Compliance se nepodařilo načíst — zkouším znovu.
          </div>
        </section>
      );
    }
    return (
      <section className="space-y-4 p-4 sm:p-6" aria-label="Compliance">
        <h1 className="text-2xl font-semibold text-slate-900">Compliance</h1>
        <p data-compliance-loading className="text-sm text-slate-400">
          Načítám shodu…
        </p>
      </section>
    );
  }

  const matrix = buildMatrix(view, projectIds, byCheck, violationsOnly);

  return (
    <section className="space-y-4 p-4 sm:p-6" aria-label="Compliance">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-2xl font-semibold text-slate-900">Compliance</h1>
      </header>

      <EcosystemHeader view={view} />

      {/* ── orientation + filter controls ────────────────────────────────── */}
      <div data-controls className="flex flex-wrap items-center gap-1.5">
        <SegButton active={!byCheck} onClick={() => setByCheck(false)} data-view="project">
          podle projektu
        </SegButton>
        <SegButton active={byCheck} onClick={() => setByCheck(true)} data-view="check">
          podle checku
        </SegButton>
        <span className="mx-1 h-5 w-px bg-slate-200" aria-hidden />
        <SegButton
          active={violationsOnly}
          onClick={() => setViolationsOnly((v) => !v)}
          data-violations-only
        >
          jen porušení
        </SegButton>
      </div>

      {/* ── matrix (desktop) / cards (mobile) ────────────────────────────── */}
      <Card title={byCheck ? 'Shoda — podle checku' : 'Shoda — podle projektu'}>
        {isMobile ? (
          <ComplianceCards data={matrix} emptyLabel="žádná data o shodě napříč projekty" />
        ) : (
          <ComplianceMatrix data={matrix} emptyLabel="žádná data o shodě napříč projekty" />
        )}
      </Card>

      {/* ── active violations ────────────────────────────────────────────── */}
      <ViolationsList view={view} />
    </section>
  );
}

// ---------------------------------------------------------------------------
// Ecosystem-score header — "Skóre ekosystému 91 % · 3 blokující · 5 poznámek"
// ---------------------------------------------------------------------------

function EcosystemHeader({ view }: { view: ComplianceView }) {
  // §5.7 honesty: the headline score is an envelope — `value:null` → "N/A", never 0%.
  const score = view.fsmAdherenceScore;
  const scorePct = score.value;

  // Blocking vs advisory failure counts across every violation.
  let blocking = 0;
  let advisory = 0;
  for (const v of view.violations) {
    for (const f of v.failures) {
      if (f.severity === 'blocking') blocking += 1;
      else advisory += 1;
    }
  }

  return (
    <div data-ecosystem-header className="space-y-1">
      <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-slate-700">
        <span className="font-semibold text-slate-900">Skóre ekosystému</span>
        {/* null score → "N/A" (never 0 %). */}
        <MetricBadge value={scorePct} unit=" %" nullLabel="N/A" className="font-semibold" />
        {score.partial && (
          <span data-score-partial className="text-xs text-amber-600">
            (neúplná data)
          </span>
        )}
        <span aria-hidden>·</span>
        <span data-blocking-count className="tabular-nums">
          {blocking} blokující
        </span>
        <span aria-hidden>·</span>
        <span data-advisory-count className="tabular-nums">
          {advisory} {advisory === 1 ? 'poznámka' : advisory >= 2 && advisory <= 4 ? 'poznámky' : 'poznámek'}
        </span>
      </p>
      <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-slate-500">
        <span>
          {/* pass-rate is a ratio 0..1; render as a % but honest about 0 vs absence
              of runs (no runs → "N/A", never a fabricated 0 % pass). */}
          Pass-rate{' '}
          <MetricBadge
            value={view.totals.runs > 0 ? Math.round(view.passRate * 100) : null}
            unit=" %"
            nullLabel="N/A"
          />
        </span>
        <span aria-hidden>·</span>
        <span>
          běhů <MetricBadge value={view.totals.runs} />
        </span>
        <span aria-hidden>·</span>
        <span>
          vynucených přepisů <MetricBadge value={view.totals.forceOverrides} />
        </span>
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Matrix folding — ComplianceView → projects × checks ComplianceMatrixData
// ---------------------------------------------------------------------------

/**
 * Fold the cross-project {@link ComplianceView} into a presentational matrix.
 *
 * The view surfaces FAIL runs only (`violations`), each with structured
 * `failures[].check`. So a cell is honest:
 *   - `fail` when that project has a violation failing that check;
 *   - `null` ("N/A") otherwise — we never fabricate a `pass` the view does not
 *     assert, and never a `0%`.
 *
 * `byCheck` transposes the grid (rows = checks, columns = projects).
 * `violationsOnly` drops rows that have no `fail` cell (all-"N/A" rows), so the
 * grid collapses to just the projects/checks that actually have a violation.
 */
function buildMatrix(
  view: ComplianceView,
  projects: { id: string; name: string }[],
  byCheck: boolean,
  violationsOnly: boolean,
): ComplianceMatrixData {
  // The set of project ids = the project list ∪ any project that has a violation.
  const projectName = new Map<string, string>();
  for (const p of projects) projectName.set(p.id, p.name);
  for (const v of view.violations) if (!projectName.has(v.projectId)) projectName.set(v.projectId, v.projectId);

  // The check columns = the union of every failing check across violations.
  const checks = new Set<string>();
  // project → check → cell state (only "fail" is ever asserted; absence → null).
  const failByProject = new Map<string, Map<string, ComplianceCellState>>();
  for (const v of view.violations) {
    let row = failByProject.get(v.projectId);
    if (!row) {
      row = new Map();
      failByProject.set(v.projectId, row);
    }
    for (const f of v.failures) {
      if (typeof f.check !== 'string' || f.check.length === 0) continue; // malformed → skip, not throw
      checks.add(f.check);
      row.set(f.check, 'fail');
    }
  }

  const checkList = [...checks].sort();
  const projectList = [...projectName.keys()].sort();

  const hasFail = (cells: { state: ComplianceCellState }[]): boolean =>
    cells.some((c) => c.state === 'fail');

  if (!byCheck) {
    // rows = projects, columns = checks
    let rows: ComplianceMatrixRow[] = projectList.map((pid) => {
      const fails = failByProject.get(pid);
      return {
        projectId: pid,
        projectName: projectName.get(pid) ?? pid,
        cells: checkList.map((check) => ({
          check,
          state: fails?.get(check) ?? null, // null → "N/A", never 0%/fail
        })),
      };
    });
    if (violationsOnly) rows = rows.filter((r) => hasFail(r.cells));
    return { checks: checkList, rows };
  }

  // rows = checks, columns = projects (transposed). The component's column header
  // is `checks`, and each row's cell `.check` is the column id — so to transpose
  // we put project ids in `checks` and check ids as the row key.
  let rows: ComplianceMatrixRow[] = checkList.map((check) => ({
    projectId: check,
    projectName: check,
    cells: projectList.map((pid) => ({
      check: pid,
      state: failByProject.get(pid)?.get(check) ?? null,
    })),
  }));
  if (violationsOnly) rows = rows.filter((r) => hasFail(r.cells));
  return { checks: projectList, rows };
}

// ---------------------------------------------------------------------------
// Active violations list — force-override counts + SYSTEMATIC badges
// ---------------------------------------------------------------------------

/**
 * §4.5 SYSTEMATIC force-override detection.
 *
 * The fine §4.5 ecosystem heuristic is "avg overrides per run > 1 OR a single run
 * with > 3 OR ≥30% of runs forced". We derive:
 *   - `ecosystem` from `totals` (avg = forceOverrides/runs, ratio = forcedRuns
 *     proxied by forceOverrides/runs since the view does not carry forcedRunCount),
 *   - a PER-violation flag from its own `forceOverrideCount` (≥3 = a clearly
 *     repeated bypass — the server's single-run proxy in build-brief.ts).
 *
 * A one-off override (count 1-2) is NOT systematic → just "pozor".
 */
function isSystematicViolation(forceOverrideCount: number): boolean {
  return forceOverrideCount >= 3;
}

function isEcosystemSystematic(view: ComplianceView): boolean {
  const { runs, forceOverrides } = view.totals;
  if (runs <= 0) return false;
  const avg = forceOverrides / runs;
  if (avg > 1) return true;
  // max single-run override across violations.
  const maxSingle = view.violations.reduce((m, v) => Math.max(m, v.forceOverrideCount), 0);
  if (maxSingle > 3) return true;
  // ≥30% forced (proxied by forceOverrides/runs — a conservative upper bound when
  // a run can only force once; never under-reports a genuine systematic pattern).
  if (forceOverrides / runs >= 0.3) return true;
  return false;
}

function ViolationsList({ view }: { view: ComplianceView }) {
  const ecosystemSystematic = isEcosystemSystematic(view);
  const violations = view.violations;

  return (
    <Card
      title="Aktivní porušení"
      action={
        ecosystemSystematic ? (
          <span
            data-ecosystem-systematic
            className="rounded-full border border-red-300 bg-red-50 px-2 py-0.5 text-xs font-semibold text-red-700"
            title="Kontroly se obcházejí systematicky napříč ekosystémem (§4.5)."
          >
            SYSTEMATIC
          </span>
        ) : null
      }
    >
      {violations.length === 0 ? (
        <p data-violations-empty className="text-sm text-slate-400">
          Žádná aktivní porušení napříč projekty.
        </p>
      ) : (
        <ul data-violations className="space-y-2">
          {violations.map((v) => {
              const systematic = isSystematicViolation(v.forceOverrideCount);
              const hasOverride = v.forceOverrideCount > 0;
              return (
                <li
                  key={`${v.projectId}/${v.epicId}/${v.runId}`}
                  data-violation
                  data-project={v.projectId}
                  data-systematic={systematic ? 'true' : 'false'}
                  className="rounded-lg border border-slate-200 bg-white p-3"
                >
                  <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
                    <StatusBadge status="selhalo" label="selhalo" />
                    <span className="font-medium tabular-nums text-slate-800">{v.projectId}</span>
                    <span className="text-slate-400">·</span>
                    <span className="tabular-nums text-slate-600">{v.epicId}</span>
                    <span className="text-xs text-slate-400">({v.runId})</span>

                    {hasOverride && (
                      <span
                        data-force-override
                        className="ml-auto rounded-full border border-amber-300 bg-amber-50 px-2 py-0.5 text-xs tabular-nums text-amber-700"
                        title="Počet vynucených přepisů (force-override) v tomto běhu."
                      >
                        force-override {v.forceOverrideCount}
                      </span>
                    )}

                    {systematic ? (
                      <span
                        data-systematic-badge
                        className="rounded-full border border-red-300 bg-red-50 px-2 py-0.5 text-xs font-semibold text-red-700"
                        title="Opakované obcházení kontrol (≥3) — systematické (§4.5)."
                      >
                        SYSTEMATIC
                      </span>
                    ) : hasOverride ? (
                      <span
                        data-oneoff-badge
                        className="rounded-full border border-amber-300 bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-700"
                        title="Jednorázový přepis — pozor, ne systematické."
                      >
                        pozor
                      </span>
                    ) : null}
                  </div>

                  {v.failures.length > 0 && (
                    <ul className="mt-2 space-y-1" data-violation-failures>
                      {v.failures.map((f, i) => (
                        <li
                          key={`${f.check}:${i}`}
                          data-check={f.check}
                          data-severity={f.severity}
                          className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs"
                        >
                          <StatusBadge
                            status={f.severity === 'blocking' ? 'zablokovano' : 'pozor'}
                            label={f.severity === 'blocking' ? 'blokující' : 'doporučení'}
                          />
                          <span className="font-medium text-slate-700">{f.check}</span>
                          <span className="text-slate-500">{f.evidence}</span>
                        </li>
                      ))}
                    </ul>
                  )}
                </li>
              );
            })}
        </ul>
      )}

      <p className="mt-2 text-sm text-slate-500">
        Porušení = běh, který skončil neshodou s pravidly pipeline. „force-override" je počet ručních
        přepisů kontrol; opakované přepisy (≥3) jsou označeny jako SYSTEMATIC.
      </p>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Segmented-control button
// ---------------------------------------------------------------------------

function SegButton({
  active,
  onClick,
  children,
  ...rest
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
} & React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="button"
      aria-pressed={active}
      onClick={onClick}
      className={cn(
        'min-h-[36px] rounded-lg border px-3 text-xs font-medium',
        active
          ? 'border-slate-900 bg-slate-900 text-white'
          : 'border-slate-200 bg-white text-slate-600 hover:bg-slate-50',
      )}
      {...rest}
    >
      {children}
    </button>
  );
}
