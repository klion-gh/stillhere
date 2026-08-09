import 'user.dart';

class Conversation {
  final String id;
  final AppUser peer;
  final DateTime createdAt;

  const Conversation({required this.id, required this.peer, required this.createdAt});

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      peer: AppUser.fromJson(json['peer'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
