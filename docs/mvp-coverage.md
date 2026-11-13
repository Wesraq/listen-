# Listen+ v1.0 MVP coverage map

Aligned to PRD / TSD / UI-UX Specification v1.0 against the current repo.

Legend: **Done (prototype)** = clickable / demo path in Flutter · **Partial** = UI present, backend/real media deferred · **Deferred** = not in this first engineering slice

## Scope interpretation

| Layer | What “first version covered” means here |
| --- | --- |
| UI/UX v1.0 | Mobile screen inventory + journeys as a **clickable prototype** |
| PRD commercial MVP | Full acceptance needs **verified payments, ledger, admin web** |
| TSD | `apps/mobile` + `apps/api` scaffold; Postgres/Firebase Admin/admin-web still open |

## Mobile screen inventory (UI/UX §4)

| ID | Screen | Status |
| --- | --- | --- |
| ONB-01–06 | Welcome, create, sign-in, market/language, interests | Done (prototype) · email Firebase Auth live |
| ONB-04 | Phone verification | Partial · phone tab stubbed |
| ONB-07 | Notification permission | Done (prototype) · soft prompt, non-blocking |
| HOM-01–03 | Home, category, collection | Done (prototype) |
| SEA-01–03 | Search, results, filters | Done (prototype) · recent + suggested |
| CON-01 | Title detail | Done (prototype) |
| CON-02 | Creator profile | Done (prototype) |
| PUR-01–03 | Checkout review / pending / result | Done (prototype) · simulated only |
| PUR-04 | Purchase history | Done (prototype) · Profile |
| LIB-01 | Library + format filters + downloads stub | Done (prototype) |
| REA-01–03 | Reader, settings, bookmarks | Done (prototype) · sample chapters, not EPUB |
| REA-04 | Offline state | Partial · downloads empty explanation |
| AUD-01–03 | Mini / full player, chapters, speed, sleep timer | Done (prototype) · simulated audio |
| AUD-04 | Downloads | Partial · empty state only |
| STU-01–15 | Studio apply → draft wizard → earnings/payout preview | Partial · local drafts, illustrative money |
| PRO-01–07 | Profile, market, language, notifications, help, legal | Done (prototype) |
| Admin web | Ops console | Done (prototype) · `apps/admin-web` + seeded `admin@listen.plus` |

## PRD acceptance criteria (§14)

| Criterion | Status |
| --- | --- |
| Register, sign in, select market, browse catalogue | Done (prototype) |
| Free title or purchase with Zambia method | Partial · simulated checkout UI |
| Backend verifies payment before access | Partial · mobile syncs entitlements to API in dev; payment webhooks still deferred |
| Idempotent payment callbacks | Deferred |
| Access ebook/audiobook from library | Done (prototype) · sample reader/player |
| Creator apply, upload, rights, price, submit | Partial · Studio wizard local |
| Admin approve/reject + history | Partial · admin-web moderation + audit log (in-memory) |
| Auditable ledger on sale | Deferred |
| Creator earnings + payout request | Partial · illustrative Studio UI |
| Finance payout approval | Partial · admin-web payout queue (prototype) |
| Refund/reversal integrity | Deferred |
| Error/event/admin audit logging | Deferred |
| Legal docs before commercial launch | Partial · prototype policy screens present |

## TSD alignment

| Item | Status |
| --- | --- |
| Flutter Android/iOS primary client | Done · iOS Firebase configured; Android `google-services.json` pending |
| No consumer web MVP | Done · root web is reference only |
| TypeScript modular monolith `apps/api` | Done (scaffold) · catalogue + library/entitlements; Flutter hydrates when reachable |
| PostgreSQL system of record | Deferred · compose file ready |
| Firebase Admin token verify | Deferred · `AUTH_MODE=dev` Bearer |
| Payment adapters / webhooks | Deferred |
| Signed media / CDN | Deferred |
| Admin web | Done (prototype) · seeded admin account |

## Explicit non-goals preserved

Social network, full podcast hosting/RSS, unlimited subscriptions, institutional licensing, AI narration, multi-country payments at once, consumer web launch.

## Recommended next engineering slices

1. Postgres + Firebase Admin ID-token verification (replace `AUTH_MODE=dev`).
2. Payment attempt state machine + webhook idempotency (stop trusting client grants).
3. Harden `apps/admin-web` (SSO, durable queues, reports/transactions screens).
4. Real EPUB + audio delivery with signed URLs.
