/// Singletons that outlive any one screen: storage, the socket, the ringtone
/// player. Kept in one place so their lifetimes are visible together, and so
/// disposal is wired once rather than at each use site.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'node_storage.dart';
import 'ringtone_service.dart';
import 'token_storage.dart';
import 'ws_client.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final nodeStorageProvider = Provider<NodeStorage>((ref) => NodeStorage());

final wsClientProvider = Provider<WsClient>((ref) {
  final client = WsClient();
  ref.onDispose(client.dispose);
  return client;
});

final ringtoneServiceProvider = Provider<RingtoneService>((ref) {
  final service = RingtoneService();
  ref.onDispose(service.dispose);
  return service;
});

/// Live WebSocket connectivity, for the "connection lost" banner. Starts
/// optimistic so the UI doesn't flash a warning during initial connect.
final wsConnectedProvider = StreamProvider<bool>((ref) {
  return ref.watch(wsClientProvider).connectionState;
});
