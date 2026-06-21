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
