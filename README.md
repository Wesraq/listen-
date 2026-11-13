# Listen+

A global reading, listening and creator-commerce marketplace. Initial market: Zambia (ZMW).

## Platforms

| Surface | Status |
| --- | --- |
| **Android / iOS (Flutter)** | Primary product client — `apps/mobile` |
| Web prototype (TanStack) | UI reference only — repo root `src/` |
| Admin web | Prototype ops console — `apps/admin-web` (seeded admin account) |
| Backend API | Scaffolded NestJS-style modular monolith — `apps/api` |

Per the product requirements, a **consumer web app is not an MVP launch goal**. The Flutter apps are the customer and creator experience.

## Mobile (native)

```sh
cd apps/mobile
flutter pub get
flutter run
```

## API

```sh
cd apps/api
npm install
npm run start:dev
```

Serves catalogue, health, library/entitlements and admin ops at `http://localhost:3001/v1`.

### Admin web

```sh
cd apps/admin-web
npm install
npm run dev
```

Sign in at `http://localhost:5174` with `admin@listen.plus` / `ListenAdmin1!` (API must be running).

## Web prototype

```sh
npm i
npm run dev
```

## Docs

Product baselines live outside this repo:

- Listen+ Product Requirements Document v1.0
- Listen+ Technical System Design v1.0
- Listen+ UI/UX Specification v1.0

In-repo coverage map: [`docs/mvp-coverage.md`](docs/mvp-coverage.md).
