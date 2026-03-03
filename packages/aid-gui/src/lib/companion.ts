import { marked } from 'marked';
import DOMPurify from 'dompurify';
import { useStore } from '../store';
import { createApiClient } from '../api/client';

// ---------------------------------------------------------------------------
// Markdown rendering
// ---------------------------------------------------------------------------

marked.setOptions({ breaks: true, gfm: true });

export function md(text: string): string {
  try {
    const raw = marked.parse(text) as string;
    return DOMPurify.sanitize(raw);
  } catch {
    return DOMPurify.sanitize(text);
  }
}

// ---------------------------------------------------------------------------
// SSE streaming POST — reads chunks and dispatches to store.
// ---------------------------------------------------------------------------

/** Current AbortController for the active stream (if any). */
let activeAbort: AbortController | null = null;

/**
 * Abort the current companion SSE stream.
 * Saves whatever has been streamed so far as the assistant message.
 */
export function abortCompanionStream(): void {
  if (activeAbort) {
    activeAbort.abort();
    activeAbort = null;
  }
}

export async function sendMessageSSE(text: string): Promise<void> {
  const store = useStore.getState();
  const projectId = store.activeProject?.id;
  if (!projectId) {
    store.setCompanionError('No active project selected');
    return;
  }

  // Abort any in-flight stream before starting a new one
  abortCompanionStream();

  store.addCompanionMessage({
    id: `msg-${Date.now()}-u`,
    role: 'user',
    content: text,
    timestamp: new Date().toISOString(),
  });
  store.setCompanionStreaming(true);
  store.resetCompanionStream();
  store.setCompanionError(null);

  const controller = new AbortController();
  activeAbort = controller;

  try {
    const res = await fetch(
      `/api/p/${encodeURIComponent(projectId)}/companion/send`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: text,
          sessionId: store.companionCurrentSession?.id || undefined,
        }),
        signal: controller.signal,
      },
    );
    if (!res.ok || !res.body) {
      store.setCompanionError(`Server returned ${res.status}`);
      store.setCompanionStreaming(false);
      activeAbort = null;
      return;
    }
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop()!;
      for (const line of lines) {
        if (!line.startsWith('data: ')) continue;
        try {
          const json = JSON.parse(line.slice(6));
          const s = useStore.getState();
          if (json.type === 'text') {
            s.appendCompanionStreamText(json.text);
          } else if (json.type === 'done') {
            s.addCompanionMessage({
              id: `msg-${Date.now()}-a`,
              role: 'assistant',
              content: s.companionStreamingText,
              timestamp: new Date().toISOString(),
              model: json.model,
            });
            s.setCompanionStreaming(false);
            activeAbort = null;
            if (json.sessionId) {
              const client = createApiClient(projectId);
              const sr = await client.getCompanionSession(json.sessionId);
              if (sr.ok) useStore.getState().setCompanionCurrentSession(sr.data);
              const lr = await client.getCompanionSessions();
              if (lr.ok) useStore.getState().setCompanionSessions(lr.data);
            }
          } else if (json.type === 'error') {
            s.setCompanionError(json.error || 'Stream error');
            s.setCompanionStreaming(false);
            activeAbort = null;
          }
        } catch {
          /* malformed SSE line */
        }
      }
    }
    const fs = useStore.getState();
    if (fs.companionStreaming) {
      if (fs.companionStreamingText) {
        fs.addCompanionMessage({
          id: `msg-${Date.now()}-a`,
          role: 'assistant',
          content: fs.companionStreamingText,
          timestamp: new Date().toISOString(),
        });
      }
      fs.setCompanionStreaming(false);
    }
    activeAbort = null;
  } catch (err) {
    activeAbort = null;
    const s = useStore.getState();
    // On abort: save partial text if any
    if (err instanceof DOMException && err.name === 'AbortError') {
      const partial = s.companionStreamingText;
      if (partial) {
        s.addCompanionMessage({
          id: `msg-${Date.now()}-a`,
          role: 'assistant',
          content: partial,
          timestamp: new Date().toISOString(),
        });
      }
      s.setCompanionStreaming(false);
      return;
    }
    s.setCompanionError(err instanceof Error ? err.message : 'Network error');
    s.setCompanionStreaming(false);
  }
}
