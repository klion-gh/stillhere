import { z } from "zod";

const envSchema = z.object({
  DATABASE_URL: z.string().min(1),
  JWT_ACCESS_SECRET: z.string().min(1),
  JWT_REFRESH_SECRET: z.string().min(1),
  ACCESS_TOKEN_TTL: z.string().default("15m"),
  REFRESH_TOKEN_TTL: z.string().default("30d"),
  PORT: z.coerce.number().default(3000),
  HOST: z.string().default("0.0.0.0"),
  CORS_ORIGIN: z.string().default("*"),
  TURN_SECRET: z.string().optional(),
  TURN_URL: z.string().optional(),
  TURN_TTL_SECONDS: z.coerce.number().default(3600),
  NODE_TOKEN_SECRET: z.string().min(1),
  NODE_TOKEN_TTL: z.string().default("365d"),
  // Only consumed once, on first boot, to bootstrap NodeConfig.passwordHash.
  // Safe to leave set in .env afterward — ignored once the row exists.
  NODE_SETUP_PASSWORD: z.string().optional(),
});

export const env = envSchema.parse(process.env);
