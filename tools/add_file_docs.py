"""Prepends a file-level header to every source file that lacks one.

Run from the repository root:

    python tools/add_file_docs.py

Idempotent: a file whose first line already opens a comment is left alone, so
this can be re-run after adding new files without disturbing existing text.
Dart headers need a `library;` directive after them, otherwise the analyzer
reports the comment as dangling.
"""

from __future__ import annotations

import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DOCS: dict[str, str] = {}


def doc(path: str, text: str) -> None:
    DOCS[path.replace("/", os.sep)] = text.strip("\n")


# ---------------------------------------------------------------- client/core
doc("client/lib/main.dart", """
Process entry point.

Everything here has to happen before the first frame, and the order is not
arbitrary: locale data first (a missing locale turns a formatted date into a
thrown exception and a grey box where the widget should be), push next (its
background handler must be registered on every launch, because Android's
stored pointer to it goes stale when the app is updated), then the desktop
window and tray.
""")

doc("client/lib/app.dart", """
The root widget, and the one place that listens to everything at once.

Calls, messages and notification presses can arrive while the user is on any
screen — or on none, with the app in the background — so the socket listener
and the notification callbacks live above the router rather than inside a
screen that may not be built yet. It also owns the two-way plumbing that has
to survive a screen not existing: buffering a call offer and its ICE
candidates, and receiving notification presses forwarded from the background
isolate.
""")

doc("client/lib/core/api_client.dart", """
The authenticated HTTP client.

Layers the signed-in user's access token on top of the node-scoped client in
features/connect/node_client.dart, and refreshes it once on a 401 before
retrying — access tokens live about fifteen minutes, so a long session hits
this constantly. Rebuilt whenever the node connection changes, since base URL
and pinned certificate both belong to the node.
""")

doc("client/lib/core/providers.dart", """
Singletons that outlive any one screen: storage, the socket, the ringtone
player. Kept in one place so their lifetimes are visible together, and so
disposal is wired once rather than at each use site.
""")

doc("client/lib/core/router.dart", """
Routing, and the redirects that decide which of three states the app is in:
not paired with a node, paired but signed out, or signed in. The router
re-evaluates whenever either controller changes, so pairing, signing out or
having a token rejected moves the user without any screen having to navigate.
""")

doc("client/lib/core/node_http_client.dart", """
Certificate pinning for self-hosted nodes.

Most nodes present a self-signed certificate, which no CA vouches for. Dart
only calls this back after normal validation has already failed, so a node
with a real certificate never reaches it: pinning can't override a CA's
verdict, only stand in where there is none. First contact accepts and records
the fingerprint; a later mismatch means the certificate changed and the
connection is refused.
""")

doc("client/lib/core/node_storage.dart", """
Persistence for the node connection: the one in use, and every node paired
before. See features/connect/saved_node.dart for the record itself.
""")

doc("client/lib/core/token_storage.dart", """
Persistence for the user session: the signed-in one, and every account signed
into before. See features/auth/saved_account.dart for the record itself.
""")

doc("client/lib/core/ws_client.dart", """
The socket. One connection per session, carrying messages, call signalling
and presence.

Most of this file is about the connection not being trustworthy: a heartbeat
that turns a silently dead socket into a real disconnect, reconnection with
backoff, and a hook to renew the access token when the server closes with
4001 rather than making the user sign in again.
""")

doc("client/lib/core/push_service.dart", """
Firebase Cloud Messaging, configured at runtime rather than at build time.

Each node has its own Firebase project and hands its configuration to the app
when they pair, so one published build works against any node — nothing about
a particular project is baked into the binary. Setup runs before the first
frame on every launch, because the background message handler has to be
registered each time: Android remembers a pointer to its compiled code, and
that pointer goes stale when the app is updated.
""")

doc("client/lib/core/background_actions.dart", """
Notification presses that arrive with no app to handle them.

Android dispatches a press on a button that doesn't open the app into a
separate isolate — the same process when the app is alive, but with none of
its state, so the running call is out of reach. Presses are forwarded back to
the app through a named port when there is one; when there isn't, declining a
call goes over HTTP instead of the socket that doesn't exist yet.
""")

doc("client/lib/core/call_notifications.dart", """
Android notifications for calls and messages.

Two channels for one incoming call: one that rings, used when the push
arrived at a process that isn't running the app, and a silent one for when
the app is alive and already looping the ring itself. A channel plays its
sound exactly once, which is why the looping ring can't come from here. A
third channel carries the controls for a call in progress.
""")

doc("client/lib/core/desktop_notifications.dart", """
Windows toasts for calls and messages, with the same actions the Android
notifications carry. Mirrors core/call_notifications.dart on the desktop
side.
""")

doc("client/lib/core/desktop_shell.dart", """
Windows window and tray behaviour: closing hides to the tray instead of
quitting, and the tray menu offers a real quit plus a notification toggle. A
messenger that exits when you close the window stops receiving calls, which
is not what closing a window is usually taken to mean. No-op off desktop.
""")

doc("client/lib/core/ringtone_service.dart", """
The ring tones: incoming, and the ringback the caller hears while waiting.

Both loop until stopped, and the incoming one is routed to the phone's ringer
stream so it follows the ringer volume and stays quiet when the phone is.
""")

doc("client/lib/core/incoming_call.dart", """
The handful of pieces of call state that have to be reachable from outside
the call screen: an offer that arrived before the screen existed, the
candidates that followed it, and which conversation is currently open or in
a call.
""")

doc("client/lib/core/avatar_cache.dart", """
Avatar bytes, fetched through the app's own HTTP client.

Image.network can't be used: the endpoint sits behind the node-token gate,
and a self-hosted node's certificate is usually self-signed, which only the
pinned client trusts.
""")

doc("client/lib/core/appearance.dart", """
The palettes and animated backgrounds the user can choose between, and the
storage of that choice.

A palette redefines colour only. Layout, spacing and typography are identical
across all six, so the app still looks like one product whichever is picked.
""")

doc("client/lib/core/theme.dart", """
The Material theme, built from the active palette.

Colours are mutable statics rather than theme entries because every screen
reads them directly. That has a cost — a widget reading them has no
dependency Flutter can track — which is what appearance.dart's watchPalette
exists to repair.
""")

doc("client/lib/core/diagnostics.dart", """
Mirrors the app's own log to the node while the node has recording switched
on.

Off is the default and the normal state. It exists so a problem that only
happens on someone else's phone — a call that won't connect, a push that
never lands — can be looked at afterwards instead of guessed at.
""")

doc("client/lib/core/update_checker.dart", """
Asks GitHub Releases whether a newer version exists, and picks the asset for
the platform it's running on.
""")

doc("client/lib/core/update_installer.dart", """
Downloads a release and hands it to the system installer, so updating never
requires leaving the app for a browser.
""")

# ------------------------------------------------------------ client/features
doc("client/lib/features/connect/connect_screen.dart", """
Choosing a node: tiles for the ones paired before, each with a live round
trip, above a tile that opens the address-and-password form. The form is what
the screen shows outright on first run, when there is nothing to choose
between.
""")

doc("client/lib/features/connect/node_controller.dart", """
Pairing with a node and reconnecting to one.

Pairing exchanges the node password for a token that lasts a year, which is
what lets a saved node be reopened without a password. Reconnecting probes
that token before accepting the session, so a node that was reinstalled says
so instead of leaving the user in an app where every request fails.
""")

doc("client/lib/features/connect/node_state.dart", """
What the app knows about its node: address, token, and the certificate
fingerprint pinned for it.
""")

doc("client/lib/features/connect/node_client.dart", """
A Dio instance scoped to the node: its base URL, its node token, its pinned
certificate. Used where the user's own token isn't needed or doesn't exist
yet — pairing and signing in. core/api_client.dart layers the user on top.
""")

doc("client/lib/features/connect/node_ping.dart", """
Measures the round trip to a saved node for its tile. Uses the one endpoint
outside the node-token gate, so it reports whether the server is up rather
than whether the credential is still good.
""")

doc("client/lib/features/auth/auth_controller.dart", """
The user session: signing in, signing back in from a saved account, renewing
tokens, and signing out.

A saved account is stored as a refresh token, never a password. The node
issues one for exactly this purpose, it expires on its own, and it can be
invalidated server-side — none of which is true of a password.
""")

doc("client/lib/features/auth/auth_state.dart", """
The signed-in user and their token pair.
""")

doc("client/lib/features/auth/register_screen.dart", """
Creating an account on the node the app is connected to.
""")

doc("client/lib/features/calls/call_controller.dart", """
One audio call, from ringing to hang-up.

Owns the peer connection and the signalling around it. Much of the care here
is about a callee whose device was asleep: the offer and the caller's ICE
candidates can arrive before this controller exists, the user can accept
before the offer has landed, and WebRTC does not reliably report that a call
is never going to connect — hence the watchdog.

The controller deliberately outlives its screen. Leaving the call screen
should leave the call running, with the notification as its handle.
""")

doc("client/lib/features/calls/call_screen.dart", """
The call: who's on it, how long it's been, connection quality, and the
controls. Reflects the controller's state; it doesn't own the call.
""")

doc("client/lib/features/chat/chat_controller.dart", """
The messages of one conversation: the page fetched on open, plus whatever
arrives on the socket while it's open.
""")

doc("client/lib/features/chat/chat_screen.dart", """
One conversation: its history, the composer, and a button to call the person.
""")

doc("client/lib/features/chat/message_bubble.dart", """
A single message. Consecutive messages from the same person are grouped, so
only the first of a run carries the full spacing.
""")

doc("client/lib/features/conversations/conversations_controller.dart", """
The chat list, and the incremental updates that keep it current — a new
message moving a conversation to the top, a peer renaming themselves —
without refetching the whole list each time.
""")

doc("client/lib/features/conversations/conversations_list_screen.dart", """
The main screen: every conversation with its last message, the way into the
profile, and the menu.
""")

doc("client/lib/features/conversations/user_search_screen.dart", """
Finding someone by tag and starting a conversation with them.
""")

doc("client/lib/features/profile/profile_screen.dart", """
Editing your own profile: picture, tag, password.
""")

doc("client/lib/features/profile/profile_controller.dart", """
The work behind the profile screen.

Pictures are downscaled and re-encoded before upload — a modern phone camera
produces several megabytes, and the node keeps avatars in its database. A tag
change returns a new token pair, because the tag is encoded in the access
token and the old one would keep showing the previous name until it expired.
""")

doc("client/lib/features/appearance/appearance_screen.dart", """
Choosing a palette and a background.

Palette cards are drawn in the colours of the palette they offer rather than
the active one, and each background is previewed by running the real
animation in miniature — otherwise the names are guesswork.
""")

doc("client/lib/features/updates/update_dialog.dart", """
The download-and-install flow for a new release, run inside the app.
""")

doc("client/lib/models/user.dart", """
A user as the node describes them: identity, tag, and whether they have a
picture.
""")

doc("client/lib/models/message.dart", """
A chat message, including when it was delivered and read.
""")

doc("client/lib/models/conversation.dart", """
A conversation: the other person, and a preview of the last thing said, which
is what the chat list shows.
""")

doc("client/lib/widgets/animated_background.dart", """
The animated backdrop behind the full-screen flows.

Eight styles, all painted by one painter driven by one controller. Every term
completes a whole number of cycles across the loop, so the frame at the end
matches the frame at the start — a fractional rate anywhere makes the restart
visible.
""")

doc("client/lib/widgets/gradient_avatar.dart", """
The circular avatar, plus the backdrop and glow shared across screens.

Without a picture, the gradient is derived from the tag, so the same person is
always the same colour on every device — recognition by colour rather than by
reading.
""")

doc("client/lib/widgets/error_banner.dart", """
The inline error banner and the app's brand mark.
""")

# ------------------------------------------------------------------- server
doc("server/src/index.ts", """
Server entry point: plugins, routes, and the background jobs that outlive any
request.

Order matters. The node gate registers before the routes it protects, and the
node password is hashed into the database before the first connection can
try to use it.
""")

doc("server/src/config/env.ts", """
Environment configuration, validated on boot.

A node is configured by hand by whoever runs it, so a missing secret should
stop the server with a clear message rather than surface later as a confusing
runtime failure.
""")

doc("server/src/db/prisma.ts", """
The database client, shared by every module.
""")

doc("server/src/plugins/auth.ts", """
Verifies the user's access token and attaches their identity to the request.
Applied per route, unlike the node gate, which covers everything.
""")

doc("server/src/plugins/node-gate.ts", """
The outer door: every request must prove it knows the node password, in the
form of a token issued at pairing.

A private node is not a public API. Only pairing, health and the socket are
exempt — the socket carries its token in the query string, because a browser
or mobile client can't always set headers on the handshake.
""")

doc("server/src/modules/node/routes.ts", """
Pairing: exchanges the node password for a long-lived node token.
""")

doc("server/src/modules/node/tokens.ts", """
Issues and verifies node tokens — the credential that gets a device through
the gate.
""")

doc("server/src/modules/node/bootstrap.ts", """
Hashes the node password into the database on first boot. Idempotent, so
leaving the variable set in the environment afterwards is harmless.
""")

doc("server/src/modules/auth/routes.ts", """
Registration, sign-in and token renewal.
""")

doc("server/src/modules/auth/tokens.ts", """
Issues and verifies the user's token pair: a short-lived access token and a
long-lived refresh token.
""")

doc("server/src/modules/users/routes.ts", """
Looking up a user by tag, which is how one person finds another.
""")

doc("server/src/modules/users/profile_routes.ts", """
The signed-in user's own profile: picture, tag and password.

Avatars are served without a user token — the node gate already limits this
to people paired with the node, and requiring more would mean every avatar
request had to carry a session.
""")

doc("server/src/modules/users/public_user.ts", """
How a user is described on the wire.

Deliberately one function rather than a shape repeated at each call site:
leaving the avatar fields out of the sign-in response is what once made an
uploaded picture disappear on the next launch.
""")

doc("server/src/modules/users/username.ts", """
Tag normalisation and validation. Tags are compared case-insensitively and
without a leading @, so one person can't be impersonated by a different
spelling of their name.
""")

doc("server/src/modules/conversations/routes.ts", """
Conversations: creating one, listing them with their last message, and
paging through history.
""")

doc("server/src/modules/calls/routes.ts", """
Call support over HTTP: the ICE servers a client needs, and declining a call
from a device whose app isn't running and therefore has no socket.
""")

doc("server/src/modules/calls/ice.ts", """
Builds the ICE server list, including short-lived TURN credentials.

TURN relays audio when a direct path can't be found, which is the common case
between two mobile networks. The credentials are derived from a shared secret
and expire on their own, so nothing long-lived is handed to a client.
""")

doc("server/src/modules/push/firebase.ts", """
Sending push through Firebase.

Push is optional: a node without it configured works fine, it just can't wake
a device that isn't already connected. Messages are data-only, because a
system-drawn notification can't ring with accept and decline buttons.
""")

doc("server/src/modules/push/client_config.ts", """
The Firebase configuration a client needs, read from disk and handed over on
request.

None of it is secret — the same values sit inside every published app — which
is why the node can serve it. The credential that authorises sending never
leaves the server.
""")

doc("server/src/modules/push/routes.ts", """
Device registration for push, and the endpoint that tells a client which
Firebase project this node uses.
""")

doc("server/src/modules/diagnostics/store.ts", """
The diagnostic trail: whether it's recording, writing to it, and expiring it.

Recording is off unless an operator turns it on, and entries are pruned after
a few days. This records who did what and when, which is worth having while
chasing a problem and not worth keeping afterwards.
""")

doc("server/src/modules/diagnostics/routes.ts", """
Diagnostics as the apps see them: whether to report, and where to send it.

There is deliberately no endpoint for turning recording on. Anything the node
serves is reachable from the internet, and a switch that starts recording
everyone's activity should not be defended by a password. The operator flips
it from inside the container instead, and the server notices within seconds.
""")

doc("server/src/diagnostics_cli.ts", """
The operator's command line for the diagnostic trail.

Runs inside the container, against the node's own database, precisely so that
it has no network surface.
""")

doc("server/src/ws/gateway.ts", """
The socket: authentication, message relay and call signalling.

Signalling is relayed rather than stored, with one exception. A callee whose
device is asleep has no socket for the better part of ten seconds after being
woken by push, so the offer and the candidates that follow it are held until
one exists — dropping them leaves a call that rings, is answered, and then
never connects.
""")

doc("server/src/ws/connections.ts", """
Who is connected, and how to reach them.

Includes the heartbeat, without which a client that vanished without closing
its socket stays registered forever and everything routed to it is written
into the void.
""")

doc("server/src/ws/pending_calls.test.ts", """
Tests for the call signalling held while a pushed device wakes up.
""")


def apply(path: str, text: str) -> bool:
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        print("missing:", path)
        return False

    body = io.open(full, encoding="utf-8").read()
    first = body.lstrip().split("\n", 1)[0]
    if first.startswith("//") or first.startswith("/*"):
        return False  # already has a header

    lines = text.split("\n")
    if path.endswith(".dart"):
        header = "\n".join(f"/// {ln}".rstrip() for ln in lines) + "\nlibrary;\n\n"
    else:
        header = "/**\n" + "\n".join(f" * {ln}".rstrip() for ln in lines) + "\n */\n"

    io.open(full, "w", encoding="utf-8", newline="").write(header + body)
    return True


def main() -> None:
    written = 0
    for path, text in DOCS.items():
        if apply(path, text):
            written += 1
    print(f"documented {written} file(s), {len(DOCS) - written} already had a header")


if __name__ == "__main__":
    main()
