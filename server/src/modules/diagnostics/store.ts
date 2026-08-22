/**
 * The diagnostic trail: whether it's recording, writing to it, and expiring it.
 *
 * Recording is off unless an operator turns it on, and entries are pruned after
 * a few days. This records who did what and when, which is worth having while
 * chasing a problem and not worth keeping afterwards.
 */
import type { FastifyBaseLogger } from "fastify";
import { prisma } from "../../db/prisma.js";

const ENABLED_KEY = "diagnostics.enabled";

/**
 * How long a recorded trail is kept. Diagnostics exist to explain something
 * that just went wrong, so anything older is noise the node has no business
 * holding on to.
 */
export const RETENTION_DAYS = 3;

const PRUNE_INTERVAL_MS = 60 * 60 * 1000;

/**
 * Cached so the hot paths (every websocket frame) don't hit the database to
 * ask whether they should be recording. The flag only changes when an
 * operator flips it, and that goes through {@link setDiagnosticsEnabled}.
 */
let enabled = false;

export function diagnosticsEnabled(): boolean {
  return enabled;
}

export async function loadDiagnosticsState(): Promise<boolean> {
  const row = await prisma.setting.findUnique({ where: { key: ENABLED_KEY } });
  enabled = row?.value === "true";
  return enabled;
}

export async function setDiagnosticsEnabled(next: boolean): Promise<void> {
  await prisma.setting.upsert({
    where: { key: ENABLED_KEY },
    create: { key: ENABLED_KEY, value: String(next) },
    update: { value: String(next) },
  });
  enabled = next;
}

export type DiagnosticEventInput = {
  at?: Date;
  userId?: string | null;
  username?: string | null;
  /** Where it came from: "android", "windows", or "server". */
  source: string;
  /** Short machine-readable name, e.g. "call.offer" or "ws.connected". */
  kind: string;
  detail?: string | null;
  data?: unknown;
};

/**
 * Writes events, or does nothing at all when diagnostics are off.
 *
 * Never rejects: a diagnostic trail must not be able to break the thing it's
 * observing. Callers can fire and forget.
 */
export async function recordEvents(
  events: DiagnosticEventInput[],
  log?: FastifyBaseLogger,
): Promise<number> {
  if (!enabled || events.length === 0) return 0;
  try {
    const result = await prisma.diagnosticEvent.createMany({
      data: events.map((e) => ({
        at: e.at ?? new Date(),
        userId: e.userId ?? null,
        username: e.username ?? null,
        source: e.source,
        kind: e.kind,
        detail: e.detail ?? null,
        data: (e.data ?? undefined) as never,
      })),
    });
    return result.count;
  } catch (err) {
    log?.warn({ err }, "diagnostics: could not record events");
    return 0;
  }
}

export function recordEvent(event: DiagnosticEventInput, log?: FastifyBaseLogger): void {
  void recordEvents([event], log);
}

export async function pruneOldEvents(log?: FastifyBaseLogger): Promise<number> {
  const cutoff = new Date(Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000);
  try {
    const { count } = await prisma.diagnosticEvent.deleteMany({ where: { at: { lt: cutoff } } });
    if (count > 0) log?.info({ count, cutoff }, "diagnostics: pruned expired events");
    return count;
  } catch (err) {
    log?.warn({ err }, "diagnostics: prune failed");
    return 0;
  }
}

/**
 * Prunes on boot and hourly thereafter. Runs even while diagnostics are off,
 * so switching them off still lets whatever was recorded expire on schedule.
 */
export function startDiagnosticsPruner(log?: FastifyBaseLogger): NodeJS.Timeout {
  void pruneOldEvents(log);
  const timer = setInterval(() => void pruneOldEvents(log), PRUNE_INTERVAL_MS);
  timer.unref?.();
  return timer;
}
