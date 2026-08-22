/**
 * Verifies the user's access token and attaches their identity to the request.
 * Applied per route, unlike the node gate, which covers everything.
 */
import fp from "fastify-plugin";
import type { FastifyPluginAsync, FastifyRequest, FastifyReply } from "fastify";
import { verifyAccessToken } from "../modules/auth/tokens.js";

declare module "fastify" {
  interface FastifyRequest {
    userId?: string;
    username?: string;
  }
}

async function authenticate(request: FastifyRequest, reply: FastifyReply) {
  const header = request.headers.authorization;
  if (!header?.startsWith("Bearer ")) {
    return reply.code(401).send({ error: "missing_token" });
  }
  try {
    const payload = verifyAccessToken(header.slice("Bearer ".length));
    request.userId = payload.sub;
    request.username = payload.username;
  } catch {
    return reply.code(401).send({ error: "invalid_token" });
  }
}

const authPlugin: FastifyPluginAsync = async (app) => {
  app.decorate("authenticate", authenticate);
};

declare module "fastify" {
  interface FastifyInstance {
    authenticate: typeof authenticate;
  }
}

export default fp(authPlugin);
export { authenticate };
