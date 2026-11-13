# Listen+ mobile

Native Android and iOS client for Listen+, built with Flutter.

This is the primary consumer and creator experience per the Listen+ PRD / Technical System Design / UI-UX specification.

## Firebase

iOS is configured for Firebase project `listenplus-d9188`:

- `ios/Runner/GoogleService-Info.plist`
- Bundle ID: `io.listen.listen`
- `lib/firebase_options.dart`
- Keychain Sharing entitlements for Auth

**Required:** Firebase Console → Authentication → Sign-in method → enable **Email/Password**.

If create-account shows `internal-error`, enable Email/Password, then re-download `GoogleService-Info.plist` for iOS app `io.listen.listen` and replace `ios/Runner/GoogleService-Info.plist`.

Android still needs `google-services.json` from the Firebase console (and matching `applicationId`).

## Run

```sh
cd apps/mobile
flutter pub get
flutter run
```

## Product shell

Bottom navigation (5 destinations):

1. Home
2. Search
3. Library
4. Studio
5. Profile

Title detail, checkout, reader and player are contextual flows — not permanent tabs.

Sample reader supports chapters, resume, bookmarks and day/sepia/night themes. Sample player supports seek, speed and chapter tracks. Progress persists locally with the session.

Catalogue and library entitlements sync from `apps/api` when reachable (`http://127.0.0.1:3001/v1` on the iOS simulator). Checkout remains a simulated UI — production must verify payments on the backend before granting access.

```sh
# Terminal A
cd apps/api && npm run start:dev

# Terminal B
cd apps/mobile && flutter run
```
