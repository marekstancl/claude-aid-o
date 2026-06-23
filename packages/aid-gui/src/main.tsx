import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { RouterProvider } from 'react-router-dom';
import { QueryClientProvider } from '@tanstack/react-query';
import { router } from './router';
import { queryClient } from './lib/queryClient';
import './index.css';

// vite-plugin-pwa (registerType:'autoUpdate') injects + registers the service
// worker automatically; no manual registration needed.
// QueryClientProvider wraps the whole router tree (incl. the <App/> layout) so
// every screen shares the one cache that useAidSocket / usePollingFallback drive.
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  </StrictMode>,
);
