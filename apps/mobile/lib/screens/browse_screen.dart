import 'package:flutter/material.dart';

import '../data/catalogue.dart';
import '../theme/app_theme.dart';
import '../widgets/status_views.dart';
import '../widgets/title_card.dart';
import 'title_flow.dart';

Future<void> openCategory(BuildContext context, CategoryInfo category) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => CategoryScreen(category: category)),
  );
}

Future<void> openCollection(BuildContext context, CollectionInfo collection) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => CollectionScreen(collection: collection)),
  );
}

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key, required this.category});

  final CategoryInfo category;

  @override
  Widget build(BuildContext context) {
    final items = titlesInCategory(category.name);

    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      body: items.isEmpty
          ? EmptyStateView(
              icon: Icons.menu_book_outlined,
              title: 'No titles yet',
              message: 'This category has no sample titles in the prototype catalogue.',
              actionLabel: 'Go back',
              onAction: () => Navigator.pop(context),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Text(
                      category.description,
                      style: TextStyle(height: 1.4, color: ListenColors.ink.withValues(alpha: 0.65)),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
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
                        return TitleCard(title: title, onOpen: () => openTitleFlow(context, title));
                      },
                      childCount: items.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key, required this.collection});

  final CollectionInfo collection;

  @override
  Widget build(BuildContext context) {
    final items = collection.items;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(collection.name),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(collection.imageAsset, fit: BoxFit.cover),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                collection.description,
                style: TextStyle(height: 1.4, color: ListenColors.ink.withValues(alpha: 0.7)),
              ),
            ),
          ),
          if (items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateView(
                icon: Icons.collections_bookmark_outlined,
                title: 'Collection unavailable',
                message: 'This editorial collection has no titles yet.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
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
                    return TitleCard(title: title, onOpen: () => openTitleFlow(context, title));
                  },
                  childCount: items.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
