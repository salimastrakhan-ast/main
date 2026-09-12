import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// Адрес сервера подставляется на сборке. По умолчанию — localhost: так
// `npm run dev` работает сразу после клона, без файла с переменными.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
  },
  server: { host: "0.0.0.0", port: 5173 },
  preview: { host: "127.0.0.1", port: 4173 },
});
