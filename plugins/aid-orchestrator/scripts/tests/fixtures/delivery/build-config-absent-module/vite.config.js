// vite.config.js — references a module that does not exist (DG-11 fail fixture)
export default {
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['./src/lib/missing-module.js']
        }
      }
    }
  }
}
