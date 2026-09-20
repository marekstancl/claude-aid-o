/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/react';
import type { ReporterDelivery } from '@aid/contract';
import { ReporterDeliveryPanel } from './ReporterDeliveryPanel';

function makeDelivery(overrides: Partial<ReporterDelivery> = {}): ReporterDelivery {
  return {
    present: true,
    outcome: 'pass',
    generatedAt: '2026-06-20T12:00:00Z',
    generatedBy: 'reporter-0.1',
    summaryCs: 'All tests passed',
    rawRelPath: 'reporter-delivery.md',
    testEvidence: [
      { name: 'unit tests', relPath: 'reporter/unit.xml', exists: true },
      { name: 'integration tests', relPath: 'reporter/integration.xml', exists: true },
      { name: 'smoke tests', relPath: 'reporter/smoke.xml', exists: false },
    ],
    warnings: [],
    ...overrides,
  };
}

describe('ReporterDeliveryPanel', () => {
  it('shows "Reporter zatím neběžel" when present is false', () => {
    const { container } = render(
      <ReporterDeliveryPanel delivery={makeDelivery({ present: false })} />
    );
    expect(container.querySelector('[data-reporter-absent]')).toBeInTheDocument();
    expect(container.textContent).toContain('Reporter zatím neběžel');
  });

  it('renders delivery outcome badge', () => {
    const { container } = render(
      <ReporterDeliveryPanel delivery={makeDelivery({ outcome: 'pass' })} />
    );
    expect(container.textContent).toContain('dodáno');
  });

  it('renders test evidence with correct exists status', () => {
    const { container } = render(
      <ReporterDeliveryPanel
        delivery={makeDelivery()}
        projectId="proj"
        epicId="E-001"
        runId="run123"
      />
    );
    const evidenceRows = container.querySelectorAll('[data-evidence-exists]');
    expect(evidenceRows).toHaveLength(3);
    expect(evidenceRows[0]).toHaveAttribute('data-evidence-exists', 'true');
    expect(evidenceRows[1]).toHaveAttribute('data-evidence-exists', 'true');
    expect(evidenceRows[2]).toHaveAttribute('data-evidence-exists', 'false');
  });

  it('shows "chybí na disku" for missing evidence', () => {
    const { container } = render(
      <ReporterDeliveryPanel delivery={makeDelivery()} />
    );
    expect(container.textContent).toContain('chybí na disku');
  });

  it('links evidence artifacts through /api/epics endpoint when run coords provided', () => {
    const { container } = render(
      <ReporterDeliveryPanel
        delivery={makeDelivery()}
        projectId="myproj"
        epicId="E-047"
        runId="run456"
      />
    );
    const links = container.querySelectorAll('a[href*="/api/epics"]');
    expect(links.length).toBeGreaterThan(0);
    // Check that the link uses the correct pattern
    const firstLink = links[0] as HTMLAnchorElement;
    expect(firstLink.href).toContain('/api/epics/myproj/E-047/runs/run456/file');
    expect(firstLink.href).toContain('name=reporter%2Funit.xml');
  });

  it('does not render evidence as links when run coords are missing', () => {
    const { container } = render(
      <ReporterDeliveryPanel delivery={makeDelivery()} />
    );
    const links = container.querySelectorAll('a[href*="/api/epics"]');
    expect(links).toHaveLength(0);
  });

  it('encodes artifact names in URLs correctly', () => {
    const { container } = render(
      <ReporterDeliveryPanel
        delivery={makeDelivery({
          testEvidence: [
            { name: 'file with spaces', relPath: 'reporter/file with spaces.txt', exists: true },
          ],
        })}
        projectId="proj"
        epicId="E-001"
        runId="run123"
      />
    );
    const link = container.querySelector('a[href*="/api/epics"]') as HTMLAnchorElement;
    expect(link.href).toContain('name=reporter%2Ffile%20with%20spaces.txt');
  });

  it('encodes projectId, epicId, runId in URL path', () => {
    const { container } = render(
      <ReporterDeliveryPanel
        delivery={makeDelivery()}
        projectId="my/proj"
        epicId="E-001/2"
        runId="run-123"
      />
    );
    const link = container.querySelector('a[href*="/api/epics"]') as HTMLAnchorElement;
    expect(link.href).toContain('/api/epics/my%2Fproj/E-001%2F2/runs/run-123/file');
  });

  it('does not render delivery report raw trigger (not allow-listed)', () => {
    const { container } = render(
      <ReporterDeliveryPanel
        delivery={makeDelivery({ rawRelPath: 'some-report.md' })}
        projectId="proj"
        epicId="E-001"
        runId="run123"
      />
    );
    // RawMarkdownDialog should not be rendered for delivery reports
    // (they are not on the server allow-list)
    const rawTrigger = container.querySelector('[data-raw-md-trigger]');
    expect(rawTrigger).toBeNull();
  });

  it('shows evidence count in heading', () => {
    const { container } = render(
      <ReporterDeliveryPanel
        delivery={makeDelivery({
          testEvidence: [
            { name: 'test1', relPath: 'reporter/test1.txt', exists: true },
            { name: 'test2', relPath: 'reporter/test2.txt', exists: true },
          ],
        })}
      />
    );
    expect(container.textContent).toContain('Důkazy (2)');
  });

  it('shows "žádné doložené důkazy" when no evidence', () => {
    const { container } = render(
      <ReporterDeliveryPanel delivery={makeDelivery({ testEvidence: [] })} />
    );
    expect(container.textContent).toContain('žádné doložené důkazy');
  });
});
