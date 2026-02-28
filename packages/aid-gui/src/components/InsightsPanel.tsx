import React, { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useDraggable } from '@dnd-kit/core';
import { useStore } from '../store';
import { cn } from '../lib/utils';
import { createApiClient } from '../api/client';
import { ListTodo, AlertTriangle, BookOpen, GripVertical } from 'lucide-react';
import type { BacklogEntry, LessonEntry, ApiError } from '../types/api';

const client = createApiClient('default');

// ---------------------------------------------------------------------------
// Priority badge component
// ---------------------------------------------------------------------------

const PriorityBadge: React.FC<{ priority: string }> = ({ priority }) => {
  const normalized = priority.toLowerCase();

  let classes = 'bg-white/10 text-white/40';
  if (normalized === 'critical' || normalized === 'high') {
    classes = 'bg-state-error/20 text-state-error';
  } else if (normalized === 'medium') {
    classes = 'bg-state-plan-review/20 text-state-plan-review';
  }

  return (
    <span className={cn('text-[9px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded', classes)}>
      {priority}
    </span>
  );
};

// ---------------------------------------------------------------------------
// Draggable backlog entry
// ---------------------------------------------------------------------------

interface DraggableBacklogEntryProps {
  entry: BacklogEntry;
}

const DraggableBacklogEntry: React.FC<DraggableBacklogEntryProps> = ({ entry }) => {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    isDragging,
  } = useDraggable({
    id: `backlog-${entry.id}`,
    data: { type: 'backlog-entry', entry },
  });

  const style = transform
    ? { transform: `translate3d(${transform.x}px, ${transform.y}px, 0)` }
    : undefined;

  return (
    <div
      ref={setNodeRef}
      style={style}
      {...attributes}
      {...listeners}
      className={cn(
        'flex items-start gap-2 p-2 rounded-lg border border-white/5 bg-white/[0.02] cursor-grab active:cursor-grabbing hover:bg-white/[0.05] transition-colors group',
        isDragging && 'opacity-30',
      )}
    >
      <GripVertical size={12} className="mt-0.5 text-white/15 group-hover:text-white/30 shrink-0" />
      <div className="flex-1 min-w-0">
        <p className="text-xs text-white/70 leading-snug line-clamp-2">{entry.description}</p>
        <div className="flex items-center gap-2 mt-1.5">
          <PriorityBadge priority={entry.priority} />
          <span className="text-[9px] font-mono text-white/20">{entry.type}</span>
          {entry.area && (
            <span className="text-[9px] font-mono text-white/20 truncate">{entry.area}</span>
          )}
        </div>
      </div>
    </div>
  );
};

// ---------------------------------------------------------------------------
// Lesson entry display
// ---------------------------------------------------------------------------

const LessonEntryCard: React.FC<{ entry: LessonEntry }> = ({ entry }) => {
  const isGotcha = entry.category === 'gotcha';
  return (
    <div className="p-2 rounded-lg border border-white/5 bg-white/[0.02]">
      <div className="flex items-center gap-1.5 mb-1">
        {isGotcha ? (
          <AlertTriangle size={10} className="text-state-error shrink-0" />
        ) : (
          <BookOpen size={10} className="text-state-executing shrink-0" />
        )}
        <span className={cn(
          'text-[9px] font-bold uppercase tracking-wider',
          isGotcha ? 'text-state-error' : 'text-state-executing',
        )}>
          {isGotcha ? 'Gotcha' : 'Lesson'}
        </span>
      </div>
      <p className="text-xs text-white/70 leading-snug line-clamp-2">
        {isGotcha ? entry.gotcha : entry.lesson}
      </p>
      {isGotcha && entry.workaround && (
        <p className="text-[10px] text-white/30 mt-1 line-clamp-1">
          Workaround: {entry.workaround}
        </p>
      )}
      {!isGotcha && entry.impact && (
        <p className="text-[10px] text-white/30 mt-1 line-clamp-1">
          Impact: {entry.impact}
        </p>
      )}
    </div>
  );
};

// ---------------------------------------------------------------------------
// Skeleton loader
// ---------------------------------------------------------------------------

const SkeletonLoader: React.FC = () => (
  <div className="space-y-2 p-3">
    {[1, 2, 3].map(i => (
      <div key={i} className="h-14 bg-white/5 rounded-lg animate-pulse" />
    ))}
  </div>
);

// ---------------------------------------------------------------------------
// Main InsightsPanel component
// ---------------------------------------------------------------------------

type TabId = 'backlog' | 'lessons';

export const InsightsPanel: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);
  const [activeTab, setActiveTab] = useState<TabId>('backlog');

  const backlogEntries = useStore((s) => s.backlogEntries);
  const lessonEntries = useStore((s) => s.lessonEntries);
  const insightsLoading = useStore((s) => s.insightsLoading);
  const setBacklogEntries = useStore((s) => s.setBacklogEntries);
  const setLessonEntries = useStore((s) => s.setLessonEntries);
  const setInsightsLoading = useStore((s) => s.setInsightsLoading);

  // Fetch backlog + lessons on mount
  useEffect(() => {
    let cancelled = false;

    async function fetchInsights() {
      setInsightsLoading(true);

      const [backlogResult, lessonsResult] = await Promise.all([
        client.getBacklog(),
        client.getLessons(),
      ]);

      if (cancelled) return;

      if (backlogResult.ok) {
        setBacklogEntries(backlogResult.data);
      }
      if (lessonsResult.ok) {
        setLessonEntries(lessonsResult.data);
      }

      setInsightsLoading(false);
    }

    fetchInsights();
    return () => { cancelled = true; };
  }, [setBacklogEntries, setLessonEntries, setInsightsLoading]);

  // Close on Escape
  useEffect(() => {
    if (!isOpen) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setIsOpen(false);
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [isOpen]);

  // Group lessons by category
  const lessonsByCategory = {
    lesson: lessonEntries.filter(e => e.category === 'lesson'),
    gotcha: lessonEntries.filter(e => e.category === 'gotcha'),
  };

  const totalCount = backlogEntries.length + lessonEntries.length;

  return (
    <>
      {/* Compact toggle button */}
      <motion.button
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.3, delay: 0.1 }}
        onClick={() => setIsOpen(true)}
        className="mt-4 w-full flex items-center justify-between px-4 py-2.5 glass rounded-2xl border border-white/5 hover:border-white/10 hover:bg-white/[0.04] transition-all group"
      >
        <div className="flex items-center gap-2">
          <ListTodo size={14} className="text-white/30 group-hover:text-white/50 transition-colors" />
          <span className="text-[10px] font-bold uppercase tracking-[0.15em] text-white/40 group-hover:text-white/60 transition-colors">
            Backlog & Lessons
          </span>
        </div>
        <div className="flex items-center gap-2">
          {totalCount > 0 && (
            <span className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-state-executing/15 text-state-executing">
              {totalCount}
            </span>
          )}
          <span className="text-[10px] text-white/20 group-hover:text-white/40 transition-colors">
            Click to open
          </span>
        </div>
      </motion.button>

      {/* Bottom sheet overlay */}
      <AnimatePresence>
        {isOpen && (
          <>
            {/* Backdrop */}
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setIsOpen(false)}
              className="fixed inset-0 bg-bg-base/60 backdrop-blur-sm z-40"
            />

            {/* Sheet */}
            <motion.div
              initial={{ y: '100%' }}
              animate={{ y: 0 }}
              exit={{ y: '100%' }}
              transition={{ type: 'spring', damping: 28, stiffness: 300 }}
              className="fixed bottom-0 left-0 right-0 z-50 glass border-t border-white/10 rounded-t-2xl shadow-2xl"
              style={{ maxHeight: '70vh' }}
            >
              {/* Handle + header */}
              <div className="flex flex-col items-center pt-2">
                <div className="w-8 h-1 rounded-full bg-white/15 mb-2" />
              </div>

              <div className="flex items-center justify-between px-5 pb-3 border-b border-white/5">
                <div className="flex items-center gap-1">
                  <button
                    onClick={() => setActiveTab('backlog')}
                    className={cn(
                      'flex items-center gap-2 px-3 py-2 text-[10px] font-bold uppercase tracking-[0.15em] transition-all border-b-2 -mb-[1px]',
                      activeTab === 'backlog'
                        ? 'text-state-executing border-state-executing'
                        : 'text-white/30 border-transparent hover:text-white/50',
                    )}
                  >
                    <ListTodo size={12} />
                    Backlog
                    <span className={cn(
                      'text-[9px] font-mono px-1.5 py-0.5 rounded',
                      activeTab === 'backlog' ? 'bg-state-executing/20 text-state-executing' : 'bg-white/5 text-white/20',
                    )}>
                      {backlogEntries.length}
                    </span>
                  </button>
                  <button
                    onClick={() => setActiveTab('lessons')}
                    className={cn(
                      'flex items-center gap-2 px-3 py-2 text-[10px] font-bold uppercase tracking-[0.15em] transition-all border-b-2 -mb-[1px]',
                      activeTab === 'lessons'
                        ? 'text-state-executing border-state-executing'
                        : 'text-white/30 border-transparent hover:text-white/50',
                    )}
                  >
                    <BookOpen size={12} />
                    Lessons
                    <span className={cn(
                      'text-[9px] font-mono px-1.5 py-0.5 rounded',
                      activeTab === 'lessons' ? 'bg-state-executing/20 text-state-executing' : 'bg-white/5 text-white/20',
                    )}>
                      {lessonEntries.length}
                    </span>
                  </button>
                </div>

                <button
                  onClick={() => setIsOpen(false)}
                  className="text-[10px] text-white/30 hover:text-white/60 px-2 py-1 rounded-lg hover:bg-white/5 transition-colors"
                >
                  ESC
                </button>
              </div>

              {/* Content */}
              <div className="overflow-y-auto custom-scrollbar" style={{ maxHeight: 'calc(70vh - 80px)' }}>
                {insightsLoading ? (
                  <SkeletonLoader />
                ) : (
                  <AnimatePresence mode="wait">
                    {activeTab === 'backlog' ? (
                      <motion.div
                        key="backlog"
                        initial={{ opacity: 0, x: -8 }}
                        animate={{ opacity: 1, x: 0 }}
                        exit={{ opacity: 0, x: 8 }}
                        transition={{ duration: 0.15 }}
                        className="p-4 space-y-2"
                      >
                        {backlogEntries.length === 0 ? (
                          <div className="py-8 text-center">
                            <ListTodo size={24} className="mx-auto mb-2 text-white/10" />
                            <p className="text-xs font-mono text-white/20">No backlog entries yet</p>
                            <p className="text-[10px] text-white/10 mt-1">Entries appear after EPIC audits</p>
                          </div>
                        ) : (
                          backlogEntries.map(entry => (
                            <DraggableBacklogEntry key={entry.id} entry={entry} />
                          ))
                        )}
                      </motion.div>
                    ) : (
                      <motion.div
                        key="lessons"
                        initial={{ opacity: 0, x: 8 }}
                        animate={{ opacity: 1, x: 0 }}
                        exit={{ opacity: 0, x: -8 }}
                        transition={{ duration: 0.15 }}
                        className="p-4 space-y-3"
                      >
                        {lessonEntries.length === 0 ? (
                          <div className="py-8 text-center">
                            <BookOpen size={24} className="mx-auto mb-2 text-white/10" />
                            <p className="text-xs font-mono text-white/20">No lessons recorded yet</p>
                            <p className="text-[10px] text-white/10 mt-1">Lessons are captured during EPIC execution</p>
                          </div>
                        ) : (
                          <>
                            {lessonsByCategory.lesson.length > 0 && (
                              <div>
                                <h4 className="text-[9px] font-bold uppercase tracking-[0.2em] text-white/25 mb-2 px-1">
                                  Lessons ({lessonsByCategory.lesson.length})
                                </h4>
                                <div className="space-y-2">
                                  {lessonsByCategory.lesson.map(entry => (
                                    <LessonEntryCard key={entry.id} entry={entry} />
                                  ))}
                                </div>
                              </div>
                            )}

                            {lessonsByCategory.gotcha.length > 0 && (
                              <div>
                                <h4 className="text-[9px] font-bold uppercase tracking-[0.2em] text-white/25 mb-2 px-1">
                                  Gotchas ({lessonsByCategory.gotcha.length})
                                </h4>
                                <div className="space-y-2">
                                  {lessonsByCategory.gotcha.map(entry => (
                                    <LessonEntryCard key={entry.id} entry={entry} />
                                  ))}
                                </div>
                              </div>
                            )}
                          </>
                        )}
                      </motion.div>
                    )}
                  </AnimatePresence>
                )}
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </>
  );
};
