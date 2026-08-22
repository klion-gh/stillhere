/**
 * The outer door: every request must prove it knows the node password, in the
 * form of a token issued at pairing.
 *
 * A private node is not a public API. Only pairing, health and the socket are
 * exempt — the socket carries its token in the query string, because a browser
 * or mobile client can't always set headers on the handshake.
 */
import fp from "fastify-plugin";
import type { FastifyPluginAsync } from "fastify";
import { verifyNodeToken } from "../modules/node/tokens.js";

// Paths reachable without proving you know the node password. /ws checks
// its own ?nodeToken= query param inside the gateway handler instead of a
// header, since WS clients can't always set custom handshake headers.
const EXEMPT_PATHS = new Set(["/health", "/node/pair", "/ws"]);

const nodeGatePlugin: FastifyPluginAsync = async (app) => {
  app.addHook("onRequest", async (request, reply) => {
    const path = request.url.split("?")[0];
    if (EXEMPT_PATHS.has(path)) {
      return;
    }

    const header = request.headers["x-node-token"];
    const token = Array.isArray(header) ? header[0] : header;
    if (!token) {
      return reply.code(401).send({ error: "missing_node_token" });
    }
    try {
      verifyNodeToken(token);
    } catch {
      return reply.code(401).send({ error: "invalid_node_token" });
    }
  });
};

export default fp(nodeGatePlugin);
