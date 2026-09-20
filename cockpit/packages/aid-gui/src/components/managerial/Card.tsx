import type { ReactNode } from 'react';
import { Collapsible } from '@base-ui/react/collapsible';
import { ChevronDown } from 'lucide-react';
import { cn } from '../../lib/utils';
import { useIsMobile } from '../shell/useIsMobile';

interface CardProps {
  /** Card heading (Czech). */
  title: ReactNode;
  /** Optional trailing element in the header (e.g. a counts pill). */
  action?: ReactNode;
  /** Collapse to a header-only toggle on mobile (default false → always open). */
  collapsibleOnMobile?: boolean;
  /** Initial open state for the collapsible variant (default true). */
  defaultOpen?: boolean;
  children: ReactNode;
  className?: string;
}

/**
 * Managerial surface primitive (§8.2). A plain white card with a header and a
 * body. When `collapsibleOnMobile` is set AND the viewport is mobile, the body
 * collapses behind a base-ui `Collapsible` toggle so dense Brief blocks stay
 * scannable on a phone. On desktop (or when not collapsible) the body is always
 * visible — never hidden behind interaction the manager can't see.
 *
 * This composes the existing shell primitives only; it introduces no new visual
 * vocabulary (same border/surface tokens as ProjectTile / ExplanationCard).
 */
export function Card({
  title,
  action,
  collapsibleOnMobile = false,
  defaultOpen = true,
  children,
  className,
}: CardProps) {
  const isMobile = useIsMobile();

  if (collapsibleOnMobile && isMobile) {
    return (
      <Collapsible.Root
        defaultOpen={defaultOpen}
        data-card
        className={cn('rounded-lg border border-slate-200 bg-white', className)}
      >
        <Collapsible.Trigger className="group flex w-full items-center justify-between gap-2 px-4 py-3 text-left">
          <span className="flex items-center gap-2 text-sm font-semibold text-slate-800">{title}</span>
          <span className="flex items-center gap-2">
            {action}
            <ChevronDown
              aria-hidden
              className="h-4 w-4 text-slate-400 transition-transform group-data-[panel-open]:rotate-180"
            />
          </span>
        </Collapsible.Trigger>
        <Collapsible.Panel className="border-t border-slate-100 px-4 py-3">{children}</Collapsible.Panel>
      </Collapsible.Root>
    );
  }

  return (
    <section data-card className={cn('rounded-lg border border-slate-200 bg-white', className)}>
      <div className="flex items-center justify-between gap-2 px-4 py-3">
        <h3 className="flex items-center gap-2 text-sm font-semibold text-slate-800">{title}</h3>
        {action}
      </div>
      <div className="border-t border-slate-100 px-4 py-3">{children}</div>
    </section>
  );
}
