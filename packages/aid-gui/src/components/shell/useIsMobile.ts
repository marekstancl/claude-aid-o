import { useEffect, useState } from 'react';

/** Shell mobile breakpoint. Salvaged from the orphaned App.tsx. */
export const MOBILE_BREAKPOINT = 768;

/**
 * Tracks whether the viewport is in the mobile range using matchMedia.
 * Boundary note: the query is `max-width: 767px`, so exactly 768px = desktop.
 */
export function useIsMobile(): boolean {
  const [isMobile, setIsMobile] = useState(() =>
    typeof window !== 'undefined'
      ? window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`).matches
      : false,
  );

  useEffect(() => {
    const mediaQuery = window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`);
    const handleChange = (e: MediaQueryListEvent | MediaQueryList) => setIsMobile(e.matches);
    handleChange(mediaQuery);
    mediaQuery.addEventListener('change', handleChange);
    return () => mediaQuery.removeEventListener('change', handleChange);
  }, []);

  return isMobile;
}
