import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Light-touch sponsored break — supports the creator without blocking forever.
class AdBreakOverlay extends StatelessWidget {
  const AdBreakOverlay({
    super.key,
    required this.placement,
    required this.elapsedSec,
    required this.skippable,
    required this.onSkip,
    required this.onContinue,
  });

  final String placement;
  final int elapsedSec;
  final bool skippable;
  final VoidCallback onSkip;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final label = switch (placement) {
      'midroll' => 'Quick mid-roll',
      'chapter' => 'Between chapters',
      _ => 'Before you continue',
    };
    final remaining = (15 - elapsedSec).clamp(0, 15);

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
            'A short message that supports this creator.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Prototype inventory · max 3 completed ads / hour · skip after 5s.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (elapsedSec / 15).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              color: ListenColors.leaf,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                skippable ? 'Ready to continue' : 'Skip in ${5 - elapsedSec.clamp(0, 5)}s',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
              ),
              const Spacer(),
              if (!skippable)
                Text(
                  '${remaining}s',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                ),
              if (skippable) ...[
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text('Skip'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ListenColors.leaf,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onContinue,
                  child: const Text('Continue'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
