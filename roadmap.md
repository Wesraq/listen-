# Listen+ roadmap

Aligned to PRD / TSD / UI-UX v1.0. Primary client: Flutter (`apps/mobile`).

Coverage matrix: [`docs/mvp-coverage.md`](docs/mvp-coverage.md) — prototype MVP screens vs commercial/backend acceptance.

## Product direction
- [x] Confirm platforms: Flutter Android + iOS; admin web for ops; no consumer web MVP.
- [x] Scaffold native Flutter client with five-tab shell and prototype journeys.
- [x] Keep root TanStack UI as web reference only.
- [x] Introduce `apps/api` TypeScript backend scaffold (NestJS-style modular monolith; in-memory library; Postgres compose ready).
- [ ] Persist catalogue/entitlements in PostgreSQL; verify Firebase ID tokens.
- [x] Introduce `apps/admin-web` prototype (seeded admin login, moderation/payout/user queues).
- [ ] Harden admin auth (SSO / Firebase Admin), Postgres-backed queues and full finance ledger UI.

## MVP Phase 1 — Identity & markets (mobile)
- [x] Welcome, create account, sign in, guest browse (prototype session).
- [x] Market + language selection (Zambia · ZMW).
- [x] Optional interest selection; Profile reflects session state.
- [x] Persist session locally across launches.
- [x] Firebase Auth email create / sign-in / reset / sign-out on mobile.
- [ ] Phone OTP auth; profile backend sync.

## MVP Phase 2 — Catalogue & discovery
- [x] Home shelves, search filters, title detail (sample catalogue).
- [x] Category + collection destinations.
- [x] Loading / empty / error states on Home, Search and Library.
- [x] Backend catalogue API (sample seed aligned with mobile).
- [x] Flutter hydrates catalogue + library entitlements from API when reachable.
- [ ] Signed media URLs + Postgres-backed catalogue.

## MVP Phase 3 — Commerce & library
- [x] Simulated checkout states (review / pending / success / failure).
- [ ] Server-side payment intents + webhook verification.
- [x] Prototype entitlements API (`/library`, `/library/entitlements/:id`).
- [ ] Entitlements from verified orders driving Library access.
- [ ] Purchase history tied to orders.

## MVP Phase 4 — Reader & player
- [x] Sample ebook reader + mini audio player.
- [x] Sample resume, chapter bookmarks, reader themes, richer simulated player (seek / speed / chapters).
- [ ] Real EPUB reader + real audio pipeline.
- [ ] Background audio, sleep timer, offline downloads.

## MVP Phase 5 — Studio & admin
- [x] Creator apply / draft upload / sample payout preview UI.
- [ ] Rights declarations, review queue, earnings from ledger.
- [ ] Admin moderation / payout approval web app.
