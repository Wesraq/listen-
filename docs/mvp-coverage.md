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
| PUR-01–03 | Checkout review / pending / result | Done (prototype) · multi-rail intents + simulate confirm → ledger |
| PUR-04 | Purchase history | Done (prototype) · Profile |
| LIB-01 | Library + format filters + downloads stub | Done (prototype) |
| REA-01–03 | Reader, settings, bookmarks | Done (prototype) · sample chapters, not EPUB |
| REA-04 | Offline state | Partial · downloads empty explanation |
| AUD-01–03 | Mini / full player, chapters, speed, sleep timer | Done (prototype) · simulated audio |
| AUD-04 | Downloads | Partial · empty state only |
| STU-01–15 | Studio apply → draft wizard → earnings/payout | Done (prototype) · ledger balances, cashout request, ads earnings |
| PRO-01–07 | Profile, market, language, notifications, help, legal | Done (prototype) |
| Admin web | Ops console | Done (prototype) · `apps/admin-web` + seeded `admin@listen.plus` |

## PRD acceptance criteria (§14)

| Criterion | Status |
| --- | --- |
| Register, sign in, select market, browse catalogue | Done (prototype) |
| Free title or purchase with Zambia method | Done (prototype) · simulate / MoMo / Airtel / card intents; live rails deferred |
| Backend verifies payment before access | Partial · confirm + webhook path settle ledger then grant; live provider webhooks deferred |
| Idempotent payment callbacks | Done (prototype) · ledger `(referenceType, referenceId)` + webhook event id |
| Access ebook/audiobook from library | Done (prototype) · sample reader/player |
| Creator apply, upload, rights, price, submit | Partial · Studio wizard + API drafts / moderation |
| Admin approve/reject + history | Done (prototype) · admin-web moderation + audit (Firestore-backed when configured) |
| Auditable ledger on sale | Done (prototype) · shared double-entry engine (see `docs/financial-engine.md`) |
| Creator earnings + payout request | Done (prototype) · Studio cashout available / hold + `/finance/me/cashouts` |
| Finance payout approval | Done (prototype) · admin Finance cashouts + ad settlements |
| Free-with-ads monetisation | Done (prototype) · AdMob rewarded → `/ads/complete` + SSV → 55/45 ledger |
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
| Firebase Admin token verify | Partial · `AUTH_MODE=firebase` / Cloud Run `hybrid` |
| Payment adapters / webhooks | Partial · simulate + webhook scaffold; live MoMo/card keys deferred |
| Signed media / CDN | Partial · `MEDIA_REQUIRE_SIGNED` + signing secret locally |
| Admin web | Done (prototype) · seeded admin account · Finance + ads |

## Explicit non-goals preserved

Social network, full podcast hosting/RSS, unlimited subscriptions, institutional licensing, AI narration, multi-country payments at once, consumer web launch.

## Recommended next engineering slices

1. Live MTN MoMo / Airtel / card keys + production webhook secrets (disable simulate confirms).
2. AdMob production app/unit IDs + SSV URL in AdMob console + signature verify.
3. Advertiser self-serve campaigns (replace seed `network_default` only).
4. Harden `apps/admin-web` (SSO, durable reports).
5. Real EPUB + audio delivery with signed URLs.
6. Postgres as durable system of record if moving off Firestore-only prototype store.

Full money-path detail: [`docs/financial-engine.md`](./financial-engine.md).
