/// The ring tones: incoming, and the ringback the caller hears while waiting.
///
/// Both loop until stopped, and the incoming one is routed to the phone's ringer
/// stream so it follows the ringer volume and stays quiet when the phone is.
library;

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import 'logger.dart';

const _tag = 'ringtone';

/// Plays the looping ring tones for calls. Two distinct tones: the incoming
/// ring (heard by the callee) and the quieter ringback (heard by the caller
/// while waiting). Both loop until explicitly stopped.
class RingtoneService {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  /// Routes the ring to the phone's ringer stream rather than media, so it
  /// follows the ringer volume and stays silent when the phone is.
  static final _ringContext = AudioContext(
    android: const AudioContextAndroid(
      usageType: AndroidUsageType.notificationRingtone,
      contentType: AndroidContentType.sonification,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      stayAwake: true,
    ),
  );

  Future<void> _play(String asset, {required double volume, bool asRingtone = false}) async {
    if (_playing) await stop();
    try {
      if (asRingtone && Platform.isAndroid) {
        await _player.setAudioContext(_ringContext);
      }
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(volume);
      await _player.play(AssetSource(asset));
      _playing = true;
    } catch (e, st) {
      // A missing audio device shouldn't take the call down with it.
      AppLogger.error(_tag, 'failed to play $asset', e, st);
    }
  }

  /// Android notification channels play their sound exactly once, which is
  /// why the ring used to stop after a single pass. The notification is now
  /// silent whenever the app is alive to ring for itself, and this loops
  /// until the call is answered, declined or gives up.
  Future<void> playIncoming() => _play('sounds/ring_incoming.mp3', volume: 1.0, asRingtone: true);

  Future<void> playOutgoing() => _play('sounds/ring_outgoing.wav', volume: 0.5);

  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    try {
      await _player.stop();
    } catch (e) {
      AppLogger.warn(_tag, 'failed to stop playback: $e');
    }
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
