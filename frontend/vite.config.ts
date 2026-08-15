import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

// Test-only config (vitest, jsdom, @testing-library/*) lives in
// vitest.config.ts, deliberately NOT here - this file is on the production
// build path (`tsc && vite build`), and none of those packages are actually
// installed yet (npm registry access was blocked when they were added), so
// referencing them here would break every build until someone runs
// `npm install` locally. See vitest.config.ts for details.
export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      manifest: {
        name: 'Universal SME Management Platform',
        short_name: 'SME Platform',
        description: 'Multi-tenant SaaS for booking, resources, billing, and inventory across any business type.',
        theme_color: '#2563eb',
        background_color: '#0f172a',
        display: 'standalone',
        start_url: '/dashboard',
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'icon-512-maskable.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
    }),
  ],
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