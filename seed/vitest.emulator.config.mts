import { defineConfig } from 'vitest/config';

// Emulator tests: run through `npm run test:emulator`.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/emulator/**/*.test.ts'],
    fileParallelism: false,
    testTimeout: 20_000,
    hookTimeout: 20_000,
  },
});
