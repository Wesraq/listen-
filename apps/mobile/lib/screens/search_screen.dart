import 'package:flutter/material.dart';

import '../data/catalogue.dart';
import '../widgets/page_intro.dart';
import '../widgets/status_views.dart';
import '../widgets/title_card.dart';
import 'browse_screen.dart';
import 'title_flow.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String query = '';
  String format = 'All';
  bool freeOnly = false;
  final recent = <String>[];

  static const suggestions = [
    'Jacaranda',
    'quiet becoming',
    'Independent voices',
    'Fiction',
    'Personal growth',
    'Zambia',
  ];

  void _commitSearch(String value) {
    final trimmed = value.trim();
    setState(() {
      query = trimmed;
      if (trimmed.isNotEmpty) {
        recent.remove(trimmed);
        recent.insert(0, trimmed);
        if (recent.length > 6) recent.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final found = titles.where((title) {
      final haystack = '${title.name} ${title.author} ${title.category}'.toLowerCase();
      final matchesQuery = query.isEmpty || haystack.contains(query.toLowerCase());
      final matchesFormat = format == 'All' ||
          title.formatLabel == format ||
          (title.isDualFormat && (format == 'Ebook' || format == 'Audiobook'));
      final matchesPrice = !freeOnly || title.isFree;
      return matchesQuery && matchesFormat && matchesPrice;
    }).toList();

    final showResults = query.isNotEmpty || freeOnly || format != 'All';

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: PageIntro(
            title: 'Find your next story',
            text: 'Books, voices and ideas from around the world.',
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (value) => setState(() => query = value),
              onSubmitted: _commitSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search titles, creators or categories',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                ...['All', 'Ebook', 'Audiobook', 'Podcast'].map(
                  (label) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label == 'All' ? 'All formats' : label),
                      selected: format == label,
                      onSelected: (_) => setState(() => format = label),
                    ),
                  ),
                ),
                FilterChip(
                  label: const Text('Free'),
                  selected: freeOnly,
                  onSelected: (value) => setState(() => freeOnly = value),
                ),
              ],
            ),
          ),
        ),
        if (!showResults) ...[
          if (recent.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Recent searches', style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final term in recent)
                      ActionChip(
                        label: Text(term),
                        onPressed: () => _commitSearch(term),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Suggested', style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final term in suggestions)
                    ActionChip(
                      label: Text(term),
                      onPressed: () => _commitSearch(term),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Popular categories', style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            sliver: SliverList.separated(
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final category = categories[index];
                return ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  tileColor: Colors.white,
                  title: Text(category.name),
                  subtitle: Text(category.description),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openCategory(context, category),
                );
              },
            ),
          ),
        ] else if (found.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateView(
              icon: Icons.search_off,
              title: 'No titles matched',
              message: query.isEmpty
                  ? 'Try a search or open a popular category.'
                  : 'No sample titles matched “$query”. Try another word or clear filters.',
              actionLabel: freeOnly || format != 'All' ? 'Clear filters' : null,
              onAction: freeOnly || format != 'All'
                  ? () => setState(() {
                        freeOnly = false;
                        format = 'All';
                      })
                  : null,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 18,
                crossAxisSpacing: 14,
                childAspectRatio: 0.58,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final title = found[index];
                  return TitleCard(title: title, onOpen: () => openTitleFlow(context, title));
                },
                childCount: found.length,
              ),
            ),
          ),
      ],
    );
  }
}
