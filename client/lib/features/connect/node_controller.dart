import 'dart:async';

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../core/node_http_client.dart';
import '../../core/providers.dart';
import '../../core/push_service.dart';
import 'node_client.dart';
import 'saved_node.dart';
import 'node_state.dart';

const _tag = 'node';

class NodeController extends AsyncNotifier<NodeState> {
  @override
  Future<NodeState> build() async {
    final storage = ref.read(nodeStorageProvider);
    final host = await storage.readHost();
    final nodeToken = await storage.readNodeToken();
    final fingerprint = await storage.readFingerprint();
    return NodeState(host: host, nodeToken: nodeToken, pinnedFingerprint: fingerprint);
  }

  String _normalizeHost(String raw) {
    var host = raw.trim();
    host = host.replaceFirst(RegExp(r'^https?://'), '');
    host = host.replaceFirst(RegExp(r'/+$'), '');
    return host;
  }

  Future<void> pair(String rawHost, String password) async {
    final host = _normalizeHost(rawHost);
    if (host.isEmpty) {
      throw NodeConnectException('Введите адрес сервера.');
    }

    final storage = ref.read(nodeStorageProvider);
    final previousHost = await storage.readHost();
    final samePinnedHost = previousHost == host;
    final pinned = samePinnedHost ? await storage.readFingerprint() : null;
    if (!samePinnedHost) {
      await storage.clearFingerprint();
    }

    state = const AsyncValue.loading();

    String? newlyPinned;
    final httpClient = HttpClient()
      ..badCertificateCallback = buildPinningCallback(
        pinnedFingerprint: pinned,
        onFirstPin: (fp) => newlyPinned = fp,
      );

    final dio = Dio(BaseOptions(baseUrl: 'https://$host', connectTimeout: const Duration(seconds: 10)));
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => httpClient);

    try {
      AppLogger.info(_tag, 'pairing with $host...');
      final res = await dio.post('/node/pair', data: {'password': password});
      final nodeToken = res.data['nodeToken'] as String;
      final fingerprintToStore = newlyPinned ?? pinned;

      await storage.saveHost(host);
      await storage.saveNodeToken(nodeToken);
      if (fingerprintToStore != null) {
        await storage.saveFingerprint(fingerprintToStore);
      }

      await storage.rememberNode(SavedNode(
        host: host,
        nodeToken: nodeToken,
        pinnedFingerprint: fingerprintToStore,
        lastUsedAt: DateTime.now(),
      ));
      ref.invalidate(savedNodesProvider);

      AppLogger.info(_tag, 'paired with $host');
      state = AsyncValue.data(NodeState(host: host, nodeToken: nodeToken, pinnedFingerprint: fingerprintToStore));

      // Each node pushes through its own Firebase project, so the app is
      // told which one to use rather than carrying a hardcoded project.
      unawaited(_configurePushFromNode(dio, nodeToken));
    } catch (e, st) {
      final exception = _mapError(e);
      AppLogger.error(_tag, 'pairing with $host failed', e, st);
      state = AsyncValue.error(exception, StackTrace.current);
      throw exception;
    }
  }

  /// Asks the node which Firebase project to use for push. A node without
  /// one configured simply answers that it's disabled, and the app runs
  /// without background delivery.
  Future<void> _configurePushFromNode(Dio dio, String nodeToken) async {
    try {
      final res = await dio.get(
        '/node/push-config',
        options: Options(headers: {'X-Node-Token': nodeToken}),
      );
      final data = res.data as Map<String, dynamic>;
      if (data['enabled'] != true) {
        AppLogger.info(_tag, 'node has no push configured');
        await PushService.forget();
        return;
      }
      await PushService.configure(PushConfig.fromJson(data));
    } catch (e) {
      AppLogger.warn(_tag, 'could not fetch push config: $e');
    }
  }

  /// Loads push config for a node paired in an earlier session, so push keeps
  /// working across restarts without re-pairing.
  Future<void> restorePushConfig() async {
    final current = state.valueOrNull;
    if (current == null || !current.isConnected) return;
    final stored = await loadStoredPushConfig();
    if (stored != null) {
      await PushService.configure(stored);
      return;
    }
    // Paired before this mechanism existed (or config was cleared): ask now.
    await _configurePushFromNode(buildNodeDio(ref), current.nodeToken!);
  }

  NodeConnectException _mapError(Object e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.connectionError || e.error is HandshakeException) {
        return NodeConnectException(
          'Не удалось установить защищённое соединение. Возможно, сертификат сервера изменился.',
        );
      }
      if (e.response?.statusCode == 401) {
        return NodeConnectException('Неверный пароль узла.');
      }
      if (e.response?.statusCode == 503) {
        return NodeConnectException('Узел ещё не настроен до конца. Попробуйте через минуту.');
      }
      return NodeConnectException('Не удалось подключиться к серверу. Проверьте адрес.');
    }
    return NodeConnectException('Не удалось подключиться к серверу.');
  }

  /// Reconnects to a node the user has paired with before.
  ///
  /// No password: the node token is what the pairing produced and it lasts a
  /// year. It can still have been invalidated — the node reinstalled, its
  /// password rotated — so the token is probed against an endpoint behind the
  /// gate before the session is accepted. Failing that check reports the
  /// problem instead of dropping the user into an app that 401s everywhere.
  Future<void> connectToSaved(SavedNode node) async {
    state = const AsyncValue.loading();

    String? newlyPinned;
    final httpClient = HttpClient()
      ..badCertificateCallback = buildPinningCallback(
        pinnedFingerprint: node.pinnedFingerprint,
        onFirstPin: (fp) => newlyPinned = fp,
      );

    final dio = Dio(BaseOptions(
      baseUrl: 'https://${node.host}',
      connectTimeout: const Duration(seconds: 10),
      headers: {'X-Node-Token': node.nodeToken},
    ));
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => httpClient);

    try {
      AppLogger.info(_tag, 'reconnecting to ${node.host} with the saved token...');
      await dio.get('/node/push-config');

      final storage = ref.read(nodeStorageProvider);
      final fingerprint = newlyPinned ?? node.pinnedFingerprint;
      await storage.saveHost(node.host);
      await storage.saveNodeToken(node.nodeToken);
      if (fingerprint != null) await storage.saveFingerprint(fingerprint);
      await storage.rememberNode(node.copyWith(
        pinnedFingerprint: fingerprint,
        lastUsedAt: DateTime.now(),
      ));
      ref.invalidate(savedNodesProvider);

      state = AsyncValue.data(
        NodeState(host: node.host, nodeToken: node.nodeToken, pinnedFingerprint: fingerprint),
      );
      AppLogger.info(_tag, 'reconnected to ${node.host}');

      unawaited(_configurePushFromNode(dio, node.nodeToken));
    } catch (e, st) {
      final exception = e is DioException && e.response?.statusCode == 401
          ? NodeConnectException('Узел больше не принимает сохранённый доступ. Добавьте его заново с паролем.')
          : _mapError(e);
      AppLogger.error(_tag, 'reconnecting to ${node.host} failed', e, st);
      state = AsyncValue.error(exception, StackTrace.current);
      throw exception;
    }
  }

  Future<void> forgetSaved(String host) async {
    await ref.read(nodeStorageProvider).forgetNode(host);
    ref.invalidate(savedNodesProvider);
  }

  Future<void> recordPinnedFingerprint(String fingerprint) async {
    final storage = ref.read(nodeStorageProvider);
    await storage.saveFingerprint(fingerprint);
    final current = state.valueOrNull;
    if (current != null) {
      if (current.host != null) {
        await storage.updateSavedFingerprint(current.host!, fingerprint);
      }
      state = AsyncValue.data(current.copyWith(pinnedFingerprint: fingerprint));
    }
  }

  /// Clears the whole node session (host, node token, pinned cert) so the
  /// router sends the user back to /connect. Used both when the user
  /// explicitly switches servers and when the node token itself is
  /// rejected server-side (password rotated, node reinstalled, etc).
  Future<void> disconnect() async {
    AppLogger.warn(_tag, 'disconnecting from node');
    // Drop the node's Firebase project too, so the next node doesn't inherit
    // it and end up pushing through someone else's project.
    await PushService.forget();
    await ref.read(nodeStorageProvider).clearAll();
    state = const AsyncValue.data(NodeState());
  }
}

final nodeControllerProvider = AsyncNotifierProvider<NodeController, NodeState>(NodeController.new);

/// Nodes the user has paired with, most recently used first.
final savedNodesProvider = FutureProvider<List<SavedNode>>((ref) async {
  return ref.read(nodeStorageProvider).readSavedNodes();
});
