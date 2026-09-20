import type { AuditSummary, AuditCategoryScore, StatusKey } from '@aid/contract';
import { cn } from '../../lib/utils';
import { Card } from './Card';
import { StatusBadge } from '../common/StatusBadge';
import { RawMarkdownDialog } from './RawMarkdownDialog';

/** Aggregate-scope summary carries provenance fields beyond the base AuditSummary. */
type AggregateAuditSummary = AuditSummary & {
  scoredEpicCount: number;
  medianEpicId: string | null;
};

interface AuditSummaryCardProps {
  summary: AuditSummary | AggregateAuditSummary;
  /**
   * - `run` (default) → a single run's audit.
   * - `boundary` → the plan-boundary auditor run.
   * - `aggregate` → project/plan aggregate (shows provenance + sparse warning).
   */
  variant?: 'run' | 'boundary' | 'aggregate';
  /**
   * Run-scope coordinates for fetching the audit-report.md artifact via the
   * hardened /file endpoint. If omitted, the raw trigger is not shown.
   */
  projectId?: string;
  epicId?: string;
  runId?: string;
  className?: string;
}

const VARIANT_TITLE: Record<NonNullable<AuditSummaryCardProps['variant']>, string> = {
  run: 'Audit běhu',
  boundary: 'Audit na hranici plánu',
  aggregate: 'Souhrnný audit',
};

/** §6.2 token for a /100 score band (drives the score badge colour). */
function scoreStatus(score: number): StatusKey {
  if (score >= 80) return 'proslo';
  if (score >= 50) return 'pozor';
  return 'selhalo';
}

function isAggregate(s: AuditSummary | AggregateAuditSummary): s is AggregateAuditSummary {
  return typeof (s as AggregateAuditSummary).scoredEpicCount === 'number';
}

/**
 * §13.5 structured audit summary. Renders an honest skeleton in every degraded
 * shape:
 *  - `present:false` → "auditor zatím neběžel".
 *  - `overallScore:null` → a grey "bez skóre" chip (never a fabricated 0).
 *  - `blockingFindings:null` → "nezjištěno" (never "false"/"ne").
 *  - aggregate `scoredEpicCount===0` → "žádné audity v projektu" (no synthesized
 *    mean); `scoredEpicCount===1` → a `concept:aggregate_audit_sparse` warning.
 *
 * The raw `.md` (audit-report.md) opens lazily in a `RawMarkdownDialog` via
 * the hardened /file endpoint; a fetch failure degrades inside that drawer and
 * leaves this summary intact. When run coords are absent, the raw trigger is
 * not shown.
 */
export function AuditSummaryCard({
  summary,
  variant = 'run',
  projectId,
  epicId,
  runId,
  className,
}: AuditSummaryCardProps) {
  const aggregate = isAggregate(summary) ? summary : null;

  // Aggregate with no scored EPIC → no honest mean to show.
  if (variant === 'aggregate' && aggregate && aggregate.scoredEpicCount === 0) {
    return (
      <Card title={VARIANT_TITLE.aggregate} className={className}>
        <p data-audit-empty className="text-sm text-slate-500">
          žádné audity v projektu
        </p>
      </Card>
    );
  }

  if (!summary.present) {
    return (
      <Card title={VARIANT_TITLE[variant]} className={className}>
        <p data-audit-absent className="text-sm text-slate-500">
          auditor zatím neběžel
        </p>
      </Card>
    );
  }

  return (
    <Card
      title={VARIANT_TITLE[variant]}
      action={
        summary.rawRelPath && projectId && epicId && runId ? (
          <RawMarkdownDialog
            projectId={projectId}
            epicId={epicId}
            runId={runId}
            name="audit-report.md"
            title="Audit (zdroj)"
          />
        ) : undefined
      }
      className={className}
    >
      <div className="space-y-3">
        {/* Score + blocking-findings chips. */}
        <div className="flex flex-wrap items-center gap-2">
          {summary.overallScore == null ? (
            <span data-audit-score="null" className="text-sm text-slate-400">
              bez skóre
            </span>
          ) : (
            <StatusBadge
              status={scoreStatus(summary.overallScore)}
              label={`${summary.overallScore}/100`}
              className="font-semibold tabular-nums"
            />
          )}

          <BlockingChip value={summary.blockingFindings} />

          {variant === 'aggregate' && aggregate && (
            <span data-audit-provenance className="text-xs text-slate-400">
              {aggregate.medianEpicId ? `z EPICu ${aggregate.medianEpicId}` : 'agregát'} · ze{' '}
              {aggregate.scoredEpicCount} auditovaných
            </span>
          )}
        </div>

        {/* Sparse-aggregate warning: a single scored EPIC is not a reliable mean. */}
        {variant === 'aggregate' && aggregate && aggregate.scoredEpicCount === 1 && (
          <p data-audit-sparse className="text-xs text-amber-700">
            Souhrnný audit z 1 EPIC - málo auditů na spolehlivý průměr.
          </p>
        )}

        {/* Deterministic Czech "proč audit dopadl takhle". */}
        {summary.headlineCs && <p className="text-sm text-slate-600">{summary.headlineCs}</p>}

        {/* Category bars. */}
        {summary.categories.length > 0 && (
          <ul className="space-y-1.5" data-audit-categories>
            {summary.categories.map((cat) => (
              <CategoryBar key={cat.category} cat={cat} />
            ))}
          </ul>
        )}

        {/* Severity counts. */}
        <div className="flex flex-wrap gap-2 text-xs tabular-nums text-slate-500">
          <span>Critical: {summary.countsBySeverity.Critical}</span>
          <span>High: {summary.countsBySeverity.High}</span>
          <span>Medium: {summary.countsBySeverity.Medium}</span>
          <span>Low: {summary.countsBySeverity.Low}</span>
        </div>

        {/* Parse degradations. */}
        {summary.warnings.length > 0 && (
          <ul className="space-y-0.5 border-t border-slate-100 pt-2">
            {summary.warnings.map((w, i) => (
              <li key={i} className="text-xs text-amber-700">
                {w}
              </li>
            ))}
          </ul>
        )}
      </div>
    </Card>
  );
}

/** blockingFindings is the only reliably-present field; null → "nezjištěno", never "false". */
function BlockingChip({ value }: { value: boolean | null }) {
  if (value == null) {
    return (
      <span data-blocking="null" className="rounded-full border border-slate-200 px-2.5 py-0.5 text-xs text-slate-400">
        blokující nálezy: nezjištěno
      </span>
    );
  }
  return (
    <StatusBadge
      status={value ? 'zablokovano' : 'proslo'}
      label={value ? 'blokující nálezy: ano' : 'blokující nálezy: ne'}
    />
  );
}

function CategoryBar({ cat }: { cat: AuditCategoryScore }) {
  const pct = Math.min(100, Math.max(0, cat.score));
  const status = scoreStatus(cat.score);
  return (
    <li className="flex items-center gap-2 text-xs">
      <span className="w-32 shrink-0 truncate text-slate-600">{cat.category}</span>
      <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-slate-100">
        <span
          className={cn('block h-full rounded-full')}
          style={{ width: `${pct}%`, backgroundColor: `var(--status-${barVar(status)})` }}
        />
      </span>
      <span className="w-14 shrink-0 text-right tabular-nums text-slate-500" title={cat.rawScore}>
        {cat.score}/100
      </span>
    </li>
  );
}

/** Map a §6.2 token to its index.css `--status-*` suffix for the bar fill. */
function barVar(status: StatusKey): string {
  switch (status) {
    case 'proslo':
      return 'pass';
    case 'pozor':
      return 'warn';
    case 'selhalo':
      return 'fail';
    default:
      return 'idle';
  }
}
