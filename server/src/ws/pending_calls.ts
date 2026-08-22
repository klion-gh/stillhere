/// Call signalling held for a callee who was asleep when the phone rang.
///
/// With push, an incoming call for an offline device goes: caller sends the
/// offer -> we wake the device -> the app starts and opens its socket. That
/// takes the better part of ten seconds, and the offer arrived before the
/// socket existed, so without somewhere to park it the call would be lost
/// exactly when push was supposed to save it.
///
/// The ICE candidates have to be parked with it. WebRTC trickles them out
/// within a second of the offer — well inside the same dead window — and
/// never repeats them. Relaying those into a closed socket and dropping them,
/// as this used to, left the callee holding a session description with no
/// remote candidates at all: nothing to run connectivity checks against, so
/// the call sat on "connecting" until something timed it out. The caller,
/// which did receive the callee's candidates, failed a few seconds later.
///
/// Entries are delivered on connect and expire on their own, so a caller who
/// hangs up first doesn't leave a ghost call waiting.

interface PendingCall {
  offer: unknown;
  candidates: unknown[];
  conversationId: string;
  expiresAt: number;
}

const pending = new Map<string, PendingCall>();

/// Roughly how long a caller will wait while listening to a ringback.
const PENDING_TTL_MS = 45_000;

/// A caller typically trickles 10-25 candidates. The cap is only here so a
/// misbehaving client can't grow this map without bound.
const MAX_HELD_CANDIDATES = 60;

export function holdCallOffer(calleeId: string, conversationId: string, payload: unknown) {
  pending.set(calleeId, {
    offer: payload,
    candidates: [],
    conversationId,
    expiresAt: Date.now() + PENDING_TTL_MS,
  });
}

/// Adds a candidate to the call already parked for this user.
///
/// Deliberately does nothing when there's no parked call for that exact
/// conversation: a candidate arriving for anything else means the callee
/// dropped mid-call, and replaying stale candidates on their next connect
/// would only confuse the session they come back to.
export function holdCallCandidate(calleeId: string, conversationId: string, payload: unknown) {
  const entry = pending.get(calleeId);
  if (!entry || entry.conversationId !== conversationId) return false;
  if (entry.candidates.length >= MAX_HELD_CANDIDATES) return false;
  entry.candidates.push(payload);
  return true;
}

export interface HeldCall {
  offer: unknown;
  candidates: unknown[];
}

/// Returns the call waiting for this user, if it hasn't expired.
export function takePendingCall(userId: string): HeldCall | null {
  const entry = pending.get(userId);
  if (!entry) return null;
  pending.delete(userId);
  if (Date.now() > entry.expiresAt) return null;
  return { offer: entry.offer, candidates: entry.candidates };
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
