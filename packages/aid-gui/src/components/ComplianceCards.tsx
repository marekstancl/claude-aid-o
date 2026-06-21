import { cn } from '../lib/utils';
import { StatusBadge } from './common/StatusBadge';
import { cellLabel, cellStatus, type ComplianceMatrixData } from './compliance';

interface ComplianceCardsProps {
  data: ComplianceMatrixData;
  className?: string;
  /** Honest empty-state line when there are no rows. */
  emptyLabel?: string;
}

/**
 * §13 Screen E (mobile): the same compliance data as {@link ComplianceMatrix}
 * stacked into per-project Cards (no horizontal scrolling on a phone). Same
 * honesty contract: a `null` cell is "N/A" (grey `necinne`), NEVER 0%/fail.
 */
export function ComplianceCards({ data, className, emptyLabel = 'žádná data o shodě' }: ComplianceCardsProps) {
  if (data.rows.length === 0) {
    return (
      <p data-compliance-cards data-empty className={cn('text-sm text-slate-400', className)}>
        {emptyLabel}
      </p>
    );
  }

  return (
    <div data-compliance-cards className={cn('flex flex-col gap-3', className)}>
      {data.rows.map((row) => (
        <section
          key={row.projectId}
          data-project={row.projectId}
          className="rounded-lg border border-slate-200 bg-white p-3"
        >
          <h3 className="mb-2 text-sm font-semibold text-slate-700">{row.projectName}</h3>
          <dl className="flex flex-col gap-1.5">
            {row.cells.map((cell) => (
              <div
                key={cell.check}
                data-check={cell.check}
                data-state={cell.state ?? 'null'}
                className="flex items-center justify-between gap-3"
                title={cell.evidence ?? undefined}
              >
                <dt className="text-sm text-slate-500">{cell.check}</dt>
                <dd>
                  <StatusBadge status={cellStatus(cell.state)} label={cellLabel(cell.state)} />
                </dd>
              </div>
            ))}
          </dl>
        </section>
      ))}
    </div>
  );
}
