import { defineConfig, mergeConfig } from 'vitest/config'

import viteConfig from './vite.config.ts'

// D5: 100% lines for the API client and every Pinia store, 90% for the rest.
// Files no test imports count too (`include`).
export default mergeConfig(
  viteConfig,
  defineConfig({
    test: {
      environment: 'jsdom',
      include: ['src/**/*.test.ts'],
      restoreMocks: true,
      unstubGlobals: true,
      coverage: {
        provider: 'v8',
        include: ['src/**/*.{ts,vue}'],
        exclude: ['src/**/*.test.ts', 'src/**/*.d.ts', 'src/app/main.ts', 'src/testing/**'],
        reporter: ['text', 'lcov'],
        thresholds: {
          lines: 90,
          'src/api/**': { lines: 100 },
          'src/features/*/stores/**': { lines: 100 },
        },
      },
    },
  }),
)
