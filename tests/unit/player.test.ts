import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import "../../web/player/framewise-player.js";

interface PlayerApi {
  evaluate(
    animation: unknown,
    frame: number,
  ): Record<
    string,
    {
      matrix: { e: number; f: number };
      opacity: number;
      transform: { rotation: number; scale: { x: number; y: number } };
      fill: { r: number; a: number } | null;
      rectSize: { x: number } | null;
    }
  >;
  evaluateEasing(easing: unknown, u: number): number;
  mapFrame(mode: string, n: number, frame: number): number;
}

const Player = (globalThis as unknown as { FramewisePlayer: PlayerApi }).FramewisePlayer;

interface Golden {
  name: string;
  animation: unknown;
  expectations: Array<{
    frame: number;
    nodeId: string;
    property: string;
    value: number | number[];
    tolerance?: number;
  }>;
}

const goldenDir = resolve(__dirname, "../golden");
const goldens: Golden[] = readdirSync(goldenDir)
  .filter((f) => f.endsWith(".json"))
  .map((f) => JSON.parse(readFileSync(resolve(goldenDir, f), "utf8")) as Golden);

function read(
  state: ReturnType<PlayerApi["evaluate"]>[string],
  property: string,
): number | number[] {
  switch (property) {
    case "position":
      return [state.matrix.e, state.matrix.f];
    case "opacity":
      return state.opacity;
    case "rotation":
      return state.transform.rotation;
    case "scale":
      return [state.transform.scale.x, state.transform.scale.y];
    case "fill":
      return state.fill ? [state.fill.r, state.fill.a] : [-1, -1];
    case "rectWidth":
      return state.rectSize ? state.rectSize.x : -1;
    default:
      throw new Error(`unknown golden property ${property}`);
  }
}

describe("player evaluator against golden fixtures", () => {
  for (const golden of goldens) {
    it(golden.name, () => {
      for (const exp of golden.expectations) {
        const states = Player.evaluate(golden.animation, exp.frame);
        const actual = read(states[exp.nodeId]!, exp.property);
        const tolerance = exp.tolerance ?? 1e-6;
        if (Array.isArray(exp.value)) {
          expect(Array.isArray(actual)).toBe(true);
          (exp.value as number[]).forEach((v, i) =>
            expect((actual as number[])[i]).toBeCloseTo(
              v,
              5 - Math.round(Math.log10(tolerance * 1e5)),
            ),
          );
        } else {
          expect(Math.abs((actual as number) - exp.value)).toBeLessThanOrEqual(tolerance);
        }
      }
    });
  }
});

describe("player primitives", () => {
  it("easing endpoints are exact", () => {
    for (const e of [
      { type: "hold" },
      { type: "linear" },
      { type: "preset", name: "ease-in-out" },
      { type: "preset", name: "bounce-out" },
      { type: "cubicBezier", x1: 0.3, y1: -0.2, x2: 0.7, y2: 1.3 },
      { type: "spring", mass: 1, stiffness: 170, damping: 20, velocity: 0 },
    ]) {
      expect(Player.evaluateEasing(e, 0)).toBe(0);
      expect(Player.evaluateEasing(e, 1)).toBe(1);
    }
  });
  it("loop mapping matches the editor semantics", () => {
    expect(Player.mapFrame("once", 60, 75)).toBe(60);
    expect(Player.mapFrame("repeat", 60, 60)).toBe(0);
    expect(Player.mapFrame("repeat", 60, -10)).toBe(50);
    expect(Player.mapFrame("pingpong", 60, 75)).toBe(45);
  });
});
