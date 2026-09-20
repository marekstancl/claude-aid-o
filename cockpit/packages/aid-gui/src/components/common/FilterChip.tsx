import { cn } from '../../lib/utils';

/**
 * A filter chip button with active/inactive states (filled vs. outlined).
 * Used by ScreenD and ScreenE (compliance/coverage views).
 */
export function FilterChip({
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
        'min-h-[32px] rounded-full border px-3 text-xs font-medium',
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
