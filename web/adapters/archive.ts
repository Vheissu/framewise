import { strToU8, strFromU8, unzipSync, zipSync, type Zippable } from "fflate";
import { BridgeError, isRecord } from "./protocol";

/**
 * .framewise archive packing and unpacking with defensive limits.
 */

export const LIMITS = {
  maxArchiveBytes: 200 * 1024 * 1024,
  maxEntries: 2000,
  maxUncompressedBytes: 512 * 1024 * 1024,
  maxDocumentBytes: 64 * 1024 * 1024,
  maxAssetBytes: 50 * 1024 * 1024,
};

export interface ManifestAsset {
  id: string;
  path: string;
  mimeType: string;
  byteLength: number;
  sha256: string;
}

export interface Manifest {
  format: "framewise";
  schemaVersion: number;
  application: string;
  generatorVersion: string;
  documentId: string;
  createdAt: string;
  modifiedAt: string;
  documentPath: string;
  assets: ManifestAsset[];
}

export interface ArchiveContents {
  manifest: Manifest;
  document: unknown;
  assets: Map<string, { bytes: Uint8Array; meta: ManifestAsset }>;
}

export interface AssetInput {
  id: string;
  bytes: Uint8Array;
  mimeType: string;
  sha256: string;
}

const ALLOWED_PATH = /^[A-Za-z0-9_.\- /]+$/;

export function isSafePath(path: string): boolean {
  if (!ALLOWED_PATH.test(path)) return false;
  if (path.startsWith("/") || path.includes("\\")) return false;
  const segments = path.split("/");
  if (segments.some((s) => s.trim() === "" || s === "." || s === "..")) return false;
  return path.length <= 256;
}

function extensionFor(mimeType: string): string {
  switch (mimeType) {
    case "image/png":
      return "png";
    case "image/jpeg":
      return "jpg";
    case "image/webp":
      return "webp";
    default:
      return "bin";
  }
}

export function buildArchive(
  document: unknown,
  documentId: string,
  generatorVersion: string,
  assets: AssetInput[],
  thumbnailSvg: string | null,
  now: Date = new Date(),
): Uint8Array {
  const documentJson = strToU8(JSON.stringify(document, null, 2));
  const files: Zippable = {};
  const manifestAssets: ManifestAsset[] = [];
  for (const asset of assets) {
    const path = `assets/sha256-${asset.sha256}.${extensionFor(asset.mimeType)}`;
    if (!isSafePath(path)) throw new BridgeError("archive.path", "Asset path rejected");
    files[path] = [asset.bytes, { level: 0 }];
    manifestAssets.push({
      id: asset.id,
      path,
      mimeType: asset.mimeType,
      byteLength: asset.bytes.byteLength,
      sha256: asset.sha256,
    });
  }
  const manifest: Manifest = {
    format: "framewise",
    schemaVersion: 1,
    application: "Framewise",
    generatorVersion,
    documentId,
    createdAt: now.toISOString(),
    modifiedAt: now.toISOString(),
    documentPath: "document.json",
    assets: manifestAssets,
  };
  files["manifest.json"] = strToU8(JSON.stringify(manifest, null, 2));
  files["document.json"] = documentJson;
  if (thumbnailSvg) files["thumbnails/project.svg"] = strToU8(thumbnailSvg);
  return zipSync(files, { level: 6 });
}

export async function readArchive(bytes: Uint8Array): Promise<ArchiveContents> {
  if (bytes.byteLength > LIMITS.maxArchiveBytes) {
    throw new BridgeError("archive.tooLarge", "The archive exceeds the 200 MB limit");
  }
  if (bytes.byteLength < 4 || bytes[0] !== 0x50 || bytes[1] !== 0x4b) {
    throw new BridgeError("archive.signature", "This is not a ZIP-based .framewise file");
  }
  let entries: Record<string, Uint8Array>;
  let total = 0;
  let count = 0;
  try {
    entries = unzipSync(bytes, {
      filter: (file) => {
        count += 1;
        if (count > LIMITS.maxEntries)
          throw new BridgeError("archive.entries", "Too many entries in archive");
        if (!isSafePath(file.name))
          throw new BridgeError(
            "archive.path",
            `Unsafe path in archive: ${file.name.slice(0, 80)}`,
          );
        total += file.originalSize;
        if (total > LIMITS.maxUncompressedBytes)
          throw new BridgeError("archive.bomb", "Archive expands beyond the allowed size");
        return true;
      },
    });
  } catch (error) {
    if (error instanceof BridgeError) throw error;
    throw new BridgeError("archive.corrupt", "The archive could not be decompressed");
  }
  const seen = new Set<string>();
  for (const name of Object.keys(entries)) {
    const normalised = name.toLowerCase();
    if (seen.has(normalised)) throw new BridgeError("archive.duplicate", `Duplicate entry ${name}`);
    seen.add(normalised);
  }
  const manifestBytes = entries["manifest.json"];
  if (!manifestBytes) throw new BridgeError("archive.manifest", "manifest.json is missing");
  const manifest = parseManifest(manifestBytes);
  const documentBytes = entries[manifest.documentPath];
  if (!documentBytes) throw new BridgeError("archive.document", "document.json is missing");
  if (documentBytes.byteLength > LIMITS.maxDocumentBytes)
    throw new BridgeError("archive.document", "document.json is too large");
  let document: unknown;
  try {
    document = JSON.parse(strFromU8(documentBytes));
  } catch {
    throw new BridgeError("archive.document", "document.json is not valid JSON");
  }
  const assets = new Map<string, { bytes: Uint8Array; meta: ManifestAsset }>();
  for (const meta of manifest.assets) {
    const assetBytes = entries[meta.path];
    if (!assetBytes) throw new BridgeError("archive.asset", `Asset ${meta.path} is missing`);
    if (assetBytes.byteLength !== meta.byteLength)
      throw new BridgeError("archive.asset", `Asset ${meta.path} has an unexpected size`);
    if (assetBytes.byteLength > LIMITS.maxAssetBytes)
      throw new BridgeError("archive.asset", `Asset ${meta.path} is too large`);
    const digest = await sha256Hex(assetBytes);
    if (digest !== meta.sha256)
      throw new BridgeError("archive.hash", `Asset ${meta.path} failed its integrity check`);
    assets.set(meta.id, { bytes: assetBytes, meta });
  }
  return { manifest, document, assets };
}

function parseManifest(bytes: Uint8Array): Manifest {
  let raw: unknown;
  try {
    raw = JSON.parse(strFromU8(bytes));
  } catch {
    throw new BridgeError("archive.manifest", "manifest.json is not valid JSON");
  }
  if (!isRecord(raw)) throw new BridgeError("archive.manifest", "manifest.json is malformed");
  if (raw.format !== "framewise")
    throw new BridgeError("archive.manifest", "Not a Framewise archive");
  if (typeof raw.schemaVersion !== "number")
    throw new BridgeError("archive.manifest", "Manifest schema version missing");
  if (raw.schemaVersion > 1) {
    throw new BridgeError(
      "archive.newer",
      `This file uses schema version ${raw.schemaVersion}, which is newer than this build supports. Update Framewise to open it.`,
    );
  }
  const documentPath = typeof raw.documentPath === "string" ? raw.documentPath : "document.json";
  if (!isSafePath(documentPath))
    throw new BridgeError("archive.path", "Unsafe document path in manifest");
  const assets: ManifestAsset[] = [];
  if (Array.isArray(raw.assets)) {
    for (const a of raw.assets) {
      if (!isRecord(a)) continue;
      if (
        typeof a.id !== "string" ||
        typeof a.path !== "string" ||
        typeof a.mimeType !== "string" ||
        typeof a.byteLength !== "number" ||
        typeof a.sha256 !== "string" ||
        !/^[0-9a-f]{64}$/.test(a.sha256)
      ) {
        throw new BridgeError("archive.manifest", "Manifest asset entry is malformed");
      }
      if (!isSafePath(a.path) || !a.path.startsWith("assets/"))
        throw new BridgeError("archive.path", `Unsafe asset path ${a.path}`);
      if (!["image/png", "image/jpeg", "image/webp"].includes(a.mimeType)) {
        throw new BridgeError("archive.asset", `Asset type ${a.mimeType} is not allowed`);
      }
      assets.push({
        id: a.id,
        path: a.path,
        mimeType: a.mimeType,
        byteLength: a.byteLength,
        sha256: a.sha256,
      });
    }
  }
  return {
    format: "framewise",
    schemaVersion: raw.schemaVersion,
    application: typeof raw.application === "string" ? raw.application : "Framewise",
    generatorVersion: typeof raw.generatorVersion === "string" ? raw.generatorVersion : "unknown",
    documentId: typeof raw.documentId === "string" ? raw.documentId : "",
    createdAt: typeof raw.createdAt === "string" ? raw.createdAt : "",
    modifiedAt: typeof raw.modifiedAt === "string" ? raw.modifiedAt : "",
    documentPath,
    assets,
  };
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer,
  );
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

export function zipFiles(files: Record<string, Uint8Array | string>): Uint8Array {
  const zippable: Zippable = {};
  for (const [name, content] of Object.entries(files)) {
    if (!isSafePath(name)) throw new BridgeError("archive.path", `Unsafe output path ${name}`);
    zippable[name] = typeof content === "string" ? strToU8(content) : content;
  }
  return zipSync(zippable, { level: 6 });
}
