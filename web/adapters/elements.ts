/**
 * Small custom elements that give Elm what the virtual DOM cannot: element
 * geometry, safe insertion of generated SVG, and dialog focus management.
 */

class RectHost extends HTMLElement {
  private observer: ResizeObserver | null = null;
  private onScroll = () => this.report();

  connectedCallback(): void {
    this.observer = new ResizeObserver(() => this.report());
    this.observer.observe(this);
    window.addEventListener("scroll", this.onScroll, true);
    window.addEventListener("resize", this.onScroll);
    requestAnimationFrame(() => this.report());
  }

  disconnectedCallback(): void {
    this.observer?.disconnect();
    window.removeEventListener("scroll", this.onScroll, true);
    window.removeEventListener("resize", this.onScroll);
  }

  private report(): void {
    const rect = this.getBoundingClientRect();
    this.dispatchEvent(
      new CustomEvent("fwrect", {
        detail: { left: rect.left, top: rect.top, width: rect.width, height: rect.height },
      }),
    );
  }
}

/** Renders generated SVG text (our own exporter output) via DOMParser, never innerHTML. */
class SvgPreview extends HTMLElement {
  static get observedAttributes(): string[] {
    return ["data-svg"];
  }

  connectedCallback(): void {
    this.render();
  }

  attributeChangedCallback(): void {
    this.render();
  }

  private render(): void {
    const text = this.getAttribute("data-svg");
    while (this.firstChild) this.removeChild(this.firstChild);
    if (!text) return;
    const parsed = new DOMParser().parseFromString(text, "image/svg+xml");
    if (parsed.getElementsByTagName("parsererror").length > 0) return;
    const root = parsed.documentElement;
    // Output from our own exporter contains no scripts; strip defensively anyway.
    for (const script of Array.from(root.querySelectorAll("script"))) script.remove();
    this.appendChild(document.importNode(root, true));
  }
}

const FOCUSABLE =
  'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

class Dialog extends HTMLElement {
  private previouslyFocused: Element | null = null;
  private onKey = (event: KeyboardEvent) => {
    if (event.key !== "Tab") return;
    const focusable = Array.from(this.querySelectorAll<HTMLElement>(FOCUSABLE));
    if (focusable.length === 0) return;
    const first = focusable[0]!;
    const last = focusable[focusable.length - 1]!;
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  };

  connectedCallback(): void {
    this.previouslyFocused = document.activeElement;
    this.addEventListener("keydown", this.onKey);
    requestAnimationFrame(() => {
      const autofocus = this.querySelector<HTMLElement>("[autofocus]");
      const target =
        autofocus ??
        this.querySelector<HTMLElement>("input, select, textarea, button:not(.icon-button)") ??
        this.querySelector<HTMLElement>(FOCUSABLE);
      target?.focus();
    });
  }

  disconnectedCallback(): void {
    this.removeEventListener("keydown", this.onKey);
    if (this.previouslyFocused instanceof HTMLElement) this.previouslyFocused.focus();
  }
}

export function registerElements(): void {
  if (!customElements.get("fw-rect-host")) customElements.define("fw-rect-host", RectHost);
  if (!customElements.get("fw-svg-preview")) customElements.define("fw-svg-preview", SvgPreview);
  if (!customElements.get("fw-dialog")) customElements.define("fw-dialog", Dialog);
}
