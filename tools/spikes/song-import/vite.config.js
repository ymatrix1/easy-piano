import { defineConfig } from 'vite';

// Cross-origin isolation for onnxruntime-web threads. `credentialless` lets the
// Demucs model load from Hugging Face, which sends no CORP header.
export default defineConfig({
  server: {
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
  },
  optimizeDeps: { exclude: ['onnxruntime-web'] },
});
