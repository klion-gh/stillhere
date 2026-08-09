import type { WebSocket } from "ws";

const connections = new Map<string, Set<WebSocket>>();

export function addConnection(userId: string, socket: WebSocket) {
  let set = connections.get(userId);
  if (!set) {
    set = new Set();
    connections.set(userId, set);
  }
  set.add(socket);
}

export function removeConnection(userId: string, socket: WebSocket) {
  const set = connections.get(userId);
  if (!set) return;
  set.delete(socket);
  if (set.size === 0) {
    connections.delete(userId);
  }
}

export function isOnline(userId: string): boolean {
  return connections.has(userId);
}

export function sendToUser(userId: string, payload: unknown): boolean {
  const set = connections.get(userId);
  if (!set || set.size === 0) return false;
  const data = JSON.stringify(payload);
  for (const socket of set) {
    if (socket.readyState === socket.OPEN) {
      socket.send(data);
    }
  }
  return true;
}
