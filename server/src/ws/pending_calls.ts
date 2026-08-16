/// Call offers held for a callee who was asleep when the phone rang.
///
/// With push, an incoming call for an offline device goes: caller sends the
/// offer -> we wake the device -> the app starts and opens its socket. The
/// offer arrived seconds before that socket existed, so without somewhere to
/// park it the call would be lost exactly when push was supposed to save it.
/// Entries are delivered on connect and expire on their own, so a caller who
/// hangs up first doesn't leave a ghost call waiting.

interface PendingCall {
  payload: unknown;
  conversationId: string;
  expiresAt: number;
}

const pending = new Map<string, PendingCall>();

/// Roughly how long a caller will wait while listening to a ringback.
const PENDING_TTL_MS = 45_000;

export function holdCallOffer(calleeId: string, conversationId: string, payload: unknown) {
  pending.set(calleeId, {
    payload,
    conversationId,
    expiresAt: Date.now() + PENDING_TTL_MS,
  });
}

/// Returns the offer waiting for this user, if it hasn't expired.
export function takePendingCall(userId: string): unknown | null {
  const entry = pending.get(userId);
  if (!entry) return null;
  pending.delete(userId);
  if (Date.now() > entry.expiresAt) return null;
  return entry.payload;
}

/// Called when the caller gives up, so the callee doesn't get a stale
/// incoming call the moment they come online.
export function dropPendingCall(calleeId: string, conversationId: string) {
  const entry = pending.get(calleeId);
  if (entry && entry.conversationId === conversationId) {
    pending.delete(calleeId);
  }
}

export function sweepExpiredCalls() {
  const now = Date.now();
  for (const [userId, entry] of pending) {
    if (now > entry.expiresAt) pending.delete(userId);
  }
}
