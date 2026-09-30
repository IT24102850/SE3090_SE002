/// <reference types="vitest/config" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Separate from vite.config.ts on purpose: this file is only ever read by
// `vitest` itself, never by `tsc`/`vite build` (the production build path),
// so it's safe for it to depend on packages that aren't installed yet.
//
// Run with `npm run test` (CI runs it on every push and pull request).
export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/setupTests.ts'],
    globals: true,
  },
});
