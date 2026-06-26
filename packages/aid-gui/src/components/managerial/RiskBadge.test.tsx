/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { STATUS, type Risk, type RiskLevel } from '@aid/contract';
import { RiskBadge, RISK_STATUS } from './RiskBadge';

function risk(over: Partial<Risk> & { level: RiskLevel }): Risk {
  return {
    level: over.level,
    reasons: over.reasons ?? [],
    confidence: over.confidence ?? 'high',
  };
}

/** Each RiskLevel → its §13.10 concept:risk:* §6.2 colour token. */
const CASES: { level: RiskLevel; status: keyof typeof STATUS }[] = [
  { level: 'nizke', status: 'proslo' },
  { level: 'stredni', status: 'pozor' },
  { level: 'vysoke', status: 'zablokovano' },
  { level: 'neurceno', status: 'ceka' },
];

describe('RiskBadge — §13.10 concept:risk:* colour mapping', () => {
  it.each(CASES)('maps level "$level" → §6.2 token "$status" with its colour', ({ level, status }) => {
    const { container } = render(<RiskBadge risk={risk({ level })} />);
    const badge = container.querySelector('[data-risk-badge]') as HTMLElement;
    expect(badge).toHaveAttribute('data-level', level);
    expect(badge).toHaveAttribute('data-status', status);
    // Colour is the canonical STATUS colour for the mapped token — never empty.
    expect(badge.style.color).toBe(STATUS[status].color);
    expect(badge.style.color).not.toBe('');
    // Registry mapping agrees.
    expect(RISK_STATUS[level]).toBe(status);
  });

  it('never relies on colour alone — every badge carries a word AND an icon', () => {
    for (const { level } of CASES) {
      const { container } = render(<RiskBadge risk={risk({ level })} />);
      const badge = container.querySelector('[data-risk-badge]') as HTMLElement;
      expect(badge.textContent?.trim()).not.toBe('');
      expect(badge.querySelector('svg')).toBeInTheDocument();
    }
  });

  it('opens a Popover of the reasons on click', () => {
    render(
      <RiskBadge
        risk={risk({
          level: 'vysoke',
          reasons: [
            { text: 'Otevřená blokující porušení', status: 'zablokovano', signal: 'open_blocking_violations', value: 2 },
          ],
        })}
      />,
    );
    fireEvent.click(screen.getByText(/Riziko vysoké/));
    expect(screen.getByText('Otevřená blokující porušení')).toBeInTheDocument();
    // The countable value rides along as an audit trail.
    expect(screen.getByText('(2)')).toBeInTheDocument();
  });

  it('level "neurceno" → word "neurčeno" and a Popover "málo dat" (never a fabricated low risk)', () => {
    const { container } = render(<RiskBadge risk={risk({ level: 'neurceno', reasons: [] })} />);
    const badge = container.querySelector('[data-risk-badge]') as HTMLElement;
    expect(badge).toHaveTextContent('neurčeno');
    // Must NOT have rendered the low-risk word/token.
    expect(badge).not.toHaveTextContent('nízké');
    expect(badge).not.toHaveAttribute('data-status', 'proslo');

    fireEvent.click(badge);
    expect(screen.getByText('málo dat')).toBeInTheDocument();
  });
});
