# Listen+ Admin Web

Internal operations UI for moderation, creators, payouts and audit (UI/UX §11 prototype).

Uses the same design system as the mobile-first web reference: DM Sans / Lora, Listen+ tokens, sidebar shell, and shadcn Button / Card / Input / Table / Badge.

## Seeded admin account

| Field | Value |
| --- | --- |
| Email | `admin@listen.plus` |
| Password | `ListenAdmin1!` |

Override on the API with `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `ADMIN_NAME`.

## Run

Start the API first:

```sh
cd apps/api
npm run start:dev
```

Then:

```sh
cd apps/admin-web
npm install
npm run dev
```

Open `http://localhost:5174` and sign in with the seeded admin account.

Vite proxies `/v1` → `http://localhost:3001`.
