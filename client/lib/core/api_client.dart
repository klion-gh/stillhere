import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/connect/node_client.dart';
import '../features/connect/node_controller.dart';

/// Dio instance for authenticated REST calls: attaches both the node token
/// (this device's pairing with the node) and the current user's access
/// token, transparently refreshes the latter once on a 401, and rebuilds
/// itself whenever the node connection changes.
final apiClientProvider = Provider<Dio>((ref) {
  // Rebuild (fresh Dio, fresh base URL/pinning) whenever the node
  // connection changes — host set after pairing, fingerprint pinned, or
  // disconnect.
  ref.watch(nodeControllerProvider);
  final dio = buildNodeDio(ref);

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = ref.read(authControllerProvider).valueOrNull?.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final code =
            (error.response?.data is Map) ? (error.response!.data as Map)['error'] as String? : null;

        if (code == 'missing_node_token' || code == 'invalid_node_token') {
          // The node itself rejected us (password rotated, node
          // reinstalled, etc) — no amount of user-token refreshing fixes
          // this. Drop the node session so the router sends the user back
          // to /connect to re-pair.
          await ref.read(nodeControllerProvider.notifier).disconnect();
          return handler.next(error);
        }

        final isAuthEndpoint = error.requestOptions.path.startsWith('/auth/');
        if (error.response?.statusCode == 401 && !isAuthEndpoint) {
          final refreshed = await ref.read(authControllerProvider.notifier).tryRefresh();
          if (refreshed) {
            final token = ref.read(authControllerProvider).valueOrNull?.accessToken;
            final retryOptions = error.requestOptions;
            retryOptions.headers['Authorization'] = 'Bearer $token';
            try {
              final response = await dio.fetch(retryOptions);
              return handler.resolve(response);
            } catch (retryError) {
              return handler.next(error);
            }
          }
        }
        handler.next(error);
      },
    ),
  );

  return dio;
});
