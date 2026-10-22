import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: {
    target: 'es2020', sourcemap: false, chunkSizeWarningLimit: 1000,
    rollupOptions: {
      output: {
        // stable vendor chunks: browsers keep them cached between releases
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined;
          if (/[\\/]node_modules[\\/](react|react-dom|react-router|react-router-dom|scheduler)[\\/]/.test(id)) return 'vendor-react';
          if (id.includes('@supabase')) return 'vendor-supabase';
          if (id.includes('lucide-react')) return 'vendor-icons';
          if (id.includes('@fontsource')) return 'vendor-fonts';
          return undefined;
        },
      },
    },
  },
  test: { environment: 'jsdom', globals: false, include: ['src/**/*.test.{ts,tsx}', 'supabase/functions/**/*.test.ts'] },
});
