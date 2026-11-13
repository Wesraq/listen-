import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../data/content_models.dart';

/// Builds reader chapters from an uploaded ebook file.
///
/// Supports:
/// - Plain / sample text (`.txt`, `.epub.txt`) split on Chapter headings
/// - Real EPUB packages (ZIP) using spine / HTML documents when present
/// - PDF files via lightweight text-stream extraction (prototype)
class EbookChapterExtractor {
  const EbookChapterExtractor();

  static const supportedExtensions = <String>[
    'epub',
    'pdf',
    'txt',
    'html',
    'htm',
    'md',
  ];

  Future<List<ContentChapter>> extractFromPath(String path) async {
    final file = File(path);
    if (!await file.exists()) return const [];
    final bytes = await file.readAsBytes();
    final name = path.split(Platform.pathSeparator).last.toLowerCase();
    return extractFromBytes(bytes, fileName: name);
  }

  List<ContentChapter> extractFromBytes(
    Uint8List bytes, {
    required String fileName,
  }) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.epub') && !lower.endsWith('.epub.txt')) {
      final fromEpub = _tryEpub(bytes);
      if (fromEpub.isNotEmpty) return fromEpub;
    }
    if (lower.endsWith('.pdf')) {
      final fromPdf = _tryPdf(bytes, fileName: fileName);
      if (fromPdf.isNotEmpty) return fromPdf;
    }

    // Sample EPUB stand-in and plain text uploads.
    final text = _decodeText(bytes);
    final fromText = _sanitizeChapters(_fromPlainText(text));
    if (fromText.isNotEmpty) return fromText;

    final fallbackBody = _cleanExtractedProse(text);
    return [
      ContentChapter(
        id: _id(0),
        title: 'Chapter 1',
        body: fallbackBody.isEmpty ? 'Imported ebook body.' : fallbackBody,
        sortOrder: 0,
      ),
    ];
  }

  /// Best-effort PDF text extraction for the prototype reader.
  /// Scanned/image-only or path-polluted PDFs fall back to a placeholder
  /// so the native PDF viewer can open the real pages instead.
  List<ContentChapter> _tryPdf(Uint8List bytes, {required String fileName}) {
    try {
      final raw = latin1.decode(bytes, allowInvalid: true);
      final buffer = StringBuffer();
      // Literal strings: (Hello World) Tj / TJ
      final literals = RegExp(r'\((?:\\.|[^\\)])*\)\s*T[jJ]');
      for (final match in literals.allMatches(raw)) {
        final token = match.group(0)!;
        final inner = RegExp(r'^\((.*)\)\s*T[jJ]$', dotAll: true).firstMatch(token);
        if (inner == null) continue;
        final piece = _unescapePdfString(inner.group(1) ?? '');
        if (_isJunkFragment(piece)) continue;
        buffer.write(piece);
        buffer.write(' ');
      }
      // Hex strings: <48656C6C6F> Tj
      final hexes = RegExp(r'<([0-9A-Fa-f\s]+)>\s*T[jJ]');
      for (final match in hexes.allMatches(raw)) {
        final hex = (match.group(1) ?? '').replaceAll(RegExp(r'\s+'), '');
        if (hex.length < 2 || hex.length.isOdd) continue;
        final out = StringBuffer();
        for (var i = 0; i + 1 < hex.length; i += 2) {
          final code = int.tryParse(hex.substring(i, i + 2), radix: 16);
          if (code == null) continue;
          if (code >= 32 && code < 127) {
            out.writeCharCode(code);
          } else if (code == 10 || code == 13) {
            out.write('\n');
          }
        }
        final piece = out.toString();
        if (_isJunkFragment(piece)) continue;
        buffer.write(piece);
        buffer.write(' ');
      }

      final cleaned = _cleanExtractedProse(buffer.toString());
      final label = fileName.split(Platform.pathSeparator).last;
      if (!_hasEnoughProse(cleaned)) {
        return [_pdfViewerPlaceholder(label)];
      }

      // Noisy PDF streams often invent false "Chapter N" splits — keep one clean body
      // unless headings are clearly human titles.
      final chapters = _sanitizeChapters(_fromPlainText(cleaned));
      final usable = chapters
          .where((c) => _hasEnoughProse(c.body) && !_isJunkFragment(c.title))
          .toList();
      if (usable.length >= 2) {
        return [
          for (var i = 0; i < usable.length; i++)
            usable[i].copyWith(
              title: _humanChapterTitle(usable[i].title, i),
              sortOrder: i,
            ),
        ];
      }
      if (usable.length == 1) {
        return [
          usable.first.copyWith(title: _humanChapterTitle(usable.first.title, 0), sortOrder: 0),
        ];
      }
      return [
        ContentChapter(
          id: _id(0),
          title: 'Imported PDF',
          body: cleaned,
          sortOrder: 0,
        ),
      ];
    } catch (_) {
      return const [];
    }
  }

  ContentChapter _pdfViewerPlaceholder(String label) {
    return ContentChapter(
      id: _id(0),
      title: 'Imported PDF',
      body:
          '“$label” was uploaded. This PDF looks image-based or encrypted, so Listen+ could not extract readable chapters yet. Re-export as text-based PDF or EPUB for full chapter detection.',
      sortOrder: 0,
    );
  }

  bool _isJunkFragment(String value) {
    final t = value.trim();
    if (t.isEmpty) return true;
    final lower = t.toLowerCase();
    if (lower.contains('/app/') ||
        lower.contains('/public/') ||
        lower.contains('/task/') ||
        lower.contains('/var/') ||
        lower.contains('/tmp/')) {
      return true;
    }
    if (RegExp(r'https?://', caseSensitive: false).hasMatch(t)) return true;
    if (RegExp(r'[/\\].+\.pdf\b', caseSensitive: false).hasMatch(t)) return true;
    if (RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      caseSensitive: false,
    ).hasMatch(t)) {
      return true;
    }
    final letters = RegExp(r'[A-Za-z]').allMatches(t).length;
    if (t.length >= 24 && letters < 6) return true;
    return false;
  }

  String _cleanExtractedProse(String raw) {
    var text = raw;
    text = text.replaceAll(
      RegExp(r'/app/[^\s]+', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(
      RegExp(r'(?:[A-Za-z]:)?(?:/[\w.-]+){2,}\.(?:pdf|epub|png|jpg)\b', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(
      RegExp(
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
        caseSensitive: false,
      ),
      ' ',
    );
    text = text.replaceAll(RegExp(r'https?://\S+', caseSensitive: false), ' ');
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim())
        .where((line) => line.isNotEmpty && !_isJunkFragment(line));
    return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  bool _hasEnoughProse(String text) {
    final letters = RegExp(r'[A-Za-z]').allMatches(text).length;
    return letters >= 48;
  }

  String _humanChapterTitle(String raw, int index) {
    final cleaned = raw
        .replaceAll(RegExp(r'^chapter\s+\d+\s*[:.\-]?\s*', caseSensitive: false), '')
        .trim();
    if (cleaned.isEmpty || _isJunkFragment(cleaned) || cleaned.length > 80) {
      return 'Chapter ${index + 1}';
    }
    return cleaned;
  }

  List<ContentChapter> _sanitizeChapters(List<ContentChapter> input) {
    final out = <ContentChapter>[];
    for (final chapter in input) {
      final title = _cleanExtractedProse(chapter.title);
      final body = _cleanExtractedProse(chapter.body);
      if (!_hasEnoughProse(body) && _isJunkFragment(title)) continue;
      if (body.isEmpty && title.isEmpty) continue;
      out.add(
        ContentChapter(
          id: chapter.id,
          title: title.isEmpty ? chapter.title : title,
          body: body.isEmpty ? chapter.body : body,
          sortOrder: out.length,
        ),
      );
    }
    return out;
  }

  String _unescapePdfString(String value) {
    return value
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\n')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\\', r'\');
  }

  List<ContentChapter> _tryEpub(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final byName = <String, ArchiveFile>{
        for (final file in archive.files)
          if (file.isFile) file.name.replaceAll('\\', '/'): file,
      };

      // Prefer reading order from package.opf spine when present.
      final ordered = _epubSpineHtmlFiles(byName);
      final htmlFiles = ordered.isNotEmpty
          ? ordered
          : (byName.values
                .where((f) {
                  final name = f.name.toLowerCase();
                  return name.endsWith('.xhtml') ||
                      name.endsWith('.html') ||
                      name.endsWith('.htm');
                })
                .where((f) {
                  final name = f.name.toLowerCase();
                  return !name.contains('nav') &&
                      !name.contains('toc') &&
                      !name.contains('cover') &&
                      !name.contains('ncx');
                })
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name)));

      if (htmlFiles.isEmpty) return const [];

      final chapters = <ContentChapter>[];
      for (var i = 0; i < htmlFiles.length; i++) {
        final file = htmlFiles[i];
        final raw = utf8.decode(file.content, allowMalformed: true);
        final plain = _stripHtml(raw).trim();
        if (plain.isEmpty) continue;
        final title = _titleFromHtml(raw) ??
            _titleFromPath(file.name) ??
            'Chapter ${chapters.length + 1}';
        chapters.add(
          ContentChapter(
            id: _id(chapters.length),
            title: title,
            body: plain,
            sortOrder: chapters.length,
          ),
        );
      }
      return _sanitizeChapters(chapters);
    } catch (_) {
      return const [];
    }
  }

  /// Resolve HTML/XHTML documents in OPF spine order when possible.
  List<ArchiveFile> _epubSpineHtmlFiles(Map<String, ArchiveFile> byName) {
    try {
      ArchiveFile? container;
      for (final entry in byName.entries) {
        if (entry.key.toLowerCase().endsWith('meta-inf/container.xml')) {
          container = entry.value;
          break;
        }
      }
      if (container == null) return const [];
      final containerXml = utf8.decode(container.content, allowMalformed: true);
      final rootMatch = RegExp(
        r'full-path\s*=\s*"([^"]+)"',
        caseSensitive: false,
      ).firstMatch(containerXml);
      if (rootMatch == null) return const [];
      final opfPath = rootMatch.group(1)!.replaceAll('\\', '/');
      ArchiveFile? opfFile = byName[opfPath];
      if (opfFile == null) {
        for (final entry in byName.entries) {
          if (entry.key.toLowerCase().endsWith(opfPath.toLowerCase())) {
            opfFile = entry.value;
            break;
          }
        }
      }
      if (opfFile == null) return const [];
      final opfXml = utf8.decode(opfFile.content, allowMalformed: true);
      final opfDir = opfPath.contains('/')
          ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
          : '';

      final idToHref = <String, String>{};
      for (final match in RegExp(
        r'<item\b[^>]*>',
        caseSensitive: false,
      ).allMatches(opfXml)) {
        final tag = match.group(0)!;
        final id = RegExp(r'\bid\s*=\s*"([^"]+)"', caseSensitive: false)
            .firstMatch(tag)
            ?.group(1);
        final href = RegExp(r'\bhref\s*=\s*"([^"]+)"', caseSensitive: false)
            .firstMatch(tag)
            ?.group(1);
        if (id == null || href == null) continue;
        idToHref[id] = href.split('#').first;
      }

      final spineIds = RegExp(
        r'<itemref\b[^>]*\bidref\s*=\s*"([^"]+)"',
        caseSensitive: false,
      ).allMatches(opfXml).map((m) => m.group(1)!).toList();
      if (spineIds.isEmpty) return const [];

      final files = <ArchiveFile>[];
      for (final id in spineIds) {
        final href = idToHref[id];
        if (href == null) continue;
        final lower = href.toLowerCase();
        if (!(lower.endsWith('.xhtml') ||
            lower.endsWith('.html') ||
            lower.endsWith('.htm'))) {
          continue;
        }
        if (lower.contains('nav') ||
            lower.contains('toc') ||
            lower.contains('cover') ||
            lower.contains('ncx')) {
          continue;
        }
        final resolved = _resolveEpubPath(opfDir, href);
        ArchiveFile? file = byName[resolved];
        if (file == null) {
          for (final entry in byName.entries) {
            final key = entry.key.toLowerCase();
            if (key == href.toLowerCase() || key.endsWith('/${href.toLowerCase()}')) {
              file = entry.value;
              break;
            }
          }
        }
        if (file != null) files.add(file);
      }
      return files;
    } catch (_) {
      return const [];
    }
  }

  String _resolveEpubPath(String baseDir, String href) {
    final cleaned = href.replaceAll('\\', '/');
    if (cleaned.startsWith('/')) return cleaned.substring(1);
    final joined = '$baseDir$cleaned';
    final parts = <String>[];
    for (final part in joined.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(part);
    }
    return parts.join('/');
  }

  List<ContentChapter> _fromPlainText(String text) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return const [];

    final chapterHeader = RegExp(
      r'^(chapter\s+\d+\b.*)$',
      multiLine: true,
      caseSensitive: false,
    );
    final matches = chapterHeader.allMatches(normalized).toList();
    if (matches.isEmpty) {
      // Markdown-style headings as a fallback.
      final md = RegExp(r'^#{1,3}\s+(.+)$', multiLine: true);
      final mdMatches = md.allMatches(normalized).toList();
      if (mdMatches.length >= 2) {
        final chapters = <ContentChapter>[];
        for (var i = 0; i < mdMatches.length; i++) {
          final start = mdMatches[i].end;
          final end = i + 1 < mdMatches.length
              ? mdMatches[i + 1].start
              : normalized.length;
          final title = mdMatches[i].group(1)?.trim() ?? 'Chapter ${i + 1}';
          final body = normalized.substring(start, end).trim();
          if (body.isEmpty && title.isEmpty) continue;
          chapters.add(
            ContentChapter(
              id: _id(chapters.length),
              title: title,
              body: body,
              sortOrder: chapters.length,
            ),
          );
        }
        return chapters;
      }
      return [
        ContentChapter(
          id: _id(0),
          title: 'Chapter 1',
          body: normalized,
          sortOrder: 0,
        ),
      ];
    }

    final chapters = <ContentChapter>[];
    // Optional preface before the first Chapter heading.
    final preface = normalized.substring(0, matches.first.start).trim();
    if (preface.isNotEmpty) {
      chapters.add(
        ContentChapter(
          id: _id(0),
          title: 'Introduction',
          body: preface,
          sortOrder: 0,
        ),
      );
    }

    for (var i = 0; i < matches.length; i++) {
      final title = matches[i].group(1)?.trim() ?? 'Chapter ${i + 1}';
      final start = matches[i].end;
      final end =
          i + 1 < matches.length ? matches[i + 1].start : normalized.length;
      final body = normalized.substring(start, end).trim();
      chapters.add(
        ContentChapter(
          id: _id(chapters.length),
          title: title,
          body: body.isEmpty ? title : body,
          sortOrder: chapters.length,
        ),
      );
    }
    return chapters;
  }

  String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  String _stripHtml(String html) {
    var text = html
        .replaceAll(
          RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    return text.trim();
  }

  String? _titleFromHtml(String html) {
    final h = RegExp(
      r'<(h1|h2|title)[^>]*>(.*?)</\1>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    if (h == null) return null;
    final title = _stripHtml(h.group(2) ?? '').trim();
    return title.isEmpty ? null : title;
  }

  String? _titleFromPath(String path) {
    final base = path.split('/').last;
    final withoutExt = base.replaceAll(RegExp(r'\.(xhtml|html|htm)$', caseSensitive: false), '');
    final cleaned = withoutExt
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty || RegExp(r'^chapter\s*\d+$', caseSensitive: false).hasMatch(cleaned)) {
      return cleaned.isEmpty ? null : cleaned;
    }
    return cleaned;
  }

  String _id(int index) =>
      'ch-${DateTime.now().millisecondsSinceEpoch}-$index';
}
