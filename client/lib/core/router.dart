/// Routing, and the redirects that decide which of three states the app is in:
/// not paired with a node, paired but signed out, or signed in. The router
/// re-evaluates whenever either controller changes, so pairing, signing out or
/// having a token rejected moves the user without any screen having to navigate.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/appearance/appearance_screen.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/calls/call_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/connect/connect_screen.dart';
import '../features/connect/node_controller.dart';
import '../features/conversations/conversations_list_screen.dart';
import '../features/conversations/user_search_screen.dart';
import '../features/profile/profile_screen.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(nodeControllerProvider, (_, __) => notifyListeners());
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/connect',
    refreshListenable: refresh,
    redirect: (context, state) {
      final nodeState = ref.read(nodeControllerProvider);
      final authState = ref.read(authControllerProvider);
      if (nodeState.isLoading || authState.isLoading) return null;

      final isConnected = nodeState.valueOrNull?.isConnected ?? false;
      final isAuthenticated = authState.valueOrNull?.isAuthenticated ?? false;
      final loc = state.matchedLocation;

      // Gate 1: must be paired with a node before anything else.
      if (!isConnected) {
        return loc == '/connect' ? null : '/connect';
      }
      // Gate 2: paired, but no user session yet.
      if (!isAuthenticated) {
        final atAuthScreen = loc == '/login' || loc == '/register';
        return atAuthScreen ? null : '/login';
      }
      // Fully set up — bounce off any gate screen into the app.
      final atGateScreen = loc == '/connect' || loc == '/login' || loc == '/register';
      return atGateScreen ? '/conversations' : null;
    },
    routes: [
      GoRoute(path: '/connect', builder: (context, state) => const ConnectScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/conversations', builder: (context, state) => const ConversationsListScreen()),
      GoRoute(path: '/search', builder: (context, state) => const UserSearchScreen()),
      GoRoute(path: '/appearance', builder: (context, state) => const AppearanceScreen()),
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(
        path: '/chat/:conversationId',
        builder: (context, state) => ChatScreen(
          conversationId: state.pathParameters['conversationId']!,
          peerUsername: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/call/:conversationId',
        builder: (context, state) => CallScreen(
          conversationId: state.pathParameters['conversationId']!,
          peerUsername: state.uri.queryParameters['peer'] ?? '',
          isOutgoing: state.uri.queryParameters['outgoing'] == 'true',
        ),
      ),
    ],
  );
});
