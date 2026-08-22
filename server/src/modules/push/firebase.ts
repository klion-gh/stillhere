/**
 * Sending push through Firebase.
 *
 * Push is optional: a node without it configured works fine, it just can't wake
 * a device that isn't already connected. Messages are data-only, because a
 * system-drawn notification can't ring with accept and decline buttons.
 */
import { readFileSync } from "node:fs";
import { initializeApp, cert, type App } from "firebase-admin/app";
import { getMessaging, type MulticastMessage } from "firebase-admin/messaging";
import { env } from "../../config/env.js";
import { prisma } from "../../db/prisma.js";

let app: App | null = null;

/// Reads the service account from the path in FIREBASE_SERVICE_ACCOUNT_FILE.
/// Push is optional: a node without Firebase configured still works, it just
/// can't wake devices that aren't currently connected.
export function initPush(log: { info: (o: object, m: string) => void; warn: (m: string) => void }) {
  if (app) return;
  const path = env.FIREBASE_SERVICE_ACCOUNT_FILE;
  if (!path) {
    log.warn("push: FIREBASE_SERVICE_ACCOUNT_FILE not set — background delivery disabled");
    return;
  }
  try {
    const serviceAccount = JSON.parse(readFileSync(path, "utf8"));
    app = initializeApp({ credential: cert(serviceAccount) });
    log.info({ projectId: serviceAccount.project_id }, "push: firebase initialised");
  } catch (err) {
    log.warn(`push: failed to initialise firebase (${(err as Error).message}) — background delivery disabled`);
  }
}

export function isPushEnabled(): boolean {
  return app !== null;
}

interface PushPayload {
  /// Data-only messages so the client decides how to present them. A
  /// notification block would let the system draw its own, which we don't
  /// want for calls — the app needs to ring and show accept/decline.
  data: Record<string, string>;
  /// Calls must punch through Doze; messages can wait for the next window.
  urgent: boolean;
}

/// Sends to every device registered for a user. Tokens the server rejects as
/// permanently invalid are pruned, otherwise they accumulate forever as
/// people reinstall.
export async function sendToUserDevices(
  userId: string,
  payload: PushPayload,
  log: { info: (o: object, m: string) => void; warn: (o: object, m: string) => void },
): Promise<number> {
  if (!app) return 0;

  const devices = await prisma.deviceToken.findMany({ where: { userId } });
  if (devices.length === 0) return 0;

  const message: MulticastMessage = {
    tokens: devices.map((d) => d.token),
    data: payload.data,
    android: {
      priority: payload.urgent ? "high" : "normal",
      ttl: payload.urgent ? 45_000 : 3_600_000,
    },
  };

  try {
    const res = await getMessaging(app).sendEachForMulticast(message);
    const stale: string[] = [];
    res.responses.forEach((r, i) => {
      if (r.success) return;
      const code = r.error?.code ?? "";
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token" ||
        code === "messaging/invalid-argument"
      ) {
        stale.push(devices[i].token);
      }
    });

    if (stale.length > 0) {
      await prisma.deviceToken.deleteMany({ where: { token: { in: stale } } });
      log.info({ userId, pruned: stale.length }, "push: pruned dead tokens");
    }

    log.info({ userId, sent: res.successCount, failed: res.failureCount }, "push: delivered");
    return res.successCount;
  } catch (err) {
    log.warn({ userId, err: (err as Error).message }, "push: send failed");
    return 0;
  }
}
