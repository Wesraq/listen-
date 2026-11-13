import 'package:flutter_test/flutter_test.dart';
import 'package:listen_plus/app.dart';
import 'package:listen_plus/data/session_store.dart';
import 'package:listen_plus/services/auth_service.dart';
import 'package:listen_plus/state/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Listen+ starts on welcome onboarding', (tester) async {
    await tester.pumpWidget(const ListenPlusApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('A world of stories'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Browse catalogue as guest'), findsOneWidget);
  });

  testWidgets('Guest can reach home shell', (tester) async {
    await tester.pumpWidget(const ListenPlusApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Browse catalogue as guest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    // Home shows a short discovery loading skeleton first.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsWidgets);
    expect(find.textContaining('Discover your next story'), findsOneWidget);
    expect(find.text('Zambezi Evenings'), findsOneWidget);
  });

  test('Session snapshot round-trips through store', () async {
    final store = SessionStore();
    await store.save(
      const SessionSnapshot(
        onboardingComplete: true,
        isSignedIn: true,
        displayName: 'Tendai M.',
        contact: 'tendai@example.com',
        marketCode: 'ZM',
        marketLabel: 'Zambia',
        currencyCode: 'ZMW',
        language: 'English',
        notificationsEnabled: true,
        interests: ['Fiction'],
        owned: ['jacaranda'],
        saved: ['quiet'],
        creatorState: 'approved',
        drafts: ['Morning Stories'],
      ),
    );

    final session = SessionState(store: store, authService: NoopAuthService());
    await session.hydrate();

    expect(session.ready, isTrue);
    expect(session.onboardingComplete, isTrue);
    // Without an active Firebase session, persisted "signed in" falls back to guest.
    expect(session.isSignedIn, isFalse);
    expect(session.displayName, 'Tendai M.');
    expect(session.owned, contains('jacaranda'));
    expect(session.saved, contains('quiet'));
    expect(session.creatorState, CreatorApplicationState.approved);
  });
}
