import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Test-only config (vitest, jsdom, @testing-library/*) lives in
// vitest.config.ts, deliberately NOT here - this file is on the production
// build path (`tsc && vite build`), and none of those packages are actually
// installed yet (npm registry access was blocked when they were added), so
// referencing them here would break every build until someone runs
// `npm install` locally. See vitest.config.ts for details.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    open: true,
    proxy: {
      '/api': {
        target: 'http://localhost:5298',
        changeOrigin: true,
      },
    }
  }
});