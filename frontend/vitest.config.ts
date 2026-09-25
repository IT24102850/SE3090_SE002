/// <reference types="vitest/config" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Separate from vite.config.ts on purpose: this file is only ever read by
// `vitest` itself, never by `tsc`/`vite build` (the production build path),
// so it's safe for it to depend on packages that aren't installed yet.
//
// npm registry access was blocked (403) in the environment these tests were
// authored in, so vitest/@testing-library/*/jsdom could never actually be
// installed or run here - this config + the *.test.tsx files are written
// and ready, but unverified. To actually run them:
//   npm install --save-dev vitest @testing-library/react @testing-library/jest-dom @testing-library/user-event jsdom
//   npm run test
export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/setupTests.ts'],
    globals: true,
  },
});
