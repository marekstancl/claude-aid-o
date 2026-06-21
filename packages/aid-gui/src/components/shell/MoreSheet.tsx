import { Dialog } from '@base-ui/react/dialog';
import { useNavigate, useParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { X, FolderOpen, HelpCircle, RefreshCw } from 'lucide-react';
import { useProjects } from './ProjectsContext';
import { InstallPwaButton } from '../common/InstallPwaButton';
import { getPlans } from '../../lib/api';

interface MoreSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

/**
 * Mobile "Více" sheet (base-ui Dialog, bottom-sheet variant). Holds the project
 * switcher, a plan switcher (plans of the currently-viewed project), the
 * Nápověda link, the real Install-PWA button (renders only when installable) and
 * a refresh button. Light-theme surfaces only.
 */
export function MoreSheet({ open, onOpenChange }: MoreSheetProps) {
  const navigate = useNavigate();
  const { projects } = useProjects();
  // Plan switcher = plans of the project currently in the route (if any).
  const { project: currentProject } = useParams();
  const { data: plans } = useQuery({
    queryKey: ['plans', currentProject],
    queryFn: () => getPlans(currentProject!),
    enabled: open && !!currentProject,
  });

  const go = (path: string) => {
    onOpenChange(false);
    navigate(path);
  };

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Backdrop className="fixed inset-0 z-50 bg-slate-900/40" />
        <Dialog.Popup className="fixed inset-x-0 bottom-0 z-50 max-h-[80vh] overflow-y-auto rounded-t-2xl border-t border-slate-200 bg-white pb-[env(safe-area-inset-bottom)] shadow-xl">
          <div className="flex items-center justify-between border-b border-slate-200 px-4 py-3">
            <Dialog.Title className="text-base font-semibold text-slate-900">Více</Dialog.Title>
            <Dialog.Close
              className="flex h-11 w-11 items-center justify-center rounded-lg text-slate-500 hover:bg-slate-100"
              aria-label="Zavřít"
            >
              <X className="h-5 w-5" />
            </Dialog.Close>
          </div>

          <div className="px-4 py-3">
            <h3 className="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-slate-400">
              <FolderOpen className="h-4 w-4" /> Projekt
            </h3>
            {projects.length === 0 ? (
              <p className="text-sm text-slate-500">Žádné projekty</p>
            ) : (
              <ul className="space-y-1">
                {projects.map((p) => (
                  <li key={p.id}>
                    <button
                      type="button"
                      onClick={() => go(`/p/${p.id}`)}
                      className="flex min-h-[44px] w-full items-center rounded-lg px-3 text-left text-sm text-slate-700 hover:bg-slate-100"
                    >
                      {p.name ?? p.id}
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="border-t border-slate-200 px-4 py-3">
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">Plán</h3>
            {!currentProject ? (
              <p className="text-sm text-slate-500">Otevři projekt pro seznam plánů.</p>
            ) : !plans || plans.length === 0 ? (
              <p className="text-sm text-slate-500">Žádné plány</p>
            ) : (
              <ul className="space-y-1">
                {plans.map((pl) => (
                  <li key={pl.planId}>
                    <button
                      type="button"
                      onClick={() => go(`/p/${currentProject}/plans/${encodeURIComponent(pl.planId)}`)}
                      className="flex min-h-[44px] w-full items-center rounded-lg px-3 text-left text-sm text-slate-700 hover:bg-slate-100"
                    >
                      {pl.title ?? pl.planId}
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="space-y-1 border-t border-slate-200 px-2 py-3">
            <button
              type="button"
              onClick={() => go('/help')}
              className="flex min-h-[44px] w-full items-center gap-3 rounded-lg px-3 text-left text-sm text-slate-700 hover:bg-slate-100"
            >
              <HelpCircle className="h-5 w-5 text-slate-400" /> Nápověda
            </button>
            {/* Real install affordance — renders only when the browser fired a
                beforeinstallprompt (returns null otherwise), per §8.1/§9.3. */}
            <InstallPwaButton className="flex min-h-[44px] w-full items-center gap-3 rounded-lg px-3 text-left text-sm text-slate-700 hover:bg-slate-100" />
            <button
              type="button"
              onClick={() => window.location.reload()}
              className="flex min-h-[44px] w-full items-center gap-3 rounded-lg px-3 text-left text-sm text-slate-700 hover:bg-slate-100"
            >
              <RefreshCw className="h-5 w-5 text-slate-400" /> Obnovit
            </button>
          </div>
        </Dialog.Popup>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
