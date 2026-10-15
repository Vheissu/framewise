// @vitest-environment jsdom
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { importSvg, parseColor, parseTransform } from "../../web/adapters/svg-import";

const nested = readFileSync(resolve(__dirname, "../fixtures/svg/nested.svg"), "utf8");

type NodeJson = {
  id: string;
  name: string;
  kind: string;
  parentId: string | null;
  childIds: string[];
  opacity: number;
  transform: {
    translation: { x: number; y: number };
    rotation: number;
    scale: { x: number; y: number };
  };
  geometry: Record<string, unknown>;
  fill: { type: string; color?: { r: number; g: number; b: number; a: number }; stops?: unknown[] };
  stroke: {
    paint: { type: string; color?: { r: number; g: number; b: number } };
    width: number;
    dashArray: number[];
  };
  effects: Array<{ type: string; radius?: number }>;
  hidden: boolean;
  metadata: { importedElementId: string | null };
};

describe("transform parsing", () => {
  it("parses translate, rotate and scale in order", () => {
    const m = parseTransform("translate(10 20) rotate(90) scale(2)");
    // point (1,0) -> scale (2,0) -> rotate (0,2) -> translate (10,22)
    const x = m.a * 1 + m.c * 0 + m.e;
    const y = m.b * 1 + m.d * 0 + m.f;
    expect(x).toBeCloseTo(10);
    expect(y).toBeCloseTo(22);
  });
  it("parses matrix and rotate about a point", () => {
    const m = parseTransform("matrix(1 0 0 1 5 6)");
    expect(m.e).toBe(5);
    const r = parseTransform("rotate(180 10 10)");
    expect(r.a * 10 + r.c * 10 + r.e).toBeCloseTo(10);
  });
});

describe("colour parsing", () => {
  it("handles hex, rgb, hsl, named, none and currentColor", () => {
    expect(parseColor("#f00")).toEqual({ r: 1, g: 0, b: 0, a: 1 });
    expect(parseColor("#00ff0080")).toMatchObject({ g: 1 });
    expect(parseColor("rgb(255, 0, 0)")).toEqual({ r: 1, g: 0, b: 0, a: 1 });
    expect(parseColor("rgba(0,0,255,0.5)")).toEqual({ r: 0, g: 0, b: 1, a: 0.5 });
    expect(parseColor("hsl(120, 100%, 50%)")).toMatchObject({ g: 1 });
    expect(parseColor("rebeccapurple")).toMatchObject({ r: 0.4 });
    expect(parseColor("none")).toBe("none");
    expect(parseColor("currentColor")).toBe("current");
    expect(parseColor("url(#grad)")).toEqual({ url: "grad" });
    expect(parseColor("nonsense")).toBeNull();
  });
});

describe("nested SVG import", () => {
  const report = importSvg(nested, "nested.svg");
  const nodes = report.nodes as NodeJson[];
  const byName = (name: string) => nodes.find((n) => n.name === name)!;

  it("uses the viewBox for the scene size", () => {
    expect(report.width).toBe(200);
    expect(report.height).toBe(120);
  });

  it("keeps the hierarchy with original ids as names and metadata", () => {
    const logo = byName("logo");
    expect(logo.kind).toBe("group");
    expect(logo.metadata.importedElementId).toBe("logo");
    const box = byName("box");
    expect(box.parentId).toBe(logo.id);
    expect(logo.childIds).toContain(box.id);
  });

  it("decomposes transforms and folds rect x/y into translation", () => {
    const logo = byName("logo");
    expect(logo.transform.translation).toEqual({ x: 10, y: 20 });
    expect(logo.transform.rotation).toBeCloseTo(30);
    expect(logo.transform.scale.x).toBeCloseTo(2);
    const box = byName("box");
    expect(box.transform.translation).toEqual({ x: 5, y: 5 });
    expect(box.geometry).toEqual({ size: { x: 20, y: 10 }, cornerRadius: 2 });
  });

  it("inherits fill and stroke from the group", () => {
    const box = byName("box");
    expect(box.fill.type).toBe("solid");
    expect(box.fill.color?.r).toBeCloseTo(0x12 / 255);
    expect(box.stroke.paint.type).toBe("solid");
    expect(box.stroke.width).toBe(2);
  });

  it("converts gradients with stop opacity", () => {
    const dot = byName("dot");
    expect(dot.fill.type).toBe("linearGradient");
    expect(dot.fill.stops).toHaveLength(2);
    expect(dot.opacity).toBe(0.5);
  });

  it("wraps clipped groups in a clip group whose first child is the clip shape", () => {
    const clipped = nodes.find((n) => n.name.includes("inner") && n.kind === "clipGroup")!;
    expect(clipped).toBeDefined();
    const first = nodes.find((n) => n.id === clipped.childIds[0])!;
    expect(first.kind).toBe("rect");
  });

  it("keeps path data for the Elm parser and reports arcs", () => {
    const curve = byName("curve");
    expect(curve.kind).toBe("path-d");
    expect(curve.geometry).toEqual({ d: "M0 0 Q 10 20 20 0 A 5 5 0 0 1 30 0 Z" });
    expect(report.approximated.some((a) => /arc/.test(a))).toBe(true);
    expect(byName("poly").kind).toBe("path");
    expect(byName("curve").stroke.dashArray).toEqual([4, 2]);
  });

  it("imports text with merged tspans and a warning", () => {
    const label = byName("label");
    expect(label.kind).toBe("text");
    expect(label.geometry).toMatchObject({
      content: "Hello there",
      fontSize: 12,
      fontWeight: 700,
      align: "middle",
    });
    expect(report.warnings.some((w) => /font/.test(w))).toBe(true);
  });

  it("imports a plain blur filter and rejects compound filters", () => {
    expect(byName("blurred").effects).toEqual([{ type: "blur", radius: 3 }]);
    expect(byName("filtered").effects).toEqual([]);
    expect(report.unsupported.some((u) => /complex/.test(u))).toBe(true);
  });

  it("resolves currentColor and reports masks as unsupported", () => {
    expect(byName("line").stroke.paint.color?.r).toBeCloseTo(0xab / 255);
    expect(report.unsupported.some((u) => /mask/.test(u))).toBe(true);
  });

  it("throws a structured error for an SVG with nothing editable", () => {
    expect(() =>
      importSvg('<svg xmlns="http://www.w3.org/2000/svg"><mask id="m"/></svg>', "empty.svg"),
    ).toThrow(/no shapes/);
  });
});
