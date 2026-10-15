# Export compatibility

Every export reads the same evaluated scene the editor renders. Before a file is produced, `Export.Capability` classifies each animation track for the chosen target as Exact, Baked (sampled every frame, or otherwise approximated with a stated reason) or Unsupported. Unsupported tracks block the export until you switch format or tick Skip Affected Tracks.

| Track property | Static SVG | Animated SVG (SMIL) | SVG + CSS | HTML player |
|---|---|---|---|---|
| position, scale, rotation, skew, pivot | still | native `animateTransform` on per-channel groups | `@keyframes transform` on per-channel groups | native |
| opacity, visibility | still | native | native | native |
| fill / stroke colour | still | native (`fill` + `fill-opacity`) | native (`rgba`) | native |
| stroke width, dash offset | still | native | native | native |
| rect size, corner radius, ellipse radii | still | native | unsupported | native |
| path geometry (compatible morph) | still | native `d` animation | unsupported | native |
| font size | still | native | unsupported | native |
| text content | still | unsupported | unsupported | native |
| motion-path progress | still | native `animateMotion` with `keyPoints` | unsupported | native |
| blur radius | still | native `stdDeviation` animation | unsupported | native |
| tracks on a clipping shape | still | unsupported | unsupported | native |

Easing: linear, the four smooth presets and cubic Bézier curves with control values inside `[0,1]` export as `keySplines` (SMIL) or `cubic-bezier()` (CSS). Hold, spring and overshoot easing is baked to per-frame samples and reported. CSS exports accept Bézier curves outside `[0,1]` in Y.

Loop mode: once becomes a single run with `fill="freeze"`; repeat becomes `repeatCount="indefinite"` or `infinite`; ping-pong is baked into a mirrored cycle for SMIL and uses `animation-direction: alternate` in CSS.

Raster images are embedded as data URIs. Text relies on fonts installed where the file is viewed.

## Rasters

PNG stills render one frame at 1×, 2× or 3× through the browser's own SVG renderer. PNG sequences render every frame in the chosen range to `<scene>_<index>.png` in a ZIP alongside `manifest.json` (fps as a rational, size, alpha, frame count, index origin).

## Not available

GIF, APNG, WebM, MP4 and Lottie appear in the Export Studio as unavailable with a reason. Encoders for these need independent verification before they are offered; the documented path is a PNG sequence plus ffmpeg or an equivalent tool.
