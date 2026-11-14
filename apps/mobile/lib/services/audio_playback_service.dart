import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Real audio playback with a media (not voice-call) session.
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
  String? lastError;

  static const _sampleAsset = 'assets/audio/sample_narration.wav';

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get playing => _player.playing;

  Future<void> _initSession() async {
    try {
      final session = await AudioSession.instance;
      // Use media playback attributes — `speech()` can route to the call/voice
      // stream on Android and sound like "no audio" at normal media volume.
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );
      await session.setActive(true);
      _sessionReady = true;
    } catch (error) {
      debugPrint('AudioSession init failed: $error');
      _sessionReady = false;
    }
  }

  Future<void> _ensureActiveSession() async {
    if (!_sessionReady) await _initSession();
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}
  }

  Future<bool> load({
    required Duration duration,
    String? filePath,
    String? mediaUrl,
  }) async {
    lastError = null;
    await _ensureActiveSession();
    usingSampleAsset = false;

    final localPath = filePath;
    final hasLocal = localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync();

    final wantsRemote = mediaUrl != null && mediaUrl.isNotEmpty;
    try {
      if (hasLocal) {
        await _player.setFilePath(localPath);
        await _player.setVolume(1.0);
        usingRealAudio = true;
        usingSampleAsset = false;
        return true;
      }
      if (wantsRemote) {
        await _player.setUrl(
          mediaUrl,
          headers: const {
            'Accept': '*/*',
            'Connection': 'keep-alive',
          },
        );
        await _player.setVolume(1.0);
        usingRealAudio = true;
        usingSampleAsset = false;
        return true;
      }
      // Only use the bundled clip when the title has no uploaded media at all.
      await _player.setAsset(_sampleAsset);
      await _player.setVolume(1.0);
      usingRealAudio = true;
      usingSampleAsset = true;
      return true;
    } catch (error, stack) {
      debugPrint('Audio load failed: $error\n$stack');
      lastError = error.toString();
      // Never mask a failed remote/local load with the demo clip — that is how
      // guests were hearing sample audio instead of catalogue content.
      if (hasLocal || wantsRemote) {
        usingRealAudio = false;
        usingSampleAsset = false;
        return false;
      }
    }
    try {
      await _player.setAsset(_sampleAsset);
      await _player.setVolume(1.0);
      usingRealAudio = true;
      usingSampleAsset = true;
      return true;
    } catch (error) {
      lastError = error.toString();
      usingRealAudio = false;
      usingSampleAsset = false;
      return false;
    }
  }

  /// Back-compat alias used by older call sites.
  Future<bool> loadSample({required Duration duration, String? filePath}) =>
      load(duration: duration, filePath: filePath);

  Future<void> play() async {
    if (!usingRealAudio) return;
    await _ensureActiveSession();
    await _player.setVolume(1.0);
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
