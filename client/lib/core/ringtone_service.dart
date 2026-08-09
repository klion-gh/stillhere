import 'package:audioplayers/audioplayers.dart';

import 'logger.dart';

const _tag = 'ringtone';

/// Plays the looping ring tones for calls. Two distinct tones: the incoming
/// ring (heard by the callee) and the quieter ringback (heard by the caller
/// while waiting). Both loop until explicitly stopped.
class RingtoneService {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  Future<void> _play(String asset, {required double volume}) async {
    if (_playing) await stop();
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(volume);
      await _player.play(AssetSource(asset));
      _playing = true;
    } catch (e, st) {
      // A missing audio device shouldn't take the call down with it.
      AppLogger.error(_tag, 'failed to play $asset', e, st);
    }
  }

  Future<void> playIncoming() => _play('sounds/ring_incoming.wav', volume: 1.0);

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
