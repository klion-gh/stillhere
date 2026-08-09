import type { FastifyInstance } from "fastify";
import type { WebSocket } from "ws";
import { z } from "zod";
import { prisma } from "../db/prisma.js";
import { verifyAccessToken } from "../modules/auth/tokens.js";
import { verifyNodeToken } from "../modules/node/tokens.js";
import { addConnection, removeConnection, sendToUser, isOnline } from "./connections.js";

const clientMessageSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("message:send"), conversationId: z.string(), content: z.string().min(1).max(4000), clientId: z.string().optional() }),
  z.object({ type: z.literal("call:offer"), conversationId: z.string(), sdp: z.unknown() }),
  z.object({ type: z.literal("call:answer"), conversationId: z.string(), sdp: z.unknown() }),
  z.object({ type: z.literal("call:ice-candidate"), conversationId: z.string(), candidate: z.unknown() }),
  z.object({ type: z.literal("call:end"), conversationId: z.string() }),
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
  app.get("/ws", { websocket: true }, (socket: WebSocket, request) => {
    const { token, nodeToken } = request.query as { token?: string; nodeToken?: string };

    if (!nodeToken) {
      socket.close(4001, "missing_node_token");
      return;
    }
    try {
      verifyNodeToken(nodeToken);
    } catch {
      socket.close(4001, "invalid_node_token");
      return;
    }

    if (!token) {
      socket.close(4001, "missing_token");
      return;
    }

    let userId: string;
    try {
      const payload = verifyAccessToken(token);
      userId = payload.sub;
    } catch {
      socket.close(4001, "invalid_token");
      return;
    }

    addConnection(userId, socket);
    void broadcastPresence(userId, "online");

    socket.on("message", (raw: Buffer) => {
      void (async () => {
        let parsedJson: unknown;
        try {
          parsedJson = JSON.parse(raw.toString());
        } catch {
          return;
        }

        const parsed = clientMessageSchema.safeParse(parsedJson);
        if (!parsed.success) return;
        const msg = parsed.data;

        const peerId = await getPeerId(msg.conversationId, userId);
        if (!peerId) return;

        if (msg.type === "message:send") {
          let saved = await prisma.message.create({
            data: { conversationId: msg.conversationId, senderId: userId, content: msg.content },
          });
          const delivered = sendToUser(peerId, {
            type: "message:new",
            message: saved,
            clientId: msg.clientId,
          });
          if (delivered) {
            saved = await prisma.message.update({ where: { id: saved.id }, data: { deliveredAt: new Date() } });
          }
          sendToUser(userId, { type: "message:ack", message: saved, clientId: msg.clientId, delivered });
          return;
        }

        // WebRTC signaling: pure relay, no persistence.
        sendToUser(peerId, { ...msg, from: userId });
      })();
    });

    socket.on("close", () => {
      removeConnection(userId, socket);
      if (!isOnline(userId)) {
        void broadcastPresence(userId, "offline");
      }
    });
  });
}
