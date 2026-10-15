import type { Bridge } from "./bridge";
import { buildArchive, readArchive, sha256Hex } from "./archive";
import { downloadBlob, openFile, readFileBytes, saveBytes } from "./files";
import { readText, writeText } from "./clipboard";
import { importSvg } from "./svg-import";
import { randomIds } from "./id";
import { imageSize } from "./raster";
import { runExport } from "./export";
import {
  BridgeError,
  isRecord,
  optionalBoolean,
  optionalString,
  requireNumber,
  requireString,
} from "./protocol";
import * as storage from "./storage";
import { setDirty, toRecent } from "../main";
import { detectCapabilities } from "./capabilities";

declare const __APP_VERSION__: string;

const MAX_IMPORT_BYTES = 50 * 1024 * 1024;
const assetUrls = new Map<string, string>();

function assetUrl(sha: string, blob: Blob): string {
  const existing = assetUrls.get(sha);
  if (existing) return existing;
  const url = URL.createObjectURL(blob);
  assetUrls.set(sha, url);
  return url;
}

async function recentsPayload(): Promise<unknown> {
  const projects = await storage.listProjects();
  return { recents: projects.map(toRecent), recoveries: storage.recoveriesFrom(projects) };
}

function documentAssetIds(document: unknown): string[] {
  if (!isRecord(document) || !Array.isArray(document.assets)) return [];
  return (document.assets as Array<Record<string, unknown>>).map((a) => String(a.id));
}

async function collectAssets(
  document: unknown,
): Promise<Array<{ id: string; bytes: Uint8Array; mimeType: string; sha256: string }>> {
  const out: Array<{ id: string; bytes: Uint8Array; mimeType: string; sha256: string }> = [];
  if (!isRecord(document) || !Array.isArray(document.assets)) return out;
  for (const meta of document.assets as Array<Record<string, unknown>>) {
    const id = String(meta.id);
    const record = await storage.getAsset(id);
    if (!record)
      throw new BridgeError(
        "asset.missing",
        `Image asset "${String(meta.name ?? id)}" is missing from browser storage`,
      );
    out.push({
      id,
      bytes: new Uint8Array(await record.blob.arrayBuffer()),
      mimeType: record.mimeType,
      sha256: record.sha256,
    });
  }
  return out;
}

async function openDocumentFile(file: File, token: string | null): Promise<unknown> {
  const bytes = await readFileBytes(file, 200 * 1024 * 1024);
  const archive = await readArchive(bytes);
  const urls: Record<string, string> = {};
  for (const [id, asset] of archive.assets) {
    const blob = new Blob([asset.bytes as BlobPart], { type: asset.meta.mimeType });
    await storage.putAsset({
      sha256: id,
      blob,
      mimeType: asset.meta.mimeType,
      byteLength: asset.bytes.byteLength,
      name: asset.meta.path,
      width: 0,
      height: 0,
    });
    urls[id] = assetUrl(id, blob);
  }
  const documentId =
    isRecord(archive.document) && typeof archive.document.id === "string"
      ? archive.document.id
      : archive.manifest.documentId;
  // the opened file is the saved baseline for Revert
  const existing = await storage.getProject(documentId);
  const revision = existing ? existing.revision + 1 : 1;
  await storage.putSavedCopy(documentId, revision, archive.document);
  return {
    kind: "document",
    document: archive.document,
    fileName: file.name,
    fileToken: token,
    revision,
    savedRevision: revision,
    assetUrls: urls,
  };
}

async function importImageFile(file: File): Promise<unknown> {
  if (!["image/png", "image/jpeg", "image/webp"].includes(file.type))
    throw new BridgeError(
      "image.type",
      `${file.type || "This file"} is not a supported image type (PNG, JPEG, WebP)`,
    );
  const bytes = await readFileBytes(file, MAX_IMPORT_BYTES);
  const sha = await sha256Hex(bytes);
  const blob = new Blob([bytes as BlobPart], { type: file.type });
  const size = await imageSize(blob);
  if (size.width * size.height > 64_000_000)
    throw new BridgeError("image.size", "The image exceeds the 64 megapixel decode limit");
  await storage.putAsset({
    sha256: sha,
    blob,
    mimeType: file.type,
    byteLength: bytes.byteLength,
    name: file.name,
    width: size.width,
    height: size.height,
  });
  return {
    kind: "image",
    name: file.name,
    url: assetUrl(sha, blob),
    asset: {
      id: sha,
      name: file.name,
      mimeType: file.type,
      byteLength: bytes.byteLength,
      sha256: sha,
      width: size.width,
      height: size.height,
    },
  };
}

async function importSvgFile(file: File): Promise<unknown> {
  const text = await file.text();
  const review = importSvg(text, file.name);
  return { kind: "svg", review };
}

async function openByKind(kind: string, file: File, token: string | null): Promise<unknown> {
  const name = file.name.toLowerCase();
  if (kind === "document" || name.endsWith(".framewise")) return openDocumentFile(file, token);
  if (kind === "svg" || name.endsWith(".svg")) return importSvgFile(file);
  if (kind === "image" || /\.(png|jpe?g|webp)$/.test(name)) return importImageFile(file);
  if (name.endsWith(".json")) {
    const text = await file.text();
    let document: unknown;
    try {
      document = JSON.parse(text);
    } catch {
      throw new BridgeError("json.parse", "The JSON snapshot could not be parsed");
    }
    if (!isRecord(document) || document.schemaVersion !== 1)
      throw new BridgeError("json.schema", "This JSON is not a Framewise snapshot");
    return {
      kind: "document",
      document,
      fileName: null,
      fileToken: null,
      revision: 0,
      savedRevision: null,
      assetUrls: {},
    };
  }
  if (/\.(gif|apng|mp4|webm|mov)$/.test(name))
    throw new BridgeError(
      "import.unsupported",
      "Video and animated image files are render outputs, not editable sources. Import an SVG or image, or open a .framewise document.",
    );
  if (/\.(lottie|tgs|riv|fig)$/.test(name))
    throw new BridgeError(
      "import.unsupported",
      "This format has no import adapter in Framewise. Export it to SVG from its native tool first.",
    );
  throw new BridgeError("import.unsupported", `${file.name} is not a supported file type`);
}

export async function handleDroppedFile(bridge: Bridge, file: File): Promise<void> {
  try {
    const payload = await openByKind("any", file, null);
    bridge.emit("file.open", payload);
  } catch (error) {
    const bridgeError =
      error instanceof BridgeError
        ? error
        : new BridgeError("import.failed", "Could not open the dropped file");
    bridge.emitError("file.open", bridgeError);
  }
}

export function registerHandlers(bridge: Bridge): void {
  bridge.register("platform.ids", async (req) => {
    const count =
      isRecord(req.payload) && typeof req.payload.count === "number"
        ? Math.min(1024, Math.max(1, req.payload.count))
        : 256;
    return { ids: randomIds(count) };
  });

  bridge.register("platform.focus", async (req) => {
    const id = requireString(req.payload, "id");
    // the element is rendered on the next animation frame
    await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
    const el = document.getElementById(id);
    if (el instanceof HTMLElement) {
      el.focus();
      if (el instanceof HTMLInputElement && el.type === "text") el.select();
    }
    return {};
  });

  bridge.register("platform.fullscreen", async () => {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await document.documentElement.requestFullscreen().catch(() => undefined);
    return {};
  });

  bridge.register("session.dirty", async (req) => {
    setDirty(optionalBoolean(req.payload, "dirty", false));
    return {};
  });

  bridge.register("storage.recents", async () => recentsPayload());

  bridge.register("storage.preferences", async (req) => {
    await storage.putSetting("preferences", req.payload);
    return {};
  });

  bridge.register("storage.layout", async (req) => {
    await storage.putSetting("layout", req.payload);
    return {};
  });

  bridge.register("storage.autosave", async (req) => {
    if (!req.documentId || req.revision === null)
      throw new BridgeError("payload.invalid", "Autosave needs a document id and revision");
    const p = req.payload;
    const document = isRecord(p) ? p.document : null;
    if (!document) throw new BridgeError("payload.invalid", "Autosave payload missing document");
    const savedRevision =
      isRecord(p) && typeof p.savedRevision === "number" ? p.savedRevision : null;
    await storage.autosave(
      {
        documentId: req.documentId,
        name: optionalString(p, "name") ?? "Untitled",
        width: isRecord(p) && typeof p.width === "number" ? p.width : 0,
        height: isRecord(p) && typeof p.height === "number" ? p.height : 0,
        sceneCount: isRecord(p) && typeof p.sceneCount === "number" ? p.sceneCount : 1,
        modifiedAt: Date.now(),
        revision: req.revision,
        savedRevision,
        fileName: optionalString(p, "fileName"),
        thumbnail: optionalString(p, "thumbnail"),
        document,
      },
      documentAssetIds(document),
    );
    return { documentId: req.documentId, revision: req.revision };
  });

  bridge.register("storage.load", async (req) => {
    const documentId = requireString(req.payload, "documentId");
    const recovery = optionalBoolean(req.payload, "recovery", false);
    const project = await storage.getProject(documentId);
    if (!project)
      throw new BridgeError(
        "storage.missing",
        "This document is no longer in browser storage. It may have been evicted; open the .framewise file instead.",
      );
    const urls: Record<string, string> = {};
    for (const id of project.assetIds ?? []) {
      const asset = await storage.getAsset(id);
      if (asset) urls[id] = assetUrl(id, asset.blob);
    }
    return {
      document: project.document,
      fileName: project.fileName,
      fileToken: null,
      revision: project.revision,
      savedRevision: project.savedRevision,
      recovery,
      assetUrls: urls,
    };
  });

  bridge.register("storage.loadSaved", async (req) => {
    const documentId = requireString(req.payload, "documentId");
    const saved = await storage.getSavedCopy(documentId);
    if (!saved)
      throw new BridgeError(
        "storage.missing",
        "No explicitly saved copy is stored for this document",
      );
    return { document: saved.document, revision: saved.revision };
  });

  bridge.register("storage.delete", async (req) => {
    const documentId = requireString(req.payload, "documentId");
    await storage.deleteProject(documentId, optionalBoolean(req.payload, "recoveryOnly", false));
    return {};
  });

  bridge.register("storage.downloadRecovery", async (req) => {
    const documentId = requireString(req.payload, "documentId");
    const project = await storage.getProject(documentId);
    if (!project) throw new BridgeError("storage.missing", "Recovery copy not found");
    const assets = await collectAssets(project.document).catch(() => []);
    const bytes = buildArchive(
      project.document,
      documentId,
      __APP_VERSION__,
      assets,
      project.thumbnail,
    );
    downloadBlob(
      new Blob([bytes as BlobPart], { type: "application/zip" }),
      `${project.name}-recovery.framewise`,
    );
    return {};
  });

  bridge.register("storage.clear", async (req) => {
    await storage.clearCategory(requireString(req.payload, "category"));
    return {};
  });

  bridge.register("storage.persist", async () => {
    const granted = await storage.requestPersistence();
    if (!granted)
      throw new BridgeError("storage.persistDenied", "Persistent storage was not granted");
    bridge.emit("event.capabilities", await detectCapabilities());
    return {};
  });

  bridge.register("file.open", async (req) => {
    const kind = (optionalString(req.payload, "kind") ?? "document") as
      "document" | "svg" | "image" | "any";
    const opened = await openFile(kind);
    return openByKind(kind, opened.file, opened.token);
  });

  bridge.register("file.save", async (req) => {
    if (!req.documentId || req.revision === null)
      throw new BridgeError("payload.invalid", "Save needs a document id and revision");
    const mode = (optionalString(req.payload, "mode") ?? "save") as "save" | "saveAs" | "copy";
    const document = isRecord(req.payload) ? req.payload.document : null;
    if (!document) throw new BridgeError("payload.invalid", "Save payload missing document");
    const assets = await collectAssets(document);
    const bytes = buildArchive(
      document,
      req.documentId,
      __APP_VERSION__,
      assets,
      optionalString(req.payload, "thumbnail"),
    );
    const result = await saveBytes(
      bytes,
      optionalString(req.payload, "suggestedName") ?? "document.framewise",
      mode,
      optionalString(req.payload, "fileToken"),
    );
    if (mode !== "copy") {
      await storage.putSavedCopy(req.documentId, req.revision, document);
      const project = await storage.getProject(req.documentId);
      if (project) {
        await storage.autosave(
          {
            ...project,
            revision: req.revision,
            savedRevision: req.revision,
            fileName: result.fileName,
            document,
            modifiedAt: Date.now(),
          },
          documentAssetIds(document),
        );
      }
    }
    return {
      documentId: req.documentId,
      revision: req.revision,
      mode: result.mode,
      fileName: result.fileName,
      fileToken: result.fileToken,
      copy: mode === "copy",
    };
  });

  bridge.register("file.downloadText", async (req) => {
    const name = requireString(req.payload, "name");
    const text = requireString(req.payload, "text");
    const mime = optionalString(req.payload, "mime") ?? "text/plain";
    downloadBlob(new Blob([text], { type: mime }), name);
    return {};
  });

  bridge.register("clipboard.write", async (req) => {
    await writeText(requireString(req.payload, "text"));
    return {};
  });

  bridge.register("clipboard.read", async () => ({ text: await readText() }));

  bridge.register("export.run", async (req) => runExport(req.payload, req.requestId, bridge));

  bridge.register("export.cancel", async (req) => {
    bridge.cancel(requireString(req.payload, "jobId"));
    return {};
  });

  void requireNumber;
}
