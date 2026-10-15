import { BridgeError } from "./protocol";

/**
 * Rasterise an SVG document string to PNG. The SVG is loaded through a
 * same-origin Blob URL; only data: URIs are allowed inside it so the canvas
 * is never tainted by remote content.
 */
export async function svgToPng(
  svg: string,
  width: number,
  height: number,
  scale: number,
): Promise<Blob> {
  if (/href\s*=\s*["'](?!data:|#)/i.test(svg)) {
    throw new BridgeError(
      "raster.external",
      "The SVG references an external resource and cannot be rasterised safely",
    );
  }
  const w = Math.max(1, Math.round(width * scale));
  const h = Math.max(1, Math.round(height * scale));
  if (w * h > 64_000_000)
    throw new BridgeError("raster.tooLarge", "The output exceeds the 64 megapixel limit");
  const blob = new Blob([svg], { type: "image/svg+xml;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  try {
    const image = await loadImage(url);
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new BridgeError("raster.context", "Could not create a drawing context");
    ctx.drawImage(image, 0, 0, w, h);
    const png = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/png"));
    if (!png) throw new BridgeError("raster.encode", "PNG encoding failed");
    return png;
  } finally {
    URL.revokeObjectURL(url);
  }
}

function loadImage(url: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.decoding = "sync";
    image.onload = () => resolve(image);
    image.onerror = () =>
      reject(new BridgeError("raster.load", "The browser could not render the SVG"));
    image.src = url;
  });
}

/** Decode an image file to learn its natural size. */
export async function imageSize(blob: Blob): Promise<{ width: number; height: number }> {
  const url = URL.createObjectURL(blob);
  try {
    const image = await loadImage(url);
    return { width: image.naturalWidth, height: image.naturalHeight };
  } finally {
    URL.revokeObjectURL(url);
  }
}

export const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

export async function isPng(blob: Blob): Promise<boolean> {
  const head = new Uint8Array(await blob.slice(0, 8).arrayBuffer());
  return PNG_SIGNATURE.every((b, i) => head[i] === b);
}
