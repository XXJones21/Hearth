import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import path from 'path';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  // 18700 is Hearth's own block; see src/lib/config.ts for why it is not 8700.
  const personaAssetTarget =
    env.VITE_HEARTH_HTTP_ORIGIN || 'http://127.0.0.1:18700';

  return {
    plugins: [react(), tailwindcss()],
    resolve: {
      alias: {
        '@': path.resolve(__dirname, './src'),
      },
    },
    // Tauri dev/prod has no Vite proxy; resolveAssetUrl builds absolute URLs
    // from getHttpOrigin() there. The proxy only serves browser-dev.
    server: {
      port: 1420,
      strictPort: true,
      proxy: {
        '/Persona': {
          target: personaAssetTarget,
          changeOrigin: true,
        },
      },
    },
    preview: {
      proxy: {
        '/Persona': {
          target: personaAssetTarget,
          changeOrigin: true,
        },
      },
    },
  };
});
