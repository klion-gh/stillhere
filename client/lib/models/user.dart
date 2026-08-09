class AppUser {
  final String id;
  final String username;

  const AppUser({required this.id, required this.username});

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(id: json['id'] as String, username: json['username'] as String);
  }
}
