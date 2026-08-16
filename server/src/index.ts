import "dotenv/config";
import Fastify from "fastify";
import cors from "@fastify/cors";
import websocket from "@fastify/websocket";
import { env } from "./config/env.js";
import authPlugin from "./plugins/auth.js";
import nodeGatePlugin from "./plugins/node-gate.js";
import { authRoutes } from "./modules/auth/routes.js";
import { userRoutes } from "./modules/users/routes.js";
import { profileRoutes } from "./modules/users/profile_routes.js";
import { conversationRoutes } from "./modules/conversations/routes.js";
import { callRoutes } from "./modules/calls/routes.js";
import { nodeRoutes } from "./modules/node/routes.js";
import { bootstrapNodeConfig } from "./modules/node/bootstrap.js";
import { pushRoutes } from "./modules/push/routes.js";
import { initPush } from "./modules/push/firebase.js";
import { wsGateway } from "./ws/gateway.js";

const app = Fastify({
  logger: true,
  // Avatars arrive base64-encoded, which inflates a 512 KB image to roughly
  // 700 KB — uncomfortably close to Fastify's 1 MB default.
  bodyLimit: 2 * 1024 * 1024,
});

await app.register(cors, { origin: env.CORS_ORIGIN === "*" ? true : env.CORS_ORIGIN.split(",") });
await app.register(websocket);
await app.register(authPlugin);
await app.register(nodeGatePlugin);

app.get("/health", async () => ({ status: "ok" }));

await app.register(nodeRoutes);
await app.register(authRoutes);
await app.register(userRoutes);
await app.register(profileRoutes);
await app.register(conversationRoutes);
await app.register(callRoutes);
await app.register(pushRoutes);
await app.register(wsGateway);

initPush(app.log);

try {
  await bootstrapNodeConfig();
  await app.listen({ port: env.PORT, host: env.HOST });
} catch (err) {
  app.log.error(err);
  process.exit(1);
}
