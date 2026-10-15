import DOMPurify from "dompurify";
import { BridgeError } from "./protocol";

/**
 * Turns untrusted SVG text into an inert, sanitised DOM. Nothing from the
 * input touches the live page before this step completes.
 */

export const SVG_LIMITS = {
  maxBytes: 10 * 1024 * 1024,
  maxElements: 20000,
  maxDepth: 128,
  maxAttributeLength: 200000,
};

const FORBIDDEN_TAGS = [
  "script",
  "foreignObject",
  "iframe",
  "object",
  "embed",
  "audio",
  "video",
  "animate",
  "animateMotion",
  "animateTransform",
  "set",
  "discard",
  "handler",
  "listener",
  "prefetch",
  "a",
];
const FORBIDDEN_ATTR = [
  "onload",
  "onclick",
  "onerror",
  "onmouseover",
  "requiredFeatures",
  "externalResourcesRequired",
  "ping",
  "formaction",
  "xlink:actuate",
];

export interface SanitisedSvg {
  root: SVGSVGElement;
  removed: string[];
  elementCount: number;
}

export const ID_PREFIX = "fwimp-";

const REF_ATTRS = [
  "href",
  "xlink:href",
  "fill",
  "stroke",
  "clip-path",
  "mask",
  "filter",
  "marker-start",
  "marker-mid",
  "marker-end",
  "style",
];

/**
 * Prefix every id and local reference before sanitising. DOMPurify strips ids
 * that collide with DOM properties (such as "blur"), which would silently
 * break a filter reference; prefixed ids never collide. The importer strips
 * the prefix again when it records names.
 */
function prefixIds(root: Element): void {
  const ids = new Set<string>();
  for (const el of Array.from(root.querySelectorAll("[id]"))) {
    const id = el.getAttribute("id");
    if (id) {
      ids.add(id);
      el.setAttribute("id", ID_PREFIX + id);
    }
  }
  if (ids.size === 0) return;
  const rewrite = (value: string): string =>
    value.replace(/#([A-Za-z_][\w.:-]*)/g, (match, id: string) =>
      ids.has(id) ? `#${ID_PREFIX}${id}` : match,
    );
  for (const el of Array.from(root.querySelectorAll("*")).concat([root])) {
    for (const name of REF_ATTRS) {
      const value = el.getAttribute(name);
      if (value && value.includes("#")) el.setAttribute(name, rewrite(value));
    }
    if (el.tagName.toLowerCase() === "style" && el.textContent && el.textContent.includes("#")) {
      el.textContent = rewrite(el.textContent);
    }
  }
}

export function sanitiseSvg(text: string): SanitisedSvg {
  if (text.length > SVG_LIMITS.maxBytes)
    throw new BridgeError("svg.tooLarge", "The SVG exceeds the 10 MB import limit");
  const head = text.slice(0, 4000);
  if (/<!DOCTYPE/i.test(head) || /<!ENTITY/i.test(text) || /<\?xml-stylesheet/i.test(head)) {
    throw new BridgeError(
      "svg.dtd",
      "The SVG declares a DOCTYPE, entities or an external stylesheet, which Framewise does not accept",
    );
  }
  const parsed = new DOMParser().parseFromString(text, "image/svg+xml");
  if (parsed.getElementsByTagName("parsererror").length > 0) {
    throw new BridgeError("svg.parse", "The SVG is not well-formed XML");
  }
  prefixIds(parsed.documentElement);
  const removed: string[] = [];
  const purify = DOMPurify();
  purify.addHook("uponSanitizeElement", (node, data) => {
    const allowed = (data.allowedTags as Record<string, boolean | undefined>)[data.tagName];
    if (FORBIDDEN_TAGS.includes(data.tagName) || (!allowed && node.nodeType === 1))
      removed.push(`<${data.tagName}>`);
  });
  purify.addHook("uponSanitizeAttribute", (node, data) => {
    const name = data.attrName.toLowerCase();
    const value = data.attrValue;
    if (value.length > SVG_LIMITS.maxAttributeLength) {
      data.keepAttr = false;
      removed.push(`${name} (too long)`);
      return;
    }
    if (name.startsWith("on")) {
      data.keepAttr = false;
      removed.push(name);
      return;
    }
    if (name === "href" || name === "xlink:href") {
      // only local fragments survive
      if (!value.trim().startsWith("#")) {
        data.keepAttr = false;
        removed.push(`${name}="${value.slice(0, 60)}"`);
      }
      return;
    }
    if (name === "style") {
      if (
        /url\s*\(\s*['"]?\s*(?!#)/i.test(value) ||
        /@import|expression\s*\(|javascript:/i.test(value)
      ) {
        data.keepAttr = false;
        removed.push("style with external url");
      }
      return;
    }
    if (
      /^(fill|stroke|clip-path|mask|filter|marker-start|marker-mid|marker-end)$/.test(name) &&
      /url\s*\(/i.test(value) &&
      !/url\s*\(\s*['"]?#/i.test(value)
    ) {
      data.keepAttr = false;
      removed.push(`${name} with external url`);
    }
  });
  const cleanDoc = purify.sanitize(parsed.documentElement, {
    USE_PROFILES: { svg: true, svgFilters: true },
    FORBID_TAGS: FORBIDDEN_TAGS,
    FORBID_ATTR: FORBIDDEN_ATTR,
    ADD_TAGS: ["style", "use"],
    ADD_ATTR: [
      "inkscape:label",
      "data-name",
      "transform",
      "clip-path",
      "gradientUnits",
      "gradientTransform",
      "spreadMethod",
      "stop-color",
      "stop-opacity",
    ],
    RETURN_DOM: true,
    WHOLE_DOCUMENT: false,
    IN_PLACE: false,
  }) as unknown as Element;
  const root = cleanDoc.tagName.toLowerCase() === "svg" ? cleanDoc : cleanDoc.querySelector("svg");
  if (!root)
    throw new BridgeError("svg.root", "No <svg> root element was found after sanitisation");
  // post-sanitisation audit: strip any <style> rule that smuggles urls or imports
  const byTag = (el: Element, name: string) =>
    Array.from(el.querySelectorAll("*")).filter(
      (e) => e.tagName.toLowerCase() === name.toLowerCase(),
    );
  for (const style of byTag(root, "style")) {
    const css = style.textContent ?? "";
    if (
      /url\s*\(\s*['"]?\s*(?!#)/i.test(css) ||
      /@import|expression\s*\(|javascript:|behavior\s*:/i.test(css)
    ) {
      style.remove();
      removed.push("<style> with external references");
    }
  }
  for (const image of byTag(root, "image")) {
    const href = image.getAttribute("href") ?? image.getAttribute("xlink:href") ?? "";
    if (
      !href.startsWith("data:image/png") &&
      !href.startsWith("data:image/jpeg") &&
      !href.startsWith("data:image/webp")
    ) {
      image.remove();
      removed.push("<image> with non-embedded source");
    }
  }
  const count = root.querySelectorAll("*").length;
  if (count > SVG_LIMITS.maxElements)
    throw new BridgeError(
      "svg.tooComplex",
      `The SVG has ${count} elements; the limit is ${SVG_LIMITS.maxElements}`,
    );
  let depth = 0;
  const walk = (el: Element, d: number) => {
    depth = Math.max(depth, d);
    if (d > SVG_LIMITS.maxDepth)
      throw new BridgeError("svg.tooDeep", "The SVG nests elements too deeply");
    for (const child of Array.from(el.children)) walk(child, d + 1);
  };
  walk(root, 0);
  return {
    root: root as SVGSVGElement,
    removed: Array.from(new Set(removed)),
    elementCount: count,
  };
}
