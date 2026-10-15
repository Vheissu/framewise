import { expect, type Page } from "@playwright/test";

/** Open the welcome screen with native file pickers disabled so saves become downloads. */
export async function openApp(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const w = window as unknown as Record<string, unknown>;
    delete w.showSaveFilePicker;
    delete w.showOpenFilePicker;
  });
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Framewise" })).toBeVisible();
}

export async function newDocument(page: Page): Promise<void> {
  await page.getByRole("button", { name: "New Document" }).first().click();
  await page.getByRole("button", { name: "Create" }).click();
  await expect(page.locator("#fw-canvas")).toBeVisible();
}

export async function openExample(page: Page, name: RegExp): Promise<void> {
  await page.getByRole("button", { name }).click();
  await expect(page.locator("#fw-canvas")).toBeVisible();
}

export async function focusCanvas(page: Page): Promise<void> {
  await page.locator("#fw-canvas").click({ position: { x: 12, y: 12 } });
}

export async function drawRect(
  page: Page,
  from: [number, number],
  to: [number, number],
): Promise<void> {
  await focusCanvas(page);
  await page.keyboard.press("r");
  const box = (await page.locator("#fw-canvas").boundingBox())!;
  await page.mouse.move(box.x + from[0], box.y + from[1]);
  await page.mouse.down();
  await page.mouse.move(box.x + to[0], box.y + to[1], { steps: 6 });
  await page.mouse.up();
}

export async function setFrame(page: Page, frame: number): Promise<void> {
  const field = page.locator('.transport input[aria-label="Frame"]');
  await field.fill(String(frame));
  await field.press("Enter");
  await field.blur();
}

/** The layer row whose name text matches exactly (button labels are excluded). */
export function layerRow(page: Page, name: string) {
  return page.locator(".layer-row", {
    has: page.locator(".layer-name", { hasText: new RegExp(`^${name}$`) }),
  });
}

export async function dragSelection(page: Page, dx: number, dy: number): Promise<void> {
  const sel = (await page.locator(".selection-outline").boundingBox())!;
  const cx = sel.x + sel.width / 2;
  const cy = sel.y + sel.height / 2;
  await page.mouse.move(cx, cy);
  await page.mouse.down();
  await page.mouse.move(cx + dx, cy + dy, { steps: 8 });
  await page.mouse.up();
}

export async function trackListText(page: Page): Promise<string> {
  return (await page.locator(".track-list").innerText()).replace(/\s+/g, " ");
}

export async function layerNames(page: Page): Promise<string[]> {
  return page.locator(".layer-tree .layer-name").allInnerTexts();
}

/**
 * The primary shortcut modifier as the app will interpret it. Playwright's
 * device profiles can report a Mac user agent on a Linux runner, so ask the
 * page rather than the host OS.
 */
export async function primary(page: Page): Promise<"Meta" | "Control"> {
  const isMac = await page.evaluate(
    () => /Mac|iPhone|iPad/.test(navigator.platform) || /Mac OS/.test(navigator.userAgent),
  );
  return isMac ? "Meta" : "Control";
}
