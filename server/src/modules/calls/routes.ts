import type { FastifyInstance } from "fastify";
import { buildIceServers } from "./ice.js";

export async function callRoutes(app: FastifyInstance) {
  app.get("/calls/ice-servers", { preHandler: app.authenticate }, async (request, reply) => {
    return reply.send({ iceServers: buildIceServers(request.userId!) });
  });
}
