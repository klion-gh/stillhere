import "dotenv/config";
import Fastify from "fastify";
import cors from "@fastify/cors";
import websocket from "@fastify/websocket";
import { env } from "./config/env.js";
import authPlugin from "./plugins/auth.js";
import nodeGatePlugin from "./plugins/node-gate.js";
import { authRoutes } from "./modules/auth/routes.js";
import { userRoutes } from "./modules/users/routes.js";
import { conversationRoutes } from "./modules/conversations/routes.js";
import { callRoutes } from "./modules/calls/routes.js";
import { nodeRoutes } from "./modules/node/routes.js";
import { bootstrapNodeConfig } from "./modules/node/bootstrap.js";
import { wsGateway } from "./ws/gateway.js";

const app = Fastify({ logger: true });

await app.register(cors, { origin: env.CORS_ORIGIN === "*" ? true : env.CORS_ORIGIN.split(",") });
await app.register(websocket);
await app.register(authPlugin);
await app.register(nodeGatePlugin);

app.get("/health", async () => ({ status: "ok" }));

await app.register(nodeRoutes);
await app.register(authRoutes);
await app.register(userRoutes);
await app.register(conversationRoutes);
await app.register(callRoutes);
await app.register(wsGateway);

try {
  await bootstrapNodeConfig();
  await app.listen({ port: env.PORT, host: env.HOST });
} catch (err) {
  app.log.error(err);
  process.exit(1);
}
