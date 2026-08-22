/// A node the user has paired with before.
///
/// The node token is a year-long credential, so returning to a server the
/// user has already used needs no password — just this record. The pinned
/// certificate fingerprint travels with it: it belongs to the host, and
/// keeping it per host is what lets someone move between two self-signed
/// nodes without either one looking like a man in the middle.
class SavedNode {
  final String host;
  final String nodeToken;
  final String? pinnedFingerprint;
  final DateTime lastUsedAt;

  const SavedNode({
    required this.host,
    required this.nodeToken,
    required this.lastUsedAt,
    this.pinnedFingerprint,
  });

  SavedNode copyWith({String? nodeToken, String? pinnedFingerprint, DateTime? lastUsedAt}) {
    return SavedNode(
      host: host,
      nodeToken: nodeToken ?? this.nodeToken,
      pinnedFingerprint: pinnedFingerprint ?? this.pinnedFingerprint,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  /// Value equality matters: this is the key of the ping provider family, and
  /// with identity equality every rebuild would spin up a fresh provider and
  /// ping the server again. lastUsedAt is left out on purpose — it changes on
  /// every connect and says nothing about which server this is.
  @override
  bool operator ==(Object other) =>
      other is SavedNode &&
      other.host == host &&
      other.nodeToken == nodeToken &&
      other.pinnedFingerprint == pinnedFingerprint;

  @override
  int get hashCode => Object.hash(host, nodeToken, pinnedFingerprint);

  Map<String, dynamic> toJson() => {
        'host': host,
        'nodeToken': nodeToken,
        'pinnedFingerprint': pinnedFingerprint,
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  static SavedNode? fromJson(Map<String, dynamic> json) {
    final host = json['host'] as String?;
    final token = json['nodeToken'] as String?;
    if (host == null || host.isEmpty || token == null || token.isEmpty) return null;
    return SavedNode(
      host: host,
      nodeToken: token,
      pinnedFingerprint: json['pinnedFingerprint'] as String?,
      lastUsedAt: DateTime.tryParse(json['lastUsedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
