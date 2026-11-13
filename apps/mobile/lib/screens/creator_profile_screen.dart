import 'package:flutter/material.dart';

import '../data/catalogue.dart';
import '../theme/app_theme.dart';
import '../widgets/title_card.dart';
import 'title_flow.dart';

Future<void> openCreatorProfile(BuildContext context, String authorName) {
  final creator = creatorByName(authorName);
  if (creator == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No public creator profile for $authorName yet.')),
    );
    return Future.value();
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => CreatorProfileScreen(creator: creator)),
  );
}

class CreatorProfileScreen extends StatelessWidget {
  const CreatorProfileScreen({super.key, required this.creator});

  final CreatorProfile creator;

  @override
  Widget build(BuildContext context) {
    final works = creator.works;
    return Scaffold(
      appBar: AppBar(title: const Text('Creator')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(creator.name, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(creator.bio, style: TextStyle(height: 1.45, color: ListenColors.ink.withValues(alpha: 0.75))),
                  const SizedBox(height: 12),
                  Text(
                    'Browse their titles below. Following creators is coming soon.',
                    style: TextStyle(fontSize: 12, color: ListenColors.ink.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 20),
                  Text('Titles', style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 18,
                crossAxisSpacing: 14,
                childAspectRatio: 0.58,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final title = works[index];
                  return TitleCard(title: title, onOpen: () => openTitleFlow(context, title));
                },
                childCount: works.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
