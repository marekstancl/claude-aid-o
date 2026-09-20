import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    globals: false,
  },
  resolve: {
    // Allow imports with .ts extensions (used by parsers)
    conditions: ['node'],
  },
});
