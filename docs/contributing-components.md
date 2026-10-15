# Contributing components

Checklists for the parts of Framewise that have to stay in sync.

## Node kind

1. `Domain.Node.NodeGeometry` variant plus `kindCode`, `kindLabel`, `geometryBounds`, `toPathGeometry` where it makes sense.
2. `DocumentIO.Encode.geometry` and `DocumentIO.Decode.geometry`.
3. `Domain.Validation.geometryCheck`.
4. `Render.Scene.shapeElement`.
5. Inspector section in `Editor.Inspector.geometrySection`; layer icon in `Editor.Layers.kindIcon`.
6. Importer mapping in `web/adapters/svg-import.ts` if SVG has an equivalent.
7. Player support in `web/player/framewise-player.js` if any property of it animates.
8. Tests: codec round trip, validation, a golden fixture if animated.

## Animatable property

1. `Domain.Property.PropertyPath` variant with `pathToCode`, `pathLabel`, `valueKind`, `isDiscrete`.
2. `Domain.Node.animatableProperties`.
3. `App.Edit.applyBaseValue` and `baseValueOf`; `Domain.Evaluate.baseValue` and the evaluator branch.
4. Inspector diamond.
5. `Export.Capability.classify` for every format; exporter branches in `Export.Smil`, `Export.Css`; player support.
6. Golden fixture with expectations.

## Export format

1. `Export.Format` entry, `availability` set to `Available` only with a tested adapter.
2. Capability classification.
3. Adapter in `web/adapters/export.ts` that validates its own output with an independent parser.
4. Playwright test that downloads the file and checks it outside the app.
5. Entry in `docs/export-compatibility.md`.
