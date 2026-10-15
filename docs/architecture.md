# Architecture

Framewise is an Elm application with a thin TypeScript layer for things the browser only exposes through JavaScript. The split is strict: Elm owns every piece of application meaning, TypeScript owns I/O.

## Elm

```
src/
  Domain/        pure model and algorithms
  DocumentIO/    JSON encode/decode for the native format
  Export/        SVG, SMIL, CSS and player-JSON exporters, capability reports
  Render/        one SVG element tree that renders to the virtual DOM and to text
  App/           model, messages, update, command registry, persistence requests
  Editor/        canvas, layers, inspector, timeline, preview, dialogs
  UI/            icons, fields, colour picker
```

`Domain.Evaluate.evaluateScene document sceneId frame` is the single evaluator. It resolves every node's local and world matrix, opacity, visibility, paint, geometry and effects at a continuous frame. The canvas, the preview, thumbnails and every exporter read from it; nothing else interpolates keyframes. Editor state (selection, hover, gesture) is never an input.

Matrix convention: column vectors, `multiply a b` applies `b` first. A node's local matrix is `T(translation) · [T(offset) · R(motionAngle)] · T(pivot) · R(rotation) · skewX · skewY · S(scale) · T(-pivot)`, which is exactly the nested-group structure the SMIL and CSS exporters emit, so those outputs are equivalent to the editor by construction. `Matrix.decompose` reverses this with a fixed pivot; world-space resize and rotate use it so rotated and nested nodes keep their component representation.

History stores document snapshots (Elm structures share unchanged parts). `App.Edit.commit` is the only path that records an entry, bumps the revision and schedules an autosave. Pointer gestures edit a transient copy and commit once on pointer up.

## TypeScript

```
web/
  main.ts                 boots Elm with flags, wires the bridge, drag and drop, service worker
  adapters/bridge.ts      request/response envelope over one port pair
  adapters/protocol.ts    envelope validation at ingress
  adapters/storage.ts     IndexedDB: projects, autosave checkpoints, saved copies, assets, settings
  adapters/archive.ts     .framewise ZIP packing with limits and hash checks
  adapters/files.ts       pickers, writable handles behind opaque tokens, download fallback
  adapters/sanitise-svg.ts, svg-import.ts   hostile-SVG handling and conversion to typed nodes
  adapters/raster.ts      SVG to PNG through a same-origin blob and canvas
  adapters/export.ts      validates and packages exporter output
  adapters/elements.ts    custom elements for geometry reporting, safe SVG preview, dialog focus
  player/framewise-player.js   runtime shipped in HTML exports
```

## Bridge protocol

Every request from Elm is `{ protocolVersion, requestId, operation, documentId, revision, payload }`. Operation names are dotted identifiers; the adapter rejects anything else before dispatch. Responses carry the same `requestId` and `operation` with `status: "ok" | "error"`; errors have a stable `code`, a user-safe `message` and `retryable`. Unsolicited events (visibility change, dropped files, tab conflicts) use `status: "event"`.

Operations:

| Operation | Direction | Purpose |
|---|---|---|
| `platform.ids` | request | Batch of `crypto.randomUUID` ids for new objects |
| `platform.focus`, `platform.fullscreen` | request | DOM focus and full-screen |
| `session.dirty` | request | Toggle the `beforeunload` guard |
| `storage.autosave`, `storage.load`, `storage.recents`, `storage.delete`, `storage.loadSaved`, `storage.downloadRecovery`, `storage.clear`, `storage.persist`, `storage.preferences`, `storage.layout` | request | IndexedDB persistence |
| `file.open`, `file.save`, `file.downloadText` | request | Files and downloads; `file.open` returns a document, an SVG import review or an image asset depending on the file |
| `clipboard.write`, `clipboard.read` | request | System clipboard with denial reported as an error |
| `export.run`, `export.cancel` | request | Package and download; progress arrives as `export.progress` events |
| `event.visibility`, `event.dragOverlay`, `event.offlineReady`, `event.capabilities`, `event.tabConflict` | event | Browser state |

Large binaries never cross the bridge as base64. Image assets live in IndexedDB under their SHA-256 and are referenced by id; the canvas gets blob URLs, exports get data URIs substituted for `fw-asset://<id>` tokens.

## Persistence

`projects` holds the latest working copy and metadata per document. `revisions` keeps the last five autosave checkpoints plus the one matching the last file save. `saved` holds the document as it was at the last explicit save, which is what Revert restores. Recovery candidates are projects whose latest autosave revision is ahead of their saved revision.

## Rendering

`Render.Scene` builds an `Element` tree from a resolved scene. `Render.SvgDoc.toHtml` turns it into the virtual DOM for the canvas and preview; `toString` serialises it for exports. Editor overlays are a separate SVG layered above the artwork and are never part of the tree, so they cannot leak into files.
