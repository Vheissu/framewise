import { BridgeError } from "./protocol";

/**
 * IndexedDB persistence. Stores:
 *  - projects: latest working copy + metadata per document
 *  - revisions: rotating autosave checkpoints
 *  - saved: the document as it was at the last explicit file save (for Revert)
 *  - assets: content-addressed binaries
 *  - settings: preferences, layout and misc key/values
 */

const DB_NAME = "framewise-db";
const DB_VERSION = 1;
const CHECKPOINTS_PER_DOCUMENT = 5;

export interface ProjectRecord {
  documentId: string;
  name: string;
  width: number;
  height: number;
  sceneCount: number;
  modifiedAt: number;
  revision: number;
  savedRevision: number | null;
  fileName: string | null;
  thumbnail: string | null;
  document: unknown;
  assetIds: string[];
}

export interface RevisionRecord {
  key: string;
  documentId: string;
  revision: number;
  checkpointAt: number;
  document: unknown;
  savedRevision: number | null;
  byteLength: number;
}

export interface AssetRecord {
  sha256: string;
  blob: Blob;
  mimeType: string;
  byteLength: number;
  name: string;
  width: number;
  height: number;
}

let dbPromise: Promise<IDBDatabase> | null = null;

export function openDatabase(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    if (typeof indexedDB === "undefined") {
      reject(new BridgeError("storage.unavailable", "IndexedDB is not available in this browser"));
      return;
    }
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains("projects"))
        db.createObjectStore("projects", { keyPath: "documentId" });
      if (!db.objectStoreNames.contains("revisions")) {
        const store = db.createObjectStore("revisions", { keyPath: "key" });
        store.createIndex("byDocument", "documentId", { unique: false });
      }
      if (!db.objectStoreNames.contains("saved"))
        db.createObjectStore("saved", { keyPath: "documentId" });
      if (!db.objectStoreNames.contains("assets"))
        db.createObjectStore("assets", { keyPath: "sha256" });
      if (!db.objectStoreNames.contains("settings")) db.createObjectStore("settings");
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(toBridgeError(request.error));
    request.onblocked = () =>
      reject(
        new BridgeError(
          "storage.blocked",
          "The database is open in another tab with an older version",
        ),
      );
  });
  return dbPromise;
}

function toBridgeError(error: DOMException | null): BridgeError {
  if (error && error.name === "QuotaExceededError") {
    return new BridgeError(
      "storage.quota",
      "Browser storage is full. Save a copy to a file and free up space.",
      true,
    );
  }
  return new BridgeError("storage.error", error?.message ?? "Storage error", true);
}

function tx<T>(
  db: IDBDatabase,
  stores: string[],
  mode: IDBTransactionMode,
  work: (t: IDBTransaction) => IDBRequest<T> | void,
): Promise<T> {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(stores, mode);
    let result: T | undefined;
    const request = work(transaction);
    if (request) {
      request.onsuccess = () => {
        result = request.result;
      };
    }
    transaction.oncomplete = () => resolve(result as T);
    transaction.onerror = () => reject(toBridgeError(transaction.error));
    transaction.onabort = () => reject(toBridgeError(transaction.error));
  });
}

function requestToPromise<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(toBridgeError(request.error));
  });
}

export async function getSetting<T>(key: string): Promise<T | undefined> {
  try {
    const db = await openDatabase();
    return await tx<T | undefined>(
      db,
      ["settings"],
      "readonly",
      (t) => t.objectStore("settings").get(key) as IDBRequest<T | undefined>,
    );
  } catch {
    return undefined;
  }
}

export async function putSetting(key: string, value: unknown): Promise<void> {
  const db = await openDatabase();
  await tx(db, ["settings"], "readwrite", (t) => {
    t.objectStore("settings").put(value, key);
  });
}

/** Autosave: write the project record and a rotating checkpoint atomically. */
export async function autosave(
  record: Omit<ProjectRecord, "assetIds">,
  assetIds: string[],
): Promise<void> {
  const db = await openDatabase();
  const json = JSON.stringify(record.document);
  const revisionRecord: RevisionRecord = {
    key: `${record.documentId}:${String(record.revision).padStart(9, "0")}`,
    documentId: record.documentId,
    revision: record.revision,
    checkpointAt: record.modifiedAt,
    document: record.document,
    savedRevision: record.savedRevision,
    byteLength: json.length,
  };
  const existing = await listRevisions(record.documentId);
  await tx(db, ["projects", "revisions"], "readwrite", (t) => {
    t.objectStore("projects").put({ ...record, assetIds });
    const revisions = t.objectStore("revisions");
    revisions.put(revisionRecord);
    // rotate: keep the newest N plus the last known good saved checkpoint
    const stale = existing
      .filter((r) => r.revision !== record.revision)
      .sort((a, b) => b.revision - a.revision)
      .slice(CHECKPOINTS_PER_DOCUMENT - 1)
      .filter((r) => r.revision !== record.savedRevision);
    for (const r of stale) revisions.delete(r.key);
  });
}

export async function listRevisions(documentId: string): Promise<RevisionRecord[]> {
  const db = await openDatabase();
  return tx<RevisionRecord[]>(
    db,
    ["revisions"],
    "readonly",
    (t) =>
      t.objectStore("revisions").index("byDocument").getAll(documentId) as IDBRequest<
        RevisionRecord[]
      >,
  );
}

export async function getProject(documentId: string): Promise<ProjectRecord | undefined> {
  const db = await openDatabase();
  return tx<ProjectRecord | undefined>(
    db,
    ["projects"],
    "readonly",
    (t) => t.objectStore("projects").get(documentId) as IDBRequest<ProjectRecord | undefined>,
  );
}

export async function listProjects(): Promise<ProjectRecord[]> {
  const db = await openDatabase();
  const all = await tx<ProjectRecord[]>(
    db,
    ["projects"],
    "readonly",
    (t) => t.objectStore("projects").getAll() as IDBRequest<ProjectRecord[]>,
  );
  return all.sort((a, b) => b.modifiedAt - a.modifiedAt);
}

export async function deleteProject(documentId: string, recoveryOnly: boolean): Promise<void> {
  const db = await openDatabase();
  const revisions = await listRevisions(documentId);
  await tx(db, ["projects", "revisions", "saved"], "readwrite", (t) => {
    for (const r of revisions) t.objectStore("revisions").delete(r.key);
    if (recoveryOnly) {
      // Keep the project but mark it as matching its saved revision so it no
      // longer shows as a recovery candidate.
      const store = t.objectStore("projects");
      const get = store.get(documentId);
      get.onsuccess = () => {
        const record = get.result as ProjectRecord | undefined;
        if (record && record.savedRevision !== null) {
          store.put({ ...record, revision: record.savedRevision });
        }
      };
    } else {
      t.objectStore("projects").delete(documentId);
      t.objectStore("saved").delete(documentId);
    }
  });
}

export async function putSavedCopy(
  documentId: string,
  revision: number,
  document: unknown,
): Promise<void> {
  const db = await openDatabase();
  await tx(db, ["saved"], "readwrite", (t) => {
    t.objectStore("saved").put({ documentId, revision, document });
  });
}

export async function getSavedCopy(
  documentId: string,
): Promise<{ documentId: string; revision: number; document: unknown } | undefined> {
  const db = await openDatabase();
  return tx(
    db,
    ["saved"],
    "readonly",
    (t) =>
      t.objectStore("saved").get(documentId) as IDBRequest<
        { documentId: string; revision: number; document: unknown } | undefined
      >,
  );
}

export async function putAsset(asset: AssetRecord): Promise<void> {
  const db = await openDatabase();
  await tx(db, ["assets"], "readwrite", (t) => {
    t.objectStore("assets").put(asset);
  });
}

export async function getAsset(sha256: string): Promise<AssetRecord | undefined> {
  const db = await openDatabase();
  return tx<AssetRecord | undefined>(
    db,
    ["assets"],
    "readonly",
    (t) => t.objectStore("assets").get(sha256) as IDBRequest<AssetRecord | undefined>,
  );
}

export async function clearCategory(category: string): Promise<void> {
  const db = await openDatabase();
  switch (category) {
    case "recents": {
      const projects = await listProjects();
      await tx(db, ["projects", "revisions", "saved"], "readwrite", (t) => {
        for (const p of projects) {
          t.objectStore("projects").delete(p.documentId);
          t.objectStore("saved").delete(p.documentId);
        }
        t.objectStore("revisions").clear();
      });
      return;
    }
    case "recoveries":
      await tx(db, ["revisions"], "readwrite", (t) => {
        t.objectStore("revisions").clear();
      });
      return;
    case "thumbnails": {
      const projects = await listProjects();
      await tx(db, ["projects"], "readwrite", (t) => {
        for (const p of projects) t.objectStore("projects").put({ ...p, thumbnail: null });
      });
      return;
    }
    case "everything":
      await tx(db, ["projects", "revisions", "saved", "assets", "settings"], "readwrite", (t) => {
        for (const name of ["projects", "revisions", "saved", "assets", "settings"])
          t.objectStore(name).clear();
      });
      return;
    default:
      throw new BridgeError("storage.category", `Unknown storage category ${category}`);
  }
}

export async function requestPersistence(): Promise<boolean> {
  if (navigator.storage && typeof navigator.storage.persist === "function") {
    return navigator.storage.persist();
  }
  return false;
}

/** Recovery candidates: projects whose newest autosave is ahead of their last file save. */
export function recoveriesFrom(projects: ProjectRecord[]): Array<{
  documentId: string;
  name: string;
  revision: number;
  savedRevision: number | null;
  checkpointAt: number;
  byteLength: number;
  decodable: boolean;
}> {
  return projects
    .filter((p) => p.savedRevision !== null && p.revision > (p.savedRevision ?? -1))
    .map((p) => ({
      documentId: p.documentId,
      name: p.name,
      revision: p.revision,
      savedRevision: p.savedRevision,
      checkpointAt: p.modifiedAt,
      byteLength: JSON.stringify(p.document).length,
      decodable: typeof p.document === "object" && p.document !== null,
    }));
}

export async function hashBlob(blob: Blob): Promise<string> {
  const buffer = await blob.arrayBuffer();
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

export { requestToPromise };
