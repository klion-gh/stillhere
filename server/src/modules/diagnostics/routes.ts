import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { prisma } from "../../db/prisma.js";
import { broadcast } from "../../ws/connections.js";
import {
  diagnosticsEnabled,
  loadDiagnosticsState,
  recordEvents,
  RETENTION_DAYS,
} from "./store.js";

/** Keeps one runaway client from filling the table in a single request. */
const MAX_EVENTS_PER_BATCH = 200;
const MAX_DETAIL_CHARS = 2000;

const eventSchema = z.object({
  at: z.string().datetime().optional(),
  source: z.string().min(1).max(32),
  kind: z.string().min(1).max(64),
  detail: z.string().max(MAX_DETAIL_CHARS).optional(),
  data: z.unknown().optional(),
});

const batchSchema = z.object({
  events: z.array(eventSchema).max(MAX_EVENTS_PER_BATCH),
});

export async function diagnosticsRoutes(app: FastifyInstance) {
  // Apps ask on every connect whether they should be reporting. Answering
  // this is cheap, and it keeps the decision on the node rather than baking
  // it into a build.
  app.get("/diagnostics/config", { preHandler: app.authenticate }, async (_request, reply) => {
    return reply.send({ enabled: diagnosticsEnabled(), retentionDays: RETENTION_DAYS });
  });

  app.post("/diagnostics/events", { preHandler: app.authenticate }, async (request, reply) => {
    // Accepted-and-dropped rather than an error: a client that hasn't noticed
    // diagnostics were switched off mid-session shouldn't see failures.
    if (!diagnosticsEnabled()) return reply.send({ recorded: 0, enabled: false });

    const parsed = batchSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_body" });
    }

    const user = await prisma.user.findUnique({
      where: { id: request.userId! },
      select: { username: true },
    });

    const recorded = await recordEvents(
      parsed.data.events.map((e) => ({
        at: e.at ? new Date(e.at) : undefined,
        userId: request.userId,
        username: user?.username ?? null,
        source: e.source,
        kind: e.kind,
        detail: e.detail ?? null,
        data: e.data,
      })),
      request.log,
    );

    return reply.send({ recorded, enabled: true });
  });
}

/**
 * Re-reads the flag periodically so the operator's CLI — which writes
 * straight to the database from inside the container — takes effect without
 * a restart, and without an admin HTTP endpoint that would sit exposed on the
 * public interface.
 */
export function startDiagnosticsWatcher(log: FastifyInstance["log"], intervalMs = 15_000) {
  let last = diagnosticsEnabled();
  const timer = setInterval(async () => {
    try {
      const now = await loadDiagnosticsState();
      if (now === last) return;
      last = now;
      log.warn({ enabled: now }, "diagnostics: recording toggled");
      // Tell every connected app straight away, so a bug can be captured
      // without asking anyone to restart anything.
      broadcast({ type: "diagnostics:config", enabled: now, retentionDays: RETENTION_DAYS });
    } catch (err) {
      log.warn({ err }, "diagnostics: could not re-read state");
    }
  }, intervalMs);
  timer.unref?.();
  return timer;
}
