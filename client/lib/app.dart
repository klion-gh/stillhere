import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/incoming_call.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'features/auth/auth_controller.dart';
import 'features/connect/node_controller.dart';
import 'features/conversations/conversations_controller.dart';

class StillHereApp extends ConsumerStatefulWidget {
  const StillHereApp({super.key});

  @override
  ConsumerState<StillHereApp> createState() => _StillHereAppState();
}

class _StillHereAppState extends ConsumerState<StillHereApp> {
  StreamSubscription<Map<String, dynamic>>? _callSignalSub;

  @override
  void initState() {
    super.initState();
    // Global listener: an incoming call can arrive while the user is
    // anywhere in the app (conversation list, a different chat, etc.), not
    // just while a ChatScreen/CallScreen happens to be mounted.
    _callSignalSub = ref.read(wsClientProvider).events.listen(_handleIncomingSignal);
  }

  void _handleIncomingSignal(Map<String, dynamic> event) {
    if (event['type'] != 'call:offer') return;

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

    final peerUsername = _resolvePeerUsername(conversationId) ?? '';
    ref.read(routerProvider).push('/call/$conversationId?peer=$peerUsername&outgoing=false');
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
    _callSignalSub?.cancel();
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
          ref.read(wsClientProvider).connect(
                host: node.host!,
                nodeToken: node.nodeToken!,
                userToken: userToken,
                pinnedFingerprint: node.pinnedFingerprint,
                onFirstPin: (fp) => ref.read(nodeControllerProvider.notifier).recordPinnedFingerprint(fp),
              );
        }
      } else if (!isAuthenticated && wasAuthenticated) {
        ref.read(wsClientProvider).disconnect();
      }
    });

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'StillHere',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true, brightness: Brightness.dark),
      routerConfig: router,
    );
  }
}
