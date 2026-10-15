/** Typed bridge envelopes. Every message is validated at ingress. */

export const PROTOCOL_VERSION = 1;

export interface Request {
  protocolVersion: number;
  requestId: string;
  operation: string;
  documentId: string | null;
  revision: number | null;
  payload: unknown;
}

export interface OkResponse {
  protocolVersion: number;
  requestId: string;
  operation: string;
  status: "ok";
  payload: unknown;
}

export interface ErrorResponse {
  protocolVersion: number;
  requestId: string;
  operation: string;
  status: "error";
  code: string;
  message: string;
  retryable: boolean;
  payload?: unknown;
}

export interface EventMessage {
  protocolVersion: number;
  requestId: string;
  operation: string;
  status: "event";
  payload: unknown;
}

export type Response = OkResponse | ErrorResponse | EventMessage;

export class BridgeError extends Error {
  code: string;
  retryable: boolean;
  payload: unknown;
  constructor(code: string, message: string, retryable = false, payload: unknown = undefined) {
    super(message);
    this.code = code;
    this.retryable = retryable;
    this.payload = payload;
  }
}

const OPERATION_PATTERN = /^[a-z][a-zA-Z0-9]*\.[a-z][a-zA-Z0-9]*$/;

/** Validate an incoming request envelope. Throws BridgeError on malformed input. */
export function validateRequest(value: unknown): Request {
  if (typeof value !== "object" || value === null) {
    throw new BridgeError("protocol.invalid", "Request is not an object");
  }
  const v = value as Record<string, unknown>;
  if (v.protocolVersion !== PROTOCOL_VERSION) {
    throw new BridgeError(
      "protocol.version",
      `Unsupported protocol version ${String(v.protocolVersion)}`,
    );
  }
  if (typeof v.requestId !== "string" || v.requestId.length === 0 || v.requestId.length > 200) {
    throw new BridgeError("protocol.invalid", "Missing request id");
  }
  if (typeof v.operation !== "string" || !OPERATION_PATTERN.test(v.operation)) {
    throw new BridgeError("protocol.invalid", "Invalid operation name");
  }
  const documentId = typeof v.documentId === "string" ? v.documentId : null;
  const revision =
    typeof v.revision === "number" && Number.isInteger(v.revision) ? v.revision : null;
  return {
    protocolVersion: PROTOCOL_VERSION,
    requestId: v.requestId,
    operation: v.operation,
    documentId,
    revision,
    payload: v.payload,
  };
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function requireString(payload: unknown, key: string): string {
  if (!isRecord(payload) || typeof payload[key] !== "string") {
    throw new BridgeError("payload.invalid", `Expected string field "${key}"`);
  }
  return payload[key] as string;
}

export function optionalString(payload: unknown, key: string): string | null {
  if (!isRecord(payload)) return null;
  const v = payload[key];
  return typeof v === "string" ? v : null;
}

export function requireNumber(payload: unknown, key: string): number {
  if (
    !isRecord(payload) ||
    typeof payload[key] !== "number" ||
    !Number.isFinite(payload[key] as number)
  ) {
    throw new BridgeError("payload.invalid", `Expected numeric field "${key}"`);
  }
  return payload[key] as number;
}

export function optionalBoolean(payload: unknown, key: string, fallback: boolean): boolean {
  if (!isRecord(payload)) return fallback;
  const v = payload[key];
  return typeof v === "boolean" ? v : fallback;
}
