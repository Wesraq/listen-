import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/catalogue.dart';
import '../data/content_models.dart';
import '../services/audio_duration.dart';
import '../data/genres.dart';
import '../services/ebook_chapter_extractor.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';

/// Distinct Creator Studio upload experiences for ebook, audiobook, and podcast.
Future<void> showStudioUploadFlow(
  BuildContext context,
  SessionState session, {
  CreatorDraft? existing,
}) async {
  CreatorDraft? resolved = existing;
  if (existing != null) {
    resolved = await session.draftForEdit(existing);
    if (!context.mounted) return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: ListenColors.sand,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _StudioUploadShell(session: session, existing: resolved),
      );
    },
  );
}

class _StudioUploadShell extends StatefulWidget {
  const _StudioUploadShell({required this.session, this.existing});

  final SessionState session;
  final CreatorDraft? existing;

  @override
  State<_StudioUploadShell> createState() => _StudioUploadShellState();
}

class _StudioUploadShellState extends State<_StudioUploadShell> {
  late String format;
  late int step;

  @override
  void initState() {
    super.initState();
    format = widget.existing?.format ?? '';
    step = widget.existing == null ? 0 : 1;
  }

  bool get isEbook => format == 'Ebook' || format == 'Ebook + Audiobook';
  bool get isAudio =>
      format == 'Audiobook' || format == 'Podcast' || format == 'Ebook + Audiobook';
  bool get isPodcast => format == 'Podcast';
  bool get isAudiobook => format == 'Audiobook' || format == 'Ebook + Audiobook';

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.92;
    return SizedBox(
      height: height,
      child: step == 0
          ? _FormatPicker(
              onPick: (value) => setState(() {
                format = value;
                step = 1;
              }),
            )
          : _FormatUploadWizard(
              session: widget.session,
              existing: widget.existing,
              format: format,
              onBackToFormats: widget.existing == null
                  ? () => setState(() {
                        format = '';
                        step = 0;
                      })
                  : null,
            ),
    );
  }
}

class _FormatPicker extends StatelessWidget {
  const _FormatPicker({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Text('What are you publishing?', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Each format has its own upload flow. eBooks build chapters from the file; audiobooks and podcasts let you add parts manually.',
          style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.62), height: 1.4),
        ),
        const SizedBox(height: 18),
        _FormatHeroCard(
          icon: Icons.menu_book_rounded,
          title: 'eBook',
          subtitle: 'Upload EPUB, PDF, or text. Listen+ detects chapters automatically for the reader.',
          accent: ListenColors.leaf,
          onTap: () => onPick('Ebook'),
        ),
        const SizedBox(height: 12),
        _FormatHeroCard(
          icon: Icons.headphones_rounded,
          title: 'Audiobook',
          subtitle: 'Add tracks yourself — one audio file per chapter or part, in listening order.',
          accent: const Color(0xFF3D5A80),
          onTap: () => onPick('Audiobook'),
        ),
        const SizedBox(height: 12),
        _PodcastFormatCard(onTap: () => onPick('Podcast')),
        const SizedBox(height: 18),
        Text('Also available', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => onPick('Ebook + Audiobook'),
          icon: const Icon(Icons.auto_stories_outlined),
          label: const Text('Same title as eBook + Audiobook'),
        ),
      ],
    );
  }
}

class _PodcastFormatCard extends StatelessWidget {
  const _PodcastFormatCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF2A1F1C), Color(0xFFC45C3E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.podcasts_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Podcast',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'A dedicated studio for show art, episode audio, scripts and show notes.',
                        style: TextStyle(color: Colors.white70, height: 1.35),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Open podcast studio →',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormatHeroCard extends StatelessWidget {
  const _FormatHeroCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        height: 1.4,
                        color: ListenColors.ink.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Continue',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatUploadWizard extends StatefulWidget {
  const _FormatUploadWizard({
    required this.session,
    required this.format,
    this.existing,
    this.onBackToFormats,
  });

  final SessionState session;
  final CreatorDraft? existing;
  final String format;
  final VoidCallback? onBackToFormats;

  @override
  State<_FormatUploadWizard> createState() => _FormatUploadWizardState();
}

class _FormatUploadWizardState extends State<_FormatUploadWizard> {
  static const _extractor = EbookChapterExtractor();

  late final TextEditingController title;
  late final TextEditingController zmw;
  late final TextEditingController usd;
  late final TextEditingController zar;

  late int step;
  String? mediaName;
  String? mediaPath;
  String? mediaKind;
  int? mediaBytes;
  String? coverImageName;
  String? coverImagePath;
  int? coverImageBytes;
  var rightsAccepted = false;
  var submitForReview = true;
  var extracting = false;
  String? extractNote;
  late String monetisationMode;
  late bool subscriptionEligible;
  late String genre;
  late List<ContentChapter> chapters;
  late List<ContentEpisode> episodes;

  bool get isEbook =>
      widget.format == 'Ebook' || widget.format == 'Ebook + Audiobook';
  bool get isDual => widget.format == 'Ebook + Audiobook';
  bool get isPodcast => widget.format == 'Podcast';
  bool get isAudiobookOnly => widget.format == 'Audiobook';
  bool get needsManualAudioParts =>
      widget.format == 'Audiobook' ||
      widget.format == 'Podcast' ||
      widget.format == 'Ebook + Audiobook';

  /// eBook-only: details → upload/chapters → pricing+rights (3).
  /// Audiobook / podcast / dual: four steps ending on rights.
  int get lastStep => widget.format == 'Ebook' ? 3 : 4;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    title = TextEditingController(text: existing?.title ?? '');
    zmw = TextEditingController(text: _money(existing, 'ZMW', '85.00'));
    usd = TextEditingController(text: _money(existing, 'USD', '4.99'));
    zar = TextEditingController(text: _money(existing, 'ZAR', '89.00'));
    mediaName = existing?.mediaName;
    mediaPath = existing?.mediaPath;
    mediaKind = existing?.mediaKind;
    mediaBytes = existing?.mediaBytes;
    coverImageName = existing?.coverImageName;
    coverImagePath = existing?.coverImagePath;
    coverImageBytes = existing?.coverImageBytes;
    rightsAccepted = existing != null;
    submitForReview = existing?.status == 'submitted' || existing == null;
    chapters = List<ContentChapter>.from(existing?.chapters ?? const []);
    episodes = List<ContentEpisode>.from(existing?.episodes ?? const []);
    genre = existing?.genre?.trim().isNotEmpty == true
        ? existing!.genre!
        : ListenGenres.defaultForFormat(widget.format);
    final existingMode = existing?.monetisationMode;
    if (widget.format == 'Podcast') {
      monetisationMode = existingMode ??
          ((existing?.prices.any((p) => p.amountMinor > 0) ?? false)
              ? 'premium_purchase'
              : 'free_with_ads');
      subscriptionEligible = existing?.subscriptionEligible ??
          (monetisationMode == 'subscription' || monetisationMode == 'premium_purchase');
    } else {
      monetisationMode = existingMode ?? 'purchase';
      subscriptionEligible = existing?.subscriptionEligible ?? true;
    }
    step = 1;
  }

  @override
  void dispose() {
    title.dispose();
    zmw.dispose();
    usd.dispose();
    zar.dispose();
    super.dispose();
  }

  String _money(CreatorDraft? draft, String currency, String fallback) {
    if (draft == null) return fallback;
    try {
      final quote = draft.prices.firstWhere((p) => p.currency == currency);
      return (quote.amountMinor / 100).toStringAsFixed(2);
    } catch (_) {
      return fallback;
    }
  }

  String get flowTitle {
    switch (widget.format) {
      case 'Audiobook':
        return 'New audiobook';
      case 'Podcast':
        return 'New podcast';
      case 'Ebook + Audiobook':
        return 'eBook + audiobook';
      default:
        return 'New eBook';
    }
  }

  Future<String?> _persist(String? sourcePath, String folder, String name) async {
    if (sourcePath == null || sourcePath.isEmpty) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${dir.path}/$folder');
      if (!await destDir.exists()) await destDir.create(recursive: true);
      final dest = File('${destDir.path}/${DateTime.now().millisecondsSinceEpoch}_$name');
      await File(sourcePath).copy(dest.path);
      return dest.path;
    } catch (_) {
      return sourcePath;
    }
  }

  Future<void> _pickCover() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final persisted = await _persist(file.path, 'covers', file.name);
      setState(() {
        coverImageName = file.name;
        coverImagePath = persisted ?? file.path;
        coverImageBytes = file.size;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not pick a cover photo.')),
      );
    }
  }

  Future<void> _useSampleEbook() async {
    final bytes = await rootBundle.load('assets/samples/sample_title.epub.txt');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/sample_title.epub.txt');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    await _applyEbookFile(
      name: 'sample_title.epub.txt',
      path: file.path,
      size: await file.length(),
    );
  }

  Future<void> _pickEbook() async {
    try {
      // Prefer EPUB (full chapter reader). Keep FileType.any so iOS does not grey files out.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final name = file.name;
      final lower = name.toLowerCase();
      final allowed = EbookChapterExtractor.supportedExtensions.any(
        (ext) => lower.endsWith('.$ext') || lower.endsWith('.epub.txt'),
      );
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose an EPUB (recommended), or TXT / HTML / Markdown / PDF.'),
          ),
        );
        return;
      }
      if (lower.endsWith('.pdf') && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PDF works for viewing pages, but EPUB unlocks chapter controls (font, theme, bookmarks).',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      final persisted = await _persist(file.path, 'media', name);
      await _applyEbookFile(
        name: name,
        path: persisted ?? file.path ?? '',
        size: file.size,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open ebook file. Try EPUB, PDF, or the sample.')),
      );
    }
  }

  Future<void> _applyEbookFile({
    required String name,
    required String path,
    required int size,
  }) async {
    if (path.isEmpty) return;
    setState(() {
      extracting = true;
      extractNote = null;
      mediaName = name;
      mediaPath = path;
      mediaBytes = size;
      mediaKind = name.toLowerCase().endsWith('.pdf') ? 'other' : 'epub';
    });
    final parsed = await _extractor.extractFromPath(path);
    if (!mounted) return;
    final isPdf = name.toLowerCase().endsWith('.pdf');
    final placeholder = parsed.length == 1 &&
        parsed.first.body.toLowerCase().contains('image-based or encrypted');
    final cleaned = [
      for (var i = 0; i < parsed.length; i++)
        parsed[i].copyWith(
          title: _safeChapterTitle(parsed[i].title, i),
          body: _safeChapterBody(parsed[i].body),
        ),
    ];
    setState(() {
      chapters = cleaned;
      extracting = false;
      extractNote = cleaned.isEmpty
          ? 'No chapters detected — try EPUB or a text-based PDF.'
          : (isPdf && placeholder
              ? 'PDF attached. Chapter text could not be extracted cleanly — readers will open the PDF pages. Prefer EPUB for editable chapters.'
              : 'Detected ${cleaned.length} chapter${cleaned.length == 1 ? '' : 's'} from $name');
    });
  }

  String _safeChapterTitle(String raw, int index) {
    final lower = raw.toLowerCase();
    if (lower.contains('/app/') ||
        lower.contains('/public/') ||
        lower.contains('.pdf') && raw.contains('/')) {
      return 'Chapter ${index + 1}';
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > 90) return 'Chapter ${index + 1}';
    return trimmed;
  }

  String _safeChapterBody(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('image-based or encrypted')) return raw;
    var text = raw;
    text = text.replaceAll(RegExp(r'/app/[^\s]+', caseSensitive: false), ' ');
    text = text.replaceAll(
      RegExp(r'(?:/[\w.-]+){2,}\.pdf\b', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
    return text.isEmpty ? raw : text;
  }

  Future<void> _pickEpisodeAudio(int index) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg'],
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final persisted = await _persist(file.path, 'episodes', file.name);
      final path = persisted ?? file.path;
      final probed = path == null ? null : await probeAudioDurationSec(path);
      setState(() {
        episodes[index] = episodes[index].copyWith(
          mediaName: file.name,
          mediaPath: path,
          durationSec: probed ?? episodes[index].durationSec,
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not attach audio for this part.')),
      );
    }
  }

  Future<void> _useSampleEpisodeAudio(int index) async {
    final bytes = await rootBundle.load('assets/samples/sample_episode.wav');
    final dir = await getTemporaryDirectory();
    final name = '${isPodcast ? 'episode' : 'track'}_${index + 1}_sample.wav';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    final persisted = await _persist(file.path, 'episodes', name);
    final path = persisted ?? file.path;
    final probed = await probeAudioDurationSec(path);
    setState(() {
      episodes[index] = episodes[index].copyWith(
        mediaName: name,
        mediaPath: path,
        durationSec: probed ?? 180,
      );
    });
  }

  void _addAudioPart() {
    final noun = isPodcast ? 'Episode' : 'Track';
    setState(() {
      episodes = [
        ...episodes,
        ContentEpisode(
          id: 'ep-${DateTime.now().millisecondsSinceEpoch}',
          title: '$noun ${episodes.length + 1}',
          durationSec: 0,
          sortOrder: episodes.length,
        ),
      ];
    });
  }

  bool _validateBeforeSave() {
    if (title.text.trim().isEmpty) {
      _toast('Enter a title.');
      return false;
    }
    if (!ListenGenres.isKnown(genre)) {
      _toast('Choose a genre for this title.');
      return false;
    }
    if (isEbook && (mediaPath == null || mediaPath!.isEmpty) && chapters.isEmpty) {
      _toast('Upload an ebook so chapters can be created.');
      return false;
    }
    if (isEbook && chapters.isEmpty) {
      _toast('No chapters detected yet. Re-upload the ebook file.');
      return false;
    }
    if (needsManualAudioParts && episodes.isEmpty) {
      _toast(isPodcast ? 'Add at least one episode.' : 'Add at least one track.');
      return false;
    }
    if (needsManualAudioParts && episodes.any((e) => !e.hasContent)) {
      _toast(
        isPodcast
            ? 'Each episode needs audio and/or a script.'
            : 'Each track needs an audio file attached.',
      );
      return false;
    }
    if (isAudiobookOnly && episodes.any((e) => e.mediaName == null || e.mediaName!.isEmpty)) {
      _toast('Attach audio for every audiobook track.');
      return false;
    }
    if (!rightsAccepted) {
      _toast('Confirm rights before submit.');
      return false;
    }
    return true;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<PriceQuote> _resolvedPrices() {
    int minor(String raw) {
      final value = double.tryParse(raw.trim()) ?? 0;
      return (value * 100).round();
    }

    // Free / ads / subscription access: no list price.
    if (monetisationMode == 'free_with_ads' ||
        monetisationMode == 'subscription' ||
        (isPodcast && monetisationMode != 'premium_purchase')) {
      return const [
        PriceQuote(currency: 'ZMW', amountMinor: 0),
        PriceQuote(currency: 'USD', amountMinor: 0),
        PriceQuote(currency: 'ZAR', amountMinor: 0),
      ];
    }
    return [
      PriceQuote(currency: 'ZMW', amountMinor: minor(zmw.text)),
      PriceQuote(currency: 'USD', amountMinor: minor(usd.text)),
      PriceQuote(currency: 'ZAR', amountMinor: minor(zar.text)),
    ];
  }

  Future<void> _save() async {
    if (!_validateBeforeSave()) return;
    if ((monetisationMode == 'purchase' || monetisationMode == 'premium_purchase') &&
        _resolvedPrices().every((p) => p.amountMinor <= 0)) {
      _toast('Set a list price, or switch to Free + ads / Subscription.');
      return;
    }

    await widget.session.saveCreatorDraft(
      existingId: widget.existing?.id,
      title: title.text.trim(),
      format: widget.format,
      prices: _resolvedPrices(),
      genre: genre,
      monetisationMode: monetisationMode,
      subscriptionEligible: monetisationMode == 'subscription' ||
          monetisationMode == 'premium_purchase' ||
          (monetisationMode == 'purchase' && subscriptionEligible),
      mediaName: mediaName,
      mediaPath: mediaPath,
      mediaKind: mediaKind,
      mediaBytes: mediaBytes,
      coverImageName: coverImageName,
      coverImagePath: coverImagePath,
      coverImageBytes: coverImageBytes,
      chapters: isEbook ? chapters : const [],
      episodes: needsManualAudioParts ? episodes : const [],
      submit: submitForReview,
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  static const _podcastAccent = Color(0xFFC45C3E);
  static const _podcastDeep = Color(0xFF2A1F1C);
  static const _ebookAccent = Color(0xFF2F6F5E);
  static const _ebookDeep = Color(0xFF1C322C);

  @override
  Widget build(BuildContext context) {
    if (isPodcast) return _buildPodcastShell();
    if (isEbook && !isDual) return _buildEbookShell();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              if (widget.onBackToFormats != null && step == 1)
                IconButton(
                  onPressed: widget.onBackToFormats,
                  icon: const Icon(Icons.arrow_back),
                )
              else if (step > 1)
                IconButton(
                  onPressed: () => setState(() => step -= 1),
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(flowTitle, style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      _stepLabel(),
                      style: TextStyle(
                        fontSize: 12,
                        color: ListenColors.ink.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _StepDots(current: step, total: lastStep),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              ..._stepBody(),
              const SizedBox(height: 20),
              _navRow(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _navRow({Color? accent}) {
    final color = accent ?? ListenColors.leaf;
    return Row(
      children: [
        if (step > 1 || widget.onBackToFormats != null)
          TextButton(
            onPressed: () {
              if (step > 1) {
                setState(() => step -= 1);
              } else {
                widget.onBackToFormats?.call();
              }
            },
            child: const Text('Back'),
          ),
        const Spacer(),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: extracting
              ? null
              : () async {
                  if (step < lastStep) {
                    if (!_canAdvance()) return;
                    setState(() => step += 1);
                    return;
                  }
                  await _save();
                },
          child: Text(
            step < lastStep
                ? 'Continue'
                : (submitForReview
                    ? (widget.existing == null ? 'Publish show' : 'Save & submit')
                    : 'Save draft'),
          ),
        ),
      ],
    );
  }

  Widget _buildPodcastShell() {
    final showName = title.text.trim().isEmpty ? 'Your show' : title.text.trim();
    return ColoredBox(
      color: const Color(0xFFF6EFE9),
      child: Column(
        children: [
          _PodcastHeroHeader(
            showName: showName,
            step: step,
            totalSteps: lastStep,
            stepLabel: _stepLabel(),
            coverPath: coverImagePath,
            onBack: (step > 1 || widget.onBackToFormats != null)
                ? () {
                    if (step > 1) {
                      setState(() => step -= 1);
                    } else {
                      widget.onBackToFormats?.call();
                    }
                  }
                : null,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                ...switch (step) {
                  1 => _podcastDetailsStep(),
                  2 => _podcastPricingStep(),
                  3 => _podcastEpisodesStep(),
                  _ => _podcastRightsStep(),
                },
                const SizedBox(height: 22),
                _navRow(accent: _podcastAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? get _catalogueCoverAsset {
    final publishedId = widget.existing?.publishedTitleId;
    if (publishedId == null) return null;
    for (final title in titles) {
      if (title.id == publishedId) return title.imageAsset;
    }
    return null;
  }

  List<Widget> _podcastDetailsStep() {
    final hasLocalCover = coverImagePath != null && File(coverImagePath!).existsSync();
    final catalogueCover = _catalogueCoverAsset;
    final hasCover = hasLocalCover || catalogueCover != null || coverImageName != null;
    final editing = widget.existing != null;
    return [
      Text(
        editing ? 'Edit show' : 'Show identity',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: _podcastDeep,
            ),
      ),
      const SizedBox(height: 6),
      Text(
        editing
            ? 'Your published show is loaded. Update the name or cover — episodes stay on the Episodes step.'
            : 'Listeners judge a show in a glance — give it a name and square artwork that stands out in the feed.',
        style: TextStyle(height: 1.4, color: ListenColors.ink.withValues(alpha: 0.62)),
      ),
      const SizedBox(height: 18),
      TextField(
        controller: title,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: 'Show title',
          hintText: 'e.g. Night Market Radio',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: ListenColors.ink.withValues(alpha: 0.08)),
          ),
        ),
      ),
      const SizedBox(height: 18),
      Text('Cover art', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: _pickCover,
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: hasCover
                    ? _podcastAccent.withValues(alpha: 0.35)
                    : ListenColors.ink.withValues(alpha: 0.1),
                width: hasCover ? 2 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _podcastDeep.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: hasCover
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasLocalCover)
                          Image.file(File(coverImagePath!), fit: BoxFit.cover)
                        else if (catalogueCover != null)
                          Image.asset(
                            catalogueCover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Image.asset(
                              'assets/images/zambezi.jpg',
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          ColoredBox(
                            color: ListenColors.mist,
                            child: Center(
                              child: Text(
                                coverImageName ?? 'Cover on file',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    hasLocalCover || catalogueCover != null
                                        ? 'Change cover'
                                        : 'Replace cover · ${coverImageName ?? 'saved'}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : CustomPaint(
                      painter: _DashedBorderPainter(
                        color: ListenColors.ink.withValues(alpha: 0.18),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: _podcastAccent.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.podcasts_rounded, color: _podcastAccent, size: 30),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Tap to add square cover',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '1400×1400 works best',
                              style: TextStyle(
                                fontSize: 12,
                                color: ListenColors.ink.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _podcastPricingStep() {
    return [
      Text(
        'How this show earns',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: _podcastDeep,
            ),
      ),
      const SizedBox(height: 6),
      Text(
        'Podcasts are not priced per episode by default. Choose how Listen+ and you share revenue — ads, subscription listening, or a premium purchase.',
        style: TextStyle(height: 1.4, color: ListenColors.ink.withValues(alpha: 0.62)),
      ),
      const SizedBox(height: 16),
      _MonetisationOption(
        selected: monetisationMode == 'free_with_ads',
        accent: _podcastAccent,
        icon: Icons.campaign_outlined,
        title: 'Free with advertising',
        subtitle:
            'Episodes stay free. You earn 55% of net ad revenue on your show. Pre-roll / mid-roll and sponsorships can attach later.',
        onTap: () => setState(() => monetisationMode = 'free_with_ads'),
      ),
      const SizedBox(height: 10),
      _MonetisationOption(
        selected: monetisationMode == 'subscription',
        accent: _podcastAccent,
        icon: Icons.workspace_premium_outlined,
        title: 'Listen+ subscription',
        subtitle:
            'Premium / exclusive access via subscription. You share the podcast slice of the 60% creator pool from qualified listening minutes.',
        onTap: () => setState(() => monetisationMode = 'subscription'),
      ),
      const SizedBox(height: 10),
      _MonetisationOption(
        selected: monetisationMode == 'premium_purchase',
        accent: _podcastAccent,
        icon: Icons.shopping_bag_outlined,
        title: 'Premium series purchase',
        subtitle:
            'Sell the show (or exclusive series) as an individual purchase. Creator 70% / Listen+ 30% of net receipts.',
        onTap: () => setState(() => monetisationMode = 'premium_purchase'),
      ),
      if (monetisationMode == 'premium_purchase') ...[
        const SizedBox(height: 16),
        Text('Premium list price', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Only needed for paid premium unlocks — not for free or subscription shows.',
          style: TextStyle(fontSize: 12.5, color: ListenColors.ink.withValues(alpha: 0.55)),
        ),
        const SizedBox(height: 10),
        ..._compactPriceFields(),
      ],
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          monetisationMode == 'free_with_ads'
              ? 'No episode price required. Ads and sponsorships drive earnings.'
              : monetisationMode == 'subscription'
                  ? 'No list price required. Earnings follow qualified podcast listening in the subscription pool.'
                  : 'Listeners buy once. Set ZMW (and optional USD / ZAR) below.',
          style: TextStyle(height: 1.4, color: ListenColors.ink.withValues(alpha: 0.7)),
        ),
      ),
    ];
  }

  List<Widget> _compactPriceFields() {
    Widget field(TextEditingController c, String currency) {
      return Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: currency,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
    }

    return [
      Row(
        children: [
          field(zmw, 'ZMW'),
          const SizedBox(width: 8),
          field(usd, 'USD'),
          const SizedBox(width: 8),
          field(zar, 'ZAR'),
        ],
      ),
    ];
  }

  List<Widget> _podcastEpisodesStep() {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Episode queue',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _podcastDeep,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Build the show one episode at a time — audio first, notes optional.',
                  style: TextStyle(height: 1.35, color: ListenColors.ink.withValues(alpha: 0.62)),
                ),
              ],
            ),
          ),
          Text(
            '${episodes.length}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _podcastAccent,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (episodes.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 28, 18, 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: ListenColors.ink.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              Icon(Icons.graphic_eq_rounded, size: 42, color: _podcastAccent.withValues(alpha: 0.8)),
              const SizedBox(height: 12),
              const Text(
                'No episodes yet',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Start with episode 1 — attach the audio listeners will play.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.55), height: 1.35),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _podcastAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _addAudioPart,
                icon: const Icon(Icons.add),
                label: const Text('Add first episode'),
              ),
            ],
          ),
        )
      else
        ...episodes.asMap().entries.map((entry) {
          final index = entry.key;
          final episode = entry.value;
          final hasAudio = (episode.mediaName != null && episode.mediaName!.isNotEmpty) ||
              (episode.mediaId != null && episode.mediaId!.isNotEmpty) ||
              (episode.mediaPath != null && episode.mediaPath!.isNotEmpty);
          final audioLabel = episode.mediaName?.isNotEmpty == true
              ? episode.mediaName!
              : (episode.mediaId != null ? 'Audio on Listen+' : 'Tap to attach episode audio');
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: _podcastDeep.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _podcastAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _podcastAccent,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          initialValue: episode.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(
                            labelText: 'Episode title',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (value) {
                            episodes[index] = episodes[index].copyWith(title: value);
                          },
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          episodes = [...episodes]..removeAt(index);
                          for (var i = 0; i < episodes.length; i++) {
                            episodes[i] = episodes[i].copyWith(sortOrder: i);
                          }
                        }),
                        icon: Icon(Icons.close, color: ListenColors.ink.withValues(alpha: 0.35)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        onTap: () => _pickEpisodeAudio(index),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: hasAudio
                                ? ListenColors.leaf.withValues(alpha: 0.08)
                                : const Color(0xFFF3E8E2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                hasAudio ? Icons.check_circle : Icons.graphic_eq,
                                color: hasAudio ? ListenColors.leaf : _podcastAccent,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  audioLabel,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: hasAudio ? ListenColors.leaf : _podcastDeep,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.upload_rounded,
                                color: ListenColors.ink.withValues(alpha: 0.35),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => _useSampleEpisodeAudio(index),
                          child: Text(hasAudio ? 'Replace with sample audio' : 'Use sample audio'),
                        ),
                      ),
                      Text(
                        episode.durationSec > 0
                            ? 'Duration · ${formatDurationLabel(episode.durationSec)}'
                            : (hasAudio
                                ? 'Audio already attached to this episode'
                                : 'Duration appears after you attach audio'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: ListenColors.ink.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: episode.body ?? '',
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Script / transcript',
                          hintText: 'Optional — helps listeners and moderation.',
                          filled: true,
                          fillColor: const Color(0xFFF7F3EE),
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) {
                          episodes[index] = episodes[index].copyWith(body: value);
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: episode.showNotes ?? '',
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Show notes',
                          filled: true,
                          fillColor: const Color(0xFFF7F3EE),
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) {
                          episodes[index] = episodes[index].copyWith(showNotes: value);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      if (episodes.isNotEmpty) ...[
        const SizedBox(height: 4),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: _podcastAccent,
            side: BorderSide(color: _podcastAccent.withValues(alpha: 0.45)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _addAudioPart,
          icon: const Icon(Icons.add),
          label: const Text('Add another episode'),
        ),
      ],
    ];
  }

  List<Widget> _podcastRightsStep() {
    final readyAudio = episodes.where((e) => e.hasContent).length;
    return [
      Text(
        'Ready to publish?',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: _podcastDeep,
            ),
      ),
      const SizedBox(height: 6),
      Text(
        'Confirm rights, then send the show for Listen+ moderation.',
        style: TextStyle(height: 1.4, color: ListenColors.ink.withValues(alpha: 0.62)),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2A1F1C), Color(0xFF4A322C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.text.trim().isEmpty ? 'Untitled show' : title.text.trim(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$readyAudio ready episode${readyAudio == 1 ? '' : 's'} · ${_podcastEarnLabel()}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
            ),
            if (coverImageName != null) ...[
              const SizedBox(height: 6),
              Text(
                'Cover · $coverImageName',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            CheckboxListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              value: rightsAccepted,
              activeColor: _podcastAccent,
              onChanged: (value) => setState(() => rightsAccepted = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('I confirm rights for these territories and formats'),
            ),
            CheckboxListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              value: submitForReview,
              activeColor: _podcastAccent,
              onChanged: (value) => setState(() => submitForReview = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Submit for moderation now'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Podcast ads: proposed 55% creator / 45% Listen+. Purchases: 70/30 of net receipts.',
        style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.6), height: 1.35),
      ),
    ];
  }

  String _stepLabel() {
    if (isEbook && !needsManualAudioParts) {
      return switch (step) {
        1 => 'Title, genre & cover',
        2 => 'Manuscript · EPUB preferred',
        3 => 'Earn & publish',
        _ => '',
      };
    }
    if (isPodcast) {
      return switch (step) {
        1 => 'Show details',
        2 => 'How this show earns',
        3 => 'Episodes',
        4 => 'Rights',
        _ => '',
      };
    }
    if (isAudiobookOnly) {
      return switch (step) {
        1 => 'Title & cover',
        2 => 'Buy · subscribe · ads',
        3 => 'Tracks / chapters',
        4 => 'Rights',
        _ => '',
      };
    }
    // Dual
    return switch (step) {
      1 => 'Details & cover',
      2 => 'eBook file · auto chapters',
      3 => 'Audiobook tracks',
      4 => 'Pricing & rights',
      _ => '',
    };
  }

  bool _canAdvance() {
    if (step == 1 && title.text.trim().isEmpty) {
      _toast('Enter a title first.');
      return false;
    }
    if (step == 1 && !ListenGenres.isKnown(genre)) {
      _toast('Choose a genre.');
      return false;
    }
    if (isEbook && step == 2 && chapters.isEmpty) {
      _toast('Upload an ebook so Listen+ can create chapters.');
      return false;
    }
    if ((isPodcast || isAudiobookOnly) && step == 3 && episodes.isEmpty) {
      _toast(isPodcast ? 'Add at least one episode.' : 'Add at least one track.');
      return false;
    }
    if (isDual && step == 3 && episodes.isEmpty) {
      _toast('Add at least one audiobook track.');
      return false;
    }
    return true;
  }

  List<Widget> _stepBody() {
    if (isEbook && !needsManualAudioParts) {
      return switch (step) {
        1 => _ebookDetailsStep(),
        2 => _ebookUploadStep(),
        _ => _pricingAndRightsStep(),
      };
    }
    if (isPodcast) {
      return switch (step) {
        1 => _detailsStep(showEbookHint: false),
        2 => _pricingOnlyStep(),
        3 => _manualAudioPartsStep(noun: 'Episode', allowScript: true),
        _ => _rightsOnlyStep(),
      };
    }
    if (isAudiobookOnly) {
      return switch (step) {
        1 => _detailsStep(showEbookHint: false),
        2 => _pricingOnlyStep(),
        3 => _manualAudioPartsStep(noun: 'Track', allowScript: false),
        _ => _rightsOnlyStep(),
      };
    }
    // Dual ebook + audiobook
    return switch (step) {
      1 => _detailsStep(showEbookHint: true),
      2 => _ebookUploadStep(),
      3 => _manualAudioPartsStep(noun: 'Track', allowScript: false),
      _ => _pricingAndRightsStep(),
    };
  }

  List<Widget> _detailsStep({required bool showEbookHint}) {
    return [
      Text(
        showEbookHint
            ? 'Name the title, pick a genre, and add a cover. Next you will upload an EPUB.'
            : (isPodcast
                ? 'Name the show, pick a genre, and add artwork listeners will recognise.'
                : 'Name the audiobook, pick a genre, and add cover art.'),
        style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.62), height: 1.35),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: title,
        decoration: InputDecoration(
          labelText: isPodcast ? 'Show / series title' : 'Title',
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 18),
      Text('Genre', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        'Listeners browse and discover by genre.',
        style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.55), fontSize: 13),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in ListenGenres.options)
            ChoiceChip(
              label: Text(option),
              selected: genre == option,
              onSelected: (_) => setState(() => genre = option),
            ),
        ],
      ),
      const SizedBox(height: 18),
      Text('Cover', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (coverImagePath != null && File(coverImagePath!).existsSync()) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.file(File(coverImagePath!), fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(
        onPressed: _pickCover,
        icon: const Icon(Icons.photo_camera_outlined),
        label: Text(coverImageName == null ? 'Add cover photo' : coverImageName!),
      ),
    ];
  }

  Widget _buildEbookShell() {
    final bookName = title.text.trim().isEmpty ? 'Your ebook' : title.text.trim();
    return ColoredBox(
      color: const Color(0xFFF3F7F5),
      child: Column(
        children: [
          _EbookHeroHeader(
            bookName: bookName,
            step: step,
            totalSteps: lastStep,
            stepLabel: _stepLabel(),
            coverPath: coverImagePath,
            onBack: (step > 1 || widget.onBackToFormats != null)
                ? () {
                    if (step > 1) {
                      setState(() => step -= 1);
                    } else {
                      widget.onBackToFormats?.call();
                    }
                  }
                : null,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                ...switch (step) {
                  1 => _ebookDetailsStep(),
                  2 => _ebookUploadStep(),
                  _ => _pricingAndRightsStep(),
                },
                const SizedBox(height: 22),
                _navRow(accent: _ebookAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _ebookDetailsStep() {
    final hasLocalCover = coverImagePath != null && File(coverImagePath!).existsSync();
    final catalogueCover = _catalogueCoverAsset;
    final hasCover = hasLocalCover || catalogueCover != null || coverImageName != null;
    final editing = widget.existing != null;
    return [
      Text(
        editing ? 'Edit ebook' : 'Book identity',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: _ebookDeep,
            ),
      ),
      const SizedBox(height: 6),
      Text(
        editing
            ? 'Update the title, genre, or cover. The manuscript stays on the next step.'
            : 'Give the book a clear title, pick a genre for discovery, and add cover art listeners will recognise.',
        style: TextStyle(height: 1.4, color: ListenColors.ink.withValues(alpha: 0.62)),
      ),
      const SizedBox(height: 18),
      TextField(
        controller: title,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: 'Book title',
          hintText: 'e.g. Lies That Are Truths',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: ListenColors.ink.withValues(alpha: 0.08)),
          ),
        ),
      ),
      const SizedBox(height: 18),
      Text('Genre', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        'Used in browse and search so the right readers find this book.',
        style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.55), fontSize: 13),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in ListenGenres.options)
            ChoiceChip(
              label: Text(option),
              selected: genre == option,
              onSelected: (_) => setState(() => genre = option),
            ),
        ],
      ),
      const SizedBox(height: 18),
      Text('Cover art', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: _pickCover,
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: hasCover
                    ? _ebookAccent.withValues(alpha: 0.35)
                    : ListenColors.ink.withValues(alpha: 0.1),
                width: hasCover ? 2 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _ebookDeep.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: hasCover
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasLocalCover)
                          Image.file(File(coverImagePath!), fit: BoxFit.cover)
                        else if (catalogueCover != null)
                          Image.asset(
                            catalogueCover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Image.asset(
                              'assets/images/jacaranda.jpg',
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          ColoredBox(
                            color: ListenColors.mist,
                            child: Center(
                              child: Text(
                                coverImageName ?? 'Cover on file',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.photo_camera_outlined, color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Change cover',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : CustomPaint(
                      painter: _DashedBorderPainter(
                        color: ListenColors.ink.withValues(alpha: 0.18),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: _ebookAccent.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.menu_book_rounded, color: _ebookAccent, size: 30),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Tap to add book cover',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Portrait works best',
                              style: TextStyle(
                                fontSize: 12,
                                color: ListenColors.ink.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    ];
  }

  String _chapterPreview(ContentChapter chapter) {
    final body = chapter.body.trim();
    if (body.isEmpty) return 'Empty body';
    final lower = body.toLowerCase();
    if (lower.contains('/app/') ||
        lower.contains('/public/task/') ||
        lower.contains('image-based or encrypted')) {
      return 'PDF page viewer will open this file — re-upload as EPUB for editable chapter text.';
    }
    return body.length > 140 ? '${body.substring(0, 140).trim()}…' : body;
  }

  List<Widget> _ebookUploadStep() {
    final hasFile = mediaName != null && mediaName!.isNotEmpty;
    final isPdf = (mediaName ?? '').toLowerCase().endsWith('.pdf');
    return [
      Text(
        'Manuscript',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: _ebookDeep,
            ),
      ),
      const SizedBox(height: 6),
      Text(
        'Upload an EPUB for chapter titles, fonts, themes, and bookmarks. PDF is supported as page viewing when text cannot be extracted cleanly.',
        style: TextStyle(height: 1.4, color: ListenColors.ink.withValues(alpha: 0.62)),
      ),
      const SizedBox(height: 16),
      GestureDetector(
        onTap: extracting ? null : _pickEbook,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 28, 18, 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: hasFile
                  ? _ebookAccent.withValues(alpha: 0.45)
                  : ListenColors.ink.withValues(alpha: 0.08),
              width: hasFile ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _ebookDeep.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _ebookAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasFile ? Icons.menu_book_rounded : Icons.upload_file_rounded,
                  color: _ebookAccent,
                  size: 30,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                hasFile ? mediaName! : 'Tap to choose EPUB file',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                hasFile
                    ? (isPdf
                        ? 'PDF attached · ${chapters.length} chapter shell${chapters.length == 1 ? '' : 's'}'
                        : '${chapters.length} chapter${chapters.length == 1 ? '' : 's'} ready')
                    : 'EPUB preferred · TXT · HTML · Markdown · PDF',
                textAlign: TextAlign.center,
                style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: extracting ? null : _pickEbook,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(hasFile ? 'Replace file' : 'Browse files'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextButton(
              onPressed: extracting ? null : _useSampleEbook,
              child: const Text('Use sample'),
            ),
          ),
        ],
      ),
      if (extracting) ...[
        const SizedBox(height: 18),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 8),
        const Center(child: Text('Creating chapters from ebook…')),
      ],
      if (extractNote != null) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _ebookAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            extractNote!,
            style: const TextStyle(
              color: _ebookAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
      if (chapters.isNotEmpty) ...[
        const SizedBox(height: 18),
        Row(
          children: [
            Text('Detected chapters', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text(
              '${chapters.length}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: _ebookAccent,
                fontSize: 18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...chapters.asMap().entries.map((entry) {
          final i = entry.key;
          final chapter = entry.value;
          final dirtyTitle = chapter.title.toLowerCase().contains('/app/') ||
              chapter.title.toLowerCase().contains('.pdf');
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ListenColors.ink.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: ValueKey('chapter-title-${chapter.id}-$i'),
                  initialValue: dirtyTitle ? 'Chapter ${i + 1}' : chapter.title,
                  decoration: InputDecoration(
                    labelText: 'Chapter ${i + 1}',
                    filled: true,
                    fillColor: const Color(0xFFF3F7F5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    chapters[i] = chapters[i].copyWith(title: value);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _chapterPreview(chapter),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: ListenColors.ink.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    ];
  }

  List<Widget> _manualAudioPartsStep({
    required String noun,
    required bool allowScript,
  }) {
    final plural = noun == 'Episode' ? 'episodes' : 'tracks';
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (isPodcast ? ListenColors.coral : const Color(0xFF3D5A80))
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          noun == 'Episode'
              ? 'Add each podcast episode yourself. Attach audio and optional script / show notes.'
              : 'Add audiobook chapters yourself as tracks. Attach one audio file per part, in order.',
          style: const TextStyle(height: 1.4),
        ),
      ),
      const SizedBox(height: 14),
      if (episodes.isEmpty)
        Text(
          'No $plural yet.',
          style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.55)),
        ),
      ...episodes.asMap().entries.map((entry) {
        final index = entry.key;
        final episode = entry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: episode.title,
                      decoration: InputDecoration(
                        labelText: '$noun ${index + 1} title',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        episodes[index] = episodes[index].copyWith(title: value);
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      episodes = [...episodes]..removeAt(index);
                      for (var i = 0; i < episodes.length; i++) {
                        episodes[i] = episodes[i].copyWith(sortOrder: i);
                      }
                    }),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _pickEpisodeAudio(index),
                icon: const Icon(Icons.audio_file_outlined),
                label: Text(
                  episode.mediaName == null ? 'Attach $noun audio' : episode.mediaName!,
                ),
              ),
              TextButton(
                onPressed: () => _useSampleEpisodeAudio(index),
                child: Text('Use sample audio for this ${noun.toLowerCase()}'),
              ),
              Text(
                episode.durationSec > 0
                    ? 'Duration from file · ${formatDurationLabel(episode.durationSec)}'
                    : 'Duration is read from the audio file after attach',
                style: TextStyle(
                  fontSize: 12.5,
                  color: ListenColors.ink.withValues(alpha: 0.55),
                ),
              ),
              if (allowScript) ...[
                const SizedBox(height: 4),
                TextFormField(
                  initialValue: episode.body ?? '',
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Script / transcript (optional)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  onChanged: (value) {
                    episodes[index] = episodes[index].copyWith(body: value);
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: episode.showNotes ?? '',
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Show notes (optional)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  onChanged: (value) {
                    episodes[index] = episodes[index].copyWith(showNotes: value);
                  },
                ),
              ],
            ],
          ),
        );
      }),
      OutlinedButton.icon(
        onPressed: _addAudioPart,
        icon: const Icon(Icons.add),
        label: Text('Add ${noun.toLowerCase()}'),
      ),
    ];
  }

  String _podcastEarnLabel() {
    return switch (monetisationMode) {
      'subscription' => 'Subscription earnings',
      'premium_purchase' => 'Premium · ZMW ${zmw.text}',
      _ => 'Free · advertising',
    };
  }

  List<Widget> _pricingOnlyStep() {
    // Audiobook monetisation — enforce all earning streams.
    const accent = Color(0xFF3D5A80);
    return [
      Text(
        isAudiobookOnly ? 'Audiobook monetisation' : 'Pricing',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 6),
      Text(
        isAudiobookOnly
            ? 'Choose how this audiobook earns: purchase, free with ads, and/or subscription-pool listening.'
            : 'Set the list price. Splits apply on net receipts after fees.',
        style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.62), height: 1.35),
      ),
      const SizedBox(height: 14),
      if (isAudiobookOnly) ...[
        _MonetisationOption(
          selected: monetisationMode == 'purchase',
          accent: accent,
          icon: Icons.shopping_bag_outlined,
          title: 'Individual purchase · 70 / 30',
          subtitle: 'List price. Creator receives 70% of net receipts on each sale.',
          onTap: () => setState(() {
            monetisationMode = 'purchase';
            subscriptionEligible = true;
          }),
        ),
        const SizedBox(height: 10),
        _MonetisationOption(
          selected: monetisationMode == 'free_with_ads',
          accent: accent,
          icon: Icons.campaign_outlined,
          title: 'Free with advertising · 55 / 45',
          subtitle:
              'Listeners stream free. Verified completed ads credit you 55% of net ad receipts. Light-touch pre/mid-roll only.',
          onTap: () => setState(() {
            monetisationMode = 'free_with_ads';
            subscriptionEligible = false;
            zmw.text = '0';
          }),
        ),
        const SizedBox(height: 10),
        _MonetisationOption(
          selected: monetisationMode == 'subscription',
          accent: accent,
          icon: Icons.workspace_premium_outlined,
          title: 'Listen+ subscription · pool',
          subtitle:
              'Included in subscription. You share the audiobook slice (45%) of the 60% creator pool from qualified minutes.',
          onTap: () => setState(() {
            monetisationMode = 'subscription';
            subscriptionEligible = true;
            zmw.text = '0';
          }),
        ),
        const SizedBox(height: 12),
      ],
      if (monetisationMode == 'purchase') ..._priceFields(),
      if (isAudiobookOnly && monetisationMode == 'purchase') ...[
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: subscriptionEligible,
          activeThumbColor: ListenColors.leaf,
          title: const Text('Also eligible for Listen+ subscription'),
          subtitle: Text(
            'Qualified listening minutes share the audiobook slice of the 60% creator pool.',
            style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.55)),
          ),
          onChanged: (value) => setState(() => subscriptionEligible = value),
        ),
      ],
    ];
  }

  List<Widget> _rightsOnlyStep() {
    return [
      ..._rightsFields(),
    ];
  }

  List<Widget> _pricingAndRightsStep() {
    return [
      Text(
        isEbook ? 'How this book earns' : 'Pricing',
        style: isEbook
            ? Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _ebookDeep,
                )
            : Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 6),
      if (isEbook)
        Text(
          'Pick how this eBook earns. Opens alone do not pay — only verified reading, purchases, or completed ads.',
          style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.62), height: 1.35),
        ),
      const SizedBox(height: 12),
      if (isEbook) ...[
        _MonetisationOption(
          selected: monetisationMode == 'purchase',
          accent: _ebookAccent,
          icon: Icons.menu_book_rounded,
          title: 'Buy the book · 70 / 30',
          subtitle: 'List price listeners pay to keep the eBook.',
          onTap: () => setState(() {
            monetisationMode = 'purchase';
            subscriptionEligible = true;
          }),
        ),
        const SizedBox(height: 10),
        _MonetisationOption(
          selected: monetisationMode == 'free_with_ads',
          accent: _ebookAccent,
          icon: Icons.campaign_outlined,
          title: 'Free with advertising · 55 / 45',
          subtitle:
              'Readers access free. Occasional between-chapter ads credit you 55% of net ad receipts.',
          onTap: () => setState(() {
            monetisationMode = 'free_with_ads';
            subscriptionEligible = false;
            zmw.text = '0';
          }),
        ),
        const SizedBox(height: 10),
        _MonetisationOption(
          selected: monetisationMode == 'subscription',
          accent: _ebookAccent,
          icon: Icons.workspace_premium_outlined,
          title: 'Listen+ subscription · pool',
          subtitle:
              'Included for subscribers. Qualified reading shares the eBook 30% slice of the 60% creator pool.',
          onTap: () => setState(() {
            monetisationMode = 'subscription';
            subscriptionEligible = true;
            zmw.text = '0';
          }),
        ),
        const SizedBox(height: 12),
      ],
      if (!isEbook || monetisationMode == 'purchase') ..._priceFields(),
      if (isEbook && monetisationMode == 'purchase') ...[
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: subscriptionEligible,
          activeThumbColor: ListenColors.leaf,
          title: const Text('Also eligible for Listen+ subscription'),
          subtitle: Text(
            'Qualified page progression shares the eBook 30% allocation inside the creator pool.',
            style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.55)),
          ),
          onChanged: (value) => setState(() => subscriptionEligible = value),
        ),
      ],
      const SizedBox(height: 16),
      ..._rightsFields(),
    ];
  }

  List<Widget> _priceFields() {
    return [
      TextField(
        controller: zmw,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'ZMW', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: usd,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'USD', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: zar,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'ZAR', border: OutlineInputBorder()),
      ),
    ];
  }

  List<Widget> _rightsFields() {
    final bits = <String>[];
    if (isEbook) {
      bits.add('${chapters.length} ebook chapter${chapters.length == 1 ? '' : 's'}');
    }
    if (needsManualAudioParts) {
      bits.add(
        '${episodes.length} ${isPodcast ? 'episode' : 'track'}${episodes.length == 1 ? '' : 's'}',
      );
    }
    return [
      Text(bits.join(' · '), style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.62))),
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: rightsAccepted,
        onChanged: (value) => setState(() => rightsAccepted = value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('I confirm rights for these territories and formats'),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: submitForReview,
        onChanged: (value) => setState(() => submitForReview = value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Submit for moderation now'),
      ),
      Text(
        'Purchases: creator 70% / Listen+ 30% of net receipts. Subscription pool and podcast ads follow the hybrid policy.',
        style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.65), height: 1.35),
      ),
    ];
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= total; i++)
          Container(
            width: i == current ? 18 : 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i == current
                  ? ListenColors.leaf
                  : ListenColors.ink.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}

class _EbookHeroHeader extends StatelessWidget {
  const _EbookHeroHeader({
    required this.bookName,
    required this.step,
    required this.totalSteps,
    required this.stepLabel,
    required this.coverPath,
    this.onBack,
  });

  final String bookName;
  final int step;
  final int totalSteps;
  final String stepLabel;
  final String? coverPath;
  final VoidCallback? onBack;

  static const _labels = ['Identity', 'Manuscript', 'Publish'];

  @override
  Widget build(BuildContext context) {
    final hasCover = coverPath != null && File(coverPath!).existsSync();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1C322C), Color(0xFF2F6F5E), Color(0xFF4F8F7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (onBack != null)
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  )
                else
                  const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'eBook studio',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '$step / $totalSteps',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 64,
                  height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasCover
                      ? Image.file(File(coverPath!), fit: BoxFit.cover)
                      : const Icon(Icons.menu_book_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bookName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stepLabel,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (var i = 0; i < totalSteps; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: i < step
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _labels[i.clamp(0, _labels.length - 1)],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: i + 1 == step ? FontWeight.w700 : FontWeight.w500,
                            color: Colors.white.withValues(alpha: i + 1 == step ? 0.95 : 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PodcastHeroHeader extends StatelessWidget {
  const _PodcastHeroHeader({
    required this.showName,
    required this.step,
    required this.totalSteps,
    required this.stepLabel,
    required this.coverPath,
    this.onBack,
  });

  final String showName;
  final int step;
  final int totalSteps;
  final String stepLabel;
  final String? coverPath;
  final VoidCallback? onBack;

  static const _labels = ['Identity', 'Earn', 'Episodes', 'Publish'];

  @override
  Widget build(BuildContext context) {
    final hasCover = coverPath != null && File(coverPath!).existsSync();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2A1F1C), Color(0xFF5A342C), Color(0xFFC45C3E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (onBack != null)
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  )
                else
                  const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Podcast studio',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '$step / $totalSteps',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasCover
                      ? Image.file(File(coverPath!), fit: BoxFit.cover)
                      : const Icon(Icons.mic_none_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        showName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stepLabel,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (var i = 0; i < totalSteps; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: i < step
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _labels[i],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: i + 1 == step ? FontWeight.w700 : FontWeight.w500,
                            color: Colors.white.withValues(alpha: i + 1 == step ? 0.95 : 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonetisationOption extends StatelessWidget {
  const _MonetisationOption({
    required this.selected,
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? accent : ListenColors.ink.withValues(alpha: 0.08),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        height: 1.35,
                        fontSize: 12.5,
                        color: ListenColors.ink.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? accent : ListenColors.ink.withValues(alpha: 0.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    const dash = 7.0;
    const gap = 5.0;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(8, 8, size.width - 16, size.height - 16),
          const Radius.circular(18),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}
