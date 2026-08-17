import type { User } from "@prisma/client";

/// The shape every endpoint uses when it hands a user to a client.
export type PublicUser = {
  id: string;
  username: string;
  hasAvatar: boolean;
  avatarUpdatedAt: Date | null;
};

/**
 * Serialises a user for the wire.
 *
 * The avatar flags belong here rather than at each call site: leaving them out
 * of the login response is what made an uploaded picture vanish on the next
 * sign-in, since the client had nothing to say the avatar existed.
 *
 * Deliberately never includes `avatar` itself — the bytes are served by
 * GET /users/:id/avatar so they aren't dragged through every payload — nor
 * `passwordHash`.
 */
export function publicUser(user: Pick<User, "id" | "username" | "avatar" | "avatarUpdatedAt">): PublicUser {
  return {
    id: user.id,
    username: user.username,
    hasAvatar: user.avatar != null,
    avatarUpdatedAt: user.avatarUpdatedAt,
  };
}
