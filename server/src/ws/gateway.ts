import type { FastifyInstance, FastifyBaseLogger } from "fastify";
import type { WebSocket } from "ws";
import { z } from "zod";
import { prisma } from "../db/prisma.js";
import { verifyAccessToken } from "../modules/auth/tokens.js";
import { verifyNodeToken } from "../modules/node/tokens.js";
import { addConnection, removeConnection, sendToUser, isOnline, startHeartbeat } from "./connections.js";
import { sendToUserDevices, isPushEnabled } from "../modules/push/firebase.js";
import { holdCallOffer, takePendingCall, dropPendingCall, sweepExpiredCalls } from "./pending_calls.js";

const clientMessageSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("message:send"), conversationId: z.string(), content: z.string().min(1).max(4000), clientId: z.string().optional() }),
  z.object({ type: z.literal("call:offer"), conversationId: z.string(), sdp: z.unknown() }),
  z.object({ type: z.literal("call:answer"), conversationId: z.string(), sdp: z.unknown() }),
  z.object({ type: z.literal("call:ice-candidate"), conversationId: z.string(), candidate: z.unknown() }),
  z.object({ type: z.literal("call:end"), conversationId: z.string() }),
  // Application-level round trip so the client can show its latency to the
  // node. (The protocol-level ping/pong used by the heartbeat isn't exposed
  // to application code on either end.)
  z.object({ type: z.literal("net:ping"), sentAt: z.number() }),
  // A peer's measured latency, forwarded so both sides of a call can show
  // each other's connection quality.
  z.object({ type: z.literal("call:stats"), conversationId: z.string(), rttMs: z.number().int().min(0).max(60000) }),
]);

async function getPeerId(conversationId: string, userId: string): Promise<string | null> {
  const conversation = await prisma.conversation.findUnique({ where: { id: conversationId } });
  if (!conversation) return null;
  if (conversation.userAId !== userId && conversation.userBId !== userId) return null;
  return conversation.userAId === userId ? conversation.userBId : conversation.userAId;
}

async function broadcastPresence(userId: string, status: "online" | "offline") {
  const conversations = await prisma.conversation.findMany({
    where: { OR: [{ userAId: userId }, { userBId: userId }] },
  });
  for (const c of conversations) {
    const peerId = c.userAId === userId ? c.userBId : c.userAId;
    sendToUser(peerId, { type: "presence:update", userId, status });
  }
}

export async function wsGateway(app: FastifyInstance) {
  const log: FastifyBaseLogger = app.log;

  const stopHeartbeat = startHeartbeat(log);
  const sweeper = setInterval(sweepExpiredCalls, 60_000);
  sweeper.unref?.();
  app.addHook("onClose", async () => {
    stopHeartbeat();
    clearInterval(sweeper);
  });

  app.get("/ws", { websocket: true }, (socket: WebSocket, request) => {
    const { token, nodeToken } = request.query as { token?: string; nodeToken?: string };

    if (!nodeToken) {
      log.warn({ ip: request.ip }, "ws: rejected, missing node token");
      socket.close(4001, "missing_node_token");
      return;
    }
    try {
      verifyNodeToken(nodeToken);
    } catch {
      log.warn({ ip: request.ip }, "ws: rejected, invalid node token");
      socket.close(4001, "invalid_node_token");
      return;
    }

    if (!token) {
      log.warn({ ip: request.ip }, "ws: rejected, missing user token");
      socket.close(4001, "missing_token");
      return;
    }

    let userId: string;
    let username: string;
    try {
      const payload = verifyAccessToken(token);
      userId = payload.sub;
      username = payload.username;
    } catch {
      log.warn({ ip: request.ip }, "ws: rejected, invalid user token");
      socket.close(4001, "invalid_token");
      return;
    }

    log.info({ userId }, "ws: connected");
    addConnection(userId, socket);
    void broadcastPresence(userId, "online");

    // If a call woke this device, the offer has been waiting for the socket
    // to exist. Hand it over now.
    const parked = takePendingCall(userId);
    if (parked) {
      log.info({ userId }, "ws: delivering call offer held while device was offline");
      sendToUser(userId, parked);
    }

    socket.on("message", (raw: Buffer) => {
      void (async () => {
        let parsedJson: unknown;
        try {
          parsedJson = JSON.parse(raw.toString());
        } catch {
          log.warn({ userId }, "ws: dropped non-JSON frame");
          return;
        }

        const parsed = clientMessageSchema.safeParse(parsedJson);
        if (!parsed.success) {
          log.warn({ userId, issues: parsed.error.issues }, "ws: dropped frame failing schema validation");
          return;
        }
        const msg = parsed.data;

        // Latency probe: echoed straight back, no conversation involved.
        if (msg.type === "net:ping") {
          sendToUser(userId, { type: "net:pong", sentAt: msg.sentAt });
          return;
        }

        const peerId = await getPeerId(msg.conversationId, userId);
        if (!peerId) {
          log.warn({ userId, conversationId: msg.conversationId, type: msg.type }, "ws: dropped, no such conversation for sender");
          return;
        }

        if (msg.type === "message:send") {
          let saved = await prisma.message.create({
            data: { conversationId: msg.conversationId, senderId: userId, content: msg.content },
          });
          // The sender's tag rides along so the recipient can render a
          // notification without first resolving the conversation.
          const delivered = sendToUser(peerId, {
            type: "message:new",
            message: saved,
            senderUsername: username,
            clientId: msg.clientId,
          });
          log.info({ userId, peerId, conversationId: msg.conversationId, delivered }, "ws: message relayed");
          if (delivered) {
            saved = await prisma.message.update({ where: { id: saved.id }, data: { deliveredAt: new Date() } });
          } else {
            // Not connected: wake their device so the message shows up now
            // rather than whenever they next open the app.
            void sendToUserDevices(
              peerId,
              {
                urgent: false,
                data: {
                  kind: "message",
                  conversationId: msg.conversationId,
                  senderUsername: username,
                  preview: msg.content.slice(0, 180),
                },
              },
              log,
            );
          }
          sendToUser(userId, { type: "message:ack", message: saved, clientId: msg.clientId, delivered });
          return;
        }

        // WebRTC signaling and call telemetry: pure relay, no persistence.
        const delivered = sendToUser(peerId, { ...msg, from: userId });
        // call:stats repeats every couple of seconds for the whole call —
        // logging it at info level would drown out everything else.
        if (msg.type !== "call:stats") {
          log.info({ userId, peerId, conversationId: msg.conversationId, type: msg.type, delivered }, "ws: call signal relayed");
        }

        // A caller hanging up should clear anything parked for the callee,
        // or they'd get a phantom incoming call on next connect.
        if (msg.type === "call:end") {
          dropPendingCall(peerId, msg.conversationId);
        }

        if (!delivered && msg.type === "call:offer") {
          const relayed = { ...msg, from: userId };
          const woken = await sendToUserDevices(
            peerId,
            {
              urgent: true,
              data: {
                kind: "call",
                conversationId: msg.conversationId,
                callerUsername: username,
              },
            },
            log,
          );

          if (woken > 0) {
            // Park the offer: the device is starting up and its socket
            // doesn't exist yet, so there's nothing to deliver to for another
            // second or two.
            holdCallOffer(peerId, msg.conversationId, relayed);
            log.info({ userId, peerId, conversationId: msg.conversationId }, "ws: callee offline, woken by push");
          } else {
            sendToUser(userId, { type: "call:unavailable", conversationId: msg.conversationId });
            log.warn(
              { userId, peerId, conversationId: msg.conversationId, pushEnabled: isPushEnabled() },
              "ws: callee unreachable, offer not delivered",
            );
          }
        }
      })();
    });

    socket.on("close", () => {
      log.info({ userId }, "ws: disconnected");
      removeConnection(userId, socket);
      if (!isOnline(userId)) {
        void broadcastPresence(userId, "offline");
      }
    });
  });
}
