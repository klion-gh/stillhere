import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/appearance.dart';
import 'core/call_notifications.dart';
import 'core/desktop_notifications.dart';
import 'core/incoming_call.dart';
import 'core/providers.dart';
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
  bool _inForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Global listener: incoming calls and messages can arrive while the user
    // is anywhere in the app — or nowhere, with it backgrounded.
    _wsSub = ref.read(wsClientProvider).events.listen(_handleWsEvent);
    CallNotifications.onCallAction = _handleCallNotificationAction;

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

      case CallNotificationAction.open:
        if (!isLive) _openCallScreen(event);
        break;
    }
  }

  void _openCallScreen(CallNotificationEvent event) {
    ref.read(routerProvider).push(
          '/call/${event.conversationId}?peer=${event.peerUsername}&outgoing=false',
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
      case 'message:new':
        _handleIncomingMessage(event);
        break;
      case 'conversation:new':
        // Someone started a conversation with us. Pull it into the list so
        // their messages and calls have somewhere to land, even though we
        // never added them.
        unawaited(ref.read(conversationsProvider.notifier).refresh());
        break;
    }
  }

  void _handleIncomingCall(Map<String, dynamic> event) {
    final conversationId = event['conversationId'] as String?;
    final sdp = event['sdp'] as Map<String, dynamic>?;
    final fromUserId = event['from'] as String?;
    if (conversationId == null || sdp == null || fromUserId == null) return;

    if (ref.read(activeCallConversationIdProvider) != null) {
      // Already on a call: politely decline the second incoming offer.
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

    // Heads-up notification with accept/decline, and the ringtone on
    // Android (a backgrounded app can't reliably play audio itself).
    unawaited(CallNotifications.showIncomingCall(
      conversationId: conversationId,
      peerUsername: peerUsername,
    ));
    unawaited(DesktopNotifications.showIncomingCall(
      conversationId: conversationId,
      peerUsername: peerUsername,
    ));
    ref.read(routerProvider).push('/call/$conversationId?peer=$peerUsername&outgoing=false');
  }

  void _handleIncomingMessage(Map<String, dynamic> event) {
    final message = event['message'] as Map<String, dynamic>?;
    if (message == null) return;
    final conversationId = message['conversationId'] as String?;
    if (conversationId == null) return;

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
