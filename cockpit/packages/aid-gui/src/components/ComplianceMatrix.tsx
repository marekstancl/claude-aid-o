import { cn } from '../lib/utils';
import { StatusBadge } from './common/StatusBadge';
import { cellLabel, cellStatus, type ComplianceMatrixData } from './compliance';

interface ComplianceMatrixProps {
  data: ComplianceMatrixData;
  className?: string;
  /** Honest empty-state line when there are no rows (never a blank grid). */
  emptyLabel?: string;
}

/**
 * §13 Screen E (desktop): projects × checks grid of {@link StatusBadge} cells.
 *
 * Honesty contract: a cell whose state is `null` (no recorded result — e.g.
 * `compliance.json` absent for that project) renders "N/A" in the grey
 * `necinne` token, NEVER 0% and NEVER a fabricated pass/fail.
 */
export function ComplianceMatrix({ data, className, emptyLabel = 'žádná data o shodě' }: ComplianceMatrixProps) {
  if (data.rows.length === 0) {
    return (
      <p data-compliance-matrix data-empty className={cn('text-sm text-slate-400', className)}>
        {emptyLabel}
      </p>
    );
  }

  return (
    <div data-compliance-matrix className={cn('overflow-x-auto', className)}>
      <table className="w-full border-collapse text-sm">
        <thead>
          <tr>
            <th className="sticky left-0 z-10 bg-white px-3 py-2 text-left font-semibold text-slate-600">
              Projekt
            </th>
            {data.checks.map((check) => (
              <th key={check} className="px-3 py-2 text-left font-medium text-slate-500">
                {check}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {data.rows.map((row) => (
            <tr key={row.projectId} data-project={row.projectId} className="border-t border-slate-100">
              <th
                scope="row"
                className="sticky left-0 z-10 bg-white px-3 py-2 text-left font-medium text-slate-700"
              >
                {row.projectName}
              </th>
              {row.cells.map((cell) => (
                <td
                  key={cell.check}
                  data-check={cell.check}
                  data-state={cell.state ?? 'null'}
                  className="px-3 py-2"
                  title={cell.evidence ?? undefined}
                >
                  <StatusBadge status={cellStatus(cell.state)} label={cellLabel(cell.state)} />
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
