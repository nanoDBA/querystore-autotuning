import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts"],
  format: ["cjs", "esm"],
  target: "es2022",
  outDir: "dist",
  dts: true,
  sourcemap: true,
  clean: true,
  minify: false,
  keepNames: true,
});
