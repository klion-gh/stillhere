import 'package:flutter_riverpod/flutter_riverpod.dart';

class IncomingCall {
  final String conversationId;
  final String fromUserId;
  final Map<String, dynamic> sdp;

  const IncomingCall({required this.conversationId, required this.fromUserId, required this.sdp});
}

/// Set by the app-level WS listener when a call:offer arrives; consumed
/// (and cleared) by CallScreen when it opens as the callee.
final pendingIncomingCallProvider = StateProvider<IncomingCall?>((ref) => null);

/// Conversation id of the call currently in progress, if any. Used to
/// auto-decline a second incoming offer while already on a call.
final activeCallConversationIdProvider = StateProvider<String?>((ref) => null);
