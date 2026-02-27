import React, { useState, useEffect, useRef, useCallback } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Send, Plus, ChevronDown, MessageSquare, Bot, AlertCircle, Loader2 } from 'lucide-react';
import { marked } from 'marked';
import DOMPurify from 'dompurify';
import { cn } from '../lib/utils';
import { useStore } from '../store';
import { createApiClient } from '../api/client';
import { VoiceButton } from './companion/VoiceButton';
import { HintButtons } from './companion/HintButtons';
import type { CompanionMessage } from '../types/api';

interface AICompanionProps { isOpen: boolean; onClose: () => void; }

marked.setOptions({ breaks: true, gfm: true });

function md(text: string): string {
  try {
    const raw = marked.parse(text) as string;
    return DOMPurify.sanitize(raw);
  } catch { return DOMPurify.sanitize(text); }
}

/** SSE streaming POST — reads chunks and dispatches to store. */
async function sendMessageSSE(text: string): Promise<void> {
  const store = useStore.getState();
  const projectId = store.activeProject?.id;
  if (!projectId) { store.setCompanionError('No active project selected'); return; }

  store.addCompanionMessage({
    id: `msg-${Date.now()}-u`, role: 'user', content: text, timestamp: new Date().toISOString(),
  });
  store.setCompanionStreaming(true);
  store.resetCompanionStream();
  store.setCompanionError(null);

  try {
    const res = await fetch(`/api/p/${encodeURIComponent(projectId)}/companion/send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: text, sessionId: store.companionCurrentSession?.id || undefined }),
    });
    if (!res.ok || !res.body) {
      store.setCompanionError(`Server returned ${res.status}`);
      store.setCompanionStreaming(false);
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
              id: `msg-${Date.now()}-a`, role: 'assistant',
              content: s.companionStreamingText, timestamp: new Date().toISOString(), model: json.model,
            });
            s.setCompanionStreaming(false);
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
          }
        } catch { /* malformed SSE line */ }
      }
    }
    const fs = useStore.getState();
    if (fs.companionStreaming) {
      if (fs.companionStreamingText) {
        fs.addCompanionMessage({
          id: `msg-${Date.now()}-a`, role: 'assistant',
          content: fs.companionStreamingText, timestamp: new Date().toISOString(),
        });
      }
      fs.setCompanionStreaming(false);
    }
  } catch (err) {
    const s = useStore.getState();
    s.setCompanionError(err instanceof Error ? err.message : 'Network error');
    s.setCompanionStreaming(false);
  }
}

// ---------------------------------------------------------------------------
export const AICompanion: React.FC<AICompanionProps> = ({ isOpen, onClose }) => {
  const [input, setInput] = useState('');
  const [showSessions, setShowSessions] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const taRef = useRef<HTMLTextAreaElement>(null);

  const activeProject = useStore((s) => s.activeProject);
  const sessions = useStore((s) => s.companionSessions);
  const session = useStore((s) => s.companionCurrentSession);
  const streaming = useStore((s) => s.companionStreaming);
  const streamText = useStore((s) => s.companionStreamingText);
  const status = useStore((s) => s.companionStatus);
  const error = useStore((s) => s.companionError);
  const messages = session?.messages ?? [];
  const available = status?.available ?? false;

  useEffect(() => {
    if (!isOpen || !activeProject) return;
    const c = createApiClient(activeProject.id);
    c.getCompanionStatus().then((r) => { if (r.ok) useStore.getState().setCompanionStatus(r.data); });
    c.getCompanionSessions().then((r) => { if (r.ok) useStore.getState().setCompanionSessions(r.data); });
  }, [isOpen, activeProject]);

  useEffect(() => { if (isOpen) setTimeout(() => taRef.current?.focus(), 100); }, [isOpen]);
  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [messages.length, streamText]);

  const handleSend = useCallback(() => {
    const t = input.trim();
    if (!t || streaming) return;
    setInput('');
    sendMessageSSE(t);
  }, [input, streaming]);

  const onKeyDown = useCallback((e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend(); }
  }, [handleSend]);

  const newSession = useCallback(() => {
    const s = useStore.getState();
    s.setCompanionCurrentSession(null); s.resetCompanionStream(); s.setCompanionError(null);
    setShowSessions(false); setInput('');
  }, []);

  const selectSession = useCallback(async (id: string) => {
    if (!activeProject) return;
    setShowSessions(false);
    const r = await createApiClient(activeProject.id).getCompanionSession(id);
    if (r.ok) { useStore.getState().setCompanionCurrentSession(r.data); useStore.getState().setCompanionError(null); }
  }, [activeProject]);

  const onInput = useCallback((e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setInput(e.target.value);
    e.target.style.height = 'auto';
    e.target.style.height = `${Math.min(e.target.scrollHeight, 120)}px`;
  }, []);

  const handleTranscript = useCallback((text: string) => {
    setInput((prev) => (prev ? `${prev} ${text}` : text));
    taRef.current?.focus();
  }, []);

  const handleHint = useCallback((prompt: string) => {
    if (streaming) return;
    setInput('');
    sendMessageSSE(prompt);
  }, [streaming]);

  const handleFocusInput = useCallback(() => {
    taRef.current?.focus();
  }, []);

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          initial={{ x: '100%', opacity: 0 }} animate={{ x: 0, opacity: 1 }}
          exit={{ x: '100%', opacity: 0 }}
          transition={{ type: 'spring', damping: 26, stiffness: 300 }}
          className={cn(
            'fixed top-12 right-0 z-50 flex flex-col',
            'bg-surface-2 border-l border-white/10 shadow-2xl',
            'w-full md:w-[33vw] md:min-w-[360px] h-[calc(100vh-48px)]',
          )}
        >
          {/* Header */}
          <div className="flex items-center gap-2 px-4 py-3 border-b border-white/5 shrink-0">
            <Bot size={18} className="text-state-executing" />
            <span className="text-sm font-semibold flex-1">AI Companion</span>
            <span
              className={cn('w-2 h-2 rounded-full', available ? 'bg-emerald-400' : 'bg-red-400')}
              title={status ? `${status.adapter} - ${available ? 'available' : 'unavailable'}` : 'Checking...'}
            />
            <div className="relative">
              <button onClick={() => setShowSessions(!showSessions)}
                className="flex items-center gap-1 text-xs text-white/50 hover:text-white/80 px-2 py-1 rounded-lg hover:bg-white/5 transition-colors">
                <MessageSquare size={14} />
                <span className="max-w-[100px] truncate">{session?.title ?? 'New chat'}</span>
                <ChevronDown size={12} />
              </button>
              {showSessions && (
                <div className="absolute right-0 top-full mt-1 w-64 bg-surface-2 border border-white/10 rounded-xl shadow-xl z-10 overflow-hidden">
                  <button onClick={newSession}
                    className="w-full flex items-center gap-2 px-3 py-2 text-xs hover:bg-white/5 text-state-executing transition-colors">
                    <Plus size={14} /> New conversation
                  </button>
                  {sessions.length > 0 && (
                    <div className="border-t border-white/5 max-h-48 overflow-y-auto custom-scrollbar">
                      {sessions.map((s) => (
                        <button key={s.id} onClick={() => selectSession(s.id)}
                          className={cn('w-full flex items-center gap-2 px-3 py-2 text-xs hover:bg-white/5 text-left transition-colors',
                            session?.id === s.id && 'bg-white/5 text-white')}>
                          <MessageSquare size={12} className="shrink-0 text-white/30" />
                          <span className="flex-1 truncate">{s.title}</span>
                          <span className="text-[10px] text-white/20 shrink-0">{s.messageCount}</span>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
            <button onClick={onClose} className="p-1.5 hover:bg-white/5 rounded-lg text-white/40 hover:text-white transition-colors" aria-label="Close companion">
              <X size={16} />
            </button>
          </div>

          {/* Error banner */}
          {error && (
            <div className="px-4 py-2 bg-red-500/10 border-b border-red-500/20 flex items-center gap-2 text-xs text-red-400 shrink-0">
              <AlertCircle size={14} /><span className="flex-1">{error}</span>
              <button onClick={() => useStore.getState().setCompanionError(null)} className="hover:text-red-300"><X size={12} /></button>
            </div>
          )}

          {/* Messages */}
          <div className="flex-1 overflow-y-auto custom-scrollbar px-4 py-4 space-y-4">
            {messages.length === 0 && !streaming && (
              <div className="flex flex-col items-center justify-center h-full text-center space-y-4">
                <Bot size={32} className="text-white/20 opacity-50" />
                <p className="text-sm text-white/30">Start a conversation with your AID project companion.</p>
                <HintButtons onHint={handleHint} onFocus={handleFocusInput} variant="full" />
                <p className="text-[11px] text-white/15">Or type a message below</p>
              </div>
            )}
            {messages.map((m) => <MsgBubble key={m.id} msg={m} />)}
            {streaming && streamText && (
              <div className="flex gap-2 items-start">
                <div className="w-6 h-6 rounded-full bg-state-executing/20 flex items-center justify-center shrink-0 mt-0.5">
                  <Bot size={14} className="text-state-executing" />
                </div>
                <div className="prose prose-invert prose-sm max-w-none bg-white/5 rounded-2xl rounded-tl-sm px-3 py-2 text-sm text-white/80"
                  dangerouslySetInnerHTML={{ __html: md(streamText) + '<span class="streaming-cursor">&#9610;</span>' }} />
              </div>
            )}
            {streaming && !streamText && (
              <div className="flex gap-2 items-center">
                <div className="w-6 h-6 rounded-full bg-state-executing/20 flex items-center justify-center shrink-0">
                  <Loader2 size={14} className="text-state-executing animate-spin" />
                </div>
                <span className="text-xs text-white/30">Thinking...</span>
              </div>
            )}
            <div ref={bottomRef} />
          </div>

          {/* Input */}
          <div className="px-4 py-3 border-t border-white/5 shrink-0">
            {messages.length > 0 && !streaming && (
              <HintButtons onHint={handleHint} onFocus={handleFocusInput} variant="compact" />
            )}
            <div className="flex items-end gap-2 bg-white/5 rounded-2xl px-3 py-2">
              <textarea ref={taRef} value={input} onChange={onInput} onKeyDown={onKeyDown}
                placeholder={activeProject ? `Message about ${activeProject.name}...` : 'Select a project first...'}
                disabled={!activeProject || !available} rows={1}
                className="flex-1 bg-transparent text-sm resize-none focus:outline-none placeholder:text-white/20 max-h-[120px] py-1" />
              <VoiceButton onTranscript={handleTranscript} disabled={!available || streaming} />
              <button onClick={handleSend} disabled={!input.trim() || streaming || !activeProject || !available}
                className={cn('p-2 rounded-xl transition-all shrink-0',
                  input.trim() && !streaming ? 'bg-state-executing text-white hover:brightness-110' : 'text-white/20 cursor-not-allowed')}
                aria-label="Send message">
                <Send size={16} />
              </button>
            </div>
            <div className="flex items-center justify-between mt-2 px-1">
              <span className="text-[10px] text-white/15">{status?.adapter ? `Adapter: ${status.adapter}` : ''}</span>
              <span className="text-[10px] text-white/15">Shift+Enter for new line</span>
            </div>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};

// ---------------------------------------------------------------------------
const MsgBubble: React.FC<{ msg: CompanionMessage }> = React.memo(({ msg }) => {
  if (msg.role === 'user') {
    return (
      <div className="flex justify-end">
        <div className="max-w-[80%] bg-state-executing/20 text-white/90 rounded-2xl rounded-br-sm px-3 py-2 text-sm whitespace-pre-wrap">
          {msg.content}
        </div>
      </div>
    );
  }
  return (
    <div className="flex gap-2 items-start">
      <div className="w-6 h-6 rounded-full bg-state-executing/20 flex items-center justify-center shrink-0 mt-0.5">
        <Bot size={14} className="text-state-executing" />
      </div>
      <div className="max-w-[85%] space-y-1">
        <div className="prose prose-invert prose-sm max-w-none bg-white/5 rounded-2xl rounded-tl-sm px-3 py-2 text-sm text-white/80"
          dangerouslySetInnerHTML={{ __html: md(msg.content) }} />
        {msg.model && <span className="text-[10px] text-white/15 pl-1">{msg.model}</span>}
      </div>
    </div>
  );
});
MsgBubble.displayName = 'MsgBubble';
