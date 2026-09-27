import '@testing-library/jest-dom/vitest';

/* jsdom implements neither of these, and a component that calls one throws
 * during render — which surfaces as "unable to find <text>" rather than as
 * the missing API, so it is worth stubbing centrally rather than per-suite.
 *
 * Note this is the setup file vitest.config.ts points at; src/test/setup.ts
 * belongs to vite.config.ts's test block, which vitest.config.ts overrides. */

if (!window.matchMedia) {
  window.matchMedia = ((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},      // deprecated, still called by some libraries
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  })) as unknown as typeof window.matchMedia;
}

if (!globalThis.ResizeObserver) {
  globalThis.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  } as unknown as typeof ResizeObserver;
}
