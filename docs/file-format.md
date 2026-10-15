# File format

## Archive

A `.framewise` file is a ZIP archive:

```
manifest.json
document.json
assets/sha256-<hash>.<png|jpg|webp>
thumbnails/project.svg          optional
```

`manifest.json` records `format: "framewise"`, `schemaVersion`, the generator version, the document id, timestamps, the document path and an asset table with `id`, `path`, `mimeType`, `byteLength` and `sha256`.

On open the reader checks, in order: ZIP signature, entry count (≤ 2000), every path (relative, no `..`, no backslashes, no duplicates), total uncompressed size (≤ 512 MB), manifest shape, schema version (newer versions are refused with a message, never downgraded), then each asset's size and SHA-256 against the manifest. Only then is `document.json` decoded by the strict Elm decoders and validated as a graph. Nothing from the archive is ever executed or inserted as markup.

## document.json

```
Document { id, schemaVersion, metadata{name, description, createdAt, modifiedAt}, sceneOrder[], scenes[], assets[] }
Scene    { id, name, description, width, height, background, fps{numerator, denominator}, durationFrames,
           playbackMode, markers[], workRange?, rootNodeIds[], nodes[], tracks[], motionPaths[], guides[] }
Node     { id, name, kind, parentId?, childIds[], hidden, locked, opacity, transform, geometry, fill, stroke,
           effects[], motion?, metadata{importedElementId?} }
Track    { id, target{nodeId, property}, enabled, locked, keyframes[] }
Keyframe { id, frame, value, easing }
```

Both `parentId` and `childIds` are stored; the validator requires them to agree and refuses documents where they do not.

Enum codes:

- `kind`: `rect`, `ellipse`, `line`, `polygon`, `path`, `text`, `image`, `group`, `clipGroup`
- `property`: `transform.position`, `transform.scale`, `transform.rotation`, `transform.skew`, `transform.pivot`, `compositing.opacity`, `compositing.visible`, `style.fill.color`, `style.stroke.color`, `style.stroke.width`, `style.stroke.dashOffset`, `shape.rect.size`, `shape.rect.cornerRadius`, `shape.ellipse.radii`, `shape.path.geometry`, `text.fontSize`, `text.content`, `motion.progress`, `effects.blur.radius`
- value `type`: `scalar`, `angle`, `point`, `size`, `color`, `bool`, `string`, `path`, `numbers`
- easing `type`: `hold`, `linear`, `preset` (with `name`), `cubicBezier` (`x1 y1 x2 y2`), `spring` (`mass stiffness damping velocity`)
- `playbackMode`: `once`, `repeat`, `pingpong`
- paint `type`: `none`, `solid`, `linearGradient`, `radialGradient`

Numbers must be finite. Colours are RGBA in `[0,1]`. Path geometry is a list of subpaths, each with a `start`, `closed` flag and segments of type `line` or `cubic`.

## Snapshots

Save Snapshot as JSON writes `document.json` on its own. It can be opened again, but image assets are not included.

## Versioning

`schemaVersion` is 1. It increments only for incompatible changes, each shipped with a migration and a fixture test. The application version is recorded separately as `generatorVersion`.
