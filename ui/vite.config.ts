import { reactRouter } from "@react-router/dev/vite";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";

export default defineConfig({
  plugins: [tailwindcss(), reactRouter(), tsconfigPaths()],
  ssr: {
    // Exclude ReactFlow from SSR since we're doing client-side only
    external: ["@xyflow/react", "node:fs", "node:fs/promises", "node:path"],
  },
});
