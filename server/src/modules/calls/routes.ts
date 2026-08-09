import type { FastifyInstance } from "fastify";
import { buildIceServers } from "./ice.js";

export async function callRoutes(app: FastifyInstance) {
  app.get("/calls/ice-servers", { preHandler: app.authenticate }, async (request, reply) => {
    const iceServers = buildIceServers(request.userId!);
    const hasTurn = iceServers.some((s) => JSON.stringify(s.urls).includes("turn:"));
    request.log.info({ userId: request.userId, hasTurn }, "calls/ice-servers: issued");
    return reply.send({ iceServers });
  });
}
