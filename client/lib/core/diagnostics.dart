/// Mirrors the app's own log to the node while the node has recording switched
/// on.
///
/// Off is the default and the normal state. It exists so a problem that only
/// happens on someone else's phone — a call that won't connect, a push that
/// never lands — can be looked at afterwards instead of guessed at.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'logger.dart';

const _tag = 'diag';

/// Never grows without bound: if the node can't be reached, the oldest
/// entries are dropped rather than the app quietly eating memory.
const _maxBuffered = 500;
const _flushThreshold = 50;
const _flushInterval = Duration(seconds: 5);

final diagnosticsReporterProvider = Provider<DiagnosticsReporter>((ref) {
  final reporter = DiagnosticsReporter(ref);
  ref.onDispose(reporter.dispose);
  return reporter;
});

class _Entry {
  final DateTime at;
  final String level;
  final String tag;
  final String message;

  _Entry(this.at, this.level, this.tag, this.message);

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'source': Platform.isAndroid ? 'android' : (Platform.isWindows ? 'windows' : 'other'),
        'kind': '$tag.$level',
        'detail': message,
      };
}

/// Mirrors the app's own log to the node while diagnostics are switched on
/// there.
///
/// Off is the default and the normal state: the node answers "disabled", the
/// logger sink stays unset, and nothing leaves the device. It exists so that
/// a problem which only shows up on someone else's phone — a call that won't
/// connect, a push that never lands — can be looked at afterwards instead of
/// guessed at.
class DiagnosticsReporter {
  DiagnosticsReporter(this._ref);

  final Ref _ref;
  final Queue<_Entry> _buffer = Queue<_Entry>();
  Timer? _timer;
  bool _enabled = false;
  bool _sending = false;

  bool get enabled => _enabled;

  /// Asks the node whether to record. Called whenever the socket connects, so
  /// a device that was offline when the switch was flipped picks it up.
  Future<void> syncWithNode() async {
    try {
      final dio = _ref.read(apiClientProvider);
      final res = await dio.get('/diagnostics/config');
      setEnabled((res.data as Map)['enabled'] == true);
    } catch (e) {
      // An older node has no such endpoint; that simply means no recording.
      AppLogger.info(_tag, 'node did not report diagnostics config: $e');
      setEnabled(false);
    }
  }

  void setEnabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;

    if (value) {
      AppLogger.warn(_tag, 'diagnostics recording is ON for this node');
      AppLogger.sink = _capture;
      _timer = Timer.periodic(_flushInterval, (_) => unawaited(flush()));
    } else {
      AppLogger.sink = null;
      _timer?.cancel();
      _timer = null;
      _buffer.clear();
      AppLogger.info(_tag, 'diagnostics recording is off');
    }
  }

  void _capture(String level, String tag, String message) {
    // Would otherwise log its own uploads and never stop.
    if (tag == _tag) return;
    _buffer.add(_Entry(DateTime.now(), level, tag, message));
    while (_buffer.length > _maxBuffered) {
      _buffer.removeFirst();
    }
    if (_buffer.length >= _flushThreshold) unawaited(flush());
  }

  Future<void> flush() async {
    if (!_enabled || _sending || _buffer.isEmpty) return;
    _sending = true;

    final batch = _buffer.toList(growable: false);
    _buffer.clear();
    try {
      final dio = _ref.read(apiClientProvider);
      await dio.post(
        '/diagnostics/events',
        data: {'events': batch.map((e) => e.toJson()).toList()},
      );
    } on DioException catch (e) {
      // Put them back so a flaky connection doesn't lose the trail — but only
      // up to the cap, and oldest-first so recent context survives.
      _buffer.addAll(batch);
      while (_buffer.length > _maxBuffered) {
        _buffer.removeFirst();
      }
      AppLogger.info(_tag, 'flush failed, ${_buffer.length} buffered: ${e.message}');
    } finally {
      _sending = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    if (AppLogger.sink == _capture) AppLogger.sink = null;
  }
}
