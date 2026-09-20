import { useNavigate } from 'react-router-dom';
import { ChevronLeft } from 'lucide-react';
import { useIsMobile } from './useIsMobile';

/**
 * Detail screens (B, Plan, C) push full-screen on mobile with a back chevron.
 * On desktop the breadcrumb covers navigation, so this renders nothing.
 */
export function MobileBackHeader({ title }: { title: string }) {
  const isMobile = useIsMobile();
  const navigate = useNavigate();
  if (!isMobile) return null;
  return (
    <header className="flex h-12 items-center gap-2 border-b border-slate-200 px-2">
      <button
        type="button"
        onClick={() => navigate(-1)}
        aria-label="Zpět"
        className="flex h-11 w-11 items-center justify-center rounded-lg text-slate-600 hover:bg-slate-100"
      >
        <ChevronLeft className="h-5 w-5" />
      </button>
      <span className="truncate text-sm font-medium text-slate-900">{title}</span>
    </header>
  );
}
