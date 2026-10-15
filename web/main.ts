import { Bridge } from "./adapters/bridge";
import { detectCapabilities } from "./adapters/capabilities";
import { randomIds } from "./adapters/id";
import { registerElements } from "./adapters/elements";
import { registerHandlers } from "./adapters/handlers";
import * as storage from "./adapters/storage";

declare const __APP_VERSION__: string;

interface ElmApp {
  ports: {
    toJs: { subscribe(callback: (value: unknown) => void): void };
    fromJs: { send(value: unknown): void };
  };
}

interface ElmModule {
  Elm: { Main: { init(options: { node: HTMLElement; flags: unknown }): ElmApp } };
}

async function boot(): Promise<void> {
  registerElements();
  const { Elm } = (await import("../src/Main.elm")) as unknown as ElmModule;
  const capabilities = await detectCapabilities();
  const [preferences, layout] = await Promise.all([
    storage.getSetting("preferences"),
    storage.getSetting("layout"),
  ]);
  let recents: unknown[] = [];
  let recoveries: unknown[] = [];
  try {
    const projects = await storage.listProjects();
    recents = projects.map(toRecent);
    recoveries = storage.recoveriesFrom(projects);
  } catch {
    // storage unavailable; the app still runs
  }
  const base = import.meta.env.BASE_URL || "/";
  const node = document.getElementById("app");
  if (!node) throw new Error("Missing #app");
  const app = Elm.Main.init({
    node,
    flags: {
      basePath: base,
      isMac: /Mac|iPhone|iPad/.test(navigator.platform) || /Mac OS/.test(navigator.userAgent),
      ids: randomIds(256),
      capabilities,
      preferences: preferences ?? null,
      layout: layout ?? null,
      recents,
      recoveries,
      now: Date.now(),
      reducedMotion: window.matchMedia("(prefers-reduced-motion: reduce)").matches,
      version: typeof __APP_VERSION__ === "string" ? __APP_VERSION__ : "dev",
    },
  });
  const bridge = new Bridge(app.ports);
  registerHandlers(bridge);
  wireWindowEvents(bridge);
  registerServiceWorker(bridge, base);
}

export function toRecent(p: storage.ProjectRecord): unknown {
  return {
    documentId: p.documentId,
    name: p.name,
    width: p.width,
    height: p.height,
    sceneCount: p.sceneCount,
    modifiedAt: p.modifiedAt,
    revision: p.revision,
    hasAutosave: true,
    fileName: p.fileName,
  };
}

let dirty = false;

export function setDirty(value: boolean): void {
  dirty = value;
}

const PRIMARY_SHORTCUT_KEYS = new Set([
  "z",
  "y",
  "s",
  "e",
  "o",
  "n",
  "k",
  "d",
  "a",
  "g",
  "f",
  "w",
  "l",
  "p",
  "i",
  "h",
  "j",
  "[",
  "]",
  "=",
  "-",
  "0",
  "1",
  "2",
  "7",
  "'",
  ";",
  "/",
  ",",
  "enter",
]);

function isEditable(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  const tag = target.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || target.isContentEditable;
}

/**
 * Stop the browser's own handling of shortcuts the editor owns (native undo in
 * the last-edited text field, Save Page, Open File, page scrolling on arrows
 * and Space over the canvas). Elm receives the same keydown through its
 * subscription and decides what the shortcut does.
 */
function preventBrowserShortcuts(): void {
  document.addEventListener(
    "keydown",
    (event) => {
      if (isEditable(event.target)) return;
      const primary = event.metaKey || event.ctrlKey;
      const key = event.key.toLowerCase();
      if (primary && PRIMARY_SHORTCUT_KEYS.has(key)) {
        event.preventDefault();
        return;
      }
      const target = event.target as HTMLElement | null;
      const onCanvas = target?.id === "fw-canvas" || target?.closest?.(".timeline") !== null;
      if (onCanvas && (key === " " || key.startsWith("arrow") || key === "home" || key === "end"))
        event.preventDefault();
    },
    { capture: true },
  );
}

function wireWindowEvents(bridge: Bridge): void {
  preventBrowserShortcuts();
  window.addEventListener("beforeunload", (event) => {
    if (dirty) {
      event.preventDefault();
      event.returnValue = "";
    }
  });
  document.addEventListener("visibilitychange", () => {
    bridge.emit("event.visibility", { hidden: document.hidden });
  });
  // drag and drop of files anywhere in the window
  let dragDepth = 0;
  window.addEventListener("dragenter", (event) => {
    if (event.dataTransfer && Array.from(event.dataTransfer.types).includes("Files")) {
      dragDepth += 1;
      bridge.emit("event.dragOverlay", { active: true });
    }
  });
  window.addEventListener("dragleave", () => {
    dragDepth = Math.max(0, dragDepth - 1);
    if (dragDepth === 0) bridge.emit("event.dragOverlay", { active: false });
  });
  window.addEventListener("dragover", (event) => {
    event.preventDefault();
  });
  window.addEventListener("drop", (event) => {
    event.preventDefault();
    dragDepth = 0;
    bridge.emit("event.dragOverlay", { active: false });
    const file = event.dataTransfer?.files?.[0];
    if (file) void import("./adapters/handlers").then((m) => m.handleDroppedFile(bridge, file));
  });
}

function registerServiceWorker(bridge: Bridge, base: string): void {
  if (!("serviceWorker" in navigator) || !import.meta.env.PROD) return;
  navigator.serviceWorker
    .register(`${base}sw.js`)
    .then((registration) => {
      if (registration.active) bridge.emit("event.offlineReady", {});
      registration.addEventListener("updatefound", () => {
        const worker = registration.installing;
        worker?.addEventListener("statechange", () => {
          if (worker.state === "activated") bridge.emit("event.offlineReady", {});
        });
      });
    })
    .catch(() => {
      // offline support is optional
    });
}

void boot();
