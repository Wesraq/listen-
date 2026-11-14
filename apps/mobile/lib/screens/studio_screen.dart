import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../data/content_models.dart';
import '../services/audio_duration.dart';
import '../services/ebook_chapter_extractor.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../widgets/page_intro.dart';
import 'studio_upload_flow.dart';
import 'support_legal.dart';

class StudioScreen extends StatelessWidget {
  const StudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();

    return RefreshIndicator(
      onRefresh: () => session.refreshFromApi(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: PageIntro(
              title: 'Studio',
              text: 'Publish ebooks, audiobooks and podcasts — each with its own upload flow.',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            sliver: SliverToBoxAdapter(
              child: () {
                final hasCreatorWork = session.drafts.any(
                  (d) =>
                      d.status == 'live' ||
                      d.status == 'submitted' ||
                      d.publishedTitleId != null,
                );
                final effective = session.creatorState == CreatorApplicationState.approved ||
                        hasCreatorWork
                    ? CreatorApplicationState.approved
                    : session.creatorState;
                return switch (effective) {
                  CreatorApplicationState.newApplicant => _WelcomePanel(
                      onApply: () => _showApplySheet(context, session),
                    ),
                  CreatorApplicationState.pending => _PendingPanel(
                      onRefresh: () async {
                        await session.refreshFromApi();
                        session.showNotice(
                          session.creatorState == CreatorApplicationState.approved
                              ? 'Creator access activated.'
                              : 'Still pending admin approval.',
                        );
                      },
                    ),
                  CreatorApplicationState.approved => const _ApprovedStudio(),
                };
              }(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showApplySheet(BuildContext context, SessionState session) async {
    final name = TextEditingController();
    final payout = TextEditingController(text: 'Mobile money · Zambia');
    var accepted = false;
    final formKey = GlobalKey<FormState>();
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Become a creator', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text(
                        'Tell us who you are and where you’d like to get paid. We’ll review your profile and rights before Studio unlocks.',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Creator or imprint name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty) ? 'Enter a creator name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: payout,
                        decoration: const InputDecoration(
                          labelText: 'Preferred payout method',
                          helperText: 'We’ll confirm details before your first payout.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: accepted,
                        onChanged: (value) => setModalState(() => accepted = value ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('I agree to the Creator Agreement and confirm I hold the rights to publish'),
                      ),
                      TextButton(
                        onPressed: () => openLegalDoc(context, LegalDoc.creatorAgreement),
                        child: const Text('Read Creator Agreement'),
                      ),
                      FilledButton(
                        onPressed: () {
                          if (!(formKey.currentState?.validate() ?? false)) return;
                          if (!accepted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Accept the Creator Agreement to continue.')),
                            );
                            return;
                          }
                          Navigator.pop(context, true);
                        },
                        child: const Text('Submit application'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (submitted == true) {
      await session.applyAsCreator(displayName: name.text.trim());
    }
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.onApply});

  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 11,
                child: Image.asset(
                  'assets/images/zambezi.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: ListenColors.leaf),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        ListenColors.ink.withValues(alpha: 0.78),
                        ListenColors.ink.withValues(alpha: 0.15),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CREATOR ACCESS',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your story belongs here.',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            height: 1.15,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Publish ebooks, audiobooks and podcasts for listeners across Africa and beyond.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: onApply,
          child: const Text('Become a creator'),
        ),
        const SizedBox(height: 10),
        Text(
          'The Listen+ team reviews identity and rights before Studio unlocks.',
          style: TextStyle(fontSize: 12, color: ListenColors.ink.withValues(alpha: 0.55)),
        ),
      ],
    );
  }
}

class _PendingPanel extends StatelessWidget {
  const _PendingPanel({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ListenColors.leaf.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: ListenColors.coral.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Under review',
              style: TextStyle(
                color: ListenColors.coral,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'We’re checking your creator application.',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'We review your identity and rights. When you’re approved, refresh to open Studio.',
            style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.65), height: 1.4),
          ),
          const SizedBox(height: 18),
          FilledButton.tonal(
            onPressed: () => onRefresh(),
            child: const Text('Check approval status'),
          ),
        ],
      ),
    );
  }
}

class _ApprovedStudio extends StatefulWidget {
  const _ApprovedStudio();

  @override
  State<_ApprovedStudio> createState() => _ApprovedStudioState();
}

class _ApprovedStudioState extends State<_ApprovedStudio> {
  int _tab = 0; // 0 content, 1 earnings
  String _statusFilter = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SessionState>().refreshFromApi();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final sales = session.sales;
    final firstName = session.displayName.trim().split(RegExp(r'\s+')).first;
    final filtered = session.drafts.where((draft) {
      if (_statusFilter == 'All') return true;
      if (_statusFilter == 'Draft') return draft.status == 'draft';
      if (_statusFilter == 'In review') return draft.status == 'submitted';
      if (_statusFilter == 'Live') return draft.status == 'live';
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudioBanner(
          creatorName: firstName.isEmpty ? 'Creator' : firstName,
          titleCount: session.drafts.length,
          liveCount: session.drafts.where((d) => d.status == 'live').length,
          onUpload: () => showStudioUploadFlow(context, session),
        ),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: [
            ButtonSegment(
              value: 0,
              label: Text('Content (${session.drafts.length})'),
              icon: const Icon(Icons.library_books_outlined, size: 18),
            ),
            ButtonSegment(
              value: 1,
              label: const Text('Earnings'),
              icon: const Icon(Icons.payments_outlined, size: 18),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (value) => setState(() => _tab = value.first),
        ),
        const SizedBox(height: 16),
        if (_tab == 0) ...[
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final label in ['All', 'Draft', 'In review', 'Live'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _statusFilter == label,
                      onSelected: (_) => setState(() => _statusFilter = label),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            _EmptyContent(
              apiReachable: session.apiReachable,
              onUpload: () => showStudioUploadFlow(context, session),
              onRefresh: () => session.refreshFromApi(),
            )
          else
            ...List.generate(
              (filtered.length / 2).ceil(),
              (row) {
                final left = filtered[row * 2];
                final rightIndex = row * 2 + 1;
                final right = rightIndex < filtered.length ? filtered[rightIndex] : null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _ContentCard(
                            draft: left,
                            marketCurrency: session.currencyCode,
                            onOpen: () => showStudioQuickEdit(context, session, left),
                            onFullEdit: () => showStudioUploadFlow(
                              context,
                              session,
                              existing: left,
                            ),
                            onParts: () async {
                              final draft = await session.draftForEdit(left);
                              if (!context.mounted) return;
                              await _manageParts(context, session, draft);
                            },
                            onDelete: left.status == 'live'
                                ? null
                                : () => session.deleteCreatorDraft(left.id),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: right == null
                              ? const SizedBox.shrink()
                              : _ContentCard(
                                  draft: right,
                                  marketCurrency: session.currencyCode,
                                  onOpen: () => showStudioQuickEdit(context, session, right),
                                  onFullEdit: () => showStudioUploadFlow(
                                    context,
                                    session,
                                    existing: right,
                                  ),
                                  onParts: () async {
                                    final draft = await session.draftForEdit(right);
                                    if (!context.mounted) return;
                                    await _manageParts(context, session, draft);
                                  },
                                  onDelete: right.status == 'live'
                                      ? null
                                      : () => session.deleteCreatorDraft(right.id),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          Text(
            'Ebooks create chapters from the uploaded file. Audiobooks and podcasts use tracks or episodes you add. Submit for review when ready.',
            style: TextStyle(fontSize: 12, height: 1.4, color: ListenColors.ink.withValues(alpha: 0.55)),
          ),
        ] else ...[
          _EarningsPanel(
            sales: sales,
            onRefresh: () => session.refreshSales(),
            onPayout: () => _showCashoutSheet(context, session, sales),
          ),
        ],
      ],
    );
  }



  Future<void> _showCashoutSheet(
    BuildContext context,
    SessionState session,
    SalesDashboard sales,
  ) async {
    if (sales.availableMinor < sales.policy.minPayoutMinor) {
      session.showNotice(
        'Available balance is below the minimum payout (${sales.money(sales.policy.minPayoutMinor)}).',
      );
      return;
    }

    var rail = 'mtn_momo';
    final destination = TextEditingController();
    final amount = TextEditingController(
      text: (sales.availableMinor / 100).toStringAsFixed(2),
    );
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Request payout', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    'Available ${sales.money(sales.availableMinor)}. A small fee is deducted on settlement. Admin confirms before funds leave Listen+.',
                    style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.62), height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount (${sales.currency})',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: rail,
                    decoration: const InputDecoration(
                      labelText: 'Payout method',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'mtn_momo', child: Text('MTN Mobile Money')),
                      DropdownMenuItem(value: 'airtel_money', child: Text('Airtel Money')),
                      DropdownMenuItem(value: 'bank', child: Text('Bank transfer')),
                    ],
                    onChanged: (value) => setModalState(() => rail = value ?? rail),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: destination,
                    keyboardType: rail == 'bank' ? TextInputType.text : TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: rail == 'bank' ? 'Bank account reference' : 'Mobile money number',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Submit payout request'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (submitted != true) {
      destination.dispose();
      amount.dispose();
      return;
    }

    final major = double.tryParse(amount.text.trim().replaceAll(',', '')) ?? 0;
    final amountMinor = (major * 100).round();
    final dest = destination.text.trim();
    destination.dispose();
    amount.dispose();

    if (amountMinor <= 0 || dest.isEmpty) {
      session.showNotice('Enter a valid amount and destination.');
      return;
    }

    await session.requestCashout(
      amountMinor: amountMinor,
      rail: rail,
      destination: dest,
    );
  }

  Future<void> _manageParts(
    BuildContext context,
    SessionState session,
    CreatorDraft draft,
  ) async {
    var chapters = List<ContentChapter>.from(draft.chapters);
    var episodes = List<ContentEpisode>.from(draft.episodes);

    Future<String?> persistPickedFile(String? sourcePath, String folder, String name) async {
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

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickEpisodeAudio(int index) async {
              try {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.any,
                  allowMultiple: false,
                  withData: false,
                );
                if (result == null || result.files.isEmpty) return;
                final file = result.files.first;
                final persisted = await persistPickedFile(file.path, 'episodes', file.name);
                final path = persisted ?? file.path;
                final probed = path == null ? null : await probeAudioDurationSec(path);
                setModalState(() {
                  episodes[index] = episodes[index].copyWith(
                    mediaName: file.name,
                    mediaPath: path,
                    durationSec: probed ?? episodes[index].durationSec,
                  );
                });
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not attach episode audio.')),
                );
              }
            }

            Future<void> useSampleEpisodeAudio(int index) async {
              final bytes = await rootBundle.load('assets/samples/sample_episode.wav');
              final dir = await getTemporaryDirectory();
              final name = 'episode_${index + 1}_sample.wav';
              final file = File('${dir.path}/$name');
              await file.writeAsBytes(bytes.buffer.asUint8List());
              final persisted = await persistPickedFile(file.path, 'episodes', name);
              final path = persisted ?? file.path;
              final probed = await probeAudioDurationSec(path);
              setModalState(() {
                episodes[index] = episodes[index].copyWith(
                  mediaName: name,
                  mediaPath: path,
                  durationSec: probed ?? 180,
                );
              });
            }

            Future<void> reextractEbookChapters() async {
              final path = draft.mediaPath;
              if (path == null || path.isEmpty || !File(path).existsSync()) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No ebook file on this draft. Re-open Upload and attach the file again.'),
                  ),
                );
                return;
              }
              final parsed = await const EbookChapterExtractor().extractFromPath(path);
              setModalState(() => chapters = parsed);
            }

            void addEpisode() {
              setModalState(() {
                episodes = [
                  ...episodes,
                  ContentEpisode(
                    id: 'ep-${DateTime.now().millisecondsSinceEpoch}',
                    title: draft.format == 'Podcast'
                        ? 'Episode ${episodes.length + 1}'
                        : 'Track ${episodes.length + 1}',
                    durationSec: 0,
                    sortOrder: episodes.length,
                    isSample: episodes.isEmpty,
                  ),
                ];
              });
            }

            final audioNoun = draft.format == 'Podcast' ? 'Episode' : 'Track';

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      draft.isDualFormat
                          ? 'Chapters & tracks'
                          : (draft.isEbook
                              ? 'Ebook chapters'
                              : (draft.format == 'Podcast' ? 'Episodes' : 'Tracks')),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      draft.title,
                      style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        children: [
                          if (draft.isEbook) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: ListenColors.leaf.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Text(
                                'Ebook chapters come from the uploaded file. You can rename them here or rebuild from the file.',
                                style: TextStyle(height: 1.35),
                              ),
                            ),
                            if (draft.isDualFormat)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('Ebook chapters', style: Theme.of(context).textTheme.titleMedium),
                              ),
                            ...chapters.asMap().entries.map((entry) {
                              final index = entry.key;
                              final chapter = entry.value;
                              return Card(
                                color: Colors.white,
                                elevation: 0,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      TextFormField(
                                        initialValue: chapter.title,
                                        decoration: InputDecoration(
                                          labelText: 'Chapter ${index + 1} title',
                                          border: const OutlineInputBorder(),
                                        ),
                                        onChanged: (value) {
                                          chapters[index] =
                                              chapters[index].copyWith(title: value);
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        chapter.body.trim().isEmpty
                                            ? 'Empty body'
                                            : (chapter.body.length > 180
                                                ? '${chapter.body.substring(0, 180).trim()}…'
                                                : chapter.body),
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.35,
                                          color: ListenColors.ink.withValues(alpha: 0.6),
                                        ),
                                      ),
                                      SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        title: const Text('Include in free sample'),
                                        subtitle: const Text('Read sample on the title page'),
                                        value: chapter.isSample,
                                        onChanged: (value) {
                                          setModalState(() {
                                            chapters[index] =
                                                chapters[index].copyWith(isSample: value);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            OutlinedButton.icon(
                              onPressed: reextractEbookChapters,
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text('Rebuild chapters from ebook file'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (draft.isAudioFormat) ...[
                            if (draft.isDualFormat)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  draft.format == 'Podcast' ? 'Episodes' : 'Audiobook tracks',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              )
                            else
                              Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: ListenColors.coral.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  draft.format == 'Podcast'
                                      ? 'Add podcast episodes manually — audio plus optional script and show notes.'
                                      : 'Add audiobook chapters manually as tracks — one audio file per part.',
                                  style: const TextStyle(height: 1.35),
                                ),
                              ),
                            ...episodes.asMap().entries.map((entry) {
                              final index = entry.key;
                              final episode = entry.value;
                              return Card(
                                color: Colors.white,
                                elevation: 0,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              initialValue: episode.title,
                                              decoration: InputDecoration(
                                                labelText: '$audioNoun title',
                                                border: const OutlineInputBorder(),
                                              ),
                                              onChanged: (value) {
                                                episodes[index] =
                                                    episodes[index].copyWith(title: value);
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () => setModalState(() {
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
                                        onPressed: () => pickEpisodeAudio(index),
                                        icon: const Icon(Icons.audio_file_outlined),
                                        label: Text(
                                          episode.mediaName == null
                                              ? 'Attach $audioNoun audio'
                                              : episode.mediaName!,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => useSampleEpisodeAudio(index),
                                        child: const Text('Use sample audio'),
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
                                      if (draft.format == 'Podcast') ...[
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          initialValue: episode.body ?? '',
                                          maxLines: 4,
                                          decoration: const InputDecoration(
                                            labelText: 'Episode content / script',
                                            border: OutlineInputBorder(),
                                            alignLabelWithHint: true,
                                          ),
                                          onChanged: (value) {
                                            episodes[index] =
                                                episodes[index].copyWith(body: value);
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          initialValue: episode.showNotes ?? '',
                                          maxLines: 2,
                                          decoration: const InputDecoration(
                                            labelText: 'Show notes (optional)',
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (value) {
                                            episodes[index] =
                                                episodes[index].copyWith(showNotes: value);
                                          },
                                        ),
                                      ],
                                      SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        title: const Text('Include in free sample'),
                                        subtitle: const Text('Listen to sample on the title page'),
                                        value: episode.isSample,
                                        onChanged: (value) {
                                          setModalState(() {
                                            episodes[index] =
                                                episodes[index].copyWith(isSample: value);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            OutlinedButton.icon(
                              onPressed: addEpisode,
                              icon: const Icon(Icons.add),
                              label: Text('Add ${audioNoun.toLowerCase()}'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Save parts'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == true) {
      await session.saveCreatorParts(
        draftId: draft.id,
        chapters: draft.isEbook ? chapters : const [],
        episodes: draft.isAudioFormat ? episodes : const [],
      );
    }
  }
}

class _StudioBanner extends StatelessWidget {
  const _StudioBanner({
    required this.creatorName,
    required this.titleCount,
    required this.liveCount,
    required this.onUpload,
  });

  final String creatorName;
  final int titleCount;
  final int liveCount;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.asset(
              'assets/images/quiet.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: ListenColors.leaf),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    ListenColors.ink.withValues(alpha: 0.82),
                    ListenColors.ink.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 18,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CREATOR STUDIO',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  creatorName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        height: 1.1,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$titleCount title${titleCount == 1 ? '' : 's'} · $liveCount live',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: ListenColors.coral,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onUpload,
                  icon: const Icon(Icons.add),
                  label: const Text('New upload'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyContent extends StatelessWidget {
  const _EmptyContent({
    required this.onUpload,
    required this.onRefresh,
    required this.apiReachable,
  });

  final VoidCallback onUpload;
  final VoidCallback onRefresh;
  final bool apiReachable;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            apiReachable ? 'No titles yet' : 'Can’t reach Listen+ right now',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            apiReachable
                ? 'Upload an ebook, audiobook, podcast, or ebook + audiobook, attach a cover, then add chapters and episode content.'
                : 'Your creator titles sync when Listen+ is reachable. Check your connection, then retry.',
            style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.62), height: 1.4),
          ),
          const SizedBox(height: 14),
          if (!apiReachable)
            FilledButton.tonal(onPressed: onRefresh, child: const Text('Retry sync'))
          else
            FilledButton.tonal(onPressed: onUpload, child: const Text('Start first upload')),
        ],
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.draft,
    required this.marketCurrency,
    required this.onOpen,
    required this.onFullEdit,
    required this.onParts,
    this.onDelete,
  });

  final CreatorDraft draft;
  final String marketCurrency;
  final VoidCallback onOpen;
  final VoidCallback onFullEdit;
  final VoidCallback onParts;
  final VoidCallback? onDelete;

  String get _price {
    for (final quote in draft.prices) {
      if (quote.currency == marketCurrency) return quote.label;
    }
    return draft.prices.isEmpty ? 'No price' : draft.prices.first.label;
  }

  Color get _statusColor => switch (draft.status) {
        'live' => ListenColors.leaf,
        'submitted' => ListenColors.coral,
        _ => ListenColors.ink.withValues(alpha: 0.55),
      };

  String get _statusLabel => switch (draft.status) {
        'live' => 'Live',
        'submitted' => 'In review',
        _ => draft.id.startsWith('local-') ? 'On device' : 'Draft',
      };

  String get _partsActionLabel {
    if (draft.isDualFormat) {
      return 'Parts (${draft.chapters.length} ch · ${draft.episodes.length} tracks)';
    }
    if (draft.isEbook) {
      return draft.chapters.isEmpty
          ? 'Rebuild chapters'
          : 'Chapters (${draft.chapters.length})';
    }
    if (draft.format == 'Podcast') {
      return draft.episodes.isEmpty
          ? 'Add episodes'
          : 'Episodes (${draft.episodes.length})';
    }
    return draft.episodes.isEmpty
        ? 'Add tracks'
        : 'Tracks (${draft.episodes.length})';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: draft.coverImagePath != null &&
                              File(draft.coverImagePath!).existsSync()
                          ? Image.file(File(draft.coverImagePath!), fit: BoxFit.cover)
                          : ColoredBox(
                              color: ListenColors.mist,
                              child: Icon(
                                draft.isDualFormat
                                    ? Icons.auto_stories_outlined
                                    : (draft.isEbook
                                        ? Icons.menu_book_outlined
                                        : Icons.headphones_outlined),
                                color: ListenColors.leaf,
                                size: 18,
                              ),
                            ),
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      switch (value) {
                        case 'quick':
                          onOpen();
                        case 'full':
                          onFullEdit();
                        case 'parts':
                          onParts();
                        case 'delete':
                          onDelete?.call();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'quick', child: Text('Quick edit · title & cover')),
                      const PopupMenuItem(value: 'full', child: Text('Full editor')),
                      const PopupMenuItem(value: 'parts', child: Text('Manage parts & samples')),
                      if (onDelete != null)
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                draft.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.25, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                draft.format,
                style: TextStyle(fontSize: 11, color: ListenColors.ink.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 2),
              Text(
                '$_price · ${draft.partsSummary}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: ListenColors.ink.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              const SizedBox(height: 10),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                onPressed: onParts,
                child: Text(_partsActionLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EarningsPanel extends StatelessWidget {
  const _EarningsPanel({
    required this.sales,
    required this.onRefresh,
    required this.onPayout,
  });

  final SalesDashboard sales;
  final VoidCallback onRefresh;
  final VoidCallback onPayout;

  @override
  Widget build(BuildContext context) {
    final policy = sales.policy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ListenColors.leaf,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Estimated earnings this month',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onRefresh,
                    tooltip: 'Refresh earnings',
                    color: Colors.white,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
              Text(
                sales.money(sales.grossSalesMinor),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                'Available ${sales.money(sales.availableMinor)} · Pending ${sales.money(sales.pendingMinor)}'
                '${sales.paidOutMinor > 0 ? ' · Paid out ${sales.money(sales.paidOutMinor)}' : ''}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12),
              ),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: ListenColors.leaf,
                ),
                onPressed: onPayout,
                child: Text(
                  sales.availableMinor >= policy.minPayoutMinor
                      ? 'Request payout · ${sales.money(sales.availableMinor)}'
                      : 'Min payout ${sales.money(policy.minPayoutMinor)}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('By format', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            _MiniStat(label: 'Ebooks', value: sales.money(sales.byFormat.ebookMinor)),
            const SizedBox(width: 8),
            _MiniStat(label: 'Audiobooks', value: sales.money(sales.byFormat.audiobookMinor)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _MiniStat(label: 'Podcasts', value: sales.money(sales.byFormat.podcastMinor)),
            const SizedBox(width: 8),
            _MiniStat(label: 'Advertising', value: sales.money(sales.byFormat.advertisingMinor)),
          ],
        ),
        const SizedBox(height: 16),
        Text('How you earn', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            '• Purchases (ebook, audiobook, premium podcast) → ${policy.purchaseSplitLabel} of net receipts (ledger)\n'
            '• Subscription listening/reading → ${policy.subscriptionSplitLabel} of net sub revenue, shared by qualified consumption (ebook 30% / audio 45% / podcast 25% of the creator pool)\n'
            '• Free with advertising → ${policy.advertisingSplitLabel} of verified AdMob completions (client reward + optional SSV), settled on the shared ledger\n'
            '• Opens/views alone do not pay — only verified reading, listening minutes, completed purchases or monetised ads.',
            style: TextStyle(
              height: 1.45,
              fontSize: 12.5,
              color: ListenColors.ink.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('Recent credits', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (sales.sales.isEmpty)
          Text(
            'Credits appear after verified purchases, subscription-pool allocation, or completed ad events.',
            style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.55)),
          )
        else
          ...sales.sales.take(8).map(
                (sale) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sale.titleName, style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              '${sale.streamLabel} · ${sale.format} · ${sale.at.split('T').first}',
                              style: TextStyle(
                                fontSize: 12,
                                color: ListenColors.ink.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${sale.currency} ${(sale.creatorShareMinor / 100).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: ListenColors.ink.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
