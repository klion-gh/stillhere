import jwt from "jsonwebtoken";
import { env } from "../../config/env.js";

export interface NodeTokenPayload {
  type: "node";
}

export function signNodeToken(): string {
  const payload: NodeTokenPayload = { type: "node" };
  return jwt.sign(payload, env.NODE_TOKEN_SECRET, {
    expiresIn: env.NODE_TOKEN_TTL as jwt.SignOptions["expiresIn"],
  });
}

export function verifyNodeToken(token: string): NodeTokenPayload {
  const decoded = jwt.verify(token, env.NODE_TOKEN_SECRET);
  if (typeof decoded === "string" || decoded.type !== "node") {
    throw new Error("Invalid node token");
  }
  return decoded as NodeTokenPayload;
}
