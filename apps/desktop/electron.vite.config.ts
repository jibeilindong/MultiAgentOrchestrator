import path from "node:path";
import { defineConfig } from "electron-vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  main: {
    build: {
      outDir: "out/main",
      rollupOptions: {
        input: path.resolve(__dirname, "electron/main.ts")
      }
    }
  },
  preload: {
    build: {
      outDir: "out/preload",
      rollupOptions: {
        input: path.resolve(__dirname, "electron/preload.ts")
      }
    }
  },
  renderer: {
    root: __dirname,
    plugins: [react()],
    resolve: {
      alias: {
        "@": path.resolve(__dirname, "src")
      }
    },
    build: {
      outDir: "out/renderer",
      rollupOptions: {
        input: path.resolve(__dirname, "index.html")
      }
    }
  }
});
