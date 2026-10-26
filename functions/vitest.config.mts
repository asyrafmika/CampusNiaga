import { defineConfig } from 'vitest/config';

// Unit tests: pure code only, no emulators.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/unit/**/*.test.ts'],
  },
});
