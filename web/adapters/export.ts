import { strToU8 } from "fflate";
import type { Bridge } from "./bridge";
import { zipFiles } from "./archive";
import { downloadBlob, sanitizeFileName } from "./files";
import { BridgeError, isRecord, requireString } from "./protocol";
import { isPng, svgToPng } from "./raster";
import { getAsset } from "./storage";
import playerSource from "../player/framewise-player.js?raw";

/**
 * Packages exporter output produced by Elm. Every artefact is validated with
 * an independent parser before the download is offered.
 */

interface ExportItem {
  sceneId: string;
  name: string;
  svg?: string;
  css?: string;
  animation?: unknown;
  title?: string;
  frames?: Array<{ frame: number; svg: string }>;
  width?: number;
  height?: number;
  scale?: number;
  fps?: { numerator: number; denominator: number };
  indexOrigin?: number;
  transparent?: boolean;
  report?: unknown;
}

export interface ExportResult {
  fileName: string;
  bytes: number;
  mime: string;
}

const ASSET_TOKEN = /fw-asset:\/\/([A-Za-z0-9_-]+)/g;

async function inlineAssets(svg: string): Promise<string> {
  const ids = Array.from(new Set(Array.from(svg.matchAll(ASSET_TOKEN), (m) => m[1]!)));
  let out = svg;
  for (const id of ids) {
    const asset = await getAsset(id);
    if (!asset)
      throw new BridgeError(
        "export.asset",
        `Asset ${id} is missing from browser storage; relink it before exporting`,
      );
    const dataUrl = await blobToDataUrl(asset.blob);
    out = out.split(`fw-asset://${id}`).join(dataUrl);
  }
  return out;
}

function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new BridgeError("export.asset", "Could not read asset"));
    reader.readAsDataURL(blob);
  });
}

export function validateSvgText(svg: string): void {
  const doc = new DOMParser().parseFromString(svg, "image/svg+xml");
  if (doc.getElementsByTagName("parsererror").length > 0)
    throw new BridgeError("export.invalid", "Generated SVG failed to parse");
  if (doc.documentElement.tagName.toLowerCase() !== "svg")
    throw new BridgeError("export.invalid", "Generated file is not an SVG document");
  if (doc.querySelector("script"))
    throw new BridgeError("export.invalid", "Generated SVG unexpectedly contains a script");
}

function parseItems(payload: unknown): {
  format: string;
  documentName: string;
  items: ExportItem[];
  appVersion: string;
} {
  const format = requireString(payload, "format");
  const documentName = requireString(payload, "documentName");
  const appVersion =
    isRecord(payload) && typeof payload.appVersion === "string" ? payload.appVersion : "0.0.0";
  if (!isRecord(payload) || !Array.isArray(payload.items))
    throw new BridgeError("payload.invalid", "Export items missing");
  return { format, documentName, items: payload.items as ExportItem[], appVersion };
}

export async function runExport(
  payload: unknown,
  jobId: string,
  bridge: Bridge,
): Promise<ExportResult> {
  const { format, documentName, items, appVersion } = parseItems(payload);
  if (items.length === 0) throw new BridgeError("export.empty", "Nothing to export");
  const progress = (status: string, done: number, total: number) =>
    bridge.emit("export.progress", { jobId, status, done, total });
  progress("preparing", 0, items.length);
  const single = items.length === 1;
  const baseName = single ? sanitizeFileName(items[0]!.name) : sanitizeFileName(documentName);

  switch (format) {
    case "svg":
    case "smil":
    case "svg-css": {
      const outputs: Record<string, string> = {};
      for (const item of items) {
        if (!item.svg) throw new BridgeError("export.invalid", "Missing SVG output");
        const svg = await inlineAssets(item.svg);
        validateSvgText(svg);
        const suffix =
          format === "smil" ? ".animated.svg" : format === "svg-css" ? ".css.svg" : ".svg";
        outputs[`${sanitizeFileName(item.name)}${suffix}`] = svg;
        if (format === "svg-css" && item.css)
          outputs[`${sanitizeFileName(item.name)}.animation.css`] = item.css;
        if (item.report)
          outputs[`${sanitizeFileName(item.name)}.report.json`] = JSON.stringify(
            item.report,
            null,
            2,
          );
      }
      const svgEntries = Object.entries(outputs).filter(([name]) => name.endsWith(".svg"));
      if (svgEntries.length === 1 && format !== "svg-css") {
        const [name, svg] = svgEntries[0]!;
        const blob = new Blob([svg], { type: "image/svg+xml;charset=utf-8" });
        downloadBlob(blob, name);
        progress("completed", 1, 1);
        return { fileName: name, bytes: blob.size, mime: "image/svg+xml" };
      }
      const zip = zipFiles(outputs);
      const name = `${baseName}-${format}.zip`;
      downloadBlob(new Blob([zip as BlobPart], { type: "application/zip" }), name);
      progress("completed", items.length, items.length);
      return { fileName: name, bytes: zip.byteLength, mime: "application/zip" };
    }
    case "html": {
      const files: Record<string, string> = {};
      for (const item of items) {
        if (!item.svg || !item.animation)
          throw new BridgeError("export.invalid", "Missing player output");
        const svg = await inlineAssets(item.svg);
        validateSvgText(svg);
        const slug = sanitizeFileName(item.name);
        const prefix = single ? "" : `${slug}/`;
        const animationJson = JSON.stringify(item.animation);
        files[`${prefix}index.html`] = playerHtml(
          item.title ?? item.name,
          svg,
          animationJson,
          appVersion,
        );
        files[`${prefix}framewise-player.js`] = playerSource;
        files[`${prefix}animation.json`] = animationJson;
        files[`${prefix}scene.svg`] = svg;
        files[`${prefix}README.txt`] = playerReadme(appVersion);
        if (item.report) files[`${prefix}report.json`] = JSON.stringify(item.report, null, 2);
      }
      const zip = zipFiles(files);
      const name = `${baseName}-player.zip`;
      downloadBlob(new Blob([zip as BlobPart], { type: "application/zip" }), name);
      progress("completed", items.length, items.length);
      return { fileName: name, bytes: zip.byteLength, mime: "application/zip" };
    }
    case "png": {
      const item = items[0]!;
      if (!item.svg) throw new BridgeError("export.invalid", "Missing SVG output");
      progress("rendering", 0, 1);
      const svg = await inlineAssets(item.svg);
      const png = await svgToPng(svg, item.width ?? 100, item.height ?? 100, item.scale ?? 1);
      if (!(await isPng(png)))
        throw new BridgeError("export.invalid", "Rendered output is not a PNG");
      if (items.length > 1) {
        const files: Record<string, Uint8Array> = {};
        for (const [index, it] of items.entries()) {
          if (!it.svg) continue;
          const bytes = new Uint8Array(
            await (
              await svgToPng(
                await inlineAssets(it.svg),
                it.width ?? 100,
                it.height ?? 100,
                it.scale ?? 1,
              )
            ).arrayBuffer(),
          );
          files[`${sanitizeFileName(it.name)}.png`] = bytes;
          progress("rendering", index + 1, items.length);
        }
        const zip = zipFiles(files);
        const name = `${baseName}-png.zip`;
        downloadBlob(new Blob([zip as BlobPart], { type: "application/zip" }), name);
        return { fileName: name, bytes: zip.byteLength, mime: "application/zip" };
      }
      const name = `${baseName}.png`;
      downloadBlob(png, name);
      progress("completed", 1, 1);
      return { fileName: name, bytes: png.size, mime: "image/png" };
    }
    case "png-sequence": {
      const files: Record<string, Uint8Array | string> = {};
      let total = 0;
      for (const item of items) total += item.frames?.length ?? 0;
      let done = 0;
      for (const item of items) {
        const frames = item.frames ?? [];
        const slug = sanitizeFileName(item.name);
        const origin = item.indexOrigin ?? 0;
        const prefix = single ? "" : `${slug}/`;
        for (const frame of frames) {
          if (bridge.isCancelled(jobId)) throw new BridgeError("cancelled", "Export cancelled");
          const svg = await inlineAssets(frame.svg);
          const png = await svgToPng(svg, item.width ?? 100, item.height ?? 100, item.scale ?? 1);
          const index = String(frame.frame - (frames[0]?.frame ?? 0) + origin).padStart(6, "0");
          files[`${prefix}${slug}_${index}.png`] = new Uint8Array(await png.arrayBuffer());
          done += 1;
          if (done % 5 === 0 || done === total) progress("rendering", done, total);
        }
        files[`${prefix}manifest.json`] = JSON.stringify(
          {
            scene: item.name,
            sceneId: item.sceneId,
            fps: item.fps,
            width: Math.round((item.width ?? 0) * (item.scale ?? 1)),
            height: Math.round((item.height ?? 0) * (item.scale ?? 1)),
            alpha: item.transparent ?? true,
            frameCount: frames.length,
            firstFrame: frames[0]?.frame ?? 0,
            lastFrame: frames[frames.length - 1]?.frame ?? 0,
            indexOrigin: origin,
            generator: `Framewise ${appVersion}`,
          },
          null,
          2,
        );
      }
      progress("packaging", done, total);
      const zip = zipFiles(files);
      const name = `${baseName}-frames.zip`;
      downloadBlob(new Blob([zip as BlobPart], { type: "application/zip" }), name);
      progress("completed", total, total);
      return { fileName: name, bytes: zip.byteLength, mime: "application/zip" };
    }
    default:
      throw new BridgeError("export.format", `Format ${format} is not available in this build`);
  }
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function escapeScriptJson(json: string): string {
  // prevent </script> and HTML comment sequences from terminating the block
  return json.replace(/<\//g, "<\\/").replace(/<!--/g, "<\\!--");
}

export function playerHtml(
  title: string,
  svg: string,
  animationJson: string,
  appVersion: string,
): string {
  const svgBody = svg.replace(/^<\?xml[^>]*>\s*/, "");
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:;">
<title>${escapeHtml(title)}</title>
<style>
  html, body { margin: 0; height: 100%; background: #111; color: #eee; font: 14px/1.4 system-ui, sans-serif; }
  .fw-stage { display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100%; gap: 12px; padding: 16px; box-sizing: border-box; }
  .fw-scene { max-width: 100%; max-height: 80vh; }
  .fw-scene svg { width: 100%; height: auto; display: block; }
  .fw-controls { display: flex; gap: 8px; align-items: center; }
  .fw-controls button { font: inherit; padding: 6px 12px; border-radius: 6px; border: 1px solid #555; background: #222; color: #eee; cursor: pointer; }
  .fw-controls button:focus-visible { outline: 2px solid #e8862d; outline-offset: 2px; }
  .fw-controls input[type=range] { width: 240px; }
  .fw-time { font-variant-numeric: tabular-nums; min-width: 8ch; }
  @media (prefers-reduced-motion: reduce) { .fw-reduced-note { display: block; } }
  .fw-reduced-note { display: none; font-size: 12px; color: #aaa; }
</style>
</head>
<body>
<div class="fw-stage">
  <div class="fw-scene" id="fw-scene">${svgBody}</div>
  <div class="fw-controls" id="fw-controls" role="toolbar" aria-label="Playback">
    <button type="button" data-fw="toggle" aria-label="Play or pause">Play</button>
    <button type="button" data-fw="restart" aria-label="Restart">Restart</button>
    <input type="range" data-fw="seek" min="0" step="1" value="0" aria-label="Seek frame">
    <span class="fw-time" data-fw="time" aria-live="off">0</span>
    <label><input type="checkbox" data-fw="loop" checked> Loop</label>
    <select data-fw="speed" aria-label="Speed"><option value="0.5">0.5×</option><option value="1" selected>1×</option><option value="2">2×</option></select>
  </div>
  <p class="fw-reduced-note">Reduced motion is on: the animation starts paused. Press Play to run it.</p>
</div>
<script id="fw-animation" type="application/json">${escapeScriptJson(animationJson)}</script>
<script src="framewise-player.js"></script>
<script>
  (function () {
    var data = JSON.parse(document.getElementById("fw-animation").textContent);
    var player = FramewisePlayer.create(document.getElementById("fw-scene"), data, { controls: document.getElementById("fw-controls") });
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) player.play();
    window.framewisePlayer = player;
  })();
</script>
<!-- Generated by Framewise ${escapeHtml(appVersion)} -->
</body>
</html>
`;
}

function playerReadme(appVersion: string): string {
  return `Framewise HTML player export (Framewise ${appVersion})

Files
  index.html            Standalone page: open it directly, no server or network needed.
  framewise-player.js   The player runtime (plain script, defines window.FramewisePlayer).
  animation.json        Portable animation data (version 1).
  scene.svg             The static scene the player animates.

Embedding
  <div id="stage"><!-- contents of scene.svg --></div>
  <script src="framewise-player.js"></script>
  <script>
    var player = FramewisePlayer.create(document.getElementById("stage"), animationJson);
    player.play();
  </script>

API
  play(), pause(), stop(), seekFrame(frame), seekSeconds(seconds), setSpeed(speed),
  setLoop("none" | "repeat" | "pingpong"), getCurrentFrame(), getDurationSeconds(), destroy()

The runtime uses no eval or network access and works under a strict Content Security Policy.
`;
}

export { strToU8 };
