import React, { useMemo } from 'react';
import { Lightbulb, FileText, Play, ShieldCheck, HelpCircle, Wrench, MessageCircle } from 'lucide-react';
import { cn } from '../../lib/utils';
import { useStore } from '../../store';

export interface HintButtonsProps {
  onHint: (prompt: string) => void;
  onFocus: () => void;
  variant?: 'full' | 'compact';
}

export interface HintDef {
  id: string;
  label: string;
  description: string;
  icon: React.ElementType;
  template: (ctx: HintContext) => string | null;
}

export interface HintContext {
  projectName: string | null;
  epicId: string | null;
  focusedIdeaTitle: string | null;
}

export const HINTS: HintDef[] = [
  {
    id: 'brainstorm', label: 'Brainstorm', description: 'Generate ideas for your project', icon: Lightbulb,
    template: (ctx) =>
      `Brainstorm ideas for ${ctx.projectName ?? 'this project'}.${ctx.focusedIdeaTitle ? ` Context: "${ctx.focusedIdeaTitle}".` : ''}`,
  },
  {
    id: 'plan', label: 'Plan EPIC', description: 'Create a structured implementation plan', icon: FileText,
    template: (ctx) => `Create an EPIC plan for: ${ctx.focusedIdeaTitle ?? 'a new feature'}.`,
  },
  {
    id: 'run', label: 'Run', description: 'Check current pipeline execution status', icon: Play,
    template: (ctx) =>
      ctx.epicId
        ? `What is the status of the current pipeline run for ${ctx.epicId}?`
        : 'What is the status of the current pipeline run?',
  },
  {
    id: 'audit', label: 'Audit', description: 'Run health audit and summarize findings', icon: ShieldCheck,
    template: () => 'Run a health audit on the project and summarize the findings.',
  },
  {
    id: 'explain', label: 'Explain', description: 'Explain architecture or a specific topic', icon: HelpCircle,
    template: (ctx) =>
      `Explain ${ctx.focusedIdeaTitle ? `"${ctx.focusedIdeaTitle}"` : 'the current project architecture'}.`,
  },
  {
    id: 'fix', label: 'Fix', description: 'Help diagnose and resolve an issue', icon: Wrench,
    template: (ctx) => `Help me fix: ${ctx.focusedIdeaTitle ?? 'an issue I am experiencing'}.`,
  },
  {
    id: 'free', label: 'Free chat', description: 'Open conversation about anything', icon: MessageCircle,
    template: () => null,
  },
];

/**
 * Context-aware hint command buttons for the AI Companion.
 *
 * Renders 7 hint buttons that generate prompt templates using project context
 * from the Zustand store: active project name, current EPIC ID, and the most
 * relevant idea (exploring status or most recently updated).
 */
export const HintButtons: React.FC<HintButtonsProps> = ({ onHint, onFocus, variant = 'full' }) => {
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

  const ctx: HintContext = { projectName, epicId, focusedIdeaTitle };

  const handleClick = (hint: HintDef) => {
    const prompt = hint.template(ctx);
    if (prompt === null) onFocus();
    else onHint(prompt);
  };

  if (variant === 'compact') {
    return (
      <div className="flex flex-wrap gap-1.5 px-1 pb-2">
        {HINTS.map((h) => (
          <button key={h.id} type="button" onClick={() => handleClick(h)}
            className={cn(
              'flex items-center gap-1 px-2 py-1 rounded-lg text-[11px]',
              'bg-white/5 text-white/40 hover:bg-white/10 hover:text-white/70 transition-colors',
            )}
            aria-label={h.label}>
            <h.icon size={12} />
            <span>{h.label}</span>
          </button>
        ))}
      </div>
    );
  }

  return (
    <div className="grid grid-cols-2 gap-2 w-full max-w-xs">
      {HINTS.map((h) => (
        <button key={h.id} type="button" onClick={() => handleClick(h)}
          className={cn(
            'flex items-center gap-2 px-3 py-2 rounded-xl text-xs',
            'bg-white/5 text-white/40 hover:bg-white/10 hover:text-white/70',
            'border border-white/5 hover:border-white/10 transition-all',
            h.id === 'free' && 'col-span-2',
          )}
          aria-label={h.label}>
          <h.icon size={14} className="shrink-0" />
          <span>{h.label}</span>
        </button>
      ))}
    </div>
  );
};

HintButtons.displayName = 'HintButtons';
