import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

/// Real audio playback with background session configuration.
/// Prefers uploaded local files / API media URLs; only then the bundled sample.
class AudioPlaybackService {
  AudioPlaybackService() {
    _initSession();
  }

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  bool _sessionReady = false;
  bool usingRealAudio = false;
  /// True only when the short bundled narration asset is playing.
  bool usingSampleAsset = false;

  static const _sampleAsset = 'assets/audio/sample_narration.wav';

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get playing => _player.playing;

  Future<void> _initSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      _sessionReady = true;
    } catch (_) {
      _sessionReady = false;
    }
  }

  Future<bool> load({
    required Duration duration,
    String? filePath,
    String? mediaUrl,
  }) async {
    if (!_sessionReady) await _initSession();
    usingSampleAsset = false;

    final localPath = filePath;
    final hasLocal = localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync();

    try {
      if (hasLocal) {
        await _player.setFilePath(localPath);
        usingRealAudio = true;
        usingSampleAsset = false;
        return true;
      }
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        await _player.setUrl(mediaUrl);
        usingRealAudio = true;
        usingSampleAsset = false;
        return true;
      }
      await _player.setAsset(_sampleAsset);
      usingRealAudio = true;
      usingSampleAsset = true;
      return true;
    } catch (_) {
      try {
        await _player.setAsset(_sampleAsset);
        usingRealAudio = true;
        usingSampleAsset = true;
        return true;
      } catch (_) {
        usingRealAudio = false;
        usingSampleAsset = false;
        return false;
      }
    }
  }

  /// Back-compat alias used by older call sites.
  Future<bool> loadSample({required Duration duration, String? filePath}) =>
      load(duration: duration, filePath: filePath);

  Future<void> play() async {
    if (!usingRealAudio) return;
    await _player.play();
  }

  Future<void> pause() async {
    if (!usingRealAudio) return;
    await _player.pause();
  }

  Future<void> seek(Duration position) async {
    if (!usingRealAudio) return;
    await _player.seek(position);
  }

  Future<void> setSpeed(double speed) async {
    if (!usingRealAudio) return;
    await _player.setSpeed(speed);
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    usingRealAudio = false;
    usingSampleAsset = false;
  }

  Future<void> dispose() async {
    await _positionSub?.cancel();
    await _stateSub?.cancel();
    await _player.dispose();
  }
}
