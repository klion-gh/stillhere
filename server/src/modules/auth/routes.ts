/**
 * Registration, sign-in and token renewal.
 */
import type { FastifyInstance } from "fastify";
import bcrypt from "bcrypt";
import { z } from "zod";
import { prisma } from "../../db/prisma.js";
import { normalizeUsername, isValidUsername } from "../users/username.js";
import { publicUser } from "../users/public_user.js";
import { signAccessToken, signRefreshToken, verifyRefreshToken } from "./tokens.js";

const credentialsSchema = z.object({
  username: z.string().min(1),
  password: z.string().min(8).max(200),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

const BCRYPT_ROUNDS = 12;

export async function authRoutes(app: FastifyInstance) {
  app.post("/auth/register", async (request, reply) => {
    const parsed = credentialsSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_body", details: parsed.error.flatten() });
    }

    const username = normalizeUsername(parsed.data.username);
    if (!isValidUsername(username)) {
      return reply.code(400).send({
        error: "invalid_username",
        message: "Username must be 3-20 characters: letters, digits, underscore.",
      });
    }

    const existing = await prisma.user.findUnique({ where: { username } });
    if (existing) {
      request.log.warn({ username }, "auth/register: username taken");
      return reply.code(409).send({ error: "username_taken" });
    }

    const passwordHash = await bcrypt.hash(parsed.data.password, BCRYPT_ROUNDS);
    const user = await prisma.user.create({ data: { username, passwordHash } });
    request.log.info({ userId: user.id, username }, "auth/register: new user");

    const accessToken = signAccessToken(user.id, user.username);
    const refreshToken = signRefreshToken(user.id);
    return reply.code(201).send({
      user: publicUser(user),
      accessToken,
      refreshToken,
    });
  });

  app.post("/auth/login", async (request, reply) => {
    const parsed = credentialsSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_body" });
    }

    const username = normalizeUsername(parsed.data.username);
    const user = await prisma.user.findUnique({ where: { username } });
    if (!user) {
      request.log.warn({ username }, "auth/login: no such user");
      return reply.code(401).send({ error: "invalid_credentials" });
    }

    const ok = await bcrypt.compare(parsed.data.password, user.passwordHash);
    if (!ok) {
      request.log.warn({ userId: user.id, username }, "auth/login: wrong password");
      return reply.code(401).send({ error: "invalid_credentials" });
    }

    request.log.info({ userId: user.id, username }, "auth/login: success");
    const accessToken = signAccessToken(user.id, user.username);
    const refreshToken = signRefreshToken(user.id);
    return reply.send({
      user: publicUser(user),
      accessToken,
      refreshToken,
    });
  });

  app.post("/auth/refresh", async (request, reply) => {
    const parsed = refreshSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_body" });
    }

    try {
      const payload = verifyRefreshToken(parsed.data.refreshToken);
      const user = await prisma.user.findUnique({ where: { id: payload.sub } });
      if (!user) {
        return reply.code(401).send({ error: "invalid_refresh_token" });
      }
      const accessToken = signAccessToken(user.id, user.username);
      const refreshToken = signRefreshToken(user.id);
      return reply.send({ accessToken, refreshToken });
    } catch {
      return reply.code(401).send({ error: "invalid_refresh_token" });
    }
  });
}
