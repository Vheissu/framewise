# Contributing

## Setup

```bash
pnpm install --frozen-lockfile
pnpm run dev            # http://localhost:5173
```

Checks that run in CI, in the same order:

```bash
pnpm run typecheck
pnpm run lint
pnpm run format:check
pnpm run elm:test
pnpm run test:unit
pnpm run test:e2e       # needs: pnpm exec playwright install
pnpm run build
pnpm run preview
```

`pnpm run format` applies elm-format and prettier.

## Where things live

- `src/Domain` is pure: document model, matrix maths, paths, easing, keyframes, the evaluator, history and validation. No ports, no DOM.
- `src/DocumentIO` encodes and decodes the document JSON. Every enum has a string code and a strict decoder.
- `src/Export` turns an evaluated scene into SVG, SMIL, CSS or the portable player JSON, with a capability report per track.
- `src/App` holds the Elm model, messages, update and the command registry. `App.Edit` is the only place that commits history.
- `src/Editor` and `src/UI` are views.
- `web/adapters` is TypeScript for the browser: IndexedDB, archives, file pickers, SVG sanitising and import, rasterising, export packaging. It never keeps its own copy of the document.
- `web/player/framewise-player.js` is the runtime shipped inside HTML exports.

See `docs/architecture.md` for the port protocol and the evaluation contract.

## Adding things

A new node kind needs: the `NodeGeometry` variant, encoder and decoder, validation, renderer (`Render.Scene`), inspector controls, bounds (`Node.geometryBounds`), the importer mapping if SVG has an equivalent, and tests.

A new animatable property needs: a `PropertyPath` variant with its code and value kind, `Edit.applyBaseValue` and `Evaluate` support, inspector diamond, a classification in `Export.Capability` for every format, and an exporter mapping or an explicit Unsupported reason.

A new export format needs an entry in `Export.Format`, a capability classification, an adapter that validates its own output with an independent parser, and a Playwright test that downloads and inspects the file. Formats without a verified adapter stay listed as unavailable.

## Golden fixtures

`tests/golden/*.json` hold animations with expected values. `node tests/golden/generate-elm.mjs` regenerates `tests/GoldenTest.elm`; the JavaScript player reads the same JSON in `tests/unit/player.test.ts`. Change expectations only with a reason in the commit message.

## Pull requests

Keep commits focused and describe the behaviour change, not the diff. Include a fixture for any geometry, timing or import bug.
