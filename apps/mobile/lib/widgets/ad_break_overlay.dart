import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Intro / loading surface before an AdMob rewarded interstitial.
///
/// Google requires a clear reward message and a skip path before the ad starts.
class AdBreakOverlay extends StatelessWidget {
  const AdBreakOverlay({
    super.key,
    required this.placement,
    required this.phase,
    required this.onSkip,
    required this.onWatch,
  });

  final String placement;
  /// intro | loading | showing
  final String phase;
  final VoidCallback onSkip;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final label = switch (placement) {
      'midroll' => 'A quick pause',
      'chapter' => 'Between chapters',
      _ => 'Before you continue',
    };
    final loading = phase == 'loading' || phase == 'showing';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2A24),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sponsored · $label',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            loading
                ? 'Loading a short sponsored message…'
                : 'Watch a short message to support this creator.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            loading
                ? 'Playback resumes automatically when the ad finishes.'
                : 'Completing the ad credits advertising revenue to this title. You can skip and continue without supporting.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          if (loading)
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(6)),
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: Color(0x26FFFFFF),
                color: ListenColors.leaf,
              ),
            )
          else
            Row(
              children: [
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text('Skip'),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ListenColors.leaf,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onWatch,
                  child: const Text('Watch ad'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
