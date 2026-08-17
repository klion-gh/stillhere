import type { FastifyInstance } from "fastify";
import { prisma } from "../../db/prisma.js";
import { sendToUser } from "../../ws/connections.js";
import { dropPendingCall } from "../../ws/pending_calls.js";
import { buildIceServers } from "./ice.js";

export async function callRoutes(app: FastifyInstance) {
  app.get("/calls/ice-servers", { preHandler: app.authenticate }, async (request, reply) => {
    const iceServers = buildIceServers(request.userId!);
    const hasTurn = iceServers.some((s) => JSON.stringify(s.urls).includes("turn:"));
    request.log.info({ userId: request.userId, hasTurn }, "calls/ice-servers: issued");
    return reply.send({ iceServers });
  });

  // Declining from the notification of an app that isn't running. That runs
  // in a background isolate with no WebSocket, so the hang-up can't go over
  // the socket the way it does everywhere else.
  app.post("/calls/:conversationId/decline", { preHandler: app.authenticate }, async (request, reply) => {
    const { conversationId } = request.params as { conversationId: string };

    const conversation = await prisma.conversation.findUnique({ where: { id: conversationId } });
    if (
      !conversation ||
      (conversation.userAId !== request.userId && conversation.userBId !== request.userId)
    ) {
      return reply.code(404).send({ error: "conversation_not_found" });
    }

    const peerId =
      conversation.userAId === request.userId ? conversation.userBId : conversation.userAId;

    // Clear whatever was parked for us, or reopening the app would show a
    // phantom incoming call for the one just declined.
    dropPendingCall(request.userId!, conversationId);
    const delivered = sendToUser(peerId, { type: "call:end", conversationId, from: request.userId });
    request.log.info(
      { userId: request.userId, peerId, conversationId, delivered },
      "calls: declined over HTTP",
    );

    return reply.send({ ok: true });
  });
}
