import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import './index.css';

// Step 1 scaffold skeleton. Routes, providers (QueryClientProvider — Step 3),
// and screens are wired in later steps. vite-plugin-pwa (registerType:'autoUpdate')
// injects + registers the service worker automatically; no manual registration needed.
function AppShell() {
  return (
    <main style={{ padding: '2rem', fontFamily: 'Inter, system-ui, sans-serif' }}>
      <h1>AID Cockpit</h1>
      <p>Cross-project monitoring for the AID orchestrator.</p>
    </main>
  );
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <AppShell />
    </BrowserRouter>
  </StrictMode>,
);
