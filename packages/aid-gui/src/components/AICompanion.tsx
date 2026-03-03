import React, { useEffect, useRef, useCallback } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Bot, AlertCircle, PanelLeftClose, ArrowLeft } from 'lucide-react';
import { cn } from '../lib/utils';
import { useStore } from '../store';
import { sendMessageSSE } from '../lib/companion';
import { createApiClient } from '../api/client';
import { ChatMessageList } from './companion/ChatMessageList';
import { ChatInput, type ChatInputHandle } from './companion/ChatInput';
import { SessionTabs } from './companion/SessionTabs';

interface AICompanionProps {
  isOpen: boolean;
  onClose: () => void;
}

// ---------------------------------------------------------------------------
export const AICompanion: React.FC<AICompanionProps> = ({ isOpen, onClose }) => {
  const chatInputRef = useRef<ChatInputHandle>(null);

  const activeProject = useStore((s) => s.activeProject);
  const session = useStore((s) => s.companionCurrentSession);
  const streaming = useStore((s) => s.companionStreaming);
  const streamText = useStore((s) => s.companionStreamingText);
  const status = useStore((s) => s.companionStatus);
  const error = useStore((s) => s.companionError);
  const setCompanionMode = useStore((s) => s.setCompanionMode);
  const setCompanionOpen = useStore((s) => s.setCompanionOpen);
  const setCommandPaletteOpen = useStore((s) => s.setCommandPaletteOpen);
  const messages = session?.messages ?? [];
  const available = status?.available ?? false;

  // Background refresh companion data (pre-fetched on project select)
  useEffect(() => {
    if (!isOpen || !activeProject) return;
    if (status) return; // Already have data from pre-fetch
    const c = createApiClient(activeProject.id);
    c.getCompanionStatus().then((r) => {
      if (r.ok) useStore.getState().setCompanionStatus(r.data);
    });
    c.getCompanionSessions().then((r) => {
      if (r.ok) useStore.getState().setCompanionSessions(r.data);
    });
  }, [isOpen, activeProject, status]);

  useEffect(() => {
    if (isOpen) setTimeout(() => chatInputRef.current?.focus(), 100);
  }, [isOpen]);

  const handleSend = useCallback(
    (text: string) => {
      if (streaming) return;
      sendMessageSSE(text);
    },
    [streaming],
  );

  const handleHint = useCallback(
    (prompt: string) => {
      if (streaming) return;
      sendMessageSSE(prompt);
    },
    [streaming],
  );

  const handleFocusInput = useCallback(() => {
    chatInputRef.current?.focus();
  }, []);

  // Back to empty state — clear current session
  const backToNew = useCallback(() => {
    const s = useStore.getState();
    s.setCompanionCurrentSession(null);
    s.resetCompanionStream();
    s.setCompanionError(null);
  }, []);

  const undockToPalette = useCallback(() => {
    setCompanionMode('palette');
    setCompanionOpen(false);
    setCommandPaletteOpen(true);
  }, [setCompanionMode, setCompanionOpen, setCommandPaletteOpen]);

  const hasMessages = messages.length > 0 || streaming;

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          initial={{ x: '100%', opacity: 0 }}
          animate={{ x: 0, opacity: 1 }}
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
            {/* Back arrow — visible when there are messages */}
            {hasMessages && (
              <button
                onClick={backToNew}
                className="p-1 hover:bg-white/5 rounded-lg text-white/30 hover:text-white/70 transition-colors"
                title="New conversation"
              >
                <ArrowLeft size={16} />
              </button>
            )}
            <Bot size={18} className="text-state-executing" />
            <span className="text-sm font-semibold">AI Companion</span>
            <span
              className={cn('w-2 h-2 rounded-full shrink-0', available ? 'bg-emerald-400' : 'bg-red-400')}
              title={status ? `${status.adapter} - ${available ? 'available' : 'unavailable'}` : 'Checking...'}
            />

            {/* Session tabs — fills remaining space */}
            <div className="flex-1 min-w-0 flex justify-end">
              <SessionTabs variant="full" maxTabs={4} />
            </div>

            {/* Undock to palette */}
            <button
              onClick={undockToPalette}
              className="p-1.5 hover:bg-white/5 rounded-lg text-white/40 hover:text-white transition-colors shrink-0"
              aria-label="Undock to command palette"
              title="Undock to dropdown"
            >
              <PanelLeftClose size={16} />
            </button>
            <button
              onClick={onClose}
              className="p-1.5 hover:bg-white/5 rounded-lg text-white/40 hover:text-white transition-colors shrink-0"
              aria-label="Close companion"
            >
              <X size={16} />
            </button>
          </div>

          {/* Error banner */}
          {error && (
            <div className="px-4 py-2 bg-red-500/10 border-b border-red-500/20 flex items-center gap-2 text-xs text-red-400 shrink-0">
              <AlertCircle size={14} />
              <span className="flex-1">{error}</span>
              <button onClick={() => useStore.getState().setCompanionError(null)} className="hover:text-red-300">
                <X size={12} />
              </button>
            </div>
          )}

          {/* Messages */}
          <ChatMessageList
            messages={messages}
            streaming={streaming}
            streamText={streamText}
            onHint={handleHint}
            onFocusInput={handleFocusInput}
            variant="full"
          />

          {/* Input */}
          <ChatInput
            ref={chatInputRef}
            onSend={handleSend}
            disabled={!activeProject || !available}
            streaming={streaming}
            placeholder={activeProject ? `Message about ${activeProject.name}...` : 'Select a project first...'}
            showHints={messages.length > 0}
            onHint={handleHint}
            onFocusInput={handleFocusInput}
          />

          {/* Adapter info */}
          <div className="px-5 pb-2 shrink-0">
            <span className="text-[10px] text-white/15">{status?.adapter ? `Adapter: ${status.adapter}` : ''}</span>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};
