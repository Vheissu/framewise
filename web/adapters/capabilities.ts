export interface Capabilities {
  nativeFilePickers: boolean;
  indexedDb: boolean;
  clipboardWrite: boolean;
  clipboardRead: boolean;
  offscreenCanvas: boolean;
  webCodecs: boolean;
  serviceWorker: boolean;
  persistentStorage: boolean;
  broadcastChannel: boolean;
  storageEstimate: { usage: number; quota: number } | null;
}

/** Detect real capabilities; never infer from the user agent string. */
export async function detectCapabilities(): Promise<Capabilities> {
  const w = globalThis as unknown as Record<string, unknown>;
  let persisted = false;
  let estimate: { usage: number; quota: number } | null = null;
  try {
    if (navigator.storage && typeof navigator.storage.persisted === "function") {
      persisted = await navigator.storage.persisted();
    }
    if (navigator.storage && typeof navigator.storage.estimate === "function") {
      const e = await navigator.storage.estimate();
      estimate = { usage: Math.round(e.usage ?? 0), quota: Math.round(e.quota ?? 0) };
    }
  } catch {
    // storage API unavailable
  }
  return {
    nativeFilePickers:
      typeof w.showSaveFilePicker === "function" && typeof w.showOpenFilePicker === "function",
    indexedDb: typeof indexedDB !== "undefined",
    clipboardWrite: typeof navigator.clipboard?.writeText === "function",
    clipboardRead: typeof navigator.clipboard?.readText === "function",
    offscreenCanvas: typeof w.OffscreenCanvas === "function",
    webCodecs: typeof w.VideoEncoder === "function",
    serviceWorker: "serviceWorker" in navigator,
    persistentStorage: persisted,
    broadcastChannel: typeof w.BroadcastChannel === "function",
    storageEstimate: estimate,
  };
}
