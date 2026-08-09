import type { FastifyInstance } from "fastify";
import bcrypt from "bcrypt";
import { z } from "zod";
import { prisma } from "../../db/prisma.js";
import { signNodeToken } from "./tokens.js";

const pairSchema = z.object({
  password: z.string().min(1),
});

export async function nodeRoutes(app: FastifyInstance) {
  app.post("/node/pair", async (request, reply) => {
    const parsed = pairSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_body" });
    }

    const config = await prisma.nodeConfig.findFirst();
    if (!config) {
      request.log.error("node/pair: no NodeConfig row — bootstrap did not run");
      return reply.code(503).send({ error: "node_not_configured" });
    }

    const ok = await bcrypt.compare(parsed.data.password, config.passwordHash);
    if (!ok) {
      request.log.warn({ ip: request.ip }, "node/pair: wrong password");
      return reply.code(401).send({ error: "invalid_node_password" });
    }

    request.log.info({ ip: request.ip }, "node/pair: paired successfully");
    return reply.send({ nodeToken: signNodeToken() });
  });
}
