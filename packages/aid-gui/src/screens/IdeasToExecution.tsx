import React, { useState, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useStore } from '../store';
import { cn } from '../lib/utils';
import { Lightbulb, Plus, Rocket, Clock, CheckCircle2, MoreHorizontal, Filter, LayoutGrid, Network, X, Trash2, Link } from 'lucide-react';
import { createApiClient } from '../api/client';
import type { ApiError, StoredIdea, IdeaCreateRequest } from '../types/api';
import {
  DndContext,
  DragOverlay,
  closestCorners,
  PointerSensor,
  useSensor,
  useSensors,
  type DragStartEvent,
  type DragEndEvent,
  type DragOverEvent,
} from '@dnd-kit/core';
import { SortableContext, useSortable, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';

const client = createApiClient('default');

// Column definitions matching API statuses
const COLUMNS = [
  { id: 'idea', title: 'Ideas' },
  { id: 'exploring', title: 'Exploring' },
  { id: 'planned', title: 'Planned' },
  { id: 'done', title: 'Done' },
] as const;

type ColumnId = typeof COLUMNS[number]['id'];

// ---------------------------------------------------------------------------
// Sortable card component
// ---------------------------------------------------------------------------

interface SortableCardProps {
  idea: StoredIdea;
  onDelete: (id: string) => void;
  onLinkEpic: (id: string) => void;
}

const SortableCard: React.FC<SortableCardProps> = ({ idea, onDelete, onLinkEpic }) => {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: idea.id, data: { type: 'idea', idea } });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.3 : 1,
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      {...attributes}
      {...listeners}
      className="glass p-4 rounded-xl border border-white/5 cursor-grab active:cursor-grabbing group hover:bg-white/[0.05] transition-colors"
    >
      <div className="flex items-start justify-between mb-3">
        <h4 className="text-sm font-medium leading-tight group-hover:text-state-executing transition-colors">{idea.title}</h4>
        {idea.priority === 'high' && <div className="w-1.5 h-1.5 rounded-full bg-state-error shadow-[0_0_8px_rgba(239,68,68,0.5)]" />}
      </div>

      <div className="flex flex-wrap gap-1.5 mb-4">
        {idea.tags.map(tag => (
          <span key={tag} className="text-[9px] font-mono text-white/30">{tag.startsWith('#') ? tag : `#${tag}`}</span>
        ))}
      </div>

      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          {idea.linkedEpic ? (
            <div className="flex items-center gap-1.5 text-[10px] font-mono text-state-executing">
              <Rocket size={10} />
              <span>{idea.linkedEpic}</span>
            </div>
          ) : idea.linkedPlan ? (
            <div className="flex items-center gap-1.5 text-[10px] font-mono text-state-plan-review">
              <Link size={10} />
              <span>{idea.linkedPlan}</span>
            </div>
          ) : (
            <Clock size={12} className="text-white/20" />
          )}
        </div>
        <div className="opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-1">
          <button
            onClick={(e) => { e.stopPropagation(); onLinkEpic(idea.id); }}
            className="p-1 hover:bg-white/10 rounded text-white/40 hover:text-state-executing"
            title="Link to EPIC"
          >
            <Rocket size={12} />
          </button>
          <button
            onClick={(e) => { e.stopPropagation(); onDelete(idea.id); }}
            className="p-1 hover:bg-white/10 rounded text-white/40 hover:text-state-error"
            title="Delete"
          >
            <Trash2 size={12} />
          </button>
          <button className="p-1 hover:bg-white/10 rounded text-white/40 hover:text-white">
            <MoreHorizontal size={12} />
          </button>
        </div>
      </div>
    </div>
  );
};

// ---------------------------------------------------------------------------
// Drag overlay card (shown while dragging)
// ---------------------------------------------------------------------------

const DragOverlayCard: React.FC<{ idea: StoredIdea }> = ({ idea }) => (
  <div className="glass p-4 rounded-xl border border-state-executing/30 cursor-grabbing w-80 shadow-lg shadow-state-executing/10">
    <div className="flex items-start justify-between mb-3">
      <h4 className="text-sm font-medium leading-tight text-state-executing">{idea.title}</h4>
      {idea.priority === 'high' && <div className="w-1.5 h-1.5 rounded-full bg-state-error shadow-[0_0_8px_rgba(239,68,68,0.5)]" />}
    </div>
    <div className="flex flex-wrap gap-1.5">
      {idea.tags.map(tag => (
        <span key={tag} className="text-[9px] font-mono text-white/30">{tag.startsWith('#') ? tag : `#${tag}`}</span>
      ))}
    </div>
  </div>
);

// ---------------------------------------------------------------------------
// Quick Capture modal
// ---------------------------------------------------------------------------

interface QuickCaptureProps {
  onSubmit: (data: IdeaCreateRequest) => void;
  onClose: () => void;
}

const QuickCapture: React.FC<QuickCaptureProps> = ({ onSubmit, onClose }) => {
  const [title, setTitle] = useState('');
  const [priority, setPriority] = useState<'low' | 'medium' | 'high'>('medium');
  const [tags, setTags] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    onSubmit({
      title: title.trim(),
      priority,
      tags: tags.split(',').map(t => t.trim()).filter(Boolean),
    });
  };

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
      onClick={onClose}
    >
      <motion.div
        initial={{ scale: 0.95, y: 20 }}
        animate={{ scale: 1, y: 0 }}
        exit={{ scale: 0.95, y: 20 }}
        onClick={(e) => e.stopPropagation()}
        className="glass p-6 rounded-2xl border border-white/10 w-[400px] shadow-2xl"
      >
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-lg font-bold">Quick Capture</h3>
          <button onClick={onClose} className="p-1 hover:bg-white/10 rounded text-white/40 hover:text-white">
            <X size={18} />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="text-[10px] font-bold uppercase tracking-widest text-white/40 block mb-2">Title</label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="What's the idea?"
              className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm placeholder:text-white/20 focus:outline-none focus:border-state-executing/50"
              autoFocus
            />
          </div>
          <div>
            <label className="text-[10px] font-bold uppercase tracking-widest text-white/40 block mb-2">Priority</label>
            <div className="flex gap-2">
              {(['low', 'medium', 'high'] as const).map(p => (
                <button
                  key={p}
                  type="button"
                  onClick={() => setPriority(p)}
                  className={cn(
                    "px-3 py-1.5 rounded-lg text-xs font-medium transition-all border",
                    priority === p
                      ? p === 'high' ? "bg-state-error/20 border-state-error/30 text-state-error"
                        : p === 'medium' ? "bg-state-plan-review/20 border-state-plan-review/30 text-state-plan-review"
                        : "bg-white/10 border-white/20 text-white"
                      : "bg-white/5 border-white/5 text-white/40 hover:text-white"
                  )}
                >
                  {p}
                </button>
              ))}
            </div>
          </div>
          <div>
            <label className="text-[10px] font-bold uppercase tracking-widest text-white/40 block mb-2">Tags (comma-separated)</label>
            <input
              type="text"
              value={tags}
              onChange={(e) => setTags(e.target.value)}
              placeholder="auth, security, backend"
              className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm placeholder:text-white/20 focus:outline-none focus:border-state-executing/50"
            />
          </div>
          <button
            type="submit"
            disabled={!title.trim()}
            className="w-full py-2.5 bg-state-executing text-bg-base font-bold rounded-xl shadow-lg shadow-state-executing/20 hover:scale-[1.02] transition-all disabled:opacity-30 disabled:hover:scale-100"
          >
            Capture Idea
          </button>
        </form>
      </motion.div>
    </motion.div>
  );
};

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export const IdeasToExecution: React.FC = () => {
  const [view, setView] = useState<'board' | 'brainstorm'>('board');
  const [showCapture, setShowCapture] = useState(false);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const ideas = useStore((s) => s.ideas);
  const ideasLoading = useStore((s) => s.ideasLoading);
  const setIdeas = useStore((s) => s.setIdeas);
  const addIdea = useStore((s) => s.addIdea);
  const updateIdeaInStore = useStore((s) => s.updateIdea);
  const removeIdea = useStore((s) => s.removeIdea);
  const setIdeasLoading = useStore((s) => s.setIdeasLoading);

  // Sensors for dnd-kit — pointer sensor with 8px activation distance
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
  );

  // Fetch ideas on mount
  useEffect(() => {
    let cancelled = false;
    async function fetchIdeas() {
      setIdeasLoading(true);
      const result = await client.getIdeas();
      if (cancelled) return;
      if (result.ok) {
        setIdeas(result.data);
      } else {
        setError((result as ApiError).error.message);
      }
      setIdeasLoading(false);
    }
    fetchIdeas();
    return () => { cancelled = true; };
  }, [setIdeas, setIdeasLoading]);

  // Group ideas by column status
  const ideasByColumn: Record<ColumnId, StoredIdea[]> = {
    idea: ideas.filter(i => i.status === 'idea'),
    exploring: ideas.filter(i => i.status === 'exploring'),
    planned: ideas.filter(i => i.status === 'planned'),
    done: ideas.filter(i => i.status === 'done'),
  };

  // Get the active idea for drag overlay
  const activeIdea = activeId ? ideas.find(i => i.id === activeId) : null;

  // Find which column an idea belongs to
  const findColumnOfIdea = useCallback((ideaId: string): ColumnId | null => {
    const idea = ideas.find(i => i.id === ideaId);
    return idea ? (idea.status as ColumnId) : null;
  }, [ideas]);

  // ----- Drag handlers -----

  const handleDragStart = useCallback((event: DragStartEvent) => {
    setActiveId(event.active.id as string);
  }, []);

  const handleDragOver = useCallback((_event: DragOverEvent) => {
    // Visual feedback handled by dnd-kit's sortable
  }, []);

  const handleDragEnd = useCallback(async (event: DragEndEvent) => {
    setActiveId(null);
    const { active, over } = event;
    if (!over) return;

    const ideaId = active.id as string;
    const overId = over.id as string;

    // Determine target column — if dropped on a column droppable area or on another idea
    let targetColumn: ColumnId | null = null;

    // Check if dropped directly on a column
    if (COLUMNS.some(c => c.id === overId)) {
      targetColumn = overId as ColumnId;
    } else {
      // Dropped on another idea — find its column
      targetColumn = findColumnOfIdea(overId);
    }

    if (!targetColumn) return;

    const currentColumn = findColumnOfIdea(ideaId);
    if (currentColumn === targetColumn) return;

    // Optimistic update
    updateIdeaInStore(ideaId, { status: targetColumn });

    // Persist to API
    const result = await client.updateIdea(ideaId, { status: targetColumn });
    if (!result.ok) {
      // Revert optimistic update
      if (currentColumn) updateIdeaInStore(ideaId, { status: currentColumn });
      setError((result as ApiError).error.message);
    }
  }, [findColumnOfIdea, updateIdeaInStore]);

  // ----- Quick Capture -----

  const handleQuickCapture = useCallback(async (data: IdeaCreateRequest) => {
    setShowCapture(false);
    const result = await client.createIdea(data);
    if (result.ok) {
      addIdea(result.data);
    } else {
      setError((result as ApiError).error.message);
    }
  }, [addIdea]);

  // ----- Delete -----

  const handleDelete = useCallback(async (ideaId: string) => {
    const idea = ideas.find(i => i.id === ideaId);
    // Optimistic remove
    removeIdea(ideaId);

    const result = await client.deleteIdea(ideaId);
    if (!result.ok) {
      // Revert
      if (idea) addIdea(idea);
      setError((result as ApiError).error.message);
    }
  }, [ideas, removeIdea, addIdea]);

  // ----- Link to EPIC -----

  const handleLinkEpic = useCallback(async (ideaId: string) => {
    // Prompt for EPIC ID (simple prompt — EPIC 3 will add a proper picker)
    const epicId = window.prompt('Enter EPIC ID to link (e.g., E-005):');
    if (!epicId) return;

    updateIdeaInStore(ideaId, { linkedEpic: epicId });
    const result = await client.updateIdea(ideaId, { linkedEpic: epicId });
    if (!result.ok) {
      updateIdeaInStore(ideaId, { linkedEpic: null });
      setError((result as ApiError).error.message);
    }
  }, [updateIdeaInStore]);

  // ----- Loading state -----

  if (ideasLoading) {
    return (
      <div className="h-full flex flex-col p-8 overflow-hidden">
        <div className="flex items-center justify-between mb-8">
          <div>
            <div className="h-7 w-56 bg-white/5 rounded animate-pulse" />
            <div className="h-4 w-80 bg-white/5 rounded animate-pulse mt-2" />
          </div>
        </div>
        <div className="flex-1 flex gap-6">
          {COLUMNS.map(col => (
            <div key={col.id} className="w-80 shrink-0">
              <div className="h-4 w-20 bg-white/5 rounded animate-pulse mb-4 mx-2" />
              <div className="space-y-3 p-2 bg-white/[0.02] rounded-2xl border border-white/5">
                {[1, 2].map(i => (
                  <div key={i} className="h-24 bg-white/5 rounded-xl animate-pulse" />
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col p-8 overflow-hidden">
      {/* Error banner */}
      {error && (
        <div className="mb-4 p-3 bg-state-error/10 border border-state-error/20 rounded-xl text-sm text-state-error flex items-center justify-between">
          <span>{error}</span>
          <button onClick={() => setError(null)} className="p-1 hover:bg-white/10 rounded"><X size={14} /></button>
        </div>
      )}

      {/* Header */}
      <div className="flex items-center justify-between mb-8">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Ideas to Execution</h2>
          <p className="text-sm text-white/40">The journey from napkin sketch to running code</p>
        </div>
        <div className="flex items-center gap-4">
          <div className="flex bg-white/5 p-1 rounded-xl border border-white/10">
            <button
              onClick={() => setView('board')}
              className={cn("p-2 rounded-lg transition-all", view === 'board' ? "bg-white/10 text-white" : "text-white/40 hover:text-white")}
            >
              <LayoutGrid size={18} />
            </button>
            <button
              onClick={() => setView('brainstorm')}
              className={cn("p-2 rounded-lg transition-all", view === 'brainstorm' ? "bg-white/10 text-white" : "text-white/40 hover:text-white")}
            >
              <Network size={18} />
            </button>
          </div>
          <button
            onClick={() => setShowCapture(true)}
            className="flex items-center gap-2 px-4 py-2 bg-state-executing text-bg-base font-bold rounded-xl shadow-lg shadow-state-executing/20 hover:scale-105 transition-all"
          >
            <Plus size={18} /> Quick Capture
          </button>
        </div>
      </div>

      {view === 'board' ? (
        <DndContext
          sensors={sensors}
          collisionDetection={closestCorners}
          onDragStart={handleDragStart}
          onDragOver={handleDragOver}
          onDragEnd={handleDragEnd}
        >
          <div className="flex-1 flex gap-6 overflow-x-auto pb-4 custom-scrollbar">
            {COLUMNS.map(col => {
              const columnIdeas = ideasByColumn[col.id];
              return (
                <div key={col.id} className="w-80 shrink-0 flex flex-col">
                  <div className="flex items-center justify-between mb-4 px-2">
                    <div className="flex items-center gap-2">
                      <span className="text-[10px] font-bold uppercase tracking-[0.2em] text-white/40">{col.title}</span>
                      <span className="text-[10px] font-mono bg-white/5 px-1.5 py-0.5 rounded text-white/20">{columnIdeas.length}</span>
                    </div>
                    <button className="text-white/20 hover:text-white transition-colors"><MoreHorizontal size={14} /></button>
                  </div>

                  <SortableContext
                    items={columnIdeas.map(i => i.id)}
                    strategy={verticalListSortingStrategy}
                    id={col.id}
                  >
                    <div
                      className="flex-1 space-y-3 p-2 bg-white/[0.02] rounded-2xl border border-white/5 overflow-y-auto custom-scrollbar min-h-[100px]"
                      data-column-id={col.id}
                    >
                      {columnIdeas.map(idea => (
                        <SortableCard
                          key={idea.id}
                          idea={idea}
                          onDelete={handleDelete}
                          onLinkEpic={handleLinkEpic}
                        />
                      ))}
                      {columnIdeas.length === 0 && (
                        <div className="py-8 text-center text-[10px] font-mono text-white/15">
                          Drop ideas here
                        </div>
                      )}
                      <button
                        onClick={() => setShowCapture(true)}
                        className="w-full py-3 border border-dashed border-white/10 rounded-xl text-[10px] font-bold uppercase tracking-widest text-white/20 hover:text-white/40 hover:border-white/20 transition-all"
                      >
                        + Add Item
                      </button>
                    </div>
                  </SortableContext>
                </div>
              );
            })}
          </div>

          <DragOverlay>
            {activeIdea ? <DragOverlayCard idea={activeIdea} /> : null}
          </DragOverlay>
        </DndContext>
      ) : (
        <div className="flex-1 glass rounded-[2.5rem] border border-white/5 relative overflow-hidden flex items-center justify-center">
          <div className="absolute inset-0 opacity-10" style={{ backgroundImage: 'radial-gradient(circle at 2px 2px, white 1px, transparent 0)', backgroundSize: '40px 40px' }} />
          <div className="text-center space-y-4 relative z-10">
            <div className="w-20 h-20 rounded-full bg-white/5 flex items-center justify-center mx-auto text-white/20">
              <Network size={40} />
            </div>
            <h3 className="text-xl font-medium text-white/40">Brainstorm Canvas</h3>
            <p className="text-sm text-white/20 max-w-xs mx-auto">Visualize connections between ideas and map your project's future.</p>
            <button className="px-6 py-2 bg-white/5 hover:bg-white/10 border border-white/10 rounded-xl text-xs font-medium transition-all">
              Initialize Canvas
            </button>
          </div>
        </div>
      )}

      {/* Quick Capture Modal */}
      <AnimatePresence>
        {showCapture && (
          <QuickCapture
            onSubmit={handleQuickCapture}
            onClose={() => setShowCapture(false)}
          />
        )}
      </AnimatePresence>
    </div>
  );
};
