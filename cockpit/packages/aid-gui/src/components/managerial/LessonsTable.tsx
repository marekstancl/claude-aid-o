import { Link } from 'react-router-dom';
import type { LessonsView, LessonEntry } from '@aid/contract';
import { cn } from '../../lib/utils';
import { Card } from './Card';
import { useIsMobile } from '../shell/useIsMobile';

interface LessonsTableProps {
  lessons: LessonsView;
  /** Deep-link builder for an EPIC chip (defaults to /p/:project/e/:epic). */
  epicHref?: (projectId: string | null, epicId: string) => string;
  className?: string;
}

/** Czech label for a lesson kind. */
function kindLabel(kind: LessonEntry['kind']): string {
  return kind === 'gotcha' ? 'past' : 'ponaučení';
}

/**
 * §13.8 lessons-per-plan. Desktop → a Table; mobile → Cards. Each row's EPIC
 * chip is a Badge + Link (when an epicId is present). Null cells (no date, no
 * epicId) render an em-dash, never a fabricated value. `entries:[]` →
 * "žádná ponaučení".
 */
export function LessonsTable({
  lessons,
  epicHref = (projectId, epicId) => `/p/${projectId ?? ''}/e/${epicId}`,
  className,
}: LessonsTableProps) {
  const isMobile = useIsMobile();
  const entries = lessons.entries;

  const body =
    entries.length === 0 ? (
      <p data-lessons-empty className="text-sm text-slate-500">
        žádná ponaučení
      </p>
    ) : isMobile ? (
      <ul className="space-y-2" data-lessons-cards>
        {entries.map((e, i) => (
          <li key={i} className="rounded-lg border border-slate-100 p-2">
            <div className="mb-1 flex items-center gap-2">
              <EpicChip projectId={lessons.projectId} epicId={e.epicId} href={epicHref} />
              <span className="text-xs text-slate-400">{kindLabel(e.kind)}</span>
              <span className="ml-auto text-xs tabular-nums text-slate-400">{e.date ?? '—'}</span>
            </div>
            <p className="text-sm text-slate-700">{e.lesson}</p>
          </li>
        ))}
      </ul>
    ) : (
      <table className="w-full text-sm" data-lessons-table>
        <thead>
          <tr className="border-b border-slate-200 text-left text-xs uppercase tracking-wide text-slate-400">
            <th className="py-1.5 pr-3 font-medium">EPIC</th>
            <th className="py-1.5 pr-3 font-medium">Typ</th>
            <th className="py-1.5 pr-3 font-medium">Ponaučení</th>
            <th className="py-1.5 font-medium">Datum</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((e, i) => (
            <tr key={i} className="border-b border-slate-100 align-top">
              <td className="py-1.5 pr-3">
                <EpicChip projectId={lessons.projectId} epicId={e.epicId} href={epicHref} />
              </td>
              <td className="py-1.5 pr-3 text-slate-500">{kindLabel(e.kind)}</td>
              <td className="py-1.5 pr-3 text-slate-700">{e.lesson}</td>
              <td className="py-1.5 tabular-nums text-slate-400">{e.date ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    );

  return (
    <Card
      title="Ponaučení"
      action={<span className="text-xs tabular-nums text-slate-400">{lessons.total}</span>}
      className={className}
    >
      {body}
      {lessons.warnings.length > 0 && (
        <ul className="mt-2 space-y-0.5 border-t border-slate-100 pt-2">
          {lessons.warnings.map((w, i) => (
            <li key={i} className="text-xs text-amber-700">
              {w}
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

function EpicChip({
  projectId,
  epicId,
  href,
  className,
}: {
  projectId: string | null;
  epicId: string | null;
  href: (projectId: string | null, epicId: string) => string;
  className?: string;
}) {
  if (!epicId) {
    return <span className={cn('text-xs text-slate-400', className)}>—</span>;
  }
  return (
    <Link
      to={href(projectId, epicId)}
      className={cn(
        'inline-flex items-center rounded-full border border-slate-200 bg-slate-50 px-2 py-0.5 font-mono text-xs text-slate-600 hover:bg-slate-100',
        className,
      )}
    >
      {epicId}
    </Link>
  );
}
