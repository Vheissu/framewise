import { ID_PREFIX, sanitiseSvg } from "./sanitise-svg";
import { randomId } from "./id";
import { BridgeError } from "./protocol";

/**
 * Converts sanitised SVG into Framewise's typed node JSON (the shape read by
 * DocumentIO.Decode.node). Nothing that cannot be typed is retained; every
 * drop or approximation is reported.
 */

export interface ImportReport {
  fileName: string;
  nodes: unknown[];
  supportedCount: number;
  approximated: string[];
  unsupported: string[];
  warnings: string[];
  width: number | null;
  height: number | null;
  asNewDocument: boolean;
}

interface Matrix {
  a: number;
  b: number;
  c: number;
  d: number;
  e: number;
  f: number;
}

const IDENTITY: Matrix = { a: 1, b: 0, c: 0, d: 1, e: 0, f: 0 };

function multiply(m: Matrix, n: Matrix): Matrix {
  return {
    a: m.a * n.a + m.c * n.b,
    b: m.b * n.a + m.d * n.b,
    c: m.a * n.c + m.c * n.d,
    d: m.b * n.c + m.d * n.d,
    e: m.a * n.e + m.c * n.f + m.e,
    f: m.b * n.e + m.d * n.f + m.f,
  };
}

/** Decompose into Framewise components with pivot (0,0): translate, rotate, skewX, scale. */
function decompose(m: Matrix): {
  translation: Vec;
  scale: Vec;
  rotation: number;
  skew: Vec;
  pivot: Vec;
} {
  const sx = Math.hypot(m.a, m.b) || 1e-9;
  const det = m.a * m.d - m.b * m.c;
  const theta = Math.atan2(m.b, m.a);
  const sy = det / sx;
  const cPrime = Math.cos(theta) * m.c + Math.sin(theta) * m.d;
  const skewX = sy === 0 ? 0 : (Math.atan(cPrime / sy) * 180) / Math.PI;
  return {
    translation: { x: m.e, y: m.f },
    scale: { x: sx, y: sy },
    rotation: (theta * 180) / Math.PI,
    skew: { x: skewX, y: 0 },
    pivot: { x: 0, y: 0 },
  };
}

interface Vec {
  x: number;
  y: number;
}

export function parseTransform(value: string | null): Matrix {
  if (!value) return IDENTITY;
  let m = IDENTITY;
  const re = /(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)/g;
  let match: RegExpExecArray | null;
  while ((match = re.exec(value)) !== null) {
    const fn = match[1]!;
    const args = match[2]!
      .split(/[\s,]+/)
      .filter((s) => s.length)
      .map(Number);
    if (args.some((n) => !Number.isFinite(n))) continue;
    let t: Matrix = IDENTITY;
    switch (fn) {
      case "matrix":
        if (args.length === 6)
          t = { a: args[0]!, b: args[1]!, c: args[2]!, d: args[3]!, e: args[4]!, f: args[5]! };
        break;
      case "translate":
        t = { ...IDENTITY, e: args[0] ?? 0, f: args[1] ?? 0 };
        break;
      case "scale":
        t = { ...IDENTITY, a: args[0] ?? 1, d: args[1] ?? args[0] ?? 1 };
        break;
      case "rotate": {
        const r = ((args[0] ?? 0) * Math.PI) / 180;
        const rot: Matrix = {
          a: Math.cos(r),
          b: Math.sin(r),
          c: -Math.sin(r),
          d: Math.cos(r),
          e: 0,
          f: 0,
        };
        if (args.length >= 3) {
          const cx = args[1]!;
          const cy = args[2]!;
          t = multiply(multiply({ ...IDENTITY, e: cx, f: cy }, rot), {
            ...IDENTITY,
            e: -cx,
            f: -cy,
          });
        } else t = rot;
        break;
      }
      case "skewX":
        t = { ...IDENTITY, c: Math.tan(((args[0] ?? 0) * Math.PI) / 180) };
        break;
      case "skewY":
        t = { ...IDENTITY, b: Math.tan(((args[0] ?? 0) * Math.PI) / 180) };
        break;
    }
    m = multiply(m, t);
  }
  return m;
}

// ---- colours ----

const NAMED: Record<string, string> = {
  black: "#000000",
  silver: "#c0c0c0",
  gray: "#808080",
  grey: "#808080",
  white: "#ffffff",
  maroon: "#800000",
  red: "#ff0000",
  purple: "#800080",
  fuchsia: "#ff00ff",
  magenta: "#ff00ff",
  green: "#008000",
  lime: "#00ff00",
  olive: "#808000",
  yellow: "#ffff00",
  navy: "#000080",
  blue: "#0000ff",
  teal: "#008080",
  aqua: "#00ffff",
  cyan: "#00ffff",
  orange: "#ffa500",
  aliceblue: "#f0f8ff",
  antiquewhite: "#faebd7",
  aquamarine: "#7fffd4",
  azure: "#f0ffff",
  beige: "#f5f5dc",
  bisque: "#ffe4c4",
  blanchedalmond: "#ffebcd",
  blueviolet: "#8a2be2",
  brown: "#a52a2a",
  burlywood: "#deb887",
  cadetblue: "#5f9ea0",
  chartreuse: "#7fff00",
  chocolate: "#d2691e",
  coral: "#ff7f50",
  cornflowerblue: "#6495ed",
  cornsilk: "#fff8dc",
  crimson: "#dc143c",
  darkblue: "#00008b",
  darkcyan: "#008b8b",
  darkgoldenrod: "#b8860b",
  darkgray: "#a9a9a9",
  darkgrey: "#a9a9a9",
  darkgreen: "#006400",
  darkkhaki: "#bdb76b",
  darkmagenta: "#8b008b",
  darkolivegreen: "#556b2f",
  darkorange: "#ff8c00",
  darkorchid: "#9932cc",
  darkred: "#8b0000",
  darksalmon: "#e9967a",
  darkseagreen: "#8fbc8f",
  darkslateblue: "#483d8b",
  darkslategray: "#2f4f4f",
  darkslategrey: "#2f4f4f",
  darkturquoise: "#00ced1",
  darkviolet: "#9400d3",
  deeppink: "#ff1493",
  deepskyblue: "#00bfff",
  dimgray: "#696969",
  dimgrey: "#696969",
  dodgerblue: "#1e90ff",
  firebrick: "#b22222",
  floralwhite: "#fffaf0",
  forestgreen: "#228b22",
  gainsboro: "#dcdcdc",
  ghostwhite: "#f8f8ff",
  gold: "#ffd700",
  goldenrod: "#daa520",
  greenyellow: "#adff2f",
  honeydew: "#f0fff0",
  hotpink: "#ff69b4",
  indianred: "#cd5c5c",
  indigo: "#4b0082",
  ivory: "#fffff0",
  khaki: "#f0e68c",
  lavender: "#e6e6fa",
  lavenderblush: "#fff0f5",
  lawngreen: "#7cfc00",
  lemonchiffon: "#fffacd",
  lightblue: "#add8e6",
  lightcoral: "#f08080",
  lightcyan: "#e0ffff",
  lightgoldenrodyellow: "#fafad2",
  lightgray: "#d3d3d3",
  lightgrey: "#d3d3d3",
  lightgreen: "#90ee90",
  lightpink: "#ffb6c1",
  lightsalmon: "#ffa07a",
  lightseagreen: "#20b2aa",
  lightskyblue: "#87cefa",
  lightslategray: "#778899",
  lightslategrey: "#778899",
  lightsteelblue: "#b0c4de",
  lightyellow: "#ffffe0",
  limegreen: "#32cd32",
  linen: "#faf0e6",
  mediumaquamarine: "#66cdaa",
  mediumblue: "#0000cd",
  mediumorchid: "#ba55d3",
  mediumpurple: "#9370db",
  mediumseagreen: "#3cb371",
  mediumslateblue: "#7b68ee",
  mediumspringgreen: "#00fa9a",
  mediumturquoise: "#48d1cc",
  mediumvioletred: "#c71585",
  midnightblue: "#191970",
  mintcream: "#f5fffa",
  mistyrose: "#ffe4e1",
  moccasin: "#ffe4b5",
  navajowhite: "#ffdead",
  oldlace: "#fdf5e6",
  olivedrab: "#6b8e23",
  orangered: "#ff4500",
  orchid: "#da70d6",
  palegoldenrod: "#eee8aa",
  palegreen: "#98fb98",
  paleturquoise: "#afeeee",
  palevioletred: "#db7093",
  papayawhip: "#ffefd5",
  peachpuff: "#ffdab9",
  peru: "#cd853f",
  pink: "#ffc0cb",
  plum: "#dda0dd",
  powderblue: "#b0e0e6",
  rebeccapurple: "#663399",
  rosybrown: "#bc8f8f",
  royalblue: "#4169e1",
  saddlebrown: "#8b4513",
  salmon: "#fa8072",
  sandybrown: "#f4a460",
  seagreen: "#2e8b57",
  seashell: "#fff5ee",
  sienna: "#a0522d",
  skyblue: "#87ceeb",
  slateblue: "#6a5acd",
  slategray: "#708090",
  slategrey: "#708090",
  snow: "#fffafa",
  springgreen: "#00ff7f",
  steelblue: "#4682b4",
  tan: "#d2b48c",
  thistle: "#d8bfd8",
  tomato: "#ff6347",
  turquoise: "#40e0d0",
  violet: "#ee82ee",
  wheat: "#f5deb3",
  whitesmoke: "#f5f5f5",
  yellowgreen: "#9acd32",
};

interface Rgba {
  r: number;
  g: number;
  b: number;
  a: number;
}

export function parseColor(
  value: string | undefined,
): Rgba | null | "none" | "current" | { url: string } {
  if (value === undefined) return null;
  const v = value.trim().toLowerCase();
  if (v === "" || v === "inherit") return null;
  if (v === "none" || v === "transparent") return "none";
  if (v === "currentcolor") return "current";
  const url = /^url\(\s*['"]?#([^'")]+)['"]?\s*\)/.exec(v);
  if (url) return { url: url[1]! };
  if (v.startsWith("#")) {
    const hex = v.slice(1);
    const expand = (h: string) =>
      h.length === 3 || h.length === 4
        ? h
            .split("")
            .map((c) => c + c)
            .join("")
        : h;
    const full = expand(hex);
    if (!/^[0-9a-f]{6}([0-9a-f]{2})?$/.test(full)) return null;
    const n = (i: number) => parseInt(full.slice(i, i + 2), 16) / 255;
    return { r: n(0), g: n(2), b: n(4), a: full.length === 8 ? n(6) : 1 };
  }
  const rgb = /^rgba?\(([^)]+)\)/.exec(v);
  if (rgb) {
    const parts = rgb[1]!.split(/[\s,/]+/).filter((p) => p.length);
    const chan = (p: string) => (p.endsWith("%") ? parseFloat(p) / 100 : parseFloat(p) / 255);
    const alpha =
      parts[3] !== undefined
        ? parts[3].endsWith("%")
          ? parseFloat(parts[3]) / 100
          : parseFloat(parts[3])
        : 1;
    if (parts.length < 3) return null;
    const out = { r: chan(parts[0]!), g: chan(parts[1]!), b: chan(parts[2]!), a: alpha };
    if ([out.r, out.g, out.b, out.a].some((n) => !Number.isFinite(n))) return null;
    return clampColor(out);
  }
  const hsl = /^hsla?\(([^)]+)\)/.exec(v);
  if (hsl) {
    const parts = hsl[1]!.split(/[\s,/]+/).filter((p) => p.length);
    if (parts.length < 3) return null;
    const h = parseFloat(parts[0]!);
    const s = parseFloat(parts[1]!) / 100;
    const l = parseFloat(parts[2]!) / 100;
    const alpha = parts[3] !== undefined ? parseFloat(parts[3]) : 1;
    return clampColor({ ...hslToRgb(h, s, l), a: alpha });
  }
  const named = NAMED[v];
  if (named) return parseColor(named);
  return null;
}

function hslToRgb(h: number, s: number, l: number): { r: number; g: number; b: number } {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const hp = (((h % 360) + 360) % 360) / 60;
  const x = c * (1 - Math.abs((hp % 2) - 1));
  let r = 0;
  let g = 0;
  let b = 0;
  if (hp < 1) [r, g, b] = [c, x, 0];
  else if (hp < 2) [r, g, b] = [x, c, 0];
  else if (hp < 3) [r, g, b] = [0, c, x];
  else if (hp < 4) [r, g, b] = [0, x, c];
  else if (hp < 5) [r, g, b] = [x, 0, c];
  else [r, g, b] = [c, 0, x];
  const m = l - c / 2;
  return { r: r + m, g: g + m, b: b + m };
}

function clampColor(c: Rgba): Rgba {
  const cl = (v: number) => Math.min(1, Math.max(0, Number.isFinite(v) ? v : 0));
  return { r: cl(c.r), g: cl(c.g), b: cl(c.b), a: cl(c.a) };
}

// ---- style resolution ----

interface Style {
  fill?: string;
  stroke?: string;
  "fill-opacity"?: string;
  "stroke-opacity"?: string;
  opacity?: string;
  "stroke-width"?: string;
  "stroke-linecap"?: string;
  "stroke-linejoin"?: string;
  "stroke-miterlimit"?: string;
  "stroke-dasharray"?: string;
  "stroke-dashoffset"?: string;
  "font-family"?: string;
  "font-size"?: string;
  "font-weight"?: string;
  "font-style"?: string;
  "text-anchor"?: string;
  "letter-spacing"?: string;
  display?: string;
  visibility?: string;
  color?: string;
  "clip-path"?: string;
  filter?: string;
  "fill-rule"?: string;
}

const INHERITED: (keyof Style)[] = [
  "fill",
  "stroke",
  "fill-opacity",
  "stroke-opacity",
  "stroke-width",
  "stroke-linecap",
  "stroke-linejoin",
  "stroke-miterlimit",
  "stroke-dasharray",
  "stroke-dashoffset",
  "font-family",
  "font-size",
  "font-weight",
  "font-style",
  "text-anchor",
  "letter-spacing",
  "visibility",
  "color",
  "fill-rule",
];

function parseDeclarations(css: string): Style {
  const out: Style = {};
  for (const decl of css.split(";")) {
    const idx = decl.indexOf(":");
    if (idx < 0) continue;
    const key = decl.slice(0, idx).trim().toLowerCase() as keyof Style;
    const value = decl
      .slice(idx + 1)
      .trim()
      .replace(/!important/i, "")
      .trim();
    if (key) out[key] = value;
  }
  return out;
}

interface CssRule {
  selectors: string[];
  style: Style;
}

/** Minimal stylesheet parser: `.class`, `#id`, `tag`, and comma lists. Anything else is reported. */
function parseStylesheet(css: string, warnings: string[]): CssRule[] {
  const rules: CssRule[] = [];
  const cleaned = css.replace(/\/\*[\s\S]*?\*\//g, "");
  const re = /([^{}]+)\{([^{}]*)\}/g;
  let match: RegExpExecArray | null;
  while ((match = re.exec(cleaned)) !== null) {
    const selectors = match[1]!
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.length);
    const supported = selectors.filter((s) =>
      /^(\.[A-Za-z_][\w-]*|#[A-Za-z_][\w-]*|[a-zA-Z]+)$/.test(s),
    );
    const unsupported = selectors.filter((s) => !supported.includes(s));
    if (unsupported.length)
      warnings.push(`CSS selector(s) not understood: ${unsupported.slice(0, 3).join(", ")}`);
    if (supported.length) rules.push({ selectors: supported, style: parseDeclarations(match[2]!) });
  }
  return rules;
}

function matchesSelector(el: Element, selector: string): boolean {
  if (selector.startsWith(".")) return el.classList.contains(selector.slice(1));
  if (selector.startsWith("#")) return el.getAttribute("id") === selector.slice(1);
  return el.tagName.toLowerCase() === selector.toLowerCase();
}

function ownStyle(el: Element, rules: CssRule[]): Style {
  const style: Style = {};
  for (const rule of rules) {
    if (rule.selectors.some((s) => matchesSelector(el, s))) Object.assign(style, rule.style);
  }
  for (const key of [
    ...INHERITED,
    "opacity",
    "display",
    "clip-path",
    "filter",
  ] as (keyof Style)[]) {
    const attr = el.getAttribute(key);
    if (attr !== null) style[key] = attr;
  }
  const inline = el.getAttribute("style");
  if (inline) Object.assign(style, parseDeclarations(inline));
  return style;
}

function inherit(parent: Style, own: Style): Style {
  const out: Style = {};
  for (const key of INHERITED) if (parent[key] !== undefined) out[key] = parent[key];
  return { ...out, ...own };
}

function parseLength(value: string | undefined, fallback: number): number {
  if (value === undefined) return fallback;
  const n = parseFloat(value);
  return Number.isFinite(n) ? n : fallback;
}

// ---- conversion ----

interface Ctx {
  nodes: unknown[];
  approximated: string[];
  unsupported: string[];
  warnings: string[];
  rules: CssRule[];
  gradients: Map<string, Element>;
  clipPaths: Map<string, Element>;
  byId: Map<string, Element>;
  useDepth: number;
  supported: number;
}

/** Descendants whose tag name matches one of `names` (case-insensitive, works in XML and HTML documents). */
function stripPrefix(id: string): string {
  return id.startsWith(ID_PREFIX) ? id.slice(ID_PREFIX.length) : id;
}

function byTag(root: Element, ...names: string[]): Element[] {
  const wanted = new Set(names.map((n) => n.toLowerCase()));
  return Array.from(root.querySelectorAll("*")).filter((el) =>
    wanted.has(el.tagName.toLowerCase()),
  );
}

function originalId(el: Element): string | null {
  const id = el.getAttribute("id");
  if (!id) return null;
  return id.startsWith(ID_PREFIX) ? id.slice(ID_PREFIX.length) : id;
}

function label(el: Element): string {
  const id = originalId(el);
  const inkscape = el.getAttribute("inkscape:label") ?? el.getAttribute("data-name");
  const tag = el.tagName.toLowerCase();
  return inkscape ?? id ?? tag;
}

function describe(el: Element): string {
  const id = originalId(el);
  return `<${el.tagName.toLowerCase()}${id ? ` id="${id}"` : ""}>`;
}

function colorJson(c: Rgba): unknown {
  return { r: c.r, g: c.g, b: c.b, a: c.a };
}

function paintJson(
  ctx: Ctx,
  el: Element,
  value: string | undefined,
  opacity: number,
  style: Style,
  fallback: Rgba | "none",
): unknown {
  const parsed = parseColor(value);
  const withAlpha = (c: Rgba) => ({ type: "solid", color: colorJson({ ...c, a: c.a * opacity }) });
  if (parsed === null) return fallback === "none" ? { type: "none" } : withAlpha(fallback);
  if (parsed === "none") return { type: "none" };
  if (parsed === "current") {
    const cur = parseColor(style.color);
    return cur && typeof cur === "object" && "r" in cur
      ? withAlpha(cur)
      : withAlpha({ r: 0, g: 0, b: 0, a: 1 });
  }
  if ("url" in parsed) {
    const grad = ctx.gradients.get(parsed.url);
    if (grad) return gradientJson(ctx, grad, el, opacity);
    ctx.unsupported.push(
      `${describe(el)}: paint server #${parsed.url} is not a gradient (pattern or missing)`,
    );
    return { type: "none" };
  }
  return withAlpha(parsed);
}

function gradientJson(ctx: Ctx, grad: Element, target: Element, opacity: number): unknown {
  // follow href chains for stops
  let stopsSource: Element | null = grad;
  let guard = 0;
  while (stopsSource && byTag(stopsSource, "stop").length === 0 && guard < 8) {
    const ref: string = (
      stopsSource.getAttribute("href") ??
      stopsSource.getAttribute("xlink:href") ??
      ""
    ).replace("#", "");
    const next: Element | undefined = ref ? ctx.gradients.get(ref) : undefined;
    stopsSource = next ?? null;
    guard += 1;
  }
  const stops = byTag(stopsSource ?? grad, "stop").map((stop) => {
    const style = parseDeclarations(stop.getAttribute("style") ?? "");
    const colorValue =
      style["stop-color" as keyof Style] ?? stop.getAttribute("stop-color") ?? "#000";
    const stopOpacity = parseLength(
      style["stop-opacity" as keyof Style] ?? stop.getAttribute("stop-opacity") ?? undefined,
      1,
    );
    const c = parseColor(colorValue as string);
    const rgba: Rgba = c && typeof c === "object" && "r" in c ? c : { r: 0, g: 0, b: 0, a: 1 };
    const offsetRaw = stop.getAttribute("offset") ?? "0";
    const offset = offsetRaw.endsWith("%") ? parseFloat(offsetRaw) / 100 : parseFloat(offsetRaw);
    return {
      offset: Math.min(1, Math.max(0, Number.isFinite(offset) ? offset : 0)),
      color: colorJson({ ...rgba, a: rgba.a * stopOpacity * opacity }),
    };
  });
  if (stops.length === 0) {
    ctx.unsupported.push(`${describe(grad)}: gradient without stops`);
    return { type: "none" };
  }
  const units = grad.getAttribute("gradientUnits") ?? "objectBoundingBox";
  if (grad.getAttribute("gradientTransform"))
    ctx.approximated.push(`${describe(grad)}: gradientTransform ignored`);
  if (grad.getAttribute("spreadMethod") && grad.getAttribute("spreadMethod") !== "pad")
    ctx.approximated.push(`${describe(grad)}: spreadMethod treated as pad`);
  const bbox = units === "objectBoundingBox" ? measureBBox(target) : null;
  const resolve = (v: string | null, fallback: number, axis: "x" | "y" | "r") => {
    if (v === null) return units === "objectBoundingBox" ? mapBox(fallback, axis, bbox) : fallback;
    const pct = v.endsWith("%") ? parseFloat(v) / 100 : null;
    const n = pct !== null ? pct : parseFloat(v);
    if (units === "objectBoundingBox") return mapBox(Number.isFinite(n) ? n : fallback, axis, bbox);
    return Number.isFinite(n) ? n : fallback;
  };
  if (grad.tagName.toLowerCase() === "radialgradient") {
    return {
      type: "radialGradient",
      center: {
        x: resolve(grad.getAttribute("cx"), 0.5, "x"),
        y: resolve(grad.getAttribute("cy"), 0.5, "y"),
      },
      radius: resolve(grad.getAttribute("r"), 0.5, "r"),
      stops,
    };
  }
  return {
    type: "linearGradient",
    start: {
      x: resolve(grad.getAttribute("x1"), 0, "x"),
      y: resolve(grad.getAttribute("y1"), 0, "y"),
    },
    end: {
      x: resolve(grad.getAttribute("x2"), 1, "x"),
      y: resolve(grad.getAttribute("y2"), 0, "y"),
    },
    stops,
  };
}

function mapBox(
  v: number,
  axis: "x" | "y" | "r",
  bbox: { x: number; y: number; width: number; height: number } | null,
): number {
  if (!bbox) return v * 100;
  if (axis === "x") return bbox.x + v * bbox.width;
  if (axis === "y") return bbox.y + v * bbox.height;
  return v * Math.max(bbox.width, bbox.height);
}

/** Measure a sanitised element by temporarily mounting its root offscreen. */
let measureHost: HTMLDivElement | null = null;
function measureBBox(el: Element): { x: number; y: number; width: number; height: number } | null {
  try {
    const svg = el.ownerDocument === document ? el.closest("svg") : null;
    if (!svg) return null;
    if (!measureHost) {
      measureHost = document.createElement("div");
      measureHost.setAttribute("aria-hidden", "true");
      measureHost.style.cssText =
        "position:fixed;left:-100000px;top:0;width:1px;height:1px;overflow:hidden;visibility:hidden;";
      document.body.appendChild(measureHost);
    }
    const wasAttached = svg.isConnected;
    if (!wasAttached) measureHost.appendChild(svg);
    const box = (el as SVGGraphicsElement).getBBox();
    if (!wasAttached) measureHost.removeChild(svg);
    return { x: box.x, y: box.y, width: box.width, height: box.height };
  } catch {
    return null;
  }
}

function baseNode(
  ctx: Ctx,
  el: Element,
  kind: string,
  parentId: string | null,
  style: Style,
  matrix: Matrix,
  geometry: unknown,
): Record<string, unknown> {
  const id = randomId();
  const opacity = Math.min(1, Math.max(0, parseLength(style.opacity, 1)));
  const fillOpacity = Math.min(1, Math.max(0, parseLength(style["fill-opacity"], 1)));
  const strokeOpacity = Math.min(1, Math.max(0, parseLength(style["stroke-opacity"], 1)));
  const isShape = !["group", "clipGroup", "image"].includes(kind);
  const isLine = kind === "line";
  const fill =
    isShape && !isLine
      ? paintJson(
          ctx,
          el,
          style.fill,
          fillOpacity,
          style,
          kind === "text" ||
            kind === "path" ||
            kind === "rect" ||
            kind === "ellipse" ||
            kind === "polygon"
            ? { r: 0, g: 0, b: 0, a: 1 }
            : "none",
        )
      : { type: "none" };
  const strokePaint = isShape
    ? paintJson(ctx, el, style.stroke, strokeOpacity, style, "none")
    : { type: "none" };
  const dash = (style["stroke-dasharray"] ?? "none").trim();
  const dashArray =
    dash === "none" || dash === ""
      ? []
      : dash
          .split(/[\s,]+/)
          .map(parseFloat)
          .filter((n) => Number.isFinite(n) && n >= 0);
  const comps = decompose(matrix);
  if (Math.abs(comps.skew.x) > 1e-6)
    ctx.approximated.push(`${describe(el)}: transform skew folded into skew X`);
  const effects: unknown[] = [];
  const filterRef = /url\(\s*['"]?#([^'")]+)/.exec(style.filter ?? "");
  if (filterRef) {
    const filterEl = ctx.byId.get(filterRef[1]!);
    const blur = filterEl ? byTag(filterEl, "feGaussianBlur")[0] : undefined;
    if (filterEl && blur && filterEl.children.length === 1) {
      const sd = parseFloat((blur.getAttribute("stdDeviation") ?? "0").split(/[\s,]+/)[0]!);
      effects.push({ type: "blur", radius: Number.isFinite(sd) ? Math.max(0, sd) : 0 });
    } else {
      ctx.unsupported.push(
        `${describe(el)}: filter #${stripPrefix(filterRef[1]!)} is not a plain Gaussian blur`,
      );
    }
  }
  if (style["fill-rule"] === "evenodd")
    ctx.approximated.push(`${describe(el)}: fill-rule evenodd rendered as nonzero`);
  return {
    id,
    name: label(el),
    kind,
    parentId,
    childIds: [],
    hidden: style.display === "none" || style.visibility === "hidden",
    locked: false,
    opacity,
    transform: comps,
    geometry,
    fill,
    stroke: {
      paint: strokePaint,
      width: Math.max(0, parseLength(style["stroke-width"], 1)),
      cap: ["butt", "round", "square"].includes(style["stroke-linecap"] ?? "")
        ? style["stroke-linecap"]
        : "butt",
      join: ["miter", "round", "bevel"].includes(style["stroke-linejoin"] ?? "")
        ? style["stroke-linejoin"]
        : "miter",
      miterLimit: Math.max(1, parseLength(style["stroke-miterlimit"], 4)),
      dashArray,
      dashOffset: parseLength(style["stroke-dashoffset"], 0),
    },
    effects,
    motion: null,
    metadata: { importedElementId: originalId(el) },
  };
}

function pointsOf(value: string | null): Vec[] {
  if (!value) return [];
  const nums = value
    .split(/[\s,]+/)
    .filter((s) => s.length)
    .map(Number);
  const out: Vec[] = [];
  for (let i = 0; i + 1 < nums.length; i += 2) {
    const x = nums[i]!;
    const y = nums[i + 1]!;
    if (Number.isFinite(x) && Number.isFinite(y)) out.push({ x, y });
  }
  return out;
}

function polylineGeometry(points: Vec[], closed: boolean): unknown {
  if (points.length === 0) return { subpaths: [] };
  const [first, ...rest] = points;
  return {
    subpaths: [{ start: first, closed, segments: rest.map((p) => ({ type: "line", to: p })) }],
  };
}

function convertElement(
  ctx: Ctx,
  el: Element,
  parentId: string | null,
  parentStyle: Style,
  parentNodeIds: string[],
): void {
  const tag = el.tagName.toLowerCase();
  const style = inherit(parentStyle, ownStyle(el, ctx.rules));
  const matrix = parseTransform(el.getAttribute("transform"));
  const push = (node: Record<string, unknown>) => {
    ctx.nodes.push(node);
    parentNodeIds.push(node.id as string);
    ctx.supported += 1;
  };
  const clipRef = /url\(\s*['"]?#([^'")]+)/.exec(
    style["clip-path"] ?? el.getAttribute("clip-path") ?? "",
  );
  if (clipRef) {
    const clip = ctx.clipPaths.get(clipRef[1]!);
    if (clip && clip.children.length >= 1) {
      if (clip.children.length > 1)
        ctx.approximated.push(
          `${describe(el)}: clip-path #${clipRef[1]} has ${clip.children.length} shapes; only the first is used`,
        );
      // wrap in a clip group: first child is the clip shape, then the element itself
      const group = baseNode(ctx, el, "clipGroup", parentId, {}, matrix, {});
      group.name = `${label(el)} (clipped)`;
      ctx.nodes.push(group);
      parentNodeIds.push(group.id as string);
      const childIds: string[] = [];
      const clipShape = clip.children[0]!;
      convertElement(ctx, clipShape, group.id as string, {}, childIds);
      // the element without its own transform (already on the group) and without the clip
      const clone = el.cloneNode(true) as Element;
      clone.removeAttribute("transform");
      clone.removeAttribute("clip-path");
      const inlineStyle = clone.getAttribute("style");
      if (inlineStyle)
        clone.setAttribute("style", inlineStyle.replace(/clip-path\s*:[^;]+;?/i, ""));
      convertElement(ctx, clone, group.id as string, parentStyle, childIds);
      group.childIds = childIds;
      return;
    }
    ctx.unsupported.push(
      `${describe(el)}: clip-path #${stripPrefix(clipRef[1]!)} could not be resolved`,
    );
  }
  switch (tag) {
    case "g":
    case "svg":
    case "a":
    case "switch": {
      const node = baseNode(ctx, el, "group", parentId, style, matrix, {});
      ctx.nodes.push(node);
      parentNodeIds.push(node.id as string);
      const childIds: string[] = [];
      for (const child of Array.from(el.children))
        convertElement(ctx, child, node.id as string, style, childIds);
      node.childIds = childIds;
      ctx.supported += 1;
      return;
    }
    case "rect": {
      const x = parseLength(el.getAttribute("x") ?? undefined, 0);
      const y = parseLength(el.getAttribute("y") ?? undefined, 0);
      const w = parseLength(el.getAttribute("width") ?? undefined, 0);
      const h = parseLength(el.getAttribute("height") ?? undefined, 0);
      const rx = parseLength(el.getAttribute("rx") ?? el.getAttribute("ry") ?? undefined, 0);
      if (
        el.getAttribute("ry") &&
        el.getAttribute("rx") &&
        el.getAttribute("rx") !== el.getAttribute("ry")
      )
        ctx.approximated.push(`${describe(el)}: rx and ry differ; rx used`);
      const m = multiply(matrix, { ...IDENTITY, e: x, f: y });
      push(
        baseNode(ctx, el, "rect", parentId, style, m, {
          size: { x: Math.max(0, w), y: Math.max(0, h) },
          cornerRadius: Math.max(0, rx),
        }),
      );
      return;
    }
    case "circle": {
      const cx = parseLength(el.getAttribute("cx") ?? undefined, 0);
      const cy = parseLength(el.getAttribute("cy") ?? undefined, 0);
      const r = Math.max(0, parseLength(el.getAttribute("r") ?? undefined, 0));
      push(
        baseNode(
          ctx,
          el,
          "ellipse",
          parentId,
          style,
          multiply(matrix, { ...IDENTITY, e: cx, f: cy }),
          { radii: { x: r, y: r } },
        ),
      );
      return;
    }
    case "ellipse": {
      const cx = parseLength(el.getAttribute("cx") ?? undefined, 0);
      const cy = parseLength(el.getAttribute("cy") ?? undefined, 0);
      const rx = Math.max(0, parseLength(el.getAttribute("rx") ?? undefined, 0));
      const ry = Math.max(0, parseLength(el.getAttribute("ry") ?? undefined, 0));
      push(
        baseNode(
          ctx,
          el,
          "ellipse",
          parentId,
          style,
          multiply(matrix, { ...IDENTITY, e: cx, f: cy }),
          { radii: { x: rx, y: ry } },
        ),
      );
      return;
    }
    case "line": {
      const start = {
        x: parseLength(el.getAttribute("x1") ?? undefined, 0),
        y: parseLength(el.getAttribute("y1") ?? undefined, 0),
      };
      const end = {
        x: parseLength(el.getAttribute("x2") ?? undefined, 0),
        y: parseLength(el.getAttribute("y2") ?? undefined, 0),
      };
      push(baseNode(ctx, el, "line", parentId, style, matrix, { start, end }));
      return;
    }
    case "polyline":
    case "polygon": {
      const pts = pointsOf(el.getAttribute("points"));
      if (pts.length < 2) {
        ctx.unsupported.push(`${describe(el)}: fewer than two points`);
        return;
      }
      push(
        baseNode(
          ctx,
          el,
          "path",
          parentId,
          style,
          matrix,
          polylineGeometry(pts, tag === "polygon"),
        ),
      );
      return;
    }
    case "path": {
      const d = el.getAttribute("d") ?? "";
      if (!d.trim()) {
        ctx.unsupported.push(`${describe(el)}: empty path data`);
        return;
      }
      if (/[aA]/.test(d.replace(/[eE][-+]?\d+/g, "")))
        ctx.approximated.push(`${describe(el)}: arc commands converted to cubic curves`);
      push(baseNode(ctx, el, "path-d", parentId, style, matrix, { d }));
      return;
    }
    case "text": {
      const content = Array.from(el.childNodes)
        .map((n) =>
          n.nodeType === Node.TEXT_NODE
            ? n.textContent
            : n.nodeType === Node.ELEMENT_NODE
              ? (n as Element).textContent
              : "",
        )
        .join("")
        .replace(/\s+/g, " ")
        .trim();
      if (el.querySelectorAll("tspan").length > 1)
        ctx.approximated.push(`${describe(el)}: multiple tspans merged into one line`);
      ctx.warnings.push(`${describe(el)}: text layout depends on fonts available on this device`);
      const x = parseLength(
        el.getAttribute("x") ?? el.querySelector("tspan")?.getAttribute("x") ?? undefined,
        0,
      );
      const y = parseLength(
        el.getAttribute("y") ?? el.querySelector("tspan")?.getAttribute("y") ?? undefined,
        0,
      );
      const weightRaw = style["font-weight"] ?? "400";
      const weight =
        weightRaw === "bold" ? 700 : weightRaw === "normal" ? 400 : parseInt(weightRaw, 10) || 400;
      const anchor = style["text-anchor"];
      push(
        baseNode(ctx, el, "text", parentId, style, multiply(matrix, { ...IDENTITY, e: x, f: y }), {
          content,
          fontFamily: (style["font-family"] ?? "sans-serif").replace(/['"]/g, ""),
          fontSize: Math.max(0.1, parseLength(style["font-size"], 16)),
          fontWeight: weight,
          italic: style["font-style"] === "italic" || style["font-style"] === "oblique",
          letterSpacing: parseLength(style["letter-spacing"], 0),
          align: anchor === "middle" ? "middle" : anchor === "end" ? "end" : "start",
        }),
      );
      return;
    }
    case "use": {
      const ref = (el.getAttribute("href") ?? el.getAttribute("xlink:href") ?? "").replace("#", "");
      const target = ctx.byId.get(ref);
      if (!target) {
        ctx.unsupported.push(`${describe(el)}: reference #${stripPrefix(ref)} not found`);
        return;
      }
      if (ctx.useDepth > 16) {
        ctx.unsupported.push(`${describe(el)}: <use> nesting too deep (possible cycle)`);
        return;
      }
      if (target.contains(el)) {
        ctx.unsupported.push(`${describe(el)}: <use> references its own ancestor`);
        return;
      }
      const x = parseLength(el.getAttribute("x") ?? undefined, 0);
      const y = parseLength(el.getAttribute("y") ?? undefined, 0);
      const clone = target.cloneNode(true) as Element;
      if (clone.tagName.toLowerCase() === "symbol") {
        // symbols become groups
        const g = clone.ownerDocument.createElementNS("http://www.w3.org/2000/svg", "g");
        for (const attr of Array.from(clone.attributes))
          if (attr.name !== "id" && attr.name !== "viewBox") g.setAttribute(attr.name, attr.value);
        while (clone.firstChild) g.appendChild(clone.firstChild);
        g.setAttribute("id", `${ref}-instance`);
        // keep the prefix so the name strips cleanly
        ctx.useDepth += 1;
        const wrapper = baseNode(
          ctx,
          el,
          "group",
          parentId,
          style,
          multiply(matrix, { ...IDENTITY, e: x, f: y }),
          {},
        );
        wrapper.name = `${stripPrefix(ref)} instance`;
        ctx.nodes.push(wrapper);
        parentNodeIds.push(wrapper.id as string);
        const childIds: string[] = [];
        convertElement(ctx, g, wrapper.id as string, style, childIds);
        wrapper.childIds = childIds;
        ctx.useDepth -= 1;
        ctx.approximated.push(`${describe(el)}: <use> expanded into a copy`);
        return;
      }
      ctx.useDepth += 1;
      const wrapper = baseNode(
        ctx,
        el,
        "group",
        parentId,
        style,
        multiply(matrix, { ...IDENTITY, e: x, f: y }),
        {},
      );
      wrapper.name = `${label(el)} (use)`;
      ctx.nodes.push(wrapper);
      parentNodeIds.push(wrapper.id as string);
      const childIds: string[] = [];
      clone.removeAttribute("id");
      convertElement(ctx, clone, wrapper.id as string, style, childIds);
      wrapper.childIds = childIds;
      ctx.useDepth -= 1;
      ctx.approximated.push(`${describe(el)}: <use> expanded into a copy`);
      return;
    }
    case "defs":
    case "lineargradient":
    case "radialgradient":
    case "clippath":
    case "style":
    case "title":
    case "desc":
    case "metadata":
    case "symbol":
    case "filter":
      return;
    case "image":
      ctx.unsupported.push(`${describe(el)}: embedded images are not imported; use Import Image`);
      return;
    case "mask":
    case "pattern":
    case "marker":
      ctx.unsupported.push(`${describe(el)}: ${tag} is not supported`);
      return;
    default:
      ctx.unsupported.push(`${describe(el)}: unsupported element`);
  }
}

export function importSvg(text: string, fileName: string): ImportReport {
  const { root, removed } = sanitiseSvg(text);
  const warnings: string[] = [];
  const rules: CssRule[] = [];
  for (const style of Array.from(root.querySelectorAll("style")))
    rules.push(...parseStylesheet(style.textContent ?? "", warnings));
  const ctx: Ctx = {
    nodes: [],
    approximated: [],
    unsupported: removed.map((r) => `${r}: removed for safety`),
    warnings,
    rules,
    gradients: new Map(),
    clipPaths: new Map(),
    byId: new Map(),
    useDepth: 0,
    supported: 0,
  };
  for (const el of Array.from(root.querySelectorAll("[id]")))
    ctx.byId.set(el.getAttribute("id")!, el);
  for (const el of Array.from(root.querySelectorAll("linearGradient, radialGradient")))
    ctx.gradients.set(el.getAttribute("id") ?? "", el);
  for (const el of Array.from(root.querySelectorAll("clipPath")))
    ctx.clipPaths.set(el.getAttribute("id") ?? "", el);
  for (const tag of ["mask", "pattern", "marker"])
    for (const el of Array.from(root.querySelectorAll(tag)))
      ctx.unsupported.push(`${describe(el)}: ${tag} is not supported`);
  for (const el of Array.from(root.querySelectorAll("filter"))) {
    if (!(el.children.length === 1 && el.children[0]!.tagName.toLowerCase() === "fegaussianblur"))
      ctx.unsupported.push(`${describe(el)}: only single feGaussianBlur filters are imported`);
  }
  // scene size
  let width: number | null = null;
  let height: number | null = null;
  const viewBox = (root.getAttribute("viewBox") ?? "").split(/[\s,]+/).map(Number);
  let rootMatrix = IDENTITY;
  if (viewBox.length === 4 && viewBox.every((n) => Number.isFinite(n))) {
    width = viewBox[2]!;
    height = viewBox[3]!;
    if (viewBox[0] !== 0 || viewBox[1] !== 0)
      rootMatrix = { ...IDENTITY, e: -viewBox[0]!, f: -viewBox[1]! };
  } else {
    const w = parseFloat(root.getAttribute("width") ?? "");
    const h = parseFloat(root.getAttribute("height") ?? "");
    if (Number.isFinite(w) && Number.isFinite(h)) {
      width = w;
      height = h;
    } else warnings.push("No viewBox or size on the root; the scene uses document defaults");
  }
  const rootStyle = ownStyle(root, rules);
  const rootIds: string[] = [];
  for (const child of Array.from(root.children))
    convertElement(ctx, child, null, rootStyle, rootIds);
  if (rootMatrix !== IDENTITY) {
    for (const node of ctx.nodes as Record<string, unknown>[]) {
      if (node.parentId === null) {
        const t = node.transform as { translation: Vec };
        t.translation = { x: t.translation.x + rootMatrix.e, y: t.translation.y + rootMatrix.f };
      }
    }
  }
  const unique = (list: string[]) => Array.from(new Set(list));
  if (ctx.supported === 0 && ctx.nodes.length === 0) {
    throw new BridgeError("svg.empty", "The SVG contains no shapes Framewise can edit", false, {
      report: { fileName, unsupported: unique(ctx.unsupported) },
    });
  }
  return {
    fileName,
    nodes: ctx.nodes,
    supportedCount: ctx.supported,
    approximated: unique(ctx.approximated),
    unsupported: unique(ctx.unsupported),
    warnings: unique(ctx.warnings),
    width,
    height,
    asNewDocument: false,
  };
}
