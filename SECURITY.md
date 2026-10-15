# Security

Framewise treats imported SVG, `.framewise` archives, clipboard payloads and JSON snapshots as untrusted input. Nothing is uploaded anywhere; the attack surface is the browser tab.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's private vulnerability reporting on this repository (Security tab, "Report a vulnerability"). Include the browser, a minimal fixture if you have one, and what you observed.

You can expect an acknowledgement within a week. Fixes ship as a normal release with a note in CHANGELOG.md; credit is given unless you ask otherwise.

## What is in scope

- Script or markup from an imported SVG reaching the live page or an export.
- Archive handling: path traversal, decompression bombs, hash bypass.
- Exported HTML player bundles executing anything other than the bundled runtime.
- Stored data from one document leaking into another.

## Out of scope

- Denial of service by very large but well-formed documents (limits exist; see `Domain.Limits` and `web/adapters/sanitise-svg.ts`).
- Issues that require a modified build or browser extensions.
