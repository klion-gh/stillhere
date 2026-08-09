import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the connection to a StillHere node — separate from
/// [TokenStorage], which holds the per-user session. Survives user logout;
/// only cleared when the user explicitly switches/forgets the node.
class NodeStorage {
  final _storage = const FlutterSecureStorage();

  static const _kHost = 'node_host';
  static const _kNodeToken = 'node_token';
  static const _kFingerprint = 'node_cert_fingerprint';

  Future<void> saveHost(String host) => _storage.write(key: _kHost, value: host);
  Future<void> saveNodeToken(String token) => _storage.write(key: _kNodeToken, value: token);
  Future<void> saveFingerprint(String fingerprint) => _storage.write(key: _kFingerprint, value: fingerprint);

  Future<String?> readHost() => _storage.read(key: _kHost);
  Future<String?> readNodeToken() => _storage.read(key: _kNodeToken);
  Future<String?> readFingerprint() => _storage.read(key: _kFingerprint);

  Future<void> clearFingerprint() => _storage.delete(key: _kFingerprint);

  Future<void> clearAll() => Future.wait([
        _storage.delete(key: _kHost),
        _storage.delete(key: _kNodeToken),
        _storage.delete(key: _kFingerprint),
      ]);
}
