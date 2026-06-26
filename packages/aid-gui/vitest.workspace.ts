import { defineWorkspace } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineWorkspace([
  // Node tests: server parsers, watchers, store logic, source-analysis frontend tests.
  {
    extends: './vitest.config.ts',
    test: {
      name: 'node',
      environment: 'node',
      include: ['tests/**/*.test.ts'],
      globals: false,
    },
  },
  // Browser-component tests: real DOM via jsdom + @testing-library.
  {
    plugins: [react()],
    test: {
      name: 'dom',
      environment: 'jsdom',
      globals: true,
      include: ['src/**/*.test.{ts,tsx}'],
      setupFiles: ['./vitest.setup.ts'],
    },
  },
]);
