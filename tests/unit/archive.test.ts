import { describe, expect, it } from "vitest";
import { strToU8, zipSync } from "fflate";
import { buildArchive, isSafePath, readArchive, sha256Hex } from "../../web/adapters/archive";
import { BridgeError } from "../../web/adapters/protocol";

const doc = {
  id: "doc_1",
  schemaVersion: 1,
  metadata: { name: "Test" },
  sceneOrder: [],
  scenes: [],
  assets: [],
};

describe("archive paths", () => {
  it("accepts normal relative paths", () => {
    expect(isSafePath("document.json")).toBe(true);
    expect(isSafePath("assets/sha256-abc.png")).toBe(true);
    expect(isSafePath("Scene 2.svg")).toBe(true);
  });
  it("rejects traversal, absolute and odd paths", () => {
    for (const p of [
      "../x",
      "a/../b",
      "/etc/passwd",
      "a\\b",
      "",
      ".",
      "assets//x",
      "a/./b",
      "x/ /y",
      "a:b",
    ]) {
      expect(isSafePath(p)).toBe(false);
    }
  });
});

describe("archive round trip", () => {
  it("packs and unpacks a document with an asset", async () => {
    const bytes = strToU8("hello png");
    const sha = await sha256Hex(bytes);
    const zip = buildArchive(
      doc,
      "doc_1",
      "0.1.0",
      [{ id: sha, bytes, mimeType: "image/png", sha256: sha }],
      "<svg/>",
    );
    const contents = await readArchive(zip);
    expect(contents.manifest.format).toBe("framewise");
    expect(contents.document).toEqual(doc);
    expect(contents.assets.get(sha)?.bytes).toEqual(bytes);
  });

  it("rejects a tampered asset", async () => {
    const bytes = strToU8("hello png");
    const sha = await sha256Hex(bytes);
    const zip = buildArchive(
      doc,
      "doc_1",
      "0.1.0",
      [{ id: sha, bytes, mimeType: "image/png", sha256: "0".repeat(64) }],
      null,
    );
    await expect(readArchive(zip)).rejects.toMatchObject({ code: "archive.hash" });
  });

  it("rejects archives that are not zips", async () => {
    await expect(readArchive(strToU8("not a zip at all"))).rejects.toMatchObject({
      code: "archive.signature",
    });
  });

  it("rejects path traversal entries", async () => {
    const zip = zipSync({
      "manifest.json": strToU8(JSON.stringify({ format: "framewise", schemaVersion: 1 })),
      "../evil.json": strToU8("{}"),
    });
    await expect(readArchive(zip)).rejects.toMatchObject({ code: "archive.path" });
  });

  it("rejects a newer schema with an explanation", async () => {
    const zip = zipSync({
      "manifest.json": strToU8(
        JSON.stringify({ format: "framewise", schemaVersion: 9, documentPath: "document.json" }),
      ),
      "document.json": strToU8("{}"),
    });
    await expect(readArchive(zip)).rejects.toMatchObject({ code: "archive.newer" });
  });

  it("rejects missing document.json", async () => {
    const zip = zipSync({
      "manifest.json": strToU8(JSON.stringify({ format: "framewise", schemaVersion: 1 })),
    });
    await expect(readArchive(zip)).rejects.toBeInstanceOf(BridgeError);
  });

  it("rejects disallowed asset mime types", async () => {
    const manifest = {
      format: "framewise",
      schemaVersion: 1,
      assets: [
        {
          id: "a",
          path: "assets/x.svg",
          mimeType: "image/svg+xml",
          byteLength: 1,
          sha256: "0".repeat(64),
        },
      ],
    };
    const zip = zipSync({
      "manifest.json": strToU8(JSON.stringify(manifest)),
      "document.json": strToU8("{}"),
      "assets/x.svg": strToU8("x"),
    });
    await expect(readArchive(zip)).rejects.toMatchObject({ code: "archive.asset" });
  });
});
