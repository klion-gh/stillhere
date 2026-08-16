class AppUser {
  final String id;
  final String username;
  final bool hasAvatar;

  /// Bumped by the server whenever the picture changes; appended to the
  /// avatar URL so a new upload isn't hidden behind a cached old one.
  final DateTime? avatarUpdatedAt;

  const AppUser({
    required this.id,
    required this.username,
    this.hasAvatar = false,
    this.avatarUpdatedAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      username: json['username'] as String,
      hasAvatar: json['hasAvatar'] as bool? ?? false,
      avatarUpdatedAt: json['avatarUpdatedAt'] != null
          ? DateTime.tryParse(json['avatarUpdatedAt'] as String)
          : null,
    );
  }

  AppUser copyWith({String? username, bool? hasAvatar, DateTime? avatarUpdatedAt}) {
    return AppUser(
      id: id,
      username: username ?? this.username,
      hasAvatar: hasAvatar ?? this.hasAvatar,
      avatarUpdatedAt: avatarUpdatedAt ?? this.avatarUpdatedAt,
    );
  }
}
