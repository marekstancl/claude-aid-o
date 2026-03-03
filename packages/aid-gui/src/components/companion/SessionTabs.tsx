import React, { useState, useCallback, useRef, useEffect } from 'react';
import {
  Plus,
  ChevronDown,
  MessageSquare,
  Trash2,
  Archive,
  Pencil,
  Check,
  X,
  MoreHorizontal,
} from 'lucide-react';
import { cn } from '../../lib/utils';
import { useStore } from '../../store';
import { createApiClient } from '../../api/client';
import type { CompanionSessionSummary } from '../../types/api';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface SessionTabsProps {
  /** How many recent tabs to show inline. */
  maxTabs?: number;
  /** Compact (palette) or full (panel) sizing. */
  variant?: 'compact' | 'full';
}

// ---------------------------------------------------------------------------
// SessionTabs — recent tabs + session manager dropdown
// ---------------------------------------------------------------------------

export const SessionTabs: React.FC<SessionTabsProps> = ({
  maxTabs = 4,
  variant = 'compact',
}) => {
  const activeProject = useStore((s) => s.activeProject);
  const sessions = useStore((s) => s.companionSessions);
  const currentSession = useStore((s) => s.companionCurrentSession);

  const [dropdownOpen, setDropdownOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editTitle, setEditTitle] = useState('');
  const dropdownRef = useRef<HTMLDivElement>(null);
  const editInputRef = useRef<HTMLInputElement>(null);

  const isCompact = variant === 'compact';
  const recentTabs = sessions.slice(0, maxTabs);
  const hasMore = sessions.length > maxTabs;

  // Close dropdown on outside click
  useEffect(() => {
    if (!dropdownOpen) return;
    const handler = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setDropdownOpen(false);
        setEditingId(null);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [dropdownOpen]);

  // Focus edit input
  useEffect(() => {
    if (editingId) editInputRef.current?.focus();
  }, [editingId]);

  // Select a session
  const selectSession = useCallback(
    async (id: string) => {
      if (!activeProject) return;
      setDropdownOpen(false);
      setEditingId(null);
      const r = await createApiClient(activeProject.id).getCompanionSession(id);
      if (r.ok) {
        useStore.getState().setCompanionCurrentSession(r.data);
        useStore.getState().setCompanionError(null);
      }
    },
    [activeProject],
  );

  // New session
  const newSession = useCallback(() => {
    const s = useStore.getState();
    s.setCompanionCurrentSession(null);
    s.resetCompanionStream();
    s.setCompanionError(null);
    setDropdownOpen(false);
    setEditingId(null);
  }, []);

  // Refresh sessions list from server
  const refreshSessions = useCallback(async () => {
    if (!activeProject) return;
    const r = await createApiClient(activeProject.id).getCompanionSessions();
    if (r.ok) useStore.getState().setCompanionSessions(r.data);
  }, [activeProject]);

  // Delete session
  const deleteSession = useCallback(
    async (e: React.MouseEvent, id: string) => {
      e.stopPropagation();
      if (!activeProject) return;
      const r = await createApiClient(activeProject.id).deleteCompanionSession(id);
      if (r.ok) {
        // If we deleted the current session, clear it
        if (currentSession?.id === id) {
          newSession();
        }
        await refreshSessions();
      }
    },
    [activeProject, currentSession?.id, newSession, refreshSessions],
  );

  // Archive session
  const archiveSession = useCallback(
    async (e: React.MouseEvent, id: string) => {
      e.stopPropagation();
      if (!activeProject) return;
      const r = await createApiClient(activeProject.id).archiveCompanionSession(id);
      if (r.ok) {
        if (currentSession?.id === id) {
          newSession();
        }
        await refreshSessions();
      }
    },
    [activeProject, currentSession?.id, newSession, refreshSessions],
  );

  // Start rename
  const startRename = useCallback(
    (e: React.MouseEvent, session: CompanionSessionSummary) => {
      e.stopPropagation();
      setEditingId(session.id);
      setEditTitle(session.title);
    },
    [],
  );

  // Confirm rename
  const confirmRename = useCallback(
    async (id: string) => {
      if (!activeProject || !editTitle.trim()) {
        setEditingId(null);
        return;
      }
      const r = await createApiClient(activeProject.id).renameCompanionSession(id, editTitle.trim());
      if (r.ok) {
        await refreshSessions();
      }
      setEditingId(null);
    },
    [activeProject, editTitle, refreshSessions],
  );

  return (
    <div className="flex items-center gap-1 min-w-0" ref={dropdownRef}>
      {/* New session button */}
      <button
        onClick={newSession}
        className={cn(
          'shrink-0 rounded-lg transition-colors',
          isCompact
            ? 'p-0.5 hover:bg-white/5 text-white/30 hover:text-state-executing'
            : 'p-1 hover:bg-white/5 text-white/40 hover:text-state-executing',
        )}
        title="New conversation"
      >
        <Plus size={isCompact ? 12 : 14} />
      </button>

      {/* Recent session tabs */}
      {recentTabs.map((s) => (
        <button
          key={s.id}
          onClick={() => selectSession(s.id)}
          className={cn(
            'flex items-center gap-1 rounded-lg truncate transition-colors min-w-0',
            isCompact
              ? 'px-2 py-0.5 text-[10px] max-w-[140px]'
              : 'px-2.5 py-1 text-[11px] max-w-[180px]',
            currentSession?.id === s.id
              ? 'bg-white/10 text-white/80'
              : 'text-white/30 hover:bg-white/5 hover:text-white/60',
          )}
          title={s.title}
        >
          <MessageSquare size={isCompact ? 9 : 10} className="shrink-0" />
          <span className="truncate">{s.title}</span>
        </button>
      ))}

      {/* Dropdown toggle — always show if there are any sessions */}
      {sessions.length > 0 && (
        <div className="relative shrink-0">
          <button
            onClick={() => setDropdownOpen(!dropdownOpen)}
            className={cn(
              'rounded-lg transition-colors',
              isCompact
                ? 'p-0.5 hover:bg-white/5 text-white/30 hover:text-white/60'
                : 'p-1 hover:bg-white/5 text-white/40 hover:text-white/60',
            )}
            title={`All conversations (${sessions.length})`}
          >
            {hasMore ? (
              <MoreHorizontal size={isCompact ? 12 : 14} />
            ) : (
              <ChevronDown size={isCompact ? 10 : 12} className={cn(dropdownOpen && 'rotate-180', 'transition-transform')} />
            )}
          </button>

          {/* Full sessions dropdown */}
          {dropdownOpen && (
            <div
              className={cn(
                'absolute top-full mt-1 bg-surface-2 border border-white/10 rounded-xl shadow-2xl z-20 overflow-hidden',
                isCompact ? 'right-0 w-64' : 'right-0 w-72',
              )}
            >
              {/* Header */}
              <div className="flex items-center justify-between px-3 py-2 border-b border-white/5">
                <span className="text-[10px] font-bold uppercase tracking-widest text-white/30">
                  Conversations ({sessions.length})
                </span>
                <button
                  onClick={newSession}
                  className="flex items-center gap-1 text-[10px] text-state-executing hover:text-state-executing/80 transition-colors"
                >
                  <Plus size={10} /> New
                </button>
              </div>

              {/* Session list */}
              <div className="max-h-60 overflow-y-auto custom-scrollbar">
                {sessions.map((s) => (
                  <div
                    key={s.id}
                    className={cn(
                      'group flex items-center gap-2 px-3 py-2 hover:bg-white/5 transition-colors cursor-pointer',
                      currentSession?.id === s.id && 'bg-white/5',
                    )}
                    onClick={() => {
                      if (editingId !== s.id) selectSession(s.id);
                    }}
                  >
                    <MessageSquare size={11} className="shrink-0 text-white/20" />

                    {editingId === s.id ? (
                      /* Inline rename */
                      <div className="flex-1 flex items-center gap-1 min-w-0">
                        <input
                          ref={editInputRef}
                          value={editTitle}
                          onChange={(e) => setEditTitle(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter') confirmRename(s.id);
                            if (e.key === 'Escape') setEditingId(null);
                          }}
                          onClick={(e) => e.stopPropagation()}
                          className="flex-1 bg-white/5 rounded px-1.5 py-0.5 text-[11px] text-white/80 focus:outline-none focus:bg-white/10 border border-white/10 min-w-0"
                        />
                        <button
                          onClick={(e) => { e.stopPropagation(); confirmRename(s.id); }}
                          className="p-0.5 text-emerald-400 hover:text-emerald-300"
                        >
                          <Check size={10} />
                        </button>
                        <button
                          onClick={(e) => { e.stopPropagation(); setEditingId(null); }}
                          className="p-0.5 text-white/30 hover:text-white/60"
                        >
                          <X size={10} />
                        </button>
                      </div>
                    ) : (
                      /* Normal row */
                      <>
                        <div className="flex-1 min-w-0">
                          <div className="text-[11px] text-white/60 truncate group-hover:text-white/80 transition-colors">
                            {s.title}
                          </div>
                          <div className="text-[9px] text-white/20">
                            {s.messageCount} msgs
                          </div>
                        </div>

                        {/* Action buttons — visible on hover */}
                        <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity shrink-0">
                          <button
                            onClick={(e) => startRename(e, s)}
                            className="p-1 rounded hover:bg-white/10 text-white/30 hover:text-white/60 transition-colors"
                            title="Rename"
                          >
                            <Pencil size={10} />
                          </button>
                          <button
                            onClick={(e) => archiveSession(e, s.id)}
                            className="p-1 rounded hover:bg-white/10 text-white/30 hover:text-amber-400 transition-colors"
                            title="Archive"
                          >
                            <Archive size={10} />
                          </button>
                          <button
                            onClick={(e) => deleteSession(e, s.id)}
                            className="p-1 rounded hover:bg-white/10 text-white/30 hover:text-red-400 transition-colors"
                            title="Delete"
                          >
                            <Trash2 size={10} />
                          </button>
                        </div>
                      </>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
