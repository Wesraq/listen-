import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/catalogue.dart';

/// Caches ebook chapter bodies and marks audio titles for offline playback.
class OfflineCacheService {
  Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/listen_offline');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> cacheEbook(TitleItem title, List<SampleChapter> chapters) async {
    final root = await _root();
    final file = File('${root.path}/${title.id}.epub.json');
    final payload = {
      'titleId': title.id,
      'name': title.name,
      'format': 'epub',
      'cachedAt': DateTime.now().toIso8601String(),
      'chapters': chapters
          .map((c) => {'id': c.id, 'title': c.title, 'body': c.body})
          .toList(),
    };
    await file.writeAsString(jsonEncode(payload));
    return file.path;
  }

  Future<String> cacheAudioMarker(TitleItem title) async {
    final root = await _root();
    final file = File('${root.path}/${title.id}.audio.json');
    await file.writeAsString(
      jsonEncode({
        'titleId': title.id,
        'name': title.name,
        'format': title.formatLabel,
        'asset': 'assets/audio/sample_narration.wav',
        'cachedAt': DateTime.now().toIso8601String(),
      }),
    );
    return file.path;
  }

  Future<bool> isCached(String titleId) async {
    final root = await _root();
    return File('${root.path}/$titleId.epub.json').existsSync() ||
        File('${root.path}/$titleId.audio.json').existsSync();
  }

  Future<void> remove(String titleId) async {
    final root = await _root();
    for (final name in ['$titleId.epub.json', '$titleId.audio.json']) {
      final file = File('${root.path}/$name');
      if (await file.exists()) await file.delete();
    }
  }
}
