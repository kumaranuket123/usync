import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../domain/repositories/i_slap_repository.dart';

/// Plays the kiss and the warm hug sound of the slap fight. A fresh start each time, so repeated
/// ones each make a sound. Never throws: a game without sound is still a game.
class AffectionSound {
  final _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  bool _ready = false;

  static String _asset(Affection a) => switch (a) {
        Affection.kiss => 'sounds/kiss.wav',
        Affection.hug  => 'sounds/hug.wav',
      };

  Future<void> play(Affection affection) async {
    try {
      if (!_ready) {
        await _player.setPlayerMode(PlayerMode.lowLatency);
        _ready = true;
      }
      await _player.stop();
      await _player.play(AssetSource(_asset(affection)));
    } catch (e) {
      debugPrint('Could not play the ${affection.name} sound: ${e.runtimeType}');
    }
  }

  Future<void> dispose() => _player.dispose();
}
