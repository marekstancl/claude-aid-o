/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/react';
import { STATUS, type Checkpoint, type CheckpointId, type Verdict } from '@aid/contract';
import { CheckpointStrip } from './CheckpointStrip';

/** Build a Checkpoint with sane defaults, overridable per-test. */
function cp(over: Partial<Checkpoint> & { id: CheckpointId }): Checkpoint {
  return {
    id: over.id,
    label: over.label ?? over.id,
    dispatched: over.dispatched ?? true,
    verdict: over.verdict ?? null,
    provenance: over.provenance ?? null,
    provenanceSource: over.provenanceSource ?? null,
    repeatCount: over.repeatCount ?? null,
    repeatSource: over.repeatSource ?? null,
    outputs: over.outputs ?? [],
  };
}

function strip(checkpoints: Checkpoint[]): HTMLElement {
  return render(<CheckpointStrip checkpoints={checkpoints} />).container
    .querySelector('[data-checkpoint-strip]') as HTMLElement;
}

describe('CheckpointStrip — §6.2 verdict → STATUS mapping', () => {
  // The real contract enum, plus the §8.5 expected §6.2 token per verdict.
  const cases: { verdict: Verdict; status: keyof typeof STATUS; word: string }[] = [
    { verdict: 'pass', status: 'proslo', word: STATUS.proslo.label },
    { verdict: 'fail', status: 'selhalo', word: STATUS.selhalo.label },
    { verdict: 'unverifiable', status: 'pozor', word: STATUS.pozor.label },
    { verdict: 'skipped', status: 'ceka', word: STATUS.ceka.label },
  ];

  it.each(cases)('maps verdict "$verdict" → §6.2 token "$status"', ({ verdict, status, word }) => {
    const el = strip([cp({ id: 'CP1', verdict })]);
    const node = el.querySelector('[data-cp="CP1"]') as HTMLElement;
    expect(node).toHaveAttribute('data-status', status);
    expect(node).toHaveTextContent(word);
  });

  it('renders a null verdict as "?" with the idle (necinne) token — never 0, never a fabricated pass', () => {
    const el = strip([cp({ id: 'CP2', verdict: null })]);
    const node = el.querySelector('[data-cp="CP2"]') as HTMLElement;
    expect(node).toHaveAttribute('data-status', 'necinne');
    expect(node).toHaveTextContent('?');
    // Must NOT have fabricated a pass.
    expect(node).not.toHaveAttribute('data-status', 'proslo');
    expect(node).not.toHaveTextContent(STATUS.proslo.label);
    // Must NOT print a literal "0".
    expect(node.textContent).not.toMatch(/\b0\b/);
  });

  it('renders null provenance as "stopa: nezaznamenáno" (not recorded, never "unverifiable")', () => {
    const el = strip([cp({ id: 'CP3', verdict: 'pass', provenance: null })]);
    const node = el.querySelector('[data-cp="CP3"]') as HTMLElement;
    expect(node.getAttribute('title')).toContain('stopa: nezaznamenáno');
    expect(node.getAttribute('title')).not.toContain('unverifiable');
  });

  it('renders repeatCount:null as "?" superscript — never 0 (legacy/stub CP2/3/4)', () => {
    const el = strip([cp({ id: 'CP2', verdict: 'pass', repeatCount: null })]);
    const sup = el.querySelector('[data-cp="CP2"] sup') as HTMLElement;
    expect(sup).toBeInTheDocument();
    expect(sup).toHaveAttribute('data-repeat', 'null');
    expect(sup).toHaveTextContent('?');
    expect(sup.textContent).not.toMatch(/\b0\b/);
  });

  it('renders a present repeatCount ≥ 2 as "×N"', () => {
    const el = strip([cp({ id: 'CP4', verdict: 'fail', repeatCount: 3 })]);
    const sup = el.querySelector('[data-cp="CP4"] sup') as HTMLElement;
    expect(sup).toHaveTextContent('×3');
  });
});

describe('CheckpointStrip — empty (stub run)', () => {
  it('renders six grey necinne placeholders + gloss, never six green dots or a crash', () => {
    const { container } = render(<CheckpointStrip checkpoints={[]} />);
    const el = container.querySelector('[data-checkpoint-strip]') as HTMLElement;
    expect(el).toHaveAttribute('data-empty');
    // Six placeholder dots, all idle.
    const dots = el.querySelectorAll('[data-status="necinne"]');
    expect(dots.length).toBe(6);
    // No fabricated green passes.
    expect(el.querySelector('[data-status="proslo"]')).toBeNull();
    // Honest gloss.
    expect(el).toHaveTextContent('kontroly zatím neproběhly');
  });
});
