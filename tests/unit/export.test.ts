// @vitest-environment jsdom
import { describe, expect, it } from "vitest";
import { playerHtml, validateSvgText } from "../../web/adapters/export";
import { sanitizeFileName } from "../../web/adapters/files";

describe("export validation", () => {
  it("accepts a valid SVG and rejects broken or scripted output", () => {
    expect(() =>
      validateSvgText('<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>'),
    ).not.toThrow();
    expect(() => validateSvgText("<svg><rect></svg>")).toThrow(/parse/);
    expect(() =>
      validateSvgText('<svg xmlns="http://www.w3.org/2000/svg"><script>1</script></svg>'),
    ).toThrow(/script/);
    expect(() => validateSvgText('<div xmlns="http://www.w3.org/1999/xhtml"/>')).toThrow(
      /not an SVG/,
    );
  });

  it("sanitises output file names", () => {
    expect(sanitizeFileName("../../etc/passwd")).not.toMatch(/\//);
    expect(sanitizeFileName("my scene: v2?.svg")).toBe("my scene- v2-.svg");
    expect(sanitizeFileName("")).toBe("framewise-export");
  });

  it("builds a player page that cannot be broken out of by the animation JSON", () => {
    const html = playerHtml(
      "T</title><script>x</script>",
      '<svg xmlns="http://www.w3.org/2000/svg"/>',
      JSON.stringify({ evil: "</script><script>alert(1)</script>" }),
      "0.1.0",
    );
    expect(html).not.toContain("</script><script>alert(1)");
    expect(html).toContain("<\\/script>");
    expect(html).toContain("&lt;script&gt;");
    expect(html).toContain("Content-Security-Policy");
    expect(html).not.toMatch(/(src|href)=["']https?:/);
  });
});
