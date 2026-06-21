import { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import type { Checkpoint, DictionaryEntry, Explanation } from '@aid/contract';
import { getExplanations } from '../lib/api';
import type { Dictionary } from '../lib/explain';
import { cn } from '../lib/utils';
import { FsmTimeline, type TimelineNode } from '../components/FsmTimeline';
import { CheckpointStrip } from '../components/CheckpointStrip';
import { ProjectTile } from '../components/ProjectTile';
import type { Project } from '@aid/contract';

/**
 * Screen F — in-app Help at `/help` (§8.2 Help, Phase 6).
 *
 * Replaces the Phase-5 STUB. Modeled on the ACTA Help pattern:
 *   - a dark-gradient hero with an embedded search Input (cyan/violet palette —
 *     intentional for the Help hero even though the app is light);
 *   - a sticky TOC sidebar on desktop / an "Obsah" dropdown on mobile, both
 *     driven by an {@link IntersectionObserver} scrollspy over the Section refs;
 *   - a metadata-driven 13-entry {@link SECTIONS} array;
 *   - content from `<Section>/<Step>/<Demo>/<Kbd>` building blocks in
 *     conversational plain Czech;
 *   - live `<Demo>` blocks rendering the dashboard's REAL components
 *     (FsmTimeline, CheckpointStrip, ProjectTile) fed STATIC demo props so a
 *     backend outage can never break a Demo.
 *
 * Section bodies are authored from the SAME `DictionaryEntry` set
 * (`/api/explanations`, react-query key `['explanations']`) that powers the live
 * UI — so terminology matches everywhere. A failed dictionary fetch still
 * renders the static SECTIONS scaffold plus a muted note (never blank); a
 * missing key renders its static title + "(popis chybí)", never a thrown
 * undefined.
 */

// ---------------------------------------------------------------------------
// SECTIONS — the metadata-driven 13-entry table of contents (§8.2 Help).
//
// Each entry binds an anchor `id`, a Czech `title`, a `keywords` search index,
// and the dictionary KEYS whose §6.3 entries author the section body. The 10
// Rev-2 ids + the 3 Rev-3 managerial ids = exactly 13 (asserted by the test).
// ---------------------------------------------------------------------------

export interface HelpSection {
  id: string;
  title: string;
  /** Help-search index (case-insensitive substring over these + the entries' keywords). */
  keywords: string;
  /** Dictionary KEYS sourcing the section body (terms match the live UI). */
  dictKeys: string[];
}

export const SECTIONS: HelpSection[] = [
  // ── 10 Rev-2 base ids (the six CP slots are consolidated into one
  //    `kontrolni-body` §8.2 section, freeing slots for `verdikty` + `prefilter`
  //    so the base set lands at exactly 10 distinct concepts) ─────────────────
  {
    id: 'co-je-aid',
    title: 'Co je AID',
    keywords: 'co je aid orchestrátor pipeline úvod přehled začátek',
    dictKeys: ['concept:plan_membership_derived'],
  },
  {
    id: 'fsm',
    title: 'Stavový automat (FSM)',
    keywords: 'fsm stav automat ready execute gates done běh stroj',
    dictKeys: ['state:READY', 'state:EXECUTE', 'state:GATES', 'state:DONE', 'state:ESCALATION', 'state:ERROR'],
  },
  {
    id: 'kontrolni-body',
    title: 'Kontrolní body (CP1–CP6)',
    keywords: 'cp cp1 cp2 cp3 cp4 cp5 cp6 checkpoint kontrolní bod plán epica krok brány audit dokončení',
    dictKeys: ['cp:CP1', 'cp:CP2', 'cp:CP3', 'cp:CP4', 'cp:CP5', 'cp:CP6'],
  },
  {
    id: 'role',
    title: 'Role agentů',
    keywords: 'role auditor curator reporter simplifier agent kontrolor',
    dictKeys: [
      'role:auditor:clean',
      'role:curator:proposals',
      'role:reporter:pass',
      'role:simplifier:proposals',
    ],
  },
  {
    id: 'gates',
    title: 'Brány a kontroly',
    keywords: 'brány gates kontroly check test lint pass fail',
    dictKeys: ['event:gate_complete:pass', 'event:gate_complete:fail', 'check:plan_ac_match'],
  },
  {
    id: 'verdikty',
    title: 'Verdikty a závěry',
    keywords: 'verdikt pass fail skip unverifiable prošlo selhalo přeskočeno neověřitelné závěr',
    dictKeys: ['verdict:pass', 'verdict:fail', 'verdict:pass_with_notes'],
  },
  {
    id: 'prefilter',
    title: 'Předfiltr kroků (RUN / SKIP)',
    keywords: 'předfiltr prefilter run skip full review klasifikace krok přeskočit',
    dictKeys: [
      'event:prefilter_classification:RUN',
      'event:prefilter_classification:SKIP',
      'event:prefilter_classification:FAIL',
    ],
  },
  {
    id: 'compliance',
    title: 'Compliance a porušení',
    keywords: 'compliance shoda porušení blocking advisory severity override',
    dictKeys: ['compliance:overall:pass', 'compliance:overall:fail', 'severity:blocking', 'severity:advisory'],
  },
  {
    id: 'timings-retry',
    title: 'Časy, opakování a zaseknutí',
    keywords: 'čas opakování retry zaseknutí stale loop běh trvání',
    dictKeys: ['concept:stale_run', 'concept:stuck_or_looping'],
  },
  {
    id: 'cti-dashboard',
    title: 'Jak číst dashboard',
    keywords: 'dashboard čtení barvy stavy tečky pruh přehled orientace',
    dictKeys: ['concept:since_first_visit', 'concept:aggregate_audit_sparse'],
  },
  // ── 3 Rev-3 managerial ids ────────────────────────────────────────────────
  {
    id: 'co-resit',
    title: 'Co potřebuju vědět (brief)',
    keywords: 'brief co řešit rozhodnutí blokuje pozor riziko přehled manažer',
    dictKeys: ['concept:decision_needed'],
  },
  {
    id: 'plan',
    title: 'Plán a jeho fáze',
    keywords: 'plán plan fáze epicy ac pokrytí audit trend backlog lekce',
    dictKeys: ['concept:plan_membership_derived', 'check:plan_ac_match'],
  },
  {
    id: 'riziko',
    title: 'Riziko a odhad úspěchu',
    keywords:
      'riziko level nízké střední vysoké pravděpodobnost úspěch agent mvp2 deterministické',
    dictKeys: [
      'concept:risk:nizke',
      'concept:risk:stredni',
      'concept:risk:vysoke',
      'concept:success_probability_mvp2',
    ],
  },
];

// ---------------------------------------------------------------------------
// Static demo props — decoupled from live data so a backend outage never breaks
// a `<Demo>`. The REAL FsmTimeline / CheckpointStrip / ProjectTile render these.
// ---------------------------------------------------------------------------

/** A static §6.4 explanation (no dictionary fetch needed for the Demo). */
function demoExplanation(headline: string, detail: string, color: string): Explanation {
  return { headline, detail, status: 'ceka', color };
}

/** READY → EXECUTE → GATES → DONE demo walk for the FsmTimeline Demo. */
const DEMO_FSM_NODES: TimelineNode[] = [
  {
    key: 'READY',
    label: 'READY',
    status: 'ceka',
    explanation: demoExplanation('Připraveno ke spuštění', 'EPICa čeká ve frontě.', '#64748b'),
  },
  {
    key: 'EXECUTE',
    label: 'EXECUTE',
    status: 'bezi',
    explanation: demoExplanation('Běží implementace', 'Agenti právě kódují kroky.', '#0284c7'),
    current: true,
  },
  {
    key: 'GATES',
    label: 'GATES',
    status: 'bezi',
    explanation: demoExplanation('Běží brány', 'Testy, lint a kontroly.', '#0284c7'),
  },
  {
    key: 'DONE',
    label: 'DONE',
    status: 'proslo',
    explanation: demoExplanation('Hotovo', 'Čeká na tvé rozhodnutí (merge).', '#059669'),
  },
];

/** CP1–CP6 demo dots for the CheckpointStrip Demo. */
const DEMO_CHECKPOINTS: Checkpoint[] = [
  cp('CP1', 'kontrola plánu', 'pass'),
  cp('CP2', 'kontrola EPICy', 'pass'),
  cp('CP3', 'kontrola kroku', 'pass'),
  cp('CP4', 'brány', 'pass'),
  cp('CP5', 'audit', 'unverifiable'),
  cp('CP6', 'dokončení', null),
];

function cp(id: Checkpoint['id'], label: string, verdict: Checkpoint['verdict']): Checkpoint {
  return {
    id,
    label,
    dispatched: verdict != null,
    verdict,
    provenance: 'demo',
    provenanceSource: 'timeline',
    repeatCount: 1,
    repeatSource: 'timeline',
    outputs: [],
  };
}

/** A static idle Project for the ProjectTile Demo (no live fetch, never crashes). */
const DEMO_PROJECT: Project = {
  id: 'ukazka',
  name: 'Ukázkový projekt',
  path: '/ukazka',
  aidoPath: '/ukazka/.aid-o',
  discovered: true,
  partial: false,
  epicsTotal: 3,
  epicsActive: 1,
  runsTotal: 7,
  activeRun: { epicId: 'E-001', runId: 'r1', state: 'EXECUTE' },
  health: {
    value: 88,
    partial: false,
    confidence: 'high',
    compliancePassRate: 1,
    openViolations: 0,
    lastGateOverall: 'pass',
    warnings: [],
  },
  lastActivityAt: null,
};

// ---------------------------------------------------------------------------
// Building blocks — <Section> / <Step> / <Demo> / <Kbd>
// ---------------------------------------------------------------------------

/** Inline `<Kbd>` chip for a keyboard hint / token. */
function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="rounded border border-slate-300 bg-slate-100 px-1.5 py-0.5 font-mono text-xs text-slate-700">
      {children}
    </kbd>
  );
}

/** A numbered step inside a Section body. */
function Step({ n, children }: { n: number; children: React.ReactNode }) {
  return (
    <li data-step={n} className="flex gap-3">
      <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-violet-100 text-xs font-semibold text-violet-700">
        {n}
      </span>
      <span className="pt-0.5 text-sm text-slate-700">{children}</span>
    </li>
  );
}

/** "V appce to vypadá takhle" framed box wrapping a live, static-fed Demo. */
function Demo({ children }: { children: React.ReactNode }) {
  return (
    <figure data-demo className="my-3 rounded-lg border border-slate-200 bg-slate-50 p-3">
      <figcaption className="mb-2 text-xs font-medium uppercase tracking-wide text-slate-400">
        V appce to vypadá takhle
      </figcaption>
      <div className="rounded-md bg-white p-3">{children}</div>
    </figure>
  );
}

/**
 * A Help section: a card with a registered IntersectionObserver ref (the
 * scrollspy target). Renders its dictionary-sourced body and optional children
 * (Steps / Demos / Kbd).
 */
function Section({
  section,
  dict,
  registerRef,
  children,
}: {
  section: HelpSection;
  dict: Dictionary;
  registerRef: (id: string, el: HTMLElement | null) => void;
  children?: React.ReactNode;
}) {
  const ref = useRef<HTMLElement | null>(null);

  useEffect(() => {
    registerRef(section.id, ref.current);
    return () => registerRef(section.id, null);
  }, [section.id, registerRef]);

  return (
    <section
      id={section.id}
      ref={ref}
      data-section={section.id}
      className="scroll-mt-24 rounded-lg border border-slate-200 bg-white p-5"
    >
      <h2 className="text-lg font-semibold text-slate-900">{section.title}</h2>
      <div className="mt-2 space-y-3">
        {section.dictKeys.map((key) => (
          <DictBody key={key} dictKey={key} dict={dict} />
        ))}
        {children}
      </div>
    </section>
  );
}

/**
 * Render one dictionary entry as a body paragraph (term + detail). A missing key
 * degrades to the key label + "(popis chybí)" — never a thrown undefined.
 */
function DictBody({ dictKey, dict }: { dictKey: string; dict: Dictionary }) {
  const entry: DictionaryEntry | undefined = dict[dictKey];
  if (!entry) {
    return (
      <p data-dict-missing={dictKey} className="text-sm text-slate-400">
        {dictKey} <span className="italic">(popis chybí)</span>
      </p>
    );
  }
  return (
    <div data-dict-key={dictKey}>
      <p className="text-sm font-medium text-slate-800">{entry.term}</p>
      <p className="text-sm text-slate-600">{entry.detailTemplate}</p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Search — filter SECTIONS by keywords + each entry's DictionaryEntry.keywords
// ---------------------------------------------------------------------------

/**
 * Case-insensitive substring filter. A section matches when the query appears in
 * its `title`/`keywords` OR in any of its dictionary entries' `term`/`keywords`
 * (so Help search and the live UI share one terminology index).
 */
function matchesQuery(section: HelpSection, dict: Dictionary, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;

  const haystack: string[] = [section.title, section.keywords];
  for (const key of section.dictKeys) {
    const entry = dict[key];
    if (entry) {
      haystack.push(entry.term, entry.headlineTemplate, entry.detailTemplate, entry.keywords.join(' '));
    }
  }
  return haystack.join(' ').toLowerCase().includes(q);
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

export function ScreenF() {
  const explanationsQuery = useQuery({
    queryKey: ['explanations'],
    queryFn: () => getExplanations('cs'),
    staleTime: 5 * 60_000,
  });
  const dict: Dictionary = explanationsQuery.data ?? {};
  const dictFailed = explanationsQuery.isError && !explanationsQuery.data;

  const [query, setQuery] = useState('');

  const visibleSections = useMemo(
    () => SECTIONS.filter((s) => matchesQuery(s, dict, query)),
    [dict, query],
  );

  // ── scrollspy (IntersectionObserver over the Section refs) ────────────────
  const refs = useRef<Map<string, HTMLElement>>(new Map());
  const [activeId, setActiveId] = useState<string>(SECTIONS[0]?.id ?? '');

  const registerRef = useMemo(
    () => (id: string, el: HTMLElement | null) => {
      if (el) refs.current.set(id, el);
      else refs.current.delete(id);
    },
    [],
  );

  useEffect(() => {
    if (typeof IntersectionObserver === 'undefined') return;
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        const id = visible[0]?.target.getAttribute('data-section');
        if (id) setActiveId(id);
      },
      { rootMargin: '-80px 0px -60% 0px', threshold: 0 },
    );
    for (const el of refs.current.values()) observer.observe(el);
    return () => observer.disconnect();
    // Re-observe when the visible set changes (search adds/removes sections).
  }, [visibleSections]);

  const noMatches = query.trim() !== '' && visibleSections.length === 0;

  return (
    <section className="space-y-6 pb-12" aria-label="Nápověda">
      {/* ── hero (dark gradient — intentional for the Help hero) ─────────────── */}
      <header
        data-help-hero
        className="rounded-b-2xl bg-gradient-to-br from-slate-900 via-violet-900 to-cyan-900 px-6 py-10 text-white sm:px-10"
      >
        <h1 className="text-3xl font-bold">Nápověda</h1>
        <p className="mt-2 max-w-2xl text-sm text-cyan-100/90">
          Jak číst dashboard, co znamenají stavy, brány, kontrolní body a riziko — vysvětleno
          lidskou řečí. Stejné pojmy, jaké uvidíš v živé appce.
        </p>
        <div className="mt-5 max-w-md">
          <input
            type="search"
            data-help-search
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Hledej v nápovědě…"
            aria-label="Hledej v nápovědě"
            className="w-full rounded-lg border border-white/20 bg-white/10 px-4 py-2.5 text-sm text-white placeholder:text-cyan-100/60 focus:border-cyan-300 focus:outline-none focus:ring-2 focus:ring-cyan-400/40"
          />
        </div>
      </header>

      <div className="mx-auto grid max-w-5xl grid-cols-1 gap-6 px-4 sm:px-6 lg:grid-cols-[220px_1fr]">
        {/* ── TOC: sticky sidebar (desktop) / dropdown (mobile) ──────────────── */}
        <Toc
          sections={visibleSections}
          activeId={activeId}
          onJump={(id) => {
            setActiveId(id);
            refs.current.get(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
          }}
        />

        {/* ── content ────────────────────────────────────────────────────────── */}
        <div className="min-w-0 space-y-5">
          {dictFailed && (
            <p data-dict-error className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700">
              Slovníček se nepodařilo načíst — texty mohou chybět.
            </p>
          )}

          {noMatches ? (
            <p data-no-matches className="text-sm text-slate-500">
              Nic nenalezeno — zkus jiný výraz.
            </p>
          ) : (
            visibleSections.map((s) => (
              <Section key={s.id} section={s} dict={dict} registerRef={registerRef}>
                <SectionExtras id={s.id} />
              </Section>
            ))
          )}
        </div>
      </div>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Per-section extra content — Steps, Kbd, and the live <Demo> blocks.
// ---------------------------------------------------------------------------

function SectionExtras({ id }: { id: string }) {
  switch (id) {
    case 'fsm':
      return (
        <>
          <p className="text-sm text-slate-600">
            Každý běh prochází stavy v pořadí <Kbd>READY</Kbd> → <Kbd>EXECUTE</Kbd> →{' '}
            <Kbd>GATES</Kbd> → <Kbd>DONE</Kbd>. Barva tečky říká, kde běh právě je.
          </p>
          <Demo>
            <FsmTimeline nodes={DEMO_FSM_NODES} />
          </Demo>
        </>
      );
    case 'kontrolni-body':
      return (
        <>
          <p className="text-sm text-slate-600">
            Šest kontrolních bodů (<Kbd>CP1</Kbd>–<Kbd>CP6</Kbd>) hlídá plán, EPICu, krok, brány,
            audit a dokončení. Tečka u každého ukazuje výsledek.
          </p>
          <Demo>
            <CheckpointStrip checkpoints={DEMO_CHECKPOINTS} />
          </Demo>
        </>
      );
    case 'cti-dashboard':
      return (
        <>
          <ol className="space-y-2">
            <Step n={1}>Nahoře je shrnutí celé flotily — kolik projektů běží, kde se čeká.</Step>
            <Step n={2}>Každá dlaždice je jeden projekt; barva tečky = stav běhu.</Step>
            <Step n={3}>Pruh ukazuje postup (krok N/M), proužek kontrol = kontrolní body.</Step>
          </ol>
          <Demo>
            <ProjectTile project={DEMO_PROJECT} />
          </Demo>
        </>
      );
    case 'riziko':
      return (
        <p data-riziko-note className="text-sm text-slate-600">
          Úroveň rizika (nízké / střední / vysoké) se počítá <strong>deterministicky ze
          skutečných počtů</strong> — z porušení, selhání bran, eskalací a obcházení kontrol.
          Konkrétní číslo pravděpodobnosti úspěchu zatím není: přesnější odhad{' '}
          <strong>přijde s agentem (MVP2)</strong>, proto je ten slot prázdný.
        </p>
      );
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// TOC — sticky sidebar (desktop) + "Obsah" dropdown (mobile)
// ---------------------------------------------------------------------------

function Toc({
  sections,
  activeId,
  onJump,
}: {
  sections: HelpSection[];
  activeId: string;
  onJump: (id: string) => void;
}) {
  return (
    <nav data-toc aria-label="Obsah" className="lg:sticky lg:top-20 lg:self-start">
      {/* Mobile: a native dropdown jumps to the section. */}
      <div className="lg:hidden">
        <label className="mb-1 block text-xs font-medium text-slate-500" htmlFor="toc-select">
          Obsah
        </label>
        <select
          id="toc-select"
          data-toc-select
          value={activeId}
          onChange={(e) => onJump(e.target.value)}
          className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm text-slate-700"
        >
          {sections.map((s) => (
            <option key={s.id} value={s.id}>
              {s.title}
            </option>
          ))}
        </select>
      </div>

      {/* Desktop: a sticky list, the active section highlighted. */}
      <ul className="hidden flex-col gap-0.5 lg:flex">
        <li className="mb-1 px-2 text-xs font-semibold uppercase tracking-wide text-slate-400">
          Obsah
        </li>
        {sections.map((s) => (
          <li key={s.id}>
            <button
              type="button"
              data-toc-link={s.id}
              aria-current={activeId === s.id ? 'true' : undefined}
              onClick={() => onJump(s.id)}
              className={cn(
                'w-full rounded-md px-2 py-1.5 text-left text-sm',
                activeId === s.id
                  ? 'bg-violet-50 font-medium text-violet-700'
                  : 'text-slate-600 hover:bg-slate-50',
              )}
            >
              {s.title}
            </button>
          </li>
        ))}
      </ul>
    </nav>
  );
}
