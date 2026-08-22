import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/connect/saved_node.dart';
import 'logger.dart';

const _tag = 'node-storage';

/// Persists the connection to a StillHere node — separate from
/// [TokenStorage], which holds the per-user session. Survives user logout;
/// only cleared when the user explicitly switches or forgets the node.
///
/// Two things live here: the node currently in use, and every node paired at
/// any point. Disconnecting clears the first and leaves the second, which is
/// what turns "switch server" from retyping an address and a password into
/// tapping a tile.
class NodeStorage {
  final _storage = const FlutterSecureStorage();

  static const _kHost = 'node_host';
  static const _kNodeToken = 'node_token';
  static const _kFingerprint = 'node_cert_fingerprint';
  static const _kSavedNodes = 'saved_nodes';

  Future<void> saveHost(String host) => _storage.write(key: _kHost, value: host);
  Future<void> saveNodeToken(String token) => _storage.write(key: _kNodeToken, value: token);
  Future<void> saveFingerprint(String fingerprint) => _storage.write(key: _kFingerprint, value: fingerprint);

  Future<String?> readHost() => _storage.read(key: _kHost);
  Future<String?> readNodeToken() => _storage.read(key: _kNodeToken);
  Future<String?> readFingerprint() => _storage.read(key: _kFingerprint);

  Future<void> clearFingerprint() => _storage.delete(key: _kFingerprint);

  /// Clears the active connection only. The saved list is deliberately left
  /// alone — switching away from a server shouldn't make the user pair with
  /// it from scratch to come back.
  Future<void> clearAll() => Future.wait([
        _storage.delete(key: _kHost),
        _storage.delete(key: _kNodeToken),
        _storage.delete(key: _kFingerprint),
      ]);

  Future<List<SavedNode>> readSavedNodes() async {
    try {
      final raw = await _storage.read(key: _kSavedNodes);
      // Anyone upgrading was paired before this list existed. Their node is
      // in the single-connection keys, and without adopting it here the
      // server they use every day would simply not be in the list.
      if (raw == null || raw.isEmpty) return _adoptActiveNode();
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(SavedNode.fromJson)
          .whereType<SavedNode>()
          .toList();
      list.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
      return list;
    } catch (e, st) {
      // A corrupt list must not lock the user out of the app; they can always
      // pair again by hand.
      AppLogger.error(_tag, 'could not read saved nodes', e, st);
      return const [];
    }
  }

  /// Turns a pre-existing single connection into the first list entry, and
  /// writes it back so this only happens once.
  Future<List<SavedNode>> _adoptActiveNode() async {
    final host = await readHost();
    final token = await readNodeToken();
    if (host == null || host.isEmpty || token == null || token.isEmpty) return const [];

    final adopted = SavedNode(
      host: host,
      nodeToken: token,
      pinnedFingerprint: await readFingerprint(),
      lastUsedAt: DateTime.now(),
    );
    await _writeSavedNodes([adopted]);
    AppLogger.info(_tag, 'adopted the existing connection to $host into the saved list');
    return [adopted];
  }

  Future<void> _writeSavedNodes(List<SavedNode> nodes) async {
    await _storage.write(
      key: _kSavedNodes,
      value: jsonEncode(nodes.map((n) => n.toJson()).toList()),
    );
  }

  /// Adds or refreshes a node, keyed by host. Re-pairing with a server the
  /// user already had replaces its token rather than listing it twice.
  Future<void> rememberNode(SavedNode node) async {
    final nodes = await readSavedNodes();
    final updated = [node, ...nodes.where((n) => n.host != node.host)];
    await _writeSavedNodes(updated);
    AppLogger.info(_tag, 'remembered ${node.host} (${updated.length} saved)');
  }

  Future<void> forgetNode(String host) async {
    final nodes = await readSavedNodes();
    await _writeSavedNodes(nodes.where((n) => n.host != host).toList());
    AppLogger.info(_tag, 'forgot $host');
  }

  /// Keeps a saved entry in step with a fingerprint pinned after the fact —
  /// the first connection to a self-signed node pins its certificate only
  /// once the TLS handshake has happened.
  Future<void> updateSavedFingerprint(String host, String fingerprint) async {
    final nodes = await readSavedNodes();
    final index = nodes.indexWhere((n) => n.host == host);
    if (index < 0) return;
    nodes[index] = nodes[index].copyWith(pinnedFingerprint: fingerprint);
    await _writeSavedNodes(nodes);
  }
}
