import { expect, test, type Download } from "@playwright/test";
import { readFileSync } from "node:fs";
import { unzipSync, strFromU8 } from "fflate";
import { openApp, openExample } from "./helpers";

async function downloadBytes(download: Download): Promise<Uint8Array> {
  const path = await download.path();
  return new Uint8Array(readFileSync(path!));
}

async function runExport(page: import("@playwright/test").Page, format: string): Promise<Download> {
  await page.getByRole("button", { name: "Export", exact: true }).first().click();
  await page.getByRole("radio", { name: format }).click();
  const waiting = page.waitForEvent("download");
  await page.locator(".export-actions").getByRole("button", { name: "Export" }).click();
  return waiting;
}

test.describe("exports", () => {
  test("animated SVG contains native SMIL and renders independently", async ({ page, context }) => {
    await openApp(page);
    await openExample(page, /Bouncing ball/);
    await expect(page.locator(".export-studio")).toHaveCount(0);
    const download = await runExport(page, "Animated SVG (SMIL)");
    const text = strFromU8(await downloadBytes(download));
    expect(text).toContain("<animateTransform");
    expect(text).toContain('repeatCount="indefinite"');
    expect(text).not.toContain("<script");
    // open the file in a fresh page with no app code and read the animated element back
    const standalone = await context.newPage();
    await standalone.setContent(text, { waitUntil: "load" });
    const count = await standalone.locator("animateTransform").count();
    expect(count).toBeGreaterThan(0);
    const names = await standalone
      .locator("g[data-fw-name]")
      .evaluateAll((els) => els.map((e) => e.getAttribute("data-fw-name")));
    expect(names).toEqual(expect.arrayContaining(["Ball", "Shadow", "Ground"]));
  });

  test("static SVG is the evaluated still at the chosen frame", async ({ page }) => {
    await openApp(page);
    await openExample(page, /Bouncing ball/);
    await page.getByRole("button", { name: "Export", exact: true }).first().click();
    await page.getByRole("radio", { name: "Static SVG" }).click();
    await page.locator("#export-frame").fill("30");
    const waiting = page.waitForEvent("download");
    await page.locator(".export-actions").getByRole("button", { name: "Export" }).click();
    const text = strFromU8(await downloadBytes(await waiting));
    expect(text).not.toContain("<animate");
    // at frame 30 the ball is at y=280, squashed to 1.15 × 0.85 (see the example definition)
    expect(text).toMatch(/matrix\(1\.15 0 0 0\.85 200 280\)/);
  });

  test("HTML player bundle runs offline with the public API", async ({ page, context }) => {
    await openApp(page);
    await openExample(page, /Bouncing ball/);
    const download = await runExport(page, "HTML + Framewise Player");
    const files = unzipSync(await downloadBytes(download));
    expect(Object.keys(files)).toEqual(
      expect.arrayContaining([
        "index.html",
        "framewise-player.js",
        "animation.json",
        "scene.svg",
        "README.txt",
      ]),
    );
    const html = strFromU8(files["index.html"]!);
    const js = strFromU8(files["framewise-player.js"]!);
    const standalone = await context.newPage();
    await standalone.route("**/*", (route) => route.abort());
    await standalone.setContent(
      html.replace('<script src="framewise-player.js"></script>', `<script>${js}</script>`),
      { waitUntil: "load" },
    );
    const frameAfterSeek = await standalone.evaluate(() => {
      const p = (
        window as unknown as {
          framewisePlayer: {
            pause(): void;
            seekFrame(f: number): void;
            getCurrentFrame(): number;
            getDurationSeconds(): number;
          };
        }
      ).framewisePlayer;
      p.pause();
      p.seekFrame(30);
      return { frame: p.getCurrentFrame(), seconds: p.getDurationSeconds() };
    });
    expect(frameAfterSeek.frame).toBe(30);
    expect(frameAfterSeek.seconds).toBe(2);
    const transform = await standalone.locator("g[data-fw-name='Ball']").getAttribute("transform");
    expect(transform).toMatch(/matrix\(1\.15 0 0 0\.85 200 280\)/);
  });

  test("PNG sequence has the right count, order and dimensions", async ({ page }) => {
    await openApp(page);
    await openExample(page, /Loading spinner/);
    await page.getByRole("button", { name: "Export", exact: true }).first().click();
    await page.getByRole("radio", { name: "PNG sequence (ZIP)" }).click();
    await page.locator("#export-start").fill("0");
    await page.locator("#export-end").fill("4");
    const waiting = page.waitForEvent("download");
    await page.locator(".export-actions").getByRole("button", { name: "Export" }).click();
    const files = unzipSync(await downloadBytes(await waiting));
    const pngs = Object.keys(files)
      .filter((f) => f.endsWith(".png"))
      .sort();
    expect(pngs).toEqual([
      "Spinner_000000.png",
      "Spinner_000001.png",
      "Spinner_000002.png",
      "Spinner_000003.png",
      "Spinner_000004.png",
    ]);
    const manifest = JSON.parse(strFromU8(files["manifest.json"]!)) as {
      frameCount: number;
      width: number;
      height: number;
      fps: { numerator: number };
    };
    expect(manifest).toMatchObject({
      frameCount: 5,
      width: 128,
      height: 128,
      fps: { numerator: 30 },
    });
    const first = files[pngs[0]!]!;
    expect(Array.from(first.slice(0, 8))).toEqual([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    // IHDR width/height big-endian at bytes 16..24
    const w = (first[16]! << 24) | (first[17]! << 16) | (first[18]! << 8) | first[19]!;
    expect(w).toBe(128);
  });

  test("unavailable formats cannot be exported and say why", async ({ page }) => {
    await openApp(page);
    await openExample(page, /Bouncing ball/);
    await page.getByRole("button", { name: "Export", exact: true }).first().click();
    await page.getByRole("radio", { name: "WebM video" }).click();
    await expect(page.locator(".notice.error")).toContainText("not available");
    await expect(
      page.locator(".export-actions").getByRole("button", { name: "Export" }),
    ).toBeDisabled();
  });

  test("CSS export blocks on a path morph until affected tracks are skipped", async ({ page }) => {
    await openApp(page);
    await openExample(page, /Path morph/);
    await page.getByRole("button", { name: "Export", exact: true }).first().click();
    await page.getByRole("radio", { name: "SVG + CSS" }).click();
    await expect(
      page.locator(".export-actions").getByRole("button", { name: "Export" }),
    ).toBeDisabled();
    await expect(page.locator(".export-report")).toContainText("Unsupported");
    await page.getByLabel(/Skip affected tracks/).check();
    const waiting = page.waitForEvent("download");
    await page.locator(".export-actions").getByRole("button", { name: "Export" }).click();
    const files = unzipSync(await downloadBytes(await waiting));
    const svgName = Object.keys(files).find((f) => f.endsWith(".css.svg"))!;
    const text = strFromU8(files[svgName]!);
    expect(text).toContain("@keyframes");
    expect(text).toContain("fill");
    expect(Object.keys(files).some((f) => f.endsWith(".animation.css"))).toBe(true);
    const report = JSON.parse(
      strFromU8(files[Object.keys(files).find((f) => f.endsWith(".report.json"))!]!),
    ) as { unsupported: number };
    expect(report.unsupported).toBeGreaterThan(0);
  });
});
