/**
 * Conversations: creating one, listing them with their last message, and
 * paging through history.
 */
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { prisma } from "../../db/prisma.js";
import { normalizeUsername } from "../users/username.js";
import { publicUser } from "../users/public_user.js";
import { sendToUser } from "../../ws/connections.js";

const createConversationSchema = z.object({
  tag: z.string().min(1),
});

const messagesQuerySchema = z.object({
  before: z.string().datetime().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

function orderedPair(a: string, b: string): [string, string] {
  return a < b ? [a, b] : [b, a];
}

export async function conversationRoutes(app: FastifyInstance) {
  app.post("/conversations", { preHandler: app.authenticate }, async (request, reply) => {
    const parsed = createConversationSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_body" });
    }

    const targetUsername = normalizeUsername(parsed.data.tag);
    const target = await prisma.user.findUnique({ where: { username: targetUsername } });
    if (!target) {
      return reply.code(404).send({ error: "user_not_found" });
    }
    if (target.id === request.userId) {
      return reply.code(400).send({ error: "cannot_message_self" });
    }

    const [userAId, userBId] = orderedPair(request.userId!, target.id);

    const existing = await prisma.conversation.findUnique({
      where: { userAId_userBId: { userAId, userBId } },
      include: { userA: true, userB: true },
    });

    const conversation =
      existing ??
      (await prisma.conversation.create({
        data: { userAId, userBId },
        include: { userA: true, userB: true },
      }));

    const peer = conversation.userA.id === request.userId ? conversation.userB : conversation.userA;
    const self = conversation.userA.id === request.userId ? conversation.userA : conversation.userB;

    // Push the new conversation to the other side so it appears in their
    // list immediately. Without this the peer only learns about it on a
    // manual refresh — and until then an incoming message or call from
    // someone who "added" them has no conversation to attach to.
    if (!existing) {
      sendToUser(peer.id, {
        type: "conversation:new",
        conversation: {
          id: conversation.id,
          peer: publicUser(self),
          createdAt: conversation.createdAt,
        },
      });
      request.log.info({ userId: request.userId, peerId: peer.id, conversationId: conversation.id }, "conversation created");
    }

    return reply.send({
      id: conversation.id,
      peer: publicUser(peer),
      createdAt: conversation.createdAt,
    });
  });

  app.get("/conversations", { preHandler: app.authenticate }, async (request, reply) => {
    const conversations = await prisma.conversation.findMany({
      where: { OR: [{ userAId: request.userId }, { userBId: request.userId }] },
      include: {
        userA: true,
        userB: true,
        // The list shows the last message rather than a timestamp, so it
        // comes down with the conversation instead of costing a request per
        // row.
        messages: { orderBy: { createdAt: "desc" }, take: 1 },
      },
    });

    const payload = conversations.map((c) => {
      const peer = c.userA.id === request.userId ? c.userB : c.userA;
      const last = c.messages[0];
      return {
        id: c.id,
        peer: publicUser(peer),
        createdAt: c.createdAt,
        lastMessage: last
          ? {
              content: last.content,
              createdAt: last.createdAt,
              fromMe: last.senderId === request.userId,
            }
          : null,
      };
    });

    // Most recently active first — a list ordered by when a chat was created
    // gets useless as soon as you have a few.
    payload.sort((a, b) => {
      const at = a.lastMessage?.createdAt ?? a.createdAt;
      const bt = b.lastMessage?.createdAt ?? b.createdAt;
      return bt.getTime() - at.getTime();
    });

    return reply.send(payload);
  });

  app.get("/conversations/:id/messages", { preHandler: app.authenticate }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const parsed = messagesQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_query" });
    }

    const conversation = await prisma.conversation.findUnique({ where: { id } });
    if (!conversation || (conversation.userAId !== request.userId && conversation.userBId !== request.userId)) {
      return reply.code(404).send({ error: "conversation_not_found" });
    }

    const messages = await prisma.message.findMany({
      where: {
        conversationId: id,
        ...(parsed.data.before ? { createdAt: { lt: new Date(parsed.data.before) } } : {}),
      },
      orderBy: { createdAt: "desc" },
      take: parsed.data.limit,
    });

    return reply.send(messages.reverse());
  });
}
