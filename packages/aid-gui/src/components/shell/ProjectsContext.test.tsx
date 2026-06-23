// @vitest-environment jsdom
/**
 * Regression guard for the REOPEN MED finding "Výpadek API se vydává za
 * neexistující projekt": a getProjects() failure must surface as `error: true`
 * (→ "Projekty se nepodařilo načíst"), NOT as an empty-but-loaded success that a
 * deep-link would mislabel "Projekt nenalezen".
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ProjectsProvider, useProjects } from './ProjectsContext';

function Probe() {
  const { loading, loaded, error, projects } = useProjects();
  return (
    <div>
      <span data-testid="loading">{String(loading)}</span>
      <span data-testid="loaded">{String(loaded)}</span>
      <span data-testid="error">{String(error)}</span>
      <span data-testid="count">{projects.length}</span>
    </div>
  );
}

function renderProbe() {
  const qc = new QueryClient();
  return render(
    <QueryClientProvider client={qc}>
      <ProjectsProvider><Probe /></ProjectsProvider>
    </QueryClientProvider>,
  );
}

afterEach(() => vi.unstubAllGlobals());

describe('ProjectsContext — API outage is not "project not found"', () => {
  it('a fetch failure sets error:true (loaded, empty) — distinguishable from a missing project', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('network down'); }));
    renderProbe();
    await waitFor(() => expect(screen.getByTestId('loaded').textContent).toBe('true'));
    expect(screen.getByTestId('error').textContent).toBe('true');
    expect(screen.getByTestId('count').textContent).toBe('0');
  });

  it('a successful empty list is NOT an error (error stays false)', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, json: async () => ({ ok: true, data: [] }) }) as unknown as Response));
    renderProbe();
    await waitFor(() => expect(screen.getByTestId('loaded').textContent).toBe('true'));
    expect(screen.getByTestId('error').textContent).toBe('false');
  });
});
