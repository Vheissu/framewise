import { expect, test, type Page } from "@playwright/test";
import { layerRow, openApp, openExample, primary, setFrame } from "./helpers";

async function frameValue(page: Page): Promise<number> {
  return Number(await page.locator('.transport input[aria-label="Frame"]').inputValue());
}

/** Client x of a frame on the ruler, read from the rendered keyframe or tick. */
async function centreX(page: Page, selector: string): Promise<number> {
  const box = (await page.locator(selector).first().boundingBox())!;
  return box.x + box.width / 2;
}

async function drag(page: Page, from: [number, number], to: [number, number], shift = false) {
  if (shift) await page.keyboard.down("Shift");
  await page.mouse.move(from[0], from[1]);
  await page.mouse.down();
  await page.mouse.move(to[0], to[1], { steps: 8 });
  await page.mouse.up();
  if (shift) await page.keyboard.up("Shift");
}

test.describe("timeline", () => {
  test.beforeEach(async ({ page }) => {
    await openApp(page);
    await openExample(page, /Illustrated scene/);
  });

  test("moving the mouse after a click does not scrub", async ({ page }) => {
    const ruler = (await page.locator(".ruler-row").boundingBox())!;
    const y = ruler.y + ruler.height - 6;
    await page.mouse.click(ruler.x + 120, y);
    const clicked = await frameValue(page);
    await page.mouse.move(ruler.x + 400, y, { steps: 6 });
    expect(await frameValue(page)).toBe(clicked);

    // a press whose release never reaches the page (a native context menu
    // swallows it, or the button comes up outside the window) must not
    // leave the playhead following the pointer
    await page.locator(".ruler-row").dispatchEvent("pointerdown", {
      clientX: ruler.x + 200,
      clientY: y,
      button: 0,
      bubbles: true,
    });
    const pressed = await frameValue(page);
    await page.mouse.move(ruler.x + 450, y, { steps: 6 });
    expect(await frameValue(page)).toBe(pressed);
    await expect(page.locator(".playhead-label")).toHaveCount(0);
  });

  test("drag on the work area strip sets, slides and clears a range", async ({ page }) => {
    const strip = (await page.locator(".range-strip").boundingBox())!;
    const y = strip.y + strip.height / 2;
    await expect(page.locator(".range-bar")).toHaveCount(0);

    await drag(page, [strip.x + 100, y], [strip.x + 300, y]);
    const bar = page.locator(".range-bar");
    await expect(bar).toHaveCount(1);
    const before = (await bar.boundingBox())!;
    expect(before.width).toBeGreaterThan(150);
    await expect(page.locator(".range-shade")).toHaveCount(2);

    // grab the middle and slide it left; the length stays the same
    await drag(page, [before.x + before.width / 2, y], [before.x + before.width / 2 - 60, y]);
    const after = (await bar.boundingBox())!;
    expect(after.x).toBeLessThan(before.x - 40);
    expect(Math.abs(after.width - before.width)).toBeLessThan(2);

    // trim the end edge
    await drag(page, [after.x + after.width - 1, y], [after.x + after.width + 50, y]);
    expect((await bar.boundingBox())!.width).toBeGreaterThan(after.width + 30);

    await page.mouse.dblclick(after.x + 20, y);
    await expect(page.locator(".range-bar")).toHaveCount(0);
  });

  test("B and N set the range ends at the playhead", async ({ page }) => {
    const field = page.locator('.transport input[aria-label="Frame"]');
    await field.fill("20");
    await field.press("Enter");
    await field.blur();
    await page.keyboard.press("b");
    await field.fill("50");
    await field.press("Enter");
    await field.blur();
    await page.keyboard.press("n");
    await expect(page.locator(".range-bar")).toHaveCount(1);
    await expect(page.getByText("Work range 20–50")).toBeVisible();
  });

  test("the playhead can be grabbed in the lanes and Shift snaps to keys", async ({ page }) => {
    const lanes = (await page.locator(".track-area-rows").boundingBox())!;
    const playhead = await centreX(page, ".playhead-grip");
    const y = lanes.y + lanes.height - 6;
    await drag(page, [playhead, y], [playhead + 200, y]);
    const scrubbed = await frameValue(page);
    expect(scrubbed).toBeGreaterThan(10);
    await expect(page.locator(".playhead-label")).toHaveCount(0);

    // a key sits at frame 45 on Near hill; land a few pixels to its right
    const key = await centreX(page, '.key[title*="@ 45"]');
    const ruler = (await page.locator(".ruler-row").boundingBox())!;
    const rulerY = ruler.y + ruler.height - 6;
    await drag(page, [key + 40, rulerY], [key + 5, rulerY]);
    expect(await frameValue(page)).not.toBe(45);
    await drag(page, [key + 40, rulerY], [key + 5, rulerY], true);
    expect(await frameValue(page)).toBe(45);
  });

  test("dragging on empty lanes selects the keys inside the box", async ({ page }) => {
    const key = (await page.locator('.key[title*="@ 45"]').boundingBox())!;
    await drag(page, [key.x - 30, key.y - 6], [key.x + 30, key.y + key.height + 6]);
    await expect(page.locator(".key.selected")).toHaveCount(1);
    await expect(page.locator(".key-marquee")).toHaveCount(0);
    // a click on empty lanes clears the selection
    await page.mouse.click(key.x - 30, key.y - 6);
    await expect(page.locator(".key.selected")).toHaveCount(0);
  });

  test("scrubbing past the edge scrolls the timeline", async ({ page }) => {
    const zoomIn = page.getByRole("button", { name: "Zoom timeline in" });
    for (let i = 0; i < 5; i++) await zoomIn.click();
    const tracks = (await page.locator(".timeline-tracks").boundingBox())!;
    const y = (await page.locator(".ruler-row").boundingBox())!.y + 24;
    await page.mouse.move(tracks.x + 40, y);
    await page.mouse.down();
    await page.mouse.move(tracks.x + tracks.width - 2, y, { steps: 6 });
    const atEdge = await frameValue(page);
    await page.mouse.move(tracks.x + tracks.width + 60, y, { steps: 2 });
    await expect.poll(() => frameValue(page)).toBeGreaterThan(atEdge + 5);
    await page.mouse.up();
    await expect(page.locator(".playhead-label")).toHaveCount(0);
  });

  test("split a layer at the playhead, then trim and move its halves", async ({ page }) => {
    const sunBar = page.locator(".layer-bar").first();
    await expect(sunBar).toHaveAttribute("title", /^In 0 · Out 90/);
    const box = (await sunBar.boundingBox())!;
    await page.mouse.click(box.x + 40, box.y + box.height / 2);
    await setFrame(page, 45);
    await page.keyboard.press(`${await primary(page)}+Shift+d`);
    const titles = () =>
      page
        .locator(".layer-bar")
        .evaluateAll((els) => els.map((e) => e.getAttribute("title")!.split(".")[0]));
    await expect.poll(titles).toEqual(expect.arrayContaining(["In 0 · Out 45", "In 45 · Out 90"]));

    // the copy is selected: trim its end at 70, then move its start to 30
    await setFrame(page, 70);
    await page.keyboard.press("Alt+BracketRight");
    await expect.poll(titles).toContain("In 45 · Out 70");
    await setFrame(page, 30);
    await page.keyboard.press("BracketLeft");
    await expect.poll(titles).toContain("In 30 · Out 55");

    // undo walks back one step at a time
    await page.keyboard.press(`${await primary(page)}+z`);
    await expect.poll(titles).toContain("In 45 · Out 70");
  });

  test("with the timeline focused, S splits, Q trims before the playhead and W after", async ({
    page,
  }) => {
    const sunBar = page.locator(".layer-bar").first();
    const box = (await sunBar.boundingBox())!;
    await page.mouse.click(box.x + 40, box.y + box.height / 2);
    const titles = () =>
      page
        .locator(".layer-bar")
        .evaluateAll((els) => els.map((e) => e.getAttribute("title")!.split(".")[0]));

    await setFrame(page, 40);
    await page.keyboard.press("s");
    await expect.poll(titles).toEqual(expect.arrayContaining(["In 0 · Out 40", "In 40 · Out 90"]));
    await setFrame(page, 60);
    await page.keyboard.press("w");
    await expect.poll(titles).toContain("In 40 · Out 60");
    await setFrame(page, 50);
    await page.keyboard.press("q");
    await expect.poll(titles).toContain("In 50 · Out 60");

    // outside the timeline the letters leave layer timing alone
    const before = await titles();
    await setFrame(page, 55);
    await layerRow(page, "Bouncy").locator(".layer-name").click();
    await page.keyboard.press("s");
    await page.keyboard.press("w");
    await page.keyboard.press("q");
    expect(await titles()).toEqual(before);
  });

  test("dragging a layer bar moves its keys; dragging its end trims it", async ({ page }) => {
    const bouncy = page.locator(".layer-bar").nth(2);
    const key = page.locator('.key[title^="Position @"]').last();
    const before = await key.getAttribute("title");
    const bar = (await bouncy.boundingBox())!;
    const y = bar.y + bar.height / 2;
    const frameWidth = bar.width / 90;
    await drag(page, [bar.x + bar.width / 2, y], [bar.x + bar.width / 2 + frameWidth * 10, y]);
    await expect(bouncy).toHaveAttribute("title", /^In 10 · Out 100/);
    expect(await key.getAttribute("title")).not.toBe(before);

    const moved = (await bouncy.boundingBox())!;
    await drag(page, [moved.x + 2, y], [moved.x + 2 + frameWidth * 5, y]);
    await expect(bouncy).toHaveAttribute("title", /^In 15 · Out 100/);
  });

  test("the filmstrip shows more frames as the timeline zooms in", async ({ page }) => {
    const frames = page.locator(".film-frame");
    await expect(frames.first()).toBeVisible();
    await expect(frames.first().locator("svg")).toHaveCount(1);
    const framesPerThumb = async () => {
      const a = Number(await frames.nth(0).getAttribute("data-frame"));
      const b = Number(await frames.nth(1).getAttribute("data-frame"));
      return b - a;
    };
    const zoomedOut = await framesPerThumb();
    for (let i = 0; i < 8; i++)
      await page.getByRole("button", { name: "Zoom timeline in" }).click();
    await expect.poll(framesPerThumb).toBeLessThan(zoomedOut);
    await page.getByRole("button", { name: "Frame thumbnails" }).click();
    await expect(frames).toHaveCount(0);
  });
});
