/**
 * The Firebase configuration a client needs, read from disk and handed over on
 * request.
 *
 * None of it is secret — the same values sit inside every published app — which
 * is why the node can serve it. The credential that authorises sending never
 * leaves the server.
 */
import { readFileSync } from "node:fs";
import { env } from "../../config/env.js";

/// The subset of Firebase configuration an app needs to talk to a project.
/// None of it is secret — the same values sit in every published APK — which
/// is why the node can hand them to clients. The service account key, which
/// actually authorises *sending*, never leaves the server.
export interface FirebaseClientConfig {
  apiKey: string;
  appId: string;
  messagingSenderId: string;
  projectId: string;
}

let cached: FirebaseClientConfig | null = null;
let loaded = false;

/// Reads the operator's google-services.json. Using the file Firebase hands
/// them verbatim beats asking them to copy four values into env vars by hand.
export function getFirebaseClientConfig(
  log: { info: (o: object, m: string) => void; warn: (m: string) => void },
): FirebaseClientConfig | null {
  if (loaded) return cached;
  loaded = true;

  const path = env.FIREBASE_CLIENT_CONFIG_FILE;
  if (!path) return null;

  try {
    const raw = JSON.parse(readFileSync(path, "utf8"));
    const projectId = raw?.project_info?.project_id;
    const messagingSenderId = raw?.project_info?.project_number;

    // A project can hold several apps (flavours, platforms); pick the one
    // matching the package name this node's clients are built with.
    const clients: any[] = raw?.client ?? [];
    const wanted = env.FIREBASE_ANDROID_PACKAGE;
    const client =
      clients.find((c) => c?.client_info?.android_client_info?.package_name === wanted) ?? clients[0];

    const appId = client?.client_info?.mobilesdk_app_id;
    const apiKey = client?.api_key?.[0]?.current_key;

    if (!projectId || !messagingSenderId || !appId || !apiKey) {
      log.warn("push: google-services.json is missing required fields — client config not served");
      return null;
    }

    cached = { apiKey, appId, messagingSenderId: String(messagingSenderId), projectId };
    log.info({ projectId, appId }, "push: client config loaded");
    return cached;
  } catch (err) {
    log.warn(`push: failed to read client config (${(err as Error).message})`);
    return null;
  }
}
