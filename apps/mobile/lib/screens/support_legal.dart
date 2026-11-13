import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum LegalDoc {
  terms,
  privacy,
  creatorAgreement,
  refund,
}

extension LegalDocX on LegalDoc {
  String get title => switch (this) {
        LegalDoc.terms => 'Terms of Service',
        LegalDoc.privacy => 'Privacy Policy',
        LegalDoc.creatorAgreement => 'Creator Agreement',
        LegalDoc.refund => 'Refund Policy',
      };

  String get body => switch (this) {
        LegalDoc.terms =>
          'Welcome to Listen+. By using the service you agree to keep your account details accurate, respect other listeners and creators, and only use content you’re entitled to access.\n\nPurchases grant digital access in your library. Abuse, fraud, or rights infringement can lead to suspension. Full counsel-approved Terms will replace this summary before public commercial launch.',
        LegalDoc.privacy =>
          'Listen+ uses account details, market preferences, purchase records, and reading or listening progress to run the service. Sign-in is handled with Firebase Auth; preferences may also be stored on your device.\n\nA counsel-reviewed Privacy Policy covering Zambia obligations, retention, and your rights will replace this summary before launch.',
        LegalDoc.creatorAgreement =>
          'Creators confirm they hold the rights to upload and sell their content in the selected territories and formats. Listen+ may review, approve, reject, or suspend submissions.\n\nEarnings and payouts shown in Studio are estimates until payout verification is live. A signed Creator Agreement will replace this summary before real commercial uploads.',
        LegalDoc.refund =>
          'Digital purchases are generally final once access is granted. If a payment fails, nothing is charged and your library is unchanged.\n\nDetailed refund windows and consumer rules for Zambia will be confirmed with counsel before launch.',
      };
}

Future<void> openLegalDoc(BuildContext context, LegalDoc doc) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LegalDocScreen(doc: doc)),
  );
}

Future<void> openHelpSupport(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const HelpSupportScreen()),
  );
}

class LegalDocScreen extends StatelessWidget {
  const LegalDocScreen({super.key, required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            'Summary for early Listen+',
            style: TextStyle(color: ListenColors.coral, fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(doc.body, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }
}

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: const [
          Text('Frequently asked', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('When do payments go live?'),
            subtitle: Text('Checkout is ready for local testing now. Live Zambia payment providers unlock once verification is complete.'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Where is my library?'),
            subtitle: Text('Open the Library tab for owned and saved titles. Home resumes where you left off.'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('How do creators get paid?'),
            subtitle: Text('Studio shows your estimated earnings. Payouts are reviewed before money is sent.'),
          ),
          SizedBox(height: 20),
          Text('Contact', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          SizedBox(height: 8),
          Text(
            'Need help? Start here in Profile → Help & support. Transaction support expands as payments go live.',
            style: TextStyle(height: 1.45),
          ),
        ],
      ),
    );
  }
}
