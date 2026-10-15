// @vitest-environment jsdom
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { sanitiseSvg } from "../../web/adapters/sanitise-svg";
import { importSvg } from "../../web/adapters/svg-import";

const hostile = readFileSync(resolve(__dirname, "../fixtures/svg/hostile.svg"), "utf8");

describe("SVG sanitiser", () => {
  it("strips scripts, handlers, foreignObject, external references and links", () => {
    const { root, removed } = sanitiseSvg(hostile);
    const text = root.outerHTML;
    expect(text).not.toMatch(/<script/i);
    expect(text).not.toMatch(/foreignObject/i);
    expect(text).not.toMatch(/onload|onclick|onerror/i);
    expect(text).not.toMatch(/evil\.example/);
    expect(text).not.toMatch(/javascript:/i);
    expect(root.querySelector("image")).toBeNull();
    expect(root.querySelector("rect[id$='safe']")).not.toBeNull();
    expect(removed.length).toBeGreaterThan(0);
  });

  it("rejects DTDs and entity declarations outright", () => {
    expect(() =>
      sanitiseSvg('<!DOCTYPE svg [<!ENTITY x "y">]><svg xmlns="http://www.w3.org/2000/svg"/>'),
    ).toThrow(/DOCTYPE|entities/);
  });

  it("rejects malformed XML", () => {
    expect(() => sanitiseSvg('<svg xmlns="http://www.w3.org/2000/svg"><rect')).toThrow(
      /well-formed/,
    );
  });

  it("rejects oversized input", () => {
    const big = `<svg xmlns="http://www.w3.org/2000/svg">${"<g/>".repeat(3_000_000)}</svg>`;
    expect(() => sanitiseSvg(big)).toThrow(/limit/);
  });

  it("rejects excessive nesting", () => {
    const deep = `<svg xmlns="http://www.w3.org/2000/svg">${"<g>".repeat(200)}${"</g>".repeat(200)}</svg>`;
    expect(() => sanitiseSvg(deep)).toThrow(/deep/);
  });
});

describe("hostile import end to end", () => {
  it("produces editable nodes with no executable residue and reports the removals", () => {
    const report = importSvg(hostile, "hostile.svg");
    expect(report.supportedCount).toBeGreaterThan(0);
    const json = JSON.stringify(report.nodes);
    expect(json).not.toMatch(/script|onload|onclick|javascript|evil\.example/i);
    expect(report.unsupported.some((u) => /script/.test(u))).toBe(true);
    // the recursive <use> pair does not loop forever and is reported
    expect(report.unsupported.some((u) => /use/i.test(u))).toBe(true);
    // the stylesheet carried an external url, so the whole <style> was dropped and reported
    expect(report.unsupported.some((u) => /<style>/.test(u))).toBe(true);
    const safe = (
      report.nodes as Array<{ name: string; metadata: { importedElementId: string | null } }>
    ).find((n) => n.name === "safe");
    expect(safe?.metadata.importedElementId).toBe("safe");
  });
});
