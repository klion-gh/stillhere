import 'package:intl/intl.dart';

/// Timestamp shown beside a chat in the conversation list: a time for today,
/// a weekday within the last week, a date beyond that — the usual messenger
/// shorthand, so the column stays narrow.
///
/// Lives outside the widget so the weekday branch can be tested. It reaches
/// for Russian locale data that `main()` loads at startup; without that load
/// this throws, and a throw inside `build()` is replaced in release builds by
/// a grey ErrorWidget that expands to fill the whole viewport.
String formatChatStamp(DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final today = now ?? DateTime.now();
  final sameDay = local.year == today.year && local.month == today.month && local.day == today.day;
  if (sameDay) return DateFormat.Hm().format(local);
  if (today.difference(local).inDays < 7) return DateFormat.E('ru').format(local);
  return DateFormat.yMd().format(local);
}
