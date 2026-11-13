import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PageIntro extends StatelessWidget {
  const PageIntro({super.key, required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR WORLD OF STORIES',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: ListenColors.coral,
            ),
          ),
          const SizedBox(height: 6),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(text, style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.65), height: 1.4)),
        ],
      ),
    );
  }
}
