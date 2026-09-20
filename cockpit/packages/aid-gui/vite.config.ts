import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    VitePWA({
      registerType: 'autoUpdate',
      manifest: {
        name: 'AID Cockpit', short_name: 'AID',
        description: 'Cross-project monitoring for the AID orchestrator',
        background_color: '#f8fafc', theme_color: '#0284c7',
        display: 'standalone', start_url: '/',
        icons: [
          { src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: '/icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: '/icon-512-maskable.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,woff2}'],
        navigateFallback: '/index.html',
        runtimeCaching: [
          { urlPattern: ({ url }) => url.pathname.startsWith('/api'), handler: 'NetworkOnly' },
        ],
      },
    }),
  ],
  server: {
    proxy: {
      // 127.0.0.1, NOT localhost: aid-server binds IPv4 (127.0.0.1) only, while
      // `localhost` resolves to ::1 (IPv6) first on dual-stack hosts → the dev
      // proxy would 500 on /api and fail the /ws handshake.
      '/api': { target: 'http://127.0.0.1:3911', changeOrigin: true },
      '/ws': { target: 'ws://127.0.0.1:3911', ws: true },
    },
  },
  build: { target: 'es2020', rollupOptions: { output: { manualChunks: { 'vendor-react': ['react','react-dom'], 'vendor-recharts': ['recharts'] } } } },
});
