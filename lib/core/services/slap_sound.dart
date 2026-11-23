import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays the slap sound. Low-latency mode and a fresh start each time, so rapid slaps each
/// make a sound. Never throws: a game without sound is still a game.
class SlapSound {
  final _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  bool _ready = false;

  Future<void> play() async {
    try {
      if (!_ready) {
        await _player.setPlayerMode(PlayerMode.lowLatency);
        _ready = true;
      }
      await _player.stop();
      await _player.play(AssetSource('sounds/slap.wav'));
    } catch (e) {
      debugPrint('Could not play the slap sound: ${e.runtimeType}');
    }
  }

  Future<void> dispose() => _player.dispose();
}
