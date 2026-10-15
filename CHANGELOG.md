# Changelog

## Unreleased

- Reworked the interface around the conventions of desktop motion tools: a toolbar across the top instead of a side rail, document tabs on the canvas panel, panels on a dark gutter, denser rows, and a properties panel laid out one property per row with the keyframe toggle on the left.
- Numeric values are blue and can be dragged sideways to scrub them.
- Layers get a label colour shown in the layer list and as their bar in the timeline. The timeline header shows a large timecode, and frame 0 is inset so its keys are not cut off.
- The welcome screen has a sidebar for actions, presets drawn to their aspect ratio, a recent-files list, and example cards that render each example's artwork.
- Fixed clip groups rendering nothing: the clip shape was wrapped in a `<g>`, which browsers ignore inside `<clipPath>`. This affected the canvas and every SVG export.
- Fixed clicking a keyframe leaving it attached to the pointer until the next click.
- Fixed the keyframe easing curve, which was built from HTML elements and never drew.

## 0.1.0

First release.

- Vector tools: select, direct select (anchor and handle editing), pen, rectangle, ellipse, line, polygon, star, text, image import, pivot, hand, zoom.
- Layers: groups, clip groups, lock, hide, rename, reorder and reparent by drag, isolation mode, filter.
- Animation: integer-frame keyframes on transform, opacity, visibility, fill, stroke, dash offset, rectangle size and corner radius, ellipse radii, path geometry (compatible morph), font size, text content, blur radius and motion-path progress. Auto-keyframe with frame-0 baselines, hold/linear/preset/cubic Bézier/spring easing with a curve editor, stagger, key copy/paste, reverse, scale and distribute.
- Playback: once/repeat/ping-pong, speed, reverse, work range, onion skin, full-screen preview.
- Documents: autosave to IndexedDB with recovery, `.framewise` ZIP archives, JSON snapshots, Chromium file-handle saves with download fallback elsewhere.
- Import: sanitised SVG with a compatibility review; PNG, JPEG and WebP images.
- Export: static SVG, animated SVG (SMIL), SVG + CSS, HTML + player bundle, PNG still, PNG sequence ZIP, each with a per-track compatibility report. GIF, APNG, video and Lottie are listed as unavailable.
- Offline: installable PWA with a precaching service worker.
