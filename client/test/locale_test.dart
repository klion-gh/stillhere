import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  final when = DateTime(2026, 8, 12, 15, 30);

  test('DateFormat.E(ru) throws until the locale data is loaded', () {
    // This is what made the conversation list show a grey box: the throw
    // happened inside build(), and release builds replace a failed subtree
    // with an ErrorWidget that expands to fill the viewport.
    expect(() => DateFormat.E('ru').format(when), throwsA(anything));
  });

  test('and works once main() has initialized it', () async {
    await initializeDateFormatting('ru');
    Intl.defaultLocale = 'ru';
    expect(DateFormat.E('ru').format(when), isNotEmpty);
    expect(DateFormat.Hm().format(when), '15:30');
    expect(DateFormat.yMd().format(when), isNotEmpty);
  });
}
