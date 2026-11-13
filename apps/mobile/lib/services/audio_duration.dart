import 'package:just_audio/just_audio.dart';

/// Reads duration from a local audio file. Returns seconds, or null on failure.
Future<int?> probeAudioDurationSec(String path) async {
  if (path.trim().isEmpty) return null;
  final player = AudioPlayer();
  try {
    final duration = await player.setFilePath(path);
    final seconds = duration?.inSeconds ?? player.duration?.inSeconds;
    if (seconds == null || seconds <= 0) return null;
    return seconds;
  } catch (_) {
    return null;
  } finally {
    await player.dispose();
  }
}

String formatDurationLabel(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final m = safe ~/ 60;
  final s = safe % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
