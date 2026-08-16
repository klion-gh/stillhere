import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { prisma } from "../../db/prisma.js";
import { getFirebaseClientConfig } from "./client_config.js";

const registerSchema = z.object({
  token: z.string().min(1).max(4096),
  platform: z.enum(["android", "ios", "windows"]),
});

const unregisterSchema = z.object({
  token: z.string().min(1).max(4096),
});

export async function pushRoutes(app: FastifyInstance) {
  /// Tells the client which Firebase project this node pushes through, so a
  /// single published APK works against any node. Gated by the node token
  /// like everything else, and deliberately carries no credentials — only
  /// the values already embedded in any published app.
  app.get("/node/push-config", async (request, reply) => {
    const config = getFirebaseClientConfig(request.log);
    if (!config) {
      return reply.send({ enabled: false });
    }
    return reply.send({ enabled: true, ...config });
  });

  app.post("/devices/register", { preHandler: app.authenticate }, async (request, reply) => {
    const parsed = registerSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_body" });
    }

    // A token can migrate between accounts when someone signs out and a
    // different user signs in on the same device, so claim it for the
    // current user rather than creating a duplicate.
    await prisma.deviceToken.upsert({
      where: { token: parsed.data.token },
      update: { userId: request.userId!, platform: parsed.data.platform },
      create: {
        userId: request.userId!,
        token: parsed.data.token,
        platform: parsed.data.platform,
      },
    });

    request.log.info({ userId: request.userId, platform: parsed.data.platform }, "devices: registered");
    return reply.send({ ok: true });
  });

  app.post("/devices/unregister", { preHandler: app.authenticate }, async (request, reply) => {
    const parsed = unregisterSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_body" });
    }

    await prisma.deviceToken.deleteMany({
      where: { token: parsed.data.token, userId: request.userId! },
    });
    request.log.info({ userId: request.userId }, "devices: unregistered");
    return reply.send({ ok: true });
  });
}
