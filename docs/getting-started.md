# Getting started

The in-app documentation (Help › Getting Started) covers the editor. This page is about running the project.

```bash
pnpm install --frozen-lockfile
pnpm run dev
```

Open http://localhost:5173. The first run downloads Elm packages into `~/.elm`.

Production build for a static host:

```bash
FRAMEWISE_BASE=/framewise/ pnpm run build
pnpm run preview
```

`FRAMEWISE_BASE` sets the URL prefix (GitHub Pages serves project sites under the repository name). The build emits `sw.js` with a precache list and a `404.html` copy of the shell so deep links to `/editor/<id>` resolve.
