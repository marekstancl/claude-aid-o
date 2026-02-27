import React, { useState, useEffect, useCallback, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useStore } from '../store';
import { cn } from '../lib/utils';
import { Lightbulb, Plus, Rocket, Clock, CheckCircle2, MoreHorizontal, Filter, LayoutGrid, Network, X, Trash2, Link } from 'lucide-react';
import { createApiClient } from '../api/client';
import type { ApiError, StoredIdea, IdeaCreateRequest, BacklogEntry } from '../types/api';
import { InsightsPanel } from '../components/InsightsPanel';
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

// Column definitions — 5-stage pipeline from Ideas to Done
const COLUMNS = [
  { id: 'ideas', title: 'Ideas', icon: Lightbulb },
  { id: 'plan', title: 'Plan', icon: Link },
  { id: 'epic', title: 'EPIC', icon: Rocket },
  { id: 'running', title: 'Running', icon: Clock },
  { id: 'done', title: 'Done', icon: CheckCircle2 },
] as const;

type ColumnId = typeof COLUMNS[number]['id'];

/**
 * Resolve effective column for an idea using `autoStatus ?? status`.
 *
 * Column mapping:
 *   null + status 'idea'      → ideas
 *   null + status 'exploring' → ideas   (backward compat)
 *   'plan' or status 'planned'→ plan
 *   'epic'                    → epic
 *   'running'                 → running
 *   'done' or status 'done'   → done
 */
function resolveColumn(idea: StoredIdea): ColumnId {
  const effective = idea.autoStatus ?? idea.status;
  switch (effective) {
    case 'idea':
    case 'exploring':
      return 'ideas';
    case 'plan':
    case 'planned':
      return 'plan';
    case 'epic':
      return 'epic';
    case 'running':
      return 'running';
    case 'done':
      return 'done';
    default:
      return 'ideas';
  }
}

/**
 * Map a column ID back to the API status value for `updateIdea()`.
 * autoStatus is server-computed from linked artifacts, so we only set
 * the manual `status` field here.
 */
function columnToApiStatus(columnId: ColumnId): StoredIdea['status'] {
  switch (columnId) {
    case 'ideas':
      return 'idea';
    case 'plan':
      return 'planned';
    case 'epic':
      return 'planned'; // manual status stays planned; autoStatus is server-driven
    case 'running':
      return 'planned'; // manual status stays planned; autoStatus is server-driven
    case 'done':
      return 'done';
    default:
      return 'idea';
  }
}

// ---------------------------------------------------------------------------
// Sortable card component
// ---------------------------------------------------------------------------

interface SortableCardProps {
  idea: StoredIdea;
  onDelete: (id: string) => void;
  onLinkEpic: (id: string) => void;
  /** When true, render a selection checkbox (Ideas column only). */
  showCheckbox?: boolean;
  /** Whether this card is currently selected. */
  isSelected?: boolean;
  /** Toggle selection for this card. */
  onToggleSelect?: (id: string) => void;
  /** When true, the card shows a building animation (EPIC column drop). */
  isBuilding?: boolean;
}

const SortableCard: React.FC<SortableCardProps> = ({ idea, onDelete, onLinkEpic, showCheckbox, isSelected, onToggleSelect, isBuilding }) => {
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
      className={cn(
        "glass p-4 rounded-xl border cursor-grab active:cursor-grabbing group hover:bg-white/[0.05] transition-colors",
        isSelected ? "border-state-executing/40 bg-state-executing/5" : "border-white/5",
        isBuilding && "animate-pulse border-state-executing/50 bg-state-executing/10 shadow-[0_0_20px_rgba(0,180,216,0.15)]",
      )}
    >
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-start gap-2">
          {showCheckbox && (
            <button
              onClick={(e) => { e.stopPropagation(); onToggleSelect?.(idea.id); }}
              className={cn(
                "mt-0.5 w-4 h-4 rounded border flex items-center justify-center shrink-0 transition-colors",
                isSelected
                  ? "bg-state-executing border-state-executing text-bg-base"
                  : "border-white/20 hover:border-white/40",
              )}
            >
              {isSelected && <CheckCircle2 size={10} />}
            </button>
          )}
          <h4 className="text-sm font-medium leading-tight group-hover:text-state-executing transition-colors">{idea.title}</h4>
        </div>
        <div className="flex items-center gap-1.5">
          {isBuilding && (
            <span className="text-[9px] font-bold uppercase tracking-widest text-state-executing bg-state-executing/20 px-1.5 py-0.5 rounded">
              Building
            </span>
          )}
          {idea.priority === 'high' && <div className="w-1.5 h-1.5 rounded-full bg-state-error shadow-[0_0_8px_rgba(239,68,68,0.5)]" />}
        </div>
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
  const [selectedIdeaIds, setSelectedIdeaIds] = useState<Set<string>>(new Set());
  const [buildingIds, setBuildingIds] = useState<Set<string>>(new Set());
  const buildingTimersRef = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());

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

  // Cleanup building animation timers on unmount
  useEffect(() => {
    return () => {
      buildingTimersRef.current.forEach((timer) => clearTimeout(timer));
      buildingTimersRef.current.clear();
    };
  }, []);

  // Trigger building animation on a card for 2 seconds
  const triggerBuildingAnimation = useCallback((ideaId: string) => {
    // Clear existing timer for this ID if any
    const existing = buildingTimersRef.current.get(ideaId);
    if (existing) clearTimeout(existing);

    setBuildingIds((prev) => new Set(prev).add(ideaId));

    const timer = setTimeout(() => {
      setBuildingIds((prev) => {
        const next = new Set(prev);
        next.delete(ideaId);
        return next;
      });
      buildingTimersRef.current.delete(ideaId);
    }, 2000);

    buildingTimersRef.current.set(ideaId, timer);
  }, []);

  // Toggle selection of an idea (Ideas column only)
  const handleToggleSelect = useCallback((ideaId: string) => {
    setSelectedIdeaIds((prev) => {
      const next = new Set(prev);
      if (next.has(ideaId)) {
        next.delete(ideaId);
      } else {
        next.add(ideaId);
      }
      return next;
    });
  }, []);

  // Create Plan action — stub for now
  const handleCreatePlan = useCallback(() => {
    const selected = Array.from(selectedIdeaIds);
    const titles = ideas
      .filter((i) => selected.includes(i.id))
      .map((i) => i.title);
    alert(`Create Plan from ${selected.length} idea(s):\n\n${titles.join('\n')}`);
  }, [selectedIdeaIds, ideas]);

  // Group ideas by column using autoStatus ?? status mapping
  const ideasByColumn: Record<ColumnId, StoredIdea[]> = {
    ideas: [],
    plan: [],
    epic: [],
    running: [],
    done: [],
  };
  for (const idea of ideas) {
    const col = resolveColumn(idea);
    ideasByColumn[col].push(idea);
  }

  // Clean up selections: remove IDs that are no longer in the Ideas column
  useEffect(() => {
    const ideasColumnIds = new Set(ideasByColumn.ideas.map((i) => i.id));
    setSelectedIdeaIds((prev) => {
      const cleaned = new Set<string>();
      for (const id of prev) {
        if (ideasColumnIds.has(id)) cleaned.add(id);
      }
      return cleaned.size !== prev.size ? cleaned : prev;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ideas]);

  // Get the active idea for drag overlay
  const activeIdea = activeId ? ideas.find(i => i.id === activeId) : null;

  // Track active backlog entry for overlay
  const [activeBacklogEntry, setActiveBacklogEntry] = useState<BacklogEntry | null>(null);
  const backlogEntries = useStore((s) => s.backlogEntries);

  // Find which column an idea belongs to
  const findColumnOfIdea = useCallback((ideaId: string): ColumnId | null => {
    const idea = ideas.find(i => i.id === ideaId);
    return idea ? resolveColumn(idea) : null;
  }, [ideas]);

  // ----- Drag handlers -----

  const handleDragStart = useCallback((event: DragStartEvent) => {
    const activeData = event.active.data.current;
    if (activeData?.type === 'backlog-entry') {
      setActiveBacklogEntry(activeData.entry as BacklogEntry);
      setActiveId(null);
    } else {
      setActiveId(event.active.id as string);
      setActiveBacklogEntry(null);
    }
  }, []);

  const handleDragOver = useCallback((_event: DragOverEvent) => {
    // Visual feedback handled by dnd-kit's sortable
  }, []);

  const handleDragEnd = useCallback(async (event: DragEndEvent) => {
    setActiveId(null);
    setActiveBacklogEntry(null);
    const { active, over } = event;
    if (!over) return;

    const activeData = active.data.current;

    // --- Handle backlog entry dropped onto Ideas column ---
    if (activeData?.type === 'backlog-entry') {
      const entry = activeData.entry as BacklogEntry;
      // Determine the target column
      const overId = over.id as string;
      let targetColumn: ColumnId | null = null;
      if (COLUMNS.some(c => c.id === overId)) {
        targetColumn = overId as ColumnId;
      } else {
        targetColumn = findColumnOfIdea(overId);
      }

      // Only create an idea if dropped on the Ideas column
      if (targetColumn === 'ideas') {
        const result = await client.createIdea({
          title: entry.description,
          tags: [entry.type, entry.area].filter(Boolean),
        });
        if (result.ok) {
          addIdea(result.data);
        } else {
          setError((result as ApiError).error.message);
        }
      }
      return;
    }

    // --- Handle idea drag between columns ---
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

    // Map column IDs to API status values
    const targetApiStatus = columnToApiStatus(targetColumn);
    const currentApiStatus = currentColumn ? columnToApiStatus(currentColumn) : null;

    // Trigger building animation when dropping into the EPIC column
    if (targetColumn === 'epic') {
      triggerBuildingAnimation(ideaId);
    }

    // Optimistic update
    updateIdeaInStore(ideaId, { status: targetApiStatus });

    // Persist to API
    const result = await client.updateIdea(ideaId, { status: targetApiStatus });
    if (!result.ok) {
      // Revert optimistic update
      if (currentApiStatus) updateIdeaInStore(ideaId, { status: currentApiStatus });
      setError((result as ApiError).error.message);
    }
  }, [findColumnOfIdea, updateIdeaInStore, addIdea, triggerBuildingAnimation]);

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

    const result = await client.linkIdea(ideaId, { linkedEpic: epicId });
    if (result.ok) {
      updateIdeaInStore(ideaId, result.data);
    } else {
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
              const ColIcon = col.icon;
              const columnIdeas = ideasByColumn[col.id];
              const isIdeasColumn = col.id === 'ideas';

              // Placeholder text per column
              const placeholderText: Record<ColumnId, string> = {
                ideas: 'Capture your first idea',
                plan: 'Ideas promoted to plans appear here',
                epic: 'Plans converted to EPICs appear here',
                running: 'EPICs currently executing appear here',
                done: 'Completed work lands here',
              };

              return (
                <div key={col.id} className="w-72 shrink-0 flex flex-col">
                  {/* Column header */}
                  <div className="flex items-center justify-between mb-4 px-2">
                    <div className="flex items-center gap-2">
                      <ColIcon size={14} className="text-white/30" />
                      <span className="text-[10px] font-bold uppercase tracking-[0.2em] text-white/40">{col.title}</span>
                      <span className="text-[10px] font-mono bg-white/5 px-1.5 py-0.5 rounded text-white/20">{columnIdeas.length}</span>
                    </div>
                    <button className="text-white/20 hover:text-white transition-colors"><MoreHorizontal size={14} /></button>
                  </div>

                  {/* Create Plan action bar — only in Ideas column when ideas are selected */}
                  {isIdeasColumn && selectedIdeaIds.size > 0 && (
                    <div className="mb-2 px-2">
                      <button
                        onClick={handleCreatePlan}
                        className="w-full flex items-center justify-center gap-2 py-2 bg-state-executing text-bg-base font-bold rounded-xl shadow-lg shadow-state-executing/20 hover:scale-[1.02] transition-all text-xs"
                      >
                        <Plus size={14} />
                        Create Plan ({selectedIdeaIds.size})
                      </button>
                    </div>
                  )}

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
                          showCheckbox={isIdeasColumn}
                          isSelected={selectedIdeaIds.has(idea.id)}
                          onToggleSelect={handleToggleSelect}
                          isBuilding={buildingIds.has(idea.id)}
                        />
                      ))}
                      {columnIdeas.length === 0 && (
                        <div className="py-8 text-center">
                          <ColIcon size={24} className="mx-auto mb-2 text-white/10" />
                          <p className="text-[10px] font-mono text-white/15">
                            {placeholderText[col.id]}
                          </p>
                        </div>
                      )}
                      {isIdeasColumn && (
                        <button
                          onClick={() => setShowCapture(true)}
                          className="w-full py-3 border border-dashed border-white/10 rounded-xl text-[10px] font-bold uppercase tracking-widest text-white/20 hover:text-white/40 hover:border-white/20 transition-all"
                        >
                          + Add Idea
                        </button>
                      )}
                    </div>
                  </SortableContext>
                </div>
              );
            })}
          </div>

          {/* Insights Panel — inside DndContext so backlog entries participate in drag-and-drop */}
          <InsightsPanel />

          <DragOverlay>
            {activeIdea ? <DragOverlayCard idea={activeIdea} /> : null}
            {activeBacklogEntry ? (
              <div className="glass p-3 rounded-xl border border-state-executing/30 cursor-grabbing w-72 shadow-lg shadow-state-executing/10">
                <p className="text-xs text-white/80 leading-snug line-clamp-2">{activeBacklogEntry.description}</p>
                <div className="flex items-center gap-2 mt-1.5">
                  <span className={cn(
                    'text-[9px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded',
                    activeBacklogEntry.priority.toLowerCase() === 'critical' || activeBacklogEntry.priority.toLowerCase() === 'high'
                      ? 'bg-state-error/20 text-state-error'
                      : activeBacklogEntry.priority.toLowerCase() === 'medium'
                        ? 'bg-state-plan-review/20 text-state-plan-review'
                        : 'bg-white/10 text-white/40',
                  )}>
                    {activeBacklogEntry.priority}
                  </span>
                  <span className="text-[9px] font-mono text-white/30">{activeBacklogEntry.type}</span>
                </div>
              </div>
            ) : null}
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
