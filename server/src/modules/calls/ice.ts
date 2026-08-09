import crypto from "node:crypto";
import { env } from "../../config/env.js";

export interface IceServer {
  urls: string | string[];
  username?: string;
  credential?: string;
}

// coturn "use-auth-secret" scheme: username = "<expiry-unix-ts>:<userId>",
// credential = base64(HMAC-SHA1(secret, username)). Coturn validates the same way.
export function buildIceServers(userId: string): IceServer[] {
  const servers: IceServer[] = [{ urls: ["stun:stun.l.google.com:19302"] }];

  if (env.TURN_SECRET && env.TURN_URL) {
    const expiry = Math.floor(Date.now() / 1000) + env.TURN_TTL_SECONDS;
    const username = `${expiry}:${userId}`;
    const credential = crypto.createHmac("sha1", env.TURN_SECRET).update(username).digest("base64");
    servers.push({
      urls: [`turn:${env.TURN_URL}?transport=udp`, `turn:${env.TURN_URL}?transport=tcp`],
      username,
      credential,
    });
  }

  return servers;
}
