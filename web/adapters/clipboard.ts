import { BridgeError } from "./protocol";

export async function writeText(text: string): Promise<void> {
  if (!navigator.clipboard || typeof navigator.clipboard.writeText !== "function") {
    throw new BridgeError("clipboard.unavailable", "The system clipboard is not available");
  }
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    throw new BridgeError("clipboard.denied", "Clipboard access was denied");
  }
}

export async function readText(): Promise<string> {
  if (!navigator.clipboard || typeof navigator.clipboard.readText !== "function") {
    throw new BridgeError("clipboard.unavailable", "Reading the system clipboard is not available");
  }
  try {
    return await navigator.clipboard.readText();
  } catch {
    throw new BridgeError("clipboard.denied", "Clipboard read was denied");
  }
}
