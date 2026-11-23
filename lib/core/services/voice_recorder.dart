import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

/// A finished voice note.
class VoiceNote {
  const VoiceNote({required this.bytes, required this.durationMs});
  final Uint8List bytes;
  final int       durationMs;
}

/// Records a voice note to a temporary file and hands back its bytes. The file is deleted as soon
/// as it has been read (or the recording is cancelled), so no readable copy stays on the phone.
class VoiceRecorder {
  final _recorder = AudioRecorder();
  String?   _path;
  DateTime? _startedAt;

  bool get isRecording => _path != null;

  /// Asks for the microphone if needed. False when the person said no.
  Future<bool> start() async {
    if (isRecording) return true;
    if (!await _recorder.hasPermission()) return false;
    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/${const Uuid().v4()}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: path);
    _path = path;
    _startedAt = DateTime.now();
    return true;
  }

  /// Stops and returns the note, or null if nothing was recording.
  Future<VoiceNote?> stop() async {
    final path = _path;
    final started = _startedAt;
    if (path == null || started == null) return null;
    _path = null;
    _startedAt = null;
    try {
      await _recorder.stop();
      final file = File(path);
      final bytes = await file.readAsBytes();
      return VoiceNote(bytes: bytes, durationMs: DateTime.now().difference(started).inMilliseconds);
    } catch (e) {
      debugPrint('Could not finish the recording: ${e.runtimeType}');
      return null;
    } finally {
      unawaited(_delete(path));
    }
  }

  /// Throws the recording away.
  Future<void> cancel() async {
    final path = _path;
    _path = null;
    _startedAt = null;
    if (path == null) return;
    try {
      await _recorder.stop();
    } catch (_) {}
    await _delete(path);
  }

  Future<void> _delete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}
