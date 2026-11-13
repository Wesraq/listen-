import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'screens/player_sheet.dart';
import 'screens/profile_screen.dart';
import 'screens/search_screen.dart';
import 'screens/studio_screen.dart';
import 'state/session.dart';
import 'theme/app_theme.dart';
import 'widgets/title_cover.dart';

class ListenPlusApp extends StatelessWidget {
  const ListenPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SessionState()..hydrate(),
      child: MaterialApp(
        title: 'Listen+',
        debugShowCheckedModeBanner: false,
        theme: buildListenTheme(),
        home: const RootGate(),
      ),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    if (!session.ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return session.onboardingComplete ? const AppShell() : const OnboardingFlow();
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  static const destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.search), selectedIcon: Icon(Icons.search), label: 'Search'),
    NavigationDestination(icon: Icon(Icons.library_books_outlined), selectedIcon: Icon(Icons.library_books), label: 'Library'),
    NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Studio'),
    NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();

    if (session.notice.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || session.notice.isEmpty) return;
        final message = session.notice;
        session.clearNotice();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: RichText(
          text: TextSpan(
            style: Theme.of(context).appBarTheme.titleTextStyle,
            children: const [
              TextSpan(text: 'listen'),
              TextSpan(text: '+', style: TextStyle(color: ListenColors.coral)),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                session.marketChip,
                style: TextStyle(fontSize: 12, color: ListenColors.ink.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => session.showNotice(
              session.notificationsEnabled
                  ? 'You’re all caught up. Your next great story is waiting.'
                  : 'Notifications are off for this session.',
            ),
            icon: const Badge(child: Icon(Icons.notifications_none)),
          ),
        ],
      ),
      body: IndexedStack(
        index: index,
        children: [
          const HomeScreen(),
          const SearchScreen(),
          LibraryScreen(onDiscover: () => setState(() => index = 1)),
          const StudioScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: destinations,
      ),
      bottomSheet: session.nowPlaying == null
          ? null
          : Material(
              elevation: 8,
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: InkWell(
                  onTap: () => openPlayerSheet(context),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (session.nowPlayingTrack != null)
                        LinearProgressIndicator(
                          value: session.nowPlayingTrack!.durationSec == 0
                              ? 0
                              : (session.playbackPositionSec / session.nowPlayingTrack!.durationSec)
                                  .clamp(0.0, 1.0),
                          minHeight: 2,
                          backgroundColor: ListenColors.sand,
                        ),
                      ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: TitleCover(
                            session: session,
                            title: session.nowPlaying!,
                            width: 40,
                            height: 52,
                          ),
                        ),
                        title: Text(session.nowPlaying!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          session.nowPlayingTrack == null
                              ? session.nowPlaying!.author
                              : '${session.nowPlayingTrack!.title} · ${session.playbackSpeed}x',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: session.togglePlay,
                              icon: Icon(session.playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                            ),
                            IconButton(
                              onPressed: session.stopPlayback,
                              icon: const Icon(Icons.close),
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
