/// A Dio instance scoped to the node: its base URL, its node token, its pinned
/// certificate. Used where the user's own token isn't needed or doesn't exist
/// yet — pairing and signing in. core/api_client.dart layers the user on top.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_config.dart';
import '../../core/node_http_client.dart';
import 'node_controller.dart';

/// A Dio instance scoped to the current node connection: base URL from the
/// paired node's host, X-Node-Token attached, TLS pinned to the node's
/// certificate. Used for anything that doesn't also need the per-user
/// Authorization token — auth endpoints, mainly. See core/api_client.dart
/// for the fully authenticated client layered on top of the same node
/// connection.
Dio buildNodeDio(Ref ref) {
  final nodeState = ref.read(nodeControllerProvider).valueOrNull;
  final baseUrl = nodeState?.host != null ? 'https://${nodeState!.host}' : ApiConfig.httpBaseUrl;

  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.badCertificateCallback = buildPinningCallback(
        pinnedFingerprint: ref.read(nodeControllerProvider).valueOrNull?.pinnedFingerprint,
        onFirstPin: (fp) => ref.read(nodeControllerProvider.notifier).recordPinnedFingerprint(fp),
      );
      return client;
    },
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = ref.read(nodeControllerProvider).valueOrNull?.nodeToken;
        if (token != null) {
          options.headers['X-Node-Token'] = token;
        }
        handler.next(options);
      },
    ),
  );
  return dio;
}
