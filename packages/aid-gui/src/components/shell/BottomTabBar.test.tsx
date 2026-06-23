/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { BottomTabBar } from './BottomTabBar';

function renderBar() {
  return render(
    <MemoryRouter>
      <BottomTabBar onMoreClick={() => {}} />
    </MemoryRouter>,
  );
}

const REV3_LABELS = ['Co řešit', 'Přehled', 'Dění', 'Compliance', 'Více'];

describe('BottomTabBar', () => {
  it('renders exactly the five Rev 3 tabs in order', () => {
    renderBar();
    for (const label of REV3_LABELS) {
      expect(screen.getByText(label)).toBeInTheDocument();
    }
    // Exactly five interactive tabs (4 NavLink + 1 "Více" button).
    const nav = screen.getByRole('navigation');
    const tabs = nav.querySelectorAll('a,button');
    expect(tabs.length).toBe(5);
  });

  it('gives every tab a >=44px touch target', () => {
    renderBar();
    const nav = screen.getByRole('navigation');
    const tabs = Array.from(nav.querySelectorAll('a,button'));
    expect(tabs).toHaveLength(5);
    for (const tab of tabs) {
      const cls = tab.className;
      expect(cls).toContain('min-h-[44px]');
      expect(cls).toContain('min-w-[44px]');
    }
  });

  it('the bar itself is 56px (h-14) with safe-area-inset bottom padding', () => {
    renderBar();
    const nav = screen.getByRole('navigation');
    expect(nav.className).toContain('h-14');
    expect(nav.className).toContain('pb-[env(safe-area-inset-bottom)]');
  });

  it('"Více" is a button that fires onMoreClick', async () => {
    const onMore = vi.fn();
    render(
      <MemoryRouter>
        <BottomTabBar onMoreClick={onMore} />
      </MemoryRouter>,
    );
    const more = screen.getByText('Více').closest('button')!;
    more.click();
    expect(onMore).toHaveBeenCalledTimes(1);
  });
});
