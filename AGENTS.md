## Product platforms

- **Primary client:** Flutter native apps for Android and iOS (`apps/mobile`).
- **Consumer web at launch:** out of MVP scope per PRD. The existing TanStack UI at the repo root is a **web prototype / UI reference** only — keep it usable, but do not treat it as the production consumer app.
- **Admin web:** prototype ops console at `apps/admin-web` (seeded local admin). Not a consumer surface.
- **Backend:** TypeScript API modular monolith at `apps/api` (NestJS-style). Catalogue + prototype library/entitlements are live in-memory; PostgreSQL persistence and Firebase Admin token verification are next. Mobile clients are untrusted for payments and entitlements.

## Prototype architecture (current stage)

- Keep shared sample catalogue and in-memory journey state for the active prototype (Flutter session and/or web prototype module).
- Flutter onboarding covers welcome, create account / sign in / guest, market+language, and optional interests before the main shell.
- Primary destinations: Home, Search, Library, Studio, Profile.
- Title detail, checkout, reader and player are contextual experiences (sheets/routes/dialogs), not bottom-nav tabs.
- Auth uses Firebase on mobile; catalogue/library sync to `apps/api` when reachable (dev Bearer). Checkout remains simulated until payment webhooks verify entitlements.
- Firebase iOS is configured (`apps/mobile/ios/Runner/GoogleService-Info.plist`, bundle `io.listen.listen`). Mobile email auth uses FlutterFire (`firebase_auth`). Enable Email/Password in the Firebase console. Do not commit Android `google-services.json` until provided.
- Never connect sample checkout or payout states to real financial services; provider verification and commercial policy require a separate backend implementation.
- Free-with-ads titles use Google AdMob rewarded interstitials (`google_mobile_ads`). Builds default to Google test app/unit IDs; ship production IDs via Info.plist / AndroidManifest App IDs plus `--dart-define=ADMOB_*=…` and `ADMOB_USE_TEST_ADS=false`. Creator advertising ledger credits only after a real reward callback (and optionally AdMob SSV at `/v1/ads/ssv`). AdMob pays the publisher account — creator splits are internal ledger, not direct AdMob payouts.
- Do not put secret values in the repo.
- Do not edit auto-generated files such as `src/routeTree.gen.ts` by hand.
