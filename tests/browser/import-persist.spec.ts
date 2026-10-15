import { expect, test } from "@playwright/test";
import { fileURLToPath } from "node:url";
import { layerNames, layerRow, openApp, newDocument, primary } from "./helpers";

const fixtures = fileURLToPath(new URL("../fixtures/svg/", import.meta.url));

test.describe("import and persistence", () => {
  test("imports a nested SVG as editable layers and keeps it after reload", async ({ page }) => {
    await openApp(page);
    await newDocument(page);
    const chooser = page.waitForEvent("filechooser");
    await page.getByRole("menuitem", { name: "File" }).click();
    await page.getByRole("menuitem", { name: "Import SVG…" }).click();
    await (await chooser).setFiles(fixtures + "nested.svg");
    await expect(page.getByRole("dialog", { name: "Import Review" })).toBeVisible();
    await page.getByRole("button", { name: "Import Supported" }).click();
    await expect(page.locator(".layer-tree")).toContainText("nested");
    await page.getByRole("menuitem", { name: "Layer" }).click();
    await page.getByRole("menuitem", { name: "Expand All" }).click();
    await expect
      .poll(() => layerNames(page))
      .toEqual(expect.arrayContaining(["logo", "box", "dot", "label"]));
    // select an imported layer, move it, undo, redo
    await layerRow(page, "box").click();
    const sel = (await page.locator(".selection-outline").boundingBox())!;
    await page.mouse.move(sel.x + sel.width / 2, sel.y + sel.height / 2);
    await page.mouse.down();
    await page.mouse.move(sel.x + sel.width / 2 + 60, sel.y + sel.height / 2, { steps: 5 });
    await page.mouse.up();
    const xField = page.locator('input[aria-label="X"]').first();
    const moved = Number(await xField.inputValue());
    await page.locator("#fw-canvas").click({ position: { x: 12, y: 12 } });
    await layerRow(page, "box").click();
    await page.keyboard.press(`${await primary(page)}+z`);
    await expect.poll(async () => Number(await xField.inputValue())).not.toBe(moved);
    // autosave then reload: the document comes back from IndexedDB
    await page.waitForTimeout(2200);
    await expect(page.locator(".save-status")).toContainText("Autosaved");
    const url = page.url();
    await page.reload();
    await expect(page).toHaveURL(url);
    await expect(page.locator(".layer-tree")).toContainText("nested");
  });

  test("a hostile SVG never executes and leaves no executable residue", async ({ page }) => {
    await openApp(page);
    await newDocument(page);
    let dialogs = 0;
    page.on("dialog", (d) => {
      dialogs += 1;
      void d.dismiss();
    });
    const requests: string[] = [];
    page.on("request", (r) => {
      if (/evil\.example/.test(r.url())) requests.push(r.url());
    });
    const chooser = page.waitForEvent("filechooser");
    await page.getByRole("menuitem", { name: "File" }).click();
    await page.getByRole("menuitem", { name: "Import SVG…" }).click();
    await (await chooser).setFiles(fixtures + "hostile.svg");
    await expect(page.getByRole("dialog", { name: "Import Review" })).toBeVisible();
    await expect(page.getByRole("dialog", { name: "Import Review" })).toContainText("<script>");
    await page.getByRole("button", { name: "Import Supported" }).click();
    await expect(page.locator(".layer-tree")).toContainText("hostile");
    await page.getByRole("menuitem", { name: "Layer" }).click();
    await page.getByRole("menuitem", { name: "Expand All" }).click();
    await expect(page.locator(".layer-tree")).toContainText("safe");
    const html = await page.locator("#fw-canvas").innerHTML();
    expect(html).not.toMatch(/<script|onload|onclick|evil\.example|javascript:/i);
    const download = page.waitForEvent("download");
    await page.getByRole("button", { name: "Export", exact: true }).first().click();
    await page.getByRole("radio", { name: "Static SVG" }).click();
    await page.locator(".export-actions").getByRole("button", { name: "Export" }).click();
    const { readFileSync } = await import("node:fs");
    const exported = readFileSync((await (await download).path())!, "utf8");
    expect(exported).not.toMatch(/<script|onload|onclick|evil\.example|javascript:/i);
    expect(dialogs).toBe(0);
    expect(requests).toEqual([]);
  });

  test("reopening a saved .framewise file restores keys and easing", async ({ page }) => {
    await openApp(page);
    await page.getByRole("button", { name: /Logo reveal/ }).click();
    const download = page.waitForEvent("download");
    await page.getByRole("button", { name: "Save", exact: true }).first().click();
    const file = await download;
    const path = (await file.path())!;
    // close and open from file
    await page.getByRole("button", { name: /Close Logo reveal/ }).click();
    await expect(page.getByRole("heading", { name: "Framewise" })).toBeVisible();
    const chooser = page.waitForEvent("filechooser");
    await page.getByRole("button", { name: "Open File" }).click();
    await (await chooser).setFiles(path);
    await page.getByRole("menuitem", { name: "Layer" }).click();
    await page.getByRole("menuitem", { name: "Expand All" }).click();
    await expect(page.locator(".layer-tree")).toContainText("Letter A");
    await layerRow(page, "Letter A").click();
    await expect(page.locator(".track-summary")).toContainText("Dash Offset");
    await expect(page.locator(".track-summary")).toContainText("2 keys");
    await expect(page.locator(".save-status")).toContainText("Saved to file");
  });

  test("scene FPS change in preserve-time mode rescales keyframes", async ({ page }) => {
    await openApp(page);
    await page.getByRole("button", { name: /Bouncing ball/ }).click();
    await page.getByRole("menuitem", { name: "File" }).click();
    await page.getByRole("menuitem", { name: "Scene Settings…" }).click();
    const dialog = page.getByRole("dialog", { name: "Scene Settings" });
    // the dialog moves focus to its first field one frame after opening
    await expect(dialog.getByLabel("Name")).toBeFocused();
    await dialog.getByLabel("FPS numerator").fill("60");
    await expect(dialog.locator(".retime-preview")).toContainText("30→60");
    await dialog.getByRole("button", { name: "Apply" }).click();
    await expect(page.locator(".transport")).toContainText("60 fps");
    await expect(page.locator(".transport")).toContainText("120 f");
    await page.getByRole("treeitem", { name: /Ball/ }).first().click();
    await page.locator(".key").first().click();
    await page.getByRole("button", { name: "Next keyframe" }).click();
    await expect(page.locator('.transport input[aria-label="Frame"]')).toHaveValue("60");
  });

  test("second scene and batch export names files per scene", async ({ page }) => {
    await openApp(page);
    await page.getByRole("button", { name: /Bouncing ball/ }).click();
    await page.getByRole("tab", { name: "Scenes" }).click();
    await page.getByRole("button", { name: "New Scene" }).click();
    await expect(page.locator(".scene-list")).toContainText("Scene 2");
    await page.getByRole("button", { name: "Export", exact: true }).first().click();
    await page.getByRole("radio", { name: "Static SVG" }).click();
    await page.getByLabel(/All scenes/).check();
    const waiting = page.waitForEvent("download");
    await page.locator(".export-actions").getByRole("button", { name: "Export" }).click();
    const download = await waiting;
    expect(download.suggestedFilename()).toMatch(/\.zip$/);
    const { unzipSync } = await import("fflate");
    const { readFileSync } = await import("node:fs");
    const files = unzipSync(new Uint8Array(readFileSync((await download.path())!)));
    expect(Object.keys(files).sort()).toEqual(["Bounce.svg", "Scene 2.svg"]);
  });
});
