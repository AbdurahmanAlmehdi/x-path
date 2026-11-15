import { fileURLToPath, URL } from 'node:url'

import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'

// The design tokens are shared with the Mac app (docs/design), not copied.
const design = fileURLToPath(
  new URL('../../docs/design/system/project/assets/Handoff', import.meta.url),
)

// `npm run dev` proxies the API to an engine on this machine. The engine
// accepts a browser's request only from an origin it serves (ADR 0018, D15),
// so the proxy presents the engine's own loopback origin.
const engine = process.env.XPD_URL ?? 'http://127.0.0.1:7480'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      '@design': design,
    },
  },
  server: {
    fs: { allow: ['.', design] },
    proxy: {
      '/api': {
        target: engine,
        changeOrigin: true,
        ws: true,
        headers: { origin: new URL(engine).origin },
      },
    },
  },
  build: {
    // xpd serves `assets/*` as immutable, so every file there is hashed.
    assetsDir: 'assets',
    sourcemap: false,
  },
})
