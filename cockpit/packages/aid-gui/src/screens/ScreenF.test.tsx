/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, cleanup, fireEvent, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { DictionaryEntry } from '@aid/contract';
import { resolveExplanation } from '../lib/explain';
import { ScreenF, SECTIONS } from './ScreenF';
import * as api from '../lib/api';

vi.mock('../lib/api', () => ({
  ApiError: class ApiError extends Error {
    code: string;
    constructor(code: string, message: string) {
      super(message);
      this.name = 'ApiError';
      this.code = code;
    }
  },
  getExplanations: vi.fn(),
}));

const getExplanations = vi.mocked(api.getExplanations);

// ── fixture dictionary — the SAME DictionaryEntry shape served by /api/explanations
//    and resolved by the live UI via resolveExplanation(). Every key referenced by
//    a SECTION has an entry here so the bodies render from real terms. ──────────
function entry(over: Partial<DictionaryEntry> & Pick<DictionaryEntry, 'id'>): DictionaryEntry {
  return {
    kind: 'concept',
    status: 'ceka',
    headlineTemplate: `${over.id} headline`,
    detailTemplate: `${over.id} detail`,
    term: `${over.id} term`,
    keywords: [over.id],
    ...over,
  };
}

function buildDict(): Record<string, DictionaryEntry> {
  const keys = new Set<string>();
  for (const s of SECTIONS) for (const k of s.dictKeys) keys.add(k);
  const dict: Record<string, DictionaryEntry> = {};
  for (const k of keys) dict[k] = entry({ id: k });

  // A couple of real-content entries the assertions key off of:
  dict['concept:success_probability_mvp2'] = entry({
    id: 'success_probability_mvp2',
    headlineTemplate: 'Přesnější odhad úspěchu přijde s agentem (MVP2).',
    detailTemplate: 'Přesnější odhad pravděpodobnosti úspěchu přijde s agentem (MVP2).',
    term: 'Odhad úspěchu (MVP2)',
    keywords: ['pravděpodobnost', 'úspěch', 'odhad', 'mvp2', 'agent'],
  });
  dict['cp:CP1'] = entry({
    id: 'CP1',
    kind: 'cp',
    headlineTemplate: 'CP1 — kontrola plánu',
    detailTemplate: 'CP1 — kontrola plánu před tím, než se z něj udělá EPICa.',
    term: 'CP1 — kontrola plánu',
    keywords: ['cp1', 'checkpoint', 'kontrolní bod', 'plán'],
  });
  dict['state:READY'] = entry({
    id: 'READY',
    kind: 'state',
    headlineTemplate: 'Připraveno ke spuštění',
    detailTemplate: 'EPICa má hotový plán a čeká, až ji pustíš.',
    term: 'Připraveno (READY)',
    keywords: ['ready', 'připraveno', 'fronta'],
  });
  return dict;
}

function renderScreen() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <ScreenF />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  getExplanations.mockResolvedValue(buildDict());
});
afterEach(() => {
  cleanup();
});

describe('ScreenF — Help (/help)', () => {
  it('renders all 13 SECTIONS', async () => {
    expect(SECTIONS).toHaveLength(13);
    const { container } = renderScreen();
    await waitFor(() => {
      expect(container.querySelector('[data-dict-key="cp:CP1"]')).toBeInTheDocument();
    });
    const rendered = Array.from(container.querySelectorAll('[data-section]')).map((el) =>
      el.getAttribute('data-section'),
    );
    for (const s of SECTIONS) expect(rendered).toContain(s.id);
    expect(rendered).toHaveLength(13);
  });

  it('renders the live <Demo> components (FsmTimeline, CheckpointStrip, ProjectTile)', async () => {
    const { container } = renderScreen();
    await waitFor(() => {
      expect(container.querySelector('[data-fsm-timeline]')).toBeInTheDocument();
    });
    // FsmTimeline demo walk READY/EXECUTE/GATES/DONE
    expect(container.querySelector('[data-node="READY"]')).toBeInTheDocument();
    expect(container.querySelector('[data-node="DONE"]')).toBeInTheDocument();
    // CheckpointStrip CP1-CP6 dots
    expect(container.querySelector('[data-checkpoint-strip] [data-cp="CP1"]')).toBeInTheDocument();
    expect(container.querySelector('[data-checkpoint-strip] [data-cp="CP6"]')).toBeInTheDocument();
    // ProjectTile demo
    expect(container.querySelector('[data-project-tile="ukazka"]')).toBeInTheDocument();
  });

  it('search filters sections by keywords (and zero matches → honest empty)', async () => {
    const { container } = renderScreen();
    await waitFor(() => {
      expect(container.querySelectorAll('[data-section]')).toHaveLength(13);
    });
    const box = within(container).getByLabelText('Hledej v nápovědě') as HTMLInputElement;

    // "mvp2" keyword narrows to the riziko section (it carries that keyword).
    fireEvent.change(box, { target: { value: 'mvp2' } });
    await waitFor(() => {
      const ids = Array.from(container.querySelectorAll('[data-section]')).map((el) =>
        el.getAttribute('data-section'),
      );
      expect(ids).toContain('riziko');
      expect(ids).not.toContain('co-je-aid');
    });

    // Zero matches → "Nic nenalezeno".
    fireEvent.change(box, { target: { value: 'zzzzz-nic-takoveho' } });
    await waitFor(() => {
      expect(container.querySelector('[data-no-matches]')).toBeInTheDocument();
      expect(container.querySelectorAll('[data-section]')).toHaveLength(0);
    });
    expect(within(container).getByText(/Nic nenalezeno/)).toBeInTheDocument();
  });

  it('section bodies render terms from the SAME DictionaryEntry set as the live UI', async () => {
    const dict = buildDict();
    getExplanations.mockResolvedValue(dict);
    const { container } = renderScreen();

    // The CP1 body term is exactly the dictionary entry's `term` — the same entry
    // a live screen would feed to resolveExplanation() for its headline.
    await waitFor(() => {
      expect(container.querySelector('[data-dict-key="cp:CP1"]')).toBeInTheDocument();
    });
    const cp1 = container.querySelector('[data-dict-key="cp:CP1"]') as HTMLElement;
    expect(within(cp1).getByText(dict['cp:CP1'].term)).toBeInTheDocument();
    expect(within(cp1).getByText(dict['cp:CP1'].detailTemplate)).toBeInTheDocument();

    // Cross-check: the live UI resolves the SAME entry to this exact headline.
    const live = resolveExplanation(dict['cp:CP1']);
    expect(live.headline).toBe(dict['cp:CP1'].headlineTemplate);
    expect(live.detail).toBe(dict['cp:CP1'].detailTemplate);
  });

  it('the riziko section explains deterministic level + probability "přijde s agentem (MVP2)"', async () => {
    const { container } = renderScreen();
    await waitFor(() => {
      expect(
        container.querySelector('[data-dict-key="concept:success_probability_mvp2"]'),
      ).toBeInTheDocument();
    });
    const note = container.querySelector('[data-riziko-note]') as HTMLElement;
    const text = note.textContent ?? '';
    expect(text).toMatch(/deterministicky/i);
    expect(text).toMatch(/skutečných počtů/i);
    expect(text).toMatch(/přijde s agentem \(MVP2\)/i);
    // The MVP2 dictionary entry text also surfaces in the section body (dict-sourced).
    const mvp2 = container.querySelector('[data-dict-key="concept:success_probability_mvp2"]') as HTMLElement;
    expect(mvp2).toBeInTheDocument();
    expect(mvp2.textContent).toMatch(/Přesnější odhad pravděpodobnosti úspěchu přijde s agentem \(MVP2\)/);
  });

  it('a dictionary fetch failure still renders the static scaffold + a muted note', async () => {
    getExplanations.mockRejectedValue(new Error('boom'));
    const { container } = renderScreen();
    await waitFor(() => {
      expect(container.querySelector('[data-dict-error]')).toBeInTheDocument();
    });
    // All 13 sections still present (never blank).
    expect(container.querySelectorAll('[data-section]')).toHaveLength(13);
    // A missing key renders "(popis chybí)" rather than throwing.
    expect(container.querySelector('[data-dict-missing="cp:CP1"]')).toBeInTheDocument();
    expect(within(container).getByText(/Slovníček se nepodařilo načíst/)).toBeInTheDocument();
  });
});
