import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';

import '../data/catalogue.dart';
import '../data/session_store.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../widgets/ad_break_overlay.dart';
import '../widgets/content_notes_sheet.dart';
import 'creator_profile_screen.dart';
import 'player_sheet.dart';

Widget _titleCover(SessionState session, TitleItem title) {
  for (final draft in session.drafts) {
    if (draft.publishedTitleId != title.id) continue;
    final path = draft.coverImagePath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
  }
  return Image.asset(
    title.imageAsset,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => Image.asset('assets/images/zambezi.jpg', fit: BoxFit.cover),
  );
}

Future<void> openTitleFlow(BuildContext context, TitleItem title) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: ListenColors.sand,
    builder: (_) => TitleFlowSheet(title: title),
  );
}

void openContinueExperience(BuildContext context, TitleItem title) {
  final session = context.read<SessionState>();
  if (title.isAudio) {
    session.play(title);
    openPlayerSheet(context);
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReaderScreen(title: title)),
    );
  }
}

class TitleFlowSheet extends StatefulWidget {
  const TitleFlowSheet({super.key, required this.title});

  final TitleItem title;

  @override
  State<TitleFlowSheet> createState() => _TitleFlowSheetState();
}

class _TitleFlowSheetState extends State<TitleFlowSheet> {
  CheckoutState? checkout;
  String payment = 'Mobile money';

  TitleItem get title => widget.title;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final owned = session.isOwned(title.id) || title.isFree;
    final hasProgress = session.progressFor(title.id) != null;
    final primaryLabel = !owned
        ? 'Buy ${title.formatLabel.toLowerCase()}'
        : title.showsAds
            ? (hasProgress
                ? (title.isAudio ? 'Continue with ads' : 'Continue reading')
                : (title.isAudio ? 'Listen free with ads' : 'Read free with ads'))
            : hasProgress
                ? (title.isAudio ? 'Continue listening' : 'Continue reading')
                : (title.isAudio ? 'Listen now' : 'Read now');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            if (checkout == null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: _titleCover(session, title),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${title.category} · ${title.formatLabel}',
                style: const TextStyle(color: ListenColors.coral, fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(title.name, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  openCreatorProfile(context, title.author);
                },
                child: Text(
                  'By ${title.author}',
                  style: const TextStyle(
                    color: ListenColors.leaf,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: ListenColors.leaf,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('★ ${title.rating} · English · ${title.length}'),
              if (hasProgress) ...[
                const SizedBox(height: 8),
                Text(
                  session.continueSubtitle(title),
                  style: const TextStyle(color: ListenColors.leaf, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 12),
              Text(title.description, style: const TextStyle(height: 1.45)),
              const SizedBox(height: 12),
              Text(title.priceLabel, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                title.showsAds
                    ? 'Free with ads — short sponsorships help support this creator.'
                    : title.resolvedMonetisationMode == 'subscription'
                        ? 'Included with your Listen+ subscription.'
                        : title.isFree
                            ? 'Free on Listen+.'
                            : 'Buy once and keep it in your library.',
                style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.5), fontSize: 12),
              ),
              const SizedBox(height: 20),
              if (owned && title.isDualFormat) ...[
                FilledButton(
                  onPressed: () => _openOwnedExperience(session, mode: 'read'),
                  child: Text(hasProgress ? 'Continue reading' : 'Read now'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => _openOwnedExperience(session, mode: 'listen'),
                  child: Text(hasProgress ? 'Continue listening' : 'Listen now'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => _openOwnedExperience(session, mode: 'read', sample: true),
                  child: const Text('Read sample'),
                ),
                TextButton(
                  onPressed: () => _openOwnedExperience(session, mode: 'listen', sample: true),
                  child: const Text('Listen to sample'),
                ),
              ] else ...[
                FilledButton(
                  onPressed: () {
                    if (owned) {
                      _openOwnedExperience(session);
                    } else {
                      setState(() => checkout = CheckoutState.review);
                    }
                  },
                  child: Text(primaryLabel),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => _openOwnedExperience(session, sample: true),
                  child: Text(title.isAudio ? 'Listen to sample' : 'Read sample'),
                ),
              ],
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => session.toggleSave(title.id),
                icon: Icon(session.isSaved(title.id) ? Icons.bookmark : Icons.bookmark_border),
                label: Text(session.isSaved(title.id) ? 'Saved' : 'Save for later'),
              ),
              if (owned)
                TextButton.icon(
                  onPressed: () async {
                    if (session.isDownloaded(title.id)) {
                      await session.removeDownload(title.id);
                    } else {
                      await session.downloadForOffline(title);
                    }
                  },
                  icon: Icon(
                    session.isDownloaded(title.id) ? Icons.download_done : Icons.download_outlined,
                  ),
                  label: Text(
                    session.isDownloaded(title.id)
                        ? 'Downloaded · tap to remove'
                        : (title.isAudio ? 'Download for offline listening' : 'Download for offline reading'),
                  ),
                ),
            ] else ...[
              Text(_checkoutTitle(), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Confirm payment to add this title to your library.',
                style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(title.imageAsset, width: 48, height: 64, fit: BoxFit.cover),
                ),
                title: Text(title.name),
                subtitle: Text('${title.formatLabel} · ${title.author}'),
                trailing: Text(title.priceLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              if (checkout == CheckoutState.review) ...[
                DropdownButtonFormField<String>(
                  initialValue: payment,
                  decoration: const InputDecoration(labelText: 'Payment method', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Mobile money', child: Text('Mobile money')),
                    DropdownMenuItem(value: 'Debit or credit card', child: Text('Debit or credit card')),
                  ],
                  onChanged: (value) => setState(() => payment = value ?? payment),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Total · ${title.currency}'),
                    const Spacer(),
                    Text(title.priceLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() => checkout = CheckoutState.pending),
                  child: const Text('Continue to payment'),
                ),
              ] else if (checkout == CheckoutState.pending) ...[
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.hourglass_top),
                  title: Text('Confirming payment'),
                  subtitle: Text('Almost there — your library updates when payment clears.'),
                ),
                FilledButton(
                  onPressed: () async {
                    await session.grantOwnership(title.id);
                    if (!mounted) return;
                    setState(() => checkout = CheckoutState.success);
                  },
                  child: const Text('Confirm payment'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => setState(() => checkout = CheckoutState.failed),
                  child: const Text('Payment didn’t go through'),
                ),
              ] else if (checkout == CheckoutState.failed) ...[
                const Text('We couldn’t complete this payment. Nothing was charged, and your library is unchanged.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() => checkout = CheckoutState.review),
                  child: const Text('Try again'),
                ),
              ] else ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle, color: ListenColors.leaf),
                  title: Text('${title.name} is now in your library.'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    openContinueExperience(context, title);
                  },
                  child: Text(title.isAudio ? 'Start listening' : 'Start reading'),
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  String _checkoutTitle() => switch (checkout) {
        CheckoutState.review => 'Review your purchase',
        CheckoutState.pending => 'Confirming payment',
        CheckoutState.failed => 'Payment unsuccessful',
        CheckoutState.success => 'You’re all set',
        null => title.name,
      };

  Future<void> _openOwnedExperience(
    SessionState session, {
    bool sample = false,
    String? mode,
  }) async {
    Navigator.of(context).pop();
    await session.refreshTitleParts(title.id);
    if (!mounted) return;
    final listen = mode == 'listen' || (mode == null && title.isAudio && !title.isDualFormat);
    if (listen) {
      final tracks = tracksFor(title.id);
      await session.play(
        title,
        trackId: sample && tracks.isNotEmpty ? tracks.first.id : null,
      );
      if (!mounted) return;
      openPlayerSheet(context);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(title: title, sampleOnly: sample),
        ),
      );
    }
  }
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.title,
    this.sampleOnly = false,
  });

  final TitleItem title;
  final bool sampleOnly;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  List<SampleChapter> chapters = const [];
  late final ScrollController scrollController = ScrollController()..addListener(_onScroll);
  int chapterIndex = 0;
  double? _pendingScrollFraction;
  bool restoringScroll = false;
  bool _loading = true;
  DateTime _openedAt = DateTime.now();
  int _readingMinutesReported = 0;
  PdfControllerPinch? _pdfController;
  bool _pdfMode = false;
  String? _pdfError;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChapters());
  }

  bool _looksLikePathPollution(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('/app/') ||
        lower.contains('/public/task/') ||
        lower.contains('/var/') ||
        lower.contains('/tmp/')) {
      return true;
    }
    final pdfPaths = RegExp(r'[/\\].+\.pdf\b').allMatches(lower).length;
    final uuids = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    ).allMatches(lower).length;
    return pdfPaths >= 1 || uuids >= 2;
  }

  bool _hasReadableChapters(List<SampleChapter> next) {
    if (next.isEmpty) return false;
    final joined = next.map((c) => '${c.title}\n${c.body}').join('\n');
    final lower = joined.toLowerCase();
    // Image-based PDF placeholder → native PDF viewer.
    if (lower.contains('image-based or encrypted')) return false;
    // Broken extracts that stored server paths as "chapters".
    if (_looksLikePathPollution(joined)) return false;
    final letters = RegExp(r'[A-Za-z]').allMatches(joined).length;
    return letters >= 48;
  }

  Future<void> _loadChapters() async {
    final session = context.read<SessionState>();
    await session.refreshTitleParts(widget.title.id);
    if (!mounted) return;

    final next = chaptersFor(widget.title.id);
    // Prefer EPUB/text chapter reader (font, theme, bookmarks, prev/next).
    if (_hasReadableChapters(next)) {
      final saved = session.progressFor(widget.title.id);
      final savedIndex = next.indexWhere((chapter) => chapter.id == saved?.locationId);
      setState(() {
        _pdfMode = false;
        chapters = next;
        chapterIndex = savedIndex >= 0 ? savedIndex : 0;
        _pendingScrollFraction = saved?.position ?? 0;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final fraction = _pendingScrollFraction ?? 0;
        _pendingScrollFraction = null;
        _restoreScroll(fraction);
      });
      return;
    }

    final pdfPath = await session.resolveEbookPdfFile(widget.title);
    if (!mounted) return;
    if (pdfPath != null && File(pdfPath).existsSync()) {
      try {
        final controller = PdfControllerPinch(
          document: PdfDocument.openFile(pdfPath),
        );
        setState(() {
          _pdfMode = true;
          _pdfController = controller;
          _pdfError = null;
          chapters = next;
          _loading = false;
        });
        return;
      } catch (error) {
        _pdfController?.dispose();
        _pdfController = null;
        setState(() {
          _pdfMode = false;
          _pdfError = 'Could not open PDF viewer.';
        });
      }
    }

    final saved = session.progressFor(widget.title.id);
    final savedIndex = next.indexWhere((chapter) => chapter.id == saved?.locationId);
    setState(() {
      chapters = next;
      chapterIndex = savedIndex >= 0 ? savedIndex : 0;
      _pendingScrollFraction = saved?.position ?? 0;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fraction = _pendingScrollFraction ?? 0;
      _pendingScrollFraction = null;
      _restoreScroll(fraction);
    });
  }

  @override
  void dispose() {
    if (!_pdfMode) {
      _persistProgress();
    }
    _flushReadingMinutes();
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    _pdfController?.dispose();
    super.dispose();
  }

  void _flushReadingMinutes() {
    if (widget.sampleOnly) return;
    final elapsed = DateTime.now().difference(_openedAt).inMinutes;
    final grant = elapsed - _readingMinutesReported;
    if (grant < 1) return;
    _readingMinutesReported = elapsed;
    context.read<SessionState>().reportQualifiedReading(widget.title, minutes: grant);
  }

  SampleChapter get chapter => chapters[chapterIndex.clamp(0, chapters.isEmpty ? 0 : chapters.length - 1)];

  void _onScroll() {
    if (_loading || chapters.isEmpty || restoringScroll || !scrollController.hasClients) return;
    _persistProgress(persist: false);
  }

  void _persistProgress({bool persist = true}) {
    if (_loading || chapters.isEmpty || !scrollController.hasClients) return;
    final max = scrollController.position.maxScrollExtent;
    final fraction = max <= 0 ? 0.0 : (scrollController.offset / max).clamp(0.0, 1.0);
    context.read<SessionState>().updateReadingProgress(
          titleId: widget.title.id,
          chapterId: chapter.id,
          scrollFraction: fraction,
          persist: persist,
        );
  }

  Future<void> _restoreScroll(double fraction) async {
    if (!scrollController.hasClients) return;
    restoringScroll = true;
    final max = scrollController.position.maxScrollExtent;
    await scrollController.animateTo(
      (fraction.clamp(0, 1) * max),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    restoringScroll = false;
  }

  Future<void> _goToChapter(int index) async {
    _persistProgress();
    _flushReadingMinutes();
    final session = context.read<SessionState>();
    // Between-chapter ad at most once per title session for free-with-ads ebooks.
    if (!widget.sampleOnly &&
        widget.title.showsAds &&
        index > chapterIndex &&
        !session.adBreakActive) {
      await session.maybeShowChapterAd(widget.title);
    }
    setState(() => chapterIndex = index);
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!scrollController.hasClients) return;
    restoringScroll = true;
    await scrollController.animateTo(0, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    restoringScroll = false;
    _persistProgress();
  }

  Future<void> _openBookmarks(BuildContext context, SessionState session) async {
    final tokens = session.progressFor(widget.title.id)?.bookmarks ?? const <String>[];
    final selected = await showModalBottomSheet<({int index, double? fraction})>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('Bookmarks', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (tokens.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No bookmarks yet. Tap the bookmark icon to save your place in a chapter.'),
                )
              else
                ...tokens.map((token) {
                  final chapterId = SessionState.bookmarkChapterId(token);
                  final fraction = SessionState.bookmarkScrollFraction(token);
                  final index = chapters.indexWhere((chapter) => chapter.id == chapterId);
                  final item = index >= 0 ? chapters[index] : null;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bookmark),
                    title: Text(item?.title ?? chapterId),
                    subtitle: Text(
                      'Chapter ${index + 1}${fraction == null ? '' : ' · ${(fraction * 100).round()}%'}',
                    ),
                    onTap: () => Navigator.pop(context, (index: index, fraction: fraction)),
                  );
                }),
            ],
          ),
        );
      },
    );
    if (selected != null && selected.index >= 0) {
      await _goToChapter(selected.index);
      if (selected.fraction != null) {
        await _restoreScroll(selected.fraction!);
      }
    }
  }

  double _currentScrollFraction() {
    if (!scrollController.hasClients) return 0;
    final max = scrollController.position.maxScrollExtent;
    if (max <= 0) return 0;
    return (scrollController.offset / max).clamp(0.0, 1.0);
  }

  Color _pageColor(ReaderThemeMode theme) => switch (theme) {
        ReaderThemeMode.day => ListenColors.sand,
        ReaderThemeMode.sepia => const Color(0xFFF3E5C7),
        ReaderThemeMode.night => const Color(0xFF1C1B1A),
      };

  Color _inkColor(ReaderThemeMode theme) => switch (theme) {
        ReaderThemeMode.day => ListenColors.ink,
        ReaderThemeMode.sepia => const Color(0xFF4A3B28),
        ReaderThemeMode.night => const Color(0xFFE8E4DC),
      };

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final prefs = session.readerPrefs;
    final pageColor = _pageColor(prefs.theme);
    final ink = _inkColor(prefs.theme);

    if (_loading) {
      return Scaffold(
        backgroundColor: pageColor,
        appBar: AppBar(
          backgroundColor: pageColor,
          foregroundColor: ink,
          title: Text(widget.title.name, style: TextStyle(color: ink)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_pdfMode && _pdfController != null) {
      final pdf = _pdfController!;
      return Scaffold(
        backgroundColor: pageColor,
        appBar: AppBar(
          backgroundColor: pageColor,
          foregroundColor: ink,
          title: Text(widget.title.name, style: TextStyle(color: ink)),
          actions: [
            IconButton(
              tooltip: 'Comments',
              onPressed: () => openContentNotesSheet(
                context,
                titleId: widget.title.id,
                locationId: 'pdf',
                anchor: 'document',
                position: 0,
              ),
              icon: const Icon(Icons.comment_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.sampleOnly ? 'Sample' : 'PDF',
                  style: TextStyle(
                    color: ListenColors.coral,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Chapter controls and bookmarks work best with EPUB editions.',
                  style: TextStyle(color: ink.withValues(alpha: 0.55), fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: PdfViewPinch(
                controller: pdf,
                builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                  options: const DefaultBuilderOptions(),
                  documentLoaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
                  pageLoaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
                  errorBuilder: (_, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not render this PDF.\n$error',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: ink),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: ValueListenableBuilder<int>(
            valueListenable: pdf.pageListenable,
            builder: (context, page, _) {
              final count = pdf.pagesCount ?? 1;
              return Container(
                color: pageColor,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: page <= 1
                          ? null
                          : () => pdf.previousPage(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                              ),
                      child: Text('Previous', style: TextStyle(color: ink.withValues(alpha: 0.85))),
                    ),
                    const Spacer(),
                    Text('$page of $count', style: TextStyle(color: ink.withValues(alpha: 0.7))),
                    const Spacer(),
                    TextButton(
                      onPressed: page >= count
                          ? null
                          : () => pdf.nextPage(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                              ),
                      child: Text('Next', style: TextStyle(color: ink.withValues(alpha: 0.85))),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }

    if (chapters.isEmpty) {
      return Scaffold(
        backgroundColor: pageColor,
        appBar: AppBar(
          backgroundColor: pageColor,
          foregroundColor: ink,
          title: Text(widget.title.name, style: TextStyle(color: ink)),
        ),
        body: Center(
          child: Text(
            _pdfError ?? 'No chapters available yet.',
            style: TextStyle(color: ink),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final paragraphs = chapter.body.split('. ');
    final bookmarked = session.isChapterBookmarked(widget.title.id, chapter.id);

    return Scaffold(
      backgroundColor: pageColor,
      appBar: AppBar(
        backgroundColor: pageColor,
        foregroundColor: ink,
        title: Text(widget.title.name, style: TextStyle(color: ink)),
        actions: [
          IconButton(
            tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark position',
            onPressed: () => session.toggleChapterBookmark(
              titleId: widget.title.id,
              chapterId: chapter.id,
              scrollFraction: _currentScrollFraction(),
            ),
            icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
          ),
          IconButton(
            tooltip: 'Bookmarks',
            onPressed: () => _openBookmarks(context, session),
            icon: const Icon(Icons.bookmarks_outlined),
          ),
          IconButton(
            tooltip: 'Comments',
            onPressed: () => openContentNotesSheet(
              context,
              titleId: widget.title.id,
              locationId: chapter.id,
              anchor: 'chapter',
              position: _currentScrollFraction(),
            ),
            icon: const Icon(Icons.comment_outlined),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.tune, color: ink),
            onSelected: (value) {
              switch (value) {
                case 'font-1':
                  session.setReaderPrefs(fontScale: 1);
                case 'font-115':
                  session.setReaderPrefs(fontScale: 1.15);
                case 'font-13':
                  session.setReaderPrefs(fontScale: 1.3);
                case 'theme-day':
                  session.setReaderPrefs(theme: ReaderThemeMode.day);
                case 'theme-sepia':
                  session.setReaderPrefs(theme: ReaderThemeMode.sepia);
                case 'theme-night':
                  session.setReaderPrefs(theme: ReaderThemeMode.night);
                case 'download':
                  session.downloadForOffline(widget.title);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'font-1', child: Text('Font · Regular')),
              const PopupMenuItem(value: 'font-115', child: Text('Font · Large')),
              const PopupMenuItem(value: 'font-13', child: Text('Font · Extra large')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'theme-day', child: Text('Theme · Day')),
              const PopupMenuItem(value: 'theme-sepia', child: Text('Theme · Sepia')),
              const PopupMenuItem(value: 'theme-night', child: Text('Theme · Night')),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'download',
                child: Text(session.isDownloaded(widget.title.id) ? 'Refresh offline EPUB' : 'Download offline'),
              ),
            ],
          ),
          PopupMenuButton<int>(
            icon: Icon(Icons.list_alt, color: ink),
            onSelected: _goToChapter,
            itemBuilder: (_) => [
              for (var i = 0; i < chapters.length; i++)
                PopupMenuItem(
                  value: i,
                  child: Text(
                    '${i + 1}. ${chapters[i].title}'
                    '${session.isChapterBookmarked(widget.title.id, chapters[i].id) ? ' ★' : ''}',
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (session.adBreakActive && session.adBreakPlacement == 'chapter')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: AdBreakOverlay(
                placement: 'chapter',
                elapsedSec: session.adBreakElapsedSec,
                skippable: session.adBreakSkippable,
                onSkip: session.skipAdBreak,
                onContinue: () => session.completeAdBreak(skipped: false),
              ),
            ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Text(
                  widget.sampleOnly ? 'Sample' : 'Reading',
                  style: TextStyle(
                    color: ListenColors.coral,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
                if (widget.title.showsAds) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Includes short ads between chapters that support this creator',
                    style: TextStyle(color: ink.withValues(alpha: 0.55), fontSize: 12),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Chapter ${chapterIndex + 1} · ${chapter.title}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: ink),
                ),
                const SizedBox(height: 16),
                ...List.generate((paragraphs.length / 3).ceil(), (index) {
                  final chunk = paragraphs.skip(index * 3).take(3).join('. ');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      chunk.endsWith('.') ? chunk : '$chunk.',
                      style: TextStyle(
                        fontSize: 16 * prefs.fontScale,
                        height: 1.55,
                        color: ink,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: pageColor,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              TextButton(
                onPressed: chapterIndex == 0 ? null : () => _goToChapter(chapterIndex - 1),
                child: Text('Previous', style: TextStyle(color: ink.withValues(alpha: 0.85))),
              ),
              const Spacer(),
              Text(
                '${chapterIndex + 1} of ${chapters.length}',
                style: TextStyle(color: ink.withValues(alpha: 0.7)),
              ),
              const Spacer(),
              TextButton(
                onPressed: chapterIndex >= chapters.length - 1 ? null : () => _goToChapter(chapterIndex + 1),
                child: Text('Next', style: TextStyle(color: ink.withValues(alpha: 0.85))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
