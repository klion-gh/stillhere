import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/node_http_client.dart';
import '../../core/providers.dart';
import 'node_state.dart';

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
      final res = await dio.post('/node/pair', data: {'password': password});
      final nodeToken = res.data['nodeToken'] as String;
      final fingerprintToStore = newlyPinned ?? pinned;

      await storage.saveHost(host);
      await storage.saveNodeToken(nodeToken);
      if (fingerprintToStore != null) {
        await storage.saveFingerprint(fingerprintToStore);
      }

      state = AsyncValue.data(NodeState(host: host, nodeToken: nodeToken, pinnedFingerprint: fingerprintToStore));
    } catch (e) {
      final exception = _mapError(e);
      state = AsyncValue.error(exception, StackTrace.current);
      throw exception;
    }
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

  Future<void> recordPinnedFingerprint(String fingerprint) async {
    await ref.read(nodeStorageProvider).saveFingerprint(fingerprint);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(current.copyWith(pinnedFingerprint: fingerprint));
    }
  }

  /// Clears the whole node session (host, node token, pinned cert) so the
  /// router sends the user back to /connect. Used both when the user
  /// explicitly switches servers and when the node token itself is
  /// rejected server-side (password rotated, node reinstalled, etc).
  Future<void> disconnect() async {
    await ref.read(nodeStorageProvider).clearAll();
    state = const AsyncValue.data(NodeState());
  }
}

final nodeControllerProvider = AsyncNotifierProvider<NodeController, NodeState>(NodeController.new);
