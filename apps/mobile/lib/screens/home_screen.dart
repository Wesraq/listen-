import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/catalogue.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../widgets/page_intro.dart';
import '../widgets/status_views.dart';
import '../widgets/title_card.dart';
import 'browse_screen.dart';
import 'title_flow.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String format = 'All';
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await context.read<SessionState>().refreshFromApi();
      if (!mounted) return;
      setState(() => loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'We couldn’t load discovery right now.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final filtered = titles.where((title) {
      if (format == 'All') return true;
      if (title.formatLabel == format) return true;
      // Dual titles appear under both Ebook and Audiobook filters.
      if (title.isDualFormat && (format == 'Ebook' || format == 'Audiobook')) {
        return true;
      }
      return false;
    }).toList()
      ..sort((a, b) {
        final aMatch = session.interests.contains(a.category) ? 0 : 1;
        final bMatch = session.interests.contains(b.category) ? 0 : 1;
        return aMatch.compareTo(bMatch);
      });
    final continueItems = session.continueTitles(limit: 6);
    final fallbackContinue = continueItems.isNotEmpty
        ? continueItems
        : session.titlesForIds(session.libraryOwnedIds).take(2).toList();
    final featured = collections.first;
    final firstName = session.displayName.trim().split(RegExp(r'\s+')).first;

    if (loading) return const CatalogueSkeleton();
    if (error != null) {
      return ErrorStateView(message: error!, onRetry: _load);
    }

    return RefreshIndicator(
      onRefresh: () async {
        await session.refreshFromApi();
        if (mounted) setState(() {});
      },
      child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: PageIntro(
            title: session.isGuest || firstName.isEmpty || firstName == 'Guest'
                ? 'Discover your next story'
                : 'Welcome back, $firstName',
            text:
                'Books, voices and ideas from around the world — ${session.marketChip}.',
          ),
        ),
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
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Image.asset(featured.imageAsset, fit: BoxFit.cover),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    top: 18,
                    right: 40,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'FEATURED COLLECTION',
                          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
                        ),
                        const SizedBox(height: 8),
                        Text(featured.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
                        const SizedBox(height: 6),
                        Text(
                          featured.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, height: 1.35),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: ListenColors.coral),
                          onPressed: () => openCollection(context, featured),
                          child: const Text('Open collection'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (fallbackContinue.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Continue', style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 96,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                scrollDirection: Axis.horizontal,
                itemCount: fallbackContinue.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final title = fallbackContinue[index];
                  return InkWell(
                    onTap: () => openContinueExperience(context, title),
                    borderRadius: BorderRadius.circular(14),
                    child: Ink(
                      width: 280,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(title.imageAsset, width: 44, height: 64, fit: BoxFit.cover),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(title.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(
                                  session.continueSubtitle(title),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.55), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            title.isAudio ? Icons.headphones : Icons.menu_book,
                            color: ListenColors.leaf,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Browse categories',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 108,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final category = categories[index];
                return InkWell(
                  onTap: () => openCategory(context, category),
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    width: 170,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                          category.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, height: 1.3, color: ListenColors.ink.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Collections', style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 150,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              scrollDirection: Axis.horizontal,
              itemCount: collections.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final collection = collections[index];
                return InkWell(
                  onTap: () => openCollection(context, collection),
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    width: 240,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      image: DecorationImage(
                        image: AssetImage(collection.imageAsset),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.35), BlendMode.darken),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(collection.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(
                            collection.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('For you', style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              child: EmptyStateView(
                icon: titles.isEmpty ? Icons.menu_book_outlined : Icons.search_off,
                title: titles.isEmpty
                    ? 'No titles yet'
                    : 'Nothing in this format',
                message: titles.isEmpty
                    ? 'Pull to refresh, or publish from Studio to fill your catalogue.'
                    : 'Try another format filter above to keep exploring.',
              ),
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
                  final title = filtered[index];
                  return TitleCard(title: title, onOpen: () => openTitleFlow(context, title));
                },
                childCount: filtered.length,
              ),
            ),
          ),
      ],
    ),
    );
  }
}
