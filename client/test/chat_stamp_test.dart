import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:stillhere/features/conversations/chat_stamp.dart';

void main() {
  final now = DateTime(2026, 8, 16, 21, 0);

  group('before main() loads the locale', () {
    test('the weekday branch throws — this is what drew the grey box', () {
      expect(
        () => formatChatStamp(DateTime(2026, 8, 13, 12, 0), now: now),
        throwsA(anything),
      );
    });

    test('but today and older dates were always fine', () {
      expect(formatChatStamp(DateTime(2026, 8, 16, 9, 5), now: now), '09:05');
      expect(formatChatStamp(DateTime(2026, 7, 1, 9, 5), now: now), isNotEmpty);
    });
  });

  group('after initialization', () {
    setUpAll(() async {
      await initializeDateFormatting('ru');
      Intl.defaultLocale = 'ru';
    });

    test('today shows a 24-hour time', () {
      expect(formatChatStamp(DateTime(2026, 8, 16, 9, 5), now: now), '09:05');
      expect(formatChatStamp(DateTime(2026, 8, 16, 21, 5), now: now), '21:05');
    });

    test('within the last week shows a Russian weekday', () {
      // 13 Aug 2026 is a Thursday.
      expect(formatChatStamp(DateTime(2026, 8, 13, 12, 0), now: now), 'чт');
    });

    test('a week or more back shows a date', () {
      final stamp = formatChatStamp(DateTime(2026, 7, 1, 12, 0), now: now);
      expect(stamp, contains('2026'));
    });

    test('the boundary at exactly seven days does not throw', () {
      expect(
        () => formatChatStamp(now.subtract(const Duration(days: 7)), now: now),
        returnsNormally,
      );
    });
  });
}
