import React, { useState, useCallback, useEffect, useRef, useMemo } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import {
  Bot,
  PanelRight,
  ArrowLeft,
  AlertCircle,
  X,
} from 'lucide-react';
import { cn } from '../lib/utils';
import { useStore } from '../store';
import { sendMessageSSE } from '../lib/companion';
import { createApiClient } from '../api/client';
import { ChatMessageList } from './companion/ChatMessageList';
import { ChatInput, type ChatInputHandle } from './companion/ChatInput';
import { VoiceButton } from './companion/VoiceButton';
import { HINTS, type HintContext } from './companion/HintButtons';
import { SessionTabs } from './companion/SessionTabs';

// ---------------------------------------------------------------------------
// CommandPalette — dropdown overlay below search bar
// ---------------------------------------------------------------------------

export const CommandPalette: React.FC = () => {
  const isOpen = useStore((s) => s.commandPaletteOpen);
  const setOpen = useStore((s) => s.setCommandPaletteOpen);
  const setCompanionMode = useStore((s) => s.setCompanionMode);
  const setCompanionOpen = useStore((s) => s.setCompanionOpen);

  const activeProject = useStore((s) => s.activeProject);
  const session = useStore((s) => s.companionCurrentSession);
  const streaming = useStore((s) => s.companionStreaming);
  const streamText = useStore((s) => s.companionStreamingText);
  const status = useStore((s) => s.companionStatus);
  const error = useStore((s) => s.companionError);
  const messages = session?.messages ?? [];
  const available = status?.available ?? false;

  const [filter, setFilter] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);
  const chatInputRef = useRef<ChatInputHandle>(null);
  const paletteRef = useRef<HTMLDivElement>(null);

  // Hint context for suggestion templates
  const projectName = useStore((s) => s.activeProject?.name ?? null);
  const epicId = useStore((s) => s.currentEpicId);
  const ideas = useStore((s) => s.ideas);
  const focusedIdeaTitle = useMemo(() => {
    if (ideas.length === 0) return null;
    const exploring = ideas.find((i) => i.status === 'exploring');
    if (exploring) return exploring.title;
    const sorted = [...ideas].sort(
      (a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime(),
    );
    return sorted[0]?.title ?? null;
  }, [ideas]);
  const hintCtx: HintContext = { projectName, epicId, focusedIdeaTitle };

  // Determine if we're in chat mode (has messages or streaming)
  const isChatMode = messages.length > 0 || streaming;

  // Background refresh companion data on open (pre-fetched on project select)
  useEffect(() => {
    if (!isOpen || !activeProject) return;
    // Only refresh if data is stale (not on first open — already pre-fetched)
    if (status) return;
    const c = createApiClient(activeProject.id);
    c.getCompanionStatus().then((r) => {
      if (r.ok) useStore.getState().setCompanionStatus(r.data);
    });
    c.getCompanionSessions().then((r) => {
      if (r.ok) useStore.getState().setCompanionSessions(r.data);
    });
  }, [isOpen, activeProject, status]);

  // Focus input on open
  useEffect(() => {
    if (isOpen) {
      setTimeout(() => {
        if (isChatMode) chatInputRef.current?.focus();
        else inputRef.current?.focus();
      }, 100);
    } else {
      setFilter('');
    }
  }, [isOpen, isChatMode]);

  // Escape key closes palette
  useEffect(() => {
    if (!isOpen) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        setOpen(false);
      }
    };
    window.addEventListener('keydown', handler, true);
    return () => window.removeEventListener('keydown', handler, true);
  }, [isOpen, setOpen]);

  // Click outside closes palette
  useEffect(() => {
    if (!isOpen) return;
    const handler = (e: MouseEvent) => {
      if (paletteRef.current && !paletteRef.current.contains(e.target as Node)) {
        // Don't close if clicking the search bar trigger itself
        const target = e.target as HTMLElement;
        if (target.closest('[data-palette-trigger]')) return;
        setOpen(false);
      }
    };
    // Use setTimeout to avoid the opening click immediately closing
    const id = setTimeout(() => {
      document.addEventListener('mousedown', handler);
    }, 0);
    return () => {
      clearTimeout(id);
      document.removeEventListener('mousedown', handler);
    };
  }, [isOpen, setOpen]);

  // Dock to right panel
  const dockToPanel = useCallback(() => {
    setCompanionMode('panel');
    setOpen(false);
    setCompanionOpen(true);
  }, [setCompanionMode, setOpen, setCompanionOpen]);

  // Back to suggestions — reset current session
  const backToSuggestions = useCallback(() => {
    const s = useStore.getState();
    s.setCompanionCurrentSession(null);
    s.resetCompanionStream();
    s.setCompanionError(null);
    setFilter('');
    setTimeout(() => inputRef.current?.focus(), 50);
  }, []);

  // Send message from filter input (suggestions mode)
  const handleFilterSubmit = useCallback(() => {
    const t = filter.trim();
    if (!t || streaming) return;
    setFilter('');
    sendMessageSSE(t);
  }, [filter, streaming]);

  // Handle hint selection
  const handleHint = useCallback(
    (prompt: string) => {
      if (streaming) return;
      setFilter('');
      sendMessageSSE(prompt);
    },
    [streaming],
  );

  const handleFocusInput = useCallback(() => {
    if (isChatMode) chatInputRef.current?.focus();
    else inputRef.current?.focus();
  }, [isChatMode]);

  // Handle send from ChatInput (chat mode)
  const handleChatSend = useCallback(
    (text: string) => {
      if (streaming) return;
      sendMessageSSE(text);
    },
    [streaming],
  );

  // Voice transcript → send directly as message
  const handleVoiceTranscript = useCallback((text: string) => {
    if (streaming) return;
    setFilter('');
    sendMessageSSE(text);
  }, [streaming]);

  // Filtered suggestions
  const filteredHints = useMemo(() => {
    if (!filter) return HINTS;
    const lower = filter.toLowerCase();
    return HINTS.filter(
      (h) => h.label.toLowerCase().includes(lower) || h.description.toLowerCase().includes(lower),
    );
  }, [filter]);

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          ref={paletteRef}
          initial={{ opacity: 0, y: -8, scale: 0.98 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: -8, scale: 0.98 }}
          transition={{ type: 'spring', damping: 25, stiffness: 400 }}
          className="absolute top-full mt-2 z-[60] bg-surface-2 border border-white/10 rounded-2xl shadow-2xl overflow-hidden flex flex-col"
          style={{
            left: '-25%',
            right: '-25%',
            maxHeight: isChatMode ? '60vh' : undefined,
          }}
        >
          {/* Header */}
          <div className="flex items-center gap-2 px-4 py-2.5 border-b border-white/5 shrink-0">
            {/* Back button when in chat mode */}
            {isChatMode && (
              <button
                onClick={backToSuggestions}
                className="p-1 hover:bg-white/5 rounded-lg text-white/30 hover:text-white/70 transition-colors"
                title="Back to suggestions"
              >
                <ArrowLeft size={14} />
              </button>
            )}
            <Bot size={16} className="text-state-executing" />
            <span className="text-xs font-semibold">AI Companion</span>
            <span
              className={cn('w-1.5 h-1.5 rounded-full shrink-0', available ? 'bg-emerald-400' : 'bg-red-400')}
              title={status ? `${status.adapter} - ${available ? 'available' : 'unavailable'}` : 'Checking...'}
            />

            {/* Session tabs — fills remaining space */}
            <div className="flex-1 min-w-0 flex justify-end">
              <SessionTabs variant="compact" maxTabs={3} />
            </div>

            {/* Dock to panel button */}
            <button
              onClick={dockToPanel}
              className="p-1 hover:bg-white/5 rounded-lg text-white/30 hover:text-white/70 transition-colors shrink-0"
              title="Dock to side panel"
            >
              <PanelRight size={14} />
            </button>

            {/* Close button */}
            <button
              onClick={() => setOpen(false)}
              className="p-1 hover:bg-white/5 rounded-lg text-white/30 hover:text-white/70 transition-colors shrink-0"
              title="Close (Esc)"
            >
              <X size={14} />
            </button>
          </div>

          {/* Error banner */}
          {error && (
            <div className="px-4 py-1.5 bg-red-500/10 border-b border-red-500/20 flex items-center gap-2 text-[11px] text-red-400 shrink-0">
              <AlertCircle size={12} />
              <span className="flex-1">{error}</span>
              <button onClick={() => useStore.getState().setCompanionError(null)} className="hover:text-red-300">
                <X size={10} />
              </button>
            </div>
          )}

          {/* Content area */}
          {isChatMode ? (
            <>
              <ChatMessageList
                messages={messages}
                streaming={streaming}
                streamText={streamText}
                onHint={handleHint}
                onFocusInput={handleFocusInput}
                variant="compact"
                className="flex-1 overflow-y-auto custom-scrollbar px-4 py-3 space-y-3"
              />
              <ChatInput
                ref={chatInputRef}
                onSend={handleChatSend}
                disabled={!activeProject || !available}
                streaming={streaming}
                placeholder={activeProject ? `Message about ${activeProject.name}...` : 'Select a project first...'}
                showHints={messages.length > 0}
                onHint={handleHint}
                onFocusInput={handleFocusInput}
                className="px-3 py-2 border-t border-white/5 shrink-0"
              />
            </>
          ) : (
            <>
              {/* Filter input with voice */}
              <div className="px-4 py-2.5 shrink-0">
                <div className="flex items-center gap-2 bg-white/5 rounded-xl px-3 py-1 border border-white/5 focus-within:bg-white/10 focus-within:border-state-executing/30 transition-colors">
                  <input
                    ref={inputRef}
                    type="text"
                    value={filter}
                    onChange={(e) => setFilter(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' && !e.shiftKey) {
                        e.preventDefault();
                        handleFilterSubmit();
                      }
                    }}
                    placeholder={
                      activeProject
                        ? `Ask about ${activeProject.name}...`
                        : 'Select a project first...'
                    }
                    disabled={!activeProject || !available}
                    className="flex-1 bg-transparent py-1 text-sm focus:outline-none placeholder:text-white/20"
                  />
                  <VoiceButton
                    onTranscript={handleVoiceTranscript}
                    disabled={!activeProject || !available}
                  />
                </div>
              </div>

              {/* Suggestions — fixed height, all items visible */}
              <div className="px-3 pb-3">
                <div className="space-y-0.5">
                  {filteredHints.map((hint) => {
                    const prompt = hint.template(hintCtx);
                    return (
                      <button
                        key={hint.id}
                        onClick={() => {
                          if (prompt === null) handleFocusInput();
                          else handleHint(prompt);
                        }}
                        className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-left hover:bg-white/5 transition-colors group"
                      >
                        <hint.icon
                          size={16}
                          className="text-white/20 group-hover:text-state-executing shrink-0 transition-colors"
                        />
                        <div className="flex-1 min-w-0">
                          <div className="text-xs text-white/70 group-hover:text-white/90 transition-colors">
                            {hint.label}
                          </div>
                          <div className="text-[10px] text-white/25 group-hover:text-white/40 transition-colors truncate">
                            {hint.description}
                          </div>
                        </div>
                      </button>
                    );
                  })}
                </div>

                {/* No results */}
                {filteredHints.length === 0 && filter && (
                  <div className="py-4 text-center">
                    <p className="text-xs text-white/30">No matches. Press Enter to send as message.</p>
                  </div>
                )}
              </div>
            </>
          )}
        </motion.div>
      )}
    </AnimatePresence>
  );
};
