/// <reference types="vitest" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: { target: 'es2020', sourcemap: false, chunkSizeWarningLimit: 900 },
  test: { environment: 'jsdom', globals: false, include: ['src/**/*.test.{ts,tsx}'] },
});
