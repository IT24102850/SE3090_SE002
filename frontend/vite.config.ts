/// <reference types="vitest/config" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// NOTE: npm registry access was blocked (403) in the environment these
// tests were authored in, so vitest/@testing-library/* could never actually
// be installed or run here - this config + the *.test.tsx files are
// written and ready, but unverified. Run `npm install` then `npm run test`
// once registry access is available.
export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/setupTests.ts'],
    globals: true,
  },
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