import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/catalogue.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../widgets/ad_break_overlay.dart';
import '../widgets/content_notes_sheet.dart';
import '../widgets/title_cover.dart';

Future<void> openPlayerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (_) => const PlayerSheet(),
  );
}

class PlayerSheet extends StatelessWidget {
  const PlayerSheet({super.key});

  static String _format(double seconds) {
    final total = seconds.round().clamp(0, 24 * 3600);
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final title = session.nowPlaying;
    final track = session.nowPlayingTrack;
    if (title == null || track == null) {
      return Container(
        decoration: const BoxDecoration(
          color: ListenColors.sand,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: const Text('Nothing playing right now.'),
      );
    }

    if (title.format == ContentFormat.podcast) {
      return _PodcastPlayer(title: title, track: track);
    }
    return _AudiobookPlayer(title: title, track: track);
  }
}

class _AudiobookPlayer extends StatelessWidget {
  const _AudiobookPlayer({required this.title, required this.track});

  final TitleItem title;
  final SampleAudioTrack track;

  static const _accent = Color(0xFFC4A574);
  static const _deep = Color(0xFF101820);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final tracks = tracksFor(title.id);
    final duration = track.durationSec.toDouble();
    final position = session.playbackPositionSec.clamp(0.0, duration <= 0 ? 1 : duration).toDouble();
    final progress = duration <= 0 ? 0.0 : (position / duration).clamp(0.0, 1.0);
    final trackIndex = tracks.indexWhere((t) => t.id == track.id);
    final chapterLabel = trackIndex >= 0 ? 'Chapter ${trackIndex + 1}' : 'Chapter';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.94,
      minChildSize: 0.55,
      maxChildSize: 0.98,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B1218), Color(0xFF15202B), Color(0xFF1E2F3D)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'NOW PLAYING',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: MediaQuery.sizeOf(context).width * 0.58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 40,
                        offset: const Offset(0, 22),
                      ),
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.12),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: _cover(session, title),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Text(
                title.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Narrated by ${title.author}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.headphones_rounded, color: _accent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chapterLabel,
                            style: TextStyle(
                              color: _accent.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      track.durationLabel,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (title.showsAds) ...[
                const SizedBox(height: 10),
                Text(
                  'Includes short ads that support this creator',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 12),
                ),
              ],
              if (session.adBreakActive) ...[
                const SizedBox(height: 16),
                AdBreakOverlay(
                  placement: session.adBreakPlacement ?? 'preroll',
                  phase: session.adBreakPhase,
                  onSkip: session.skipAdBreak,
                  onWatch: session.watchAdBreak,
                ),
              ],
              const SizedBox(height: 20),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _accent,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
                  thumbColor: Colors.white,
                  overlayColor: _accent.withValues(alpha: 0.18),
                  trackHeight: 3.5,
                ),
                child: Slider(
                  value: position,
                  max: duration <= 0 ? 1 : duration,
                  onChanged: session.adBreakActive ? null : session.seekTo,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      PlayerSheet._format(position),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      '${(progress * 100).round()}%',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.32), fontSize: 11),
                    ),
                    const Spacer(),
                    Text(
                      '-${PlayerSheet._format(duration - position)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 30,
                    color: Colors.white.withValues(alpha: 0.85),
                    onPressed: session.adBreakActive || trackIndex <= 0
                        ? null
                        : () => session.selectTrack(tracks[trackIndex - 1]),
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  IconButton(
                    iconSize: 34,
                    color: Colors.white,
                    onPressed: session.adBreakActive ? null : () => session.skipBy(-15),
                    icon: const Icon(Icons.replay_10_rounded),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: _accent,
                    shape: const CircleBorder(),
                    elevation: 10,
                    shadowColor: _accent.withValues(alpha: 0.45),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: session.adBreakActive ? null : session.togglePlay,
                      child: SizedBox(
                        width: 76,
                        height: 76,
                        child: Icon(
                          session.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: _deep,
                          size: 42,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    iconSize: 34,
                    color: Colors.white,
                    onPressed: session.adBreakActive ? null : () => session.skipBy(30),
                    icon: const Icon(Icons.forward_30_rounded),
                  ),
                  IconButton(
                    iconSize: 30,
                    color: Colors.white.withValues(alpha: 0.85),
                    onPressed: session.adBreakActive ||
                            trackIndex < 0 ||
                            trackIndex >= tracks.length - 1
                        ? null
                        : () => session.selectTrack(tracks[trackIndex + 1]),
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _audiobookPill(
                    label: '${session.playbackSpeed}x',
                    onTap: () {
                      const speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
                      final index = speeds.indexOf(session.playbackSpeed);
                      final next = speeds[(index + 1) % speeds.length];
                      session.setPlaybackSpeed(next);
                    },
                  ),
                  const SizedBox(width: 8),
                  _audiobookPill(
                    label: session.sleepTimerMinutesRemaining == null
                        ? 'Sleep timer'
                        : 'Sleep ${session.sleepTimerMinutesRemaining}m',
                    onTap: () {
                      final current = session.sleepTimerMinutesRemaining;
                      final next = switch (current) {
                        null => 15,
                        15 => 30,
                        30 => 45,
                        45 => 60,
                        _ => null,
                      };
                      session.setSleepTimerMinutes(next);
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Add a note',
                    onPressed: () => openContentNotesSheet(
                      context,
                      titleId: title.id,
                      locationId: track.id,
                      anchor: 'audio',
                      position: position,
                    ),
                    icon: Icon(Icons.bookmark_add_outlined, color: Colors.white.withValues(alpha: 0.75)),
                  ),
                  IconButton(
                    tooltip: session.isDownloaded(title.id) ? 'Remove download' : 'Download for offline',
                    onPressed: () async {
                      if (session.isDownloaded(title.id)) {
                        await session.removeDownload(title.id);
                      } else {
                        await session.downloadForOffline(title);
                      }
                    },
                    icon: Icon(
                      session.isDownloaded(title.id) ? Icons.download_done : Icons.offline_bolt_outlined,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Text(
                    'Chapters',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${tracks.length} ${tracks.length == 1 ? 'chapter' : 'chapters'}',
                    style: TextStyle(
                      color: _accent.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...tracks.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final selected = item.id == track.id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.11)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: selected
                        ? Border.all(color: _accent.withValues(alpha: 0.5))
                        : Border.all(color: Colors.white.withValues(alpha: 0.04)),
                  ),
                  child: ListTile(
                    onTap: () => session.selectTrack(item),
                    leading: CircleAvatar(
                      backgroundColor: selected ? _accent : Colors.white.withValues(alpha: 0.08),
                      foregroundColor: selected ? _deep : Colors.white,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      item.durationLabel,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 12),
                    ),
                    trailing: selected
                        ? Icon(
                            session.playing ? Icons.equalizer : Icons.pause_circle_outline,
                            color: _accent,
                          )
                        : Icon(Icons.play_circle_outline, color: Colors.white.withValues(alpha: 0.35)),
                  ),
                );
              }),
              const SizedBox(height: 8),
              Text(
                'Your place is saved automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _audiobookPill({required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class _PodcastPlayer extends StatelessWidget {
  const _PodcastPlayer({required this.title, required this.track});

  final TitleItem title;
  final SampleAudioTrack track;

  static const _accent = Color(0xFFC45C3E);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final tracks = tracksFor(title.id);
    final duration = track.durationSec.toDouble();
    final position = session.playbackPositionSec.clamp(0.0, duration <= 0 ? 1 : duration).toDouble();
    final progress = duration <= 0 ? 0.0 : (position / duration).clamp(0.0, 1.0);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.94,
      minChildSize: 0.55,
      maxChildSize: 0.98,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A1412), Color(0xFF2A1F1C), Color(0xFF3D2A24)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'NOW PLAYING',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: MediaQuery.sizeOf(context).width * 0.72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 36,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _cover(session, title),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                title.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title.author,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.podcasts_rounded, color: _accent.withValues(alpha: 0.95), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        track.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      track.durationLabel,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (title.showsAds) ...[
                const SizedBox(height: 10),
                Text(
                  'Includes short ads that support this creator',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                ),
              ],
              if (session.adBreakActive) ...[
                const SizedBox(height: 16),
                AdBreakOverlay(
                  placement: session.adBreakPlacement ?? 'preroll',
                  phase: session.adBreakPhase,
                  onSkip: session.skipAdBreak,
                  onWatch: session.watchAdBreak,
                ),
              ],
              const SizedBox(height: 22),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _accent,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                  thumbColor: Colors.white,
                  overlayColor: _accent.withValues(alpha: 0.2),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: position,
                  max: duration <= 0 ? 1 : duration,
                  onChanged: session.adBreakActive ? null : session.seekTo,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      PlayerSheet._format(position),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      '${(progress * 100).round()}%',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                    ),
                    const Spacer(),
                    Text(
                      '-${PlayerSheet._format(duration - position)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 34,
                    color: Colors.white,
                    onPressed: session.adBreakActive ? null : () => session.skipBy(-15),
                    icon: const Icon(Icons.replay_10_rounded),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: _accent,
                    shape: const CircleBorder(),
                    elevation: 8,
                    shadowColor: _accent.withValues(alpha: 0.5),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: session.adBreakActive ? null : session.togglePlay,
                      child: SizedBox(
                        width: 74,
                        height: 74,
                        child: Icon(
                          session.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    iconSize: 34,
                    color: Colors.white,
                    onPressed: session.adBreakActive ? null : () => session.skipBy(30),
                    icon: const Icon(Icons.forward_30_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _pill(
                    label: '${session.playbackSpeed}x',
                    onTap: () {
                      const speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
                      final index = speeds.indexOf(session.playbackSpeed);
                      final next = speeds[(index + 1) % speeds.length];
                      session.setPlaybackSpeed(next);
                    },
                  ),
                  const SizedBox(width: 8),
                  _pill(
                    label: session.sleepTimerMinutesRemaining == null
                        ? 'Sleep timer'
                        : 'Sleep ${session.sleepTimerMinutesRemaining}m',
                    onTap: () {
                      final current = session.sleepTimerMinutesRemaining;
                      final next = switch (current) {
                        null => 15,
                        15 => 30,
                        30 => 45,
                        _ => null,
                      };
                      session.setSleepTimerMinutes(next);
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Add a note',
                    onPressed: () => openContentNotesSheet(
                      context,
                      titleId: title.id,
                      locationId: track.id,
                      anchor: 'audio',
                      position: position,
                    ),
                    icon: Icon(Icons.comment_outlined, color: Colors.white.withValues(alpha: 0.75)),
                  ),
                  IconButton(
                    tooltip: session.isDownloaded(title.id) ? 'Remove download' : 'Download for offline',
                    onPressed: () async {
                      if (session.isDownloaded(title.id)) {
                        await session.removeDownload(title.id);
                      } else {
                        await session.downloadForOffline(title);
                      }
                    },
                    icon: Icon(
                      session.isDownloaded(title.id) ? Icons.download_done : Icons.offline_bolt_outlined,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Episodes',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              ...tracks.map((item) {
                final selected = item.id == track.id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: selected
                        ? Border.all(color: _accent.withValues(alpha: 0.55))
                        : null,
                  ),
                  child: ListTile(
                    onTap: () => session.selectTrack(item),
                    leading: CircleAvatar(
                      backgroundColor: selected ? _accent : Colors.white.withValues(alpha: 0.08),
                      child: Icon(
                        selected && session.playing ? Icons.equalizer : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      item.durationLabel,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                    ),
                    trailing: selected
                        ? Text(
                            'Playing',
                            style: TextStyle(color: _accent.withValues(alpha: 0.95), fontSize: 12),
                          )
                        : null,
                  ),
                );
              }),
              const SizedBox(height: 8),
              Text(
                'Your place is saved automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pill({required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

Widget _cover(SessionState session, TitleItem title) {
  return TitleCover(session: session, title: title);
}

