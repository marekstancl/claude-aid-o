import { Link } from 'react-router-dom';
import { FolderX, WifiOff } from 'lucide-react';

/**
 * Empty state shown when a route references a :project param that is not in
 * /api/projects. Prevents a crash on a bad deep-link and offers a way back.
 *
 * `loadError` distinguishes an API outage (the project list could not be
 * fetched) from a genuinely-missing project — an outage must NOT be reported as
 * "Projekt nenalezen" (it would mislabel every valid deep-link, MED finding).
 */
export function ProjectNotFound({
  projectId,
  loadError = false,
}: {
  projectId: string;
  loadError?: boolean;
}) {
  return (
    <section className="flex h-full flex-col items-center justify-center gap-4 p-8 text-center">
      <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-slate-100">
        {loadError ? (
          <WifiOff className="h-6 w-6 text-amber-500" />
        ) : (
          <FolderX className="h-6 w-6 text-slate-400" />
        )}
      </div>
      <div className="space-y-1">
        <h2 className="text-lg font-semibold text-slate-900">
          {loadError ? 'Projekty se nepodařilo načíst' : 'Projekt nenalezen'}
        </h2>
        <p className="text-sm text-slate-500">
          {loadError
            ? 'Server je nedostupný nebo spojení selhalo. Zkus to prosím znovu.'
            : `Projekt „${projectId}" neexistuje nebo už není sledovaný.`}
        </p>
      </div>
      <Link
        to="/prehled"
        className="rounded-lg border border-slate-200 bg-white px-4 py-2 text-sm font-medium text-slate-700 transition-colors hover:bg-slate-50"
      >
        Zpět na Přehled
      </Link>
    </section>
  );
}
