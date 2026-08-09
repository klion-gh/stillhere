import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { prisma } from "../../db/prisma.js";
import { normalizeUsername } from "./username.js";

const lookupQuerySchema = z.object({
  tag: z.string().min(1),
});

export async function userRoutes(app: FastifyInstance) {
  app.get("/users/lookup", { preHandler: app.authenticate }, async (request, reply) => {
    const parsed = lookupQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_query" });
    }

    const username = normalizeUsername(parsed.data.tag);
    const user = await prisma.user.findUnique({ where: { username } });
    if (!user) {
      return reply.code(404).send({ error: "user_not_found" });
    }
    if (user.id === request.userId) {
      return reply.code(400).send({ error: "cannot_lookup_self" });
    }

    return reply.send({ id: user.id, username: user.username });
  });
}
