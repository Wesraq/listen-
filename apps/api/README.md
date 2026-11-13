# Listen+ API

TypeScript modular monolith for identity, catalogue, entitlements and (later) commerce.

Mobile clients are **untrusted** for payments and entitlements — this service owns verification.

## Run

```sh
cd apps/api
npm install
npm run start:dev
```

API base: `http://localhost:3001/v1`

## Endpoints (slice 1)

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| GET | `/health` | no | Liveness |
| GET | `/catalogue/titles` | no | Optional `?format=` `?category=` |
| GET | `/catalogue/titles/:id` | no | Title detail |
| GET | `/catalogue/titles/:id/chapters` | no | Ebook sample chapters |
| GET | `/catalogue/titles/:id/tracks` | no | Audio sample tracks |
| GET | `/catalogue/categories` | no | |
| GET | `/catalogue/collections` | no | |
| GET | `/catalogue/collections/:id` | no | Includes nested titles |
| GET | `/me` | Bearer | Profile stub |
| GET | `/library` | Bearer | Owned + saved |
| GET | `/library/entitlements/:titleId` | Bearer | Access check |
| POST | `/library/owned/:titleId` | Bearer | Prototype grant only |
| POST | `/library/saved/:titleId` | Bearer | Toggle save |
| POST | `/admin/auth/login` | no | Seeded admin session |
| GET | `/admin/overview` | Admin Bearer | Ops summary |
| GET/POST | `/admin/users…` | Admin Bearer | Users / creator status |
| GET/POST | `/admin/moderation…` | Admin Bearer | Content queue |
| GET/POST | `/admin/payouts…` | Admin Bearer | Payout queue |
| GET | `/admin/audit` | Admin Bearer | Privileged action log |

### Seeded admin account

| Email | Password |
| --- | --- |
| `admin@listen.plus` | `ListenAdmin1!` |

Override with `ADMIN_EMAIL` / `ADMIN_PASSWORD`. Use `apps/admin-web` to sign in.

### Dev auth

Set `AUTH_MODE=dev` (default). Send:

```http
Authorization: Bearer <firebase-uid>
```

Optional: `Bearer uid|email|Display Name`

Firebase Admin ID-token verification and PostgreSQL persistence come next.

> Nest constructors use explicit `@Inject(...)` so DI works under `tsx` (no `emitDecoratorMetadata`).

## Example

```sh
curl -s http://localhost:3001/v1/health
curl -s http://localhost:3001/v1/catalogue/titles | head
curl -s -H 'Authorization: Bearer demo-user' http://localhost:3001/v1/library
```
