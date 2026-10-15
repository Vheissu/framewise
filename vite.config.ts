import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { defineConfig, type Plugin } from "vitest/config";
import elm from "vite-plugin-elm";

const pkg = JSON.parse(readFileSync(resolve(__dirname, "package.json"), "utf8")) as {
  version: string;
};
const base = process.env.FRAMEWISE_BASE ?? "/";

/** Emits sw.js with the list of built assets to precache, and adds a CSP meta tag in production. */
function framewiseShell(): Plugin {
  return {
    name: "framewise-shell",
    apply: "build",
    transformIndexHtml(html) {
      const csp = [
        "default-src 'self'",
        "script-src 'self'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' blob: data:",
        "connect-src 'self'",
        "font-src 'self'",
        "worker-src 'self'",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'none'",
        "frame-ancestors 'none'",
      ].join("; ");
      return html.replace(
        "<head>",
        `<head>\n    <meta http-equiv="Content-Security-Policy" content="${csp}" />`,
      );
    },
    generateBundle(_, bundle) {
      const files = Object.keys(bundle).map((f) => `${base}${f}`);
      const precache = [
        base,
        `${base}index.html`,
        `${base}manifest.webmanifest`,
        `${base}icons/icon.svg`,
        ...files,
      ];
      const template = readFileSync(resolve(__dirname, "web/sw-template.js"), "utf8");
      const sw = template
        .replace("__VERSION__", `${pkg.version}-${Date.now().toString(36)}`)
        .replace("__PRECACHE__", JSON.stringify(precache))
        .replace(/__BASE__/g, base);
      this.emitFile({ type: "asset", fileName: "sw.js", source: sw });
    },
    closeBundle() {
      // SPA fallback for static hosts such as GitHub Pages
      try {
        const dist = resolve(__dirname, "dist");
        mkdirSync(dist, { recursive: true });
        writeFileSync(resolve(dist, "404.html"), readFileSync(resolve(dist, "index.html")));
      } catch {
        // dist may not exist in some build modes
      }
    },
  };
}

export default defineConfig({
  base,
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
  },
  plugins: [
    elm({ debug: false, optimize: process.env.NODE_ENV === "production" }),
    framewiseShell(),
  ],
  build: {
    target: "es2022",
    sourcemap: true,
  },
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
  },
  preview: {
    host: "127.0.0.1",
    port: 4173,
    strictPort: true,
  },
  test: {
    include: ["tests/unit/**/*.test.ts"],
    environment: "node",
  },
});
