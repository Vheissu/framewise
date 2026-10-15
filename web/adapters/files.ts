import { BridgeError } from "./protocol";

/**
 * File access. Native pickers are a progressive enhancement; the fallback is
 * `<input type="file">` and Blob downloads. Writable handles never leave
 * this module: Elm sees an opaque token.
 */

interface FileSystemWritableFileStreamLike {
  write(data: Uint8Array | Blob): Promise<void>;
  close(): Promise<void>;
}

interface FileSystemFileHandleLike {
  name: string;
  getFile(): Promise<File>;
  createWritable(): Promise<FileSystemWritableFileStreamLike>;
  queryPermission?(descriptor: {
    mode: "readwrite" | "read";
  }): Promise<"granted" | "denied" | "prompt">;
  requestPermission?(descriptor: {
    mode: "readwrite" | "read";
  }): Promise<"granted" | "denied" | "prompt">;
}

type PickerWindow = Window & {
  showOpenFilePicker?: (options: unknown) => Promise<FileSystemFileHandleLike[]>;
  showSaveFilePicker?: (options: unknown) => Promise<FileSystemFileHandleLike>;
};

const handles = new Map<string, FileSystemFileHandleLike>();
let handleCounter = 0;

function storeHandle(handle: FileSystemFileHandleLike): string {
  handleCounter += 1;
  const token = `fh_${handleCounter}_${Math.random().toString(36).slice(2, 8)}`;
  handles.set(token, handle);
  return token;
}

export interface OpenedFile {
  file: File;
  token: string | null;
}

export const ACCEPT = {
  document: { description: "Framewise document", accept: { "application/zip": [".framewise"] } },
  svg: { description: "SVG image", accept: { "image/svg+xml": [".svg"] } },
  image: {
    description: "Image",
    accept: { "image/png": [".png"], "image/jpeg": [".jpg", ".jpeg"], "image/webp": [".webp"] },
  },
  any: {
    description: "Framewise, SVG or image",
    accept: {
      "application/zip": [".framewise"],
      "image/svg+xml": [".svg"],
      "image/png": [".png"],
      "image/jpeg": [".jpg", ".jpeg"],
      "image/webp": [".webp"],
    },
  },
};

export async function openFile(kind: keyof typeof ACCEPT): Promise<OpenedFile> {
  const w = window as PickerWindow;
  if (typeof w.showOpenFilePicker === "function") {
    try {
      const [handle] = await w.showOpenFilePicker({ multiple: false, types: [ACCEPT[kind]] });
      if (!handle) throw new BridgeError("cancelled", "No file chosen");
      const file = await handle.getFile();
      return { file, token: kind === "document" ? storeHandle(handle) : null };
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError")
        throw new BridgeError("cancelled", "Open cancelled");
      if (error instanceof BridgeError) throw error;
      // fall through to the input element
    }
  }
  return new Promise((resolve, reject) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = Object.values(ACCEPT[kind].accept).flat().join(",");
    input.style.display = "none";
    document.body.appendChild(input);
    const cleanup = () => input.remove();
    input.addEventListener("change", () => {
      const file = input.files && input.files[0];
      cleanup();
      if (!file) reject(new BridgeError("cancelled", "Open cancelled"));
      else resolve({ file, token: null });
    });
    input.addEventListener("cancel", () => {
      cleanup();
      reject(new BridgeError("cancelled", "Open cancelled"));
    });
    input.click();
  });
}

export interface SaveResult {
  mode: "written" | "downloaded";
  fileName: string;
  fileToken: string | null;
}

/**
 * Save bytes. `mode` "save" reuses the token's handle when still writable;
 * "saveAs" and "copy" always ask for a destination.
 */
export async function saveBytes(
  bytes: Uint8Array,
  suggestedName: string,
  mode: "save" | "saveAs" | "copy",
  token: string | null,
): Promise<SaveResult> {
  const w = window as PickerWindow;
  if (typeof w.showSaveFilePicker === "function") {
    let handle: FileSystemFileHandleLike | null = null;
    if (mode === "save" && token) {
      const existing = handles.get(token);
      if (existing) {
        const permission = existing.queryPermission
          ? await existing.queryPermission({ mode: "readwrite" })
          : "granted";
        if (permission === "granted") handle = existing;
        else if (permission === "prompt" && existing.requestPermission) {
          const granted = await existing.requestPermission({ mode: "readwrite" });
          if (granted === "granted") handle = existing;
        }
      }
    }
    if (!handle) {
      try {
        handle = await w.showSaveFilePicker({ suggestedName, types: [ACCEPT.document] });
      } catch (error) {
        if (error instanceof DOMException && error.name === "AbortError")
          throw new BridgeError("cancelled", "Save cancelled");
        throw new BridgeError("file.denied", "The browser refused access to the file", true);
      }
    }
    try {
      const writable = await handle.createWritable();
      await writable.write(bytes);
      await writable.close();
    } catch (error) {
      throw new BridgeError(
        "file.write",
        error instanceof Error ? error.message : "Writing the file failed",
        true,
      );
    }
    // verify the write landed
    const written = await handle.getFile();
    if (written.size !== bytes.byteLength)
      throw new BridgeError("file.verify", "The written file size does not match", true);
    return {
      mode: "written",
      fileName: handle.name,
      fileToken: mode === "copy" ? token : storeHandle(handle),
    };
  }
  downloadBlob(new Blob([bytes as BlobPart], { type: "application/zip" }), suggestedName);
  return { mode: "downloaded", fileName: suggestedName, fileToken: null };
}

export function downloadBlob(blob: Blob, fileName: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = sanitizeFileName(fileName);
  a.rel = "noopener";
  a.style.display = "none";
  document.body.appendChild(a);
  a.click();
  setTimeout(() => {
    a.remove();
    URL.revokeObjectURL(url);
  }, 2000);
}

export function sanitizeFileName(name: string): string {
  const cleaned = name
    .replace(/[\\/:*?"<>|\u0000-\u001f]/g, "-")
    .replace(/\.\.+/g, ".")
    .trim();
  return cleaned.length ? cleaned.slice(0, 180) : "framewise-export";
}

export async function readFileBytes(file: File, maxBytes: number): Promise<Uint8Array> {
  if (file.size > maxBytes)
    throw new BridgeError(
      "file.tooLarge",
      `${file.name} is larger than the ${Math.round(maxBytes / 1048576)} MB limit`,
    );
  return new Uint8Array(await file.arrayBuffer());
}
