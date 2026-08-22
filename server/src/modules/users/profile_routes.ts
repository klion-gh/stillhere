/**
 * The signed-in user's own profile: picture, tag and password.
 *
 * Avatars are served without a user token — the node gate already limits this
 * to people paired with the node, and requiring more would mean every avatar
 * request had to carry a session.
 */
import type { FastifyInstance } from "fastify";
import bcrypt from "bcrypt";
import { z } from "zod";
import { prisma } from "../../db/prisma.js";
import { normalizeUsername, isValidUsername } from "./username.js";
import { signAccessToken, signRefreshToken } from "../auth/tokens.js";
import { sendToUser } from "../../ws/connections.js";

const BCRYPT_ROUNDS = 12;

/// Big enough for a decent avatar, small enough to sit in a row and be
/// fetched on a phone connection without thought.
const MAX_AVATAR_BYTES = 512 * 1024;
const ALLOWED_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);

const renameSchema = z.object({ username: z.string().min(1) });

const passwordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8).max(200),
});

const avatarSchema = z.object({
  // Base64 keeps this a plain JSON endpoint — no multipart plugin for one
  // small upload.
  data: z.string().min(1),
  mime: z.string().min(1),
});

export async function profileRoutes(app: FastifyInstance) {
  app.get("/users/me", { preHandler: app.authenticate }, async (request, reply) => {
    const user = await prisma.user.findUnique({ where: { id: request.userId! } });
    if (!user) return reply.code(404).send({ error: "user_not_found" });
    return reply.send({
      id: user.id,
      username: user.username,
      hasAvatar: user.avatar != null,
      avatarUpdatedAt: user.avatarUpdatedAt,
    });
  });

  /// Avatars are public to anyone paired with the node — the node token gate
  /// already covers that, and a per-user check would stop conversation lists
  /// from rendering peers.
  app.get("/users/:id/avatar", async (request, reply) => {
    const { id } = request.params as { id: string };
    const user = await prisma.user.findUnique({
      where: { id },
      select: { avatar: true, avatarMime: true, avatarUpdatedAt: true },
    });
    if (!user?.avatar || !user.avatarMime) {
      return reply.code(404).send({ error: "no_avatar" });
    }
    return reply
      .header("Content-Type", user.avatarMime)
      // Changing the avatar bumps avatarUpdatedAt, which clients append as a
      // query param to bust this.
      .header("Cache-Control", "public, max-age=86400")
      .send(Buffer.from(user.avatar));
  });

  app.post("/users/me/avatar", { preHandler: app.authenticate }, async (request, reply) => {
    const parsed = avatarSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "invalid_body" });

    if (!ALLOWED_MIME.has(parsed.data.mime)) {
      return reply.code(400).send({ error: "unsupported_type" });
    }

    let bytes: Buffer;
    try {
      bytes = Buffer.from(parsed.data.data, "base64");
    } catch {
      return reply.code(400).send({ error: "invalid_image" });
    }
    if (bytes.length === 0) return reply.code(400).send({ error: "invalid_image" });
    if (bytes.length > MAX_AVATAR_BYTES) return reply.code(413).send({ error: "image_too_large" });

    const updated = await prisma.user.update({
      where: { id: request.userId! },
      data: { avatar: bytes, avatarMime: parsed.data.mime, avatarUpdatedAt: new Date() },
    });
    request.log.info({ userId: request.userId, bytes: bytes.length }, "profile: avatar updated");
    return reply.send({ ok: true, avatarUpdatedAt: updated.avatarUpdatedAt });
  });

  app.delete("/users/me/avatar", { preHandler: app.authenticate }, async (request, reply) => {
    await prisma.user.update({
      where: { id: request.userId! },
      data: { avatar: null, avatarMime: null, avatarUpdatedAt: new Date() },
    });
    return reply.send({ ok: true });
  });

  app.post("/users/me/username", { preHandler: app.authenticate }, async (request, reply) => {
    const parsed = renameSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "invalid_body" });

    const username = normalizeUsername(parsed.data.username);
    if (!isValidUsername(username)) {
      return reply.code(400).send({ error: "invalid_username" });
    }

    const existing = await prisma.user.findUnique({ where: { username } });
    if (existing && existing.id !== request.userId) {
      return reply.code(409).send({ error: "username_taken" });
    }

    const user = await prisma.user.update({
      where: { id: request.userId! },
      data: { username },
    });

    // The tag is baked into the access token, so hand back a fresh pair
    // rather than leaving the client showing its old name until expiry.
    const accessToken = signAccessToken(user.id, user.username);
    const refreshToken = signRefreshToken(user.id);

    // Anyone in a conversation with them is displaying the old tag.
    const conversations = await prisma.conversation.findMany({
      where: { OR: [{ userAId: user.id }, { userBId: user.id }] },
    });
    for (const c of conversations) {
      const peerId = c.userAId === user.id ? c.userBId : c.userAId;
      sendToUser(peerId, { type: "peer:updated", userId: user.id, username: user.username });
    }

    request.log.info({ userId: user.id, username }, "profile: username changed");
    return reply.send({ user: { id: user.id, username: user.username }, accessToken, refreshToken });
  });

  app.post("/users/me/password", { preHandler: app.authenticate }, async (request, reply) => {
    const parsed = passwordSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "invalid_body" });

    const user = await prisma.user.findUnique({ where: { id: request.userId! } });
    if (!user) return reply.code(404).send({ error: "user_not_found" });

    const ok = await bcrypt.compare(parsed.data.currentPassword, user.passwordHash);
    if (!ok) {
      request.log.warn({ userId: user.id }, "profile: wrong current password");
      return reply.code(401).send({ error: "wrong_password" });
    }

    const passwordHash = await bcrypt.hash(parsed.data.newPassword, BCRYPT_ROUNDS);
    await prisma.user.update({ where: { id: user.id }, data: { passwordHash } });
    request.log.info({ userId: user.id }, "profile: password changed");
    return reply.send({ ok: true });
  });
}
