/// A conversation: the other person, and a preview of the last thing said, which
/// is what the chat list shows.
library;

import 'user.dart';

class LastMessage {
  final String content;
  final DateTime createdAt;
  final bool fromMe;

  const LastMessage({required this.content, required this.createdAt, required this.fromMe});

  factory LastMessage.fromJson(Map<String, dynamic> json) {
    return LastMessage(
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      fromMe: json['fromMe'] as bool? ?? false,
    );
  }
}

class Conversation {
  final String id;
  final AppUser peer;
  final DateTime createdAt;
  final LastMessage? lastMessage;

  const Conversation({
    required this.id,
    required this.peer,
    required this.createdAt,
    this.lastMessage,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      peer: AppUser.fromJson(json['peer'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastMessage: json['lastMessage'] != null
          ? LastMessage.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
    );
  }

  Conversation copyWith({AppUser? peer, LastMessage? lastMessage}) {
    return Conversation(
      id: id,
      peer: peer ?? this.peer,
      createdAt: createdAt,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}
