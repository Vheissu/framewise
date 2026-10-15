# Framewise

## Comprehensive Product, Architecture, and Implementation Specification

**Product:** Framewise  
**Category:** Open-source, local-first SVG and vector animation editor  
**Primary implementation:** Elm 0.19.3, TypeScript interoperability modules, SVG, HTML, CSS  
**Distribution:** Browser application and installable Progressive Web App (PWA)  
**Source licence:** MIT, subject to verifying all vendored dependency and asset licences  
**Native document format:** `.framewise` (versioned ZIP container)  
**Document status:** Authoritative implementation contract for an autonomous coding agent  
**Specification date:** 15 October 2026

---

## 1. Executive definition

Framewise is a polished, desktop-grade, open-source vector animation authoring application that runs locally in the browser. It combines a precise SVG illustration workspace with a keyframe timeline, compositing controls, motion paths, vector editing, reusable symbols, an easing editor, and reliable exports. Users can draw an icon, import an existing SVG, animate independent named layers, preview their work, save an editable native document, and export animation assets for websites and other products.

**Product promise:** Create and animate vector artwork in a visual editor without surrendering control of the SVG, the keyframes, the file, or the output.

The core application must work without an account or remote service. Project contents stay on the user's device unless the user explicitly exports or shares them. The editor must be useful for a working designer or developer, not merely an animation demonstration. It must prioritize predictable controls, undoability, non-destructive editing, legible design, and portability.

Framewise is **not** a clone of Adobe XD, After Effects, Figma, or Rive. It is a tightly focused SVG/vector animation studio with a coherent interaction model. Its presentation should feel like a restrained professional creative application, not a template dashboard or an AI-generated admin panel.

### 1.1 Non-negotiable outcomes

1. Create, open, edit, autosave, recover, and explicitly save a native Framewise document.
2. Create multiple named scenes/artboards with independently configurable dimensions, frame rates, backgrounds, and timelines.
3. Import common SVG artwork securely, retaining supported vectors, groups, useful names, fills, strokes, clip paths, gradients, and transforms.
4. Create and modify vector geometry, text, images, named hierarchical groups, symbols, clip masks, and editable layers.
5. Keyframe supported properties independently on any eligible element, with a consistent animation engine across editor playback, preview, still export, and render export.
6. Edit easing visually; support loops, timing, delays, stagger, reverse playback, and motion paths without making core state depend on animation libraries.
7. Offer accurate document/canvas interaction: selecting, moving, transforming, snapping, path editing, grouping, locking, hiding, ordering, and multi-selection.
8. Provide functional undo/redo, clipboard operations, project persistence, export diagnostics, and informative errors.
9. Produce valid outputs. Never silently substitute a static SVG or a simplified animation when the chosen target cannot represent the project faithfully.
10. Meet accessibility, security, test coverage, error-recovery, and reasonable performance requirements described here.

### 1.2 Important scope boundaries

- Framewise edits **2D SVG-oriented content**, not 3D scenes, CAD objects, or raster illustration brushes.
- A single scene is the unit of playback/export. Documents may contain many scenes. Batch export may render several scenes independently.
- There is no mandatory authentication, cloud workspace, server database, hosted collaboration, or paid service.
- A JavaScript runtime is allowed for operations that cannot be represented as portable animated SVG or CSS. Such exports are explicitly labelled **HTML + Framewise Player**, not mislabelled as pure SVG.
- Existing arbitrary SVG can contain features that cannot be mapped to editable objects. Import must provide a compatibility report and safe fallback choices; it must not pretend perfect round-trip fidelity.
- Lottie/dotLottie are interoperability formats, not the Framewise source format. Support is capability-gated and must never claim total compatibility.
- Audio timeline editing and audio/video compositing are excluded. Video formats can be **render outputs** of vector scenes, not editable video tracks.

---

## 2. Target users and example workflows

| User | Primary need | Successful outcome |
|---|---|---|
| Web developer | Animate an icon, loader, illustration, or logo | Clean self-contained SVG/CSS or embeddable HTML animation |
| Motion designer | Manipulate layered artwork with a precise timeline | Controlled keyframe animation and high-quality rendering |
| UI designer | Produce micro-interactions | Reusable symbols and editable animations for prototypes/products |
| OSS contributor | Extend an open source creative app | Well-defined Elm domains, adapters, formats, and test fixtures |
| Educator/student | Learn timing, interpolation, and vector motion | No-login browser tool, examples, inspectable source and outputs |

Representative end-to-end workflows:

**Animated icon:** New 128×128 transparent scene -> draw or import vector -> rename layers -> set pivot -> keyframe rotation and opacity -> adjust easing -> loop -> export self-contained SVG -> test in Chrome, Firefox, and Safari.

**Logo reveal:** Import multilayer SVG -> inspect unsupported import features -> reorganize groups -> animate stroke dash offset, masks, transforms and opacity -> preview continuously -> export HTML player or compatible animated SVG.

**Product illustration:** Compose multi-layer vector art across scenes -> create symbols -> animate transforms, paths, gradients and text as supported -> reuse symbol with timing offsets -> render PNG frames and WebM where supported.

**Recovery:** Create/edit scene -> automatic local recovery checkpoint -> browser tab closes unexpectedly -> reopen Framewise -> recover the latest coherent autosave -> inspect unsaved changes -> Save As.

---

## 3. Product architecture principles

1. **Elm owns application meaning.** Document contents, editor tool mode, current scene, selections, history, inspector state, active tracks, keyframes, validation, playback intent, and UI state are Elm models updated through explicit messages.
2. **Pure animation evaluator.** A pure evaluator computes a rendered scene at a specified frame/time from the document. Playback, frame seeking, exports, and thumbnails use the same semantics.
3. **Strict adapter boundary.** TypeScript performs DOM APIs, IndexedDB, ZIP parsing/creation, font loading, file pickers, geometry operations requiring mature libraries, high-performance rasterisation, encoding, and narrowly defined platform functions. TypeScript does not maintain a second authoritative scene model.
4. **Data before pixels.** Documents record semantic shapes, animation tracks, assets, and transforms, never a screenshot masquerading as editable source.
5. **Deterministic output.** Identical document and frame input yield identical scene property values regardless of UI playback history. Avoid timing accumulation drift.
6. **Everything reversible.** Destructive actions have undo history and, when appropriate, explicit user confirmation.
7. **No silent loss.** Unknown SVG or format features are reported. Unsupported exports cannot pass as complete.
8. **Local-first.** Browser storage and native files are the core workflow. A static web host is sufficient for deployment.
9. **Accessible by construction.** Menus, dialogs, property editors, layer trees and timeline controls have keyboard equivalents and visible focus.
10. **Preserve a clean dependency boundary.** Avoid large, unmaintained libraries or accidental reliance on proprietary services. Pin versions and document licences.

---

## 4. Supported environments

### 4.1 Platforms

- Current stable Chrome, Edge, Firefox, and Safari on Windows, macOS, and Linux.
- Primary editor targets desktop/laptop with pointer and keyboard, minimum usable viewport approximately 1100×700 CSS pixels.
- Tablet browsers: preview and basic document navigation; editing is capability-responsive. Do not make promises about parity for precision Bézier editing without a hardware keyboard/pointer.
- Phone browsers: welcome/open, project library, and responsive preview with download/export where possible; a clear Open on desktop notice for advanced editing.
- PWA installation from supporting browsers. PWA must not be required for the regular web app.
- Offline repeat access after successful asset caching, except features explicitly requiring a missing browser capability. All core editing, import, persistence, and SVG export must be usable offline.

### 4.2 Capability detection

Detect actual browser capabilities on startup and again before using them. Never infer support from user-agent strings alone. Maintain `CapabilityReport` for:

- Native open/save file pickers.
- File and drag-and-drop APIs.
- Clipboard read/write and permissions.
- IndexedDB availability and quota status.
- `ResizeObserver`, `DOMMatrix`, Pointer Events and pointer capture.
- FontFace loading.
- Web Workers and OffscreenCanvas.
- ImageBitmap and rasterisation capabilities.
- WebCodecs encoders and codec-specific `isConfigSupported` results.
- MediaRecorder support, if used as a fallback (never treated as inherently deterministic).
- WebAssembly/optional encoders.
- Preferred reduced motion and color scheme.

**Native picker policy:** `showSaveFilePicker` and `showOpenFilePicker` are progressive enhancements, not essential dependencies. Always support `<input type="file">`, Blob-based downloads, and ZIP document import. Treat download-based Save as an explicit file creation, not proof that an existing file was overwritten.

---

## 5. Visual language and responsive shell

### 5.1 Identity

Framewise should feel like a purpose-built creative desktop tool:

- Neutral graphite and warm grey surfaces with excellent contrast; optional light theme.
- A single restrained accent, suggested electric violet or blue, for selection and active controls, with accessible contrast.
- Functional spacing and crisp borders, modest 6-8px corner radii. Do not overuse oversized cards, glows, gradients, charts, or decorative imagery.
- Use tabular numerals in timeline rulers, measurement fields, and time readouts.
- Use a consistent 4px spacing scale and 14px base UI typography; tooltips and labels must remain readable.
- Icons should come from one coherent open-source family, verified for redistributable licensing. Every icon-only control needs an accessible name and tooltip.
- Animation preview should never induce unnecessary UI movement. Respect reduced-motion preferences for app chrome.

### 5.2 Main editor geometry

Desktop editor layout:

```text
┌────────────────────────────────────────────────────────────────────────────────┐
│ App/menu bar: Framewise | File Edit View Insert Object Layer Animate Window Help│
├────────────────────────────────────────────────────────────────────────────────┤
│ Document tab(s) / project name / save state     Preview   Share?   Export      │
├───────┬────────────────┬─────────────────────────────────────┬─────────────────┤
│ Tools │ Layers / Assets│            SVG canvas               │ Inspector        │
│ rail  │ / Library      │      artboard(s), guides, grid      │ Context tabs     │
│       │                │                                     │                 │
│       │                │                                     │                 │
├───────┴────────────────┴─────────────────────────────────────┴─────────────────┤
│ Timeline header | scene | transport | current frame | fps | duration | zoom    │
├────────────────────────────────────────────────────────────────────────────────┤
│ track list / property rows    | ruler | keyframes | playhead | selections      │
├────────────────────────────────────────────────────────────────────────────────┤
│ Status | tool hint | selected item | x/y | zoom | snapping | errors / warnings│
└────────────────────────────────────────────────────────────────────────────────┘
```

Recommended initial dimensions, all adjustable: top chrome 38-48px each band, tool rail 52px, left panel 260px, right inspector 310px, timeline 250px, status bar 26px. Canvas takes remaining space. Left/right panels collapse and resize independently. Timeline height is draggable and may be maximised. Maintain persisted workspace layouts per browser profile, separate from project files unless explicitly exported as a layout preset.

### 5.3 Workspace behaviours

- Viewport zoom: fit scene, fit selection, 100%, custom 10%-3200% with pointer-centric zoom. Do not couple zoom to artboard dimensions.
- Pan: Space+drag or middle mouse button; trackpad panning/zoom according to predictable platform conventions. Canvas wheel interaction must not unexpectedly scroll the document page.
- Pixel preview, antialiasing preference, checkerboard transparency, scene clipping, guides, grid, safe area and rulers.
- Drag-and-drop panel separators with double-click reset; persist panel state.
- Tab bar for several open documents; each tab indicates dirty/autosave/exporting state and keeps independent view state.
- Colour theme: system/light/dark; density: comfortable/compact; reduced motion override.
- Screen layouts at narrow widths must prioritise canvas and collapse panels into drawers. Never cut off Save or Preview.

---

## 6. Information architecture: every application surface

Every named screen, menu item, dialog and major interaction below must be implemented and wired. Do not leave non-functional decorative controls.

### 6.1 Welcome / project hub (`/`)

Elements:

- Framewise branding, New Document, Open File, Recent Projects, Recover Unsaved Work, Examples, Keyboard Shortcuts, Documentation and Settings.
- Cards/list for recent local project metadata: thumbnail, name, dimensions, modified timestamp, local autosave presence, and Open/Remove from Recents.
- Preset picker with search and categories: icon 24/32/48/64/128, logo square, illustration 1080×1080, banner 1920×1080, custom.
- New document form: title, initial scene name, width, height, units (`px`), fps preset/custom rational rate, scene duration (frames or timecode), canvas background, transparent export default, colour profile sRGB.
- Last session recovery banner and clear distinction between recent metadata and actual browser-stored files.
- Examples stored locally with application assets: bouncing ball, loading spinner, logo reveal, morph sample, illustrated scene, motion-path demo. Examples are copied into new editable documents, never overwritten.
- Help links: local quick-start docs and version/changelog, external repository link as an optional navigation.

Flows:

- New -> validate inputs -> create document with one scene -> navigate editor -> focus canvas.
- Open -> OS picker or fallback input -> parse/validate/migrate -> workspace tab -> error report if needed.
- Recent -> load durable IndexedDB document snapshot or request linked external file permission; missing file triggers locate/recover, not a blank editor.
- Recovery -> restore a separate recovered document (never silently overwrite a user's last explicitly saved file).

### 6.2 Document editor (`/editor/:localDocumentId`)

Sections: menus, document tabs, tool rail, layers/assets pane, center scene canvas, property inspector, animation timeline, bottom status bar. Routes identify browser-local entries only. Native file identities and persistent database keys must not be exposed as trusted URLs.

Selecting a scene updates canvas, layers, inspector, timeline, scene settings, current frame and export selection together. Switching scenes preserves each scene's last viewport and timeline position locally. Selection and live drag preview must not mutate unrelated scenes.

### 6.3 Full-screen preview (`/preview/:localDocumentId/:sceneId` or overlay)

- Clean stage, scene name, play/pause, restart, loop toggle, playback speed, scrubber, frame/time indicator, background override, fit/actual size and full-screen.
- Can preview a chosen scene without editor overlays or selection handles.
- Uses the same pure evaluator and render pipeline as editor at the same fractional frame.
- Enables a shareable **locally generated export file**, not a broken cloud URL. There is no public sharing service.
- Escape closes preview and restores editor state. Reduced motion may default to paused, but explicit Play works.

### 6.4 Asset manager (left panel tab and expanded modal)

- **Document Assets:** imported raster images, vector imports, embedded fonts or font metadata, palettes, gradients, reusable symbols, and imported reference assets.
- Search by name/type, grid/list display, filters, asset metadata, rename, replace, duplicate, delete, find usages, export asset and relink missing asset.
- Drag assets onto artboard creates a new node or symbol instance; never merely draws a bitmap of an SVG if its content was imported as editable artwork.
- Deleting in-use assets presents replace, detach, or cancel. Stored binaries use content hashes for deduplication.
- **Symbols:** create from selection, insert instance, edit master, detach instance, inspect overrides, propagate master changes, detect recursion.
- **Colour styles:** named solid colours and gradients with live usage counts, rename and propagate changes.

### 6.5 Export studio (modal or `/export/:documentId`)

Left: selected scene(s), presets and output target. Center: live result preview and compatibility warnings. Right: target-specific settings. Bottom: export job queue/progress, Cancel, Export, and Open/Download Result.

- Explicit asset selection (current scene, selected scene(s), all scenes, selected node/group, still frame).
- Outputs described in section 20.
- Live report of exact, baked approximation, unsupported, and omitted features per target, with links to affected layers/tracks.
- Resolution, background, frame range, FPS, scale, loop mode, quality, frame naming, transparent output, output naming, and metadata choices as applicable.
- Result sizes estimated using output-aware methods; do not claim exact sizes before encoding.
- Export settings persist per document and optionally as user-level named presets.

### 6.6 Preferences

Tabs:

- **General:** theme, language (English UI base), density, opening behaviour, recent file limit, autosave settings, confirmations.
- **Canvas:** grid spacing/subdivisions, guides, checker colours, default zoom, ruler units, selection bounds, handle size.
- **Animation:** default FPS, default scene duration, default easing, auto-keyframe policy, playback loop preference, onion skin defaults.
- **Performance:** hardware acceleration toggle where applicable, image cache size, render quality while scrubbing, worker count bounds, thumbnail cache clearing.
- **Shortcuts:** searchable shortcut reference, export/import keymap, remap supported actions, reset conflicting bindings.
- **Privacy & Storage:** local project usage, cache size, storage estimate/persistence, download all recovery data, clear individual data types, reset application state with confirmation.
- **About:** version, licence, notices, contributor links and diagnostics export (no user artwork without explicit choice).

### 6.7 Recovery manager

- Show document name, source, last explicit save, latest autosave, checkpoint timestamp, possible conflict, recovery size.
- Preview safe thumbnail. Actions: Open Recovery Copy, Compare Metadata, Download Backup, Discard Recovery (confirm).
- If schema cannot be parsed, preserve raw bytes and offer download of the corrupt snapshot. Never discard data just because decoding failed.

### 6.8 Documentation and help

- Built-in searchable Getting Started, Editor Concepts, Keyboard Shortcuts, SVG Import Notes, Export Compatibility, Troubleshooting, Accessibility and File Format documentation.
- Link contextual help icons in inspector controls to specific local pages or anchors.
- A What's New view reads bundled release notes, never remote content required for startup.

### 6.9 Universal command palette

- Open with Ctrl/Cmd+K, search across application commands, scenes, layers, symbols, shortcuts and docs.
- Results show category, label, shortcut, reason unavailable and the action on selection.
- Keyboard navigation, fuzzy matching, recent commands and Escape close.
- Commands are registered once with unique IDs and reused by menus, palette, context menus and shortcuts.

---

## 7. Complete menu and command map

Every command is registered in a central `CommandRegistry` with stable ID, title, shortcut, enablement predicate, optional confirmation and Elm message. Menus must disable invalid operations and explain the reason in a tooltip. On macOS display Cmd; on Windows/Linux display Ctrl for primary modifier.

### 7.1 File

| Command | Behaviour |
|---|---|
| New Document | Open preset/custom document dialog |
| New Scene | Add scene using selected preset or current scene dimensions |
| Open | Native picker or file input |
| Open Recent | Locally known projects and unavailable-file handling |
| Import SVG | SVG import with sanitisation and compatibility review |
| Import Image | PNG, JPEG, WebP asset import with dimension/size validation |
| Import Native Project | Same parser as Open, with option to merge scenes/assets |
| Save | Write existing writable native file handle when valid; otherwise prompt Save As/download |
| Save As | New native `.framewise` file/download; mark that revision explicitly saved only after success |
| Save Copy | Write snapshot without changing active document identity or dirty state |
| Revert to Saved | Compare and confirm, then restore last explicitly saved revision |
| Recover Unsaved | Open recovery manager |
| Document Settings | Document name, metadata, defaults, colour settings |
| Scene Settings | Dimensions, FPS, duration, background, loop, guides |
| Export | Open Export Studio |
| Quick Export | Repeat validated last used preset with current selection |
| Close Document | Prompt if unsaved and recovery unavailable; preserve tabs correctly |
| Close All | Respect independent dirty state and ask once per necessary action |

### 7.2 Edit

Undo; Redo; Cut; Copy; Paste; Paste in Place; Paste Style; Copy Style; Duplicate; Delete; Select All; Deselect; Invert Selection; Find Layer; Rename; Preferences; Keyboard Shortcuts. Clipboard supports native private Framewise JSON where permissions allow, plus image/SVG/text fallbacks. Always tolerate clipboard permission denial.

### 7.3 View

Zoom In/Out; Actual Size; Fit Scene; Fit Selection; Center View; Toggle Rulers; Grid; Guides; Snap to Grid; Snap to Guides; Snap to Objects; Pixel Preview; Outline Mode; Wireframe/Bounds Mode; Onion Skin; Show Animated Bounds; Show Motion Paths; Checkerboard; Show/Hide Panels; Reset Workspace; Full Screen Preview.

### 7.4 Insert

Rectangle; Ellipse; Rounded Rectangle; Line; Pen Path; Freeform Polygon; Star; Text; Image; Group; Clip Group; Symbol Instance; Guide Horizontal/Vertical; Scene; Default Keyframe; Motion Path.

### 7.5 Object

Transform; Align; Distribute; Arrange; Rotate/Flip; Set Pivot; Reset Transform; Convert to Path; Join/Split Paths; Close/Open Path; Reverse Path Direction; Boolean Union/Subtract/Intersect/Exclude; Outline Stroke; Simplify Path; Flatten Transform; Clip to Shape; Release Clip; Create Symbol; Detach Symbol; Group/Ungroup; Make/Release Compound Path. Commands that fundamentally alter editable geometry must show a short operation description when content will be converted.

### 7.6 Layer

Rename; Duplicate; Move Up/Down; Bring to Front/Back; Group/Ungroup; Lock/Unlock; Hide/Show; Isolate Selection; Collapse/Expand Tree; Select Parent/Children; Highlight Animated; Reveal on Canvas; Copy/Paste Layer Style; Convert to Symbol; Export Selected Layer.

### 7.7 Animate

Add Keyframe; Remove Keyframe; Auto-Keyframe toggle; Toggle Animation for Property; Copy/Paste Keyframes; Reverse Selection; Shift Keyframes; Scale Keyframes; Distribute Keyframes; Hold/Linear/Ease In/Ease Out/Ease In Out; Edit Curve; Apply Easing Preset; Set Loop Range; Clear Loop Range; Trim Animation; Create Motion Path; Follow Tangent; Toggle Onion Skin; Toggle Ghost Paths; Bake Expression/Unsupported Easing to Samples; Reset Playhead; Set Playback Speed; Preview.

### 7.8 Window

Show/Hide Layers, Assets, Inspector, Timeline, History, Export Queue and Library; Timeline Focus; Canvas Focus; Save Layout Preset; Reset Layout.

### 7.9 Help

Getting Started; Learn Framewise; Export Compatibility; Troubleshooting; Shortcut Reference; Report Bug; Contribute; Open Source Licences; About Framewise.

### 7.10 Context menus

Context menus depend on canvas empty space, single node, multi-selection, Bézier handle, timeline keyframe, track header, layer row, asset tile, artboard, and a tab. Context menus share command IDs with main menus and never expose actions impossible for that target.

---

## 8. Toolbar and selection model

### 8.1 Tools

| Tool | Canvas behaviour | Shortcut suggestion |
|---|---|---|
| Select | Select, drag, resize, rotate, multi-select | V |
| Direct Select | Select/edit path anchors and handles | A |
| Hand | Pan viewport, temporary with Space | H |
| Zoom | Click zoom, Alt-click zoom out, marquee zoom | Z |
| Pen | Construct/edit lines and cubic Bézier segments | P |
| Rectangle | Create shape, Shift locks square | R |
| Ellipse | Create ellipse, Shift locks circle | O |
| Rounded Rectangle | Rectangle with corner controls | U |
| Line | Straight/polyline creation | L |
| Polygon/Star | Adjustable sides, radius and inset | tool flyout |
| Text | Place and edit text | T |
| Image | Import/place supported raster | I |
| Motion Path | Define path for selected node animation | M |
| Eyedropper | Sample rendered colour | tool flyout |
| Pivot | Move local transform origin | tool flyout |

A tool's interaction is a finite-state machine: idle, hovered, pointer-down pending threshold, dragging, editing handles, committing, cancelling. Keyboard Escape cancels the current gesture without altering document history. Pointer capture is used so drags continue outside the viewport. Gesture start records the original values; pointer move updates a **transient preview**, and pointer up commits one history command.

### 8.2 Selection semantics

- Click selects topmost unlocked visible node, unless isolated or group-edit mode modifies hit testing.
- Shift-click toggles membership; box selection uses a configurable intersect/contain policy.
- Click through with modifier cycles overlapping nodes. Clicking a group selects the group by default, with double-click to enter group isolation.
- Selected node IDs are stable and ordered; inspector shows shared values or Mixed for multi-selection.
- Selection after delete follows nearest surviving sibling/parent rather than stale ID.
- Locked nodes cannot be selected from canvas by default; they remain addressable from layer panel for unlocking.
- Hidden nodes are not hit-tested. Nodes with zero effective opacity may remain selectable via layer panel.
- Selection bounding boxes calculate effective transformed geometry. Rotated handles act in local transform space; shared multi-select handles apply around the group selection pivot.

### 8.3 Transform, snapping, guides

- Move, rotate, scale, skew, resize as applicable, pivot and flip.
- Inspector fields provide X, Y, W, H, rotation, scale X/Y, skew, pivot X/Y and constrain proportions.
- Define origin in parent-local coordinates and a 3×3 affine transform internally; preserve edit-friendly decomposed representation and handle singular matrices safely.
- Snap priority configurable: guides, grid, artboard edges/center, anchor points, object edges and centers. Display snap candidates and temporary measurement guides.
- Snapping tolerance is measured in screen pixels so it feels consistent across zoom levels.
- Shift constrains axis or angle; Alt/Option transforms around center or duplicates when moving per established tool conventions. Tooltips explain active modifiers.
- Nudge by one canvas unit, large nudge by 10 units (configurable); each key press coalesces suitably for history.
- Align/distribute across selection relative to selection bounds or artboard. For one object alignment refers to artboard.

### 8.4 Path editing

- Support SVG `M`, `L`, `H`, `V`, `C`, `S`, `Q`, `T`, `A`, `Z` import, normalized into an internal editable cubic/line segment representation with appropriate conversion and fidelity diagnostics.
- Direct selection exposes anchor/handle pairs, smooth/corner/cusp mode, handle mirroring, anchor insertion/removal, split/close, join, reverse, simplify, and numerical editing.
- Curve manipulation uses local-to-world matrices; do not edit displayed path data without mapping positions back to local coordinates.
- Path boolean operations invoke a tested geometry adapter with numeric-tolerance policy; show status while calculating; preserve original nodes in undo. Fail gracefully with a diagnostic rather than writing malformed paths.
- Stroke expands non-destructively where possible. Outline Stroke creates a new editable filled path only after explicit conversion.
- Support open paths, compound paths, winding rules, stroke line caps/joins, dash patterns and dash offset.

---

## 9. Layers, groups, assets and symbols

### 9.1 Layer panel

- Hierarchical tree with drag reorder, nesting, indentation, disclosure arrows, layer type icon, editable name, visibility eye, lock, warning badge, animated indicator, and optional colour tag.
- Filter/search by name, type, animation status, missing asset or warning.
- Multi-select rows with Ctrl/Cmd and Shift. Keyboard arrows move selection; left/right collapse/expand; Space toggles preview selection only when focus semantics allow.
- Drag node into group, out to parent, or reorder siblings; prohibit cyclic nesting and dropping onto locked groups.
- Reorder changes SVG paint order and is undoable.
- Group transforms and opacity apply to children. Isolation mode scopes canvas editing and breadcrumb navigation.
- Root scene nodes do not include artboards as draggable children; scene selection and management are separate.

### 9.2 Node kinds

Supported authorable nodes:

- Rectangle, rounded rectangle, ellipse/circle, line, polygon/star, editable path, compound path.
- Text run (font family, size, weight, style, letter spacing, line height where supported, alignment, baseline and fill/stroke).
- Raster image, with linked document asset, cropping and preserve-aspect settings.
- Group, clipping group and symbol instance.
- A vector import should become these semantic nodes when possible.

Every node has `id`, user-editable `name`, `kind`, parent ID (or tree nesting), locked/hidden state, transform, compositing, fill/stroke/effects, and optional per-node metadata. Names need not be unique, but IDs must be.

### 9.3 Symbols

- A symbol definition contains a self-contained hierarchy, local coordinate system and supported animated tracks.
- A symbol instance has its own transform, opacity, playback offset, speed and looping settings; may override named style tokens and explicitly exposed properties.
- Editing master updates instances while maintaining compatible overrides.
- Detach produces real nodes/tracks with newly allocated IDs and resolved style values.
- Symbols cannot recursively reference themselves directly or transitively; validate graph on import and edit.
- When exporting flat SVG, expand instances with stable namespaced IDs unless safe `<use>` reuse retains exact output semantics.

### 9.4 Asset lifecycle

- Imported binary assets are stored under content-hash identifiers; document nodes reference assets, not data URLs in Elm model.
- Support PNG/JPEG/WebP imports; SVG is imported as editable document geometry by default, optionally as safe vector asset where semantics permit.
- Preserve file names and attribution/license metadata entered by users; never invent licensing for imported material.
- Fonts rely on local/browser fonts unless safely embedded with explicit user permission. The export report warns when text may reflow due to missing font.
- Replacing an asset retains placements and transforms; changing dimensions preserves object bounding box until explicitly reflowed.

---

## 10. Canvas rendering engine

### 10.1 Canonical coordinate model

- One user document unit is one SVG user-space unit, displayed as px by default.
- Each scene has `(width, height)` and an independent `viewBox` initially `[0,0,width,height]`.
- Every node stores a local geometry description and affine transform relative to parent.
- Scene/world transform is composition of parent transforms; viewport transform is a separate pan/zoom matrix.
- All hit testing, guides, snaps, rulers, drag deltas and anchor editing must consistently convert among pointer CSS pixel coordinates, scene coordinates and node-local coordinates.
- Node transforms are always numeric data in the native file, not an opaque CSS string.
- Preserve fractional coordinates and avoid per-edit rounding; round only for display and bounded export precision.

### 10.2 Render layers

1. Application background and optional checkerboard (HTML/CSS).
2. Scene drop shadow/scene bounds (editor only).
3. SVG scene artwork as a scene subtree (actual export-relevant rendering).
4. SVG overlay for selection outlines, anchor controls, motion paths, guides and snapping highlights (editor only).
5. Optional HTML overlay for rulers, mouse coordinates and inline text editing widgets.

**Do not export editor overlays.** Use stable, deterministic DOM/SVG identifiers namespaced by document/scene to avoid `defs` collision. Keep `<defs>` separate from rendered artwork. Render selection outlines in scene coordinates with screen-sized handles computed from zoom. Namespaced selectors must not leak into other editors/previews in the same page.

### 10.3 Styles and paint

- Solid colour fill and stroke with alpha, `none`, named shared colour styles, linear and radial gradients with colour stops, spread and geometry.
- Stroke width, cap, join, miter limit, dash array and dash offset; fill rule and stroke alignment caveats explicit.
- Opacity per shape and group; common SVG blend modes and filters only where consistently supported.
- Supported first-party effects: drop shadow and Gaussian blur. Unsupported SVG filters are either safely handled as read-only rasterized approximations after user approval, or rejected with an explicit reason.
- Clip paths and masks are supported as distinct operations. A clipping group is not the same as a destructive path subtraction.
- Default colour interpolation is sRGB in a defined interpolation space; document colour values stored as RGBA with explicit alpha. Avoid ambiguous CSS parser output.

### 10.4 Text and fonts

- Inline text editing, selectable text nodes, font family, weight, size, alignment, letter spacing, line height in multiline mode, fill/stroke and transform.
- Measure DOM-rendered text through a geometry bridge; avoid guessing text widths in Elm.
- Use a defined font fallback list. Alert users if requested fonts are not resolved.
- Preserve text editability in native format; export as `<text>` with documented font dependencies, or Convert Text to Paths where a font-to-outline adapter is available and licensed for the font in question.
- Do not claim exact text layout across all platforms or embed proprietary fonts without permission.

### 10.5 Image display

- Decode asynchronously; store intrinsic dimensions; show loading/error placeholders.
- Safe blob/ObjectURL lifecycle managed by adapter, revoked when no longer referenced.
- Images may be transformed, clipped and animated via node property tracks.
- Cross-origin remote fetching is not implicit. File imports are user-mediated; export warns about missing/inaccessible assets.

---

## 11. Scene and artboard management

Scene sidebar/list or scene switcher includes thumbnail, name, dimensions, FPS, duration and status. User can:

- Create/duplicate/rename/delete/reorder scene.
- Set background (transparent, solid), width/height, independent viewBox, frame rate and duration.
- Resize scene with choose-between scale-content, keep-content-positions or anchor-driven reflow.
- Change FPS preserving **timing in seconds** or preserving **frame indices**, with explicit preview of resulting keyframe positions.
- Trim/extend scene duration with choice to retain or discard out-of-range keyframes. Retained out-of-range keys are hidden from regular playback but remain editable after duration restoration; report them in diagnostics.
- Set preview looping: none, finite count, infinite, ping-pong. Exports translate this per target.
- Set scene-internal frame labels and named markers; navigate via marker list.
- Configure a work range for playback/export independent of full scene duration.
- Duplicate scene with shared asset references but unique scene/node/track IDs where required.

Scenes are independent compositions, not pages that play continuously as one video unless the user chooses the explicit **Sequence Scenes** export option. Such a sequence concatenates rendered scenes with deterministic timings and no implicit transitions. It never changes source scene structure.

---

## 12. Timeline: layout and editing behaviour

### 12.1 Structure

Timeline upper band:

- Scene selector, play/pause, jump first/last frame, previous/next frame, previous/next keyframe, loop, auto-keyframe, playback speed, frame/timecode field, FPS badge, duration, onion-skin toggle, snap toggle, zoom/fit timeline.

Timeline content:

- Left fixed-width track list aligned with ruler rows; right horizontally scrollable time region.
- Scene ruler, loop range handles, named markers, playhead and current frame stripe.
- Rows nested by node, animated property and optional channel. Colour/shape differentiation of keys by interpolation type.
- Expand/collapse node property groups; show animated-only/all-properties mode.
- Track mute/solo/lock, visibility, overflow marker and per-track value at playhead.
- Multi-keyframe marquee, shift selection, clipboard operations and dragging with live delta readout.
- Resize left track list, adjust row height/density, vertical/horizontal timeline zoom, fit selected keys, scroll to playhead.

### 12.2 Time model

- **Canonical keyframe position is an integer frame index**, starting at frame 0.
- FPS is a positive rational number `{ numerator, denominator }`, so rates such as 30000/1001 are representable.
- Scene `durationFrames` is the number of rendered intervals; a 60-frame 30-fps scene spans 2 seconds, with frame sample indices 0 through 59 for video export and a conceptual endpoint at frame 60 for loops and timeline editing.
- Keyframes may exist at frame `durationFrames` as endpoint keys. Endpoint semantics must be consistent for seamless loops.
- Preview playhead supports `continuousFrame : Float` for interpolated scrubbing/real-time playback. Discrete user-entered frame positions snap to integers unless subframe preview is enabled.
- Convert display time to frames by `timeSeconds * fpsNumerator / fpsDenominator`, derived from an absolute clock origin; never increment floating point time by a fixed delta for every frame.
- SMPTE-style timecode is derived from frames and documented for fractional rates. Do not claim drop-frame rules unless implemented and unit tested.
- Each scene's `fps`, `durationFrames` and frame range are independent.

### 12.3 Keyframe creation and modification

- Clicking a property diamond inserts a key at playhead using the evaluated current value, without causing a visual jump.
- Editing an animatable property at a nonzero frame with Auto-Keyframe on creates or updates that frame's key. With it off, explicit policy: edit base value where there are no keys; where keys exist, ask whether to edit nearest key or add key, or follow a user preference displayed in UI. Never silently mutate the wrong frame.
- First animated property track gets a frame-0 baseline key reflecting pre-animation appearance unless the user deliberately opts out.
- Delete property keyframe, all keys on track, all animation from node or whole scene with distinct commands.
- Copy/paste keys across compatible tracks with relative spacing and type checks; reject incompatible targets explicitly.
- Move keys horizontally, multi-drag, distribute evenly, reverse within selection, scale timing from an anchor, shift by frame delta, stretch work range and snap to keys/markers/playhead.
- A track cannot have more than one key at the same frame. Collisions resolve through explicit overwrite/merge preference, with undo.
- Out-of-range keys show warnings and remain recoverable unless deleted.
- Tracks with disabled animation use the base property value and do not discard keys.
- Keyframe interpolation is specified per outgoing segment. The final key has no outgoing segment unless looping connects it to frame-0 according to explicit loop rules.

### 12.4 Playback

- Play starts from current playhead and advances using `requestAnimationFrame` timestamps routed through a single clock adapter. `performance.now()` is not directly called from Elm.
- Pause preserves exact playhead; Stop returns to start of active work range, according to control label.
- Playback rate presets 0.25, 0.5, 1, 1.5, 2 with custom bounded value.
- Support forward/reverse, once, loop, finite repeats and ping-pong in preview. Define end-boundary behaviour with unit tests.
- Rendering should skip obsolete frames under load instead of letting playback clock lag; an optional frame-step quality mode is available for deterministic inspection.
- On browser tab hidden, pause or suspend animation clock and resume without elapsed-time burst according to preference.
- Respect system reduced-motion setting for autoplay defaults. Explicit user playback is permitted.

### 12.5 Onion skin

- Draw configurable preceding/following sampled frames as non-interactive ghosted geometry.
- Settings: frames before/after, tint, opacity falloff, show/hide during playback, limit to selected nodes or whole scene.
- Onion skins are editor-only and not exported. Cache sampled geometry and invalidate on source edits.

---

## 13. Animation property specification

Each animated property has a **typed property address**, valid value domain, interpolation mode, evaluator and output capability matrix.

| Property family | Properties | Default interpolation | Notes |
|---|---|---|---|
| Transform | Translation X/Y, scale X/Y, rotation, skew X/Y, pivot | Numeric / angle-aware | Specify shortest-path rotation versus continuous revolutions |
| Visibility/compositing | Opacity, visibility, clip reveal | Numeric / stepped | Visibility is discrete |
| Shape geometry | Rectangle dimensions/corners, ellipse radii, polygon radius/points where topology stable | Numeric | Validate positive bounds and shape-specific invariants |
| Paths | Path anchor/handle coordinates, path morph | Pointwise with validated topology | Complex morphs require path normalization/re-sampling |
| Paint | Fill RGBA, stroke RGBA, gradient stop colours/positions, gradient geometry | Colour/numeric | Discrete interpolation when incompatible paint type |
| Stroke | Width, dash offset, dash values where arity matches | Numeric | Nonnegative width, valid dash constraints |
| Effects | Blur radius, shadow offset/blur/opacity/colour | Numeric / colour | Browser/filter support warnings |
| Text | Font size, tracking, content swap, colour | Numeric/stepped | Text content is stepped, font family is discrete |
| Image | Opacity, crop bounds, transform | Numeric | Source asset switch is stepped |
| Motion | Path progress, auto orient rotation and normal offset | Arc-length/progress | See section 15 |
| Symbol instance | Local transform, style override, playback offset/rate | Typed | Nested time remapping is deterministic |

Properties not explicitly animatable remain statically editable. Inspector must visually distinguish animatable properties. All animations are non-destructive modifications of the evaluated scene: the base geometry/paint remains editable.

### 13.1 Typed values

Implement a property value union equivalent to:

```elm
type PropertyValue
    = Scalar Float
    | Angle Float
    | PointValue Vec2
    | SizeValue Vec2
    | ColorValue Rgba
    | BoolValue Bool
    | StringValue String
    | PathValue PathGeometry
    | GradientValue Gradient
    | NumberList (List Float)
    | DiscreteAsset AssetId
```

Use an explicit `PropertyPath` union rather than unvalidated free-form strings inside Elm. The on-disk representation has stable string codes mapped via a strict decoder. For example `transform.position`, `style.fill.color`, `shape.path.geometry`, `stroke.dashOffset`.

### 13.2 Value validation

- Numeric values must be finite (no NaN or Infinity) and within documented safe geometric ranges.
- Alpha clamped `[0,1]`; lengths and radii validated by field constraints; negative scale may be permitted to represent reflection.
- Interpolating colour must define alpha and gamma handling; implement tests with known samples, not CSS `color-mix` defaults.
- Interpolate angles with a selected mode: shortest arc, clockwise, counterclockwise or unbounded explicit revolutions. Normalize carefully without erasing intentional full turns.
- Discrete properties step at the defined key boundary; never interpolate arbitrary strings or asset IDs.
- Validation runs on command dispatch and file decode, with recoverable warnings where appropriate.

---

## 14. Easing, curves and animation semantics

### 14.1 Easing modes

- Hold/step start/step end.
- Linear.
- Presets: ease, ease-in, ease-out, ease-in-out, back-in/out, elastic-in/out, bounce-in/out with deterministic implementations.
- Cubic Bézier with editable handles `(x1,y1,x2,y2)` and constrained monotonic X control values, except explicitly advanced modes.
- Spring easing with mass, stiffness, damping and initial velocity, evaluated from a deterministic mathematical model or fixed-step numerical solver with a defined tolerance. Do not use a stateful per-frame integrator tied to render frequency.

### 14.2 Curve editor

- Graph preview, preset dropdown, control handles, numeric inputs, copy/paste curve, reverse, reset.
- Select single/multiple key segments; show mixed state where easing differs; modifying applies to compatible selected segments.
- Show progress interpolation against time and a moving preview marker.
- Cubic Bézier inversion solves X->t with Newton iterations plus bisection fallback, handles tangent degeneracy and returns stable values at 0 and 1.
- Spring/overshoot values may go outside `[0,1]`; clamp only properties requiring bounded domains, not the abstract easing function.
- Include optional per-property easing overrides when one key governs multiple channels; otherwise a track's outgoing segment controls its property.

### 14.3 Loop and boundary semantics

For a scene of `N` frames:

- Non-looping playback clamps playhead to endpoint at frame `N` then stops.
- Repeating playback maps continuous frame to range `[0,N)` using a mathematically correct modulo for negative/reverse time.
- Ping-pong maps cycles over `[0,N]` with mirrored progress; avoids repeated endpoint frame when exporting video.
- Hold behaviour after a track's last key is its final value unless a defined repeating track or symbol remapping says otherwise.
- Seamless looping is a user choice; tool can report a boundary discontinuity in animated properties and optionally copy initial values to an endpoint key.

### 14.4 Stagger and orchestration

- Multi-select nodes -> Stagger dialog: order (layer/selection/reverse/spatial), start frame, spacing, which properties/tracks, preserve offsets.
- Shift tracks in time without copying property values.
- Named markers and ranges serve navigation and export selection.
- Per-node animation offset is supported as an explicit remapping only for reusable symbol instances; regular scene tracks remain in scene time, avoiding hidden compounded offsets.

---

## 15. Motion paths and path morphing

### 15.1 Motion path authoring

- Select node -> Create Motion Path -> draw/edit independent named path, or link an existing vector path.
- Motion path is a dedicated asset/object with a stable ID, editable without altering the animated node's base vector geometry.
- Keyframe progress `0..1` along path, optional normal offset and orientation mode (fixed, tangent, tangent+offset).
- Compute arc-length approximations adaptively, cache lookup table keyed by path revision and tolerance. Progress maps to path distance, not raw cubic parameter.
- Show projected position, tangent arrow, start/end markers and current progress handle.
- Define behaviour for zero-length paths and cusps; avoid NaN orientation.
- Motion path coordinates are scene-local or explicitly parent-local; document conversion rules must be tested when reparenting nodes.

### 15.2 Morphing

- Compatible-path morphing interpolates corresponding points, including handles.
- Incompatible geometry presents **Prepare Morph**: convert supported primitives to paths, normalize commands, resample contours, align start points and winding directions, then preview matched contours.
- For multiple contours/holes, explicitly pair corresponding contours; automatic matching is advisory and must allow user correction.
- Preserve original source geometries for undo and optional non-destructive morph object state.
- If contour topology or shape matching cannot be made reliable, show a diagnostic and offer crossfade or an explicit raster/HTML output path, rather than pretending it is a true path morph.
- Morph evaluation stays independent of the canvas frame rate.
- Constrain data size to protect against adversarial/pathological imports and degenerate curves.

---

## 16. Native document format and schema

### 16.1 File envelope

`.framewise` is a ZIP archive containing UTF-8 JSON plus local binary assets:

```text
project.framewise
├── manifest.json
├── document.json
├── assets/
│   ├── sha256-<hash>.png
│   ├── sha256-<hash>.webp
│   └── sha256-<hash>.woff2          # only if license/user rights permit
├── thumbnails/
│   ├── scene-<id>.png
│   └── project.png
└── metadata/
    └── compatibility-report.json   # optional informational output
```

Do not require thumbnails or metadata for opening. Unknown optional entries may be skipped safely; never execute files from the archive. Binary assets must have manifest hashes/lengths and strict size constraints. All paths must be relative, normalized, and within the archive; reject `../`, absolute paths and duplicate conflicting entries.

Native format must be genuinely editable, separate from `.svg` export. The app also supports a human-readable **Save Snapshot as JSON** command, with embedded assets omitted or explicitly encoded/packaged; it must not claim to be a lossless interchange replacement for `.framewise`.

### 16.2 Manifest example

```json
{
  "format": "framewise",
  "schemaVersion": 1,
  "application": "Framewise",
  "generatorVersion": "0.1.0",
  "documentId": "doc_01J...",
  "createdAt": "2026-10-15T00:00:00Z",
  "modifiedAt": "2026-10-15T00:00:00Z",
  "documentPath": "document.json",
  "assets": [
    {
      "id": "asset_01J...",
      "path": "assets/sha256-abc.png",
      "mimeType": "image/png",
      "byteLength": 1024,
      "sha256": "<64-lowercase-hex-characters>"
    }
  ]
}
```

The example identifiers/hashes above are illustrative placeholders, not valid fixture data. Tests use valid fixture hashes. Generation of document IDs uses cryptographically random IDs through the JS bridge (`crypto.randomUUID` or equivalent), never `Math.random` for persistent identity.

### 16.3 Canonical document model

```text
Document
  id: DocumentId
  schemaVersion: Int
  metadata: { name, description, author?, createdAt, modifiedAt, tags[] }
  defaults: { background, fps, durationFrames, colourSpace }
  sceneOrder: SceneId[]
  scenes: Map<SceneId, Scene>
  assets: Map<AssetId, AssetMeta>
  symbols: Map<SymbolId, SymbolDefinition>
  colourStyles: Map<StyleId, StyleToken>
  exportPresets: ExportPreset[]

Scene
  id, name, width, height, viewBox, background
  fps: { numerator, denominator }
  durationFrames, playbackMode, markers[], workRange
  rootNodeIds: NodeId[]
  nodes: Map<NodeId, Node>
  tracks: Map<TrackId, AnimationTrack>
  motionPaths: Map<MotionPathId, MotionPath>
  guides: Guide[]

Node
  id, name, kind, parentId?, childIds[]
  hidden, locked, opacity, blendMode
  transform: { translation, scale, rotation, skew, pivot }
  geometry: NodeGeometry
  appearance: { fill, stroke, clipId?, maskId?, effects[] }
  metadata: { importedElementId?, notes?, userTags[] }

AnimationTrack
  id, target: { nodeId, propertyPath }
  enabled, locked, keyframes[]

Keyframe
  id, frame: Int, value: PropertyValue
  interpolation: { type, easingParams }

MotionPath
  id, name, geometry, coordinateSpace, revision
```

Represent root/child ordering once canonically. If both `parentId` and `childIds` are serialized for ergonomic access, decoder validates reciprocal consistency and provides a deterministic repair flow; editor mutations use one authoritative tree operation module.

Native data must distinguish document state from editor session state: selection, hover, open panel sizes, current cursor position, viewport pan/zoom, and clipboard are not part of exported artwork. If per-scene guide settings are saved with document, they are metadata rather than graphic nodes.

### 16.4 Node kind union

```elm
type NodeGeometry
    = Rectangle RectGeometry
    | Ellipse EllipseGeometry
    | Line LineGeometry
    | Polygon PolygonGeometry
    | Path PathGeometry
    | Text TextGeometry
    | RasterImage ImageGeometry
    | Group
    | ClippingGroup ClipGeometry
    | SymbolInstance SymbolInstanceGeometry
```

Provide strict decoders/encoders for every union branch. Encode versions for enum variants that could change. Unknown field policy: preserve harmless recognized extension fields in a namespaced metadata map; reject invalid required fields, unknown executable content and structural ambiguity. Importing a newer unsupported major schema opens a read-only notice with an option to download original, never silently downgrades it.

### 16.5 References and validation

On opening and before save/export validate:

- Unique IDs; valid parent/child edges; no hierarchy or symbol cycles.
- Existing node, symbol, asset, clip/mask, path and track references.
- Correct property value type for every track target.
- Sorted keyframes; no duplicate frames; legal duration/FPS.
- Finite transforms; nonnegative dimensions where required; bounded path complexity.
- Valid colour channels, gradient stops, raster metadata and MIME/hash matches.
- No orphan assets except deliberately retained for recovery, which should be prunable via Asset Cleanup.

Report errors with JSON pointers/object IDs and actionable recovery decisions.

### 16.6 Migrations and compatibility

- Schema upgrades are pure versioned transformations `vN -> vN+1`; include fixture tests for all supported prior schema versions.
- Parse -> validate envelope -> migrate -> decode -> validate graph -> preview; keep original bytes until successful completion.
- No direct mutation of source file during open/import.
- Increment schema version only for incompatible structure changes; record generator version separately.
- Native archive imports require zip-bomb, maximum-entry, path traversal and uncompressed-size defenses.

---

## 17. Elm application architecture

### 17.1 Application model

Use `Browser.application` if the editor uses in-app routes; use navigation key and URL parsing only for local views. A root Elm `Model` includes:

```elm
type alias Model =
    { route : Route
    , workspace : WorkspaceState
    , documents : Dict DocumentId OpenDocument
    , activeDocument : Maybe DocumentId
    , editor : EditorState
    , preferences : Preferences
    , persistence : PersistenceState
    , exports : ExportState
    , capabilities : Capabilities
    , notifications : List Notice
    }
```

`OpenDocument` carries canonical document, revision ID, last explicitly saved revision, last autosaved revision, history, validation errors, optional file-handle reference token and derived caches. File handle itself must stay in TS keyed by opaque token, not JSON-serialized into Elm.

### 17.2 Suggested modules

```text
src/
  Main.elm
  App/
    Model.elm
    Msg.elm
    Update.elm
    View.elm
    Router.elm
    Commands.elm
    Shortcuts.elm
    Preferences.elm
  Domain/
    Document.elm
    Scene.elm
    Node.elm
    Geometry.elm
    Path.elm
    Matrix.elm
    Paint.elm
    Assets.elm
    Symbols.elm
    Selection.elm
    Timeline.elm
    Track.elm
    Keyframe.elm
    Easing.elm
    Interpolation.elm
    MotionPath.elm
    Evaluate.elm
    History.elm
    Validation.elm
  DocumentIO/
    Encode.elm
    Decode.elm
    Migrate.elm
    Clipboard.elm
  Editor/
    Canvas.elm
    Tools.elm
    Gestures.elm
    Layers.elm
    Inspector.elm
    TimelineView.elm
    Preview.elm
    Commands.elm
  UI/
    Menus.elm
    Dialogs.elm
    Toast.elm
    Fields.elm
    Tree.elm
    Popup.elm
  Ports.elm
  Shared/Ids.elm
  Shared/Result.elm

web/
  main.ts
  adapters/
    bridge.ts
    protocol.ts
    files.ts
    archive.ts
    storage.ts
    svg-import.ts
    sanitise-svg.ts
    svg-export.ts
    geometry.ts
    raster.ts
    encoding.ts
    clipboard.ts
    fonts.ts
    capabilities.ts
    playback-clock.ts
    id.ts
  workers/
    import.worker.ts
    export.worker.ts
  styles/
    tokens.css
    shell.css
    canvas.css
    timeline.css
  service-worker.ts
```

Directory/module paths may change to obey Elm's actual module naming and build conventions; conceptual boundaries must remain intact.

### 17.3 Elm update discipline

- Use domain-specific `Msg` unions; do not centralize all state updates in a giant stringly typed dispatcher.
- A user action becomes an explicit domain command that either returns updated state + effects, or a structured error. Validation belongs beside the command.
- Pure domain functions must not use ports or depend on the DOM.
- Keep temporary pointer gesture state separate from committed domain state.
- Apply history only on committed user actions, not on animation ticks, hover, window resize, derived caches or streaming export progress.
- Long work is asynchronous with request IDs and cancellation. A stale worker response must not overwrite a newer revision.
- Derived presentation data may be memoized or cached in appropriate JS/Elm structures but remains invalidatable by document/scene revision.

### 17.4 Interop protocol

Use typed JSON envelopes with versioned operation names and explicit request/response matching:

```json
{
  "protocolVersion": 1,
  "requestId": "req_123",
  "documentId": "doc_123",
  "revision": 17,
  "operation": "archive.write",
  "payload": { "target": "download" }
}
```

Response:

```json
{
  "protocolVersion": 1,
  "requestId": "req_123",
  "operation": "archive.write",
  "status": "ok",
  "payload": { "filename": "my-animation.framewise", "bytes": 12451 }
}
```

Error response includes stable `code`, user-safe message, optional diagnostic detail and retryability. No arbitrary function names, selectors or scripts may be sent as operations. Large binary objects stay in JS stores and travel by opaque `assetId`/job handle; avoid serializing megabytes of base64 through Elm ports.

Bridge categories:

- `platform`: capabilities, time clock, random ID generation, device settings.
- `file`: open, write, download, drag/drop, permission status.
- `archive`: ZIP read/write, hashing, archive validation.
- `storage`: project CRUD, revisions, recovery, quota.
- `svgImport`: parse/sanitize/normalize and compatibility diagnostics.
- `geometry`: boolean paths, path measurement, complex morph preprocessing, text measurement.
- `render`: rasterise frame, batch frames, compose export output.
- `encode`: GIF/APNG/video where capability permits.
- `clipboard`: read/write.
- `fonts`: load/inspect.

A TypeScript schema validator must validate all messages at bridge ingress and the Elm decoder must validate all returned payloads. Do not assume ports are inherently trustworthy.

### 17.5 Build/tooling

- Elm compiler `0.19.3`, Vite, TypeScript strict mode and `vite-plugin-elm` (verify pinned compatible version in lockfile).
- Elm packages: `elm/browser`, `elm/core`, `elm/html`, `elm/svg`, `elm/json`, `elm/url`, `elm/file` where appropriate, `elm/time`, `elm/random` only where justified, plus `elm-explorations/test` for domain tests.
- Styling: CSS custom properties and scoped modular styles; Tailwind may be used sparingly for shell utility composition, not as a substitute for coherent design tokens. Avoid generating a giant CSS bundle.
- Use npm or pnpm consistently with a committed lockfile; pin important dependencies and enforce reproducible builds.
- Add type checking, Elm compilation, lint/format and tests to CI.

---

## 18. Import pipeline and SVG compatibility

### 18.1 Supported inputs

| Input | Treatment |
|---|---|
| `.framewise` | Strict native document load/validation/migration |
| `.svg` | Safe parse, normalize and convert to editable vector nodes |
| `.png`, `.jpeg`/`.jpg`, `.webp` | Image asset + raster node |
| `.json` Framewise snapshot | Supported only with validated native snapshot schema |
| `.gif`, `.apng`, `.mp4`, `.webm` | Not editable source formats; show a clear unsupported-import message |
| `.lottie`, `.tgs`, `.riv`, `.fig` | Not claim-supported without dedicated tested import adapters; show format help |

### 18.2 SVG security preprocessing

Treat every imported SVG as hostile input. Before it can enter the live DOM:

1. Validate MIME/extension and size; decode as UTF-8/XML with safe parser.
2. Reject DTD/entities and XML features that could expand or fetch external resources.
3. Sanitize SVG using strict allowlists and, where appropriate, a maintained sanitizer such as DOMPurify configured for SVG. Sanitization alone is not equivalent to semantic validation.
4. Reject executable elements/attributes: scripts, event handlers, `foreignObject`, remote/external `use`, unsafe styles, external stylesheets and resource fetches.
5. Resolve local fragment IDs within the sanitized document with cycle detection, depth limits, and size budgets.
6. Parse supported structure into typed intermediate representation. Never retain unsafe raw XML as an inert-looking editable node that might execute on export.
7. Normalize transforms, style inheritance, geometry, gradients, clip paths and local references.
8. Produce an import compatibility report before committing the import transaction.

Disallow `javascript:`, uncontrolled `data:` URLs, remote URLs, CSS imports, and URL-bearing attributes except validated local fragments. Avoid unsafe SVG `<image>` paths. The app must not upload imported SVGs to any service.

### 18.3 SVG feature handling matrix

| Feature | Import | Edit/round trip |
|---|---|---|
| Rect/circle/ellipse/line/polyline/polygon/path | Full where valid | Editable nodes |
| Groups and nested transforms | Full where valid | Editable hierarchy |
| IDs/names | Preserve as metadata, allocate stable Framewise IDs | Layer names editable |
| Solid fills/strokes | Full | Editable |
| Linear/radial gradients | Supported subset | Editable stops/geometry |
| Dashes, caps, joins, fill rules | Full supported subset | Editable |
| Text and `tspan` | Supported with limitations | Warn on layout/font differences |
| Safe clipping paths | Supported | Editable clipping group where possible |
| Masks | Defined supported subset | Preserve safely or report approximation |
| Basic Gaussian blur/drop shadow | Supported subset | Editable effects |
| Arbitrary SVG filters | Report unsupported | No silent preservation/execution |
| SMIL embedded animations | Report; optional conversion of simple numeric keys | Not losslessly imported by default |
| CSS/JS animations in source SVG | Strip/reject executable animation logic | No arbitrary code execution |
| `foreignObject`/scripts/external references | Reject/remove | Never executed |
| Symbols/use local references | Expand or convert to symbol instances with cycle checks | Warn if semantics change |
| Patterns/markers/custom paint servers | Report limitations | Only implement if safe typed support exists |

Import dialog lists counts by category, warnings, affected layer IDs, file safety actions and controls: Cancel, Import Supported, Expand Safe References, or Rasterize Unsupported Artwork. Rasterization is explicit and never presented as editable source vectors. If a source cannot be safely sanitized, reject with an explanatory error.

### 18.4 Import placement

- `Open SVG as New Document` creates scene sized from `viewBox` or width/height with documented unit conversion; offer sensible fallbacks if dimensions absent.
- `Import into Scene` adds groups as named nodes at center or preserving source coordinates, user selectable.
- Drag SVG onto canvas shows a ghost preview and drop location, same parsing path as Import.
- Multiple SVG files become named groups or independent scenes based on chosen option.
- Undo import as one transaction with asset reference cleanup.

---
## 19. Property inspector: exact controls and data flows

### 19.1 General behaviour

- Inspector changes with selection: **Nothing selected**, **Scene selected**, **Single node**, **Multiple nodes**, **Path anchors**, **Motion path**, **Timeline keyframe(s)**, **Symbol master/instance**, **Asset**, or **Export item**.
- Controls display real evaluated values at current frame, with a visible keyframe diamond for animatable values. A distinction must exist between base value and value at playhead.
- Every numerical field supports click-to-focus, keyboard input, arrow increment, Shift+arrow coarse adjustment, scrub-drag on label where practical, copy/paste of numbers and unit parsing.
- Show mixed values for multi-selection; editing applies the same target value or delta according to the control's documented semantics.
- Editing begins an undo transaction, previews changes while active and commits on Enter/blur; Escape restores the prior value.
- Reject invalid typed input without sending NaN/Infinity into domain state. Show inline errors and permitted ranges.
- Inspector sections are collapsible and keyboard navigable; expanded/collapsed state persists per inspector context.

### 19.2 Scene inspector

| Group | Controls | Behaviour |
|---|---|---|
| Identity | Name, description, scene tags | Rename immediately, undoable |
| Size | Width, height, lock ratio, viewBox | Validate dimensions; resize policy explicit |
| Background | Transparent/solid, colour picker | Scene preview background, optionally export |
| Timing | FPS preset/rational custom, duration frames/time, loop mode, work range | Update timeline, with retiming choices |
| View | Grid/guides/ruler visibility, snap defaults | Some values are session preferences, not document geometry |
| Accessibility | Scene title, description, reduced-motion fallback frame | Used in export metadata where supported |
| Metadata | ID (read-only), creation/modification info | Informational, no arbitrary file mutation |

### 19.3 Single node inspector

**Header:** type, editable name, parent breadcrumb, select parent, lock, visibility, duplicate, delete, warnings.

**Transform:** position X/Y, width/height where applicable, aspect lock, rotation, scale X/Y, skew X/Y, pivot X/Y, flip horizontal/vertical, Reset Transform.

**Geometry:** contextual fields: corner radius per corner; ellipse radius; line endpoints; polygon sides/inset; path anchor count and simplify tolerance; text contents/style; image crop and fit.

**Appearance:** fill enabled/type, solid/gradient selector, opacity, gradient stops, stroke enabled/type/width, line cap/join, dash, dash offset, fill rule, group blend mode, overall node opacity.

**Effects:** blur, shadow list, mask/clip reference, enable/reorder/delete effect, supported render target warnings.

**Animation:** property track summary, keyframe diamond per field, timing overview, motion path attachment, ease editor launch, visibility of muted tracks.

**Export:** layer name/ID in output, exclude from export toggle (explicit editor-only flag if implemented), compatibility warnings.

**Accessibility:** semantic title/description and decorative flag when node is exported with accessible metadata.

### 19.4 Multi-selection inspector

- Shared transform fields and relative delta operations.
- Batch rename with sequential suffix/token substitution, group, align/distribute, lock/visibility and common style application.
- Inspector lists Mixed rather than selecting an arbitrary object as source of truth.
- Editing the same animated property on several selected nodes creates a coordinated history transaction with independent tracks.
- Effects not shared across objects appear mixed/partial; do not accidentally delete an object's distinct effects by editing another.

### 19.5 Text inspector

Text, font family, fallback, font weight/style, font size, letter spacing, line spacing, alignment, baseline, line breaks, horizontal/vertical scale, decoration where supported, fill/stroke, conversion to outlines with licensing caveat. Font selector separates available system fonts from embedded user imports; missing font badges remain visible.

### 19.6 Symbol instance inspector

Master name/link, edit master, detach, reset overrides, per-instance style/property overrides, time offset, playback speed, instance loop mode and node transform. Show origin of each inherited property and a reset indicator for overridden fields.

### 19.7 Keyframe inspector

Frame index and displayed timecode, typed value, outgoing interpolation, Bézier handles or spring parameters, copy/paste easing, link to affected property, remove key, jump previous/next key. Multiple keyframes display relative shift and shared easing controls.

### 19.8 Colour picker

- Native Framewise picker, not an inconsistent collection of browser colour inputs.
- RGBA/hex/HSL entry with alpha checkerboard and visual sliders; gradient tab for stop creation/deletion/reposition.
- Recent colours, document named swatches, sample from canvas.
- Text display clearly distinguishes hex with/without alpha; conversion is tested.
- Confirm and cancel preserve transaction semantics. Escape must restore initial colour.

---

## 20. Export engine and format contracts

### 20.1 Fundamental export rule

**All export formats originate from one canonical evaluated scene, not separate ad hoc animations built by the UI.** Every exporter declares its capabilities and losses. Given the same scene and time, an image preview and a rendered frame must agree within documented pixel/colour tolerances.

The export pipeline is:

```text
Canonical Document + Scene Selection + Export Options
  -> validate and resolve assets/fonts/symbols
  -> analyse feature usage and target compatibility
  -> choose native animation, sampled/baked or unsupported mapping
  -> snapshot immutable revision for job
  -> compile target artefact(s)
  -> validate generated output
  -> user-visible preview/report/download
```

Running exports use an immutable captured document revision. Edits occurring after export starts do not silently change the job output. Export queue displays the revision and offers Re-export Latest.

### 20.2 Output compatibility matrix

Legend: **Native** means target expresses behaviour directly; **Bake** means converted to sampled frames or approximate keyframes with reported tolerance; **Limited** means only verified subset; **Not supported** means the export must warn/block or require switching format.

| Output | Static geometry | Transform/opacity | Fill/stroke animation | Morph | Complex filters | Transparent bg | Playback controls |
|---|---|---|---|---|---|---|---|
| Static SVG | Native at chosen frame | Evaluated still | Evaluated still | Evaluated still | Limited | Yes | No |
| Animated SVG (SMIL) | Native | Native supported subset | Native supported subset | Limited/Bake numeric path | Limited | Yes | Native loop semantics only |
| SVG + CSS | Native | Native supported subset | Limited | Not generally lossless | Limited | Yes | CSS animation only |
| HTML + JS player | Native | Native | Native supported subset via evaluator | Native supported | Limited to supported renderer | Yes | Yes |
| PNG still / sequence | Raster | Bake | Bake | Bake | Renderer dependent | Yes | Frames only |
| WebP still | Raster | Bake at selected frame | Bake at selected frame | Bake | Renderer dependent | Yes | No |
| GIF | Raster | Bake | Bake | Bake | Renderer dependent | 1-bit transparency only | Loop metadata |
| APNG | Raster | Bake | Bake | Bake | Renderer dependent | Yes | Loop metadata |
| WebM video | Raster | Bake | Bake | Bake | Renderer dependent | Codec-dependent | No embedded player |
| MP4 video | Raster | Bake | Bake | Bake | Renderer dependent | Generally no alpha in standard delivery path | No embedded player |
| Lottie JSON / dotLottie | Limited vector subset | Limited | Limited | Limited | Limited | Usually yes | Player-dependent |

**No output is automatically listed as supported just because its file extension is available.** A dedicated tested adapter must implement the semantics.

### 20.3 Static SVG export

- Serialize the **evaluated still state** at selected frame into a valid SVG with scene dimensions/viewBox, named layers as groups, local references and resolved definitions.
- Remove all keyframes, scripts, editor metadata and interaction overlays.
- Flatten symbols safely; retain accessible title/desc and reasonable IDs.
- Embed permitted raster images as data URIs for self-contained output, with explicit warning about output file size; do not reference transient Blob URLs.
- Options: selected scene/object, include background, precision, optimized/minified SVG, IDs preserve/generate, convert text to paths where allowed, embed fonts/images where legally and technically supported.
- Strip unnecessary metadata while retaining visual equivalence within numeric tolerance.

### 20.4 Animated SVG export (SMIL)

- Use valid SVG elements such as `<animate>`, `<animateTransform>` and `<animateMotion>` only when the feature is representable in the selected browser support target.
- Translate keyframe times using exact rational FPS and scene duration. Convert cubic Bézier curves to compatible `keySplines` and `calcMode="spline"` where possible. Convert holds to discrete semantics.
- Preserve rotation pivot and nested transform composition. For a transform consisting of multiple animated channels, choose a verified composition strategy, such as nested groups with individual animations or deterministic transform matrix samples, not conflicting animation nodes targeting the same attribute.
- Repeating animations use correct `dur`, `repeatCount`, and final-boundary values.
- Unsupported easing and advanced geometry may be baked into sampled key values at a selectable precision/tolerance; include size/performance warning and side-by-side preview comparison.
- Export diagnostics identify nodes/tracks that cannot map exactly. If unsupported output fidelity exceeds configured tolerance, block with Switch to HTML Player, Bake, Skip Affected Tracks (explicit), or Cancel.
- Test animated SVG in target Chrome, Firefox and Safari; never assume exact SMIL feature equivalence across browser engines.

### 20.5 SVG + CSS export

- Export valid `scene.svg` plus `animation.css`, or an optional standalone SVG embedding permitted `<style>` rules where supported.
- Generate stable classes/IDs and `@keyframes` for transform, opacity and supported style animations.
- Explicitly set transform-origin and transform-box semantics; test in browser engines rather than assuming CSS defaults match SVG transform pivots.
- CSS path morph, arbitrary shape geometry, motion path and filter behavior must be represented only if actually tested and supported; otherwise offer HTML player or animation baking with a compatibility report.
- Include `@media (prefers-reduced-motion: reduce)` behaviour (pause or fallback frame) by option.
- Exports containing a separate CSS file come in ZIP packages or paired downloads. Do not write inaccessible local filesystem references.

### 20.6 HTML + Framewise Player export

- Package a self-contained `index.html`, optimized SVG asset data, minimal `framewise-player.js` runtime, styles and any necessary images/fonts.
- The player runs deterministic property evaluation outside the Elm editor, based on a versioned portable animation JSON subset generated at export.
- Player public API:

```ts
interface FramewisePlayer {
  play(): void;
  pause(): void;
  stop(): void;
  seekFrame(frame: number): void;
  seekSeconds(seconds: number): void;
  setSpeed(speed: number): void;
  setLoop(mode: 'none' | 'repeat' | 'pingpong'): void;
  getCurrentFrame(): number;
  getDurationSeconds(): number;
  destroy(): void;
}
```

- Optional controls include play/pause, progress seek, loop, replay and speed; UI must be keyboard accessible.
- Support JavaScript initialization without global variable collisions; documented ESM import option.
- No CDN, analytics, user tracking or remote dependencies. CSP-safe runtime without dynamic `eval`/`new Function`.
- Minimize runtime weight, preserve accessible SVG titles and control labels, respect reduced motion.
- Player evaluator and Elm evaluator share golden fixture outputs to prevent animation drift despite implementation in different languages.

### 20.7 PNG/WebP still exports

- Use one evaluated frame and render at scene native size times scaling factor.
- Support 1x/2x/3x and custom output dimensions; preserve aspect unless unlocked.
- Transparent and solid background options, pixel sampling, optional padding/bleed, colour management assumptions documented.
- Use a sanitised same-origin Blob URL or a directly rendered SVG to raster canvas, then `toBlob`/OffscreenCanvas.
- Do not let tainted canvases silently fail; show exact missing/remote-asset error.

### 20.8 PNG image sequence

- Render each requested scene frame (or selected range) deterministically.
- Names formatted with zero-padding: `scene-name_000001.png` etc. Index origin is user-configurable and recorded in export metadata.
- Download a ZIP of PNG frames plus optional `manifest.json` with FPS numerator/denominator, size, alpha and frame count.
- Preserve image order, ensure no duplicate or missing frame at loop endpoint, and include cancellation and memory-limiting batching.

### 20.9 GIF/APNG

- GIF: 256-colour quantization, palette options (global/per-frame), dithering, frame delay conversion, repeat count, binary transparency limitations, dimensions and quality controls. Warn when alpha cannot be represented faithfully.
- APNG: full-alpha PNG-frame animation with correct control chunks and frame delays, loop behaviour and preview.
- Both use deterministic rendered source frames and a tested encoding adapter/worker. Test decoder compatibility using reference fixtures.
- Avoid using MediaRecorder as a substitute for deterministic frame encoding.

### 20.10 Video export

- WebM presets with browser-supported codecs verified using feature detection. Do not assume transparency or codec support without checking.
- MP4/H.264 only when an available encoder and lawful/licensed muxing implementation support requested output; a format may be unavailable in particular browsers. Offer ZIP PNG sequence as universal fallback.
- Frame rendering at exact requested FPS and duration, without dropped/duplicated timeline samples. Encode in a worker where supported; keep buffering bounded.
- Use a tested container muxer; raw `EncodedVideoChunk` outputs are not standalone WebM or MP4.
- Video export options: resolution, FPS, codec, bitrate/quality, background colour, selected frame range, repeated loops, name and output size controls.
- Cancel must release encoders, ObjectURLs, frame buffers and worker resources; stale callbacks cannot present a cancelled file as complete.

### 20.11 Lottie and dotLottie interoperability

This is a **bounded interchange implementation**, not full compatibility with all After Effects/Lottie features:

- Export supported geometric nodes, paths, transforms, opacity, fills/strokes and verified easing modes to the actual Lottie JSON specification.
- Emit precise compatibility diagnostics for each unsupported property, text/font feature, masks, gradients, complex effects, symbols and morph tracks.
- dotLottie packaging conforms to a selected documented container version (v1 or v2) and is tested against a matching real player; do not simply rename a ZIP to `.lottie`.
- Each advertised output type must have fixtures opened by at least one independent compatible player, including a visually compared render.
- A support status of Export with Warnings means warnings are visible before download and output preview includes affected elements.
- If the Lottie implementation does not faithfully support a specific document, use a blocked state rather than producing a falsely complete file.
- Do not implement generic import solely because export exists. Import requires a separate rigorous adapter and specification.

### 20.12 Export jobs, errors and reproducibility

- Statuses: queued, validating, preparing, rendering, encoding, packaging, completed, cancelled, failed.
- Show progress as frames/total where measurable; do not invent percentages for unpredictable encoding stages.
- All jobs are cancellable and have bounded concurrency. Failed job retains a usable diagnostic summary and Retry action.
- Output naming uses sanitized names; reject path separators/control characters and dangerous filename collisions inside archives.
- Preserve provenance: source document revision, scene ID, export settings, warnings and app version in optional sidecar metadata.
- Before enabling Download, validate file signature, nonzero length, expected MIME, archive entries where applicable and a render smoke test when practical.

---

## 21. Persistence, autosave, history and recovery

### 21.1 Storage model

Use IndexedDB in the TypeScript adapter, with schema-managed object stores:

```text
framewise-db
  projects            # current durable JSON document revisions / metadata
  revisions           # save and autosave checkpoints keyed by document/revision
  assets              # deduplicated Blobs keyed by content hash
  thumbnails          # best-effort cached scene thumbnails
  recent              # recent document/file metadata, no raw file permissions assumed
  settings            # preferences, layouts, shortcut map
  session             # open tabs, active scenes, viewport cursors
  jobs                # export job metadata only; transient large frame buffers not persisted
```

Native `.framewise` files are the portable source of truth once saved externally. IndexedDB projects are local working copies and recovery. A browser can evict origin storage; explain this accurately and encourage explicit file saves. Where supported, request persistent storage only as a purposeful user action, with a clear explanation.

### 21.2 Explicit Save and Save As semantics

**Save:**

1. Snapshot coherent current revision and validate it.
2. Serialize archive and asset hashes.
3. If the application has an authorized writable native file handle, write to it transactionally where the API allows, close/commit the stream and verify success.
4. If no suitable file handle exists or browser lacks the API, invoke Save As/download with an unambiguous save-as-new-file experience.
5. Update `lastExplicitSaveRevision` only after successful durable write/download dispatch acknowledgement, while clearly distinguishing an unverified browser download from confirmed file overwrite.
6. Show saving, saved, download initiated or error statuses truthfully.

**Save As** allocates a new destination without changing document ID unless user invokes Duplicate Document. After file download in browsers without writable handles, the UI should still indicate local modifications are retained and may need a new download for subsequent revisions.

**Save Copy** does not change active file identity, tab name or dirty state. **Revert** requires a confirmed explicit-save checkpoint, not latest autosave.

### 21.3 Autosave

- Autosave semantic document revisions to IndexedDB after a bounded idle period and on important transitions; do not write full archives and large blobs after each pointer tick.
- Keep autosave revisions and last explicit save separate. Display `Unsaved changes`, `Autosaved locally`, `Saved to file`, `Save failed` as distinct statuses.
- Use atomic IndexedDB transactions for metadata/revision references so interrupted writes cannot leave an apparently valid project with missing assets.
- Rotate checkpoints with configurable retention and space budgets; never delete the last known good recovery copy.
- On quota errors, stop claiming autosave succeeded, warn user prominently, and offer immediate download/back-up.
- `beforeunload` warns only when real unsaved work is at risk; do not attempt unreliable asynchronous saves during unload.

### 21.4 Browser/tab conflicts

- Use BroadcastChannel where available to advertise document edit ownership or changed local revisions.
- If same local document is opened for editing in multiple tabs, show read-only/duplicate/force takeover choices. Avoid silent last-writer-wins corruption.
- Tab ownership uses heartbeat and stale-session cleanup; do not assume BroadcastChannel messages are persistent locks.
- If another tab writes a newer revision, preserve local working copy and offer side-by-side metadata/change decision.

### 21.5 History model

History stores domain commands with reversible deltas or a bounded structural snapshot when appropriate. Requirements:

- Every editing operation has a stable operation ID, description, timestamp and inverse or before/after patch.
- Coalesce continuous pointer dragging, colour scrubbing, slider movement and text typing into understandable undo steps.
- Import, group, symbol edits, broad keyframe transformations, scene resize and boolean paths are single undoable transactions.
- Undo/redo replay command state, not DOM node mutators.
- Undo must restore asset references, node ordering, selection where meaningful, and all affected keyframes.
- Redo stack invalidates on new committed command after undo.
- Bound memory; checkpoint state and truncate oldest history with user-configurable limits. Autosave persists document snapshots but does not promise an unlimited cross-session undo stack.
- History panel lists recent command descriptions with selected revision preview where reasonably safe. Jump-to-history is a replay with confirmation when it discards newer edits.

### 21.6 Delete and cleanup

- Deleting a node removes descendant geometry and affected tracks/motion attachments but leaves shared symbols/assets if still referenced.
- Background cleanup can remove orphaned binary assets only after a reference count audit across current durable revisions and recovery retention.
- Clear Storage in Preferences provides exact categories and sizes, requires explicit confirmation, and cannot claim deletion of separately downloaded native files.

---

## 22. Clipboard, drag-and-drop and interoperability

### 22.1 Clipboard

- Internal clipboard schema contains selected node subtree(s), needed style references, symbol definitions, tracks and dependent asset IDs or transferable bytes.
- Copy/paste between Framewise documents remaps all colliding IDs, preserves relative positions and timing, and copies required assets.
- Paste in Place retains source scene coordinates where possible; ordinary Paste positions selection near viewport center or pointer with consistent offset.
- Copy as SVG generates sanitised static SVG at current frame. Paste SVG imports with the same safe pipeline as file import.
- Copy/Paste Style transfers compatible appearance attributes only; inspector shows what was skipped.
- Clipboard permissions can be denied. Internal in-memory copy/paste still works in same tab, with an explanation when cross-tab/system clipboard is unavailable.
- Cut commits deletion only after internal copy succeeds; never lose selected content because system clipboard API rejected a write.

### 22.2 Drag-and-drop

- Supported: files into canvas, assets into canvas, layer reorder/reparent, timeline keyframe dragging, markers, colour styles onto shapes.
- A file drop must not navigate away from the app. Full-window drop overlay differentiates Open New Document and Import Into Current Scene.
- Validate maximum size and supported file types before enqueueing importer; show progress and cancellation.
- Drag ghost previews never mutate document until committed.

---

## 23. Keyboard shortcuts and input behaviour

All shortcuts are defined in a cross-platform command registry and displayed in menus/tooltips. A user can remap non-reserved commands while conflicts are detected. Never intercept browser/system shortcuts in text inputs when they are expected to edit text.

| Action | Windows/Linux | macOS |
|---|---|---|
| New | Ctrl+N | Cmd+N |
| Open | Ctrl+O | Cmd+O |
| Save | Ctrl+S | Cmd+S |
| Save As | Ctrl+Shift+S | Cmd+Shift+S |
| Export | Ctrl+E | Cmd+E |
| Undo / Redo | Ctrl+Z / Ctrl+Shift+Z | Cmd+Z / Cmd+Shift+Z |
| Copy / Paste | Ctrl+C / Ctrl+V | Cmd+C / Cmd+V |
| Duplicate | Ctrl+D | Cmd+D |
| Select All | Ctrl+A | Cmd+A |
| Group | Ctrl+G | Cmd+G |
| Ungroup | Ctrl+Shift+G | Cmd+Shift+G |
| Command palette | Ctrl+K | Cmd+K |
| Preview | Ctrl+Enter | Cmd+Enter |
| Play/pause timeline | Space when timeline/canvas non-text input focused | Same |
| Select tool | V | V |
| Direct select | A | A |
| Pen | P | P |
| Rectangle | R | R |
| Ellipse | O | O |
| Text | T | T |
| Hand tool | H or hold Space during canvas gesture | Same |
| Zoom tool | Z | Z |
| Keyframe at playhead | K when timeline/animation focus | Same |
| Previous / next frame | Left / Right when timeline focus and no editable field | Same |
| Jump start / end | Home / End when timeline focus | Same |
| Delete selected object/key | Delete/Backspace, context-sensitive | Same |
| Cancel tool/dialog | Escape | Same |

The select/canvas/timeline key context must be explicit so typing `R` into a text editor doesn't create a rectangle. Shortcut manager records a focused target class. For example, Space pans while actively holding it over canvas but plays/pauses when timeline focus is active and no pointer drag is in progress; show a visual tool hint.

Arrow nudging is context-sensitive: selected object in canvas gets movement; selected keys in timeline get frame shift; editable numeric field gets step changes; keyboard tree navigation gets row movement. Document interaction never steals screen reader shortcuts unnecessarily.

---

## 24. Accessibility and reduced motion

### 24.1 Requirements

- Target WCAG 2.2 AA for application controls and static UI where applicable; acknowledge that complex canvas drawing remains an accessibility challenge and provide meaningful alternative interfaces.
- Use semantic buttons, native inputs where appropriate, accessible labels, descriptions, roles, focus indicators and logical reading order.
- Menus use correct `menu`/`menuitem` keyboard semantics with arrow/Home/End/Escape. Dialogs trap focus and restore it to trigger on close.
- Do not communicate animation-track status, selected state, errors or disabled actions by colour alone.
- Screen reader live announcements for save state, selection changes, export completion, import failures and destructive confirmations, throttled to avoid chatter.
- Layer tree exposes hierarchy and selection via keyboard using appropriate treeview semantics where correctly implemented.
- Timeline track list offers a keyboard-operable table/tree alternative for selecting keys and editing exact frame/value, not merely draggable SVG diamonds.
- Inspector inputs and command palette provide fully keyboard-operable alternatives to the most important canvas operations.
- Set accessible title/description for exported SVG scenes when users configure them.

### 24.2 Motion preferences

- Respect `prefers-reduced-motion: reduce` for application chrome and autoplay. Disable nonessential transition effects and start animated previews paused by default.
- Exporter offers: original animation, reduced-motion fallback to nominated frame, and optional `prefers-reduced-motion` styles for CSS/HTML player output.
- Do not automatically remove authored animation data from source documents due to OS preference.
- Animated content can always be paused. Offer a Stop All Motion button in preview and escape controls.

### 24.3 Colour, contrast, zoom and focus

- Both themes meet intended text/control contrast with disabled state still legible.
- Work at 200% browser zoom where feasible; sidebars collapse instead of clipping primary actions.
- Expose touch target sizing preferences and high-contrast borders.
- Keyboard focus remains stable when canvas state updates at 60 FPS; avoid VDOM remounts of active input controls.

---

## 25. Performance and scalability

### 25.1 Workload targets

Performance thresholds are engineering objectives under a published reference device/browser profile, not false universal guarantees:

- Routine edits in a 300-node scene should remain interactively responsive at 60Hz on contemporary desktop hardware where geometry permits.
- A 1,000-node scene should remain editable with sensible overlays and visibility culling rather than freeze on simple selection/move operations.
- Scrubbing a scene with dozens of simultaneously animated properties should prioritize playhead feedback and progressively refine costly filters.
- Autosave must not visibly interrupt pointer interaction.
- Exporting long frame sequences should have bounded memory growth and meaningful cancellation.

### 25.2 Render optimization

- Partition static scene structure from per-frame animated values. Skip recomputation of unaffected nodes.
- Track node/track revision numbers; memoize world transform, path bounds, hit-test data, effect definitions and arc-length tables.
- Use keyed SVG nodes. Avoid recreating whole node subtrees for single-property changes.
- Batch geometry operations and DOM measurements through adapters; avoid JS/Elm port chatter for every pointer pixel when it is safe to calculate pure matrix transformations in Elm.
- Throttle visual UI updates during heavy pointer motion while retaining precise final pointer position.
- Use spatial indexing (e.g., quadtree or R-tree adapter) when hit testing many nodes, but preserve exact SVG fill/stroke tests for final candidates.
- Cull offscreen editor decoration; do not accidentally cull artboard geometry needed for actual export.
- Use web workers for parsing archives, hashing large files, raster/encoding jobs when feasible, and expensive geometry preprocessing.
- Apply limits to data size, keyframe count, path segment count, symbol recursion and filter complexity to avoid unbounded work.
- Prefer reconstructable cache eviction over retaining binary image copies in both Elm and TypeScript.

### 25.3 Quality modes

- **Editing quality:** optionally simplify expensive filters and onion skins while manipulating the canvas; indicate when approximation is active.
- **Preview quality:** canonical evaluator and normal rendering, adaptive frame skipping allowed.
- **Export quality:** canonical frame sampling and full resolved effects within renderer capability, no silent simplification.

### 25.4 Diagnostics

A developer diagnostics pane (disabled by default) provides application version, browser capabilities, document statistics, invalid links, cache sizes, FPS/render timings, port request queue, recent recoverable errors and export warnings. No document contents are transmitted. Export Diagnostics creates a user-reviewable text/JSON bundle with artwork excluded unless explicitly opted in.

---

## 26. Security and privacy

### 26.1 Threat model

Treat imported SVG/XML, project archives, asset metadata, clipboard payloads, fonts, malformed paths, image decoders, user-supplied names, user-authored external URLs and future plugin extensions as potential attack surfaces.

Threats include SVG XSS, XML entity attacks, remote resource loading, ZIP bombs, path traversal, malformed image payloads, cross-origin canvas taint, memory exhaustion, stale async overwrites, compromised dependencies, malicious export HTML, unsafe protocol commands and local-storage data loss.

### 26.2 Hard requirements

- Never inject raw imported SVG into `innerHTML`/`outerHTML` or equivalent prior to sanitization, validation and conversion to typed data.
- Never execute imported scripts, CSS URLs, `foreignObject` HTML, inline event handlers, executable external references or source map metadata.
- Enforce maximum imported file/archive sizes, expanded byte count, entry count, XML depth, attribute length, node count and path segment count. Limits may be configurable only within bounded safe constraints.
- Validate SVG URL attributes and `<use>` references via explicit allowlists; local-only references must resolve within a bounded graph.
- Avoid server-side upload and automatic URL fetching entirely in the default product.
- Use restrictive CSP with no `unsafe-eval`; ensure exported HTML player is compatible with a documented CSP.
- Use Trusted Types in supporting browsers for any unavoidable HTML sinks; DOMPurify is a defense component, not permission to bypass typed modeling.
- Use safe link targets and `rel="noopener noreferrer"` for external links.
- Validate all imported native document references and prohibit archive path traversal.
- Document content is private by default; no telemetry, remote fonts, remote analytics, third-party network fonts or error reporting without explicit opt-in.
- Pin dependencies, audit licences and vulnerabilities, and produce a dependency manifest/SBOM in automated release processes.
- Restrict service worker cache to versioned app assets. Never cache arbitrary imported artwork into a public/shared CDN cache.
- Ensure safe error messaging does not expose secrets or entire user file contents.

### 26.3 Permission design

The app requests only permissions relevant to a user's action (open file, write file, clipboard, storage persistence). Denial produces a clear fallback. The application must not request broad file system access to search documents or silently re-open deleted/revoked handles.

### 26.4 Font and licence safety

Imported font data is optional. The editor must not suggest redistribution is automatically lawful. Fonts must be embedded in exports only with explicit user control; otherwise use fallback or converted paths where legally supported. Publish dependency and icon/font notices.

---

## 27. Error handling and empty states

Every async operation has Idle/Working/Success/Error/Cancelled states. For each error, show what failed, whether work is safe, and a recovery option. Use user-facing language rather than raw stack traces; allow Copy Technical Details where helpful.

| Condition | Required handling |
|---|---|
| Invalid native archive | Stop load, preserve source, show failed validation details and Download Original |
| Newer unsupported native schema | Read-only error/explanation, keep bytes, no automatic downgrade |
| Unsupported SVG constructs | Import compatibility review; choose partial safe import or cancel |
| Malicious SVG | Reject, do not preview in executable DOM |
| Missing binary asset | Show layer placeholder, identify missing ID, relink or remove |
| Missing font | Fallback with visible warning; export comparison hint |
| Autosave quota exceeded | Prominent persistent warning; download backup; retry/cleanup |
| Save picker denied | Do not mark file saved; offer download fallback |
| Encoder unsupported | Disable format/preset with reason and alternative |
| Browser tab backgrounded | Playback pause/resume policy, no timing jump |
| Device memory pressure | Cancel or reduce preview quality; preserve autosave; explain |
| Duplicate IDs / broken references | Fail validation or offer deterministic repair as recovery copy |
| Export impossible without loss | Block or require deliberate Bake/Skip choice |
| Worker crash | Job failure, recreate worker on retry, retain source revision |
| Unsaved tab close | Show confirmation/recovery state, not silent loss |

Empty project state: one scene, attractive simple grid/background, contextual tool hint and clear Draw Shape or Import SVG actions. Empty timeline state explains how to select an object and add a key. Empty assets state invites import. Empty recents state shows examples and Create New. No empty panel should simply contain a blank void.

---

## 28. Offline/PWA specification

- Installable web app manifest with icon family, name, start URL, theme/background colours, display mode and app description.
- Service worker pre-caches versioned app shell, Elm compiled JS, CSS, icons, documentation and examples. Avoid caching third-party network responses by default.
- Offline startup should work after initial successful installation/cache population; show Offline Ready status in settings.
- Network loss during editing does not change project functionality. Links to repository/external docs degrade gracefully.
- Service worker updates stage new code and ask user before activation if open documents have unsaved edits. Do not invalidate IndexedDB schema unexpectedly.
- Exported document files and working user assets remain in IndexedDB/Downloads/native files, not public service worker caches.
- No push messaging, accounts, subscription logic or remote analytics.

---

## 29. Rendering and algorithm contracts

### 29.1 Canonical evaluation API

```text
evaluateScene(document, sceneId, continuousFrame)
  -> ResolvedScene
       { sceneId, frame, width, height, background,
         orderedRenderableNodes, defs, diagnostics }
```

Evaluation is pure and must not depend on prior playback frames. It performs:

1. Validate/resolve scene and symbol references.
2. Map global frame to symbol instance-local frame where applicable.
3. Evaluate enabled typed property tracks at frame using outgoing segment interpolation.
4. Apply tracks to base node properties without mutating the document.
5. Calculate motion-path positions and orientation relative to base transform.
6. Resolve symbol overrides and nested grouping.
7. Compose world transforms and inherited visibility/opacity/style rules.
8. Emit renderable scene tree with stable identity and safe references.

No editor selection/hover state is accepted by this API. Preview and export must not call different animation evaluators for the same property semantics.

### 29.2 Interpolation formulas and order

- Let keyframes at frames `a` and `b` (with `a < b`) have values `va, vb`; normalized segment position is `u = clamp((frame-a)/(b-a),0,1)`.
- Apply outgoing interpolation of the `a` key: `t = easing(u)` (or step semantics).
- Numeric result is `va + (vb-va)*t`, subject to property-specific validation.
- 2D vectors interpolate componentwise. Colours use explicit RGBA interpolation policy. Path geometry interpolates corresponding points/handles only after valid preparation.
- Before first key use first-key value, after final key use final-key value unless documented extrapolation/remapping applies.
- For a track with zero keys use base property. For one key use constant keyed value.
- Invalid/NaN interpolation result is a structured error with nearest safe value only if user explicitly selects recovery; never propagate NaN to SVG attributes.

### 29.3 Geometry and matrix math

- Adopt a single matrix multiplication convention (e.g., column vectors and left-multiply world transformations) and document it in `Domain.Matrix` with examples.
- Standard node composition order is pivot translate -> translation -> rotation -> skew -> scale -> inverse pivot, with exact convention tested against SVG visual outcomes.
- Reparenting with Keep World Position computes new local matrix via inverse new-parent world transform; fail safely if inverse is singular.
- Hit test through inverse matrices and candidate geometry; fallback to SVG DOM point-in-fill/stroke adapters where mathematically necessary.
- Bounding box includes stroke where relevant and transformed corners for selection, but allow exact path extrema for snapping/fit.
- Bézier extrema are computed by solving component derivatives; arcs are converted using mathematically sound algorithms.
- Avoid lossy transform decomposition during trivial node moves; store canonical transform components and rebuild matrices consistently.

### 29.4 Image raster equality

Reference image tests compare evaluator output rendered through browser SVG to encoded still/video frames at identical frame positions. Define output profiles and tolerances: alpha and pixel values are permitted minor browser raster differences, but transforms, shape bounds and keyframe timing must be semantically identical. Text/font tests use bundled permissively licensed test fonts to minimize platform variation.

### 29.5 Quality and data limits

Central `Limits` policy should include explicit guarded values for:

- Maximum canvas dimensions and output pixel count.
- Maximum project/archive size and expanded archive size.
- Maximum nodes per scene and per imported SVG.
- Maximum path segments/contours.
- Maximum keyframes/tracks and scene duration.
- Maximum nested group/symbol depth.
- Maximum external asset size and image decode dimensions.
- Maximum concurrent export jobs and rendered frame buffers.

Limits should be conservative defaults with tests; large content should fail predictably before exhausting memory, and the UI should explain which limit was exceeded.

---

## 30. Testing strategy and required fixtures

All critical domain logic must have automated tests. An agent must not treat visual appearance alone as evidence that save/export/morph/undo works.

### 30.1 Elm domain tests

Use `elm-explorations/test` for:

- Typed document encode/decode round trips, required/optional fields, invalid enums, migration fixtures.
- Scene/node tree invariants, duplicate IDs, parent/child consistency, symbol cycle prevention.
- Matrix composition/inversion, reparent keep-world-position, rotation/pivot cases, negative scale.
- Path conversion, bounds, curve extrema and degeneracies.
- Keyframe insertion/removal/collision and ordered track invariants.
- Easing exact endpoints, cubic Bézier inversion, stepped modes, negative time and spring determinism.
- Time model with 24, 25, 30, 60 and 30000/1001 FPS including loops and endpoint frames.
- History transaction coalescing and undo/redo reversibility for each tool command.
- Selection, grouping, reordering and asset reference retention.
- Colour conversions and numeric validation.
- Interpolated motion path position/tangent, including zero-length paths.
- Symbol inheritance, overrides and local time remapping.
- Export compatibility classifier for each track/property/format pair.

Use fuzz tests for numeric/path invariants and property-based serialization where libraries permit. Every bug involving corrupt geometry or timing should get a regression fixture.

### 30.2 TypeScript adapter tests

Use Vitest (or equivalent) to validate:

- Bridge schema strictness, request ID correlation, timeout/cancellation and stale revision rejection.
- ZIP packaging/unpackaging, path traversal rejection, duplicate archives, zip bomb limitations, content hash verification.
- SVG sanitisation against hostile scripts, event attributes, `foreignObject`, remote URLs, DTD, malformed CSS, recursive local references, huge path input and external image links.
- SVG import intermediate representation with gradients/groups/transforms/text/clips.
- Geometry adapter boolean/path preprocessing on known fixtures and floating-point tolerance.
- File save permission failure and download fallback state mapping.
- Local storage checkpoint rollback and quota failures.
- SVG/CSS/HTML/PNG/GIF/APNG output signatures and validator behaviour.
- Deterministic exporter settings and output file name sanitisation.

### 30.3 Browser end-to-end tests

Use Playwright with Chromium, Firefox and WebKit for workflows:

1. Welcome -> New -> Draw rectangle -> Change fill -> Save -> Reopen and compare document.
2. Import SVG with nested groups -> select layer -> move -> undo -> redo -> Save As.
3. Add keyframes to position/rotation/opacity -> scrub -> preview -> inspect exact evaluated values.
4. Drag layers to a group -> reorder -> hide/lock -> export -> validate SVG paint order.
5. Draw Bézier path -> direct edit anchors -> create motion path -> replay -> export animation.
6. Create symbol -> insert two instances -> override one -> update master -> detach one -> undo.
7. Change scene FPS in preserve-time mode -> verify keyframe times and frame conversion.
8. Create second scene -> batch export both with correct names/fps.
9. Export self-contained static SVG and SMIL-supported animated SVG -> load independently, render visual snapshots.
10. Export HTML player -> load without network -> run public play/pause/seek API and verify frames.
11. Run PNG sequence export -> verify number/order/dimensions/alpha and frame samples.
12. Simulate interrupted session -> recover autosave -> Save As.
13. Simulate file-picker denial and IndexedDB quota failure -> ensure no false saved status.
14. Verify keyboard-only menu, layer operations, property edit, keyframe insertion, preview and save.
15. Import malicious SVG fixture -> confirm script never executes, no network fetch and no executable payload in export.
16. Disable network after app load/PWA cache -> reopen persisted project, edit and export offline.
17. Try unsupported video codec and Lottie construct -> explicit explanation, no invalid file offered.
18. Check browser tab switching/conflict resolution preserves both local working copies.

### 30.4 Golden artwork fixtures

Maintain checked-in fixtures for:

- Basic shape animation (transform, opacity).
- Compound groups, rotated parent and child.
- Repeating spinner loop with seamless endpoint.
- Non-looping timeline with final frame reached.
- Motion path and auto rotation.
- Closed path morph (topology match).
- Path morph that intentionally fails validation.
- Stroke dash draw-on animation.
- Gradient and alpha animation.
- Text with known permissive font.
- Clip/group animation.
- Symbol time remapping with overrides.
- Transparent PNG sequence.
- Unsupported filter and missing asset diagnostics.

Golden expected values should include frame-index/property JSON (renderer-independent) and selected browser image snapshots. Regenerate only with intentional review, never auto-accept changed baselines.

### 30.5 Cross-format export verification

For each advertised export format:

- File parses using an independent decoder/parser.
- Dimensions, duration, FPS, loop and alpha settings match documented limits.
- Pixel/semantic snapshots at first, middle, last and representative keyed frames agree with canonical evaluator.
- Unsupported features produce diagnostics rather than disappearing.
- File is testable without app-origin URLs, transient Blob URLs or a CDN.
- Generated HTML player runs under intended CSP without external resources.

### 30.6 Visual, accessibility and security tests

- Screenshot reference suite for default editor, light theme, narrow viewport, export dialog, import warnings, layer tree, timeline and colour picker.
- axe-core automated scans plus manual keyboard and screen-reader walkthroughs; automated tools do not prove full WCAG conformance.
- Run dependency vulnerability checks and licence scanning; lint for unsafe DOM sinks.
- Fuzz imported project JSON, SVG and ZIP input and verify graceful failures without executable content.

---

## 31. Quality gates and acceptance criteria

**A feature is complete only when** its UI is functional, domain logic is implemented, serialization is correct where applicable, undo/redo works, errors are handled, keyboard/accessibility behaviour is reasonable, unit/browser tests exist, and exported result matches documented capabilities.

### 31.1 Project/document acceptance

- A user can create, edit, save, close, reopen and recover a nontrivial multi-scene project without losing nodes, geometry, assets, symbols, tracks or keyframe values.
- Saving in Chromium via writable picker genuinely updates the selected file; in Firefox/Safari users receive a correctly labelled download fallback.
- Explicit save state accurately distinguishes autosave from file persistence.
- Changing theme/layout never marks artwork dirty.

### 31.2 Vector editor acceptance

- Imported supported SVG remains editable as distinct named nodes/layers.
- Group and nested transform operations visually match calculated world matrices.
- All visible tools are usable. Broken geometry cannot enter the canonical model.
- Layer selection, lock/hide, grouping, reparenting, clipping, pivot edits and path operations survive save/reopen.
- Unsupported SVG features show visible and actionable warnings.

### 31.3 Animation acceptance

- Every advertised animatable property can be keyed, edited, scrubbed, played, copied, deleted, undone and exported in at least one faithful target format.
- The same frame renders equivalently regardless of play history or seek order.
- Cubic Bézier and spring interpolation are deterministic. Reverse/loop/ping-pong boundaries have explicit test coverage.
- Motion paths are editable, arc-length evaluated and orientation behaves predictably.
- Path morph either produces a real geometry interpolation or a visible incompatibility report.

### 31.4 Export acceptance

- SVG still, animated SVG on supported feature subsets, SVG + CSS supported subsets, HTML player, PNG still/sequence, GIF/APNG and capability-appropriate video render targets all have independent decode/preview tests.
- Export UI does not offer a broken format or misleading output. Lottie/dotLottie are advertised as supported only for verified compatible feature subsets.
- User can inspect unsupported features and choose a deliberate fallback, with exported result reflecting that choice.
- A browser without WebCodecs can still export static SVG/PNG, SVG animations where representable, HTML player and PNG sequences.

### 31.5 Security/reliability acceptance

- Hostile SVG, invalid ZIP and corrupt native files do not execute code or alter existing projects.
- Offline editor functionality is preserved after caching and across routine reloads.
- Export or import cancellation leaves project state uncorrupted.
- A recoverable checkpoint exists after unsaved editing and interrupted session closure, subject to clearly communicated browser storage limitations.

### 31.6 Design/accessibility acceptance

- The editor looks deliberately designed and coherent across themes; no placeholder UI in production.
- Key commands are reachable through menus and command palette, and important editing flows work without mouse-only gestures.
- Panels resize without broken layout; 200% zoom has no loss of essential save/recovery controls.
- Reduced motion, status messages, focus management and accessible labels are correctly implemented.

---

## 32. Repository layout, release and contribution requirements

Recommended repository:

```text
framewise/
├── README.md
├── SPECIFICATION.md
├── LICENSE
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── CHANGELOG.md
├── THIRD_PARTY_NOTICES.md
├── elm.json
├── package.json
├── pnpm-lock.yaml                 # or npm lockfile, choose one
├── tsconfig.json
├── vite.config.ts
├── playwright.config.ts
├── public/
│   ├── manifest.webmanifest
│   ├── icons/
│   └── examples/
├── src/                           # Elm source per section 17
├── web/                           # TypeScript adapters/CSS/workers
├── tests/
│   ├── elm/
│   ├── unit/
│   ├── browser/
│   ├── fixtures/
│   └── golden/
├── docs/
│   ├── getting-started.md
│   ├── editor-guide.md
│   ├── animation-model.md
│   ├── file-format.md
│   ├── export-compatibility.md
│   ├── security.md
│   ├── architecture.md
│   └── contributing-components.md
└── .github/
    ├── workflows/
    │   ├── checks.yml
    │   ├── browser-tests.yml
    │   └── release.yml
    └── ISSUE_TEMPLATE/
```

### 32.1 README

Includes concise product explanation, actual screenshots/GIF captured from running app, browser support, feature matrix, hosted demo link if available, limitations, installation, build/test commands, offline/privacy guarantees, export warnings and contributors/credits. Do not present planned but unimplemented features as shipping features.

### 32.2 Contributor requirements

- Document Elm domain model and port contracts with small, runnable examples.
- Centralize language strings for future translation; base application language English.
- Every new node type must add serializer, validator, inspector controls, renderer, hit test, history behaviour, fixtures and export capability report.
- Every new animated property must implement typed value, interpolation, evaluator integration, timeline/inspector control and export adapters or explicit incompatibility.
- Every new output format must add independent validation tests and target capability declarations.
- Pull requests must pass Elm tests, TS tests, type checking, browser smoke tests, lint and licence/security checks.
- Use issue templates for bugs (browser, document format, reproduction, safe fixture), enhancement proposals and export compatibility issues.
- Provide `SECURITY.md` with a private vulnerability reporting route and disclosure policy.

### 32.3 CI commands

Document commands corresponding to:

```bash
pnpm install --frozen-lockfile
pnpm run typecheck
pnpm run lint
pnpm run format:check
pnpm run elm:test
pnpm run test:unit
pnpm run test:e2e
pnpm run build
pnpm run preview
```

These are target command names. The package scripts must actually exist and use the chosen package manager. CI runs on Linux and browser smoke tests in Chromium/Firefox/WebKit; validate release artefacts on Windows/macOS browser environments where relevant.

### 32.4 Deployment

- Build as static assets served over HTTPS from GitHub Pages, Cloudflare Pages, Netlify, or equivalent.
- Correct SPA fallback routing for editor/preview local IDs. Do not redirect unknown static assets to HTML silently if it corrupts export/worker loading.
- Include content security policy, immutable hashed asset caching and service worker update strategy.
- No server keys, API secrets, runtime database server or upload endpoints are required.
- Produce source maps for development; production error reporting must remain opt-in and not leak document content.
- Version app and native document schema separately.
- Provide release downloads including reproducible source/build instructions and immutable checksums where applicable.

---

## 33. Example end-to-end behavioural contracts

### 33.1 Create bouncing ball animation

1. User opens Framewise -> New -> 400×400, 30 FPS, 60 frames, transparent.
2. Insert ellipse at `(150,40)` with dimensions `100×100` and blue fill. Layer named `Ball`.
3. At frame 0, insert position key.
4. At frame 15, move ball to `(150,250)` with Auto-Keyframe enabled; key created at 15.
5. Set outgoing frame-0 easing to Ease In. Add frame-30 position returning to `(150,40)` with Ease Out on prior segment.
6. Enable scene loop; make endpoint at frame 60 match frame 0 if full 60-frame loop.
7. Preview shows expected result and frame readout is correct.
8. Save as `bouncing-ball.framewise` and reopen; every key/easing/shape value persists.
9. Export supported SMIL SVG; run standalone file in three browser engines. Export 60-frame PNG ZIP and verify frame samples match evaluator.

### 33.2 Imported logo reveal

1. Import a valid complex SVG containing nested groups, gradients and clipping.
2. Compatibility report enumerates retained/approximated/unsupported features; users can choose Import Supported.
3. Layers remain independently named; user can rename and reorder without unintentionally flattening.
4. Animate group transform, stroke dash offset and opacity. Curve editor adjusts interpolation.
5. Export Studio warns if chosen CSS target cannot express the stroke/clip animation faithfully and offers compatible SMIL or HTML Player.
6. User exports HTML Player bundle; it works without Framewise, network or unreferenced assets.

### 33.3 Recovery after a failed Save

1. User edits a native document with current revision 42; latest externally saved revision is 35.
2. Autosave writes revision 42 to IndexedDB.
3. User selects Save; browser denies native file write.
4. UI displays explicit failed write, still dirty relative to saved file, but Autosaved Locally.
5. Browser crashes; on reopen Recovery Manager offers revision 42 and identifies original file revision 35.
6. User opens recovery copy, verifies artwork and downloads new `.framewise` archive. Original file was not overwritten and no revisions were discarded.

### 33.4 Adversarial import

1. User drops an SVG containing an inline script, `onload` handler, `foreignObject`, remote image reference and recursive `<use>`.
2. Parser rejects dangerous structure, no network requests are made, and no script runs.
3. Import review either rejects the file with clear issues or offers safe, partial conversion of recognized shapes without any executable residue.
4. Resulting Framewise document can be saved and exported safely without reintroducing attacker-controlled markup.

---

## 34. Explicit engineering decisions and non-goals

1. **Elm is the editor's main programming language.** Do not rewrite the application in React/Vue/Svelte because a component is awkward to implement. Use TypeScript solely for well-defined platform/encoding/graphics adapters and the lightweight exported player.
2. **SVG DOM is the editable scene renderer.** Do not replace vector content wholesale with Canvas/WebGL or a raster screenshot. Canvas/OffscreenCanvas is permitted for export/rasterization and complex previews.
3. **Local-first is not a marketing label.** Core editing/import/export does not depend on API credentials or server storage.
4. **No opaque imported markup in model.** Dangerous/unknown SVG fragments do not get stashed and replayed on export.
5. **Native file and export SVG are different things.** The `.framewise` archive carries editability and timeline data; exported SVG carries exactly the supported visual output.
6. **There is one evaluator.** UI playback and all export adapters must share semantic test fixtures.
7. **A capability matrix is part of the product.** Do not add format buttons before they produce independently validated results.
8. **Do not create dead navigation.** Every screen/menu/control described has a real handler, persistence where needed, disabled states, errors and tests.
9. **Do not use decorative placeholders.** Empty states and examples are functional.
10. **No timeline/phase framework or time estimates.** Implement the complete specified product using logical dependency ordering internally without exposing milestone-oriented filler in product documentation.
11. **No fabricated cross-format perfection.** Import/output limitations are first-class functionality, not bugs to hide.
12. **Do not build login, hosted collaboration, plugin marketplace, AI generation, sound editor, video clip editor, remote sharing back end or payment screens.** These would distract from a reliable open-source SVG animation studio and are not part of this product contract.

---

## 35. Implementation agent instructions

The engineering agent must use this document as a functional contract, not as aspirational marketing copy.

**Required conduct:**

- Implement coherent working features end to end, including actual UI interaction, domain logic, serialization, error states, tests and documented compatibility.
- Favor small typed domain functions and explicit effect adapters over broad untyped JavaScript abstractions.
- Maintain a clear boundary between committed document state, transient gesture state, derived evaluated render state and persistent recovery copies.
- Use current documented package APIs and verify browser support before depending on features. The Elm compiler currently specified is 0.19.3, and tool/package versions must be pinned from actually installable compatible releases.
- Use accessible UI primitives and a coherent design system. Do not ship a generic generated dashboard aesthetic.
- Any file export displayed as available must actually produce a valid file tested in a consumer independent of Framewise.
- If a feature is genuinely unsupported in a browser, expose its capability status and a documented fallback. Do not quietly remove it from the interface or misrepresent it as complete.
- Do not introduce external APIs, user tracking, required cloud storage, authentication or subscription code.
- Keep Markdown docs, `README.md`, format specification, menu registry, tests and in-app shortcut help synchronized with actual implementation.
- The final codebase must compile, run, and pass representative creation -> animate -> save -> reopen -> export scenarios without manual source modifications.

### 35.1 Definition of a finished application

The finished Framewise product is an open-source, offline-capable, browser-based vector animation studio in which someone can create or import a complex SVG drawing, edit its independent layer hierarchy, animate supported properties at precise frames, customize easing and motion paths, preview deterministically, preserve everything in an editable `.framewise` file, recover interrupted work, and export only formats whose behaviour is honestly and independently verified. The interface must remain clean and reliable across supported browsers with explicit fallbacks for capabilities they do not provide.

---

## 36. Technical references and verification sources

These links provide implementation guidance. They are not substitutes for validating package/browser behaviour in the checked-in test suite.

- Elm compiler release (0.19.3): https://github.com/elm/compiler/releases/tag/0.19.3
- Elm language/package reference: https://package.elm-lang.org/
- Elm SVG package: https://package.elm-lang.org/packages/elm/svg/latest/
- Elm Browser package: https://package.elm-lang.org/packages/elm/browser/latest/
- Elm test package: https://package.elm-lang.org/packages/elm-explorations/test/latest/
- Vite Elm integration: https://github.com/hmsk/vite-plugin-elm
- SVG animation/SMIL guide: https://developer.mozilla.org/en-US/docs/Web/SVG/Guides/SVG_animation_with_SMIL
- SVG `<animateTransform>`: https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/animateTransform
- SVG `<animate>` and motion accessibility: https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/animate
- File System Access save picker limitations: https://developer.mozilla.org/en-US/docs/Web/API/Window/showSaveFilePicker
- WebCodecs VideoEncoder and browser support: https://developer.mozilla.org/en-US/docs/Web/API/VideoEncoder
- dotLottie formal format versions: https://www.dotlottie.io/spec/
- DOMPurify for defence-in-depth SVG sanitisation: https://github.com/cure53/DOMPurify
- Web Content Accessibility Guidelines 2.2: https://www.w3.org/TR/WCAG22/
- SVG 2 specification: https://www.w3.org/TR/SVG2/
- Web Animations specification: https://www.w3.org/TR/web-animations-1/

**Final note:** Browser formats and standards overlap without being equivalent. The Framewise native model must remain richer than the least capable export target, with explicit detection and truthful reporting whenever conversion would lose intent or visual fidelity.
