/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/react';
import { STATUS, type StatusKey } from '@aid/contract';
import { StatusBadge, STATUS_ICON } from './StatusBadge';

const TOKENS = Object.keys(STATUS) as StatusKey[];

/** Read the rendered colour off the badge's inline style (colour signal). */
function colorOf(el: HTMLElement): string {
  return el.style.color;
}

describe('StatusBadge — §6.2 / §8.5 atomic primitive', () => {
  it('covers exactly the eight §6.2 tokens', () => {
    expect(TOKENS).toHaveLength(8);
    expect(new Set(TOKENS)).toEqual(
      new Set(['bezi', 'ceka', 'proslo', 'selhalo', 'zablokovano', 'eskalace', 'pozor', 'necinne']),
    );
    // The §8.5 icon map keys must match the §6.2 tokens 1:1.
    expect(Object.keys(STATUS_ICON).sort()).toEqual([...TOKENS].sort());
  });

  it.each(TOKENS)('renders token "%s" with its Czech word, icon and colour', (token) => {
    const { container } = render(<StatusBadge status={token} />);
    const badge = container.querySelector('[data-status]') as HTMLElement;

    // §6.2 Czech word (non-colour signal #1).
    expect(badge).toHaveTextContent(STATUS[token].label);
    // §8.5 icon present (non-colour signal #2).
    expect(badge.querySelector('svg')).toBeInTheDocument();
    // Canonical STATUS colour applied (and never undefined/empty).
    expect(colorOf(badge)).toBe(STATUS[token].color);
    expect(colorOf(badge)).not.toBe('');
  });

  it('never relies on colour alone — every badge carries a word AND an icon', () => {
    for (const token of TOKENS) {
      const { container } = render(<StatusBadge status={token} />);
      const badge = container.querySelector('[data-status]') as HTMLElement;
      expect(badge.textContent?.trim()).not.toBe('');
      expect(badge.querySelector('svg')).toBeInTheDocument();
    }
  });

  it('is colorblind-safe: red selhalo vs green prošlo differ by word AND icon', () => {
    const fail = render(<StatusBadge status="selhalo" />).container.querySelector(
      '[data-status]',
    ) as HTMLElement;
    const pass = render(<StatusBadge status="proslo" />).container.querySelector(
      '[data-status]',
    ) as HTMLElement;

    // Distinct Czech words.
    expect(fail).toHaveTextContent('selhalo');
    expect(pass).toHaveTextContent('prošlo');
    expect(fail.textContent).not.toBe(pass.textContent);

    // Distinct icons (different lucide component → different rendered markup).
    expect(STATUS_ICON.selhalo).not.toBe(STATUS_ICON.proslo);
    const failIcon = fail.querySelector('svg')?.innerHTML;
    const passIcon = pass.querySelector('svg')?.innerHTML;
    expect(failIcon).toBeTruthy();
    expect(passIcon).toBeTruthy();
    expect(failIcon).not.toBe(passIcon);
  });

  it('honours an explicit label override while keeping icon + colour', () => {
    const { container } = render(<StatusBadge status="bezi" label="vlastní" />);
    const badge = container.querySelector('[data-status]') as HTMLElement;
    expect(badge).toHaveTextContent('vlastní');
    expect(badge.querySelector('svg')).toBeInTheDocument();
    expect(colorOf(badge)).toBe(STATUS.bezi.color);
  });
});
