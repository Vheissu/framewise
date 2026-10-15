/**
 * Drag sideways on a numeric field to change its value, the way desktop motion
 * tools let you scrub "hot text". Movement is turned into the same ArrowUp and
 * ArrowDown keydowns the keyboard sends, so Elm still owns the value, the step
 * size (Shift multiplies by ten) and the undo history, which coalesces the
 * whole drag into one step. A click without movement focuses the field for
 * typing with its text selected.
 */
const PIXELS_PER_STEP = 3;
const DRAG_THRESHOLD = 3;

export function enableScrubbing(root: Document = document): void {
  root.addEventListener(
    "pointerdown",
    (event) => {
      const input = event.target;
      if (!(input instanceof HTMLInputElement) || !input.matches("input[data-scrub]")) return;
      if (event.button !== 0 || input.disabled || root.activeElement === input) return;
      event.preventDefault();

      const pointerId = event.pointerId;
      const startX = event.clientX;
      let lastX = startX;
      let carried = 0;
      let scrubbing = false;
      try {
        input.setPointerCapture(pointerId);
      } catch {
        // capture is a nicety; movement still arrives while over the field
      }

      const move = (e: PointerEvent): void => {
        if (e.pointerId !== pointerId) return;
        if (!scrubbing) {
          if (Math.abs(e.clientX - startX) < DRAG_THRESHOLD) return;
          scrubbing = true;
          lastX = e.clientX;
          root.body.classList.add("scrubbing");
          return;
        }
        carried += e.clientX - lastX;
        lastX = e.clientX;
        while (Math.abs(carried) >= PIXELS_PER_STEP) {
          const up = carried > 0;
          carried += up ? -PIXELS_PER_STEP : PIXELS_PER_STEP;
          input.dispatchEvent(
            new KeyboardEvent("keydown", {
              key: up ? "ArrowUp" : "ArrowDown",
              shiftKey: e.shiftKey,
              bubbles: true,
              cancelable: true,
            }),
          );
        }
      };

      const end = (e: PointerEvent): void => {
        if (e.pointerId !== pointerId) return;
        input.removeEventListener("pointermove", move);
        input.removeEventListener("pointerup", end);
        input.removeEventListener("pointercancel", end);
        root.body.classList.remove("scrubbing");
        if (!scrubbing && e.type === "pointerup") {
          input.focus();
          input.select();
        }
      };

      input.addEventListener("pointermove", move);
      input.addEventListener("pointerup", end);
      input.addEventListener("pointercancel", end);
    },
    true,
  );
}
