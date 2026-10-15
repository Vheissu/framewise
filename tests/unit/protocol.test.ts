import { describe, expect, it } from "vitest";
import { BridgeError, validateRequest } from "../../web/adapters/protocol";

describe("bridge protocol", () => {
  it("accepts a well-formed envelope", () => {
    const req = validateRequest({
      protocolVersion: 1,
      requestId: "r1",
      operation: "storage.load",
      documentId: "d",
      revision: 3,
      payload: { a: 1 },
    });
    expect(req.operation).toBe("storage.load");
    expect(req.revision).toBe(3);
  });

  it("rejects unknown protocol versions", () => {
    expect(() => validateRequest({ protocolVersion: 2, requestId: "r", operation: "a.b" })).toThrow(
      BridgeError,
    );
  });

  it("rejects operation names that are not dotted identifiers", () => {
    for (const bad of ["eval", "a.b.c", "../x", "a b", "A.b", "a.", ".b"]) {
      expect(() => validateRequest({ protocolVersion: 1, requestId: "r", operation: bad })).toThrow(
        BridgeError,
      );
    }
  });

  it("rejects missing request ids", () => {
    expect(() => validateRequest({ protocolVersion: 1, operation: "a.b" })).toThrow(/request id/);
  });
});
