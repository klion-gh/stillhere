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

/// ICE candidates that arrived before the call controller existed.
///
/// The node holds the caller's candidates while a pushed device wakes up and
/// releases them right behind the offer — a frame or two before the call
/// screen has been built and subscribed to the socket. That event stream is a
/// broadcast stream, so anything sent before the subscription exists is
/// simply gone. Without this the callee is left with a session description
/// and no remote candidates: a call that rings and then never connects.
final pendingIncomingCandidatesProvider =
    StateProvider<List<Map<String, dynamic>>>((ref) => const []);

/// Conversation id of the call currently in progress, if any. Used to
/// auto-decline a second incoming offer while already on a call.
final activeCallConversationIdProvider = StateProvider<String?>((ref) => null);

/// Conversation the user currently has open, so incoming messages for it
/// don't fire a notification they're already reading.
final activeChatConversationIdProvider = StateProvider<String?>((ref) => null);
