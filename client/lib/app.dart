import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/appearance.dart';
import 'core/background_actions.dart';
import 'core/call_notifications.dart';
import 'core/desktop_notifications.dart';
import 'core/diagnostics.dart';
import 'core/incoming_call.dart';
import 'core/providers.dart';
import 'core/push_service.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/calls/call_controller.dart';
import 'features/connect/node_controller.dart';
import 'features/conversations/conversations_controller.dart';

class StillHereApp extends ConsumerStatefulWidget {
  const StillHereApp({super.key});

  @override
  ConsumerState<StillHereApp> createState() => _StillHereAppState();
}

class _StillHereAppState extends ConsumerState<StillHereApp> with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  ReceivePort? _actionPort;
  bool _inForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Global listener: incoming calls and messages can arrive while the user
    // is anywhere in the app — or nowhere, with it backgrounded.
    _wsSub = ref.read(wsClientProvider).events.listen(_handleWsEvent);
    CallNotifications.onCallAction = _handleCallNotificationAction;
    // Presses handled in the background isolate come back through here.
    _actionPort = registerNotificationActionPort(_handleCallNotificationAction);

    // A token can be issued long after the session is restored, so register
    // it whenever it arrives rather than only on the login transition —
    // otherwise a cold start with a saved session never tells the node about
    // this device, and calls stop arriving unless the app is already open.
    PushService.onTokenReady = (_) async {
      await ref.read(authControllerProvider.notifier).registerPushToken();
    };

    // main() already brought push up from the stored config. This only covers
    // the node paired before that config was being saved: it has to wait for
    // the node state to load, which is exactly why doing it from a post-frame
    // callback used to skip setup altogether.
    unawaited(_restorePushConfigWhenNodeReady());

    DesktopNotifications.onCallAction = (conversationId, peerUsername, action) {
      _handleCallNotificationAction(CallNotificationEvent(
        action: action,
        conversationId: conversationId,
        peerUsername: peerUsername,
      ));
    };
    DesktopNotifications.onMessageTap = (conversationId, peerUsername) {
      ref.read(routerProvider).push('/chat/$conversationId', extra: peerUsername);
    };
  }

  /// Waits for the stored node session to finish loading before asking it for
  /// push config. Reading the provider's future rather than its current value
  /// is the difference between "not paired" and "not loaded yet".
  Future<void> _restorePushConfigWhenNodeReady() async {
    if (PushService.isAvailable) return;
    try {
      await ref.read(nodeControllerProvider.future);
      await ref.read(nodeControllerProvider.notifier).restorePushConfig();
    } catch (_) {
      // No node paired, or it couldn't be reached — push simply stays off.
    }
  }

  /// Accept/decline tapped on a call notification, or the notification body
  /// itself (which should land on the call screen).
  void _handleCallNotificationAction(CallNotificationEvent event) {
    if (event.conversationId.isEmpty) return;

    final liveArgs = ref.read(activeCallArgsProvider);
    final isLive = liveArgs != null && liveArgs.conversationId == event.conversationId;

    switch (event.action) {
      case CallNotificationAction.decline:
        if (isLive) {
          // Goes through the controller so the ringtone stops and the screen
          // moves to its ended state, not just a bare call:end on the wire.
          ref.read(callControllerProvider(liveArgs).notifier).declineIncomingCall();
        } else {
          ref.read(wsClientProvider).send({
            'type': 'call:end',
            'conversationId': event.conversationId,
          });
          ref.read(pendingIncomingCallProvider.notifier).state = null;
        }
        unawaited(CallNotifications.cancelIncomingCall());
        unawaited(DesktopNotifications.cancelIncomingCall());
        break;

      case CallNotificationAction.accept:
        if (isLive) {
          unawaited(ref.read(callControllerProvider(liveArgs).notifier).acceptIncomingCall());
        } else {
          // No controller yet (notification arrived before the screen); open
          // it, then answer once it has built.
          _openCallScreen(event);
          Future.delayed(const Duration(milliseconds: 400), () {
            final args = ref.read(activeCallArgsProvider);
            if (args == null || args.conversationId != event.conversationId) return;
            unawaited(ref.read(callControllerProvider(args).notifier).acceptIncomingCall());
          });
        }
        break;

      // Controls on the shade entry for a call that's already running. The
      // call is live by definition here, so they go straight to its
      // controller.
      case CallNotificationAction.hangUp:
        if (isLive) {
          ref.read(callControllerProvider(liveArgs).notifier).hangUp();
        } else {
          ref.read(wsClientProvider).send({
            'type': 'call:end',
            'conversationId': event.conversationId,
          });
        }
        unawaited(CallNotifications.cancelOngoingCall());
        break;

      case CallNotificationAction.toggleMute:
        if (isLive) unawaited(ref.read(callControllerProvider(liveArgs).notifier).toggleMute());
        break;

      case CallNotificationAction.toggleSpeaker:
        if (isLive) unawaited(ref.read(callControllerProvider(liveArgs).notifier).toggleSpeaker());
        break;

      case CallNotificationAction.open:
        // Tapping the body should always land on the call, including for a
        // call already running that the user navigated away from.
        _openCallScreen(event);
        break;
    }
  }

  void _openCallScreen(CallNotificationEvent event) {
    // The controller is keyed by the whole CallArgs, so reopening a live call
    // has to reuse its exact arguments. Guessing outgoing=false would spin up
    // a second controller for a call the user placed themselves.
    final live = ref.read(activeCallArgsProvider);
    final args = live?.conversationId == event.conversationId
        ? live!
        : CallArgs(
            conversationId: event.conversationId,
            peerUsername: event.peerUsername,
            isOutgoing: false,
          );
    ref.read(routerProvider).push(
          '/call/${args.conversationId}?peer=${args.peerUsername}&outgoing=${args.isOutgoing}',
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
  }

  void _handleWsEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'call:offer':
        _handleIncomingCall(event);
        break;
      case 'call:ice-candidate':
        _bufferEarlyCandidate(event);
        break;
      case 'message:new':
        _handleIncomingMessage(event);
        break;
      case 'conversation:new':
        // Someone started a conversation with us. Pull it into the list so
        // their messages and calls have somewhere to land, even though we
        // never added them.
        unawaited(ref.read(conversationsProvider.notifier).refresh());
        break;
      case 'message:ack':
        // Our own message: keep the list preview in step with what we sent.
        _applyMessageToList(event, fromMe: true);
        break;
      case 'diagnostics:config':
        // The node's operator switched recording on or off. Honoured live so
        // a problem can be captured without asking anyone to restart.
        ref.read(diagnosticsReporterProvider).setEnabled(event['enabled'] == true);
        break;
      case 'peer:updated':
        final userId = event['userId'] as String?;
        final username = event['username'] as String?;
        if (userId != null && username != null) {
          ref.read(conversationsProvider.notifier).applyPeerRename(
                userId: userId,
                username: username,
              );
        }
        break;
    }
  }

  /// Holds candidates that arrive before the call controller has subscribed.
  ///
  /// Only relevant for the window between the offer landing and the call
  /// screen being built — once a controller exists it listens to the socket
  /// itself, so there's nothing to catch.
  void _bufferEarlyCandidate(Map<String, dynamic> event) {
    if (ref.read(activeCallArgsProvider) != null) return;
    final conversationId = event['conversationId'] as String?;
    if (conversationId == null) return;

    final buffered = ref.read(pendingIncomingCandidatesProvider);
    if (buffered.length >= 64) return;
    ref.read(pendingIncomingCandidatesProvider.notifier).state = [...buffered, event];
  }

  void _handleIncomingCall(Map<String, dynamic> event) {
    final conversationId = event['conversationId'] as String?;
    final sdp = event['sdp'] as Map<String, dynamic>?;
    final fromUserId = event['from'] as String?;
    if (conversationId == null || sdp == null || fromUserId == null) return;

    final activeConversationId = ref.read(activeCallConversationIdProvider);
    if (activeConversationId == conversationId) {
      // The offer for the call already on screen. This happens whenever a
      // push woke the app: the notification opens the call screen, and the
      // offer the node parked for us only arrives once the socket is up.
      // The call controller picks it up from the same stream — hanging up
      // here is what used to leave the callee stuck on "connecting" while
      // the caller saw the call end.
      return;
    }
    if (activeConversationId != null) {
      // A different call while one is in progress: politely decline.
      ref.read(wsClientProvider).send({'type': 'call:end', 'conversationId': conversationId});
      return;
    }

    ref.read(pendingIncomingCallProvider.notifier).state = IncomingCall(
      conversationId: conversationId,
      fromUserId: fromUserId,
      sdp: sdp,
    );

    final known = _resolvePeerUsername(conversationId);
    final peerUsername = known ?? '';
    if (known == null) {
      // A call from someone whose conversation we haven't loaded yet — fetch
      // it so the call screen can show who's calling.
      unawaited(ref.read(conversationsProvider.notifier).refresh());
    }

    // Heads-up notification with accept/decline. Silent: the call screen this
    // pushes starts the looping ring, and the channel's own sound would play
    // once over the top of it.
    unawaited(CallNotifications.showIncomingCall(
      conversationId: conversationId,
      peerUsername: peerUsername,
      withSound: false,
    ));
    unawaited(DesktopNotifications.showIncomingCall(
      conversationId: conversationId,
      peerUsername: peerUsername,
    ));
    ref.read(routerProvider).push('/call/$conversationId?peer=$peerUsername&outgoing=false');
  }

  /// Keeps the conversation list's preview and ordering current without
  /// refetching it for every message.
  void _applyMessageToList(Map<String, dynamic> event, {required bool fromMe}) {
    final message = event['message'] as Map<String, dynamic>?;
    if (message == null) return;
    final conversationId = message['conversationId'] as String?;
    final content = message['content'] as String?;
    final createdAt = message['createdAt'] as String?;
    if (conversationId == null || content == null || createdAt == null) return;

    ref.read(conversationsProvider.notifier).applyIncomingMessage(
          conversationId: conversationId,
          content: content,
          createdAt: DateTime.tryParse(createdAt) ?? DateTime.now(),
          fromMe: fromMe,
        );
  }

  void _handleIncomingMessage(Map<String, dynamic> event) {
    final message = event['message'] as Map<String, dynamic>?;
    if (message == null) return;
    final conversationId = message['conversationId'] as String?;
    if (conversationId == null) return;

    _applyMessageToList(event, fromMe: false);

    final senderUsername =
        (event['senderUsername'] as String?) ?? _resolvePeerUsername(conversationId) ?? 'Сообщение';

    if (_resolvePeerUsername(conversationId) == null) {
      // First message from someone who added us — surface the conversation.
      unawaited(ref.read(conversationsProvider.notifier).refresh());
    }

    // Don't buzz for a chat the user is already looking at.
    final viewing = ref.read(activeChatConversationIdProvider);
    if (_inForeground && viewing == conversationId) return;

    final preview = (message['content'] as String?) ?? '';
    unawaited(CallNotifications.showMessage(
      conversationId: conversationId,
      senderUsername: senderUsername,
      preview: preview,
    ));
    unawaited(DesktopNotifications.showMessage(
      conversationId: conversationId,
      senderUsername: senderUsername,
      preview: preview,
    ));
  }

  String? _resolvePeerUsername(String conversationId) {
    final conversations = ref.read(conversationsProvider).valueOrNull;
    if (conversations == null) return null;
    for (final c in conversations) {
      if (c.id == conversationId) return c.peer.username;
    }
    return null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _actionPort?.close();
    _wsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If the node session drops (password rotated, node reinstalled, user
    // switched servers), the old user session belonged to that node's own
    // user database and no longer means anything — clear it too.
    ref.listen(nodeControllerProvider, (previous, next) {
      final wasConnected = previous?.valueOrNull?.isConnected ?? false;
      final isConnected = next.valueOrNull?.isConnected ?? false;
      if (wasConnected && !isConnected) {
        ref.read(authControllerProvider.notifier).logout();
      }
    });

    // Own/disconnect the single WS connection as auth state transitions.
    ref.listen(authControllerProvider, (previous, next) {
      final wasAuthenticated = previous?.valueOrNull?.isAuthenticated ?? false;
      final isAuthenticated = next.valueOrNull?.isAuthenticated ?? false;
      final userToken = next.valueOrNull?.accessToken;

      if (isAuthenticated && userToken != null && !wasAuthenticated) {
        final node = ref.read(nodeControllerProvider).valueOrNull;
        if (node != null && node.host != null && node.nodeToken != null) {
          unawaited(ref.read(authControllerProvider.notifier).registerPushToken());
          // A restored session is rebuilt from the id and tag kept on disk,
          // so it knows nothing about the avatar. Without this the user's own
          // picture disappears on every launch.
          unawaited(ref.read(authControllerProvider.notifier).refreshProfile());
          // Recording is a node-side switch, so ask on every connect.
          unawaited(ref.read(diagnosticsReporterProvider).syncWithNode());
          ref.read(wsClientProvider).connect(
                host: node.host!,
                nodeToken: node.nodeToken!,
                userToken: userToken,
                pinnedFingerprint: node.pinnedFingerprint,
                onFirstPin: (fp) => ref.read(nodeControllerProvider.notifier).recordPinnedFingerprint(fp),
                // Access tokens expire well within a session; let the socket
                // renew rather than staying locked out until the next login.
                refreshAccessToken: () async {
                  final ok = await ref.read(authControllerProvider.notifier).tryRefresh();
                  if (!ok) return null;
                  return ref.read(authControllerProvider).valueOrNull?.accessToken;
                },
              );
        }
      } else if (!isAuthenticated && wasAuthenticated) {
        ref.read(wsClientProvider).disconnect();
      }
    });

    final router = ref.watch(routerProvider);
    // Rebuilds the whole theme (and repaints every screen reading AppColors)
    // when the user picks a different palette.
    final palette = ref.watch(appearanceProvider).palette;
    final theme = buildAppTheme(palette);

    return MaterialApp.router(
      title: 'StillHere',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
