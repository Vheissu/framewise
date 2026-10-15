# Third-party notices

Runtime dependencies bundled into the application:

| Package | Version | Licence | Use |
|---|---|---|---|
| dompurify | 3.4.17 | Apache-2.0 OR MPL-2.0 | SVG sanitisation before import |
| fflate | 0.8.2 | MIT | ZIP reading and writing for `.framewise` files and export bundles |
| elm/core, elm/browser, elm/html, elm/svg, elm/json, elm/url, elm/time, elm/virtual-dom | see elm.json | BSD-3-Clause | Elm runtime and standard library |

Development dependencies (compiler, bundler, linters, test runners) are listed in `package.json` and are not shipped.

Interface icons are original drawings in `src/UI/Icons.elm`, licensed with the rest of the project under MIT. No fonts are bundled; the interface uses the operating system's UI font.

The exported HTML player (`web/player/framewise-player.js`) is part of this project and is MIT licensed, so exported bundles can be redistributed freely.
