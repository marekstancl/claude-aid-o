import '@testing-library/jest-dom/vitest';

// jsdom ships no `matchMedia`. Components that read the viewport via
// `useIsMobile` (e.g. the §8.2 managerial cards/tables) need a stub; default to
// the desktop branch (`matches: false`). A test that wants the mobile branch
// overrides `window.matchMedia` itself (and restores it in afterEach).
if (typeof window !== 'undefined' && typeof window.matchMedia !== 'function') {
  window.matchMedia = (query: string): MediaQueryList =>
    ({
      matches: false,
      media: query,
      onchange: null,
      addEventListener: () => {},
      removeEventListener: () => {},
      addListener: () => {},
      removeListener: () => {},
      dispatchEvent: () => false,
    }) as unknown as MediaQueryList;
}

// jsdom ships no `ResizeObserver`. recharts' `ResponsiveContainer` constructs one
// on mount (Screen B's Audit-trend chart, Screen A/Plan charts). Provide a no-op
// stub so chart-bearing components render in tests without throwing.
if (typeof globalThis !== 'undefined' && typeof globalThis.ResizeObserver === 'undefined') {
  globalThis.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  } as unknown as typeof ResizeObserver;
}

// jsdom ships no `IntersectionObserver`. Screen F's Help scrollspy constructs one
// over its Section refs. Provide a no-op stub (it never fires in jsdom — the
// screen's scrollspy is purely a UX nicety and degrades to the first section)
// so the Help screen renders in tests without throwing.
if (typeof globalThis !== 'undefined' && typeof globalThis.IntersectionObserver === 'undefined') {
  globalThis.IntersectionObserver = class {
    readonly root = null;
    readonly rootMargin = '';
    readonly thresholds: ReadonlyArray<number> = [];
    constructor() {}
    observe() {}
    unobserve() {}
    disconnect() {}
    takeRecords() {
      return [];
    }
  } as unknown as typeof IntersectionObserver;
}
