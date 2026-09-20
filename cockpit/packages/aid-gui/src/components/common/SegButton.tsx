import { cn } from '../../lib/utils';

/**
 * A segmented control button with active/inactive states (filled vs. outlined).
 * Used by ScreenE (compliance/coverage segmentation views).
 */
export function SegButton({
  active,
  onClick,
  children,
  ...rest
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
} & React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="button"
      aria-pressed={active}
      onClick={onClick}
      className={cn(
        'min-h-[36px] rounded-lg border px-3 text-xs font-medium',
        active
          ? 'border-slate-900 bg-slate-900 text-white'
          : 'border-slate-200 bg-white text-slate-600 hover:bg-slate-50',
      )}
      {...rest}
    >
      {children}
    </button>
  );
}
