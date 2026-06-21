/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/react';
import type { BacklogDelta, BacklogDeltaItem } from '@aid/contract';
import { BacklogDeltaList } from './BacklogDeltaList';

function item(id: string, title: string, change: BacklogDeltaItem['changeSince']): BacklogDeltaItem {
  return { id, title, type: null, area: null, status: null, priority: null, changeSince: change };
}

function delta(over: Partial<BacklogDelta>): BacklogDelta {
  return {
    scope: 'project',
    projectId: 'wan',
    planId: null,
    openCount: 0,
    closedCount: 0,
    firstVisit: false,
    lastSeen: '2026-06-01T00:00:00Z',
    added: [],
    closed: [],
    priorityChanged: [],
    statusChanged: [],
    warnings: [],
    ...over,
  };
}

describe('BacklogDeltaList — §13.7 four buckets', () => {
  it('renders all four buckets with their rows', () => {
    const { container } = render(
      <BacklogDeltaList
        delta={delta({
          added: [item('B-1', 'nový item', 'added')],
          closed: [item('B-2', 'zavřený item', 'closed')],
          priorityChanged: [item('B-3', 'přepriorizovaný', 'priorityChanged')],
          statusChanged: [item('B-4', 'změna stavu', 'statusChanged')],
        })}
      />,
    );
    const root = container.querySelector('[data-backlog-delta]') as HTMLElement;
    expect(root.querySelector('[data-bucket="added"]')).toBeInTheDocument();
    expect(root.querySelector('[data-bucket="closed"]')).toBeInTheDocument();
    expect(root.querySelector('[data-bucket="priorityChanged"]')).toBeInTheDocument();
    expect(root.querySelector('[data-bucket="statusChanged"]')).toBeInTheDocument();
    expect(root).toHaveTextContent('nový item');
    expect(root).toHaveTextContent('zavřený item');
    expect(root).toHaveTextContent('přepriorizovaný');
    expect(root).toHaveTextContent('změna stavu');
  });

  it('firstVisit → "bez porovnání - vše jako nové" (never four empty buckets)', () => {
    const { container } = render(<BacklogDeltaList delta={delta({ firstVisit: true })} />);
    expect(container.querySelector('[data-backlog-firstvisit]')).toHaveTextContent(
      'bez porovnání - vše jako nové',
    );
    // No bucket scaffold on a first visit.
    expect(container.querySelector('[data-backlog-delta]')).toBeNull();
  });

  it('is read-only — renders no buttons that mutate backlog (only filter chips)', () => {
    const { container } = render(
      <BacklogDeltaList delta={delta({ added: [item('B-1', 'x', 'added')] })} />,
    );
    // Every button present is a filter chip; none is a write action.
    const buttons = container.querySelectorAll('button');
    for (const b of buttons) {
      expect(b).toHaveAttribute('data-filter-chip');
    }
  });

  it('an empty bucket shows a calm "nic" line, not a disappearing block', () => {
    const { container } = render(
      <BacklogDeltaList delta={delta({ added: [item('B-1', 'x', 'added')] })} />,
    );
    const closed = container.querySelector('[data-bucket="closed"]') as HTMLElement;
    expect(closed).toBeInTheDocument();
    expect(closed).toHaveTextContent('nic');
  });
});
