import { useCallback, useState } from 'react';
import { Dialog } from '@base-ui/react/dialog';
import { FileText, X } from 'lucide-react';
import { cn } from '../../lib/utils';
import { getRunFile, ApiError } from '../../lib/api';

interface RawMarkdownDialogProps {
  /**
   * Run-scoped artifact fetch — projectId, epicId, runId are required for the
   * hardened `/file` endpoint (§7.4.1). If any are absent, no trigger renders.
   */
  projectId?: string;
  epicId?: string;
  runId?: string;
  /** Allow-listed artifact name (e.g. 'audit-report.md', 'reporter/foo.txt'). */
  name?: string;
  /** Dialog heading (Czech). */
  title: string;
  /** Trigger button label (Czech, defaults to "Zobrazit zdroj"). */
  triggerLabel?: string;
  className?: string;
}

type FetchState =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'loaded'; text: string }
  | { kind: 'error' };

/**
 * Drawer that lazily fetches a run-scoped artifact from the hardened `/file`
 * endpoint the first time it is opened (§7.4.1). The fetch is deliberately NOT
 * eager — the structured summary on screen is the primary surface; the raw
 * artifact is a drill-down.
 *
 * Honesty contract:
 *  - Missing any of `projectId`, `epicId`, `runId`, or `name` → no trigger
 *    (nothing to open).
 *  - a fetch failure renders "raw report se nepodařilo načíst" inside the open
 *    drawer; it NEVER throws and NEVER blanks the structured summary behind it.
 */
export function RawMarkdownDialog({
  projectId,
  epicId,
  runId,
  name,
  title,
  triggerLabel = 'Zobrazit zdroj',
  className,
}: RawMarkdownDialogProps) {
  const [state, setState] = useState<FetchState>({ kind: 'idle' });

  const load = useCallback(async () => {
    if (!projectId || !epicId || !runId || !name) return;
    setState({ kind: 'loading' });
    try {
      const data = await getRunFile(projectId, epicId, runId, name);
      setState({ kind: 'loaded', text: data.content });
    } catch (err: unknown) {
      // ApiError or any other error — log for debugging but degrade gracefully.
      if (err instanceof ApiError) {
        console.debug(`Failed to fetch artifact ${name}:`, err.code, err.message);
      } else if (err instanceof Error) {
        console.debug(`Failed to fetch artifact ${name}:`, err.message);
      }
      setState({ kind: 'error' });
    }
  }, [projectId, epicId, runId, name]);

  // Nothing to show — missing run coordinates or artifact name.
  if (!projectId || !epicId || !runId || !name) return null;

  const onOpenChange = (open: boolean) => {
    if (open && state.kind === 'idle') void load();
  };

  return (
    <Dialog.Root onOpenChange={onOpenChange}>
      <Dialog.Trigger
        data-raw-md-trigger
        className={cn(
          'inline-flex items-center gap-1.5 rounded-lg border border-slate-200 px-2.5 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100',
          className,
        )}
      >
        <FileText aria-hidden className="h-3.5 w-3.5" />
        {triggerLabel}
      </Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Backdrop className="fixed inset-0 z-50 bg-slate-900/40" />
        <Dialog.Popup className="fixed inset-x-0 bottom-0 z-50 max-h-[85vh] overflow-y-auto rounded-t-2xl border-t border-slate-200 bg-white pb-[env(safe-area-inset-bottom)] shadow-xl sm:inset-x-auto sm:right-0 sm:top-0 sm:bottom-0 sm:max-h-none sm:w-[36rem] sm:max-w-[90vw] sm:rounded-none sm:rounded-l-2xl sm:border-l sm:border-t-0">
          <div className="flex items-start justify-between gap-3 border-b border-slate-200 px-4 py-3">
            <Dialog.Title className="text-base font-semibold text-slate-900">{title}</Dialog.Title>
            <Dialog.Close
              className="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg text-slate-500 hover:bg-slate-100"
              aria-label="Zavřít"
            >
              <X className="h-5 w-5" />
            </Dialog.Close>
          </div>
          <div className="px-4 py-4">
            {state.kind === 'loading' && <p className="text-sm text-slate-500">Načítám…</p>}
            {state.kind === 'error' && (
              <p data-raw-md-error className="text-sm text-amber-700">
                raw report se nepodařilo načíst
              </p>
            )}
            {state.kind === 'loaded' && (
              <pre className="whitespace-pre-wrap break-words font-mono text-xs leading-relaxed text-slate-700">
                {state.text}
              </pre>
            )}
          </div>
        </Dialog.Popup>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
