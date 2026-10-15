import {
  BridgeError,
  PROTOCOL_VERSION,
  validateRequest,
  type Request,
  type Response,
} from "./protocol";

export type Handler = (request: Request, bridge: Bridge) => Promise<unknown>;

interface ElmPorts {
  toJs: { subscribe(callback: (value: unknown) => void): void };
  fromJs: { send(value: unknown): void };
}

/**
 * The single port bridge. Handlers are registered by operation name; stale
 * responses for a document revision that moved on are still delivered (Elm
 * decides what to do), but handlers may consult `isCurrent` to skip work.
 */
export class Bridge {
  private handlers = new Map<string, Handler>();
  private ports: ElmPorts;
  private cancelled = new Set<string>();

  constructor(ports: ElmPorts) {
    this.ports = ports;
    ports.toJs.subscribe((value) => {
      void this.dispatch(value);
    });
  }

  register(operation: string, handler: Handler): void {
    this.handlers.set(operation, handler);
  }

  /** Emit an unsolicited event to Elm. */
  emit(operation: string, payload: unknown): void {
    const message: Response = {
      protocolVersion: PROTOCOL_VERSION,
      requestId: "",
      operation,
      status: "event",
      payload,
    };
    this.ports.fromJs.send(message);
  }

  /** Emit an unsolicited error for an operation (e.g. a dropped file that failed to import). */
  emitError(operation: string, error: BridgeError): void {
    const message: Response = {
      protocolVersion: PROTOCOL_VERSION,
      requestId: "",
      operation,
      status: "error",
      code: error.code,
      message: error.message,
      retryable: error.retryable,
      payload: error.payload,
    };
    this.ports.fromJs.send(message);
  }

  cancel(jobId: string): void {
    this.cancelled.add(jobId);
  }

  isCancelled(jobId: string): boolean {
    return this.cancelled.has(jobId);
  }

  private async dispatch(value: unknown): Promise<void> {
    let request: Request;
    try {
      request = validateRequest(value);
    } catch (error) {
      console.warn("Rejected malformed bridge request", error);
      return;
    }
    const handler = this.handlers.get(request.operation);
    if (!handler) {
      this.respondError(
        request,
        new BridgeError("operation.unknown", `Unknown operation ${request.operation}`),
      );
      return;
    }
    try {
      const payload = await handler(request, this);
      const response: Response = {
        protocolVersion: PROTOCOL_VERSION,
        requestId: request.requestId,
        operation: request.operation,
        status: "ok",
        payload,
      };
      this.ports.fromJs.send(response);
    } catch (error) {
      this.respondError(request, error);
    }
  }

  private respondError(request: Request, error: unknown): void {
    const bridgeError =
      error instanceof BridgeError
        ? error
        : error instanceof DOMException && error.name === "AbortError"
          ? new BridgeError("cancelled", "The operation was cancelled")
          : new BridgeError("internal", safeMessage(error), true);
    const response: Response = {
      protocolVersion: PROTOCOL_VERSION,
      requestId: request.requestId,
      operation: request.operation,
      status: "error",
      code: bridgeError.code,
      message: bridgeError.message,
      retryable: bridgeError.retryable,
      payload: bridgeError.payload ?? {
        documentId: request.documentId,
        revision: request.revision,
      },
    };
    this.ports.fromJs.send(response);
  }
}

function safeMessage(error: unknown): string {
  if (error instanceof Error) return error.message.slice(0, 300);
  return "Unexpected error";
}
