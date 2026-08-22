/// What the app knows about its node: address, token, and the certificate
/// fingerprint pinned for it.
library;

class NodeState {
  final String? host;
  final String? nodeToken;
  final String? pinnedFingerprint;

  const NodeState({this.host, this.nodeToken, this.pinnedFingerprint});

  bool get isConnected => host != null && nodeToken != null;

  NodeState copyWith({String? host, String? nodeToken, String? pinnedFingerprint}) {
    return NodeState(
      host: host ?? this.host,
      nodeToken: nodeToken ?? this.nodeToken,
      pinnedFingerprint: pinnedFingerprint ?? this.pinnedFingerprint,
    );
  }
}

class NodeConnectException implements Exception {
  final String message;
  NodeConnectException(this.message);
  @override
  String toString() => message;
}
