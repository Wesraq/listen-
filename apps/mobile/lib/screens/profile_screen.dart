import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/catalogue.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../widgets/page_intro.dart';
import '../widgets/title_cover.dart';
import 'support_legal.dart';
import 'title_flow.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  TextEditingController? nameController;
  String language = 'English';
  bool notifications = true;
  bool primed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (primed) return;
    final session = context.read<SessionState>();
    nameController = TextEditingController(text: session.displayName);
    language = session.language;
    notifications = session.notificationsEnabled;
    primed = true;
  }

  @override
  void dispose() {
    nameController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final purchases = session.titlesForIds(session.libraryOwnedIds);
    final controller = nameController!;

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        const PageIntro(
          title: 'Your profile',
          text: 'Manage how you show up on Listen+.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 28, child: Text(session.avatarLetters)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.displayName.isEmpty ? 'Listener' : session.displayName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          session.isGuest
                              ? 'Browsing as guest'
                              : session.contact.isEmpty
                                  ? 'Signed in'
                                  : session.contact,
                        ),
                        Text(
                          switch (session.creatorState) {
                            CreatorApplicationState.newApplicant => 'Listener account',
                            CreatorApplicationState.pending => 'Creator application under review',
                            CreatorApplicationState.approved => 'Creator · Studio unlocked',
                          },
                          style: TextStyle(fontSize: 12, color: ListenColors.ink.withValues(alpha: 0.55)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (session.isGuest) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => session.resetOnboardingForDemo(),
                  child: const Text('Create account / sign in'),
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                enabled: !session.isGuest,
                decoration: const InputDecoration(labelText: 'Display name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Country & currency',
                  helperText: 'Prices and catalogue availability follow your market.',
                  border: OutlineInputBorder(),
                ),
                child: Text(session.marketChip),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: language,
                decoration: const InputDecoration(labelText: 'Preferred language', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'English', child: Text('English')),
                  DropdownMenuItem(value: 'Bemba', child: Text('Bemba')),
                  DropdownMenuItem(value: 'Nyanja', child: Text('Nyanja')),
                ],
                onChanged: session.isGuest ? null : (value) => setState(() => language = value ?? language),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notifications'),
                subtitle: const Text('New titles, library reminders and order updates'),
                value: notifications,
                onChanged: session.isGuest ? null : (value) => setState(() => notifications = value),
              ),
              if (session.interests.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Interests', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final interest in session.interests) Chip(label: Text(interest))],
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: session.isGuest
                    ? null
                    : () => session.updateProfile(
                          name: controller.text,
                          languageValue: language,
                          notifications: notifications,
                        ),
                child: const Text('Save preferences'),
              ),
              if (session.isSignedIn) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => session.signOut(),
                  child: const Text('Sign out'),
                ),
                TextButton(
                  onPressed: () => session.resetOnboardingForDemo(),
                  child: const Text('Replay onboarding'),
                ),
              ],
              const SizedBox(height: 24),
              Text('Purchase history', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (purchases.isEmpty)
                Text(
                  'No purchases yet. Titles you buy will show up here.',
                  style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.6)),
                )
              else
                ...purchases.map(
                  (title) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: TitleCover(
                        session: session,
                        title: title,
                        width: 40,
                        height: 56,
                      ),
                    ),
                    title: Text(title.name),
                    subtitle: Text(
                      '${title.formatLabel} · ${title.isFree ? 'Free' : '${money(title.priceMinor)} · Purchased'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openTitleFlow(context, title),
                  ),
                ),
              const SizedBox(height: 24),
              Text('Support & legal', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.help_outline),
                title: const Text('Help & support'),
                onTap: () => openHelpSupport(context),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: const Text('Terms of Service'),
                onTap: () => openLegalDoc(context, LegalDoc.terms),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy Policy'),
                onTap: () => openLegalDoc(context, LegalDoc.privacy),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.handshake_outlined),
                title: const Text('Creator Agreement'),
                onTap: () => openLegalDoc(context, LegalDoc.creatorAgreement),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Refund Policy'),
                onTap: () => openLegalDoc(context, LegalDoc.refund),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  await session.refreshFromApi();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        session.apiReachable
                            ? 'Library and catalogue updated.'
                            : 'Could not reach Listen+ right now. Your library on this device is unchanged.',
                      ),
                    ),
                  );
                },
                child: const Text('Refresh library'),
              ),
              const SizedBox(height: 8),
              Text(
                session.apiReachable
                    ? 'Connected to Listen+.'
                    : 'Working offline — changes sync when you are back online.',
                style: TextStyle(fontSize: 12, height: 1.4, color: ListenColors.ink.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
