import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/catalogue.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';

String? _coverPathFor(SessionState session, String titleId) {
  for (final draft in session.drafts) {
    if (draft.publishedTitleId != titleId) continue;
    final path = draft.coverImagePath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) return path;
  }
  return null;
}

class TitleCard extends StatelessWidget {
  const TitleCard({super.key, required this.title, required this.onOpen});

  final TitleItem title;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Stack(
            children: [
              Positioned.fill(
                child: Material(
                  color: ListenColors.mist,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onOpen,
                    child: _coverPathFor(session, title.id) != null
                        ? Image.file(
                            File(_coverPathFor(session, title.id)!),
                            fit: BoxFit.cover,
                          )
                        : Image.asset(
                            title.imageAsset,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Image.asset(
                              'assets/images/zambezi.jpg',
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    title.formatLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.9),
                    foregroundColor: ListenColors.ink,
                    minimumSize: const Size(36, 36),
                  ),
                  onPressed: () => session.toggleSave(title.id),
                  icon: Icon(session.isSaved(title.id) ? Icons.bookmark : Icons.bookmark_border, size: 18),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onOpen,
          child: Text(
            title.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2),
          ),
        ),
        const SizedBox(height: 2),
        Text(title.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.6), fontSize: 12)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                title.priceLabelFor(session.currencyCode),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.star, size: 12, color: ListenColors.coral),
            const SizedBox(width: 2),
            Text(title.rating, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}
