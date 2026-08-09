import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'node_storage.dart';
import 'token_storage.dart';
import 'ws_client.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final nodeStorageProvider = Provider<NodeStorage>((ref) => NodeStorage());

final wsClientProvider = Provider<WsClient>((ref) {
  final client = WsClient();
  ref.onDispose(client.dispose);
  return client;
});
