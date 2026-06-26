import { Link } from 'react-router-dom';
import type { SimplifierSummary, SimplifierDisposition, AuditEffort } from '@aid/contract';
import { cn } from '../../lib/utils';
import { Card } from './Card';
import { RawMarkdownDialog } from './RawMarkdownDialog';

/** Czech word + chip colour classes per Simplifier disposition. */
const DISPOSITION: Record<NonNullable<SimplifierDisposition>, { label: string; cls: string }> = {
  approve: { label: 'přijmout', cls: 'border-emerald-300 bg-emerald-50 text-emerald-700' },
  reject: { label: 'odmítnout', cls: 'border-slate-300 bg-slate-50 text-slate-600' },
  defer: { label: 'odložit', cls: 'border-amber-300 bg-amber-50 text-amber-700' },
};

/** Czech effort word for the S/M/L scale (null → "?"). */
function effortWord(effort: AuditEffort): string {
  switch (effort) {
    case 'S':
      return 'malé';
    case 'M':
      return 'střední';
    case 'L':
      return 'velké';
    default:
      return '?';
  }
}

interface SimplifierPanelProps {
  summary: SimplifierSummary;
  /** Deep-link builder for a proposal's target area (defaults to no link). */
  proposalHref?: (area: string) => string;
  /**
   * Run-scope coordinates for fetching the simplifier-report.md artifact via
   * the hardened /file endpoint. If omitted, the raw trigger is not shown.
   */
  projectId?: string;
  epicId?: string;
  runId?: string;
  className?: string;
}

/**
 * MF6 plan-boundary Simplifier proposals (§4.3). Read-only — it shows what the
 * Simplifier proposed and how each was dispositioned; it never applies anything.
 *
 * `present:false` → "Simplifier zatím neběžel". Each proposal renders its
 * disposition badge (přijmout/odmítnout/odložit), an effort chip and an optional
 * deep-link. The raw `.md` (simplifier-report.md) opens lazily in a drawer via
 * the hardened /file endpoint. When run coords are absent, the raw trigger is
 * not shown.
 */
export function SimplifierPanel({
  summary,
  proposalHref,
  projectId,
  epicId,
  runId,
  className,
}: SimplifierPanelProps) {
  if (!summary.present) {
    return (
      <Card title="Zjednodušení (Simplifier)" className={className}>
        <p data-simplifier-absent className="text-sm text-slate-500">
          Simplifier zatím neběžel
        </p>
      </Card>
    );
  }

  return (
    <Card
      title="Zjednodušení (Simplifier)"
      action={
        summary.rawRelPath && projectId && epicId && runId ? (
          <RawMarkdownDialog
            projectId={projectId}
            epicId={epicId}
            runId={runId}
            name="simplifier-report.md"
            title="Návrhy zjednodušení (zdroj)"
          />
        ) : undefined
      }
      className={className}
    >
      <div className="space-y-3">
        {summary.headlineCs && <p className="text-sm text-slate-600">{summary.headlineCs}</p>}

        {summary.proposals.length === 0 ? (
          <p data-simplifier-empty className="text-sm text-slate-400">
            žádné návrhy
          </p>
        ) : (
          <ul className="space-y-2" data-simplifier-proposals>
            {summary.proposals.map((p, i) => {
              const disp = p.disposition ? DISPOSITION[p.disposition] : null;
              const href = p.area && proposalHref ? proposalHref(p.area) : null;
              return (
                <li
                  key={p.id ?? `prop-${i}`}
                  className="flex flex-col gap-1 rounded-lg border border-slate-100 p-2"
                >
                  <div className="flex flex-wrap items-center gap-2">
                    {p.id && (
                      <span className="font-mono text-xs tabular-nums text-slate-400">{p.id}</span>
                    )}
                    {disp ? (
                      <span
                        data-disposition={p.disposition}
                        className={cn('rounded-full border px-2 py-0.5 text-xs font-medium', disp.cls)}
                      >
                        {disp.label}
                      </span>
                    ) : (
                      <span className="rounded-full border border-slate-200 px-2 py-0.5 text-xs text-slate-400">
                        nerozhodnuto
                      </span>
                    )}
                    <span className="rounded-full border border-slate-200 px-2 py-0.5 text-xs text-slate-500">
                      úsilí: {effortWord(p.effort)}
                    </span>
                    {href && (
                      <Link to={href} className="text-xs text-sky-700 hover:underline">
                        {p.area}
                      </Link>
                    )}
                  </div>
                  <p className="text-sm text-slate-700">{p.proposal}</p>
                </li>
              );
            })}
          </ul>
        )}

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
