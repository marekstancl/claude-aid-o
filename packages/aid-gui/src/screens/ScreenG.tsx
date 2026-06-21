import { useEffect, useRef, useState } from 'react';
import { useQuery, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { Download, X } from 'lucide-react';
import { getBrief, getProjects } from '../lib/api';
import { getLastSeen, setLastSeen } from '../lib/lastSeen';
import { storage } from '../lib/storage';
import { BriefPanel } from '../components/managerial/BriefPanel';
import { ProjectTileGrid } from '../components/ProjectTileGrid';
import { Card } from '../components/managerial/Card';

/** The §13.3 infra scopeKey for the landing brief's lastSeen container. */
const INFRA_SCOPE_KEY = 'infra';
/** localStorage flag for a dismissed PWA install banner. */
const PWA_DISMISSED_KEY = 'aid.pwa.dismissed';

/**
 * Chromium-only `beforeinstallprompt` event (not in lib.dom — typed locally).
 * Mirrors the local shape in {@link import('../components/common/InstallPwaButton')}.
 */
interface BeforeInstallPromptEvent extends Event {
  readonly platforms: string[];
  readonly userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
  prompt(): Promise<void>;
}

/**
 * Screen G — the cross-infra managerial brief and the landing route `/` (§8.2).
 *
 * The non-technical front door. It renders ONE infra-scope {@link Brief} from
 * `GET /api/brief?since=<lastSeen>` via {@link BriefPanel}, with the seven §8.2
 * blocks in priority order — Rozhodnutí, Co blokuje, Riziko, Na co pozor, Co se
 * změnilo, Co bude dál, Přehled projektů. Blockers/decisions ALWAYS come first;
 * a tile grid is NEVER the first content region.
 *
 * Two independent queries back the screen so a brief failure never hides the
 * project tiles:
 *   - `['brief','infra',since]` — the managerial brief (4s refetch, last-good kept)
 *   - `['projects']`            — the cross-project tiles (the embedded "Přehled
 *                                  projektů", still useful when the brief fails)
 *
 * "Označit jako přečtené" writes `now()` to `localStorage['aid.lastSeen.infra']`
 * and invalidates the brief so the "Co se změnilo" delta resets. A dismissible
 * PWA install banner is wired to a captured `beforeinstallprompt`.
 */
export function ScreenG() {
  const queryClient = useQueryClient();

  // null on first visit → the brief renders "první návštěva" with no "N nových".
  const since = getLastSeen(INFRA_SCOPE_KEY);

  const briefQuery = useQuery({
    queryKey: ['brief', 'infra', since],
    queryFn: () => getBrief({}, since ?? undefined),
    refetchInterval: 4000,
    // Keep the last-good brief on screen while a refetch errors (live dashboard).
    placeholderData: keepPreviousData,
  });

  // Projects feed the embedded tile grid; an independent query so a brief
  // failure still renders the tiles if /api/projects succeeds.
  const projectsQuery = useQuery({
    queryKey: ['projects'],
    queryFn: getProjects,
    refetchInterval: 4000,
    placeholderData: keepPreviousData,
  });

  const brief = briefQuery.data;
  const projects = projectsQuery.data ?? [];

  const markAsRead = () => {
    setLastSeen(INFRA_SCOPE_KEY, new Date().toISOString());
    // Re-key the brief read so "Co se změnilo" recomputes against the new lastSeen.
    void queryClient.invalidateQueries({ queryKey: ['brief', 'infra'] });
  };

  return (
    <section className="space-y-4 p-4 sm:p-6" aria-label="Co potřebuju vědět">
      <PwaInstallBanner />

      <header className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-2xl font-semibold text-slate-900">Co potřebuju vědět</h1>
        <button
          type="button"
          data-mark-read
          onClick={markAsRead}
          className="inline-flex min-h-[36px] items-center rounded-lg border border-slate-200 px-3 text-sm text-slate-600 hover:bg-slate-100"
        >
          Označit jako přečtené
        </button>
      </header>

      {/* Brief load failure → calm error surface; last-good data is kept by react-query. */}
      {briefQuery.isError && !brief && (
        <p data-brief-error className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700">
          Brief se nepodařilo načíst — zkouším znovu.
        </p>
      )}

      {brief ? (
        // BriefPanel renders the seven §8.2 blocks (blockers/decisions FIRST) and,
        // at infra scope, embeds the "Přehled projektů" tile grid as the final block.
        <BriefPanel scope="infra" brief={brief} projects={projects} />
      ) : briefQuery.isError ? (
        // No brief at all (errored before any success) — still show the tiles
        // section so the screen stays useful.
        <Card title="Přehled projektů" collapsibleOnMobile>
          <ProjectTileGrid projects={projects} />
        </Card>
      ) : (
        <p data-brief-loading className="text-sm text-slate-400">
          Načítám přehled…
        </p>
      )}
    </section>
  );
}

/**
 * Dismissible PWA install banner. Captures `beforeinstallprompt`
 * (`preventDefault` + store), shows ONLY while a prompt is available AND the
 * banner has not been dismissed. Clicking fires the native prompt; dismissing
 * persists `localStorage['aid.pwa.dismissed']='1'`. When `beforeinstallprompt`
 * never fires, nothing renders (no banner, no error).
 */
function PwaInstallBanner() {
  const promptRef = useRef<BeforeInstallPromptEvent | null>(null);
  const [available, setAvailable] = useState(false);
  const [dismissed, setDismissed] = useState(() => {
    const store = storage();
    try {
      return store?.getItem(PWA_DISMISSED_KEY) === '1';
    } catch {
      return false;
    }
  });

  useEffect(() => {
    const onBeforeInstallPrompt = (event: Event) => {
      event.preventDefault();
      promptRef.current = event as BeforeInstallPromptEvent;
      setAvailable(true);
    };
    const onInstalled = () => {
      promptRef.current = null;
      setAvailable(false);
    };
    window.addEventListener('beforeinstallprompt', onBeforeInstallPrompt);
    window.addEventListener('appinstalled', onInstalled);
    return () => {
      window.removeEventListener('beforeinstallprompt', onBeforeInstallPrompt);
      window.removeEventListener('appinstalled', onInstalled);
    };
  }, []);

  if (!available || dismissed) return null;

  const install = async () => {
    const evt = promptRef.current;
    if (!evt) return;
    await evt.prompt();
    // A prompt may be used once; consume it regardless of the user's choice.
    promptRef.current = null;
    setAvailable(false);
  };

  const dismiss = () => {
    const store = storage();
    try {
      store?.setItem(PWA_DISMISSED_KEY, '1');
    } catch {
      /* best-effort — the banner simply reappears next session */
    }
    setDismissed(true);
  };

  return (
    <div
      data-pwa-banner
      className="flex items-center justify-between gap-3 rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm"
    >
      <button
        type="button"
        data-pwa-install
        onClick={install}
        className="inline-flex items-center gap-2 text-slate-700 hover:underline"
      >
        <Download className="h-4 w-4 text-slate-400" />
        Nainstalovat jako aplikaci
      </button>
      <button
        type="button"
        data-pwa-dismiss
        onClick={dismiss}
        aria-label="Skrýt nabídku instalace"
        className="rounded p-1 text-slate-400 hover:bg-slate-200 hover:text-slate-600"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  );
}
