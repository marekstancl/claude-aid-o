import { describe, it, expect, vi, beforeEach } from 'vitest';
import { getRunFile, ApiError } from './api';

describe('getRunFile', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    global.fetch = vi.fn();
  });

  it('fetches from the correct hardened endpoint with encoded params', async () => {
    const mockFetch = vi.mocked(global.fetch);
    mockFetch.mockResolvedValue(
      new Response(JSON.stringify({ ok: true, data: { format: 'markdown', content: 'Test' } }))
    );

    await getRunFile('myproj', 'E-047', 'run456', 'audit-report.md');

    expect(mockFetch).toHaveBeenCalledWith(
      '/api/epics/myproj/E-047/runs/run456/file?name=audit-report.md',
      expect.objectContaining({ headers: { Accept: 'application/json' } })
    );
  });

  it('encodes special characters in projectId, epicId, runId', async () => {
    const mockFetch = vi.mocked(global.fetch);
    mockFetch.mockResolvedValue(
      new Response(JSON.stringify({ ok: true, data: { format: 'markdown', content: 'Test' } }))
    );

    await getRunFile('my/proj', 'E-001/2', 'run-123', 'audit-report.md');

    expect(mockFetch).toHaveBeenCalledWith(
      '/api/epics/my%2Fproj/E-001%2F2/runs/run-123/file?name=audit-report.md',
      expect.any(Object)
    );
  });

  it('encodes special characters in name query parameter', async () => {
    const mockFetch = vi.mocked(global.fetch);
    mockFetch.mockResolvedValue(
      new Response(JSON.stringify({ ok: true, data: { format: 'markdown', content: 'Test' } }))
    );

    await getRunFile('proj', 'E-001', 'run123', 'reporter/file with spaces.txt');

    const callUrl = (mockFetch.mock.calls[0][0] as string);
    // URLSearchParams encodes the name value
    expect(callUrl).toContain('name=reporter');
    expect(callUrl).toContain('file');
    expect(callUrl).toContain('spaces');
  });

  it('returns unwrapped data on success', async () => {
    const mockFetch = vi.mocked(global.fetch);
    const expected = { format: 'markdown', content: '# Test Content' };
    mockFetch.mockResolvedValue(
      new Response(JSON.stringify({ ok: true, data: expected }))
    );

    const result = await getRunFile('proj', 'E-001', 'run123', 'audit-report.md');

    expect(result).toEqual(expected);
  });

  it('throws ApiError on non-OK response', async () => {
    const mockFetch = vi.mocked(global.fetch);
    mockFetch.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: false,
          error: { code: 'NOT_FOUND', message: 'Artifact not found' },
        })
      )
    );

    await expect(getRunFile('proj', 'E-001', 'run123', 'missing.md')).rejects.toThrow(
      ApiError
    );
  });

  it('throws ApiError on network error', async () => {
    const mockFetch = vi.mocked(global.fetch);
    mockFetch.mockRejectedValue(new Error('Network failure'));

    await expect(getRunFile('proj', 'E-001', 'run123', 'audit-report.md')).rejects.toThrow(
      ApiError
    );
  });

  it('throws ApiError on non-JSON response', async () => {
    const mockFetch = vi.mocked(global.fetch);
    mockFetch.mockResolvedValue(
      new Response('Not JSON', { status: 500 })
    );

    await expect(getRunFile('proj', 'E-001', 'run123', 'audit-report.md')).rejects.toThrow(
      ApiError
    );
  });
});
