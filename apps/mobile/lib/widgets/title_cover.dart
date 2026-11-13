import 'dart:io';

import 'package:flutter/material.dart';

import '../data/catalogue.dart';
import '../data/content_models.dart';
import '../state/session.dart';

/// Resolves cover art: local file → durable coverUrl → bundled sample.
class TitleCover extends StatelessWidget {
  const TitleCover({
    super.key,
    required this.session,
    required this.title,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final SessionState session;
  final TitleItem title;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveTitleCover(session, title);
    if (resolved.filePath != null) {
      return Image.file(
        File(resolved.filePath!),
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, _, _) => _assetFallback(),
      );
    }
    if (resolved.networkUrl != null && resolved.networkUrl!.isNotEmpty) {
      return Image.network(
        resolved.networkUrl!,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, _, _) => _assetFallback(),
      );
    }
    return _assetFallback();
  }

  Widget _assetFallback() {
    return Image.asset(
      title.imageAsset,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, _, _) => Image.asset(
        'assets/images/zambezi.jpg',
        fit: fit,
        width: width,
        height: height,
      ),
    );
  }
}

class ResolvedCover {
  const ResolvedCover({this.filePath, this.networkUrl});
  final String? filePath;
  final String? networkUrl;
}

ResolvedCover resolveTitleCover(SessionState session, TitleItem title) {
  CreatorDraft? draft;
  for (final item in session.drafts) {
    if (item.publishedTitleId == title.id || item.inferredPublishedTitleId == title.id) {
      draft = item;
      break;
    }
  }

  final local = draft?.coverImagePath;
  if (local != null && local.isNotEmpty && File(local).existsSync()) {
    return ResolvedCover(filePath: local);
  }

  final coverUrl = title.coverUrl?.trim();
  if (coverUrl != null && coverUrl.isNotEmpty) {
    return ResolvedCover(networkUrl: coverUrl);
  }

  final coverId = (title.coverImageId ?? draft?.coverImageId)?.trim();
  if (coverId != null && coverId.isNotEmpty) {
    return ResolvedCover(networkUrl: session.mediaAbsoluteUrl('/v1/media/$coverId'));
  }

  return const ResolvedCover();
}
