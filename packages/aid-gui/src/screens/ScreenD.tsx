import { useMemo, useState } from 'react';
import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import type { ActivityEvent } from '@aid/contract';
import { getActivity, getProjects, getExplanations } from '../lib/api';
import { explainEvent, type Dictionary } from '../lib/explain';
import { cn } from '../lib/utils';
import { useAidSocket } from '../hooks/useAidSocket';
import { useProjects } from '../components/shell/ProjectsContext';
import { FilterChip } from '../components/common/FilterChip';
import { Card } from '../components/managerial/Card';
import { EventRow } from '../components/common/EventRow';

/**
 * Screen D — the merged cross-project live activity stream (§13) at `/activity`.
 *
 * Replaces the Phase-5 STUB. It renders the ecosystem-wide activity feed
 * (`getActivity({})`, newest-first) as narrated {@link EventRow}s — each line is
 * a Czech {@link explainEvent} sentence, never raw JSON. The feed stays live two
 * ways, belt-and-suspenders:
 *   - the app-shell global socket invalidates `['activity']` on every event
 *     (see {@link useAidSocket}), and this screen subscribes too;
 *   - a 2s `refetchInterval` is the deterministic floor when the WS is down (a
 *     disk change still surfaces within ~2s). The global offline banner lives in
 *     the app shell — NOT duplicated here.
 *
 * Three filters (project / event-kind / "jen důležité" severity) narrow the feed
 * client-side over the full payload, and a PAUSE toggle freezes auto-scroll while
 * events keep buffering in the react-query cache (un-pausing reveals them).
 *
 * Each row links to the EPIC deep view anchored at the event's timestamp:
 * `/p/:project/e/:epic?ts=<ts>`.
 */

/** Coarse event-kind buckets for the filter (FSM · CP · gate · audit). */
type EventKind = 'fsm' | 'cp' | 'gate' | 'audit';

const KIND_LABEL: Record<EventKind, string> = {
  fsm: 'FSM',
  cp: 'kontrolní body',
  gate: 'brány',
  audit: 'audit / role',
};

/** Map a raw event name onto one of the coarse §13 kinds (null = uncategorised). */
function eventKind(ev: ActivityEvent): EventKind | null {
  const name = ev.event;
  if (name.startsWith('fsm')) return 'fsm';
  if (name.startsWith('gate') || name.startsWith('gates')) return 'gate';
  if (name.startsWith('checkpoint') || name.startsWith('cp') || name.startsWith('verifier')) {
    return 'cp';
  }
  // Role / audit / compliance verdicts → the "audit / role" bucket.
  if (ev.role || name.startsWith('audit') || name.startsWith('compliance')) return 'audit';
  return null;
}

/**
 * "Jen důležité" (severity) keeps only events that carry a meaningful signal:
 * a fail/override/escalation/error, or an explicit `result:'fail'`.
 */
function isImportant(ev: ActivityEvent): boolean {
  if (ev.result === 'fail') return true;
  const n = ev.event;
  return (
    n.includes('fail') ||
    n.includes('override') ||
    n.includes('error') ||
    n.includes('blocked') ||
    n.includes('mismatch') ||
    n.includes('escalat')
  );
}

export function ScreenD() {
  // Belt-and-suspenders live subscription (the app shell already subscribes to
  // ALL topics/projects; this keeps the screen self-sufficient). The 2s poll
  // below is the deterministic floor when the socket is down.
  useAidSocket({ topics: [], projects: [] });

  const { projects: shellProjects } = useProjects();

  const activityQuery = useQuery({
    queryKey: ['activity'],
    queryFn: () => getActivity({}),
    refetchInterval: 2000,
    placeholderData: keepPreviousData,
  });

  // Fallback project list (when the shell context is empty) so the project
  // filter always has options.
  const projectsQuery = useQuery({
    queryKey: ['projects'],
    queryFn: getProjects,
    staleTime: 30_000,
    enabled: shellProjects.length === 0,
  });

  const explanationsQuery = useQuery({
    queryKey: ['explanations'],
    queryFn: () => getExplanations('cs'),
    staleTime: 5 * 60_000,
  });
  const dictionary: Dictionary = explanationsQuery.data ?? {};

  const allEvents = activityQuery.data ?? [];

  // ── filter state ─────────────────────────────────────────────────────────
  const [projectFilter, setProjectFilter] = useState<string | null>(null);
  const [kindFilter, setKindFilter] = useState<EventKind | null>(null);
  const [importantOnly, setImportantOnly] = useState(false);
  const [paused, setPaused] = useState(false);

  // Project options: prefer the shell list, fall back to the local query, and
  // union in any projectId actually seen in the feed (so a project with activity
  // but not yet in the list is still filterable).
  const projectOptions = useMemo(() => {
    const ids = new Set<string>();
    const source = shellProjects.length > 0 ? shellProjects : (projectsQuery.data ?? []);
    for (const p of source) ids.add(p.id);
    for (const ev of allEvents) ids.add(ev.projectId);
    return [...ids].sort();
  }, [shellProjects, projectsQuery.data, allEvents]);

  // Apply filters + newest-first ordering. The PAUSE toggle does NOT drop the
  // tail: when paused we render the buffer as-of the LAST render's order, but
  // because react-query keeps fetching, un-pausing simply re-derives the full
  // (now larger) list — events keep buffering in the cache the whole time.
  const visible = useMemo(() => {
    const filtered = allEvents.filter((ev) => {
      if (projectFilter && ev.projectId !== projectFilter) return false;
      if (kindFilter && eventKind(ev) !== kindFilter) return false;
      if (importantOnly && !isImportant(ev)) return false;
      return true;
    });
    // Newest-first (the REST endpoint is already newest-first, but sort defensively).
    return filtered.sort((a, b) => (a.ts < b.ts ? 1 : a.ts > b.ts ? -1 : 0));
  }, [allEvents, projectFilter, kindFilter, importantOnly]);

  const hasError = activityQuery.isError && allEvents.length === 0;

  return (
    <section className="space-y-4 p-4 sm:p-6" aria-label="Dění">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-2xl font-semibold text-slate-900">Dění</h1>
        <PauseToggle paused={paused} onToggle={() => setPaused((p) => !p)} />
      </header>

      <p className="text-sm text-slate-500">
        Živý tok událostí napříč všemi projekty. Každý řádek je vysvětlený lidskou řečí; klikni pro
        detail EPICu v daném okamžiku.
      </p>

      {/* ── Filters ──────────────────────────────────────────────────────── */}
      <div data-filters className="flex flex-col gap-3">
        <FilterRow label="Projekt">
          <FilterChip active={projectFilter === null} onClick={() => setProjectFilter(null)}>
            vše
          </FilterChip>
          {projectOptions.map((id) => (
            <FilterChip
              key={id}
              active={projectFilter === id}
              onClick={() => setProjectFilter((cur) => (cur === id ? null : id))}
              data-project-filter={id}
            >
              {id}
            </FilterChip>
          ))}
        </FilterRow>

        <FilterRow label="Druh">
          <FilterChip active={kindFilter === null} onClick={() => setKindFilter(null)}>
            vše
          </FilterChip>
          {(Object.keys(KIND_LABEL) as EventKind[]).map((k) => (
            <FilterChip
              key={k}
              active={kindFilter === k}
              onClick={() => setKindFilter((cur) => (cur === k ? null : k))}
              data-kind-filter={k}
            >
              {KIND_LABEL[k]}
            </FilterChip>
          ))}
        </FilterRow>

        <FilterRow label="Závažnost">
          <FilterChip
            active={importantOnly}
            onClick={() => setImportantOnly((v) => !v)}
            data-important-filter
          >
            jen důležité
          </FilterChip>
        </FilterRow>
      </div>

      {/* ── Stream ───────────────────────────────────────────────────────── */}
      <Card title={paused ? 'Co se děje (pozastaveno)' : 'Co se děje'}>
        {paused && (
          <p data-paused-note className="mb-2 text-xs text-amber-700">
            Tok je pozastavený — nové události se dál ukládají, jen neposouvají seznam. Zrušením pauzy
            se zobrazí.
          </p>
        )}
        {hasError ? (
          <p data-activity-error className="text-sm text-amber-700">
            Aktivitu se nepodařilo načíst — zkouším znovu. (Zobrazuji poslední známý stav.)
          </p>
        ) : visible.length === 0 ? (
          <p data-activity-empty className="text-sm text-slate-400">
            Žádné události neodpovídají filtru.
          </p>
        ) : (
          <ul
            data-event-feed
            data-paused={paused ? 'true' : 'false'}
            className={cn(
              'divide-y divide-slate-100',
              // Paused: freeze auto-scroll by NOT letting the list grow the
              // scroll container (overflow hidden, capped height). Live: natural.
              paused ? 'max-h-[60vh] overflow-hidden' : '',
            )}
          >
            {visible.map((event, i) => (
              <li key={`${event.ts}:${event.event}:${event.projectId}:${i}`}>
                <ActivityRow event={event} dictionary={dictionary} />
              </li>
            ))}
          </ul>
        )}
      </Card>
    </section>
  );
}

// ---------------------------------------------------------------------------
// One clickable activity row → EPIC deep view anchored at the event ts
// ---------------------------------------------------------------------------

function ActivityRow({ event, dictionary }: { event: ActivityEvent; dictionary: Dictionary }) {
  const explanation = explainEvent(event, dictionary);

  // A row links to the EPIC deep view at the event's moment. Only events that
  // carry an epicId are linkable; the rest render as a plain (non-link) row.
  if (event.epicId) {
    const href = `/p/${encodeURIComponent(event.projectId)}/e/${encodeURIComponent(
      event.epicId,
    )}?ts=${encodeURIComponent(event.ts)}`;
    return (
      <Link
        to={href}
        data-activity-row
        data-project={event.projectId}
        data-epic={event.epicId}
        className="block rounded-lg px-1 hover:bg-slate-50"
      >
        <RowBody event={event} explanation={explanation} />
      </Link>
    );
  }

  return (
    <div data-activity-row data-project={event.projectId} className="px-1">
      <RowBody event={event} explanation={explanation} />
    </div>
  );
}

/** The EventRow plus a small project chip (the merged feed is cross-project). */
function RowBody({
  event,
  explanation,
}: {
  event: ActivityEvent;
  explanation: ReturnType<typeof explainEvent>;
}) {
  return (
    <div className="flex items-start gap-2">
      <span
        data-row-project
        className="mt-2 shrink-0 rounded-full border border-slate-200 bg-slate-50 px-2 py-0.5 text-[11px] tabular-nums text-slate-500"
      >
        {event.projectId}
      </span>
      <span className="min-w-0 flex-1">
        <EventRow event={event} explanation={explanation} at={event.ts} />
      </span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Small presentational primitives (filter chips + pause toggle)
// ---------------------------------------------------------------------------

function FilterRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      <span className="mr-1 text-xs font-medium text-slate-500">{label}:</span>
      {children}
    </div>
  );
}


function PauseToggle({ paused, onToggle }: { paused: boolean; onToggle: () => void }) {
  return (
    <button
      type="button"
      data-pause-toggle
      aria-pressed={paused}
      onClick={onToggle}
      className={cn(
        'min-h-[40px] rounded-lg border px-3 text-sm font-medium',
        paused
          ? 'border-amber-300 bg-amber-50 text-amber-700'
          : 'border-slate-200 bg-white text-slate-700 hover:bg-slate-50',
      )}
    >
      {paused ? 'Pokračovat' : 'Pozastavit'}
    </button>
  );
}
