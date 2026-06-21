import type { Explanation } from '@aid/contract';
import { cn } from '../../lib/utils';

interface ExplanationLineProps {
  explanation: Explanation;
  className?: string;
}

/**
 * §8.4 explanation layer, always-visible tier: a muted one-line Czech gloss
 * (the resolved {@link Explanation.headline}). No interaction — the deep gloss
 * lives in {@link ExplanationCard}.
 */
export function ExplanationLine({ explanation, className }: ExplanationLineProps) {
  return <p className={cn('text-sm text-slate-500', className)}>{explanation.headline}</p>;
}
