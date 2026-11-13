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
          'Listen+ is a prototype marketplace for reading and listening. These Terms summarise intended commercial rules: accounts must be accurate, purchases are digital entitlements, and abuse or rights infringement can lead to suspension.\n\nThis copy is illustrative for the MVP prototype and must be replaced by counsel-approved legal text before public commercial launch.',
        LegalDoc.privacy =>
          'Listen+ processes account details, market preferences, purchase records and reading/listening progress to operate the service. Prototype sessions store data locally on device and in Firebase Auth for sign-in.\n\nBefore launch, publish a counsel-reviewed Privacy Policy covering Zambia obligations, retention and user rights.',
        LegalDoc.creatorAgreement =>
          'Creators warrant they hold rights to upload and sell their content in selected territories and formats. Listen+ may review, approve, reject or suspend submissions. Earnings and payouts shown in Studio are illustrative until ledger and payout verification ship.\n\nReplace with the signed Creator Agreement before accepting real uploads.',
        LegalDoc.refund =>
          'Digital content refunds follow market policy once counsel confirms consumer rules for Zambia. In this prototype, failed simulated checkouts never charge money and successful simulations remain reversible only via demo reset.\n\nDefine refund windows, partial refunds and entitlement revocation before launch.',
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
            'Prototype policy text',
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
            title: Text('Why is checkout simulated?'),
            subtitle: Text('Real Zambia payment providers are verified by the backend before entitlements are granted.'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Where is my library?'),
            subtitle: Text('Open the Library tab for owned and saved titles. Continue from Home resumes progress.'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('How do creators get paid?'),
            subtitle: Text('Studio shows illustrative earnings. Finance approval and settlement evidence are admin workflows.'),
          ),
          SizedBox(height: 20),
          Text('Contact', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          SizedBox(height: 8),
          Text(
            'For the prototype, use Profile → Help to review guidance. Transaction issues will route through support once the API and admin console are live.',
            style: TextStyle(height: 1.45),
          ),
        ],
      ),
    );
  }
}
