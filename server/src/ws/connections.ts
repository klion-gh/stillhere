import type { WebSocket } from "ws";

const connections = new Map<string, Set<WebSocket>>();

/// Sockets that answered our last ping. A socket that misses one full
/// heartbeat round is considered dead and torn down — without this, a
/// client that vanished without a close frame (mobile NAT dropping an idle
/// mapping, laptop suspended, network switched) stays registered forever
/// and every message routed to it is silently written into the void.
const alive = new WeakSet<WebSocket>();

const HEARTBEAT_INTERVAL_MS = 30_000;

export function addConnection(userId: string, socket: WebSocket) {
  let set = connections.get(userId);
  if (!set) {
    set = new Set();
    connections.set(userId, set);
  }
  set.add(socket);
  alive.add(socket);

  socket.on("pong", () => {
    alive.add(socket);
  });
}

export function removeConnection(userId: string, socket: WebSocket) {
  const set = connections.get(userId);
  if (!set) return;
  set.delete(socket);
  alive.delete(socket);
  if (set.size === 0) {
    connections.delete(userId);
  }
}

export function isOnline(userId: string): boolean {
  const set = connections.get(userId);
  if (!set) return false;
  for (const socket of set) {
    if (socket.readyState === socket.OPEN) return true;
  }
  return false;
}

/// Returns true only if the payload was actually written to at least one
/// open socket. (An earlier version returned true whenever the user had a
/// registered set at all, so `delivered: true` in the logs could be a lie
/// about a connection that was already closed.)
export function sendToUser(userId: string, payload: unknown): boolean {
  const set = connections.get(userId);
  if (!set || set.size === 0) return false;
  const data = JSON.stringify(payload);
  let delivered = false;
  for (const socket of set) {
    if (socket.readyState === socket.OPEN) {
      socket.send(data);
      delivered = true;
    }
  }
  return delivered;
}

/// Starts the ping/terminate loop. Returns a stop function for shutdown.
export function startHeartbeat(log: { info: (o: object, m: string) => void }): () => void {
  const timer = setInterval(() => {
    let reaped = 0;
    for (const [userId, set] of connections) {
      for (const socket of [...set]) {
        if (!alive.has(socket)) {
          // Missed a full round: no pong since the last tick.
          socket.terminate();
          removeConnection(userId, socket);
          reaped++;
          continue;
        }
        alive.delete(socket);
        try {
          socket.ping();
        } catch {
          socket.terminate();
          removeConnection(userId, socket);
          reaped++;
        }
      }
    }
    if (reaped > 0) {
      log.info({ reaped }, "ws: reaped dead connections");
    }
  }, HEARTBEAT_INTERVAL_MS);

  timer.unref?.();
  return () => clearInterval(timer);
}
