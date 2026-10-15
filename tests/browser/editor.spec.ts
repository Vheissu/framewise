import { expect, test } from "@playwright/test";
import {
  primary,
  drawRect,
  dragSelection,
  focusCanvas,
  layerNames,
  layerRow,
  newDocument,
  openApp,
  openExample,
  setFrame,
  trackListText,
} from "./helpers";

test.describe("editor", () => {
  test("welcome, new document, draw, change fill, save as download", async ({ page }) => {
    await openApp(page);
    await newDocument(page);
    await drawRect(page, [200, 200], [320, 280]);
    await expect(page.locator(".layer-tree")).toContainText("Rectangle");
    // change the fill through the picker
    await page.getByRole("button", { name: "Fill colour" }).click();
    await page.getByRole("textbox", { name: "Hex colour" }).fill("#ff0000");
    await page.getByRole("button", { name: "Done" }).click();
    await expect(page.locator(".paint-hex").first()).toHaveText("#ff0000");
    await expect(page.locator("#fw-canvas rect[fill='#ff0000']")).toHaveCount(1);
    const download = page.waitForEvent("download");
    await page.getByRole("button", { name: "Save", exact: true }).first().click();
    const file = await download;
    expect(file.suggestedFilename()).toMatch(/\.framewise$/);
    await expect(page.locator(".save-status")).toContainText("Downloaded");
  });

  test("auto-keyframe, scrub, undo and redo", async ({ page }) => {
    await openApp(page);
    await newDocument(page);
    await drawRect(page, [200, 200], [320, 280]);
    await setFrame(page, 15);
    await dragSelection(page, 100, 40);
    await expect.poll(() => trackListText(page)).toContain("Position");
    // frame 0 baseline exists: scrub back and the node is at its original place
    await setFrame(page, 0);
    const xAt0 = await page.locator('input[aria-label="X"]').first().inputValue();
    await setFrame(page, 15);
    const xAt15 = await page.locator('input[aria-label="X"]').first().inputValue();
    expect(Number(xAt15)).toBeGreaterThan(Number(xAt0) + 50);
    await focusCanvas(page);
    await page.keyboard.press(`${await primary(page)}+z`);
    await expect.poll(() => trackListText(page)).not.toContain("Position");
    await page.keyboard.press(`${await primary(page)}+Shift+z`);
    await expect.poll(() => trackListText(page)).toContain("Position");
  });

  test("playback advances the playhead and loops", async ({ page }) => {
    await openApp(page);
    await openExample(page, /Bouncing ball/);
    await page.getByRole("button", { name: "Play", exact: true }).click();
    await page.waitForTimeout(600);
    await page.getByRole("button", { name: "Pause", exact: true }).click();
    const frame = Number(await page.locator('.transport input[aria-label="Frame"]').inputValue());
    expect(frame).toBeGreaterThan(0);
    expect(frame).toBeLessThanOrEqual(60);
  });

  test("group, reorder, hide and lock from the layer panel", async ({ page }) => {
    await openApp(page);
    await newDocument(page);
    await drawRect(page, [100, 100], [180, 160]);
    await drawRect(page, [220, 100], [300, 160]);
    await focusCanvas(page);
    await page.keyboard.press(`${await primary(page)}+a`);
    await page.keyboard.press(`${await primary(page)}+g`);
    await expect.poll(() => layerNames(page)).toEqual(["Group 1", "Rectangle 2", "Rectangle"]);
    await page.getByRole("button", { name: "Hide Rectangle 2" }).click();
    await expect(page.locator(".layer-row.hidden-layer")).toHaveCount(1);
    await page.getByRole("button", { name: "Lock Rectangle 2" }).click();
    await expect(page.locator(".layer-row.locked-layer")).toHaveCount(1);
    await layerRow(page, "Rectangle").click();
    await page.keyboard.press(`${await primary(page)}+]`);
    await expect.poll(() => layerNames(page)).toEqual(["Group 1", "Rectangle", "Rectangle 2"]);
  });

  test("command palette runs commands and reports why one is disabled", async ({ page }) => {
    await openApp(page);
    await newDocument(page);
    await focusCanvas(page);
    await page.keyboard.press(`${await primary(page)}+k`);
    await page.getByRole("textbox", { name: "Search commands" }).fill("ungroup");
    await expect(page.locator(".palette-item").first()).toContainText("Select an object first");
    await page.getByRole("textbox", { name: "Search commands" }).fill("toggle grid");
    await page.keyboard.press("Enter");
    await expect.poll(() => page.locator(".grid-line").count()).toBeGreaterThan(0);
  });

  test("keyboard-only: menus, layer rename, property edit and keyframe", async ({ page }) => {
    await openApp(page);
    await openExample(page, /Loading spinner/);
    await page.getByRole("menuitem", { name: "Edit" }).click();
    await expect(page.getByRole("menuitem", { name: "Select All" })).toBeVisible();
    await page.getByRole("menuitem", { name: "Select All" }).click();
    await expect(page.locator(".statusbar")).toContainText("2 selected");
    await layerRow(page, "Ring").click();
    await page.keyboard.press("Enter");
    await expect(page.locator("#layer-rename-input")).toBeFocused();
    await page.keyboard.type("Spinner ring");
    await page.keyboard.press("Enter");
    await expect(page.locator(".layer-tree")).toContainText("Spinner ring");
    const opacity = page.locator('input[aria-label="Opacity"]').first();
    await opacity.fill("50");
    await opacity.press("Enter");
    await expect(page.locator("#fw-canvas g[opacity='0.5']")).toHaveCount(1);
    await page.getByRole("button", { name: /Opacity: add keyframe/ }).click();
    await expect.poll(() => trackListText(page)).toContain("Opacity");
  });
  test("clicking a keyframe selects it without dragging it", async ({ page }) => {
    await openApp(page);
    await openExample(page, /Bouncing ball/);
    const key = page.locator(".key").first();
    const before = await key.getAttribute("title");
    await key.click();
    await expect(page.locator(".key.selected")).toHaveCount(1);
    // moving away after the click must not carry the key along
    const box = await page.locator(".timeline-tracks").boundingBox();
    if (!box) throw new Error("no track area");
    await page.mouse.move(box.x + box.width * 0.7, box.y + 30, { steps: 5 });
    await expect(page.locator(".key").first()).toHaveAttribute("title", before ?? "");
  });

  test("dragging sideways on a value scrubs it", async ({ page }) => {
    await openApp(page);
    await newDocument(page);
    await drawRect(page, [200, 200], [320, 280]);
    const x = page.locator('input[aria-label="X"]').first();
    const start = Number(await x.inputValue());
    const box = await x.boundingBox();
    if (!box) throw new Error("no X field");
    await page.mouse.move(box.x + 6, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + 6 + 33, box.y + box.height / 2, { steps: 11 });
    await page.mouse.up();
    await expect.poll(async () => Number(await x.inputValue())).toBeGreaterThan(start + 5);
    await expect(x).not.toBeFocused();
  });
});
