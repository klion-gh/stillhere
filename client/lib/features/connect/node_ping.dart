import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/node_http_client.dart';
import 'saved_node.dart';

/// Round trip to a node, or null when it can't be reached.
class NodePing {
  final int? millis;

  const NodePing(this.millis);

  bool get reachable => millis != null;
}

/// Measures the round trip to a saved node.
///
/// Uses /health, which sits outside the node-token gate, so this says
/// something about the server being up rather than about the credential still
/// being valid — that's exactly what a tile wants to show. Kept short: a tile
/// that spins for ten seconds is worse than one that says "нет связи".
final nodePingProvider = FutureProvider.autoDispose.family<NodePing, SavedNode>((ref, node) async {
  final httpClient = HttpClient()
    ..badCertificateCallback = buildPinningCallback(
      pinnedFingerprint: node.pinnedFingerprint,
      // Pinning happens when connecting for real; a ping must never be what
      // establishes trust in a certificate.
      onFirstPin: (_) {},
    );

  final dio = Dio(BaseOptions(
    baseUrl: 'https://${node.host}',
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
  ));
  dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => httpClient);

  final started = DateTime.now();
  try {
    await dio.get('/health');
    return NodePing(DateTime.now().difference(started).inMilliseconds);
  } catch (_) {
    return const NodePing(null);
  } finally {
    httpClient.close(force: true);
  }
});
