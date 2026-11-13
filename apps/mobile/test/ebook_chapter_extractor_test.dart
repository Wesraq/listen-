import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:listen_plus/services/ebook_chapter_extractor.dart';

void main() {
  const extractor = EbookChapterExtractor();

  test('splits plain text on Chapter headings', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        'Preface line\n\nChapter 1\nBody one.\n\nChapter 2\nBody two.\n',
      ),
    );
    final chapters = extractor.extractFromBytes(bytes, fileName: 'story.txt');
    expect(chapters.length, 3);
    expect(chapters[0].title, 'Introduction');
    expect(chapters[1].title, 'Chapter 1');
    expect(chapters[1].body, contains('Body one'));
    expect(chapters[2].title, 'Chapter 2');
  });
}
