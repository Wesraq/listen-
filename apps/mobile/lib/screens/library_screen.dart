import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/catalogue.dart';
import '../state/session.dart';
import '../widgets/page_intro.dart';
import '../widgets/status_views.dart';
import '../widgets/title_card.dart';
import 'title_flow.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.onDiscover});

  final VoidCallback? onDiscover;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int tab = 0; // 0 owned, 1 saved, 2 downloads stub
  String format = 'All';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final downloadIds = session.downloads.map((d) => d.titleId).toSet();
    final ids = switch (tab) {
      0 => session.owned,
      1 => session.saved,
      _ => downloadIds,
    };
    final items = titles.where((title) {
      if (!ids.contains(title.id)) return false;
      if (format == 'All') return true;
      if (title.formatLabel == format) return true;
      if (title.isDualFormat && (format == 'Ebook' || format == 'Audiobook')) {
        return true;
      }
      return false;
    }).toList();

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: PageIntro(
            title: 'Your library',
            text: 'A little escape, always within reach.',
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text('Owned (${session.owned.length})')),
                ButtonSegment(value: 1, label: Text('Saved (${session.saved.length})')),
                ButtonSegment(value: 2, label: Text('Downloads (${session.downloads.length})')),
              ],
              selected: {tab},
              onSelectionChanged: (value) => setState(() => tab = value.first),
            ),
          ),
        ),
        if (tab != 2) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: ['All', 'Ebook', 'Audiobook', 'Podcast']
                    .map(
                      (label) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label == 'All' ? 'All formats' : label),
                          selected: format == label,
                          onSelected: (_) => setState(() => format = label),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        if (tab == 2 && items.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateView(
              icon: Icons.download_outlined,
              title: 'Nothing downloaded',
              message:
                  'Open a title you own and tap Download for offline EPUB chapters or audio cache.',
            ),
          )
        else if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateView(
              icon: tab == 0 ? Icons.library_books_outlined : Icons.bookmark_border,
              title: tab == 0 ? 'Nothing owned yet' : 'Nothing saved yet',
              message: tab == 0
                  ? 'Library shows titles you own — purchases, free unlocks, and your own published Studio titles. Browse the catalogue on Home or Search, then buy or save.'
                  : 'Save a title from Home or Search to find it later.',
              actionLabel: 'Discover stories',
              onAction: widget.onDiscover,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 18,
                crossAxisSpacing: 14,
                childAspectRatio: 0.58,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final title = items[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: TitleCard(
                          title: title,
                          onOpen: () => openContinueExperience(context, title),
                        ),
                      ),
                      if (tab == 2)
                        TextButton(
                          onPressed: () => session.removeDownload(title.id),
                          child: const Text('Remove offline'),
                        ),
                    ],
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
      ],
    );
  }
}
