import { defineConfig, devices } from '@playwright/test'

// tool/e2e/web_e2e.sh starts a real engine with the built dashboard and
// sets XPD_URL; the specs run one at a time against it.
const engine = new URL(process.env.XPD_URL ?? 'http://127.0.0.1:7480')

export default defineConfig({
  testDir: 'e2e',
  fullyParallel: false,
  workers: 1,
  forbidOnly: Boolean(process.env.CI),
  reporter: 'list',
  use: {
    baseURL: engine.origin,
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    {
      // WebKit refuses `Secure` cookies on http://localhost (WebKit bug
      // 232088), so it proves the loopback cookie has none (D3a), that the
      // event and log sockets connect under the dashboard's CSP, that an
      // approval is decided there as in Chromium, and that the workflow
      // builder's CodeMirror renders under the CSP.
      name: 'webkit',
      testMatch: /(signin|runs|approvals|workflows)\.spec\.ts/,
      use: {
        ...devices['Desktop Safari'],
        baseURL: `http://localhost:${engine.port}`,
      },
    },
  ],
})
