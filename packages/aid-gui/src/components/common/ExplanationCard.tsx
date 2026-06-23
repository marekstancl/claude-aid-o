import { useState } from 'react';
import { Popover } from '@base-ui/react/popover';
import { Dialog } from '@base-ui/react/dialog';
import { Info, X } from 'lucide-react';
import type { Explanation } from '@aid/contract';
import { useIsMobile } from '../shell/useIsMobile';

interface ExplanationCardProps {
  explanation: Explanation;
  /** Accessible label for the info trigger (defaults to a Czech phrase). */
  triggerLabel?: string;
}

const TRIGGER_CLASS =
  'inline-flex h-11 w-11 items-center justify-center rounded-lg text-slate-400 hover:bg-slate-100 hover:text-slate-600';

/**
 * §8.4 explanation layer, deep tier: an info trigger that opens the resolved
 * {@link Explanation.detail}. Desktop → base-ui Popover (click, never
 * hover-only). Mobile → bottom-sheet Dialog opened on tap. The trigger is a
 * real ≥44px button. When `detail` is empty the trigger is hidden entirely
 * (no empty popover).
 */
export function ExplanationCard({ explanation, triggerLabel = 'Zobrazit vysvětlení' }: ExplanationCardProps) {
  const isMobile = useIsMobile();
  const [open, setOpen] = useState(false);

  // Empty detail → nothing to deep-explain; hide the trigger.
  if (!explanation.detail.trim()) return null;

  if (isMobile) {
    return (
      <Dialog.Root open={open} onOpenChange={setOpen}>
        <Dialog.Trigger className={TRIGGER_CLASS} aria-label={triggerLabel}>
          <Info aria-hidden className="h-5 w-5" />
        </Dialog.Trigger>
        <Dialog.Portal>
          <Dialog.Backdrop className="fixed inset-0 z-50 bg-slate-900/40" />
          <Dialog.Popup className="fixed inset-x-0 bottom-0 z-50 max-h-[80vh] overflow-y-auto rounded-t-2xl border-t border-slate-200 bg-white pb-[env(safe-area-inset-bottom)] shadow-xl">
            <div className="flex items-start justify-between gap-3 border-b border-slate-200 px-4 py-3">
              <Dialog.Title className="text-base font-semibold text-slate-900">
                {explanation.headline}
              </Dialog.Title>
              <Dialog.Close
                className="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg text-slate-500 hover:bg-slate-100"
                aria-label="Zavřít"
              >
                <X className="h-5 w-5" />
              </Dialog.Close>
            </div>
            <Dialog.Description className="px-4 py-4 text-sm leading-relaxed text-slate-700">
              {explanation.detail}
            </Dialog.Description>
          </Dialog.Popup>
        </Dialog.Portal>
      </Dialog.Root>
    );
  }

  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger className={TRIGGER_CLASS} aria-label={triggerLabel}>
        <Info aria-hidden className="h-5 w-5" />
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Positioner sideOffset={6} className="z-50">
          <Popover.Popup className="max-w-xs rounded-xl border border-slate-200 bg-white p-4 shadow-lg">
            <Popover.Title className="mb-1 text-sm font-semibold text-slate-900">
              {explanation.headline}
            </Popover.Title>
            <Popover.Description className="text-sm leading-relaxed text-slate-700">
              {explanation.detail}
            </Popover.Description>
          </Popover.Popup>
        </Popover.Positioner>
      </Popover.Portal>
    </Popover.Root>
  );
}
