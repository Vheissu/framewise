# Security notes

See SECURITY.md for reporting. This page describes what the code does.

## Imported SVG

1. Size, DOCTYPE, entity and external-stylesheet checks on the raw text.
2. `DOMParser` as `image/svg+xml`; parse errors are rejected.
3. DOMPurify with the SVG profile and additional hooks: scripts, `foreignObject`, animation elements, links and event handlers are removed; `href` values that are not local fragments are dropped; `style` attributes and `<style>` elements with external `url()`, `@import` or `javascript:` are dropped; `<image>` elements without an embedded PNG, JPEG or WebP data URI are removed.
4. Element count (≤ 20000) and depth (≤ 128) limits.
5. Conversion into typed node JSON. The sanitised DOM is attached only to a hidden, inert container for bounding-box measurement of gradients.
6. The Elm decoder re-validates every field; path data is re-parsed by the Elm path parser.

Raw markup never reaches the live page. Everything the canvas renders is generated from typed data.

## Archives

Entry count, path safety, duplicate entries, total uncompressed size and per-asset SHA-256 checks run before anything is decoded. Asset MIME types are limited to PNG, JPEG and WebP.

## Exports

Generated SVG is parsed with an independent `DOMParser` before download and rejected if it fails or contains a script. The HTML player page carries a `Content-Security-Policy` with no network sources; the animation JSON is embedded with `</script` sequences escaped.

## Application

The production build ships a CSP meta tag (`default-src 'self'`, no `unsafe-eval`). There is no telemetry, no remote fonts and no network access beyond loading the app shell. The service worker caches only versioned app assets; user documents stay in IndexedDB.
