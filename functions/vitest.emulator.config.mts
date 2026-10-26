import { defineConfig } from 'vitest/config';

// Emulator tests: run through `npm run test:emulator`, which starts the
// emulators with a demo- project so nothing can reach a real project.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/emulator/**/*.test.ts'],
    setupFiles: ['test/emulator/setup.ts'],
    // Tests share one emulator instance and reset it between tests.
    fileParallelism: false,
    testTimeout: 20_000,
    hookTimeout: 20_000,
  },
});
