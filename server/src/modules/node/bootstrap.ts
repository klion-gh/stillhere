/**
 * Hashes the node password into the database on first boot. Idempotent, so
 * leaving the variable set in the environment afterwards is harmless.
 */
import bcrypt from "bcrypt";
import { prisma } from "../../db/prisma.js";
import { env } from "../../config/env.js";

const BCRYPT_ROUNDS = 12;

// Runs once on first boot: hashes NODE_SETUP_PASSWORD into the single
// NodeConfig row. Idempotent — once the row exists, this is a no-op, so
// leaving NODE_SETUP_PASSWORD set in .env on later restarts is harmless.
export async function bootstrapNodeConfig(): Promise<void> {
  const existing = await prisma.nodeConfig.findFirst();
  if (existing) return;

  if (!env.NODE_SETUP_PASSWORD) {
    throw new Error(
      "NodeConfig is not initialized and NODE_SETUP_PASSWORD is not set. " +
        "Set NODE_SETUP_PASSWORD in the environment on first boot to choose the node password."
    );
  }

  const passwordHash = await bcrypt.hash(env.NODE_SETUP_PASSWORD, BCRYPT_ROUNDS);
  await prisma.nodeConfig.create({ data: { passwordHash } });
}
