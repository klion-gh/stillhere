/// An account the user has signed into on a particular node.
///
/// Holds the refresh token, never the password. That's the whole point: a
/// tile can restore a session because the node issued a long-lived
/// credential for exactly that, and a stolen phone yields a token the node
/// can invalidate rather than a password that probably unlocks other things
/// too. The token has a life of its own — around a month — after which the
/// tile falls back to asking for the password.
///
/// Scoped by host: two nodes each have their own user database, so the same
/// tag on different servers is two different people.
class SavedAccount {
  final String host;
  final String userId;
  final String username;
  final String refreshToken;
  final bool hasAvatar;
  final DateTime? avatarUpdatedAt;
  final DateTime lastUsedAt;

  const SavedAccount({
    required this.host,
    required this.userId,
    required this.username,
    required this.refreshToken,
    required this.lastUsedAt,
    this.hasAvatar = false,
    this.avatarUpdatedAt,
  });

  SavedAccount copyWith({
    String? username,
    String? refreshToken,
    bool? hasAvatar,
    DateTime? avatarUpdatedAt,
    DateTime? lastUsedAt,
  }) {
    return SavedAccount(
      host: host,
      userId: userId,
      username: username ?? this.username,
      refreshToken: refreshToken ?? this.refreshToken,
      hasAvatar: hasAvatar ?? this.hasAvatar,
      avatarUpdatedAt: avatarUpdatedAt ?? this.avatarUpdatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  /// Value equality so this can key a provider family without a rebuild
  /// creating a fresh one. lastUsedAt is excluded: it changes on every sign-in
  /// and says nothing about which account this is.
  @override
  bool operator ==(Object other) =>
      other is SavedAccount &&
      other.host == host &&
      other.userId == userId &&
      other.username == username &&
      other.refreshToken == refreshToken;

  @override
  int get hashCode => Object.hash(host, userId, username, refreshToken);

  Map<String, dynamic> toJson() => {
        'host': host,
        'userId': userId,
        'username': username,
        'refreshToken': refreshToken,
        'hasAvatar': hasAvatar,
        'avatarUpdatedAt': avatarUpdatedAt?.toIso8601String(),
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  static SavedAccount? fromJson(Map<String, dynamic> json) {
    final host = json['host'] as String?;
    final userId = json['userId'] as String?;
    final username = json['username'] as String?;
    final refreshToken = json['refreshToken'] as String?;
    if (host == null || userId == null || username == null || refreshToken == null) return null;
    if (host.isEmpty || refreshToken.isEmpty) return null;

    return SavedAccount(
      host: host,
      userId: userId,
      username: username,
      refreshToken: refreshToken,
      hasAvatar: json['hasAvatar'] as bool? ?? false,
      avatarUpdatedAt: DateTime.tryParse(json['avatarUpdatedAt'] as String? ?? ''),
      lastUsedAt: DateTime.tryParse(json['lastUsedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
