/// <reference types="@testing-library/jest-dom" />
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, fireEvent, waitFor } from '@testing-library/react';
import { RawMarkdownDialog } from './RawMarkdownDialog';
import * as api from '../../lib/api';

vi.mock('../../lib/api', () => ({
  getRunFile: vi.fn(),
  ApiError: class ApiError extends Error {
    code: string;
    constructor(code: string, message: string) {
      super(message);
      this.code = code;
      this.name = 'ApiError';
    }
  },
}));

describe('RawMarkdownDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders no trigger when any run coordinate is missing', () => {
    const { container } = render(
      <RawMarkdownDialog
        projectId="proj"
        epicId="E-001"
        runId="run123"
        // name is missing
        title="Test"
      />
    );
    expect(container.querySelector('[data-raw-md-trigger]')).toBeNull();
  });

  it('renders no trigger when name is empty string', () => {
    const { container } = render(
      <RawMarkdownDialog
        projectId="proj"
        epicId="E-001"
        runId="run123"
        name=""
        title="Test"
      />
    );
    expect(container.querySelector('[data-raw-md-trigger]')).toBeNull();
  });

  it('renders a trigger button when all run coords and name are provided', () => {
    const { container } = render(
      <RawMarkdownDialog
        projectId="proj"
        epicId="E-001"
        runId="run123"
        name="audit-report.md"
        title="Test Report"
      />
    );
    const trigger = container.querySelector('[data-raw-md-trigger]');
    expect(trigger).toBeInTheDocument();
    expect(trigger).toHaveTextContent('Zobrazit zdroj');
  });

  it('uses custom triggerLabel when provided', () => {
    const { container } = render(
      <RawMarkdownDialog
        projectId="proj"
        epicId="E-001"
        runId="run123"
        name="audit-report.md"
        title="Test"
        triggerLabel="Custom Label"
      />
    );
    expect(container.querySelector('[data-raw-md-trigger]')).toHaveTextContent('Custom Label');
  });

  it('fetches the artifact via getRunFile with correct parameters when opened', async () => {
    const mockGetRunFile = vi.mocked(api.getRunFile);
    mockGetRunFile.mockResolvedValue({
      format: 'markdown',
      content: '# Test Content\nHello world',
    });

    const { container } = render(
      <RawMarkdownDialog
        projectId="myproj"
        epicId="E-047"
        runId="run456"
        name="audit-report.md"
        title="Audit Report"
      />
    );

    const trigger = container.querySelector('[data-raw-md-trigger]') as HTMLButtonElement;
    fireEvent.click(trigger);

    await waitFor(() => {
      expect(mockGetRunFile).toHaveBeenCalledWith('myproj', 'E-047', 'run456', 'audit-report.md');
    });
  });

  it('renders the fetched content inside the drawer', async () => {
    const mockGetRunFile = vi.mocked(api.getRunFile);
    mockGetRunFile.mockResolvedValue({
      format: 'markdown',
      content: '# Audit Results\nScore: 85/100',
    });

    const { container, baseElement } = render(
      <RawMarkdownDialog
        projectId="proj"
        epicId="E-001"
        runId="run123"
        name="audit-report.md"
        title="Audit"
      />
    );

    const trigger = container.querySelector('[data-raw-md-trigger]') as HTMLButtonElement;
    fireEvent.click(trigger);

    await waitFor(() => {
      const content = baseElement.querySelector('pre');
      expect(content).toBeInTheDocument();
      expect(content?.textContent).toContain('# Audit Results\nScore: 85/100');
    });
  });

  it('shows error message on fetch failure', async () => {
    const mockGetRunFile = vi.mocked(api.getRunFile);
    const ApiErrorClass = (api.ApiError as unknown) as typeof api.ApiError;
    mockGetRunFile.mockRejectedValue(new ApiErrorClass('NOT_FOUND', 'Artifact not found'));

    const { container, baseElement } = render(
      <RawMarkdownDialog
        projectId="proj"
        epicId="E-001"
        runId="run123"
        name="missing.md"
        title="Missing Report"
      />
    );

    const trigger = container.querySelector('[data-raw-md-trigger]') as HTMLButtonElement;
    fireEvent.click(trigger);

    await waitFor(() => {
      const error = baseElement.querySelector('[data-raw-md-error]');
      expect(error).toBeInTheDocument();
      expect(error).toHaveTextContent('raw report se nepodařilo načíst');
    });
  });

  it('shows loading state while fetching', async () => {
    const mockGetRunFile = vi.mocked(api.getRunFile);
    let resolveAsync: (value: unknown) => void = () => {};
    mockGetRunFile.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveAsync = resolve;
        })
    );

    const { container, baseElement } = render(
      <RawMarkdownDialog
        projectId="proj"
        epicId="E-001"
        runId="run123"
        name="audit-report.md"
        title="Loading Test"
      />
    );

    const trigger = container.querySelector('[data-raw-md-trigger]') as HTMLButtonElement;
    fireEvent.click(trigger);

    await waitFor(() => {
      expect(baseElement.textContent).toContain('Načítám…');
    });

    resolveAsync({ format: 'markdown', content: 'Done' });
    await waitFor(() => {
      expect(baseElement.textContent).not.toContain('Načítám…');
      expect(baseElement.textContent).toContain('Done');
    });
  });

  it('only fetches once when opened multiple times', async () => {
    const mockGetRunFile = vi.mocked(api.getRunFile);
    mockGetRunFile.mockResolvedValue({
      format: 'markdown',
      content: 'Content 1',
    });

    const { container, baseElement } = render(
      <RawMarkdownDialog
        projectId="proj"
        epicId="E-001"
        runId="run123"
        name="report.md"
        title="Test"
      />
    );

    const trigger = container.querySelector('[data-raw-md-trigger]') as HTMLButtonElement;

    // First click — should fetch
    fireEvent.click(trigger);
    await waitFor(() => expect(mockGetRunFile).toHaveBeenCalledTimes(1));

    // Close and reopen — fetch should not happen again (already loaded)
    const closeBtn = baseElement.querySelector('[aria-label="Zavřít"]') as HTMLButtonElement;
    if (closeBtn) {
      fireEvent.click(closeBtn);
      // Re-open
      fireEvent.click(trigger);
      // Still only 1 fetch (cached)
      expect(mockGetRunFile).toHaveBeenCalledTimes(1);
    }
  });
});
